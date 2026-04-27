# Integration tests for Story 001 — InputManager autoload bootstrap.
# Covers ACs 1-5, AC-DBG-1, and autoload-order check.
# Framework: GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

# InputMap is a Godot global singleton — actions registered during a test
# persist across the rest of the session. Cleanup debug_toggle after each
# test to guarantee isolation between idempotency and registration tests.
func after_test() -> void:
	if InputMap.has_action(&"debug_toggle"):
		InputMap.erase_action(&"debug_toggle")

# ---------------------------------------------------------------------------
# AC1 — Script exists and extends Node
# ---------------------------------------------------------------------------

func test_inputmanager_script_exists_and_extends_node() -> void:
	# Arrange / Act
	var script: GDScript = load("res://src/core/input_manager.gd") as GDScript

	# Assert
	assert_object(script).is_not_null()
	var instance: Node = script.new() as Node
	assert_object(instance).is_not_null()
	assert_bool(instance is Node).is_true()
	instance.free()

# ---------------------------------------------------------------------------
# AC3 — ACTIONS_MVP constant contains all required actions
# ---------------------------------------------------------------------------

func test_inputmanager_actions_mvp_contains_all_required_actions() -> void:
	# Arrange
	var required: Array[StringName] = [
		&"move_forward", &"move_back", &"move_left", &"move_right",
		&"jump", &"dash", &"attack", &"restart",
		&"ui_cancel", &"ui_confirm",
	]

	# Act — read the constant directly from the script class
	var actions: Array[StringName] = InputManager.ACTIONS_MVP

	# Assert — every required action must be present
	for action: StringName in required:
		assert_bool(action in actions) \
			.override_failure_message("ACTIONS_MVP missing required action: %s" % action) \
			.is_true()

# ---------------------------------------------------------------------------
# AC4 — every ACTIONS_MVP action has at least one binding in project.godot [input]
# ---------------------------------------------------------------------------

func test_inputmanager_all_mvp_actions_have_input_bindings() -> void:
	# Arrange — actions live on the global InputMap once project.godot is loaded
	var actions: Array[StringName] = InputManager.ACTIONS_MVP

	# Act / Assert — every MVP action must exist with at least one bound event
	for action: StringName in actions:
		assert_bool(InputMap.has_action(action)) \
			.override_failure_message("project.godot [input] is missing action: %s" % action) \
			.is_true()
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		assert_int(events.size()) \
			.override_failure_message("Action %s must have ≥ 1 binding in project.godot, got %d" % [action, events.size()]) \
			.is_greater_equal(1)

# ---------------------------------------------------------------------------
# AC5 — _pressed_this_tick and _consumed_this_tick pre-allocated at _ready()
# ---------------------------------------------------------------------------

func test_inputmanager_dicts_preallocated_after_ready() -> void:
	# Arrange — instantiate and add to scene tree to trigger _ready()
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	await get_tree().process_frame

	# Act
	var pressed_size: int = manager._pressed_this_tick.size()
	var consumed_size: int = manager._consumed_this_tick.size()
	var expected_size: int = InputManager.ACTIONS_MVP.size()

	# Assert — sizes match
	assert_int(pressed_size).is_equal(expected_size)
	assert_int(consumed_size).is_equal(expected_size)

	# Assert — all values are false
	for action: StringName in InputManager.ACTIONS_MVP:
		assert_bool(manager._pressed_this_tick[action]) \
			.override_failure_message("_pressed_this_tick[%s] should be false after _ready()" % action) \
			.is_false()
		assert_bool(manager._consumed_this_tick[action]) \
			.override_failure_message("_consumed_this_tick[%s] should be false after _ready()" % action) \
			.is_false()

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-DBG-1 — debug_toggle action present in debug, absent in release
# ---------------------------------------------------------------------------

func test_inputmanager_debug_toggle_registered_matches_build_type() -> void:
	# Arrange — ensure a fresh InputManager has run _ready()
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	await get_tree().process_frame

	# Act
	var is_registered: bool = InputMap.has_action(&"debug_toggle")
	var is_debug_build: bool = OS.has_feature("debug")

	# Assert — presence must match build type (AC-DBG-1)
	assert_bool(is_registered).is_equal(is_debug_build)

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-DBG-1 idempotency — double _ready() must not duplicate F3 binding
# ---------------------------------------------------------------------------

func test_inputmanager_debug_toggle_idempotent_on_double_ready() -> void:
	if not OS.has_feature("debug"):
		# Idempotency only relevant in debug builds — pass trivially in release
		assert_bool(true).is_true()
		return

	# Arrange — first instance
	var first: InputManagerScript = InputManagerScript.new()
	add_child(first)
	await get_tree().process_frame
	first.queue_free()
	await get_tree().process_frame

	# Act — second instance triggers _ready() again
	var second: InputManagerScript = InputManagerScript.new()
	add_child(second)
	await get_tree().process_frame

	# Assert — action exists, with exactly 1 event bound
	assert_bool(InputMap.has_action(&"debug_toggle")).is_true()
	var events: Array[InputEvent] = InputMap.action_get_events(&"debug_toggle")
	assert_int(events.size()) \
		.override_failure_message("debug_toggle must have exactly 1 event bound after double _ready()") \
		.is_equal(1)

	second.queue_free()

# ---------------------------------------------------------------------------
# AC7 — _unhandled_input ignores echo key events (smoke test)
# ---------------------------------------------------------------------------

func test_inputmanager_unhandled_input_does_not_crash_on_echo_key_event() -> void:
	# Arrange
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	await get_tree().process_frame

	# Act — inject an echo InputEventKey directly (story-002 polling not yet wired)
	var echo_event := InputEventKey.new()
	echo_event.physical_keycode = KEY_W
	echo_event.echo = true
	# Call directly to verify no crash and early-return contract holds
	manager._unhandled_input(echo_event)

	# Assert — _pressed_this_tick unchanged (echo must be ignored)
	assert_bool(manager._pressed_this_tick[&"move_forward"]) \
		.override_failure_message("Echo key event must not set _pressed_this_tick") \
		.is_false()

	manager.queue_free()

# ---------------------------------------------------------------------------
# Autoload order — InputManager must be FIRST in [autoload] section
# ---------------------------------------------------------------------------

func test_inputmanager_declared_first_in_project_godot_autoload() -> void:
	# Arrange
	var file: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Could not open res://project.godot — file missing?") \
		.is_not_null()

	# Act — scan for [autoload] section, find first non-empty line after it
	var in_autoload_section: bool = false
	var first_autoload_line: String = ""

	while not file.eof_reached():
		var raw_line: String = file.get_line()
		var line: String = raw_line.strip_edges()

		if line == "[autoload]":
			in_autoload_section = true
			continue

		if in_autoload_section:
			if line.begins_with("["):
				# Left the autoload section without finding an entry
				break
			if line.length() > 0:
				first_autoload_line = line
				break

	file.close()

	# Assert — first entry must be InputManager
	assert_str(first_autoload_line) \
		.override_failure_message(
			"First entry in [autoload] must start with 'InputManager=' — got: '%s'" % first_autoload_line
		) \
		.starts_with("InputManager=")
