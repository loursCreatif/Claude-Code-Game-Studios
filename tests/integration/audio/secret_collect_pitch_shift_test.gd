# Tests integration Story-008 — Secret collect handler pitch +5 semitones bus SFX
# invariant slow-mo (Rule 17 r2.2 NB-CRD-6 Option A + Formula 7).
#
# Couvre AC-AUD-18 (a-h) : dispatch correct, bus exclusif SFX, pas de ducking,
# compteur multi-kill intact, position 3D capturée, pas de blood ambiance, tier
# indifférent, fallback NaN/inf, defensive queue_free.
# Couvre AC-AUD-19 (a-c) : pitch invariant slow-mo, pas composite Formula 5,
# retour time_scale = 1.0.
#
# Story : production/epics/audio-system/story-008-secret-handler-pitch-aigu-bus-sfx-invariant-slow-mo.md
# ADR   : ADR-0009 D-3 (R-AUD-17 secret pitch +5 semitones bus SFX exclusif)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const POOL_3D_SIZE: int = 12
const POOL_2D_SIZE: int = 5
const EXPECTED_SECRET_PITCH: float = 1.3348398541700344  # 2.0 ** (5/12)
const FORMULA5_AT_03: float = 0.8821  # composite forbidden : 1.335 * 0.8821 ≈ 1.178
const SLOW_MO_TIME_SCALE: float = 0.3


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 44100
	s.stereo = false
	s.data = PackedByteArray()
	return s


func _last_3d_slot_idx(audio: Node) -> int:
	return (audio._3d_index - 1 + POOL_3D_SIZE) % POOL_3D_SIZE


func _last_2d_slot_idx(audio: Node) -> int:
	return (audio._2d_index - 1 + POOL_2D_SIZE) % POOL_2D_SIZE


func before_test() -> void:
	var audio: Node = _get_audio_system()
	# Reset pools
	for i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()
		p.pitch_scale = 1.0
		# Disconnect leftover clac callbacks (defensive cross-test).
		if i < audio._clac_finished_callbacks.size():
			var cb: Callable = audio._clac_finished_callbacks[i]
			if p.finished.is_connected(cb):
				p.finished.disconnect(cb)
	for i: int in range(POOL_2D_SIZE):
		var p2: AudioStreamPlayer = audio._2d_pool[i]
		if p2.playing:
			p2.stop()
		p2.pitch_scale = 1.0
	audio._3d_index = 0
	audio._2d_index = 0
	# Reset trackers
	audio._active_clac_players.clear()
	audio._slot_fixed_pitch.clear()
	# Reset combat state (assert intact post-secret)
	audio._kill_count_this_swing = 0
	audio._blood_pending_count = 0
	for i: int in range(audio.BLOOD_QUEUE_SIZE):
		audio._blood_pending_msec[i] = -1.0
	# Stub streams
	audio.clac_stream = _make_stream()
	audio.blood_stream = _make_stream()  # set non-null pour détecter accidental dispatch
	audio.swoosh_stream = null
	# Reset slow-mo cache
	audio._last_pitch_factor = 1.0
	audio._last_time_scale = 1.0
	# Reset bus swing_active à NOMINAL (pour assert pas de ducking)
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	AudioServer.set_bus_volume_db(swing_idx, -6.0)
	# Restore time_scale (defensive cross-test pollution)
	Engine.time_scale = 1.0


func after_test() -> void:
	# Guard restore — autres tests assument time_scale=1.0
	Engine.time_scale = 1.0
	var audio: Node = _get_audio_system()
	for i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()
	for i: int in range(POOL_2D_SIZE):
		var p2: AudioStreamPlayer = audio._2d_pool[i]
		if p2.playing:
			p2.stop()
	audio._slot_fixed_pitch.clear()


func _make_secret_node(pos: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	add_child(n)
	n.global_position = pos
	return n


# ---------------------------------------------------------------------------
# AC-AUD-18 (a) Dispatch correct + (e) position 3D capturée
# ---------------------------------------------------------------------------

func test_secret_collect_dispatches_play_3d_at_with_pitch_5_semitones_bus_sfx() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(5.0, 1.0, 3.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert : slot 3D occupé avec pitch ≈ 1.335, bus SFX, position correcte
	var idx: int = _last_3d_slot_idx(audio)
	var slot: AudioStreamPlayer3D = audio._3d_pool[idx]
	assert_bool(slot.playing).is_true()
	assert_float(slot.pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.001)
	assert_str(String(slot.bus)).is_equal("SFX")
	assert_vector(slot.global_position).is_equal_approx(Vector3(5.0, 1.0, 3.0), Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# AC-AUD-18 (b) Bus exclusif SFX (PAS COMBAT_KILL ni SWING_ACTIVE)
# ---------------------------------------------------------------------------

func test_secret_collect_does_not_use_combat_kill_or_swing_active_bus() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert
	var idx: int = _last_3d_slot_idx(audio)
	var bus_str: String = String(audio._3d_pool[idx].bus)
	assert_str(bus_str).is_not_equal("combat_kill")
	assert_str(bus_str).is_not_equal("swing_active")


# ---------------------------------------------------------------------------
# AC-AUD-18 (c) Pas de ducking SWING_ACTIVE
# ---------------------------------------------------------------------------

func test_secret_collect_does_not_duck_swing_active_bus() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	var db_before: float = AudioServer.get_bus_volume_db(swing_idx)
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert
	var db_after: float = AudioServer.get_bus_volume_db(swing_idx)
	assert_float(db_after).is_equal_approx(db_before, 0.001)


# ---------------------------------------------------------------------------
# AC-AUD-18 (d) Compteur multi-kill intact
# ---------------------------------------------------------------------------

func test_secret_collect_does_not_increment_kill_count_this_swing() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	audio._kill_count_this_swing = 2  # value arbitraire pré-existante
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert
	assert_int(audio._kill_count_this_swing).is_equal(2)


# ---------------------------------------------------------------------------
# AC-AUD-18 (f) Pas de blood ambiance chain
# ---------------------------------------------------------------------------

func test_secret_collect_does_not_schedule_blood_ambiance() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var blood_count_before: int = audio._blood_pending_count
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert
	assert_int(audio._blood_pending_count).is_equal(blood_count_before)


# ---------------------------------------------------------------------------
# AC-AUD-18 (g) Tier indifférent
# ---------------------------------------------------------------------------

func test_secret_collect_tier_3_produces_same_pitch_as_tier_1() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 3)
	# Assert
	var idx: int = _last_3d_slot_idx(audio)
	assert_float(audio._3d_pool[idx].pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.001)


# ---------------------------------------------------------------------------
# AC-AUD-18 (h) Position invalide NaN → fallback play_2d head-locked
# ---------------------------------------------------------------------------

func test_secret_collect_nan_position_falls_back_to_play_2d() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(NAN, NAN, NAN))
	var idx_3d_before: int = audio._3d_index
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert : play_2d appelé (slot 2D occupé avec pitch 1.335 bus SFX)
	var idx_2d: int = _last_2d_slot_idx(audio)
	var slot_2d: AudioStreamPlayer = audio._2d_pool[idx_2d]
	assert_bool(slot_2d.playing).is_true()
	assert_float(slot_2d.pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.001)
	assert_str(String(slot_2d.bus)).is_equal("SFX")
	# Assert : play_3d_at PAS appelé (_3d_index inchangé)
	assert_int(audio._3d_index).is_equal(idx_3d_before)


func test_secret_collect_inf_position_falls_back_to_play_2d() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(INF, 0.0, 0.0))
	var idx_3d_before: int = audio._3d_index
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert
	var idx_2d: int = _last_2d_slot_idx(audio)
	assert_bool(audio._2d_pool[idx_2d].playing).is_true()
	assert_int(audio._3d_index).is_equal(idx_3d_before)


# ---------------------------------------------------------------------------
# Note : test "freed node fallback play_2d" non implémenté.
# Raison : GDScript typed strict reject les freed nodes AVANT l'entrée de la
# fonction (signature `secret_node: Node`). En runtime, Godot auto-disconnect
# les signals vers freed nodes (donc DEFERRED reçu sur freed sender quasi-
# impossible). La garde `is_instance_valid` reste défensive comme coup de
# ceinture supplémentaire (cost: 1 if-check), mais ne peut pas être testée
# isolément sans relâcher le typing handler.
# ---------------------------------------------------------------------------
# AC-AUD-19 (a) Pitch invariant slow-mo + (b) pas composite Formula 5
# ---------------------------------------------------------------------------

func test_secret_collect_pitch_invariant_under_slow_mo_03() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	Engine.time_scale = SLOW_MO_TIME_SCALE
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act : émet sous slow-mo
	audio._on_secret_collected(secret_node, 1)
	# Assert pre-tick : pitch déjà à 1.335 (handler le set)
	var idx: int = _last_3d_slot_idx(audio)
	var slot: AudioStreamPlayer3D = audio._3d_pool[idx]
	assert_float(slot.pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.005)
	# Act : tick slow-mo loop (équivalent _physics_process tick)
	audio._tick_slow_mo_pitch_shift()
	# Assert : pitch toujours invariant après tick (tracker _slot_fixed_pitch protège)
	assert_float(slot.pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.005)
	# Assert (b) : pas composite Formula 5 (1.335 * 0.8821 ≈ 1.178)
	var composite: float = EXPECTED_SECRET_PITCH * FORMULA5_AT_03
	assert_float(absf(slot.pitch_scale - composite)).is_greater(0.05)


func test_secret_collect_tracker_fixed_pitch_registered() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	# Act
	audio._on_secret_collected(secret_node, 1)
	# Assert : slot enregistré dans tracker avec pitch attendu
	var idx: int = _last_3d_slot_idx(audio)
	assert_bool(audio._slot_fixed_pitch.has(idx)).is_true()
	assert_float(audio._slot_fixed_pitch[idx]).is_equal_approx(EXPECTED_SECRET_PITCH, 0.001)


# ---------------------------------------------------------------------------
# AC-AUD-19 (c) Retour time_scale = 1.0 → prochain secret pitch 1.335
# ---------------------------------------------------------------------------

func test_secret_collect_time_scale_restore_yields_consistent_pitch() -> void:
	# Arrange : 1er secret sous slow-mo
	var audio: Node = _get_audio_system()
	Engine.time_scale = SLOW_MO_TIME_SCALE
	var secret1: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	audio._on_secret_collected(secret1, 1)
	# Act : restore time_scale puis 2e secret
	Engine.time_scale = 1.0
	var secret2: Node3D = _make_secret_node(Vector3(2.0, 0.0, 0.0))
	audio._on_secret_collected(secret2, 1)
	# Assert : 2e slot toujours pitch 1.335
	var idx2: int = _last_3d_slot_idx(audio)
	assert_float(audio._3d_pool[idx2].pitch_scale).is_equal_approx(EXPECTED_SECRET_PITCH, 0.001)


# ---------------------------------------------------------------------------
# Cleanup tracker fixed_pitch au recyclage round-robin
# ---------------------------------------------------------------------------

func test_secret_slot_cleanup_on_round_robin_recycle() -> void:
	# Arrange : secret slot 0
	var audio: Node = _get_audio_system()
	audio._3d_index = 0
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	audio._on_secret_collected(secret_node, 1)
	assert_bool(audio._slot_fixed_pitch.has(0)).is_true()
	# Act : recycle slot 0 via play_3d_at (force _3d_index back to 0)
	audio._3d_index = 0
	var stream: AudioStream = _make_stream()
	audio.play_3d_at(stream, Vector3.ZERO, &"SFX", 1.0)
	# Assert : tracker nettoyé
	assert_bool(audio._slot_fixed_pitch.has(0)).is_false()


func test_secret_slot_cleanup_on_force_stop_saturated() -> void:
	# Arrange : secret slot 5
	var audio: Node = _get_audio_system()
	audio._3d_index = 5
	var secret_node: Node3D = _make_secret_node(Vector3(0.0, 0.0, 0.0))
	audio._on_secret_collected(secret_node, 1)
	assert_bool(audio._slot_fixed_pitch.has(5)).is_true()
	# Act : force-stop via wrapper
	audio._round_robin_3d_stop_if_saturated(5)
	# Assert : tracker nettoyé
	assert_bool(audio._slot_fixed_pitch.has(5)).is_false()


# ---------------------------------------------------------------------------
# connect_secret_signals — null guard + signal absent guard
# ---------------------------------------------------------------------------

func test_connect_secret_signals_null_node_no_crash() -> void:
	# Arrange + Act + Assert : no crash
	var audio: Node = _get_audio_system()
	audio.connect_secret_signals(null)
	assert_bool(true).is_true()  # reach point sans crash


func test_connect_secret_signals_node_without_signal_no_crash() -> void:
	# Arrange : node sans signal `secret_collected`
	var audio: Node = _get_audio_system()
	var stub: Node = Node.new()
	add_child(stub)
	# Act + Assert : no crash, push_warning capturé silencieusement
	audio.connect_secret_signals(stub)
	assert_bool(true).is_true()
