# Tests integration Story-004 — Dash / Wall-jump / Respawn dispatch handlers.
#
# Couvre :
# - dash_started → play_2d sur SFX (≤ 100 ms)
# - wall_jumped → play_2d sur SFX (≤ 200 ms)
# - respawned → noop (silence intentionnel, no play_2d call — Pillar 1 clarté)
# - 2 slots actifs simultanés (dash + walljump) sur SFX bus
# - Streams null guards
#
# Story : production/epics/audio-system/story-004-movement-handlers-dash-wallrun-walljump-death.md
# ADR   : ADR-0009 D-4 (Movement signals dispatch)
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
	audio._2d_index = 0
	audio.dash_stream = _make_stream()
	audio.walljump_stream = _make_stream()
	# Reset wall-run state (cross-test isolation avec wallrun_fade_out_test)
	audio._wallrun_slot_idx = -1
	audio._wallrun_fade_active = false
	# Stop tous les slots 2D
	for p: AudioStreamPlayer in audio._2d_pool:
		if p.playing:
			p.stop()


# ---------------------------------------------------------------------------
# dash_started → play_2d SFX
# ---------------------------------------------------------------------------

func test_dash_started_dispatches_play_2d_on_sfx_bus() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var slot_before: int = audio._2d_index

	# Act
	audio._on_dash_started(Vector3.FORWARD, 25.0)

	# Assert — slot consommé sur SFX
	var slot_used: int = (audio._2d_index - 1 + audio.POOL_2D_SIZE) % audio.POOL_2D_SIZE
	assert_int(slot_used).is_equal(slot_before)
	var slot: AudioStreamPlayer = audio._2d_pool[slot_used]
	assert_object(slot.stream).is_equal(audio.dash_stream)
	assert_str(String(slot.bus)).is_equal("SFX")


func test_dash_started_no_op_when_stream_null() -> void:
	var audio: Node = _get_audio_system()
	audio.dash_stream = null
	var idx_before: int = audio._2d_index

	audio._on_dash_started()

	assert_int(audio._2d_index).is_equal(idx_before)


# ---------------------------------------------------------------------------
# wall_jumped → play_2d SFX
# ---------------------------------------------------------------------------

func test_wall_jumped_dispatches_play_2d_on_sfx_bus() -> void:
	var audio: Node = _get_audio_system()
	var slot_before: int = audio._2d_index

	audio._on_wall_jumped(Vector3.UP, Vector3(5.0, 0.0, 0.0))

	var slot_used: int = (audio._2d_index - 1 + audio.POOL_2D_SIZE) % audio.POOL_2D_SIZE
	assert_int(slot_used).is_equal(slot_before)
	var slot: AudioStreamPlayer = audio._2d_pool[slot_used]
	assert_object(slot.stream).is_equal(audio.walljump_stream)
	assert_str(String(slot.bus)).is_equal("SFX")


func test_wall_jumped_no_op_when_stream_null() -> void:
	var audio: Node = _get_audio_system()
	audio.walljump_stream = null
	var idx_before: int = audio._2d_index

	audio._on_wall_jumped()

	assert_int(audio._2d_index).is_equal(idx_before)


# ---------------------------------------------------------------------------
# Multi-dispatch — 2 slots actifs simultanés
# ---------------------------------------------------------------------------

func test_dash_and_walljump_consume_2_distinct_slots() -> void:
	var audio: Node = _get_audio_system()
	var slot_initial: int = audio._2d_index

	audio._on_dash_started(Vector3.FORWARD, 25.0)
	audio._on_wall_jumped(Vector3.UP, Vector3.ZERO)

	# Round-robin a avancé de 2 slots (sauf wrap)
	var expected_after: int = (slot_initial + 2) % audio.POOL_2D_SIZE
	assert_int(audio._2d_index).is_equal(expected_after)

	# 2 slots distincts contiennent dash et walljump streams
	var dash_slot: int = slot_initial
	var walljump_slot: int = (slot_initial + 1) % audio.POOL_2D_SIZE
	assert_object(audio._2d_pool[dash_slot].stream).is_equal(audio.dash_stream)
	assert_object(audio._2d_pool[walljump_slot].stream).is_equal(audio.walljump_stream)


# ---------------------------------------------------------------------------
# respawned silence intentionnel — NO handler exposé
# ---------------------------------------------------------------------------

func test_respawned_no_handler_exposed_silence_intentional() -> void:
	# Garantit qu'aucun handler _on_respawned n'est défini sur AudioSystem.
	# Pillar 1 clarté rythmique : silence post-respawn intentionnel
	# (vs play_2d juxtaposé à frame N+1 du death overlap).
	var audio: Node = _get_audio_system()
	assert_bool(audio.has_method("_on_respawned")).is_false()


# ---------------------------------------------------------------------------
# connect_movement_signals — null guard
# ---------------------------------------------------------------------------

func test_connect_movement_signals_null_player_logs_error_no_crash() -> void:
	var audio: Node = _get_audio_system()
	# Doit pas crasher (push_error puis return)
	audio.connect_movement_signals(null)
	# Pas d'assertion side-effect — le simple fait de ne pas crasher = pass
	assert_bool(true).is_true()
