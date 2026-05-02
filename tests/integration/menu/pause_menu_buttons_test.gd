extends GdUnitTestSuite

## AC-MNU-21/22/23/24/25/32 — boutons Pause Menu Resume/MainMenu/Quit (story-007).
##
## Pattern : test seams Callable (`_main_menu_handler`, `_quit_handler`) du
## `PauseMenuControllerScript` overridés par spies pour isoler les callbacks
## sans déclencher `change_scene_to_file` (qui détruirait le node de test) ni
## `get_tree().quit()` (qui terminerait le runner).
##
## Ordre release-avant-transition (AC-MNU-22 / AC-MNU-32) vérifié via observation
## directe de `InputManager._enable_blockers` : avant le seam, le blocker doit
## déjà être absent (preuve que `release_enable_request` s'est exécuté avant).
## Approche plus déterministe que des timestamps `Time.get_ticks_usec()`.
##
## Resume idempotence (AC-MNU-24) : 2 emits → request_resume appelé 2× au sens
## du verbe (Menu sans guard custom, Implementation Notes), mais GSM absorbe
## via `if _current_state != PAUSED: return` → 1 seule transition state_changed.

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")

var _pause: CanvasLayer
var _saved_gsm_state: int


func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state


func after_test() -> void:
	# Cleanup InputManager blocker éventuellement laissé par un test (au cas où
	# release n'a pas été déclenché, ex. test isolant le request_disable seul).
	if _pause != null and is_instance_valid(_pause):
		var id: int = _pause.get_instance_id()
		if InputManager._enable_blockers.has(id):
			InputManager._enable_blockers.erase(id)
		_pause.queue_free()
		_pause = null
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	await get_tree().process_frame


func _spawn() -> CanvasLayer:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func _enter_paused_state() -> void:
	# Bypass GSM verbe pour mettre directement le state à PAUSED (évite émission
	# state_changed CONNECT_DEFERRED parasite). Le test contrôle ensuite l'émission.
	GameStateManager._current_state = GameStateManager.State.PAUSED


func test_ac_mnu_21_resume_button_invokes_request_resume_then_hides_overlay() -> void:
	# AC-MNU-21 : ResumeButton.pressed → request_resume() 1× ; après state_changed(PLAYING)
	# le panel devient invisible (handler story-004 + _apply_visibility story-005).
	_pause = _spawn()
	await get_tree().process_frame

	# Mise en place : GSM=PAUSED + tree.paused=true (cohérent avec request_pause sortie).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	GameStateManager.request_pause()  # Transition légale PLAYING→PAUSED via verbe officiel.
	await get_tree().process_frame  # CONNECT_DEFERRED handler propage PAUSED → panel visible.

	var pause_panel: PanelContainer = _pause.get_node("PausePanel")
	assert_bool(pause_panel.visible) \
		.override_failure_message("AC-MNU-21 precond: panel must be visible while PAUSED") \
		.is_true()

	# Act : click Resume.
	_pause.resume_button.pressed.emit()
	# request_resume est SYNC : transitionne PAUSED→PLAYING + émet state_changed(PLAYING)
	# CONNECT_DEFERRED → handler exécuté à la prochaine frame.
	await get_tree().process_frame

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-21: GSM should transition to PLAYING after Resume click") \
		.is_equal(GameStateManager.State.PLAYING)
	assert_bool(pause_panel.visible) \
		.override_failure_message("AC-MNU-21: panel must be hidden after state_changed(PLAYING) handler") \
		.is_false()


func test_ac_mnu_22_main_menu_button_releases_blocker_before_transition() -> void:
	# AC-MNU-22 : MainMenu callback ordonne (1) release_enable_request AVANT
	# (2) request_scene_transition. Vérifié en observant que le blocker a déjà
	# été retiré au moment où le seam `_main_menu_handler` s'exécute.
	_pause = _spawn()
	await get_tree().process_frame
	_enter_paused_state()

	# Setup : poser un blocker InputManager au nom du Pause Overlay.
	InputManager.request_disable(_pause)
	assert_bool(InputManager._enable_blockers.has(_pause.get_instance_id())) \
		.override_failure_message("AC-MNU-22 setup: blocker should be active before MainMenu click") \
		.is_true()

	# Spy : enregistre l'état du blocker AU MOMENT où le seam s'exécute.
	# Ordre attendu (production) : _apply_visibility → release_enable_request → seam.
	# Donc à l'entrée du seam, le blocker doit déjà être absent.
	var blocker_present_at_transition: Array[bool] = [true]  # init pessimiste
	var seam_call_count: Array[int] = [0]
	_pause._main_menu_handler = func() -> void:
		seam_call_count[0] += 1
		blocker_present_at_transition[0] = InputManager._enable_blockers.has(_pause.get_instance_id())

	# Act : click MainMenu.
	_pause.main_menu_button.pressed.emit()

	assert_int(seam_call_count[0]) \
		.override_failure_message("AC-MNU-22: _main_menu_handler must fire exactly 1×") \
		.is_equal(1)
	assert_bool(blocker_present_at_transition[0]) \
		.override_failure_message("AC-MNU-22: release_enable_request must run BEFORE _main_menu_handler — blocker still present at seam entry") \
		.is_false()


func test_ac_mnu_23_quit_button_releases_blocker_before_quit() -> void:
	# AC-MNU-23 : QuitButton.pressed → release_enable_request AVANT _quit_handler.
	_pause = _spawn()
	await get_tree().process_frame
	_enter_paused_state()

	InputManager.request_disable(_pause)

	var blocker_at_quit: Array[bool] = [true]
	var quit_count: Array[int] = [0]
	_pause._quit_handler = func() -> void:
		quit_count[0] += 1
		blocker_at_quit[0] = InputManager._enable_blockers.has(_pause.get_instance_id())

	_pause.quit_button.pressed.emit()

	assert_int(quit_count[0]) \
		.override_failure_message("AC-MNU-23: _quit_handler must fire exactly 1×") \
		.is_equal(1)
	assert_bool(blocker_at_quit[0]) \
		.override_failure_message("AC-MNU-23: release_enable_request must run BEFORE _quit_handler — blocker still present at quit") \
		.is_false()


func test_ac_mnu_24_resume_double_click_idempotent_single_state_transition() -> void:
	# AC-MNU-24 : 2× resume_button.pressed → 2 calls effectifs à request_resume,
	# mais GSM idempotence absorbe le 2e (guard `if _current_state != PAUSED`).
	# Observable : 1 seul state_changed(PLAYING) émis.
	_pause = _spawn()
	await get_tree().process_frame

	GameStateManager._current_state = GameStateManager.State.PLAYING
	GameStateManager.request_pause()
	await get_tree().process_frame

	var state_changes: Array[int] = []
	var spy: Callable = func(new_state: int) -> void:
		state_changes.append(new_state)
	GameStateManager.state_changed.connect(spy)

	_pause.resume_button.pressed.emit()
	_pause.resume_button.pressed.emit()  # 2e click même frame.
	await get_tree().process_frame

	GameStateManager.state_changed.disconnect(spy)

	assert_array(state_changes) \
		.override_failure_message("AC-MNU-24: state_changed must emit PLAYING exactly 1× despite double-click — got %s" % str(state_changes)) \
		.is_equal([GameStateManager.State.PLAYING])
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-24: final state must be PLAYING") \
		.is_equal(GameStateManager.State.PLAYING)


func test_ac_mnu_25_scene_transition_paused_to_menu_via_gsm() -> void:
	# AC-MNU-25 : ADR-0007 matrice ; request_scene_transition depuis PAUSED → MENU.
	# On exerce le verbe GSM directement (pas de change_scene_to_file effectif —
	# on intercepte le verbe avant qu'il ne touche get_tree().change_scene_to_file
	# en stoppant l'observation après l'émission de state_changed).
	GameStateManager._current_state = GameStateManager.State.PAUSED
	get_tree().paused = true

	var states_seen: Array[int] = []
	var spy: Callable = func(new_state: int) -> void:
		states_seen.append(new_state)
	GameStateManager.state_changed.connect(spy)

	# request_scene_transition libère paused puis _transition_to(MENU) émet state_changed
	# AVANT change_scene_to_file (lecture src/core/game_state_manager.gd:79-86).
	# Note : change_scene_to_file est queued (Godot defer-loads), donc safe en test
	# tant que la cleanup after_test restaure l'état.
	GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")

	GameStateManager.state_changed.disconnect(spy)

	assert_array(states_seen) \
		.override_failure_message("AC-MNU-25: state_changed must emit MENU after request_scene_transition — got %s" % str(states_seen)) \
		.is_equal([GameStateManager.State.MENU])
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-25: GSM state must be MENU after transition") \
		.is_equal(GameStateManager.State.MENU)
	assert_bool(get_tree().paused) \
		.override_failure_message("AC-MNU-25: get_tree().paused must be false after MENU transition") \
		.is_false()


func test_ac_mnu_32_release_strict_order_no_mouse_recapture_on_main_menu() -> void:
	# AC-MNU-32 : transition PAUSED → MENU séquence exacte —
	#   (1) `_apply_visibility(false, recapture_mouse=false)` : pas de mouse recapture ;
	#   (2) `release_enable_request(self)` strictement avant `_main_menu_handler.call()`.
	# La preuve "recapture_mouse=false honoré" est implicite : `_apply_visibility` actuel
	# (story-005) ignore le paramètre, donc set_mouse_captured n'est jamais appelé depuis
	# Menu (story-008 livrera l'extension). Vérification : Input.mouse_mode inchangé.
	_pause = _spawn()
	await get_tree().process_frame
	_enter_paused_state()

	InputManager.request_disable(_pause)

	# Snapshot mouse_mode AVANT click pour vérifier non-mutation côté Menu.
	var mouse_mode_before: int = Input.mouse_mode

	var blocker_at_seam: Array[bool] = [true]
	_pause._main_menu_handler = func() -> void:
		blocker_at_seam[0] = InputManager._enable_blockers.has(_pause.get_instance_id())

	_pause.main_menu_button.pressed.emit()

	assert_bool(blocker_at_seam[0]) \
		.override_failure_message("AC-MNU-32: blocker must be released BEFORE transition seam fires") \
		.is_false()
	assert_int(Input.mouse_mode) \
		.override_failure_message("AC-MNU-32: Menu must NOT call set_mouse_captured(true) on MainMenu transition — mouse_mode mutated from %d to %d" % [mouse_mode_before, Input.mouse_mode]) \
		.is_equal(mouse_mode_before)
