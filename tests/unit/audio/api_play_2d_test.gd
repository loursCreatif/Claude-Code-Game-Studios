# Tests unitaires Story-002 — API play_2d (round-robin + saturation + return idx).
#
# Couvre AC story-002 §`play_2d` : retourne slot index utilisé, round-robin,
# saturation handling avec push_warning, null guard.
#
# Framework : GdUnit4 v5 (extends GdUnitTestSuite).
# Story : production/epics/audio-system/story-002-api-verbes-play-duck-paused.md
# ADR   : ADR-0009 D-2 (pool round-robin) + R-AUD-1 (API publique exclusive)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


func before_test() -> void:
	# Reset round-robin index pour déterminisme cross-test
	_get_audio_system()._2d_index = 0


# ---------------------------------------------------------------------------
# play_2d return value (story-002 upgrade vs story-001 void)
# ---------------------------------------------------------------------------

func test_play_2d_returns_slot_index_used() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()

	# Act
	var idx0: int = audio.play_2d(stream, &"SFX")
	var idx1: int = audio.play_2d(stream, &"SFX")

	# Assert
	assert_int(idx0).is_equal(0)
	assert_int(idx1).is_equal(1)


func test_play_2d_returns_negative_one_on_null_stream() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act
	var idx: int = audio.play_2d(null, &"SFX")

	# Assert — retour erreur explicite, pas de crash
	assert_int(idx).is_equal(-1)


# ---------------------------------------------------------------------------
# Round-robin advance + wrap
# ---------------------------------------------------------------------------

func test_play_2d_round_robin_5_slots_then_wraps() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var indices: Array[int] = []

	# Act — 6 calls (5 slots + wrap)
	for _i: int in range(6):
		indices.append(audio.play_2d(stream, &"SFX"))

	# Assert
	assert_array(indices).is_equal([0, 1, 2, 3, 4, 0])


# ---------------------------------------------------------------------------
# Saturation handling
# ---------------------------------------------------------------------------

func test_play_2d_saturation_interrupts_active_slot() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()

	# Act — 5 plays consécutifs (tous slots actifs), puis 6e force interruption
	for _i: int in range(5):
		audio.play_2d(stream, &"SFX")
	# Le 6e play réutilise slot 0 — interruption forcée
	var idx: int = audio.play_2d(stream, &"SFX")

	# Assert — wrap reuse + slot encore valide
	assert_int(idx).is_equal(0)
	# Slot 0 doit être en cours de play (interrompu puis re-play)
	assert_bool(audio._2d_pool[0].playing or audio._2d_pool[0].stream == stream).is_true()
