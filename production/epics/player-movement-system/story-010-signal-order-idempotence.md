# Story 010: Signal order determinism + idempotence par transition

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0005 (Movement Signals Architecture) — D-6 ordre intra-tick sortie-avant-entrée, D-8 idempotence par transition
**Decision Summary**: Ordre émission : sortie état courant avant entrée nouvel état, `died` terminal, `respawned` reset implicite (pas de `grounded_entered`), `attacked` en fin de tick. Signaux d'entrée idempotents (1× par transition) — guards `if _state == NEW: return` AVANT emit.

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: ordre D-6 respecté (sortie avant entrée, `died` terminal, `attacked` fin de tick) ; guards idempotence `_state != new_state` avant state assignment + emit.
- Forbidden: re-emit d'un signal d'entrée d'état pendant que le même état persiste (e.g. wall_run_entered re-émis parce que raycast perd contact puis retrouve sans sortir d'abord).
- Guardrail: tests déterministes reproductibles (seed fixe, ordre scripted).

---

## Acceptance Criteria

*From ADR-0005 D-6 / D-8 + VC-3 / VC-4 :*

- [ ] **VC-3 : Ordre die-during-dash** : GIVEN `_state=DASHING` au tick N, WHEN `die()` appelé tick N, THEN consumer reçoit `dash_ended` AVANT `died` dans le même tick, timestamps croissants. Implémentation : dans `die()`, si `_state == DASHING` : `dash_ended.emit() ; _state = DEAD ; died.emit()`.
- [ ] **Ordre die-during-wall-run** : GIVEN `_state=WALL_RUNNING`, WHEN `die()` appelé, THEN `wall_run_exited` émis AVANT `died` (capture `_wall_normal` AVANT reset).
- [ ] **Ordre wall-jump** : GIVEN `_state=WALL_RUNNING`, WHEN `jump` pressed, THEN `wall_run_exited` émis AVANT `wall_jumped` (story 007 + ce flow).
- [ ] **`died` terminal** : GIVEN `_state=DEAD`, WHEN quel que soit l'événement dans le même tick + N ticks suivants jusqu'à `respawn()`, THEN aucun signal Movement hors `respawned` émis.
- [ ] **`respawned` implicit grounded** : GIVEN respawn, WHEN `_state` bascule DEAD→GROUNDED, THEN `respawned(pos)` émis 1×. PAS de `grounded_entered` (inexistant — canonical list D-2 figée 8 signaux).
- [ ] **`attacked` fin de tick** : GIVEN le tick a eu une transition d'état (dash_start + attack ce même tick), WHEN `_physics_process` finit, THEN ordre : signaux state machine (dash_started...) PUIS `attacked.emit()` en dernier.
- [ ] **VC-4 : Idempotence `wall_run_entered`** : GIVEN Airborne approche mur, WHEN state machine entre en WallRunning, reste 0.5s, sort (raycast perd contact), re-entre (retrouve contact), THEN `wall_run_entered` émis exactement 2× (1 par entrée réelle).
- [ ] **Idempotence `dash_started`** : GIVEN `* → State.DASHING`, WHEN dash en cours (N ticks), THEN `dash_started` émis exactement 1× à l'entrée.
- [ ] **Idempotence `wall_jumped`** : jump tenu pendant le reste du frame ne re-emit pas.
- [ ] **Idempotence pattern implémentation** : chaque transition met à jour `_state` AVANT emit. Guards `if _state == NEW_STATE: return` au début des fonctions d'entrée.

---

## Implementation Notes

*Derived from ADR-0005 D-6 / D-8 + AC-MV-41 (déjà couvert Story 008 idempotence die) :*

- Refactor `_physics_process` pour exposer clairement l'ordre :
  1. Lecture inputs
  2. Check transitions de sortie d'état courant (ex: `DASHING → GROUNDED/AIRBORNE` via `dash_timer <= 0`) — émettre `dash_ended` AVANT changer `_state`.
  3. Logique gravité / mouvement horizontal selon état.
  4. Check transitions d'entrée (nouvel état déclenché : wall-run entry, dash entry, wall-jump) — appliquer guard `if _state == target: return` + mutation `_state` AVANT emit.
  5. `move_and_slide()`
  6. Check `is_on_floor()` post-move pour transition Grounded↔Airborne implicite.
  7. `attacked` forward (si pas DEAD) — émis en DERNIER.
- Dans `die()` (refactor Story 008) :
  ```
  func die() -> void:
      if _state == State.DEAD:
          return
      # ordre D-6 : sortir de l'état courant d'abord
      match _state:
          State.DASHING:
              dash_ended.emit()
          State.WALL_RUNNING:
              var saved_normal = _wall_normal
              _wall_normal = Vector3.ZERO
              wall_run_exited.emit()
      _state = State.DEAD
      velocity = Vector3.ZERO
      _respawn_timer = RESPAWN_DELAY
      died.emit()
  ```
- Dans wall-jump (refactor Story 007) :
  ```
  if _state == State.WALL_RUNNING and was_pressed_this_tick(&"jump"):
      var saved_normal = _wall_normal
      var launch_vel = saved_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP
      velocity = launch_vel
      air_jumps_used = MAX_AIR_JUMPS
      _wall_normal = Vector3.ZERO
      _state = State.AIRBORNE
      wall_run_exited.emit()   # sortie d'abord
      wall_jumped.emit(saved_normal, launch_vel)   # puis entrée du nouvel événement
  ```
- Idempotence wall_run_entered : dans la logique entry Story 006, condition `if _state != State.WALL_RUNNING and <conditions>`. Le `_state = State.WALL_RUNNING` s'applique AVANT `wall_run_entered.emit(_wall_normal)`. Re-entry = transition Airborne→WallRunning nouvelle → 1 emit.
- Entry guards explicites ajoutés à chaque fonction interne de transition (pattern D-8).

---

## Out of Scope

- Zero-alloc des emits → Story 011
- Dispatch performance cumul → Story 014
- Test bench lourd cross-state → Story 015/016

---

## QA Test Cases

**VC-3 — die during dash order** :
- Given : Dashing à t=0.05s, consumer stub enregistre `(signal_name, usec_timestamp)` via `Time.get_ticks_usec()` dans callbacks
- When : `player.die()` à tick N
- Then : `dash_ended` reçu puis `died` (timestamps croissants, même `_physics_process`).
- Edge cases : répéter avec WallRunning → `wall_run_exited` AVANT `died`.

**Ordre wall-jump** :
- Given : WallRunning
- When : `simulate_action_press(&"jump")`
- Then : `wall_run_exited` reçu AVANT `wall_jumped`, payload `wall_jumped.wall_normal` == `_wall_normal` d'avant reset.

**`died` terminal** :
- Given : `_state=DEAD`
- When : 5 ticks écoulés avec inputs jump/dash simulés
- Then : aucun signal Movement reçu (ni dash_started, ni attacked, ni wall_run_entered).
- Edge cases : seul `respawned` émis après delay.

**`respawned` unique** :
- Given : respawn lifecycle Story 008
- When : transition DEAD→GROUNDED
- Then : `respawned(pos)` reçu exactement 1× ; 0 signal `dash_started`/`wall_run_entered`/... au tick du respawn.

**`attacked` fin de tick** :
- Given : tick avec dash entry + attack pressed
- When : `_physics_process` se termine
- Then : ordre reçu : `dash_started(...)` puis `attacked()` ; jamais l'inverse.

**VC-4 — idempotence wall_run_entered** :
- Given : scénario scripted Airborne→WallRunning (0.5s) → raycast perd contact (Airborne) → retrouve contact (WallRunning de nouveau)
- When : durée totale 2s
- Then : consumer compte `wall_run_entered == 2`, `wall_run_exited == 2`. Pas 3 ou plus.

**Idempotence dash_started** :
- Given : transition Grounded→Dashing à tick N
- When : dash en cours 6 ticks
- Then : `dash_started` reçu exactement 1× (au tick N).

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/movement/signal_order_idempotence_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 009 (signals déclarés + branchés), Stories 005-008 (state machine)
- Unlocks: Story 014 (perf benchmark signals), Story 016 (combo chain assertions signal order)
