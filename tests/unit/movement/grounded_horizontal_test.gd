# Unit tests for Story 002 — Grounded horizontal movement (stop instantané).
#
# Covers:
#   AC-MV-01 : forward 1 s → position.z ≈ -10 m (± 0.3 m)
#   AC-MV-02 : release input → velocity.x/z = 0 in exactly ONE physics tick
#   AC-MV-03 : A+D simultaneous → velocity stays 0
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn (CharacterBody3D root = MovementController).
#
# Input injection : Input.action_press / Input.action_release (official GdUnit4 pattern).
# These drive Input.get_vector inside InputManager.get_move_input_vector().
#
# Note: move_and_slide() performs the actual position update from velocity.
# Because tests call _physics_process directly (bypassing the real physics step),
# we need to call it 60× with dt=1/60 to simulate 1 s and verify position accumulation.

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PHYSICS_DT: float = 1.0 / 60.0
const TOLERANCE: float = 0.3


var _player: MovementController = null
var _floor_body: StaticBody3D = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Floor BoxShape3D — garantit is_on_floor()=true en Jolt headless 4.6,
	# évite que step 3 transitionne GROUNDED→AIRBORNE au tick 1 (sinon air
	# control lent au lieu de grounded movement → -5m au lieu de -10m).
	# Pattern cohérent avec gravity_airborne_test::test_airborne_to_grounded_transition.
	_floor_body = StaticBody3D.new()
	_floor_body.position = Vector3(0.0, -0.25, 0.0)
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 0.5, 100.0)
	floor_shape.shape = box
	_floor_body.add_child(floor_shape)
	add_child(_floor_body)

	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute (asserts ADR-0005 VC-7 invariant inside MovementController).
	await get_tree().process_frame

	# Ensure a clean baseline: capsule juste au-dessus du floor, no velocity.
	_player.position = Vector3(0.0, 0.92, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	# Jolt headless 4.6 a besoin de plusieurs physics frames pour register la
	# StaticBody3D avant que is_on_floor() retourne true.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	_release_all_move_inputs()
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null
	if is_instance_valid(_floor_body):
		_floor_body.queue_free()
	_floor_body = null


# ---------------------------------------------------------------------------
# Helper : input injection
# ---------------------------------------------------------------------------

func _press(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _release_all_move_inputs() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"move_back")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")


# ---------------------------------------------------------------------------
# AC-MV-01 : forward 1 s → position.z ≈ -10 m
# ---------------------------------------------------------------------------

## GIVEN : Player Grounded, position=ZERO, rotation.y=0 (forward = -Z world).
## WHEN  : hold W (move_forward) and call _physics_process 60 times at dt=1/60.
## THEN  : player.position.z is within 0.3 m of -10.0 m.
func test_forward_60_ticks_advances_negative_z_10m() -> void:
	# Arrange — state is GROUNDED by default (MovementController._state initialised to State.GROUNDED).
	_press(&"move_forward")

	# Act — simulate 1 s at 60 Hz.
	for _i: int in 60:
		_player._physics_process(PHYSICS_DT)

	_release(&"move_forward")

	# Assert — AC-MV-01: distance ≈ 10 m ± 0.3 m along -Z.
	assert_float(_player.position.z).is_between(-10.0 - TOLERANCE, -10.0 + TOLERANCE)


# ---------------------------------------------------------------------------
# AC-MV-02 : release input → zero velocity in ONE tick
# ---------------------------------------------------------------------------

## GIVEN : Player Grounded with existing horizontal velocity (simulates mid-movement).
## WHEN  : no move input, call _physics_process once.
## THEN  : velocity.x and velocity.z are both < 0.001.
func test_release_input_stops_velocity_in_one_tick() -> void:
	# Arrange — inject a non-zero velocity as if the player was moving.
	_player.velocity = Vector3(10.0, 0.0, 0.0)
	# No action pressed → InputManager.get_move_input_vector() returns Vector2.ZERO.

	# Act — single physics tick with no input.
	_player._physics_process(PHYSICS_DT)

	# Assert — AC-MV-02: stop is instantaneous (one tick max).
	assert_float(absf(_player.velocity.x)).is_less(0.001)
	assert_float(absf(_player.velocity.z)).is_less(0.001)


# ---------------------------------------------------------------------------
# AC-MV-03 : A+D simultaneously → velocity stays 0
# ---------------------------------------------------------------------------

## GIVEN : Player Grounded.
## WHEN  : move_left AND move_right pressed at the same time, one physics tick.
## THEN  : velocity.x and velocity.z are both < 0.001 (inputs cancel each other).
func test_opposite_inputs_zero_velocity() -> void:
	# Arrange — press both horizontal opposites.
	_press(&"move_left")
	_press(&"move_right")

	# Act — one physics tick.
	_player._physics_process(PHYSICS_DT)

	_release(&"move_left")
	_release(&"move_right")

	# Assert — AC-MV-03: Input.get_vector returns ~Vector2.ZERO when left+right cancel.
	assert_float(absf(_player.velocity.x)).is_less(0.001)
	assert_float(absf(_player.velocity.z)).is_less(0.001)
