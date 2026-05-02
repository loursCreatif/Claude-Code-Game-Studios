# Story 007: Wall-jump + air_jumps_used = MAX (décision Martin r3 A)

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
**Decision Summary**: `_physics_process` autorité. Wall-jump bloque double-jump post (décision Martin r3 A), invariant level design couloirs MVP ≤ 3.25 m.

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: wall-jump `velocity = wall_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP` + `air_jumps_used = MAX_AIR_JUMPS` + transition `State.WALL_RUNNING → State.AIRBORNE` ; invariants runtime `WALL_JUMP_UP² / (2 × GRAVITY_MAX) ≥ 0.7 × JUMP_VELOCITY² / (2 × GRAVITY_MAX)`.
- Forbidden: wall-jump sans reset de `_wall_normal` à Vector3.ZERO.
- Guardrail: input→velocity p99 ≤ 16 ms (ADR-0001 VC-2).

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-32** : GIVEN WallRunning avec `air_jumps_used == 0` avant wall-jump, WHEN `jump` pressed, THEN `velocity == wall_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP ± 0.1`, `air_jumps_used == MAX_AIR_JUMPS`, `_state == State.AIRBORNE`, `_wall_normal == Vector3.ZERO`.
- [ ] **AC-MV-35** : GIVEN Airborne juste après wall-jump (`air_jumps_used == MAX_AIR_JUMPS`), `can_air_jump=true`, WHEN `jump` pressed, THEN rien (double-jump bloqué, décision Martin r3 A).
- [ ] **Priorité wall-jump vs double-jump** : tick où wall-run s'active ET `jump` pressed ce tick → wall-jump gagne (GDD Edge Cases ligne 286).
- [ ] **Air_jumps_used reset uniquement au sol** : après wall-jump, `air_jumps_used` reste à MAX jusqu'à prochaine transition Airborne→Grounded (`is_on_floor()`). GDD Rule 3 + Rule 8 + AC-MV-35.
- [ ] **Trajectoire invariant** : WALL_JUMP_UP ≥ 6.0 m/s (range min r3), gain vertical `h = 6²/(2×24) = 0.75 m` nominal.

---

## Implementation Notes

*Derived from GDD Rule 8 + Formulas > Wall-jump + Edge Cases :*

- Constantes : `const WALL_JUMP_SIDE = 7.0 ; const WALL_JUMP_UP = 6.5` (nominal). `MAX_AIR_JUMPS = 1` déjà défini Story 004.
- Dans `_physics_process(delta)` après check wall-run state :
  - Si `_state == State.WALL_RUNNING` ET `was_pressed_this_tick(&"jump")` :
    - `var launch_vel = _wall_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP`
    - `velocity = launch_vel` (écrase horizontal + vertical)
    - `air_jumps_used = MAX_AIR_JUMPS` (bloque double-jump, décision Martin r3 A)
    - `_state = State.AIRBORNE`
    - `_wall_normal = Vector3.ZERO`
    - *(signal `wall_jumped(wall_normal, launch_velocity)` sera émis Story 009 — ici juste state change)*
- Priorité vs double-jump : le check `_state == State.WALL_RUNNING` précède le check double-jump (`_state == State.AIRBORNE`) dans la séquence `_physics_process`. Donc si au tick N le joueur transite Airborne→WallRunning (Story 006), le `jump` pressé ce même tick tombe dans la branche WALL_RUNNING → wall-jump.
- Invariant `_ready` : `var safe_walljump_h = WALL_JUMP_UP * WALL_JUMP_UP / (2.0 * 24.0) ; var safe_jump_h = JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * 24.0) ; assert(safe_walljump_h >= 0.7 * safe_jump_h, "WALL_JUMP_UP viole invariant 70% single jump height")`.

---

## Out of Scope

- Signal `wall_jumped(Vector3, Vector3)` → Story 009
- Camera shake (consumer) → Camera epic
- Audio `wall_jump.wav` → Audio epic post-MVP

---

## QA Test Cases

**AC-MV-32 — wall-jump full** :
- Given : WallRunning, `_wall_normal=(1, 0, 0)` (mur sur la gauche), `velocity=(0, 0, 10)`, `air_jumps_used=0`
- When : `simulate_action_press(&"jump")`
- Then : `velocity == (7, 6.5, 0) ± 0.1`, `air_jumps_used == 1`, `_state == State.AIRBORNE`, `_wall_normal == Vector3.ZERO`.
- Edge cases : répéter avec `_wall_normal=(-1, 0, 0)` → `velocity.x == -7`.

**AC-MV-35 — double-jump bloqué post wall-jump** :
- Given : Juste après wall-jump, `_state=AIRBORNE`, `air_jumps_used=1`, `can_air_jump=true`, `velocity.y=3.0`
- When : `simulate_action_press(&"jump")`
- Then : `velocity.y` inchangée (pas set à `AIR_JUMP_VELOCITY=6.5`), `air_jumps_used == 1`.

**AC-3 — priorité wall-jump vs double-jump simultanée** :
- Given : Airborne approche mur, `jump` pressé au tick où wall-run s'active
- When : `_physics_process` tick N avec `jump` pressed + raycast hit
- Then : priorité wall-jump — `velocity == wall-jump trajectory`, pas air-jump trajectory ; `_state == State.AIRBORNE` post.
- Edge cases : deterministe (ordre évaluation scripted).

**AC-4 — reset uniquement au sol** :
- Given : Airborne post wall-jump, `air_jumps_used=1`
- When : joueur continue Airborne 2s puis touche sol
- Then : au moment `is_on_floor()=true`, `air_jumps_used == 0` (reset Story 004). Vérifie que ni wall-run re-entry ni wall-jump n'a reset entre-temps.

**Invariant _ready** :
- Given : WALL_JUMP_UP=5.0 (range min r2 obsolète)
- When : `_ready()`
- Then : assert crash `"WALL_JUMP_UP viole invariant 70% single jump height"` (5²/48 = 0.52 < 0.7 × 7.5²/48 = 0.82).
- Edge cases : WALL_JUMP_UP=6.0 minimum acceptable.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/wall_jump_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001, 004 (jump + air_jumps_used counter), 006 (wall-run state + wall_normal)
- Unlocks: Story 009 (signal wall_jumped), Story 016 (combo chain final step)
