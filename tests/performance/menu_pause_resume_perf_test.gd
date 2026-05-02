extends GdUnitTestSuite

## Story-011 — Menu Pause/Resume Performance benchmarks (F-MNU-1 budget < 100 ms).
##
## Couvre AC-MNU-40/41 BLOCKING (latency P95+P99+max < 100 ms) +
## AC-MNU-42/43 ADVISORY (zero-alloc 64 KB / 60 s + frame budget 16.6 ms).
## AC-MNU-65 ADVISORY (xvfb rendu actif) reste manuel — runner xvfb-run sur CI Linux.
##
## Méthodologie : composé `T_in + T_gsm + T_def` (exclut T_ren non-observable headless).
## Instrumentation : `Time.get_ticks_usec()` (précision µs cohérent input_to_velocity_latency_test).
##
## Pattern : drive GSM via _current_state direct + auto_free pause overlay (cohérent
## tests/integration/menu/state_sync_connect_deferred_test.gd).
##
## CI gate : BLOCKING (gates AC-MNU-40/41 — F-MNU-1 Pillar 1 budget Pause snap).
##
## Invocation safe (CLAUDE.md Godot CLI Safety) :
##   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##     --add res://tests/performance/menu_pause_resume_perf_test.gd \
##     --ignoreHeadlessMode

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")

# Budgets F-MNU-1 (Pillar 1 < 100 ms total perçu).
const SAMPLE_COUNT: int = 60
const BUDGET_LATENCY_US: int = 100_000  # 100 ms en µs (AC-MNU-40/41 BLOCKING)

# AC-MNU-42 zero-alloc gate (64 KB sur 100 cycles post-warmup).
const WARMUP_CYCLES: int = 10
const ZERO_ALLOC_CYCLES: int = 100
const MEMORY_DELTA_BUDGET_BYTES: int = 65_536  # 64 KB

# AC-MNU-43 frame budget guardrail (16.6 ms = 1 frame 60 fps).
const FRAME_BUDGET_MS: float = 16.6

var _pause_layer: CanvasLayer
var _saved_gsm_state: int


# =============================================================================
# Setup / teardown — état GSM hermétique entre tests.
# =============================================================================

func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state


func after_test() -> void:
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null
	await get_tree().process_frame


func _spawn_pause_layer() -> CanvasLayer:
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func _get_panel(layer: CanvasLayer) -> PanelContainer:
	return layer.get_node("PausePanel") as PanelContainer


## Workaround test-only : InputManager.release_enable_request erase dict mais ne
## déconnecte pas tree_exited (CONNECT_ONE_SHOT cleans up only on signal fire).
## En cycles répétés sur le même owner, le 2e request_disable error "already connected".
## Force-disconnect ici pour permettre N cycles propres dans le perf test.
## Production safety : couvert en story-008 par single show/hide pattern (no real bug exposure).
func _force_clean_input_blocker_connection(owner: Node) -> void:
	if not is_instance_valid(owner):
		return
	# Iterate signal connection list pour matcher target = InputManager.
	# bind(id) crée des Callable distincts non-équivalents par is_connected, donc on
	# scan toute la liste tree_exited et on déconnecte ceux pointant vers InputManager.
	var conns: Array = owner.get_signal_connection_list(&"tree_exited")
	for conn in conns:
		var cb: Callable = conn["callable"] as Callable
		if cb.get_object() == InputManager:
			owner.tree_exited.disconnect(cb)


## Quantile via sort + index — pattern input_to_velocity_latency_test.
func _quantile_us(samples: Array[int], q: float) -> int:
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var idx: int = int(float(sorted.size() - 1) * q)
	return sorted[idx]


func _max_us(samples: Array[int]) -> int:
	var m: int = 0
	for s: int in samples:
		if s > m:
			m = s
	return m


# =============================================================================
# AC-MNU-40 — Pause latency P95+P99+max < 100 ms (BLOCKING)
# =============================================================================

## F-MNU-1 budget total < 100 ms (Pillar 1 FLOW AVANT TOUT).
## GIVEN GSM=PLAYING + Pause Overlay instancié,
## WHEN 60× ui_cancel_pressed.emit() suivi de await process_frame (CONNECT_DEFERRED),
## THEN P95 < 100 ms ET P99 < 100 ms ET max < 100 ms.
func test_ac_mnu_40_pause_latency_p95_p99_max_under_100ms() -> void:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame  # _ready + pull resync

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-40 setup: panel must be hidden in PLAYING state pre-pause") \
		.is_false()

	var samples: Array[int] = []
	samples.resize(SAMPLE_COUNT)

	for i: int in SAMPLE_COUNT:
		# Mesure latence pause : emit → process_frame → visible == true.
		var t0: int = Time.get_ticks_usec()
		InputManager.ui_cancel_pressed.emit()
		await get_tree().process_frame  # CONNECT_DEFERRED queue flush
		await get_tree().process_frame  # 2nd frame : safety margin (deferred → visible toggle)
		var t1: int = Time.get_ticks_usec()

		assert_bool(panel.visible) \
			.override_failure_message("AC-MNU-40 iter %d: panel must be visible post-pause" % i) \
			.is_true()

		samples[i] = t1 - t0

		# Reset PLAYING via flux normal (request_resume → state_changed → _apply_visibility(false)).
		GameStateManager.request_resume()
		await get_tree().process_frame
		await get_tree().process_frame
		_force_clean_input_blocker_connection(_pause_layer)

	var p95_us: int = _quantile_us(samples, 0.95)
	var p99_us: int = _quantile_us(samples, 0.99)
	var max_us: int = _max_us(samples)

	var failure_msg: String = (
		"AC-MNU-40 FAIL : P95=%.2f ms P99=%.2f ms max=%.2f ms (budget < %.0f ms F-MNU-1)" % [
			float(p95_us) / 1000.0,
			float(p99_us) / 1000.0,
			float(max_us) / 1000.0,
			float(BUDGET_LATENCY_US) / 1000.0,
		]
	)
	assert_int(p95_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)
	assert_int(p99_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)
	assert_int(max_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)


# =============================================================================
# AC-MNU-41 — Resume latency P95+P99+max < 100 ms (BLOCKING)
# =============================================================================

## Symétrique AC-MNU-40 — GSM=PAUSED, mesure latence vers visible == false.
func test_ac_mnu_41_resume_latency_p95_p99_max_under_100ms() -> void:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame
	# Setup PAUSED via flux normal (pour que panel.visible == true initial).
	GameStateManager.request_pause()
	await get_tree().process_frame

	var panel: PanelContainer = _get_panel(_pause_layer)
	assert_bool(panel.visible) \
		.override_failure_message("AC-MNU-41 setup: panel must be visible in PAUSED state pre-resume") \
		.is_true()

	var samples: Array[int] = []
	samples.resize(SAMPLE_COUNT)

	for i: int in SAMPLE_COUNT:
		var t0: int = Time.get_ticks_usec()
		InputManager.ui_cancel_pressed.emit()
		await get_tree().process_frame
		var t1: int = Time.get_ticks_usec()

		assert_bool(panel.visible) \
			.override_failure_message("AC-MNU-41 iter %d: panel must be hidden post-resume" % i) \
			.is_false()

		samples[i] = t1 - t0

		# Reset PAUSED via flux normal (request_pause).
		_force_clean_input_blocker_connection(_pause_layer)
		GameStateManager.request_pause()
		await get_tree().process_frame
		await get_tree().process_frame

	var p95_us: int = _quantile_us(samples, 0.95)
	var p99_us: int = _quantile_us(samples, 0.99)
	var max_us: int = _max_us(samples)

	var failure_msg: String = (
		"AC-MNU-41 FAIL : P95=%.2f ms P99=%.2f ms max=%.2f ms (budget < %.0f ms F-MNU-1)" % [
			float(p95_us) / 1000.0,
			float(p99_us) / 1000.0,
			float(max_us) / 1000.0,
			float(BUDGET_LATENCY_US) / 1000.0,
		]
	)
	assert_int(p95_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)
	assert_int(p99_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)
	assert_int(max_us).override_failure_message(failure_msg).is_less(BUDGET_LATENCY_US)


# =============================================================================
# AC-MNU-42 — Zero-alloc 100 cycles post-warmup < 64 KB (ADVISORY)
# =============================================================================

## Pattern input_zero_alloc_stress_runner — warmup baseline (Theme cache settle)
## puis 100 cycles measurés, delta MEMORY_STATIC < 64 KB.
func test_ac_mnu_42_pause_resume_zero_alloc_post_warmup() -> void:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame

	# Phase 1 : warmup (Theme cache, font preload, signal table init absorbés).
	for i: int in WARMUP_CYCLES:
		await _do_pause_resume_cycle()

	var baseline_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))

	# Phase 2 : 100 cycles mesurés.
	for i: int in ZERO_ALLOC_CYCLES:
		await _do_pause_resume_cycle()

	var after_bytes: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var delta: int = after_bytes - baseline_bytes

	var failure_msg: String = (
		"AC-MNU-42 FAIL : MEMORY_STATIC delta=%d bytes après %d cycles (budget < %d bytes / 64 KB)" % [
			delta, ZERO_ALLOC_CYCLES, MEMORY_DELTA_BUDGET_BYTES,
		]
	)
	assert_int(delta).override_failure_message(failure_msg).is_less(MEMORY_DELTA_BUDGET_BYTES)


func _do_pause_resume_cycle() -> void:
	GameStateManager.request_pause()
	await get_tree().process_frame
	await get_tree().process_frame
	GameStateManager.request_resume()
	await get_tree().process_frame
	await get_tree().process_frame
	_force_clean_input_blocker_connection(_pause_layer)


# =============================================================================
# AC-MNU-43 — Pause/Resume snap < 16.6 ms frame budget (ADVISORY)
# =============================================================================

## Snap sans tween → Performance.TIME_PROCESS du frame de transition < 16.6 ms.
## Capturé après _apply_visibility(false, true) + 1 process_frame (frame résolu).
func test_ac_mnu_43_resume_no_frame_skip_under_16_6ms() -> void:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_pause_layer = _spawn_pause_layer()
	await get_tree().process_frame
	GameStateManager.request_pause()
	await get_tree().process_frame

	# Mesure frame budget sur le tick de resume.
	GameStateManager.request_resume()
	await get_tree().process_frame  # frame de transition

	var time_process_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0

	var failure_msg: String = (
		"AC-MNU-43 FAIL : TIME_PROCESS=%.2f ms post-resume (budget < %.1f ms = 1 frame 60 fps)" % [
			time_process_ms, FRAME_BUDGET_MS,
		]
	)
	assert_float(time_process_ms).override_failure_message(failure_msg).is_less(FRAME_BUDGET_MS)
