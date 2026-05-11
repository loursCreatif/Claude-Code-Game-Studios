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
##        story-014-tech-debt-cleanup (TD-008 : constantes extraites → movement_constants.gd)
## Control Manifest: 2026-04-23 Core layer

class_name MovementController
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Constants — imported from movement_constants.gd (TD-008)
# ---------------------------------------------------------------------------

## Toutes les constantes numériques et l'enum State sont définis dans
## movement_constants.gd. On les expose ici via des constantes de délégation
## pour que le reste du codebase ne change pas son point d'accès.
const MC := preload("res://src/gameplay/player/movement_constants.gd")

## Re-export de l'enum State pour que les consommateurs externes puissent
## écrire MovementController.State.GROUNDED (compatibilité ADR-0005 REQ-8).
const State := MC.State

const MOVE_SPEED: float = MC.MOVE_SPEED
const AIR_CONTROL_FACTOR: float = MC.AIR_CONTROL_FACTOR
const GRAVITY: float = MC.GRAVITY
const JUMP_VELOCITY: float = MC.JUMP_VELOCITY
const AIR_JUMP_VELOCITY: float = MC.AIR_JUMP_VELOCITY
const MAX_AIR_JUMPS: int = MC.MAX_AIR_JUMPS
const COYOTE_TIME_TICKS: int = MC.COYOTE_TIME_TICKS
const DASH_SPEED: float = MC.DASH_SPEED
const DASH_DURATION: float = MC.DASH_DURATION
const DASH_EXIT_SPEED: float = MC.DASH_EXIT_SPEED
const DASH_MOMENTUM_WINDOW: float = MC.DASH_MOMENTUM_WINDOW
const DASH_COOLDOWN: float = MC.DASH_COOLDOWN
const RESPAWN_DELAY_MS: float = MC.RESPAWN_DELAY_MS
const DISPLAY_TICK_RATE: float = MC.DISPLAY_TICK_RATE
const RESPAWN_DELAY_S: float = MC.RESPAWN_DELAY_S
const WALL_DETECT_MARGIN: float = MC.WALL_DETECT_MARGIN
const WALL_RUN_MIN_SPEED: float = MC.WALL_RUN_MIN_SPEED
const WALL_RUN_GRAVITY: float = MC.WALL_RUN_GRAVITY
const WALL_RUN_FALL_CAP: float = MC.WALL_RUN_FALL_CAP
const WALL_RUN_MAX_DURATION: float = MC.WALL_RUN_MAX_DURATION
const WALL_JUMP_SIDE: float = MC.WALL_JUMP_SIDE
const WALL_JUMP_UP: float = MC.WALL_JUMP_UP

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
signal died()

## Emitted when the player teleports to the checkpoint after the respawn delay.
## spawn_position matches the value passed to set_checkpoint() at die() time.
signal respawned(spawn_position: Vector3)

## Emitted each tick the attack input edge is consumed and the player is not DEAD.
signal attacked()

# ---------------------------------------------------------------------------
# Export variables
# (Reserved — balance tuning exposed in story-008+)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

## Read-only current movement state.
## ADR-0005 REQ-8: no external setter.
var state: MC.State:
	get = _get_state

## Number of air jumps consumed since last landing.
var air_jumps_used: int = 0

## Read-only: whether the air-jump ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start.
var can_air_jump: bool:
	get = _get_can_air_jump

## Read-only: whether the dash ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start.
var can_dash: bool:
	get = _get_can_dash

## Read-only: whether the wall-run ability is unlocked.
## Story-013 / AC-MV-60: false on fresh start.
var can_wall_run: bool:
	get = _get_can_wall_run

## Read-only wall normal of the currently running surface.
## Vector3.ZERO when not in WALL_RUNNING state.
var wall_normal: Vector3:
	get = _get_wall_normal

## Remaining dash burst time (seconds). Counts down from DASH_DURATION to 0.
var dash_timer: float = 0.0

## Read-only: remaining dash cooldown time in seconds.
var dash_cooldown_timer: float:
	get = _get_dash_cooldown_timer

## Read-only: cooldown progress ratio [0.0 ready → 1.0 just used].
var dash_cooldown_ratio: float:
	get = _get_dash_cooldown_ratio

## Read-only: true when player is actively in DASHING state.
var is_dashing: bool:
	get = _get_is_dashing

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

var _state: MC.State = MC.State.GROUNDED
var _can_air_jump: bool = false
var _can_dash: bool = false
var _can_wall_run: bool = false

## Remaining coyote time in physics ticks.
var _coyote_timer_ticks: int = 0

## Remaining cooldown before next dash is allowed (seconds).
var _dash_cooldown_timer: float = 0.0

## Dash direction locked at entry tick (XZ plane only, normalized).
var _dash_dir: Vector3 = Vector3.ZERO

## Remaining time in the post-dash momentum deceleration window (seconds).
var _momentum_timer: float = 0.0

## Backing field for the wall_normal read-only property.
var _wall_normal: Vector3 = Vector3.ZERO

## Elapsed time in current wall-run (seconds).
var _wall_run_timer: float = 0.0

## Last known checkpoint position.
var _checkpoint_position: Vector3 = Vector3.ZERO

## Countdown timer for the respawn delay (seconds).
var _respawn_timer: float = 0.0

## Captures whether the player was DASHING at the moment die() was called.
var _was_dashing_at_death: bool = false

# ---------------------------------------------------------------------------
# @onready variables
# ---------------------------------------------------------------------------

@onready var _wall_ray_left: RayCast3D = %WallRayLeft
@onready var _wall_ray_right: RayCast3D = %WallRayRight

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ADR-0001 TR-mov-007 : Jolt default_gravity must be 0.0.
	assert(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) == 0.0,
		"ADR-0001 TR-mov-007: default_gravity must be 0.0 (custom GRAVITY=24 in MovementController)"
	)

	# ADR-0005 VC-7 : respawn delay must cover at least one full physics tick.
	assert(
		RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE,
		"ADR-0005 VC-7 invariant violated: RESPAWN_DELAY_MS (%f ms) < one physics tick (%f ms)"
		% [RESPAWN_DELAY_MS, 1000.0 / DISPLAY_TICK_RATE]
	)

	# story-005 invariant: DASH_SPEED >= 2.5× MOVE_SPEED.
	assert(
		DASH_SPEED >= MOVE_SPEED * 2.5,
		"story-005 invariant: DASH_SPEED (%f) must be >= MOVE_SPEED * 2.5 (%f)"
		% [DASH_SPEED, MOVE_SPEED * 2.5]
	)

	# story-005 invariant: cooldown >= 4× dash duration.
	assert(
		DASH_COOLDOWN >= 4.0 * DASH_DURATION,
		"story-005 invariant: DASH_COOLDOWN (%f) must be >= 4 * DASH_DURATION (%f)"
		% [DASH_COOLDOWN, 4.0 * DASH_DURATION]
	)

	# story-007 invariant: wall-jump vertical gain >= 70% of single-jump peak height.
	var safe_walljump_h: float = (WALL_JUMP_UP * WALL_JUMP_UP) / (2.0 * GRAVITY)
	var safe_jump_h: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
	assert(
		safe_walljump_h >= 0.7 * safe_jump_h,
		"story-007 invariant: WALL_JUMP_UP (%f) gives height %f m, must be >= 70%% of single jump height (%f m)"
		% [WALL_JUMP_UP, safe_walljump_h, 0.7 * safe_jump_h]
	)

	# story-014 : DISPLAY_TICK_RATE doit matcher physics/common/physics_ticks_per_second.
	assert(
		int(DISPLAY_TICK_RATE) == int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)),
		"DISPLAY_TICK_RATE (%d) doit matcher physics/common/physics_ticks_per_second (%d) project.godot"
		% [int(DISPLAY_TICK_RATE), int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))]
	)


func _physics_process(delta: float) -> void:
	# All gameplay mutations happen here — ADR-0001 / Control Manifest 2026-04-23.
	#
	# Tick ordering :
	#   0.  Track was_grounded (coyote).
	#   0b. Toggle raycasts.
	#   1.  Decrement timers.
	#   2.  Read movement input.
	#   3.  GROUNDED↔AIRBORNE transitions.
	#   4.  Wall-run entry (before jump so wall-jump fires correctly same tick).
	#   5.  Jump handling (wall-jump priority).
	#   6.  Coyote initialisation.
	#   7.  Coyote decrement.
	#   8.  Dash entry.
	#   9.  Wall-run physics tick.
	#   10. Horizontal velocity.
	#   11. Gravity.
	#   11b.Attack forward emit.
	#   12. _apply_movement().

	# DEAD early-return — story-008 / AC-MV-40.
	if _state == MC.State.DEAD:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn(_checkpoint_position)
		_apply_movement()
		return

	# 0. Track previous state for transition detection (coyote).
	var was_grounded: bool = (_state == MC.State.GROUNDED)

	# 0b. Toggle raycasts — story-006 perf F7.
	var rays_active: bool = (
		_state != MC.State.GROUNDED
		and _state != MC.State.DASHING
		and _state != MC.State.DEAD
	)
	_wall_ray_left.enabled = rays_active
	_wall_ray_right.enabled = rays_active

	# 1. Decrement cooldown and momentum timers.
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)
	_momentum_timer = maxf(0.0, _momentum_timer - delta)

	# 2. Read input.
	var wish_dir_2d: Vector2 = InputManager.get_move_input_vector()
	var wish_dir_3d: Vector3 = Vector3.ZERO
	if wish_dir_2d.length_squared() > 0.0001:
		wish_dir_3d = (transform.basis * Vector3(wish_dir_2d.x, 0.0, wish_dir_2d.y)).normalized()

	# 3. State transitions GROUNDED↔AIRBORNE.
	if _state != MC.State.DASHING and _state != MC.State.WALL_RUNNING:
		if _state == MC.State.GROUNDED and not is_on_floor():
			_state = MC.State.AIRBORNE
		elif _state == MC.State.AIRBORNE and is_on_floor():
			_state = MC.State.GROUNDED
			air_jumps_used = 0
			_coyote_timer_ticks = 0

	# 4. Wall-run entry check — before jump so wall-jump fires correctly same tick.
	_try_start_wall_run()

	# 5. Jump handling.
	var jumped_this_tick: bool = false
	if _state != MC.State.DASHING:
		var jump_pressed: bool = InputManager.was_pressed_this_tick(&"jump")

		if _state == MC.State.WALL_RUNNING and jump_pressed:
			# AC-MV-32 : wall-jump.
			var wall_normal_at_jump: Vector3 = _wall_normal
			var launch_vel: Vector3 = wall_normal_at_jump * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP
			velocity = launch_vel
			air_jumps_used = MAX_AIR_JUMPS
			_state = MC.State.AIRBORNE
			_wall_normal = Vector3.ZERO
			_wall_run_timer = 0.0
			wall_run_exited.emit()
			wall_jumped.emit(wall_normal_at_jump, launch_vel)
			jumped_this_tick = true
		elif _state == MC.State.GROUNDED and jump_pressed:
			velocity.y = JUMP_VELOCITY
			jumped_this_tick = true
		elif _state == MC.State.AIRBORNE and jump_pressed:
			if _coyote_timer_ticks > 0:
				velocity.y = JUMP_VELOCITY
				_coyote_timer_ticks = 0
				jumped_this_tick = true
			elif can_air_jump and air_jumps_used < MAX_AIR_JUMPS:
				velocity.y = AIR_JUMP_VELOCITY
				air_jumps_used += 1
				jumped_this_tick = true

	# 6. Coyote initialisation.
	if was_grounded and _state == MC.State.AIRBORNE and not jumped_this_tick:
		_coyote_timer_ticks = COYOTE_TIME_TICKS

	# 7. Coyote decrement.
	if _state == MC.State.AIRBORNE and _coyote_timer_ticks > 0:
		_coyote_timer_ticks -= 1

	# 8. Dash entry check.
	_try_start_dash(wish_dir_3d)

	# 9. Wall-run physics tick.
	if _state == MC.State.WALL_RUNNING:
		_update_wall_run(delta)

	# 10. Horizontal velocity.
	if _state == MC.State.DASHING:
		_apply_dash_state(delta)
	else:
		_apply_horizontal_control(delta, wish_dir_3d)

	# 11. Gravity: skipped during WALL_RUNNING and DASHING.
	if _state != MC.State.WALL_RUNNING and _state != MC.State.DASHING:
		velocity.y -= GRAVITY * delta

	# 11b. Attack forward — ADR-0005 D-2 / story-009.
	if _state != MC.State.DEAD and InputManager.was_pressed_this_tick(&"attack"):
		attacked.emit()

	# 12. Move.
	_apply_movement()

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Transitions the player to State.DEAD and starts the respawn countdown.
## Story-008 / AC-MV-40 / ADR-0005 D-8. Idempotent (AC-MV-41).
func die() -> void:
	assert(
		OS.get_thread_caller_id() == OS.get_main_thread_id(),
		"MovementController.die() doit être appelée depuis le main thread (ADR-0005 D-4)"
	)

	if _state == MC.State.DEAD:
		return

	_was_dashing_at_death = (_state == MC.State.DASHING)

	# ADR-0005 D-6 : emit sub-state exit signals BEFORE entering DEAD.
	if _state == MC.State.DASHING:
		dash_ended.emit()
	elif _state == MC.State.WALL_RUNNING:
		_wall_normal = Vector3.ZERO
		_wall_run_timer = 0.0
		wall_run_exited.emit()

	_state = MC.State.DEAD
	velocity = Vector3.ZERO
	_respawn_timer = RESPAWN_DELAY_S

	if _wall_ray_left != null:
		_wall_ray_left.enabled = false
	if _wall_ray_right != null:
		_wall_ray_right.enabled = false

	died.emit()


## Stores the position the player will be teleported to on the next respawn.
## Story-008 / AC-MV-40.
func set_checkpoint(pos: Vector3) -> void:
	_checkpoint_position = pos


## Sets a capability flag. Called by UpgradeSystem when an upgrade is acquired.
## Story-013 / AC-MV-61. Valid names : &"dash", &"air_jump", &"wall_run".
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

func _get_state() -> MC.State:
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
	return _state == MC.State.DASHING


## Checks dash input and starts the DASHING state if conditions are met.
## Story-005 / AC-MV-20–25.
func _try_start_dash(wish_dir_3d: Vector3) -> void:
	if not InputManager.was_pressed_this_tick(&"dash"):
		return

	if _state == MC.State.DEAD or _state == MC.State.DASHING:
		return

	if not can_dash:
		return

	if _dash_cooldown_timer > 0.0:
		_on_dash_rejected()
		return

	var horiz_wish: Vector3 = Vector3(wish_dir_3d.x, 0.0, wish_dir_3d.z)
	var dash_dir: Vector3
	if horiz_wish.length_squared() < 0.0001:
		var fwd: Vector3 = -transform.basis.z
		fwd.y = 0.0
		dash_dir = fwd.normalized()
	else:
		dash_dir = horiz_wish.normalized()

	# ADR-0005 D-6 : si dash pressé pendant WALL_RUNNING, wall_run_exited AVANT dash entry.
	var _was_wall_running: bool = (_state == MC.State.WALL_RUNNING)
	if _was_wall_running:
		_wall_normal = Vector3.ZERO
		_wall_run_timer = 0.0
		wall_run_exited.emit()

	_dash_dir = dash_dir
	_state = MC.State.DASHING
	dash_timer = DASH_DURATION
	_dash_cooldown_timer = DASH_COOLDOWN
	velocity.y = 0.0
	dash_started.emit(_dash_dir, DASH_SPEED)


## Applies velocity while in DASHING state and handles the exit transition.
## Story-005 / AC-MV-20.
func _apply_dash_state(delta: float) -> void:
	velocity.x = _dash_dir.x * DASH_SPEED
	velocity.z = _dash_dir.z * DASH_SPEED
	velocity.y = 0.0

	dash_timer -= delta

	if dash_timer <= 0.0:
		velocity.x = _dash_dir.x * DASH_EXIT_SPEED
		velocity.z = _dash_dir.z * DASH_EXIT_SPEED
		_momentum_timer = DASH_MOMENTUM_WINDOW
		_state = MC.State.GROUNDED if is_on_floor() else MC.State.AIRBORNE
		dash_ended.emit()


## Applies horizontal velocity: momentum deceleration or normal control.
## Story-005 momentum + stories 002–003.
func _apply_horizontal_control(delta: float, wish_dir_3d: Vector3) -> void:
	if _momentum_timer > 0.0 and _state != MC.State.DEAD:
		var t: float = _momentum_timer / DASH_MOMENTUM_WINDOW
		var current_speed: float = MOVE_SPEED + (DASH_EXIT_SPEED - MOVE_SPEED) * t
		velocity.x = _dash_dir.x * current_speed
		velocity.z = _dash_dir.z * current_speed
		return

	if _state == MC.State.GROUNDED:
		velocity.x = wish_dir_3d.x * MOVE_SPEED
		velocity.z = wish_dir_3d.z * MOVE_SPEED
	elif _state == MC.State.AIRBORNE:
		var air_wish: Vector3 = wish_dir_3d * MOVE_SPEED
		velocity.x = move_toward(velocity.x, air_wish.x, AIR_CONTROL_FACTOR * delta)
		velocity.z = move_toward(velocity.z, air_wish.z, AIR_CONTROL_FACTOR * delta)


## Hook called when dash input is rejected due to cooldown (AC-MV-22).
## Story-005 stub — body intentionally empty at MVP.
func _on_dash_rejected() -> void:
	pass


## Returns the backing wall normal field (read-only property getter).
func _get_wall_normal() -> Vector3:
	return _wall_normal


## Checks wall-run entry conditions and transitions to WALL_RUNNING if met.
## Story-006 / AC-MV-30 / AC-MV-34.
func _try_start_wall_run() -> void:
	if _state != MC.State.AIRBORNE:
		return
	if not can_wall_run:
		return
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed <= WALL_RUN_MIN_SPEED:
		return

	_wall_ray_left.force_raycast_update()
	_wall_ray_right.force_raycast_update()

	var left_hit: bool = _wall_ray_left.is_colliding()
	var right_hit: bool = _wall_ray_right.is_colliding()

	if not left_hit and not right_hit:
		return

	# AC-MV-34 : left ray has priority in narrow corridors.
	_wall_normal = _wall_ray_left.get_collision_normal() if left_hit else _wall_ray_right.get_collision_normal()
	_state = MC.State.WALL_RUNNING
	_wall_run_timer = 0.0
	wall_run_entered.emit(_wall_normal)


## Runs one wall-run physics tick: reduced gravity, fall cap, timeout, contact-loss exit.
## Story-006 / AC-MV-30/31/33.
func _update_wall_run(delta: float) -> void:
	_wall_run_timer += delta

	_wall_ray_left.force_raycast_update()
	_wall_ray_right.force_raycast_update()

	if is_on_floor():
		_exit_wall_run(MC.State.GROUNDED)
		return

	if _wall_run_timer >= WALL_RUN_MAX_DURATION:
		_exit_wall_run(MC.State.AIRBORNE)
		return

	if not _wall_ray_left.is_colliding() and not _wall_ray_right.is_colliding():
		_exit_wall_run(MC.State.AIRBORNE)
		return

	velocity.y -= WALL_RUN_GRAVITY * delta
	velocity.y = maxf(velocity.y, -WALL_RUN_FALL_CAP)


## Exits the wall-run state cleanly, resetting all wall-run bookkeeping.
## Story-006 / AC-MV-31/33. target_state must be AIRBORNE or GROUNDED.
func _exit_wall_run(target_state: MC.State) -> void:
	_state = target_state
	_wall_normal = Vector3.ZERO
	_wall_run_timer = 0.0
	wall_run_exited.emit()


## Teleports the player to pos and resets all movement state to a clean GROUNDED baseline.
## Story-008 / AC-MV-40/24/42.
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
		_dash_cooldown_timer = DASH_COOLDOWN * 0.5
	else:
		_dash_cooldown_timer = 0.0
	_was_dashing_at_death = false
	_state = MC.State.GROUNDED
	respawned.emit(pos)


## Applies the NaN/Inf safeguard then calls move_and_slide().
## story-012 / AC-MV-70.
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
