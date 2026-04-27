# Unit tests for Story 003 — Custom gravity + Airborne air control.
#
# Covers:
#   AC-1 : AIRBORNE 30 ticks → velocity.y ≈ -12.0 m/s ± 0.5 (g=24 × 0.5s)
#   AC-2 : ProjectSettings.default_gravity == 0.0 (no double-cumul Jolt)
#   AC-3 : Air control 1 tick → velocity.x ≈ -10 + 65/60 ≈ -8.917 ± 0.05
#   AC-4 : AIRBORNE→GROUNDED transition when is_on_floor() becomes true
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn (CharacterBody3D root = MovementController).
#
# Input injection : Input.action_press / Input.action_release.
# State injection : player.set("_state", MovementController.State.AIRBORNE) via reflection.
#
# Note on gravity in GROUNDED: gravity IS applied every tick, but move_and_slide()
# absorbs the downward velocity when on_floor() is true. Tests set _state=AIRBORNE
# directly to bypass the floor check and observe pure gravity accumulation.

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


func _release_all_move_inputs() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute — triggers both asserts (ADR-0001 gravity + ADR-0005 VC-7).
	await get_tree().process_frame

	# Baseline: no velocity, origin position, GROUNDED state.
	_player.position = Vector3(0.0, 10.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO


func after_test() -> void:
	_release_all_move_inputs()
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null


# ---------------------------------------------------------------------------
# AC-1 : Custom gravity 24 m/s² — 30 ticks ≈ -12.0 m/s
# ---------------------------------------------------------------------------

## GIVEN : Player Airborne, velocity = Vector3.ZERO, no input.
## WHEN  : 30 physics ticks at dt=1/60 (= 0.5 s simulated).
## THEN  : velocity.y ≈ -12.0 m/s ± 0.5  (g=24 × 0.5 = 12.0 m/s downward).
##
## Validates TR-mov-007: custom GRAVITY=24, no Jolt double-cumul.
## Expected: -24 * 0.5 = -12.0. Tolerance ±0.5 covers floating-point drift.
func test_gravity_24_mps2_airborne_30_ticks_yields_minus_12_velocity() -> void:
	# Arrange — force AIRBORNE and zero velocity to isolate pure gravity.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3.ZERO
	# No input — InputManager.get_move_input_vector() returns Vector2.ZERO.

	# Act — 30 ticks = 0.5 simulated seconds.
	for _i: int in 30:
		_player._physics_process(PHYSICS_DT)

	# Assert — AC-1: velocity.y should be ≈ -12.0 m/s.
	# move_and_slide() may absorb some vertical velocity; player is at y=10
	# so no floor collision occurs. Expected: -24 * 30/60 = -12.0.
	assert_float(_player.velocity.y).is_between(-12.5, -11.5)


# ---------------------------------------------------------------------------
# AC-2 : ProjectSettings default_gravity == 0.0
# ---------------------------------------------------------------------------

## GIVEN : project.godot has physics/3d/default_gravity=0.0 (ADR-0001 amendement).
## WHEN  : read ProjectSettings.get_setting("physics/3d/default_gravity", 9.8).
## THEN  : result == 0.0 — no Jolt gravity cumulating on top of custom GRAVITY=24.
##
## If this test fails, the double-cumul protection is broken and velocity.y
## would accumulate at 24 + 9.8 = 33.8 m/s² instead of 24.
func test_default_gravity_project_setting_is_zero() -> void:
	# Act — read the project setting that controls Jolt's built-in gravity.
	var gravity_setting: float = ProjectSettings.get_setting(
		"physics/3d/default_gravity", 9.8
	) as float

	# Assert — AC-2: must be exactly 0.0 (set in project.godot §physics).
	assert_float(gravity_setting).is_equal(0.0)


# ---------------------------------------------------------------------------
# AC-3 : Air control — 1 tick recenters velocity.x by AIR_CONTROL_FACTOR/60
# ---------------------------------------------------------------------------

## GIVEN : Player Airborne, velocity = (-10, 0, 0) (moving left in world space).
##         Player rotation = 0 (forward = -Z, right = +X world).
## WHEN  : move_right input held, 1 physics tick at dt=1/60.
## THEN  : velocity.x ≈ -10 + 65/60 ≈ -8.917 ± 0.05.
##
## move_toward(-10, +10, 65/60) = -10 + 65/60 = -8.9167 (move_toward does not
## overshoot, and step=1.0833 < distance=20, so it just advances by step).
func test_air_control_recenter_one_tick_yields_approx_minus_8_917() -> void:
	# Arrange — AIRBORNE with leftward velocity, player facing default (rotation=0).
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(-10.0, 0.0, 0.0)
	_player.rotation = Vector3.ZERO  # right = +X world → move_right maps to +X.

	Input.action_press(&"move_right")

	# Act — single physics tick.
	_player._physics_process(PHYSICS_DT)

	Input.action_release(&"move_right")

	# Assert — AC-3: move_toward(-10, +10, 65/60) = -10 + 1.0833 = -8.9167.
	# Tolerance ±0.05 covers basis normalisation and floating-point rounding.
	var expected_vx: float = -10.0 + (65.0 / 60.0)
	assert_float(_player.velocity.x).is_between(expected_vx - 0.05, expected_vx + 0.05)


# ---------------------------------------------------------------------------
# AC-4 : AIRBORNE→GROUNDED transition when is_on_floor() becomes true
# ---------------------------------------------------------------------------

## GIVEN : Player in AIRBORNE state, placed just above a StaticBody3D floor plane
##         so that the next physics tick — which calls move_and_slide() — will
##         detect the floor and is_on_floor() will return true.
## WHEN  : 1 physics tick.
## THEN  : _state == State.GROUNDED.
##
## Implementation: create a thin StaticBody3D with a PlaneShape3D floor at y=-1,
## place the player at y=0.5 (capsule base near y=-0.4), velocity.y=-5 pushing
## down. move_and_slide() resolves the collision; is_on_floor() returns true;
## the state machine transitions AIRBORNE→GROUNDED.
func test_airborne_to_grounded_transition_when_landing_on_floor() -> void:
	# Arrange — create a StaticBody3D floor so Jolt can detect is_on_floor().
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 0.5, 100.0)
	floor_shape_node.shape = box
	# Floor top surface at y=0. BoxShape3D centered at y=-0.25 (top edge y=0).
	floor_body.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_shape_node)
	add_child(floor_body)

	# Place player capsule just above the floor (capsule origin at y=0.9 → base at y=0.0).
	# Capsule: height=1.8, radius=0.35 → centre at y=0.9, bottom at y=0.0.
	_player.position = Vector3(0.0, 0.92, 0.0)
	_player.velocity = Vector3(0.0, -1.0, 0.0)  # pushing downward into the floor.
	_set_state(_player, MovementController.State.AIRBORNE)

	# Wait one physics frame so the physics server registers the new bodies.
	await get_tree().physics_frame

	# Act — one physics tick: gravity applied + move_and_slide() resolves collision.
	_player._physics_process(PHYSICS_DT)

	# Assert — AC-4: state must have transitioned to GROUNDED.
	assert_int(_player.state as int).is_equal(MovementController.State.GROUNDED as int)

	# Cleanup — remove the floor body.
	floor_body.queue_free()
