# Tests unitaires Story-013 — CombatSystem slow-mo wall-clock + Callable injection.
#
# Couvre AC-1 à AC-6 (cf. story-013) + AC-CMB-19/24/25 + Rule 13 Formula 7 :
#   AC-1 : injection wall-clock baseline (mock retourne 1000 au 1er kill).
#   AC-2 : restore à 50 ms exact (gate `>= SLOW_MO_DURATION_MS` strict).
#   AC-3 : multi-kill idempotence (1× assignment seulement).
#   AC-4 : external time_scale=0.5 override → écrasé à 0.3, restore à 1.0 (pas 0.5).
#   AC-5 : accessibility branch C — `_reduce_motion_disable_slow_mo == true` → no-op.
#   AC-6 : restore depuis `_physics_process` (couvert indirectement via `_check_slow_mo_restore`).
#
# Pattern test critique : teardown obligatoire `Engine.time_scale = 1.0` en `after_test()`
# (contamination cross-test si _trigger_slow_mo_if_first_kill mute time_scale et oublie restore).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-013-slow-mo-wall-clock-callable-injection.md
# ADR     : ADR-0006 D-5 (slow-mo Callable injection), ADR-0001 (restore _physics_process)
# GDD     : design/gdd/player-combat-system.md AC-CMB-19/24/25

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const TIME_SCALE_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func after_test() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


## Builder pour mock `_get_time_msec` retournant des valeurs séquentielles depuis un array.
class TimeMock extends RefCounted:
	var values: Array[int] = []
	var index: int = 0

	func get_msec() -> int:
		var v: int = values[index] if index < values.size() else values[values.size() - 1]
		index += 1
		return v


# ---------------------------------------------------------------------------
# AC-1 — Injection wall-clock baseline
# ---------------------------------------------------------------------------

## AC-1 : `_get_time_msec` mocké retourne 1000 au 1er kill →
## time_scale=0.3, _slow_mo_active=true, _slow_mo_start_msec=1000.
func test_combat_trigger_slow_mo_first_kill_sets_engine_time_scale() -> void:
	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Act
	combat._trigger_slow_mo_if_first_kill()

	# Assert
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-1: time_scale doit être SLOW_MO_SCALE=0.3") \
		.is_between(
			CombatSystem.SLOW_MO_SCALE - TIME_SCALE_TOLERANCE,
			CombatSystem.SLOW_MO_SCALE + TIME_SCALE_TOLERANCE
		)
	assert_bool(combat._slow_mo_active).is_true()
	assert_int(combat._slow_mo_start_msec).is_equal(1000)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Restore at exact 50ms wall-clock
# ---------------------------------------------------------------------------

## AC-2 : à 1030 ms (delta 30 < 50) → time_scale reste 0.3 ;
## à 1050 ms (delta 50 == SLOW_MO_DURATION_MS) → restore à 1.0.
func test_combat_check_slow_mo_restore_at_exact_50ms_threshold() -> void:
	var combat: CombatSystem = _make_combat()

	# Setup slow-mo actif starting at 1000
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000, 1030, 1050]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	combat._trigger_slow_mo_if_first_kill()  # consumes 1000
	assert_int(combat._slow_mo_start_msec).is_equal(1000)

	# Act 1 : check at 1030 ms (elapsed 30 ms < 50)
	combat._check_slow_mo_restore()  # consumes 1030

	# Assert 1 : pas encore restore
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-2: à elapsed=30ms, time_scale doit rester 0.3") \
		.is_between(
			CombatSystem.SLOW_MO_SCALE - TIME_SCALE_TOLERANCE,
			CombatSystem.SLOW_MO_SCALE + TIME_SCALE_TOLERANCE
		)
	assert_bool(combat._slow_mo_active).is_true()

	# Act 2 : check at 1050 ms (elapsed 50 ms == SLOW_MO_DURATION_MS)
	combat._check_slow_mo_restore()  # consumes 1050

	# Assert 2 : restore à 1.0
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-2: à elapsed=50ms exact, time_scale doit être restauré à 1.0") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-2: _slow_mo_active doit être false post-restore") \
		.is_false()
	assert_int(combat._slow_mo_start_msec).is_equal(0)

	combat.get_parent().queue_free()


## AC-2 edge : à 1049 ms (49 < 50 strict) → time_scale reste 0.3.
func test_combat_check_slow_mo_restore_at_49ms_strict_gate() -> void:
	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000, 1049]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	combat._trigger_slow_mo_if_first_kill()
	combat._check_slow_mo_restore()

	# Pas encore restore (gate `>= 50` strict)
	assert_bool(combat._slow_mo_active).is_true()
	assert_float(Engine.time_scale) \
		.is_between(
			CombatSystem.SLOW_MO_SCALE - TIME_SCALE_TOLERANCE,
			CombatSystem.SLOW_MO_SCALE + TIME_SCALE_TOLERANCE
		)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Multi-kill idempotence
# ---------------------------------------------------------------------------

## AC-3 : 5 kills consécutifs → `_trigger_slow_mo_if_first_kill` 1× seulement.
## time_scale assignée 1×, _slow_mo_start_msec figé au 1er kill.
func test_combat_trigger_slow_mo_idempotent_across_multiple_kills() -> void:
	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	# Si triggered N fois, on devrait consommer N entries.
	# Si idempotent, on consomme 1 seule entry.
	time_mock.values = [1000, 2000, 3000, 4000, 5000]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Act — 5 kills "simultanés"
	for _i: int in range(5):
		combat._trigger_slow_mo_if_first_kill()

	# Assert
	assert_int(combat._slow_mo_start_msec) \
		.override_failure_message("AC-3: _slow_mo_start_msec doit être 1000 (1er kill seulement)") \
		.is_equal(1000)
	assert_int(time_mock.index) \
		.override_failure_message("AC-3: _get_time_msec consommé 1× seulement (idempotence)") \
		.is_equal(1)
	assert_bool(combat._slow_mo_active).is_true()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — External time_scale=0.5 override
# ---------------------------------------------------------------------------

## AC-4 : Engine.time_scale=0.5 (debug) → 1er kill l'écrase à 0.3.
## Restore va vers 1.0 (pas 0.5 — Combat ne mémorise pas l'état pré-slow-mo).
func test_combat_external_time_scale_overridden_by_slow_mo_then_restored_to_one() -> void:
	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000, 1100]  # 1100 - 1000 = 100 > 50 → restore
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Externe : someone mute time_scale (debug)
	Engine.time_scale = 0.5

	# Act 1 : 1er kill → écrase à 0.3
	combat._trigger_slow_mo_if_first_kill()
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-4: 1er kill doit écraser time_scale=0.5 à 0.3") \
		.is_between(
			CombatSystem.SLOW_MO_SCALE - TIME_SCALE_TOLERANCE,
			CombatSystem.SLOW_MO_SCALE + TIME_SCALE_TOLERANCE
		)

	# Act 2 : restore après 100 ms
	combat._check_slow_mo_restore()

	# Assert : restore à 1.0 (pas 0.5)
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-4: restore doit aller à 1.0 (pas 0.5)") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Accessibility branch C : reduce_motion disable
# ---------------------------------------------------------------------------

## AC-5 : `_reduce_motion_disable_slow_mo == true` → 5 kills consécutifs n'altèrent
## jamais Engine.time_scale (reste à 1.0).
func test_combat_reduce_motion_disables_slow_mo_for_all_kills() -> void:
	var combat: CombatSystem = _make_combat()
	combat._reduce_motion_disable_slow_mo = true

	var time_mock: TimeMock = TimeMock.new()
	time_mock.values = [1000, 2000, 3000, 4000, 5000]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	# Act — 5 kills
	for _i: int in range(5):
		combat._trigger_slow_mo_if_first_kill()

	# Assert
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-5: time_scale doit rester 1.0 quand reduce_motion ON") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-5: _slow_mo_active doit rester false") \
		.is_false()
	assert_int(time_mock.index) \
		.override_failure_message("AC-5: _get_time_msec PAS appelé (early return avant call)") \
		.is_equal(0)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-6 — _check_slow_mo_restore appelé depuis _physics_process (intégration)
# ---------------------------------------------------------------------------

## AC-6 : _physics_process appelle _check_slow_mo_restore en premier (ordre déterministe).
## Vérifié : déclencher slow-mo, simuler un tick avec time_mock indiquant 100 ms écoulés
## → après _physics_process, time_scale = 1.0.
func test_combat_physics_process_triggers_slow_mo_restore() -> void:
	var combat: CombatSystem = _make_combat()
	var time_mock: TimeMock = TimeMock.new()
	# 1er call: trigger (1000), 2e call: check_restore en _physics_process (1100).
	time_mock.values = [1000, 1100]
	combat._get_time_msec = Callable(time_mock, "get_msec")

	combat._trigger_slow_mo_if_first_kill()
	assert_bool(combat._slow_mo_active).is_true()

	# Act — _physics_process doit appeler _check_slow_mo_restore
	combat._physics_process(1.0 / 60.0)

	# Assert
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-6: _physics_process doit appeler _check_slow_mo_restore") \
		.is_false()
	assert_float(Engine.time_scale) \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)

	combat.get_parent().queue_free()
