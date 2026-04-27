## MovementController — CharacterBody3D root script for the Player scene.
##
## Implements the state enum, read-only state property, and core lifecycle stubs
## mandated by Story 001 (scene skeleton + project settings).
##
## Governing ADRs:
##   ADR-0001 : Physics rate 60 Hz + Jolt 4.6 default — project settings owner.
##              Amendement: default_gravity=0.0 (Jolt), custom GRAVITY=24 m/s²
##              applied manually in _physics_process (TR-mov-007, story-003).
##   ADR-0002 : Camera scene tree (CameraArm → CameraEffects → Camera3D) —
##              no write from this script to camera nodes (D-10).
##   ADR-0005 : Movement signals architecture — 8 signals MVP declared story-009.
##              state property read-only enforced (REQ-8).
##              D-2: canonical list of 8 signals, payloads Vector3/float only.
##              D-4: emit ONLY from _physics_process (or functions called from it).
##              D-6: sub-state exit signal precedes terminal-state entry signal.
##              D-8: die() idempotent (early return if already DEAD).
##              VC-7: RESPAWN_DELAY_S >= 1/DISPLAY_TICK_RATE invariant.
##
## Story: story-001-project-settings-scene-skeleton
##        story-002-grounded-horizontal-movement
##        story-003-gravity-airborne-air-control
##        story-004-jump-double-jump-coyote
##        story-005-dash-state-burst-momentum
##        story-006-wall-run-detection-state
##        story-007-wall-jump
##        story-008-death-respawn-lifecycle
##        story-009-signals-typed-contract
##        story-012-velocity-nan-safeguard
##        story-013-capability-gating
## Control Manifest: 2026-04-23 Core layer

class_name MovementController
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Horizontal movement speed in grounded state (m/s).
## Story-002 placeholder — tunable in story-008+ balance pass via MovementTuning resource.
## GDD Rule 1 / TR-mov-001: Vhorizontal = wish_dir * MOVE_SPEED (no acceleration).
const MOVE_SPEED: float = 10.0

## Custom gravity acceleration (m/s²), applied manually every physics tick.
## Story-003 / TR-mov-007 / ADR-0001 amendement: Jolt default_gravity is forced
## to 0.0 in project.godot to prevent double-cumul. This constant owns the full
## downward acceleration.
## GDD Formula: velocity.y -= GRAVITY * delta (hors WALL_RUNNING).
const GRAVITY: float = 24.0

## Air control deceleration/acceleration factor (m/s² effective, via move_toward).
## Story-003 / GDD Formulas > Airborne air control.
## move_toward(velocity.xz, wish_dir * MOVE_SPEED, AIR_CONTROL_FACTOR * delta)
## → at 65 m/s², crossing from -10 to +10 takes ≈ 20/65 ≈ 308 ms (≈ 18-19 ticks).
const AIR_CONTROL_FACTOR: float = 65.0

## Upward velocity applied when jumping from GROUNDED state (m/s).
## Story-004 / AC-MV-10 / GDD Tuning Knobs.
## Peak height = JUMP_VELOCITY² / (2 * GRAVITY) = 7.5² / 48 ≈ 1.172 m.
const JUMP_VELOCITY: float = 7.5

## Upward velocity applied when performing an air jump (double-jump) (m/s).
## Story-004 / AC-MV-11 / GDD Tuning Knobs.
## Slightly lower than JUMP_VELOCITY — feels distinct and less overwhelming.
const AIR_JUMP_VELOCITY: float = 6.5

## Maximum number of air jumps allowed before landing resets the counter.
## Story-004 / AC-MV-12. Set to 1 for double-jump (1 ground + 1 air).
## Story-013 will gate availability via can_air_jump (Upgrade System).
const MAX_AIR_JUMPS: int = 1

## Coyote time window in physics ticks (6 ticks × 1/60 s ≈ 100 ms).
## Story-004 / AC-MV-14 / ADR-0001 tick-based timing (deterministic).
## During this window after stepping off a ledge, jumping executes a grounded
## jump (JUMP_VELOCITY) without consuming an air jump.
const COYOTE_TIME_TICKS: int = 6

## Dash burst speed (m/s). Applied during the DASHING state.
## Story-005 / AC-MV-20 / GDD Formulas > Dash.
## Invariant: DASH_SPEED >= MOVE_SPEED * 2.5 (checked in _ready).
const DASH_SPEED: float = 30.0

## Duration of the dash burst in seconds.
## Story-005 / AC-MV-20 / ADR-0001 tick-based timing via -= delta.
## Distance = DASH_SPEED * DASH_DURATION = 30 * 0.10 = 3.0 m (within AC ±0.15).
const DASH_DURATION: float = 0.10

## Horizontal speed applied immediately when exiting DASHING state (m/s).
## Story-005 / AC-MV-20: At t=DASH_DURATION, velocity.xz == dash_dir * DASH_EXIT_SPEED.
const DASH_EXIT_SPEED: float = 15.0

## Duration of the momentum deceleration window after the dash burst (seconds).
## Story-005 / AC-MV-20: At t=DASH_DURATION+DASH_MOMENTUM_WINDOW, speed returns to MOVE_SPEED.
const DASH_MOMENTUM_WINDOW: float = 0.20

## Cooldown between dashes (seconds). Starts at dash entry.
## Story-005 / AC-MV-22 / Invariant: DASH_COOLDOWN >= 4 * DASH_DURATION (checked in _ready).
const DASH_COOLDOWN: float = 0.8

## Minimum respawn delay in milliseconds.
## ADR-0005 VC-7: must be >= 1000.0 / DISPLAY_TICK_RATE (one physics tick).
## Placeholder value — tunable in story-008+ balance pass.
const RESPAWN_DELAY_MS: float = 50.0

## Display tick rate used to derive the minimum respawn window.
## Must match physics/common/physics_ticks_per_second in project.godot (ADR-0001).
const DISPLAY_TICK_RATE: float = 60.0

## Respawn delay in seconds, derived from RESPAWN_DELAY_MS.
## Story-008: used as countdown in _physics_process DEAD branch.
## RESPAWN_DELAY_MS=50 → RESPAWN_DELAY_S=0.05 (≈ 3 ticks at 60 Hz).
const RESPAWN_DELAY_S: float = RESPAWN_DELAY_MS / 1000.0

## Half-width used for wall proximity raycasts (capsule_radius + WALL_DETECT_MARGIN).
## TR-mov-002: total ray length = 0.35 + 0.45 = 0.80 m.
const WALL_DETECT_MARGIN: float = 0.45

## Minimum horizontal speed required to enter WALL_RUNNING state (m/s).
## Story-006 / AC-MV-30 / GDD Rule 7: horiz_speed > WALL_RUN_MIN_SPEED before entry.
const WALL_RUN_MIN_SPEED: float = 5.0

## Reduced gravity applied while WALL_RUNNING (m/s²). Much lower than GRAVITY=24.
## Story-006 / AC-MV-30 / GDD Formula: velocity.y -= WALL_RUN_GRAVITY * delta.
const WALL_RUN_GRAVITY: float = 4.0

## Maximum downward speed clamped during WALL_RUNNING (m/s, positive magnitude).
## Story-006 / Fall cap: velocity.y = max(velocity.y, -WALL_RUN_FALL_CAP).
const WALL_RUN_FALL_CAP: float = 3.0

## Maximum duration of a single wall-run before forced exit (seconds).
## Story-006 / AC-MV-33: timer-based exit, deterministic delta accumulation.
const WALL_RUN_MAX_DURATION: float = 1.5

## Horizontal component of the wall-jump velocity (m/s), applied along _wall_normal.
## Story-007 / AC-MV-32: launch_vel = _wall_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP.
## Invariant: checked in _ready (≥ 70 % of single jump height in WALL_JUMP_UP).
const WALL_JUMP_SIDE: float = 7.0

## Vertical component of the wall-jump velocity (m/s).
## Story-007 / AC-MV-32 / GDD Rule 8: nominal 6.5 m/s → peak height ≈ 0.88 m.
## Must satisfy: WALL_JUMP_UP² / (2×GRAVITY) ≥ 0.7 × JUMP_VELOCITY² / (2×GRAVITY).
const WALL_JUMP_UP: float = 6.5

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## Canonical movement state machine values.
## Full transitions defined in stories 002–007; GROUNDED and AIRBORNE active here.
## Story-003: GROUNDED↔AIRBORNE transitions based on is_on_floor().
enum State {
	GROUNDED,
	AIRBORNE,
	DASHING,
	WALL_RUNNING,
	DEAD,
}

# ---------------------------------------------------------------------------
# Signals
# Canonical list per ADR-0005 D-2. Ajout d'un signal = amendement ADR-0005.
# Emit ONLY from _physics_process (or functions called from it) — ADR-0005 D-4.
# Payload types: Vector3 / float exclusivement — ADR-0005 D-3 (zero-alloc,
# no Dict/Array/String/Node/Resource/StringName).
# ---------------------------------------------------------------------------

## Emitted when the player enters the DASHING state.
## dash_dir is the locked XZ normalized dash direction; dash_speed is DASH_SPEED.
signal dash_started(dash_dir: Vector3, dash_speed: float)

## Emitted when the DASHING state ends (burst timer expired).
signal dash_ended()

## Emitted when the player enters the WALL_RUNNING state.
## wall_normal is the outward normal of the wall surface (normalized).
signal wall_run_entered(wall_normal: Vector3)

## Emitted when the player exits the WALL_RUNNING state (any exit path).
signal wall_run_exited()

## Emitted on a successful wall-jump.
## wall_normal is the pre-reset outward surface normal (captured before _wall_normal=ZERO).
## launch_velocity is the full computed launch vector (wall_normal*WALL_JUMP_SIDE + UP*WALL_JUMP_UP).
signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)

## Emitted when the player transitions to State.DEAD via die().
## ADR-0005 D-6: sub-state exit signals (dash_ended / wall_run_exited) are emitted BEFORE this.
## die() is a public method; callers outside _physics_process (e.g. Combat in its own
## _physics_process, or GdUnit4 test thread — always main thread) are safe because
## GdUnit4 test execution runs on the main thread.
signal died()

## Emitted when the player teleports to the checkpoint after the respawn delay.
## spawn_position matches the value passed to set_checkpoint() at die() time.
signal respawned(spawn_position: Vector3)

## Emitted each tick the attack input edge is consumed and the player is not DEAD.
## Idempotent: InputManager.was_pressed_this_tick() consumes the edge once per tick,
## so attacked fires at most once per physics frame (ADR-0005 D-8).
signal attacked()

# ---------------------------------------------------------------------------
# Export variables
# (Reserved — balance tuning exposed in story-008+)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

## Read-only current movement state.
## ADR-0005 REQ-8: no external setter. Writing player.state = X from outside
## raises a GDScript error in debug builds (no setter defined).
var state: State:
	get = _get_state

## Number of air jumps consumed since last landing.
## Reset to 0 on every AIRBORNE→GROUNDED transition (AC-MV-11, AC-MV-12).
var air_jumps_used: int = 0

## Read-only: whether the air-jump ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start. Mutated only via set_capability(&"air_jump", ...).
## Pattern F7 (ADR-0005 REQ-8): backed by _can_air_jump, no external setter.
var can_air_jump: bool:
	get = _get_can_air_jump

## Read-only: whether the dash ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start. Mutated only via set_capability(&"dash", ...).
## Pattern F7 (ADR-0005 REQ-8): backed by _can_dash, no external setter.
var can_dash: bool:
	get = _get_can_dash

## Read-only: whether the wall-run ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start. Mutated only via set_capability(&"wall_run", ...).
## Pattern F7 (ADR-0005 REQ-8): backed by _can_wall_run, no external setter.
var can_wall_run: bool:
	get = _get_can_wall_run

## Read-only wall normal of the currently running surface.
## Story-006 / ADR-0005 REQ-8: backed by _wall_normal, no external setter.
## Vector3.ZERO when not in WALL_RUNNING state. Consumed by CameraSystem (story-005 tilt).
var wall_normal: Vector3:
	get = _get_wall_normal

## Remaining dash burst time (seconds). Counts down from DASH_DURATION to 0.
## Read externally by HUD or animation systems (ADR-0005 REQ-8 compatible).
var dash_timer: float = 0.0

## Read-only: remaining dash cooldown time in seconds.
## ADR-0005 REQ-8: backed by private _dash_cooldown_timer, no setter.
var dash_cooldown_timer: float:
	get = _get_dash_cooldown_timer

## Read-only: cooldown progress ratio [0.0 ready → 1.0 just used].
## Computed as 1.0 - clamp(remaining / DASH_COOLDOWN). Useful for HUD fill bars.
var dash_cooldown_ratio: float:
	get = _get_dash_cooldown_ratio

## Read-only: true when player is actively in DASHING state.
## Convenience alias — avoids exposing _state externally (ADR-0005 REQ-8).
var is_dashing: bool:
	get = _get_is_dashing

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## Backing field for the state property.
var _state: State = State.GROUNDED

## Backing field for can_air_jump read-only property (story-013 / pattern F7).
## Default false — AC-MV-60 (fresh start all capabilities disabled).
var _can_air_jump: bool = false

## Backing field for can_dash read-only property (story-013 / pattern F7).
## Default false — AC-MV-60 (fresh start all capabilities disabled).
var _can_dash: bool = false

## Backing field for can_wall_run read-only property (story-013 / pattern F7).
## Default false — AC-MV-60 (fresh start all capabilities disabled).
var _can_wall_run: bool = false

## Remaining coyote time in physics ticks.
## Set to COYOTE_TIME_TICKS on GROUNDED→AIRBORNE transition not caused by a jump.
## Decremented each AIRBORNE tick. When > 0, a jump press executes a grounded
## jump (JUMP_VELOCITY) and does NOT consume an air jump (AC-MV-14).
var _coyote_timer_ticks: int = 0

## Remaining cooldown before next dash is allowed (seconds). Counts down to 0.
## Set to DASH_COOLDOWN on dash entry. AC-MV-22: dash input ignored while > 0.
var _dash_cooldown_timer: float = 0.0

## Dash direction locked at entry tick (XZ plane only, normalized).
## AC-MV-23: direction does not change during the burst or momentum window.
## Fallback: -transform.basis.z projected XZ when wish_dir is near-zero.
var _dash_dir: Vector3 = Vector3.ZERO

## Remaining time in the post-dash momentum deceleration window (seconds).
## Set to DASH_MOMENTUM_WINDOW on dash exit. While > 0, horizontal speed
## decelerates linearly from DASH_EXIT_SPEED to MOVE_SPEED (AC-MV-20).
var _momentum_timer: float = 0.0

## Backing field for the wall_normal read-only property.
## Story-006 / AC-MV-34: mutated only by _try_start_wall_run() and _exit_wall_run().
## Vector3.ZERO when not WALL_RUNNING. Never written by external consumers (ADR-0005 REQ-8).
var _wall_normal: Vector3 = Vector3.ZERO

## Elapsed time in current wall-run (seconds). Counts up from 0 at entry.
## Story-006 / AC-MV-33: when >= WALL_RUN_MAX_DURATION, forces exit to AIRBORNE.
var _wall_run_timer: float = 0.0

## Last known checkpoint position, written by set_checkpoint() and consumed by _respawn().
## Story-008 / AC-MV-40: respawn teleports player to this position.
## Defaults to Vector3.ZERO (origin) until the Checkpoint System calls set_checkpoint().
var _checkpoint_position: Vector3 = Vector3.ZERO

## Countdown timer for the respawn delay (seconds). Starts at RESPAWN_DELAY_S on die().
## Story-008: decremented each DEAD-state tick; _respawn() fires when it reaches <= 0.
var _respawn_timer: float = 0.0

## Captures whether the player was DASHING at the moment die() was called.
## Story-008 / AC-MV-24: drives partial vs full dash cooldown reset on respawn.
## Reset to false after _respawn() applies the cooldown decision (one-shot flag).
var _was_dashing_at_death: bool = false

# ---------------------------------------------------------------------------
# @onready variables
# ---------------------------------------------------------------------------

## Left-side wall detection raycast. Targets (-0.8, 0, 0) relative to player.
## Story-006 / TR-mov-002 / ADR-0001: unique-name access via %WallRayLeft.
## Disabled when GROUNDED or DASHING (perf F7 — no wasted physics queries).
@onready var _wall_ray_left: RayCast3D = %WallRayLeft

## Right-side wall detection raycast. Targets (0.8, 0, 0) relative to player.
## Story-006 / TR-mov-002 / ADR-0001: unique-name access via %WallRayRight.
## Disabled when GROUNDED or DASHING (perf F7 — no wasted physics queries).
@onready var _wall_ray_right: RayCast3D = %WallRayRight

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ADR-0001 TR-mov-007: Jolt default_gravity must be 0.0 to prevent double-cumul
	# with the custom GRAVITY=24 applied in _physics_process (story-003).
	# If this fires, set physics/3d/default_gravity=0.0 in project.godot.
	assert(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) == 0.0,
		"ADR-0001 TR-mov-007: default_gravity must be 0.0 (custom GRAVITY=24 in MovementController)"
	)

	# ADR-0005 VC-7 invariant: respawn delay must cover at least one full
	# physics tick so the state machine cannot transition faster than the
	# physics rate allows.
	assert(
		RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE,
		"ADR-0005 VC-7 invariant violated: RESPAWN_DELAY_MS (%f ms) < one physics tick (%f ms)"
		% [RESPAWN_DELAY_MS, 1000.0 / DISPLAY_TICK_RATE]
	)

	# story-005 invariant: DASH_SPEED must be at least 2.5× MOVE_SPEED to
	# ensure the dash burst feels distinct from grounded movement (GDD tuning knob).
	assert(
		DASH_SPEED >= MOVE_SPEED * 2.5,
		"story-005 invariant: DASH_SPEED (%f) must be >= MOVE_SPEED * 2.5 (%f)"
		% [DASH_SPEED, MOVE_SPEED * 2.5]
	)

	# story-005 invariant: cooldown must be at least 4× the dash duration so
	# the player cannot spam dashes faster than physics can resolve them.
	assert(
		DASH_COOLDOWN >= 4.0 * DASH_DURATION,
		"story-005 invariant: DASH_COOLDOWN (%f) must be >= 4 * DASH_DURATION (%f)"
		% [DASH_COOLDOWN, 4.0 * DASH_DURATION]
	)

	# story-007 invariant: wall-jump vertical gain must be ≥ 70% of single-jump
	# peak height — guarantees wall-jump is never trivially weaker than a ground
	# jump (GDD Rule 8 / Control Manifest 2026-04-23).
	# Nominal: WALL_JUMP_UP=6.5 → h=0.880 m ; 0.7 × JUMP_VELOCITY=7.5 → 0.820 m ✓
	var safe_walljump_h: float = (WALL_JUMP_UP * WALL_JUMP_UP) / (2.0 * GRAVITY)
	var safe_jump_h: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
	assert(
		safe_walljump_h >= 0.7 * safe_jump_h,
		"story-007 invariant: WALL_JUMP_UP (%f) gives height %f m, must be >= 70%% of single jump height (%f m)"
		% [WALL_JUMP_UP, safe_walljump_h, 0.7 * safe_jump_h]
	)

	# story-014 cohérence physics tick rate : DISPLAY_TICK_RATE doit matcher
	# ProjectSettings physics/common/physics_ticks_per_second pour que les
	# invariants RESPAWN_DELAY/DISPLAY_TICK_RATE restent valides au runtime.
	assert(
		int(DISPLAY_TICK_RATE) == int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)),
		"DISPLAY_TICK_RATE (%d) doit matcher physics/common/physics_ticks_per_second (%d) project.godot"
		% [int(DISPLAY_TICK_RATE), int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))]
	)


func _physics_process(delta: float) -> void:
	# All gameplay mutations (velocity, position, rotation) happen here,
	# never in _process() (Control Manifest 2026-04-23 Core layer).
	#
	# Story-002: grounded horizontal movement.
	# Story-003: gravity + airborne state + air control.
	# Story-004: jump, double-jump (can_air_jump), coyote time.
	# Story-005: dash burst + exit momentum + cooldown.
	# Story-006: wall-run detection, reduced gravity, fall cap, timeout, exit.
	# Story-007: wall-jump (priority over double-jump in same tick).
	#
	# Tick ordering (story-007 priority requirement):
	#   0.  Track was_grounded (coyote).
	#   0b. Toggle raycasts.
	#   1.  Decrement timers.
	#   2.  Read movement input.
	#   3.  GROUNDED↔AIRBORNE state transitions.
	#   4.  Wall-run entry — MUST precede jump so wall-jump fires correctly on
	#       the same tick that wall-run activates (GDD Edge Cases line 286).
	#   5.  Jump handling — wall-jump branch first (story-007 AC-MV-32).
	#   6.  Coyote initialisation (only when transitioning without a jump).
	#   7.  Coyote decrement.
	#   8.  Dash entry — peut sortir WALL_RUNNING (GDD line 288 : dash gagne).
	#   9.  Wall-run physics tick (reduced gravity, fall cap, timeout, exit).
	#   10. Horizontal velocity (DASHING / momentum / normal control).
	#   11. Gravity (skipped DASHING / WALL_RUNNING).
	#   11b. Attack forward emit — APRÈS state machine, gated DEAD (D-6 rule 4).
	#   12. _apply_movement() — NaN safeguard + move_and_slide().

	# DEAD early-return — story-008 / AC-MV-40.
	# All inputs are ignored during the respawn delay. velocity==ZERO so
	# move_and_slide() is effectively a no-op (Jolt still needs the call for
	# internal cleanup / floor contact resolution).
	# Control Manifest 2026-04-23 Core: no Timer nodes — delta-based countdown.
	if _state == State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn(_checkpoint_position)
		_apply_movement()
		return

	# 0. Track previous state for transition detection (story-004 coyote).
	var was_grounded: bool = (_state == State.GROUNDED)

	# 0b. Toggle raycasts based on state — story-006 perf F7.
	# Raycasts are only active when neither Grounded, Dashing, nor Dead.
	# This prevents wasted physics queries and satisfies AC-6 + AC-7.
	var rays_active: bool = (
		_state != State.GROUNDED
		and _state != State.DASHING
		and _state != State.DEAD
	)
	_wall_ray_left.enabled = rays_active
	_wall_ray_right.enabled = rays_active

	# 1. Decrement cooldown and momentum timers (story-005).
	# No Timer nodes (Control Manifest forbidden). Delta-based, deterministic.
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	_momentum_timer = maxf(0.0, _momentum_timer - delta)

	# 2. Read input (story-002).
	var wish_dir_2d: Vector2 = InputManager.get_move_input_vector()
	var wish_dir_3d: Vector3 = Vector3.ZERO
	if wish_dir_2d.length_squared() > 0.0001:
		wish_dir_3d = (transform.basis * Vector3(wish_dir_2d.x, 0.0, wish_dir_2d.y)).normalized()

	# 3. State transitions GROUNDED↔AIRBORNE — skipped while DASHING or WALL_RUNNING (story-005/006).
	# Dash and wall-run each manage their own exit transitions.
	if _state != State.DASHING and _state != State.WALL_RUNNING:
		if _state == State.GROUNDED and not is_on_floor():
			_state = State.AIRBORNE
		elif _state == State.AIRBORNE and is_on_floor():
			_state = State.GROUNDED
			air_jumps_used = 0
			_coyote_timer_ticks = 0

	# 4. Wall-run entry check (story-006) — placed BEFORE jump handling (step 5)
	# so that a wall-run activated this tick is already in WALL_RUNNING state
	# when the jump check runs. This guarantees wall-jump priority on the same
	# tick that wall-run activates (story-007 / GDD Edge Cases line 286 / AC-3).
	# Raycasts are disabled during DASHING (step 0b) so only fires from AIRBORNE.
	_try_start_wall_run()

	# 5. Jump handling — skipped during DASHING (story-005, input lock AC-MV-23).
	# ADR-0004 D-1: poll was_pressed_this_tick — edge-triggered, consumed once per press.
	# Forbidden: Input.is_action_just_pressed (Control Manifest 2026-04-23 Core layer).
	#
	# Priority order (story-007 Control Manifest):
	#   a) WALL_RUNNING + jump → wall-jump (AC-MV-32): velocity overwritten, air_jumps_used = MAX.
	#   b) GROUNDED + jump → grounded jump (AC-MV-10).
	#   c) AIRBORNE + jump → coyote (AC-MV-14) or double-jump (AC-MV-11/12/13).
	var jumped_this_tick: bool = false
	if _state != State.DASHING:
		var jump_pressed: bool = InputManager.was_pressed_this_tick(&"jump")

		if _state == State.WALL_RUNNING and jump_pressed:
			# AC-MV-32: wall-jump — overwrite full velocity with lateral + vertical launch.
			# Forbidden: must reset _wall_normal (Control Manifest 2026-04-23).
			# AC-MV-35: set air_jumps_used = MAX_AIR_JUMPS to block post-wall double-jump.
			# ADR-0005 D-6 story-009: capture locals BEFORE any mutation so signal
			# payload carries pre-reset values (wall_normal is ZERO after reset).
			var wall_normal_at_jump: Vector3 = _wall_normal  # captured before reset
			var launch_vel: Vector3 = wall_normal_at_jump * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP
			velocity = launch_vel
			air_jumps_used = MAX_AIR_JUMPS
			_state = State.AIRBORNE
			_wall_normal = Vector3.ZERO  # reset after capture
			_wall_run_timer = 0.0
			wall_run_exited.emit()  # ADR-0005 D-6: exit WALL_RUNNING before wall_jumped
			wall_jumped.emit(wall_normal_at_jump, launch_vel)  # payload from pre-reset locals
			jumped_this_tick = true
		elif _state == State.GROUNDED and jump_pressed:
			# AC-MV-10: grounded jump — set velocity.y to JUMP_VELOCITY.
			velocity.y = JUMP_VELOCITY
			jumped_this_tick = true
		elif _state == State.AIRBORNE and jump_pressed:
			if _coyote_timer_ticks > 0:
				# AC-MV-14: coyote window active — execute grounded jump without consuming air jump.
				velocity.y = JUMP_VELOCITY
				_coyote_timer_ticks = 0
				jumped_this_tick = true
			elif can_air_jump and air_jumps_used < MAX_AIR_JUMPS:
				# AC-MV-11: double-jump — consume one air jump slot.
				# AC-MV-12: air_jumps_used >= MAX_AIR_JUMPS → branch skipped (no triple-jump).
				# AC-MV-13: can_air_jump == false → branch skipped (ability gated).
				velocity.y = AIR_JUMP_VELOCITY
				air_jumps_used += 1
				jumped_this_tick = true

	# 6. Coyote initialisation: set timer when transitioning GROUNDED→AIRBORNE
	# without an intentional jump (step-off, ledge walk, etc.) (story-004).
	if was_grounded and _state == State.AIRBORNE and not jumped_this_tick:
		_coyote_timer_ticks = COYOTE_TIME_TICKS

	# 7. Coyote decrement: tick down the window each AIRBORNE frame.
	# When the window expires (_coyote_timer_ticks reaches 0) the next jump
	# press falls through to the air-jump branch above.
	if _state == State.AIRBORNE and _coyote_timer_ticks > 0:
		_coyote_timer_ticks -= 1

	# 8. Dash entry check (story-005).
	# Evaluated before the horizontal control branch so an entry this tick
	# immediately sets state to DASHING and writes velocity in step 10.
	_try_start_dash(wish_dir_3d)

	# 9. Wall-run physics tick (story-006).
	# Manages reduced gravity, fall cap, timeout, and exit checks. AC-MV-30/31/33.
	if _state == State.WALL_RUNNING:
		_update_wall_run(delta)

	# 10. Horizontal velocity — DASHING takes full priority, then momentum, then normal control.
	if _state == State.DASHING:
		_apply_dash_state(delta)
	else:
		_apply_horizontal_control(delta, wish_dir_3d)

	# 11. Gravity: skipped during WALL_RUNNING (story-006) and DASHING (story-005 AC-MV-25).
	# GROUNDED: gravity applied but absorbed by move_and_slide() floor normal.
	# WALL_RUNNING applies its own reduced gravity inside _update_wall_run (step 9).
	if _state != State.WALL_RUNNING and _state != State.DASHING:
		velocity.y -= GRAVITY * delta

	# 11b. Attack forward — ADR-0005 D-2 / story-009 (AC-5).
	# was_pressed_this_tick() consumes the edge once per tick → max 1 emit per frame.
	# Gate: DEAD state blocks the emit (ADR-0005 D-6 rule 2).
	if _state != State.DEAD and InputManager.was_pressed_this_tick(&"attack"):
		attacked.emit()

	# 12. Move — resolves collisions and applies velocity (ADR-0001 Jolt).
	# story-012: safeguard NaN/Inf via _apply_movement() before move_and_slide().
	_apply_movement()

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Transitions the player to State.DEAD and starts the respawn countdown.
## Story-008 / AC-MV-40 / ADR-0005 D-8.
## Idempotent: repeated calls in the same tick are absorbed via early return (AC-MV-41).
## If dying during WALL_RUNNING, wall state is cleaned up immediately (ADR-0005 D-6:
## sub-state exit precedes terminal-state entry and its signal).
## Signal died.emit() — deferred to story-009.
func die() -> void:
	# Main-thread guard (ADR-0005 D-4) — die() est public, peut être appelée
	# depuis CombatSystem._physics_process (main thread garanti par Godot) ou
	# depuis GdUnit4 test runner (main thread). Toute autre origine (Thread,
	# WorkerThreadPool, Timer.timeout depuis non-main) viole D-4.
	assert(
		OS.get_thread_caller_id() == OS.get_main_thread_id(),
		"MovementController.die() doit être appelée depuis le main thread (ADR-0005 D-4)"
	)

	if _state == State.DEAD:
		return  # Idempotent — AC-MV-41 + ADR-0005 D-8

	# Save dash context for partial-cooldown decision at respawn (AC-MV-24).
	_was_dashing_at_death = (_state == State.DASHING)

	# ADR-0005 D-6 / story-009: emit sub-state exit signals BEFORE entering DEAD.
	# Order: source-state exit signal → DEAD transition → died signal (terminal).
	if _state == State.DASHING:
		# Dash burst interrupted: emit dash_ended so animation/VFX consumers
		# can cancel the dash effect immediately.
		dash_ended.emit()
	elif _state == State.WALL_RUNNING:
		# Wall-run bookkeeping reset — mirrors _exit_wall_run without state change.
		_wall_normal = Vector3.ZERO
		_wall_run_timer = 0.0
		wall_run_exited.emit()

	_state = State.DEAD
	velocity = Vector3.ZERO
	_respawn_timer = RESPAWN_DELAY_S

	# Désactiver les raycasts pendant la fenêtre DEAD pour éviter les queries
	# Jolt inutiles (godot-specialist review 2026-04-27 Issue 5). Réactivés
	# automatiquement step 0b au respawn quand state != GROUNDED/DASHING/DEAD.
	if _wall_ray_left != null:
		_wall_ray_left.enabled = false
	if _wall_ray_right != null:
		_wall_ray_right.enabled = false

	died.emit()  # ADR-0005 D-2 / story-009 — terminal signal, after state set


## Stores the position the player will be teleported to on the next respawn.
## Story-008 / AC-MV-40. Called by the Checkpoint System (story-015+).
## Safe to call at any time, including during DEAD state (sets future destination).
func set_checkpoint(pos: Vector3) -> void:
	_checkpoint_position = pos


## Sets a capability flag. Called by UpgradeSystem when a node-level upgrade is acquired.
## Story-013 / AC-MV-61: only entry point for mutating gated capabilities; consumers may not
## write can_dash/can_air_jump/can_wall_run directly (read-only F7 pattern, ADR-0005 REQ-8).
## Valid capability names: &"dash", &"air_jump", &"wall_run".
## Unknown capability names log a push_error and leave all flags unchanged.
func set_capability(cap: StringName, enabled: bool) -> void:
	match cap:
		&"dash":
			_can_dash = enabled
		&"air_jump":
			_can_air_jump = enabled
		&"wall_run":
			_can_wall_run = enabled
		_:
			push_error(
				"Unknown capability: %s (expected dash / air_jump / wall_run)" % cap
			)

# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

func _get_state() -> State:
	return _state


func _get_can_air_jump() -> bool:
	return _can_air_jump


func _get_can_dash() -> bool:
	return _can_dash


func _get_can_wall_run() -> bool:
	return _can_wall_run


func _get_dash_cooldown_timer() -> float:
	return _dash_cooldown_timer


func _get_dash_cooldown_ratio() -> float:
	return 1.0 - clampf(_dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0)


func _get_is_dashing() -> bool:
	return _state == State.DASHING


## Checks dash input and starts the DASHING state if conditions are met.
## Called each tick before horizontal control. Story-005 / AC-MV-20 through AC-MV-25.
## AC-MV-21 : can_dash == false → silently ignored (no cooldown triggered).
## AC-MV-22 : cooldown > 0 → _on_dash_rejected() stub called.
## AC-MV-25 : velocity.y reset to 0.0 at entry tick.
## Fallback : zero wish_dir → uses -transform.basis.z projected to XZ plane.
func _try_start_dash(wish_dir_3d: Vector3) -> void:
	if not InputManager.was_pressed_this_tick(&"dash"):
		return

	# State gate: ignore during DEAD or already DASHING.
	if _state == State.DEAD or _state == State.DASHING:
		return

	# Ability gate: can_dash == false → silent ignore (AC-MV-21, story-013 wires later).
	if not can_dash:
		return

	# Cooldown gate: reject with hook if cooldown is still running (AC-MV-22).
	if _dash_cooldown_timer > 0.0:
		_on_dash_rejected()
		return

	# Compute dash direction: wish_dir XZ, fallback to body forward.
	var horiz_wish: Vector3 = Vector3(wish_dir_3d.x, 0.0, wish_dir_3d.z)
	var dash_dir: Vector3
	if horiz_wish.length_squared() < 0.0001:
		# Fallback: project body forward (-Z in local space) to horizontal plane.
		var fwd: Vector3 = -transform.basis.z
		fwd.y = 0.0
		dash_dir = fwd.normalized()
	else:
		dash_dir = horiz_wish.normalized()

	# GDD line 288 + ADR-0005 D-6 : si dash pressé pendant WALL_RUNNING, le dash
	# gagne — wall_normal reset, sortie wall-run émise AVANT entrée Dashing.
	# Sub-state exit signal precedes terminal-state entry signal.
	var _was_wall_running: bool = (_state == State.WALL_RUNNING)
	if _was_wall_running:
		_wall_normal = Vector3.ZERO
		_wall_run_timer = 0.0
		wall_run_exited.emit()  # ADR-0005 D-6 ordre : exit avant entrée

	_dash_dir = dash_dir
	_state = State.DASHING
	dash_timer = DASH_DURATION
	_dash_cooldown_timer = DASH_COOLDOWN
	velocity.y = 0.0  # AC-MV-25: reset vertical velocity on entry
	dash_started.emit(_dash_dir, DASH_SPEED)  # ADR-0005 D-2 / story-009


## Applies velocity while in DASHING state and handles the exit transition.
## Called from _physics_process when _state == State.DASHING. Story-005 / AC-MV-20.
## Direction is locked (_dash_dir) — horizontal input is ignored (AC-MV-23).
## Gravity is suppressed externally (step 9 checks for DASHING).
func _apply_dash_state(delta: float) -> void:
	# Lock velocity to dash direction — overrides any prior horizontal control.
	velocity.x = _dash_dir.x * DASH_SPEED
	velocity.z = _dash_dir.z * DASH_SPEED
	velocity.y = 0.0  # keep vertical suppressed throughout burst

	dash_timer -= delta

	if dash_timer <= 0.0:
		# Dash burst complete: apply exit speed and start momentum window.
		velocity.x = _dash_dir.x * DASH_EXIT_SPEED
		velocity.z = _dash_dir.z * DASH_EXIT_SPEED
		_momentum_timer = DASH_MOMENTUM_WINDOW
		# Transition to appropriate state based on floor contact.
		_state = State.GROUNDED if is_on_floor() else State.AIRBORNE
		dash_ended.emit()  # ADR-0005 D-2 / story-009 — emitted after state transition


## Applies horizontal velocity: momentum deceleration (post-dash) or normal grounded/airborne control.
## Called from _physics_process when _state != State.DASHING. Story-005 momentum + stories 002-003.
func _apply_horizontal_control(delta: float, wish_dir_3d: Vector3) -> void:
	# Momentum window: decelerate linearly from DASH_EXIT_SPEED → MOVE_SPEED (AC-MV-20).
	# Overrides normal horizontal control while the window is active.
	if _momentum_timer > 0.0 and _state != State.DEAD:
		var t: float = _momentum_timer / DASH_MOMENTUM_WINDOW  # 1.0 → 0.0
		var current_speed: float = MOVE_SPEED + (DASH_EXIT_SPEED - MOVE_SPEED) * t
		velocity.x = _dash_dir.x * current_speed
		velocity.z = _dash_dir.z * current_speed
		return

	# Normal horizontal control (stories 002–003).
	if _state == State.GROUNDED:
		# Instant stop: velocity set directly each tick (GDD Rule 1 / TR-mov-001).
		# Release input → wish_dir_3d = ZERO → velocity 0 in one tick (AC-MV-02).
		velocity.x = wish_dir_3d.x * MOVE_SPEED
		velocity.z = wish_dir_3d.z * MOVE_SPEED
	elif _state == State.AIRBORNE:
		# Air control: move_toward clamps to target without exceeding it (story-003).
		# GDD Formula: move_toward(velocity.xz, wish_dir * MOVE_SPEED, AIR_CONTROL_FACTOR * delta).
		var air_wish: Vector3 = wish_dir_3d * MOVE_SPEED
		velocity.x = move_toward(velocity.x, air_wish.x, AIR_CONTROL_FACTOR * delta)
		velocity.z = move_toward(velocity.z, air_wish.z, AIR_CONTROL_FACTOR * delta)


## Hook called when dash input is rejected due to cooldown still active (AC-MV-22).
## Story-005 stub — body intentionally empty at MVP.
## Audio playback (dash_reject.wav) will be wired post-MVP in the Audio epic.
func _on_dash_rejected() -> void:
	pass  # Hook for Audio epic post-MVP — story-005 stub


## Returns the backing wall normal field (read-only property getter).
## Story-006 / ADR-0005 REQ-8: no external setter on wall_normal.
func _get_wall_normal() -> Vector3:
	return _wall_normal


## Checks wall-run entry conditions and transitions to WALL_RUNNING if met.
## Called each tick from _physics_process after dash entry (step 7b).
## Only fires when AIRBORNE — raycasts are disabled during DASHING (step 0b),
## so a Dashing→WallRunning direct transition is architecturally impossible.
## Story-006 / AC-MV-30 / AC-MV-34 (left priority in narrow corridor).
func _try_start_wall_run() -> void:
	if _state != State.AIRBORNE:
		return
	if not can_wall_run:
		return
	# AC-MV-30: horizontal speed must exceed threshold.
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed <= WALL_RUN_MIN_SPEED:
		return

	# Force fresh queries before reading is_colliding() (Jolt deferred update).
	_wall_ray_left.force_raycast_update()
	_wall_ray_right.force_raycast_update()

	var left_hit: bool = _wall_ray_left.is_colliding()
	var right_hit: bool = _wall_ray_right.is_colliding()

	if not left_hit and not right_hit:
		return

	# AC-MV-34: left ray has priority in narrow corridors where both rays hit.
	_wall_normal = _wall_ray_left.get_collision_normal() if left_hit else _wall_ray_right.get_collision_normal()
	_state = State.WALL_RUNNING
	_wall_run_timer = 0.0
	wall_run_entered.emit(_wall_normal)  # ADR-0005 D-2 / story-009


## Runs one wall-run physics tick: applies reduced gravity, enforces fall cap,
## checks timeout and contact-loss exits.
## Called from _physics_process (step 7c) only when _state == WALL_RUNNING.
## Story-006 / AC-MV-30 (reduced gravity) / AC-MV-31 (exit on no contact) /
##             AC-MV-33 (timeout) / Fall cap.
func _update_wall_run(delta: float) -> void:
	_wall_run_timer += delta

	# Force fresh raycast results before exit checks.
	_wall_ray_left.force_raycast_update()
	_wall_ray_right.force_raycast_update()

	# Floor landing exits to GROUNDED — highest priority exit.
	if is_on_floor():
		_exit_wall_run(State.GROUNDED)
		return

	# Timeout exit — AC-MV-33.
	if _wall_run_timer >= WALL_RUN_MAX_DURATION:
		_exit_wall_run(State.AIRBORNE)
		return

	# Contact-loss exit — AC-MV-31: both rays no longer touch a wall.
	if not _wall_ray_left.is_colliding() and not _wall_ray_right.is_colliding():
		_exit_wall_run(State.AIRBORNE)
		return

	# Still wall-running: apply reduced gravity and clamp fall speed.
	velocity.y -= WALL_RUN_GRAVITY * delta
	velocity.y = maxf(velocity.y, -WALL_RUN_FALL_CAP)


## Exits the wall-run state cleanly, resetting all wall-run bookkeeping.
## Story-006 / AC-MV-31 / AC-MV-33. Called by _update_wall_run on any exit path.
## target_state must be AIRBORNE or GROUNDED — never WALL_RUNNING or DASHING.
func _exit_wall_run(target_state: State) -> void:
	_state = target_state
	_wall_normal = Vector3.ZERO
	_wall_run_timer = 0.0
	wall_run_exited.emit()  # ADR-0005 D-2 / story-009 — emitted after reset (no payload)


## Teleports the player to pos and resets all movement state to a clean GROUNDED baseline.
## Story-008 / AC-MV-40 — called from _physics_process when _respawn_timer expires.
## AC-MV-24: partial dash cooldown (50%) if _was_dashing_at_death, full reset (0.0) otherwise.
## AC-MV-42: full reset when dying outside of DASHING.
## Signal respawned.emit(pos) — deferred to story-009.
func _respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	air_jumps_used = 0
	_wall_normal = Vector3.ZERO
	_wall_run_timer = 0.0
	_momentum_timer = 0.0
	dash_timer = 0.0
	_coyote_timer_ticks = 0
	if _was_dashing_at_death:
		_dash_cooldown_timer = DASH_COOLDOWN * 0.5  # AC-MV-24 partial cooldown
	else:
		_dash_cooldown_timer = 0.0  # AC-MV-42 full reset — dash immediately available
	_was_dashing_at_death = false  # consumed — must reset or AC-MV-24 only fires once
	_state = State.GROUNDED
	respawned.emit(pos)  # ADR-0005 D-2 / story-009 — payload is checkpoint position


## Applies the NaN/Inf safeguard then calls move_and_slide().
## story-012 / AC-MV-70 / GDD Edge Cases "Vélocité NaN ou Infinity".
##
## Placement: called at the end of every _physics_process() branch (normal flow and
## DEAD early-return) AFTER all velocity mutations (gravity, dash, wall-run fall cap,
## air control, jump). Never call move_and_slide() directly from _physics_process —
## all callers must go through this helper to guarantee the safeguard fires.
##
## Pattern: is_finite() (NOT clamp) — IEEE 754 compliant. clamp(NaN, ...) == NaN,
## and a hard cap would break legitimate deep-fall velocities (godot-specialist F8 r3).
## push_error: non-silent, recovery-oriented (no crash in release builds — ADR-0001).
func _apply_movement() -> void:
	if not velocity.is_finite():
		push_error(
			"velocity NaN/Inf detected at tick %d — reset to zero (ADR-0001 autorité + GDD Edge Cases)"
			% Engine.get_physics_frames()
		)
		velocity = Vector3.ZERO
	move_and_slide()


# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

# (Reserved — connected in _ready() when signals are introduced in story-009+)
