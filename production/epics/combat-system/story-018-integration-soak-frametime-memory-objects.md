# Story 018: Integration soak frametime + memory + OBJECT_COUNT

> **Epic**: Player Combat System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-35b (worst case ShapeCast + soak global) + AC-CMB-37 (1000-cycle soak avec MEMORY_STATIC + OBJECT_COUNT)

**ADR Governing Implementation**: ADR-0006 + ADR-0001 + ADR-0003 (rendering Forward+)
**ADR Decision Summary**: 2 mesures distinctes : (1) **Worst case ShapeCast p99** sur 8 ticks actifs d'un swing avec velocity=30 m/s forcée (no env collision) sur N=100 swings consécutifs = 800 samples ; (2) **Soak frametime global** sur 1000 frames consécutifs (idle + swings réguliers, capture cycles GC). Plus AC-CMB-37 : 1000 cycles `Idle→Swinging→Idle` avec MEMORY_STATIC + OBJECT_COUNT delta.

**Engine**: Godot 4.6 + Jolt + Forward+ | **Risk**: MEDIUM
**Engine Notes**: `Performance.MEMORY_STATIC` mesure heap C++ Godot ; `Performance.OBJECT_COUNT` capture fuites GDScript Objects. `Time.get_ticks_usec()` recommended (pas Profiler).

**Control Manifest Rules (Feature layer)**:
- Required: setup separate worst-case ShapeCast (no env collision) vs soak global (env normal)
- Forbidden: utiliser un setup unique 1000 frames velocity=30 (provoque collision env → velocity tombe à 0 → sous-estime worst case, r6 perf BLOCKING #1 fix)
- Guardrail: tolerance memoire +500 KB ; OBJECT_COUNT delta +5

---

## Acceptance Criteria

*From GDD AC-CMB-35b + AC-CMB-37 + r6 fixes :*

- [ ] **AC-CMB-35b mesure (1)** : Worst case ShapeCast p99 — `player.velocity = Vector3(0, 0, -30.0)` forcée par test (no `move_and_slide()`), 100 swings consécutifs Dashing V=30, 800 samples (100×8 ticks actifs), `frame_time p99 ≤ 16.6 ms`
- [ ] **AC-CMB-35b mesure (2)** : Soak frametime global — 1000 frames consécutifs (16.7 sec @ 60 Hz) en conditions normales (idle + swings réguliers N=10), `frame_time p99 ≤ 16.6 ms`, `frame_time p50 ≤ 12.0 ms`, `draw_calls ≤ 500`
- [ ] **AC-CMB-37** : 1000 cycles `Idle → Swinging (8 ticks) → Idle` avec MockEnemy tué chaque swing :
  - (a) `_hit_this_swing.is_empty()` après chaque retour Idle
  - (b) `Engine.time_scale == 1.0` après chaque slow-mo
  - (c) `_cooldown_timer == 0.0` après chaque expiration
  - (d) `Performance.MEMORY_STATIC` après 1000 cycles ≤ avant + 500 KB
  - (e) `Performance.OBJECT_COUNT` après 1000 cycles ≤ avant + 5 objets (détection fuite Nodes/AudioStreamPlayer3D/Arrays)
  - (f) zéro `push_error` ou `push_warning` pendant les 1000 cycles
- [ ] Logs : `tests/perf/combat-integration-frametime-log.md` (colonnes p50, p99, draw_calls_max, hardware tier, **setup type [ShapeCast worst / Soak global]**)
- [ ] Hardware testbed = Tier 1 (`docs/architecture/hardware-spec-testbeds.md`)

---

## Implementation Notes

*Derived from ADR-0006 + GDD AC-CMB-35b r6 fix + AC-CMB-37 r4 P-08 :*

```gdscript
# tests/integration/combat/integration_soak_test.gd
extends Node3D

func test_worst_case_shapecast_p99() -> void:
    # Setup : Player + Combat + Camera + 10 enemies + Jolt + Forward+
    # Force velocity = Vector3(0,0,-30) sans move_and_slide (no env collision)
    var samples: PackedInt64Array
    for swing_i in 100:
        combat._start_swing()
        for tick_i in 8:
            var t0 := Time.get_ticks_usec()
            combat._physics_process(1.0/60.0)
            var t1 := Time.get_ticks_usec()
            samples.append(t1 - t0)
        combat._reset_swing()
    samples.sort()
    var p99 := samples[int(samples.size() * 0.99)] / 1000.0
    assert(p99 <= 16.6, "Worst case ShapeCast p99=%.3f ms > 16.6 ms" % p99)

func test_soak_global_1000_frames() -> void:
    # Conditions normales : idle + 10 swings sur 1000 frames
    var samples: PackedInt64Array
    var draw_calls_max := 0
    for i in 1000:
        var t0 := Time.get_ticks_usec()
        combat._physics_process(1.0/60.0)
        var t1 := Time.get_ticks_usec()
        samples.append(t1 - t0)
        if i % 100 == 0:  # 10 swings totaux
            combat._start_swing()
        var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME) as int
        draw_calls_max = maxi(draw_calls_max, dc)
    samples.sort()
    var p50 := samples[int(samples.size() * 0.5)] / 1000.0
    var p99 := samples[int(samples.size() * 0.99)] / 1000.0
    assert(p50 <= 12.0)
    assert(p99 <= 16.6)
    assert(draw_calls_max <= 500)

func test_soak_1000_cycles_memory_object_count() -> void:
    var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
    var obj_before := Performance.get_monitor(Performance.OBJECT_COUNT)
    for i in 1000:
        combat._start_swing()
        for j in 8:
            combat._physics_process(1.0/60.0)
        # await Idle, kill MockEnemy, etc.
    var mem_delta := Performance.get_monitor(Performance.MEMORY_STATIC) - mem_before
    var obj_delta := Performance.get_monitor(Performance.OBJECT_COUNT) - obj_before
    assert(mem_delta <= 500_000, "Memory leak %d KB" % (mem_delta / 1024))
    assert(obj_delta <= 5, "Object leak %d objects" % obj_delta)
```

---

## Out of Scope

- Microbench isolé (story-017)
- VFX decal cap soak (AC-CMB-42 BLOCKED VFX System)

---

## QA Test Cases

- **AC-1** Worst case ShapeCast p99
  - Given: setup velocity=30 forcée, 100 swings × 8 ticks
  - When: 800 samples mesurés
  - Then: p99 ≤ 16.6 ms
  - Edge cases: bench Tier 2 hardware — info only, gate Tier 1

- **AC-2** Soak global 1000 frames
  - Given: setup conditions normales (idle + 10 swings sur 1000 frames)
  - When: 1000 samples + draw_calls per frame
  - Then: p50 ≤ 12.0 ms, p99 ≤ 16.6 ms, draw_calls_max ≤ 500
  - Edge cases: 1 frame spike GC isolé — toléré dans p99 mais pas dans p50

- **AC-3** Memory + Object delta 1000 cycles
  - Given: 1000 cycles Idle→Swinging→Idle avec kill chaque swing
  - When: snapshot MEMORY_STATIC + OBJECT_COUNT avant/après
  - Then: MEMORY_STATIC delta ≤ 500 KB, OBJECT_COUNT delta ≤ 5
  - Edge cases: AudioStreamPlayer3D fuit chaque kill → MEMORY_STATIC peut passer mais OBJECT_COUNT fail (P-08 fix r4)

- **AC-4** Zero warnings/errors
  - Given: 1000 cycles avec capture push_error/push_warning
  - When: bench complet
  - Then: zéro message
  - Edge cases: 1 push_warning du test infra (compteur mismatch) — AC fail

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/combat/integration_soak_test.gd` (3 test methods) + `tests/perf/combat-integration-frametime-log.md`

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 017 (microbench valide), Stories 005-016 implémentées
- Unlocks: Sprint 1 sign-off, gate-check pre-production
