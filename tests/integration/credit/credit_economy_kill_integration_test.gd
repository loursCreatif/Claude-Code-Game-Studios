# Tests d'intégration Story-002 — CreditEconomy + Level System + Enemy stub.
# Couvre AC-CRD-33 (Enemy → enemy_killed → Credit reçoit dans le tick) et
# AC-CRD-49 (premier `level_active` no-op vs. second `level_active` purge).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
# Naming : test_credit_economy_[scenario]_[expected_result] per .claude/rules/test-standards.md.
#
# GDD   : design/gdd/credit-economy-system.md (Rule 5 connexion event-driven, Rule 6 idempotence)
# Story : production/epics/credit-economy-system/story-002-source-kill-idempotence-batching.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# EnemyStub — minimal node satisfying the Enemy contract for integration tests.
# Mirrors what real Enemy.die() will emit downstream. Joins the canonical
# "enemies" group so LevelSystem-driven connection setup can find it.
# ---------------------------------------------------------------------------

class EnemyStub extends Node:
	signal enemy_killed(enemy: Node, position: Vector3)

	func _ready() -> void:
		add_to_group(&"enemies")

	func die(position: Vector3 = Vector3.ZERO) -> void:
		enemy_killed.emit(self, position)


# ---------------------------------------------------------------------------
# Signal spy
# ---------------------------------------------------------------------------

var _emit_calls: Array = []


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true  # story-002 normal-flow assumes hydrated.
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()


## Spawns an EnemyStub, adds it as child (so it joins SceneTree + group), and
## returns it. Auto-freed at test end.
func _spawn_enemy_stub() -> EnemyStub:
	var stub: EnemyStub = auto_free(EnemyStub.new())
	add_child(stub)
	return stub


## Returns true if the given enemy has CreditEconomy._on_enemy_killed in its
## enemy_killed connection list.
func _is_credit_connected(enemy: EnemyStub) -> bool:
	return enemy.enemy_killed.is_connected(CreditEconomy._on_enemy_killed)


# ---------------------------------------------------------------------------
# AC-CRD-33 — Enemy emits → Credit increments → credits_changed before tick end
# ---------------------------------------------------------------------------

func test_credit_economy_enemy_kill_full_signal_chain_emits_in_same_tick() -> void:
	# Arrange — stub registered in "enemies" group BEFORE level_active.
	var stub: EnemyStub = _spawn_enemy_stub()
	assert_bool(stub.is_in_group(&"enemies")) \
		.override_failure_message("Stub must join 'enemies' group on _ready") \
		.is_true()

	# Trigger Credit's connection setup (simulates Level transition).
	CreditEconomy._on_level_active(1, Vector3.ZERO)

	assert_bool(_is_credit_connected(stub)) \
		.override_failure_message("AC-CRD-33: Credit must connect to enemy after level_active") \
		.is_true()

	# Act — enemy dies, then a single physics tick flushes the batch.
	stub.die(Vector3(2.0, 0.0, 3.0))
	CreditEconomy._physics_process(0.0)

	# Assert — full chain executed.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-33: total must increment by 1") \
		.is_equal(1)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-33: exactly 1 credits_changed emit") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-33: payload (1, +1, KILL)") \
		.is_equal([1, 1, CreditEconomy.SourceKind.KILL])


# ---------------------------------------------------------------------------
# AC-CRD-49 — first level_active : no-op purge, total intact, all enemies wired
# ---------------------------------------------------------------------------

func test_credit_economy_first_level_active_purges_empty_set_and_wires_enemies() -> void:
	# Arrange — fresh boot conditions.
	CreditEconomy._total_credits = 0
	CreditEconomy._credited_this_run.clear()
	var stubs: Array[EnemyStub] = [
		_spawn_enemy_stub(),
		_spawn_enemy_stub(),
		_spawn_enemy_stub(),
	]

	# Sanity — group has at least our 3 stubs (other test artefacts may exist).
	var group_size: int = get_tree().get_nodes_in_group(&"enemies").size()
	assert_int(group_size) \
		.override_failure_message("Group must contain at least 3 spawned stubs, got %d" % group_size) \
		.is_greater_equal(3)

	# Act — first level_active of the session.
	CreditEconomy._on_level_active(1, Vector3.ZERO)

	# Assert — set still empty (a), total unchanged (b), all stubs connected (c).
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-49 (a): set must be empty after first level_active") \
		.is_equal(0)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-49 (b): total must be intact") \
		.is_equal(0)
	for stub in stubs:
		assert_bool(_is_credit_connected(stub)) \
			.override_failure_message("AC-CRD-49 (c): stub %s must be connected" % stub) \
			.is_true()


# ---------------------------------------------------------------------------
# AC-CRD-49 — second level_active : set purged, total preserved
# ---------------------------------------------------------------------------

func test_credit_economy_second_level_active_purges_populated_set_keeps_total() -> void:
	# Arrange — simulate end-of-étage-1 state.
	CreditEconomy._total_credits = 12
	CreditEconomy._credited_this_run.clear()
	# Populate with 5 dummy ids representing past-run kills.
	for i in range(5):
		CreditEconomy._credited_this_run[1000 + i] = true
	assert_int(CreditEconomy._credited_this_run.size()).is_equal(5)

	# Act — second level_active (étage 2).
	CreditEconomy._on_level_active(2, Vector3.ZERO)

	# Assert — set purged (d), total preserved (e).
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-49 (d): set must be purged on level_active") \
		.is_equal(0)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-49 (e): total must survive across étages") \
		.is_equal(12)
