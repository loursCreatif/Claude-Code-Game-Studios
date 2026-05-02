extends GdUnitTestSuite

## AC-MNU-8/9 — Pause Overlay lifecycle propre lors de scene transition (story-005).
##
## AC-MNU-8 [Integration — BLOCKING] : Pause Overlay actif ; scene change → aucun node
## dans `get_tree().get_nodes_in_group("pause_overlay")` (no orphan).
## AC-MNU-9 [Logic — BLOCKING] : `tree_exiting` émis par PauseLayer AVANT que la prochaine
## scène ne soit prête.
##
## Pattern : simulate scene transition via `queue_free()` + process frames. Cela teste
## le contrat Godot natif (group purge + tree_exiting émission) sans set up complexe
## de change_scene_to_file.

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")
const GROUP_NAME: StringName = &"pause_overlay"

var _pause_layer: CanvasLayer


func before_test() -> void:
	pass


func after_test() -> void:
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null
	await get_tree().process_frame


func _spawn() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func test_ac_mnu_8_pause_overlay_in_group_at_spawn() -> void:
	# Pré-condition AC-MNU-8 : `add_to_group("pause_overlay")` posé au _ready.
	_pause_layer = _spawn()
	await get_tree().process_frame

	var nodes: Array[Node] = get_tree().get_nodes_in_group(GROUP_NAME)
	assert_int(nodes.size()) \
		.override_failure_message("AC-MNU-8 setup: PauseLayer must register in 'pause_overlay' group at _ready — got %d" % nodes.size()) \
		.is_equal(1)
	assert_object(nodes[0]) \
		.override_failure_message("AC-MNU-8 setup: group member must be the spawned PauseLayer") \
		.is_same(_pause_layer)


func test_ac_mnu_8_no_orphan_after_node_removed() -> void:
	# AC-MNU-8 : après que le node sorte du tree (simulation scene transition), le group
	# est purgé automatiquement par Godot — aucun orphan.
	_pause_layer = _spawn()
	await get_tree().process_frame
	assert_int(get_tree().get_nodes_in_group(GROUP_NAME).size()).is_equal(1)

	# Simulate scene transition : queue_free retire le node du tree à la prochaine frame.
	_pause_layer.queue_free()
	_pause_layer = null
	await get_tree().process_frame

	var nodes_after: Array[Node] = get_tree().get_nodes_in_group(GROUP_NAME)
	assert_int(nodes_after.size()) \
		.override_failure_message("AC-MNU-8: group must be empty after Pause Overlay leaves tree — got %d orphans" % nodes_after.size()) \
		.is_equal(0)


func test_ac_mnu_9_tree_exiting_emitted_before_node_destroyed() -> void:
	# AC-MNU-9 : `tree_exiting` émis par PauseLayer dès qu'il sort du tree.
	# On capture l'émission via un spy callback connecté avant queue_free.
	_pause_layer = _spawn()
	await get_tree().process_frame

	var tree_exiting_emitted: Array[bool] = [false]
	# Capture par closure (Lambda capture l'array par référence).
	_pause_layer.tree_exiting.connect(func() -> void:
		tree_exiting_emitted[0] = true
	)

	_pause_layer.queue_free()
	# tree_exiting est émis SYNC par Godot avant que la queue_free ne complete.
	# Une frame suffit pour que le delete réel se fasse.
	await get_tree().process_frame

	assert_bool(tree_exiting_emitted[0]) \
		.override_failure_message("AC-MNU-9: tree_exiting must be emitted by PauseLayer before destruction") \
		.is_true()

	_pause_layer = null  # Node freed, after_test ne doit pas re-toucher.
