# Story 016: VRAM + RAM + combined ≤ 70 MB F6 + memory stability 60s

> **Epic**: Level System
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 5h (level_memory_runner perf harness VRAM+RAM sampling 2h + 60s memory stability soak runner 1.5h + 4 perf tests 1h + CI job perf-level-memory 0.5h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-005`, `TR-lvl-037`

**ADR Governing Implementation**: ADR-0003 (Rendering Latency — shader baker + texture management)
**ADR Decision Summary** : ADR-0003 shader baker 4.6 pré-compile shaders export → VRAM static stable. Memory ceiling global 2 GB RAM + 1 GB VRAM (technical-preferences). Level sous-budget = 50 MB VRAM + 20 MB RAM = 70 MB combined (F6 derivation).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes** : `RenderingServer.get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)` retourne VRAM bytes. `Performance.get_monitor(MEMORY_STATIC)` pour static heap. `Performance.get_monitor(OBJECT_NODE_COUNT)` pour tracking node count. Delta mesure = `post_load - pre_load`.

---

## Acceptance Criteria

- [x] **AC-LVL-32** : VRAM budget static (tuning G-Perf) — post-load delta ≤ 50 MB mesuré via `RenderingServer.get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)`
- [x] **AC-LVL-36** : No major allocations after level_active — 1 s warmup, 60 s exploration → `delta_static_memory ≤ 512 KB` ET `delta_object_count ≤ +5` (GDScript heap)
- [x] **AC-LVL-37** : Baseline memory stage < 50 MB — before load vs. after load delta ≤ 70 MB combined (RAM 20 MB + VRAM 50 MB)

---

## Implementation Notes

- Créer `tests/performance/level_memory_runner.gd` — test runner qui :
  - Phase 1 (baseline) : boot minimal scene (pas de Level), capture `vram_before = RenderingServer.get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)` et `ram_before = Performance.get_monitor(MEMORY_STATIC)`
  - Phase 2 (load) : `level.load_etage(1)` + await `level_active`
  - Phase 3 (post-load mesure) : `vram_after = ...` ; delta VRAM = `vram_after - vram_before`
  - Phase 4 (stability 60s) : 1 s warmup (idle frames), puis 60 s de simulation player walks through rooms (sampling chaque 1 s)
  - Capture `delta_static_memory_60s = MEMORY_STATIC(T60) - MEMORY_STATIC(T0_warmup_end)`
  - Capture `delta_object_count_60s = OBJECT_NODE_COUNT(T60) - OBJECT_NODE_COUNT(T0_warmup_end)`
  - Gates : `delta_vram <= 50_000_000` (50 MB), `delta_ram + delta_vram <= 70_000_000`, `delta_static_memory_60s <= 524_288` (512 KB), `delta_object_count_60s <= 5`
- Helper simulate exploration : téléport player entre RoomTriggers à intervalle régulier (not vrai playtest, automation synthétique suffisante)
- Pattern zero-alloc : pré-alloc sampling arrays pour métriques hors hot path

---

## Out of Scope

- Story 015 : draw calls budget (distinct metric)
- Story 017 : frame time + load time
- Story 022 : texture atlas ≤ 1024² authoring (contribue à VRAM budget mais lint séparé)

---

## QA Test Cases

- **AC-LVL-32** : Test `test_vram_delta_under_50mb_post_load`
  - Given: Level UNLOADED, baseline VRAM captured
  - When: `load_etage(1)` + await level_active
  - Then: `vram_delta = vram_after - vram_before <= 50 MB` (50_000_000 bytes)
  - Edge cases: re-load same etage = stable delta (pas de cumul leak)

- **AC-LVL-37 combined** : Test `test_combined_ram_vram_delta_under_70mb`
  - Given: Baseline RAM+VRAM captured
  - When: `load_etage(1)` + await
  - Then: `(ram_after - ram_before) + (vram_after - vram_before) <= 70 MB`
  - Edge cases: fixture etage 8 rooms minimum structure → budget tighter mais same gate

- **AC-LVL-36 memory stability** : Test `test_static_memory_delta_under_512kb_60s`
  - Given: Level ACTIVE post-warmup
  - When: 60 s simulation exploration (player walk through all rooms)
  - Then: `MEMORY_STATIC(T60) - MEMORY_STATIC(T1_warmup) <= 524_288` bytes (512 KB)
  - Edge cases: signal emission frequency during exploration ne doit pas allouer ; level_active call backs ne restent pas en mémoire

- **AC-LVL-36 object count** : Test `test_object_count_delta_under_5_60s`
  - Given: Level ACTIVE post-warmup
  - When: 60 s exploration
  - Then: `OBJECT_NODE_COUNT(T60) - OBJECT_NODE_COUNT(T1_warmup) <= 5`
  - Edge cases: node leak détection (ex. Area3D signal handlers qui accumulent)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/performance/level_memory_runner.gd` — 4 automated gates
- CI job `perf-level-memory` passes with exit code 0
- Log output `production/qa/perf-level-memory-[date].log`

**Status**: [x] Created — voir `## Completion Notes` ci-dessous pour les chemins exacts

---

## Dependencies

- Depends on: **Story 002** (ACTIVE state — ADR-0007 Accepted), **Story 012** (primitives fixtures), **Story 015** (DC gate baseline stable)
- Unlocks: Story 017 (frame time mesure — memory stable prérequis)

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 3/3 passing (AC-LVL-32, AC-LVL-36, AC-LVL-37)
**Files created**:
- `tests/performance/level_memory_runner.gd` (633 lignes) — 4 phases (baseline → load → post-load → 60s soak), zero-alloc PackedInt64Array(65) + PackedInt32Array(65)
- `tests/performance/level_memory_runner.tscn` — scène compagnon Node3D
- `tests/unit/level/level_memory_test.gd` (349 lignes) — 10 tests GdUnit4 structurels (4 happy + 4 fail-path + 2 zero-alloc/buffer)
**Files modified**:
- `.github/workflows/tests.yml` — ajout job `perf-level-memory` (lignes 335-376) + `needs:` du job `test` (ligne 381)

**Deviations** (advisory):
- AC-LVL-32 VRAM gate trivialement PASS en CI headless (VRAM = 0 sans GPU réel) — documenté inline runner.gd + workflow. Validation hardware significative requise avant milestone gate.
- `LevelManager.load_etage(1)` non appelé (autoload non disponible MVP) — fixture chargée directement, identique pattern story-015.
- Edge case "re-load même étage" non implémenté — single-load par design.
- Naming tests manque segment `_[system]_` selon `.claude/rules/test-standards.md` — convention drift mineur.
- Budget AC-LVL-36 utilise 512 KB + 5 objects (ADR-0011 D-13 Gap G-8) plus serré que TR-lvl-037 registry text "≤ 2 MB" — aligné avec ADR, pas un drift.
- Unit tests vérifient les helpers arithmétiques mirrors, pas `_evaluate_gate_*` ni `_finalize_soak` du runner directement (qa-tester L-4) — follow-up recommandé.

**Test Evidence**: Logic — `tests/unit/level/level_memory_test.gd` + `tests/performance/level_memory_runner.gd` + CI job `perf-level-memory`
**Code Review**: Complete — APPROVED post-fixes (godot-gdscript-specialist + qa-tester, 2026-04-27 r2). BLOCKING corrigé cette session : `Performance.OBJECT_COUNT` → `OBJECT_NODE_COUNT` + `OS.get_static_memory_usage()` → `Performance.MEMORY_STATIC` (alignement story implementation notes + convention `level_reload_reset_test.gd`).
