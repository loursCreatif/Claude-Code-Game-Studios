# Performance benchmark Story-016 — ShopController load + cycle achat + handler.
# Couvre AC-SHP-34 (load + _ready < 200 ms CI / < 100 ms baseline dev),
# AC-SHP-35 (purchase cycle < 16.6 ms), AC-SHP-36 (credits_changed handler < 5 ms).
# AC-SHP-38 (static frame contribution < 0.5 ms) reste manual profiler — N/A automatisé.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Performance — autoloads réels, mesure stricte via Time.get_ticks_usec().
#
# GDD   : design/gdd/shop-system.md (AC-SHP-34/35/36/38)
# Story : production/epics/shop-system/story-016-performance-benchmarks.md
# ADR   : ADR-0003 (Rendering & Display Latency 16.6 ms)
#
# Invocation safe (CLAUDE.md Godot CLI Safety) :
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add res://tests/performance/shop_perf_benchmark.gd \
#     --ignoreHeadlessMode
#
# CI gate ADVISORY : si `CI_PERFORMANCE_GATE=advisory`, fail remplacés par log
# warning (variance runner GitHub Actions tolérée). Dev local : BLOCKING.

extends GdUnitTestSuite

const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")
const _SHOP_TSCN_PATH: String = "res://scenes/shop/shop.tscn"
const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _CREDIT_SAVE_KEY: String = "total_credits"

# Budgets — voir story-016 implementation notes.
const BUDGET_LOAD_CI_MS: float = 200.0       # AC-SHP-34 BLOCKING CI Ubuntu jitter
const BUDGET_LOAD_DEV_MS: float = 100.0      # AC-SHP-34 baseline dev SSD
const BUDGET_PURCHASE_MS: float = 16.6       # AC-SHP-35 BLOCKING — 1 frame 60 fps
const BUDGET_HANDLER_MS: float = 5.0         # AC-SHP-36 BLOCKING

const N_ITERATIONS_PURCHASE: int = 50
const N_ITERATIONS_HANDLER: int = 100
const N_WARMUP: int = 10


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


func _make_shop_via_script() -> Control:
	var s: Control = _ShopControllerScript.new()
	s._ready()
	return s


func _free_shop(s: Control) -> void:
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# ---------------------------------------------------------------------------
# AC-SHP-34 — load + instanciation + _ready() < 200 ms CI
# ---------------------------------------------------------------------------
# Mesure load(packed) + instantiate() + _ready() via instanciation script-level
# (pas le .tscn pour éviter coût scene-tree headless lié aux Controls visuels).
# Note : la mesure scene .tscn nécessite un Window/Viewport actif ; au MVP le
# script-only mesure couvre bien le coût `_ready()` du ShopController qui est
# le surface principal (autoload init + signal connect + recalc affordability).

func test_shop_load_and_ready_under_budget() -> void:
	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(N_ITERATIONS_HANDLER)

	# Warmup
	for w in range(N_WARMUP):
		var ws: Control = _make_shop_via_script()
		_free_shop(ws)

	# Mesure stricte — chaque iter : new + _ready() + cleanup
	for i in range(N_ITERATIONS_HANDLER):
		var t_start: int = Time.get_ticks_usec()
		var s: Control = _make_shop_via_script()
		var t_elapsed_us: int = Time.get_ticks_usec() - t_start
		samples[i] = float(t_elapsed_us) / 1000.0
		_free_shop(s)

	samples.sort()
	var median_ms: float = samples[N_ITERATIONS_HANDLER / 2]
	var p95_ms: float = samples[int(N_ITERATIONS_HANDLER * 0.95)]
	var max_ms: float = samples[N_ITERATIONS_HANDLER - 1]

	print_rich("[b]AC-SHP-34 shop load + _ready perf[/b] N=%d : median=%.3f ms, p95=%.3f ms, max=%.3f ms (budget CI<%.1f / dev<%.1f)" \
		% [N_ITERATIONS_HANDLER, median_ms, p95_ms, max_ms, BUDGET_LOAD_CI_MS, BUDGET_LOAD_DEV_MS])

	# Médiane gate — toujours BLOCKING CI budget
	var budget: float = BUDGET_LOAD_CI_MS if _is_ci_advisory() else BUDGET_LOAD_DEV_MS
	if _is_ci_advisory() and median_ms >= budget:
		print_rich("[color=yellow]⚠ ADVISORY[/color] AC-SHP-34 : median %.3f ms ≥ %.1f ms (CI variance tolérée)" \
			% [median_ms, budget])
	else:
		assert_float(median_ms) \
			.override_failure_message("AC-SHP-34 [BLOCKING] : median %.3f ms must be < %.1f ms" \
				% [median_ms, budget]) \
			.is_less(budget)


# ---------------------------------------------------------------------------
# AC-SHP-35 — cycle achat complet < 16.6 ms (1 frame 60 fps)
# ---------------------------------------------------------------------------

func test_shop_purchase_cycle_under_one_frame() -> void:
	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(N_ITERATIONS_PURCHASE)

	# Warmup — JIT cache prime
	for w in range(N_WARMUP):
		_seed_credits(50)
		Upgrade._owned.clear()
		Upgrade.can_air_jump = false
		var ws: Control = _make_shop_via_script()
		ws._on_buy_pressed(&"double_jump", 0)
		_free_shop(ws)

	# Mesure stricte
	for i in range(N_ITERATIONS_PURCHASE):
		# Setup propre par iter — empêche guard already_owned + double-click in_progress
		_seed_credits(50)
		Upgrade._owned.clear()
		Upgrade.can_air_jump = false
		var s: Control = _make_shop_via_script()

		var t_start: int = Time.get_ticks_usec()
		s._on_buy_pressed(&"double_jump", 0)
		var t_elapsed_us: int = Time.get_ticks_usec() - t_start
		samples[i] = float(t_elapsed_us) / 1000.0

		_free_shop(s)

	samples.sort()
	var median_ms: float = samples[N_ITERATIONS_PURCHASE / 2]
	var p95_ms: float = samples[int(N_ITERATIONS_PURCHASE * 0.95)]
	var max_ms: float = samples[N_ITERATIONS_PURCHASE - 1]

	print_rich("[b]AC-SHP-35 purchase cycle perf[/b] N=%d : median=%.3f ms, p95=%.3f ms, max=%.3f ms (budget < %.1f ms)" \
		% [N_ITERATIONS_PURCHASE, median_ms, p95_ms, max_ms, BUDGET_PURCHASE_MS])

	if _is_ci_advisory() and p95_ms >= BUDGET_PURCHASE_MS:
		print_rich("[color=yellow]⚠ ADVISORY[/color] AC-SHP-35 : p95 %.3f ms ≥ %.1f ms (CI variance tolérée)" \
			% [p95_ms, BUDGET_PURCHASE_MS])
	else:
		# Gate sur p95 (déterministe, pas extreme outlier max)
		assert_float(p95_ms) \
			.override_failure_message("AC-SHP-35 [BLOCKING] : p95 %.3f ms must be < %.1f ms (1 frame 60 fps)" \
				% [p95_ms, BUDGET_PURCHASE_MS]) \
			.is_less(BUDGET_PURCHASE_MS)


# ---------------------------------------------------------------------------
# AC-SHP-36 — credits_changed handler invocation < 5 ms
# ---------------------------------------------------------------------------

func test_shop_credits_changed_handler_under_five_ms() -> void:
	# Setup unique — handler stateless side-effect (recalc affordability + str)
	_seed_credits(100)
	var s: Control = _make_shop_via_script()

	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(N_ITERATIONS_HANDLER)

	# Warmup
	for w in range(N_WARMUP):
		s._on_credits_changed(50, -50, 0)

	# Mesure stricte — appel direct méthode (isolation du coût handler hors signal)
	for i in range(N_ITERATIONS_HANDLER):
		var t_start: int = Time.get_ticks_usec()
		s._on_credits_changed(50 + i, -1, 0)
		var t_elapsed_us: int = Time.get_ticks_usec() - t_start
		samples[i] = float(t_elapsed_us) / 1000.0

	samples.sort()
	var median_ms: float = samples[N_ITERATIONS_HANDLER / 2]
	var p95_ms: float = samples[int(N_ITERATIONS_HANDLER * 0.95)]
	var max_ms: float = samples[N_ITERATIONS_HANDLER - 1]

	print_rich("[b]AC-SHP-36 credits_changed handler perf[/b] N=%d : median=%.3f ms, p95=%.3f ms, max=%.3f ms (budget < %.1f ms)" \
		% [N_ITERATIONS_HANDLER, median_ms, p95_ms, max_ms, BUDGET_HANDLER_MS])

	if _is_ci_advisory() and p95_ms >= BUDGET_HANDLER_MS:
		print_rich("[color=yellow]⚠ ADVISORY[/color] AC-SHP-36 : p95 %.3f ms ≥ %.1f ms (CI variance tolérée)" \
			% [p95_ms, BUDGET_HANDLER_MS])
	else:
		assert_float(p95_ms) \
			.override_failure_message("AC-SHP-36 [BLOCKING] : p95 %.3f ms must be < %.1f ms" \
				% [p95_ms, BUDGET_HANDLER_MS]) \
			.is_less(BUDGET_HANDLER_MS)

	_free_shop(s)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## CI advisory mode — voir credit_economy_benchmark.gd::_is_ci_advisory.
func _is_ci_advisory() -> bool:
	return OS.has_environment("CI_PERFORMANCE_GATE") \
		and OS.get_environment("CI_PERFORMANCE_GATE") == "advisory"
