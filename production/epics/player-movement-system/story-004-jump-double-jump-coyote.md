# Story 004: Jump + Double-jump + air_jumps_used + Coyote time

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt)
**Decision Summary**: `_physics_process` autorité gameplay unique. `Engine.get_physics_frames()` pour timing déterministe tick-based (coyote time). Pattern anti-drop input via `InputManager.was_pressed_this_tick(&"jump")` (ADR-0004 D-1).

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: `InputManager.was_pressed_this_tick(&"jump")` polling depuis `_physics_process` ; compteur `air_jumps_used` reset uniquement au contact sol (Grounded entry) ; coyote timer tick-based.
- Forbidden: `Input.is_action_just_pressed` direct hors InputManager ; mutation `velocity.y` depuis `_process`.
- Guardrail: input→velocity latency p99 ≤ 16 ms (ADR-0001 VC-2).

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-10** : GIVEN Grounded, WHEN `jump` pressed, THEN `velocity.y == JUMP_VELOCITY` au tick suivant, peak atteint `JUMP_VELOCITY² / (2*GRAVITY) ± 0.05 m`.
- [ ] **AC-MV-11** : GIVEN Airborne `air_jumps_used=0` ET `can_air_jump=true`, WHEN `jump` pressed, THEN `velocity.y == AIR_JUMP_VELOCITY` ET `air_jumps_used == 1`.
- [ ] **AC-MV-12** : GIVEN Airborne `air_jumps_used=1` ET `can_air_jump=true`, WHEN `jump` pressed, THEN rien (pas de triple-jump).
- [ ] **AC-MV-13** : GIVEN Airborne `can_air_jump=false`, WHEN `jump` pressed, THEN rien.
- [ ] **AC-MV-14** : GIVEN joueur vient de quitter sol sans jump (fall), WHEN `jump` pressed ≤ 100 ms après transition `is_on_floor()` true→false, THEN saut sol exécuté (pas d'air-jump consumé).
- [ ] **Just-pressed edge** : input `jump` tenu ne saute pas en continu — consommer 1 edge press par tick max.
- [ ] **Reset air_jumps_used** : à chaque transition `State.AIRBORNE` → `State.GROUNDED`, `air_jumps_used = 0`.

---

## Implementation Notes

*Derived from GDD Rules 2/3/4 + Tuning Knobs + ADR-0001 Pattern d'input sampling :*

- Constantes : `const JUMP_VELOCITY = 7.5 ; const AIR_JUMP_VELOCITY = 6.5 ; const MAX_AIR_JUMPS = 1 ; const COYOTE_TIME_TICKS = 6` (6 ticks × 16.6 ms = 100 ms à 60 Hz).
- Variables membres : `var air_jumps_used: int = 0`, `var _coyote_timer_ticks: int = 0` (décrémenté chaque tick, set à COYOTE_TIME_TICKS à la transition Grounded→Airborne NON due à un jump).
- Placeholder `var can_air_jump: bool = false` (sera câblé à Upgrade System Story 013).
- Dans `_physics_process(delta)` après transition state :
  ```
  if _state == State.GROUNDED:
      air_jumps_used = 0
      _coyote_timer_ticks = 0
      if was_pressed_this_tick(&"jump"):
          velocity.y = JUMP_VELOCITY
          # transition GROUNDED→AIRBORNE traitée naturellement au tick suivant
  elif _state == State.AIRBORNE:
      if was_pressed_this_tick(&"jump"):
          if _coyote_timer_ticks > 0:
              velocity.y = JUMP_VELOCITY  # coyote jump, ne consume pas air-jump
              _coyote_timer_ticks = 0
          elif can_air_jump and air_jumps_used < MAX_AIR_JUMPS:
              velocity.y = AIR_JUMP_VELOCITY
              air_jumps_used += 1
      if _coyote_timer_ticks > 0:
          _coyote_timer_ticks -= 1
  ```
- Detecting "quitter sol sans jump délibéré" : lors de transition Grounded→Airborne, si la cause n'est PAS `jump` pressed ce tick → set `_coyote_timer_ticks = COYOTE_TIME_TICKS`. Pratique : détecter via `was_jumping_this_tick: bool` flag local au tick.

---

## Out of Scope

- Jump buffer (AC-MV-15 POST-MVP, décision Martin r2)
- Wall-jump (Story 007 — set `air_jumps_used = MAX_AIR_JUMPS`)
- Dash (Story 005)
- `can_air_jump` flip par Upgrade (Story 013)

---

## QA Test Cases

**AC-MV-10 — jump sol hauteur** :
- Given : Player Grounded, `JUMP_VELOCITY=7.5`, `GRAVITY=24`
- When : `simulate_action_press(&"jump")`, attendre peak `t = JUMP_VELOCITY/GRAVITY ≈ 0.3125s`
- Then : `max(position.y) - spawn.y ≈ 7.5²/(2*24) = 1.172 m ± 0.05`
- Edge cases : tick précis = 19 ticks physics à 60 Hz.

**AC-MV-11 — double-jump consume** :
- Given : Airborne, `air_jumps_used=0`, `can_air_jump=true`, `velocity.y=-5`
- When : `simulate_action_press(&"jump")`
- Then : `velocity.y == AIR_JUMP_VELOCITY (=6.5) ± 0.001` ET `air_jumps_used == 1`

**AC-MV-12 — no triple-jump** :
- Given : Airborne, `air_jumps_used=1`, `can_air_jump=true`
- When : `simulate_action_press(&"jump")`
- Then : `velocity.y` inchangée (pas de mutation vers `AIR_JUMP_VELOCITY`)

**AC-MV-13 — ability gated** :
- Given : Airborne, `air_jumps_used=0`, `can_air_jump=false`
- When : `simulate_action_press(&"jump")`
- Then : `velocity.y` inchangée, `air_jumps_used == 0` (pas d'incrément)

**AC-MV-14 — coyote 100 ms** :
- Given : Player step off ledge sans jump à tick 0
- When : `simulate_action_press(&"jump")` à tick 5 (= 83 ms < 100 ms window)
- Then : `velocity.y == JUMP_VELOCITY` (coyote jump), `air_jumps_used == 0`
- Edge cases : tick 7 (= 116 ms > window) → jump consume air-jump à la place.

**AC-6 — edge-triggered (hold no spam)** :
- Given : Grounded, `jump` maintenu pressé 10 ticks
- When : `was_pressed_this_tick(&"jump")` polling
- Then : 1 seul saut exécuté (1er tick), ticks 2-10 `velocity.y` laissée à gravité.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/jump_coyote_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001, Story 002, Story 003 (transitions Grounded↔Airborne)
- Unlocks: Story 005 (dash cancel jump mid-air), Story 006 (wall-run priority wall-jump vs double-jump), Story 007 (wall-jump set air_jumps_used=MAX)
