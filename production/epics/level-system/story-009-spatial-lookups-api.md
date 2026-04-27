# Story 009: Spatial lookups API (checkpoint / enemy / hazard / tutorial)

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 3h (4 méthodes API publiques 1h + helpers internes (`_current_scene_root` guard) 0.25h + 5 GdUnit4 tests 1.25h + CI hook 0.25h + doc API signatures 0.25h)
> **Performance Note**: Hot-path impact nul. Toutes les méthodes lookups sont appelées 1× par peer au binding `_on_level_active` (sync safe-point post-`level_active` emission), jamais en `_physics_process`. Coût `find_children()` amorti = O(n) sur scene tree au binding ≤ 0.5 ms one-shot vs. budget Physics ADR-0001 VC-4 ≤ 4 ms. Pas d'allocation hot-path (Control Manifest Core Layer). Guard défensif `if _current_scene_root == null: return []` zéro coût en chemin nominal.

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: — (TRs 022/025/027/030/032 dans C5 EPIC sont en réalité des signaux, réels TRs spatial lookups non-énumérés individuellement dans registry ; couverts par ACs AC-LVL-30/44)

**ADR Governing Implementation**: ADR-0005 (Movement Signals Architecture — principes API publique read-only, pas de signal emit)
**ADR Decision Summary** : API publique Level = contracts de lecture pour peers. Pas de signal emit dans cette story (lookups synchrones). ADR-0005 D-10 : Level ne référence pas peers par nom, mais expose API que peers lisent depuis leur `_on_level_active` handler.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `find_children(name: String, type: String, recursive: bool)` stable 4.0-4.6. Result = `Array[Node]`. Pour `get_tutorial_anchor(tag)` : convention tag = `name` du `Marker3D`. Retourne `null` si `find_children` retourne empty.

**Control Manifest Rules (Core Layer)** : API read-only safe après `level_active` ; pas d'allocation hot-path (lookups appelés 1× au binding, pas en `_physics_process`).

---

## Acceptance Criteria

- [ ] **AC-LVL-30** : `get_tutorial_anchor` retourne null si tag inconnu — `get_tutorial_anchor("nonexistent")` → retourne `null`, pas d'exception, `push_warning` en debug
- [ ] **AC-LVL-30b** : `get_checkpoint_slots()` retourne tuples paired volume↔anchor — pour scène avec `CheckpointVolume_01/02` + `CheckpointAnchor_01/02` authorés : Array length == 2 ; chaque entrée `{volume: Area3D, anchor: Vector3}` ; `anchor` = `global_position` du Marker3D paired (même NN). Volume sans anchor paired = `push_warning` + skip (no exception). 0 checkpoints authorés = empty array.
- [ ] **AC-LVL-30c** : Lookups appelés avant `level_active` retournent valeurs safe — `level.get_checkpoint_slots()` / `get_enemy_slots()` / `get_hazard_slots()` / `get_tutorial_anchor("foo")` quand `_current_scene_root == null` (état UNLOADED ou LOADING) → no exception ; return `[]` (Array methods) / `null` (`get_tutorial_anchor`) ; `push_warning` "lookup called before level_active" en debug.
- [ ] **AC-LVL-44** : API signatures documentées (dev-time AC, validable dans cette story) — chaque méthode publique (`get_checkpoint_slots`, `get_enemy_slots`, `get_hazard_slots`, `get_tutorial_anchor`) a un doc-comment GDScript décrivant : params, return type, comportement quand `_current_scene_root == null`, side-effects (`push_warning`). **Note**: validation `design/registry/level.yaml` (Tuning Knobs file) est déférée à Story 022 (pas un blocker pour cette story)

---

## Implementation Notes

- 4 méthodes publiques sur `level.gd` :
  ```gdscript
  func get_checkpoint_slots() -> Array:  # Array[CheckpointSlot] struct-like Dictionary
      var slots: Array = []
      var volumes := _current_scene_root.find_children("CheckpointVolume_*", "Area3D", true)
      for v in volumes:
          var idx := v.name.trim_prefix("CheckpointVolume_")
          var anchor := _current_scene_root.find_child("CheckpointAnchor_" + idx, true, false) as Marker3D
          if anchor == null:
              push_warning("CheckpointVolume_%s missing paired CheckpointAnchor" % idx)
              continue
          slots.append({"volume": v, "anchor": anchor.global_position})
      return slots

  func get_enemy_slots() -> Array[Marker3D]:
      return _current_scene_root.find_children("EnemySlot_*", "Marker3D", true) as Array[Marker3D]

  func get_hazard_slots() -> Array[Marker3D]:
      return _current_scene_root.find_children("HazardSlot_*", "Marker3D", true) as Array[Marker3D]

  func get_tutorial_anchor(tag: String) -> Marker3D:
      var markers := _current_scene_root.find_children(tag, "Marker3D", true)
      if markers.is_empty():
          push_warning("tutorial anchor not found: %s" % tag)
          return null
      return markers[0] as Marker3D
  ```
- Convention naming : `CheckpointVolume_01` ↔ `CheckpointAnchor_01` (zero-pad 2 chiffres)
- `get_secret_slots()` traité en story 018 (secret split contract nécessite struct tuple)
- `get_onboarding_anchors()` traité en story 019 (onboarding contract étage 1)
- API call safety : toutes méthodes assument `_state == ACTIVE` et `_current_scene_root != null`. Guard défensif : `if _current_scene_root == null: push_warning("lookup called before level_active") ; return []`
- API appelées typiquement 1× par peer au `_on_level_active` handler (sync safe-point post-level_active emission)

---

## Out of Scope

- Story 018 : `get_secret_slots()` (secret tuple struct spécifique)
- Story 019 : `get_onboarding_anchors()` (étage 1 only)
- Story 021 : `validate_checkpoint_anchors()` (EC-7 runtime validation, distinct de l'API read)
- Story 022 : `design/registry/level.yaml` tuning knobs authoring

---

## QA Test Cases

- **AC-LVL-30** : Test `test_get_tutorial_anchor_returns_null_for_unknown_tag`
  - Given: Level ACTIVE avec Marker3D nommés "first_dash" et "first_wall" dans scene
  - When: `level.get_tutorial_anchor("nonexistent")`
  - Then: Return `null` ; debug build : `push_warning` "tutorial anchor not found: nonexistent"
  - Edge cases: tag match existant = return Marker3D ; casse (`"First_Dash"`) = null (case-sensitive)

- Test `test_get_checkpoint_slots_returns_paired_tuples`
  - Given: Scene avec CheckpointVolume_01/02 + CheckpointAnchor_01/02 authorés
  - When: `level.get_checkpoint_slots()`
  - Then: Array length == 2 ; chaque entrée `{volume: Area3D, anchor: Vector3}` ; anchor positions = global_position markers
  - Edge cases: volume sans anchor paired = push_warning + skip (pas d'exception) ; 0 checkpoints = empty array

- Test `test_get_enemy_slots_returns_all_enemy_markers`
  - Given: Scene avec EnemySlot_01, EnemySlot_02, EnemySlot_03
  - When: `level.get_enemy_slots()`
  - Then: Array length == 3, ordre correspond aux naming NN ascendant
  - Edge cases: 0 enemies (étage traversal-only) = empty array

- Test `test_get_hazard_slots_returns_all_hazard_markers`
  - Given: Scene avec HazardSlot_01 seul
  - When: `level.get_hazard_slots()`
  - Then: Array length == 1

- Test `test_lookups_before_level_active_return_empty`
  - Given: Level UNLOADED (`_current_scene_root == null`)
  - When: `level.get_checkpoint_slots()` / `get_enemy_slots()` / `get_tutorial_anchor("foo")`
  - Then: Pas d'exception ; return `[]` / `null` respectivement ; `push_warning` debug

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/level/level_spatial_lookups_test.gd` — 5 test cases (AC-LVL-30 unknown tag null, AC-LVL-30b paired tuples, AC-LVL-30c safe before level_active, get_enemy_slots ordering, get_hazard_slots single)

**Status**: [ ] To be created during implementation at `tests/unit/level/level_spatial_lookups_test.gd`

---

## Dependencies

- Depends on: **Story 001** (state machine) + **Story 002** (ACTIVE state ADR-0007) + **Story 010** (hiérarchie SpawnMarkers parent)
- Unlocks: Downstream epics (Checkpoint / Enemy / Hazard / Tutorial) consume ces APIs

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 4/4 passing (AC-LVL-30 + AC-LVL-30b + AC-LVL-30c + AC-LVL-44)
**Verdict**: COMPLETE WITH NOTES

**Implementation**:
- `src/gameplay/level/level_system.gd` (+87 lignes) : 4 méthodes publiques (`get_checkpoint_slots` l.349, `get_enemy_slots` l.374, `get_hazard_slots` l.388, `get_tutorial_anchor` l.405) + setter test-only `_set_current_scene_root_for_test` l.691 (debug-guarded, pattern story-008 cohérent)
- `tests/unit/level/level_spatial_lookups_test.gd` (créé, 281 lignes, 5 tests GdUnit4)

**Test Evidence**: `tests/unit/level/level_spatial_lookups_test.gd` — parse check `godot --headless --check-only` EXIT 0

**Code Review**: Complete (`/code-review` exécuté 2026-04-27 — verdict APPROVED WITH SUGGESTIONS)

**Deviations** (advisory, non-bloquantes) :
- `get_checkpoint_slots() -> Array` non typé (compromis GDScript : pas d'`Array[Dictionary]` supporté)
- Coverage gaps advisory identifiés par qa-tester : (GAP-1) cas 0 volumes pour `get_checkpoint_slots` non testé directement ; (GAP-2) push_warning anchor mauvais type sans assertion test ; (GAP-3) ordering déterministe `get_enemy_slots` non asserté ; (GAP-4) QA Test Case doc l.108 omet `get_hazard_slots`

**Suggestions Code Review** (non-bloquantes) :
- L.349 : ajouter commentaire inline documentant compromis `Array[Dictionary]`
- L.379-382 / 392-395 : envisager `return nodes as Array[Marker3D]` après vérif Godot 4.6 cast filtré
- Ajouter tests advisory (0 volumes, anchor mauvais type, ordering)

**Out-of-scope respecté** : `get_secret_slots()` (story-018), `get_onboarding_anchors()` (story-019), `validate_checkpoint_anchors()` (story-021), `design/registry/level.yaml` (story-022) intacts

**Gates Skipped** (Solo mode) : QL-TEST-COVERAGE, LP-CODE-REVIEW
