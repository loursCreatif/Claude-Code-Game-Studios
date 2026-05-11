# Unit test Story-006 — Idempotence guards 3 niveaux (UI / Save+Load / Upgrade).
# Couvre AC-SHP-13/14 + EC-SHP-10/11 + guard release garanti tous paths.
# Niveau Save/Load et UpgradeSystem contract testés ailleurs (story-003 / upgrade-005).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare ShopController + Upgrade real autoload.
extends GdUnitTestSuite

const _CREDIT_SAVE_KEY: String = "total_credits"
const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


func before_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
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
# AC-SHP-13 — 2 calls consécutifs same id : try_spend appelé 1× total
# =============================================================================
# En SYNC GDScript, le 1er call complète intégralement avant le 2e. Le 2e call
# voit _owned_upgrades.has(id) == true (Étape 1) et return silently. try_spend
# n'est appelé qu'une fois (au 1er call) — semantically équivalent au double-click.

## GIVEN solde 50, double_jump non owned,
## WHEN _on_buy_pressed appelé 2× consécutifs (n_index=0),
## THEN total décrémenté de cost_0 = BASE_UPGRADE_COST + TIER_COST_STEP × 0 = 8 (1× try_spend),
##      pas 16 (2×).
## Post commit 9a4cc0b — valeurs canoniques BASE=8 / STEP=20 (F-CRD-3 r2 B-2).
func test_idempotence_double_call_same_id_spends_only_once() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()
	var expected_total: int = 50 - CreditEconomy.BASE_UPGRADE_COST  # 50 - 8 = 42

	# Act — 2 calls consécutifs
	s._on_buy_pressed(&"double_jump", 0)
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — total décrémenté de cost_0 seulement (pas 2×)
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-13: 2 calls double_jump → total attendu %d (50-%d×1), obtenu %d" % [expected_total, CreditEconomy.BASE_UPGRADE_COST, CreditEconomy.get_total()]) \
		.is_equal(expected_total)
	assert_int(s.get_owned_upgrades().size()) \
		.override_failure_message("AC-SHP-13: _owned_upgrades.size() doit rester 1 (pas de doublon)") \
		.is_equal(1)

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-14 — already owned (init state) : try_spend non appelé (early guard 1)
# =============================================================================

## GIVEN _owned_upgrades = [double_jump] post-hydrate, solde 50,
## WHEN _on_buy_pressed(&"double_jump", 0),
## THEN try_spend non appelé (total inchangé, Upgrade non re-muté).
func test_idempotence_already_owned_id_no_spend_no_apply() -> void:
	# Arrange — seed save avec double_jump déjà owned
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY,
		[&"double_jump"] as Array[StringName])
	_seed_credits(50)
	var s: Control = _make_shop()    # _ready() → hydrate _owned_upgrades = [double_jump]
	var initial_total: int = CreditEconomy.get_total()
	s.reset_call_order_log_for_test()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — aucun side-effect (try_spend pas appelé)
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-14: total doit rester %d (early return guard has(id))" % initial_total) \
		.is_equal(initial_total)
	# Pas d'append au call_order_log (save+apply skipped)
	assert_int(s.get_call_order_log().size()) \
		.override_failure_message("AC-SHP-14: call_order_log doit rester vide (save/apply skipped)") \
		.is_equal(0)

	# Cleanup
	s.free()


# =============================================================================
# EC-SHP-10 — race window : 2e click alors que _purchase_in_progress=true
# =============================================================================

## GIVEN solde 50 + flag _purchase_in_progress=true (simulé via test seam),
## WHEN _on_buy_pressed,
## THEN second event return Étape 2 silently (no spend, no apply).
func test_idempotence_purchase_in_progress_blocks_second_event() -> void:
	# Arrange — solde + flag forcé
	_seed_credits(50)
	var s: Control = _make_shop()
	s.set_purchase_in_progress_for_test(true)
	var initial_total: int = CreditEconomy.get_total()

	# Act — handler invoqué pendant in-flight
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — early return Étape 2 (pas de mutation)
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("EC-SHP-10: total inchangé attendu, obtenu %d (race window blocked)" % CreditEconomy.get_total()) \
		.is_equal(initial_total)
	assert_int(s.get_owned_upgrades().size()).is_equal(0)
	assert_bool(s.get_purchase_in_progress_for_test()) \
		.override_failure_message("EC-SHP-10: flag doit rester true (Étape 2 return ne reset pas)") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# EC-SHP-11 — spam click sur OWNED : 5 events handler → 0 mutation
# =============================================================================

## GIVEN _owned_upgrades = [double_jump] hydrated,
## WHEN _on_buy_pressed appelé 5× consécutifs,
## THEN aucun side-effect (try_spend.count == 0, save+apply skipped chaque fois).
func test_idempotence_spam_click_on_owned_zero_side_effects() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY,
		[&"double_jump"] as Array[StringName])
	_seed_credits(100)
	var s: Control = _make_shop()
	var initial_total: int = CreditEconomy.get_total()
	s.reset_call_order_log_for_test()

	# Act — spam 5 clicks
	for i in 5:
		s._on_buy_pressed(&"double_jump", 0)

	# Assert — total inchangé, log vide (Étape 1 guard intercepts every time)
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("EC-SHP-11: spam 5 clicks total inchangé attendu %d, obtenu %d" % [initial_total, CreditEconomy.get_total()]) \
		.is_equal(initial_total)
	assert_int(s.get_owned_upgrades().size()).is_equal(1)
	assert_int(s.get_call_order_log().size()) \
		.override_failure_message("EC-SHP-11: call_order_log vide attendu (5 events all blocked Étape 1)") \
		.is_equal(0)

	# Cleanup
	s.free()


# =============================================================================
# Guard release garanti — succès cycle libère _purchase_in_progress
# =============================================================================

## GIVEN cycle complet exécuté avec succès,
## WHEN cycle terminé,
## THEN _purchase_in_progress == false (libéré pour clicks ultérieurs).
func test_idempotence_purchase_flag_released_after_success() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — flag libéré post-succès
	assert_bool(s.get_purchase_in_progress_for_test()) \
		.override_failure_message("Guard release: _purchase_in_progress doit être false post-succès") \
		.is_false()

	# Cleanup
	s.free()


# =============================================================================
# Guard release sur insufficient balance — flag jamais set car early return Étape 4
# =============================================================================

## GIVEN solde 5 < cost 20 (insufficient avant flag set),
## WHEN _on_buy_pressed,
## THEN flag reste false (early return AVANT mutation flag — Étape 4 guard).
func test_idempotence_purchase_flag_untouched_on_insufficient_balance() -> void:
	# Arrange
	_seed_credits(5)    # < 20 cost double_jump
	var s: Control = _make_shop()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — flag jamais set
	assert_bool(s.get_purchase_in_progress_for_test()) \
		.override_failure_message("Guard release: insufficient balance early return doit laisser flag false") \
		.is_false()

	# Cleanup
	s.free()
