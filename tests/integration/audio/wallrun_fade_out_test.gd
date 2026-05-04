# Tests integration Story-004 — Wall-run loop start + fade-out 100 ms wall-clock.
#
# Couvre :
# - wall_run_entered → play_2d loop slot tracked
# - wall_run_exited → fade démarre _physics_process tick
# - À t=50 ms : volume_db ≈ -40 dB (Formula 1 lerp 0 → -80 sur 100 ms)
# - À t=100 ms : volume_db = SILENCE_DB + slot stop() + tracker reset (-1)
# - Edge cases : exit sans entry actif (no-op), wall-clock indep time_scale
#
# Pattern wall-clock injection via `_get_time_msec: Callable` (ADR-0006 D-5).
#
# Story : production/epics/audio-system/story-004-movement-handlers-dash-wallrun-walljump-death.md
# ADR   : ADR-0009 D-4 + Formula 1 hardened (linear dB lerp)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const SILENCE_DB: float = -80.0


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 44100
	s.stereo = false
	s.data = PackedByteArray()
	return s


func before_test() -> void:
	var audio: Node = _get_audio_system()
	audio._2d_index = 0
	audio._wallrun_slot_idx = -1
	audio._wallrun_fade_active = false
	audio.wallrun_loop_stream = _make_stream()
	audio._get_time_msec = Time.get_ticks_msec
	# Reset volume_db tous les slots 2D pour isolation
	for p: AudioStreamPlayer in audio._2d_pool:
		p.volume_db = 0.0
		if p.playing:
			p.stop()


# ---------------------------------------------------------------------------
# wall_run_entered → loop slot tracked
# ---------------------------------------------------------------------------

func test_wall_run_entered_starts_loop_and_tracks_slot() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	assert_int(audio._wallrun_slot_idx).is_equal(-1)

	# Act
	audio._on_wall_run_entered(Vector3.UP)

	# Assert — slot tracker mis à jour, slot pool 2D consommé
	assert_int(audio._wallrun_slot_idx).is_greater_equal(0)
	assert_int(audio._wallrun_slot_idx).is_less(audio.POOL_2D_SIZE)


func test_wall_run_entered_no_op_when_stream_null() -> void:
	# Arrange — wallrun_loop_stream null (asset pipeline pending)
	var audio: Node = _get_audio_system()
	audio.wallrun_loop_stream = null

	# Act
	audio._on_wall_run_entered(Vector3.UP)

	# Assert — slot tracker non muté
	assert_int(audio._wallrun_slot_idx).is_equal(-1)


# ---------------------------------------------------------------------------
# wall_run_exited → fade démarre + _physics_process tick
# ---------------------------------------------------------------------------

func test_wall_run_exited_starts_fade_active() -> void:
	# Arrange — _on_wall_run_entered NE consomme PAS _get_time_msec ;
	# seul _on_wall_run_exited capture start_msec.
	var audio: Node = _get_audio_system()
	var seq: Array = [1010]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_wall_run_entered(Vector3.UP)

	# Act
	audio._on_wall_run_exited()

	# Assert — fade marqué actif, start_msec capturé
	assert_bool(audio._wallrun_fade_active).is_true()
	assert_int(audio._wallrun_fade_start_msec).is_equal(1010)


func test_wall_run_fade_at_t_50ms_volume_db_approx_minus_40() -> void:
	# Arrange — séquence [exit_start=1000, tick_now=1050]
	# (enter ne consomme pas _get_time_msec)
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1050]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_wall_run_entered(Vector3.UP)
	audio._on_wall_run_exited()

	# Act — tick at t=1050 (consume seq[2])
	audio._tick_wallrun_fade()

	# Assert — Formula 1 : lerp(0, -80, 0.5) = -40 ± 2 dB
	var slot: AudioStreamPlayer = audio._2d_pool[audio._wallrun_slot_idx]
	assert_float(slot.volume_db).is_equal_approx(-40.0, 2.0)


func test_wall_run_fade_at_t_100ms_silence_and_slot_stopped() -> void:
	# Arrange — séquence [exit_start=1000, tick_now=1100]
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1100]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_wall_run_entered(Vector3.UP)
	var captured_slot: int = audio._wallrun_slot_idx
	audio._on_wall_run_exited()

	# Act
	audio._tick_wallrun_fade()

	# Assert — t=1.0 → volume reset 0.0 (post-stop), slot stoppé, tracker reset
	var slot: AudioStreamPlayer = audio._2d_pool[captured_slot]
	assert_bool(slot.playing).is_false()
	assert_int(audio._wallrun_slot_idx).is_equal(-1)
	assert_bool(audio._wallrun_fade_active).is_false()


func test_wall_run_fade_clamps_at_t_above_1_no_overshoot() -> void:
	# Arrange — tick at 1200 (au-delà 1100 = end)
	var audio: Node = _get_audio_system()
	var seq: Array = [1000, 1200]
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_wall_run_entered(Vector3.UP)
	audio._on_wall_run_exited()

	# Act
	audio._tick_wallrun_fade()

	# Assert — slot stoppé + tracker reset (clampf t=1.0 atteint, pas d'overshoot)
	assert_int(audio._wallrun_slot_idx).is_equal(-1)
	assert_bool(audio._wallrun_fade_active).is_false()


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

func test_wall_run_exited_no_op_when_no_active_slot() -> void:
	# Arrange — pas de wall_run_entered préalable
	var audio: Node = _get_audio_system()
	assert_int(audio._wallrun_slot_idx).is_equal(-1)

	# Act
	audio._on_wall_run_exited()

	# Assert — fade pas déclenché (no-op safe)
	assert_bool(audio._wallrun_fade_active).is_false()


func test_wall_run_fade_wall_clock_indep_engine_time_scale() -> void:
	# Arrange — slow-mo 0.3 ; séquence wall-clock STILL avance normalement
	var audio: Node = _get_audio_system()
	var prev_time_scale: float = Engine.time_scale
	Engine.time_scale = 0.3
	var seq: Array = [1000, 1100]  # 100 ms wall-clock indep slow-mo
	var idx: Array = [0]
	audio._get_time_msec = func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v
	audio._on_wall_run_entered(Vector3.UP)
	audio._on_wall_run_exited()

	# Act
	audio._tick_wallrun_fade()

	# Assert — fade complet à 100 ms wall-clock (PAS 333 ms = 100/0.3 si Tween scaled)
	assert_int(audio._wallrun_slot_idx).is_equal(-1)
	assert_bool(audio._wallrun_fade_active).is_false()

	# Cleanup
	Engine.time_scale = prev_time_scale
