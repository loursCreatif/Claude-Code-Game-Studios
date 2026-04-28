# Unit test Story-005 — Purchase cycle 6 étapes déterministes SYNC.
# Couvre AC-SHP-6/7/8/9/11 + EC-SHP-2 + EC-SHP-23 atomicity lint statique.
# AC-SHP-10 (BuyButton.disabled UI) : déférée — scene-attach context absent unit.
# AC-SHP-48 (mock UpgradeSystem) : utilise real Upgrade autoload (chain unblocked).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare ShopController + Upgrade real autoload.
extends GdUnitTestSuite

const _CREDIT_SAVE_KEY: String = "total_credits"
const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


# =============================================================================
# Setup / Teardown — reset save state + autoload state
# =============================================================================

func before_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	# Reset Upgrade autoload (mutable singleton)
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


func _make_shop() -> Control:
	var s: Control = _ShopControllerScript.new()
	s._ready()
	return s


# =============================================================================
# AC-SHP-6 — try_spend(40) appelé 1 fois pour dash_horizontal affordable
# =============================================================================

## GIVEN solde 50 (>= 40 cost dash_horizontal),
## WHEN _on_buy_pressed(&"dash_horizontal", 1),
## THEN total_credits passe de 50 à 10 (try_spend(40) executé).
func test_purchase_cycle_dash_horizontal_affordable_spends_40() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()
	var initial: int = CreditEconomy.get_total()

	# Act
	s._on_buy_pressed(&"dash_horizontal", 1)

	# Assert — try_spend(40) appliqué
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-6: total après try_spend(40) attendu %d, obtenu %d" % [initial - 40, CreditEconomy.get_total()]) \
		.is_equal(initial - 40)

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-7 — try_spend true → _owned_upgrades.has(id) immédiatement (no await)
# =============================================================================

## GIVEN solde 30 >= 20 cost double_jump,
## WHEN _on_buy_pressed(&"double_jump", 0),
## THEN _owned_upgrades.has(&"double_jump") true post-call (atomic SYNC).
func test_purchase_cycle_owned_upgrades_marked_immediately_after_spend() -> void:
	# Arrange
	_seed_credits(30)
	var s: Control = _make_shop()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_bool(&"double_jump" in owned) \
		.override_failure_message("AC-SHP-7: double_jump doit être owned immédiatement post-_on_buy_pressed (no await)") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-8 — séquencement save AVANT apply (call order log)
# =============================================================================

## GIVEN solde suffisant,
## WHEN cycle complet exécuté,
## THEN _call_order_log.find("save") < find("apply") (5b avant 5c — EC-SHP-16/23).
func test_purchase_cycle_save_called_before_apply_upgrade() -> void:
	# Arrange
	_seed_credits(30)
	var s: Control = _make_shop()
	s.reset_call_order_log_for_test()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var log: Array[String] = s.get_call_order_log()
	var save_idx: int = log.find("save")
	var apply_idx: int = log.find("apply")
	assert_int(save_idx) \
		.override_failure_message("AC-SHP-8: 'save' attendu dans call_order_log, log=%s" % str(log)) \
		.is_greater_equal(0)
	assert_int(apply_idx) \
		.override_failure_message("AC-SHP-8: 'apply' attendu dans call_order_log, log=%s" % str(log)) \
		.is_greater_equal(0)
	assert_bool(save_idx < apply_idx) \
		.override_failure_message("AC-SHP-8: save_idx (%d) doit être < apply_idx (%d) — ordre 5b→5c, log=%s" % [save_idx, apply_idx, str(log)]) \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-9 — Upgrade.apply_upgrade(id) appelé exactement 1 fois (real autoload)
# =============================================================================

## GIVEN solde 50 + cycle dash_horizontal,
## WHEN _on_buy_pressed,
## THEN Upgrade.is_owned(&"dash_horizontal") true ET Upgrade.can_dash true.
func test_purchase_cycle_apply_upgrade_called_real_autoload_dash() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()

	# Act
	s._on_buy_pressed(&"dash_horizontal", 1)

	# Assert — real Upgrade autoload state mutated
	assert_bool(Upgrade.is_owned(&"dash_horizontal")) \
		.override_failure_message("AC-SHP-9: Upgrade.is_owned(dash_horizontal) attendu true") \
		.is_true()
	assert_bool(Upgrade.can_dash) \
		.override_failure_message("AC-SHP-9: Upgrade.can_dash attendu true post-apply") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-11 — solde insuffisant → aucune mutation (early DISABLED guard)
# =============================================================================

## GIVEN solde 15 < cost 20,
## WHEN _on_buy_pressed(&"double_jump", 0),
## THEN total inchangé, _owned_upgrades vide, Upgrade non muté.
func test_purchase_cycle_insufficient_balance_no_mutation() -> void:
	# Arrange
	_seed_credits(15)
	var s: Control = _make_shop()
	var initial_total: int = CreditEconomy.get_total()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — aucune mutation
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-11: total inchangé attendu %d, obtenu %d" % [initial_total, CreditEconomy.get_total()]) \
		.is_equal(initial_total)
	assert_int(s.get_owned_upgrades().size()) \
		.override_failure_message("AC-SHP-11: _owned_upgrades doit rester vide") \
		.is_equal(0)
	assert_bool(Upgrade.is_owned(&"double_jump")) \
		.override_failure_message("AC-SHP-11: Upgrade ne doit PAS être muté quand solde insuffisant") \
		.is_false()
	assert_bool(Upgrade.can_air_jump) \
		.override_failure_message("AC-SHP-11: Upgrade.can_air_jump doit rester false") \
		.is_false()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-48 (Sprint 1 ready — chain unblocked) — cycle exécuté 2x reste idempotent
# =============================================================================

## GIVEN solde large + cycle exécuté 1 fois sur double_jump,
## WHEN _on_buy_pressed appelé une 2e fois sur même id,
## THEN deuxième appel est silent no-op (étape 1 guard) — Upgrade pas re-muté,
## try_spend pas re-appelé (total inchangé entre les 2 calls).
func test_purchase_cycle_idempotent_already_owned_silent_noop() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()
	s._on_buy_pressed(&"double_jump", 0)
	var total_after_first: int = CreditEconomy.get_total()

	# Act — 2e call same id (cas A : already owned)
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — total identique (try_spend pas re-appelé)
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-48: 2e call sur owned id doit être silent no-op (total identique entre call1=%d et call2=%d)" % [total_after_first, CreditEconomy.get_total()]) \
		.is_equal(total_after_first)
	assert_int(s.get_owned_upgrades().size()) \
		.override_failure_message("AC-SHP-48: _owned_upgrades.size() doit rester 1 (pas de doublon)") \
		.is_equal(1)

	# Cleanup
	s.free()


# =============================================================================
# Cycle complet — total_credits décrémenté + persisté + Upgrade muté en chain
# =============================================================================

## Smoke test full cycle 6 steps : double_jump achetable + dash_horizontal achetable.
func test_purchase_cycle_full_chain_two_upgrades_in_sequence() -> void:
	# Arrange
	_seed_credits(100)    # >= 20 + 40 = 60 minimum
	var s: Control = _make_shop()

	# Act — buy both
	s._on_buy_pressed(&"double_jump", 0)
	s._on_buy_pressed(&"dash_horizontal", 1)

	# Assert — both owned + total décrémenté de 60
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("Full cycle: total attendu 100-60=40, obtenu %d" % CreditEconomy.get_total()) \
		.is_equal(40)
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_bool(&"double_jump" in owned).is_true()
	assert_bool(&"dash_horizontal" in owned).is_true()
	assert_bool(Upgrade.can_air_jump).is_true()
	assert_bool(Upgrade.can_dash).is_true()

	# Persisted to save
	var saved: Array[StringName] = SaveLoadSystem.load_string_array(
		_UPGRADE_SAVE_KEY, [] as Array[StringName])
	assert_int(saved.size()).is_equal(2)
	assert_bool(&"double_jump" in saved).is_true()
	assert_bool(&"dash_horizontal" in saved).is_true()

	# Cleanup
	s.free()


# =============================================================================
# EC-SHP-23 — atomicity lint static : zero await/yield dans _on_buy_pressed body
# =============================================================================

## GIVEN ShopController source,
## WHEN extract function body _on_buy_pressed,
## THEN aucun match `await ` ni `yield(` ni `process_frame` dans le body.
func test_purchase_cycle_no_await_yield_atomicity_lint() -> void:
	# Arrange
	var path: String = "res://src/ui/shop/shop_controller.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	# Extract body of _on_buy_pressed
	var func_marker: String = "func _on_buy_pressed("
	var start: int = src.find(func_marker)
	assert_int(start) \
		.override_failure_message("source doit contenir func _on_buy_pressed(") \
		.is_greater_equal(0)
	# Body s'étend du début de func jusqu'à prochain top-level "func "
	var rest: String = src.substr(start + func_marker.length())
	var next_func: int = rest.find("\nfunc ")
	var body: String = rest.substr(0, next_func) if next_func >= 0 else rest

	# Act + Assert — patterns interdits
	assert_bool(body.contains("await ")) \
		.override_failure_message("EC-SHP-23: 'await ' trouvé dans _on_buy_pressed body — atomicité rompue") \
		.is_false()
	assert_bool(body.contains("yield(")) \
		.override_failure_message("EC-SHP-23: 'yield(' trouvé dans _on_buy_pressed body — atomicité rompue") \
		.is_false()
	assert_bool(body.contains("process_frame")) \
		.override_failure_message("EC-SHP-23: 'process_frame' trouvé dans _on_buy_pressed body") \
		.is_false()


# =============================================================================
# EC-SHP-2 — guard cost > 0 (debug assert + release-mode fallback)
# =============================================================================
# Test n_index = -1 → _compute_cost retourne 0 → cycle return early sans mutation.
# (assertion ne peut être testée directement en GdUnit4 — vérification fallback)

func test_purchase_cycle_negative_n_index_no_mutation() -> void:
	# Arrange
	_seed_credits(100)
	var s: Control = _make_shop()
	var initial: int = CreditEconomy.get_total()

	# Act — n_index négatif → _compute_cost return 0 + warning
	s._on_buy_pressed(&"unknown_id", -1)

	# Assert — early return, aucune mutation
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("EC-SHP-2: n_index=-1 → cost=0 → return early, total inchangé") \
		.is_equal(initial)
	assert_int(s.get_owned_upgrades().size()).is_equal(0)

	# Cleanup
	s.free()
