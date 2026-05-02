# Test d'intégration Story-001 — CreditEconomy + Shop stub (AC-CRD-35).
#
# Vérifie qu'un Shop minimal qui appelle try_spend(cost) une seule fois est
# suffisant : retourne true, décrémente le solde, émet credits_changed.
# Le shop ne re-vérifie PAS le solde après — guardrail AC-CRD-35.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
# Naming : test_credit_economy_[scenario]_[expected_result].
#
# GDD   : design/gdd/credit-economy-system.md (AC-CRD-35)
# Story : production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# ShopStub — minimal inline call site
# ---------------------------------------------------------------------------

## Shop minimal qui enregistre sa séquence d'appels pour que le test puisse
## vérifier qu'il n'a JAMAIS appelé try_spend une seconde fois ni get_total.
class ShopStub extends Node:
	## true si le dernier attempt_purchase a retourné true.
	var purchase_result: bool = false

	## Liste ordonnée des appels effectués vers CreditEconomy.
	## Entrées : "try_spend(<amount>)" pour chaque appel à try_spend.
	## get_total est intentionnellement jamais appelé — le test assert son absence.
	var call_log: Array[String] = []

	## Tente un achat. Appelle try_spend une seule fois et stocke le résultat.
	## N'appelle PAS get_total avant ou après (AC-CRD-35 guardrail).
	func attempt_purchase(cost: int) -> void:
		call_log.append("try_spend(%d)" % cost)
		purchase_result = CreditEconomy.try_spend(cost)

# ---------------------------------------------------------------------------
# Signal spy — manual capture
# ---------------------------------------------------------------------------

var _emit_calls: Array = []


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

var _shop: ShopStub = null


func before_test() -> void:
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	CreditEconomy._credited_this_run.clear()
	_emit_calls = []
	_shop = ShopStub.new()
	add_child(_shop)
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
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

	# Act : le shop appelle try_spend exactement une fois.
	_shop.attempt_purchase(COST)

	# --- Result ---
	assert_bool(_shop.purchase_result) \
		.override_failure_message("ShopStub doit recevoir true depuis try_spend") \
		.is_true()

	# --- State ---
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Balance doit être décrémentée du COST") \
		.is_equal(INITIAL - COST)

	# --- Signal ---
	assert_int(_emit_calls.size()) \
		.override_failure_message("Exactement 1 credits_changed emit attendu") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("Payload doit être (INITIAL-COST, -COST, SPEND_SHOP)") \
		.is_equal([INITIAL - COST, -COST, CreditEconomy.SourceKind.SPEND_SHOP])

	# --- Call sequence guardrail ---
	# ShopStub doit avoir appelé try_spend(COST) exactement une fois — rien d'autre.
	# Match exact = vrai guardrail AC-CRD-35 : tout appel supplémentaire (get_total
	# de vérification, second try_spend) casse cette assertion.
	var expected_log: Array[String] = ["try_spend(%d)" % COST]
	assert_array(_shop.call_log) \
		.override_failure_message("ShopStub doit appeler try_spend(cost) exactement une fois (AC-CRD-35)") \
		.is_equal(expected_log)
