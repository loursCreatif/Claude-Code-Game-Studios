# Performance benchmark Story-007 — Enemy 30 grunts frame budget + zero-alloc.
# Couvre AC-ENM-21 (frame time p99 < 16.6 ms avec 30 grunts simultanés) +
# AC-ENM-22 (MEMORY_STATIC delta < 64 KB sur N ticks — extrapolation linéaire 1000).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Performance.
#
# GDD   : design/gdd/enemy-system.md (AC-ENM-21 r2 + AC-ENM-22 r2)
# Story : production/epics/enemy-system/story-007-performance-benchmark-thirty-grunts.md
# ADR   : ADR-0001 (frame budget 16.6 ms — Enemy doit tenir ≤ 0.5 ms cumulé)
#         ADR-0006 (Combat Tick Model — pas de _physics_process Enemy MVP, Rule 10)
#
# Invocation safe (CLAUDE.md Godot CLI Safety) :
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add res://tests/performance/enemy_thirty_grunts_perf_test.gd \
#     --ignoreHeadlessMode
#
# CI gate ADVISORY : si `CI_PERFORMANCE_GATE=advisory`, les fail p99/memory sont
# remplacés par log warning (variance runner GitHub Actions tolérée).
#
# Note méthodologique : N_TICKS = 200 (~3.3 s @ 60 Hz nominal) au lieu des
# 1000 ticks GDD pour rester dans le budget temps test (~10 s tot). Le delta
# MEMORY_STATIC est extrapolé linéairement vers 1000 ticks pour l'audit AC-ENM-22.
# Si l'extrapolation dépasse 64 KB, le test échoue immédiatement — pas besoin de
# tourner 1000 frames pour détecter un leak progressif.

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRUNT_SCENE_PATH: String = "res://src/gameplay/enemy/Grunt.tscn"
const N_GRUNTS: int = 30
const N_TICKS_MEASURE: int = 200
const N_TICKS_WARMUP: int = 10
const N_TICKS_EXTRAPOLATE: int = 1000

const MEMORY_DELTA_GATE_BYTES: int = 65_536  # 64 KB AC-ENM-22
const FRAME_TIME_P99_GATE_MS: float = 16.6   # AC-ENM-21 frame budget ADR-0001
const GRID_SPACING_M: float = 3.0            # éviter overlap collision (LaserCone range = 6 m)


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _grunts: Array[Grunt] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var scene: PackedScene = load(GRUNT_SCENE_PATH)
	_grunts.clear()
	for i in N_GRUNTS:
		var g: Grunt = scene.instantiate() as Grunt
		# Grid 6×5 espacée 3 m → 30 instances disjointes (LaserCone non-overlapping
		# adjacent dans la mesure du possible — réaliste worst-case Sprint C).
		g.position = Vector3(float(i % 6) * GRID_SPACING_M, 0.0, float(i / 6) * GRID_SPACING_M)
		add_child(g)
		_grunts.append(g)
	# 2 process frames pour stabiliser : _ready + collision register.
	await get_tree().process_frame
	await get_tree().process_frame


func after_test() -> void:
	for g in _grunts:
		if is_instance_valid(g):
			g.queue_free()
	_grunts.clear()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-21 — frame time p99 < 16.6 ms avec 30 grunts (LaserCone monitoring active)
# ---------------------------------------------------------------------------

func test_thirty_grunts_frame_time_p99_under_budget() -> void:
	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(N_TICKS_MEASURE)

	# Warmup : laisse le scheduler/physics server stabiliser.
	for w in range(N_TICKS_WARMUP):
		await get_tree().process_frame

	# Mesure : delta wall-clock entre process_frame consécutifs.
	var t_prev: int = Time.get_ticks_usec()
	for i in N_TICKS_MEASURE:
		await get_tree().process_frame
		var t_now: int = Time.get_ticks_usec()
		samples[i] = float(t_now - t_prev) / 1000.0  # μs → ms
		t_prev = t_now

	samples.sort()
	var median_ms: float = samples[N_TICKS_MEASURE / 2]
	var p99_ms: float = samples[int(N_TICKS_MEASURE * 0.99)]
	var max_ms: float = samples[N_TICKS_MEASURE - 1]

	print_rich(
		"[b]AC-ENM-21 frame time 30 grunts[/b] N=%d : median=%.3f ms, p99=%.3f ms, max=%.3f ms (gate p99 < %.1f ms)" \
		% [N_TICKS_MEASURE, median_ms, p99_ms, max_ms, FRAME_TIME_P99_GATE_MS]
	)

	if _is_ci_advisory():
		if p99_ms >= FRAME_TIME_P99_GATE_MS:
			print_rich("[color=yellow]⚠ ADVISORY[/color] AC-ENM-21 : frame p99 %.3f ms ≥ %.1f ms (CI variance tolérée)" \
				% [p99_ms, FRAME_TIME_P99_GATE_MS])
	else:
		assert_float(p99_ms) \
			.override_failure_message(
				"AC-ENM-21 : frame time p99 %.3f ms must be < %.1f ms with %d grunts " \
				% [p99_ms, FRAME_TIME_P99_GATE_MS, N_GRUNTS] +
				"(median=%.3f, max=%.3f). Investiguer LaserCone monitoring saturation " \
				% [median_ms, max_ms] +
				"ou Grunt._ready() recalc."
			) \
			.is_less(FRAME_TIME_P99_GATE_MS)


# ---------------------------------------------------------------------------
# AC-ENM-22 — MEMORY_STATIC delta < 64 KB sur 1000 ticks extrapolés (no leak)
# ---------------------------------------------------------------------------

func test_thirty_grunts_memory_static_delta_under_64kb_extrapolated() -> void:
	# Warmup étendu pour dissiper allocations boot Godot (signal table, physics
	# islands, draw lists). Sans ça, baseline overestimé → faux positif.
	for w in range(20):
		await get_tree().process_frame

	var baseline: int = Performance.get_monitor(Performance.MEMORY_STATIC)

	for i in N_TICKS_MEASURE:
		await get_tree().process_frame

	var delta_bytes: int = Performance.get_monitor(Performance.MEMORY_STATIC) - baseline

	# Extrapolation linéaire vers 1000 ticks (GDD contract). Si delta < 0
	# (Godot a free du transient), on borne à 0 pour éviter math négative.
	var delta_clamped: int = maxi(delta_bytes, 0)
	var extrapolated_1000: int = int(float(delta_clamped) * (float(N_TICKS_EXTRAPOLATE) / float(N_TICKS_MEASURE)))

	print_rich(
		"[b]AC-ENM-22 memory delta 30 grunts[/b] N=%d ticks : delta=%d B, extrap_%d=%d B (gate < %d B)" \
		% [N_TICKS_MEASURE, delta_bytes, N_TICKS_EXTRAPOLATE, extrapolated_1000, MEMORY_DELTA_GATE_BYTES]
	)

	if _is_ci_advisory():
		if extrapolated_1000 >= MEMORY_DELTA_GATE_BYTES:
			print_rich("[color=yellow]⚠ ADVISORY[/color] AC-ENM-22 : extrap %d B ≥ %d B (CI variance tolérée)" \
				% [extrapolated_1000, MEMORY_DELTA_GATE_BYTES])
	else:
		assert_int(extrapolated_1000) \
			.override_failure_message(
				"AC-ENM-22 : MEMORY_STATIC delta extrapolated 1000 ticks = %d B must be < %d B " \
				% [extrapolated_1000, MEMORY_DELTA_GATE_BYTES] +
				"(raw %d B sur %d ticks, %d grunts). Identifier alloc per-tick : " \
				% [delta_bytes, N_TICKS_MEASURE, N_GRUNTS] +
				"check si Grunt._physics_process s'est réactivé (Rule 10 violation), " +
				"ou si LaserCone Area3D leak shape RID."
			) \
			.is_less(MEMORY_DELTA_GATE_BYTES)


# ---------------------------------------------------------------------------
# Bonus AC-ENM-21 sanity — Rule 10 enforced : aucun grunt n'a _physics_process actif
# ---------------------------------------------------------------------------

func test_thirty_grunts_no_physics_process_active_rule_10() -> void:
	# Rule 10 (Enemy GDD) : Grunt MVP strictement statique. set_physics_process(false)
	# au _ready(). Si ce test échoue, le budget AC-ENM-21 est invalidé : 30 ticks
	# Grunt cumulés réintroduiraient un coût per-frame non budgété.
	for g in _grunts:
		assert_bool(g.is_physics_processing()) \
			.override_failure_message(
				"Rule 10 violation : Grunt %s.is_physics_processing()=true. " \
				% str(g.name) +
				"Grunt MVP doit set_physics_process(false) au _ready()."
			) \
			.is_false()


# ---------------------------------------------------------------------------
# Bonus — sanity setup : 30 grunts spawned + alive
# ---------------------------------------------------------------------------

func test_thirty_grunts_setup_invariants() -> void:
	assert_int(_grunts.size()) \
		.override_failure_message("Setup : %d grunts attendus, got %d" % [N_GRUNTS, _grunts.size()]) \
		.is_equal(N_GRUNTS)
	for g in _grunts:
		assert_int(g._state) \
			.override_failure_message("Setup : Grunt %s doit être ALIVE post _ready" % str(g.name)) \
			.is_equal(Grunt.State.ALIVE)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns true when running on a CI runner that explicitly opted into ADVISORY
## perf gating. Configured via `CI_PERFORMANCE_GATE=advisory` env var dans
## `.github/workflows/tests.yml` job perf. Dev local : env var absente → BLOCKING.
func _is_ci_advisory() -> bool:
	return OS.has_environment("CI_PERFORMANCE_GATE") \
		and OS.get_environment("CI_PERFORMANCE_GATE") == "advisory"
