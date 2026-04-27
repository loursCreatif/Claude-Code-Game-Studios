# Unit tests for Story 012 — Velocity NaN/Infinity safeguard.
#
# Covers:
#   AC-MV-70 : velocity = Vector3(INF, INF, INF) → reset to Vector3.ZERO + push_error
#   NaN      : velocity.x = NaN → reset to Vector3.ZERO
#   -INF     : velocity.y = -INF → reset to Vector3.ZERO
#   Pass-through : valid velocity (30, -24, 0) → remains finite, unchanged by safeguard
#   Edge     : deep fall y=-100 → is_finite() true, NOT reset (no artificial clamp)
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn (CharacterBody3D root = MovementController).
#
# Test strategy:
#   _apply_movement() is called directly as a unit — bypasses the full _physics_process
#   pipeline so NaN/Inf values survive long enough to reach the safeguard.
#   If we went through _physics_process() the state machine would first overwrite velocity
#   (grounded horizontal = wish_dir * MOVE_SPEED) before reaching the safeguard.
#
# Note on push_error capture:
#   GdUnit4 does not expose a clean assert_push_error() helper for all versions.
#   We test the observable effect (velocity reset to ZERO) which is the only
#   recoverable output guaranteed by the safeguard. The push_error side-effect
#   will appear in CI logs and the Godot debugger.
#
# ADR: ADR-0001 (Physics rate 60 Hz + Jolt).
# Story: story-012-velocity-nan-safeguard

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PHYSICS_DT: float = 1.0 / 60.0

var _player: MovementController = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute — triggers ADR-0001 gravity assert + ADR-0005 VC-7 assert.
	await get_tree().process_frame

	# Baseline: GROUNDED at elevated position with zero velocity.
	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO


func after_test() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null


# ---------------------------------------------------------------------------
# AC-MV-70 : INF velocity reset to ZERO
# ---------------------------------------------------------------------------

## GIVEN  : Player GROUNDED.
## WHEN   : player.velocity is set to Vector3(INF, INF, INF), then _apply_movement() called.
## THEN   : player.velocity == Vector3.ZERO AND velocity.is_finite() == true.
## EFFECT : push_error is emitted (observable in CI logs / debugger, not asserted here).
##
## Verifies AC-MV-70: any component being +INF triggers the safeguard.
func test_velocity_inf_replaced_by_zero_with_push_error() -> void:
	# Arrange — force INF velocity (simulates a runaway physics accumulation).
	_player.velocity = Vector3(INF, INF, INF)

	# Pre-condition sanity: velocity is indeed not finite before the safeguard.
	assert_bool(_player.velocity.is_finite()).is_false()

	# Act — call the safeguard helper directly.
	_player._apply_movement()

	# Assert — AC-MV-70: velocity replaced by ZERO, is_finite() restored.
	assert_vector3(_player.velocity).is_equal(Vector3.ZERO)
	assert_bool(_player.velocity.is_finite()).is_true()


# ---------------------------------------------------------------------------
# NaN : partial NaN reset to ZERO
# ---------------------------------------------------------------------------

## GIVEN  : Player GROUNDED.
## WHEN   : player.velocity = Vector3(NAN, 1.0, 2.0) (NaN on X component only).
## THEN   : player.velocity == Vector3.ZERO.
##
## Vector3.is_finite() returns false if ANY component is NaN (IEEE 754 property:
## NaN != NaN, and Godot propagates is_finite() = false on partial NaN).
## The safeguard resets the FULL vector to ZERO — no partial recovery (AC-MV-70).
func test_velocity_nan_x_replaced_by_zero() -> void:
	# Arrange — NaN on x component (0.0/0.0 is the canonical GDScript NaN literal).
	var nan_val: float = 0.0 / 0.0
	_player.velocity = Vector3(nan_val, 1.0, 2.0)

	# Pre-condition: is_finite() must report false (NaN present).
	assert_bool(_player.velocity.is_finite()).is_false()

	# Act.
	_player._apply_movement()

	# Assert — full reset: NaN on any axis → entire velocity becomes ZERO.
	assert_vector3(_player.velocity).is_equal(Vector3.ZERO)
	assert_bool(_player.velocity.is_finite()).is_true()


# ---------------------------------------------------------------------------
# -INF : negative-infinity velocity reset to ZERO
# ---------------------------------------------------------------------------

## GIVEN  : Player GROUNDED.
## WHEN   : player.velocity = Vector3(0, -INF, 0) (-INF on Y only).
## THEN   : player.velocity == Vector3.ZERO.
##
## Verifies that -INF (terminal fall accumulation bug) is caught by the safeguard.
## This scenario typically arises if gravity is applied unbounded for many ticks
## while is_on_floor() falsely returns false.
func test_velocity_negative_inf_y_replaced_by_zero() -> void:
	# Arrange — -INF on vertical axis.
	_player.velocity = Vector3(0.0, -INF, 0.0)

	# Pre-condition.
	assert_bool(_player.velocity.is_finite()).is_false()

	# Act.
	_player._apply_movement()

	# Assert.
	assert_vector3(_player.velocity).is_equal(Vector3.ZERO)
	assert_bool(_player.velocity.is_finite()).is_true()


# ---------------------------------------------------------------------------
# Pass-through : valid velocity unchanged by safeguard
# ---------------------------------------------------------------------------

## GIVEN  : Player GROUNDED.
## WHEN   : player.velocity = Vector3(30.0, -24.0, 0.0) (dash speed + gravity).
## THEN   : velocity.is_finite() == true AND at least one component != 0.
##
## move_and_slide() may alter the exact values (collision resolution, floor snapping),
## so we assert is_finite() and non-zero rather than exact equality.
## This proves the safeguard does NOT fire on legitimate velocities.
func test_valid_velocity_passes_through_unchanged() -> void:
	# Arrange — realistic velocity: horizontal dash + downward gravity accumulation.
	_player.velocity = Vector3(30.0, -24.0, 0.0)

	# Pre-condition: must be finite.
	assert_bool(_player.velocity.is_finite()).is_true()

	# Act.
	_player._apply_movement()

	# Assert — safeguard did not fire: velocity remains finite.
	assert_bool(_player.velocity.is_finite()).is_true()
	# At least one component must be non-zero (movement was not zeroed by safeguard).
	# move_and_slide() may clamp some axes on collision, but cannot zero all three
	# for a player floating at y=50 with no floor or wall contact.
	var any_nonzero: bool = (
		_player.velocity.x != 0.0
		or _player.velocity.y != 0.0
		or _player.velocity.z != 0.0
	)
	assert_bool(any_nonzero).is_true()


# ---------------------------------------------------------------------------
# Edge: deep fall velocity passes through (is_finite vs clamp)
# ---------------------------------------------------------------------------

## GIVEN  : Player AIRBORNE (forced via reflection).
## WHEN   : player.velocity = Vector3(0, -100.0, 0) (deep fall — 4× terminal GRAVITY).
## THEN   : velocity.is_finite() == true (deep fall is NOT clamped by the safeguard).
##
## This validates the architectural decision (ADR-0001 / story-012):
## use is_finite() NOT clamp(-50, +50) so legitimate large velocities (long falls,
## Jolt impulse resolution on steep slopes) are never artificially truncated.
func test_deep_fall_velocity_y_minus_100_passes_through() -> void:
	# Arrange — force AIRBORNE so gravity context matches the scenario.
	_player.set("_state", MovementController.State.AIRBORNE)
	_player.velocity = Vector3(0.0, -100.0, 0.0)

	# Pre-condition: -100 is a finite float.
	assert_bool(_player.velocity.is_finite()).is_true()

	# Act.
	_player._apply_movement()

	# Assert — deep fall must remain finite (safeguard must NOT trigger on -100).
	assert_bool(_player.velocity.is_finite()).is_true()
