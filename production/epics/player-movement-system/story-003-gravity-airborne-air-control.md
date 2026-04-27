# Story 003: Custom gravity + Airborne air control

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-003`, `TR-mov-007`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt, amendement `default_gravity=0.0`)
**Decision Summary**: MovementController applique gravité custom `GRAVITY=24` dans `_physics_process` (hors WallRunning). Jolt `default_gravity=0.0` pour éviter double-cumul. Airborne utilise `move_toward(velocity.xz, wish_dir*MOVE_SPEED, AIR_CONTROL_FACTOR*delta)`.

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Jolt gravity-disable TR-mov-007 critical, validé ADR-0001 amendement 2026-04-21)

**Control Manifest Rules**:
- Required: MovementController applique gravité custom GRAVITY=24 manuellement `_physics_process` (hors WallRunning) ; transitions Grounded↔Airborne basées sur `is_on_floor()`.
- Forbidden: ajouter `default_gravity` globale Jolt ; muter `velocity.y` depuis `_process`.
- Guardrail: physics budget ≤ 4 ms/frame p99 (ADR-0001 VC-4).

---

## Acceptance Criteria

*From GDD (subset, Airborne-scoped) :*

- [ ] **Gravité custom** : GIVEN Player Airborne à `velocity.y=0`, WHEN 0.5s passe, THEN `velocity.y ≈ -12.0 m/s ± 0.5` (g=24 × 0.5).
- [ ] **Pas de double-cumul Jolt** : `ProjectSettings.get_setting("physics/3d/default_gravity") == 0.0` (assert runtime au `_ready`) ; mesure velocity.y confirme gravité = 24 m/s² et non 24+9.8.
- [ ] **Transition Grounded→Airborne** : GIVEN Grounded, WHEN `is_on_floor()` devient false (step off ledge), THEN `_state == State.AIRBORNE` au tick suivant. (Prépare Story 004 qui gère jump entry.)
- [ ] **Transition Airborne→Grounded** : GIVEN Airborne, WHEN `is_on_floor()` devient true, THEN `_state == State.GROUNDED` au tick suivant. `air_jumps_used = 0` sera géré Story 004.
- [ ] **Air control — recentré** : GIVEN Airborne à `velocity.xz = (-10, 0)` (moving left), WHEN input `move_right` tenu pendant 0.5s, THEN `velocity.xz.x ≈ -10 + 0.5 * k_air ≈ -10 + 32.5 ≈ 22.5` clampé par `move_toward` vers `+10` → valeur réelle ≈ +10 (atteinte en `20/65 ≈ 308ms`). Après 1s → stabilisé à `+MOVE_SPEED ± 0.3`.

---

## Implementation Notes

*Derived from GDD Rule 2 (transitions) + Formulas > Gravité + Formulas > Airborne air control :*

- Ajouter `const GRAVITY = 24.0`, `const AIR_CONTROL_FACTOR = 65.0`, `const MOVE_SPEED = 10.0` (si pas déjà fait Story 002).
- Dans `_physics_process(delta)` après la lecture wish_dir :
  - Si `_state == State.GROUNDED` ET `is_on_floor() == false` → transition vers `State.AIRBORNE` (mettre `_state = State.AIRBORNE` AVANT emit éventuel).
  - Si `_state == State.AIRBORNE` ET `is_on_floor() == true` → `_state = State.GROUNDED`.
- Branche Grounded : code Story 002 (horizontal binaire).
- Branche Airborne :
  - `air_wish = wish_dir_3d * MOVE_SPEED`
  - `velocity.x = move_toward(velocity.x, air_wish.x, AIR_CONTROL_FACTOR * delta)`
  - `velocity.z = move_toward(velocity.z, air_wish.z, AIR_CONTROL_FACTOR * delta)`
  - Attention : ne PAS additionner `AIR_CONTROL_FACTOR * delta` à velocity — utiliser move_toward (plafonne à la cible).
- Gravité appliquée dans les deux états (Grounded tolère via `is_on_floor()` absorbé par `move_and_slide`) mais hors WallRunning (State.WALL_RUNNING sera géré Story 006) :
  - Si `_state != State.WALL_RUNNING` : `velocity.y -= GRAVITY * delta`.
- Assertion `_ready` : `assert(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) == 0.0, "ADR-0001: default_gravity must be 0.0 to prevent double-cumul with custom GRAVITY")`.

---

## Out of Scope

- Jump / double-jump (Story 004)
- Dash gravity override (Story 005)
- Wall-run gravity reduction WALL_RUN_GRAVITY=4 + fall cap (Story 006)

---

## QA Test Cases

**AC-1 — gravité 24 m/s² Airborne** :
- Given : Player `position.y=10`, `velocity=Vector3.ZERO`, `_state=AIRBORNE`
- When : 30 physics ticks (0.5s)
- Then : `abs(velocity.y - (-12.0)) < 0.5`
- Edge cases : `position.y ≈ 10 - 0.5*24*0.25 = 7 ± 0.5`.

**AC-2 — default_gravity=0 assert** :
- Given : `_ready()` appelé
- When : ProjectSettings.default_gravity != 0.0
- Then : assert crash debug build avec message ADR-0001.

**AC-3 — air control recentré Ghostrunner-like** :
- Given : Player Airborne `velocity=(-10, 0, 0)`, wish_dir=(1,0,0)
- When : 1 physics tick (`delta=1/60`)
- Then : `velocity.x ≈ -10 + 65/60 ≈ -8.917 ± 0.01`
- Edge cases : après `20/65 ≈ 0.308s` (~18-19 ticks), `velocity.x ≈ 10 ± 0.3`.

**AC-4 — transitions Grounded↔Airborne** :
- Given : Player Grounded sur plateforme edge
- When : step off (position avance jusqu'à `is_on_floor()=false`)
- Then : `_state == State.AIRBORNE` au tick où `is_on_floor()` bascule.
- Inverse : Airborne qui retombe → Grounded.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/gravity_airborne_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene + state enum), Story 002 (wish_dir + Grounded)
- Unlocks: Story 004 (jump = Airborne entry), Story 005 (dash désactive gravité), Story 006 (wall-run override gravité)
