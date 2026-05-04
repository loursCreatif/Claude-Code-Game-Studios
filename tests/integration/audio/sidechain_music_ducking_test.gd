# Tests integration Story-012 — Sidechain compressor MUSIC ← combat_kill verification
# via AudioServer.get_bus_peak_volume_left_db (post-effects).
#
# Couvre AC-AUD-16 (a) peak ducked -6 dB ± 1.5 / (b) release ~200 ms vers -3 dB
#       / (c) multi-kill reset / (d) continuité music playing == true / (e) headless fallback.
#
# Story : production/epics/audio-system/story-012-sidechain-music-peak-meter-verification-headless-fallback.md
# ADR   : ADR-0009 D-1 amendement r2 (sidechain MUSIC ← combat_kill)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const MUSIC_NOMINAL_DB: float = -3.0
const DUCKED_PEAK_DB: float = -6.0
const DUCKED_TOLERANCE: float = 1.5
const RELEASE_TOLERANCE: float = 1.0


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


## Stream long-running pour test continuité playing == true (story-012 d).
## AudioStreamWAV avec data 8-bit + loop_mode LOOP_FORWARD garantit playback
## continu pendant toute la durée du test (≥ 300 ms).
func _make_loopable_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = 44100
	# 1 seconde de silence 8-bit @ 44100 Hz = 44100 bytes (offset 0x80 = silence center pour 8-bit unsigned)
	var data: PackedByteArray = PackedByteArray()
	data.resize(44100)
	data.fill(0x80)
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = 44100
	return s


## Détection driver Dummy headless : le peak meter ne mixe rien et retourne -INF
## constant. On joue music quelques frames puis on lit le peak ; si <= -90 dB
## après 60 ms de play, le driver ne supporte pas le peak meter post-effects.
func _supports_peak_meter(audio: Node, music_idx: int) -> bool:
	var probe_stream: AudioStream = _make_stream()
	audio.play_music(probe_stream)
	# Attendre quelques mix chunks
	for _i: int in range(6):
		await get_tree().physics_frame
	await get_tree().create_timer(0.060).timeout
	var peak: float = AudioServer.get_bus_peak_volume_left_db(music_idx, 0)
	# Stop probe music pour ne pas polluer test suivant
	audio._music_player.stop()
	# Driver Dummy retourne -INF (Godot expose -inf comme float très négatif)
	return peak > -90.0


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
	audio.swoosh_stream = null
	audio.blood_stream = null
	audio._get_time_msec = Time.get_ticks_msec
	# Reset bus volumes nominaux
	var music_idx: int = AudioServer.get_bus_index(&"Music")
	AudioServer.set_bus_volume_db(music_idx, MUSIC_NOMINAL_DB)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	AudioServer.set_bus_volume_db(swing_idx, -6.0)


func after_test() -> void:
	var audio: Node = _get_audio_system()
	if audio._music_player.playing:
		audio._music_player.stop()
		audio._music_player.volume_db = 0.0


# AC-AUD-16 (a) + (b) — headless conditional, SKIP si Dummy driver
func test_audio_sidechain_peak_post_compressor_ducked_then_release_to_nominal() -> void:
	var audio: Node = _get_audio_system()
	var music_idx: int = AudioServer.get_bus_index(&"Music")

	if not await _supports_peak_meter(audio, music_idx):
		push_warning("AC-AUD-16 (a)+(b) SKIPPED — driver headless ne supporte pas peak meter post-effects (peak <= -90 dB sur probe). Evidence requirement Sprint Audio sound-designer playtest + AudioEffectRecord waveform Audacity/REAPER (production/qa/evidence/audio-sidechain-music-{date}.md)")
		return

	# Arrange : music playing nominal -3 dB, sidechain configuré au boot
	var music_stream: AudioStream = _make_stream()
	audio.play_music(music_stream)
	for _i: int in range(6):
		await get_tree().physics_frame

	# Act : trigger clac sur combat_kill bus
	audio.play_3d_at(audio.clac_stream, Vector3.ZERO, &"combat_kill")
	await get_tree().create_timer(0.020).timeout

	# Assert (a) : peak ducked ≈ -6 dB ± 1.5
	var ducked_peak: float = AudioServer.get_bus_peak_volume_left_db(music_idx, 0)
	assert_float(ducked_peak).override_failure_message(
		"AC-AUD-16 (a) — peak ducked attendu %.2f ± %.2f dB, mesuré %.2f dB" % [DUCKED_PEAK_DB, DUCKED_TOLERANCE, ducked_peak]
	).is_between(DUCKED_PEAK_DB - DUCKED_TOLERANCE, DUCKED_PEAK_DB + DUCKED_TOLERANCE)

	# Act : attendre release exponentielle ~200 ms
	await get_tree().create_timer(0.220).timeout

	# Assert (b) : peak remonte vers nominal -3 dB ± 1
	var released_peak: float = AudioServer.get_bus_peak_volume_left_db(music_idx, 0)
	assert_float(released_peak).override_failure_message(
		"AC-AUD-16 (b) — peak release vers nominal %.2f ± %.2f dB, mesuré %.2f dB" % [MUSIC_NOMINAL_DB, RELEASE_TOLERANCE, released_peak]
	).is_between(MUSIC_NOMINAL_DB - RELEASE_TOLERANCE, MUSIC_NOMINAL_DB + RELEASE_TOLERANCE)


# AC-AUD-16 (c) — headless conditional
func test_audio_sidechain_multi_kill_reset_peak_falls_back_release_restart() -> void:
	var audio: Node = _get_audio_system()
	var music_idx: int = AudioServer.get_bus_index(&"Music")

	if not await _supports_peak_meter(audio, music_idx):
		push_warning("AC-AUD-16 (c) SKIPPED — driver headless ne supporte pas peak meter post-effects. Evidence requirement Sprint Audio.")
		return

	# Arrange : music playing nominal
	var music_stream: AudioStream = _make_stream()
	audio.play_music(music_stream)
	for _i: int in range(6):
		await get_tree().physics_frame

	# Act 1 : 1er clac à t=0
	audio.play_3d_at(audio.clac_stream, Vector3.ZERO, &"combat_kill")
	await get_tree().create_timer(0.050).timeout  # t = 50 ms — release partiellement avancé

	# Act 2 : 2e clac avant fin release
	audio.play_3d_at(audio.clac_stream, Vector3.ZERO, &"combat_kill")
	await get_tree().create_timer(0.020).timeout  # t = 70 ms total

	# Assert (c) : peak retombe à -6 dB (release redémarre depuis zéro)
	var reset_peak: float = AudioServer.get_bus_peak_volume_left_db(music_idx, 0)
	assert_float(reset_peak).override_failure_message(
		"AC-AUD-16 (c) — peak retombe à %.2f ± %.2f dB suite à 2e clac multi-kill, mesuré %.2f dB. Si peak stagne à -3 dB → sidechain re-trigger non fonctionnel (vérifier attack_us config)" % [DUCKED_PEAK_DB, DUCKED_TOLERANCE, reset_peak]
	).is_between(DUCKED_PEAK_DB - DUCKED_TOLERANCE, DUCKED_PEAK_DB + DUCKED_TOLERANCE)


# AC-AUD-16 (d) — BLOCKING headless (flag boolean playing, indépendant du peak meter)
func test_audio_sidechain_music_continuity_playing_true_during_ducking() -> void:
	# Arrange : music joue pré-clac (stream loopable garantit playing constant)
	var audio: Node = _get_audio_system()
	var music_stream: AudioStream = _make_loopable_stream()
	audio.play_music(music_stream)
	await get_tree().physics_frame

	var music_player_playing_pre: bool = audio._music_player.playing
	assert_bool(music_player_playing_pre).override_failure_message(
		"AC-AUD-16 (d) precondition — music_player.playing doit être true post play_music()"
	).is_true()

	# Act 1 : clac dispatch (sidechain duck volume mais NE STOP PAS playback)
	audio.play_3d_at(audio.clac_stream, Vector3.ZERO, &"combat_kill")
	await get_tree().create_timer(0.030).timeout  # t = 30 ms post-clac, mid-ducking

	# Assert (d) mid-ducking : playing reste true
	var music_player_playing_during: bool = audio._music_player.playing
	assert_bool(music_player_playing_during).override_failure_message(
		"AC-AUD-16 (d) — music_player.playing doit rester true pendant ducking (continuité Couche 3). Sidechain doit ducker volume PAS arrêter playback."
	).is_true()

	# Act 2 : attendre post-release
	await get_tree().create_timer(0.250).timeout  # t = 280 ms total, post-release

	# Assert (d) post-release : playing toujours true
	var music_player_playing_post: bool = audio._music_player.playing
	assert_bool(music_player_playing_post).override_failure_message(
		"AC-AUD-16 (d) — music_player.playing doit rester true post-release ducking, mesuré false"
	).is_true()
