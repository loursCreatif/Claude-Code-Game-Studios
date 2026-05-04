# Tests integration Story-007 Phase D.3 r2.3 — _active_clac_players orphan tracker fix.
#
# Couvre : cleanup pré-stop round-robin saturation guard ; cleanup pré-connect
# si slot recyclé pour nouveau clac ; defensive disconnect _on_clac_finished.
# Garantit qu'aucun slot ne reste dans tracker après force-stop ou réutilisation.
#
# Story : production/epics/audio-system/story-007-slow-mo-pitch-shift-bus-allowlist-clac-exclusion.md
# ADR   : ADR-0009 D-3 r2.3
# Framework : GdUnit4 v5

extends GdUnitTestSuite


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
	for i: int in range(audio.POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()
		p.pitch_scale = 1.0
		# Disconnect any leftover finished callback (defensive).
		if i < audio._clac_finished_callbacks.size():
			var cb: Callable = audio._clac_finished_callbacks[i]
			if p.finished.is_connected(cb):
				p.finished.disconnect(cb)
	audio._3d_index = 0
	audio._active_clac_players.clear()
	Engine.time_scale = 1.0


func after_test() -> void:
	Engine.time_scale = 1.0
	var audio: Node = _get_audio_system()
	for i: int in range(audio.POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = audio._3d_pool[i]
		if p.playing:
			p.stop()


# ---------------------------------------------------------------------------
# Phase D.3 r2.3 fix — cleanup tracker AVANT stop() round-robin saturation
# ---------------------------------------------------------------------------

func test_orphan_tracker_round_robin_stop_erases_clac_before_force_stop() -> void:
	# Arrange : slot 5 dans tracker + finished callback connecté.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._3d_index = 5
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.0)
	assert_int(slot_idx).is_equal(5)
	audio._active_clac_players[slot_idx] = true
	var slot: AudioStreamPlayer3D = audio._3d_pool[slot_idx]
	var cb: Callable = audio._clac_finished_callbacks[slot_idx]
	slot.finished.connect(cb, CONNECT_ONE_SHOT)
	# Act : force-stop via wrapper.
	audio._round_robin_3d_stop_if_saturated(slot_idx)
	# Assert : tracker vide + callback disconnecté.
	assert_bool(audio._active_clac_players.has(slot_idx)).is_false()
	assert_bool(slot.finished.is_connected(cb)).is_false()


func test_orphan_tracker_play_3d_at_recycle_cleans_previous_clac_slot() -> void:
	# Arrange : slot 0 occupé par clac actif dans tracker.
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._3d_index = 0
	var first_slot: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.0)
	assert_int(first_slot).is_equal(0)
	audio._active_clac_players[first_slot] = true
	var slot: AudioStreamPlayer3D = audio._3d_pool[first_slot]
	var cb: Callable = audio._clac_finished_callbacks[first_slot]
	slot.finished.connect(cb, CONNECT_ONE_SHOT)
	# Act : round-robin cycle complet — _3d_index revient à 0 après 12 plays.
	# Force _3d_index back to 0 manuellement (simulate saturation cycle).
	audio._3d_index = 0
	var recycled_slot: int = audio.play_3d_at(stream, Vector3.ZERO, &"combat_kill", 1.0)
	assert_int(recycled_slot).is_equal(0)
	# Assert : tracker pour slot 0 = nettoyé AVANT stop() dans play_3d_at,
	# puis pas re-set (car on n'a pas fait register manuel cette fois).
	assert_bool(audio._active_clac_players.has(0)).is_false()
	# Et le callback ancien est disconnecté (CONNECT_ONE_SHOT n'a pas tiré
	# car force-stop ne fire pas finished).
	assert_bool(slot.finished.is_connected(cb)).is_false()


func test_orphan_tracker_cleanup_idempotent_on_non_clac_slot() -> void:
	# Arrange : slot 7 NOT in tracker (pas un clac).
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	audio._3d_index = 7
	var slot_idx: int = audio.play_3d_at(stream, Vector3.ZERO, &"Ambience", 1.0)
	assert_int(slot_idx).is_equal(7)
	# Act : appel cleanup → no-op gracieux.
	audio._cleanup_clac_slot_tracker(slot_idx)
	# Assert : pas d'erreur, tracker toujours vide.
	assert_bool(audio._active_clac_players.has(slot_idx)).is_false()
	assert_int(audio._active_clac_players.size()).is_equal(0)


func test_orphan_tracker_round_robin_stop_no_op_if_slot_not_playing() -> void:
	# Arrange : slot 3 not playing.
	var audio: Node = _get_audio_system()
	# Slot vierge (before_test stop tous).
	var slot: AudioStreamPlayer3D = audio._3d_pool[3]
	assert_bool(slot.playing).is_false()
	# Act.
	audio._round_robin_3d_stop_if_saturated(3)
	# Assert : aucune erreur, tracker toujours vide.
	assert_bool(audio._active_clac_players.has(3)).is_false()


func test_orphan_tracker_round_robin_stop_invalid_slot_idx_warns() -> void:
	# Arrange : slot_idx out-of-range.
	var audio: Node = _get_audio_system()
	# Act + Assert : push_warning, pas de crash, no-op.
	audio._round_robin_3d_stop_if_saturated(-1)
	audio._round_robin_3d_stop_if_saturated(audio.POOL_3D_SIZE)
	# Pas d'assertion d'état particulière — juste vérif no-crash.
	assert_int(audio._active_clac_players.size()).is_equal(0)


# ---------------------------------------------------------------------------
# Phase D.3 originale — _on_clac_slot_finished cleanup naturel
# ---------------------------------------------------------------------------

func test_orphan_tracker_on_clac_slot_finished_erases_entry() -> void:
	# Arrange : slot 2 dans tracker.
	var audio: Node = _get_audio_system()
	audio._active_clac_players[2] = true
	# Act : simule signal `finished` qui déclenche _on_clac_slot_finished.
	audio._on_clac_slot_finished(2)
	# Assert.
	assert_bool(audio._active_clac_players.has(2)).is_false()


func test_orphan_tracker_multiple_slots_independent_cleanup() -> void:
	# Arrange : slots 1, 4, 8 simultanés dans tracker.
	var audio: Node = _get_audio_system()
	audio._active_clac_players[1] = true
	audio._active_clac_players[4] = true
	audio._active_clac_players[8] = true
	# Act : cleanup slot 4 only.
	audio._cleanup_clac_slot_tracker(4)
	# Assert : slot 1 et 8 conservés, slot 4 erased.
	assert_bool(audio._active_clac_players.has(1)).is_true()
	assert_bool(audio._active_clac_players.has(4)).is_false()
	assert_bool(audio._active_clac_players.has(8)).is_true()
	assert_int(audio._active_clac_players.size()).is_equal(2)


# ---------------------------------------------------------------------------
# Type guard — Dictionary[int, bool] typed
# ---------------------------------------------------------------------------

func test_orphan_tracker_typed_dictionary_int_bool() -> void:
	# Arrange/Act : insère key int + value bool.
	var audio: Node = _get_audio_system()
	audio._active_clac_players[3] = true
	# Assert : dictionary respecte le typing (Godot 4.4+ runtime check).
	assert_int(audio._active_clac_players.size()).is_equal(1)
	assert_bool(audio._active_clac_players[3]).is_true()
	assert_int(typeof(audio._active_clac_players[3])).is_equal(TYPE_BOOL)
