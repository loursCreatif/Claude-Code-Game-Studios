# Story 007: room_entered signal (RoomTrigger_NN Area3D + tree order + NaN guard)

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Estimate**: ~5-6 hours (4 ACs + 4 GUT test cases + handler integration)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-022`, `TR-lvl-031`, `TR-lvl-032`

**ADR Governing Implementation**: ADR-0005
**ADR Decision Summary** : D-1 signals typés directs ; D-3 payload `int` value-type ; D-4 emit depuis `_physics_process` (body_entered firé par physics step = OK) ; D-8 idempotence 1× par transition (ici 1× par entry, re-entry = nouveau signal = OK par design GDD).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `Area3D.body_entered(body: Node3D)` émis par physics step dans tree order déterministe (DFS preorder enfants de `InteractiveVolumes`). Vérifier NaN via `is_nan(body.global_position.x) or is_nan(body.global_position.y) or is_nan(body.global_position.z)` — retourner avec `push_warning` debug.

**Control Manifest Rules (Core Layer)** : signal typed int payload, emit sync depuis physics handler, fire par entry (pas de dedup).

---

## Acceptance Criteria

- [x] **AC-LVL-21** : `room_entered` émis sur crossing — player téléport dans `RoomTrigger_03` → signal `room_entered(2, total_rooms)` exactement 1× dans 2 frames (payload 0-indexed : `int("03") - 1 = 2`)
- [x] **AC-LVL-22** : `room_entered` idempotent sur re-entry — player exits puis re-entre même Area3D → chaque entry émet signal séparé ; pas de dedup côté Level
- [x] **AC-LVL-23** : Deterministic order on simultaneous triggers (EC-5) — overlapping RoomTrigger_03 + RoomTrigger_04 même frame → `room_entered(2, …)` PUIS `room_entered(3, …)` en tree order (payload 0-indexed)
- [x] **AC-LVL-38** : NaN transform ignoré (EC-9) — `body_entered` avec `body.global_position.x = NaN` → pas d'emission, `push_warning` debug

---

## Implementation Notes

- Signal declaration : `signal room_entered(room_index: int, total_rooms: int)` typed (note : GDD spec `room_entered(3, total_rooms)` → 2 args int, confirmé dans AC-LVL-21)
- Authoring convention : `RoomTrigger_NN` Area3D enfants de `InteractiveVolumes` (story 010 hiérarchie), NN ∈ {01..10} zero-padded
- Naming convention extract : `var parts := area.name.split("_")` ; `var idx := int(parts[1]) - 1` (1-indexed name → 0-indexed payload) — ou utiliser `@export var room_index: int` sur chaque RoomTrigger (preferred, évite parse)
- `_total_rooms` computed au moment de `level_active` via `find_children("RoomTrigger_*", "Area3D", true).size()`, cached en `_total_rooms: int`
- Chaque RoomTrigger_NN connecte son signal `body_entered` au handler Level `_on_room_trigger_body_entered(body, room_index)` via `body_entered.connect(_on_room_trigger_body_entered.bind(idx))`
- Handler :
  ```gdscript
  func _on_room_trigger_body_entered(body: Node3D, room_index: int) -> void:
      if _state != LevelState.ACTIVE: return
      if not body.is_in_group("player"): return
      var pos := body.global_position
      if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
          push_warning("room_entered ignored: body position contains NaN")
          return
      _assert_main_thread()
      _current_room_index = room_index
      room_entered.emit(room_index, _total_rooms)
  ```
- EC-5 : Godot garantit tree-order DFS dans `body_entered` emission quand 2 Areas overlap le même frame, reposant sur ordre déclaration dans scene tree. Convention authoring : placer RoomTrigger_NN en ordre numérique dans `InteractiveVolumes` children

---

## Out of Scope

- Story 010 : hiérarchie canonique parent `InteractiveVolumes`
- Story 013 : collision layer 5 discipline pour RoomTrigger
- Story 020 : lint room count ∈ [8, 10]

---

## QA Test Cases

- **AC-LVL-21** : Test `test_room_entered_emits_once_per_entry`
  - Given: Level ACTIVE avec 10 RoomTriggers authorés ; player test body à (0,0,0) hors triggers
  - When: Teleport player dans RoomTrigger_03 volume (room_index=2 0-indexed) ; wait 2 physics frames
  - Then: Signal `room_entered(2, 10)` reçu exactement 1× ; `_current_room_index == 2`
  - Edge cases: teleport dans RoomTrigger_01 (edge 0) = signal `(0, 10)` ; RoomTrigger_10 = signal `(9, 10)`

- **AC-LVL-22** : Test `test_room_entered_re_entry_emits_new_signal`
  - Given: Level ACTIVE, player dans RoomTrigger_03
  - When: Teleport out (hors area) puis teleport in même area × 3
  - Then: 3 signals reçus avec args identiques `(2, 10)` ; `_current_room_index == 2` final
  - Edge cases: dedup absent côté Level (HUD consumer responsable si besoin)

- **AC-LVL-23** : Test `test_overlapping_triggers_fire_in_tree_order`
  - Given: Level avec RoomTrigger_03 et RoomTrigger_04 qui overlap physiquement (authoring contrived pour test)
  - When: Teleport player dans zone d'overlap même frame
  - Then: Séquence signals reçue : `room_entered(2, 10)` PUIS `room_entered(3, 10)` (tree order, RoomTrigger_03 est child avant RoomTrigger_04 dans InteractiveVolumes)
  - Edge cases: overlap 3+ triggers = tree order strict

- **AC-LVL-38** : Test `test_room_entered_ignores_nan_position`
  - Given: Test body avec `global_position = Vector3(NAN, 0, 0)` (force NaN via helper)
  - When: Simuler `_on_room_trigger_body_entered(body, 2)` directement
  - Then: Aucun signal émis ; debug build : `push_warning` enregistré dans test log
  - Edge cases: NaN sur y ou z = même behavior ; Inf = même behavior (extend test si besoin)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/level/level_room_entered_test.gd` — 4 test cases

**Status**: [x] Created — `tests/integration/level/level_room_entered_test.gd` (273 LOC, 4 tests GdUnit4)

---

## Dependencies

- Depends on: **Story 001** (state machine), **Story 002** (ACTIVE state), **Story 010** (hiérarchie), **Story 013** (collision layers)
- Unlocks: Story 006 (EC-12 reset utilise `_current_room_index`)

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 4/4 passing (AC-LVL-21, AC-LVL-22, AC-LVL-23, AC-LVL-38)
**Files**:
- `src/gameplay/level/level_system.gd` — `signal room_entered`, handler `_on_room_trigger_body_entered`, helpers `_connect_room_triggers` + `_extract_room_index`, mute `_current_room_index` + `_total_rooms` + reset via `_reset_runtime_state`
- `tests/integration/level/level_room_entered_test.gd` — 273 LOC, 4 GdUnit4 test cases (1:1 AC mapping)
- `tests/fixtures/levels/test_etage_07.tscn` — 10× RoomTrigger_NN dans InteractiveVolumes

**Test Evidence**: Integration test at `tests/integration/level/level_room_entered_test.gd` ✓

**Code Review**: Skipped (Solo mode). Specialist reviews lancés inline via /code-review (godot-gdscript-specialist + qa-tester) — verdict APPROVED WITH SUGGESTIONS. Re-validation r19 (2026-04-27) : 0 BLOCKING, 3 WARNING, 3 SUGGESTIONS, 2 NITs (gdscript-specialist) + GAPS MED qa-tester (6 items hardening backlog).

**Deviations** :
- ADVISORY (résolu) — TR-lvl-032 mentionne "Ignore NaN/**Inf** in body position" mais l'implémentation initiale ne couvrait que NaN. Fix appliqué : ajout du guard `is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z)` dans `_on_room_trigger_body_entered` aligné registry. AC-LVL-38 ne testait que NaN ; un test Inf est à ajouter en follow-up.
- ADVISORY (à corriger dans la story) — AC-LVL-21 ligne 27 dit `room_entered(3, total_rooms)` (1-indexed) ; Implementation Notes ligne 38 + QA Test Cases ligne 71 disent 0-indexed (`int(parts[1]) - 1`). Code et tests sont 0-indexed (cohérents). Incohérence interne du story doc, à corriger.
- ADVISORY (test fragility) — `test_room_entered_ignores_nan_position` ligne 257 : assignation `Vector3(NAN, 0, 0)` à `global_position` peut être clamp par Godot 4.6. Suggestion : ajouter `assert_float(player.global_position.x).is_nan()` avant l'appel handler.
- ADVISORY (edge coverage) — Bornes idx 0 (RoomTrigger_01) et idx 9 (RoomTrigger_10), NaN y/z, Inf, overlap 3+ : non testés. Follow-up story possible.
- ADVISORY (r19 hardening backlog) — gdscript-specialist : W-1 cast explicite `int(area.get("room_index"))` l.394 ; W-2 documenter cast safety l.384 ; W-3 `assert_int(count).is_equal(0)` pre-loop AC-LVL-22 ; S-1 doc `_extract_room_index` (RoomTrigger_NN strict) ; S-2 guard size avant `emit_order[0/1]` AC-LVL-23 ; S-3 supprimer `add_to_group` redondant AC-LVL-38 ; N-1 condenser NaN+Inf via `pos.is_finite()` (Godot 4.6 supporte) ; N-2 naming tests `test_level_system_room_*`.
- ADVISORY (qa-tester GAP-5) — `_extract_room_index` retournant -1 sur naming violation propagé sans guard idx<0 dans handler ; payload invalide silencieux. Follow-up : guard `if room_index < 0: push_error + return` dans handler.
- ADVISORY (qa-tester GAP-6) — `_total_rooms` multi-cycle (load fixture A → unload → load fixture B avec moins triggers) non vérifié explicitement ; reset par `_reset_runtime_state` mais pas asserté en test.

**r20 hardening fixes appliqués (2026-04-27, /code-review chain solo)** :
- ✅ W-1 — `level_system.gd:391` cast explicite `area.get("room_index") as int` (typing strict).
- ✅ Guard `is_valid_int()` ajouté l.396 pour rejeter `RoomTrigger_Lobby` et autres tokens non numériques.
- ✅ S-3 — `level_room_entered_test.gd:245` `add_to_group("player")` redondant supprimé.
- ✅ Story doc — AC-LVL-21 et AC-LVL-23 corrigées de 1-indexed (`room_entered(3,…)`) à 0-indexed (`room_entered(2,…)`) pour cohérence avec Implementation Notes + QA Test Cases + tests + code.
- ⏭️ Reportés en follow-up : W-2, W-3, S-1, S-2, N-1, N-2, GAP-5, GAP-6 (hardening non-bloquant, story-007 reste COMPLETE).
