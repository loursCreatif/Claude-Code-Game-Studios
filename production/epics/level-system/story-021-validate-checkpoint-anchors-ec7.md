# Story 021: validate_checkpoint_anchors (EC-7) + CheckpointVolume↔Anchor pair coherence

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 4h (validate_checkpoint_anchors lint 1.5h + CheckpointVolume↔Anchor pair coherence check 1h + 4 lint tests + 2 runtime tests (physics space state) 1h + CI hook 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-020`, `TR-lvl-038`

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt — raycast space state)
**ADR Decision Summary** : ADR-0001 requires physics simulation running to query `PhysicsDirectSpaceState3D.intersect_ray()`. Validation runtime (pas lint pre-build) pour raycast check. Checkpoint System (epic futur) consume `validate_checkpoint_anchors()` pour safe respawn.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `get_world_3d().direct_space_state` accessible quand scene est dans tree et physics server running. `PhysicsRayQueryParameters3D.create(from, to, collision_mask)` stable 4.0-4.6.

---

## Acceptance Criteria

- [x] **AC-LVL-19** : Checkpoint tuple coherence (R-5.2) — chaque `CheckpointVolume_NN` a paired `CheckpointAnchor_NN` avec même index ; distance ≤ 10 m
- [x] **AC-LVL-40** : `validate_checkpoint_anchors` catches bad authoring (EC-7) — `validate_checkpoint_anchors()` sur anchor dans wall → retourne array non-vide avec `{anchor_name, position, reason: "inside_static_body"}`

---

## Implementation Notes

- 2 validations distinctes :
  1. **Lint pre-build pairing** : `validate_checkpoint_pairs(root) -> Array[String]` (parse-only, aligne avec lint suite story 010/020)
  2. **Runtime validation** : `Level.validate_checkpoint_anchors() -> Array[Dictionary]` (physics space state check)

### Lint Pre-Build Pairing

```gdscript
static func validate_checkpoint_pairs(root: Node3D) -> Array[String]:
    var errors: Array[String] = []
    var volumes := root.find_children("CheckpointVolume_*", "Area3D", true)
    var anchors := root.find_children("CheckpointAnchor_*", "Marker3D", true)
    var volume_indices := {}
    for v in volumes:
        var idx := v.name.trim_prefix("CheckpointVolume_")
        volume_indices[idx] = v
    var anchor_indices := {}
    for a in anchors:
        var idx := a.name.trim_prefix("CheckpointAnchor_")
        anchor_indices[idx] = a
    for idx in volume_indices:
        if not anchor_indices.has(idx):
            errors.append("CheckpointVolume_%s missing paired CheckpointAnchor_%s" % [idx, idx])
        else:
            var d := volume_indices[idx].global_position.distance_to(anchor_indices[idx].global_position)
            if d > 10.0:
                errors.append("CheckpointVolume_%s ↔ CheckpointAnchor_%s distance %.2fm > 10m" % [idx, idx, d])
    for idx in anchor_indices:
        if not volume_indices.has(idx):
            errors.append("CheckpointAnchor_%s orphan (no CheckpointVolume_%s)" % [idx, idx])
    return errors
```

### Runtime Validation (Level API)

```gdscript
func validate_checkpoint_anchors() -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    if _current_scene_root == null:
        push_warning("validate_checkpoint_anchors called before level_active")
        return results
    var anchors := _current_scene_root.find_children("CheckpointAnchor_*", "Marker3D", true)
    var space := get_world_3d().direct_space_state
    for anchor in anchors:
        var pos := anchor.global_position
        # Cast small shape at anchor position vs LAYER_ENVIRONMENT = 4
        var query := PhysicsShapeQueryParameters3D.new()
        var shape := SphereShape3D.new()
        shape.radius = 0.3  # match player capsule radius approximate
        query.shape = shape
        query.transform = Transform3D(Basis(), pos)
        query.collision_mask = 1 << 3  # LAYER_ENVIRONMENT (4th bit, 0-indexed)
        var collisions := space.intersect_shape(query, 1)
        if not collisions.is_empty():
            results.append({
                "anchor_name": anchor.name,
                "position": pos,
                "reason": "inside_static_body",
            })
    return results
```

- Runtime API exposée pour Checkpoint System (futur) + debug tool. Pas gated en CI (playtest debug utility)

---

## Out of Scope

- Story 020 : checkpoint count F3 + spacing AC-LVL-51 (lint count, distinct de paired anchors)
- Checkpoint System epic : consume `validate_checkpoint_anchors()` + spawn respawn logic

---

## QA Test Cases

- **AC-LVL-19 pair OK** : Test `test_checkpoint_pair_within_10m_passes`
  - Setup : CheckpointVolume_01 at (0,0,0), CheckpointAnchor_01 at (5, 0, 0) (distance 5 ≤ 10)
  - Verify : `validate_checkpoint_pairs(root)` retourne `[]`

- **AC-LVL-19 missing pair** : Test `test_checkpoint_volume_without_anchor_flagged`
  - Setup : CheckpointVolume_01 sans CheckpointAnchor_01
  - Verify : Violation "CheckpointVolume_01 missing paired CheckpointAnchor_01"

- **AC-LVL-19 orphan** : Test `test_checkpoint_anchor_without_volume_flagged`
  - Setup : CheckpointAnchor_01 sans CheckpointVolume_01
  - Verify : Violation "CheckpointAnchor_01 orphan"

- **AC-LVL-19 distance** : Test `test_checkpoint_pair_distance_over_10m_flagged`
  - Setup : Volume at (0,0,0), Anchor at (15, 0, 0) (distance 15 > 10)
  - Verify : Violation "distance 15.00m > 10m"

- **AC-LVL-40** : Test `test_validate_checkpoint_anchors_detects_anchor_inside_wall`
  - Given: Level ACTIVE avec CheckpointAnchor_01 at (5, 0, 0) ET StaticBody3D BoxShape3D centré (5, 0, 0) size (2, 4, 2) → anchor enclosed in wall
  - When: `level.validate_checkpoint_anchors()`
  - Then: Array length ≥ 1 contenant `{anchor_name: "CheckpointAnchor_01", position: Vector3(5,0,0), reason: "inside_static_body"}`

- **AC-LVL-40 clear** : Test `test_validate_checkpoint_anchors_empty_when_all_clear`
  - Given: Tous anchors en espace ouvert (pas de StaticBody3D proche)
  - When: `level.validate_checkpoint_anchors()`
  - Then: `[]` (pas de violations)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/lint/checkpoint_pairs_lint_test.gd` — 4 lint tests
- `tests/integration/level/level_validate_checkpoint_anchors_test.gd` — 2 runtime tests (requires physics space state)

**Status**: [ ] To be created during implementation per Required evidence paths listed above

---

## Dependencies

- Depends on: **Story 002** (ACTIVE state pour runtime check — ADR-0007 Accepted), **Story 010** (hiérarchie), **Story 013** (LAYER_ENVIRONMENT)
- Unlocks: Checkpoint System epic (runtime validation API)

---

## Completion Notes

**Completed** : 2026-04-27
**Criteria** : 2/2 passing (AC-LVL-19 + AC-LVL-40)
**Mode** : Solo (QL-TEST-COVERAGE + LP-CODE-REVIEW skipped per `production/review-mode.txt`)

**Implementation files** :
- `tools/lint/level_lint.gd` (+71 lignes) — `validate_checkpoint_pairs` static + constante `MAX_CHECKPOINT_PAIR_DISTANCE_M = 10.0`.
- `tools/lint/run_level_lint.gd` (+4 lignes) — chaînage `validate_checkpoint_pairs` après `validate_static_body_count_per_room` + doc-comment update.
- `src/gameplay/level/level_system.gd` (+72 lignes) — `validate_checkpoint_anchors` runtime API + `_set_current_scene_root_for_test` test seam.

**Test files** :
- `tests/unit/lint/checkpoint_pairs_lint_test.gd` (189 lignes, 4 tests GdUnit4) — pair OK, missing anchor, orphan anchor, distance > 10m.
- `tests/integration/level/level_validate_checkpoint_anchors_test.gd` (185 lignes, 2 tests GdUnit4) — anchor inside wall, all clear.

**Deviations** :
- **ADR-0008 D-3 (correction positive)** : story example proposait `query.collision_mask = 1 << 3` (bitmask littéral interdit par rule `.claude/rules/collision-layer-api-1-indexed.md`). Implémentation utilise `CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])` avec commentaire explicatif. Conforme.
- **Manifest version** : story v2026-04-23 = current control-manifest v2026-04-23 → no staleness.
- **Scope** : strictement les 5 fichiers listés dans le story.

**Code Review** : Complete — verdict APPROVED WITH SUGGESTIONS (godot-gdscript-specialist + qa-tester en parallèle). 2 fixes appliqués (`Dictionary[String, Area3D]` typés + `is_instance_valid(_current_scene_root)` guard).

**Suggestions QA non-bloquantes (à logger en tech debt)** :
1. Test boundary distance exactement 10.00 m (strict `>` confirmé code, pas testé).
2. Test scène vide (0 volumes / 0 anchors → `[]`).
3. Test fixture mixte (volume orphan + anchor orphan dans même scene → `errors.size() == 2`).
4. Risque flake Jolt physics_frame×2 si CI montre instabilité — passer à 3 frames si observé.
5. Format message `"distance 15.00m > 10m"` fragile à un re-format `%.2f` — extraire format en constante si refactor.

**Tech debt** : 5 suggestions QA ci-dessus à logger via `/tech-debt` au prochain triage.

**Anomalie détectée + auto-fix** : Le fichier `tests/integration/level/level_validate_checkpoint_anchors_test.gd` avait disparu du disque entre code-review et story-done (uniquement le `.uid` companion subsistait). Restauré depuis le contenu lu pendant code-review. Cause inconnue — surveiller récurrence.
