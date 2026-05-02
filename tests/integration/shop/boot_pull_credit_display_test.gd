# Integration test Story-004 — ShopController boot pull credit display.
# Couvre AC-SHP-3 (pull pattern initial credit display) + edges 0/9999.
# Pattern pull cohérent ADR-0007 D-9 (consumers lisent état initial via getter,
# pas signal — protège EC-SHP-4 BOOT_HYDRATE perdu si Shop pas encore connecté).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — utilise CreditEconomy autoload + ShopController instance bare.
extends GdUnitTestSuite

const _CREDIT_SAVE_KEY: String = "total_credits"
const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


# =============================================================================
# Setup / Teardown — controlled CreditEconomy state via SaveLoadSystem seed
# =============================================================================

func before_test() -> void:
	# Reset save state (upgrade hydration côté shop ne doit pas polluer)
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	# Re-hydrate explicit pour garantir _total_credits == 0 entre tests
	# (CreditEconomy autoload mutable persiste entre tests sans re-load).
	CreditEconomy._hydrate_from_save()


func after_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()


# Helper — seed CreditEconomy via _hydrate_from_save (test-only direct call).
func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


# =============================================================================
# AC-SHP-3 — get_total() == 35 → credit display text == "35"
# =============================================================================

## GIVEN CreditEconomy.get_total() == 35,
## WHEN ShopController._ready() exécuté,
## THEN _credit_display_text == "35" immédiatement (avant tout await).
func test_shop_boot_pull_credit_display_value_35() -> void:
	# Arrange
	_seed_credits(35)
	assert_int(CreditEconomy.get_total()).is_equal(35)    # sanity
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("AC-SHP-3: credit display text attendu '35', obtenu '%s'" % s.get_credit_display_text()) \
		.is_equal("35")

	# Cleanup
	s.free()


# =============================================================================
# Edge — solde 0 → label "0" (pas vide, pas placeholder)
# =============================================================================

func test_shop_boot_pull_credit_display_value_zero_renders_zero() -> void:
	# Arrange — before_test seed 0
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("solde 0: credit display text attendu '0', obtenu '%s'" % s.get_credit_display_text()) \
		.is_equal("0")

	# Cleanup
	s.free()


# =============================================================================
# Edge — solde élevé 9999 → label "9999"
# =============================================================================

func test_shop_boot_pull_credit_display_value_9999() -> void:
	# Arrange
	_seed_credits(9999)
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("solde 9999: credit display text attendu '9999', obtenu '%s'" % s.get_credit_display_text()) \
		.is_equal("9999")

	# Cleanup
	s.free()


# =============================================================================
# Pull pattern enforcement — code path appelle CreditEconomy.get_total
# =============================================================================
# Grep statique sur src/ui/shop/shop_controller.gd : au moins 1 match
# `CreditEconomy.get_total(` dans le body de `_pull_initial_credit_display`.
# Lint cover-all simple : si la méthode existe et fait le pull, ce test passe.

func test_shop_controller_source_calls_credit_economy_get_total() -> void:
	# Arrange
	var path: String = "res://src/ui/shop/shop_controller.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(f) \
		.override_failure_message("source file %s introuvable" % path) \
		.is_not_null()
	var src: String = f.get_as_text()
	f.close()

	# Act + Assert
	var has_pull: bool = src.contains("CreditEconomy.get_total(")
	assert_bool(has_pull) \
		.override_failure_message("ADR-0007 D-9 pull pattern: shop_controller.gd doit appeler CreditEconomy.get_total() — pas de match trouvé") \
		.is_true()
