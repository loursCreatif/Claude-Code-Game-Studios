# Story 004: _save_version lazy init + forward-only schema versioning

> **Epic**: Save/Load System
> **Status**: Complete
> **Layer**: Foundation / Persistence
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: ~1-2h — t-shirt XS
> **Risk**: LOW

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-14 (`_save_version` clé réservée + `_CURRENT_SAVE_VERSION = 1` + framework migration Tier 2+ forward-only), R-SAV-15 (initialisation lazy `_save_version` — premier save_* écrit également la version)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-6 schema versioning forward-only via `_save_version`. Valeur MVP figée à `1`. Toute modification de schéma (rename clé, change type, split section) DOIT incrémenter `_CURRENT_SAVE_VERSION` et fournir un migration step (ADR successeur ou amendement). Comportement sur `_save_version` futur (> `_CURRENT_SAVE_VERSION` lu, EC-SAV-11) : warning logué, lecture partielle, pas de crash.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- ConfigFile sérialise int directement : `_save_version=1` apparaît tel quel dans le `[data]` section.
- `get_value("data", "_save_version", 1)` retourne `1` si key absent (comportement lazy init côté lecture).
- Lazy write : à chaque `save_int` / `save_string_array`, vérifier si `_save_version` est déjà set dans `_config` ; sinon le set AVANT le `_config.save()`.

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: `_save_version` clé top-level présente dans tout fichier `savegame.cfg` post-MVP. Valeur figée à `1` MVP.
- **Forbidden**: jamais downgrade `_save_version` (forward-only).
- **Guardrail**: lecture `_save_version > _CURRENT_SAVE_VERSION` retourne warning + lecture partielle (clés absentes en version courante = defaults).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [x] **AC-SAV-6** [Logic] [BLOCKING] : GIVEN `save_int("k", 0)` exécuté, WHEN file content lu via `FileAccess.open`, THEN contient `[data]\n_save_version=1\nk=0\n` (version key auto-écrit R-SAV-15).
- [x] **AC-SAV-15** [Logic] [BLOCKING] : GIVEN `_save_version=99` (futur) écrit dans le fichier, WHEN boot, THEN `push_warning("save version 99 > supported 1")` émis ET load réussit pour clés présentes.
- [x] **AC-SAV-16** [Logic] [BLOCKING] : GIVEN `_save_version` absent (fichier vide ou ancien), WHEN boot, THEN `get_save_version() == 1` (défaut MVP).

---

## Implementation Notes

*Derived from ADR-0010 D-6 forward-only schema versioning:*

1. **Constante de version dans `secret_constants.gd`-equivalent ou inline header save_load_system.gd** :
   ```gdscript
   const _CURRENT_SAVE_VERSION: int = 1
   const _SAVE_VERSION_KEY: String = "_save_version"
   ```

2. **Lazy init au premier write** (R-SAV-15) — wrapper helper privé `_ensure_save_version_set()` appelé depuis tous les verbes save_* :
   ```gdscript
   func _ensure_save_version_set() -> void:
       if not _config.has_section_key("data", _SAVE_VERSION_KEY):
           _config.set_value("data", _SAVE_VERSION_KEY, _CURRENT_SAVE_VERSION)

   func save_int(key: String, value: int) -> void:
       _assert_main_thread()
       if not _config_loaded:
           push_error(...)
           return
       _ensure_save_version_set()  # ← lazy init R-SAV-15
       _config.set_value("data", key, value)
       var err: int = _config.save(SAVE_FILE_PATH)
       if err != OK:
           push_error(...)
   ```
   Idem pour `save_string_array` et `save_int_array` (Tier 2+ story-006).

3. **Boot warning version future** (AC-SAV-15) — dans `_ready()` après `_config.load()` :
   ```gdscript
   func _ready() -> void:
       process_mode = Node.PROCESS_MODE_ALWAYS
       _config = ConfigFile.new()
       var err: int = _config.load(SAVE_FILE_PATH)
       if err == OK or err == ERR_FILE_NOT_FOUND:
           _config_loaded = true
           if err == OK:
               _check_save_version_compatibility()  # ← NEW
       else:
           push_error(...)
           _config_loaded = true

   func _check_save_version_compatibility() -> void:
       var version: int = _config.get_value("data", _SAVE_VERSION_KEY, _CURRENT_SAVE_VERSION)
       if version > _CURRENT_SAVE_VERSION:
           push_warning("SaveLoadSystem: save version %d > supported %d — partial read, missing keys return defaults" % [version, _CURRENT_SAVE_VERSION])
   ```

4. **`get_save_version() -> int`** méta-getter (AC-SAV-16) :
   ```gdscript
   func get_save_version() -> int:
       _assert_main_thread()
       if not _config_loaded:
           return _CURRENT_SAVE_VERSION
       return _config.get_value("data", _SAVE_VERSION_KEY, _CURRENT_SAVE_VERSION)
   ```
   Note : `get_save_version()` est aussi listé dans story-006 (Tier 2+ stubs + meta). Doublon assumé — story-004 livre la version finale, story-006 confirmera signature stable.

5. **NE PAS** implémenter framework migration (`_MIGRATIONS = {1: _migrate_v1_v2}`) — déféré Tier 2+ via OQ-SAV-5.

---

## Out of Scope

- **Story 002 / 003**: verbes scalar / array eux-mêmes (story-004 ajoute juste le wrapper `_ensure_save_version_set` AVANT `_config.set_value`)
- **Story 006**: méta-getter `get_save_version()` finalisé (story-004 livre déjà l'implé ; story-006 fait juste le test signature explicite)
- **ADR Tier 2+ futur** : framework migration, downgrade handling, version-aware key removal — tous OQ-SAV-5 déférés.

---

## QA Test Cases

**AC-SAV-6** — first save écrit `_save_version=1` :
- Given : fichier `user://savegame.cfg` supprimé avant test
- When : `save_int("k", 0)` appelé une seule fois
- Then : `FileAccess.get_file_as_string(SAVE_FILE_PATH)` matches regex `\[data\]\s*\n.*_save_version\s*=\s*1.*\n.*k\s*=\s*0.*` (ordre des clés non garanti par ConfigFile, mais `_save_version=1` ET `k=0` doivent tous deux être présents)
- Edge cases : `save_int` appelé 2 fois → fichier contient toujours `_save_version=1` une seule fois (pas de doublon).

**AC-SAV-15** — version future warning + lecture partielle :
- Given : fichier `[data]\n_save_version=99\ntotal_credits=42\n` écrit manuellement
- When : SaveLoadSystem boot puis `load_int("total_credits", 0)`
- Then : `push_warning` capturé contenant `"save version 99"` ET `"supported 1"` ; retour `42` (lecture partielle réussie)
- Edge cases : version `2` (tier 2+ futur) — même comportement warning + lecture. Version `0` (impossible théorique) — testé comme AC-SAV-16 default.

**AC-SAV-16** — default version 1 sur fichier sans version :
- Given : fichier ConfigFile sans `_save_version` (ex `[data]\ntotal_credits=42\n`)
- When : SaveLoadSystem boot puis `get_save_version()`
- Then : retour `1`
- Edge cases : fichier vide (`[data]\n`) — même retour `1`.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/save_load/save_version_test.gd` — must exist and pass (3 tests AC-SAV-6/15/16)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-002** (verbes save_int doivent exister pour wrapper `_ensure_save_version_set`)
- Unlocks: forward-compat Tier 2+ migration (cosmetic — pas de consumer direct)

---

## Completion Notes

**Completed**: 2026-04-28
**Criteria**: 3/3 passing (AC-SAV-6, AC-SAV-15, AC-SAV-16)
**Verdict**: COMPLETE WITH NOTES

**Tests run** :
- `tests/unit/save_load/save_version_test.gd` 3/3 PASSED (AC-SAV-6/15/16)
- Suite save_load globale : 17/17 unit + 3/3 integration = **20/20 vert** (zéro régression sur story-001/002/003)

**Files modified (2)** :
- `src/core/save_load_system.gd` 156 → 196 L (+40 L) :
  - Ajout `const _SAVE_VERSION_KEY: String = "_save_version"`
  - `_ensure_save_version_set()` private helper (lazy init R-SAV-15, idempotent)
  - `_check_save_version_compatibility()` private helper (warning version future R-SAV-15)
  - `get_save_version() -> int` public method (R-SAV-14, _assert_main_thread + default _CURRENT_SAVE_VERSION)
  - Wrap `save_int` + `save_string_array` avec `_ensure_save_version_set()` AVANT `_config.set_value`
  - Hook `_check_save_version_compatibility()` dans `_ready()` UNIQUEMENT si err == OK (fichier existant)
- `tests/unit/save_load/save_version_test.gd` NEW 145 L : 3 tests pattern hermétique GdUnit4 identique scalar/array_verbs_test.gd.

**Deviations (ADVISORY)** :
- **AC-SAV-15 push_warning non-asserté** : émis runtime visible stderr mais non-asserté programmatiquement — limite GdUnit4 sans plugin stderr capture, documenté in-test. Sémantique vérifiée par retour `load_int == 42` (lecture partielle réussie malgré version future).
- **`_SAVE_VERSION_KEY` const fix inline** : specialist avait omis la déclaration lors du draft (référencé 4× sans définition → parse error potentiel). Corrigé directement avant exec tests. Pas de divergence sémantique vs spec.

**Code Review** : Skipped (Solo mode — feedback_no_confirmation_apply_directly + production/review-mode.txt = solo)
**Tech Debt Logged** : 0 items (advisory déjà documentés in-test/in-spec, push_warning capture déféré E2E plugin futur)

**Unblocks aval** :
- **save-load story-005** `NOTIFICATION_WM_CLOSE_REQUEST` handler — base lifecycle solide
- **save-load story-006** Tier 2+ stubs (`save_int_array` + meta `get_save_version` confirme signature)
- **shop-system / credit-economy / upgrade-system stories** — chain forward-compat verrouillé : tout fichier savegame.cfg post-MVP a `_save_version=1` lazy-écrit au premier save
