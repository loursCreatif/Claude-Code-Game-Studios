# Story 006: Tier 2+ verbs stubs (load_int_array / save_int_array) + get_save_version meta

> **Epic**: Save/Load System
> **Status**: Complete
> **Layer**: Foundation / Persistence
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: ~1-2h — t-shirt XS
> **Risk**: LOW

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-4 (API publique : ... + 2 Tier 2+ verbes `load_int_array` / `save_int_array` + 1 getter méta `get_save_version`)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-2 verrouille les signatures Tier 2+ stubs **identiques** au GDD R-SAV-4 — provision pour Secret System Tier 2+ persistance permanente disque (OQ-SEC-2) sans casser l'API publique. Les stubs sont des implémentations **fonctionnelles** (pas des `pass`) car la signature exacte est verrouillée et un consumer Tier 2+ pourrait commencer à les appeler dès le moment où Save/Load est livré.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- ConfigFile sérialise `Array[int]` directement comme tableau d'entiers `[1, 2, 3]`. Pas de cast / normalisation requis (contrairement à R-SAV-12 String→StringName pour `Array[StringName]`).
- `typeof(value) != TYPE_ARRAY` validation globale + itération pour vérifier que chaque élément `typeof(elem) == TYPE_INT`.

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: signatures stables R-SAV-4 (load_int_array / save_int_array / get_save_version) — pas de renomination Tier 2+.
- **Forbidden**: implémentation `pass` ou `return default` brute pour `load_int_array` / `save_int_array` — les Tier 2+ verbes sont fonctionnels Sprint 1, juste pas activés MVP côté consumer.
- **Guardrail**: cohérent avec le pattern story-002 (load_int) et story-003 (load_string_array) — sémantique D-2 reste applicable.

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [x] **AC-SAV-32** [Logic] [PROVISIONAL — chain-blocked OQ-SAV-1] : GIVEN Upgrade System designé (futur), WHEN contrats Save/Load consommés par Upgrade clarifiés (ou confirmés N/A), THEN amendement R-SAV-4 si verbes additionnels requis. Mécanisme : CHAIN-BLOCKED — re-valider à Upgrade GDD r1. **Story-006 livre les signatures figées** : aucun amendement R-SAV-4 attendu si Upgrade reste agnostique de Save/Load (hypothèse Save/Load r1).

**Note story-specific** : pas d'AC-SAV-* directement labellé pour les stubs Tier 2+ dans le GDD r1 — story-006 est défensive (ADR-0010 D-2 verrouille les signatures, story-006 vérifie qu'elles existent et fonctionnent). AC implicites :

- [x] **AC-006-1** [Logic] [BLOCKING-story] : GIVEN SaveLoadSystem ready, WHEN `save_int_array("k", [1, 2, 3])` puis `load_int_array("k", [])`, THEN retour `Array[int]([1, 2, 3])` (taille=3, types int, ordre préservé).
- [x] **AC-006-2** [Logic] [BLOCKING-story] : GIVEN clé existe avec Array hétérogène `[1, "string", null, 4]`, WHEN `load_int_array("k", [])`, THEN retour `[1, 4]` (2 éléments valides), 2 push_warning émis.
- [x] **AC-006-3** [Logic] [BLOCKING-story] : GIVEN signatures publiques inspectées via reflection / `script.get_method_list()`, THEN méthodes `load_int_array(key: String, default: Array[int]) -> Array[int]`, `save_int_array(key: String, value: Array[int]) -> void`, `get_save_version() -> int` toutes présentes avec types exacts.

---

## Implementation Notes

*Derived from ADR-0010 D-2 sémantique Tier 2+ stubs:*

1. **`save_int_array(key: String, value: Array[int]) -> void`** — analogue à `save_string_array` mais sans normalisation :
   ```gdscript
   func save_int_array(key: String, value: Array[int]) -> void:
       _assert_main_thread()
       if not _config_loaded:
           push_error("SaveLoadSystem: save_int_array('%s') called before _config_loaded" % key)
           return
       _ensure_save_version_set()
       _config.set_value("data", key, value)
       var err: int = _config.save(SAVE_FILE_PATH)
       if err != OK:
           push_error("SaveLoadSystem: save_int_array('%s') failed err=%d" % [key, err])
   ```

2. **`load_int_array(key: String, default: Array[int]) -> Array[int]`** :
   ```gdscript
   func load_int_array(key: String, default: Array[int]) -> Array[int]:
       _assert_main_thread()
       if not _config_loaded:
           return default
       var raw: Variant = _config.get_value("data", key, default)
       if typeof(raw) != TYPE_ARRAY:
           if raw != default:
               push_warning("SaveLoadSystem: load_int_array('%s') expected Array, got %s — return default" % [key, type_string(typeof(raw))])
           return default
       var result: Array[int] = []
       for elem: Variant in raw:
           if typeof(elem) == TYPE_INT:
               result.append(elem)
           else:
               push_warning("SaveLoadSystem: load_int_array('%s') skip element type=%s" % [key, type_string(typeof(elem))])
       return result
   ```

3. **`get_save_version() -> int`** — déjà partiellement livré par story-004 ; story-006 confirme la signature stable et ajoute le test signature explicite si non présent.

4. **NE PAS** ajouter de verbes additionnels (PROVISIONAL OQ-SAV-1 Upgrade) — Sprint 1 livraison limitée à R-SAV-4 strict.

---

## Out of Scope

- **Story 002 / 003**: scalar et string array verbs (déjà livrés)
- **Story 004**: `_save_version` lazy init wrapper (déjà livré — `_ensure_save_version_set()` réutilisé ici)
- **Tier 2+ activation Secret System** : OQ-SEC-2 — Secret System Tier 2+ persistance utilisera `save_int_array` / `load_int_array` (instance_ids des secrets collectés). MVP : pas activé, juste signatures réservées.

---

## QA Test Cases

**AC-006-1** — roundtrip Array[int] :
- Given : `_config_loaded == true`
- When : `save_int_array("k", [1, 2, 3])` puis `load_int_array("k", [])`
- Then : retour size==3, retour == `[1, 2, 3]`, tous TYPE_INT
- Edge cases : valeurs négatives (`[-1, 0, 1]`), `INT_MAX`, `INT_MIN`, array vide `[]`.

**AC-006-2** — partial validation Array hétérogène :
- Given : `_config.set_value("data", "k", [1, "string", null, 4])`
- When : `load_int_array("k", [])`
- Then : retour `[1, 4]`, 2 push_warning capturés
- Edge cases : tous éléments invalides → retour `[]` + N warnings ; ordre préservé sur subset valide.

**AC-006-3** — signatures publiques stables :
- Given : SaveLoadSystem instance
- When : inspection via `save_load.get_script().get_method_list()` ou `Callable.is_valid()` sur chaque verbe
- Then : présent : `load_int_array`, `save_int_array`, `get_save_version` avec arités correctes (2/2/0 args)
- Edge cases : test type-check optionnel via GUT static helper si disponible.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/save_load/tier2_verbs_signature_test.gd` — must exist and pass (3 tests AC-006-1/2/3)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-001** (skeleton), **story-004** (`_ensure_save_version_set` wrapper)
- Unlocks: Secret System Tier 2+ persistance permanente (OQ-SEC-2 — pas activé MVP, signatures provisionnées)
- **Provisional** : AC-SAV-32 chain-blocked sur Upgrade GDD r1 (futur) — si Upgrade exige verbes additionnels, amendement R-SAV-4 + story-006 v2.

---

## Completion Notes

**Completed**: 2026-04-28
**Criteria**: 3/3 passing (AC-006-1/2/3) + AC-SAV-32 PROVISIONAL chain-blocked closure (signatures figées comme requis)
**Verdict**: COMPLETE

**Tests run** :
- `tests/unit/save_load/tier2_verbs_signature_test.gd` 7/7 PASSED (AC-006-1 roundtrip + 2 edges + AC-006-2 hetero/all-invalid/type-mismatch + AC-006-3 signatures Callable + arités + sanity get_save_version)
- Suite save_load globale : 24/24 unit + 7/7 integration = **31/31 vert** 574 ms total. Zéro régression sur stories 001-005.

**Files modified (2)** :
- `src/core/save_load_system.gd` 219 → 274 L (+55 L) :
  - `load_int_array(key, default) -> Array[int]` (pattern story-003 avec guard `has_section_key` pour éviter cross-type comparison Godot 4 strict)
  - `save_int_array(key, value) -> void` (analogue `save_string_array` sans normalisation)
  - `get_save_version()` déjà livré story-004, signature confirmée stable
- `tests/unit/save_load/tier2_verbs_signature_test.gd` NEW 235 L : 7 tests pattern hermétique GdUnit4.

**Deviations** :
- **Pattern `if raw != default` remplacé par `if not has_section_key(...) return default`** : la spec ADR-0010 D-2 inline montrait `if raw != default: push_warning ; return default` mais ce pattern provoque un crash Godot 4 strict (`int != Array` invalid operator) — déjà identifié et corrigé story-003 array_verbs. Sémantiquement équivalent (clé absente = retour silencieux du default), aucune perte fonctionnelle.

**Code Review** : Skipped (Solo mode — feedback_no_confirmation_apply_directly + production/review-mode.txt = solo)
**Tech Debt Logged** : 0 items

**Unblocks aval** :
- **Secret System Tier 2+** persistance permanente (OQ-SEC-2) — `save_int_array` / `load_int_array` désormais consommables (signatures figées R-SAV-4)
- **save-load story-007** lints static cross-system isolation
- **save-load story-008** perf gate ConfigFile save budget
