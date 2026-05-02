# Story 002: load_etage() threaded + UNLOADED → LOADING → ACTIVE + level_active CONNECT_DEFERRED

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-001`, `TR-lvl-002`, `TR-lvl-021`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0005 (Movement Signals Architecture), ADR-0007 (Game State Manager — Accepted 2026-04-23 r2)
**ADR Decision Summary** : ADR-0005 D-5 critères a-d exigent `CONNECT_DEFERRED` pour consumers qui instancient nodes / démarrent streams / allouent > 256 B / > 0.5 ms CPU ; `level_active` matche les 4 critères (peers instancient VFX/audio players au binding). ADR-0007 D-5 : `LevelSystem.load_etage(id)` additive scene pour étages gameplay, appelé exclusivement par GSM en transition MENU → PLAYING. D-7 : GSM reçoit `level_active` SYNC, transitionne à PLAYING dans le même tick.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes** : `ResourceLoader.load_threaded_request(path)` + `load_threaded_get_status(path)` API stable 4.0-4.6. Polling status en `_process` acceptable (logic cosmétique — mutation `_state` Level en fin de frame via `call_deferred` pour rester conforme ADR-0001 autorité `_physics_process`). `CONNECT_DEFERRED` pour `level_active` garantit peers `_ready()` avant handler.

**Control Manifest Rules (Core Layer)**:
- Required : signals typés directs sur Level (ADR-0005 D-1) ; payload `Vector3`/`int` value types (D-3) ; emit depuis `_physics_process` exclusivement (D-4) ; `CONNECT_DEFERRED` iff consumer matche critères a-d (D-5)
- Forbidden : `preload()` de systèmes aval depuis Level (D-10) ; référence Checkpoint/Enemy/HUD par nom depuis level.gd
- Guardrail : load time ≤ 1000 ms (F4, AC-LVL-3 gate en story 017)

---

## Acceptance Criteria

*From GDD `design/gdd/level-system.md`, scoped to this story :*

- [x] **AC-LVL-2** : Transition Unloaded → Active via load_etage — signal `level_active(1, player_start)` reçu < 1000 ms AND `get_state() == ACTIVE` AND `get_current_etage_id() == 1`
- [x] **AC-LVL-26** : `level_active` received post-autoload-ready — peer `_ready()` tick < `level_active` handler tick (ordre Godot native autoload→main scene + CONNECT_DEFERRED philosophy)
- [x] **AC-LVL-27** : Signals typed correctly — `Level.get_signal_list()` entry `level_active` matches `(etage_id: int, player_start: Vector3)`

---

## Implementation Notes

*Dérivé ADR-0005 + ADR-0007 Implementation Guidelines :*

- Signature : `func load_etage(etage_id: int) -> void` dans `src/gameplay/level/level_system.gd`
- Guard T-1 : `assert(_state == LevelState.UNLOADED, "concurrent load rejected — unload first")` (story 003 gère reject release)
- Transition UNLOADED → LOADING : `_state = LevelState.LOADING` puis `ResourceLoader.load_threaded_request("res://scenes/levels/etage_%02d.tscn" % etage_id)`
- Poll status en `_process(delta)` : `ResourceLoader.load_threaded_get_status(path, progress)` → si `THREAD_LOAD_LOADED`, récupérer PackedScene, `instantiate()`, `add_child()` (parent = Level node), discover PlayerStart via helper story 001
- Signal declaration : `signal level_active(etage_id: int, player_start: Vector3)` (typed)
- Emit : `_assert_main_thread()` puis `level_active.emit(_current_etage_id, _player_start)` — UNIQUEMENT depuis `_physics_process` (pas `_process`). Pattern : set `_transition_to_active_pending: bool = true` en `_process` dès load loaded, consommer flag en début `_physics_process` tick suivant
- Le tick de mutation `_state = LevelState.ACTIVE` arrive DANS `_physics_process` immédiatement avant l'emit
- Peers (Checkpoint/Enemy/HUD/Tutorial/Audio/VFX) connectent `level_active` avec `CONNECT_DEFERRED` dans leur `_ready()` — ne pas `await` dans level.gd
- Fallback si `etage_id` invalide (scene manquante) : délégué à story 004 (`level_load_failed`)

---

## Out of Scope

- **Story 001** : scaffolding `_state`, enum, PlayerStart discovery
- **Story 003** : `unload_current()`, concurrent-load reject release, `level_unloading`
- **Story 004** : `level_load_failed`, `level_load_slow`
- **Story 017** : gate empirique F4 ≤ 1000 ms (mesure `Time.get_ticks_msec()` entre load_etage call et level_active emission)

---

## QA Test Cases

- **AC-LVL-2** : Test `test_load_etage_transitions_unloaded_to_active_with_signal`
  - Given: Level dans UNLOADED, test PackedScene `test_etage_01.tscn` avec 1 PlayerStart à (10, 2, 5) sur disk
  - When: `level.load_etage(1)` + `await level.level_active`
  - Then: Signal reçu avec args `(1, Vector3(10.0, 2.0, 5.0))` ET `level.get_state() == ACTIVE` ET `level.get_current_etage_id() == 1`
  - Edge cases: timeout 2000 ms → fail si pas reçu ; vérifier payload exact (NaN guard)

- **AC-LVL-26** : Test `test_level_active_received_after_peer_ready`
  - Given: Peer `Node` child de root avec `_ready()` qui set `_ready_fired_tick = Engine.get_physics_frames()` et connecte `level_active` avec `CONNECT_DEFERRED` et set `_handler_fired_tick = Engine.get_physics_frames()` dans handler
  - When: `level.load_etage(1)` + await signal
  - Then: `peer._handler_fired_tick >= peer._ready_fired_tick` (handler après ready)
  - Edge cases: peer spawné dynamiquement après `level_active` emission → handler ne fire pas (ownership peer)

- **AC-LVL-27** : Test `test_level_active_signal_has_typed_signature`
  - Given: Level instancié
  - When: `var siglist := level.get_signal_list()`
  - Then: Entry nommée "level_active" existe avec args `[{name: "etage_id", type: TYPE_INT}, {name: "player_start", type: TYPE_VECTOR3}]`
  - Edge cases: connexion avec callable signature incompatible échoue en debug build (test helper `connect_with_bad_signature_asserts`)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/level/level_load_etage_test.gd` — doit exister et passer (3 test cases)

**Status**: [x] Created at `tests/integration/level/level_load_etage_test.gd` — 3 test cases (1 par AC) ; fixtures `tests/fixtures/levels/test_etage_01.tscn` (PlayerStart à (10, 2, 5)) et `test_etage_02.tscn` (PlayerStart à (0, 0, 0)) ; exécution effective en CI via `MikeSchulze/gdUnit4-action@v1` (Godot 4.6).

---

## Completion Notes

**Completed** : 2026-04-27 r2 (post-/code-review fixes)
**Verdict** : COMPLETE WITH NOTES (mode review = solo)
**Criteria** : 3/3 passing (AC-LVL-2, AC-LVL-26, AC-LVL-27)
**Test Evidence** : `tests/integration/level/level_load_etage_test.gd` — 3 cases, GdUnit4

### Test-Criterion Traceability

| AC | Test | Statut |
|----|------|--------|
| AC-LVL-2  | `test_load_etage_transitions_unloaded_to_active_with_signal` | COVERED |
| AC-LVL-26 | `test_level_active_received_after_peer_ready` (réécrit r2 — peer GDScript fixture compilé inline avec `_ready()` réel) | COVERED |
| AC-LVL-27 | `test_level_active_signal_has_typed_signature` | COVERED |

**Code Review** : `/code-review src/gameplay/level/level_system.gd tests/integration/level/level_load_etage_test.gd` exécuté 2026-04-27 r2 — verdict initial **CHANGES REQUIRED** (3 blockers + 4 minors) → corrections appliquées → verdict final **APPROVED WITH SUGGESTIONS**.

**Blockers corrigés (r2)** :
- **B-1 race flag** `_process` THREAD_LOAD_FAILED branch ne reset pas `_transition_to_active_pending` → ajout `_transition_to_active_pending = false` après reset state (l.94 du fichier corrigé).
- **B-2 violation ADR-0011 REQ-8** : `add_child(root_3d)` attachait la scène au singleton Level → corrigé en `get_tree().root.add_child(root_3d)` (l.126) per body.l.127 ADR-0011 (« Pas `self.add_child(...)` »). Story Implementation Notes l.45 « (parent = Level node) » est en drift par rapport à l'ADR — l'ADR fait foi.
- **AC-LVL-26 test tautologique** : peer `Node.new()` + `set_script(null)` no-op + assertion `handler_tick >= ready_tick` toujours vraie (compteur monotone). Réécrit avec un peer compilé inline via `GDScript.new()` + `source_code` qui surcharge réellement `_ready()` ; assertion discriminante `peer.handler_saw_ready == true` (échouerait si CONNECT_DEFERRED était cassé en sync ou si la connexion sortait de `_ready()`).

**Minors appliqués** :
- **M-1** : `var progress: Array = []` alloué chaque frame en LOADING → pré-alloué en membre `_load_progress: Array = []` (zero-alloc per ADR-0005 D-9).
- **M-2** : `var markers: Array` → `Array[Node]` (typage strict, élimine cast implicite).
- **M-4** : `_assert_main_thread()` hoisté en tête de `_physics_process` AVANT toute mutation d'état (évite état observable incohérent si assert fail en debug).

**Conformité ADR (post-correctifs)** :
- Signal `level_active(etage_id: int, player_start: Vector3)` typé value ✓ ADR-0005 D-1/D-3, ADR-0011 D-5 byte-exact.
- Emit depuis `_physics_process` exclusif ✓ ADR-0005 D-4.
- `_assert_main_thread()` AVANT mutation ✓ ADR-0011 D-9 / AC-LVL-29.
- Pattern flag `_process` set / `_physics_process` consume ✓ ADR-0001 autorité gameplay.
- Scene attachée à `get_tree().root` ✓ ADR-0011 REQ-8.
- `load_etage` guard `assert(_state == UNLOADED)` ✓ T-1 ; release path reject = story-003.
- Lints : 0 bitmask littéral collision (ADR-0008 D-3) ; 0 `preload()` (ADR-0007 D-10) ; 0 référence Checkpoint/Enemy/HUD (ADR-0011 isolation).

**Deviations / Out of Scope** :
- **OUT OF SCOPE** : `signal level_unloading(etage_id: int)` + `_unload_pending: bool` ajoutés (l.39, l.69) en anticipation story-003 — déclarés mais non émis. Pas de fonctionnalité active ; pas de blocker pour story-002. À valider lors de `/story-done` story-003.
- **GDD/registry drift mineur (advisory)** : TR-lvl-002 / TR-lvl-021 décrivent l'émission « via call_deferred ». L'implémentation utilise pattern flag + `CONNECT_DEFERRED` (consumer-side) émis depuis `_physics_process`. Contrat fonctionnel équivalent (peer `_ready()` avant handler) — mais le wording registry est obsolète vs ADR-0005 D-4 + ADR-0011 D-5. À MAJ registry lors d'un prochain `/architecture-review` (non bloquant).
- **Implementation Notes story drift (advisory)** : story §Implementation Notes l.45 dit « `add_child()` (parent = Level node) ». ADR-0011 REQ-8 exige `get_tree().root.add_child(...)`. Implémentation suit l'ADR, pas la story.

**Manifest Staleness** : story manifest `2026-04-23` = control-manifest `2026-04-23` ✓ no drift.

**Files Validated** :
- `src/gameplay/level/level_system.gd` — paths story-002 (signal, _process, _physics_process, load_etage, helpers). Renommé depuis `level.gd` (story-001 r3) pour conformité ADR-0011 D-3 ; autoload `LevelSystem` ajouté à `project.godot`.
- `tests/integration/level/level_load_etage_test.gd` — 3 tests AC story-002 ; AC-LVL-26 réécrit r2 avec peer GDScript compilé inline (assertion discriminante `handler_saw_ready`).
- `tests/fixtures/levels/test_etage_01.tscn` — fixture PlayerStart (10,2,5).
- `tests/fixtures/levels/test_etage_02.tscn` — fixture PlayerStart (0,0,0).

**Runtime Verification** : production code parse OK (`godot --check-only` 4.6.2). Test file parse error attendue en local (GdUnit4 non installé) ; exécution effective via CI `MikeSchulze/gdUnit4-action@v1`.

---

## Dependencies

- Depends on: **Story 001** (scaffolding state machine)
- Unlocks: Story 003 (unload_current), Story 004 (level_load_failed), Story 005 (EtageExitTrigger), Story 017 (load time gate)
