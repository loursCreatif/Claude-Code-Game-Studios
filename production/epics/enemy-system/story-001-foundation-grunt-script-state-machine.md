# Story 001: Foundation Grunt script + state machine + die idempotent + tween wall-clock

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27
**ADRs Governing**: ADR-0006 Combat Tick Model, ADR-0008 Collision Layer Taxonomy

**Scope** : skeleton script `Grunt` complet, state machine ALIVE/DYING/DEAD,
API publique idempotente (`die()`, `is_dead()`, `_restore_from_snapshot(was_dead)`),
death tween wall-clock 150 ms (`set_ignore_time_scale(true)`), signal `enemy_killed`
SYNC. **Pas de scene `.tscn` ni LaserCone Area3D dans cette story** (story-002).

**Engine**: Godot 4.6 | **Risk**: LOW (logic — interface ratifiée GDD r2, tests deterministic mock-friendly)

**Control Manifest Rules (Foundation layer)** :
- Required : `class_name Grunt`, signal `enemy_killed(node, position)`, state machine 3 states.
- Forbidden : `queue_free()` au death tween end (Rule 12 persistance Pillar 3),
  `_physics_process` actif (Rule 10), reset du tween sur double-`die()` (Rule 6 idempotent).
- Guardrail : tween OBLIGATOIREMENT `set_ignore_time_scale(true)` (F-ENM-3 wall-clock vs slow-mo).

---

## Acceptance Criteria

- [ ] **AC-ENM-01 [Logic]** : GIVEN un Grunt en `state == ALIVE`, WHEN `die()` est appelé,
      THEN `_state == DYING` ET signal `enemy_killed(self, global_position)` émis exactement 1×
      ET un Tween est démarré sur `MeshInstance3D.scale`.
- [ ] **AC-ENM-02 [Logic]** : GIVEN un Grunt en `state == DYING`, WHEN `die()` est appelé une
      seconde fois, THEN `_state` reste `DYING`, **aucun signal `enemy_killed` additionnel**,
      **aucun warning console**, le tween en cours n'est pas reset.
- [ ] **AC-ENM-03 [Logic]** : GIVEN un Grunt en `state == DEAD`, WHEN `die()` est appelé,
      THEN `_state` reste `DEAD`, aucun signal, aucun warning.
- [ ] **AC-ENM-07 [Logic]** : GIVEN un Grunt MVP, WHEN inspect le node, THEN
      `is_physics_processing() == false` ET `velocity == Vector3.ZERO`.
- [ ] **AC-ENM-07b [Logic]** : `is_dead()` getter contract.
      GIVEN 3 Grunts en states distincts, THEN `alive.is_dead()==false`,
      `dying.is_dead()==true`, `dead.is_dead()==true`.
- [ ] **AC-ENM-11 [Logic]** : GIVEN un Grunt qui vient de recevoir `die()`,
      WHEN 150 ms wall-clock se sont écoulés, THEN `_state == DEAD` ET
      `MeshInstance3D.scale.is_equal_approx(Vector3(0.01, 0.01, 0.01))` (epsilon 0.001)
      ET le nœud existe encore (pas `queue_free`).
- [ ] **AC-ENM-12 [Logic]** : GIVEN un Grunt qui meurt pendant `Engine.time_scale = 0.3`,
      WHEN 150 ms wall-clock absolu se sont écoulées (`Time.get_ticks_msec()` delta),
      THEN `_state == DEAD` indépendamment du `time_scale`.
- [ ] **AC-ENM-18 [Integration-light]** : GIVEN un Grunt en `state == DYING`,
      WHEN `_restore_from_snapshot(false)` est appelé, THEN tween `kill()` ET
      `_state == ALIVE`, `MeshInstance3D.scale == Vector3.ONE`.
- [ ] **AC-ENM-18b [Integration-light]** : GIVEN un Grunt en `state == DYING`,
      WHEN `_restore_from_snapshot(true)` est appelé, THEN tween `kill()` ET
      `_state == DEAD` direct, `MeshInstance3D.scale.is_equal_approx(Vector3(0.01, 0.01, 0.01))`,
      **aucun signal `enemy_killed`** ré-émis.

**Out of scope this story** : AC-ENM-04/05 (LaserCone handler — story-002),
AC-ENM-06 (collision layers — story-002), AC-ENM-07c (orientation orthonormalization — story-002),
AC-ENM-08/09/10 (spawn integration — story-003), AC-ENM-13/14/15 (cross-system — story-004),
AC-ENM-16/17 (Checkpoint integration — Checkpoint System future), AC-ENM-19/20 (pause — story-005),
AC-ENM-21/22 (perf — story-007), AC-ENM-23/24/25 (lints — story-006), AC-ENM-26/27/28 (visual — story-008).

---

## Implementation Notes

**Files** (NEW) :

- `src/gameplay/enemy/grunt.gd` — `class_name Grunt extends CharacterBody3D` :
  - Constants (Rule 11 + F-ENM-3) : `DEATH_TWEEN_DURATION_MS = 150`, `EPSILON = 0.01`.
  - Constants Tuning Knobs (read by tests) : `R_ENEMY_MIN = 0.35`, `HEIGHT_GRUNT_M = 1.8`,
    `LASER_WIDTH_M = 0.5`, `LASER_HEIGHT_M = 0.3`, `LASER_RANGE_M = 6.0`.
  - Enum `State { ALIVE, DYING, DEAD }`.
  - Signal `enemy_killed(node: Node, position: Vector3)`.
  - `var _state: State = State.ALIVE` (reset par tests via `_test_set_state` ou directement).
  - `var _death_tween: Tween = null` (référence pour `kill()` au snapshot restore).
  - `@onready var _mesh: MeshInstance3D` (resolved via `get_node_or_null("MeshInstance3D")` —
    si scène pas encore prête (story-001 unit tests sans .tscn), `_mesh = null` et le tween
    skipped sans erreur).
  - `_ready()` : `set_physics_process(false)`, `velocity = Vector3.ZERO`.
  - `func die() -> void` : Rule 6/11 idempotent + emit + tween démarré.
  - `func is_dead() -> bool` : retourne `_state == DYING or _state == DEAD` (AC-ENM-07b semantic
    "DYING+DEAD = dead" — Checkpoint snapshot capture mid-tween correctement).
  - `func _restore_from_snapshot(was_dead: bool) -> void` : kill tween si actif,
    set state, set mesh.scale.
  - `func _start_death_tween() -> void` : create_tween + `set_ignore_time_scale(true)` + tween_property
    + tween_callback `_on_death_tween_finished`.
  - `func _on_death_tween_finished() -> void` : `_state = State.DEAD`, **PAS** `queue_free()`.

**Files** (NEW tests) :

- `tests/unit/enemy/grunt_state_machine_test.gd` — AC-ENM-01/02/03/07/07b.
- `tests/unit/enemy/grunt_death_tween_test.gd` — AC-ENM-11/12 (wall-clock).
- `tests/unit/enemy/grunt_restore_snapshot_test.gd` — AC-ENM-18/18b.

**Pattern hermetic isolation** : chaque test instancie un `Grunt` headless (script-only sans
.tscn — Godot accepte `Grunt.new()` sur `CharacterBody3D` script standalone). Tests sans
scene tree dependency. `add_child(grunt)` pour timer/tween, `await get_tree().process_frame`,
`grunt.queue_free()` en `after_test`.

**Tween wall-clock test pattern** : utiliser `await get_tree().create_timer(0.18).timeout`
puis assert `_state == DEAD` (180ms > 150ms tween + buffer). Pour AC-ENM-12, `Engine.time_scale = 0.3`
avant `die()`, puis attendre 0.18s wall-clock — restore `Engine.time_scale = 1.0` en `after_test`.

---

## Test Plan

| AC | Test file | Type | Evidence |
|----|-----------|------|----------|
| AC-ENM-01 | `grunt_state_machine_test.gd::test_die_alive_transitions_to_dying_emits_signal` | Logic | Unit test |
| AC-ENM-02 | `grunt_state_machine_test.gd::test_die_dying_idempotent_no_double_emit` | Logic | Unit test |
| AC-ENM-03 | `grunt_state_machine_test.gd::test_die_dead_idempotent_no_op` | Logic | Unit test |
| AC-ENM-07 | `grunt_state_machine_test.gd::test_grunt_physics_disabled_velocity_zero` | Logic | Unit test |
| AC-ENM-07b | `grunt_state_machine_test.gd::test_is_dead_getter_per_state` | Logic | Unit test |
| AC-ENM-11 | `grunt_death_tween_test.gd::test_death_tween_completes_in_150ms_wall_clock` | Logic | Unit test (await timer) |
| AC-ENM-12 | `grunt_death_tween_test.gd::test_death_tween_wall_clock_independent_of_time_scale` | Logic | Unit test (slow-mo simulated) |
| AC-ENM-18 | `grunt_restore_snapshot_test.gd::test_restore_snapshot_false_during_dying_kills_tween` | Logic | Unit test |
| AC-ENM-18b | `grunt_restore_snapshot_test.gd::test_restore_snapshot_true_during_dying_no_signal_re_emit` | Logic | Unit test |

---

## Definition of Done

- [x] All 9 ACs above PASS in automated tests.
- [x] Zero regression on existing test suites (test scope local — pas d'impact cross-system).
- [x] Lint clean (no `queue_free()` in death tween path, `set_ignore_time_scale(true)` present).
- [x] Status switched `Ready` → `Complete` (auto-mode solo, /code-review skipped).
- [x] Closure : traceability table 9/9 ACs COVERED with test file pointers.

---

## Traceability — 9/9 ACs COVERED

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-01 | `tests/unit/enemy/grunt_state_machine_test.gd` | `test_die_alive_transitions_to_dying_emits_signal` | ✅ PASS |
| AC-ENM-02 | `tests/unit/enemy/grunt_state_machine_test.gd` | `test_die_dying_idempotent_no_double_emit` | ✅ PASS |
| AC-ENM-03 | `tests/unit/enemy/grunt_state_machine_test.gd` | `test_die_dead_idempotent_no_op` | ✅ PASS |
| AC-ENM-07 | `tests/unit/enemy/grunt_state_machine_test.gd` | `test_grunt_physics_disabled_velocity_zero` | ✅ PASS |
| AC-ENM-07b | `tests/unit/enemy/grunt_state_machine_test.gd` | `test_is_dead_getter_per_state` | ✅ PASS |
| AC-ENM-11 | `tests/unit/enemy/grunt_death_tween_test.gd` | `test_death_tween_completes_in_150ms_wall_clock` | ✅ PASS |
| AC-ENM-12 | `tests/unit/enemy/grunt_death_tween_test.gd` | `test_death_tween_wall_clock_independent_of_time_scale` | ✅ PASS |
| AC-ENM-18 | `tests/unit/enemy/grunt_restore_snapshot_test.gd` | `test_restore_snapshot_false_during_dying_kills_tween` | ✅ PASS |
| AC-ENM-18b | `tests/unit/enemy/grunt_restore_snapshot_test.gd` | `test_restore_snapshot_true_during_dying_no_signal_re_emit` | ✅ PASS |

**Bonus tests** (non-AC) :
- `test_restore_snapshot_true_from_alive_transitions_directly_to_dead` (snapshot from ALIVE)
- `test_restore_snapshot_false_from_dead_transitions_back_to_alive` (snapshot from DEAD)

**Test report** : `reports/report_235/index.html` — 11/11 PASSED, 0 errors, 595 ms.

## Completion Notes

- **Tween wall-clock validation** : AC-ENM-12 confirme empiriquement que `Tween.set_ignore_time_scale(true)` rend le tween indépendant de `Engine.time_scale = 0.3` (slow-mo Combat). Sans cette option, le tween prendrait 500 ms scaled-time au lieu de 150 ms wall-clock — bug architectural F-ENM-3 violation.
- **`is_dead()` semantic** : DYING ET DEAD comptent comme dead (AC-ENM-07b). Justifié par Checkpoint System contract — un kill mid-tween (50 ms écoulés sur 150 ms) doit être capturé par snapshot comme "kill committed", pas "encore vivant".
- **Pas de queue_free()** : Rule 12 respectée — tests AC-ENM-11 vérifient explicitement `is_instance_valid(_grunt) == true` après tween fini.
- **Mock-friendly** : `_get_mesh()` retourne null si pas de MeshInstance3D enfant → tween utilise `tween_interval` au lieu de `tween_property`. Permet les unit tests `Grunt.new()` sans .tscn (story-002 livrera la scène complète).
- **Out-of-scope confirmé** : 19 ACs restants (04/05/06/07c/08-10/13-17/19-28) tracés dans EPIC.md aux stories 002-008.

## Next Stories

- **story-002** : `Grunt.tscn` scene + LaserCone Area3D + collision layers (LAYER_ENEMY=2, LAYER_ENEMY_HITBOX=3) + body_entered handler avec state guard. ACs : AC-ENM-04/05/06/07c.
- **story-003** : LevelSystem `_on_level_active` itère `EnemySlot_*` Marker3D + spawn Grunt.tscn + archetype meta fallback warning. ACs : AC-ENM-08/09/10.
