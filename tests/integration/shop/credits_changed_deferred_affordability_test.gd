# Integration test Story-007 — credits_changed CONNECT_DEFERRED + affordability recalc.
# Couvre AC-SHP-4 (DEFERRED flag), AC-SHP-12/16/17/18/19 (affordability logic),
# EC-SHP-14 (1 frame recalc all cards), EC-SHP-40 (handlers séquentiels DEFERRED).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — utilise CreditEconomy autoload + Upgrade autoload.
extends GdUnitTestSuite

const _CREDIT_SAVE_KEY: String = "total_credits"
const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


func before_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	# Reset Upgrade
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false
	# Reset CreditEconomy state
	CreditEconomy._hydrate_from_save()


func after_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false
	CreditEconomy._hydrate_from_save()


func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


func _make_shop() -> Control:
	var s: Control = _ShopControllerScript.new()
	s._ready()
	return s


# =============================================================================
# AC-SHP-4 — credits_changed connecté avec CONNECT_DEFERRED flag (bitmask)
# =============================================================================

## GIVEN ShopController._ready() exécuté,
## WHEN inspecter CreditEconomy.credits_changed.get_connections(),
## THEN connection vers _on_credits_changed a flags & CONNECT_DEFERRED != 0.
func test_credits_changed_connected_with_deferred_flag() -> void:
	# Arrange
	var s: Control = _make_shop()

	# Act
	var conns: Array = CreditEconomy.credits_changed.get_connections()
	var found_deferred: bool = false
	for conn in conns:
		if conn.callable.get_object() == s:
			if (conn.flags & CONNECT_DEFERRED) != 0:
				found_deferred = true
				break

	# Assert
	assert_bool(found_deferred) \
		.override_failure_message("AC-SHP-4: connection vers Shop doit avoir flag CONNECT_DEFERRED, conns=%s" % str(conns)) \
		.is_true()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-4 lint static — source contient "CONNECT_DEFERRED" sur credits_changed
# =============================================================================

func test_shop_controller_source_uses_connect_deferred() -> void:
	var path: String = "res://src/ui/shop/shop_controller.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	assert_bool(src.contains("CONNECT_DEFERRED")) \
		.override_failure_message("AC-SHP-4 lint: source doit contenir CONNECT_DEFERRED") \
		.is_true()
	assert_bool(src.contains("credits_changed.connect")) \
		.override_failure_message("AC-SHP-4 lint: source doit contenir credits_changed.connect") \
		.is_true()


# =============================================================================
# AC-SHP-16 — solde 19 < 20 → both upgrades not affordable
# =============================================================================

func test_affordability_balance_19_both_disabled() -> void:
	# Arrange
	_seed_credits(19)
	var s: Control = _make_shop()    # _ready() → recalc avec total=19

	# Assert
	assert_bool(s.is_affordable(&"double_jump")) \
		.override_failure_message("AC-SHP-16: 19 < 20 cost double_jump → non affordable") \
		.is_false()
	assert_bool(s.is_affordable(&"dash_horizontal")) \
		.override_failure_message("AC-SHP-16: 19 < 40 cost dash_horizontal → non affordable") \
		.is_false()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-17 — solde 20 + double_jump acheté (net=0) → dash_horizontal disabled
# =============================================================================

func test_affordability_balance_20_buy_dj_then_dash_disabled() -> void:
	# Arrange
	_seed_credits(20)
	var s: Control = _make_shop()
	# Sanity initial : double_jump affordable (20==20), dash pas (20<40)
	assert_bool(s.is_affordable(&"double_jump")).is_true()
	assert_bool(s.is_affordable(&"dash_horizontal")).is_false()

	# Act — buy double_jump (cycle complet)
	s._on_buy_pressed(&"double_jump", 0)
	# Le handler DEFERRED ne s'exécute qu'au prochain idle frame.
	# Ici on simule via call direct au handler (test logic recalc).
	s._on_credits_changed(CreditEconomy.get_total(), -20, 0)

	# Assert — solde 0, dash non affordable
	assert_int(CreditEconomy.get_total()).is_equal(0)
	assert_bool(s.is_affordable(&"dash_horizontal")) \
		.override_failure_message("AC-SHP-17: solde 0 < 40 → dash_horizontal non affordable") \
		.is_false()
	# double_jump owned → pas affordable=achat (déjà disabled OWNED logic)
	assert_bool(s.is_affordable(&"double_jump")) \
		.override_failure_message("AC-SHP-17: double_jump owned → is_affordable false (already OWNED)") \
		.is_false()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-18 — solde 60 + double_jump acheté (40 reste) → dash_horizontal affordable
# =============================================================================

func test_affordability_balance_60_buy_dj_then_dash_affordable() -> void:
	# Arrange
	_seed_credits(60)
	var s: Control = _make_shop()

	# Act
	s._on_buy_pressed(&"double_jump", 0)
	s._on_credits_changed(CreditEconomy.get_total(), -20, 0)

	# Assert — 60-20=40 ; dash cost 40 ; affordable
	assert_int(CreditEconomy.get_total()).is_equal(40)
	assert_bool(s.is_affordable(&"dash_horizontal")) \
		.override_failure_message("AC-SHP-18: solde 40 >= 40 cost → dash_horizontal affordable") \
		.is_true()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-19 — solde 60, 2 cycles → solde 0, both owned, both not-affordable
# =============================================================================

func test_affordability_full_chain_two_purchases() -> void:
	# Arrange
	_seed_credits(60)
	var s: Control = _make_shop()

	# Act — 2 achats séquentiels (avec recalc handler après chaque)
	s._on_buy_pressed(&"double_jump", 0)
	s._on_credits_changed(CreditEconomy.get_total(), -20, 0)
	s._on_buy_pressed(&"dash_horizontal", 1)
	s._on_credits_changed(CreditEconomy.get_total(), -40, 0)

	# Assert
	assert_int(CreditEconomy.get_total()).is_equal(0)
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()).is_equal(2)
	assert_bool(&"double_jump" in owned).is_true()
	assert_bool(&"dash_horizontal" in owned).is_true()
	# Both owned → is_affordable=false (OWNED state)
	assert_bool(s.is_affordable(&"double_jump")).is_false()
	assert_bool(s.is_affordable(&"dash_horizontal")).is_false()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# AC-SHP-12 — emit credits_changed DEFERRED + await idle frame → state propagé
# =============================================================================

## GIVEN shop ACTIVE in scene tree, solde 100,
## WHEN credits_changed.emit(15, -85, SPEND_SHOP) puis await get_tree().process_frame,
## THEN _credit_display_text == "15", affordability recalculée pour 15.
func test_credits_changed_deferred_emit_propagates_after_idle_frame() -> void:
	# Arrange
	_seed_credits(100)
	var s: Control = _ShopControllerScript.new()
	add_child(s)    # nécessaire pour await get_tree() events
	s._ready()    # double-_ready : safe car _connect_* est idempotent
	# Sanity post _ready : display "100", dash affordable
	assert_str(s.get_credit_display_text()).is_equal("100")

	# Act — emit + idle frame (handler DEFERRED s'exécute)
	CreditEconomy.credits_changed.emit(15, -85, 0)
	await get_tree().process_frame
	await get_tree().process_frame    # safety : 2 frames pour propagation

	# Assert — state mis à jour POST-DEFERRED
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("AC-SHP-12: post-emit DEFERRED + await, display attendu '15', obtenu '%s'" % s.get_credit_display_text()) \
		.is_equal("15")
	# 15 < 20 < 40 → both non affordable
	assert_bool(s.is_affordable(&"double_jump")).is_false()
	assert_bool(s.is_affordable(&"dash_horizontal")).is_false()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	remove_child(s)
	s.free()


# =============================================================================
# EC-SHP-14 — 1 frame post-credit_changed : tous BuyButtons non-owned recalculés
# =============================================================================

## GIVEN solde initial 60, double_jump non owned,
## WHEN credits_changed handler invoqué directement (simule 1 frame),
## THEN _affordable_state mis à jour pour TOUTES les entries non-owned (atomique).
func test_affordability_single_handler_call_recalcs_all_non_owned() -> void:
	# Arrange
	_seed_credits(60)
	var s: Control = _make_shop()
	# Pré-state : both affordable (60>=20, 60>=40)
	assert_bool(s.is_affordable(&"double_jump")).is_true()
	assert_bool(s.is_affordable(&"dash_horizontal")).is_true()

	# Act — simulate credits_changed(10) → both should become non-affordable
	s._on_credits_changed(10, -50, 0)

	# Assert — both recalc'd in same handler invocation (EC-SHP-14)
	assert_bool(s.is_affordable(&"double_jump")) \
		.override_failure_message("EC-SHP-14: 10 < 20 → double_jump non affordable post-handler") \
		.is_false()
	assert_bool(s.is_affordable(&"dash_horizontal")) \
		.override_failure_message("EC-SHP-14: 10 < 40 → dash_horizontal non affordable post-handler") \
		.is_false()

	# Cleanup
	CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()
