# Tests unitaires Story-001 — CreditEconomy autoload skeleton + try_spend SYNC.
# Couvre AC-CRD-01 / 02 / 03 / 04 / 05 / 06 / 17 / 18 / 19 / 28 / 29.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (story type Logic — coding-standards.md §Test Evidence).
#
# Naming : test_credit_economy_[scenario]_[expected_result] per .claude/rules/test-standards.md.
#
# GDD   : design/gdd/credit-economy-system.md
# Story : production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Signal spy — manual capture (no watch_signals API in GdUnit4 SYNC mode)
# ---------------------------------------------------------------------------

# Each test gets a fresh empty array; spy callable appends [total, delta, source].
var _emit_calls: Array = []

# AC-CRD-29 spy flag — set true synchronously by handler.
var _handler_called: bool = false


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])


func _on_credits_changed_sync_flag(_total: int, _delta: int, _source: int) -> void:
	_handler_called = true


# ---------------------------------------------------------------------------
# Setup / teardown — singleton state reset (autoload registered in project.godot)
# ---------------------------------------------------------------------------

func before_test() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._negative_amount_warning_count = 0
	_emit_calls = []
	_handler_called = false
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_sync_flag):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_sync_flag)
	# Re-enable error messages in case AC-CRD-06 disabled them.
	Engine.print_error_messages = true

# ---------------------------------------------------------------------------
# AC-CRD-01 — total_credits is always >= 0
# ---------------------------------------------------------------------------

func test_credit_economy_total_credits_never_negative() -> void:
	# Initial state.
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("Initial balance must be >= 0") \
		.is_greater_equal(0)

	# After failed over-spend, still >= 0.
	var result: bool = CreditEconomy.try_spend(9999)
	assert_bool(result) \
		.override_failure_message("Should return false when balance is 0") \
		.is_false()
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("Balance after failed spend must be >= 0") \
		.is_greater_equal(0)

	# Explicit non-zero starting balance.
	CreditEconomy._total_credits = 5
	result = CreditEconomy.try_spend(3)
	assert_bool(result).is_true()
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("Balance after valid spend must be >= 0") \
		.is_greater_equal(0)

# ---------------------------------------------------------------------------
# AC-CRD-02 — try_spend(amount > balance) returns false, no state change, no signal
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_insufficient_balance_returns_false_no_emit() -> void:
	CreditEconomy._total_credits = 10

	var result: bool = CreditEconomy.try_spend(15)

	assert_bool(result) \
		.override_failure_message("try_spend with amount > balance must return false") \
		.is_false()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("State must be unchanged") \
		.is_equal(10)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-02: no credits_changed emit allowed on failed spend") \
		.is_equal(0)

# ---------------------------------------------------------------------------
# AC-CRD-03 — try_spend(N) on balance == N: true, balance 0, signal (0, -N, SPEND_SHOP)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_exact_balance_returns_true_emits_correct_payload() -> void:
	CreditEconomy._total_credits = 10

	var result: bool = CreditEconomy.try_spend(10)

	assert_bool(result) \
		.override_failure_message("try_spend exact balance must return true") \
		.is_true()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Balance must be 0 after exact spend") \
		.is_equal(0)
	assert_int(_emit_calls.size()) \
		.override_failure_message("Exactly 1 credits_changed emit expected") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-03: payload must be (0, -10, SPEND_SHOP)") \
		.is_equal([0, -10, CreditEconomy.SourceKind.SPEND_SHOP])

# ---------------------------------------------------------------------------
# AC-CRD-04 — accounting invariant across a mixed sequence
# ---------------------------------------------------------------------------

func test_credit_economy_accounting_invariant_mixed_sequence() -> void:
	# Sequence: +5, +3, -4, +10, -8 → 0+5+3-4+10-8 = 6
	# Gains via direct mutation pending story-002 / story-003 public gain API.
	CreditEconomy._total_credits += 5
	CreditEconomy._total_credits += 3
	var spend1: bool = CreditEconomy.try_spend(4)
	CreditEconomy._total_credits += 10
	var spend2: bool = CreditEconomy.try_spend(8)

	assert_bool(spend1) \
		.override_failure_message("First spend (4 from 8) must succeed") \
		.is_true()
	assert_bool(spend2) \
		.override_failure_message("Second spend (8 from 14) must succeed") \
		.is_true()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Final balance must equal 6 (invariant)") \
		.is_equal(6)

# ---------------------------------------------------------------------------
# AC-CRD-05 — try_spend(0) is a silent no-op
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_zero_returns_true_no_emit_no_state_change() -> void:
	CreditEconomy._total_credits = 10

	var result: bool = CreditEconomy.try_spend(0)

	assert_bool(result) \
		.override_failure_message("try_spend(0) must return true") \
		.is_true()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("State must be unchanged for amount 0") \
		.is_equal(10)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-05: no signal allowed for try_spend(0)") \
		.is_equal(0)

# ---------------------------------------------------------------------------
# AC-CRD-06 — try_spend(-N) returns false, push_warning, no state change, no signal
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_negative_amount_returns_false_no_emit() -> void:
	CreditEconomy._total_credits = 10

	# Suppress expected warning's stderr output to keep test logs clean.
	# Evidence captured via _negative_amount_warning_count seam (AC-CRD-06
	# evidence — see credit_economy.gd doc comment), since GdUnit4 has no
	# push_warning interceptor.
	Engine.print_error_messages = false
	var result: bool = CreditEconomy.try_spend(-5)
	Engine.print_error_messages = true

	assert_bool(result) \
		.override_failure_message("try_spend with negative amount must return false") \
		.is_false()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("State must be unchanged for negative amount") \
		.is_equal(10)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-06: no signal allowed for negative amount") \
		.is_equal(0)
	assert_int(CreditEconomy._negative_amount_warning_count) \
		.override_failure_message("push_warning must fire exactly once for negative amount (AC-CRD-06 evidence)") \
		.is_equal(1)

	# Second negative call must increment counter again — every negative-amount
	# call emits its own push_warning (idempotence of the warning branch).
	Engine.print_error_messages = false
	var result2: bool = CreditEconomy.try_spend(-1)
	Engine.print_error_messages = true
	assert_bool(result2).is_false()
	assert_int(CreditEconomy._negative_amount_warning_count) \
		.override_failure_message("Each negative-amount call must emit its own push_warning") \
		.is_equal(2)

# ---------------------------------------------------------------------------
# AC-CRD-17 — alias of AC-CRD-03 (integration alias: exact-balance spend)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_exact_10_emits_spend_shop_payload() -> void:
	CreditEconomy._total_credits = 10

	var result: bool = CreditEconomy.try_spend(10)

	assert_bool(result).is_true()
	assert_int(CreditEconomy._total_credits).is_equal(0)
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-17: payload (0, -10, SPEND_SHOP)") \
		.is_equal([0, -10, CreditEconomy.SourceKind.SPEND_SHOP])

# ---------------------------------------------------------------------------
# AC-CRD-18 — alias of AC-CRD-02 (integration alias: over-spend by 1)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_11_on_10_returns_false_state_stable() -> void:
	CreditEconomy._total_credits = 10

	var result: bool = CreditEconomy.try_spend(11)

	assert_bool(result).is_false()
	assert_int(CreditEconomy._total_credits).is_equal(10)
	assert_int(_emit_calls.size()).is_equal(0)

# ---------------------------------------------------------------------------
# AC-CRD-19 — two sequential try_spend(3) on balance 5
# ---------------------------------------------------------------------------

func test_credit_economy_two_sequential_spends_second_fails_when_insufficient() -> void:
	CreditEconomy._total_credits = 5

	var result1: bool = CreditEconomy.try_spend(3)  # 5 -> 2, success
	var result2: bool = CreditEconomy.try_spend(3)  # 2 -> fail (3 > 2)

	assert_bool(result1) \
		.override_failure_message("First spend must succeed (5 >= 3)") \
		.is_true()
	assert_bool(result2) \
		.override_failure_message("Second spend must fail (2 < 3)") \
		.is_false()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Balance must be 2 after first spend") \
		.is_equal(2)
	# Only one signal — for the successful spend.
	assert_int(_emit_calls.size()) \
		.override_failure_message("Only the successful spend emits credits_changed") \
		.is_equal(1)

# ---------------------------------------------------------------------------
# AC-CRD-28 — credits_changed payload: total is POST-mutation, delta is signed
# ---------------------------------------------------------------------------

func test_credit_economy_signal_payload_total_is_post_mutation_delta_is_signed() -> void:
	CreditEconomy._total_credits = 15

	var result: bool = CreditEconomy.try_spend(7)

	assert_bool(result).is_true()
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Post-mutation balance must be 8") \
		.is_equal(8)
	# total == 8 (post), delta == -7 (signed spend), source == SPEND_SHOP.
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-28: payload (8, -7, SPEND_SHOP)") \
		.is_equal([8, -7, CreditEconomy.SourceKind.SPEND_SHOP])

# ---------------------------------------------------------------------------
# AC-CRD-29 — emission is SYNC: handler fires in same call stack as try_spend
# ---------------------------------------------------------------------------

func test_credit_economy_emit_is_synchronous_handler_called_before_try_spend_returns() -> void:
	CreditEconomy._total_credits = 10

	# Connect with default flags (0 = SYNC, not CONNECT_DEFERRED).
	CreditEconomy.credits_changed.connect(_on_credits_changed_sync_flag)

	var result: bool = CreditEconomy.try_spend(5)

	# No await — if SYNC, _handler_called must already be true.
	assert_bool(result) \
		.override_failure_message("try_spend must succeed") \
		.is_true()
	assert_bool(_handler_called) \
		.override_failure_message("AC-CRD-29: handler must fire synchronously inside try_spend stack") \
		.is_true()
