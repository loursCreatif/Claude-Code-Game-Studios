# Unit test Story-010 — SaveLoad write SYNC + corruption handling.
# Couvre AC-SHP-20 (lint statique : pas de await sur save_string_array) +
# AC-SHP-22 (cycle continue jusqu'à apply_upgrade post-save).
# AC-SHP-21 (cross-instance persistence) → tests/integration/shop/saveload_persistence_test.gd.
# AC-SHP-23/24 déjà couverts par tests/integration/shop/boot_hydrate_owned_upgrades_test.gd.
# Framework : GdUnit4 (extends GdUnitTestSuite). Type : Logic.
extends GdUnitTestSuite

const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")
const _SHOP_CONTROLLER_PATH: String = "res://src/ui/shop/shop_controller.gd"
const _SAVE_KEY: String = "owned_upgrades"
const _CREDIT_KEY: String = "total_credits"


# =============================================================================
# Setup / Teardown — reset autoload + save state
# =============================================================================

func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_KEY, 0)
	CreditEconomy._total_credits = 0
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_KEY, 0)
	CreditEconomy._total_credits = 0
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false


# =============================================================================
# AC-SHP-20 — lint statique : aucun await/call_deferred sur save_string_array
# =============================================================================

## GIVEN shop_controller.gd source,
## WHEN scan body purchase cycle (_on_buy_pressed),
## THEN aucune ligne `await ... save_string_array` ni `call_deferred` sur save.
func test_save_string_array_called_sync_no_await_no_deferred_lint() -> void:
	# Arrange
	var f: FileAccess = FileAccess.open(_SHOP_CONTROLLER_PATH, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	# Extract _on_buy_pressed body
	var marker: String = "func _on_buy_pressed("
	var start: int = src.find(marker)
	assert_int(start) \
		.override_failure_message("source doit contenir func _on_buy_pressed(") \
		.is_greater_equal(0)
	var rest: String = src.substr(start + marker.length())
	var next_func: int = rest.find("\nfunc ")
	var body: String = rest.substr(0, next_func) if next_func >= 0 else rest

	# Assert — patterns interdits
	# Note : `await ... save_string_array` doit produire 0 match
	var lower_body: String = body.to_lower()
	assert_bool(lower_body.contains("await ")) \
		.override_failure_message("AC-SHP-20: 'await ' interdit dans _on_buy_pressed (atomicité SYNC)") \
		.is_false()
	# Vérifie que `save_string_array` est bien appelé (preuve du write SYNC)
	assert_bool(body.contains("save_string_array(")) \
		.override_failure_message("AC-SHP-20: save_string_array(...) doit être appelé dans _on_buy_pressed") \
		.is_true()
	# Vérifie qu'il n'y a pas de call_deferred sur save (forbidden ADR-0010 D-2 SYNC)
	assert_bool(body.contains("call_deferred(\"save_string_array\"")) \
		.override_failure_message("AC-SHP-20: call_deferred sur save_string_array interdit") \
		.is_false()


# =============================================================================
# AC-SHP-22 — cycle continue jusqu'à apply post-save (séquence atomique)
# =============================================================================

## GIVEN solde + cycle achat exécuté,
## WHEN inspecter _call_order_log,
## THEN log contient à la fois "save" et "apply" (pas de break inter-étape).
func test_save_string_array_followed_by_apply_upgrade_no_break() -> void:
	# Arrange
	CreditEconomy._total_credits = 50
	var s: Control = _ShopControllerScript.new()
	s._ready()

	# Act
	s._on_buy_pressed(&"dash_horizontal", 1)

	# Assert — save AVANT apply, deux étapes complétées
	var log: Array[String] = s.get_call_order_log()
	assert_bool(log.has("save")) \
		.override_failure_message("AC-SHP-22: 'save' attendu dans call_order_log %s" % str(log)) \
		.is_true()
	assert_bool(log.has("apply")) \
		.override_failure_message("AC-SHP-22: 'apply' attendu dans call_order_log %s — break inter-étape suspecté" % str(log)) \
		.is_true()
	assert_bool(Upgrade.is_owned(&"dash_horizontal")) \
		.override_failure_message("AC-SHP-22: Upgrade.is_owned(dash_horizontal) attendu true post-cycle") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-21 — write réel persisté observable post-cycle (intra-instance)
# =============================================================================

## GIVEN cycle achat exécuté,
## WHEN re-load via SaveLoadSystem.load_string_array,
## THEN owned_upgrades contient l'id acheté.
func test_save_string_array_writes_persisted_observable_via_load() -> void:
	# Arrange
	CreditEconomy._total_credits = 20
	var s: Control = _ShopControllerScript.new()
	s._ready()

	# Act
	s._on_buy_pressed(&"double_jump", 0)
	var saved: Array[StringName] = SaveLoadSystem.load_string_array(
		_SAVE_KEY, [] as Array[StringName])

	# Assert — persistence write-through SYNC observable
	assert_int(saved.size()) \
		.override_failure_message("AC-SHP-21: persisted size attendu 1, obtenu %d (write-through SYNC)" % saved.size()) \
		.is_equal(1)
	assert_bool(&"double_jump" in saved) \
		.override_failure_message("AC-SHP-21: double_jump absent du save persisted") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-SHP-22 corollaire — call_order_log : "save" précède strictement "apply"
# =============================================================================

func test_save_indexed_before_apply_in_call_order_log() -> void:
	# Arrange
	CreditEconomy._total_credits = 20
	var s: Control = _ShopControllerScript.new()
	s._ready()

	# Act
	s._on_buy_pressed(&"double_jump", 0)

	# Assert
	var log: Array[String] = s.get_call_order_log()
	var save_idx: int = log.find("save")
	var apply_idx: int = log.find("apply")
	assert_bool(save_idx >= 0 and apply_idx >= 0 and save_idx < apply_idx) \
		.override_failure_message("AC-SHP-22 ordre strict: save (%d) doit < apply (%d) — log=%s" % [save_idx, apply_idx, str(log)]) \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# EC-SHP-22 — autoload order garanti par project.godot (lint)
# =============================================================================

## GIVEN project.godot section [autoload],
## WHEN scan order,
## THEN SaveLoadSystem présent AVANT CreditEconomy AVANT Upgrade
## (Shop n'est pas autoload — instancié via shop.tscn).
func test_autoload_order_saveload_before_credit_before_upgrade() -> void:
	# Arrange
	var f: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	# Extract [autoload] section
	var auto_start: int = src.find("[autoload]")
	assert_int(auto_start).override_failure_message("project.godot doit contenir [autoload]").is_greater_equal(0)
	# Section continues until next [section] or EOF
	var rest: String = src.substr(auto_start)
	var next_section: int = rest.find("\n[", 1)
	var section: String = rest.substr(0, next_section) if next_section >= 0 else rest

	# Assert — ordre relatif (Godot charge dans l'ordre déclaré)
	var saveload_idx: int = section.find("SaveLoadSystem=")
	var credit_idx: int = section.find("CreditEconomy=")
	var upgrade_idx: int = section.find("Upgrade=")
	assert_bool(saveload_idx >= 0) \
		.override_failure_message("EC-SHP-22: SaveLoadSystem doit être autoload") \
		.is_true()
	assert_bool(credit_idx >= 0) \
		.override_failure_message("EC-SHP-22: CreditEconomy doit être autoload") \
		.is_true()
	assert_bool(upgrade_idx >= 0) \
		.override_failure_message("EC-SHP-22: Upgrade doit être autoload") \
		.is_true()
	assert_bool(saveload_idx < credit_idx) \
		.override_failure_message("EC-SHP-22: SaveLoadSystem (idx=%d) doit précéder CreditEconomy (idx=%d)" % [saveload_idx, credit_idx]) \
		.is_true()
	assert_bool(credit_idx < upgrade_idx) \
		.override_failure_message("EC-SHP-22: CreditEconomy (idx=%d) doit précéder Upgrade (idx=%d)" % [credit_idx, upgrade_idx]) \
		.is_true()
