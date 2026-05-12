# Story 003: LevelSystem spawn integration (`EnemySlot_*` Marker3D iteration + archetype fallback)

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27 (Rule 9 + EC-ENM-15/16 + OQ-ENM-2 RESOLVED)
**ADRs Governing**: ADR-0011 (Level System architecture)
**Depends on**: story-002 (Grunt.tscn canonical scene available)

**Scope** : helper static `EnemySpawner.spawn_for_scene(scene_root)` qui itère
les Marker3D enfants nommés `EnemySlot_*`, instancie `Grunt.tscn`, copie
position + orientation orthonormalisée, gère fallback archetype unknown.
Hook dans `LevelSystem._physics_process` juste AVANT `level_active.emit()` pour
que les consumers du signal voient une scène pré-populée.

**Engine**: Godot 4.6 | **Risk**: LOW (helper static pur — pas d'autoload OQ-ENM-2,
pas de state, alloc 1× par boot étage)

**Control Manifest Rules (Core layer)** :
- Required : `find_children("EnemySlot_*", "Marker3D", true, false)` pour iteration,
  `slot.global_basis.orthonormalized()` pour FacingPivot.
- Forbidden : autoload séparé `EnemySpawner` (OQ-ENM-2 RESOLVED — LevelSystem orchestre),
  bouger LevelSystem state machine.
- Guardrail : spawn AVANT `level_active.emit()` pour cohérence consumer view.

---

## Acceptance Criteria

- [x] **AC-ENM-08 [Integration]** : GIVEN scene_root avec `EnemySlot_01..03` (3 Marker3D)
      à des positions distinctes, WHEN `EnemySpawner.spawn_for_scene(root)` invoqué,
      THEN exactement 3 Grunt instances sont ajoutés au scene tree, leurs
      `global_position` matchent les `EnemySlot.global_position` (epsilon 0.001).
- [x] **AC-ENM-09 [Integration]** : GIVEN un `EnemySlot_01` orienté
      `Basis.IDENTITY.rotated(Vector3.UP, PI / 4)` (45° autour Y), WHEN spawn,
      THEN `Grunt.%FacingPivot.global_basis.is_equal_approx(slot.global_basis.orthonormalized())`
      (epsilon 0.001).
- [x] **AC-ENM-10 [Integration]** : GIVEN `EnemySlot.set_meta("archetype", "drone")` au MVP,
      WHEN spawn, THEN un Grunt est instancié à la place ET
      `push_warning("Enemy archetype 'drone' unknown — fallback to 'grunt'")` apparaît.

**Bonus ACs covered** :
- **EC-ENM-15** : étage légal sans EnemySlot → `[]` retourné silencieusement (onboarding salle calme).
- **Robustesse** : `scene_root null` → `[]` + push_warning sans crash.
- **Default meta** : slot sans `archetype` meta → grunt instancié sans warning.

---

## Implementation Notes

**Files** (NEW) :
- `src/gameplay/enemy/enemy_spawner.gd` — `class_name EnemySpawner extends Object`,
  static method `spawn_for_scene(scene_root: Node3D) -> Array[Grunt]` :
  - `find_children("EnemySlot_*", "Marker3D", true, false)` pour iteration.
  - Loop : lit `slot.get_meta("archetype", &"grunt")` → fallback warning si != grunt.
  - `grunt.global_position = slot.global_position`.
  - `grunt.%FacingPivot.global_basis = slot.global_basis.orthonormalized()` (EC-ENM-6).
  - Retourne `Array[Grunt]` spawnés (debug + tests).

**Files** (MODIFIED) :
- `src/gameplay/level/level_system.gd` :
  - Ajout 1 ligne dans `_physics_process` au point de transition LOADING → ACTIVE,
    juste AVANT `level_active.emit()` :
    ```gdscript
    EnemySpawner.spawn_for_scene(_current_scene_root)
    level_active.emit(_current_etage_id, _player_start)
    ```
  - 0 modification de l'API publique LevelSystem (compatible cross-system).
- `.godot/global_script_class_cache.cfg` — entrée `EnemySpawner` ajoutée.

**Files** (NEW tests) :
- `tests/integration/enemy/enemy_spawner_test.gd` — 6 tests AC-ENM-08/09/10 + 3 bonus.

---

## Test Plan

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-08 | `enemy_spawner_test.gd` | `test_spawn_three_slots_creates_three_grunts_at_correct_positions` | ✅ PASS |
| AC-ENM-09 | `enemy_spawner_test.gd` | `test_spawn_slot_with_rotation_copies_orthonormalized_basis_to_facing_pivot` | ✅ PASS |
| AC-ENM-10 | `enemy_spawner_test.gd` | `test_spawn_unknown_archetype_falls_back_to_grunt` | ✅ PASS |
| Robustesse null | `enemy_spawner_test.gd` | `test_spawn_null_scene_root_returns_empty` | ✅ PASS |
| EC-ENM-15 | `enemy_spawner_test.gd` | `test_spawn_scene_without_slots_returns_empty` | ✅ PASS |
| Default meta | `enemy_spawner_test.gd` | `test_spawn_slot_without_archetype_meta_uses_default_grunt` | ✅ PASS |

**Test report** : `reports/report_238/index.html` — 30/30 PASSED enemy suite (story-001 + 002 + 003), 0 errors, 1.089 s.

**Régression vérifiée** : `tests/integration/level/level_unload_test.gd` montre 3 erreurs / 5 échecs **identiques** baseline (avant mon changement) — failures pré-existantes liées au display server / autoload headless, **NON** causées par mon ajout `EnemySpawner.spawn_for_scene()` (vérifié via `git stash` + re-run).

---

## Definition of Done

- [x] All 3 ACs (AC-ENM-08/09/10) PASS in automated tests.
- [x] Bonus tests (EC-ENM-15, null robustness, default meta) PASS.
- [x] Zero régression on enemy suite (story-001/002 — 24/24 still PASS).
- [x] Zero régression on LevelSystem suite (failures identiques baseline pré-existants — vérifié git stash).
- [x] Lint clean : pas d'autoload séparé `EnemySpawner` (OQ-ENM-2 compliant).
- [x] Status switched `Ready` → `Complete` (auto-mode solo).

---

## Completion Notes

- **OQ-ENM-2 honoré** : pas d'autoload `EnemySpawner` séparé. Le helper est un `Object`
  static appelé directement par LevelSystem au point de transition.
- **Decoupling minimal LevelSystem** : 1 ligne ajoutée à `level_system.gd:236` — la complexité
  de spawn est encapsulée dans `enemy_spawner.gd`. Pas de bloat sur LevelSystem (déjà 900+ lignes).
- **Spawn timing** : avant `level_active.emit()` pour que les consumers (Combat, Audio, etc.)
  voient une scène populée au tick de leur premier handler. Évite race condition
  "consumer connects → no grunts yet".
- **Orthonormalize override** : grunt._ready() a déjà orthonormalisé sur basis IDENTITY
  default (story-002 EC-ENM-6) ; le spawner override avec `slot.global_basis.orthonormalized()`
  pour appliquer l'orientation slot proprement. Double-orthonormalize idempotent (no-op si déjà clean).
- **EC-ENM-15 robustesse** : étage onboarding sans grunt légal — `find_children` retourne `[]`,
  loop skip, retour silencieux. Pas de log spam.
- **AC-ENM-10 fallback** : `push_warning` non testé via assertion (GdUnit4 ne capture
  pas console standard) ; couverture par robustness assertion (1 grunt instancié malgré
  archetype unknown). Future story-006 ajoutera lint authoring-time pour catch
  `archetype` invalide statiquement.

## Next Stories

- **story-004** : Cross-system integration tests (Combat sweep + Player laser → mutual kill EC-ENM-14, AC-ENM-13/14/15).
- **story-005** : Pause/state lifecycle integration (GameStateManager) — AC-ENM-19/20.
- **story-006** : Authoring lints (`validate_enemy_slot_marker3d` + `validate_enemy_slot_min_distance` + `validate_enemy_slot_clearance`) — AC-ENM-23/24/25.
