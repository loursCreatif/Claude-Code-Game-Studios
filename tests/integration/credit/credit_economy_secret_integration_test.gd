# Integration test Story-003 — CreditEconomy ↔ SecretSystem (stub) signal wiring.
# Couvre AC-CRD-34 (signal contract end-to-end via stub SecretSystem fixture).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
#
# GDD   : design/gdd/credit-economy-system.md (R-CRD-9 SYNC LOCKED Secret r1)
# Story : production/epics/credit-economy-system/story-003-source-secret-formula-tier.md
#
# Stub justification : SecretSystem epic n'est pas encore implémenté. Le test
# instancie un Node minimal exposant le contrat signal canonique
# (`secret_collected(secret_node, tier)`) et connecte directement au handler
# de CreditEconomy — exactement ce que SecretSystem fera une fois implémenté.

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# StubSecretSystem — minimal node exposing the canonical secret_collected contract
# ---------------------------------------------------------------------------

class StubSecretSystem extends Node:
	signal secret_collected(secret_node: Node, tier: int)

	## Convenience helper — emit "secret X collected at tier T".
	func collect(secret_node: Node, tier: int) -> void:
		secret_collected.emit(secret_node, tier)


class MockSecretNode extends Node:
	pass


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
	CreditEconomy._is_hydrated = true
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	# Story 004 : guard GSM PLAYING (sinon secret handler reject silent).
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)


## Spawns a stub SecretSystem wired to CreditEconomy._on_secret_collected and
## a mock SecretNode. Returns [stub, mock] for the caller to drive.
func _spawn_wired_stub_and_secret() -> Array:
	var stub: StubSecretSystem = auto_free(StubSecretSystem.new())
	add_child(stub)
	stub.secret_collected.connect(CreditEconomy._on_secret_collected)
	var mock: MockSecretNode = auto_free(MockSecretNode.new())
	add_child(mock)
	return [stub, mock]


# ---------------------------------------------------------------------------
# AC-CRD-34 — Stub SecretSystem émet (mock_node, 2) → +10, emit (N+10, +10, SECRET)
# ---------------------------------------------------------------------------

func test_credit_economy_stub_secret_system_emits_tier2_credits_ten() -> void:
	var wired: Array = _spawn_wired_stub_and_secret()
	var stub: StubSecretSystem = wired[0]
	var mock: MockSecretNode = wired[1]

	stub.collect(mock, 2)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-34: stub-emitted secret tier 2 must credit +10") \
		.is_equal(10)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-34: exactly 1 credits_changed emit expected (SYNC contract)") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.override_failure_message("AC-CRD-34: payload must be (10, +10, SECRET)") \
		.is_equal([10, 10, CreditEconomy.SourceKind.SECRET])


# ---------------------------------------------------------------------------
# Edge — stub émet plusieurs secrets distincts → each emit immédiat (pas de batching SECRET)
# ---------------------------------------------------------------------------

func test_credit_economy_stub_secret_system_multiple_secrets_each_emit_immediately() -> void:
	var wired: Array = _spawn_wired_stub_and_secret()
	var stub: StubSecretSystem = wired[0]
	var mock1: MockSecretNode = wired[1]
	var mock2: MockSecretNode = auto_free(MockSecretNode.new())
	add_child(mock2)

	stub.collect(mock1, 1)  # +5
	stub.collect(mock2, 3)  # +15

	# Pas de batching SECRET — 2 émissions distinctes attendues.
	assert_int(CreditEconomy._total_credits).is_equal(20)
	assert_int(_emit_calls.size()) \
		.override_failure_message("Story 003: pas de batching SECRET — 2 secrets = 2 emits distincts") \
		.is_equal(2)
	assert_array(_emit_calls[0]).is_equal([5, 5, CreditEconomy.SourceKind.SECRET])
	assert_array(_emit_calls[1]).is_equal([20, 15, CreditEconomy.SourceKind.SECRET])
