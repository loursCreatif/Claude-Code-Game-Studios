# Unit tests for Story 003 — InputManager mouse_motion signal republish.
# Covers AC-AG-4 (signal émis 1× par event, payload Vector2 brut).
# Framework: GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

const InputManagerScript: GDScript = preload("res://src/core/input_manager.gd")

var _manager: Node = null
var _received_deltas: Array[Vector2] = []


func before_test() -> void:
	_manager = InputManagerScript.new() as Node
	add_child(_manager)
	await get_tree().process_frame
	_received_deltas = []
	_manager.mouse_motion.connect(_on_mouse_motion)


func after_test() -> void:
	if _manager.mouse_motion.is_connected(_on_mouse_motion):
		_manager.mouse_motion.disconnect(_on_mouse_motion)
	_manager.queue_free()
	_manager = null
	_received_deltas = []


func _on_mouse_motion(delta: Vector2) -> void:
	_received_deltas.append(delta)


# ---------------------------------------------------------------------------
# AC-AG-4 — mouse_motion émis 1× pour un InputEventMouseMotion injecté
# ---------------------------------------------------------------------------

func test_mouse_motion_signal_emitted_once_with_relative_payload() -> void:
	# Arrange
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(10.0, 0.0)

	# Act — appeler directement _unhandled_input (pas de viewport en GdUnit headless)
	_manager._unhandled_input(ev)

	# Assert
	assert_int(_received_deltas.size()) \
		.override_failure_message(
			"mouse_motion must emit exactly once — got %d emissions" % _received_deltas.size()
		) \
		.is_equal(1)
	assert_bool(_received_deltas[0].is_equal_approx(Vector2(10.0, 0.0))) \
		.override_failure_message(
			"mouse_motion payload must be Vector2(10, 0) — got %s" % _received_deltas[0]
		) \
		.is_true()


func test_mouse_motion_signal_emitted_with_zero_delta() -> void:
	# Arrange — un event avec relative=Vector2.ZERO doit être republié sans filtre
	# (le consumer Camera applique sensitivity et clamp ; emit Vector2.ZERO inoffensif).
	# Documente le choix d'implémentation : pas de no-op early return sur delta nul.
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2.ZERO

	# Act
	_manager._unhandled_input(ev)

	# Assert
	assert_int(_received_deltas.size()) \
		.override_failure_message(
			"mouse_motion must emit even when delta is Vector2.ZERO (no-op consumer side)"
		) \
		.is_equal(1)
	assert_bool(_received_deltas[0].is_equal_approx(Vector2.ZERO)).is_true()


func test_mouse_motion_signal_emitted_with_negative_delta() -> void:
	# Arrange — flick gauche/haut
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(-50.0, -25.0)

	# Act
	_manager._unhandled_input(ev)

	# Assert
	assert_int(_received_deltas.size()).is_equal(1)
	assert_bool(_received_deltas[0].is_equal_approx(Vector2(-50.0, -25.0))).is_true()


func test_mouse_motion_signal_not_emitted_when_disabled() -> void:
	# Arrange — désactiver le manager (story-004 expose l'API refcount, ici set direct)
	_manager._enabled = false
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(100.0, 0.0)

	# Act
	_manager._unhandled_input(ev)

	# Assert
	assert_int(_received_deltas.size()) \
		.override_failure_message("mouse_motion must NOT emit when _enabled=false") \
		.is_equal(0)


func test_mouse_motion_signal_not_emitted_during_focus_burst_window() -> void:
	# Arrange — armer la fenêtre 50 ms post-FOCUS_IN (story-005 future logic)
	_manager._focus_regained_until_ticks_usec = Time.get_ticks_usec() + 1_000_000  # +1 s
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(10.0, 0.0)

	# Act
	_manager._unhandled_input(ev)

	# Assert
	assert_int(_received_deltas.size()) \
		.override_failure_message("mouse_motion must NOT emit during focus burst window") \
		.is_equal(0)


func test_mouse_motion_signal_does_not_trigger_action_polling() -> void:
	# Arrange — un MouseMotion ne doit pas déclencher _pressed_this_tick (return early)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.relative = Vector2(5.0, 5.0)

	# Act
	_manager._unhandled_input(ev)

	# Assert — toutes les actions MVP doivent rester false
	for a: StringName in _manager.ACTIONS_MVP:
		assert_bool(_manager._pressed_this_tick.get(a, false)) \
			.override_failure_message(
				"InputEventMouseMotion must not flip _pressed_this_tick[%s]" % a
			) \
			.is_false()
