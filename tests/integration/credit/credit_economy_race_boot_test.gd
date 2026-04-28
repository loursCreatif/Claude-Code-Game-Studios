# Tests integration Story-004 — race boot scenario (AC-CRD-51).
# Couvre la séquence temporelle stricte :
#   T0 : `level_active` reçu (connexions enemy établies + idempotence cleared)
#   T0 → T1 : `_is_hydrated == false` ; signaux `enemy_killed` rejetés silent
#   T1 : `state_changed(PLAYING)` reçu → hydrate + emit BOOT_HYDRATE 1×
#   T1+ : kills traités normalement
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
#
# GDD   : design/gdd/credit-economy-system.md (R-CRD-11 + EC-CRD-11 B-7 race boot)
# Story : production/epics/credit-economy-system/story-004-persistence-boot-hydrate-quit-save.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# MockEnemy — minimal node exposing canonical enemy_killed contract
# ---------------------------------------------------------------------------

class MockEnemy extends Node:
	signal enemy_killed(enemy: Node, position: Vector3)

	func die(position: Vector3 = Vector3.ZERO) -> void:
		enemy_killed.emit(self, position)


# ---------------------------------------------------------------------------
# Setup / teardown — fresh state for race boot scenario
# ---------------------------------------------------------------------------

var _emit_calls: Array[Array] = []


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])


func before_test() -> void:
	if FileAccess.file_exists("user://savegame.cfg"):
		DirAccess.remove_absolute("user://savegame.cfg")

	# Pre-seed savegame so hydration produces a non-zero observable value.
	SaveLoadSystem._config = ConfigFile.new()
	SaveLoadSystem._config_loaded = true
	SaveLoadSystem.save_int("total_credits", 7)

	# Reset Credit to fresh boot state.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false

	GameStateManager._current_state = GameStateManager.State.MENU

	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	if FileAccess.file_exists("user://savegame.cfg"):
		DirAccess.remove_absolute("user://savegame.cfg")


# ---------------------------------------------------------------------------
# AC-CRD-51 — full race boot scenario, 5 phases
# ---------------------------------------------------------------------------

func test_credit_economy_race_boot_pre_hydration_kills_rejected_then_post_hydration_credited() -> void:
	# === Phase a (T0) : level_active → connexions enemy établies ============
	var enemy_a: MockEnemy = auto_free(MockEnemy.new())
	var enemy_b: MockEnemy = auto_free(MockEnemy.new())
	add_child(enemy_a)
	add_child(enemy_b)
	enemy_a.add_to_group("enemies")
	enemy_b.add_to_group("enemies")

	# Trigger _on_level_active directly (LevelSystem signal handler entry point).
	CreditEconomy._on_level_active(1, Vector3.ZERO)

	# Verify connexions established.
	assert_bool(enemy_a.enemy_killed.is_connected(CreditEconomy._on_enemy_killed)) \
		.override_failure_message("Phase a: enemy_a must be connected post level_active") \
		.is_true()
	assert_bool(enemy_b.enemy_killed.is_connected(CreditEconomy._on_enemy_killed)).is_true()

	# === Phase b (T0+) : _is_hydrated still false ===========================
	assert_bool(CreditEconomy._is_hydrated) \
		.override_failure_message("Phase b: _is_hydrated must be false pre-PLAYING") \
		.is_false()

	# === Phase c (T0+) : kills before hydration → rejected silent ===========
	# GSM is still MENU at this point — even ignoring _is_hydrated, GSM guard would reject.
	# But the spec explicitly tests _is_hydrated guard : force GSM PLAYING to isolate.
	GameStateManager._current_state = GameStateManager.State.PLAYING

	enemy_a.die()
	CreditEconomy._physics_process(0.0)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Phase c: pre-hydration kill must not credit") \
		.is_equal(0)
	assert_int(_emit_calls.size()) \
		.override_failure_message("Phase c: pre-hydration kill must produce 0 emit") \
		.is_equal(0)

	# Reset GSM for phase d to keep the temporal narrative intact (T1 = PLAYING received).
	GameStateManager._current_state = GameStateManager.State.MENU

	# === Phase d (T1) : state_changed(PLAYING) → hydrate + BOOT_HYDRATE emit
	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)
	GameStateManager._current_state = GameStateManager.State.PLAYING  # mirror real GSM behavior

	assert_bool(CreditEconomy._is_hydrated) \
		.override_failure_message("Phase d: _is_hydrated must be true post-PLAYING") \
		.is_true()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Phase d: hydrated total must be 7 (saved value)") \
		.is_equal(7)
	assert_int(_emit_calls.size()) \
		.override_failure_message("Phase d: exactly 1 BOOT_HYDRATE emit expected") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([7, 0, CreditEconomy.SourceKind.BOOT_HYDRATE])

	# === Phase e (T1+) : post-hydration kills credited normally =============
	enemy_b.die()
	CreditEconomy._physics_process(0.0)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Phase e: post-hydration kill must credit +1") \
		.is_equal(8)
	assert_int(_emit_calls.size()) \
		.override_failure_message("Phase e: BOOT_HYDRATE + 1 KILL = 2 emits") \
		.is_equal(2)
	assert_array(_emit_calls[1]) \
		.is_equal([8, 1, CreditEconomy.SourceKind.KILL])
