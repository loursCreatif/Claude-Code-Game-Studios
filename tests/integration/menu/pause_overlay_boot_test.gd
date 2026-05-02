extends GdUnitTestSuite

## AC-MNU-6 — Pause Overlay boot lifecycle integration (story-002).
##
## Couvre :
##   AC-MNU-6  : PauseLayer.visible == false ET PausePanel.visible == false après _ready().
##   AC-MNU-37 : PauseLayer.process_mode == 3 (PROCESS_MODE_ALWAYS Godot 4.6) post-_ready
##               (preuve runtime au-delà du lint static .tscn).
##
## Framework : GdUnit4 (extends GdUnitTestSuite).

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")

var _pause_layer: CanvasLayer


func before_test() -> void:
	_pause_layer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(_pause_layer)
	add_child(_pause_layer)


func test_pause_overlay_layer_hidden_at_boot() -> void:
	# AC-MNU-6 — root CanvasLayer reste rendu mais panel caché (anti-flash 1 frame).
	# Le CanvasLayer lui-même n'a pas de propriété visible standard ; on vérifie le panel.
	await get_tree().process_frame
	var panel: PanelContainer = _pause_layer.get_node("PausePanel")
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-6: PausePanel must be hidden at boot — got visible=true (anti-flash EC-MNU-32/40 violated)") \
		.is_false()


func test_pause_overlay_process_mode_runtime_equals_always() -> void:
	# AC-MNU-37 — preuve runtime que process_mode == 3 (PROCESS_MODE_ALWAYS).
	# Double assert : symbolic ET literal (erratum Godot 4.6 — 4 = DISABLED).
	await get_tree().process_frame
	assert_int(_pause_layer.process_mode) \
		.override_failure_message("AC-MNU-37: PauseLayer.process_mode must equal 3 (PROCESS_MODE_ALWAYS) — got %d" % _pause_layer.process_mode) \
		.is_equal(3)
	assert_int(_pause_layer.process_mode) \
		.override_failure_message("AC-MNU-37: PauseLayer.process_mode must equal Node.PROCESS_MODE_ALWAYS symbolic constant") \
		.is_equal(Node.PROCESS_MODE_ALWAYS)
