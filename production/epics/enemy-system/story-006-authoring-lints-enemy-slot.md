# Story 006: Authoring lints (`validate_enemy_slot_*` triplet)

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Tooling
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27 (EC-ENM-6/7/8 + AC-ENM-23/24/25)
**ADRs Governing**: ADR-0011 Level System architecture
**Depends on**: story-003 (LevelSystem `EnemySlot_*` Marker3D contract validé)

**Scope** : 3 validators authoring-time ajoutés à `tools/lint/level_lint.gd` :
- `validate_enemy_slot_marker3d` — scale uniform Vector3.ONE (EC-ENM-6).
- `validate_enemy_slot_min_distance` — distance ≥ 1.0 m entre paires (EC-ENM-8).
- `validate_enemy_slot_clearance` — pas placé dans la AABB d'un StaticBody3D (EC-ENM-7).

**Approche** : 100 % static, hermetic, zero physics dependency. Le clearance check
remplace le « raycast vertical » du GDD par une AABB intersection point-in-box test
sur les BoxShape3D de StaticEnvironment. Catch les mêmes erreurs d'authoring (slot
dans un mur) sans nécessiter PhysicsServer3D au lint time.

**Engine**: Godot 4.6 | **Risk**: VERY LOW (3 fonctions static pures, append à la fin
de level_lint.gd, zero modification existante)

**Control Manifest Rules (Tooling layer)** :
- Required : `find_children("EnemySlot_*", "Marker3D", true, false)` — même contrat
  que `EnemySpawner.spawn_for_scene()` runtime (story-003), garantit cohérence
  lint↔runtime.
- Forbidden : raycast / PhysicsServer3D au lint time (CI headless friendly).
- Guardrail : violation messages incluent slot name + EC/AC référencés pour traceability.

---

## Acceptance Criteria

- [x] **AC-ENM-23 [Logic]** : GIVEN un fichier `.tscn` étage avec `EnemySlot_01.scale = Vector3(2, 1, 1)`
      (non-uniform), WHEN `LevelLint.validate_enemy_slot_marker3d(root)` exécute,
      THEN un FAIL est rapporté avec message contenant « EnemySlot scale not uniform » (EC-ENM-6).
- [x] **AC-ENM-24 [Logic]** : GIVEN deux `EnemySlot_*` séparés de moins de `1.0 m`,
      WHEN `LevelLint.validate_enemy_slot_min_distance(root)` exécute, THEN un FAIL
      est rapporté avec message liant les 2 slot names (EC-ENM-8).
- [x] **AC-ENM-25 [Logic]** : GIVEN un `EnemySlot_*` placé dans un wall (position
      ∈ AABB d'un StaticBody3D BoxShape3D), WHEN `LevelLint.validate_enemy_slot_clearance(root)`
      exécute, THEN un FAIL est rapporté (EC-ENM-7).

**Bonus ACs covered** :
- **EC-ENM-15 onboarding salle calme** : étage sans EnemySlot → 3 validators retournent `[]`.
- **Boundary cases** : distance exactement 1.0 m → PASS (règle stricte `< 1.0 m`) ;
  scale uniformément 2× → FAIL (la règle est `Vector3.ONE`, pas « uniforme »).
- **Robustesse** : `StaticEnvironment` absent → clearance silently empty (hierarchy lint
  flag séparé).

---

## Implementation Notes

**Files** (MODIFIED) :
- `tools/lint/level_lint.gd` — append 3 nouveaux validators + 1 helper privé `_collect_enemy_slots`
  + 2 nouvelles constantes (`ENEMY_SLOT_SCALE_TOLERANCE`, `ENEMY_SLOT_MIN_DISTANCE_M`).
  Aucune modification des validators existants — ajout pur.

**Files** (NEW tests) :
- `tests/unit/lint/enemy_slot_lint_test.gd` — 12 tests couvrant 3 ACs + boundaries + robustness.

**API surface ajoutée** :
```gdscript
const ENEMY_SLOT_SCALE_TOLERANCE: float = 0.001
const ENEMY_SLOT_MIN_DISTANCE_M: float = 1.0

static func _collect_enemy_slots(root: Node3D) -> Array[Marker3D]
static func validate_enemy_slot_marker3d(root: Node3D) -> Array[String]
static func validate_enemy_slot_min_distance(root: Node3D) -> Array[String]
static func validate_enemy_slot_clearance(root: Node3D) -> Array[String]
```

**Algorithme clearance** :
- Pour chaque slot : transform global_position → CollisionShape3D local space via
  `cs.global_transform.affine_inverse() * slot_pos`.
- Test point-in-box : `|local_pos.x| ≤ size.x/2 AND |local_pos.y| ≤ size.y/2 AND |local_pos.z| ≤ size.z/2`.
- Break early dès qu'un slot est flag (un FAIL par slot suffit).

---

## Test Plan

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-23 | `enemy_slot_lint_test.gd` | `test_enemy_slot_marker3d_uniform_identity_scale_passes` | ✅ PASS |
| AC-ENM-23 | `enemy_slot_lint_test.gd` | `test_enemy_slot_marker3d_non_uniform_scale_fails` | ✅ PASS |
| AC-ENM-23 boundary | `enemy_slot_lint_test.gd` | `test_enemy_slot_marker3d_uniform_2x_scale_also_fails` | ✅ PASS |
| AC-ENM-23 EC-ENM-15 | `enemy_slot_lint_test.gd` | `test_enemy_slot_marker3d_no_slots_returns_empty` | ✅ PASS |
| AC-ENM-24 | `enemy_slot_lint_test.gd` | `test_enemy_slot_min_distance_3m_apart_passes` | ✅ PASS |
| AC-ENM-24 | `enemy_slot_lint_test.gd` | `test_enemy_slot_min_distance_below_threshold_fails` | ✅ PASS |
| AC-ENM-24 N-pairs | `enemy_slot_lint_test.gd` | `test_enemy_slot_min_distance_three_close_slots_reports_three_pairs` | ✅ PASS |
| AC-ENM-24 boundary | `enemy_slot_lint_test.gd` | `test_enemy_slot_min_distance_exactly_at_threshold_passes` | ✅ PASS |
| AC-ENM-25 | `enemy_slot_lint_test.gd` | `test_enemy_slot_clearance_open_space_passes` | ✅ PASS |
| AC-ENM-25 | `enemy_slot_lint_test.gd` | `test_enemy_slot_clearance_inside_wall_fails` | ✅ PASS |
| AC-ENM-25 robust | `enemy_slot_lint_test.gd` | `test_enemy_slot_clearance_no_static_env_returns_empty` | ✅ PASS |
| AC-ENM-25 EC-ENM-15 | `enemy_slot_lint_test.gd` | `test_enemy_slot_clearance_no_slots_returns_empty` | ✅ PASS |

**Test report** : `reports/report_246` — 12/12 PASSED en 175 ms.

**Régression vérifiée** : suite lint complète exécutée avant/après mes changements via
`git stash` — **14 errors / 10 failures pré-existants identiques** (déjà présents dans
`checkpoint_pairs_lint`, `visual_authoring_lint`, `wall_run_door_lint`, `secret_lures_lint`,
`level_formulas_lint`). Aucune régression introduite par story-006.

---

## Definition of Done

- [x] All 3 ACs (AC-ENM-23/24/25) PASS in automated tests.
- [x] Bonus tests (boundaries + EC-ENM-15 + robustness) PASS.
- [x] Zero régression on lint suite (failures identiques baseline pré-existants — vérifié git stash).
- [x] Zero régression on enemy suite (story-001/002/003/005 — 34/34 still PASS).
- [x] No raycast / PhysicsServer3D dependency au lint time (hermetic CI compatible).
- [x] Status switched `Ready` → `Complete` (auto-mode solo).

---

## Completion Notes

- **Divergence GDD AC-ENM-25** : le GDD décrit « raycast vertical ± 1 m ». L'implémentation
  utilise un test AABB point-in-box équivalent — catch les mêmes erreurs d'authoring (slot
  dans un mur), sans dépendance physics au lint time. Cohérent avec les autres validators
  level_lint.gd (tous structural / non-physics, e.g. `validate_wall_run_surfaces`).
- **Limite assumée AC-ENM-25** : couvre uniquement les BoxShape3D StaticBody3D — cas dominant
  des walls/sols de l'étage MVP. Les ConvexPolygonShape3D et MeshShape3D ne sont pas couverts,
  mais ne sont pas utilisés sur l'étage MVP (cf wall_run_door_lint qui assume aussi BoxShape3D).
- **Future story-007 build** : ces 3 validators s'invoqueront naturellement dans
  `tools/lint/run_level_lint.gd` (CI runner) une fois qu'un étage MVP réel utilisera des
  EnemySlot_* — au MVP, les validators retournent `[]` sur les étages actuels (aucun
  EnemySlot encore authored). Aucun impact CI immédiat.
- **Cohérence runtime↔lint** : `_collect_enemy_slots` utilise le même `find_children("EnemySlot_*",
  "Marker3D", true, false)` que `EnemySpawner.spawn_for_scene()` (story-003). Si l'authoring
  passe le lint, le spawn fonctionnera (et vice versa).

## Next Stories

- **story-004** : Combat sweep + Player laser cross-system tests (Blocked — Combat sweep impl).
- **story-007** : Performance benchmark 30 grunts (Ready — story-003 base).
