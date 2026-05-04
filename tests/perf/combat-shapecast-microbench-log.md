# Combat ShapeCast Microbench Log

> **Story** : production/epics/combat-system/story-017-shapecast-microbench-p99.md
> **AC** : AC-CMB-35a — `_collect_swing_hits()` p99 ≤ 5 ms (Tier 1 Minimum Supporté)
> **Run command** : `godot --headless --script tests/perf/combat_shapecast_microbench.gd`

Format : 1 entry par run, append-only. Le bench script `combat_shapecast_microbench.gd`
écrit automatiquement les entries en append-end. Ne pas éditer manuellement.

Hardware testbed reference : `docs/architecture/hardware-spec-testbeds.md`

---

## Run 2026-05-04T21:34:09

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.003 ms (threshold ≤ 5.0 ms)
- **max** : 0.003 ms
- **Verdict** : PASS

## Run 2026-05-04T21:35:56

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.005 ms (threshold ≤ 5.0 ms)
- **max** : 0.015 ms
- **Verdict** : PASS

## Run 2026-05-04T21:36:54

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.003 ms (threshold ≤ 5.0 ms)
- **max** : 0.003 ms
- **Verdict** : PASS

## Run 2026-05-04T21:37:48

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Framework** : GdUnit4 v5 (`extends GdUnitTestSuite`)
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.003 ms (threshold ≤ 5.0 ms)
- **max** : 0.003 ms
- **Verdict** : PASS

## Run 2026-05-04T21:39:30

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.003 ms (threshold ≤ 5.0 ms)
- **max** : 0.003 ms
- **Verdict** : PASS

## Run 2026-05-04T21:47:26

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.002 ms
- **p99** : 0.003 ms (threshold ≤ 5.0 ms)
- **max** : 0.003 ms
- **Verdict** : PASS

## Run 2026-05-04T21:48:00

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000 (warmup 60 ignorés)
- **Enemies** : 10 (seed 12345, volume 5.0m³)
- **p50** : 0.003 ms
- **p99** : 0.007 ms (threshold ≤ 5.0 ms)
- **max** : 0.028 ms
- **Verdict** : PASS
