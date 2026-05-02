# Epic: Camera System

> **Layer**: Core
> **GDD**: design/gdd/camera-system.md
> **Architecture Module**: CameraSystem (Node3D wrapper — CameraArm hierarchy)
> **Status**: Ready
> **Stories**: 13 stories written 2026-04-22 (12 Ready + 1 Blocked) — distribution 4 Logic / 7 Integration / 1 Visual-Feel / 1 Config-Data
> **Manifest Version**: 2026-04-21
> **Engine Risk**: HIGH (VR-1 Shader Baker 4.5+ / VR-2 D3D12 4.6 default Windows — ADR-0003 rendering latency advisory Sprint 1)

## Overview

CameraSystem est la fenêtre perceptive du joueur sur le monde — le médium par
lequel Pillar 1 FLOW AVANT TOUT et Pillar 2 LA PROGRESSION SE VOIT deviennent
tangibles. Il orchestre quatre rôles couplés : (1) appliquer pitch vertical
(`camera_arm.rotation.x`) en consommant le signal `mouse_motion(delta: Vector2)`
de l'InputManager (ADR-0004) sans smoothing — feel raw mandatory ; (2) appliquer
yaw horizontal à `player.rotation.y` (owned by Camera per ADR-0002, Movement
lit read-only) ; (3) rendre visibles les états Movement via transforms
obligatoires — tilt wall-run (`camera_effects.rotation.z`), FOV pulse dash,
shake kick wall-jump, fade rouge died ; (4) servir de source `aim_forward()`
roll-corrected pour la hitbox katana PlayerCombat (stable horizontalement en
wall-run). Le système tourne en `_process` (frame rate affichage 60+ fps,
ADR-0003 split) — pas de `_physics_process`. L'ownership mutations est strict
par étage scene tree (ADR-0002 D-1) : yaw=Player, pitch=CameraArm, tilt=
CameraEffects, FOV+shake=Camera3D, head-bob=CameraArm.position.y (Tier 2 OFF
MVP). Latence mouse→rotation ≤ 1 frame d'affichage (16 ms cible, 8 ms idéal,
cohérent budget Pillar 1). Budget perf p99 ≤ 0.5 ms/frame (TR-cam-005).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| ADR-0002 : Camera Scene Tree CameraArm | Hiérarchie 3-étages `Player → CameraArm → CameraEffects → Camera3D → AudioListener3D`. Ownership séparée : yaw=Player, pitch=CameraArm, tilt=CameraEffects.rotation.z, FOV+shake=Camera3D. Prévient conflits Tween head-bob ↔ wall-run tilt. `aim_forward()` roll-corrected trigonométrique (ignore tilt). | MEDIUM |
| ADR-0003 : Rendering & Display Latency | Camera logique en `_process` (pas `_physics_process`) — autorité display. Mouse motion event-driven via signal connection. Latency budget ≤ 16 ms input→display p99, 8 ms idéal. D3D12 Windows default 4.6 (VR-2 HIGH advisory). | HIGH (D3D12 advisory Sprint 1) |
| ADR-0001 : Physics Rate 60 Hz + Jolt | Split `_physics_process` 60 Hz (gameplay) vs `_process` frame rate (camera/rendering). Camera reads `player.rotation.y` + Movement state read-only ; aucune autorité gameplay. | HIGH (indirect — consumer Foundation physics) |
| ADR-0004 : Input API & Focus Handling | Signal `mouse_motion(delta: Vector2)` consommé par Camera via signal connection dans `_ready()`. InputManager = seul producer mouse motion (TR-inp-002). `is_mouse_captured` gate check avant apply. | HIGH (VR-3 dual-focus 4.6 advisory — Foundation consumer) |

## GDD Requirements

| TR-ID | Requirement (abrégé) | ADR Coverage |
|-------|----------------------|--------------|
| TR-cam-001 | Yaw sur `player.rotation.y` ; pitch sur `camera_arm.rotation.x` ; tilt sur `camera_effects.rotation.z` ; FOV+shake sur `camera3d` — ownership séparée par étage scene tree | ADR-0002 ✅ |
| TR-cam-002 | `aim_forward()` calculé trigo close-form depuis yaw+pitch, ignore tilt par construction (hitbox katana stable horizontalement en wall-run) | ADR-0002 ✅ |
| TR-cam-003 | Logique caméra en `_process` (frame rate 60+ fps) — pas `_physics_process`. Mouse motion event-driven via signal | ADR-0001, ADR-0003 ✅ |
| TR-cam-004 | Tilt wall-run visible à 95% de WALL_RUN_TILT_ANGLE=0.35 rad dans ≤ 200 ms (lerp `camera_effects.rotation.z`) | ❌ No ADR (spec implémentable depuis GDD Rule 4 — comportement non-structurel, pas d'ADR requis) |
| TR-cam-005 | Performance budget caméra ≤ 0.5 ms/frame p99 — logique camera en `_process` (yaw+pitch apply, tilt lerp, shake decay, FOV interp) | ADR-0002 ✅ (claim enregistré registry 2026-04-21) |
| TR-cam-006 | Lifecycle save/load `camera_settings.tres` (mouse_sensitivity, mouse_y_inverted, fov_user_offset) — persist + migration versions + fallback corruption | ADR-0014 ✅ (Accepted 2026-05-02 — Polish P3) |

## Known Gaps

- **TR-cam-004** (tilt timing spec) — pas bloquant. Comportement non-structurel,
  testable directement depuis GDD Rule 4 (AC-CAM-TILT-*). Pas d'ADR requis —
  cela reste un behavior target, pas une décision architecturale. Stories
  peuvent procéder avec référence GDD directe.
- **TR-cam-006** (save/load camera_settings) — RÉSOLU 2026-05-02. **ADR-0014 Save/Load Settings Infrastructure** Accepted (Polish P3). Story 013 Status `Ready` — implémentation programmable post-Sprint 1 release. Pattern partagé avec TR-inp-009 (input-010) via helper static `SettingsResource`.

## Validation Requirements (Sprint 1)

- **VR-2 (ADR-0003 VC-1)** : D3D12 4.6 Windows default — Camera rendering
  `_process` tick stable 60+ fps sans frame drops, test CI 3 OS. Advisory,
  non-blocker Accept mais requis CI Sprint 1.
- **VR-3 (ADR-0004 VC-1 via InputManager)** : Camera consume signal
  `mouse_motion` pendant dual-focus 4.6 transitions sans burst Wayland
  pollution (fenêtre 50 ms gated par `is_mouse_captured`).
- **Pitch gimbal lock** : `PITCH_LIMIT = PI/2 - 0.05`, clamp garanti 100%
  frames, zéro wraparound à sensitivity max.
- **Tilt wall-run reproducibility** : AC-CAM-TILT 95% cible ≤ 200 ms, test
  deterministic (lerp factor calibré, mock wall_run_entered signal).
- **aim_forward stability** : lint check `camera3d.rotation` jamais muté
  hors CameraSystem (ADR-0002 Forbidden rule).
- **Hot path `_process` budget** : p99 ≤ 0.5 ms/frame (TR-cam-005), p50
  ≤ 0.2 ms release build.
- **Signal handler cleanup** : `_exit_tree()` disconnect InputManager
  signals (mouse_motion + focus), zéro leak sur respawn scene reload.

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All acceptance criteria from `design/gdd/camera-system.md` sont verified
  (AC-CAM-YAW-*, AC-CAM-PITCH-*, AC-CAM-TILT-*, AC-CAM-FOV-*, AC-CAM-SHAKE-*,
  AC-CAM-RESPAWN-*, AC-CAM-Perf-*, AC-CAM-Integration-*)
- All Logic stories ont passing test files dans `tests/unit/camera/`
  (trigo aim_forward, clamp pitch, lerp tilt, FOV interp)
- All Integration stories ont passing tests dans `tests/integration/camera/`
  (signal binding InputManager + MovementController, respawn pitch-preserved)
- All Visual/Feel stories ont evidence docs avec sign-off dans
  `production/qa/evidence/` (wall-run tilt kinesthésique, dash FOV pulse,
  respawn fade rouge Mirror's Edge reference)
- Control Manifest v2026-04-21 Core layer rules respectés (scene tree
  ADR-0002, `_process` autorité ADR-0003, mouse signal consumer ADR-0004)
- VR-2 D3D12 Windows CI frame stability test passe (advisory Sprint 1)
- VR-3 dual-focus gated mouse consume vérifié 3 OS
- Dette GDD r3 apurée si log
  `design/gdd/reviews/camera-system-review-log.md` le demande encore

## Cross-References

- GDD : `design/gdd/camera-system.md`
- Review log : `design/gdd/reviews/camera-system-review-log.md`
- ADRs : `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md`, `docs/architecture/adr-0003-rendering-latency.md`, `docs/architecture/adr-0001-physics-rate-60hz.md`, `docs/architecture/adr-0004-input-api-focus-handling.md`
- Architecture module : `docs/architecture/architecture.md` §4.1, §6.3
- Control Manifest : `docs/architecture/control-manifest.md` (Core Layer section)
- TR Registry : `docs/architecture/tr-registry.yaml` (TR-cam-001..006)
- Architecture review : `docs/architecture/architecture-review-2026-04-21-camera.md`
- Upstream epics : `production/epics/input-system/EPIC.md` (mouse_motion signal), `production/epics/player-movement-system/EPIC.md` (wall_run_entered/exited, dash_started/ended, wall_jumped, died, respawned signals)

## Stories

| # | Story | Type | Status | ADR | TR |
|---|-------|------|--------|-----|-----|
| 001 | Scene tree 3-étages CameraArm + project settings rendering | Integration | Ready | ADR-0002, ADR-0003 | TR-cam-001, TR-cam-003 |
| 002 | Yaw + Pitch raw apply (sensitivity, invert_y, PITCH_LIMIT, MAX_ROT_PER_FRAME) | Logic | Ready | ADR-0002, ADR-0004 | TR-cam-001 |
| 003 | Enabled + is_mouse_captured() gates sur mouse_motion handler | Logic | Ready | ADR-0004 | TR-cam-003 |
| 004 | aim_forward forme close trigonométrique (roll-ignored) | Logic | Ready | ADR-0002 | TR-cam-002 |
| 005 | Tilt wall-run — derive wall_side + lerp CameraEffects.rotation.z | Integration | Ready | ADR-0002, ADR-0005 | TR-cam-004 |
| 006 | FOV dash pulse — lerp camera3d.fov | Integration | Ready | ADR-0002, ADR-0005 | TR-cam-001 |
| 007 | Shake additif + wall_jump kick (sign_with_fallback, limit_length) | Integration | Ready | ADR-0002, ADR-0005 | TR-cam-001 |
| 008 | Respawn lifecycle — died/respawned + state + idempotence + pitch/yaw preservation | Integration | Ready | ADR-0002, ADR-0005 | TR-cam-001 |
| 009 | Respawn fade rouge → flash blanc → clear (Mirror's Edge) | Visual/Feel | Ready | ADR-0002 | — |
| 010 | Reduce_motion gate (tilt×0.25, fov_kick×0.5, shake×0) | Logic | Ready | ADR-0002 | — |
| 011 | _exit_tree cleanup + NaN safeguard + focus-loss behavior | Integration | Ready | ADR-0002, ADR-0004 | TR-cam-001 |
| 012 | Perf instrumentation ring buffer p50/p99 + E2E mouse latency | Integration (Perf) | Ready | ADR-0002, ADR-0003 | TR-cam-005 |
| 013 | camera_settings.tres save/load | Config/Data | Ready (Polish P3) | M | TR-cam-006 |

## Dependency Chain

```
Story 001 (scene skeleton)
    └── Story 002 (yaw+pitch apply)
            ├── Story 003 (enabled+capture gates)
            ├── Story 004 (aim_forward)
            ├── Story 005 (tilt wall-run) ──┬──┐
            ├── Story 006 (FOV dash) ────────┤  │
            └── Story 007 (shake+wall-jump) ─┤  │
                                              │  │
                     Story 008 (respawn lifecycle) ◄── depends on 005,006,007,003
                             └── Story 009 (fade rouge + flash blanc)
                     Story 010 (reduce_motion) ◄── depends on 005,006,007
                     Story 011 (cleanup+NaN+focus) ◄── depends on 001,002,005-008
                     Story 012 (perf ring buffer) ◄── depends on 001-007,011
                     Story 013 (save/load) ◄── Ready (ADR-0014 Accepted 2026-05-02)
```

## Story Distribution

| Type | Count | Stories |
|------|-------|---------|
| Logic | 4 | 002, 003, 004, 010 |
| Integration | 7 | 001, 005, 006, 007, 008, 011, 012 |
| Visual/Feel | 1 | 009 |
| Config/Data | 1 | 013 (Ready, Polish P3) |
| **Total** | **13** | — |

## Next Step

Run `/story-readiness production/epics/camera-system/story-001-scene-skeleton-project-settings.md` puis `/dev-story` pour démarrer l'implémentation de la scene skeleton.

Les stories suivantes doivent être implémentées dans l'ordre de la dependency chain ; chaque story liste précisément ses `Depends on:` et `Unlocks:`.

Story 013 (camera_settings save/load) est `Ready` depuis ADR-0014 Save/Load Settings Infrastructure (Accepted 2026-05-02). Implémentation programmable phase Polish P3 (post-Sprint 1 release). Pattern helper `SettingsResource` partagé avec input story-010 (TR-inp-009) — pas de duplication.
