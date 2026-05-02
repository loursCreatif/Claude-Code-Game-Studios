extends GdUnitTestSuite

## AC-MNU-11/13/14/15/16 — ESC ui_cancel_pressed trigger pause/resume (story-003).
##
## Couvre :
##   AC-MNU-11 [BLOCKING] : PLAYING + ESC → request_pause() exactement 1×.
##   AC-MNU-13 [BLOCKING] : PAUSED + ESC → request_resume() 1× + state_changed(PLAYING) propagé.
##   AC-MNU-14 [BLOCKING] : RESPAWNING + ESC → no-op (ni pause ni resume, aucune exception).
##   AC-MNU-15 [BLOCKING] : MENU sans Pause Overlay instancié + ESC → aucun crash, aucun handler.
##   AC-MNU-16 [BLOCKING] : PLAYING + double ESC même frame → request_pause() 1× (GSM idempotent).
##
## Pattern : drive GSM via _current_state direct (cohérent credit_economy_run_purge_test.gd) +
## save/restore en before_test/after_test pour isolation.

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")

var _pause_layer: CanvasLayer
var _saved_gsm_state: int
var _state_changed_calls: Array[int] = []


func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state
	_state_changed_calls.clear()
	# Connect spy AVANT instantiation pour capter tout emit pendant _ready.
	GameStateManager.state_changed.connect(_on_state_changed_capture)


func after_test() -> void:
	# Restaurer le state GSM avant nettoyage scène — sinon transitions illégales
	# (ex. PLAYING avec tree.paused résiduel) peuvent leak entre tests.
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	if GameStateManager.state_changed.is_connected(_on_state_changed_capture):
		GameStateManager.state_changed.disconnect(_on_state_changed_capture)
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null


func _on_state_changed_capture(new_state: int) -> void:
	_state_changed_calls.append(new_state)


func _spawn_pause_layer() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func test_ac_mnu_11_playing_esc_triggers_request_pause() -> void:
	# AC-MNU-11 : GSM=PLAYING + Pause Overlay instancié → ESC = request_pause 1×.
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	_state_changed_calls.clear()  # Drop signaux _ready, on mesure l'effet de l'ESC seul.

	InputManager.ui_cancel_pressed.emit()
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-11: GSM should transition PLAYING → PAUSED on ESC") \
		.is_equal(GameStateManager.State.PAUSED)
	assert_array(_state_changed_calls) \
		.override_failure_message("AC-MNU-11: state_changed must emit exactly 1× with PAUSED — got %s" % str(_state_changed_calls)) \
		.is_equal([GameStateManager.State.PAUSED])


func test_ac_mnu_13_paused_esc_triggers_request_resume() -> void:
	# AC-MNU-13 : GSM=PAUSED + ESC → request_resume 1× + state_changed(PLAYING).
	# On part de PLAYING puis on transite legalement via request_pause pour avoir
	# un état PAUSED cohérent (tree.paused == true).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-13 setup: GSM should be PAUSED before ESC test") \
		.is_equal(GameStateManager.State.PAUSED)

	_state_changed_calls.clear()

	InputManager.ui_cancel_pressed.emit()
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-13: GSM should transition PAUSED → PLAYING on ESC") \
		.is_equal(GameStateManager.State.PLAYING)
	assert_array(_state_changed_calls) \
		.override_failure_message("AC-MNU-13: state_changed must emit PLAYING after resume — got %s" % str(_state_changed_calls)) \
		.is_equal([GameStateManager.State.PLAYING])


func test_ac_mnu_14_respawning_esc_is_noop() -> void:
	# AC-MNU-14 : GSM=RESPAWNING + ESC → no-op (matrice ADR-0007 D-2).
	GameStateManager._current_state = GameStateManager.State.RESPAWNING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	_state_changed_calls.clear()

	InputManager.ui_cancel_pressed.emit()
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-14: RESPAWNING + ESC must remain RESPAWNING (no-op)") \
		.is_equal(GameStateManager.State.RESPAWNING)
	assert_array(_state_changed_calls) \
		.override_failure_message("AC-MNU-14: state_changed must NOT emit during RESPAWNING + ESC") \
		.is_empty()


func test_ac_mnu_14_boss_defeated_and_menu_esc_are_noop() -> void:
	# AC-MNU-14 (extension) : BOSS_DEFEATED + MENU même comportement no-op.
	for state_id: int in [GameStateManager.State.BOSS_DEFEATED, GameStateManager.State.MENU]:
		GameStateManager._current_state = state_id
		var layer: CanvasLayer = _spawn_pause_layer()
		await get_tree().process_frame
		_state_changed_calls.clear()

		InputManager.ui_cancel_pressed.emit()
		await get_tree().process_frame

		assert_int(GameStateManager.get_current_state()) \
			.override_failure_message("AC-MNU-14 ext: state %s must remain unchanged on ESC" % GameStateManager.State.keys()[state_id]) \
			.is_equal(state_id)
		assert_array(_state_changed_calls) \
			.override_failure_message("AC-MNU-14 ext: no state_changed during %s + ESC" % GameStateManager.State.keys()[state_id]) \
			.is_empty()

		layer.queue_free()
		await get_tree().process_frame


func test_ac_mnu_15_menu_no_pause_overlay_esc_no_crash() -> void:
	# AC-MNU-15 : MENU sans Pause Overlay → ESC dans le vide, aucun crash.
	GameStateManager._current_state = GameStateManager.State.MENU
	# Pas d'instantiation pause_overlay — on simule l'état boot menu.

	# Vérifier qu'aucun handler du script pause_menu_controller.gd n'est connecté.
	var connections: Array = InputManager.ui_cancel_pressed.get_connections()
	const PAUSE_CTRL_PATH: String = "res://src/gameplay/menu/pause_menu_controller.gd"
	for conn: Dictionary in connections:
		var callable: Callable = conn["callable"]
		var target: Object = callable.get_object()
		if target == null:
			continue
		var target_script: Script = target.get_script() as Script
		if target_script == null:
			continue
		assert_str(target_script.resource_path) \
			.override_failure_message("AC-MNU-15: no PauseMenuController instance should be connected to ui_cancel_pressed in MENU state without overlay") \
			.is_not_equal(PAUSE_CTRL_PATH)

	_state_changed_calls.clear()

	# Émettre — doit no-op car aucun handler PauseMenu.
	InputManager.ui_cancel_pressed.emit()
	await get_tree().process_frame

	# Pas de crash + pas de transition state.
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-15: MENU + ESC without overlay must remain MENU") \
		.is_equal(GameStateManager.State.MENU)


func test_ac_mnu_16_double_esc_same_frame_idempotent() -> void:
	# AC-MNU-16 : 2× ui_cancel_pressed même frame physique → request_pause() effectif 1×.
	# Idempotence absorbée par GSM guard (D-7), pas par Menu.
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	_state_changed_calls.clear()

	# Double emit synchrone.
	InputManager.ui_cancel_pressed.emit()
	InputManager.ui_cancel_pressed.emit()
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-16: GSM should be PAUSED after double ESC") \
		.is_equal(GameStateManager.State.PAUSED)
	assert_array(_state_changed_calls) \
		.override_failure_message("AC-MNU-16: state_changed must emit exactly 1× even with double emit (GSM idempotence) — got %s" % str(_state_changed_calls)) \
		.is_equal([GameStateManager.State.PAUSED])
