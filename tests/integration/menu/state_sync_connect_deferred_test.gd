extends GdUnitTestSuite

## AC-MNU-12/33/34/35 — state sync handler via CONNECT_DEFERRED + pull resync (story-004).
##
## Couvre :
##   AC-MNU-12 [BLOCKING] : PLAYING + request_pause() → state_changed(PAUSED) deferred → panel.visible == true.
##   AC-MNU-33 [BLOCKING] : sync direct call _on_gsm_state_changed(PAUSED) → panel.visible == true même frame.
##   AC-MNU-34 [BLOCKING] : direct call _on_gsm_state_changed(RESPAWNING) → panel.visible == false (anti-flicker).
##   AC-MNU-35 [BLOCKING] : GSM=PAUSED AVANT instantiation → _ready() pull resync → panel.visible == true.
##
## Pattern : drive GSM via _current_state direct (cohérent ui_cancel_trigger_test.gd) +
## save/restore en before_test/after_test pour isolation.

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")
const PAUSE_CTRL_PATH: String = "res://src/gameplay/menu/pause_menu_controller.gd"

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


func _spawn_pause_layer() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func _get_panel(layer: CanvasLayer) -> PanelContainer:
	return layer.get_node("PausePanel") as PanelContainer


func test_ac_mnu_12_request_pause_propagates_visible_via_deferred() -> void:
	# AC-MNU-12 : PLAYING + request_pause → state_changed(PAUSED) CONNECT_DEFERRED →
	# après 1 process_frame le panel est visible.
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame  # _ready completed + pull resync run

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-12 setup: panel must be hidden in PLAYING state pre-pause") \
		.is_false()

	GameStateManager.request_pause()
	# CONNECT_DEFERRED — handler tourne au prochain idle frame, pas synchrone.
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-12: GSM should be PAUSED after request_pause") \
		.is_equal(GameStateManager.State.PAUSED)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-12: panel must be visible after deferred state_changed(PAUSED)") \
		.is_true()


func test_ac_mnu_33_sync_direct_call_paused_shows_panel_immediately() -> void:
	# AC-MNU-33 : appel direct du handler avec PAUSED → visible immédiat (sync interne).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible).is_false()  # PLAYING setup baseline

	# Sync direct call — pas de await, le handler est sync interne.
	_pause_layer.call("_on_gsm_state_changed", GameStateManager.State.PAUSED)

	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-33: direct _on_gsm_state_changed(PAUSED) must show panel same frame") \
		.is_true()


func test_ac_mnu_34_respawning_hides_panel_immediately() -> void:
	# AC-MNU-34 : panel visible (PAUSED) ; appel direct RESPAWNING → hidden (Pillar 3 anti-flicker).
	GameStateManager._current_state = GameStateManager.State.PAUSED
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-34 setup: panel must be visible in PAUSED state via pull resync") \
		.is_true()

	# Direct call avec RESPAWNING (pas une transition GSM légale depuis PAUSED, mais
	# le handler doit gérer le cas pour défense en profondeur — Pillar 3).
	_pause_layer.call("_on_gsm_state_changed", GameStateManager.State.RESPAWNING)

	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-34: RESPAWNING must hide panel immediately (anti-flicker)") \
		.is_false()


func test_ac_mnu_35_paused_at_boot_pull_resync_shows_panel() -> void:
	# AC-MNU-35 : ADR-0007 D-9 pull pattern — overlay instancié alors que GSM est déjà
	# PAUSED. Sans pull resync au _ready, le panel raterait l'état initial.
	GameStateManager._current_state = GameStateManager.State.PAUSED
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-35: pull resync at _ready must apply PAUSED visibility (panel shown)") \
		.is_true()


func test_ac_mnu_35_extended_menu_at_boot_pull_resync_hides_panel() -> void:
	# AC-MNU-35 (extension) : MENU au boot → panel hidden via pull resync (cohérence
	# matrice visibility R-MNU-4 — MENU/RESPAWNING/BOSS_DEFEATED hide).
	GameStateManager._current_state = GameStateManager.State.MENU
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-35 ext: MENU pull resync must hide panel") \
		.is_false()


func test_handler_connected_with_connect_deferred_flag() -> void:
	# Garantie r2 BLK-1 : le handler _on_gsm_state_changed est bien connecté avec
	# CONNECT_DEFERRED (flag = 1), pas en mode SYNC default. Inspecte la connexion
	# via get_connections() pour vérifier le flag.
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var connections: Array = GameStateManager.state_changed.get_connections()
	var found_deferred: bool = false
	for conn: Dictionary in connections:
		var callable: Callable = conn["callable"]
		var target: Object = callable.get_object()
		if target == null:
			continue
		var target_script: Script = target.get_script() as Script
		if target_script == null:
			continue
		if target_script.resource_path != PAUSE_CTRL_PATH:
			continue
		# Trouvé la connexion PauseMenuController — vérifier flags.
		var flags: int = conn["flags"] as int
		if (flags & CONNECT_DEFERRED) != 0:
			found_deferred = true
			break

	assert_bool(found_deferred) \
		.override_failure_message("r2 BLK-1: PauseMenuController._on_gsm_state_changed must be connected with CONNECT_DEFERRED") \
		.is_true()
