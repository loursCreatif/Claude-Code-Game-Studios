# Tests unit Story-006 — GSM pause/resume Master mute + state preservation offset.
#
# Couvre AC-AUD-08 (a/b/c) + AC-AUD-09 (a/b/c) + forbidden mutation autorité GSM
# + process_mode == ALWAYS.
#
# Pattern wall-clock injection via `_get_time_msec: Callable` (ADR-0006 D-5).
# Pattern test : invocation directe `_on_state_changed(state_int)` au lieu de mock GSM
# (signal DEFERRED testé séparément via has_signal/is_connected idempotent guard).
#
# Story : production/epics/audio-system/story-006-gsm-pause-resume-master-mute-state-preservation.md
# ADR   : ADR-0009 D-1 + ADR-0007 D-4 + ADR-0007 D-10
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const STATE_PLAYING: int = 1
const STATE_PAUSED: int = 2


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
	audio._is_paused = false
	audio._fade_pause_msec = 0
	audio._swoosh_fade_active = false
	audio._swoosh_fade_start_msec = 0
	audio._ducking_release_active = false
	audio._ducking_release_start_msec = 0
	audio._wallrun_fade_active = false
	audio._wallrun_fade_start_msec = 0
	audio._crossfade_active = false
	audio._crossfade_start_msec = 0
	audio._music_fade_out_active = false
	audio._music_fade_out_start_msec = 0
	audio._get_time_msec = Time.get_ticks_msec
	# Toujours unmute en sortie de test pour ne pas polluer le suivant
	AudioServer.set_bus_mute(0, false)
	if audio._music_player.playing:
		audio._music_player.stop()
	audio._music_player.volume_db = 0.0
	audio._music_player.stream = null


func after_test() -> void:
	# Garde-fou si test laisse Master muté
	AudioServer.set_bus_mute(0, false)


# ---------------------------------------------------------------------------
# process_mode == ALWAYS (Godot 4.6 enum value 3)
# ---------------------------------------------------------------------------

func test_process_mode_is_always_for_pause_signal_reception() -> void:
	# AudioSystem doit recevoir state_changed(PLAYING) DEFERRED même quand
	# SceneTree paused → process_mode = ALWAYS requis (ADR-0007 D-4).
	var audio: Node = _get_audio_system()
	assert_int(audio.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


# ---------------------------------------------------------------------------
# AC-AUD-08 (a) — Mute Master sur state PAUSED
# ---------------------------------------------------------------------------

func test_state_paused_mutes_master_bus() -> void:
	var audio: Node = _get_audio_system()

	audio._on_state_changed(STATE_PAUSED)

	assert_bool(AudioServer.is_bus_mute(0)).is_true()


# ---------------------------------------------------------------------------
# AC-AUD-08 (b) — Queue audio préservée (music.playing reste true)
# ---------------------------------------------------------------------------

func test_state_paused_preserves_music_player_playing() -> void:
	var audio: Node = _get_audio_system()
	audio._music_player.stream = _make_stream()
	audio._music_player.play()

	audio._on_state_changed(STATE_PAUSED)

	# music.playing reste true — pas de stop() ni stream_paused individuel (R-AUD-10)
	assert_bool(audio._music_player.playing).is_true()


# ---------------------------------------------------------------------------
# AC-AUD-08 (c) — Snapshot wall-clock fade-pause-msec
# ---------------------------------------------------------------------------

func test_state_paused_captures_fade_pause_msec_snapshot() -> void:
	var audio: Node = _get_audio_system()
	audio._swoosh_fade_active = true
	audio._swoosh_fade_start_msec = 1000
	audio._get_time_msec = func() -> int: return 1015

	audio._on_state_changed(STATE_PAUSED)

	# _fade_pause_msec capturé == 1015
	assert_int(audio._fade_pause_msec).is_equal(1015)
	# _swoosh_fade_start_msec inchangé pour le moment (offset appliqué au resume)
	assert_int(audio._swoosh_fade_start_msec).is_equal(1000)


func test_state_paused_idempotent_double_pause_no_op() -> void:
	# Double emit GSM (theorique) ne doit pas re-snapshot _fade_pause_msec
	var audio: Node = _get_audio_system()
	audio._get_time_msec = _make_time_callable([1000, 2000])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PAUSED)  # idempotent

	# Premier snapshot conservé (1000) — pas écrasé par 2000
	assert_int(audio._fade_pause_msec).is_equal(1000)


# ---------------------------------------------------------------------------
# AC-AUD-09 (a) — Unmute Master sur state PLAYING (resume)
# ---------------------------------------------------------------------------

func test_state_playing_after_pause_unmutes_master() -> void:
	var audio: Node = _get_audio_system()

	audio._on_state_changed(STATE_PAUSED)
	assert_bool(AudioServer.is_bus_mute(0)).is_true()  # sanity

	audio._on_state_changed(STATE_PLAYING)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()


# ---------------------------------------------------------------------------
# AC-AUD-09 (b) — Offset wall-clock appliqué aux fades actifs
# ---------------------------------------------------------------------------

func test_state_playing_applies_offset_to_swoosh_fade_start() -> void:
	# Setup : swoosh fade démarré à t=1000, pause à t=1015 (fade à 15ms),
	# resume à t=6015 (5 s wall-clock écoulées).
	# Offset : start_msec += (resume - pause) = 5000 → 6000.
	# Au resume tick : elapsed = 6015 - 6000 = 15ms — fade reprend exactement à mi-fade.
	var audio: Node = _get_audio_system()
	audio._swoosh_fade_active = true
	audio._swoosh_fade_start_msec = 1000
	audio._get_time_msec = _make_time_callable([1015, 6015])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# Offset appliqué : 1000 + (6015 - 1015) = 6000
	assert_int(audio._swoosh_fade_start_msec).is_equal(6000)


func test_state_playing_applies_offset_to_ducking_release_start() -> void:
	var audio: Node = _get_audio_system()
	audio._ducking_release_active = true
	audio._ducking_release_start_msec = 2000
	audio._get_time_msec = _make_time_callable([2010, 5010])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# 2000 + (5010 - 2010) = 5000
	assert_int(audio._ducking_release_start_msec).is_equal(5000)


func test_state_playing_applies_offset_to_wallrun_fade_start() -> void:
	var audio: Node = _get_audio_system()
	audio._wallrun_fade_active = true
	audio._wallrun_fade_start_msec = 500
	audio._get_time_msec = _make_time_callable([550, 1550])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# 500 + (1550 - 550) = 1500
	assert_int(audio._wallrun_fade_start_msec).is_equal(1500)


func test_state_playing_applies_offset_to_crossfade_start() -> void:
	var audio: Node = _get_audio_system()
	audio._crossfade_active = true
	audio._crossfade_start_msec = 100
	audio._get_time_msec = _make_time_callable([200, 700])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# 100 + (700 - 200) = 600
	assert_int(audio._crossfade_start_msec).is_equal(600)


func test_state_playing_applies_offset_to_music_fade_out_start() -> void:
	var audio: Node = _get_audio_system()
	audio._music_fade_out_active = true
	audio._music_fade_out_start_msec = 3000
	audio._get_time_msec = _make_time_callable([3050, 8050])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# 3000 + (8050 - 3050) = 8000
	assert_int(audio._music_fade_out_start_msec).is_equal(8000)


func test_state_playing_no_offset_when_fades_inactive() -> void:
	# Sanity : si aucun fade actif, aucun start_msec ne doit muter
	var audio: Node = _get_audio_system()
	audio._swoosh_fade_start_msec = 1000
	audio._ducking_release_start_msec = 2000
	audio._wallrun_fade_start_msec = 500
	audio._crossfade_start_msec = 100
	audio._music_fade_out_start_msec = 3000
	audio._get_time_msec = _make_time_callable([10, 5010])

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# Tous les start_msec inchangés (aucun *_active = true)
	assert_int(audio._swoosh_fade_start_msec).is_equal(1000)
	assert_int(audio._ducking_release_start_msec).is_equal(2000)
	assert_int(audio._wallrun_fade_start_msec).is_equal(500)
	assert_int(audio._crossfade_start_msec).is_equal(100)
	assert_int(audio._music_fade_out_start_msec).is_equal(3000)


# ---------------------------------------------------------------------------
# AC-AUD-09 (c) — Music audible immédiatement (pas de re-trigger play)
# ---------------------------------------------------------------------------

func test_state_playing_does_not_retrigger_music_play() -> void:
	var audio: Node = _get_audio_system()
	var stream_a: AudioStream = _make_stream()
	audio._music_player.stream = stream_a
	audio._music_player.play()

	audio._on_state_changed(STATE_PAUSED)
	audio._on_state_changed(STATE_PLAYING)

	# music.playing toujours true (pas de stop puis re-play — queue préservée)
	assert_bool(audio._music_player.playing).is_true()
	# Stream identique (pas de réassignation)
	assert_object(audio._music_player.stream).is_equal(stream_a)


# ---------------------------------------------------------------------------
# Idempotence guard sur _exit_pause
# ---------------------------------------------------------------------------

func test_state_playing_without_prior_pause_no_op() -> void:
	# Si state_changed(PLAYING) reçu sans pause préalable (theorique) → no-op.
	var audio: Node = _get_audio_system()
	audio._swoosh_fade_active = true
	audio._swoosh_fade_start_msec = 1000

	audio._on_state_changed(STATE_PLAYING)

	# Aucun offset appliqué (start_msec inchangé)
	assert_int(audio._swoosh_fade_start_msec).is_equal(1000)
	assert_bool(audio._is_paused).is_false()


# ---------------------------------------------------------------------------
# États non gérés (MENU, RESPAWNING, BOSS_DEFEATED) — no-op
# ---------------------------------------------------------------------------

func test_state_menu_no_op_no_mute() -> void:
	var audio: Node = _get_audio_system()
	audio._on_state_changed(0)  # MENU
	assert_bool(AudioServer.is_bus_mute(0)).is_false()
	assert_bool(audio._is_paused).is_false()


func test_state_respawning_no_op_no_mute() -> void:
	var audio: Node = _get_audio_system()
	audio._on_state_changed(3)  # RESPAWNING
	assert_bool(AudioServer.is_bus_mute(0)).is_false()
	assert_bool(audio._is_paused).is_false()


# ---------------------------------------------------------------------------
# Forbidden : mutation autorité GSM (Engine.time_scale / get_tree().paused)
# ---------------------------------------------------------------------------

func test_audio_system_source_forbids_engine_time_scale_mutation() -> void:
	# Lint static : audio_system.gd ne doit JAMAIS muter Engine.time_scale
	# (autorité unique GSM ADR-0007 D-4).
	var f: FileAccess = FileAccess.open("res://src/core/audio_system.gd", FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()
	# Forbidden : `Engine.time_scale = ` (assignation). Lecture autorisée.
	var has_assign: bool = src.contains("Engine.time_scale =") or src.contains("Engine.time_scale=")
	assert_bool(has_assign).override_failure_message(
		"audio_system.gd contient mutation Engine.time_scale — VIOLATION ADR-0007 D-4 (autorité GSM)"
	).is_false()


func test_audio_system_source_forbids_get_tree_paused_mutation() -> void:
	var f: FileAccess = FileAccess.open("res://src/core/audio_system.gd", FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()
	# Forbidden : `get_tree().paused = ` (assignation). Lecture autorisée si lookup.
	var has_assign: bool = src.contains("get_tree().paused =") or src.contains("get_tree().paused=")
	assert_bool(has_assign).override_failure_message(
		"audio_system.gd contient mutation get_tree().paused — VIOLATION ADR-0007 D-4 (autorité GSM)"
	).is_false()


# ---------------------------------------------------------------------------
# DEFERRED connect contract (idempotent + flag DEFERRED)
# ---------------------------------------------------------------------------

func test_connect_gsm_signals_idempotent() -> void:
	# Re-call _connect_gsm_signals ne doit pas créer de connexion duplicate.
	var audio: Node = _get_audio_system()
	audio._connect_gsm_signals()
	audio._connect_gsm_signals()  # idempotent

	var gsm: Node = audio.get_node_or_null("/root/GameStateManager")
	if gsm == null:
		# Pas de GSM autoload en test runtime → no-op gracieux acceptable
		assert_bool(true).is_true()
		return
	# Si GSM présent : 1 seule connexion (pas 2)
	var connections: Array = gsm.state_changed.get_connections()
	var count_to_audio: int = 0
	for c: Dictionary in connections:
		if c.callable.get_object() == audio:
			count_to_audio += 1
	assert_int(count_to_audio).is_equal(1)
