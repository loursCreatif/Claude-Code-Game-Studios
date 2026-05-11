## MovementConstants — constantes numériques et enum State du MovementController.
##
## Extrait de movement_controller.gd (TD-008) pour réduire la taille du fichier
## principal. Ce fichier est un conteneur statique pur : aucune logique, aucun état,
## aucun signal.
##
## Usage :
##   const MC := preload("res://src/gameplay/player/movement_constants.gd")
##   var my_speed := MC.MOVE_SPEED        # constante
##   var s: MC.State = MC.State.GROUNDED  # enum
##
## Governing ADRs :
##   ADR-0001 : Physics rate 60 Hz — DISPLAY_TICK_RATE + GRAVITY définis ici.
##   ADR-0005 : Movement signals architecture — State enum canonical list.
##
## Story : story-014-tech-debt-cleanup (TD-008 split <300 lignes)

class_name MovementConstants
extends RefCounted

# ---------------------------------------------------------------------------
# Enum — état de la state machine de mouvement
# ---------------------------------------------------------------------------

## Canonical movement state machine values.
## Full transitions defined in stories 002–007.
## ADR-0005 D-2 : canonical list, any addition requires ADR-0005 amendment.
enum State {
	GROUNDED,
	AIRBORNE,
	DASHING,
	WALL_RUNNING,
	DEAD,
}

# ---------------------------------------------------------------------------
# Constantes — mouvement horizontal
# ---------------------------------------------------------------------------

## Horizontal movement speed in grounded state (m/s).
## GDD Rule 1 / TR-mov-001 : Vhorizontal = wish_dir * MOVE_SPEED (no acceleration).
const MOVE_SPEED: float = 10.0

## Air control deceleration/acceleration factor (m/s² effective, via move_toward).
## Story-003 / GDD Formulas > Airborne air control.
const AIR_CONTROL_FACTOR: float = 65.0

# ---------------------------------------------------------------------------
# Constantes — gravité et saut
# ---------------------------------------------------------------------------

## Custom gravity acceleration (m/s²), applied manually every physics tick.
## ADR-0001 amendement : Jolt default_gravity forcé à 0.0 dans project.godot.
const GRAVITY: float = 24.0

## Upward velocity applied when jumping from GROUNDED state (m/s).
## Story-004 / AC-MV-10 — peak height = JUMP_VELOCITY² / (2*GRAVITY) ≈ 1.172 m.
const JUMP_VELOCITY: float = 7.5

## Upward velocity applied when performing an air jump (double-jump) (m/s).
## Story-004 / AC-MV-11.
const AIR_JUMP_VELOCITY: float = 6.5

## Maximum number of air jumps allowed before landing resets the counter.
## Story-004 / AC-MV-12. Set to 1 for double-jump (1 ground + 1 air).
const MAX_AIR_JUMPS: int = 1

## Coyote time window in physics ticks (6 ticks × 1/60 s ≈ 100 ms).
## Story-004 / AC-MV-14 / ADR-0001 tick-based timing (deterministic).
const COYOTE_TIME_TICKS: int = 6

# ---------------------------------------------------------------------------
# Constantes — dash
# ---------------------------------------------------------------------------

## Dash burst speed (m/s). Applied during the DASHING state.
## Story-005 / AC-MV-20 — Invariant : DASH_SPEED >= MOVE_SPEED * 2.5.
const DASH_SPEED: float = 30.0

## Duration of the dash burst in seconds.
## Story-005 / AC-MV-20 — distance = DASH_SPEED * DASH_DURATION = 3.0 m.
const DASH_DURATION: float = 0.10

## Horizontal speed applied immediately when exiting DASHING state (m/s).
## Story-005 / AC-MV-20.
const DASH_EXIT_SPEED: float = 15.0

## Duration of the momentum deceleration window after the dash burst (seconds).
## Story-005 / AC-MV-20.
const DASH_MOMENTUM_WINDOW: float = 0.20

## Cooldown between dashes (seconds). Starts at dash entry.
## Story-005 / AC-MV-22 — Invariant : DASH_COOLDOWN >= 4 * DASH_DURATION.
const DASH_COOLDOWN: float = 0.8

# ---------------------------------------------------------------------------
# Constantes — respawn
# ---------------------------------------------------------------------------

## Minimum respawn delay in milliseconds.
## ADR-0005 VC-7 : must be >= 1000.0 / DISPLAY_TICK_RATE (one physics tick).
const RESPAWN_DELAY_MS: float = 50.0

## Display tick rate used to derive the minimum respawn window.
## Must match physics/common/physics_ticks_per_second in project.godot (ADR-0001).
const DISPLAY_TICK_RATE: float = 60.0

## Respawn delay in seconds, derived from RESPAWN_DELAY_MS.
## RESPAWN_DELAY_MS=50 → RESPAWN_DELAY_S=0.05 (≈ 3 ticks at 60 Hz).
const RESPAWN_DELAY_S: float = RESPAWN_DELAY_MS / 1000.0

# ---------------------------------------------------------------------------
# Constantes — wall-run
# ---------------------------------------------------------------------------

## Half-width used for wall proximity raycasts (capsule_radius + WALL_DETECT_MARGIN).
## TR-mov-002 : total ray length = 0.35 + 0.45 = 0.80 m.
const WALL_DETECT_MARGIN: float = 0.45

## Minimum horizontal speed required to enter WALL_RUNNING state (m/s).
## Story-006 / AC-MV-30 / GDD Rule 7.
const WALL_RUN_MIN_SPEED: float = 5.0

## Reduced gravity applied while WALL_RUNNING (m/s²).
## Story-006 / AC-MV-30.
const WALL_RUN_GRAVITY: float = 4.0

## Maximum downward speed clamped during WALL_RUNNING (m/s, positive magnitude).
## Story-006 — velocity.y = max(velocity.y, -WALL_RUN_FALL_CAP).
const WALL_RUN_FALL_CAP: float = 3.0

## Maximum duration of a single wall-run before forced exit (seconds).
## Story-006 / AC-MV-33.
const WALL_RUN_MAX_DURATION: float = 1.5

# ---------------------------------------------------------------------------
# Constantes — wall-jump
# ---------------------------------------------------------------------------

## Horizontal component of the wall-jump velocity (m/s), applied along wall_normal.
## Story-007 / AC-MV-32.
const WALL_JUMP_SIDE: float = 7.0

## Vertical component of the wall-jump velocity (m/s).
## Story-007 / AC-MV-32 — must satisfy WALL_JUMP_UP² / (2×GRAVITY) ≥ 0.7 × JUMP_VELOCITY² / (2×GRAVITY).
const WALL_JUMP_UP: float = 6.5
