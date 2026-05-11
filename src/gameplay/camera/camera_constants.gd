class_name CameraConstants
extends RefCounted

## Constantes partagées du Camera System (TD-008 extraction depuis camera_system.gd).
## Référencées par CameraSystem via `const CC := preload("camera_constants.gd")`.
## Source : ADR-0002, GDD camera-system.md, stories 002–013.


# ---------------------------------------------------------------------------
# Perf ring buffer (story 012, GDD AC-CAM-80/81, ADR-0004 D-8)
# ---------------------------------------------------------------------------

## Capacité ring buffer coût _process — ~4 s à 60 fps (GDD AC-CAM-80 : 240 samples).
const PROCESS_COST_CAPACITY: int = 240

## Capacité ring buffer latence mouse_motion — 1000 événements (GDD AC-CAM-81).
const LATENCY_CAPACITY: int = 1000


# ---------------------------------------------------------------------------
# Yaw/pitch bounds (story 002, ADR-0002)
# ---------------------------------------------------------------------------

## Limite pitch absolue ≈ 87.1° (PI/2 − 0.05 rad). Évite gimbal lock.
## AC-CAM-03 : 10 motions vers le haut → pitch reste à PITCH_LIMIT.
const PITCH_LIMIT: float = PI / 2.0 - 0.05

## Cap magnitude par event mouse motion. Protège contre flick dégénéré (AC-CAM-04).
const MAX_ROT_PER_FRAME: float = PI


# ---------------------------------------------------------------------------
# FOV dash pulse (story 006, TR-cam-001)
# ---------------------------------------------------------------------------

## FOV de base (degrés). Prototype validé 2026-04-21.
const BASE_FOV: float = 90.0

## Bonus FOV lors d'un dash (degrés). Peak = BASE_FOV + DASH_FOV_KICK = 100°.
const DASH_FOV_KICK: float = 10.0

## Vitesse lerp FOV (unit/s). Snap-in ~150 ms — fov ≥ 98.5° en 9 frames (AC-CAM-20).
const DASH_FOV_LERP_SPEED: float = 14.0


# ---------------------------------------------------------------------------
# Wall-run tilt (story 005, TR-cam-004)
# ---------------------------------------------------------------------------

## Angle de tilt cible (rad) lors d'un wall-run. ~20° en degrés.
const WALL_RUN_TILT_ANGLE: float = 0.35

## Vitesse lerp tilt (unit/s). t_95 ≈ 250 ms à 60 fps.
const TILT_LERP_SPEED: float = 12.0


# ---------------------------------------------------------------------------
# Shake additif + wall_jump kick (story 007, ADR-0002 Risk 3)
# ---------------------------------------------------------------------------

## Decay rate (1/s) — exp(-SHAKE_DECAY * delta) → retour < 5% en ~250 ms.
const SHAKE_DECAY: float = 12.0

## Magnitude kick wall-jump (rad ≈ 3°). GDD Rule 7.
const WALL_JUMP_KICK_MAGNITUDE: float = 0.05

## Cap absolu magnitude cumulée shake (rad ≈ 11.5°). AC-CAM-32.
const MAX_SHAKE_MAGNITUDE: float = 0.2


# ---------------------------------------------------------------------------
# Respawn lifecycle (story 008, ADR-0002 + ADR-0005 D-2/D-6/D-8)
# ---------------------------------------------------------------------------

## Mini-state Camera-side — gate mouse_motion + idempotence handler died.
## ADR-0005 D-8 : transition 1× par changement. COSMETIC ONLY (pas logique gameplay).
enum State { ACTIVE, RESPAWNING }

## Couleur overlay rouge sombre activé pendant Respawning (AC-CAM-40).
const RESPAWN_OVERLAY_COLOR: Color = Color(0.4, 0.0, 0.0, 0.6)

## CanvasLayer.layer pour overlay respawn — au-dessus HUD (50) et Pause (80).
const RESPAWN_OVERLAY_LAYER: int = 100


# ---------------------------------------------------------------------------
# Respawn fade + flash visual (story 009, GDD Rule 9 + Visual/Audio)
# ---------------------------------------------------------------------------

## Durée fade rouge → transparent (s). GDD Visual/Audio : 100 ms.
const RESPAWN_OVERLAY_FADE_DURATION: float = 0.100

## Durée flash blanc (s). GDD Visual/Audio : 50 ms.
const RESPAWN_FLASH_DURATION: float = 0.050

## Couleur flash blanc Mirror's Edge reference (alpha 0.9).
const RESPAWN_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

## Couleur fin de fade (rouge transparent). Alpha 0, couleur maintenue pour interpolation.
const RESPAWN_FADE_END_COLOR: Color = Color(0.4, 0.0, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Reduce_motion gate (story 010, GDD Rule 14)
# ---------------------------------------------------------------------------

## Multiplier tilt quand reduce_motion == true. Tilt × 0.25 → 0.0875 rad.
const REDUCE_MOTION_TILT_MULT: float = 0.25

## Multiplier FOV kick quand reduce_motion == true. Peak 95° au lieu de 100°.
const REDUCE_MOTION_FOV_KICK_MULT: float = 0.5
