# Unit test Story-009 — ESC = Continue (anti-friction Pillar 1).
# Couvre AC-SHP-26 (ESC déclenche transition) + AC-SHP-27 (LOADING guard).
# EC-SHP-12/13 (ESC pendant tweens) déférés à story-013 (tweens implementation).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare ShopController + Callable injection + InputEventAction.
extends GdUnitTestSuite

const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


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


class TransitionSpy:
	extends RefCounted
	var call_count: int = 0
	var captured_path: String = ""
	func capture(path: String) -> void:
		call_count += 1
		captured_path = path


# Helper — créer InputEventAction "ui_cancel" pressed.
func _make_ui_cancel_event() -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


# =============================================================================
# AC-SHP-26 — _unhandled_input ui_cancel post-ready → transition appelée
# =============================================================================

## GIVEN shop ACTIVE post-_ready, transition spy injected,
## WHEN _unhandled_input(InputEventAction ui_cancel pressed),
## THEN spy.call_count == 1 (même path que click).
func test_esc_equals_continue_triggers_transition_post_ready() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))
	# Sanity : _ready_completed = true post _ready
	assert_bool(s.get_ready_completed_for_test()).is_true()

	# Act — envoie ui_cancel via _unhandled_input
	var event: InputEventAction = _make_ui_cancel_event()
	s._unhandled_input(event)

	# Assert
	assert_int(spy.call_count) \
		.override_failure_message("AC-SHP-26: ESC post-ready doit appeler transition 1×, obtenu %d" % spy.call_count) \
		.is_equal(1)
	assert_str(spy.captured_path) \
		.override_failure_message("AC-SHP-26: captured_path doit être main_menu, obtenu '%s'" % spy.captured_path) \
		.is_equal("res://scenes/menus/main_menu.tscn")

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-27 — _unhandled_input ESC pendant LOADING (_ready_completed=false) → ignoré
# =============================================================================

## GIVEN shop LOADING (`_ready_completed = false` forcé),
## WHEN _unhandled_input ui_cancel,
## THEN transition pas appelée (LOADING guard).
func test_esc_during_loading_ignored() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))
	# Force LOADING state
	s.set_ready_completed_for_test(false)

	# Act
	var event: InputEventAction = _make_ui_cancel_event()
	s._unhandled_input(event)

	# Assert — transition pas appelée
	assert_int(spy.call_count) \
		.override_failure_message("AC-SHP-27: ESC pendant LOADING doit être ignoré, obtenu call_count=%d" % spy.call_count) \
		.is_equal(0)
	assert_bool(s.get_closing_for_test()) \
		.override_failure_message("AC-SHP-27: _closing doit rester false (handler skipped)") \
		.is_false()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# Non-cancel events ignorés — autres input events ne déclenchent pas transition
# =============================================================================

## GIVEN shop ACTIVE,
## WHEN _unhandled_input avec event != ui_cancel (ex. ui_accept),
## THEN transition pas appelée.
func test_esc_non_cancel_events_dont_trigger_transition() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))

	# Act — envoie ui_accept (Enter/Space) au lieu de ui_cancel
	var event: InputEventAction = InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	s._unhandled_input(event)

	# Assert
	assert_int(spy.call_count) \
		.override_failure_message("ui_accept ne doit PAS déclencher transition (handler scope ui_cancel uniquement)") \
		.is_equal(0)

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# ESC double-press — second event consumé par _closing guard (AC-SHP-26 + EC-SHP-18)
# =============================================================================

## GIVEN shop ACTIVE,
## WHEN ESC envoyé 2× consécutifs,
## THEN spy.call_count == 1 (2e bloqué par _closing flag, dérivé de _on_continue_pressed).
func test_esc_double_press_uses_closing_guard() -> void:
	# Arrange
	var s: Control = _make_shop()
	var spy: TransitionSpy = TransitionSpy.new()
	s.set_transition_callable_for_test(Callable(spy, "capture"))

	# Act — double ESC
	var event: InputEventAction = _make_ui_cancel_event()
	s._unhandled_input(event)
	s._unhandled_input(event)

	# Assert — guard EC-SHP-18 partagé via _on_continue_pressed
	assert_int(spy.call_count) \
		.override_failure_message("EC-SHP-18 partagé : double ESC doit appeler 1×, obtenu %d" % spy.call_count) \
		.is_equal(1)

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()
