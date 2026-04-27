# Integration tests for Story 008 — Death + Respawn Lifecycle.
# Covers AC-MV-40 (die() → DEAD + inputs ignored + respawn at checkpoint),
#        AC-MV-41 (die() idempotent — 3× same tick → 1× transition),
#        AC-MV-24 (die during Dashing → partial cooldown DASH_COOLDOWN * 0.5),
#        AC-MV-42 (die outside Dashing → full cooldown reset to 0.0),
#        Reset total au respawn, set_checkpoint() API.
#
# ADR-0001 (Physics 60 Hz + Jolt), ADR-0005 D-8 (idempotence), VC-7 (RESPAWN_DELAY).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Story: story-008-death-respawn-lifecycle

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Scene preload
# ---------------------------------------------------------------------------

const PlayerScene: PackedScene = preload("res://src/gameplay/player/Player.tscn")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Simulate one physics tick by calling _physics_process on the player.
## InputManager._physics_process must be called first so was_pressed_this_tick
## buffer is flushed exactly once per tick (mirrors production tick order).
## Default dt matches ADR-0001 physics rate: 1/60 s.
func _tick(player: MovementController, dt: float = 1.0 / 60.0) -> void:
	InputManager._physics_process(dt)
	player._physics_process(dt)


## Force-write a private backing field via Object.set() — GdUnit4 integration
## test helper pattern. Only used to put the player in a specific state
## without going through the full transition pipeline.
func _set_state(player: MovementController, s: MovementController.State) -> void:
	player.set("_state", s)


# ---------------------------------------------------------------------------
# AC-MV-40 (partial) — die() transitions to DEAD + clears velocity immediately
# ---------------------------------------------------------------------------

func test_die_transitions_to_dead_state_immediately() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame
	player.velocity = Vector3(3.0, 0.0, 4.0)

	# Act
	player.die()

	# Assert — state is DEAD and velocity zeroed at call site (no tick needed)
	assert_int(player._state) \
		.override_failure_message(
			"AC-MV-40: die() must set _state to DEAD — got %d" % player._state
		) \
		.is_equal(MovementController.State.DEAD)

	assert_vector(player.velocity) \
		.override_failure_message(
			"AC-MV-40: die() must zero velocity immediately — got %s" % str(player.velocity)
		) \
		.is_equal(Vector3.ZERO)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-MV-41 — die() idempotent when called multiple times same tick
# ---------------------------------------------------------------------------

func test_die_is_idempotent_when_called_multiple_times_same_tick() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Record initial _respawn_timer (zero before first die())
	# After die(), _respawn_timer = RESPAWN_DELAY_S.
	# Subsequent die() calls must early-return without overwriting it.

	# Act — three consecutive calls in the same tick
	player.die()
	var timer_after_first: float = player._respawn_timer
	player.die()
	var timer_after_second: float = player._respawn_timer
	player.die()
	var timer_after_third: float = player._respawn_timer

	# Assert — state is DEAD exactly once
	assert_int(player._state) \
		.override_failure_message("AC-MV-41: _state must be DEAD after 3x die()") \
		.is_equal(MovementController.State.DEAD)

	# Assert — _respawn_timer set exactly once (by first die()), not re-set by subsequent calls
	assert_float(timer_after_first) \
		.override_failure_message(
			"AC-MV-41: first die() must set _respawn_timer to RESPAWN_DELAY_S (%f) — got %f"
			% [MovementController.RESPAWN_DELAY_S, timer_after_first]
		) \
		.is_equal_approx(MovementController.RESPAWN_DELAY_S, 1e-6)

	assert_float(timer_after_second) \
		.override_failure_message(
			"AC-MV-41: second die() must not overwrite _respawn_timer — got %f (expected %f)"
			% [timer_after_second, timer_after_first]
		) \
		.is_equal_approx(timer_after_first, 1e-6)

	assert_float(timer_after_third) \
		.override_failure_message(
			"AC-MV-41: third die() must not overwrite _respawn_timer — got %f (expected %f)"
			% [timer_after_third, timer_after_first]
		) \
		.is_equal_approx(timer_after_first, 1e-6)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-MV-40 (inputs) — jump input ignored during DEAD state
# ---------------------------------------------------------------------------

func test_inputs_ignored_during_dead_state() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Enable ability so the jump path would fire if inputs were processed
	player.can_air_jump = true

	# Put player airborne so a jump press would normally set velocity.y = JUMP_VELOCITY
	_set_state(player, MovementController.State.AIRBORNE)
	player.die()

	# Simulate jump press — within RESPAWN_DELAY_S window (one tick = 1/60 ≈ 0.0167 s < 0.05 s)
	InputManager.simulate_action_press(&"jump")

	# Act — one tick (still inside respawn window)
	_tick(player)

	# Assert — velocity.y must remain 0.0 (jump was not processed)
	assert_float(player.velocity.y) \
		.override_failure_message(
			"AC-MV-40: jump input must be ignored during DEAD — velocity.y should be 0.0, got %f"
			% player.velocity.y
		) \
		.is_equal_approx(0.0, 1e-5)

	assert_int(player._state) \
		.override_failure_message(
			"AC-MV-40: _state must remain DEAD one tick into respawn window — got %d" % player._state
		) \
		.is_equal(MovementController.State.DEAD)

	# Cleanup — release input
	InputManager.simulate_action_release(&"jump")
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-MV-40 (respawn) — player teleports to checkpoint after delay
# ---------------------------------------------------------------------------

func test_respawn_after_delay_restores_to_checkpoint() -> void:
	# Arrange
	var spawn_pos: Vector3 = Vector3(42.0, 1.0, 7.0)
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_checkpoint(spawn_pos)
	player.global_position = Vector3(10.0, 5.0, 5.0)
	player.die()

	# Act — 4 ticks × 1/60 ≈ 0.0667 s > RESPAWN_DELAY_S=0.05 s → should respawn
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — at checkpoint
	assert_float(player.global_position.distance_to(spawn_pos)) \
		.override_failure_message(
			"AC-MV-40: global_position must be at checkpoint %s after respawn — got %s (dist %f)"
			% [str(spawn_pos), str(player.global_position), player.global_position.distance_to(spawn_pos)]
		) \
		.is_less_equal(0.1)

	# Assert — state GROUNDED
	assert_int(player._state) \
		.override_failure_message(
			"AC-MV-40: _state must be GROUNDED after respawn — got %d" % player._state
		) \
		.is_equal(MovementController.State.GROUNDED)

	# Assert — velocity zeroed
	assert_vector(player.velocity) \
		.override_failure_message(
			"AC-MV-40: velocity must be Vector3.ZERO after respawn — got %s" % str(player.velocity)
		) \
		.is_equal(Vector3.ZERO)

	# Assert — air jumps reset
	assert_int(player.air_jumps_used) \
		.override_failure_message(
			"AC-MV-40: air_jumps_used must be 0 after respawn — got %d" % player.air_jumps_used
		) \
		.is_equal(0)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-MV-24 — die during Dashing → partial cooldown after respawn
# ---------------------------------------------------------------------------

func test_die_during_dashing_yields_partial_cooldown_after_respawn() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.DASHING)
	player.set("_dash_cooldown_timer", MovementController.DASH_COOLDOWN)
	player.dash_timer = 0.05

	# Act — die() captures _was_dashing_at_death=true; 4 ticks → respawn fires
	player.die()
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — GROUNDED after respawn
	assert_int(player._state) \
		.override_failure_message(
			"AC-MV-24: _state must be GROUNDED after respawn — got %d" % player._state
		) \
		.is_equal(MovementController.State.GROUNDED)

	# Assert — partial cooldown = DASH_COOLDOWN * 0.5
	var expected_cd: float = MovementController.DASH_COOLDOWN * 0.5
	assert_float(player._dash_cooldown_timer) \
		.override_failure_message(
			"AC-MV-24: _dash_cooldown_timer must be DASH_COOLDOWN*0.5 (%f) — got %f"
			% [expected_cd, player._dash_cooldown_timer]
		) \
		.is_equal_approx(expected_cd, 1e-5)

	# Assert — dash_timer reset to 0
	assert_float(player.dash_timer) \
		.override_failure_message(
			"AC-MV-24: dash_timer must be 0.0 after respawn — got %f" % player.dash_timer
		) \
		.is_equal_approx(0.0, 1e-5)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-MV-42 — die outside Dashing → full cooldown reset after respawn
# ---------------------------------------------------------------------------

func test_die_grounded_yields_full_cooldown_reset_after_respawn() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	# Player is GROUNDED with a partial cooldown from a recent dash
	player.set("_dash_cooldown_timer", 0.5)

	# Act
	player.die()
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — cooldown fully reset
	assert_int(player._state) \
		.override_failure_message(
			"AC-MV-42: _state must be GROUNDED after respawn — got %d" % player._state
		) \
		.is_equal(MovementController.State.GROUNDED)

	assert_float(player._dash_cooldown_timer) \
		.override_failure_message(
			"AC-MV-42: _dash_cooldown_timer must be 0.0 (full reset) after non-dash death — got %f"
			% player._dash_cooldown_timer
		) \
		.is_equal_approx(0.0, 1e-5)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# set_checkpoint() — position persists for next respawn
# ---------------------------------------------------------------------------

func test_set_checkpoint_persists_position_for_next_respawn() -> void:
	# Arrange
	var checkpoint: Vector3 = Vector3(100.0, 2.0, 50.0)
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	player.set_checkpoint(checkpoint)

	# Act
	player.die()
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert
	assert_float(player.global_position.distance_to(checkpoint)) \
		.override_failure_message(
			"set_checkpoint: global_position must be near checkpoint %s — got %s (dist %f)"
			% [str(checkpoint), str(player.global_position), player.global_position.distance_to(checkpoint)]
		) \
		.is_less_equal(0.1)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Reset total — wall state fully cleared on respawn
# ---------------------------------------------------------------------------

func test_respawn_clears_wall_state_completely() -> void:
	# Arrange
	var player: MovementController = PlayerScene.instantiate() as MovementController
	add_child(player)
	await get_tree().process_frame

	_set_state(player, MovementController.State.WALL_RUNNING)
	player.set("_wall_normal", Vector3(1.0, 0.0, 0.0))
	player.set("_wall_run_timer", 0.5)
	player.air_jumps_used = 1

	# Act — die() clears wall state immediately, then respawn after delay
	player.die()
	_tick(player)
	_tick(player)
	_tick(player)
	_tick(player)

	# Assert — all wall bookkeeping reset
	assert_vector(player._wall_normal) \
		.override_failure_message(
			"Reset: _wall_normal must be Vector3.ZERO after respawn — got %s" % str(player._wall_normal)
		) \
		.is_equal(Vector3.ZERO)

	assert_float(player._wall_run_timer) \
		.override_failure_message(
			"Reset: _wall_run_timer must be 0.0 after respawn — got %f" % player._wall_run_timer
		) \
		.is_equal_approx(0.0, 1e-5)

	assert_int(player.air_jumps_used) \
		.override_failure_message(
			"Reset: air_jumps_used must be 0 after respawn — got %d" % player.air_jumps_used
		) \
		.is_equal(0)

	# Cleanup
	player.queue_free()
	await get_tree().process_frame
