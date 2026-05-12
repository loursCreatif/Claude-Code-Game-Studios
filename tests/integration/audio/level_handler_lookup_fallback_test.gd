# Tests integration Story-005 — Level handler lookup + fallback + level_unloading.
#
# Couvre :
# - _on_level_active fallback mapping vide → push_warning + return early (pas crossfade)
# - _on_level_active mapping valide → play_music + crossfade ambient démarré
# - _on_level_active fallback préserve music précédente (pas de stop)
# - _on_level_unloading déclenche stop_music fade-out wall-clock 0.5 s
# - _on_level_unloading déclenche ambient fade-out only (new_player == null)
# - music_fade_out tick complete à t=full_duration (stop + restore volume)
# - connect_level_signals null guard
#
# Pattern injection :
# - `_get_etage_audio_streams: Callable` (substituable test, default empty fallback)
# - `_get_time_msec: Callable` (ADR-0006 D-5 wall-clock injection)
#
# Story : production/epics/audio-system/story-005-level-handler-crossfade-formula4-anti-dip-fallback.md
# ADR   : ADR-0009 D-2 + ADR-0011 (Level Scene Architecture r4 Option C)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const AMBIENT_UNLOAD_FADE_MS: float = 500.0


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
	var idx: Array = [0]
	return func() -> int:
		var v: int = seq[idx[0]]
		if idx[0] < seq.size() - 1:
			idx[0] += 1
		return v


func before_test() -> void:
	var audio: Node = _get_audio_system()
	audio._ambience_active_idx = 0
	audio._crossfade_active = false
	audio._crossfade_old_player = null
	audio._crossfade_new_player = null
	audio._music_fade_out_active = false
	audio._get_time_msec = Time.get_ticks_msec
	audio._get_etage_audio_streams = func(_id: int) -> Dictionary: return {}
	for p: AudioStreamPlayer in audio._ambience_pool:
		if p.playing:
			p.stop()
		p.volume_db = 0.0
		p.stream = null
	if audio._music_player.playing:
		audio._music_player.stop()
	audio._music_player.volume_db = 0.0
	audio._music_player.stream = null


# ---------------------------------------------------------------------------
# _on_level_active fallback mapping vide
# ---------------------------------------------------------------------------

func test_level_active_fallback_empty_mapping_no_crossfade_no_music() -> void:
	# Arrange — mapping vide explicit (default)
	var audio: Node = _get_audio_system()
	audio._get_etage_audio_streams = func(_id: int) -> Dictionary: return {}

	# Act
	audio._on_level_active(99, Vector3.ZERO)

	# Assert — push_warning + return early : aucun side effect audio
	assert_bool(audio._crossfade_active).is_false()
	assert_bool(audio._music_player.playing).is_false()


func test_level_active_fallback_keeps_previous_music_playing() -> void:
	# Music précédente continue (pas de stop) si nouveau etage a mapping vide.
	var audio: Node = _get_audio_system()
	var music_a: AudioStream = _make_stream()
	audio._music_player.stream = music_a
	audio._music_player.play()
	audio._get_etage_audio_streams = func(_id: int) -> Dictionary: return {}

	audio._on_level_active(99, Vector3.ZERO)

	assert_bool(audio._music_player.playing).is_true()
	assert_object(audio._music_player.stream).is_equal(music_a)


# ---------------------------------------------------------------------------
# _on_level_active mapping valide
# ---------------------------------------------------------------------------

func test_level_active_valid_mapping_starts_music_and_crossfade() -> void:
	var audio: Node = _get_audio_system()
	var music_s: AudioStream = _make_stream()
	var ambient_s: AudioStream = _make_stream()
	audio._get_etage_audio_streams = func(_id: int) -> Dictionary:
		return {&"music": music_s, &"ambient": ambient_s}

	audio._on_level_active(1, Vector3.ZERO)

	# Music play_music déclenché
	assert_bool(audio._music_player.playing).is_true()
	assert_object(audio._music_player.stream).is_equal(music_s)
	# Crossfade démarré sur Ambience pool
	assert_bool(audio._crossfade_active).is_true()
	assert_int(audio._ambience_active_idx).is_equal(1)
	assert_object(audio._ambience_pool[1].stream).is_equal(ambient_s)


func test_level_active_partial_mapping_music_only() -> void:
	# Mapping {music: X} sans ambient → play_music sans crossfade ambient
	var audio: Node = _get_audio_system()
	var music_s: AudioStream = _make_stream()
	audio._get_etage_audio_streams = func(_id: int) -> Dictionary:
		return {&"music": music_s}

	audio._on_level_active(1, Vector3.ZERO)

	assert_bool(audio._music_player.playing).is_true()
	assert_bool(audio._crossfade_active).is_false()


# ---------------------------------------------------------------------------
# _on_level_unloading
# ---------------------------------------------------------------------------

func test_level_unloading_starts_music_fade_out() -> void:
	var audio: Node = _get_audio_system()
	audio._music_player.stream = _make_stream()
	audio._music_player.volume_db = 0.0
	audio._music_player.play()

	audio._on_level_unloading(1)

	assert_bool(audio._music_fade_out_active).is_true()
	assert_float(audio._music_fade_out_duration_ms).is_equal_approx(AMBIENT_UNLOAD_FADE_MS, 0.1)


func test_level_unloading_starts_ambient_fade_out_only() -> void:
	var audio: Node = _get_audio_system()
	audio._ambience_pool[0].stream = _make_stream()
	audio._ambience_pool[0].volume_db = 0.0
	audio._ambience_pool[0].play()

	audio._on_level_unloading(1)

	# Crossfade en mode fade-out only : new_player == null
	assert_bool(audio._crossfade_active).is_true()
	assert_float(audio._crossfade_duration_ms).is_equal_approx(AMBIENT_UNLOAD_FADE_MS, 0.1)
	assert_object(audio._crossfade_new_player).is_null()
	assert_object(audio._crossfade_old_player).is_equal(audio._ambience_pool[0])


func test_level_unloading_no_op_if_ambient_idle() -> void:
	# Si aucun ambient ne joue (ex. boot avant level_active), pas de crossfade fade-out
	var audio: Node = _get_audio_system()

	audio._on_level_unloading(1)

	assert_bool(audio._crossfade_active).is_false()


# ---------------------------------------------------------------------------
# Music fade-out tick (Formula 4 Phase C linear-amplitude)
# ---------------------------------------------------------------------------

func test_music_fade_out_completes_at_t_full_duration() -> void:
	var audio: Node = _get_audio_system()
	audio._music_player.stream = _make_stream()
	audio._music_player.volume_db = 0.0
	audio._music_player.play()
	# stop_music capture _music_fade_out_start_msec via _get_time_msec.call() (1 call)
	# puis _tick_music_fade_out call() (1 call) → seq [start=0, tick=500]
	audio._get_time_msec = _make_time_callable([0, 500])

	audio.stop_music(0.5)  # 500 ms fade-out
	audio._tick_music_fade_out()

	# Fade complet à t=1.0 → stop + restore volume_db
	assert_bool(audio._music_fade_out_active).is_false()
	assert_bool(audio._music_player.playing).is_false()
	assert_float(audio._music_player.volume_db).is_equal_approx(0.0, 0.1)


# ---------------------------------------------------------------------------
# connect_level_signals null guard
# ---------------------------------------------------------------------------

func test_connect_level_signals_null_logs_error_no_crash() -> void:
	var audio: Node = _get_audio_system()
	audio.connect_level_signals(null)
	assert_bool(true).is_true()
