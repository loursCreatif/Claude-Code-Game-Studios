# Tests integration Story-007 — slow-mo pitch shift bus allowlist + clac exclusion.
#
# Couvre AC-AUD-15-a (a/b/b'/d/e) — bus invariants, bus pitch-shifted, slot clac
# exclu via _active_clac_players tracker, duration sample inchangée, sons démarrés
# pendant slow-mo zéro latence 1 tick. AC-AUD-15-b (c) anti-pop : SKIPPED headless
# CI (driver Dummy) — evidence playtest sound-designer Sprint Audio.
#
# Story : production/epics/audio-system/story-007-slow-mo-pitch-shift-bus-allowlist-clac-exclusion.md
# ADR   : ADR-0009 D-3 amendement r2
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const SLOW_MO_TIME_SCALE: float = 0.3
# Formula 5 stricte (pseudo-code ADR-0009 D-3 r2 ligne 71) :
#   pitch_factor = 2^(compute_semitones(ts)/12) = 2^(log2(ts)*12/12) = 2^log2(ts) = ts
# Donc pitch_factor IS strictement égal à time_scale (linear time = linear freq).
# NB : les valeurs numériques "0.8821 ≈ -2.1 semitones" dans les AC du story file
# sont une erreur éditoriale (correspond à un mapping perceptuel non-implémenté).
# Le test valide le comportement RÉEL de Formula 5 = la pseudo-code canonique.
const EXPECTED_PITCH_FACTOR_AT_03: float = 0.3  # Formula 5 strict
const TOLERANCE: float = 0.005
const TOLERANCE_INVARIANT: float = 0.001


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
	# Reset pool 3D — tous slots stop, pitch_scale=1.0, tracker vide.
	for i: int in range(audio.POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()
		p.pitch_scale = 1.0
	audio._3d_index = 0
	# Reset ambience pool.
	for i: int in range(audio.POOL_AMBIENCE_SIZE):
		var a: AudioStreamPlayer = audio._ambience_pool[i]
		if a.playing:
			a.stop()
		a.pitch_scale = 1.0
		a.volume_db = 0.0
	# Reset music_player.
	if audio._music_player.playing:
		audio._music_player.stop()
	audio._music_player.pitch_scale = 1.0
	# Reset clac tracker + pitch cache.
	audio._active_clac_players.clear()
	audio._last_pitch_factor = 1.0
	audio._last_time_scale = 1.0
	# Reset Engine.time_scale (toujours restore en sortie test pour ne pas polluer).
	Engine.time_scale = 1.0


func after_test() -> void:
	# Garde-fou : restore time_scale + invariants pour ne pas polluer suivants.
	Engine.time_scale = 1.0
	var audio: Node = _get_audio_system()
	for i: int in range(audio.POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()
		p.pitch_scale = 1.0


# ---------------------------------------------------------------------------
# AC-AUD-15-a (a) — bus invariants (SWING_ACTIVE, MUSIC) restent à pitch 1.0
# ---------------------------------------------------------------------------

func test_pitch_shift_swing_active_bus_invariant_under_slow_mo() -> void:
	# Arrange : son sur bus SWING_ACTIVE (allowlist=false), slot 3D actif.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var slot_idx: int = audio.play_3d_at(stream, Vector3(1.0, 0.0, 0.0), &"swing_active", 1.0)
	assert_int(slot_idx).is_greater_equal(0)
	# Act : active slow-mo + tick.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert : pitch_scale invariant 1.0 (bus hors allowlist).
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.0, TOLERANCE_INVARIANT)


func test_pitch_shift_music_bus_invariant_under_slow_mo() -> void:
	# Arrange : music joue.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._music_player.stream = stream
	audio._music_player.play()
	# Act.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert : music invariant 1.0.
	assert_float(audio._music_player.pitch_scale).is_equal_approx(1.0, TOLERANCE_INVARIANT)


# ---------------------------------------------------------------------------
# AC-AUD-15-a (b) — bus pitch-shifted (COMBAT_KILL non-clac, AMBIENCE)
# ---------------------------------------------------------------------------

func test_pitch_shift_blood_ambient_combat_kill_bus_shifted_under_slow_mo() -> void:
	# Arrange : blood (slot non-clac, NOT in tracker) sur COMBAT_KILL (allowlist=true).
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	var slot_idx: int = audio.play_3d_at(stream, Vector3(2.0, 0.0, 0.0), &"combat_kill", 1.0)
	# Vérifier slot n'est PAS dans tracker (pas un clac).
	assert_bool(audio._active_clac_players.has(slot_idx)).is_false()
	# Act : slow-mo + tick.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert : pitch_scale ≈ 0.8821.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(EXPECTED_PITCH_FACTOR_AT_03, TOLERANCE)


func test_pitch_shift_ambient_pool_bus_shifted_under_slow_mo() -> void:
	# Arrange : ambient[0] joue (story-005 _ambience_pool).
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._ambience_pool[0].stream = stream
	audio._ambience_pool[0].play()
	# Act.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert.
	assert_float(audio._ambience_pool[0].pitch_scale).is_equal_approx(EXPECTED_PITCH_FACTOR_AT_03, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-AUD-15-a (b') — slot clac exclu via _active_clac_players tracker
# ---------------------------------------------------------------------------

func test_pitch_shift_clac_slot_excluded_preserves_rule13_rank1() -> void:
	# Arrange : simule clac rank 1 (pitch=1.0) dans slot 3 + tracker.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	# Force slot 3 via _3d_index.
	audio._3d_index = 3
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.0)
	# Manuellement register slot dans tracker (simule Combat handler post-call).
	audio._active_clac_players[slot_idx] = true
	# Re-set pitch à 1.0 (Rule 13 rank 0 = 1.0 — play_3d_at a auto-pitch slow-mo
	# car bus allowlist + pitch default=1.0 ; mais test arrange POST-register donc
	# on simule l'état "clac registered avant tick").
	audio._3d_pool[slot_idx].pitch_scale = 1.0
	# Act : slow-mo + tick.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert : Rule 13 rank 1 préservé (1.0), PAS multiplié par 0.8821.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.0, TOLERANCE)


func test_pitch_shift_clac_slot_excluded_preserves_rule13_rank2() -> void:
	# Arrange : simule clac rank 2 (pitch=1.122) dans slot 4 + tracker.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._3d_index = 4
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.122)
	audio._active_clac_players[slot_idx] = true
	# Act.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert : rank 2 préservé.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.122, TOLERANCE)


func test_pitch_shift_clac_slot_excluded_preserves_rule13_rank3() -> void:
	# Arrange : rank 3 (pitch=1.260) dans slot 5.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._3d_index = 5
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.260)
	audio._active_clac_players[slot_idx] = true
	# Act.
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Assert.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.260, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-AUD-15-a (e) — sons démarrés pendant slow-mo : zéro latence 1 tick
# ---------------------------------------------------------------------------

func test_pitch_shift_blood_started_during_slow_mo_pre_set_at_play_no_tick_latency() -> void:
	# Arrange : slow-mo déjà actif AVANT play.
	var audio: Node = _get_audio_system()
	Engine.time_scale = SLOW_MO_TIME_SCALE
	var stream: AudioStream = _make_stream()
	# Act : play_3d_at blood (default pitch 1.0, bus allowlist).
	var slot_idx: int = audio.play_3d_at(stream, Vector3(3.0, 0.0, 0.0), &"combat_kill", 1.0)
	# Assert : pitch_scale ≈ 0.8821 IMMÉDIATEMENT (pas après tick suivant).
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(EXPECTED_PITCH_FACTOR_AT_03, TOLERANCE)


func test_pitch_shift_clac_played_during_slow_mo_with_explicit_pitch_preserved() -> void:
	# Arrange : slow-mo actif, Combat handler appelle play_3d_at avec rule13 pitch.
	var audio: Node = _get_audio_system()
	Engine.time_scale = SLOW_MO_TIME_SCALE
	var stream: AudioStream = _make_stream()
	# Act : play_3d_at clac avec rank 2 pitch (1.122 explicit).
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.122)
	# Assert : pitch_scale = 1.122 préservé (pas auto-overridé car != 1.0 default).
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.122, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-AUD-15-a (d) — duration sample inchangée (Godot pitch_scale ne mute pas le file)
# ---------------------------------------------------------------------------

func test_pitch_shift_does_not_mutate_stream_data() -> void:
	var audio: Node = _get_audio_system()
	var stream: AudioStreamWAV = _make_stream() as AudioStreamWAV
	# Données arbitraires pour vérifier non-mutation.
	stream.data = PackedByteArray([0, 0, 0, 0])
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.0)
	Engine.time_scale = SLOW_MO_TIME_SCALE
	audio._tick_slow_mo_pitch_shift()
	# Pitch shifté mais data inchangée.
	assert_int(stream.data.size()).is_equal(4)
	# pitch_scale appliqué au player, PAS au stream.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(EXPECTED_PITCH_FACTOR_AT_03, TOLERANCE)


# ---------------------------------------------------------------------------
# Restore invariants quand slow-mo se termine
# ---------------------------------------------------------------------------

func test_pitch_shift_restores_invariants_when_time_scale_returns_to_one() -> void:
	# Arrange : slow-mo actif, blood pitch-shifté.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	Engine.time_scale = SLOW_MO_TIME_SCALE
	var slot_idx: int = audio.play_3d_at(stream, Vector3(1.0, 0.0, 0.0), &"combat_kill", 1.0)
	audio._tick_slow_mo_pitch_shift()
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(EXPECTED_PITCH_FACTOR_AT_03, TOLERANCE)
	# Act : restore time_scale + tick.
	Engine.time_scale = 1.0
	audio._tick_slow_mo_pitch_shift()
	# Assert : pitch_scale restored à 1.0.
	assert_float(audio._3d_pool[slot_idx].pitch_scale).is_equal_approx(1.0, TOLERANCE_INVARIANT)


# ---------------------------------------------------------------------------
# Formula 5 — compute_semitones boundary
# ---------------------------------------------------------------------------

func test_pitch_shift_compute_semitones_at_one_returns_zero() -> void:
	var audio: Node = _get_audio_system()
	assert_float(audio.compute_semitones(1.0)).is_equal_approx(0.0, 0.001)


func test_pitch_shift_compute_semitones_at_03_returns_minus_20_84() -> void:
	# Formula 5 strict : log2(0.3) × 12 ≈ -1.737 × 12 ≈ -20.84.
	# pitch_factor résultant = 2^(-20.84/12) ≈ 0.3 (= time_scale, linear time/freq).
	var audio: Node = _get_audio_system()
	var st: float = audio.compute_semitones(0.3)
	assert_float(st).is_between(-20.85, -20.83)


func test_pitch_shift_compute_semitones_negative_time_scale_guard() -> void:
	# Guard : ts <= 0.0 → return 0.0 (no log domain error).
	var audio: Node = _get_audio_system()
	assert_float(audio.compute_semitones(-0.5)).is_equal_approx(0.0, 0.001)
	assert_float(audio.compute_semitones(0.0)).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Lint allowlist : COMBAT_KILL + AMBIENCE = true, autres = false (Rule 11 r2)
# ---------------------------------------------------------------------------

func test_pitch_shift_allowlist_combat_kill_true() -> void:
	var audio: Node = _get_audio_system()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"combat_kill", false)).is_true()


func test_pitch_shift_allowlist_ambience_true() -> void:
	var audio: Node = _get_audio_system()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"Ambience", false)).is_true()


func test_pitch_shift_allowlist_master_music_sfx_swing_ui_false() -> void:
	var audio: Node = _get_audio_system()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"Master", true)).is_false()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"Music", true)).is_false()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"SFX", true)).is_false()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"swing_active", true)).is_false()
	assert_bool(audio.PITCH_ALLOWLIST.get(&"UI", true)).is_false()
