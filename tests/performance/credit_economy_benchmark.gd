# Performance benchmark Story-006 — CreditEconomy multi-kill tick + boot hydrate.
# Couvre AC-CRD-39 (multi-kill 3 + flush < 1 ms médiane N=100, P95 < 3 ms) +
# AC-CRD-40 (boot hydrate < 2 ms).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Performance.
#
# GDD   : design/gdd/credit-economy-system.md (AC-CRD-39 r3 + AC-CRD-40)
# Story : production/epics/credit-economy-system/story-006-performance-benchmark.md
# ADR   : ADR-0001 (frame budget 16.6 ms — Credit doit tenir < 6% en pire cas)
#
# Invocation safe (CLAUDE.md Godot CLI Safety) :
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add res://tests/performance/credit_economy_benchmark.gd \
#     --ignoreHeadlessMode
#
# CI gate ADVISORY : si `CI_PERFORMANCE_GATE=advisory`, les fail médian/P95
# sont remplacés par un log warning (variance runner GitHub Actions tolérée).

extends GdUnitTestSuite

const N_ITERATIONS: int = 100
const N_WARMUP: int = 10
const BUDGET_MEDIAN_MS: float = 1.0
const BUDGET_P95_MS: float = 3.0
const BUDGET_HYDRATE_MS: float = 2.0


# ---------------------------------------------------------------------------
# MockEnemy reusable — même contrat que tests/unit/credit/credit_economy_kill_source_test.gd
# ---------------------------------------------------------------------------

class MockEnemy extends Node:
	signal enemy_killed(enemy: Node, position: Vector3)


# ---------------------------------------------------------------------------
# Setup / teardown — preserve autoload state for cross-suite cleanliness
# ---------------------------------------------------------------------------

func before_test() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	GameStateManager._current_state = GameStateManager.State.PLAYING


func after_test() -> void:
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()


# ---------------------------------------------------------------------------
# AC-CRD-39 — multi-kill tick (3 kills + 1 emit batché) < 1 ms médiane N=100
# ---------------------------------------------------------------------------

func test_credit_economy_multi_kill_tick_median_under_one_ms_p95_under_three() -> void:
	# Pre-spawn 3 mocks reused across iterations — keep allocation out of the hot path.
	var mocks: Array[MockEnemy] = []
	for i in range(3):
		var m: MockEnemy = auto_free(MockEnemy.new())
		add_child(m)
		mocks.append(m)

	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(N_ITERATIONS)

	# Warmup — JIT cache, dictionary capacity, signal connection table prime.
	for w in range(N_WARMUP):
		_run_one_multi_kill_iteration(mocks)

	# Mesure stricte.
	for i in range(N_ITERATIONS):
		# Pré-iteration : reset idempotence set sinon la 2e iteration ré-incrémente
		# sur les mêmes instance_id (kills déjà crédités → silent ignore biaiserait
		# la mesure puisque le hot path ne ferait que les guards + early return).
		CreditEconomy._credited_this_run.clear()
		var t_start: int = Time.get_ticks_usec()
		_run_one_multi_kill_iteration(mocks)
		var t_elapsed_us: int = Time.get_ticks_usec() - t_start
		samples[i] = float(t_elapsed_us) / 1000.0  # microseconds → milliseconds

	samples.sort()
	var median_ms: float = samples[N_ITERATIONS / 2]
	var p95_ms: float = samples[int(N_ITERATIONS * 0.95)]
	var max_ms: float = samples[N_ITERATIONS - 1]

	print_rich("[b]AC-CRD-39 multi-kill tick perf[/b] N=%d : median=%.3f ms, p95=%.3f ms, max=%.3f ms (budget median<%.1f, p95<%.1f)" \
		% [N_ITERATIONS, median_ms, p95_ms, max_ms, BUDGET_MEDIAN_MS, BUDGET_P95_MS])

	if _is_ci_advisory():
		if median_ms >= BUDGET_MEDIAN_MS:
			print_rich("[color=yellow]⚠ ADVISORY[/color] AC-CRD-39 a : median %.3f ms ≥ %.1f ms (CI variance tolérée)" \
				% [median_ms, BUDGET_MEDIAN_MS])
		if p95_ms >= BUDGET_P95_MS:
			print_rich("[color=yellow]⚠ ADVISORY[/color] AC-CRD-39 b : p95 %.3f ms ≥ %.1f ms (CI variance tolérée)" \
				% [p95_ms, BUDGET_P95_MS])
	else:
		assert_float(median_ms) \
			.override_failure_message("AC-CRD-39 a [BLOCKING dev] : median %.3f ms must be < %.1f ms" \
				% [median_ms, BUDGET_MEDIAN_MS]) \
			.is_less(BUDGET_MEDIAN_MS)
		assert_float(p95_ms) \
			.override_failure_message("AC-CRD-39 b : p95 %.3f ms must be < %.1f ms" \
				% [p95_ms, BUDGET_P95_MS]) \
			.is_less(BUDGET_P95_MS)


## Single multi-kill iteration : 3 kills + 1 flush via _physics_process.
## Mirrors the production hot path — `_on_enemy_killed` accumulates into
## the batch queue, then `_physics_process(0.0)` flushes the single emit.
func _run_one_multi_kill_iteration(mocks: Array[MockEnemy]) -> void:
	# 3 kills accumulés dans la même tick (le pattern combat MAX_KILLS_PER_SWING=3).
	for m in mocks:
		CreditEconomy._on_enemy_killed(m, Vector3.ZERO)
	# Flush batch via tick boundary.
	CreditEconomy._physics_process(0.0)


# ---------------------------------------------------------------------------
# AC-CRD-40 — boot hydrate (load_int + assign + emit BOOT_HYDRATE) < 2 ms
# ---------------------------------------------------------------------------

func test_credit_economy_boot_hydrate_under_two_ms() -> void:
	# Pré-rempli SaveLoad avec une valeur déterministe.
	SaveLoadSystem.save_int("total_credits", 42)

	# Reset Credit pour mesurer une hydratation fraîche.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false

	var t_start: int = Time.get_ticks_usec()
	CreditEconomy._hydrate_from_save()
	var t_elapsed_ms: float = float(Time.get_ticks_usec() - t_start) / 1000.0

	print_rich("[b]AC-CRD-40 boot hydrate perf[/b] : %.3f ms (budget < %.1f ms)" \
		% [t_elapsed_ms, BUDGET_HYDRATE_MS])

	# Sanity — la valeur est bien chargée.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Pre: hydrate must restore saved value 42") \
		.is_equal(42)

	if _is_ci_advisory() and t_elapsed_ms >= BUDGET_HYDRATE_MS:
		print_rich("[color=yellow]⚠ ADVISORY[/color] AC-CRD-40 : %.3f ms ≥ %.1f ms (CI variance tolérée)" \
			% [t_elapsed_ms, BUDGET_HYDRATE_MS])
	else:
		assert_float(t_elapsed_ms) \
			.override_failure_message("AC-CRD-40 : boot hydrate %.3f ms must be < %.1f ms" \
				% [t_elapsed_ms, BUDGET_HYDRATE_MS]) \
			.is_less(BUDGET_HYDRATE_MS)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Returns true when running on a CI runner that explicitly opted into ADVISORY
## perf gating. Configured via `CI_PERFORMANCE_GATE=advisory` env var dans
## `.github/workflows/tests.yml` job perf. Dev local : env var absente → BLOCKING.
func _is_ci_advisory() -> bool:
	return OS.has_environment("CI_PERFORMANCE_GATE") \
		and OS.get_environment("CI_PERFORMANCE_GATE") == "advisory"
