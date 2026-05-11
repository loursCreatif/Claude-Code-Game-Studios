extends AutoloadResetTestSuite

## AC-MNU-1/2/3 — Main Menu boot lifecycle integration.
##
## Couvre :
##   AC-MNU-1 : GSM.get_current_state() == MENU au boot
##   AC-MNU-2 : StartButton.has_focus() == true après _ready + 1 frame
##   AC-MNU-3 : aucun emit state_changed depuis Menu au boot (pull pattern ADR-0007 D-9)
##
## Framework : GdUnit4 (extends GdUnitTestSuite). SYNC mode — signal spy manuel
## (pas de watch_signals/monitor API utilisable depuis SYNC GdUnit4).

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")

var _menu: Control


func before_test() -> void:
	# AutoloadResetTestSuite.before_test() snapshots GSM + Engine + AudioSystem + VFXSystem.
	# La suite remplace ensuite GSM à MENU (requis par MainMenuController._ready() assert).
	super.before_test()
	# Force GSM à MENU après snapshot — la restauration after_test() remettra la valeur
	# d'avant (qui peut être MENU ou autre selon l'ordre de run). Le snapshot est déjà pris.
	GameStateManager._current_state = GameStateManager.State.MENU

	_menu = MAIN_MENU_SCENE.instantiate()
	auto_free(_menu)
	add_child(_menu)


func test_main_menu_boot_state_is_menu() -> void:
	# AC-MNU-1 — GSM doit reporter MENU avant et après la frame de _ready.
	await get_tree().process_frame
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("GSM should report MENU state at boot") \
		.is_equal(GameStateManager.State.MENU)


func test_main_menu_start_button_has_focus_after_ready() -> void:
	# AC-MNU-2 — StartButton.grab_focus() appelé 1× dans _ready.
	await get_tree().process_frame
	var start_btn: Button = _menu.get_node("VBoxContainer/StartButton")
	assert_bool(start_btn.has_focus()) \
		.override_failure_message("StartButton should have focus exactly 1× after _ready + 1 frame") \
		.is_true()


func test_main_menu_no_state_changed_emitted_at_boot() -> void:
	# AC-MNU-3 — Menu utilise pull pattern, jamais d'emit state_changed au boot.
	# Spy manuel : compteur connecté AVANT que le _ready de Menu s'exécute pour
	# capter un éventuel emit parasite.
	if is_instance_valid(_menu):
		_menu.queue_free()
		await get_tree().process_frame

	var emit_count: Array[int] = [0]
	var spy: Callable = func(_new_state: int) -> void: emit_count[0] += 1
	GameStateManager.state_changed.connect(spy)

	var fresh_menu: Control = MAIN_MENU_SCENE.instantiate()
	auto_free(fresh_menu)
	add_child(fresh_menu)
	await get_tree().process_frame

	GameStateManager.state_changed.disconnect(spy)

	assert_int(emit_count[0]) \
		.override_failure_message("Menu must NOT emit state_changed at boot — GSM owns the signal (ADR-0007 D-10)") \
		.is_equal(0)
