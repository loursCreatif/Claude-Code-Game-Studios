# Tests unitaires Story-002 — API play_3d_at (world space + is_finite assert).
#
# Couvre AC story-002 §`play_3d_at` : world space contract Phase D.1, is_finite()
# fallback play_2d, pitch_scale, return idx slot 3D.
#
# Framework : GdUnit4 v5.
# Story : production/epics/audio-system/story-002-api-verbes-play-duck-paused.md
# ADR   : ADR-0009 D-2 + Phase D.1 (world space contract)

extends GdUnitTestSuite


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


func before_test() -> void:
	_get_audio_system()._3d_index = 0


# ---------------------------------------------------------------------------
# play_3d_at world space contract (Phase D.1)
# ---------------------------------------------------------------------------

func test_play_3d_at_sets_global_position_to_world_pos() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var world_pos: Vector3 = Vector3(10.0, 5.0, -3.0)

	# Act
	var idx: int = audio.play_3d_at(stream, world_pos, &"combat_kill")

	# Assert
	assert_int(idx).is_equal(0)
	var slot: AudioStreamPlayer3D = audio._3d_pool[0]
	assert_vector(slot.global_position).is_equal(world_pos)
	assert_str(String(slot.bus)).is_equal("combat_kill")


func test_play_3d_at_returns_slot_index_then_advances() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()

	# Act
	var idx0: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill")
	var idx1: int = audio.play_3d_at(stream, Vector3.ONE, &"combat_kill")

	# Assert
	assert_int(idx0).is_equal(0)
	assert_int(idx1).is_equal(1)


func test_play_3d_at_pitch_scale_applied() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()

	# Act
	audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.5)

	# Assert
	var slot: AudioStreamPlayer3D = audio._3d_pool[0]
	assert_float(slot.pitch_scale).is_equal_approx(1.5, 0.001)


# ---------------------------------------------------------------------------
# is_finite() fallback (Phase D.1 defensive)
# ---------------------------------------------------------------------------

func test_play_3d_at_nan_falls_back_to_play_2d() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var nan_pos: Vector3 = Vector3(NAN, NAN, NAN)
	var index_3d_before: int = audio._3d_index
	var index_2d_before: int = audio._2d_index

	# Act
	var idx: int = audio.play_3d_at(stream, nan_pos, &"combat_kill")

	# Assert — return -1 (fallback signaled), 3D index UNCHANGED, 2D index advanced
	assert_int(idx).is_equal(-1)
	assert_int(audio._3d_index).is_equal(index_3d_before)
	assert_int(audio._2d_index).is_equal((index_2d_before + 1) % 5)


func test_play_3d_at_inf_falls_back_to_play_2d() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var inf_pos: Vector3 = Vector3(INF, 0.0, 0.0)

	# Act
	var idx: int = audio.play_3d_at(stream, inf_pos, &"combat_kill")

	# Assert — fallback signaled
	assert_int(idx).is_equal(-1)


# ---------------------------------------------------------------------------
# Null guards
# ---------------------------------------------------------------------------

func test_play_3d_at_null_stream_returns_negative_one() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act
	var idx: int = audio.play_3d_at(null, Vector3.ZERO, &"combat_kill")

	# Assert
	assert_int(idx).is_equal(-1)
