extends GdUnitTestSuite

## AC-MNU-7 [Logic — BLOCKING] : pull pattern resync au boot en PAUSED → visible immédiat.
## + edge cases snap binaire `_apply_visibility(true/false)` + guard `is_inside_tree()` r2 BLK-3.
##
## Pattern : drive GSM via _current_state direct + save/restore (cohérent ui_cancel_trigger_test).

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")

var _pause_layer: CanvasLayer
var _saved_gsm_state: int


func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state


func after_test() -> void:
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null
	await get_tree().process_frame


func _spawn() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func _panel(layer: CanvasLayer) -> PanelContainer:
	return layer.get_node("PausePanel") as PanelContainer


func test_ac_mnu_7_pull_resync_paused_at_boot_shows_panel() -> void:
	# AC-MNU-7 : GSM=PAUSED + spawn → _ready pull resync via _apply_visibility(true) → visible.
	GameStateManager._current_state = GameStateManager.State.PAUSED
	_pause_layer = _spawn()
	await get_tree().process_frame

	assert_bool(_panel(_pause_layer).visible) \
		.override_failure_message("AC-MNU-7: pull resync PAUSED at boot must invoke _apply_visibility(true) → panel visible") \
		.is_true()


func test_apply_visibility_snap_binary_show_then_hide() -> void:
	# Snap binaire R-MNU-15 — zéro tween : `pause_panel.visible` doit refléter le param immédiatement.
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn()
	await get_tree().process_frame

	var panel: PanelContainer = _panel(_pause_layer)

	_pause_layer.call("_apply_visibility", true, false)
	assert_bool(panel.visible) \
		.override_failure_message("snap show: visible must be true immediately") \
		.is_true()

	_pause_layer.call("_apply_visibility", false, false)
	assert_bool(panel.visible) \
		.override_failure_message("snap hide: visible must be false immediately") \
		.is_false()

	_pause_layer.call("_apply_visibility", true, true)
	assert_bool(panel.visible).is_true()


func test_apply_visibility_default_recapture_true() -> void:
	# r2 BLK-2 signature : default `recapture_mouse = true` (caller peut omettre).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn()
	await get_tree().process_frame

	# Appel avec un seul arg — default recapture_mouse=true doit être appliqué sans crash.
	_pause_layer.call("_apply_visibility", true)
	assert_bool(_panel(_pause_layer).visible).is_true()

	_pause_layer.call("_apply_visibility", false)
	assert_bool(_panel(_pause_layer).visible).is_false()


func test_apply_visibility_guard_returns_when_not_in_tree() -> void:
	# r2 BLK-3 : guard `is_inside_tree()` — appel sur un node hors du tree ne crash pas
	# et ne modifie pas le panel. Crée un controller orphelin (pas add_child).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	var orphan: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(orphan)
	# Pas d'add_child — le node n'est pas dans le tree.
	# Mais le @onready var pause_panel n'est pas résolu sans _ready run. Ajouter d'abord
	# pour que _ready execute, puis remove pour tester le guard out-of-tree.
	add_child(orphan)
	await get_tree().process_frame
	remove_child(orphan)

	# Le panel a été initialisé par _ready avant remove. Set a known state.
	var panel: PanelContainer = orphan.get_node("PausePanel") as PanelContainer
	panel.visible = false

	# Appel hors tree — guard doit retourner sans toucher panel.visible.
	orphan.call("_apply_visibility", true, false)

	assert_bool(panel.visible) \
		.override_failure_message("r2 BLK-3 guard: out-of-tree _apply_visibility must no-op (panel.visible unchanged)") \
		.is_false()

	orphan.queue_free()
