# Tests unitaires Story-002 — null stream guards + bus inconnu guards.
#
# Couvre AC story-002 §`set_bus_volume_db_user` + `duck_bus` bus inconnu
# + `play_music`/`stop_music` null stream.
#
# Framework : GdUnit4 v5.

extends GdUnitTestSuite


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


# ---------------------------------------------------------------------------
# set_bus_volume_db_user — bus inconnu guard
# ---------------------------------------------------------------------------

func test_set_bus_volume_db_user_unknown_bus_no_op() -> void:
	# Arrange — capture volume bus Master AVANT pour vérifier non-mutation
	var audio: Node = _get_audio_system()
	var master_db_before: float = AudioServer.get_bus_volume_db(0)

	# Act — bus inconnu, doit push_warning + no-op
	audio.set_bus_volume_db_user(&"BUS_NEXISTE_PAS", -10.0)

	# Assert — Master inchangé (no side-effect cross-bus)
	var master_db_after: float = AudioServer.get_bus_volume_db(0)
	assert_float(master_db_after).is_equal_approx(master_db_before, 0.001)


func test_set_bus_volume_db_user_known_bus_applies_db() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var ui_idx: int = AudioServer.get_bus_index(&"UI")
	var ui_db_before: float = AudioServer.get_bus_volume_db(ui_idx)

	# Act
	audio.set_bus_volume_db_user(&"UI", -6.0)

	# Assert
	assert_float(AudioServer.get_bus_volume_db(ui_idx)).is_equal_approx(-6.0, 0.001)

	# Cleanup — restore (test isolation)
	AudioServer.set_bus_volume_db(ui_idx, ui_db_before)


# ---------------------------------------------------------------------------
# duck_bus — bus inconnu guard
# ---------------------------------------------------------------------------

func test_duck_bus_unknown_bus_no_op() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var master_db_before: float = AudioServer.get_bus_volume_db(0)

	# Act
	audio.duck_bus(&"BUS_FANTOME", -6.0, 100.0)

	# Assert — pas de mutation cross-bus
	assert_float(AudioServer.get_bus_volume_db(0)).is_equal_approx(master_db_before, 0.001)


func test_duck_bus_applies_delta_db_instantanement() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var ui_idx: int = AudioServer.get_bus_index(&"UI")
	var ui_db_before: float = AudioServer.get_bus_volume_db(ui_idx)

	# Act — delta -3 dB
	audio.duck_bus(&"UI", -3.0, 100.0)

	# Assert
	assert_float(AudioServer.get_bus_volume_db(ui_idx)).is_equal_approx(ui_db_before - 3.0, 0.001)

	# Cleanup
	AudioServer.set_bus_volume_db(ui_idx, ui_db_before)


# ---------------------------------------------------------------------------
# play_music / stop_music — null stream guards
# ---------------------------------------------------------------------------

func test_play_music_null_stream_no_crash() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act + Assert — pas de crash, push_error capturé interne
	audio.play_music(null)
	# Si on arrive ici sans crash, le guard a fonctionné
	assert_bool(true).is_true()


func test_stop_music_when_not_playing_no_crash() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	if audio._music_player.playing:
		audio._music_player.stop()

	# Act + Assert — stop sur player inactif = no-op safe
	audio.stop_music()
	assert_bool(audio._music_player.playing).is_false()
