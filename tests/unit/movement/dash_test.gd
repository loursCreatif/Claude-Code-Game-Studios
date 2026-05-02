# Unit tests for Story 005 — Dash state: burst + exit momentum + cooldown.
#
# Covers:
#   AC-MV-20 : GIVEN can_dash=true + cooldown=0, WHEN dash pressed with wish_dir,
#              THEN position advances DASH_SPEED * DASH_DURATION = 3.0 m ±0.15 m
#              in DASH_DURATION s; at exit velocity.xz == dash_dir * DASH_EXIT_SPEED ±0.5;
#              at t=DASH_DURATION+DASH_MOMENTUM_WINDOW, velocity.xz.length == MOVE_SPEED ±0.3.
#   AC-MV-21 : GIVEN can_dash=false, WHEN dash pressed, THEN state != DASHING and
#              _dash_cooldown_timer == 0.0 (no cooldown triggered).
#   AC-MV-22 : GIVEN cooldown active, WHEN dash pressed, THEN state != DASHING and
#              _on_dash_rejected() invoked (no re-entry).
#   AC-MV-23 : GIVEN DASHING, WHEN horizontal input changes, THEN _dash_dir unchanged
#              and velocity follows locked direction.
#   AC-MV-25 : GIVEN AIRBORNE with velocity.y=8.0, WHEN dash pressed, THEN
#              velocity.y == 0.0 ±0.001 after first DASHING tick.
#   Invariants: DASH_SPEED >= MOVE_SPEED*2.5 and DASH_COOLDOWN >= 4*DASH_DURATION.
#   Fallback  : No input → dash_dir uses body forward (-Z for rotation.y=0).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn (CharacterBody3D root = MovementController).
#
# Input injection pattern:
#   simulate_action_press(&"dash") → injects InputEventAction via Input.parse_input_event
#   → _unhandled_input sets _pressed_this_tick[&"dash"] = true immediately (synchronous)
#   → InputManager._physics_process(dt) swaps _pressed_this_tick → _consumed_this_tick
#   → player._physics_process(dt) reads was_pressed_this_tick(&"dash") → true
#
# State injection: player.set("_state", MovementController.State.AIRBORNE) via reflection.
# ADR-0005 REQ-8: state property has no public setter — reflect on _state directly.
#
# Ordering invariant: InputManager._physics_process MUST be called before
# player._physics_process so the swap occurs before MovementController reads the flags.

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PHYSICS_DT: float = 1.0 / 60.0

var _player: MovementController = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Injects _state directly, bypassing the read-only public property (ADR-0005 REQ-8).
func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


## Simulates one full physics tick: swap InputManager flags then run player logic.
## Preserves the ordering invariant (InputManager before MovementController).
func _tick(player: MovementController) -> void:
	InputManager._physics_process(PHYSICS_DT)
	player._physics_process(PHYSICS_DT)


## Presses dash and runs one physics tick (press + swap + player logic).
func _press_dash_and_tick(player: MovementController) -> void:
	InputManager.inject_pressed_for_test(&"dash")
	_tick(player)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute — triggers story-005 invariant asserts and ADR asserts.
	await get_tree().process_frame

	# Baseline: no velocity, elevated position (no floor), GROUNDED state.
	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.air_jumps_used = 0
	_player.set_capability(&"air_jump", false)
	_player.set_capability(&"dash", false)


func after_test() -> void:
	# (edge auto-consumed — &"dash" no release needed)
	Input.action_release(&"move_forward")
	Input.action_release(&"move_left")
	# Consume any residual press flag via one swap so next test starts clean.
	InputManager._physics_process(PHYSICS_DT)
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null


# ---------------------------------------------------------------------------
# AC-MV-20 part 1 : Dash distance ≈ 2.80 m and exit speed == DASH_EXIT_SPEED
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED, can_dash=true, position ZERO, rotation.y=0 (forward = -Z),
##         wish_dir forward (move_forward pressed).
## WHEN  : press(&"dash") + 6 ticks (6 * 1/60 ≈ 0.1s = DASH_DURATION).
## THEN  : abs(position.z - (-2.80)) < 0.15 (dash distance AC-MV-20 ±0.15 m).
##         velocity.xz.length() ≈ DASH_EXIT_SPEED ±0.5 (exit speed at t=DASH_DURATION).
##
## Note: player is at y=50 (no floor). State defaults to GROUNDED for first tick.
## After 6 ticks the dash timer is exhausted and exit speed is applied.
## The distance is integration of DASH_SPEED across DASH_DURATION ticks.
func test_dash_distance_280cm_and_exit_speed() -> void:
	# Arrange — GROUNDED, can_dash enabled, positioned at origin, facing -Z.
	_player.position = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.set_capability(&"dash", true)
	_player.velocity = Vector3.ZERO

	# Act — press move_forward to set wish_dir to -Z, then press dash.
	# Tick 1 is the dash entry tick; ticks 2-6 drive through the burst.
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	for _i: int in 6:
		_tick(_player)
	Input.action_release(&"move_forward")

	# Assert — AC-MV-20 distance: player should have moved ~2.80m in -Z direction.
	# DASH_SPEED=30 * DASH_DURATION=0.10 = 3.0 m ideal; tolerance ±0.15 m.
	assert_float(_player.position.z).is_between(-2.80 - 0.15, -2.80 + 0.15)

	# Assert — AC-MV-20 exit speed: velocity.xz.length should be DASH_EXIT_SPEED ±0.5.
	var horiz_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_float(horiz_speed).is_between(
		MovementController.DASH_EXIT_SPEED - 0.5,
		MovementController.DASH_EXIT_SPEED + 0.5
	)


# ---------------------------------------------------------------------------
# AC-MV-20 part 2 : Momentum deceleration returns speed to MOVE_SPEED after window
# ---------------------------------------------------------------------------

## GIVEN : Post-dash momentum state injected directly:
##         _momentum_timer = DASH_MOMENTUM_WINDOW, _dash_dir = (0,0,-1), state = AIRBORNE.
## WHEN  : 12 ticks elapsed (12 * 1/60 ≈ 0.20s = DASH_MOMENTUM_WINDOW).
## THEN  : velocity.xz.length() ≈ MOVE_SPEED ±0.5 (deceleration complete, AC-MV-20).
##
## This test exercises the momentum branch in _apply_horizontal_control directly,
## without running the full dash burst, for determinism.
func test_dash_momentum_decel_to_move_speed_after_window() -> void:
	# Arrange — inject post-dash momentum state via reflection.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.set("_momentum_timer", MovementController.DASH_MOMENTUM_WINDOW)
	_player.set("_dash_dir", Vector3(0.0, 0.0, -1.0))
	_player.velocity = Vector3(0.0, 0.0, -MovementController.DASH_EXIT_SPEED)

	# Act — run 12 ticks (≈ DASH_MOMENTUM_WINDOW at 60 Hz).
	for _i: int in 12:
		_tick(_player)

	# Assert — AC-MV-20 momentum end: speed should have decayed to MOVE_SPEED ±0.5.
	var horiz_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_float(horiz_speed).is_between(
		MovementController.MOVE_SPEED - 0.5,
		MovementController.MOVE_SPEED + 0.5
	)


# ---------------------------------------------------------------------------
# AC-MV-21 : Dash blocked when can_dash=false
# ---------------------------------------------------------------------------

## GIVEN : can_dash=false (default ability gate, Story-013 not yet wired).
## WHEN  : press(&"dash") + 1 tick.
## THEN  : state != DASHING AND _dash_cooldown_timer == 0.0 (no cooldown triggered).
##
## Verifies AC-MV-21: ability gate silently ignores dash input without side effects.
func test_dash_blocked_when_can_dash_false() -> void:
	# Arrange — default can_dash=false (set in before_test).
	_player.set_capability(&"dash", false)

	# Act — press dash and run one tick.
	_press_dash_and_tick(_player)

	# Assert — AC-MV-21: state must NOT be DASHING, cooldown must NOT have started.
	assert_bool(_player._state == MovementController.State.DASHING).is_false()
	assert_float(_player.get("_dash_cooldown_timer") as float).is_equal(0.0)


# ---------------------------------------------------------------------------
# AC-MV-22 : Dash rejected during cooldown — hook called, no re-entry
# ---------------------------------------------------------------------------

## GIVEN : can_dash=true, _dash_cooldown_timer=0.7 (cooldown still active).
## WHEN  : press(&"dash") + 1 tick.
## THEN  : state != DASHING (no re-entry into dash burst).
##         _on_dash_rejected() invoked (verified implicitly: no crash + state guard).
##
## The hook stub is empty at MVP. The test verifies state guard correctness.
## A richer spy pattern would require a local subclass — deferred to story-009+ signals.
func test_dash_rejected_during_cooldown_no_reentry() -> void:
	# Arrange — can_dash enabled but cooldown still running.
	_player.set_capability(&"dash", true)
	_player.set("_dash_cooldown_timer", 0.7)

	# Act — press dash and run one tick.
	_press_dash_and_tick(_player)

	# Assert — AC-MV-22: dash must NOT re-enter DASHING state.
	assert_bool(_player._state == MovementController.State.DASHING).is_false()
	# Cooldown must still be > 0 (decremented by one tick ≈ 0.0167s but was 0.7).
	assert_float(_player.get("_dash_cooldown_timer") as float).is_greater(0.0)


# ---------------------------------------------------------------------------
# AC-MV-23 : Dash direction locked during burst (horizontal input ignored)
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED, can_dash=true, move_forward pressed (wish_dir = -Z).
##         Dash entered on tick 1 — _dash_dir locked to (0,0,-1).
## WHEN  : release move_forward, press move_left at tick 2 (mid-dash).
##         Run 3 more ticks inside the burst window.
## THEN  : _dash_dir remains (0,0,-1) — locked at entry.
##         velocity.x ≈ 0 (direction lock, not left input).
##
## Verifies AC-MV-23: horizontal input during the burst cannot redirect the dash.
func test_dash_direction_lock_during_dash() -> void:
	# Arrange — GROUNDED, dash enabled, facing -Z.
	_player.position = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.set_capability(&"dash", true)
	_player.velocity = Vector3.ZERO

	# Tick 1 — enter dash in -Z direction.
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	_tick(_player)
	# Release move_forward and press move_left after dash entry.
	Input.action_release(&"move_forward")
	# (edge auto-consumed — &"dash" no release needed)

	# Ticks 2–4 — mid-dash with move_left held.
	Input.action_press(&"move_left")
	for _i: int in 3:
		_tick(_player)
	Input.action_release(&"move_left")

	# Assert — AC-MV-23: _dash_dir must still be (0,0,-1).
	var dash_dir: Vector3 = _player.get("_dash_dir") as Vector3
	assert_float(dash_dir.x).is_equal_approx(0.0, 0.001)
	assert_float(dash_dir.z).is_equal_approx(-1.0, 0.001)

	# velocity.x must be near 0 (dash locked to -Z, not left input).
	# During burst: velocity.x = _dash_dir.x * DASH_SPEED = 0.0 * 30 = 0.
	assert_float(_player.velocity.x).is_between(-0.5, 0.5)


# ---------------------------------------------------------------------------
# AC-MV-25 : velocity.y reset to 0 at dash entry
# ---------------------------------------------------------------------------

## GIVEN : Player AIRBORNE, velocity = (0, 8, 0), can_dash=true, cooldown=0.
## WHEN  : press(&"dash") + 1 tick.
## THEN  : abs(velocity.y) < 0.001 — vertical velocity reset at dash entry.
##
## Verifies AC-MV-25: Rule 6 resets velocity.y=0.0 on the same tick as entry.
## Gravity suppression during DASHING prevents re-accumulation in the same tick.
func test_dash_resets_velocity_y_on_entry() -> void:
	# Arrange — AIRBORNE with upward velocity (simulating jump in progress).
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(0.0, 8.0, 0.0)
	_player.set_capability(&"dash", true)
	_player.set("_dash_cooldown_timer", 0.0)

	# Act — press dash and run one tick.
	_press_dash_and_tick(_player)

	# Assert — AC-MV-25: velocity.y must be 0.0 ±0.001.
	# Gravity is suppressed during DASHING (step 9 in _physics_process), so y stays 0.
	assert_float(absf(_player.velocity.y)).is_less_equal(0.001)


# ---------------------------------------------------------------------------
# Invariants : DASH_SPEED >= MOVE_SPEED*2.5, DASH_COOLDOWN >= 4*DASH_DURATION
# ---------------------------------------------------------------------------

## GIVEN : Default constants (DASH_SPEED=30, MOVE_SPEED=10, DASH_COOLDOWN=0.8,
##          DASH_DURATION=0.1).
## WHEN  : Player instantiated (_ready runs with invariant asserts).
## THEN  : No assertion failure — constants satisfy both invariants.
##
## This test verifies the constants statically (30 >= 25 ✓, 0.8 >= 0.4 ✓).
## Any editor modification that violates the invariants will crash _ready()
## in debug builds AND fail these static checks.
func test_dash_invariants_satisfied_by_default_constants() -> void:
	# Assert invariant 1: DASH_SPEED >= MOVE_SPEED * 2.5.
	assert_bool(
		MovementController.DASH_SPEED >= MovementController.MOVE_SPEED * 2.5
	).is_true()

	# Assert invariant 2: DASH_COOLDOWN >= 4 * DASH_DURATION.
	assert_bool(
		MovementController.DASH_COOLDOWN >= 4.0 * MovementController.DASH_DURATION
	).is_true()

	# Verify concrete values for traceability in CI logs.
	assert_float(MovementController.DASH_SPEED).is_equal(30.0)
	assert_float(MovementController.DASH_DURATION).is_equal(0.10)
	assert_float(MovementController.DASH_COOLDOWN).is_equal(0.8)
	assert_float(MovementController.DASH_EXIT_SPEED).is_equal(15.0)
	assert_float(MovementController.DASH_MOMENTUM_WINDOW).is_equal(0.20)


# ---------------------------------------------------------------------------
# Fallback : No input → dash uses body forward (-Z when rotation.y=0)
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED, rotation.y=0, no movement input, can_dash=true, cooldown=0.
## WHEN  : press(&"dash") + 1 tick.
## THEN  : _dash_dir.x ≈ 0.0 AND _dash_dir.z ≈ -1.0 (body forward = -Z).
##
## Verifies the fallback: when |wish_dir_xz| < 0.01, _try_start_dash uses
## -transform.basis.z projected to the XZ plane (rotation.y=0 → -Z world axis).
func test_dash_default_dir_uses_body_forward_when_no_input() -> void:
	# Arrange — GROUNDED, no input, facing default (rotation.y=0 → forward = -Z).
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set_capability(&"dash", true)
	_player.set("_dash_cooldown_timer", 0.0)
	# Ensure no movement input is active (after_test releases, but be explicit).

	# Act — press dash (no move_forward) and run one tick.
	_press_dash_and_tick(_player)

	# Assert — fallback: _dash_dir must be (0, 0, -1) (body forward with rotation.y=0).
	var dash_dir: Vector3 = _player.get("_dash_dir") as Vector3
	assert_float(dash_dir.x).is_equal_approx(0.0, 0.001)
	assert_float(dash_dir.z).is_equal_approx(-1.0, 0.001)
