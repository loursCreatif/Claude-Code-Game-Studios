# Combat Integration Frametime Log — story-018 (AC-CMB-35b)

Append-only log des runs `tests/integration/combat/integration_soak_test.gd` —
mesures `_physics_process()` du CombatSystem (combat-only, hors rendering).

**Threshold AC-CMB-35b** :
- Worst case ShapeCast p99 ≤ 16.6 ms (frame budget 60 fps)
- Soak global p50 ≤ 12.0 ms / p99 ≤ 16.6 ms

**Note Tier 1** : tous les runs ci-dessous sont des **INFORMATIONAL BASELINE** sur
dev laptop. Sign-off Tier 1 official (`docs/architecture/hardware-spec-testbeds.md`)
DEFERRED CI infrastructure dédiée.

**Note draw_calls** : headless RenderingServer absent → `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`
retourne 0. Le gate strict `draw_calls ≤ 500` requiert un bench Godot CLI full stack
sur testbed Tier 1 (DEFERRED).

## Run 2026-05-04T21:45:18 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.020 ms (threshold ≤ 16.6 ms)
- **max** : 0.077 ms
- **Verdict** : PASS

## Run 2026-05-04T21:45:18 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.014 ms (threshold ≤ 16.6 ms)
- **max** : 0.043 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T21:47:08 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.014 ms (threshold ≤ 16.6 ms)
- **max** : 0.046 ms
- **Verdict** : PASS

## Run 2026-05-04T21:47:08 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.013 ms (threshold ≤ 16.6 ms)
- **max** : 0.021 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T21:47:24 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.014 ms (threshold ≤ 16.6 ms)
- **max** : 0.045 ms
- **Verdict** : PASS

## Run 2026-05-04T21:47:24 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.013 ms (threshold ≤ 16.6 ms)
- **max** : 0.049 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T21:48:00 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.018 ms (threshold ≤ 16.6 ms)
- **max** : 0.026 ms
- **Verdict** : PASS

## Run 2026-05-04T21:48:00 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.015 ms (threshold ≤ 16.6 ms)
- **max** : 0.038 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T21:54:25 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.010 ms
- **p99** : 0.012 ms (threshold ≤ 16.6 ms)
- **max** : 0.017 ms
- **Verdict** : PASS

## Run 2026-05-04T21:54:25 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.011 ms (threshold ≤ 16.6 ms)
- **max** : 0.014 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T22:09:18 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.015 ms (threshold ≤ 16.6 ms)
- **max** : 0.023 ms
- **Verdict** : PASS

## Run 2026-05-04T22:09:18 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.011 ms (threshold ≤ 16.6 ms)
- **max** : 0.022 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T22:10:33 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.018 ms (threshold ≤ 16.6 ms)
- **max** : 0.100 ms
- **Verdict** : PASS

## Run 2026-05-04T22:10:33 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.007 ms
- **p99** : 0.014 ms (threshold ≤ 16.6 ms)
- **max** : 0.023 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-04T22:11:10 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.011 ms
- **p99** : 0.034 ms (threshold ≤ 16.6 ms)
- **max** : 0.162 ms
- **Verdict** : PASS

## Run 2026-05-04T22:11:10 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.008 ms
- **p99** : 0.028 ms (threshold ≤ 16.6 ms)
- **max** : 0.069 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-05T07:10:40 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.021 ms
- **p99** : 0.027 ms (threshold ≤ 16.6 ms)
- **max** : 0.081 ms
- **Verdict** : PASS

## Run 2026-05-05T07:10:40 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.032 ms (threshold ≤ 16.6 ms)
- **max** : 0.090 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-05T07:11:22 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.024 ms
- **p99** : 0.119 ms (threshold ≤ 16.6 ms)
- **max** : 0.598 ms
- **Verdict** : PASS

## Run 2026-05-05T07:11:22 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.016 ms
- **p99** : 0.091 ms (threshold ≤ 16.6 ms)
- **max** : 0.473 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-05T09:39:17 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.024 ms
- **p99** : 0.032 ms (threshold ≤ 16.6 ms)
- **max** : 0.103 ms
- **Verdict** : PASS

## Run 2026-05-05T09:39:17 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.021 ms (threshold ≤ 16.6 ms)
- **max** : 0.039 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T19:31:29 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.020 ms
- **p99** : 0.037 ms (threshold ≤ 16.6 ms)
- **max** : 0.056 ms
- **Verdict** : PASS

## Run 2026-05-09T19:31:29 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.031 ms (threshold ≤ 16.6 ms)
- **max** : 0.085 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T19:32:11 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.020 ms
- **p99** : 0.022 ms (threshold ≤ 16.6 ms)
- **max** : 0.038 ms
- **Verdict** : PASS

## Run 2026-05-09T19:32:11 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.022 ms (threshold ≤ 16.6 ms)
- **max** : 0.038 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T19:35:32 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.021 ms
- **p99** : 0.024 ms (threshold ≤ 16.6 ms)
- **max** : 0.038 ms
- **Verdict** : PASS

## Run 2026-05-09T19:35:32 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.022 ms (threshold ≤ 16.6 ms)
- **max** : 0.030 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T20:12:30 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.020 ms
- **p99** : 0.027 ms (threshold ≤ 16.6 ms)
- **max** : 0.057 ms
- **Verdict** : PASS

## Run 2026-05-09T20:12:30 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.023 ms (threshold ≤ 16.6 ms)
- **max** : 0.039 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T20:47:12 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.020 ms
- **p99** : 0.034 ms (threshold ≤ 16.6 ms)
- **max** : 0.097 ms
- **Verdict** : PASS

## Run 2026-05-09T20:47:12 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.025 ms (threshold ≤ 16.6 ms)
- **max** : 0.046 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-09T20:59:47 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.021 ms
- **p99** : 0.029 ms (threshold ≤ 16.6 ms)
- **max** : 0.050 ms
- **Verdict** : PASS

## Run 2026-05-09T20:59:47 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.014 ms
- **p99** : 0.021 ms (threshold ≤ 16.6 ms)
- **max** : 0.030 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-11T14:56:56 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.013 ms
- **p99** : 0.018 ms (threshold ≤ 16.6 ms)
- **max** : 0.041 ms
- **Verdict** : PASS

## Run 2026-05-11T14:56:56 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.009 ms
- **p99** : 0.015 ms (threshold ≤ 16.6 ms)
- **max** : 0.027 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-11T15:36:29 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.013 ms
- **p99** : 0.019 ms (threshold ≤ 16.6 ms)
- **max** : 0.035 ms
- **Verdict** : PASS

## Run 2026-05-11T15:36:29 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.009 ms
- **p99** : 0.016 ms (threshold ≤ 16.6 ms)
- **max** : 0.018 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-11T16:15:12 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.013 ms
- **p99** : 0.028 ms (threshold ≤ 16.6 ms)
- **max** : 0.047 ms
- **Verdict** : PASS

## Run 2026-05-11T16:15:13 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.010 ms
- **p99** : 0.019 ms (threshold ≤ 16.6 ms)
- **max** : 0.089 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS

## Run 2026-05-11T16:33:52 — Worst case ShapeCast (100x8)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 800
- **p50** : 0.014 ms
- **p99** : 0.017 ms (threshold ≤ 16.6 ms)
- **max** : 0.025 ms
- **Verdict** : PASS

## Run 2026-05-11T16:33:52 — Soak global (1000 frames)

- **Hardware** : macOS — Apple M4 (10 cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)
- **Godot version** : 4.6 (project pinned)
- **Physics** : Jolt 4.6 default
- **Samples** : 1000
- **p50** : 0.009 ms
- **p99** : 0.031 ms (threshold ≤ 16.6 ms)
- **max** : 0.069 ms
- **draw_calls_max** : 0 (DEFERRED full bench Godot CLI — headless RenderingServer)
- **Verdict** : PASS
