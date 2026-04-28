## Unit tests for CreditEconomy autoload skeleton + try_spend API.
##
## Covers: AC-CRD-01, AC-CRD-02, AC-CRD-03, AC-CRD-04, AC-CRD-05,
##         AC-CRD-06, AC-CRD-17, AC-CRD-18, AC-CRD-19, AC-CRD-28, AC-CRD-29.
##
## GDD   : design/gdd/credit-economy-system.md
## Story : production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md
## Framework: GUT 9 (GutTest)

extends GutTest

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

# Shared spy flag for AC-CRD-29 — reset in before_each to guarantee isolation.
var _handler_called: bool = false


func before_each() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._negative_amount_warning_count = 0
	_handler_called = false


func after_each() -> void:
	# Re-enable error messages in case AC-CRD-06 disabled them.
	Engine.print_error_messages = true
	# Disconnect any lingering test-local signal handlers.
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_spy):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_spy)

func _on_credits_changed_spy(_total: int, _delta: int, _source: CreditEconomy.SourceKind) -> void:
	_handler_called = true

# ---------------------------------------------------------------------------
# AC-CRD-01 — total_credits is always >= 0
# ---------------------------------------------------------------------------

func test_credit_economy_total_credits_never_negative() -> void:
	# Initial state.
	assert_true(CreditEconomy.get_total() >= 0, "Initial balance must be >= 0")

	# After failed over-spend, still >= 0.
	var result: bool = CreditEconomy.try_spend(9999)
	assert_false(result, "Should return false when balance is 0")
	assert_true(CreditEconomy.get_total() >= 0, "Balance after failed spend must be >= 0")

	# Explicit non-zero starting balance.
	CreditEconomy._total_credits = 5
	result = CreditEconomy.try_spend(3)
	assert_true(result)
	assert_true(CreditEconomy.get_total() >= 0, "Balance after valid spend must be >= 0")

# ---------------------------------------------------------------------------
# AC-CRD-02 — try_spend(amount > balance) returns false, no state change, no signal
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_insufficient_balance_returns_false_no_emit() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(15)

	assert_false(result, "try_spend with amount > balance must return false")
	assert_eq(CreditEconomy._total_credits, 10, "State must be unchanged")
	assert_signal_emit_count(CreditEconomy, "credits_changed", 0)

# ---------------------------------------------------------------------------
# AC-CRD-03 — try_spend(N) on balance == N: true, balance 0, signal (0, -N, SPEND_SHOP)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_exact_balance_returns_true_emits_correct_payload() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(10)

	assert_true(result, "try_spend exact balance must return true")
	assert_eq(CreditEconomy._total_credits, 0, "Balance must be 0 after exact spend")
	assert_signal_emit_count(CreditEconomy, "credits_changed", 1)
	assert_signal_emitted_with_parameters(
		CreditEconomy,
		"credits_changed",
		[0, -10, CreditEconomy.SourceKind.SPEND_SHOP]
	)

# ---------------------------------------------------------------------------
# AC-CRD-04 — accounting invariant across a mixed sequence
# ---------------------------------------------------------------------------

func test_credit_economy_accounting_invariant_mixed_sequence() -> void:
	# Sequence: +5, +3, -4, +10, -8
	# Expected final: 0 + 5 + 3 - 4 + 10 - 8 = 6
	#
	# NOTE: gains are simulated via direct mutation `_total_credits += N` because
	# the public gain API (`add_credits` / KILL + SECRET handlers) is implemented
	# in story-002 and story-003. When those land, this test should be migrated
	# to use the public gain entry points so the invariant is verified end-to-end
	# rather than against the private state seam.
	CreditEconomy._total_credits += 5   # +5 gain (story-002 substitute)
	CreditEconomy._total_credits += 3   # +3 gain (story-002 substitute)
	var spend1: bool = CreditEconomy.try_spend(4)  # -4
	CreditEconomy._total_credits += 10  # +10 gain (story-002 substitute)
	var spend2: bool = CreditEconomy.try_spend(8)  # -8

	assert_true(spend1, "First spend (4 from 8) must succeed")
	assert_true(spend2, "Second spend (8 from 14) must succeed")
	assert_eq(CreditEconomy._total_credits, 6, "Final balance must equal 6 (invariant)")

# ---------------------------------------------------------------------------
# AC-CRD-05 — try_spend(0) is a silent no-op
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_zero_returns_true_no_emit_no_state_change() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(0)

	assert_true(result, "try_spend(0) must return true")
	assert_eq(CreditEconomy._total_credits, 10, "State must be unchanged for amount 0")
	assert_signal_emit_count(CreditEconomy, "credits_changed", 0)

# ---------------------------------------------------------------------------
# AC-CRD-06 — try_spend(-N) returns false, push_warning, no state change, no signal
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_negative_amount_returns_false_no_emit() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	# Suppress the expected warning's stderr output to keep test logs clean.
	# Evidence that push_warning fired is captured via _negative_amount_warning_count
	# (AC-CRD-06 seam — see credit_economy.gd doc comment), since GUT does not
	# expose a push_warning interceptor.
	Engine.print_error_messages = false
	var result: bool = CreditEconomy.try_spend(-5)
	Engine.print_error_messages = true

	assert_false(result, "try_spend with negative amount must return false")
	assert_eq(CreditEconomy._total_credits, 10, "State must be unchanged for negative amount")
	assert_signal_emit_count(CreditEconomy, "credits_changed", 0)
	assert_eq(
		CreditEconomy._negative_amount_warning_count,
		1,
		"push_warning must fire exactly once for a negative amount (AC-CRD-06 evidence)"
	)

	# Second negative call must increment the counter again (idempotence of the
	# warning branch — every negative-amount call emits its own push_warning).
	Engine.print_error_messages = false
	var result2: bool = CreditEconomy.try_spend(-1)
	Engine.print_error_messages = true
	assert_false(result2)
	assert_eq(
		CreditEconomy._negative_amount_warning_count,
		2,
		"Each negative-amount call must emit its own push_warning"
	)

# ---------------------------------------------------------------------------
# AC-CRD-17 — alias of AC-CRD-03 (integration alias: exact-balance spend)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_exact_10_emits_spend_shop_payload() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(10)

	assert_true(result)
	assert_eq(CreditEconomy._total_credits, 0)
	assert_signal_emit_count(CreditEconomy, "credits_changed", 1)
	assert_signal_emitted_with_parameters(
		CreditEconomy,
		"credits_changed",
		[0, -10, CreditEconomy.SourceKind.SPEND_SHOP]
	)

# ---------------------------------------------------------------------------
# AC-CRD-18 — alias of AC-CRD-02 (integration alias: over-spend by 1)
# ---------------------------------------------------------------------------

func test_credit_economy_try_spend_11_on_10_returns_false_state_stable() -> void:
	CreditEconomy._total_credits = 10
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(11)

	assert_false(result)
	assert_eq(CreditEconomy._total_credits, 10)
	assert_signal_emit_count(CreditEconomy, "credits_changed", 0)

# ---------------------------------------------------------------------------
# AC-CRD-19 — two sequential try_spend(3) on balance 5
# ---------------------------------------------------------------------------

func test_credit_economy_two_sequential_spends_second_fails_when_insufficient() -> void:
	CreditEconomy._total_credits = 5
	watch_signals(CreditEconomy)

	var result1: bool = CreditEconomy.try_spend(3)  # 5 -> 2, should succeed
	var result2: bool = CreditEconomy.try_spend(3)  # 2 -> fail, 3 > 2

	assert_true(result1, "First spend must succeed (5 >= 3)")
	assert_false(result2, "Second spend must fail (2 < 3)")
	assert_eq(CreditEconomy._total_credits, 2, "Balance must be 2 after first spend")
	# Only one signal emitted (for the successful spend).
	assert_signal_emit_count(CreditEconomy, "credits_changed", 1)

# ---------------------------------------------------------------------------
# AC-CRD-28 — credits_changed payload: total is POST-mutation, delta is signed
# ---------------------------------------------------------------------------

func test_credit_economy_signal_payload_total_is_post_mutation_delta_is_signed() -> void:
	CreditEconomy._total_credits = 15
	watch_signals(CreditEconomy)

	var result: bool = CreditEconomy.try_spend(7)

	assert_true(result)
	assert_eq(CreditEconomy._total_credits, 8, "Post-mutation balance must be 8")
	# total == 8 (post), delta == -7 (signed spend), source == SPEND_SHOP
	assert_signal_emitted_with_parameters(
		CreditEconomy,
		"credits_changed",
		[8, -7, CreditEconomy.SourceKind.SPEND_SHOP]
	)

# ---------------------------------------------------------------------------
# AC-CRD-29 — emission is SYNC: handler fires in same call stack as try_spend
# ---------------------------------------------------------------------------

func test_credit_economy_emit_is_synchronous_handler_called_before_try_spend_returns() -> void:
	CreditEconomy._total_credits = 10

	# Connect with default flags (0 = SYNC, not CONNECT_DEFERRED).
	CreditEconomy.credits_changed.connect(_on_credits_changed_spy)

	var result: bool = CreditEconomy.try_spend(5)

	# No await here — if SYNC, _handler_called must already be true.
	assert_true(result, "try_spend must succeed")
	assert_true(
		_handler_called,
		"Handler must be called synchronously within the same try_spend call stack (AC-CRD-29)"
	)

	CreditEconomy.credits_changed.disconnect(_on_credits_changed_spy)
