# Unit tests for Story 003 — InputManager mouse capture API.
# Covers AC-MC-1 (capture true), AC-MC-2 (capture false), AC-MC-3 (read-through).
# Framework: GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

const InputManagerScript: GDScript = preload("res://src/core/input_manager.gd")

var _manager: Node = null
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_test() -> void:
	# Sauvegarder le mode courant pour restauration (Input.mouse_mode est global Godot).
	_saved_mouse_mode = Input.mouse_mode
	_manager = InputManagerScript.new() as Node
	add_child(_manager)
	await get_tree().process_frame


func after_test() -> void:
	_manager.queue_free()
	_manager = null
	# Restaurer le mode pour ne pas fuiter entre tests.
	Input.mouse_mode = _saved_mouse_mode


# ---------------------------------------------------------------------------
# AC-MC-1 — set_mouse_captured(true) → MOUSE_MODE_CAPTURED + is_mouse_captured() true
# ---------------------------------------------------------------------------

func test_set_mouse_captured_true_locks_cursor() -> void:
	# Arrange — partir d'un état visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Act
	_manager.set_mouse_captured(true)

	# Assert
	assert_int(Input.mouse_mode) \
		.override_failure_message(
			"Input.mouse_mode must be MOUSE_MODE_CAPTURED — got %d" % Input.mouse_mode
		) \
		.is_equal(Input.MOUSE_MODE_CAPTURED)
	assert_bool(_manager.is_mouse_captured()) \
		.override_failure_message("is_mouse_captured() must return true after set(true)") \
		.is_true()


# ---------------------------------------------------------------------------
# AC-MC-2 — set_mouse_captured(false) → MOUSE_MODE_VISIBLE + is_mouse_captured() false
# ---------------------------------------------------------------------------

func test_set_mouse_captured_false_releases_cursor() -> void:
	# Arrange — partir d'un état capturé
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Act
	_manager.set_mouse_captured(false)

	# Assert
	assert_int(Input.mouse_mode) \
		.override_failure_message(
			"Input.mouse_mode must be MOUSE_MODE_VISIBLE — got %d" % Input.mouse_mode
		) \
		.is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_bool(_manager.is_mouse_captured()) \
		.override_failure_message("is_mouse_captured() must return false after set(false)") \
		.is_false()


# ---------------------------------------------------------------------------
# AC-MC-3 — read-through (pas de cache) sur Input.mouse_mode externe
# ---------------------------------------------------------------------------

func test_is_mouse_captured_reflects_external_mode_change() -> void:
	# Arrange — capturer via le manager
	_manager.set_mouse_captured(true)
	assert_bool(_manager.is_mouse_captured()).is_true()

	# Act — code externe modifie Input.mouse_mode (plugin debug, etc.)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Assert — read-through, pas de cache
	assert_bool(_manager.is_mouse_captured()) \
		.override_failure_message(
			"is_mouse_captured() must read through to current Input.mouse_mode (no cache)"
		) \
		.is_false()


func test_set_mouse_captured_toggle_sequence_idempotent() -> void:
	# Arrange / Act — toggle plusieurs fois, vérifier état stable à chaque palier
	_manager.set_mouse_captured(true)
	assert_bool(_manager.is_mouse_captured()).is_true()

	_manager.set_mouse_captured(true)  # idempotent
	assert_bool(_manager.is_mouse_captured()).is_true()

	_manager.set_mouse_captured(false)
	assert_bool(_manager.is_mouse_captured()).is_false()

	_manager.set_mouse_captured(false)  # idempotent
	assert_bool(_manager.is_mouse_captured()).is_false()
