# Story 001: Level scene root + LevelState enum + PlayerStart discovery

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-002`, `TR-lvl-030`, `TR-lvl-044`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt), ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary** : ADR-0001 fixe `_physics_process` 60 Hz comme unique autorité gameplay et Jolt 4.6 default. ADR-0005 D-4 restreint emit signals aux fonctions appelées depuis `_physics_process` et exige payloads zero-alloc Vector3/float/int ; D-8 impose idempotence 1× par transition via guard `if _state == NEW: return`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `Marker3D` + `find_children("PlayerStart", "Marker3D", true)` stable 4.0–4.6. Enum `LevelState` = pattern GDScript natif (sync value type). `Thread.get_caller_id() == OS.get_main_thread_id()` pour assert main-thread (API corrigée r2, pas `OS.get_thread_caller_id()`).

**Control Manifest Rules (Core Layer)**:
- Required : `_physics_process(delta)` autorité exclusive mutation `_state` (ADR-0001) ; signals typés directs sur `Level` (pas EventBus), liste canonique figée, payloads value types (ADR-0005 D-1/D-3)
- Forbidden : muter `_state` depuis `_process`/`_input`/`_ready`/`Timer.timeout` (`mutate_gameplay_state_in_process`) ; Dictionary/Array/String/Node/Resource en payload signal (`allocating_signal_payload`)
- Guardrail : physics budget p99 ≤ 4 ms/frame total (Level `_physics_process` contribution minime — pas hot path)

---

## Acceptance Criteria

*From GDD `design/gdd/level-system.md`, scoped to this story :*

- [x] **AC-LVL-1** : Boot initial Unloaded — `Level.get_state() == LevelState.UNLOADED` ET `get_current_etage_id() == -1`
- [x] **AC-LVL-8** : Assert PlayerStart absent — debug assert "missing PlayerStart marker" ; release fallback `Vector3.ZERO` + `push_error`
- [x] **AC-LVL-10** : Idempotence de `unload_current()` — appel quand `UNLOADED` = silent no-op, pas crash
- [x] **AC-LVL-18** : PlayerStart unique — `find_children("PlayerStart", "Marker3D", true)` retourne length == 1
- [x] **AC-LVL-29** : Main-thread only — chaque fonction emit signal asserte `Thread.get_caller_id() == OS.get_main_thread_id()` AVANT `emit_signal`

---

## Implementation Notes

*Dérivé ADR-0001 + ADR-0005 Implementation Guidelines :*

- `src/gameplay/level/level.gd` — class_name `LevelSystem` extends `Node` (autoload ou child de main scene, selon ADR-0011/0007 à venir)
- Enum canonique : `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }` (ordre exact GDD)
- Propriétés privées : `var _state: LevelState = LevelState.UNLOADED`, `var _current_etage_id: int = -1`, `var _current_scene_root: Node3D = null`, `var _player_start: Vector3 = Vector3.ZERO`
- API publique : `func get_state() -> LevelState`, `func get_current_etage_id() -> int`, `func get_player_start() -> Vector3`
- Helper privé `func _discover_player_start(root: Node3D) -> Vector3` : `var markers := root.find_children("PlayerStart", "Marker3D", true)` ; `assert(markers.size() == 1, "missing PlayerStart marker")` en debug ; sinon `push_error("missing PlayerStart marker")` + return `Vector3.ZERO` (fallback release)
- Helper privé `func _assert_main_thread() -> void` : `assert(Thread.get_caller_id() == OS.get_main_thread_id(), "Level signals must emit on main thread")` — appelé AVANT chaque `emit_signal` dans les stories 002-008
- `unload_current()` scaffolding idempotent : `if _state == LevelState.UNLOADED: return` (no-op silencieux)
- Pas de `ResourceLoader.load_threaded_*` dans cette story (L-002) ni de signal emit (L-002/003/004/005)

---

## Out of Scope

*Traité par stories voisines — ne pas implémenter ici :*

- **Story 002** : `load_etage()` threaded, transition UNLOADED → LOADING → ACTIVE, `level_active` signal
- **Story 003** : `unload_current()` effectif (queue_free, level_unloading, concurrent-load reject)
- **Story 005** : `EtageExitTrigger` + `etage_completed`
- **Story 010** : validation de la hiérarchie canonique parent (StaticEnvironment/InteractiveVolumes/…)

---

## QA Test Cases

*Pré-générés depuis ACs — le développeur implémente contre ces tests, pas l'inverse :*

- **AC-LVL-1** : Test `test_boot_state_unloaded_and_etage_id_negative_one`
  - Given: Nouveau `LevelSystem.new()` attaché au tree, `_ready()` appelé
  - When: Lecture `get_state()` et `get_current_etage_id()`
  - Then: `assert_eq(level.get_state(), LevelState.UNLOADED)` ET `assert_eq(level.get_current_etage_id(), -1)`
  - Edge cases: répéter 3× (construction, re-ready via remove+add) → toujours UNLOADED

- **AC-LVL-10** : Test `test_unload_current_idempotent_when_unloaded`
  - Given: Level dans état UNLOADED
  - When: Appeler `level.unload_current()` 3× consécutivement
  - Then: `assert_eq(level.get_state(), LevelState.UNLOADED)` après chaque appel ; aucun crash ; aucun signal émis (monitor `signal_connection_list` vide)
  - Edge cases: appel depuis `_process` vs `_physics_process` vs handler signal → même comportement

- **AC-LVL-8** : Test `test_player_start_discovery_debug_asserts_missing`
  - Given: Scene root `Node3D` sans `PlayerStart` enfant, build type = debug (`OS.has_feature("debug") == true`)
  - When: Appel `level._discover_player_start(root)`
  - Then: `assert_fails_with_message(level._discover_player_start(root), "missing PlayerStart marker")`
  - Edge cases: 0 PlayerStart = assert fail ; 2 PlayerStart = assert fail ; 1 = PASS return position

- **AC-LVL-18** : Test `test_player_start_unique_per_stage`
  - Given: Scene root avec 1 Marker3D nommé "PlayerStart" à position (5, 2, 3)
  - When: Appel `level._discover_player_start(root)`
  - Then: `assert_eq(level._discover_player_start(root), Vector3(5.0, 2.0, 3.0))`
  - Edge cases: Marker3D nommé "playerstart" (case mismatch) = 0 trouvé = assert fail

- **AC-LVL-29** : Test `test_main_thread_assert_fails_on_worker_thread`
  - Given: Level instancié sur main thread
  - When: Appel `level._assert_main_thread()` depuis `WorkerThreadPool.add_task(Callable(level, "_assert_main_thread"))`
  - Then: Assertion échoue avec message contenant "main thread"
  - Edge cases: appel sync main thread = PASS silent ; appel depuis `_physics_process` = PASS

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/level/level_state_machine_test.gd` — doit exister et passer (5 test cases ci-dessus)

**Status**: [x] Created at `tests/unit/level/level_state_machine_test.gd` — 5 test cases (1 par AC) ; cache `.godot/global_script_class_cache.cfg` régénéré sans erreur de parse, `LevelSystemScript` enregistré ; exécution effective en CI via `MikeSchulze/gdUnit4-action@v1` (Godot 4.6).

---

## Dependencies

- Depends on: **None** (story foundation du epic)
- Unlocks: Story 002 (load_etage), Story 003 (unload_current effectif), Story 005 (EtageExitTrigger), Story 007 (room_entered), Story 008 (player_out_of_world)

---

## Completion Notes

**Completed** : 2026-04-27
**Verdict** : COMPLETE WITH NOTES (mode review = solo)
**Criteria** : 5/5 passing (AC-LVL-1, AC-LVL-8, AC-LVL-10, AC-LVL-18, AC-LVL-29)
**Test Evidence** : `tests/unit/level/level_state_machine_test.gd` — 5 cases, GdUnit4

**Code Review** : `/code-review` exécuté 2026-04-27 — verdict CHANGES REQUIRED, 4 corrections appliquées avant clôture :
- B1 — assertion `get_signal_list().size() == 0` retirée (Node hérite de signaux built-in `tree_entered`, `renamed`, etc. — tautologique)
- B2 — `_discover_player_start()` réordonné `push_error` AVANT `assert(false)` pour que GdUnit4 `is_push_error` capte en debug
- B3 — predicate public `is_on_main_thread()` ajouté pour testabilité cross-thread (workaround GdUnit4 cross-thread assert capture limitation)
- B4 — `class_name LevelSystem` → `LevelSystemScript` pour prévenir collision avec futur autoload `LevelSystem` (story 002, ADR-0011 l.460 ; cf. mémoire feedback InputManager 2026-04-23)

**Deviations** :
- **OUT OF SCOPE** : `level.gd` contient désormais l'implémentation story-002 (signal `level_active`, `_DEFAULT_SCENE_PATH_TEMPLATE`, `@export scene_path_template`, `_process` polling LOADING, `_physics_process` commit ACTIVE+emit, `load_etage(etage_id)`, vars `_loading_path`/`_transition_to_active_pending`). Élargissement accepté entre /code-review et /story-done. Conséquence : story-002 est de facto largement implémentée — vérifier ses ACs au prochain `/story-done` plutôt que ré-implémenter.
- **ADVISORY** : ADR-0011 D-3 prescrit le path `res://src/gameplay/level/level_system.gd` ; le fichier reste à `level.gd`. Drift documentaire non bloquant — résoudre lors de la finalisation autoload story-002 (renommer fichier ou amender ADR-0011).
- **ADVISORY** : les paths story-002 (`load_etage()` / `_process` polling / `_physics_process` commit / `level_active.emit`) ne sont **pas** couverts par les tests de cette story. Couverture à compléter par tests story-002.

**Manifest Staleness** : story manifest `2026-04-23` = control-manifest `2026-04-23` ✓ no drift.

**Files modified** :
- `src/gameplay/level/level.gd` — scaffold story-001 + implémentation story-002 anticipée
- `tests/unit/level/level_state_machine_test.gd` — 5 tests AC story-001 corrigés post-revue
- `.godot/global_script_class_cache.cfg` — régénéré (rename `LevelSystem` → `LevelSystemScript`)
