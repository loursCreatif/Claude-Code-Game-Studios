extends GdUnitTestSuite

## AC-MNU-17/18/19/20 — boutons MainMenu Start Run + Quitter (story-006).
##
## Pattern : test seams Callable (`_start_handler`, `_quit_handler`) du
## `MainMenuControllerScript` overridés par spies pour isoler les callbacks
## sans déclencher `LevelSystem.load_etage(1)` (scenes/etages/etage_01.tscn
## inexistant Sprint A) ni `get_tree().quit()` (terminerait le runner).
##
## AC-MNU-18 (chain Menu → start_etage → level_active → PLAYING) testé via
## émission directe `LevelSystem.level_active(1, Vector3.ZERO)` après le call
## start_etage réel — validation de la connexion CONNECT_ONE_SHOT côté GSM.

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")

var _menu: Control
var _saved_gsm_state: int


func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state


func after_test() -> void:
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	# Cleanup connexion résiduelle GSM ↔ LevelSystem.level_active si laissée par un test
	# qui a exercé start_etage réel sans simuler level_active.
	for conn: Dictionary in LevelSystem.level_active.get_connections():
		var callable: Callable = conn["callable"]
		if callable.get_object() == GameStateManager:
			LevelSystem.level_active.disconnect(callable)
	await get_tree().process_frame


func _spawn() -> Control:
	GameStateManager._current_state = GameStateManager.State.MENU
	var menu: Control = MAIN_MENU_SCENE.instantiate()
	auto_free(menu)
	add_child(menu)
	return menu


func test_ac_mnu_17_start_button_invokes_start_handler_with_etage_1() -> void:
	# AC-MNU-17 : StartButton.pressed → _start_handler invoqué exactement 1× ;
	# l'implémentation default appellerait GSM.start_etage(MVP_START_ETAGE_ID=1).
	_menu = _spawn()
	await get_tree().process_frame

	var calls: Array[int] = []
	_menu._start_handler = func() -> void:
		# Le default appelle GSM.start_etage(MVP_START_ETAGE_ID) ; on enregistre la const.
		calls.append(_menu.MVP_START_ETAGE_ID)

	_menu.start_button.pressed.emit()

	assert_array(calls) \
		.override_failure_message("AC-MNU-17: _start_handler must fire exactly 1× with etage_id=1") \
		.is_equal([1])


func test_ac_mnu_18_start_chain_to_playing_via_level_active() -> void:
	# AC-MNU-18 : déclencher start_etage réel → simuler LevelSystem.level_active →
	# GSM doit transitionner vers PLAYING.
	_menu = _spawn()
	await get_tree().process_frame

	# On laisse le default _start_handler appeler GSM.start_etage(1) réellement.
	# GSM va connecter level_active CONNECT_ONE_SHOT à _on_level_active puis appeler
	# LevelSystem.load_etage(1) qui peut push_error si scenes/etages/etage_01.tscn
	# absent — on tolère, l'observable est la connexion + transition simulée.
	var state_changed_calls: Array[int] = []
	var spy: Callable = func(new_state: int) -> void:
		state_changed_calls.append(new_state)
	GameStateManager.state_changed.connect(spy)

	_menu.start_button.pressed.emit()

	# Vérifier que GSM a bien connecté level_active (preuve start_etage invoqué chain).
	var connected_to_gsm: bool = false
	for conn: Dictionary in LevelSystem.level_active.get_connections():
		if conn["callable"].get_object() == GameStateManager:
			connected_to_gsm = true
			break
	assert_bool(connected_to_gsm) \
		.override_failure_message("AC-MNU-18: GSM must connect to LevelSystem.level_active after start_etage") \
		.is_true()

	# Simuler level_active manuellement — déclenche GSM._on_level_active → MENU → PLAYING.
	LevelSystem.level_active.emit(1, Vector3.ZERO)
	await get_tree().process_frame

	GameStateManager.state_changed.disconnect(spy)

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-18: GSM should transition to PLAYING after level_active emission") \
		.is_equal(GameStateManager.State.PLAYING)
	assert_array(state_changed_calls) \
		.override_failure_message("AC-MNU-18: state_changed must emit PLAYING — got %s" % str(state_changed_calls)) \
		.is_equal([GameStateManager.State.PLAYING])


func test_ac_mnu_19_quit_button_invokes_quit_handler_exactly_once() -> void:
	# AC-MNU-19 : QuitButton.pressed → _quit_handler invoqué 1× (sans appeler vraiment quit()).
	_menu = _spawn()
	await get_tree().process_frame

	var quit_count: Array[int] = [0]
	_menu._quit_handler = func() -> void:
		quit_count[0] += 1

	_menu.quit_button.pressed.emit()

	assert_int(quit_count[0]) \
		.override_failure_message("AC-MNU-19: _quit_handler must fire exactly 1× on QuitButton.pressed") \
		.is_equal(1)


func test_ac_mnu_20_double_click_start_idempotent_no_crash() -> void:
	# AC-MNU-20 : 2× start_button.pressed → start_handler appelé 2× au sens du callback,
	# mais l'effet observable (connexion level_active à GSM) reste unique (GSM check
	# `if not is_connected: connect`). Pas de crash, état cohérent.
	_menu = _spawn()
	await get_tree().process_frame

	var spy_calls: Array[int] = []
	_menu._start_handler = func() -> void:
		spy_calls.append(_menu.MVP_START_ETAGE_ID)
		# On simule l'effet GSM.start_etage : connect level_active si pas déjà connecté.
		# Cohérent avec ADR-0007 D-7 idempotence par check is_connected.
		# (Test ne touche pas vraiment GSM/LevelSystem — pure observation seam.)

	_menu.start_button.pressed.emit()
	_menu.start_button.pressed.emit()

	# Le seam reflète "Menu sans guard custom" — Implementation Notes §4 :
	# 2 calls atteignent le handler. L'idempotence est côté GSM (pas testé ici car
	# seam intercept avant GSM). AC-MNU-20 littéral "1×" reposait sur GSM idempotence
	# qui fonctionne via is_connected check du verbe start_etage.
	assert_array(spy_calls) \
		.override_failure_message("AC-MNU-20: handler reached 2× as expected (Menu has no guard) — got %s" % str(spy_calls)) \
		.is_equal([1, 1])
	# Pas de crash — le test passe sans exception.


func test_ac_mnu_20_real_gsm_idempotent_double_click_single_connection() -> void:
	# AC-MNU-20 (vraie idempotence GSM) : avec _start_handler default, 2 clicks
	# laissent UNE seule connexion GSM ↔ LevelSystem.level_active (D-7 check is_connected).
	_menu = _spawn()
	await get_tree().process_frame

	# 2 clicks consécutifs même frame.
	_menu.start_button.pressed.emit()
	_menu.start_button.pressed.emit()

	# Compter les connexions du target GSM sur LevelSystem.level_active.
	var gsm_connections: int = 0
	for conn: Dictionary in LevelSystem.level_active.get_connections():
		if conn["callable"].get_object() == GameStateManager:
			gsm_connections += 1

	assert_int(gsm_connections) \
		.override_failure_message("AC-MNU-20: GSM must have exactly 1 connection to LevelSystem.level_active even after double-click — got %d" % gsm_connections) \
		.is_equal(1)
