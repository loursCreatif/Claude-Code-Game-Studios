# Integration test Story-003 — ShopController boot hydrate _owned_upgrades.
# Couvre AC-SHP-1/2/24 + EC-SHP-39 (cross-type cast String→StringName par SaveLoadSystem).
# AC-SHP-15 (BuyButtons disabled UI) déférée à story-005 (rendering).
# AC-SHP-23 (corruption) couverte par défense profonde SaveLoadSystem (ADR-0010 D-2)
# — code path non-atteignable depuis Shop puisque load_string_array est typed strict.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — utilise SaveLoadSystem live + ShopController instance bare.
extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


# =============================================================================
# Setup / Teardown — reset save state entre tests (autoload SaveLoadSystem mutable)
# =============================================================================

func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


# =============================================================================
# AC-SHP-1 — _owned_upgrades match SaveLoad return [double_jump]
# =============================================================================

## GIVEN SaveLoadSystem seedée avec [&"double_jump"],
## WHEN ShopController instance + _ready() exécuté,
## THEN _owned_upgrades == [&"double_jump"].
func test_shop_boot_hydrate_owned_upgrades_single_id_propagated() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump"] as Array[StringName])
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-1: _owned_upgrades.size() attendu 1, obtenu %d" % owned.size()) \
		.is_equal(1)
	assert_object(owned[0]) \
		.override_failure_message("AC-SHP-1: owned[0] != &'double_jump'") \
		.is_equal(&"double_jump")

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-2 — empty save key → _owned_upgrades == []
# =============================================================================

## GIVEN save key empty (default before_test) ou absente,
## WHEN ShopController._ready() exécuté,
## THEN _owned_upgrades == [].
func test_shop_boot_hydrate_empty_save_returns_empty_owned() -> void:
	# Arrange — before_test garantit empty
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-2: empty save → _owned_upgrades.size() attendu 0, obtenu %d" % owned.size()) \
		.is_equal(0)

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-1 multi — save [double_jump, dash_horizontal] propagated complete
# =============================================================================

## GIVEN SaveLoadSystem seedée avec MVP catalog complet,
## WHEN ShopController._ready() exécuté,
## THEN _owned_upgrades contient les 2 ids dans l'ordre.
func test_shop_boot_hydrate_full_mvp_catalog_propagated() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY,
		[&"double_jump", &"dash_horizontal"] as Array[StringName])
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-1: full MVP catalog size attendu 2, obtenu %d" % owned.size()) \
		.is_equal(2)
	assert_bool(&"double_jump" in owned) \
		.override_failure_message("AC-SHP-1: &'double_jump' absent de _owned_upgrades") \
		.is_true()
	assert_bool(&"dash_horizontal" in owned) \
		.override_failure_message("AC-SHP-1: &'dash_horizontal' absent de _owned_upgrades") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-24 — unknown id [triple_jump] conservé silencieusement (EC-SHP-8 forward-safe)
# =============================================================================

## GIVEN SaveLoadSystem seedée avec [&"triple_jump"] (id Tier 2+ inconnu MVP),
## WHEN ShopController._ready() exécuté,
## THEN _owned_upgrades contient &"triple_jump" silencieusement.
func test_shop_boot_hydrate_unknown_tier2_id_preserved_silently() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"triple_jump"] as Array[StringName])
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-24: unknown id préservé attendu (size=1), obtenu %d" % owned.size()) \
		.is_equal(1)
	assert_object(owned[0]) \
		.override_failure_message("AC-SHP-24: &'triple_jump' doit être conservé pour re-save (forward-safe)") \
		.is_equal(&"triple_jump")

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-1 mixed — save [double_jump, triple_jump_unknown] keeps both
# =============================================================================

## GIVEN SaveLoadSystem seedée avec mix MVP + unknown,
## WHEN ShopController._ready() exécuté,
## THEN _owned_upgrades contient les deux ids (UI filtre via _CATALOG, save inchangée).
func test_shop_boot_hydrate_mix_mvp_and_unknown_both_preserved() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY,
		[&"double_jump", &"triple_jump"] as Array[StringName])
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-1+24: mix MVP+unknown size attendu 2, obtenu %d" % owned.size()) \
		.is_equal(2)
	assert_bool(&"double_jump" in owned).is_true()
	assert_bool(&"triple_jump" in owned).is_true()

	# Cleanup
	s.free()


# =============================================================================
# EC-SHP-39 — String saved (pas StringName) → cast au load par SaveLoadSystem
# =============================================================================
# SaveLoadSystem.save_string_array enforce typed Array[StringName] en signature,
# mais ConfigFile sérialise StringName → String (R-SAV-12 normalisation au load).
# Ce test confirme le round-trip String-stored → StringName-loaded.

func test_shop_boot_hydrate_stringname_round_trip_via_configfile() -> void:
	# Arrange — save avec StringName, ConfigFile stocke comme String, load normalise
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump"] as Array[StringName])
	var s: Control = _ShopControllerScript.new()

	# Act
	s._ready()

	# Assert — typeof == TYPE_STRING_NAME (24) post-load
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()).is_equal(1)
	assert_int(typeof(owned[0])) \
		.override_failure_message("EC-SHP-39: typeof(owned[0]) attendu TYPE_STRING_NAME (%d), obtenu %d" % [TYPE_STRING_NAME, typeof(owned[0])]) \
		.is_equal(TYPE_STRING_NAME)

	# Cleanup
	s.free()
