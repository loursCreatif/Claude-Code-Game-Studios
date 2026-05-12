# Tests perf Story-011 — Audio 5-swings stress 1000 frames + sub-budgets handler/play_3d_at Phase D.4.
#
# Couvre AC-AUD-13 (a/b/c/d/e/f) — frame time / audio CPU / memory delta / object count /
# handler isolé p99 < 100 µs / play_3d_at isolé p99 < 50 µs.
#
# AC-AUD-13 (g) sidechain CPU : ADVISORY — pas de monitor Godot 4.6 expose CPU compresseur isolé,
# evidence Sprint Audio Godot Profiler manuel (cf. evidence doc).
#
# Story : production/epics/audio-system/story-011-performance-budget-5-swings-stress-sub-budgets-phase-d4.md
# ADR   : ADR-0009 D-2 (pool exclusive) + D-3 (wall-clock fades) + VC-8 (perf 5-swings stress)
# Framework : GdUnit4 v5

extends GdUnitTestSuite


const FRAMES: int = 1000
const FRAME_BUDGET_MS: float = 16.6
const AUDIO_BUDGET_MS: float = 0.5
const HANDLER_BUDGET_US: int = 100
const PLAY_3D_BUDGET_US: int = 50
const MEMORY_BUDGET_KB: int = 100

const POOL_3D_SIZE: int = 12
const POOL_2D_SIZE: int = 5
const POOL_AMBIENCE_SIZE: int = 2


var _frame_proxy_us: PackedInt64Array
var _audio_cpu_us: PackedInt64Array
var _handler_us: PackedInt64Array
var _play_3d_us: PackedInt64Array
var _previous_time_scale: float


func _get_audio_system() -> Node:
	return get_tree().root.get_node("AudioSystem")


func _make_stream() -> AudioStream:
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.data = PackedByteArray()
	return s


func _percentile_99(samples: PackedInt64Array) -> int:
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	var idx: int = int(float(sorted.size()) * 0.99)
	return sorted[idx]


func before_test() -> void:
	# Pré-alloc PackedInt64Array zero-alloc dans la boucle hot path 1000 frames
	# (8 KB heap pré-réservés × 4 buffers = 32 KB stable, alloc one-shot avant boucle).
	_frame_proxy_us = PackedInt64Array()
	_frame_proxy_us.resize(FRAMES)
	_audio_cpu_us = PackedInt64Array()
	_audio_cpu_us.resize(FRAMES)
	_handler_us = PackedInt64Array()
	_handler_us.resize(FRAMES)
	_play_3d_us = PackedInt64Array()
	_play_3d_us.resize(FRAMES)
	_previous_time_scale = Engine.time_scale
	Engine.time_scale = 1.0  # AC-AUD-13 fixture isolation slow-mo (story-007 orthogonal)

	# Reset AudioSystem state pour isolation entre tests
	var audio: Node = _get_audio_system()
	audio._kill_count_this_swing = 0
	audio._3d_index = 0
	audio._2d_index = 0
	audio._swoosh_fade_active = false
	audio._ducking_release_active = false
	audio._wallrun_fade_active = false
	audio._crossfade_active = false
	audio._music_fade_out_active = false
	audio._blood_pending_count = 0
	for i: int in range(audio.BLOOD_QUEUE_SIZE):
		audio._blood_pending_msec[i] = -1.0
	audio._active_clac_players.clear()
	audio._slot_fixed_pitch.clear()
	audio.clac_stream = _make_stream()
	audio.swoosh_stream = _make_stream()
	audio.blood_stream = _make_stream()
	audio._get_time_msec = Time.get_ticks_msec
	# Reset bus swing_active à NOMINAL
	var swing_idx: int = AudioServer.get_bus_index(&"swing_active")
	if swing_idx != -1:
		AudioServer.set_bus_volume_db(swing_idx, -6.0)


func after_test() -> void:
	Engine.time_scale = _previous_time_scale
	var audio: Node = _get_audio_system()
	audio._kill_count_this_swing = 0
	audio._swoosh_fade_active = false
	audio._ducking_release_active = false
	audio._blood_pending_count = 0
	for i: int in range(audio.BLOOD_QUEUE_SIZE):
		audio._blood_pending_msec[i] = -1.0
	audio._active_clac_players.clear()
	audio._slot_fixed_pitch.clear()


# ---------------------------------------------------------------------------
# AC-AUD-13 (a/b/c/d) — Stress 5 swings 1000 frames perf budget
# ---------------------------------------------------------------------------

## Pattern stress déterministe : 5 swings overlappés via direct handler calls.
## Frame i :
##   - i % 200 == 0   : swing_started (3 swings cycliques actifs sur 1000 frames)
##   - i % 50  == 25  : enemy_killed @ position quasi-random (5 blood ambiance scheduled)
##   - i % 200 == 180 : swing_ended (close swing actif)
## Mesure isolée _physics_process audio (story-003 ticks fade/release/blood/wallrun/crossfade/music).
func _emit_5_swings_pattern(audio: Node, frame_idx: int, enemy_mock: Node3D) -> void:
	if frame_idx % 200 == 0:
		audio._on_swing_started()
	if frame_idx % 50 == 25:
		var pos: Vector3 = Vector3(
			float((frame_idx * 7) % 11) - 5.0,
			1.0,
			float((frame_idx * 13) % 7) - 3.0
		)
		enemy_mock.global_position = pos
		audio._on_enemy_killed(enemy_mock, pos)
	if frame_idx % 200 == 180:
		audio._on_swing_ended()


func test_audio_5_swings_stress_1000_frames_perf_budget() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var enemy_mock: Node3D = Node3D.new()
	enemy_mock.global_position = Vector3(5.0, 1.0, 3.0)
	add_child(enemy_mock)
	# Stabilise le frame compteur post-add_child : un physics_frame de warm-up
	await get_tree().physics_frame
	var memory_pre_kb: int = Performance.get_monitor(Performance.MEMORY_STATIC) / 1024
	# AC-AUD-13 (d) : check direct size pool stable (R-AUD-2 invariant strict — pool pré-alloué
	# jamais étendu runtime). Bypass `Performance.OBJECT_COUNT` global qui inclut les
	# AudioServer voices internes Godot non-cleanups au tick de mesure (faux positif headless).
	var pool_3d_pre: int = audio._3d_pool.size()
	var pool_2d_pre: int = audio._2d_pool.size()
	var pool_ambience_pre: int = audio._ambience_pool.size()

	# Act — 1000 frames stress
	for i: int in range(FRAMES):
		var frame_start: int = Time.get_ticks_usec()
		_emit_5_swings_pattern(audio, i, enemy_mock)
		var audio_start: int = Time.get_ticks_usec()
		audio._physics_process(0.01666)
		_audio_cpu_us[i] = Time.get_ticks_usec() - audio_start
		_frame_proxy_us[i] = Time.get_ticks_usec() - frame_start

	var memory_post_kb: int = Performance.get_monitor(Performance.MEMORY_STATIC) / 1024
	var pool_3d_post: int = audio._3d_pool.size()
	var pool_2d_post: int = audio._2d_pool.size()
	var pool_ambience_post: int = audio._ambience_pool.size()

	# Print measurements pour evidence doc (post-loop, hors mesure hot path)
	var frame_p99_us: int = _percentile_99(_frame_proxy_us)
	var audio_p99_us: int = _percentile_99(_audio_cpu_us)
	print("AUDIO_PERF_STRESS frame_p99_us=%d audio_p99_us=%d memory_delta_kb=%d pool_3d=%d pool_2d=%d pool_amb=%d" \
		% [frame_p99_us, audio_p99_us, memory_post_kb - memory_pre_kb, pool_3d_post, pool_2d_post, pool_ambience_post])

	# Assert — AC-AUD-13 (a) frame proxy p99 ≤ 16.6 ms (headless = mesure body+audio uniquement)
	var frame_p99_ms: float = float(frame_p99_us) / 1000.0
	assert_float(frame_p99_ms).override_failure_message(
		"AC-AUD-13 (a) — frame proxy p99 = %f ms > %f ms budget (60 fps locked)" \
			% [frame_p99_ms, FRAME_BUDGET_MS]
	).is_less_equal(FRAME_BUDGET_MS)

	# AC-AUD-13 (b) audio CPU p99 ≤ 0.5 ms
	var audio_p99_ms: float = float(audio_p99_us) / 1000.0
	assert_float(audio_p99_ms).override_failure_message(
		"AC-AUD-13 (b) — AudioSystem._physics_process p99 = %f ms > %f ms budget" \
			% [audio_p99_ms, AUDIO_BUDGET_MS]
	).is_less_equal(AUDIO_BUDGET_MS)

	# AC-AUD-13 (c) memory delta ≤ +100 KB
	var memory_delta_kb: int = memory_post_kb - memory_pre_kb
	assert_int(memory_delta_kb).override_failure_message(
		"AC-AUD-13 (c) — MEMORY_STATIC delta = %d KB > %d KB budget (alloc heap dans hot path ?)" \
			% [memory_delta_kb, MEMORY_BUDGET_KB]
	).is_less_equal(MEMORY_BUDGET_KB)

	# AC-AUD-13 (d) pool size invariants (R-AUD-2 — pool pré-alloué jamais étendu runtime).
	# Vérification structurelle directe au lieu de Performance.OBJECT_COUNT global qui
	# inclut les AudioServer voices internes Godot (non-cleanups instantané, faux positif).
	assert_int(pool_3d_post).override_failure_message(
		"AC-AUD-13 (d) — _3d_pool size = %d != %d pre-stress (R-AUD-2 violation : pool étendu runtime)" \
			% [pool_3d_post, pool_3d_pre]
	).is_equal(pool_3d_pre)
	assert_int(pool_2d_post).override_failure_message(
		"AC-AUD-13 (d) — _2d_pool size = %d != %d pre-stress (R-AUD-2 violation)" \
			% [pool_2d_post, pool_2d_pre]
	).is_equal(pool_2d_pre)
	assert_int(pool_ambience_post).override_failure_message(
		"AC-AUD-13 (d) — _ambience_pool size = %d != %d pre-stress (R-AUD-2 violation)" \
			% [pool_ambience_post, pool_ambience_pre]
	).is_equal(pool_ambience_pre)

	# Cleanup
	enemy_mock.queue_free()


# ---------------------------------------------------------------------------
# AC-AUD-13 (e) — Handler _on_enemy_killed isolé p99 < 100 µs Phase D.4
# ---------------------------------------------------------------------------

func test_handler_on_enemy_killed_isolated_p99_under_100_us() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var enemy_mock: Node3D = Node3D.new()
	enemy_mock.global_position = Vector3(5.0, 1.0, 3.0)
	add_child(enemy_mock)
	await get_tree().physics_frame

	# Act — 1000 calls directs _on_enemy_killed
	for i: int in range(FRAMES):
		# Reset _kill_count tous les 3 kills pour rotation pitch rangs 0/1/2/cap
		if i % 3 == 0:
			audio._kill_count_this_swing = 0
		var start: int = Time.get_ticks_usec()
		audio._on_enemy_killed(enemy_mock, enemy_mock.global_position)
		_handler_us[i] = Time.get_ticks_usec() - start

	# Assert — AC-AUD-13 (e) p99 < 100 µs
	var p99_us: int = _percentile_99(_handler_us)
	print("AUDIO_PERF_HANDLER on_enemy_killed_p99_us=%d budget_us=%d" % [p99_us, HANDLER_BUDGET_US])
	assert_int(p99_us).override_failure_message(
		"AC-AUD-13 (e) — _on_enemy_killed handler p99 = %d µs > %d µs budget Phase D.4" \
			% [p99_us, HANDLER_BUDGET_US]
	).is_less(HANDLER_BUDGET_US)

	# Cleanup
	enemy_mock.queue_free()


# ---------------------------------------------------------------------------
# AC-AUD-13 (f) — play_3d_at isolé p99 < 50 µs Phase D.4
# ---------------------------------------------------------------------------

func test_play_3d_at_isolated_p99_under_50_us() -> void:
	# Arrange
	var audio: Node = _get_audio_system()
	var stream: AudioStream = _make_stream()
	# Pré-warm pool round-robin (passe complète sur 12 slots pour stabiliser cache)
	for i: int in range(POOL_3D_SIZE):
		audio.play_3d_at(stream, Vector3(0.0, 0.0, 0.0), &"combat_kill")
	audio._active_clac_players.clear()
	audio._slot_fixed_pitch.clear()

	# Act — 1000 calls play_3d_at sur bus combat_kill (mesure round-robin pool reuse cost)
	for i: int in range(FRAMES):
		var start: int = Time.get_ticks_usec()
		audio.play_3d_at(stream, Vector3(5.0, 1.0, 3.0), &"combat_kill")
		_play_3d_us[i] = Time.get_ticks_usec() - start

	# Assert — AC-AUD-13 (f) p99 < 50 µs (pool reuse pas d'alloc)
	var p99_us: int = _percentile_99(_play_3d_us)
	print("AUDIO_PERF_PLAY3D play_3d_at_p99_us=%d budget_us=%d" % [p99_us, PLAY_3D_BUDGET_US])
	assert_int(p99_us).override_failure_message(
		"AC-AUD-13 (f) — play_3d_at p99 = %d µs > %d µs budget Phase D.4 (pool reuse pas d'alloc)" \
			% [p99_us, PLAY_3D_BUDGET_US]
	).is_less(PLAY_3D_BUDGET_US)
