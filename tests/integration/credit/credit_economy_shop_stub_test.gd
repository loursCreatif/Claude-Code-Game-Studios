## Integration test for CreditEconomy + Shop stub (AC-CRD-35).
##
## Verifies that a minimal Shop call site using try_spend(cost) once is
## sufficient: returns true, decrements balance, emits credits_changed —
## the shop does NOT need a second verification call.
##
## GDD   : design/gdd/credit-economy-system.md (AC-CRD-35)
## Story : production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md
## Framework: GUT 9 (GutTest)

extends GutTest

# ---------------------------------------------------------------------------
# ShopStub — minimal inline call site
# ---------------------------------------------------------------------------
## Minimal shop that records its own call sequence so the test can verify
## it never called try_spend a second time and never called get_total.
class ShopStub extends Node:
	## true if the last attempt_purchase returned true.
	var purchase_result: bool = false

	## Ordered list of calls made: each entry is a String.
	## Entries: "try_spend(<amount>)" for each call to CreditEconomy.try_spend.
	## get_total is intentionally never called — test asserts its absence.
	var call_log: Array[String] = []

	## Performs a purchase attempt. Calls try_spend once and stores result.
	## Does NOT call get_total before or after (AC-CRD-35 guardrail).
	func attempt_purchase(cost: int) -> void:
		call_log.append("try_spend(%d)" % cost)
		purchase_result = CreditEconomy.try_spend(cost)

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

var _shop: ShopStub = null

func before_each() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	CreditEconomy._credited_this_run.clear()
	_shop = ShopStub.new()
	add_child(_shop)


func after_each() -> void:
	if is_instance_valid(_shop):
		_shop.queue_free()
	_shop = null

# ---------------------------------------------------------------------------
# AC-CRD-35 — Shop stub calls try_spend once; sufficient → true + decrement + signal
# ---------------------------------------------------------------------------

func test_credit_economy_shop_stub_try_spend_once_sufficient_decrements_and_signals() -> void:
	const INITIAL: int = 50
	const COST: int = 30

	CreditEconomy._total_credits = INITIAL
	watch_signals(CreditEconomy)

	# Act: shop calls try_spend exactly once.
	_shop.attempt_purchase(COST)

	# --- Result assertions ---
	assert_true(_shop.purchase_result, "ShopStub must receive true from try_spend")

	# --- State assertions ---
	assert_eq(
		CreditEconomy._total_credits,
		INITIAL - COST,
		"Balance must be decremented by cost"
	)

	# --- Signal assertions ---
	assert_signal_emit_count(CreditEconomy, "credits_changed", 1)
	assert_signal_emitted_with_parameters(
		CreditEconomy,
		"credits_changed",
		[INITIAL - COST, -COST, CreditEconomy.SourceKind.SPEND_SHOP]
	)

	# --- Call sequence guardrail ---
	# ShopStub must have called try_spend(COST) exactly once and nothing else.
	# Exact-content match is the real guardrail for AC-CRD-35: any extra call
	# (a get_total verification, a second try_spend) breaks this assertion.
	var expected_log: Array[String] = ["try_spend(%d)" % COST]
	assert_eq(
		_shop.call_log,
		expected_log,
		"ShopStub must call try_spend(cost) exactly once and make no other calls (AC-CRD-35)"
	)
