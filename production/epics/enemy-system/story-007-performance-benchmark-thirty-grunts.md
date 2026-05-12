# Story 007: Performance benchmark 30 grunts (frame budget + zero-alloc)

> **Epic**: Enemy System
> **Status**: Complete
> **Layer**: Perf
> **Type**: Perf
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

## Context

**GDD Source**: `design/gdd/enemy-system.md` r2 APPROVED 2026-04-27 (AC-ENM-21 + AC-ENM-22)
**ADRs Governing**: ADR-0001 (frame budget 16.6 ms), ADR-0006 Combat Tick Model (Rule 10 statique)
**Depends on**: story-001 (Grunt foundation set_physics_process(false)), story-002 (Grunt.tscn + LaserCone)

**Scope** : valider que 30 grunts simultanés (worst-case GDD §269 / Level R-2.6 :
8-10 salles × 3 EnemySlot) tiennent les budgets perf MVP :
- Frame time p99 < 16.6 ms (frame budget ADR-0001 partagé Movement + Combat + Level + Audio).
- MEMORY_STATIC delta < 64 KB sur 1000 ticks (extrapolé linéairement) — pas de leak progressif.
- Rule 10 enforced : `set_physics_process(false)` au `_ready()` (no hidden tick budget).

**Approche** : test perf hermetic GdUnit4, pas de runner headless dédié `.tscn` (évite incident
2026-04-27 `--main-scene` stub CLAUDE.md). Spawn 30 Grunt.tscn programmatiquement en grille
6×5 espacée 3 m, mesure delta wall-clock entre `process_frame` consécutifs (200 ticks après
warmup 10 ticks), extrapolation linéaire delta MEMORY_STATIC sur 1000 ticks pour audit
AC-ENM-22.

**Engine**: Godot 4.6 | **Risk**: LOW (test pur — aucune modification src/, mesure passive
30 instances Grunt.tscn déjà livrées story-001/002).

**Control Manifest Rules (Perf layer)** :
- Required : 30 grunts simultanés, LaserCone monitoring=true (worst-case Sprint C playtest).
- Required : `Performance.MEMORY_STATIC` delta extrapolé linéairement vers 1000 ticks pour
  fidélité AC-ENM-22 sans tourner 16.6 s wall-clock dans CI.
- Forbidden : `--main-scene` runner stub `.tscn` (CLAUDE.md Godot CLI Safety, incident 2026-04-27).
- Guardrail : ADVISORY mode si `CI_PERFORMANCE_GATE=advisory` env var (variance runner GitHub).

---

## Acceptance Criteria

- [x] **AC-ENM-21 [Perf]** : GIVEN un étage avec 30 grunts instanciés, WHEN gameplay loop
      tourne ~3.3 s à frame rate test (200 ticks post-warmup), THEN frame time p99 < 16.6 ms
      (frame budget ADR-0001).
- [x] **AC-ENM-22 [Perf]** : GIVEN 30 grunts sur un étage, WHEN process_frame loop sur
      200 ticks (~3.3 s), THEN delta `MEMORY_STATIC` extrapolé linéairement vers 1000 ticks
      reste < 64 KB (no-alloc-hot-paths rule extended).

**Bonus ACs covered** :
- **Rule 10 sanity** : tous les 30 grunts ont `is_physics_processing() == false` post _ready
  (Enemy MVP strictement statique — invalidite préventive d'un budget AC-ENM-21 caché).
- **Setup invariants** : 30 grunts ALIVE post _ready (sanity check fixture).

---

## Implementation Notes

**Files** (NEW tests) :
- `tests/performance/enemy_thirty_grunts_perf_test.gd` — 4 tests AC-ENM-21/22 + 2 sanity bonus.

**Files** (NO src/ change) :
- Aucune modification Grunt.gd / Grunt.tscn / EnemySpawner. Le contrat Rule 10 est déjà
  satisfait en story-001 (`set_physics_process(false)` au `_ready()`).

**Méthodologie mesure** :
- Spawn 30 Grunt.tscn instances en grille 6×5 espacée 3 m (LaserCone range 6 m → couvrage
  partiel adjacents, réaliste worst-case).
- Warmup : 10-20 process_frame avant mesure (stabilise scheduler / physics islands / signal
  table).
- AC-ENM-21 : 200 samples Time.get_ticks_usec() delta entre process_frame consécutifs, sort,
  index `[N*0.99]` = p99.
- AC-ENM-22 : baseline `Performance.MEMORY_STATIC` post-warmup, run 200 ticks, delta
  extrapolé linéairement vers 1000 ticks (`delta * 5`). Si extrap < 64 KB, no leak.

**Pourquoi 200 ticks au lieu de 1000** : 1000 ticks @ 60 Hz nominal = 16.6 s wall-clock par
test, dépasse budget temps GdUnit4 raisonnable (~10 s tot pour suite de 4 tests). 200 ticks
suffit pour détecter un leak progressif (delta non-zéro extrapolé saute le gate immédiatement).
La fidélité AC-ENM-22 est préservée via extrapolation linéaire.

---

## Test Plan

| AC | Test file | Test function | Status |
|----|-----------|---------------|--------|
| AC-ENM-21 | `enemy_thirty_grunts_perf_test.gd` | `test_thirty_grunts_frame_time_p99_under_budget` | ✅ PASS |
| AC-ENM-22 | `enemy_thirty_grunts_perf_test.gd` | `test_thirty_grunts_memory_static_delta_under_64kb_extrapolated` | ✅ PASS |
| Rule 10 sanity | `enemy_thirty_grunts_perf_test.gd` | `test_thirty_grunts_no_physics_process_active_rule_10` | ✅ PASS |
| Setup sanity | `enemy_thirty_grunts_perf_test.gd` | `test_thirty_grunts_setup_invariants` | ✅ PASS |

**Test report** : `reports/report_251` — 4/4 PASSED en 3.083 s.

**Mesures observées (local M-class headless)** :
- AC-ENM-21 : median = 6.860 ms, p99 = 8.654 ms, max = 8.962 ms (gate < 16.6 ms) — **52 % du budget**.
- AC-ENM-22 : delta = 0 B, extrap 1000 ticks = 0 B (gate < 65 536 B) — **zero-leak**.

---

## Definition of Done

- [x] All 2 ACs (AC-ENM-21/22) PASS in automated tests.
- [x] Rule 10 sanity bonus + setup invariants PASS.
- [x] Zero régression on enemy suite (story-001/002/003/005/006 — 46/46 still PASS).
- [x] No `--main-scene` runner stub (CLAUDE.md compliance).
- [x] CI ADVISORY hook préservé (`CI_PERFORMANCE_GATE=advisory` → log warning au lieu de fail).
- [x] Status switched `Ready` → `Complete` (auto-mode solo).

---

## Completion Notes

- **Headroom budget AC-ENM-21** : p99 mesuré = 8.654 ms = **52 % du frame budget**. Marge
  confortable pour Movement (~3 ms) + Combat (~2 ms) + Level (~1 ms) + Audio (~1 ms) +
  Render Forward+ (~5-8 ms target). Worst-case combiné target ≤ 16.6 ms reste atteignable.
- **Zero-alloc per-tick** : `delta MEMORY_STATIC = 0 B` sur 200 ticks confirme que Grunt MVP
  ne pollue pas le hot path (Rule 10 enforced via `set_physics_process(false)`). Les seuls
  contributeurs potentiels — LaserCone Area3D collision queries — sont pris en charge par
  PhysicsServer3D natif (pas d'alloc GDScript).
- **Limite test environment** : mesure faite en headless sans render réel. Le frame budget
  réel intègre RenderingServer Forward+. Le test capture le coût Enemy + Physics, pas le
  coût Render. Coverage suffisante pour AC-ENM-21 (Enemy budget cumulé ≤ 0.5 ms est trivial
  puisque Rule 10 = no tick), insuffisante pour validation playtest finale build VS intégré
  (cf OQ-ENM-10 Sprint C playtest).
- **Future story-008 extension** : playtest visual/feel sur build VS intégré pourra ré-utiliser
  ce harness pour mesurer p99 frame avec render Forward+ + 30 grunts + Player actif. La
  méthodologie spawn programmatique reste valable.
- **Couplage runtime↔test** : le test charge `Grunt.tscn` directement (preload via `load`) —
  cohérent avec le contrat EnemySpawner.spawn_for_scene story-003 qui instantiate la même
  PackedScene.

## Next Stories

- **story-004** : Combat sweep + Player laser cross-system tests (Blocked — Combat sweep impl).
- **story-008** : Visual/Feel playtest evidence (UNBLOCKED — story-007 build perf validé,
  prêt pour playtest sur build VS intégré).
