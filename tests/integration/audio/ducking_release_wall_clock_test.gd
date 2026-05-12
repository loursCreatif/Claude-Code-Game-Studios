# Tests integration Story-003 — Ducking SWING_ACTIVE -6 dB instantané
# + release wall-clock 30 ms (Formula 2 perceptuel linear-amplitude lerp)
# + boundary R≤0 short-circuit NOMINAL.
#
# Couvre AC-AUD-06 (-12 dB instantané, release vers -6 dB nominal) +
# boundary R = 0.0 / R = -1.0 (restore instant).
#
# Formula 2 hardened (Phase C) :
#   start_amp = db_to_linear(NOMINAL + DELTA) = db_to_linear(-12) ≈ 0.2512
#   end_amp   = db_to_linear(NOMINAL)         = db_to_linear(-6)  ≈ 0.5012
#   t=0.5 → mid_amp ≈ 0.376 → linear_to_db ≈ -8.5 dB ± 1
#
# Story : production/epics/audio-system/story-003-combat-handlers-swing-multikill-ducking-boundary.md
# ADR   : ADR-0009 D-3 (R-AUD-12 ducking event-driven)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const SWING_ACTIVE_NOMINAL_DB: float = -6.0
const DUCKING_DELTA_DB: float = -6.0


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


func before_test() -> void:
	var audio: Node = _get_audio_system()
	audio._kill_count_this_swing = 0
	audio._3d_index = 0
	audio._2d_index = 0
	audio._ducking_release_active = false
	audio._swoosh_fade_active = false
	audio._blood_pending_count = 0
	for i: int in range(audio.BLOOD_QUEUE_SIZE):
		audio._blood_pending_msec[i] = -1.0
	audio._active_clac_players.clear()
	audio.clac_stream = _make_stream()
	audio.swoosh_stream = null
	audio.blood_stream = null
	audio._get_time_msec = Time.get_ticks_msec
	audio.ducking_release_ms = 30.0
	# Reset bus swing_active à NOMINAL
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	AudioServer.set_bus_volume_db(swing_idx, SWING_ACTIVE_NOMINAL_DB)


# ---------------------------------------------------------------------------
# AC-AUD-06 — ducking instantané -12 dB sur enemy_killed
# ---------------------------------------------------------------------------

func test_ducking_instantaneous_minus_12db_on_enemy_killed() -> void:
	# Arrange — séquence wall-clock [start=1000]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v

	# Act
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — bus directement à NOMINAL + DELTA = -12 dB instantané (1 frame)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(SWING_ACTIVE_NOMINAL_DB + DUCKING_DELTA_DB, 0.001)
	assert_bool(audio._ducking_release_active).is_true()


# ---------------------------------------------------------------------------
# AC-AUD-06 — release wall-clock 30 ms vers NOMINAL (Formula 2 perceptuel)
# ---------------------------------------------------------------------------

func test_ducking_release_at_t_15ms_perceptual_midpoint_minus_8_5_db() -> void:
	# Arrange — séquence [start=1000, tick=1015]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1015]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_enemy_killed(null, Vector3.ZERO)  # consume seq[0] = 1000 → start

	# Act — tick at t=1015 (consume seq[1])
	audio._tick_ducking_release()

	# Assert — Formula 2 perceptuel : mid_amp ≈ 0.376 → -8.5 dB ± 1
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(-8.5, 1.0)


func test_ducking_release_at_t_30ms_back_to_nominal() -> void:
	# Arrange — séquence [start=1000, tick=1030]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1030]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Act
	audio._tick_ducking_release()

	# Assert — retour à NOMINAL_DB = -6.0 dB, release inactif
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(SWING_ACTIVE_NOMINAL_DB, 0.001)
	assert_bool(audio._ducking_release_active).is_false()


# ---------------------------------------------------------------------------
# AC-AUD-06 boundary cases — R ≤ 0 short-circuit NOMINAL immédiat
# ---------------------------------------------------------------------------

func test_ducking_boundary_r_zero_immediate_restore_nominal() -> void:
	# Arrange — R = 0.0 (corruption save)
	var audio: Node = _get_audio_system()
	audio.ducking_release_ms = 0.0

	# Act
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — bus à NOMINAL_DB instantané, release NON actif
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	assert_float(AudioServer.get_bus_volume_db(swing_idx)).is_equal_approx(SWING_ACTIVE_NOMINAL_DB, 0.001)
	assert_bool(audio._ducking_release_active).is_false()


func test_ducking_boundary_r_negative_immediate_restore_nominal() -> void:
	# Arrange — R = -1.0 (guard symétrique négatif)
	var audio: Node = _get_audio_system()
	audio.ducking_release_ms = -1.0

	# Act
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	assert_float(AudioServer.get_bus_volume_db(swing_idx)).is_equal_approx(SWING_ACTIVE_NOMINAL_DB, 0.001)
	assert_bool(audio._ducking_release_active).is_false()


# ---------------------------------------------------------------------------
# Multi-kill rapides — restart from -12 (no accumulation)
# ---------------------------------------------------------------------------

func test_ducking_rapid_kills_restart_from_minus_12_no_accumulation() -> void:
	# Arrange — 1er kill, puis 2e quasi-immédiat (release pas terminée)
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1005, 1010]  # kill1, kill2, ... (mid-release)
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Act — 2e kill mid-release (tick 1005)
	audio._on_enemy_killed(null, Vector3.ZERO)

	# Assert — bus restart à -12 (PAS -18 = accumulation -6 + -6)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(-12.0, 0.001)
