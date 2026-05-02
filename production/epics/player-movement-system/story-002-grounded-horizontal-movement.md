# Story 002: Grounded horizontal movement (stop instantané)

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt)
**Decision Summary**: `_physics_process` unique autorité mutation gameplay ; formules calibrées dt=1/60.

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Jolt CharacterBody3D `move_and_slide` — pas de drift 4.4→4.6)
**Engine Notes**: `move_and_slide()` n'a pas `delta` param en 4.x (diffère 3.x). Utiliser `CharacterBody3D.velocity` direct.

**Control Manifest Rules (Core layer)**:
- Required: mutation horizontal velocity uniquement dans `_physics_process` ; `InputManager.was_pressed_this_tick` / API polling consommée depuis `_physics_process`.
- Forbidden: mutation `velocity` en `_process` ; `Input.get_vector` hors InputManager.
- Guardrail: tests GUT déterministes (injection `Input.parse_input_event(InputEventAction)`).

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-01** : GIVEN Grounded, WHEN presse `W` pendant 1 s, THEN position a avancé de `MOVE_SPEED * 1 = 10 m` ± 0.3 m.
- [ ] **AC-MV-02** : GIVEN Grounded moving, WHEN relâche tous inputs move, THEN vélocité horizontale `Vector2.ZERO` au tick suivant (stop instantané, max 1 physics tick ≈ 16.6 ms).
- [ ] **AC-MV-03** : GIVEN Grounded, WHEN presse `A`+`D` simultanément, THEN vélocité horizontale reste 0.

---

## Implementation Notes

*Derived from GDD Rule 1 + Formulas > Déplacement horizontal (Grounded) + ADR-0001 D-1 :*

- Dans `_physics_process(delta)`, lire `move_forward/back/left/right` via `InputManager.was_pressed_this_tick` ou poll équivalent (dépend API Input exposée story-002 Foundation). Vector `wish_dir_2d = Vector2(right-left, back-forward)` normalisé.
- Projeter sur plan XZ selon `transform.basis` du CharacterBody3D : `wish_dir_3d = (transform.basis * Vector3(wish_dir_2d.x, 0, wish_dir_2d.y)).normalized()` si `|wish_dir_2d| > 0.01`, sinon `Vector3.ZERO`.
- Si Grounded : `velocity.x = wish_dir_3d.x * MOVE_SPEED ; velocity.z = wish_dir_3d.z * MOVE_SPEED` ; si idle : `velocity.x = 0.0 ; velocity.z = 0.0`. Pas d'accélération/décélération.
- `MOVE_SPEED = 10.0` constante exportée dans `movement_tuning.tres` (ou placeholder hardcodée + TODO `@export var tuning: MovementTuning`).
- `move_and_slide()` appelé après toutes les mutations velocity du tick.
- Hors scope : gravité (Story 003), transitions state (Story 003+ pour Grounded→Airborne).

---

## Out of Scope

- Story 003 : gravité + Airborne transition + air control
- Story 004 : jump (jump input ignoré ici — mais WASD continue de fonctionner)
- Story 013 : lecture `can_*` flags (cette story ne gate rien)

---

## QA Test Cases

**AC-MV-01 — forward 1s distance** :
- Given : Player Grounded à `position=Vector3.ZERO`, `rotation.y=0` (forward = -Z)
- When : injection `InputEventAction("move_forward", pressed=true)` pendant 60 ticks physics
- Then : `abs(player.position.z - (-10.0)) < 0.3`
- Edge cases : vérifier sur 61 ticks pour assurer > 1s ; tolérance ±0.3 m couvre physique Jolt.

**AC-MV-02 — stop instantané** :
- Given : Player Grounded, `velocity.x = 10.0` (mouvement established)
- When : tick N+1, aucun input move
- Then : `velocity.x == 0.0 AND velocity.z == 0.0` (tick N+1 exactement, pas N+2)
- Edge cases : également tester `velocity.length_squared() < 0.001` tolérance float.

**AC-MV-03 — opposés simultanés** :
- Given : Player Grounded
- When : `move_left` ET `move_right` pressés simultanément
- Then : `velocity.x == 0.0 AND velocity.z == 0.0` (Input.get_vector retourne Vector2.ZERO ou équivalent)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/grounded_horizontal_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene + state enum + project settings)
- Unlocks: Story 003 (airborne hérite de la même lecture wish_dir)
