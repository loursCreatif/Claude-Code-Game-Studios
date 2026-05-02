# Story 017: ShapeCast microbench p99 ≤5ms

> **Epic**: Player Combat System
> **Status**: Done
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-35a (microbench `_collect_swing_hits()` complet, p99 ≤ 5 ms Tier 1)

**ADR Governing Implementation**: ADR-0006 + ADR-0001
**ADR Decision Summary**: Microbench isolé `tests/perf/combat-shapecast-microbench.gd` mesure `_collect_swing_hits()` COMPLET (union `_tick0_intersect_shape_overlap()` + `force_shapecast_update()` 3 substeps) sur 1000 samples (60 warmup ignorés). Seuil refus `p99 > 5 ms` Tier 1 Minimum Supporté (`docs/architecture/hardware-spec-testbeds.md`).

**Engine**: Godot 4.6 + Jolt | **Risk**: MEDIUM
**Engine Notes**: `Time.get_ticks_usec()` recommandé (pas Godot Profiler — résolution ~10 ms + overhead 1-3 ms). Jolt Performance peut différer GodotPhysics3D — bench post-cutoff requis.

**Control Manifest Rules (Feature layer)**:
- Required: bench mesure `_collect_swing_hits()` COMPLET, pas juste 3 substeps isolés (r6 P-1 fix)
- Forbidden: utiliser Godot Profiler pour mesure (overhead trop haut)
- Guardrail: hardware testbed = Tier 1 Minimum Supporté (cf. `hardware-spec-testbeds.md`)

---

## Acceptance Criteria

*From GDD AC-CMB-35a + r6 P-1 fix :*

- [ ] **AC-CMB-35a setup** : scène minimale `tests/perf/combat-shapecast-microbench.gd` avec ShapeCast3D (CapsuleShape3D radius=0.45 height=1.8), 10 MockEnemies aléatoirement dans volume 5×5×5 m, Jolt physics actif
- [ ] **Mesure** : `_collect_swing_hits()` COMPLET exécuté (union `_tick0_intersect_shape_overlap()` au tick 0 — `PhysicsShapeQueryParameters3D.new()` + `intersect_shape()` + dedup Dictionary, PLUS `force_shapecast_update()` + itération `get_collision_count()` à tous les ticks 0-7) ; mesuré via `Time.get_ticks_usec()` autour du bloc complet
- [ ] **Warmup 60 samples** = 60 swings complets (pas 60 casts isolés) — assure p99 capture worst case tick-0
- [ ] **1000 samples** post-warmup ; calcul p50, p99 ; loggé dans `tests/perf/combat-shapecast-microbench-log.md`
- [ ] **Seuil refus** : `p99 > 5 ms` sur Tier 1 (docs/architecture/hardware-spec-testbeds.md) → AC fail
- [ ] **Justification** : 5 ms = ~30% du frame budget 16.6 ms ; ShapeCast doit tenir dans sa part ; 11.6 ms reste pour Movement, Camera, VFX, Audio, rendering
- [ ] Log inclut : hardware tier (Tier 1 / 2 / 3 si bench multi-tier), Godot version pinned (4.6), Jolt version, commit SHA, p50, p99

---

## Implementation Notes

*Derived from ADR-0006 + GDD r6 P-1 :*

```gdscript
# tests/perf/combat-shapecast-microbench.gd
extends Node3D

const N_SAMPLES: int = 1000
const N_WARMUP: int = 60
const N_ENEMIES: int = 10

var _samples: PackedInt64Array = PackedInt64Array()

func _ready() -> void:
    # Setup : 10 MockEnemies positionnés aléatoirement dans 5x5x5 m
    var rng := RandomNumberGenerator.new()
    rng.seed = 12345  # déterministe
    for i in N_ENEMIES:
        var enemy := MockEnemy.new()
        enemy.global_position = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0, 5), rng.randf_range(-2.5, 2.5))
        add_child(enemy)
    var combat := CombatSystem.new()
    add_child(combat)
    # Warmup : 60 swings complets
    for i in N_WARMUP:
        combat._collect_swing_hits()  # ignore
    # Sampling
    for i in N_SAMPLES:
        var t0 := Time.get_ticks_usec()
        combat._collect_swing_hits()
        var t1 := Time.get_ticks_usec()
        _samples.append(t1 - t0)
    _samples.sort()
    var p50 := _samples[int(N_SAMPLES * 0.5)] / 1000.0
    var p99 := _samples[int(N_SAMPLES * 0.99)] / 1000.0
    var log_path := "tests/perf/combat-shapecast-microbench-log.md"
    # Append entry: date, godot version, jolt version, commit, p50, p99
    print("p50=%.3f ms p99=%.3f ms" % [p50, p99])
    if p99 > 5.0:
        push_error("Microbench AC-CMB-35a FAIL: p99=%.3f ms > 5 ms threshold" % p99)
        get_tree().quit(1)
```

- Run command : `godot --headless --script tests/perf/combat-shapecast-microbench.gd`
- Hardware spec : `docs/architecture/hardware-spec-testbeds.md` Tier 1

---

## Out of Scope

- Story 018 : intégration soak (frametime global + memory + object count) — bench plus large
- VFX / decals (AC-CMB-42) : bench séparé BLOCKED VFX System

---

## QA Test Cases

- **AC-1** Microbench script exists and runs
  - Given: `tests/perf/combat-shapecast-microbench.gd`
  - When: `godot --headless --script tests/perf/combat-shapecast-microbench.gd` exécuté
  - Then: exit code 0, log fichier généré
  - Edge cases: exit code 1 si p99 > 5 ms

- **AC-2** Sample count
  - Given: bench script run complet
  - When: log lu
  - Then: 1000 samples post-warmup (60 warmup ignorés)
  - Edge cases: bench interrompu — log incomplet, AC fail

- **AC-3** Tier 1 hardware compliance
  - Given: bench run sur Tier 1 testbed
  - When: log entry généré
  - Then: contient mention "Tier 1 Minimum Supporté", references `hardware-spec-testbeds.md`
  - Edge cases: Tier 2 run noté (info) mais pas critère gate

- **AC-4** p99 threshold
  - Given: bench complet
  - When: p99 calculé
  - Then: `p99 ≤ 5.0 ms`
  - Edge cases: p99 = 5.001 ms — fail strict ; p99 = 4.999 ms — pass

- **AC-5** Log entry format
  - Given: log file `combat-shapecast-microbench-log.md`
  - When: dernière entry lue
  - Then: contient timestamp, godot version (4.6), jolt version, commit SHA, p50, p99, hardware tier
  - Edge cases: champs manquants — AC fail

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/perf/combat-shapecast-microbench.gd` (script) + `tests/perf/combat-shapecast-microbench-log.md` (log entries)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 005-012 (full sweep + kill resolution implémentés), `hardware-spec-testbeds.md` (existe r3 technical-director)
- Unlocks: Story 018 (soak integration), Sprint 1 sign-off
