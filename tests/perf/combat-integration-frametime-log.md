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
