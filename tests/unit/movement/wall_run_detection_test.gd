# Unit tests for Story 006 — Wall-run detection, state, raycasts.
#
# Covers:
#   AC-MV-30  : GIVEN can_wall_run=true, Airborne, horiz_speed > WALL_RUN_MIN_SPEED,
#               WHEN ≥1 raycast touches a wall, THEN _state == WALL_RUNNING and
#               gravity applied is WALL_RUN_GRAVITY (not GRAVITY).
#   AC-MV-31  : GIVEN WALL_RUNNING, WHEN no raycast hits, THEN _state == AIRBORNE
#               next tick and _wall_normal == Vector3.ZERO.
#   AC-MV-33  : GIVEN WALL_RUNNING with wall contact maintained, WHEN
#               WALL_RUN_MAX_DURATION elapses, THEN _state == AIRBORNE.
#   AC-MV-34  : GIVEN both raycasts hit simultaneously (narrow corridor),
#               THEN _wall_normal == %WallRayLeft.get_collision_normal() (left priority).
#   Fall cap  : GIVEN WALL_RUNNING, velocity.y below -WALL_RUN_FALL_CAP,
#               THEN velocity.y clamped to -WALL_RUN_FALL_CAP.
#   AC-6      : GIVEN GROUNDED, THEN %WallRayLeft.enabled == false AND
#               %WallRayRight.enabled == false.
#   AC-7      : GIVEN DASHING, THEN both rays disabled (no Dashing→WallRunning).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Scene     : res://src/gameplay/player/Player.tscn.
#
# Wall-creation strategy:
#   Approach A (preferred) — StaticBody3D + CollisionShape3D + BoxShape3D added as
#   child in before_test / local helper. force_raycast_update() after add_child
#   ensures the query fires before the assertion.
#
# Ordering invariant: InputManager._physics_process MUST run before
# player._physics_process (swap before read).

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
func _tick(player: MovementController) -> void:
	InputManager._physics_process(PHYSICS_DT)
	player._physics_process(PHYSICS_DT)


## Creates a StaticBody3D wall with a BoxShape3D collider at the given position.
## Size is the full extents of the box (default: 1×4×4 m).
## The wall is added as a child of parent and returned for later cleanup.
func _create_wall(parent: Node, pos: Vector3, size: Vector3 = Vector3(1.0, 4.0, 4.0)) -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = pos
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	wall.add_child(shape_node)
	parent.add_child(wall)
	return wall


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as MovementController
	add_child(_player)
	# Let _ready() execute — triggers story-005/006 invariant asserts and ADR asserts.
	await get_tree().process_frame

	# Baseline: suspended in air (no floor), GROUNDED state, no ability flags.
	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.air_jumps_used = 0
	_player.set_capability(&"air_jump", false)
	_player.set_capability(&"dash", false)
	_player.set_capability(&"wall_run", false)
	# Force GROUNDED baseline : Jolt headless sans floor transitionne state à
	# AIRBORNE pendant le process_frame du _ready. Pattern b60d809 +
	# project_settings_and_scene_test (set_physics_process(false)) insuffisant ici
	# car _state est muté ailleurs. Reflexion via set("_state", ...) bypass
	# read-only protection (cohérent helper _set_state).
	_set_state(_player, MovementController.State.GROUNDED)


func after_test() -> void:
	# Consume any residual press flag via one swap so next test starts clean.
	InputManager._physics_process(PHYSICS_DT)
	if is_instance_valid(_player):
		_player.queue_free()
	_player = null


# ---------------------------------------------------------------------------
# AC-6 — Raycasts disabled when GROUNDED
# ---------------------------------------------------------------------------

## GIVEN : Player in default GROUNDED state (before_test baseline).
## WHEN  : One physics tick.
## THEN  : %WallRayLeft.enabled == false AND %WallRayRight.enabled == false.
##
## Story-006 perf F7: no wasted raycast queries while on the ground.
func test_raycasts_disabled_when_grounded() -> void:
	# Arrange — GROUNDED is the default state from before_test.
	assert_bool(_player._state == MovementController.State.GROUNDED).is_true()

	# Act.
	_tick(_player)

	# Assert — both rays must be disabled in GROUNDED.
	var ray_left: RayCast3D = _player.get_node("%WallRayLeft") as RayCast3D
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	assert_bool(ray_left.enabled).is_false()
	assert_bool(ray_right.enabled).is_false()


# ---------------------------------------------------------------------------
# Assoc AC-6 — Raycasts enabled when AIRBORNE
# ---------------------------------------------------------------------------

## GIVEN : Player state injected to AIRBORNE.
## WHEN  : One physics tick.
## THEN  : %WallRayLeft.enabled == true AND %WallRayRight.enabled == true.
func test_raycasts_enabled_when_airborne() -> void:
	# Arrange.
	_set_state(_player, MovementController.State.AIRBORNE)

	# Act.
	_tick(_player)

	# Assert — both rays must be enabled in AIRBORNE.
	var ray_left: RayCast3D = _player.get_node("%WallRayLeft") as RayCast3D
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	assert_bool(ray_left.enabled).is_true()
	assert_bool(ray_right.enabled).is_true()


# ---------------------------------------------------------------------------
# AC-7 — Raycasts disabled during DASHING (blocks Dashing→WallRunning)
# ---------------------------------------------------------------------------

## GIVEN : Player state injected to DASHING.
## WHEN  : One physics tick.
## THEN  : Both rays disabled — Dashing→WallRunning transition is architecturally
##         impossible because raycasts cannot query while disabled.
func test_raycasts_disabled_during_dashing() -> void:
	# Arrange — inject DASHING state with a valid dash_dir so _apply_dash_state
	# does not crash on zero-vector access. dash_timer > 0 keeps burst active.
	_set_state(_player, MovementController.State.DASHING)
	_player.set("_dash_dir", Vector3(0.0, 0.0, -1.0))
	_player.dash_timer = MovementController.DASH_DURATION

	# Act.
	_tick(_player)

	# Assert.
	var ray_left: RayCast3D = _player.get_node("%WallRayLeft") as RayCast3D
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	assert_bool(ray_left.enabled).is_false()
	assert_bool(ray_right.enabled).is_false()


# ---------------------------------------------------------------------------
# AC-MV-30 — Wall-run applies reduced gravity
# ---------------------------------------------------------------------------

## GIVEN : Player WALL_RUNNING, wall on the right side (right raycast hits),
##         velocity.y = 0.0.
## WHEN  : One physics tick.
## THEN  : velocity.y decreased by WALL_RUN_GRAVITY * dt (not GRAVITY * dt).
##         Verifies AC-MV-30: reduced gravity during wall-run.
##
## Wall is placed at (+0.5, 50, 0) so that %WallRayRight (target +0.8 m) hits it.
## _wall_normal pre-set to pass the _update_wall_run raycast exit check.
func test_wall_run_state_applies_reduced_gravity() -> void:
	# Arrange — create right-side wall adjacent to the player.
	var wall: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	auto_free(wall)

	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.velocity = Vector3(0.0, 0.0, 0.0)
	_set_state(_player, MovementController.State.WALL_RUNNING)
	# Pre-set _wall_normal so the exit check in _update_wall_run sees a valid normal.
	_player.set("_wall_normal", Vector3(-1.0, 0.0, 0.0))
	_player.set("_wall_run_timer", 0.0)

	# Force raycasts active so _update_wall_run can query them.
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_right.enabled = true
	ray_right.force_raycast_update()

	# Act — one tick.
	_tick(_player)

	# Assert — velocity.y must have decreased by WALL_RUN_GRAVITY * dt, not GRAVITY * dt.
	var expected_delta_y: float = -MovementController.WALL_RUN_GRAVITY * PHYSICS_DT
	assert_float(_player.velocity.y).is_between(
		expected_delta_y - 0.01,
		expected_delta_y + 0.01
	)
	# Extra guard: full-gravity delta would be -GRAVITY * dt ≈ -0.4 — must NOT be that.
	var full_gravity_delta: float = -MovementController.GRAVITY * PHYSICS_DT
	assert_bool(absf(_player.velocity.y - full_gravity_delta) > 0.1).is_true()


# ---------------------------------------------------------------------------
# Fall cap — velocity.y clamped to -WALL_RUN_FALL_CAP during WALL_RUNNING
# ---------------------------------------------------------------------------

## GIVEN : Player WALL_RUNNING, velocity.y = -10.0 (far below the cap).
## WHEN  : One tick with wall contact maintained.
## THEN  : velocity.y == -WALL_RUN_FALL_CAP (= -3.0).
##
## Verifies the fall cap: max(velocity.y, -WALL_RUN_FALL_CAP).
func test_wall_run_fall_cap_clamps_velocity_y() -> void:
	# Arrange — right-side wall to maintain contact.
	var wall: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	auto_free(wall)

	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.velocity = Vector3(0.0, -10.0, 0.0)
	_set_state(_player, MovementController.State.WALL_RUNNING)
	_player.set("_wall_normal", Vector3(-1.0, 0.0, 0.0))
	_player.set("_wall_run_timer", 0.0)

	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_right.enabled = true
	ray_right.force_raycast_update()

	# Act.
	_tick(_player)

	# Assert — fall cap enforced.
	assert_float(_player.velocity.y).is_greater_equal(-MovementController.WALL_RUN_FALL_CAP - 0.001)


# ---------------------------------------------------------------------------
# AC-MV-33 — Timeout exits wall-run after 1.5 s
# ---------------------------------------------------------------------------

## GIVEN : Player WALL_RUNNING, right-side wall present (raycasts hit every tick).
## WHEN  : 91 ticks elapsed (91 × 1/60 ≈ 1.517 s > WALL_RUN_MAX_DURATION = 1.5 s).
## THEN  : _state == AIRBORNE AND wall_normal == Vector3.ZERO.
func test_wall_run_timeout_exits_after_1_5_seconds() -> void:
	# Arrange — right-side wall stays in place for all ticks.
	var wall: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	auto_free(wall)

	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.velocity = Vector3(0.0, 0.0, 0.0)
	_set_state(_player, MovementController.State.WALL_RUNNING)
	_player.set("_wall_normal", Vector3(-1.0, 0.0, 0.0))
	_player.set("_wall_run_timer", 0.0)

	# Enable rays before the loop so step 0b doesn't disable them before entry.
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_right.enabled = true

	# Act — 91 ticks: timer reaches 91/60 ≈ 1.517 s > 1.5 s.
	for _i: int in 91:
		ray_right.force_raycast_update()
		_tick(_player)

	# Assert — timeout exit.
	assert_bool(_player._state == MovementController.State.AIRBORNE).is_true()
	assert_bool(_player.wall_normal == Vector3.ZERO).is_true()


# ---------------------------------------------------------------------------
# AC-MV-31 — Exit wall-run when raycast contact is lost
# ---------------------------------------------------------------------------

## GIVEN : Player WALL_RUNNING with right-side wall present, stable for 1 tick.
## WHEN  : Wall is removed (queue_free), one more tick runs.
## THEN  : _state == AIRBORNE AND _wall_normal == Vector3.ZERO.
func test_wall_run_exit_when_no_raycast_hit() -> void:
	# Arrange — right-side wall for initial stable tick.
	var wall: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	# NOT auto_free — we manage lifecycle manually for this test.

	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.velocity = Vector3(0.0, 0.0, 0.0)
	_set_state(_player, MovementController.State.WALL_RUNNING)
	_player.set("_wall_normal", Vector3(-1.0, 0.0, 0.0))
	_player.set("_wall_run_timer", 0.0)

	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_right.enabled = true
	ray_right.force_raycast_update()

	# Stable tick 1 — wall present, still WALL_RUNNING.
	_tick(_player)
	assert_bool(_player._state == MovementController.State.WALL_RUNNING).is_true()

	# Remove wall and wait for physics to resolve.
	wall.queue_free()
	await get_tree().process_frame

	# Tick 2 — wall gone, raycasts miss.
	ray_right.force_raycast_update()
	var ray_left: RayCast3D = _player.get_node("%WallRayLeft") as RayCast3D
	ray_left.force_raycast_update()
	_tick(_player)

	# Assert — contact lost → AIRBORNE.
	assert_bool(_player._state == MovementController.State.AIRBORNE).is_true()
	assert_bool(_player.wall_normal == Vector3.ZERO).is_true()


# ---------------------------------------------------------------------------
# AC-MV-34 — Left ray priority in narrow corridor (both rays hit)
# ---------------------------------------------------------------------------

## GIVEN : Narrow corridor: left wall at (-0.5, 50, 0) AND right wall at (+0.5, 50, 0).
##         Player AIRBORNE at origin, can_wall_run=true, horiz velocity = (10, 0, 0).
## WHEN  : One tick (both raycasts hit simultaneously).
## THEN  : _state == WALL_RUNNING AND wall_normal == %WallRayLeft.get_collision_normal().
##         The left ray normal points in +X (wall is on the -X side of the player).
##
## Deterministic: both walls are static and symmetric. Left priority is hardcoded
## in _try_start_wall_run — no random factor.
func test_wall_run_left_priority_in_narrow_corridor() -> void:
	# Arrange — two walls forming a ~1.0 m corridor around the player.
	var wall_left: StaticBody3D = _create_wall(self, Vector3(-0.5, 50.0, 0.0))
	var wall_right: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	auto_free(wall_left)
	auto_free(wall_right)

	_player.position = Vector3(0.0, 50.0, 0.0)
	# Horizontal speed > WALL_RUN_MIN_SPEED (5 m/s).
	_player.velocity = Vector3(10.0, 0.0, 0.0)
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.set_capability(&"wall_run", true)

	# Force both rays active so _try_start_wall_run can query them.
	var ray_left: RayCast3D = _player.get_node("%WallRayLeft") as RayCast3D
	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_left.enabled = true
	ray_right.enabled = true
	ray_left.force_raycast_update()
	ray_right.force_raycast_update()

	# Act — one tick triggers _try_start_wall_run.
	_tick(_player)

	# Assert — must have entered WALL_RUNNING with the left ray's normal.
	assert_bool(_player._state == MovementController.State.WALL_RUNNING).is_true()

	# Left wall is at -0.5 on X, so its outward normal points toward +X.
	var expected_normal: Vector3 = ray_left.get_collision_normal()
	assert_float(_player.wall_normal.x).is_equal_approx(expected_normal.x, 0.01)
	assert_float(_player.wall_normal.y).is_equal_approx(expected_normal.y, 0.01)
	assert_float(_player.wall_normal.z).is_equal_approx(expected_normal.z, 0.01)


# ---------------------------------------------------------------------------
# wall_normal read-only — Vector3.ZERO outside WALL_RUNNING
# ---------------------------------------------------------------------------

## GIVEN : Player GROUNDED (default state).
## WHEN  : One tick.
## THEN  : wall_normal == Vector3.ZERO (property exposed, no WALL_RUNNING active).
func test_wall_normal_is_zero_outside_wall_running() -> void:
	# Arrange — GROUNDED is default; _wall_normal backing field starts ZERO.
	assert_bool(_player._state == MovementController.State.GROUNDED).is_true()

	# Act.
	_tick(_player)

	# Assert — public read-only property returns ZERO when not wall-running.
	assert_bool(_player.wall_normal == Vector3.ZERO).is_true()


# ---------------------------------------------------------------------------
# can_wall_run gate — wall-run blocked when flag is false
# ---------------------------------------------------------------------------

## GIVEN : Player AIRBORNE, horiz_speed = 10, right wall present, can_wall_run=false.
## WHEN  : One tick.
## THEN  : _state == AIRBORNE (not WALL_RUNNING) — ability gate respected.
func test_wall_run_blocked_when_can_wall_run_false() -> void:
	# Arrange.
	var wall: StaticBody3D = _create_wall(self, Vector3(0.5, 50.0, 0.0))
	auto_free(wall)

	_player.position = Vector3(0.0, 50.0, 0.0)
	_player.velocity = Vector3(10.0, 0.0, 0.0)
	_set_state(_player, MovementController.State.AIRBORNE)
	_player.set_capability(&"wall_run", false)  # gate closed

	var ray_right: RayCast3D = _player.get_node("%WallRayRight") as RayCast3D
	ray_right.enabled = true
	ray_right.force_raycast_update()

	# Act.
	_tick(_player)

	# Assert — must stay AIRBORNE.
	assert_bool(_player._state == MovementController.State.AIRBORNE).is_true()
	assert_bool(_player.wall_normal == Vector3.ZERO).is_true()
