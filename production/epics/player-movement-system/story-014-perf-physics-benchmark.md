# Story 014: Perf physics tick rate + frame budget benchmark

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADRs Governing**: ADR-0001 (VC-1 tick rate stable, VC-2 input→velocity p99, VC-4 physics frame budget), ADR-0005 (VC-8 signal dispatch cumul ≤ 0.1 ms/frame)
**Decision Summary**: Suite de benchmarks Sprint 1 validant les cibles Pillar 1 (≤ 16 ms p99 intra-engine) + Pillar 4 (60 fps locked entry-level laptop, physics ≤ 4 ms/frame p99) + ADR-0005 dispatch cumul amorti ≤ 0.1 ms.

**Engine**: Godot 4.6 | **Risk**: HIGH (VR-1 Shader Baker 4.5+ smoke + VR-2 D3D12 4.6 Windows default frame stability — advisory Sprint 1 CI 3 OS)

**Control Manifest Rules**:
- Required: benchmarks sur hardware référence entry-level laptop ; mesures release build (pas debug interpreter 5-10× plus lent) ; `Performance.TIME_PHYSICS_PROCESS` + `Engine.get_physics_frames()` + profiler Godot.
- Forbidden: bench sur debug build pour claims release ; assertion stricte sur hardware premium (laptop minimum spec = cible).
- Guardrail: CI workflow `tests.yml` inclut ces benchmarks 3 OS (Windows/macOS/Linux) advisory, non-blocker gate Accept mais requis Sprint 1.

---

## Acceptance Criteria

*From GDD AC-MV-50/51 + ADR-0001 VC-1/VC-2/VC-4 + ADR-0005 VC-8 + Feel AC Physics tick rate + Feel AC Fallback 60 Hz + Visual/Audio Critical :*

- [ ] **ADR-0001 VC-1 — Tick rate stable** : `tests/performance/physics_tick_rate_test.gd` — GIVEN debug build, scène test tourne 30 s. THEN `Engine.get_physics_frames()` delta ∈ [1782, 1818] (60×30 ±1%).
- [ ] **ADR-0001 VC-2 — Input→velocity latency p99** : `tests/performance/input_to_velocity_latency_test.gd` — GIVEN 200 dash inputs instrumentés `Time.get_ticks_usec()`. THEN moyenne ≤ 12 ms ET p99 ≤ 16.6 ms release, ≤ 50 ms debug interpreter (gate par `OS.has_feature("debug")`).
- [ ] **ADR-0001 VC-4 — Physics frame budget** : `tests/performance/physics_frame_budget_test.gd` — GIVEN scène MVP + 10 ennemis placeholder physics-simulés. THEN `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)` × 1000 ≤ 4 ms/frame p99.
- [ ] **ADR-0005 VC-8 — Signal dispatch cumul** : `tests/performance/movement_signals_dispatch_bench.gd` — GIVEN scène stress (60 dashs + 60 wall-runs + 60 attacks sur 60 s). THEN coût CPU cumulé signal emits + callbacks sync + deferred queue ≤ 0.1 ms/frame amorti.
- [ ] **AC-MV-50 — Séquence combo physics stable** : scène test `tests/scenes/perf_test_movement.tscn` (10 ennemis NavMeshAgent en patrouille, capabilities toutes actives), séquence course→saut→double-saut→dash→wall-run→wall-jump en boucle 30 s → `Performance.TIME_PROCESS × 1000` p99 ≤ 16.6 ms.
- [ ] **AC-MV-51 — input→dash velocity-set** : 200 inputs `dash` via GUT → p99 (timestamp velocity-set − timestamp input event) ≤ 16 ms.
- [ ] **VR-1 Shader Baker smoke** : premier boot sur `tests/scenes/perf_test_movement.tscn` → cold start ≤ 30 s (compilation cache), warm restart < 3 s (cache valide), zéro hitching visible post-boot. *ADVISORY Sprint 1.*
- [ ] **VR-2 D3D12 Windows frame stability** : CI Windows runner exécute séquence 30 s, aucune frame > 33 ms (2× budget). *ADVISORY Sprint 1.*
- [ ] **Feel AC Fallback 60 Hz** : release build hardware min spec, dash→wall-run→wall-jump 60 s → `Performance.TIME_PROCESS` P90 ≤ 16.6 ms (60 fps min soutenu). *ADVISORY.*

---

## Implementation Notes

*Derived from ADR-0001 Validation Criteria + ADR-0005 VC-8 :*

- Scène benchmark `tests/scenes/perf_test_movement.tscn` :
  - Player complet (Stories 001-013 all-in)
  - Niveau stub géométrique avec 2 murs parallèles (wall-run corridor 3.0 m), plateforme 1.5 m haut, pit 4 m deep
  - 10 ennemis stub : CharacterBody3D + NavigationAgent3D + patrol cycle simple
  - Capabilities toutes à `true` (set_capability debug fixture)
- Tests individuels réutilisent le framework GUT existant (`tests/gdunit4_runner.gd` + MikeSchulze/gdUnit4-action@v1 Godot 4.6 dans `.github/workflows/tests.yml`).
- Pattern benchmark `input_to_velocity_latency_test.gd` :
  ```
  for i in 200:
      var t0 = Time.get_ticks_usec()
      simulate_action_press(&"dash")
      await get_tree().physics_frame
      # dans le tick où velocity.xz == dash_dir * DASH_SPEED
      var t1 = Time.get_ticks_usec()
      samples.append(t1 - t0)
      simulate_action_release(&"dash")
      await get_tree().physics_frame
      # reset cooldown pour next iter
      player._dash_cooldown_timer = 0.0
  samples.sort()
  var p99 = samples[int(199 * 0.99)] / 1000.0  # ms
  assert_lt(p99, 16.6, "AC-MV-51 p99 = %.2f ms" % p99)
  ```
- Pattern `movement_signals_dispatch_bench.gd` :
  ```
  var monitor_start = Time.get_ticks_usec()
  for frame in 3600:  # 60 Hz × 60 s
      if frame % 60 == 0: player.dash_started.emit(Vector3(1,0,0), 30.0)
      if frame % 60 == 30: player.wall_run_entered.emit(Vector3(0,0,1))
      if frame % 60 == 45: player.attacked.emit()
      await get_tree().physics_frame
  var elapsed_us = Time.get_ticks_usec() - monitor_start
  var per_frame_us = elapsed_us / 3600.0
  assert_lt(per_frame_us, 100.0, "VC-8 dispatch cumul p99 = %.2f ms/frame" % (per_frame_us/1000))
  ```
- VR-1/VR-2 : gate CI workflow (Windows/macOS/Linux matrix) ; advisory (non-blocker) mais tracking obligatoire Sprint 1.

---

## Out of Scope

- Combat/AI hot path benchmarks (out of Movement scope)
- Long soak tests > 10 min (post-MVP Polish)
- GPU VRAM measurement (rendering budget = ADR-0003 VC-1, pas Movement)

---

## QA Test Cases

**VC-1 Tick rate** :
- Given : debug build, scène vide + Player
- When : 30s runtime
- Then : `Engine.get_physics_frames()` ∈ [1782, 1818]

**VC-2 Input latency p99** :
- Given : release build (gate debug false)
- When : 200 dash inputs instrumented
- Then : p99 ≤ 16.6 ms, moyenne ≤ 12 ms

**VC-4 Physics budget** :
- Given : scène MVP + 10 ennemis
- When : 10s séquence combo
- Then : `TIME_PHYSICS_PROCESS * 1000` p99 ≤ 4 ms

**VC-8 Signal dispatch** :
- Given : scène stress signals
- When : 60s × (dash + wall-run + attack)
- Then : coût cumul ≤ 0.1 ms/frame amorti

**AC-MV-50 Frame budget combo** :
- Given : scène perf + 10 ennemis + combo loop
- When : 30s
- Then : p99 ≤ 16.6 ms

**VR-1 Shader Baker cold start** :
- Given : cache vide
- When : premier boot scène test
- Then : ≤ 30s ; warm restart < 3s

**VR-2 D3D12 Windows stability** :
- Given : CI Windows runner, D3D12 default 4.6
- When : scène perf 30s
- Then : aucune frame > 33 ms

---

## Test Evidence

**Story Type**: Integration (BLOCKING pour VC-1/VC-2/VC-4 — ADR Validation Criteria)
**Required evidence**:
- `tests/performance/physics_tick_rate_test.gd` (VC-1)
- `tests/performance/input_to_velocity_latency_test.gd` (VC-2 + AC-MV-51)
- `tests/performance/physics_frame_budget_test.gd` (VC-4)
- `tests/performance/movement_signals_dispatch_bench.gd` (VC-8)
- `tests/scenes/perf_test_movement.tscn`
- CI workflow `.github/workflows/tests.yml` 3 OS matrix (Windows/macOS/Linux) — advisory gating

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-013 (all gameplay implemented avant bench)
- Unlocks: Story 016 (combo chain utilise scène perf), Story 017 (playtest valide feel AC)
