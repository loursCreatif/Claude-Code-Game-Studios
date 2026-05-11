# Epic: Input System

> **Layer**: Foundation
> **GDD**: design/gdd/input-system.md
> **Architecture Module**: InputManager (autoload singleton)
> **Status**: Complete (10/10 stories shipped — ADR-0014 unblocked Polish P3)
> **Stories**: 10 créées + shippées (story-010 settings persistence post-ADR-0014 Accepted)
> **Manifest Version**: 2026-04-21
> **Engine Risk**: HIGH (VR-3 dual-focus 4.6 advisory — Sprint 1)

## Overview

InputManager est l'unique point d'accès à l'input joueur pour tout le projet. Il
expose une API de polling tick-based (`was_pressed_this_tick`) consommée par
MovementController et tous les autres systèmes gameplay, republie la souris via
signal `mouse_motion(delta)`, gère un pattern refcounted `request_disable` /
`release_enable_request` pour 3 owners légitimes (Menu, Checkpoint, Cutscene),
et découple Foundation de Game State Manager en émettant un signal one-way
`application_focus_lost` / `application_focus_gained`. La discipline zero-alloc
(ring buffer `PackedFloat32Array` pour la latence, StringName préalloués) et
l'autorité `_physics_process` (swap `_pressed ↔ _consumed` début de tick,
ADR-0004 D-3) sont les invariants non-négociables — ils servent le Pillar 1
FLOW AVANT TOUT (latence intra-engine ≤ 16 ms p99).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| ADR-0004 : Input API & Focus Handling | `was_pressed_this_tick` canonique, suppression `is_action_just_pressed` hot path, swap `_pressed↔_consumed`, refcount `request_disable`, signals focus one-way (découplage Foundation), fenêtre 50 ms burst-safe, ring buffer PackedFloat32Array, main-thread only, fixtures `OS.has_feature("debug")` + `Input.parse_input_event(InputEventAction)` | HIGH (VR-3 dual-focus 4.6 Wayland/X11/macOS) |
| ADR-0001 : Physics Rate 60 Hz + Jolt | Autorité gameplay `_physics_process` 60 Hz — InputManager lit OS events en `_unhandled_input`, expose API polling consommée dans le tick 60 Hz | HIGH (Jolt default 4.6 — Foundation consumer) |

## GDD Requirements

| TR-ID | Requirement (abrégé) | ADR Coverage |
|-------|----------------------|--------------|
| TR-inp-001 | Polling tick-based `was_pressed_this_tick(action)` — consumer `_physics_process` tick N reçoit press N-1→N | ADR-0004, ADR-0001 ✅ |
| TR-inp-002 | Mouse motion via `_unhandled_input` republiée en signal `mouse_motion(delta: Vector2)` — pas d'action lue | ADR-0004 ✅ |
| TR-inp-003 | InputManager = autoload singleton, unique point d'accès — `Input.*` interdit ailleurs (lint) | ADR-0004 ✅ |
| TR-inp-004 | StringName discipline : actions pré-alloués `const ACTION_JUMP := &"jump"` (zero-alloc hot path) | ADR-0004 ✅ |
| TR-inp-005 | Refcount `request_disable(owner)` / `release_enable_request(owner)` — 3 owners (Menu/Checkpoint/Cutscene) sans race, auto-cleanup sur `tree_exited` | ADR-0004 ✅ |
| TR-inp-006 | Signal `application_focus_lost` / `application_focus_gained` pour découplage Input ↔ GameStateManager (Foundation one-way) | ADR-0004 ✅ |
| TR-inp-007 | Zero-alloc hot path : ring buffer `PackedFloat32Array` préalloué cap 120 pour métriques latence | ADR-0004 ✅ |
| TR-inp-008 | Latence cible p99 ≤ 16 ms intra-engine (input event → physics state change) | ADR-0001, ADR-0003 ✅ |
| TR-inp-009 | Save/load `input_settings.tres` (remap Tier 2+, sensitivity, invert_y, focus burst window 20-150 ms) | ADR-0014 ✅ (Accepted 2026-05-02 — Polish P3) |

## Known Gaps

- **TR-inp-009** (save/load input_settings) — RÉSOLU 2026-05-02. **ADR-0014 Save/Load Settings Infrastructure** Accepted (Polish P3). Story 010 Status `Ready` — implémentation programmable post-Sprint 1. Pattern helper `SettingsResource` partagé avec camera story-013 (TR-cam-006).

## Validation Requirements (Sprint 1)

- **VR-3 (ADR-0004 VC-1)** : Integration test `NOTIFICATION_APPLICATION_FOCUS_OUT/IN`
  dual-focus Godot 4.6 sur 3 OS (Windows / macOS / Linux Wayland+X11). Advisory,
  non-blocker Accept mais requis CI Sprint 1.
- **Zero-alloc benchmark** : 10 000 events / 60 s sous `MEMORY_STATIC < 64 KB`
  (AC-PF-4 du GDD).
- **Hot path p99** : `was_pressed_this_tick` ≤ 0.1 ms p99 release build
  (AC-PF-5 du GDD).
- **Cold-start cost** : `_ready` + 1 tick ≤ 16 ms (AC-L-4).
- **E2E latency target** : p99 ≤ 16 ms (AC-L-1/2/3 combinés).

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/input-system.md` are verified (incluant
  AC-CR-*, AC-AG-*, AC-MC-*, AC-DS-*, AC-CS-*, AC-DBG-*, AC-L-*, AC-PF-*)
- All Logic and Integration stories have passing test files in `tests/unit/input/`
  et `tests/integration/input/`
- All Visual/Feel and UI stories have evidence docs with sign-off in
  `production/qa/evidence/`
- Control Manifest v2026-04-21 Foundation layer rules respectés (16 Required,
  7 Forbidden, 2 Guardrails)
- VR-3 CI integration test dual-focus passe sur 3 OS (advisory Sprint 1)
- Dette GDD r6 apurée si le log `design/gdd/reviews/input-system-review-log.md`
  le demande encore

## Cross-References

- GDD : `design/gdd/input-system.md`
- Review log : `design/gdd/reviews/input-system-review-log.md`
- ADRs : `docs/architecture/adr-0004-input-api-focus-handling.md`, `docs/architecture/adr-0001-physics-rate-60hz.md`
- Architecture module : `docs/architecture/architecture.md` §4.1, §6.1
- Control Manifest : `docs/architecture/control-manifest.md` (Foundation Layer section)
- TR Registry : `docs/architecture/tr-registry.yaml` (TR-inp-001..009)
- Architecture review : `docs/architecture/architecture-review-2026-04-21-input.md`

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [InputManager autoload bootstrap](story-001-inputmanager-autoload-boot.md) | Integration | Ready | ADR-0004 D-1 |
| 002 | [Polling `was_pressed_this_tick` + swap](story-002-action-polling-was-pressed-this-tick.md) | Logic | Ready | ADR-0004 D-1/D-3/D-9 |
| 003 | [Signal `mouse_motion(delta)`](story-003-mouse-motion-signal.md) | Logic | Ready | ADR-0004 |
| 004 | [Enable refcount multi-owner](story-004-enable-refcount.md) | Integration | Ready | ADR-0004 D-4 |
| 005 | [Focus handling + fenêtre 50 ms](story-005-focus-handling.md) | Integration | Ready | ADR-0004 D-5/D-6/D-7 |
| 006 | [Latency ring buffer zero-alloc](story-006-latency-ring-buffer.md) | Logic | Ready | ADR-0004 D-8 |
| 007 | [Benchmark E2E p99 ≤ 16 ms](story-007-latency-benchmark-e2e.md) | Integration | Ready | ADR-0004 + ADR-0001 |
| 008 | [Zero-alloc stress 10k events/60s](story-008-zero-alloc-stress.md) | Integration | Ready | ADR-0004 D-8 + VC-3 |
| 009 | [Debug overlay F3](story-009-debug-overlay.md) | UI | Ready | ADR-0004 D-9 |
| 010 | [Settings persistence `input_settings.tres`](story-010-settings-persistence.md) | Config/Data | Complete (2026-05-02) | ADR-0014 ✅ |

**Dependency chain** : 001 → {002, 003, 006} → {004, 005, 009} → {007, 008}. Story 010 indépendante (Polish P3, Complete 2026-05-02 — ADR-0014 helper `SettingsResource` partagé avec camera-013).

## Next Step

Run `/story-readiness production/epics/input-system/story-001-inputmanager-autoload-boot.md` puis `/dev-story` pour commencer l'implémentation.
