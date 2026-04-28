# Story 006: Performance benchmark N=100 (multi-kill + hydrate)

> **Epic**: Credit Economy System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Performance
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: AC-CRD-39 (perf multi-kill tick `< 1 ms médiane N=100`, BLOCKING dev / ADVISORY CI — r3 NB-CRD-5 reformulé), AC-CRD-40 (perf boot hydrate `< 2 ms`).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe AC GDD r3.)*

**ADR Governing Implementation**:
- ADR-0001: Physics Rate 60Hz — frame budget 16.6 ms (60 fps lock). Credit ne doit pas dépasser 6% du budget en pire cas P95 (1 ms = 6%).

**ADR Decision Summary**: Credit Economy doit traiter 3 kills simultanés (`MAX_KILLS_PER_SWING = 3`) + 1 emit batché en `< 1 ms médiane N=100` sur hardware target dev (entry-level gaming laptop), et hydrater le boot en `< 2 ms` (lecture ConfigFile + assign + emit signal). Gate r3 NB-CRD-5 : BLOCKING sur dev local, ADVISORY sur CI (variance plateforme partagée tolérée).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Time.get_ticks_usec()` est l'API standard pour benchmarks micro Godot 4.6. GdUnit4 supporte les benchmarks N-iteration via fixtures custom (pas de framework benchmark intégré — itérer manuellement dans une test fonction). Variance CI (GitHub Actions runner partagé) peut atteindre ±2-5 ms — d'où le double-gate r3 BLOCKING dev / ADVISORY CI.

**Control Manifest Rules (Feature layer)**:
- Required: benchmark utilise `Time.get_ticks_usec()` autour du bloc handler complet (3 increments + 1 emit) ; calculer médiane + P95 + max sur N=100 itérations ; reporter résultats dans output test (pour audit CI).
- Forbidden: utiliser `print_debug` dans le hot path benchmark (pollue la mesure) ; mesurer une seule itération (variance ±20% jusqu'à N=20-30, médiane fiable à partir de N=100).
- Guardrail: warmup 10 itérations avant la mesure pour éviter le coût d'amorçage JIT/cache (pattern standard benchmark Godot).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (Performance gate hardware-target) :*

- [ ] AC-CRD-39 [Performance] (r3 NB-CRD-5) — multi-kill 3 + `BATCH_MULTI_KILL_EMIT == true`, mesure N=100 itérations : (a) **médiane** `< 1 ms`, (b) **P95** `< 3 ms`, (c) outliers `> 3 ms` exclus si plateforme non-reproductible. **Gate** : BLOCKING dev / ADVISORY CI (loggué dans rapport sans bloquer merge si variance CI).
- [ ] AC-CRD-40 [Performance] — boot hydrate (lecture save + assign + emit BOOT_HYDRATE) : `< 2 ms`. Mécanisme : chrono `Time.get_ticks_usec()` avant/après `_hydrate_from_save()`.

---

## Implementation Notes

*Derived from ADR-0001 + GDD AC-CRD-39 r3 + AC-CRD-40 :*

1. **Fichier benchmark** : `tests/performance/credit_economy_benchmark.gd` (extension du dossier `tests/performance/` existant — pattern aligné `level_ccd_sweep_runner.gd` mais via `--script`, pas `--main-scene` — voir CLAUDE.md Godot CLI Safety).
2. **Pattern N-iteration médiane** :
   ```gdscript
   extends GdUnitTestSuite

   const N_ITERATIONS: int = 100
   const N_WARMUP: int = 10

   func test_multi_kill_tick_perf() -> void:
       var credit := load("res://src/core/credit_economy.gd").new()
       # ... setup mock enemies, hydrate, etc.
       var samples: PackedFloat64Array = PackedFloat64Array()
       samples.resize(N_ITERATIONS)

       # Warmup
       for i in N_WARMUP:
           _simulate_multi_kill_tick(credit)

       # Mesure
       for i in N_ITERATIONS:
           var t_start: int = Time.get_ticks_usec()
           _simulate_multi_kill_tick(credit)
           var t_elapsed: int = Time.get_ticks_usec() - t_start
           samples[i] = t_elapsed / 1000.0  # microsecondes → millisecondes

       # Stats
       samples.sort()
       var median_ms: float = samples[N_ITERATIONS / 2]
       var p95_ms: float = samples[int(N_ITERATIONS * 0.95)]
       var max_ms: float = samples[N_ITERATIONS - 1]

       print_rich("[b]Credit multi-kill perf[/b] — median=%.3f ms, p95=%.3f ms, max=%.3f ms" % [median_ms, p95_ms, max_ms])

       assert_float(median_ms).is_less(1.0)  # AC-CRD-39 a — BLOCKING dev
       assert_float(p95_ms).is_less(3.0)  # AC-CRD-39 b — tolérance variance machine
       # AC-CRD-39 c : pas d'assertion sur outliers en CI — log only

   func _simulate_multi_kill_tick(credit: Node) -> void:
       # 3 kills séquentiels + flush physics_process
       for i in 3:
           var fake_enemy := Node.new()
           credit._on_enemy_killed(fake_enemy, Vector3.ZERO)
           fake_enemy.queue_free()
       credit._physics_process(0.016)  # flush batch
   ```

3. **Pattern boot hydrate** :
   ```gdscript
   func test_boot_hydrate_perf() -> void:
       var credit := load("res://src/core/credit_economy.gd").new()
       # SaveLoad mock pré-rempli avec valeur 42
       var t_start: int = Time.get_ticks_usec()
       credit._hydrate_from_save()
       var t_elapsed_ms: float = (Time.get_ticks_usec() - t_start) / 1000.0
       print_rich("Credit boot hydrate — %.3f ms" % t_elapsed_ms)
       assert_float(t_elapsed_ms).is_less(2.0)  # AC-CRD-40
   ```

4. **CI ADVISORY** : si CI runner est marqué non-reproductible (env var `CI_PERFORMANCE_GATE=advisory`), wrapper l'assert dans un `if/else` qui log au lieu de fail :
   ```gdscript
   if OS.has_environment("CI_PERFORMANCE_GATE") and OS.get_environment("CI_PERFORMANCE_GATE") == "advisory":
       if median_ms >= 1.0:
           print_rich("[color=yellow]⚠ ADVISORY[/color] : Credit perf median=%.3f ms exceeds 1ms gate (CI variance tolérée)" % median_ms)
       else:
           assert_float(median_ms).is_less(1.0)
   else:
       assert_float(median_ms).is_less(1.0)  # BLOCKING dev local
   ```
   Configurer `CI_PERFORMANCE_GATE=advisory` dans `.github/workflows/tests.yml` job perf, puis garder dev local sans cette env var pour gate BLOCKING strict.

5. **Invocation safe** : ce benchmark se lance via `godot --headless --script tests/performance/credit_economy_benchmark.gd` (pattern script, pas main-scene — CLAUDE.md Godot CLI Safety).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 002/003/004 : implémentation des handlers (déjà en place avant cette story).
- Soak test long (extended play) — pas pertinent pour Credit Economy MVP, le système est stateless mécaniquement.
- Mémoire / leak detection — Credit est un autoload single-instance, no allocation hot path (Dictionary.clear() est O(1)).

---

## QA Test Cases

- **AC-CRD-39** :
  - Setup : Credit instancié + 3 mock Enemies + hydrate complete (`_is_hydrated = true`, GSM PLAYING).
  - 10 warmup itérations (multi-kill tick simulé) — résultats jetés.
  - 100 itérations mesurées : chaque itération = 3 emits `enemy_killed` + 1 advance `_physics_process`.
  - Stats : median, P95, max.
  - **Pass dev** : median < 1.0 ms ET P95 < 3.0 ms.
  - **Pass CI advisory** : log warning si fail, ne bloque pas (env var `CI_PERFORMANCE_GATE=advisory`).
  - **Edge** : entre 2 itérations, reset `_credited_this_run` pour que les `instance_id` ne s'accumulent pas (sinon biais mémoire Dictionary).

- **AC-CRD-40** :
  - Setup : Credit instancié, SaveLoad mock pré-rempli (`load_int("total_credits", 0)` retourne `42`).
  - 1 mesure : `_hydrate_from_save()` chrono.
  - **Pass** : `< 2.0 ms`.
  - **Edge** : tester avec valeur `0` (default sur absent) — devrait être plus rapide ou égal.

---

## Test Evidence

**Story Type**: Performance
**Required evidence**:
- `tests/performance/credit_economy_benchmark.gd` (AC-39, 40) — must exist, must pass on dev local (BLOCKING), must run on CI (ADVISORY log).
- Output benchmark numbers (médiane, P95, max) loggés dans le rapport CI pour audit historique.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 002** (handler `_on_enemy_killed` + batching), **Story 004** (`_hydrate_from_save()` + state init complet pour benchmark setup réaliste).
- Unlocks: aucune story Credit (gate de fin sprint Performance).
