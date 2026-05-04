# Tests integration Story-003 — Swoosh fade-out wall-clock + boundary D≤0.
#
# Couvre AC-AUD-04 (fade Formula 1 indépendant time_scale, 30 ms wall-clock)
# + boundary D=0.0 / D=-1.0 (short-circuit SILENCE_DB immédiat).
#
# Pattern wall-clock injection via `_get_time_msec: Callable` (ADR-0006 D-5).
# Lambda capture-by-value gotcha : Array wrapper `[idx]` pour mutation référence.
#
# Story : production/epics/audio-system/story-003-combat-handlers-swing-multikill-ducking-boundary.md
# ADR   : ADR-0009 D-3 (Combat handlers) + Phase D.3 wall-clock fade
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const SWING_ACTIVE_NOMINAL_DB: float = -6.0
const SILENCE_DB: float = -80.0


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func before_test() -> void:
	var audio: Node = _get_audio_system()
	audio._swoosh_fade_active = false
	audio._kill_count_this_swing = 0
	audio.swoosh_fade_duration_ms = 30.0
	audio._get_time_msec = Time.get_ticks_msec
	# Reset bus swing_active volume à NOMINAL
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	AudioServer.set_bus_volume_db(swing_idx, SWING_ACTIVE_NOMINAL_DB)


# ---------------------------------------------------------------------------
# AC-AUD-04 — wall-clock fade Formula 1 (linear dB lerp NOMINAL → SILENCE)
# ---------------------------------------------------------------------------

func test_swoosh_fade_starts_active_after_swing_ended() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var seq: Array = [1000]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v

	# Act
	audio._on_swing_ended()

	# Assert
	assert_bool(audio._swoosh_fade_active).is_true()
	assert_int(audio._swoosh_fade_start_msec).is_equal(1000)


func test_swoosh_fade_at_t_15ms_volume_db_approx_minus_43() -> void:
	# Arrange — séquence wall-clock [start=1000, tick=1015]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1015]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_swing_ended()  # consume seq[0] = 1000 → start

	# Act — tick at t=1015 (consume seq[1])
	audio._tick_swoosh_fade()

	# Assert — Formula 1 : lerp(-6, -80, 0.5) = -43 ± 2 dB
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(-43.0, 2.0)


func test_swoosh_fade_at_t_30ms_volume_db_below_minus_60() -> void:
	# Arrange — séquence [start=1000, tick=1030]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1030]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_swing_ended()

	# Act
	audio._tick_swoosh_fade()

	# Assert — t=1.0 → volume_db = SILENCE_DB ≤ -60 dB
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_less_equal(-60.0)
	assert_bool(audio._swoosh_fade_active).is_false()


func test_swoosh_fade_clamps_at_t_above_1_no_overshoot() -> void:
	# Arrange — tick à t=1050 (au-delà de 1030 = fade end)
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1050]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_swing_ended()

	# Act
	audio._tick_swoosh_fade()

	# Assert — clampf vise t=1.0, vol = SILENCE_DB (pas plus bas)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var vol: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(vol).is_equal_approx(SILENCE_DB, 0.001)


# ---------------------------------------------------------------------------
# AC-AUD-04 boundary cases — D ≤ 0 short-circuit
# ---------------------------------------------------------------------------

func test_swoosh_fade_boundary_d_zero_immediate_silence() -> void:
	# Arrange — D = 0.0 (corruption save / fixture mal configuré)
	var audio: Node = _get_audio_system()
	audio.swoosh_fade_duration_ms = 0.0

	# Act
	audio._on_swing_ended()

	# Assert — bus à SILENCE_DB instantané, fade NON actif (short-circuit)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	assert_float(AudioServer.get_bus_volume_db(swing_idx)).is_equal_approx(SILENCE_DB, 0.001)
	assert_bool(audio._swoosh_fade_active).is_false()


func test_swoosh_fade_boundary_d_negative_immediate_silence() -> void:
	# Arrange — D = -1.0 (guard symétrique négatif)
	var audio: Node = _get_audio_system()
	audio.swoosh_fade_duration_ms = -1.0

	# Act
	audio._on_swing_ended()

	# Assert — comportement identique à D=0
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	assert_float(AudioServer.get_bus_volume_db(swing_idx)).is_equal_approx(SILENCE_DB, 0.001)
	assert_bool(audio._swoosh_fade_active).is_false()


# ---------------------------------------------------------------------------
# AC-AUD-04 wall-clock independence — fade NOT scaled by time_scale
# ---------------------------------------------------------------------------

func test_swoosh_fade_wall_clock_indep_engine_time_scale() -> void:
	# Arrange — Engine.time_scale slow-mo (0.3) ; séquence wall-clock STILL avance normalement
	var audio: Node = _get_audio_system()
	var prev_time_scale: float = Engine.time_scale
	Engine.time_scale = 0.3
	var seq: Array = [1000, 1030]  # 30 ms wall-clock — indépendant slow-mo
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_swing_ended()

	# Act
	audio._tick_swoosh_fade()

	# Assert — fade complet à 30 ms wall-clock (PAS 100 ms = 30/0.3 si Tween scaled)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	assert_float(AudioServer.get_bus_volume_db(swing_idx)).is_less_equal(-60.0)

	# Cleanup
	Engine.time_scale = prev_time_scale
