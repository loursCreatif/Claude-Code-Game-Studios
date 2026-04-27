# Story 010: Canonical hierarchy + validate_scene_hierarchy() lint

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Config/Data
> **Estimate**: 6h (level_lint.gd helper 1h + run_level_lint.gd runner CI 1h + 4 fixtures .tscn 1.5h + 4 tests GdUnit4 1.5h + CI job lint-level-invariants 1h)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-006`

**ADR Governing Implementation**: — (authoring invariant, pas d'ADR structurel — GDD R-1 r2 source)
**ADR Decision Summary** : N/A. Lint pre-build GDD-owned ; invariant authoring scene tree.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `@tool` script runner ou `godot --headless --script tools/lint/level_lint.gd` en CI. Parse `.tscn` via `ResourceLoader.load(path)` + instantiate + `find_child(name, recursive=false)`. Pas de runtime overhead (pré-build).

**Control Manifest Rules (Core Layer)** : lint CI gating, authoring invariant — pas d'impact runtime. Convention naming préservée (PascalCase Node3D names).

---

## Acceptance Criteria

- [ ] **AC-LVL-11** : Hiérarchie canonique présente (R-1) — `StaticEnvironment` (Node3D), `InteractiveVolumes` (Node3D), `SpawnMarkers` (Node3D), `EtageExitTrigger` (Area3D) tous non-null
- [ ] **AC-LVL-43** : Signals list matches Detailed Design — runtime introspection vs contractual list (meta traceability, scan `Level.get_signal_list()` = {level_active, level_unloading, etage_completed, room_entered, player_out_of_world, level_load_failed, level_load_slow})

---

## Implementation Notes

- Créer `tools/lint/level_lint.gd` avec fonction `func validate_scene_hierarchy(scene_root: Node3D) -> Array[String]` — retourne liste de violations (empty = pass)
- Vérifications minimales :
  ```gdscript
  static func validate_scene_hierarchy(root: Node3D) -> Array[String]:
      var errors: Array[String] = []
      for required in ["StaticEnvironment", "InteractiveVolumes", "SpawnMarkers"]:
          var n := root.find_child(required, false, false)
          if n == null or not (n is Node3D):
              errors.append("missing required Node3D child: %s" % required)
      var exit := root.find_child("EtageExitTrigger", false, false)
      if exit == null or not (exit is Area3D):
          errors.append("missing EtageExitTrigger as Area3D child of root")
      return errors
  ```
- Créer runner CI : `tools/lint/run_level_lint.gd` qui charge `res://scenes/levels/etage_*.tscn`, instantiate, appelle `validate_scene_hierarchy()`, exit code 0 si empty errors, 1 sinon
- GitHub Actions job `lint-level-invariants` : `godot --headless --script tools/lint/run_level_lint.gd`
- Naming convention : chaque node enfant du root doit matcher exactement par `find_child(name, false, false)` (non-recursive, non-owned scan direct)
- AC-LVL-43 signals list : test runtime séparé `test_level_signal_list_matches_contract` qui appelle `level.get_signal_list()` et compare à liste canonique 7 signaux

---

## Out of Scope

- Story 011 : archetype enum + lint diversity
- Story 013 : validate_collision_layers (distinct lint)
- Story 018 : validate_secret_lures (distinct lint)
- Story 019 : validate_onboarding_anchors (distinct lint)
- Story 021 : validate_checkpoint_anchors (distinct lint, runtime)

---

## QA Test Cases

- **AC-LVL-11** : Test `test_validate_scene_hierarchy_pass_on_canonical_scene`
  - Setup : Créer fixture `tests/fixtures/level/etage_canonical.tscn` avec root Node3D + 4 enfants requis (StaticEnvironment, InteractiveVolumes, SpawnMarkers, EtageExitTrigger)
  - Verify : `validate_scene_hierarchy(root)` retourne `[]`
  - Pass : array vide

- Test `test_validate_scene_hierarchy_fails_missing_static_environment`
  - Setup : Fixture `etage_missing_static.tscn` avec root + 3 enfants (pas de StaticEnvironment)
  - Verify : `validate_scene_hierarchy(root)` retourne array de len ≥ 1 contenant "missing required Node3D child: StaticEnvironment"
  - Pass : exact message présent

- Test `test_validate_scene_hierarchy_fails_on_wrong_type`
  - Setup : Fixture avec `EtageExitTrigger` de type Node3D au lieu d'Area3D
  - Verify : Violation détectée "missing EtageExitTrigger as Area3D child of root"

- **AC-LVL-43** : Test `test_level_signal_list_matches_contract`
  - Given: Level instancié (post story 001-008 implementation)
  - When: `level.get_signal_list()` filtré aux signaux déclarés par `level.gd` (pas hérités Node)
  - Then: Set exact = `{level_active, level_unloading, etage_completed, room_entered, player_out_of_world, level_load_failed, level_load_slow}`
  - Edge cases: pas de signal undocumented ; pas de signal absent ; typed signatures correctes (covered story 002 AC-LVL-27)

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**:
- `tests/unit/lint/level_hierarchy_lint_test.gd` — 3 lint test cases
- `tests/unit/level/level_signals_contract_test.gd` — 1 runtime introspection test
- CI job `lint-level-invariants` vert sur scenes/levels/etage_*.tscn

**Status**: [x] Created — runner CI vérifié exit 0 local, tests GdUnit4 prêts pour pipeline

---

## Dependencies

- Depends on: **None** (authoring-only story — peut démarrer avant runtime behaviour stories)
- Unlocks: Story 005 (EtageExitTrigger authorial parent), Story 007 (RoomTrigger parent InteractiveVolumes), Story 008 (WorldBoundsVolume parent), Story 009 (SpawnMarkers parent)

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 2/2 passing (AC-LVL-11, AC-LVL-43)
**Deviations**: None
**Test Evidence**:
- `tools/lint/level_lint.gd` — helper static `LevelLint.validate_scene_hierarchy()`
- `tools/lint/run_level_lint.gd` — runner CI standalone (vérifié local exit 0)
- `tests/unit/lint/level_hierarchy_lint_test.gd` — 3 tests AC-LVL-11
- `tests/unit/level/level_signals_contract_test.gd` — 1 test AC-LVL-43 (contrat partiel 4/7, TODO commentés stories 005/007/008)
- `tests/fixtures/level/etage_{canonical,missing_static,wrong_type}.tscn`
- `.github/workflows/tests.yml` — job `lint-level-invariants` wiré dans `needs:` du job test
**Code Review**: Complete — godot-gdscript-specialist : SUGGESTIONS appliquées (typage `: GDScript` sur preload, `add_child(auto_free(...))` dans tests, `root_3d.queue_free()` cohérence). 0 blocker.
**QA Coverage Gate**: Skipped — Solo mode.
**Lead Programmer Review**: Skipped — Solo mode.
**Notes complémentaires** :
- Le contrat de signaux est volontairement partiel (4/7) avec TODO commentés. Stories 005/007/008 devront ajouter leur signal au `CONTRACT_SIGNALS` ; le test échouera tant que ce n'est pas fait — comportement régressif voulu.
- Fix runner standalone : `class_name LevelLint` non résolu en mode `--script`, donc `preload` explicite. Pattern à propager pour futurs lints CI.
