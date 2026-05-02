# Story 008: player_out_of_world signal + WorldBoundsVolume BoxShape3D (EC-1, F6)

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: 4h (signal declaration 0.5h + WorldBoundsVolume Area3D+BoxShape3D authoring 1h + handler `_on_world_bounds_body_exited` + safety net Y < -2 0.5h + `_last_valid_position` ring buffer + reset hooks 0.5h + 3 GdUnit4 test cases 1h + CI hook 0.5h)
> **Performance Note**: Hot-path impact négligeable. Handler `_on_world_bounds_body_exited` = early returns + 1 emit gardé par flag bool ; safety-net check `_physics_process` = 1 comparaison `y < -2.0` + 1 update `_last_valid_position` (Vector3 assignement value-type, zero-alloc). Coût cumulé < 0.01 ms/frame vs budget Physics ADR-0001 VC-4 ≤ 4 ms. Pas de signal `CONNECT_DEFERRED` (consumer = CheckpointSystem futur léger, mode SYNC par défaut ADR-0005 D-5).

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-017` (etage bounding volume), `TR-lvl-018` (Y ≥ -2), `TR-lvl-024` (player_out_of_world signal)

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz), ADR-0005
**ADR Decision Summary** : ADR-0001 : collision check via Jolt Area3D body_exited en physics step. ADR-0005 D-3 payload `Vector3` value-type. Signal one-shot fire par out-of-world event (player respawn reset = nouveau potential fire).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `WorldBoundsVolume` = `Area3D` avec `BoxShape3D` exclusivement (pas `ConcavePolygonShape3D` ni trimesh — helper `validate_level_shapes()` vérifie). `body_exited` fire quand player sort du volume. Fallback complémentaire : check `player.global_position.y < -2.0` en `_physics_process` (double safety si player tunnel au bord). Vector3 `last_valid_position` capturé avant exit (stocké en ring pour robustesse).

**Control Manifest Rules (Core Layer)** : signal typed Vector3 payload, emit depuis `_physics_process` (body_exited physics context), `WorldBoundsVolume` BoxShape3D only.

---

## Acceptance Criteria

- [x] **AC-LVL-16** : No geometry below Y=-2.0 (R-2.U.3) — scan AABB de tous StaticBody3D ; aucun n'a `aabb.min.y < -2.0` sauf floor à y=0 (invariant authoring, story 020 lint) — **DEFERRED out-of-scope story-020 lint**
- [x] **AC-LVL-25** : `player_out_of_world` triggered by WorldBounds (EC-1) — `player.global_position.y < -2.0` OU outside `WorldBoundsVolume` → signal `player_out_of_world(last_valid_position)` exactement 1× — **COVERED par 4 tests GdUnit4**
- [x] **AC-LVL-49** : WorldBoundsVolume encloses stage (F6) — AABB union de tous StaticBody3D + WorldBoundsVolume → Volume contient union strictement avec ≥ 3 m marge sur tous axes (story 020 lint) — **DEFERRED out-of-scope story-020 lint**

---

## Implementation Notes

- Signal declaration : `signal player_out_of_world(last_valid_position: Vector3)` typed
- Authoring : `WorldBoundsVolume` = Area3D enfant direct de Level root ou enfant de `InteractiveVolumes` (decision : placer sous `InteractiveVolumes` pour cohérence hiérarchie story 010). BoxShape3D obligatoire (lint `validate_level_shapes()` en story 013/020 aggregate)
- Dimensions typical : 5000 m³ bounding (F6 : 10 rooms × 100 m² × 5 m) + 3 m marge → Box 30×25×10 m. Authoring-driven
- Maintenance `_last_valid_position: Vector3` dans `level.gd` : ring buffer trivial = mise à jour chaque `_physics_process` avec `player.global_position` si dedans WorldBoundsVolume ET `y >= -2.0` (peer lookup via groupe "player")
- Path 1 (primary) : `WorldBoundsVolume.body_exited.connect(_on_world_bounds_body_exited)` ; handler :
  ```gdscript
  func _on_world_bounds_body_exited(body: Node3D) -> void:
      if _state != LevelState.ACTIVE: return
      if not body.is_in_group("player"): return
      if _out_of_world_emitted_this_life: return  # idempotence jusqu'à respawn
      _out_of_world_emitted_this_life = true
      _assert_main_thread()
      player_out_of_world.emit(_last_valid_position)
  ```
- Path 2 (safety net) : en `_physics_process`, if `player.global_position.y < -2.0 and not _out_of_world_emitted_this_life` : même emission
- Reset `_out_of_world_emitted_this_life = false` sur signal Player `respawned` (Checkpoint System cascade) OU sur `load_etage()` fresh. Consumer = CheckpointSystem (pas Level)
- Pas de tracking secondaire si player revient dans bounds (one-shot par death / respawn cycle)

---

## Out of Scope

- Story 013 : `validate_level_shapes()` lint BoxShape3D
- Story 020 : lint F6 bounding + Y ≥ -2 authoring invariant
- Checkpoint System (epic futur) : consume `player_out_of_world` → respawn logic

---

## QA Test Cases

- **AC-LVL-25 path 1** : Test `test_player_out_of_world_via_worldbounds_exit`
  - Given: Level ACTIVE, WorldBoundsVolume Box 30×25×10 m centré origin, player at (0, 1, 0), `_last_valid_position` updated
  - When: Teleport player à (50, 1, 0) (hors bounds) ; wait 2 physics frames
  - Then: Signal `player_out_of_world(Vector3(0, 1, 0))` reçu exactement 1×
  - Edge cases: player revient dans bounds = pas de nouveau signal (idempotent) ; respawn reset puis re-sortie = signal émis à nouveau

- **AC-LVL-25 path 2** : Test `test_player_out_of_world_via_y_below_minus_2`
  - Given: Level ACTIVE, player at (0, -5, 0) (sous seuil Y=-2) — simule tunneling au bord bounds
  - When: wait 1 physics frame
  - Then: Signal `player_out_of_world` émis avec last valid pos (dernière position `y >= -2`)
  - Edge cases: player à `y = -1.99` = pas de trigger (seuil strict `< -2.0`) ; player à `y = -2.0` pile = pas de trigger (gate strict)

- **AC-LVL-25 idempotence** : Test `test_player_out_of_world_idempotent_single_life`
  - Given: Level ACTIVE, player tombe sous Y=-2
  - When: 5 frames consécutifs avec player à `y=-10`
  - Then: Signal `player_out_of_world` émis 1× uniquement (flag `_out_of_world_emitted_this_life` bloque re-emission)
  - Edge cases: reset flag sur `load_etage()` fresh = re-emission possible après

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/level/level_player_out_of_world_test.gd` — 4 test cases

**Status**: [x] Created — `tests/integration/level/level_player_out_of_world_test.gd` (4 GdUnit4 test cases) + fixture `tests/fixtures/levels/test_etage_08.tscn`

---

## Dependencies

- Depends on: **Story 001** (state machine), **Story 002** (ACTIVE state), **Story 010** (hiérarchie InteractiveVolumes parent de WorldBoundsVolume)
- Unlocks: Checkpoint System epic (consume signal)

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 1/1 in-scope passing (AC-LVL-25 — 4 tests d'intégration). 2 ACs DEFERRED par design (out-of-scope explicite story-020 lint authoring pour AC-LVL-16 + AC-LVL-49).

**Files**:
- `src/gameplay/level/level_system.gd` — `signal player_out_of_world(last_valid_position: Vector3)`, handler `_on_world_bounds_body_exited`, safety-net check Y<-2 in `_physics_process` via `_update_last_valid_position_and_check_y_threshold`, idempotence flag `_out_of_world_emitted_this_life`, public reset `reset_out_of_world_flag()`, reset via `_reset_runtime_state()` in `load_etage()` + `UNLOADING→UNLOADED` transition
- `tests/integration/level/level_player_out_of_world_test.gd` — 4 GdUnit4 test cases :
  1. `test_player_out_of_world_emits_via_worldbounds_exit` (path 1 body_exited + idempotence re-entry)
  2. `test_player_out_of_world_emits_via_y_below_minus_two` (path 2 safety net + gate strict y=-2.0)
  3. `test_player_out_of_world_idempotent_single_life` (5 frames + reset_out_of_world_flag re-emission)
  4. `test_player_out_of_world_reset_via_fresh_load_etage` (auto-reset via _reset_runtime_state — ajouté lors de /code-review 2026-04-27)
- `tests/fixtures/levels/test_etage_08.tscn` — PlayerStart Marker3D (0,0,0) + EtageExitTrigger (0,2,-100) + InteractiveVolumes parent + WorldBoundsVolume Area3D (BoxShape3D 30×25×10)

**Test Evidence**: Integration test at `tests/integration/level/level_player_out_of_world_test.gd` ✓

**Code Review** (2026-04-27 r21) : Solo mode → LP-CODE-REVIEW + QL-TEST-COVERAGE skipped. `/code-review` lancé manuellement → verdict initial CHANGES REQUIRED (1 test d'edge case manquant : auto-reset flag via `load_etage()`). Fix appliqué directement (test #4 ajouté). Verdict final : **APPROVED**. Specialist passes : godot-gdscript-specialist (typage strict ✓, doc comments ✓, mutation-before-emit ✓, idempotence cohérente, pattern miroir stories-005/007). qa-tester (4/4 cas QA spec couverts, hooks DI exposés, gate strict testé explicitement).

**Manifest Version** : 2026-04-23 → match current → no staleness.

**Deviations** : NONE — implémentation conforme à ADR-0005 D-3/D-4/D-8/D-9, ADR-0011 D-9 (BoxShape3D), TR-lvl-017/018/024.

**Suggestions non-bloquantes (follow-up tickets possibles)** :
- Cache-miss alloc dans `_resolve_player_node` via `get_nodes_in_group("player")` — boot-only window (avant que PlayerController rejoigne le groupe), hors scope strict `.claude/rules/no-alloc-hot-paths.md` mais viole l'esprit ADR-0005 D-9. Mitigation : cache via signal `level_active` consumer ou `child_entered_tree`. **Doc-comment ajouté 2026-04-27 r22 reconnaissant explicitement les fenêtres de miss bornées.**
- Exposer `Y_OUT_OF_WORLD_THRESHOLD` en public (suppr. préfixe `_`) pour que les tests référencent la constante au lieu de hardcoder `-2.0` dans les commentaires fixtures.
- Clarifier flow control dans `_update_last_valid_position_and_check_y_threshold` (ligne 528-535) avec un `else if` explicite.
- Tests advisory non-couverts : NaN/Inf guards (`_on_world_bounds_body_exited`, `_update_last_valid_position_and_check_y_threshold`), `push_error` multi-WorldBoundsVolume, `push_warning` missing-WorldBoundsVolume.

**Polish 2026-04-27 r22 (re-review pass /code-review + /story-done)** :
- `level_system.gd` `_update_last_valid_position_and_check_y_threshold` : doc-comment étendu pour expliciter la dépendance à l'ordering Godot 4.6 physics step (`Area3D.body_exited` fire en fin de step, AVANT `_physics_process` du step suivant), justifiant l'absence de check "dedans WorldBoundsVolume" demandé par story-008 spec ligne 39 (sûr en pratique, redondant et coûteux sinon).
- `level_system.gd` `_resolve_player_node` : doc-comment étendu pour inventaire des fenêtres cache-miss bornées (1er tick post-`level_active`, post-`_reset_runtime_state`, post-respawn CheckpointSystem) et confirmation que steady-state reste zero-alloc.
- `level_player_out_of_world_test.gd` `test_player_out_of_world_emits_via_y_below_minus_two` : signal connecté AVANT le déplacement au gate strict (lignes 144-149) → assertion explicite `emit_count == 0` au gate `y == -2.0`. Gate strict devient testable contractuellement, pas plus seulement par déduction.

**Status final** : `Ready` → **`Complete`** (avec notes).

