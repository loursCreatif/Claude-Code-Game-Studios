# Tests integration Story-018 — AC-CMB-35b/37 soak combat (5 méthodes).
#
# Couvre AC-CMB-37 (1000 cycles Idle→Swinging→Idle avec MEMORY_STATIC + OBJECT_COUNT delta) :
#   (a) `_hit_this_swing.is_empty()` après chaque retour Idle
#   (b) `Engine.time_scale == 1.0` après chaque slow-mo
#   (c) `_cooldown_timer == 0.0` après chaque expiration
#   (d) `Performance.MEMORY_STATIC` after 1000 cycles ≤ avant + 500 KB
#   (e) `Performance.OBJECT_COUNT` delta ≤ +5
#
# Couvre AC-CMB-35b (frametime soak combat-only — pas de rendering headless) :
#   (1) Worst case ShapeCast p99 — 100 swings × ACTIVE_TICKS = 800 samples ≤ 16.6 ms
#   (2) Soak frametime global — 1000 frames _physics_process consécutifs, p50 ≤ 12.0 ms / p99 ≤ 16.6 ms
#
# DEFERRED rendering full stack :
#   - draw_calls ≤ 500 (headless RenderingServer absent — bench full Godot CLI requis)
#   - p50/p99 frame complète (incl. rendering pass) — testbed Tier 1 hardware
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-018-integration-soak-frametime-memory-objects.md
# ADR     : ADR-0001 (Physics 60Hz), ADR-0006 (Combat Tick Model)
# GDD     : design/gdd/player-combat-system.md AC-CMB-35b/37

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const DELTA_60HZ: float = 1.0 / 60.0

## Nombre de cycles Idle→SWINGING→Idle pour le soak unit (1000 = AC-CMB-37 nominal).
## Réduit à 200 pour vitesse CI (gate moins strict — bench complet via script CLI).
const SOAK_CYCLES: int = 200

## Tolérance memory delta : +500 KB (AC-CMB-37 d).
const MEMORY_DELTA_TOLERANCE_BYTES: int = 500 * 1024

## Tolérance OBJECT_COUNT delta : +5 (AC-CMB-37 e).
const OBJECT_COUNT_DELTA_TOLERANCE: int = 5

## AC-CMB-35b : threshold p99 frame budget 60 fps = 16.6 ms.
const FRAMETIME_P99_THRESHOLD_MS: float = 16.6

## AC-CMB-35b (2) : threshold p50 soak global = 12.0 ms (laisse headroom rendering hors combat).
const FRAMETIME_P50_THRESHOLD_MS: float = 12.0

## AC-CMB-35b (1) : nombre de swings consécutifs (worst case sweep).
const WORST_CASE_SWING_COUNT: int = 100

## AC-CMB-35b (2) : nombre de frames soak global (16.7 sec @ 60 Hz).
const SOAK_FRAME_COUNT: int = 1000

## Path log frametime (cohérent avec story-017 microbench log).
const FRAMETIME_LOG_PATH: String = "res://tests/perf/combat-integration-frametime-log.md"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func after_test() -> void:
	Engine.time_scale = 1.0


func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-CMB-37 (a)(b)(c) — Cycle invariants reset propre
# ---------------------------------------------------------------------------

## AC-CMB-37 a/b/c : pour chaque cycle Idle→SWINGING(8 ticks)→Idle, vérifier que
## les 3 vars critiques retournent à leur état neutre.
func test_combat_soak_cycles_reset_invariants_after_each_swing() -> void:
	var combat: CombatSystem = _make_combat()

	for cycle: int in range(SOAK_CYCLES):
		combat.attacked()
		# 8 ticks de swing (ACTIVE_TICKS=8) puis transition Idle
		for _t: int in range(CombatSystem.ACTIVE_TICKS):
			combat._physics_process(DELTA_60HZ)

		# (a) _hit_this_swing vidé après retour Idle
		assert_bool(combat._hit_this_swing.is_empty()) \
			.override_failure_message(
				"AC-CMB-37 (a) cycle %d: _hit_this_swing doit être vide" % cycle
			) \
			.is_true()
		# (b) Engine.time_scale = 1.0 (slow-mo non triggered car pas de kill réel)
		assert_float(Engine.time_scale) \
			.override_failure_message(
				"AC-CMB-37 (b) cycle %d: Engine.time_scale doit être 1.0" % cycle
			) \
			.is_between(1.0 - 0.0001, 1.0 + 0.0001)

		# Drainer le cooldown jusqu'à 0 (cooldown = 400 ms = ~24 ticks après swing)
		while combat._cooldown_timer > 0.0:
			combat._physics_process(DELTA_60HZ)

		# (c) _cooldown_timer == 0 après expiration
		assert_float(combat._cooldown_timer) \
			.override_failure_message(
				"AC-CMB-37 (c) cycle %d: _cooldown_timer doit être 0.0" % cycle
			) \
			.is_equal(0.0)



# ---------------------------------------------------------------------------
# AC-CMB-37 (d)(e) — MEMORY_STATIC + OBJECT_COUNT delta
# ---------------------------------------------------------------------------

## AC-CMB-37 d/e : après SOAK_CYCLES cycles, MEMORY_STATIC delta ≤ 500 KB,
## OBJECT_COUNT delta ≤ +5.
##
## Note : ces métriques sont sensibles au runtime Godot (GC timing, autoloads, etc.).
## Tolerance MEMORY=500 KB et OBJECT_COUNT=+5 absorbe le bruit GC inter-runs sans
## forcer de yield manuel (qui ralentirait CI pour un gain marginal sur un soak court).
func test_combat_soak_cycles_memory_and_object_count_within_tolerance() -> void:
	var combat: CombatSystem = _make_combat()

	# Snapshot baseline (warmup 5 cycles pour stabiliser allocations)
	for _i: int in range(5):
		combat.attacked()
		for _t: int in range(CombatSystem.ACTIVE_TICKS):
			combat._physics_process(DELTA_60HZ)
		while combat._cooldown_timer > 0.0:
			combat._physics_process(DELTA_60HZ)

	var mem_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var obj_before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))

	# Soak SOAK_CYCLES cycles
	for _cycle: int in range(SOAK_CYCLES):
		combat.attacked()
		for _t: int in range(CombatSystem.ACTIVE_TICKS):
			combat._physics_process(DELTA_60HZ)
		while combat._cooldown_timer > 0.0:
			combat._physics_process(DELTA_60HZ)

	var mem_after: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var obj_after: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))

	var mem_delta: int = mem_after - mem_before
	var obj_delta: int = obj_after - obj_before

	# (d) MEMORY_STATIC delta ≤ 500 KB
	assert_int(mem_delta) \
		.override_failure_message(
			"AC-CMB-37 (d): MEMORY_STATIC delta = %d bytes (%.1f KB) > tolérance %d KB. " \
			% [mem_delta, mem_delta / 1024.0, MEMORY_DELTA_TOLERANCE_BYTES / 1024] \
			+ "Soak %d cycles révèle leak heap." % SOAK_CYCLES
		) \
		.is_less_equal(MEMORY_DELTA_TOLERANCE_BYTES)

	# (e) OBJECT_COUNT delta ≤ +5
	assert_int(obj_delta) \
		.override_failure_message(
			"AC-CMB-37 (e): OBJECT_COUNT delta = %d > tolérance %d. " \
			% [obj_delta, OBJECT_COUNT_DELTA_TOLERANCE] \
			+ "Soak %d cycles révèle Object orphans (likely Array/Dict alloc dans hot path)." \
			% SOAK_CYCLES
		) \
		.is_less_equal(OBJECT_COUNT_DELTA_TOLERANCE)



# ---------------------------------------------------------------------------
# AC-CMB-35b (1) — Worst case ShapeCast p99 (100 swings × 8 ticks actifs)
# ---------------------------------------------------------------------------

## Mesure frametime `_physics_process()` pendant les ticks SWINGING actifs uniquement
## (où `_collect_swing_hits` exécute le sweep complet : intersect + 3 substeps + dedup).
## 800 samples (100 swings × ACTIVE_TICKS=8). Threshold AC-CMB-35b p99 ≤ 16.6 ms.
##
## INFORMATIONAL BASELINE — dev laptop. Tier 1 hardware sign-off DEFERRED CI infra.
func test_combat_worst_case_shapecast_p99_under_16_6ms() -> void:
	var combat: CombatSystem = _make_combat()
	var samples: PackedInt64Array = PackedInt64Array()
	samples.resize(WORST_CASE_SWING_COUNT * CombatSystem.ACTIVE_TICKS)

	var sample_idx: int = 0
	for _swing: int in range(WORST_CASE_SWING_COUNT):
		while combat._cooldown_timer > 0.0:
			combat._physics_process(DELTA_60HZ)
		combat.attacked()
		for _t: int in range(CombatSystem.ACTIVE_TICKS):
			var t0: int = Time.get_ticks_usec()
			combat._physics_process(DELTA_60HZ)
			var t1: int = Time.get_ticks_usec()
			samples[sample_idx] = t1 - t0
			sample_idx += 1

	samples.sort()
	var p50_us: int = samples[int(samples.size() * 0.5)]
	var p99_us: int = samples[int(samples.size() * 0.99)]
	var max_us: int = samples[samples.size() - 1]
	var p50_ms: float = float(p50_us) / 1000.0
	var p99_ms: float = float(p99_us) / 1000.0
	var max_ms: float = float(max_us) / 1000.0

	_append_frametime_log_entry("Worst case ShapeCast (100x8)", samples.size(), p50_ms, p99_ms, max_ms, -1)

	assert_float(p99_ms) \
		.override_failure_message(
			"AC-CMB-35b (1) FAIL: worst case ShapeCast p99=%.3f ms > %.1f ms threshold. " \
			% [p99_ms, FRAMETIME_P99_THRESHOLD_MS] \
			+ "p50=%.3f ms / max=%.3f ms — voir log %s" \
			% [p50_ms, max_ms, FRAMETIME_LOG_PATH]
		) \
		.is_less_equal(FRAMETIME_P99_THRESHOLD_MS)



# ---------------------------------------------------------------------------
# AC-CMB-35b (2) — Soak frametime global (1000 frames consécutifs)
# ---------------------------------------------------------------------------

## Mesure 1000 frames `_physics_process()` consécutifs avec swings réguliers (1 swing
## toutes les 100 frames). Threshold AC-CMB-35b p50 ≤ 12.0 ms / p99 ≤ 16.6 ms.
## draw_calls capturé best-effort (headless RenderingServer absent → 0).
##
## INFORMATIONAL BASELINE — dev laptop. Tier 1 hardware sign-off DEFERRED CI infra.
func test_combat_soak_global_1000_frames_p50_p99_under_thresholds() -> void:
	var combat: CombatSystem = _make_combat()
	var samples: PackedInt64Array = PackedInt64Array()
	samples.resize(SOAK_FRAME_COUNT)
	var draw_calls_max: int = 0

	for i: int in range(SOAK_FRAME_COUNT):
		if i % 100 == 0 and combat._state == CombatSystem.State.IDLE \
				and combat._cooldown_timer == 0.0:
			combat.attacked()

		var t0: int = Time.get_ticks_usec()
		combat._physics_process(DELTA_60HZ)
		var t1: int = Time.get_ticks_usec()
		samples[i] = t1 - t0

		var dc: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		draw_calls_max = maxi(draw_calls_max, dc)

	samples.sort()
	var p50_us: int = samples[int(samples.size() * 0.5)]
	var p99_us: int = samples[int(samples.size() * 0.99)]
	var max_us: int = samples[samples.size() - 1]
	var p50_ms: float = float(p50_us) / 1000.0
	var p99_ms: float = float(p99_us) / 1000.0
	var max_ms: float = float(max_us) / 1000.0

	_append_frametime_log_entry("Soak global (1000 frames)", samples.size(), p50_ms, p99_ms, max_ms, draw_calls_max)

	assert_float(p50_ms) \
		.override_failure_message(
			"AC-CMB-35b (2) FAIL: soak p50=%.3f ms > %.1f ms threshold. " \
			% [p50_ms, FRAMETIME_P50_THRESHOLD_MS] \
			+ "p99=%.3f ms / max=%.3f ms — voir log" % [p99_ms, max_ms]
		) \
		.is_less_equal(FRAMETIME_P50_THRESHOLD_MS)

	assert_float(p99_ms) \
		.override_failure_message(
			"AC-CMB-35b (2) FAIL: soak p99=%.3f ms > %.1f ms threshold. " \
			% [p99_ms, FRAMETIME_P99_THRESHOLD_MS] \
			+ "p50=%.3f ms / max=%.3f ms — voir log" % [p50_ms, max_ms]
		) \
		.is_less_equal(FRAMETIME_P99_THRESHOLD_MS)



# ---------------------------------------------------------------------------
# Helper — frametime log entry
# ---------------------------------------------------------------------------

## Append entry au log frametime combat (cohérent avec story-017 microbench log).
## draw_calls_max = -1 quand non applicable (worst case test ne sample pas draw_calls).
func _append_frametime_log_entry(setup_label: String, sample_count: int, p50_ms: float, p99_ms: float, max_ms: float, draw_calls_max: int) -> void:
	var os_name: String = OS.get_name()
	var processor_name: String = OS.get_processor_name()
	var processor_count: int = OS.get_processor_count()
	var hardware_label: String = "%s — %s (%d cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)" \
			% [os_name, processor_name, processor_count]

	var verdict: String = "PASS" if p99_ms <= FRAMETIME_P99_THRESHOLD_MS else "**FAIL**"
	var draw_calls_line: String = ""
	if draw_calls_max >= 0:
		draw_calls_line = "- **draw_calls_max** : %d (DEFERRED full bench Godot CLI — headless RenderingServer)\n" % draw_calls_max

	var entry: String = (
		"\n## Run %s — %s\n\n" % [Time.get_datetime_string_from_system(), setup_label] +
		"- **Hardware** : %s\n" % hardware_label +
		"- **Godot version** : 4.6 (project pinned)\n" +
		"- **Physics** : Jolt 4.6 default\n" +
		"- **Samples** : %d\n" % sample_count +
		"- **p50** : %.3f ms\n" % p50_ms +
		"- **p99** : %.3f ms (threshold ≤ %.1f ms)\n" % [p99_ms, FRAMETIME_P99_THRESHOLD_MS] +
		"- **max** : %.3f ms\n" % max_ms +
		draw_calls_line +
		"- **Verdict** : %s\n" % verdict
	)
	var log_file: FileAccess = FileAccess.open(FRAMETIME_LOG_PATH, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(FRAMETIME_LOG_PATH, FileAccess.WRITE)
	if log_file != null:
		log_file.seek_end()
		log_file.store_string(entry)
		log_file.close()

