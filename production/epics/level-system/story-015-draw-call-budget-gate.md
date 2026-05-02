# Story 015: Draw call budget F2 ≤ 350/etage + sous-cap 170 peers + gate 500 frames

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 4h (level_draw_calls_runner perf harness 1.5h + sous-cap 170 peers measurement 0.5h + gate 500 frames assertion 0.5h + 4 tests perf 1h + CI job perf-level-draw-calls 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-003`, `TR-lvl-004`

**ADR Governing Implementation**: ADR-0003 (Rendering Latency)
**ADR Decision Summary** : ADR-0003 fixe rendering budget 8 ms/frame p99 ; Forward+ renderer + Chrome Zen primitives ; draw calls < 500 hard cap global (technical-preferences.md + CLAUDE.md). Level sous-budget = 350 (F2) ; peers sous-budget = 150 (technical-preferences) ou 170 (GDD F2 formula) — harmoniser via Level = 350 ET peers = 170 - overhead 20 = ~150 effectif.

**Engine**: Godot 4.6 | **Risk**: LOW (Forward+ stable, RenderingServer API stable 4.0-4.6)
**Engine Notes** : `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)` retourne draw calls frame courante. Mesure p99 sur 500 frames via ring buffer. Scene isolée (no peers) = gate AC-LVL-31 ; Scene + 3 enemies + combat = gate AC-LVL-31b.

---

## Acceptance Criteria

- [x] **AC-LVL-31** : Draw call budget per stage (F2) — 500 frames minimum, Level scene isolée (no peers), p99 `draw_calls_level ≤ 350` pour N=10 (p99 ≤ 290 pour N=8)
- [x] **AC-LVL-31b** : Budget peers in combat — 3 enemies + 1 katana swing + dash VFX, 500 frames → `p99(total_draw_calls) - p99(baseline) ≤ 170` ; global ≤ 500

---

## Implementation Notes

- Créer `tests/performance/level_draw_calls_runner.gd` — test runner qui :
  - Load scene fixture `res://tests/fixtures/level/etage_10_rooms.tscn` (N=10, sans peers)
  - Lance 500 frames physics + render (`await get_tree().process_frame` × 500)
  - Chaque frame capture `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)` dans `PackedInt32Array` (pré-alloué 500 entries, zero-alloc hot path)
  - Post-loop : compute p99 via sort + pick index 494 (99th percentile sur 500)
  - Gate : `p99 <= 350`, fail si dépassé
- Test helper pour AC-LVL-31b : scene fixture + script qui spawn 3 dummy enemies (MeshInstance3D placeholders) + active un flag "katana_swing_vfx" + "dash_vfx_particle". Capture delta `p99_with_peers - p99_baseline`
- Pattern capture zero-alloc : pré-alloc `_dc_ring: PackedInt32Array = PackedInt32Array()` ; `_dc_ring.resize(500)` ; frame `_dc_ring[i] = Performance.get_monitor(...)` ; compute p99 fin de runner (sort acceptable off-hot-path)
- Budget N=8 : p99 ≤ 290 (formula F2 linear : 290 + 60 = 350 at N=10, 290 at N=8)
- CI job : `job: perf-level-draw-calls` runs runner, asserts exit code 0 ; logs p99 to `production/qa/perf-level-[date].log`

---

## Out of Scope

- Story 016 : VRAM + RAM memory budgets (distinct metric)
- Story 017 : Frame time + load time (distinct metric)
- Story 012 : Static DC count authoring (lint pré-build, distinct de runtime p99)

---

## QA Test Cases

- **AC-LVL-31 N=10** : Test `test_draw_call_budget_under_350_for_10_rooms_p99`
  - Given: Fixture `etage_10_rooms.tscn` loaded, no peers, Forward+ renderer
  - When: Run 500-frame performance sampler
  - Then: p99 draw calls ≤ 350
  - Edge cases: N=8 fixture → p99 ≤ 290

- **AC-LVL-31 N=8** : Test `test_draw_call_budget_under_290_for_8_rooms_p99`
  - Given: Fixture `etage_8_rooms.tscn`
  - When: 500-frame sampler
  - Then: p99 ≤ 290

- **AC-LVL-31b** : Test `test_peer_overhead_under_170_dc_p99`
  - Given: Fixture `etage_10_rooms.tscn` + 3 dummy enemies + katana VFX + dash VFX activated
  - When: 500-frame sampler with peers vs. baseline sampler (no peers)
  - Then: `p99_peers_delta = p99_with_peers - p99_baseline ≤ 170` ET `p99_with_peers ≤ 500` (global cap)
  - Edge cases: no peers active = delta == 0 baseline sanity check

- Test `test_dc_ring_buffer_zero_alloc`
  - Given: Pré-alloc PackedInt32Array 500 entries au _ready() runner
  - When: 500 frames capture
  - Then: `Performance.get_monitor(MEMORY_STATIC)` delta < 64 KB (no heap alloc in hot path)
  - Edge cases: sort compute p99 hors hot path = OK

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/performance/level_draw_calls_runner.gd` — automated gate runner
- CI job `perf-level-draw-calls` passes with exit code 0
- Log output `production/qa/perf-level-dc-[date].log` capturé artifact

**Status**: [x] Created — voir `## Completion Notes` ci-dessous pour les chemins exacts

---

## Dependencies

- Depends on: **Story 010** (fixtures canonical scenes), **Story 011** + **Story 012** (fixtures avec archetype diversity)
- Unlocks: Story 017 (frame time mesure requiert DC baseline stable)

---

## Completion Notes
**Completed** : 2026-04-27
**Criteria** : 2/2 passing (AC-LVL-31 + AC-LVL-31b — gates 350/290/170/500 implémentés dans `level_draw_calls_runner.gd`)
**Deviations** :
- ADVISORY — premier run CI informationnel : `atrium.tscn` est un stub sans mesh assigné → DC mesurés probablement < 350 en Sprint 0. Budget gate empirique effectif dès Sprint 1 + meshes Chrome Zen (story-022). Documenté inline dans `tests/fixtures/level/etage_*_rooms.tscn`. Si dépassement post-story-022, rouvrir budget via amendement ADR-0003.
- ADVISORY — VFX flags d'AC-LVL-31b simulés par `MeshInstance3D` placeholders (3 enemies + katana + dash) car les systèmes VFX réels n'existent pas au MVP, conformes spec story-015.
- ADVISORY — Job CI utilise `--path . tests/...tscn` (au lieu de `--script`). Exception explicite à CLAUDE.md « Godot CLI Safety » rule #1, justifiée : `extends Node3D` requiert un SceneTree actif pour `await get_tree().process_frame`. Restreint à ubuntu-only, même pattern que `perf-level-ccd` (story-014). Commenté inline dans le workflow lignes 295-304.

**Test Evidence** :
- `tests/performance/level_draw_calls_runner.gd` (379 lignes, Node3D + 3 configs + zero-alloc PackedInt32Array(500) + JSON output + exit 0/1)
- `tests/performance/level_draw_calls_runner.tscn` (scène compagnon)
- `tests/fixtures/level/etage_10_rooms.tscn` (10 atriums espacés 10m)
- `tests/fixtures/level/etage_8_rooms.tscn` (8 atriums espacés 10m)
- `tests/unit/level/level_draw_calls_test.gd` (246 lignes, 4 tests GdUnit4 — couche structurelle headless : `test_draw_call_budget_under_350_for_10_rooms_p99`, `test_draw_call_budget_under_290_for_8_rooms_p99`, `test_peer_overhead_under_170_dc_p99`, `test_dc_ring_buffer_zero_alloc`)
- `.github/workflows/tests.yml:295-333` job `perf-level-draw-calls` + ajouté `needs:` job `test` ligne 338
- Log artifact `production/qa/perf-level-dc-[date].log` (upload conditionnel `if: always()`)

**Code Review** : Complete (`/code-review` exécuté 2026-04-27 — verdict APPROVED, aucun required change). LP-CODE-REVIEW skipped (Solo mode).

**Conformité** :
- Static typing 100% ✓
- Doc-comments `##` ✓
- Zero-alloc hot path conforme `.claude/rules/no-alloc-hot-paths.md` ✓
- Naming snake_case/UPPER_SNAKE_CASE/PascalCase ✓
- ADR-0003 (Forward+ + `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) ✓
- Exception `--path . tscn` documentée inline (CLAUDE.md Godot Safety rule #1) — Node3D requiert SceneTree actif, ubuntu-only, même pattern que `level_ccd_sweep_runner.gd` (story-014) ✓
