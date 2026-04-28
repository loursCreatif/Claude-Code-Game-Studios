# Story 001: Autoload skeleton + ConfigFile init + project.godot registration

> **Epic**: Save/Load System
> **Status**: Ready
> **Layer**: Foundation / Persistence
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: ~2-3h — t-shirt S
> **Risk**: MEDIUM (engine-compat Godot 4.4 `FileAccess.store_*` mitigé via ConfigFile abstraction ; erratum process_mode 4.6 = `3` SHIP-CRITICAL)

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-1 (autoload Node singleton), R-SAV-7 (boot lifecycle), R-SAV-8 (`PROCESS_MODE_ALWAYS = 3`)
*(Requirement text lives in `design/gdd/save-load-system.md` — TR-sav-* registry à appender post-Sprint 1 via `/architecture-review` Phase 8)*

**ADR Governing Implementation**: ADR-0010 Save/Load Persistence Architecture (ConfigFile Ratification) — Accepted 2026-04-27
**ADR Decision Summary**: D-1 Format ConfigFile sur `user://savegame.cfg` ; D-3 position autoload **#3** sur 4 (`InputManager → GSM → SaveLoadSystem → AudioSystem`) figée ; D-4 `process_mode = PROCESS_MODE_ALWAYS` ; D-7 main-thread-only assertion debug.

**Secondary ADR**: ADR-0007 Game State Manager — Accepted 2026-04-23 (D-1 ordre canonique autoload + D-4 process_mode discipline Foundation)

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**:
- `ConfigFile` API stable depuis Godot 3.x — `set_value(section, key, value)` / `get_value(section, key, default)` / `save(path) -> Error` / `load(path) -> Error`. Non-affectée par les breaking changes 4.4-4.6.
- `FileAccess.store_*` Godot 4.4 a changé `void` → `bool`. **Évité** via abstraction ConfigFile (D-1 rejet binary justifié engine-compat ADR-0010).
- **Erratum process_mode SHIP-CRITICAL** (commit `1649049`, 2026-04-28) : `Node.PROCESS_MODE_ALWAYS` = entier **`3`** Godot 4.6 (pas `4` qui est `PROCESS_MODE_DISABLED`). Tout AC asserting `process_mode == ALWAYS` doit utiliser **double-assert** (constante symbolique + valeur entière `3`).
- `user://` path résolu par Godot vers location système locale (Win `%APPDATA%/Godot/app_userdata/<projectName>/`, Linux `~/.local/share/godot/app_userdata/<projectName>/`, macOS `~/Library/Application Support/Godot/app_userdata/<projectName>/`). Dossier garanti existant avant `_ready()` (Godot bootstrap).
- `ERR_FILE_NOT_FOUND` au boot fresh est nominal (R-SAV-7).

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: Autoload registré `project.godot` après `GameStateManager`, avant `AudioSystem` (ADR-0007 D-1 + ADR-0010 D-3). `process_mode = PROCESS_MODE_ALWAYS` (= 3) déclaré programmatiquement dans `_ready()` (ADR-0010 D-4 + ADR-0007 D-4). **Aucun `class_name`** dans `save_load_system.gd` — décision design ADR-0010 §Key Interfaces ligne 217-218 + GDD R-SAV-1 ligne 46 : « le fichier est `save_load_system.gd` sans `class_name` (autoload sans `class_name` évite la collision Godot 4.6) ». Le nom autoload `SaveLoadSystem` reste accessible globalement comme singleton.
- **Forbidden**: Aucune référence vers consumer gameplay (Credit / Shop / Secret / Upgrade / HUD / Audio / Input) dans `src/core/save_load_system.gd`. Aucun `Thread.start` / `WorkerThreadPool.add_task` / `call_deferred` cross-thread vers verbes SaveLoad (ADR-0010 D-7).
- **Guardrail**: `_ready()` SaveLoadSystem < 5 ms headless CI (boot budget — boot fresh OK, boot corrompu OK avec push_error).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [ ] **AC-SAV-1** [Logic] [BLOCKING] : GIVEN `user://savegame.cfg` n'existe pas (suppression manuelle préalable), WHEN engine boot et `SaveLoadSystem._ready()` exécuté, THEN `_config_loaded == true` ET `load_int("total_credits", 0) == 0` retourné. Mécanisme : unit GUT — supprimer fichier via DirAccess avant test, instancier SaveLoadSystem, assert getter helper `_is_ready()` ou direct `load_int` retour default.
- [ ] **AC-SAV-4** [Integration] [BLOCKING] : GIVEN engine boot avec project.godot autoload order InputManager → GSM → SaveLoadSystem → AudioSystem, WHEN tick 0 atteint, THEN `SaveLoadSystem._ready()` a déjà fini avant que `CreditEconomy._ready()` (Credit position 5+) appelle `load_int`. Mécanisme : integration test GUT — assert `SaveLoadSystem._is_ready() == true` dans `CreditEconomy._ready()` via signal `tree_entered` ordering.
- [ ] **AC-SAV-20** [Logic] [BLOCKING] : GIVEN SaveLoadSystem instancié, WHEN inspection `process_mode`, THEN `== PROCESS_MODE_ALWAYS` (R-SAV-8 ADR-0007 D-4). Mécanisme : unit GUT — assert `SaveLoadSystem.process_mode == Node.PROCESS_MODE_ALWAYS` ET `SaveLoadSystem.process_mode == 3` (double-assert erratum 4.6).

---

## Implementation Notes

*Derived from ADR-0010 Implementation Guidelines + ADR-0007 D-1/D-4:*

1. **Créer `src/core/save_load_system.gd`** :
   ```gdscript
   # Autoload nom : SaveLoadSystem (position 3 sur 4 — ADR-0007 D-1 + ADR-0010 D-3)
   # Aucun class_name — autoload sans class_name évite la collision Godot 4.6
   # (ADR-0010 §Key Interfaces ligne 217-218 + GDD R-SAV-1 ligne 46).
   # Les consumers accèdent au singleton via `SaveLoadSystem.xxx` (nom autoload globalement accessible).
   extends Node

   const SAVE_FILE_PATH: String = "user://savegame.cfg"
   const _CURRENT_SAVE_VERSION: int = 1

   var _config: ConfigFile
   var _config_loaded: bool = false

   func _ready() -> void:
       process_mode = Node.PROCESS_MODE_ALWAYS  # = 3 Godot 4.6 erratum 1649049
       assert(process_mode == 3, "SaveLoadSystem: process_mode != 3 (PROCESS_MODE_ALWAYS Godot 4.6 erratum)")
       _config = ConfigFile.new()
       var err: int = _config.load(SAVE_FILE_PATH)
       if err == OK or err == ERR_FILE_NOT_FOUND:
           _config_loaded = true
       else:
           push_error("SaveLoadSystem: load failed err=%d path=%s" % [err, SAVE_FILE_PATH])
           _config_loaded = true  # graceful : verbes load_* retourneront defaults

   func _is_ready() -> bool:
       return _config_loaded
   ```

2. **`project.godot` `[autoload]` section** : insérer `SaveLoadSystem="*res://src/core/save_load_system.gd"` **entre `GameStateManager` et `LevelSystem`** (ordre canonique ADR-0007 D-1 InputManager → GSM → SaveLoadSystem → AudioSystem). Position #3 verrouillée par ADR-0010 D-3.

3. **Verbes `load_int` / `save_int` stubs minimaux pour AC-SAV-1** : implémenter le minimum viable de `load_int` retournant default (story-002 fournira la sémantique complète scalar). Pour AC-SAV-1 il suffit que `load_int("total_credits", 0) == 0` quand fichier absent.
   ```gdscript
   func load_int(key: String, default: int) -> int:
       _assert_main_thread()
       if not _config_loaded:
           return default
       var value: Variant = _config.get_value("data", key, default)
       if typeof(value) != TYPE_INT:
           if value != default:
               push_warning("SaveLoadSystem: load_int(%s) type mismatch, return default" % key)
           return default
       return value
   ```

4. **`_assert_main_thread()` helper debug** (ADR-0010 D-7) :
   ```gdscript
   func _assert_main_thread() -> void:
       if OS.has_feature("debug"):
           assert(OS.get_thread_caller_id() == OS.get_main_thread_id(),
               "SaveLoadSystem: called from non-main thread (ADR-0010 D-7)")
   ```

5. **NE PAS** déclarer de `signal` dans le fichier (R-SAV-10 zero outbound). NE PAS appeler `.connect(` (R-SAV-11 zero orchestration). NE PAS importer/référencer aucun consumer (R-SAV-17).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- **Story 002**: sémantique complète `load_int` / `save_int` (corruption, type mismatch, EC-SAV edge cases AC-SAV-2/3/5/7-9/17/18/19)
- **Story 003**: `load_string_array` / `save_string_array` + R-SAV-12 String→StringName normalization
- **Story 004**: `_save_version` lazy init + framework forward-only (R-SAV-14/15)
- **Story 005**: `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler (R-SAV-9)
- **Story 006**: stubs `load_int_array` / `save_int_array` Tier 2+ + `get_save_version()` méta
- **Story 007**: lints CI static cross-system isolation (5 grep gates VC-6/7/8/9/10)
- **Story 008**: perf gate `ConfigFile.save() < 1 ms` SSD reference (F-SAV-1 / AC-SAV-26)

---

## QA Test Cases

**AC-SAV-1** — boot fresh fichier absent retourne defaults :
- Given : `user://savegame.cfg` est supprimé manuellement avant test (`DirAccess.remove_absolute(SAVE_FILE_PATH)` dans `before_each`)
- When : SaveLoadSystem instancié et `_ready()` exécuté
- Then : `save_load._is_ready() == true` ET `save_load.load_int("total_credits", 0) == 0`
- Edge cases : ERR_FILE_NOT_FOUND traité comme nominal (pas de push_error). Vérifier qu'aucun `push_error` n'a été émis (capture via stub log si possible).

**AC-SAV-4** — autoload order garantit hydration consumer post-`_ready()` :
- Given : `project.godot` autoload order = `InputManager` → `GameStateManager` → `SaveLoadSystem` → `LevelSystem` (Audio à venir)
- When : engine boot complet (tree_entered de tous autoloads)
- Then : depuis le `_ready()` de tout consumer placé après SaveLoadSystem (mock CreditEconomy stub), `SaveLoadSystem._is_ready() == true`
- Edge cases : tester que l'ordre `_ready()` respecte l'ordre `[autoload]` du project.godot (Godot bootstrap garantit cet ordre).

**AC-SAV-20** — process_mode double-assert erratum 4.6 :
- Given : SaveLoadSystem instancié (post-`_ready()`)
- When : inspection `save_load.process_mode`
- Then : `save_load.process_mode == Node.PROCESS_MODE_ALWAYS` ET `int(save_load.process_mode) == 3`
- Edge cases : capturer le cas où dev future écrit `= 4` par erreur (= PROCESS_MODE_DISABLED) — le double-assert fail loud sur le mismatch entier.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/save_load/autoload_skeleton_test.gd` — must exist and pass (3 tests AC-SAV-1/4/20)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **None** (Foundation Persistence — pas de hard prereq amont)
- Unlocks:
  - story-002 (scalar verbs sémantique complète)
  - **upgrade-system story-001 AC-UPG-3 BLOCKING** ✅ (`SaveLoadSystem` registered avant `UpgradeSystem`)
  - credit-economy-system story-* (boot hydrate `total_credits`)
  - shop-system story-* (boot hydrate `owned_upgrades`)
  - menu-system story-007 (délégation save-on-quit AC-MNU-57)
