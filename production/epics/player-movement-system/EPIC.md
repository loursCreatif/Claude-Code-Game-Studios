# Epic: Player Movement System

> **Layer**: Core
> **GDD**: design/gdd/player-movement-system.md
> **Architecture Module**: MovementController (CharacterBody3D script)
> **Status**: Ready
> **Stories**: 18 créées (17 Ready + 1 Blocked — ADR-0015)
> **Manifest Version**: 2026-04-21
> **Engine Risk**: HIGH (VR-1 Shader Baker / VR-2 D3D12 n/a direct — ADR-0001 Jolt 4.6 default advisory Sprint 1)

## Overview

MovementController est le cœur mécanique de CHROME://ASCENT — il implémente le
risque #1 du projet (feel = seul différenciateur de Pillar 1 FLOW AVANT TOUT).
Il orchestre cinq états (Grounded, Airborne, Dashing, WallRunning, Dead), trois
capacités gated par l'Upgrade System (double-jump, dash, wall-run), et applique
les formules vélocité/saut/dash/wall-run calibrées sur dt=1/60 (ADR-0001). Il
possède l'autorité exclusive `_physics_process` sur position/vélocité/state
(ADR-0001 D-3) et émet 8 signaux typés MVP direct + 1 nom réservé post-MVP
vers CameraSystem, PlayerCombat, CheckpointRespawn, VFX et HUD via le pattern
direct typed signals outbound-only (ADR-0005) — MovementController ne référence
aucun consumer. La hiérarchie scene-tree trois étages (`Player →
CameraArm → CameraEffects → Camera3D → AudioListener3D`, ADR-0002) garantit
que Movement mute `player.rotation.y` (yaw) et son propre transform sans
entrer en collision avec les mutations Camera (pitch/tilt/shake). L'invariant
non-négociable : latence input→physics state change ≤ 16 ms p99 côté engine.

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| ADR-0001 : Physics Rate 60 Hz + Jolt | `_physics_process` 60 Hz autorité gameplay, Jolt physics explicit, `max_physics_steps_per_frame=4`, `default_gravity=0.0` (Movement applique gravité custom GRAVITY=24), CharacterBody3D + ShapeCast3D wall detection | HIGH (Jolt default 4.6 — advisory Sprint 1) |
| ADR-0005 : Movement Signals Architecture | 8 signaux typés MVP (dash_started/ended, wall_run_entered/exited, wall_jumped, died, respawned, attacked) + `falling` réservé, emit depuis `_physics_process` ONLY, CONNECT_DEFERRED par défaut (sync selon critères a-d), ordre intra-tick sortie-avant-entrée, idempotence par transition, zero-alloc payloads, MovementController outbound-only (D-10) | LOW |
| ADR-0002 : Camera Scene Tree CameraArm | Hiérarchie 3-étages, Movement écrit `player.rotation.y` + son transform ; Camera écrit `camera_arm.rotation.x` (pitch) / `camera_effects.rotation.z` (tilt) / `camera3d.*` (FOV/shake). Ownership séparée prévient conflits Tween. | MEDIUM |

## GDD Requirements

| TR-ID | Requirement (abrégé) | ADR Coverage |
|-------|----------------------|--------------|
| TR-mov-001 | Physics tick rate 60 Hz — formules vélocité/saut/dash/wall-run calibrées dt=1/60, `PHYSICS_TICK_RATE` paramétré | ADR-0001 ✅ |
| TR-mov-002 | CharacterBody3D + Jolt + ShapeCast3D wall detection + raycasts `%WallRayLeft/%WallRayRight` unique-name | ADR-0001 ✅ |
| TR-mov-003 | Autorité gameplay `_physics_process` unique — mouvement, collision, respawn state, wall-run state mutés uniquement en physics frame | ADR-0001 ✅ |
| TR-mov-004 | Hiérarchie camera 3-étages CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D | ADR-0002 ✅ |
| TR-mov-005 | Jump buffer POST-MVP (retiré r3) — aucune implémentation MVP, jump = immediate response only | ⚠️ N/A intentionnel (décision Martin r3) |
| TR-mov-006 | Architecture signaux Movement : 8 signaux typés MVP + pattern direct typed signals, emit physics only, CONNECT_DEFERRED/sync critères a-d, ordre sortie-avant-entrée, idempotence, zero-alloc, outbound-only | ADR-0005 ✅ |
| TR-mov-007 | Project Setting `physics/3d/default_gravity=0.0` — custom gravity Movement (GRAVITY=24) nécessite gravity globale Jolt désactivée pour éviter double-cumul | ADR-0001 ✅ (amendement 2026-04-21) |
| TR-mov-008 | Accessibility toggles `reduce_flash` et `reduce_motion` (WCAG 2.3.1/2.3.3) MVP-required — propagation cross-system (Camera shake bypass, Movement tilt bypass, VFX flash bypass) | ❌ No ADR (G-4 — ADR-0015 Accessibility Interface Layer planned phase Polish) |

## Known Gaps

- **TR-mov-008** (accessibility toggles) — non-blocker MVP. Spec implémentable
  depuis GDD l. 382-388 existe. Stories touchant ce TR (surtout tilt wall-run
  bypass) seront marquées **Blocked** jusqu'à écriture de **ADR-0015
  Accessibility Interface Layer** (phase Polish) OU inline spec acceptée.
  Option de déblocage rapide : écrire un ADR léger pour formaliser le setter
  `set_reduce_motion(bool)` sur MovementController avant la story wall-run.

## Validation Requirements (Sprint 1)

- **Hot path physics budget** : `_physics_process` ≤ 4 ms p99 incluant
  Movement + Camera reads + signal emit (ADR-0001 + ADR-0005 Pillar 4).
- **Signal latency intra-tick** : `dash_started` → CameraSystem handler
  CONNECT_DEFERRED reçu au frame N+1 (ADR-0005 D-5), zéro alloc par emit.
- **Wall-jump reproducibility** : AC-MV-34 couloir étroit priorité `%WallRayLeft`
  wins, determinism test (seed fixe, 100 iterations).
- **RESPAWN_DELAY 50 ms** : AC playtest attribution causale 5/5 joueurs
  identifient cause mort. Contrainte matérielle ≥ 1 frame (16.6 ms) pour
  CONNECT_DEFERRED consumers (VFX/Audio/HUD) garantie avant `respawn()`.
- **Jolt integration smoke** : CharacterBody3D + ShapeCast3D wall detection
  vitesse max dash+wall-run, no tunneling à vélocité maximale du moveset.
- **Prototype continuity** : `prototypes/movement-katana/` (existant, documenté)
  → migration progressive vers `src/` doit préserver feel mesuré.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/player-movement-system.md` sont
  verified (AC-MV-*, AC-Feel-*, AC-Perf-*, AC-Signal-*, AC-Respawn-*)
- All Logic stories ont passing test files dans `tests/unit/movement/`
  (formules vélocité, edge cases transitions, determinism wall-jump priority)
- All Integration stories ont passing tests dans `tests/integration/movement/`
  (signals propagation CameraSystem/PlayerCombat, respawn lifecycle)
- All Visual/Feel stories ont evidence docs avec sign-off dans
  `production/qa/evidence/` (dash feel, wall-run tilt, respawn attribution)
- Control Manifest v2026-04-21 Core layer rules respectés (autorité
  `_physics_process`, signals pattern ADR-0005, scene tree ADR-0002)
- Prototype `prototypes/movement-katana/` playtest ≥ 3 sessions valide feel
  avant gate Pre-Production → Production
- Dette GDD r4 apurée si le log `design/gdd/reviews/player-movement-system-review-log.md`
  le demande encore (4 edits post-Accepted : canonical list l. 82, ref D-5
  l. 74-75, Progress RÉSOLU l. 619, 3 ACs symétriques idempotence/ordre)

## Cross-References

- GDD : `design/gdd/player-movement-system.md`
- Review log : `design/gdd/reviews/player-movement-system-review-log.md`
- ADRs : `docs/architecture/adr-0001-physics-rate-60hz.md`, `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md`, `docs/architecture/adr-0005-movement-signals-architecture.md`
- Architecture module : `docs/architecture/architecture.md` §4.1, §6.2
- Control Manifest : `docs/architecture/control-manifest.md` (Core Layer section)
- TR Registry : `docs/architecture/tr-registry.yaml` (TR-mov-001..008)
- Architecture review : `docs/architecture/architecture-review-2026-04-21-movement.md`
- Prototype : `prototypes/movement-katana/` (amorce Sprint 1 feel validation)

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | [Project Settings + Scene skeleton + State enum](story-001-project-settings-scene-skeleton.md) | Integration | Ready | ADR-0001, ADR-0002 |
| 002 | [Grounded horizontal movement (stop instantané)](story-002-grounded-horizontal-movement.md) | Logic | Ready | ADR-0001 |
| 003 | [Custom gravity + Airborne air control](story-003-gravity-airborne-air-control.md) | Logic | Ready | ADR-0001 |
| 004 | [Jump + Double-jump + Coyote time](story-004-jump-double-jump-coyote.md) | Logic | Ready | ADR-0001 |
| 005 | [Dash state (burst + exit momentum + cooldown)](story-005-dash-state-burst-momentum.md) | Logic | Ready | ADR-0001 |
| 006 | [Wall-run detection + state + raycasts](story-006-wall-run-detection-state.md) | Logic | Ready | ADR-0001 |
| 007 | [Wall-jump + air_jumps_used = MAX](story-007-wall-jump.md) | Logic | Ready | ADR-0001 |
| 008 | [Death + respawn lifecycle + idempotence](story-008-death-respawn-lifecycle.md) | Integration | Ready | ADR-0001, ADR-0005 |
| 009 | [Signals + typed contract test](story-009-signals-typed-contract.md) | Integration | Ready | ADR-0005 D-2/D-3/D-4 |
| 010 | [Signal order + idempotence transitions](story-010-signal-order-idempotence.md) | Integration | Ready | ADR-0005 D-6/D-8 |
| 011 | [Zero-alloc signals + outbound-only lint](story-011-zero-alloc-outbound-lint.md) | Integration | Ready | ADR-0005 D-9/D-10 |
| 012 | [Velocity NaN/Infinity safeguard](story-012-velocity-nan-safeguard.md) | Logic | Ready | ADR-0001 |
| 013 | [Capability gating (can_dash/air_jump/wall_run)](story-013-capability-gating.md) | Config/Data | Ready | ADR-0001 |
| 014 | [Perf physics tick rate + frame budget benchmark](story-014-perf-physics-benchmark.md) | Integration | Ready | ADR-0001 VC-1/2/4 + ADR-0005 VC-8 |
| 015 | [Cross-system mocks (Combat + Checkpoint)](story-015-cross-system-mocks.md) | Integration | Ready | ADR-0005 D-10 |
| 016 | [Combo chain full integration](story-016-combo-chain-integration.md) | Integration | Ready | ADR-0001 + ADR-0005 |
| 017 | [Visual/Feel playtest evidence](story-017-visual-feel-playtest-evidence.md) | Visual/Feel | Ready | ADR-0001 (Pillar 1) |
| 018 | [Accessibility reduce_motion/reduce_flash](story-018-accessibility-toggles.md) | Config/Data | **Blocked** | ❌ ADR-0015 absent |

**Dependency chain** : `001 → {002, 012, 013}` ; `002 → 003 → 004` ; `004 → {005, 006}` ; `{005, 006} → 007` ; `{001..007} → 008` ; `{001..008} → 009 → {010, 011}` ; `{001..013} → 014 → 015 → 016 → 017`. Story 018 indépendante, blocked hors ADR-0015.

**Story type distribution** : 8 Logic, 7 Integration, 1 Visual/Feel (ADVISORY gate), 2 Config/Data (1 BLOCKED).

## Next Step

Run `/story-readiness production/epics/player-movement-system/story-001-project-settings-scene-skeleton.md` puis `/dev-story` pour commencer l'implémentation Sprint 1.
