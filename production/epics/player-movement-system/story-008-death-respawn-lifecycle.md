# Story 008: Death + respawn lifecycle + idempotence

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-003`, `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADRs Governing**: ADR-0001 (Physics Rate 60 Hz — autorité gameplay), ADR-0005 (Movement Signals — `died`/`respawned` signals + idempotence D-8 + invariant RESPAWN_DELAY VC-7)
**Decision Summary**: `die()` idempotent (early return `if _state == DEAD: return`). `RESPAWN_DELAY=50ms` ≥ 1/DISPLAY_TICK_RATE invariant. Partial cooldown si mort pendant Dashing (AC-MV-24), full reset sinon (AC-MV-42).

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: `die()` early return pattern ; assert `_ready` `RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE` ; ordre D-6 intra-tick : sortie état (dash_ended) AVANT `died`, `died` terminal.
- Forbidden: muter état Movement depuis signal handler consumer (pattern D-7) ; emit `died` hors `_physics_process` ; utiliser `Timer.timeout.connect` pour driver respawn delay.
- Guardrail: respawn total ≤ 100 ms (AC-MV-40 + Feel AC Respawn total).

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-40** : GIVEN n'importe quel état vivant, WHEN `die()` appelé au tick T, THEN au tick T : `_state == State.DEAD` + signal `died` émis exactement 1×. Pendant `t ∈ [T, T + RESPAWN_DELAY]` : inputs ignorés (velocity inchangée par inputs). À `t = T + RESPAWN_DELAY + 1 tick` : `position == checkpoint.position ± 0.01`, `velocity == Vector3.ZERO`, `_state == State.GROUNDED`, `inputs_accepted == true`.
- [ ] **AC-MV-41** : GIVEN `_state == DEAD`, WHEN `die()` rappelé 3× dans le même physics tick, THEN signal `died` émis exactement 1× au total (early return pattern godot-specialist F6).
- [ ] **AC-MV-24** : GIVEN `is_dashing=true` à t=0.05s de Dashing, WHEN `die()` appelé, THEN après respawn : `is_dashing=false`, `dash_timer=0`, `_dash_cooldown_timer ∈ [DASH_COOLDOWN*0.4, DASH_COOLDOWN*0.6] (partial)`, `velocity=Vector3.ZERO`.
- [ ] **AC-MV-42** : GIVEN mort standard (hors Dashing), WHEN `respawn()` s'exécute, THEN `_dash_cooldown_timer == 0.0` (dash immédiatement disponible au retry, rétention Pillar 3).
- [ ] **Reset total au respawn** : `air_jumps_used=0`, `_wall_run_timer=0`, `_wall_normal=Vector3.ZERO`, `_momentum_timer=0`, transition directe → `State.GROUNDED`.
- [ ] **Invariant runtime `_ready`** : `assert(RESPAWN_DELAY * 1000.0 >= 1000.0 / 60.0, "ADR-0005 VC-7 RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE invariant")`.
- [ ] **Signal `respawned(spawn_position: Vector3)`** émis 1× au tick de respawn post-delay (émis dans `respawn()` appelée depuis `_physics_process`).
- [ ] **Method `set_checkpoint(pos: Vector3)`** publique pour Checkpoint System.

---

## Implementation Notes

*Derived from GDD Rule 9 + Published API > `die()` + Edge Cases + ADR-0005 D-8 :*

- Constantes : `const RESPAWN_DELAY = 0.05 ; const DISPLAY_TICK_RATE = 60.0`.
- Variables : `var _checkpoint_position: Vector3 = Vector3.ZERO`, `var _respawn_timer: float = 0.0`, `var _was_dashing_at_death: bool = false`.
- Method `die() -> void` :
  ```
  func die() -> void:
      if _state == State.DEAD:
          return  # idempotent AC-MV-41 + ADR-0005 D-8
      _was_dashing_at_death = (_state == State.DASHING)
      # ordre D-6 : sortie état courant AVANT died
      if _state == State.DASHING:
          # sera Story 009 → dash_ended.emit()
          pass
      elif _state == State.WALL_RUNNING:
          # sera Story 009 → wall_run_exited.emit()
          _wall_normal = Vector3.ZERO
      _state = State.DEAD
      velocity = Vector3.ZERO
      _respawn_timer = RESPAWN_DELAY
      # sera Story 009 → died.emit()
  ```
- Dans `_physics_process(delta)` :
  - Si `_state == State.DEAD` :
    - Ignore tous inputs (pas de lecture `was_pressed_this_tick`).
    - `_respawn_timer -= delta`
    - Si `_respawn_timer <= 0.0` → appeler `respawn(_checkpoint_position)` (transition DEAD→GROUNDED).
- Method `respawn(pos: Vector3) -> void` (private-ish, called from `_physics_process`) :
  ```
  func respawn(pos: Vector3) -> void:
      global_position = pos
      velocity = Vector3.ZERO
      air_jumps_used = 0
      _wall_run_timer = 0.0
      _wall_normal = Vector3.ZERO
      _momentum_timer = 0.0
      dash_timer = 0.0
      # cooldown : partial si was dashing, full reset sinon (Edge Cases Respawn)
      if _was_dashing_at_death:
          _dash_cooldown_timer = DASH_COOLDOWN * 0.5
      else:
          _dash_cooldown_timer = 0.0
      _was_dashing_at_death = false
      _state = State.GROUNDED
      # sera Story 009 → respawned.emit(pos)
  ```
- Method publique :
  ```
  func set_checkpoint(pos: Vector3) -> void:
      _checkpoint_position = pos
  ```
- `_ready` ajoute assert : `assert(RESPAWN_DELAY * 1000.0 >= 1000.0 / DISPLAY_TICK_RATE, "ADR-0005 VC-7: RESPAWN_DELAY below 1 display frame — deferred consumers may not receive died before respawn")`.

---

## Out of Scope

- Emit `died` / `respawned` signaux → Story 009 (cette story appelle state transition, Story 009 branche les `.emit()` avec test typed contract)
- Hazards / Enemies déclencheurs de `die()` → epics downstream
- Camera fade rouge, VFX, Audio → consumers externes

---

## QA Test Cases

**AC-MV-40 — respawn lifecycle complet** :
- Given : Player Grounded à `position=(10, 0, 5)`, `_checkpoint_position=(0, 0, 0)`, `velocity=(3, 0, 4)`
- When : `die()` appelé, 4 physics ticks écoulés (RESPAWN_DELAY=50ms = 3 ticks à 60Hz + 1 post)
- Then : au tick T : `_state==DEAD`, velocity=ZERO ; pendant T..T+3 : inputs ignorés (simuler `move_forward` pressed → velocity.xz reste ZERO) ; à T+4 : `position ≈ (0,0,0) ± 0.01`, `_state==GROUNDED`, `air_jumps_used==0`.
- Edge cases : compter exactement les ticks physics avec `Engine.get_physics_frames()`.

**AC-MV-41 — die idempotence 3× same tick** :
- Given : Player vivant
- When : `die() ; die() ; die()` dans le même `_physics_process` (simuler 3 hazards overlapping)
- Then : transition DEAD exactement 1× ; (Story 009 ajoute) `died.emit()` exactement 1×.

**AC-MV-24 — die pendant dash partial cooldown** :
- Given : Dashing à t=0.05s, `_dash_cooldown_timer=0.75` (au cours du dash, cooldown set dès entry Story 005)
- When : `die()` puis respawn
- Then : `dash_timer==0`, `_dash_cooldown_timer ∈ [0.32, 0.48] = [0.8*0.4, 0.8*0.6]`, `velocity==ZERO`, `is_dashing==false`.

**AC-MV-42 — die Grounded full reset cooldown** :
- Given : Grounded (pas Dashing), `_dash_cooldown_timer=0.5` (dash utilisé récemment)
- When : `die()` + respawn
- Then : `_dash_cooldown_timer == 0.0`.

**Invariant RESPAWN_DELAY** :
- Given : `RESPAWN_DELAY=0.010` (10 ms < 16.66 ms)
- When : `_ready()`
- Then : assert crash avec ADR-0005 VC-7 message.

**Method `set_checkpoint`** :
- Given : Player init, `_checkpoint_position==(0,0,0)`
- When : `player.set_checkpoint(Vector3(42, 1, 7))`
- Then : `die()` puis respawn → `position ≈ (42, 1, 7) ± 0.01`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/movement/death_respawn_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001, 002, 003, 004, 005, 006, 007 (state machine complète avant de pouvoir les teardown)
- Unlocks: Story 009 (emit signals dans `die()`/`respawn()`), Story 015 (mock Checkpoint), Story 016 (combo chain tolère die mid-sequence)
