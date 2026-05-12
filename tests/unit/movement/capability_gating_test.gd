# Unit tests for Story 013 — Capability gating (can_dash / can_air_jump / can_wall_run).
#
# Covers:
#   AC-MV-60 : Fresh start → all 3 capability flags default to false.
#   AC-MV-61 : set_capability(&"dash", true) → dash transitions to DASHING on input.
#   Gating dash      : can_dash=false → dash input ignored, no cooldown triggered.
#   Gating air-jump  : can_air_jump=false → AIRBORNE jump ignored (no AIR_JUMP_VELOCITY).
#   Gating wall-run  : can_wall_run=false → wall raycast hit does not transition to WALL_RUNNING.
#   set_capability   : unknown cap → push_error, no mutation.
#   Round-trip       : set true then false → flag correctly reverts.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn.
#
# ADR-0005 REQ-8 + Pattern F7: can_dash / can_air_jump / can_wall_run are READ-ONLY
# properties (backing _can_*). The only mutation entry point is set_capability(cap, enabled).

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PHYSICS_DT: float = 1.0 / 60.0

var _player: MovementController = null


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


func _set_coyote_ticks(player: MovementController, ticks: int) -> void:
	player.set("_coyote_timer_ticks", ticks)


func _tick(player: MovementController) -> void:
	InputManager._physics_process(PHYSICS_DT)
	player._physics_process(PHYSICS_DT)


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	await get_tree().process_frame
	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.air_jumps_used = 0


func after_test() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	# Release any inputs left pressed.
	# (edge auto-consumed — &"jump" no release needed)
	# (edge auto-consumed — &"dash" no release needed)
	Input.action_release(&"move_forward")


# ---------------------------------------------------------------------------
# AC-MV-60 — Fresh start defaults
# ---------------------------------------------------------------------------

func test_fresh_start_all_capabilities_false() -> void:
	# AC-MV-60: a fresh-instantiated player has no capabilities granted yet.
	# UpgradeSystem (epic downstream) must call set_capability(true) for each unlock.
	assert_bool(_player.can_dash).is_false()
	assert_bool(_player.can_air_jump).is_false()
	assert_bool(_player.can_wall_run).is_false()


# ---------------------------------------------------------------------------
# AC-MV-61 — set_capability("dash", true) enables dash
# ---------------------------------------------------------------------------

func test_set_capability_dash_enables_dash_state_transition() -> void:
	# AC-MV-61: enabling dash via setter then pressing dash → DASHING transition.
	_player.set_capability(&"dash", true)
	assert_bool(_player.can_dash).is_true()

	_set_state(_player, MovementController.State.GROUNDED)
	# wish_dir = forward (W pressed) so dash gets a non-fallback direction.
	Input.action_press(&"move_forward")
	InputManager.inject_pressed_for_test(&"dash")
	_tick(_player)

	assert_int(_player._state).is_equal(MovementController.State.DASHING)


# ---------------------------------------------------------------------------
# Gating dash — can_dash=false (default) blocks the transition
# ---------------------------------------------------------------------------

func test_dash_blocked_when_can_dash_false_default() -> void:
	# AC-MV-21 rappel via gating: fresh start → can_dash=false → dash input no-op.
	assert_bool(_player.can_dash).is_false()
	_set_state(_player, MovementController.State.GROUNDED)

	InputManager.inject_pressed_for_test(&"dash")
	_tick(_player)

	assert_int(_player._state).is_not_equal(MovementController.State.DASHING)
	# Cooldown must NOT have started (gating happens BEFORE cooldown set).
	assert_float(_player._dash_cooldown_timer).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Gating air-jump — can_air_jump=false (default) blocks AIRBORNE jump
# ---------------------------------------------------------------------------

func test_double_jump_blocked_when_can_air_jump_false() -> void:
	# AC-MV-13 rappel: AIRBORNE + can_air_jump=false → jump input does not give AIR_JUMP_VELOCITY.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.air_jumps_used = 0
	# Disable coyote so we test the air-jump branch (not coyote ground-jump).
	_set_coyote_ticks(_player, 0)
	_player.velocity = Vector3.ZERO

	InputManager.inject_pressed_for_test(&"jump")
	_tick(_player)

	# Air-jump must NOT have fired: air_jumps_used unchanged, velocity.y not lifted.
	assert_int(_player.air_jumps_used).is_equal(0)
	# velocity.y should be only gravity decrement (-GRAVITY * dt ≈ -0.4), NOT AIR_JUMP_VELOCITY (=6.5).
	assert_float(_player.velocity.y).is_less(MovementController.AIR_JUMP_VELOCITY * 0.5)


# ---------------------------------------------------------------------------
# Gating air-jump — set_capability("air_jump", true) enables it
# ---------------------------------------------------------------------------

func test_double_jump_works_when_set_capability_air_jump() -> void:
	_player.set_capability(&"air_jump", true)
	assert_bool(_player.can_air_jump).is_true()

	_set_state(_player, MovementController.State.AIRBORNE)
	_player.air_jumps_used = 0
	_set_coyote_ticks(_player, 0)
	_player.velocity = Vector3.ZERO

	InputManager.inject_pressed_for_test(&"jump")
	_tick(_player)

	# Air-jump fires: counter incremented, velocity.y lifted near AIR_JUMP_VELOCITY.
	assert_int(_player.air_jumps_used).is_equal(1)
	# velocity.y after gravity tick = AIR_JUMP_VELOCITY - GRAVITY * dt ≈ 6.5 - 0.4 = 6.1.
	var expected_vy: float = MovementController.AIR_JUMP_VELOCITY - MovementController.GRAVITY * PHYSICS_DT
	assert_float(_player.velocity.y).is_equal_approx(expected_vy, 0.05)


# ---------------------------------------------------------------------------
# Gating wall-run — can_wall_run=false blocks WALL_RUNNING entry
# ---------------------------------------------------------------------------

func test_wall_run_blocked_when_can_wall_run_false() -> void:
	# Setup: AIRBORNE with horizontal speed > WALL_RUN_MIN_SPEED, but can_wall_run=false.
	# Even with raycasts hitting a wall, no transition to WALL_RUNNING is allowed.
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.velocity = Vector3(10.0, 0.0, 0.0)  # speed > WALL_RUN_MIN_SPEED (5.0)
	assert_bool(_player.can_wall_run).is_false()

	# Place a wall to the right of the player so %WallRayRight (target +0.8 X) hits.
	var wall: StaticBody3D = StaticBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.0, 4.0, 4.0)
	col.shape = shape
	wall.add_child(col)
	wall.global_position = _player.global_position + Vector3(0.5, 0.0, 0.0)
	add_child(wall)
	auto_free(wall)
	await get_tree().physics_frame  # let Jolt register the body

	_tick(_player)

	# Gating: state must remain AIRBORNE despite wall contact.
	assert_int(_player._state).is_equal(MovementController.State.AIRBORNE)


# ---------------------------------------------------------------------------
# set_capability robustness
# ---------------------------------------------------------------------------

func test_set_capability_unknown_cap_pushes_error_no_mutation() -> void:
	# Unknown cap key → push_error (not captured by GdUnit4 but observable
	# via the absence of mutation on the 3 known flags).
	_player.set_capability(&"unknown_cap", true)

	assert_bool(_player.can_dash).is_false()
	assert_bool(_player.can_air_jump).is_false()
	assert_bool(_player.can_wall_run).is_false()


func test_set_capability_round_trip_true_then_false() -> void:
	# Round-trip: enable then disable a capability — flag toggles correctly.
	_player.set_capability(&"dash", true)
	assert_bool(_player.can_dash).is_true()

	_player.set_capability(&"dash", false)
	assert_bool(_player.can_dash).is_false()

	# Round-trip on wall_run + air_jump as well for full coverage.
	_player.set_capability(&"wall_run", true)
	assert_bool(_player.can_wall_run).is_true()
	_player.set_capability(&"wall_run", false)
	assert_bool(_player.can_wall_run).is_false()

	_player.set_capability(&"air_jump", true)
	assert_bool(_player.can_air_jump).is_true()
	_player.set_capability(&"air_jump", false)
	assert_bool(_player.can_air_jump).is_false()
