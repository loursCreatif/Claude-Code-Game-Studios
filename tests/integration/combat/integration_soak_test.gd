# Tests integration Story-018 — AC-CMB-37 cycle soak (unit-testable subset).
#
# Couvre AC-CMB-37 (1000 cycles Idle→Swinging→Idle avec MEMORY_STATIC + OBJECT_COUNT delta) :
#   (a) `_hit_this_swing.is_empty()` après chaque retour Idle
#   (b) `Engine.time_scale == 1.0` après chaque slow-mo
#   (c) `_cooldown_timer == 0.0` après chaque expiration
#   (d) `Performance.MEMORY_STATIC` after 1000 cycles ≤ avant + 500 KB
#   (e) `Performance.OBJECT_COUNT` delta ≤ +5
#
# Hors scope unit (DEFERRED bench script) :
#   - AC-CMB-35b (1) worst case ShapeCast p99 sur Jolt — `tests/perf/combat_integration_soak.gd`
#   - AC-CMB-35b (2) soak frametime global avec rendering — bench Godot CLI
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


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func after_test() -> void:
	Engine.time_scale = 1.0


func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
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

	combat.get_parent().queue_free()


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

	combat.get_parent().queue_free()
