# Story 019: OnboardingAnchors étage 1 + validate_onboarding_anchors + get_onboarding_anchors

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: 5h (OnboardingAnchors étage 1 authoring 0.5h + validate_onboarding_anchors lint 1.5h + get_onboarding_anchors API 0.5h + raycast LOS validation FirstEnemySightline 1h + 4 lint tests + 1 raycast integration test 1h + CI hook 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: — (r2 fix #5 couvert par AC-LVL-54, cross-GDD contract Combat CO-1/CO-2)

**ADR Governing Implementation**: — (cross-system authoring contract, GDD-owned r2)
**ADR Decision Summary** : N/A. Bridge Level ↔ Combat onboarding contract stage 1 : Level publie `FirstEnemySightline` + `SafeZoneCenter`, Combat System consume via `get_onboarding_anchors()` pour positionner premier enemy + safe zone défensive.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : Raycast line-of-sight via `PhysicsDirectSpaceState3D.intersect_ray(PhysicsRayQueryParameters3D)` pour validate `FirstEnemySightline` non obstrué. Collision mask raycast = LAYER_ENVIRONMENT (4).

---

## Acceptance Criteria

- [x] **AC-LVL-54** : Combat onboarding anchors (stage 1 r2 fix #5)
  - (a) `FirstEnemySightline` Marker3D présent ET raycast depuis `PlayerStart` salle 3 (ou salle COMBAT canonique) non obstrué par StaticBody3D avant atteinte marker (ligne-de-vue directe) ; distance ≤ 15 m
  - (b) `SafeZoneCenter` Marker3D présent ET distance ≥ 6 m de tout `EnemySlot_NN` de la salle ET distance ≥ 4 m de tout `HazardSlot_NN` de la salle
  - (c) pour étage ≠ 1 : absence `OnboardingAnchors` non-fatale (returns empty Dict)

---

## Implementation Notes

- Authoring : sub-tree `OnboardingAnchors` Node3D direct child du Level root (hors `SpawnMarkers` pour isolation sémantique stage 1)
  - `OnboardingAnchors/FirstEnemySightline` (Marker3D)
  - `OnboardingAnchors/SafeZoneCenter` (Marker3D)
- `get_onboarding_anchors() -> Dictionary` dans level.gd :
  ```gdscript
  func get_onboarding_anchors() -> Dictionary:
      var anchors := _current_scene_root.find_child("OnboardingAnchors", false, false)
      if anchors == null:
          return {}  # Stage != 1 ou tutorial absent, non-fatal
      var sightline := anchors.find_child("FirstEnemySightline", false, false) as Marker3D
      var safe := anchors.find_child("SafeZoneCenter", false, false) as Marker3D
      if sightline == null or safe == null:
          push_warning("OnboardingAnchors incomplete")
          return {}
      return {
          "first_enemy_sightline": sightline,
          "safe_zone_center": safe,
      }
  ```
- `validate_onboarding_anchors(root: Node3D, etage_id: int) -> Array[String]` dans `tools/lint/level_lint.gd` :
  ```gdscript
  static func validate_onboarding_anchors(root: Node3D, etage_id: int) -> Array[String]:
      var errors: Array[String] = []
      var anchors := root.find_child("OnboardingAnchors", false, false)
      if anchors == null:
          if etage_id == 1:
              errors.append("etage 1 requires OnboardingAnchors sub-tree")
          return errors  # etage != 1 → non-fatal
      var sightline := anchors.find_child("FirstEnemySightline", false, false) as Marker3D
      var safe := anchors.find_child("SafeZoneCenter", false, false) as Marker3D
      if sightline == null: errors.append("OnboardingAnchors missing FirstEnemySightline")
      if safe == null: errors.append("OnboardingAnchors missing SafeZoneCenter")
      if sightline != null:
          # Locate PlayerStart of COMBAT room 3 (canonical naming Room_03 if archetype COMBAT)
          var player_start := root.find_child("PlayerStart", true, false) as Marker3D  # stage PlayerStart
          if player_start != null:
              var dist := player_start.global_position.distance_to(sightline.global_position)
              if dist > 15.0:
                  errors.append("FirstEnemySightline distance %.2fm > 15m" % dist)
              # Raycast line-of-sight requires PhysicsDirectSpaceState3D — needs running scene
              # Lint pre-build fallback: approximate via AABB overlap check of static bodies between points (simplified)
              # Full runtime validation via integration test below
      if safe != null:
          var enemy_slots := root.find_children("EnemySlot_*", "Marker3D", true)
          for e in enemy_slots:
              var d := safe.global_position.distance_to(e.global_position)
              if d < 6.0:
                  errors.append("SafeZoneCenter distance %.2fm < 6m from %s" % [d, e.name])
          var hazards := root.find_children("HazardSlot_*", "Marker3D", true)
          for h in hazards:
              var d := safe.global_position.distance_to(h.global_position)
              if d < 4.0:
                  errors.append("SafeZoneCenter distance %.2fm < 4m from %s" % [d, h.name])
      return errors
  ```
- Raycast line-of-sight runtime check : intégré dans test integration (requires scene instantiated + physics state) plutôt que lint pre-build (pre-build est parse-only, pas de physics simulate)

---

## Out of Scope

- Story 009 : autres spatial lookups API
- Story 018 : secret split contract
- Combat epic : consume `get_onboarding_anchors()` pour spawn enemy + safe zone

---

## QA Test Cases

- **AC-LVL-54(a) presence** : Test `test_validate_onboarding_anchors_fails_missing_on_etage_1`
  - Setup : Fixture etage 1 sans `OnboardingAnchors` sub-tree
  - Verify : Violation `"etage 1 requires OnboardingAnchors sub-tree"`

- **AC-LVL-54(a) distance** : Test `test_first_enemy_sightline_distance_over_15m_fails`
  - Setup : PlayerStart at origin, FirstEnemySightline at (20, 0, 0)
  - Verify : Violation "distance 20.00m > 15m"

- **AC-LVL-54(a) line-of-sight runtime** : Test `test_first_enemy_sightline_obstructed_raycast_fails`
  - Given: Scene ACTIVE, PlayerStart at (0,1,0), FirstEnemySightline at (10, 1, 0), StaticBody3D wall at (5, 1, 0) entre les deux
  - When: Raycast depuis PlayerStart vers Sightline via `get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, end, 1 << 3))`
  - Then: Raycast hit non-empty = violation (obstruction détectée)
  - Edge cases: pas de wall = raycast clear = pass

- **AC-LVL-54(b) enemy distance** : Test `test_safe_zone_too_close_to_enemy_slot_fails`
  - Setup : SafeZoneCenter at (0,0,0), EnemySlot_01 at (5, 0, 0) (distance 5 < 6)
  - Verify : Violation "distance 5.00m < 6m from EnemySlot_01"

- **AC-LVL-54(b) hazard distance** : Test `test_safe_zone_too_close_to_hazard_fails`
  - Setup : SafeZone at origin, HazardSlot_01 at (3.5, 0, 0) (distance 3.5 < 4)
  - Verify : Violation "< 4m from HazardSlot_01"

- **AC-LVL-54(c)** : Test `test_onboarding_absent_on_etage_non_1_passes`
  - Setup : etage 2 fixture sans OnboardingAnchors
  - Verify : `validate_onboarding_anchors(root, 2)` retourne `[]`

- **get_onboarding_anchors** : Test `test_get_onboarding_anchors_returns_dict_on_etage_1`
  - Given: etage 1 ACTIVE avec OnboardingAnchors complet
  - When: `level.get_onboarding_anchors()`
  - Then: Dictionary avec keys "first_enemy_sightline" + "safe_zone_center" pointant sur Marker3D nodes

- **get_onboarding_anchors stage 2** : Test `test_get_onboarding_anchors_returns_empty_dict_etage_2`
  - Given: etage 2 ACTIVE sans OnboardingAnchors
  - When: `level.get_onboarding_anchors()`
  - Then: `{}` vide

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- `tests/unit/lint/onboarding_anchors_lint_test.gd` — 4 lint test cases
- `tests/integration/level/level_onboarding_raycast_test.gd` — 1 runtime raycast test
- `tests/unit/level/level_get_onboarding_test.gd` — 2 API tests

**Status**: [x] Created and committed — see Completion Notes below.

---

## Completion Notes

**Completed** : 2026-04-27 (solo auto-approve)
**Criteria** : AC-LVL-54 (a/b/c) ✓ — lint validator + runtime API + raycast integration test.

**Files modifiés** :
- `tools/lint/level_lint.gd` (889 → 1127 l, +238 l ; +76 l net pour cette story) — `static func validate_onboarding_anchors(root, etage_id)` ligne 1078 + header doc updated avec TR-019/AC-LVL-54.
- `src/gameplay/level/level_system.gd` (815 → 848 l, +33 l) — `func get_onboarding_anchors() -> Dictionary` ligne 833 (mirroir get_secret_slots()).
- `tools/lint/run_level_lint.gd` (+23 l) — appel `validate_onboarding_anchors(root_3d, etage_id)` ligne 133 + helper privé `_extract_etage_id_from_path(path: String) -> int` (parse NN du nom, fallback 1).

**Files créés** :
- `tests/unit/lint/onboarding_anchors_lint_test.gd` (216 l, 5 tests : missing on etage 1 / sightline distance >15m / safe_zone <6m enemy / safe_zone <4m hazard / etage ≠ 1 returns empty).
- `tests/unit/level/level_get_onboarding_test.gd` (159 l, 2 tests : full dict on etage 1 / empty {} on etage 2). Pattern `_set_current_scene_root_for_test` story-018.
- `tests/integration/level/level_onboarding_raycast_test.gd` (142 l, 1 test : `test_first_enemy_sightline_obstructed_raycast_fails` PhysicsDirectSpaceState3D.intersect_ray + 2× `await get_tree().physics_frame` + `CollisionLayers.build_mask([LAYER_ENVIRONMENT])`).

**CI** : aucun changement requis — `lint-level-invariants` job (`.github/workflows/tests.yml:251`) exécute `run_level_lint.gd` qui appelle désormais `validate_onboarding_anchors` (couverture transitive).

**Mapping ACs → livrables** :
- AC-LVL-54(a) presence + distance → `validate_onboarding_anchors` checks "etage 1 requires OnboardingAnchors" + "FirstEnemySightline distance %.2fm > 15m" + tests `*_fails_missing_on_etage_1` + `*_distance_over_15m_fails`.
- AC-LVL-54(a) line-of-sight runtime → integration test `test_first_enemy_sightline_obstructed_raycast_fails`.
- AC-LVL-54(b) enemy/hazard distance → `validate_onboarding_anchors` checks ≥6m enemy + ≥4m hazard + 2 lint tests.
- AC-LVL-54(c) etage ≠ 1 non-fatal → check inline `if etage_id == 1 → error else return []` + test `*_etage_non_1_passes` + API test `*_returns_empty_dict_etage_2`.

**Déviation documentée** :
- DEV-1 : Le test d'intégration utilise `CollisionLayers.build_mask([LAYER_ENVIRONMENT])` au lieu de `1 << 3` literal mentionné en spec (ligne 113). Conforme ADR-0008 D-3 + rule `collision-layer-api-1-indexed.md` (visible dans `level_validate_checkpoint_anchors_test.gd`). Bitmask identique.

**Conformité** :
- Static typing 100% ✓
- Doc-comments `##` extensifs ✓
- Naming snake_case/PascalCase/UPPER_SNAKE_CASE ✓
- ADR-0005 D-10 (API publique read-only) ✓
- ADR-0008 D-3 (CollisionLayers.build_mask) ✓
- Pattern miroir `get_secret_slots()` (story-018) ✓

**Solo gates** : QL-TEST-COVERAGE skipped + LP-CODE-REVIEW skipped (Solo mode).

**Sprint impact** : 20ème story Level System Complete. Débloque Combat epic onboarding consumer étage 1 (CO-1/CO-2 cross-GDD contract).

---

## Dependencies

- Depends on: **Story 010** (hiérarchie Level root), **Story 011** (archetype COMBAT pour salle 3), **Story 013** (LAYER_ENVIRONMENT pour raycast)
- Unlocks: Combat epic (onboarding consumer étage 1)
