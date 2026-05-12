# Story 002: Grunt scene + collision layers + LaserCone Area3D + lethal handler

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic + Integration
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27
**ADRs Governing**: ADR-0006 Combat Tick Model, ADR-0008 Collision Layer Taxonomy
**Depends on**: story-001 (Grunt class + state machine + die())

**Scope** : Scène canonique `res://src/gameplay/enemy/Grunt.tscn` (Rule 3 hierarchy),
collision layers via `CollisionLayers` API 1-idx (Rule 4 + ADR-0008 D-6 lint compliant),
LaserCone Area3D `body_entered` handler câblé en `_ready()` (Rule 8) avec state guard
`_state != ALIVE` (Rule 11.b — DYING/DEAD ne tue plus), orthonormalization
`%FacingPivot.global_basis` (EC-ENM-6).

**Engine**: Godot 4.6 | **Risk**: LOW (logic + scene assembly — patterns établis par
Combat/Player.tscn, helper `CollisionLayers` éprouvé sur 5 systèmes existants)

**Control Manifest Rules (Core layer)** :
- Required : `CollisionLayers.LAYER_*` constants only (forbidden bitmask littéraux),
  `set_collision_layer_value`/`set_collision_mask_value` API 1-idx, `unique_name_in_owner`
  pour `%FacingPivot` + `%LaserCone`.
- Forbidden : `body.collision_layer = 0b00010` direct, accès `MovementController`
  cross-system depuis grunt.gd (utiliser group `"player"` + `has_method("die")`).
- Guardrail : LaserCone `monitoring=false` IMMÉDIATEMENT à transition ALIVE → DYING
  (Rule 11.b — pas en attente du tween 150 ms).

---

## Acceptance Criteria

- [x] **AC-ENM-04 [Logic]** : GIVEN un Grunt en `state == ALIVE`, WHEN un body entre dans
      le `LaserCone.body_entered` Area3D ET `body.is_in_group("player")`, THEN
      `body.die()` est appelé exactement 1 fois.
- [x] **AC-ENM-05 [Logic]** : GIVEN un Grunt en `state == DYING`, WHEN un body entre dans
      le `LaserCone.body_entered` Area3D, THEN `body.die()` n'est **pas** appelé
      (handler retourne via guard `_state != ALIVE`).
- [x] **AC-ENM-06 [Logic]** : GIVEN un Grunt instancié, WHEN inspect des collision layers,
      THEN `Grunt.collision_layer == 0b00000010` (LAYER_ENEMY=2) ET
      `Grunt.collision_mask == 0b00001000` (LAYER_ENVIRONMENT=4) ET
      `LaserCone.collision_layer == 0b00000100` (LAYER_ENEMY_HITBOX=3) ET
      `LaserCone.collision_mask == 0b00000001` (LAYER_PLAYER=1) ET
      `LaserCone.monitoring == true`.
- [x] **AC-ENM-07c [Logic]** : GIVEN un `EnemySlot_01` créé avec
      `basis = Basis.IDENTITY.scaled(Vector3(2, 1, 1))` (non-uniform scale), WHEN spawn,
      THEN `Grunt.%FacingPivot.global_basis.is_normalized() == true` (cône non-déformé).

**Bonus ACs covered** :
- **Rule 11.b** : LaserCone monitoring=false IMMÉDIATEMENT à DYING (avant fin tween).
- **EC-ENM-4** : grunt DEAD body_entered → handler skip.
- **EC-ENM-5** : 2 grunts overlap → 2× Player.die() (idempotence Movement-side).
- **Anti-friendly-fire** : body sans group "player" → handler ignore silencieusement.

---

## Implementation Notes

**Files** (NEW) :
- `src/gameplay/enemy/Grunt.tscn` — canonical scene Rule 3 :
  - `Grunt: CharacterBody3D` (groups=["enemy"]) avec script grunt.gd
  - `CollisionShape3D` (CapsuleShape3D 0.35×1.8) à y=0.9 (capsule sol-plafond)
  - `MeshInstance3D` (CapsuleMesh + StandardMaterial3D gris foncé)
  - `%FacingPivot: Node3D` (unique_name_in_owner)
  - `FacingPivot/%LaserCone: Area3D` (unique_name_in_owner, monitorable=false, position Z=-3 devant le grunt)
  - `LaserCone/CollisionShape3D` (BoxShape3D 0.5×0.3×6)
  - `LaserCone/MeshInstance3D` (QuadMesh + StandardMaterial3D rouge fluo emission_energy=3.0)

**Files** (MODIFIED) :
- `src/gameplay/enemy/grunt.gd` :
  - `_ready()` : ajout `_set_layers_safe(self, [LAYER_ENEMY], [LAYER_ENVIRONMENT])` body
    + orthonormalize `%FacingPivot.global_basis` (EC-ENM-6)
    + `_set_layers_safe(cone, [LAYER_ENEMY_HITBOX], [LAYER_PLAYER])` LaserCone
    + `cone.monitoring = true`
    + connect `body_entered` → `_on_laser_cone_body_entered`.
  - `die()` : ajout `cone.monitoring = false` IMMÉDIATEMENT à DYING (Rule 11.b).
  - Helper `_set_layers_safe(node, layers, masks)` : force-clear bits 1-32 puis set demandés
    (analogue à pattern combat_system.gd `_init_collision_layers_strict`).
  - Handler `_on_laser_cone_body_entered(body: Node3D)` : guard `_state != ALIVE` +
    `body.is_in_group("player")` + `body.has_method("die")` → `body.die()`.

**Files** (NEW tests) :
- `tests/unit/enemy/grunt_collision_layers_test.gd` — 6 tests AC-ENM-06 + Rule 11.b bonus.
- `tests/unit/enemy/grunt_laser_handler_test.gd` — 5 tests AC-ENM-04/05 + 3 bonus.
- `tests/unit/enemy/grunt_orthonormalization_test.gd` — 2 tests AC-ENM-07c + IDENTITY bonus.

---

## Test Plan

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-04 | `grunt_laser_handler_test.gd` | `test_laser_handler_calls_player_die_when_alive` | ✅ PASS |
| AC-ENM-05 | `grunt_laser_handler_test.gd` | `test_laser_handler_skips_when_dying` | ✅ PASS |
| AC-ENM-06 (body layer) | `grunt_collision_layers_test.gd` | `test_grunt_body_layer_is_layer_enemy_only` | ✅ PASS |
| AC-ENM-06 (body mask) | `grunt_collision_layers_test.gd` | `test_grunt_body_mask_is_layer_environment_only` | ✅ PASS |
| AC-ENM-06 (cone layer) | `grunt_collision_layers_test.gd` | `test_laser_cone_layer_is_layer_enemy_hitbox_only` | ✅ PASS |
| AC-ENM-06 (cone mask) | `grunt_collision_layers_test.gd` | `test_laser_cone_mask_is_layer_player_only` | ✅ PASS |
| AC-ENM-06 (monitoring) | `grunt_collision_layers_test.gd` | `test_laser_cone_monitoring_enabled_at_ready` | ✅ PASS |
| Rule 11.b | `grunt_collision_layers_test.gd` | `test_laser_cone_monitoring_disabled_at_dying` | ✅ PASS |
| EC-ENM-4 | `grunt_laser_handler_test.gd` | `test_laser_handler_skips_when_dead` | ✅ PASS |
| Anti-FF | `grunt_laser_handler_test.gd` | `test_laser_handler_ignores_non_player_body` | ✅ PASS |
| EC-ENM-5 | `grunt_laser_handler_test.gd` | `test_two_grunts_overlap_call_player_die_independently` | ✅ PASS |
| AC-ENM-07c | `grunt_orthonormalization_test.gd` | `test_facing_pivot_orthonormalized_when_spawn_basis_non_uniform` | ✅ PASS |
| AC-ENM-07c (IDENTITY) | `grunt_orthonormalization_test.gd` | `test_facing_pivot_identity_basis_unchanged` | ✅ PASS |

**Test report** : `reports/report_237/index.html` — 24/24 PASSED (story-001 + story-002 combined), 0 errors, 909 ms.

---

## Definition of Done

- [x] All 4 ACs (AC-ENM-04/05/06/07c) PASS in automated tests.
- [x] Bonus tests (Rule 11.b, EC-ENM-4, EC-ENM-5, anti-FF) PASS.
- [x] Zero regression on story-001 (11/11 still PASS).
- [x] Lint clean : pas de bitmask littéral dans grunt.gd ni Grunt.tscn (API 1-idx only via CollisionLayers helper).
- [x] Status switched `Ready` → `Complete` (auto-mode solo, /code-review skipped).

---

## Completion Notes

- **API 1-idx compliant** : `_set_layers_safe()` force-clear bits 1-32 puis set explicitement les layers/masks. Robuste contre les rémanences éditeur (`.tscn` aurait pu set des bits via UI).
- **Group "player" decoupling** : handler n'importe pas `MovementController` — utilise `is_in_group("player")` + `has_method("die")`. Aligné Combat Rule 14 (Enemy assume la responsabilité d'appeler `Player.die()`, pas Combat).
- **MockPlayer pattern** : tests laser_handler utilisent `class MockPlayer extends CharacterBody3D` inline avec `die_call_count: int` — évite dépendance scène Player complète.
- **Orthonormalization timing** : `_ready()` fait `pivot.global_basis = pivot.global_basis.orthonormalized()`. Cela requiert que le pivot soit dans la scene tree (sinon `global_basis` retombe sur local). Test `add_child → await process_frame` garantit cet état.
- **LaserCone position** : centre du box à mi-portée Z=-3 devant le grunt. `monitorable=false` pour économiser physics (LaserCone détecte le Player, pas l'inverse — Player n'a pas besoin de "voir" le LaserCone via raycast).

## Next Stories

- **story-003** : LevelSystem `_on_level_active` itère `EnemySlot_*` Marker3D + spawn `Grunt.tscn` à chaque slot avec `EnemySlot.global_basis` orientation + archetype meta fallback warning. Bloquait sur scene canonical (résolu par story-002). ACs : AC-ENM-08/09/10.
