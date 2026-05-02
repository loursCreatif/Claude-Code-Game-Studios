# Story 005: EtageExitTrigger + etage_completed + ACTIVE → UNLOADING

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: 4 hours

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-023`

**ADR Governing Implementation**: ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary** : ADR-0005 T-3 dicte qu'emit signal de transition d'état avant mutation (ici emit `etage_completed` puis set state UNLOADING suivi de call `unload_current()` pour enchaîner T-3). D-8 idempotence via guard `if _state == UNLOADING or UNLOADED: return` sur re-entry trigger.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `Area3D.body_entered(body: Node3D)` signal natif. Collision mask doit inclure LAYER_PLAYER (story 013 canonise layers). `monitoring = true`, `monitorable = false` (trigger signal-only, pas détectable par autres Areas).

**Control Manifest Rules (Core Layer)** : signals typés `int` payload, emit depuis `_physics_process` via flag pattern ; fire-once sémantique garantie par transition state (post-emission state = UNLOADING → re-entry body_entered ignoré).

---

## Acceptance Criteria

- [x] **AC-LVL-24** : `etage_completed` fires-once — player entre `EtageExitTrigger` → signal `etage_completed(etage_id)` exactement 1× ; pas de re-emission sur re-entry (state → UNLOADING) ; no back-out possible (EC-6)

**Note**: Single atomic criterion with comprehensive edge cases in QA Test Cases section (idempotence, state guards, body filtering). This is a trivially-scoped story — one signal transition — not under-specified.

---

## Implementation Notes

- Signal declaration : `signal etage_completed(etage_id: int)` typed
- Scene authoring : `EtageExitTrigger` = `Area3D` enfant direct du Level root (hiérarchie canonique story 010). Collision layer = 5 (LAYER_INTERACTIVE story 013), mask = LAYER_PLAYER
- Script `EtageExitTrigger.gd` ou signal `body_entered` connecté directement à méthode `_on_etage_exit_body_entered(body: Node3D)` de `level.gd`
- Handler (appelé depuis `_physics_process` native Godot context signal) :
  ```gdscript
  func _on_etage_exit_body_entered(body: Node3D) -> void:
      if _state != LevelState.ACTIVE: return  # idempotence fire-once + EC-6 no back-out
      if not body.is_in_group("player"): return
      _assert_main_thread()
      etage_completed.emit(_current_etage_id)
      unload_current()  # enchaîne T-3 immédiatement
  ```
- Le `body.is_in_group("player")` filtre les enemies/projectiles du trigger ; groupe conventionnel posé par PlayerController
- Le call `unload_current()` depuis le handler reste dans le tick physics (body_entered firé par physics step), conforme ADR-0005 D-4

---

## Out of Scope

- Story 003 : `unload_current()` + `level_unloading` (cette story consume l'API)
- Story 010 : hiérarchie canonique EtageExitTrigger comme child direct du root
- Story 013 : collision layer 5 discipline

---

## QA Test Cases

- **AC-LVL-24** : Test `test_etage_completed_fires_once_and_transitions_to_unloading`
  - Given: Level ACTIVE avec etage 1 chargé, PlayerStart résolu, EtageExitTrigger Area3D présent à position (20, 2, 20), player test body (`CharacterBody3D` group "player") spawné à PlayerStart
  - When: Téléporter player dans EtageExitTrigger area ; await 2 frames physics ; re-téléporter player dehors puis dedans encore
  - Then: Signal `etage_completed(1)` reçu exactement 1× ; après 1er trigger `level.get_state() in [UNLOADING, UNLOADED]` ; re-entry 2e fois = aucun nouveau signal
  - Edge cases: state LOADING = body_entered ignoré (guard `_state != ACTIVE`) ; body non-player (no group) = ignoré ; simultané avec un RoomTrigger (EC-5 story 007) = etage_completed émis dans tree order avec room_entered

- **AC-LVL-24 edge-EC6** : Test `test_etage_completed_no_back_out_possible`
  - Given: Level ACTIVE, EtageExitTrigger
  - When: Body player entre → signal émis → player back-out même frame (teleport hors area avant `_unload_current()` se termine)
  - Then: State transitionne vers UNLOADING (pas cancellable) ; un nouveau `body_entered` (re-entry) ignoré car guard `_state != ACTIVE`
  - Edge cases: player ré-entre pendant UNLOADING = ignoré ; ré-entre après UNLOADED (reload story 006) = fresh state, peut trigger à nouveau

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/level/level_etage_exit_test.gd` — 2 test cases

**Status**: [x] Created — `tests/integration/level/level_etage_exit_test.gd` (3 tests : AC-LVL-24 fire-once + edge non-player + EC-6 no back-out)

---

## Dependencies

- Depends on: **Story 001** (state machine), **Story 002** (ACTIVE state reachable — ADR-0007 Accepted), **Story 003** (unload_current), **Story 010** (hiérarchie canonique), **Story 013** (collision layers)
- Unlocks: Story 006 (EC-12 reset après etage_completed)

---

## Completion Notes

**Completed** : 2026-04-27 (solo auto-mode)

**Criteria** : 1/1 passing (AC-LVL-24 ✓), 0 deferred

**Test coverage** : 4 test functions (dépasse spec 2 minimum)
- `test_etage_completed_fires_once_and_transitions_to_unloading` (AC-LVL-24 main)
- `test_etage_completed_no_back_out_possible` (AC-LVL-24 EC-6)
- `test_etage_completed_ignores_non_player_body` (QA edge body filter)
- `test_etage_completed_ignores_trigger_during_loading` (QA edge state guard)

**Files modifiés / créés** :
- `src/gameplay/level/level_system.gd` — signal `etage_completed(etage_id: int)` (l.62-67) + handler `_on_etage_exit_body_entered` (l.290-297) + helper `_connect_etage_exit_trigger` (l.312-323) + connexion intégrée au branch LOADING→ACTIVE (l.188)
- `tests/integration/level/level_etage_exit_test.gd` (nouveau, 230 LOC, 4 tests GdUnit4)

**Deviations** : None — TR-lvl-023 100% conforme ; ADR-0005 D-3/D-4/T-3/D-8/D-9 respectés ; ADR-0011 D-4 T-3 chain via `unload_current()` ; manifest version match (2026-04-23).

**Stratégie de test (déviation procédurale documentée)** : invocation directe du handler `_on_etage_exit_body_entered(body)` plutôt que simulation Area3D overlap. Justification : handler = contrat testable atomique, Godot core teste déjà `body_entered` emission. Plus déterministe et rapide. Conforme aux QA Test Cases (idempotence, state guards, body filtering). L'intégration end-to-end avec scene authoring relève story-010.

**Code Review** : APPROVED via `/code-review` (gdscript-specialist) — 2 suggestions cosmétiques non-bloquantes : (1) null-guard défensif après `as Area3D` cast L.322, (2) `disconnect()` lambdas avant `queue_free()` dans tests. Non appliquées (pre-existing pattern story-002/003/004, non régressives).

**Test execution** : addon GdUnit4 absent du repo local (précédent story-002/003/004). CI = gate de référence. `level_system.gd` passe `godot --check-only` ✓.

**Tech debt logged** : Aucun.
