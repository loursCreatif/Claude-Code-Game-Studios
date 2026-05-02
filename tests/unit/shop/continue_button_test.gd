# Unit test Story-008 — ContinueButton handler + GSM transition + EC-SHP-18 guard.
# Couvre AC-SHP-25 (request_scene_transition appelé) + EC-SHP-18 (double-press).
# AC-SHP-28 (button.disabled=false) déférée — scene-attach dependent.
# AC-SHP-53 (initial focus ContinueButton) déférée — scene-attach dependent.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare ShopController + Callable injection (no GSM scene change).
extends GdUnitTestSuite

const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")
const _MAIN_MENU_PATH: String = "res://scenes/menus/main_menu.tscn"


func before_test() -> void:
	SaveLoadSystem.save_string_array("owned_upgrades", [] as Array[StringName])
	SaveLoadSystem.save_int("total_credits", 0)
	CreditEconomy._hydrate_from_save()


func after_test() -> void:
	SaveLoadSystem.save_string_array("owned_upgrades", [] as Array[StringName])
	SaveLoadSystem.save_int("total_credits", 0)
	CreditEconomy._hydrate_from_save()


func _make_shop() -> Control:
	var s: Control = _ShopControllerScript.new()
	s._ready()
	return s


# Helper — capture transition calls via Callable injection (no real GSM call).
class TransitionSpy:
	extends RefCounted
	var call_count: int = 0
	var captured_path: String = ""
	func capture(path: String) -> void:
		call_count += 1
		captured_path = path


# =============================================================================
# AC-SHP-25 — click ContinueButton → request_scene_transition called once
# =============================================================================

## GIVEN shop ACTIVE + transition callable injected,
## WHEN _on_continue_pressed() invoked,
## THEN transition.call_count == 1, captured_path == main_menu.
func test_continue_button_handler_triggers_scene_transition_once() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))

	# Act
	s._on_continue_pressed()

	# Assert
	assert_int(spy.call_count) \
		.override_failure_message("AC-SHP-25: transition attendu 1 call, obtenu %d" % spy.call_count) \
		.is_equal(1)
	assert_str(spy.captured_path) \
		.override_failure_message("AC-SHP-25: captured_path attendu '%s', obtenu '%s'" % [_MAIN_MENU_PATH, spy.captured_path]) \
		.is_equal(_MAIN_MENU_PATH)

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# EC-SHP-18 — double-press ContinueButton : 2e appel ignoré via _closing flag
# =============================================================================

## GIVEN shop ACTIVE + transition spy,
## WHEN _on_continue_pressed() appelé 2× consécutifs,
## THEN spy.call_count == 1 (2e bloqué par _closing).
func test_continue_button_double_press_blocked_by_closing_flag() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))

	# Act — double-press
	s._on_continue_pressed()
	s._on_continue_pressed()

	# Assert
	assert_int(spy.call_count) \
		.override_failure_message("EC-SHP-18: double-press doit appeler 1× seulement, obtenu %d" % spy.call_count) \
		.is_equal(1)
	assert_bool(s.get_closing_for_test()) \
		.override_failure_message("EC-SHP-18: _closing flag doit être true post-press") \
		.is_true()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# Initial state — _closing flag false avant tout press
# =============================================================================

func test_continue_button_initial_closing_flag_false() -> void:
	var s: Control = _make_shop()
	assert_bool(s.get_closing_for_test()) \
		.override_failure_message("Initial state: _closing doit être false post-_ready()") \
		.is_false()
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# Path constant — main menu scene path commence par res:// (assert GSM)
# =============================================================================

func test_continue_button_main_menu_path_starts_with_res() -> void:
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))
	s._on_continue_pressed()

	# Path doit être res://... pour passer assert GSM.request_scene_transition
	assert_bool(spy.captured_path.begins_with("res://")) \
		.override_failure_message("captured_path doit begin_with 'res://', obtenu '%s'" % spy.captured_path) \
		.is_true()
	assert_bool(spy.captured_path.ends_with(".tscn")) \
		.override_failure_message("captured_path doit ends_with '.tscn', obtenu '%s'" % spy.captured_path) \
		.is_true()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# Reset closing flag — re-instanciation safe (ré-utilisation Shop scene)
# =============================================================================

func test_continue_button_reset_closing_allows_subsequent_press() -> void:
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))

	# 1er press → 1 call
	s._on_continue_pressed()
	assert_int(spy.call_count).is_equal(1)

	# Reset (simule scene re-load)
	s.reset_closing_for_test()
	assert_bool(s.get_closing_for_test()).is_false()

	# 2e press après reset → +1 call
	s._on_continue_pressed()
	assert_int(spy.call_count) \
		.override_failure_message("Post-reset, 2e press doit appeler transition (count=%d attendu 2)" % spy.call_count) \
		.is_equal(2)

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()
