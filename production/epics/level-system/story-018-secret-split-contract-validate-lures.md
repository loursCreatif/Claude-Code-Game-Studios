# Story 018: Secret triplet + required_ability + validate_secret_lures + get_secret_slots

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 5h (Secret triplet authoring convention + @export required_ability StringName 1h + validate_secret_lures lint 1.5h + get_secret_slots API runtime 1h + 4 lint tests + 2 runtime tests 1h + CI hook 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: — (r2 fix #4 TR couvert par AC-LVL-46 + AC-LVL-53 sans TR-lvl distinct dans registry)

**ADR Governing Implementation**: — (authoring contract GDD-owned r2)
**ADR Decision Summary** : N/A. Contract Level + Secret System (Feature layer epic futur). Level publie triplets, Secret System consume via `get_secret_slots()` pour spawner lures VFX + respond collection Volume.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `StringName` pré-alloué constants (ADR-0004 pattern) pour `required_ability` enum canonical values. `@export var required_ability: StringName = &"none"` inspector-friendly. `Marker3D` pour lure + anchor, `Area3D` pour collect volume.

---

## Acceptance Criteria

- [x] **AC-LVL-46** : Secret count in MVP range (F7) — count `SecretCollectVolume_NN` distinct ∈ [3, 5] ; ≥ 1 secret has `required_ability ∈ {wall_run, wall_run_long}` (economic constraint pillar 4)
- [x] **AC-LVL-53** : Tuple Secret cohérent Lure ↔ Volume ↔ Anchor (r2 fix #4) — pour chaque NN, les 3 sous-arbres contiennent un élément NN ; chaque `SecretLureMarker_NN` a `required_ability ∈ {none, dash, double_jump, wall_run, wall_run_long}` exporté ; orphelin ou annotation manquante = lint fail

---

## Implementation Notes

- Constants canonical StringNames dans `src/gameplay/level/secret_abilities.gd` :
  ```gdscript
  class_name SecretAbilities
  const NONE: StringName = &"none"
  const DASH: StringName = &"dash"
  const DOUBLE_JUMP: StringName = &"double_jump"
  const WALL_RUN: StringName = &"wall_run"
  const WALL_RUN_LONG: StringName = &"wall_run_long"

  static func valid_abilities() -> Array[StringName]:
      return [NONE, DASH, DOUBLE_JUMP, WALL_RUN, WALL_RUN_LONG]
  ```
- `SecretLureMarker.gd` script attaché aux Marker3D nommés `SecretLureMarker_NN` :
  ```gdscript
  @tool
  extends Marker3D
  class_name SecretLureMarker
  @export var required_ability: StringName = &""
  ```
- Triplet authoring convention :
  - `SecretLureMarker_NN` Marker3D sous `SpawnMarkers` (visible marker cross-room, no collider, VFX spawn)
  - `SecretCollectVolume_NN` Area3D sous `InteractiveVolumes` (collection detection)
  - `SecretAnchor_NN` Marker3D sous `SpawnMarkers` (content spawn position)
- `get_secret_slots() -> Array` dans level.gd :
  ```gdscript
  func get_secret_slots() -> Array:
      var slots: Array = []
      var lures := _current_scene_root.find_children("SecretLureMarker_*", "Marker3D", true)
      for lure in lures:
          var idx := lure.name.trim_prefix("SecretLureMarker_")
          var collect := _current_scene_root.find_child("SecretCollectVolume_" + idx, true, false)
          var anchor := _current_scene_root.find_child("SecretAnchor_" + idx, true, false)
          if collect == null or anchor == null:
              push_warning("Secret tuple incomplete at index %s" % idx)
              continue
          slots.append({
              "lure": lure,
              "collect_volume": collect,
              "content_anchor": anchor.global_position,
              "required_ability": lure.get("required_ability") if lure.has_method("get") else &"",
          })
      return slots
  ```
- `validate_secret_lures(root: Node3D) -> Array[String]` dans `tools/lint/level_lint.gd` :
  - Scan 3 sub-trees, check for each NN présent : les 2 autres existent
  - Check chaque SecretLureMarker_NN a `required_ability` in `SecretAbilities.valid_abilities()`
  - Check count SecretCollectVolume_NN ∈ [3, 5]
  - Check ≥ 1 secret a `required_ability in [WALL_RUN, WALL_RUN_LONG]` (economic constraint)

---

## Out of Scope

- Story 009 : lookups API autres (checkpoint/enemy/hazard/tutorial)
- Story 019 : onboarding anchors (distinct de secrets)
- Secret System (Feature epic futur) : VFX lure visible cross-room, Volume detection + content spawn

---

## QA Test Cases

- **AC-LVL-53 orphan** : Test `test_validate_secret_lures_fails_orphan_lure_without_volume`
  - Setup : Fixture `SecretLureMarker_01` présent mais `SecretCollectVolume_01` absent
  - Verify : Violation `"Secret tuple incomplete at index 01 — missing SecretCollectVolume"`

- **AC-LVL-53 missing ability** : Test `test_validate_secret_lures_fails_missing_required_ability`
  - Setup : SecretLureMarker_01/02/03 complets triplets, mais Lure_02 n'a pas `required_ability` exporté (empty StringName)
  - Verify : Violation `"SecretLureMarker_02 required_ability not in {none, dash, double_jump, wall_run, wall_run_long}"`

- **AC-LVL-46 count range** : Test `test_secret_count_within_3_to_5`
  - Setup : 3 triplets (floor), 4 triplets (nominal), 5 triplets (cap)
  - Verify : tous pass ; 2 triplets = fail "count 2 < 3" ; 6 = fail "count 6 > 5"

- **AC-LVL-46 economic** : Test `test_at_least_one_secret_requires_wall_run`
  - Setup : 4 triplets tous avec `required_ability=dash` (aucun wall_run)
  - Verify : Violation `"economic constraint: ≥ 1 secret must require wall_run or wall_run_long"`
  - Edge cases: 1 secret avec wall_run_long = pass

- **get_secret_slots** : Test `test_get_secret_slots_returns_typed_tuples`
  - Given: 3 triplets complets dans scene ACTIVE
  - When: `level.get_secret_slots()`
  - Then: Array length == 3 ; chaque entry Dictionary avec keys `{lure, collect_volume, content_anchor, required_ability}` ; types correspondent

- **get_secret_slots skip incomplete** : Test `test_get_secret_slots_skips_incomplete_tuples_with_warning`
  - Given: 2 complets + 1 orphan (Lure only)
  - When: `get_secret_slots()`
  - Then: Array length == 2 ; push_warning enregistré pour orphan

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/lint/secret_lures_lint_test.gd` — 4 lint test cases
- `tests/unit/level/level_get_secret_slots_test.gd` — 2 API runtime tests

**Status**: [x] Created and committed — see Completion Notes below.

---

## Completion Notes

**Completed** : 2026-04-27 (solo auto-approve)
**Criteria** : 2/2 ACs (AC-LVL-46 + AC-LVL-53) ✓ — implémentation lint + API runtime + 4 tests lint + 2 tests runtime.

**Files créés** :
- `src/gameplay/level/secret_abilities.gd` (62 l) — class_name SecretAbilities + 5 StringName constants pré-allouées (`&"none"`, `&"dash"`, `&"double_jump"`, `&"wall_run"`, `&"wall_run_long"`) + static `valid_abilities() -> Array[StringName]`.
- `src/gameplay/level/secret_lure_marker.gd` (34 l) — `@tool extends Marker3D class_name SecretLureMarker` + `@export var required_ability: StringName`.
- `tests/unit/lint/secret_lures_lint_test.gd` (323 l) — 4 GdUnit4 tests : orphan lure / missing required_ability / count range [3,5] (5 sous-cas) / economic constraint wall_run.
- `tests/unit/level/level_get_secret_slots_test.gd` (~165 l) — 2 GdUnit4 tests : typed tuples retournés / orphan tuples skip.

**Files modifiés** :
- `tools/lint/level_lint.gd` (759 → 889 l, +130 l) — ajout `validate_secret_lures(root: Node3D) -> Array[String]` (ligne 789) + preload SecretAbilities pattern miroir CollisionLayersScript.
- `src/gameplay/level/level_system.gd` (758 → 815 l, +57 l) — ajout `get_secret_slots() -> Array` (ligne 434) avec doc-comments + guard scene_root + skip incomplete tuples + 4 keys Dictionary.
- `tools/lint/run_level_lint.gd` — ajout call `validate_secret_lures(root_3d)` ligne 122 + accumulation errors + header comment update ligne 91.

**Mapping ACs → livrables** :
- AC-LVL-46 (count [3,5] + economic constraint) → `validate_secret_lures` count check + wall_run_long check + 2 tests `test_secret_count_within_3_to_5` + `test_at_least_one_secret_requires_wall_run`.
- AC-LVL-53 (triplet coherence + required_ability) → `validate_secret_lures` 3-way orphan checks + ability membership + 2 tests `test_validate_secret_lures_fails_orphan_lure_without_volume` + `test_validate_secret_lures_fails_missing_required_ability` + 2 runtime tests `test_get_secret_slots_returns_typed_tuples` + `test_get_secret_slots_skips_incomplete_tuples_with_warning`.

**Conformité** :
- Static typing 100% ✓
- Doc-comments `##` extensifs ✓
- StringName pré-alloué `&""` (ADR-0004 pattern) ✓
- Naming snake_case/PascalCase/UPPER_SNAKE_CASE ✓
- API publique read-only consommée par peers (ADR-0005 D-10) ✓
- Pattern miroir `get_checkpoint_slots()` (story-009) ✓

**Solo gates** : QL-TEST-COVERAGE skipped + LP-CODE-REVIEW skipped (Solo mode confirmé via `production/review-mode.txt`).

**Sprint impact** : 19ème story Level System Complete. Débloque Secret System epic (Feature layer futur — peers consument `get_secret_slots()` pour spawn lure VFX + collect detection).

---

## Code Review Notes (2026-04-27)

**Verdict** : APPROVED (post-fixes).

`/code-review` exécuté sur les 7 livrables (godot-gdscript-specialist + qa-tester en parallèle). 5 must-fix appliqués :

- `level_system.gd:434` — typing return `-> Array[Dictionary]` (était `Array` non typé, contrat ADR-0005 D-10).
- `level_system.gd:438` — `var slots: Array[Dictionary] = []` (cohérent return type).
- `level_system.gd:462-470` — commentaire explicatif pattern `lure.get("required_ability")` Variant ; `as SecretLureMarker` non utilisable car level_system.gd est autoload chargé avant peuplement registry class_name (cf. pattern `preload(...)` adopté par level_lint.gd pour la même raison).
- `tests/unit/lint/secret_lures_lint_test.gd:+38 l` — ajout `test_validate_secret_lures_fails_orphan_volume_without_lure` couvrant la branche lint lignes 838-843 (volume orphelin sans lure correspondant).
- Lint runner re-validé clean : `godot --headless --script tools/lint/run_level_lint.gd` → exit 0.

**Suggestions non bloquantes (à archiver tech-debt)** :
- `_collect_secret_indices` scanne enfants directs uniquement vs `find_child(.., true, ..)` récursif ailleurs — incohérence acceptable (convention authoring flat) à documenter.
- `secret_abilities.gd:58-62` : `valid_abilities()` deprecated peut être supprimé (aucun caller historique réel, fichier neuf).
- `secret_lure_marker.gd:26-28` : ordre `@tool` / `class_name` / `extends` plus idiomatique que l'ordre actuel.
- Branche orphan Anchor (lint lignes 845-849) non couverte par test direct.
- `test_secret_count_within_3_to_5` bundle 5 sous-cas — splittable si standard "1 fonction = 1 scénario" adopté.

---

## Dependencies

- Depends on: **Story 009** (API lookups pattern), **Story 010** (hiérarchie SpawnMarkers + InteractiveVolumes)
- Unlocks: Secret System epic (consume lookups)
