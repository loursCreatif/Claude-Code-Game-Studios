# Tests unitaires Story-003 — CreditEconomy Source SECRET handler /
# formula F-CRD-2 / tier validation EC-CRD-9 / Pillar 4 plancher AC-CRD-16.
# Couvre AC-CRD-12 / 13 / 14 / 15 / 16.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic.
#
# Naming : test_credit_economy_[scenario]_[expected_result] per .claude/rules/test-standards.md.
#
# GDD   : design/gdd/credit-economy-system.md (Rule 9, F-CRD-2, EC-CRD-9, AC-CRD-16)
# Story : production/epics/credit-economy-system/story-003-source-secret-formula-tier.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# MockSecret — minimal node placeholder
# ---------------------------------------------------------------------------

## Mimics the canonical contract `secret_collected(secret_node, tier)`. Used
## as the `secret_node: Node` payload in tests — the handler ignores its
## identity (no idempotence guard côté Credit, R-SEC-08 upstream).
class MockSecret extends Node:
	pass


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
	CreditEconomy._is_hydrated = true  # story-003 normal-flow assumes hydrated.
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._negative_amount_warning_count = 0
	# Story 004 : guard GSM PLAYING (sinon `_on_secret_collected` reject silent).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)


## Spawns a MockSecret child node freed at test end via auto_free.
func _spawn_mock_secret() -> MockSecret:
	var mock: MockSecret = auto_free(MockSecret.new())
	add_child(mock)
	return mock


# ---------------------------------------------------------------------------
# AC-CRD-12 — secret tier 1 → +5, payload (N+5, +5, SECRET)
# ---------------------------------------------------------------------------

func test_credit_economy_secret_tier1_credits_five_and_emits_secret_payload() -> void:
	CreditEconomy._total_credits = 7
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 1)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-12: total must increment by BASE_SECRET_CREDIT × 1 = 5") \
		.is_equal(12)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-12: exactly 1 credits_changed emit expected") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-12: payload must be (12, +5, SECRET)") \
		.is_equal([12, 5, CreditEconomy.SourceKind.SECRET])


# ---------------------------------------------------------------------------
# AC-CRD-13 — secret tier 2 → +10, payload (N+10, +10, SECRET)
# ---------------------------------------------------------------------------

func test_credit_economy_secret_tier2_credits_ten_and_emits_secret_payload() -> void:
	CreditEconomy._total_credits = 0
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 2)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-13: total must increment by BASE_SECRET_CREDIT × 2 = 10") \
		.is_equal(10)
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-13: payload must be (10, +10, SECRET)") \
		.is_equal([10, 10, CreditEconomy.SourceKind.SECRET])


# ---------------------------------------------------------------------------
# AC-CRD-14 — secret tier 3 → +15, payload (N+15, +15, SECRET)
# ---------------------------------------------------------------------------

func test_credit_economy_secret_tier3_credits_fifteen_and_emits_secret_payload() -> void:
	CreditEconomy._total_credits = 100
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 3)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-14: total must increment by BASE_SECRET_CREDIT × 3 = 15") \
		.is_equal(115)
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-14: payload must be (115, +15, SECRET)") \
		.is_equal([115, 15, CreditEconomy.SourceKind.SECRET])


# ---------------------------------------------------------------------------
# AC-CRD-15 — tier invalide (0, -1, 4, 99) → ignore silencieux + warn, 0 emit
# ---------------------------------------------------------------------------

func test_credit_economy_secret_tier_zero_ignored_no_credit_no_emit() -> void:
	CreditEconomy._total_credits = 42
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 0)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-15: tier=0 must NOT credit") \
		.is_equal(42)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-15: tier=0 must produce 0 emit") \
		.is_equal(0)


func test_credit_economy_secret_tier_negative_ignored_no_credit_no_emit() -> void:
	CreditEconomy._total_credits = 42
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, -1)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-15: tier=-1 must NOT credit") \
		.is_equal(42)
	assert_int(_emit_calls.size()).is_equal(0)


func test_credit_economy_secret_tier_four_just_over_ignored_no_credit_no_emit() -> void:
	# Edge boundary — tier=4 is the just-over case (3 is the max valid tier).
	CreditEconomy._total_credits = 42
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 4)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-15: tier=4 must NOT credit (just-over boundary)") \
		.is_equal(42)
	assert_int(_emit_calls.size()).is_equal(0)


func test_credit_economy_secret_tier_ninety_nine_ignored_no_credit_no_emit() -> void:
	CreditEconomy._total_credits = 42
	var mock: MockSecret = _spawn_mock_secret()

	CreditEconomy._on_secret_collected(mock, 99)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-15: tier=99 must NOT credit (over-bound)") \
		.is_equal(42)
	assert_int(_emit_calls.size()).is_equal(0)


# ---------------------------------------------------------------------------
# AC-CRD-16 — Pillar 4 plancher : BASE_SECRET_CREDIT × 1 >= 5 × KILL_CREDIT_GRUNT
# ---------------------------------------------------------------------------

func test_credit_economy_pillar4_floor_secret_tier1_at_least_five_grunts() -> void:
	# Design-time invariant : si un futur tuner abaisse BASE_SECRET_CREDIT à 4,
	# ce test échoue (et `_ready()` assertion crash le boot — double protection).
	var secret_tier1: int = CreditEconomy.BASE_SECRET_CREDIT * 1
	var five_grunts: int = 5 * CreditEconomy.KILL_CREDIT_GRUNT

	assert_int(secret_tier1) \
		.override_failure_message("AC-CRD-16: BASE_SECRET_CREDIT × 1 (%d) must be >= 5 × KILL_CREDIT_GRUNT (%d)" \
			% [secret_tier1, five_grunts]) \
		.is_greater_equal(five_grunts)
