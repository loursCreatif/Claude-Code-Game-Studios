extends GdUnitTestSuite

## AC-MNU-61 — Tab cycle wrap inverse + forward + bornes N=0/1/3 (story-012).
##
## Couvre :
##   AC-MNU-61 [Logic — BLOCKING] : Pause Overlay visible (N=3) + ResumeButton focused ;
##     Shift+Tab → QuitButton.has_focus() (wrap inverse vers dernier).
##   AC-MNU-61 Forward wrap : QuitButton focused + Tab → ResumeButton.has_focus() (wrap last→first).
##   AC-MNU-61 N=1 : un seul bouton visible + Tab → focus inchangé (idempotent).
##   AC-MNU-61 N=0 : aucun bouton focusable + Tab → aucun crash (no-op gracieux).
##
## F-MNU-3 formule : next_index = (current + 1) mod N (Tab forward) ;
##   prev_index = (current - 1 + N) mod N (Shift+Tab inverse).
##
## Pattern : save/restore GSM state + Input.parse_input_event pour simuler Tab/Shift+Tab.
## Note : en headless, UI focus fonctionne via Godot's internal focus system même sans
## fenêtre affichée. grab_focus() est appelé dans _apply_visibility(true).

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


func _spawn_pause_layer() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


## Workaround story-011 InputManager bug (cycles répétés).
func _force_clean_input_blocker_connection(owner: Node) -> void:
	if not is_instance_valid(owner):
		return
	var conns: Array = owner.get_signal_connection_list(&"tree_exited")
	for conn in conns:
		var cb: Callable = conn["callable"] as Callable
		if cb.get_object() == InputManager:
			owner.tree_exited.disconnect(cb)


## Helper : émettre un InputEventKey Tab (avec ou sans Shift).
func _simulate_tab(shift: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.shift_pressed = shift
	ev.pressed = true
	Input.parse_input_event(ev)


## Helper : émettre Tab release (pour éviter l'état "pressed" résiduel).
func _simulate_tab_release(shift: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.shift_pressed = shift
	ev.pressed = false
	Input.parse_input_event(ev)


# =============================================================================
# AC-MNU-61 BLOCKING — Shift+Tab wrap inverse (N=3)
# =============================================================================

## GIVEN Pause Overlay visible (N=3 : Resume, MainMenu, Quit) + ResumeButton focused.
## WHEN Shift+Tab.
## THEN QuitButton.has_focus() (wrap vers dernier — index 2 = Quit, depuis index 0 = Resume).
func test_ac_mnu_61_shift_tab_from_first_wraps_to_last() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame  # Safety margin CONNECT_DEFERRED

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button

	assert_bool(resume_btn != null) \
		.override_failure_message("AC-MNU-61: ResumeButton must exist") \
		.is_true()
	assert_bool(quit_btn != null) \
		.override_failure_message("AC-MNU-61: QuitButton must exist") \
		.is_true()

	# _apply_visibility(true) appelle resume_button.grab_focus() — confirmer.
	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 setup: ResumeButton must have focus after pause (grab_focus in _apply_visibility)") \
		.is_true()

	# Act — Shift+Tab (wrap inverse : premier → dernier).
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	# Assert — QuitButton a le focus (wrap vers dernier).
	assert_bool(quit_btn.has_focus()) \
		.override_failure_message("AC-MNU-61: Shift+Tab from ResumeButton (first) must wrap to QuitButton (last) — F-MNU-3 inverse wrap") \
		.is_true()

	# Cleanup
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Tab forward wrap (N=3) : dernier → premier
# =============================================================================

## GIVEN Pause Overlay visible (N=3) + QuitButton focused.
## WHEN Tab.
## THEN ResumeButton.has_focus() (wrap last → first).
func test_ac_mnu_61_tab_from_last_wraps_to_first() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button
	var main_menu_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/MainMenuButton") as Button

	# Forcer focus sur QuitButton (dernier).
	quit_btn.grab_focus()
	await get_tree().process_frame

	assert_bool(quit_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 forward wrap setup: QuitButton must have focus before Tab") \
		.is_true()

	# Act — Tab forward (dernier → wrap → premier).
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	# Assert — ResumeButton a le focus (wrap first).
	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61: Tab from QuitButton (last) must wrap to ResumeButton (first) — F-MNU-3 forward wrap") \
		.is_true()

	# Cleanup
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Tab forward cycle complet N=3 (Resume → MainMenu → Quit → Resume)
# =============================================================================

## GIVEN Pause Overlay visible (N=3) + ResumeButton focused.
## WHEN Tab × 3 (cycle complet).
## THEN séquence focus : Resume → MainMenu → Quit → Resume.
func test_ac_mnu_61_tab_full_cycle_n3() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var main_menu_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/MainMenuButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 cycle setup: ResumeButton must have focus") \
		.is_true()

	# Tab 1 : Resume → MainMenu.
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	assert_bool(main_menu_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 cycle step 1: Tab from Resume must focus MainMenu") \
		.is_true()

	# Tab 2 : MainMenu → Quit.
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	assert_bool(quit_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 cycle step 2: Tab from MainMenu must focus Quit") \
		.is_true()

	# Tab 3 : Quit → wrap → Resume.
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 cycle step 3: Tab from Quit (last) must wrap to Resume (first)") \
		.is_true()

	# Cleanup
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Shift+Tab full inverse cycle N=3
# =============================================================================

## GIVEN ResumeButton focused.
## WHEN Shift+Tab × 3.
## THEN séquence : Quit → MainMenu → Resume (cycle inverse complet).
func test_ac_mnu_61_shift_tab_full_inverse_cycle_n3() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var main_menu_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/MainMenuButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 inverse cycle setup: ResumeButton must have focus") \
		.is_true()

	# Shift+Tab 1 : Resume → wrap → Quit.
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	assert_bool(quit_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 inverse cycle step 1: Shift+Tab from Resume must wrap to Quit") \
		.is_true()

	# Shift+Tab 2 : Quit → MainMenu.
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	assert_bool(main_menu_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 inverse cycle step 2: Shift+Tab from Quit must focus MainMenu") \
		.is_true()

	# Shift+Tab 3 : MainMenu → Resume.
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 inverse cycle step 3: Shift+Tab from MainMenu must focus Resume") \
		.is_true()

	# Cleanup
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Borne N=1 (un seul bouton visible = idempotent)
# =============================================================================

## GIVEN PausePanel avec 1 seul bouton focusable (les autres hidden).
## WHEN Tab / Shift+Tab.
## THEN focus reste sur le seul bouton (idempotent — F-MNU-3 N=1 mod 1 = 0).
func test_ac_mnu_61_single_button_tab_idempotent() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var main_menu_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/MainMenuButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button

	# Masquer MainMenu et Quit pour simuler N=1.
	main_menu_btn.visible = false
	quit_btn.visible = false
	resume_btn.grab_focus()
	await get_tree().process_frame

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 N=1 setup: ResumeButton must have focus") \
		.is_true()

	# Tab forward avec N=1 — doit rester sur ResumeButton.
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 N=1: Tab with single visible button must be idempotent (focus stays on ResumeButton)") \
		.is_true()

	# Shift+Tab inverse avec N=1 — idempotent aussi.
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	assert_bool(resume_btn.has_focus()) \
		.override_failure_message("AC-MNU-61 N=1: Shift+Tab with single visible button must be idempotent") \
		.is_true()

	# Cleanup
	main_menu_btn.visible = true
	quit_btn.visible = true
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Borne N=0 (aucun bouton focusable = no-op sans crash)
# =============================================================================

## GIVEN PausePanel avec tous les boutons masqués.
## WHEN Tab / Shift+Tab.
## THEN aucun crash (Godot Focus system gère gracefully zero-focusable).
func test_ac_mnu_61_no_buttons_tab_no_crash() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame

	var resume_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/ResumeButton") as Button
	var main_menu_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/MainMenuButton") as Button
	var quit_btn: Button = _pause_layer.get_node("PausePanel/VBoxContainer/QuitButton") as Button

	# Masquer tous les boutons (N=0 focusable).
	resume_btn.visible = false
	main_menu_btn.visible = false
	quit_btn.visible = false
	await get_tree().process_frame

	# Act — Tab sans bouton focusable. Godot focus system fait no-op.
	_simulate_tab(false)
	await get_tree().process_frame
	_simulate_tab_release(false)

	# Assert — aucun crash (test arrive ici = no crash), state GSM inchangé.
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-61 N=0: Tab with no focusable buttons must not crash or change GSM state") \
		.is_equal(GameStateManager.State.PAUSED)

	# Shift+Tab sans bouton focusable.
	_simulate_tab(true)
	await get_tree().process_frame
	_simulate_tab_release(true)

	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-MNU-61 N=0: Shift+Tab with no focusable buttons must not crash or change GSM state") \
		.is_equal(GameStateManager.State.PAUSED)

	# Cleanup
	resume_btn.visible = true
	main_menu_btn.visible = true
	quit_btn.visible = true
	GameStateManager.request_resume()
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-61 — Vérification buttons présents (3 boutons au total dans N=3 case)
# =============================================================================

## Confirmation structurelle : Pause Overlay contient exactement 3 boutons dans VBoxContainer.
func test_ac_mnu_61_pause_overlay_has_3_buttons() -> void:
	# Arrange
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	var vbox: VBoxContainer = _pause_layer.get_node("PausePanel/VBoxContainer") as VBoxContainer
	assert_bool(vbox != null) \
		.override_failure_message("AC-MNU-61: VBoxContainer must exist in PausePanel") \
		.is_true()

	var button_count: int = 0
	for child: Node in vbox.get_children():
		if child is Button:
			button_count += 1

	assert_int(button_count) \
		.override_failure_message("AC-MNU-61: Pause Overlay must have exactly 3 buttons (Resume, MainMenu, Quit) — got %d" % button_count) \
		.is_equal(3)
