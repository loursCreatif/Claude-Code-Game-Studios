# Story 006: ShapeCast3D node config + collision layers

> **Epic**: Player Combat System
> **Status**: Done
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-012` (collision layer taxonomy 5-layer ratifié inline Rule 12)

**ADR Governing Implementation**: ADR-0008 (Collision Layer Taxonomy)
**ADR Decision Summary**: 5 layers (1=Player, 2=Enemy, 3=EnemyHitbox, 4=Environment, 5=Interactive). Katana ShapeCast `layer=1, mask=2`. API 1-indexée `set_collision_layer_value(N)` obligatoire. Helper `CollisionLayers.build_mask(Array[int])` pour PhysicsQueryParameters. `project.godot [layer_names]/3d_physics/layer_1..5` mandatory. Lint CI `lint-collision-layers` gate FAIL sur bitmask direct.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: API 1-indexée `set_collision_layer_value(layer: int, value: bool)` + `set_collision_mask_value(layer: int, value: bool)` stable Godot 4.0+. Confirmed valid Jolt 4.6.

**Control Manifest Rules (Feature layer)**:
- Required: API 1-indexée `set_collision_layer_value(N, true)` (ADR-0008 D-3)
- Forbidden: bitmask literal direct dans `src/**/*.gd` (`collision_layer = 0b00010` interdit) — lint CI `lint-collision-layers`
- Guardrail: `project.godot [layer_names]` doit nommer les 5 layers (ADR-0008 D-4)

---

## Acceptance Criteria

*From GDD AC-CMB-09 + ADR-0008 D-2/D-3/D-6 :*

- [ ] **AC-CMB-09** : `ShapeCast3D.collision_mask` configuré via API 1-indexée → bit 2 only (Enemy layer) ; `ShapeCast3D.collision_layer` → bit 1 only (Player layer)
- [ ] Configuration au `_ready()` :
  ```gdscript
  $ShapeCast3D.set_collision_layer_value(1, true)   # Player layer
  $ShapeCast3D.set_collision_mask_value(2, true)    # Enemy layer
  ```
- [ ] Aucune autre layer/mask bit set (vérification statique post-config)
- [ ] **Lint CI** : `lint-collision-layers` passe sur `src/gameplay/combat/combat_system.gd` (zéro bitmask direct)
- [ ] `project.godot` contient `[layer_names]/3d_physics/layer_1..5` (Player, Enemy, EnemyHitbox, Environment, Interactive)
- [ ] ShapeCast3D properties initialisées : `enabled = false` (default tant qu'on n'est pas en Swinging), `shape = CapsuleShape3D` (radius=0.45, height=1.8)
- [ ] `max_results` configuré pour permettre multi-hit (au moins `MAX_KILLS_PER_SWING + 2` pour buffer dedup)

---

## Implementation Notes

*Derived from ADR-0008 D-2/D-3 + GDD Section D Rule 12 :*

- Dans `combat_system.tscn`, configurer ShapeCast3D inline avec :
  - `enabled = false`
  - `shape = SubResource("CapsuleShape3D")` (radius=0.45, height=1.8 — constants `KATANA_RADIUS`, `KATANA_REACH`)
  - `max_results = 8` (≥ MAX_KILLS_PER_SWING + buffer)
- Dans `combat_system.gd._ready()`, force le set via API 1-indexée (override scene values pour cover ADR-0008 D-3 strict) :
  ```gdscript
  var sc := $ShapeCast3D as ShapeCast3D
  for i in range(1, 33):
      sc.set_collision_layer_value(i, false)
      sc.set_collision_mask_value(i, false)
  sc.set_collision_layer_value(1, true)   # Player
  sc.set_collision_mask_value(2, true)    # Enemy
  ```
- Updater `project.godot` (si pas déjà fait) avec `[layer_names]/3d_physics/layer_N=...`
- Si helper `CollisionLayers.build_mask()` existe (Sprint 0 follow-up), l'utiliser pour les PhysicsShapeQueryParameters3D dans story-010 (intersect_shape).

---

## Out of Scope

- Story 005 : `_build_capsule_basis()` (helper appelé pour orienter le ShapeCast — story-007)
- Story 007 : positionnement origin / target_position du ShapeCast
- Story 008-010 : sweep tick-par-tick + anti-tunneling

---

## QA Test Cases

- **AC-1** Layer bit set
  - Given: ShapeCast3D configuré au `_ready()`
  - When: `sc.get_collision_layer()` lu
  - Then: `sc.get_collision_layer_value(1) == true`, tous autres bits 2-32 == false
  - Edge cases: muter manuellement layer bit 4 → AC fail (vérifier post-config)

- **AC-2** Mask bit set
  - Given: ShapeCast3D configuré au `_ready()`
  - When: `sc.get_collision_mask_value(2) == true` ; tous autres == false
  - Then: ✅
  - Edge cases: bit 1 (Player) doit être false (Combat ne hit pas le Player lui-même)

- **AC-3** Lint collision-layers
  - Given: `src/gameplay/combat/combat_system.gd` complet
  - When: lint CI script `lint-collision-layers` exécute
  - Then: PASS, zéro forbidden_pattern `collision_layer_mask_bitmask_literal_in_src_gd`
  - Edge cases: commentaire `# layer 0b00010` toléré (commenté)

- **AC-4** Project settings layer_names
  - Given: `project.godot`
  - When: lecture sections
  - Then: `[layer_names]/3d_physics/layer_1 = "Player"` ... `layer_5 = "Interactive"` présents
  - Edge cases: noms exact case-sensitive (PascalCase)

- **AC-5** Shape config
  - Given: ShapeCast3D
  - When: `sc.shape is CapsuleShape3D`
  - Then: `shape.radius == 0.45 ± 0.001`, `shape.height == 1.8 ± 0.001`
  - Edge cases: muter shape runtime — autorisé pour story-009 substeps

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/shapecast_collision_layers_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene skeleton avec ShapeCast3D node), Sprint 0 collision_layers.gd helper (optionnel)
- Unlocks: Story 007 (positionnement), Story 010 (intersect_shape mitigation), Story 011 (kill resolution)
