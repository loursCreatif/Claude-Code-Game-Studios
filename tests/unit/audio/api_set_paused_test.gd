# Tests unitaires Story-002 — API set_paused (Master mute via API).
#
# Couvre AC story-002 §`set_paused` : AudioServer.set_bus_mute(0, paused).
# State preservation (_fade_pause_msec offset) → story-006 GSM handler.
#
# Framework : GdUnit4 v5.

extends GdUnitTestSuite


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func before_test() -> void:
	# Reset Master mute pour isolation
	AudioServer.set_bus_mute(0, false)


# ---------------------------------------------------------------------------
# set_paused → Master mute toggle
# ---------------------------------------------------------------------------

func test_set_paused_true_mutes_master() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	assert_bool(AudioServer.is_bus_mute(0)).is_false()  # baseline

	# Act
	audio.set_paused(true)

	# Assert
	assert_bool(AudioServer.is_bus_mute(0)).is_true()


func test_set_paused_false_unmutes_master() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	AudioServer.set_bus_mute(0, true)
	assert_bool(AudioServer.is_bus_mute(0)).is_true()  # baseline

	# Act
	audio.set_paused(false)

	# Assert
	assert_bool(AudioServer.is_bus_mute(0)).is_false()


func test_set_paused_idempotent_multiple_calls() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act — multiple toggles
	audio.set_paused(true)
	audio.set_paused(true)
	audio.set_paused(true)

	# Assert
	assert_bool(AudioServer.is_bus_mute(0)).is_true()

	# Reverse
	audio.set_paused(false)
	audio.set_paused(false)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()
