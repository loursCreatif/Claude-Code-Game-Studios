extends GutTest

## AC-MNU-1/2/3 — Main Menu boot lifecycle integration.
##
## Couvre :
##   AC-MNU-1 : GSM.get_current_state() == MENU au boot
##   AC-MNU-2 : StartButton.has_focus() == true après _ready + 1 frame
##   AC-MNU-3 : aucun emit state_changed depuis Menu au boot (pull pattern ADR-0007 D-9)

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/menus/main_menu.tscn")

var _menu: Control


func before_each() -> void:
	_menu = MAIN_MENU_SCENE.instantiate()
	add_child_autofree(_menu)


func test_boot_state_is_menu() -> void:
	# AC-MNU-1 — GSM doit reporter MENU avant et après la frame de _ready.
	await get_tree().process_frame
	assert_eq(
		GameStateManager.get_current_state(),
		GameStateManager.State.MENU,
		"GSM should report MENU state at boot"
	)


func test_start_button_has_focus_after_ready() -> void:
	# AC-MNU-2 — StartButton.grab_focus() appelé 1× dans _ready.
	await get_tree().process_frame
	var start_btn: Button = _menu.get_node("VBoxContainer/StartButton")
	assert_true(
		start_btn.has_focus(),
		"StartButton should have focus exactly 1× after _ready + 1 frame"
	)


func test_no_state_changed_emitted_at_boot() -> void:
	# AC-MNU-3 — Menu utilise pull pattern, jamais d'emit state_changed au boot.
	# watch_signals doit être positionné AVANT que le _ready de Menu s'exécute
	# pour capter un éventuel emit parasite. On free le _menu issu de before_each
	# et on instancie après watch_signals.
	if is_instance_valid(_menu):
		_menu.queue_free()
		await get_tree().process_frame

	watch_signals(GameStateManager)
	var fresh_menu: Control = MAIN_MENU_SCENE.instantiate()
	add_child_autofree(fresh_menu)
	await get_tree().process_frame

	assert_signal_not_emitted(
		GameStateManager,
		"state_changed",
		"Menu must NOT emit state_changed at boot — GSM owns the signal (ADR-0007 D-10)"
	)
