# Tests d'intégration AC-VFX-24 — VFXSystem outbound-zero mutation.
# Couvre le runtime contract : `_on_enemy_killed`, `_on_swing_started/ended`,
# `_on_died`, `_on_respawned` ne mutent JAMAIS les nodes upstream
# (enemy / combat / camera) ni leurs propriétés observables.
#
# Complément story-007 : le lint static `lint-vfx-outbound` (AC-VFX-23) couvre
# `emit_signal` interdit dans le code VFX, mais ne peut pas attraper une mutation
# directe `enemy.position = X`. Ce test couvre la moitié runtime du contract.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — nodes réels Node3D pour observer global_position post-handler.

extends GdUnitTestSuite

var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")
var _MockGSM: GDScript = preload("res://tests/unit/vfx/mock_gsm.gd")


# =============================================================================
# Helpers
# =============================================================================

## Instancie VFXSystem + mocks Combat/Enemy/Camera/GSM PLAYING (handlers actifs).
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm].
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_gsm)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_gsm_signals(mock_gsm)

	return [vfx, mock_combat, mock_enemy, mock_camera, mock_gsm]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-24 — Runtime mutation property check
# =============================================================================

## GIVEN un Node3D réel `enemy_node` avec global_position fixe + mocks Combat/Camera
##       avec metadata pré-set, VFXSystem actif (PLAYING),
## WHEN tous les handlers VFX sont triggered (enemy_killed avec enemy_node ref +
##      swing_started/ended + died + respawned),
## THEN aucune propriété observable des nodes upstream n'est mutée :
##      enemy_node.global_position / global_rotation / scale + mock_combat.metadata
##      + mock_camera.metadata sont identiques pre/post.
func test_handlers_do_not_mutate_upstream_nodes_properties() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]
	var mock_enemy: Node = nodes[2]
	var mock_camera: Node = nodes[3]

	# Real Node3D enemy positionné — VFX reçoit la ref dans `_on_enemy_killed(enemy, pos)`
	var enemy_node: Node3D = Node3D.new()
	enemy_node.name = &"TestEnemyNode3D"
	add_child(enemy_node)
	enemy_node.global_position = Vector3(5.0, 2.0, -3.0)
	enemy_node.scale = Vector3(1.5, 1.5, 1.5)
	enemy_node.rotation = Vector3(0.0, deg_to_rad(45.0), 0.0)

	# Metadata observables sur mock_combat / mock_camera (Node, pas Node3D)
	mock_combat.set_meta(&"vfx_test_marker", 42)
	mock_camera.set_meta(&"vfx_test_marker", 99)

	# Snapshot pré-handlers
	var enemy_pos_pre: Vector3 = enemy_node.global_position
	var enemy_scale_pre: Vector3 = enemy_node.scale
	var enemy_rot_pre: Vector3 = enemy_node.rotation
	var combat_meta_pre: int = mock_combat.get_meta(&"vfx_test_marker")
	var camera_meta_pre: int = mock_camera.get_meta(&"vfx_test_marker")
	var enemy_name_pre: StringName = enemy_node.name
	var combat_name_pre: StringName = mock_combat.name
	var camera_name_pre: StringName = mock_camera.name

	# Mock time fixe — laisser flash kill / trail fade fonctionner sans variance
	var mocked_msec: int = 1000
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — émettre TOUS les handlers VFX dans une séquence réaliste
	# (1) enemy_killed avec ref Node3D réelle (non null) — AC-VFX-24 cible principale
	mock_enemy.emit_enemy_killed(enemy_node, enemy_node.global_position)
	await get_tree().physics_frame

	# (2) swing_started + swing_ended via mock_combat
	mock_combat.emit_swing_started(Vector3.FORWARD)
	await get_tree().physics_frame
	mock_combat.emit_swing_ended()
	await get_tree().physics_frame

	# (3) died via mock_camera
	mock_camera.emit_died()
	await get_tree().physics_frame

	# (4) respawned via mock_camera
	mock_camera.emit_respawned(Vector3.ZERO)
	await get_tree().physics_frame

	# Assert — enemy_node Node3D properties intactes
	assert_vector(enemy_node.global_position) \
		.override_failure_message("AC-VFX-24: enemy_node.global_position muté par VFX (pre=%s, post=%s)" % [enemy_pos_pre, enemy_node.global_position]) \
		.is_equal_approx(enemy_pos_pre, Vector3(0.0001, 0.0001, 0.0001))

	assert_vector(enemy_node.scale) \
		.override_failure_message("AC-VFX-24: enemy_node.scale muté par VFX (pre=%s, post=%s)" % [enemy_scale_pre, enemy_node.scale]) \
		.is_equal_approx(enemy_scale_pre, Vector3(0.0001, 0.0001, 0.0001))

	assert_vector(enemy_node.rotation) \
		.override_failure_message("AC-VFX-24: enemy_node.rotation muté par VFX (pre=%s, post=%s)" % [enemy_rot_pre, enemy_node.rotation]) \
		.is_equal_approx(enemy_rot_pre, Vector3(0.0001, 0.0001, 0.0001))

	# Assert — names inchangés (proxy pour aucune ré-allocation node)
	assert_str(String(enemy_node.name)) \
		.override_failure_message("AC-VFX-24: enemy_node.name muté par VFX (pre=%s, post=%s)" % [enemy_name_pre, enemy_node.name]) \
		.is_equal(String(enemy_name_pre))

	assert_str(String(mock_combat.name)) \
		.override_failure_message("AC-VFX-24: mock_combat.name muté par VFX (pre=%s, post=%s)" % [combat_name_pre, mock_combat.name]) \
		.is_equal(String(combat_name_pre))

	assert_str(String(mock_camera.name)) \
		.override_failure_message("AC-VFX-24: mock_camera.name muté par VFX (pre=%s, post=%s)" % [camera_name_pre, mock_camera.name]) \
		.is_equal(String(camera_name_pre))

	# Assert — metadata observables intactes (proxy pour aucun set_meta upstream)
	assert_int(mock_combat.get_meta(&"vfx_test_marker")) \
		.override_failure_message("AC-VFX-24: mock_combat metadata mutée par VFX (pre=%d, post=%d)" % [combat_meta_pre, mock_combat.get_meta(&"vfx_test_marker")]) \
		.is_equal(combat_meta_pre)

	assert_int(mock_camera.get_meta(&"vfx_test_marker")) \
		.override_failure_message("AC-VFX-24: mock_camera metadata mutée par VFX (pre=%d, post=%d)" % [camera_meta_pre, mock_camera.get_meta(&"vfx_test_marker")]) \
		.is_equal(camera_meta_pre)

	# Cleanup
	enemy_node.queue_free()
	_free_all(nodes)


# =============================================================================
# AC-VFX-24 — Variant : enemy_killed avec ref Node3D + flash kill secondaire
# =============================================================================

## GIVEN un Node3D enemy proche d'un kill cluster (5 kills successifs),
## WHEN les 5 enemy_killed sont émis avec la même ref Node3D,
## THEN enemy_node.global_position reste identique malgré tous les decals + particles
##      + flash kill spawned (regression guard contre mutation accidentelle dans
##      _spawn_blood_spurt / _spawn_decal_on_surface / _trigger_flash_kill).
func test_repeated_enemy_killed_does_not_mutate_enemy_ref() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]

	var enemy_node: Node3D = Node3D.new()
	enemy_node.name = &"ClusterKillEnemy"
	add_child(enemy_node)
	enemy_node.global_position = Vector3(10.0, 0.0, 0.0)

	var pos_pre: Vector3 = enemy_node.global_position

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — 5 kills successifs avec time avance pour bypass WCAG 333 ms guard
	for i: int in range(5):
		mocked_msec = i * 400  # > 333 ms entre chaque flash
		mock_enemy.emit_enemy_killed(enemy_node, enemy_node.global_position)
		await get_tree().physics_frame

	# Assert — position inchangée après 5 kills + decals + particles + flashes
	assert_vector(enemy_node.global_position) \
		.override_failure_message("AC-VFX-24: enemy_node.global_position muté après 5 kills successifs (pre=%s, post=%s)" % [pos_pre, enemy_node.global_position]) \
		.is_equal_approx(pos_pre, Vector3(0.0001, 0.0001, 0.0001))

	# Cleanup
	enemy_node.queue_free()
	_free_all(nodes)
