# Story 011: Performance F-MNU-1 — Pause/Resume Headless P95+P99 < 100 ms

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `F-MNU-1` (pause_perceived_ms = T_in + T_gsm + T_def + T_ren ∈ [16.6, 50.8] ms ; cible Pillar 1 < 100 ms)

**ADR Governing Implementation**: ADR-0001 60 Hz physics + frame budget 16.6 ms ; ADR-0007 D-9 pull pattern (synchrone côté GSM `_state` mutation) ; ADR-0004 D-3 InputManager swap pattern T_in ≤ 1 tick.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Time.get_ticks_msec()` stable. `Performance.get_monitor(Performance.MEMORY_STATIC)` stable. CI headless via `godot --headless --script tests/gut_runner.gd`. xvfb pour rendu actif (CI Linux).

**Control Manifest Rules (Presentation layer)**:
- Required : Pause snap < 100 ms total (Pillar 1 budget).
- Performance Guardrail : Frame budget 16.6 ms ; pause/resume cycle ne doit pas spike > 1 frame.

---

## Acceptance Criteria

- [ ] **AC-MNU-40** [Performance — BLOCKING] *(r2)* : GSM=PLAYING ; `ui_cancel_pressed` émis 60 fois consécutives (reset PAUSED→PLAYING entre, 1 s wait stabilisation) ; latence `[input emit] → [pause_layer.visible == true]` mesurée — **P95 < 100 ms ET P99 < 100 ms ET max < 100 ms**. Stratégie : composé `T_in + T_gsm + T_def` (exclut `T_ren` non observable headless).
- [ ] **AC-MNU-41** [Performance — BLOCKING] *(r2)* : GSM=PAUSED ; `ui_cancel_pressed` 60 cycles ; latence resume P95 < 100 ms ET P99 < 100 ms ET max < 100 ms.
- [ ] **AC-MNU-42** [Performance — ADVISORY] *(r2)* : (a) 10 cycles warmup ignorés (Theme cache, font preload, signal table) puis (b) 100 cycles mesurés ; `delta_memory_bytes = MEMORY_STATIC_after_100 − MEMORY_STATIC_after_warmup < 64 KB`.
- [ ] **AC-MNU-43** [Performance — ADVISORY] : transition PAUSED → PLAYING (snap sans tween) ; aucun frame skip — `Performance.TIME_PROCESS` < 16.6 ms pendant transition.
- [ ] **AC-MNU-65** [Performance — ADVISORY] *(r2)* : build avec rendu actif (CI xvfb ou local desktop) ; latence complète `[input emit] → [pause_layer.visible == true rendered on screen]` capture via `RenderingServer.frame_post_draw` ; P95 < 100 ms ET max < 100 ms.

---

## Implementation Notes

*Derived from F-MNU-1 r2 + AC-MNU-40..43/65 :*

1. Créer `tests/performance/menu/pause_resume_perf_test.gd` (GUT test runner Godot headless) :
   ```gdscript
   extends GutTest

   var _latencies_pause_ms: PackedFloat32Array
   var _latencies_resume_ms: PackedFloat32Array

   func before_all() -> void:
       _latencies_pause_ms = PackedFloat32Array()
       _latencies_pause_ms.resize(60)
       _latencies_resume_ms = PackedFloat32Array()
       _latencies_resume_ms.resize(60)

   func test_pause_latency_p95_p99_max_under_100ms() -> void:
       MockGSM._state = GameStateManager.State.PLAYING
       for i in range(60):
           var t0_ms := Time.get_ticks_msec()
           MockInputManager.ui_cancel_pressed.emit()
           await get_tree().process_frame  # CONNECT_DEFERRED 1-frame
           assert_true(pause_layer.visible)
           var t1_ms := Time.get_ticks_msec()
           _latencies_pause_ms[i] = float(t1_ms - t0_ms)
           # reset PAUSED → PLAYING entre
           MockGSM.request_resume()
           await get_tree().process_frame
           OS.delay_msec(1000)  # stabilisation 1 s
       var p95 := _quantile(_latencies_pause_ms, 0.95)
       var p99 := _quantile(_latencies_pause_ms, 0.99)
       var max_ms := _max(_latencies_pause_ms)
       assert_true(p95 < 100.0 and p99 < 100.0 and max_ms < 100.0,
           "Pause latency: P95=%.2f P99=%.2f max=%.2f" % [p95, p99, max_ms])

   func test_resume_latency_p95_p99_max_under_100ms() -> void:
       # Symétrique — GSM=PAUSED, mesure latence vers visible == false
       ...
   ```
2. **AC-MNU-42 zero-alloc warmup baseline** :
   ```gdscript
   func test_pause_overlay_zero_alloc_after_warmup() -> void:
       # 10 cycles warmup (ignorés)
       for i in range(10):
           _do_pause_resume_cycle()
       var baseline_bytes := Performance.get_monitor(Performance.MEMORY_STATIC)
       # 100 cycles mesurés
       for i in range(100):
           _do_pause_resume_cycle()
       var after_bytes := Performance.get_monitor(Performance.MEMORY_STATIC)
       var delta := after_bytes - baseline_bytes
       assert_true(delta < 65536, "MEMORY_STATIC delta=%d > 64KB" % delta)
   ```
3. **AC-MNU-43** : capturer `Performance.get_monitor(Performance.TIME_PROCESS)` immédiatement après `_apply_visibility(false, true)` ; assertion < 16.6 ms.
4. **AC-MNU-65 ADVISORY xvfb rendu actif** : test séparé `tests/performance/menu/pause_resume_rendered_test.gd` qui se connecte à `RenderingServer.frame_post_draw` pour capturer le timestamp post-rendu :
   ```gdscript
   var _t_input_ms: int
   var _t_rendered_ms: int

   func _on_frame_post_draw() -> void:
       _t_rendered_ms = Time.get_ticks_msec()

   func test_e2e_latency_with_render() -> void:
       RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
       _t_input_ms = Time.get_ticks_msec()
       MockInputManager.ui_cancel_pressed.emit()
       await get_tree().process_frame
       await get_tree().process_frame  # 2 frames pour CONNECT_DEFERRED + render
       var latency_ms := _t_rendered_ms - _t_input_ms
       assert_true(latency_ms < 100, "E2E render latency=%d ms" % latency_ms)
   ```
   CI : utiliser xvfb-run (Linux) — runner job `perf-menu-rendered`.
5. **CI integration** : ajouter job `perf-menu-pause-resume` dans `.github/workflows/tests.yml` qui execute `godot --headless --script tests/performance/menu/pause_resume_perf_runner.gd`. Fail si AC-MNU-40/41/42 fail.

---

## Out of Scope

- Stories 001-009 : implémentation menu code (cette story bench le résultat).
- Story 010 : lints anti-patterns (cette story consomme un menu déjà conforme).
- Test nominal pause/resume (Story 003/004/005 livrent les tests Logic/Integration).

---

## QA Test Cases

**AC-MNU-40** : pause latency 60 runs P95/P99/max
- Given : MockGSM `_state = PLAYING`, MockInputManager initialisé.
- When : 60 cycles `ui_cancel_pressed.emit()` → wait visible == true → reset PLAYING → 1 s.
- Then : `_quantile(latencies, 0.95) < 100 AND _quantile(latencies, 0.99) < 100 AND max(latencies) < 100`.
- Edge cases : Godot debug interpreter ajoute overhead ~3-5 ms ; budget 100 ms reste safe.

**AC-MNU-41** : resume latency symétrique
- Given : MockGSM `_state = PAUSED`, Pause Overlay visible.
- When : 60 cycles ; mesure `[input emit] → [visible == false]`.
- Then : P95/P99/max < 100 ms.

**AC-MNU-42** : delta memory < 64 KB
- Given : warmup 10 cycles (Theme cache settle).
- When : baseline MEMORY_STATIC capturé puis 100 cycles puis after MEMORY_STATIC.
- Then : `delta < 65536`.
- Edge cases : si premier cycle alloue 12 KB Theme cache (hot reload), warmup absorbe.

**AC-MNU-43** : pas de frame skip resume
- Given : Pause Overlay visible.
- When : `_apply_visibility(false, true)` exécuté.
- Then : `Performance.TIME_PROCESS` capturé immédiatement < 16.6 ms.

**AC-MNU-65** [Performance ADVISORY rendu actif] :
- Setup : xvfb-run sur CI Linux OU exécution local desktop.
- Verify : `[input emit] → frame_post_draw` capturé ; latence < 100 ms P95 + max.
- Pass condition : ADVISORY — fail = monitor, pas blocker MVP. Évidence rendu actif documentée `production/qa/evidence/perf-menu-rendered-[date].md`.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/performance/menu/pause_resume_perf_test.gd` (AC-MNU-40/41/42/43 — headless GUT, BLOCKING gates)
- `tests/performance/menu/pause_resume_rendered_test.gd` (AC-MNU-65 ADVISORY xvfb)
- CI workflow job `perf-menu-pause-resume` ajouté + green run.
- Evidence : `production/qa/evidence/perf-menu-baseline-[date].md` (latencies P95/P99/max + delta memory bytes).

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Stories 002, 003, 004, 005, 008 (pipeline pause/resume complet livré pour bench).
- Unlocks : Story 013 (playtest peut citer perf baseline pour décider Pillar 1 sign-off creative-director).
