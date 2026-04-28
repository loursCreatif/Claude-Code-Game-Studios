# Tests unitaires Story-002 — CreditEconomy Source KILL handler / idempotence
# / multi-kill batching.
# Couvre AC-CRD-07 / 08 / 09 / 11 / 31 / 47 / 48.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic.
#
# Naming : test_credit_economy_[scenario]_[expected_result] per .claude/rules/test-standards.md.
#
# GDD   : design/gdd/credit-economy-system.md (Rules 3 / 5 / 6 / 7 / 8)
# Story : production/epics/credit-economy-system/story-002-source-kill-idempotence-batching.md
# ADR   : adr-0001 (physics authority) + adr-0006 (combat tick model — MAX_KILLS_PER_SWING)

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# MockEnemy — minimal node exposing the canonical enemy_killed contract
# ---------------------------------------------------------------------------

## Mimics Enemy.die() emission contract :
##   signal enemy_killed(enemy: Node, position: Vector3)
## Tests connect this signal directly to CreditEconomy._on_enemy_killed.
class MockEnemy extends Node:
	signal enemy_killed(enemy: Node, position: Vector3)

	## Convenience helper — emit "I died at position p".
	func die(position: Vector3 = Vector3.ZERO) -> void:
		enemy_killed.emit(self, position)


# ---------------------------------------------------------------------------
# Signal spy — manual capture (SYNC mode)
# ---------------------------------------------------------------------------

var _emit_calls: Array = []


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Reset CreditEconomy state — autoload persists across tests.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true  # story-002 normal-flow assumes hydrated.
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._negative_amount_warning_count = 0
	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	# Drain any pending flush state so the autoload is clean for the next suite.
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()


## Wires a freshly created MockEnemy directly to CreditEconomy._on_enemy_killed.
## Returns the mock so the caller can `.die()` it. Mock is auto-freed.
func _spawn_connected_mock() -> MockEnemy:
	var mock: MockEnemy = auto_free(MockEnemy.new())
	add_child(mock)
	mock.enemy_killed.connect(CreditEconomy._on_enemy_killed)
	return mock


# ---------------------------------------------------------------------------
# AC-CRD-07 — single kill : +1, 1 emit (N+1, +1, KILL) same physics tick
# ---------------------------------------------------------------------------

func test_credit_economy_single_kill_increments_one_and_emits_kill_payload() -> void:
	# Arrange.
	CreditEconomy._total_credits = 5
	var mock: MockEnemy = _spawn_connected_mock()

	# Act — emit kill, then advance one physics frame for the flush.
	mock.die(Vector3(1.0, 0.0, 2.0))
	CreditEconomy._physics_process(0.0)

	# Assert — total mutated synchronously, emit fired in flush.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-07: total must increment by 1") \
		.is_equal(6)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-07: exactly 1 credits_changed emit expected") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-07: payload must be (6, +1, KILL)") \
		.is_equal([6, 1, CreditEconomy.SourceKind.KILL])


# ---------------------------------------------------------------------------
# AC-CRD-08 — 3 kills same tick + batching ON : +3, exactly 1 emit (N+3, +3, KILL)
# ---------------------------------------------------------------------------

func test_credit_economy_multi_kill_three_same_tick_emits_one_batched_payload() -> void:
	# Precondition — story 002 r2 B-1 default.
	assert_bool(CreditEconomy.BATCH_MULTI_KILL_EMIT) \
		.override_failure_message("Story-002 MVP requires BATCH_MULTI_KILL_EMIT=true") \
		.is_true()

	CreditEconomy._total_credits = 10
	var m1: MockEnemy = _spawn_connected_mock()
	var m2: MockEnemy = _spawn_connected_mock()
	var m3: MockEnemy = _spawn_connected_mock()

	# Three sequential kills BEFORE the next physics_frame — same tick scope.
	m1.die()
	m2.die()
	m3.die()

	# Total mutated synchronously inside each handler call.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Total must mutate intra-handler (Rule 7 comptable)") \
		.is_equal(13)
	# No emit observed YET — flush happens in next physics tick.
	assert_int(_emit_calls.size()) \
		.override_failure_message("Pre-flush: zero emit allowed (intermediates suppressed)") \
		.is_equal(0)

	CreditEconomy._physics_process(0.0)

	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-08: exactly 1 batched emit") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-08: batched payload (13, +3, KILL)") \
		.is_equal([13, 3, CreditEconomy.SourceKind.KILL])

	# Edge — second physics frame produces NO emit (pending drained).
	CreditEconomy._physics_process(0.0)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-08 edge: 2nd frame must not re-emit") \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-CRD-09 — re-emit same instance_id : ignored silently, no state change
# ---------------------------------------------------------------------------

func test_credit_economy_idempotent_re_emit_same_instance_id_no_effect() -> void:
	CreditEconomy._total_credits = 2
	var mock: MockEnemy = _spawn_connected_mock()

	mock.die()
	mock.die()  # same instance_id → must be ignored.

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-09: re-emit must not increment") \
		.is_equal(3)
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-09: only one entry in idempotence set") \
		.is_equal(1)

	CreditEconomy._physics_process(0.0)

	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-09: only the first kill emits") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([3, 1, CreditEconomy.SourceKind.KILL])


# ---------------------------------------------------------------------------
# AC-CRD-11 — MAX_KILLS_PER_SWING upstream Combat : 3 increments per tick max
# ---------------------------------------------------------------------------

func test_credit_economy_three_distinct_kills_one_tick_yields_three_increments() -> void:
	# Combat enforces MAX_KILLS_PER_SWING=3 upstream (ADR-0006). Credit Economy
	# is NOT responsible for the cap — it credits whatever Enemy emits as long
	# as instance_id is unique. This test verifies the normal-flow contract.
	CreditEconomy._total_credits = 0
	var mocks: Array[MockEnemy] = []
	for i in range(3):
		mocks.append(_spawn_connected_mock())

	for m in mocks:
		m.die()

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-11: 3 distinct kills → +3 increments") \
		.is_equal(3)

	CreditEconomy._physics_process(0.0)

	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([3, 3, CreditEconomy.SourceKind.KILL])


# ---------------------------------------------------------------------------
# AC-CRD-31 — multi-kill batched : intermediate states (N+1, N+2) NOT observable
# ---------------------------------------------------------------------------

func test_credit_economy_multi_kill_intermediate_states_not_observed_by_listener() -> void:
	CreditEconomy._total_credits = 0
	var m1: MockEnemy = _spawn_connected_mock()
	var m2: MockEnemy = _spawn_connected_mock()
	var m3: MockEnemy = _spawn_connected_mock()

	m1.die()
	m2.die()
	m3.die()
	CreditEconomy._physics_process(0.0)

	# Listener spy must have captured EXACTLY the final batched payload.
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-31: exactly 1 emit, no intermediates") \
		.is_equal(1)
	# Walk the emit log defensively for any (N+1, +1, KILL) or (N+2, +1, KILL).
	for call in _emit_calls:
		var total_seen: int = call[0]
		var delta_seen: int = call[1]
		assert_int(total_seen).is_not_equal(1)
		assert_int(total_seen).is_not_equal(2)
		# Intermediate +1 deltas are forbidden — only the batched +3 must surface.
		assert_int(delta_seen).is_equal(3)


# ---------------------------------------------------------------------------
# AC-CRD-47 — high-cap stress (~9_999_999) : no overflow, no crash
# ---------------------------------------------------------------------------

func test_credit_economy_near_cap_kill_does_not_crash() -> void:
	CreditEconomy._total_credits = 9_999_999
	var mock: MockEnemy = _spawn_connected_mock()

	mock.die()
	CreditEconomy._physics_process(0.0)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-47: 9_999_999 + 1 == 10_000_000 (Godot int 64-bit)") \
		.is_equal(10_000_000)
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([10_000_000, 1, CreditEconomy.SourceKind.KILL])


# ---------------------------------------------------------------------------
# AC-CRD-48 — two distinct enemies same tick : +2, set size 2
# ---------------------------------------------------------------------------

func test_credit_economy_two_distinct_enemies_same_tick_increment_two() -> void:
	CreditEconomy._total_credits = 0
	var m1: MockEnemy = _spawn_connected_mock()
	var m2: MockEnemy = _spawn_connected_mock()

	# Sanity — distinct instance_ids.
	assert_int(m1.get_instance_id()).is_not_equal(m2.get_instance_id())

	m1.die()
	m2.die()

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-48: 2 distinct kills → +2") \
		.is_equal(2)
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-48: idempotence set has 2 entries") \
		.is_equal(2)

	CreditEconomy._physics_process(0.0)

	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([2, 2, CreditEconomy.SourceKind.KILL])
