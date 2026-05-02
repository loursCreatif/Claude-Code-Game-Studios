# Unit tests for Story 002 — Grunt collision layers (AC-ENM-06).
# Verifies body & LaserCone layer/mask bits + monitoring=true post-_ready.
#
# Pattern : load Grunt.tscn (canonical scene Rule 3), instantiate, add_child,
# await process_frame → _ready runs → assert API 1-idx values.
#
# Story Type : Logic. Test Evidence path : tests/unit/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRUNT_SCENE_PATH: String = "res://src/gameplay/enemy/Grunt.tscn"


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _grunt: Grunt = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(GRUNT_SCENE_PATH) as PackedScene
	_grunt = packed.instantiate() as Grunt
	add_child(_grunt)
	await get_tree().process_frame


func after_test() -> void:
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-06 — Body & LaserCone collision layers
# ---------------------------------------------------------------------------

func test_grunt_body_layer_is_layer_enemy_only() -> void:
	# Body LAYER_ENEMY=2 (bit 1, value 0b00000010 = 2).
	assert_bool(_grunt.get_collision_layer_value(CollisionLayers.LAYER_ENEMY)) \
		.override_failure_message("AC-ENM-06: body doit avoir LAYER_ENEMY=2 set") \
		.is_true()
	assert_int(_grunt.collision_layer) \
		.override_failure_message("AC-ENM-06: body.collision_layer == 0b10 (LAYER_ENEMY=2 only) — got %d" % _grunt.collision_layer) \
		.is_equal(0b10)


func test_grunt_body_mask_is_layer_environment_only() -> void:
	# Body mask LAYER_ENVIRONMENT=4 (bit 3, value 0b00001000 = 8). Pas de mask LAYER_ENEMY
	# (ennemis ne se collisionnent pas entre eux — anti train-wreck Rule 4).
	assert_bool(_grunt.get_collision_mask_value(CollisionLayers.LAYER_ENVIRONMENT)) \
		.override_failure_message("AC-ENM-06: body mask doit avoir LAYER_ENVIRONMENT=4") \
		.is_true()
	assert_bool(_grunt.get_collision_mask_value(CollisionLayers.LAYER_ENEMY)) \
		.override_failure_message("AC-ENM-06: body mask ne doit PAS avoir LAYER_ENEMY (anti train-wreck)") \
		.is_false()
	assert_int(_grunt.collision_mask) \
		.override_failure_message("AC-ENM-06: body.collision_mask == 0b1000 (LAYER_ENVIRONMENT=4 only) — got %d" % _grunt.collision_mask) \
		.is_equal(0b1000)


func test_laser_cone_layer_is_layer_enemy_hitbox_only() -> void:
	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	assert_object(cone).is_not_null()

	# LaserCone LAYER_ENEMY_HITBOX=3 (bit 2, value 0b00000100 = 4).
	assert_bool(cone.get_collision_layer_value(CollisionLayers.LAYER_ENEMY_HITBOX)) \
		.override_failure_message("AC-ENM-06: LaserCone doit avoir LAYER_ENEMY_HITBOX=3 set") \
		.is_true()
	assert_int(cone.collision_layer) \
		.override_failure_message("AC-ENM-06: LaserCone.collision_layer == 0b100 (LAYER_ENEMY_HITBOX=3 only)") \
		.is_equal(0b100)


func test_laser_cone_mask_is_layer_player_only() -> void:
	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	assert_object(cone).is_not_null()

	# LaserCone mask LAYER_PLAYER=1 (bit 0, value 0b00000001 = 1).
	assert_bool(cone.get_collision_mask_value(CollisionLayers.LAYER_PLAYER)) \
		.override_failure_message("AC-ENM-06: LaserCone mask doit avoir LAYER_PLAYER=1") \
		.is_true()
	assert_int(cone.collision_mask) \
		.override_failure_message("AC-ENM-06: LaserCone.collision_mask == 0b1 (LAYER_PLAYER=1 only)") \
		.is_equal(0b1)


func test_laser_cone_monitoring_enabled_at_ready() -> void:
	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	assert_bool(cone.monitoring) \
		.override_failure_message("AC-ENM-06: LaserCone.monitoring doit être true au _ready (ALIVE state)") \
		.is_true()


# ---------------------------------------------------------------------------
# Bonus — LaserCone monitoring=false post-die() (Rule 11.b)
# ---------------------------------------------------------------------------

func test_laser_cone_monitoring_disabled_at_dying() -> void:
	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	assert_bool(cone.monitoring).is_true()

	# Act
	_grunt.die()

	# Assert — Rule 11.b : monitoring=false IMMÉDIATEMENT à DYING (pas en attente du tween).
	assert_bool(cone.monitoring) \
		.override_failure_message("Rule 11.b: LaserCone.monitoring=false dès DYING (avant fin du tween 150 ms)") \
		.is_false()
