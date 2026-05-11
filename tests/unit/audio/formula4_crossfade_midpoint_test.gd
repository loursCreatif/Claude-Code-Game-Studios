# Tests unit Story-005 — Formula 4 hardened Phase C linear-amplitude crossfade midpoint.
#
# Couvre AC-AUD-21 :
# - (a) Boot t=0 : volume_db_old ≈ 0 dB ± 0.1, volume_db_new ≤ -60 dB
# - (b) Midpoint t=500 : both ≈ -6 dB ± 1 (linear-amplitude lerp Phase C)
# - (c) Anti-regression : NOT ≈ -40 dB sur les deux (r2 dB-domain lerp bug)
# - (d) Fin t=1000 : old ≤ -60, new ≈ 0 dB ± 0.1
# - (e) Boundary D=0.0 : swap instantané + push_warning
# - Round-robin idx toggle 0↔1
# - Wall-clock indep Engine.time_scale (slow-mo 0.3)
#
# Pattern wall-clock injection via `_get_time_msec: Callable` (ADR-0006 D-5).
#
# Story : production/epics/audio-system/story-005-level-handler-crossfade-formula4-anti-dip-fallback.md
# ADR   : ADR-0009 D-2 + Formula 4 hardened Phase C
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const SILENCE_DB: float = -80.0
const CROSSFADE_DURATION_MS: float = 1000.0


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 44100
	s.stereo = false
	s.data = PackedByteArray()
	return s


func _make_time_callable(seq: Array) -> Callable:
	# Lambda capture-by-value Array wrapper [idx] pour mutation reference
	# (gotcha GDScript : capture int by-value, Array by-reference).
	var idx: Array = [0]
	return func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v


func before_test() -> void:
	Engine.time_scale = 1.0
	var audio: Node = _get_audio_system()
	audio._ambience_active_idx = 0
	audio._crossfade_active = false
	audio._crossfade_old_player = null
	audio._crossfade_new_player = null
	audio._crossfade_duration_ms = CROSSFADE_DURATION_MS
	audio._music_fade_out_active = false
	audio._get_time_msec = Time.get_ticks_msec
	for p: AudioStreamPlayer in audio._ambience_pool:
		if p.playing:
			p.stop()
		p.volume_db = 0.0
		p.stream = null


func after_test() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# AC-AUD-21 (a) — Boot t=0
# ---------------------------------------------------------------------------

func test_crossfade_t0_old_at_0db_new_silent() -> void:
	# Arrange — Ambience #1 joue stream A à 0 dB
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	var stream_b: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream_a
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()
	# Sequence : [start_msec=0, tick_now=0]
	audio._get_time_msec = _make_time_callable([0, 0])

	# Act
	audio._start_ambient_crossfade(stream_b, CROSSFADE_DURATION_MS)
	audio._tick_ambient_crossfade()

	# Assert AC-AUD-21 (a) : old ≈ 0 ± 0.1, new ≤ -60
	assert_float(audio._ambience_pool[0].volume_db).is_equal_approx(0.0, 0.1)
	assert_float(audio._ambience_pool[1].volume_db).is_less_equal(-60.0)


# ---------------------------------------------------------------------------
# AC-AUD-21 (b) — Midpoint t=500 linear-amplitude lerp Phase C
# ---------------------------------------------------------------------------

func test_crossfade_midpoint_t500_both_minus_6_db_phase_c() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	var stream_b: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream_a
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()
	audio._get_time_msec = _make_time_callable([0, 500])

	# Act
	audio._start_ambient_crossfade(stream_b, CROSSFADE_DURATION_MS)
	audio._tick_ambient_crossfade()

	# Assert AC-AUD-21 (b) : Phase C linear_to_db(0.5) ≈ -6.02 dB ± 1
	# ANTI-REGRESSION : si r2 dB-domain lerp utilisé → midpoint ≈ -40 (FAIL ici)
	assert_float(audio._ambience_pool[0].volume_db).is_equal_approx(-6.0, 1.0)
	assert_float(audio._ambience_pool[1].volume_db).is_equal_approx(-6.0, 1.0)


# ---------------------------------------------------------------------------
# AC-AUD-21 (c) — Anti-regression Phase C explicit guard
# ---------------------------------------------------------------------------

func test_crossfade_anti_regression_not_minus_40_db_dB_domain_bug() -> void:
	# r2 stale bug : dB-domain lerp(0, -80, 0.5) = -40 dB sur les deux → dip ~3 dB perceptuel.
	# Phase C linear-amplitude lerp → midpoint ≈ -6 dB (uniforme perceptuel).
	# Si ce test FAIL avec ≈ -40 → re-vérifier `linear_to_db(maxf(amp, 1e-4))` impl.
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	var stream_b: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream_a
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()
	audio._get_time_msec = _make_time_callable([0, 500])

	audio._start_ambient_crossfade(stream_b, CROSSFADE_DURATION_MS)
	audio._tick_ambient_crossfade()

	# Distance vs -40 dB ≥ 20 dB → guarantit qu'on n'est PAS sur dB-domain bug
	assert_float(absf(audio._ambience_pool[0].volume_db - (-40.0))).is_greater(20.0)
	assert_float(absf(audio._ambience_pool[1].volume_db - (-40.0))).is_greater(20.0)


# ---------------------------------------------------------------------------
# AC-AUD-21 (d) — Fin crossfade t=1000
# ---------------------------------------------------------------------------

func test_crossfade_end_t1000_old_stopped_new_at_0db() -> void:
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	var stream_b: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream_a
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()
	audio._get_time_msec = _make_time_callable([0, 1000])

	audio._start_ambient_crossfade(stream_b, CROSSFADE_DURATION_MS)
	audio._tick_ambient_crossfade()

	# AC-AUD-21 (d) : old stopped + restored, new ≈ 0 ± 0.1
	assert_bool(audio._ambience_pool[0].playing).is_false()
	assert_float(audio._ambience_pool[1].volume_db).is_equal_approx(0.0, 0.1)
	assert_bool(audio._crossfade_active).is_false()


# ---------------------------------------------------------------------------
# AC-AUD-21 (e) — Boundary D=0.0 swap instantané
# ---------------------------------------------------------------------------

func test_crossfade_boundary_d_zero_swap_instantane() -> void:
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	var stream_b: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream_a
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()

	audio._start_ambient_crossfade(stream_b, 0.0)

	# AC-AUD-21 (e) : old → SILENCE_DB + stop, new → 0 dB
	assert_float(audio._ambience_pool[0].volume_db).is_equal(SILENCE_DB)
	assert_float(audio._ambience_pool[1].volume_db).is_equal_approx(0.0, 0.1)
	assert_bool(audio._crossfade_active).is_false()
	assert_int(audio._ambience_active_idx).is_equal(1)


# ---------------------------------------------------------------------------
# Round-robin idx toggle 0↔1
# ---------------------------------------------------------------------------

func test_crossfade_idx_toggles_0_to_1_to_0() -> void:
	var audio: Node = _get_audio_system()
	audio._ambience_pool[0].stream = _make_stream()
	audio._ambience_pool[0].play()

	audio._start_ambient_crossfade(_make_stream(), 0.0)
	assert_int(audio._ambience_active_idx).is_equal(1)

	audio._start_ambient_crossfade(_make_stream(), 0.0)
	assert_int(audio._ambience_active_idx).is_equal(0)


# ---------------------------------------------------------------------------
# Wall-clock independence Engine.time_scale
# ---------------------------------------------------------------------------

func test_crossfade_wall_clock_indep_engine_time_scale() -> void:
	var audio: Node = _get_audio_system()
	var prev: float = Engine.time_scale
	Engine.time_scale = 0.3  # slow-mo
	audio._ambience_pool[0].stream = _make_stream()
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()
	audio._get_time_msec = _make_time_callable([0, 1000])

	audio._start_ambient_crossfade(_make_stream(), CROSSFADE_DURATION_MS)
	audio._tick_ambient_crossfade()

	# Fade complet à 1000 ms wall-clock (PAS 3333 ms si Tween scaled par time_scale)
	assert_bool(audio._crossfade_active).is_false()
	assert_float(audio._ambience_pool[1].volume_db).is_equal_approx(0.0, 0.1)

	Engine.time_scale = prev
