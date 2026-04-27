# Story 013: Layers 4+5 discipline + validate_collision_layers + wall thickness ≥ 0.3m

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: 4h (validate_collision_layers 1.5h + validate_wall_thickness 1h + validate_level_shapes 0.5h + 9 tests GdUnit4 1h)
> **Performance Note**: Aucun impact runtime — lint authoring-time uniquement, exécuté en CI build-time (`tools/lint/run_level_lint.gd`) et en éditeur via `validate_scene()`. Coût négligeable : parcours hiérarchie scene tree O(N) avec N = noeuds StaticEnvironment + InteractiveVolumes (typiquement < 200 noeuds par étage).

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-007`, `TR-lvl-008`, `TR-lvl-019`

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt), **ADR-0008 (Collision Layer Taxonomy & Mask Canonicalization, Accepted 2026-04-23 r4)**
**ADR Decision Summary** :
- ADR-0001 fixe Jolt default 4.6 (physique 60 Hz Area3D `body_entered`/`body_exited`).
- **ADR-0008 D-1** ratifie la taxonomie 5-layer canonique : 1=Player, 2=Enemy, 3=EnemyHitbox, 4=Environment, 5=Interactive (ferme Gap G-5).
- **ADR-0008 D-2** définit les archetypes : Static environment `layer=4, mask=0` ; Interactive trigger `layer=5, mask⊃LAYER_PLAYER, monitoring=true, monitorable=false` — exactement ce que validate_collision_layers gate.
- **ADR-0008 D-3** rend l'API 1-indexée (`set_collision_layer_value(N)` / `get_collision_mask_value(N)`) obligatoire ; bitmask littéraux interdits (lint `lint-collision-layers` CI déjà en place).
- **ADR-0008 D-4** : `project.godot [layer_names]/3d_physics/layer_1..5` synchronisés avec `src/core/collision_layers.gd` (autoload-class `CollisionLayers`).
- Wall thickness ≥ 0.3 m (TR-lvl-019, ADR-0001) nécessaire pour Jolt CCD fiabilité (EC-8 CLAIM-UNVERIFIED, benchmark story 014).

**Engine**: Godot 4.6 | **Risk**: LOW (API 1-idx stable Godot 4.0+, Jolt 4.6 = 0 divergence — ADR-0008 Engine Compatibility section)
**Engine Notes** : Utiliser API 1-indexée `set_collision_layer_value(N, true)` et `set_collision_mask_value(N, true)` — **NON** bitmask manuel (ADR-0008 D-3 + `.claude/rules/collision-layer-api-1-indexed.md`). Constantes : référencer **`CollisionLayers.LAYER_PLAYER`** / **`CollisionLayers.LAYER_ENVIRONMENT`** / **`CollisionLayers.LAYER_INTERACTIVE`** depuis `src/core/collision_layers.gd` (helper canonique ADR-0008 D-1) — ne PAS redéfinir localement. `BoxShape3D.size` Vector3 = size x/y/z (full extent). WorldBoundsVolume BoxShape3D obligatoire (pas ConcavePolygonShape3D).

**Control Manifest Rules (Core Layer)** : layers authoring discipline ; Movement consume Layer 4 pour walk/wall-run ; Level Area3D Layer 5 signal-only (monitorable=false).

---

## Acceptance Criteria

- [ ] **AC-LVL-12** : Layer 4 exclusive for static geometry — tous `StaticBody3D` sous `StaticEnvironment` ont `get_collision_layer_value(4) == true` ET `collision_mask == 0` (API `set_collision_layer_value(4, true)` pas bitmask)
- [ ] **AC-LVL-13** : Layer 5 exclusive for interactive triggers — tous `Area3D` sous `InteractiveVolumes` ont `collision_layer_value(5) == true` ET `monitorable == false` ET `monitoring == true` ET `collision_mask ⊃ LAYER_PLAYER` (Layer 1)
- [ ] **AC-LVL-17** : Minimal wall thickness (EC-8) — chaque `BoxShape3D` wall a `min(size.x, size.z) ≥ 0.3 m` sur axe "thickness" (axe perpendiculaire à la face wall-runnable)

---

## Implementation Notes

- **Constantes** : référencer le helper canonique `CollisionLayers` depuis `src/core/collision_layers.gd` (ADR-0008 D-1). Aucune redéfinition locale dans `level.gd`. Le contract test `tests/unit/collision/layer_mask_contract_test.gd` (Sprint 0 commit fa148c4) garantit déjà que les valeurs `CollisionLayers.LAYER_*` matchent `project.godot [layer_names]`.
- Ajouter `validate_collision_layers(root: Node3D) -> Array[String]` dans `tools/lint/level_lint.gd` (à intégrer au runner `tools/lint/run_level_lint.gd` après `validate_room_archetype_invariants`) :
  ```gdscript
  static func validate_collision_layers(root: Node3D) -> Array[String]:
      var errors: Array[String] = []
      var static_env: Node = root.find_child("StaticEnvironment", false, false)
      if static_env != null:
          for sb: StaticBody3D in static_env.find_children("*", "StaticBody3D", true, false):
              if not sb.get_collision_layer_value(CollisionLayers.LAYER_ENVIRONMENT):
                  errors.append("%s missing layer %d (LAYER_ENVIRONMENT)" % [sb.get_path(), CollisionLayers.LAYER_ENVIRONMENT])
              if sb.collision_mask != 0:
                  errors.append("%s collision_mask must be 0, got %d" % [sb.get_path(), sb.collision_mask])
      var vol: Node = root.find_child("InteractiveVolumes", false, false)
      if vol != null:
          for a: Area3D in vol.find_children("*", "Area3D", true, false):
              if not a.get_collision_layer_value(CollisionLayers.LAYER_INTERACTIVE):
                  errors.append("%s missing layer %d (LAYER_INTERACTIVE)" % [a.get_path(), CollisionLayers.LAYER_INTERACTIVE])
              if a.monitorable:
                  errors.append("%s monitorable must be false" % a.get_path())
              if not a.monitoring:
                  errors.append("%s monitoring must be true" % a.get_path())
              if not a.get_collision_mask_value(CollisionLayers.LAYER_PLAYER):
                  errors.append("%s collision_mask must include LAYER_PLAYER (%d)" % [a.get_path(), CollisionLayers.LAYER_PLAYER])
      return errors
  ```
- Ajouter `validate_wall_thickness(root: Node3D) -> Array[String]` :
  - Scan tous `StaticBody3D` avec `BoxShape3D`, check `min(shape.size.x, shape.size.z) >= 0.3`
  - Violation message : `"%s BoxShape3D thickness %.2fm < 0.3m (EC-8)" % [path, thickness]`
- Ajouter `validate_level_shapes(root: Node3D) -> Array[String]` :
  - Check `WorldBoundsVolume` utilise `BoxShape3D` exclusivement (jamais `ConcavePolygonShape3D` ou trimesh)
  - Violation : `"WorldBoundsVolume must use BoxShape3D, got <class>"`

---

## Out of Scope

- Story 014 : wall-run surface height/length lint + EC-8 Jolt CCD benchmark
- Story 008 : WorldBoundsVolume runtime behaviour player_out_of_world
- Combat Layer 1/2/3 (owned par Combat epic)

---

## QA Test Cases

- **AC-LVL-12 pass** : Test `test_static_body_on_layer_4_with_zero_mask`
  - Setup : Fixture StaticBody3D avec `set_collision_layer_value(4, true)` + `collision_mask = 0`
  - Verify : `validate_collision_layers(root)` retourne `[]`

- **AC-LVL-12 fail** : Test `test_static_body_missing_layer_4_flagged`
  - Setup : StaticBody3D sur Layer 1 (default)
  - Verify : Violation `"... missing layer 4 (LAYER_ENVIRONMENT)"`

- **AC-LVL-12 fail mask** : Test `test_static_body_with_nonzero_mask_flagged`
  - Setup : StaticBody3D Layer 4 mais `collision_mask = 7`
  - Verify : Violation `"collision_mask must be 0, got 7"`

- **AC-LVL-13 Area3D pass** : Test `test_interactive_area_layer_5_monitoring_correct`
  - Setup : Area3D Layer 5, monitorable=false, monitoring=true, mask includes layer 1
  - Verify : `[]`

- **AC-LVL-13 fails** : 4 tests individuels (missing layer 5 / monitorable=true / monitoring=false / mask missing LAYER_PLAYER) — chaque violation capturée

- **AC-LVL-17 pass** : Test `test_wall_thickness_0_3m_passes`
  - Setup : BoxShape3D `size = Vector3(3, 4, 0.3)` → thickness axis = z = 0.3
  - Verify : `validate_wall_thickness(root)` retourne `[]`

- **AC-LVL-17 fail** : Test `test_wall_thickness_below_0_3m_flagged`
  - Setup : BoxShape3D `size = Vector3(3, 4, 0.25)` → thickness = 0.25
  - Verify : Violation `"... thickness 0.25m < 0.3m (EC-8)"`

- validate_level_shapes : Test `test_world_bounds_volume_requires_box_shape`
  - Setup : WorldBoundsVolume avec ConcavePolygonShape3D
  - Verify : Violation

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `tests/unit/lint/collision_layers_lint_test.gd` — ~10 test cases ; CI job `lint-level-invariants` étendu pour exécuter `validate_collision_layers` + `validate_wall_thickness` + `validate_level_shapes` sur toutes les scènes `res://scenes/levels/etage_*.tscn`

**Status**: [ ] To be created during implementation at `tests/unit/lint/collision_layers_lint_test.gd`

---

## Dependencies

- Depends on: **Story 010** (hiérarchie StaticEnvironment + InteractiveVolumes)
- Unlocks: Story 005 (EtageExitTrigger layer 5), Story 007 (RoomTrigger layer 5), Story 008 (WorldBoundsVolume BoxShape3D), Story 014 (wall-run surface)

---

## Completion Notes

**Completed** : 2026-04-27
**Criteria** : 3/3 passing (AC-LVL-12 ✓, AC-LVL-13 ✓, AC-LVL-17 ✓)
**Deviations** : None — implémentation conforme pseudocode story, API 1-indexée ADR-0008 D-3 respectée, constantes `CollisionLayers.LAYER_*` référencées via preload (ADR-0008 D-1, pas de redéfinition locale).
**Test Evidence** :
- Unit tests : `tests/unit/lint/collision_layers_lint_test.gd` (523 lignes, 11 fonctions test GdUnit4 couvrant les 9 cas spec + 2 edge cases pour `validate_level_shapes`).
- CI gate : job `lint-level-invariants` (`.github/workflows/tests.yml:233-255`) exécute `run_level_lint.gd` qui appelle `validate_collision_layers` + `validate_wall_thickness` + `validate_level_shapes` sur toutes les scènes `res://scenes/levels/etage_*.tscn`.
**Implementation files** :
- `tools/lint/level_lint.gd` (425 → 560 lignes, +135) : 3 méthodes statiques publiques `validate_collision_layers()` l.449, `validate_wall_thickness()` l.507, `validate_level_shapes()` l.546 + preload `CollisionLayersScript` l.77.
- `tools/lint/run_level_lint.gd` : 3 appels supplémentaires intégrés au pipeline `_validate_scene()` après `validate_room_archetype_invariants`.
- `tests/unit/lint/collision_layers_lint_test.gd` (créé) : 11 fonctions test `extends GdUnitTestSuite`, fixtures programmatiques (pas de `.tscn`), naming `test_[scenario]_[expected_result]`, structure Arrange/Act/Assert.
**Verification** : `godot --headless --check-only` exit 0 sur les deux fichiers `.gd` ; runner `godot --headless --script tools/lint/run_level_lint.gd` exit 0 (pas encore de `etage_*.tscn` → PASS attendu, sera gate effective dès première scène d'étage authored).
**Code Review** : Skipped (Solo mode — gate LP-CODE-REVIEW non applicable).
**QA Coverage** : Skipped (Solo mode — gate QL-TEST-COVERAGE non applicable).
**Tech debt logged** : aucun.
**Out-of-scope respecté** : aucune modification à `level_system.gd`, story-014 (wall-run surface lint), story-008 (WorldBoundsVolume runtime), Combat layers 1/2/3.
