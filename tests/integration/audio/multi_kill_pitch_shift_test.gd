# Tests integration Story-003 — Multi-kill clac pitch-shift rangs +0/+2/+4 cap
# + counter reset AC-AUD-17.
#
# Couvre AC-AUD-05 (rangs pitch ≈ 1.0 / 1.122 / 1.260 / 1.260 cap)
# + AC-AUD-17 (counter reset swing_started/swing_ended — pas carry-over bug).
#
# Story : production/epics/audio-system/story-003-combat-handlers-swing-multikill-ducking-boundary.md
# ADR   : ADR-0009 D-3 (R-AUD-13 multi-kill counter owned Audio)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const POOL_3D_SIZE: int = 12


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


func _last_3d_slot_idx(audio: Node) -> int:
	# play_3d_at avance _3d_index post-play ; le slot utilisé est (current - 1) mod size
	return (audio._3d_index - 1 + POOL_3D_SIZE) % POOL_3D_SIZE


func before_test() -> void:
	var audio: Node = _get_audio_system()
	audio._kill_count_this_swing = 0
	audio._3d_index = 0
	audio._2d_index = 0
	audio._swoosh_fade_active = false
	audio._ducking_release_active = false
	audio._blood_pending_count = 0
	for i: int in range(audio.BLOOD_QUEUE_SIZE):
		audio._blood_pending_msec[i] = -1.0
	audio._active_clac_players.clear()
	audio.clac_stream = _make_stream()
	audio.swoosh_stream = null  # éviter pollution slot 2D
	audio.blood_stream = null   # éviter scheduling parasite
	audio._get_time_msec = Time.get_ticks_msec
	# Reset bus swing_active à NOMINAL
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	AudioServer.set_bus_volume_db(swing_idx, -6.0)


# ---------------------------------------------------------------------------
# AC-AUD-05 — rangs pitch +0 / +2 / +4 cap
# ---------------------------------------------------------------------------

func test_multi_kill_pitch_rang_0_first_kill_unity() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act — 1er kill du swing
	audio._on_enemy_killed(null, Vector3(1.0, 0.0, 0.0))

	# Assert — rang 0 → pitch_scale = 2^(0/12) = 1.0
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_float(slot.pitch_scale).is_equal_approx(1.0, 0.001)
	assert_int(audio._kill_count_this_swing).is_equal(1)


func test_multi_kill_pitch_rang_1_second_kill_plus_2_semitones() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Act — 2e kill
	audio._on_enemy_killed(null, Vector3(2.0, 0.0, 0.0))

	# Assert — rang 1 → pitch_scale = 2^(2/12) ≈ 1.122
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_float(slot.pitch_scale).is_equal_approx(1.122462, 0.005)
	assert_int(audio._kill_count_this_swing).is_equal(2)


func test_multi_kill_pitch_rang_2_third_kill_plus_4_semitones() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Act — 3e kill
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — rang 2 → pitch_scale = 2^(4/12) ≈ 1.260
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_float(slot.pitch_scale).is_equal_approx(1.259921, 0.01)
	assert_int(audio._kill_count_this_swing).is_equal(3)


func test_multi_kill_pitch_cap_4th_kill_no_carry_over_plus_6() -> void:
	# Arrange — 3 kills déjà, puis pathologique 4e (au-delà MAX_KILLS_PER_SWING Combat=3)
	var audio: Node = _get_audio_system()
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Act — 4e kill (cap rank 2, pas rank 3 = +6)
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — pitch_scale CAP à 2^(4/12) ≈ 1.260, PAS 2^(6/12) ≈ 1.414
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_float(slot.pitch_scale).is_equal_approx(1.259921, 0.01)
	# Verify NOT +6 semitones bug
	assert_float(slot.pitch_scale).is_less(1.35)
	assert_int(audio._kill_count_this_swing).is_equal(4)


# ---------------------------------------------------------------------------
# AC-AUD-17 — counter reset swing_started / swing_ended
# ---------------------------------------------------------------------------

func test_counter_reset_on_swing_ended() -> void:
	# Arrange — 3 kills accumulés
	var audio: Node = _get_audio_system()
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)
	assert_int(audio._kill_count_this_swing).is_equal(3)

	# Act
	audio._on_swing_ended()

	# Assert — counter reset
	assert_int(audio._kill_count_this_swing).is_equal(0)


func test_counter_reset_on_swing_started_no_carry_over() -> void:
	# Arrange — séquence reproduisant bug carry-over potentiel
	var audio: Node = _get_audio_system()
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_swing_ended()
	audio._on_swing_started()
	assert_int(audio._kill_count_this_swing).is_equal(0)

	# Act — premier kill du nouveau swing
	audio._on_enemy_killed(null, Vector3(5.0, 0.0, 0.0))

	# Assert — pitch = 1.0 (rang 0, PAS carry-over rang 3 = +6)
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_float(slot.pitch_scale).is_equal_approx(1.0, 0.001)
	assert_int(audio._kill_count_this_swing).is_equal(1)


# ---------------------------------------------------------------------------
# Phase D.3 — _active_clac_players tracker (story-007 dependency)
# ---------------------------------------------------------------------------

func test_active_clac_players_tracker_populated_on_kill() -> void:
	# Arrange
	var audio: Node = _get_audio_system()

	# Act
	audio._on_enemy_killed(null, Vector3.ZERO)
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — 2 slots tracked
	assert_int(audio._active_clac_players.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Position payload — capture au tick d'émission (R-AUD-7)
# ---------------------------------------------------------------------------

func test_clac_played_at_world_position_per_payload() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var pos: Vector3 = Vector3(10.0, 5.0, -3.0)

	# Act
	audio._on_enemy_killed(null, pos)

	# Assert — slot 3D positionné en world space (Phase D.1 contract)
	var slot: AudioStreamPlayer3D = audio._3d_pool[_last_3d_slot_idx(audio)]
	assert_vector(slot.global_position).is_equal(pos)
