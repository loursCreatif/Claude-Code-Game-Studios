# Story 012: 4 PackedScene primitives + per-archetype R-4 budgets + validate_room_archetype_invariants

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: 6 hours (4 PackedScene primitives 2h + R4_BUDGETS const + helper validate_room_archetype_invariants 2h + 6 fixtures + 6 tests 1.5h + CI runner integration 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: — (budgets R-4 authoring invariants, couvert AC-LVL-55)

**ADR Governing Implementation**: ADR-0011 (Level Scene Architecture — Lint-Gated Authoring Invariants, Accepted 2026-04-23 r3)
**ADR Decision Summary** : D-2 (hiérarchie canonique 4 groupes : InteractiveVolumes, Geometry, Spawns, NavLogic), D-6 (11 invariants pré-build lint-gated via `tools/lint/level_lint.gd`), D-13 (budgets per-archetype enforcement — TRAVERSAL/COMBAT/SHAFT/SECRET_HUB count limits sur DC/StaticBody3D/Area3D/Marker3D, gate par `validate_room_archetype_invariants`).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `PackedScene` instanciable via `scene.instantiate()`. Shader Baker 4.6 (ADR-0003) pré-compile shader unique partagé. Primitives utilisent `BoxShape3D` + `MeshInstance3D` flat shader — pas de mesh importé.

---

## Acceptance Criteria

- [ ] **AC-LVL-55** : Budget perf par archetype (R-4 r2) — pour chaque Room_NN selon archetype, count DC + StaticBody3D + Area3D + Marker3D ≤ budgets :
  - TRAVERSAL : DC ≤ 22, SB3D ≤ 18, Area3D ≤ 4, Marker3D ≤ 10
  - COMBAT : DC ≤ 38, SB3D ≤ 32, Area3D ≤ 10, Marker3D ≤ 30
  - SHAFT : DC ≤ 32, SB3D ≤ 28, Area3D ≤ 6, Marker3D ≤ 18
  - SECRET_HUB : DC ≤ 34, SB3D ≤ 25, Area3D ≤ 12, Marker3D ≤ 24
  - Aggregate : `Σ DC_salle + LEVEL_OVERHEAD ≤ 350` (F2)
  - Violation = lint fail par-salle précisant budget dépassé

---

## Implementation Notes

- Créer 4 PackedScene primitives dans `res://scenes/levels/primitives/` :
  - `mezzanine.tscn` — platform + 2 walls + ledge (3-5 DC / 4-6 Bodies)
  - `atrium.tscn` — void frame + 4 walls + 2 wall-run guides (5-8 DC / 6-10 Bodies)
  - `shaft_connector.tscn` — 2 walls face-to-face wall-run (4-6 DC / 4-6 Bodies)
  - `vertical_shaft_room.tscn` — entire pit chamber ≥8m rise, **mandatory for SHAFT archetype** (8-14 DC / 12-20 Bodies)
- Shader partagé `res://assets/shaders/chrome_zen_flat.gdshader` (authoring story 022)
- Ajouter `validate_room_archetype_invariants(room: Node3D, archetype: int) -> Array[String]` dans `tools/lint/level_lint.gd` :
  ```gdscript
  const R4_BUDGETS := {
      RoomArchetype.Type.TRAVERSAL: {"dc": 22, "sb3d": 18, "area3d": 4, "marker3d": 10},
      RoomArchetype.Type.COMBAT:    {"dc": 38, "sb3d": 32, "area3d": 10, "marker3d": 30},
      RoomArchetype.Type.SHAFT:     {"dc": 32, "sb3d": 28, "area3d": 6, "marker3d": 18},
      RoomArchetype.Type.SECRET_HUB:{"dc": 34, "sb3d": 25, "area3d": 12, "marker3d": 24},
  }
  ```
- Count helpers : `room.find_children("*", "MeshInstance3D", true).size()` pour DC (approximation visible MeshInstance3D — précis car Chrome Zen = 1 MeshInstance3D = 1 DC), `find_children("*", "StaticBody3D", true)`, `find_children("*", "Area3D", true)`, `find_children("*", "Marker3D", true)`
- SHAFT archetype additional check : `room.find_children("*", "", true)` doit contenir ≥1 `VerticalShaftRoom` instance (check par name prefix "VerticalShaftRoom")
- Aggregate check : `Σ dc_per_room + LEVEL_OVERHEAD (= 20 estimated rendering overhead for light probes + WorldBounds area render etc) ≤ 350`
- Runner CI : lint-level-invariants étendu pour tourner sur chaque Room_NN dans fixture etages

---

## Out of Scope

- Story 011 : enum RoomArchetype + @export + diversity
- Story 015 : gate runtime draw calls p99 500 frames (distinct de count static)
- Story 022 : Chrome Zen shader authoring

---

## QA Test Cases

- **AC-LVL-55 TRAVERSAL pass** : Test `test_traversal_room_within_budget`
  - Setup : Fixture `room_traversal_ok.tscn` avec 15 MeshInstance3D, 12 StaticBody3D, 3 Area3D, 8 Marker3D, archetype=TRAVERSAL
  - Verify : `validate_room_archetype_invariants(room, TRAVERSAL)` retourne `[]`

- **AC-LVL-55 TRAVERSAL fail** : Test `test_traversal_room_exceeds_dc_budget`
  - Setup : Fixture avec 25 MeshInstance3D (> 22), archetype=TRAVERSAL
  - Verify : Violation `"Room_01 TRAVERSAL DC=25 exceeds budget 22 (+3)"`

- **AC-LVL-55 COMBAT** : Test `test_combat_room_exceeds_sb3d_budget`
  - Setup : Room COMBAT avec 35 StaticBody3D (> 32)
  - Verify : Violation `"Room_NN COMBAT StaticBody3D=35 exceeds budget 32 (+3)"`

- **AC-LVL-55 SHAFT mandatory primitive** : Test `test_shaft_room_requires_vertical_shaft_room_primitive`
  - Setup : Room SHAFT sans instance VerticalShaftRoom
  - Verify : Violation `"Room_NN SHAFT archetype requires ≥1 VerticalShaftRoom primitive instance"`

- **AC-LVL-55 aggregate** : Test `test_aggregate_dc_exceeds_formula2_cap`
  - Setup : 10 rooms with aggregate DC = 340 (OK) vs 370 (violation)
  - Verify : Pass 340 + 20 overhead = 360 ≤ 350 (FAIL) ET 310 + 20 = 330 (OK)
  - Note: recalibrate test if LEVEL_OVERHEAD differs in final impl

- **AC-LVL-55 budgets per archetype** : Test `test_all_archetype_budget_tables_correct`
  - Verify : R4_BUDGETS dict exact match GDD R-4 r2 Table

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `tests/unit/lint/room_archetype_budget_lint_test.gd` — 6 test cases ; 4 PackedScene primitive fixtures ; CI job étendu

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 011** (RoomArchetype enum) — Complete
- Soft dep: Story 022 (Chrome Zen shader `chrome_zen_flat.gdshader`) — primitives utilisent shader stub si story 022 non livré ; shader réel injecté plus tard sans rework structurel
- Unlocks: Story 015 (draw call runtime gate consomme count static baseline)

---

## Completion Notes

**Completed** : 2026-04-27
**Criteria** : 1/1 passing (AC-LVL-55 fully covered)
**Code Review** : APPROVED WITH SUGGESTIONS (solo mode — LP-CODE-REVIEW skipped)
**Verdict** : COMPLETE WITH NOTES

**Test Evidence (Config/Data — ADVISORY)** :
- `tests/unit/lint/room_archetype_budget_lint_test.gd` — 7 fonctions test, 7 fixtures couvrant pass/fail/boundary
- `tests/fixtures/level/room_archetype_budgets/` — 6 fixtures `.tscn`
- `scenes/levels/primitives/{mezzanine,atrium,shaft_connector,vertical_shaft_room}.tscn` — 4 PackedScene primitives
- `assets/shaders/chrome_zen_flat.gdshader` — stub (soft dep story-022)
- `tools/lint/level_lint.gd` étendu (R4_BUDGETS const, LEVEL_OVERHEAD, AGGREGATE_DC_CAP, validate_room_archetype_invariants) ; `tools/lint/run_level_lint.gd` runner étendu
- Smoke ad-hoc 6/6 fixtures PASS validé localement avant retrait du smoke script

**Deviations** :
- **ADVISORY** : `LEVEL_OVERHEAD = 20` (story-012 + impl) vs GDD R-4 r2 / Formula 2 narrative `LEVEL_OVERHEAD = 50`. Reconcile à propager via `/propagate-design-change` ; impact direct sur calibration aggregate test cases.
- **ADVISORY (corrigé inline)** : header `level_lint.gd` citait `TR-lvl-041` (texture atlas) au lieu de `TR-lvl-004` (DC F2). Fixé pendant /story-done.

**Suggestions code review (non-bloquantes)** :
- Ajouter 2 tests dédiés Area3D + Marker3D dépassement budget (parité avec DC + SB3D existants).
- Extraire un helper `_check_metric_against_budget(...)` pour collapser les 4 blocs de check (cosmétique).

**Code review verdict** : APPROVED WITH SUGGESTIONS — aucun blocker, aucune violation ADR-0011/ADR-0008/standards.
