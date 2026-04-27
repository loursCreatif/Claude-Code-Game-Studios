# Story 006: Wall-run detection + state + raycasts latéraux

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-002`, `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt + CharacterBody3D + ShapeCast3D/RayCast3D wall detection)
**Decision Summary**: Wall detection via `%WallRayLeft` et `%WallRayRight` unique-name (Godot 4.5+ pattern). Jolt physics. `_physics_process` autorité. Raycasts désactivés quand Grounded (perf F7).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Jolt RayCast3D stability, `wall_normal` cohérent à vmax)

**Control Manifest Rules**:
- Required: pattern unique-name `%WallRayLeft` / `%WallRayRight` ; raycasts `.enabled = false` en Grounded, `.enabled = true` en Airborne ; gravité spéciale WALL_RUN_GRAVITY=4 + fall cap -3 m/s pendant WallRunning.
- Forbidden: transition Dashing → WallRunning directe (raycasts désactivés pendant Dashing, GDD rule 7) ; mutation `wall_normal` par consumer.
- Guardrail: priorité gauche déterministe sur couloir étroit (AC-MV-34), tests reproductibles.

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-30** : GIVEN `can_wall_run=true`, Airborne, `horiz_speed > WALL_RUN_MIN_SPEED (5 m/s)`, WHEN ≥1 raycast latéral touche mur vertical, THEN `_state == State.WALL_RUNNING` ≤ 3 physics ticks plus tard ET gravité descend à `WALL_RUN_GRAVITY=4`.
- [ ] **AC-MV-31** : GIVEN WallRunning, WHEN plus aucun raycast ne touche, THEN `_state == State.AIRBORNE` au tick suivant ET gravité normale reprend.
- [ ] **AC-MV-33** : GIVEN WallRunning, raycast maintenu, WHEN `WALL_RUN_MAX_DURATION (1.5s)` écoulée sans `jump` ni perte contact, THEN `_state == State.AIRBORNE` à `t ≥ 1.5s`, gravité normale.
- [ ] **AC-MV-34** : GIVEN `can_wall_run=true`, Airborne, `horiz_speed > 5`, WHEN `%WallRayLeft` ET `%WallRayRight` touchent simultanément (couloir ≤ 1.6 m), THEN `_wall_normal == %WallRayLeft.get_collision_normal()` ET `_state == State.WALL_RUNNING` (priorité gauche déterministe).
- [ ] **Fall cap** : pendant WallRunning, `velocity.y >= -WALL_RUN_FALL_CAP (-3 m/s)`.
- [ ] **Raycasts disabled Grounded** : `%WallRayLeft.enabled == false AND %WallRayRight.enabled == false` quand `_state == State.GROUNDED`.
- [ ] **Gate Dashing → WallRunning interdit** : GIVEN Dashing avec raycast touchant mur, WHEN `dash_timer <= 0` → Airborne au tick suivant ; wall-run peut démarrer seulement à partir de là (pas pendant Dashing).
- [ ] **`wall_normal` exposé** : `var wall_normal: Vector3` read-only ; `Vector3.ZERO` hors WallRunning.

---

## Implementation Notes

*Derived from GDD Rule 7 + Edge Cases :*

- Constantes : `const WALL_RUN_MIN_SPEED = 5.0 ; const WALL_RUN_GRAVITY = 4.0 ; const WALL_RUN_FALL_CAP = 3.0 ; const WALL_RUN_MAX_DURATION = 1.5 ; const WALL_DETECT_MARGIN = 0.45` (raycast length 0.35+0.45=0.8 m).
- Variables : `var _wall_normal: Vector3 = Vector3.ZERO`, `var wall_normal: Vector3 : get: return _wall_normal`, `var _wall_run_timer: float = 0.0`.
- Placeholder `var can_wall_run: bool = false` (Story 013).
- `@onready var wall_ray_left: RayCast3D = %WallRayLeft ; @onready var wall_ray_right: RayCast3D = %WallRayRight`.
- Dans `_physics_process(delta)` :
  - Toggle raycasts selon state : `%WallRayLeft.enabled = (_state != State.GROUNDED AND _state != State.DASHING) ; %WallRayRight.enabled = idem`.
  - Si `_state == State.AIRBORNE` ET `can_wall_run` ET `Vector2(velocity.x, velocity.z).length() > WALL_RUN_MIN_SPEED` :
    - `wall_ray_left.force_raycast_update() ; wall_ray_right.force_raycast_update()`
    - `var left_hit := wall_ray_left.is_colliding() ; var right_hit := wall_ray_right.is_colliding()`
    - Si `left_hit` OU `right_hit` → priorité gauche : `_wall_normal = wall_ray_left.get_collision_normal() if left_hit else wall_ray_right.get_collision_normal()` ; `_state = State.WALL_RUNNING` ; `_wall_run_timer = 0.0`.
  - Si `_state == State.WALL_RUNNING` :
    - `_wall_run_timer += delta`
    - `velocity.y -= WALL_RUN_GRAVITY * delta`
    - `velocity.y = max(velocity.y, -WALL_RUN_FALL_CAP)`
    - Check sortie : `left_hit = wall_ray_left.is_colliding() ; right_hit = wall_ray_right.is_colliding()`. Si NEITHER hit → `_state = State.AIRBORNE ; _wall_normal = Vector3.ZERO`. Si `is_on_floor()` → `_state = State.GROUNDED ; _wall_normal = Vector3.ZERO`. Si `_wall_run_timer >= WALL_RUN_MAX_DURATION` → `_state = State.AIRBORNE ; _wall_normal = Vector3.ZERO`.
- Note : gravité Story 003 doit être conditionnée `if _state != State.WALL_RUNNING: velocity.y -= GRAVITY * delta`.

---

## Out of Scope

- Wall-jump (Story 007)
- Signal `wall_run_entered/exited` émission → Story 009
- Camera tilt (consumer) → Camera epic
- `can_wall_run` flag depuis Upgrade → Story 013

---

## QA Test Cases

**AC-MV-30 — entry wall-run** :
- Given : Player Airborne proche mur vertical, `velocity.x=6` (> WALL_RUN_MIN_SPEED), `can_wall_run=true`
- When : mouvement vers mur jusqu'à raycast hit (≤ 3 ticks)
- Then : `_state == State.WALL_RUNNING` au tick du hit, `velocity.y` décrémente de seulement `WALL_RUN_GRAVITY * delta = 0.0667` (vs `GRAVITY * delta = 0.4`).

**AC-MV-31 — exit perte contact** :
- Given : WallRunning
- When : tick où raycasts left ET right ne touchent plus (joueur s'écarte du mur)
- Then : `_state == State.AIRBORNE`, `_wall_normal == Vector3.ZERO`, gravité normale reprend (velocity.y décrémente GRAVITY*delta).

**AC-MV-33 — timeout 1.5s** :
- Given : WallRunning à `t=0`, raycast maintenu constant
- When : `_wall_run_timer` atteint 1.5s (90 ticks à 60 Hz)
- Then : `_state == State.AIRBORNE` au tick 91, `_wall_normal == Vector3.ZERO`.

**AC-MV-34 — couloir étroit priorité gauche** :
- Given : Couloir 1.4 m (< 1.6), `can_wall_run=true`, Airborne, speed=6
- When : les deux raycasts hit simultanément
- Then : `_wall_normal == wall_ray_left.get_collision_normal()` (pas la normale de droite) ; test deterministe sur 100 itérations (seed fixe).

**AC-6 — raycasts disabled Grounded** :
- Given : Player Grounded stationnaire
- When : `_physics_process` tick
- Then : `%WallRayLeft.enabled == false AND %WallRayRight.enabled == false`.

**AC-7 — transition Dashing → WallRunning interdite** :
- Given : Dashing à t=0.03s, raycast gauche touche mur
- When : dash se poursuit jusqu'à `dash_timer <= 0`
- Then : pendant tout Dashing, `_state == State.DASHING` (pas WallRunning) ; à `t > DASH_DURATION`, peut éventuellement entrer WallRunning si conditions encore réunies.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/wall_run_detection_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene tree + raycasts), 003 (Airborne + gravity), 005 (Dashing exit → Airborne avant wall-run possible)
- Unlocks: Story 007 (wall-jump), Story 009 (signals), Story 016 (combo chain)
