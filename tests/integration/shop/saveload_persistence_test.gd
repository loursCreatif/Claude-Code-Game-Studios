# Integration test Story-010 — SaveLoad write SYNC + persistence cross-instance.
# Couvre AC-SHP-20 (SYNC lint static), AC-SHP-21 (reload retrouve owned),
# EC-SHP-22 (autoload order garanti SaveLoadSystem present at Shop._ready()).
# AC-SHP-22 (push_error sur disk full) : déféré — pas de hook simple pour
# simuler échec ConfigFile.save() dans GdUnit4 ; couvert par push_error
# côté SaveLoadSystem implementation (save-load epic story-005 WM_CLOSE).
# AC-SHP-23/24 déjà couverts story-003 (forward-compat unknown ids).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — utilise SaveLoadSystem live + Upgrade live.
extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"
const _CREDIT_SAVE_KEY: String = "total_credits"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


# =============================================================================
# AC-SHP-20 — lint static : aucun await sur save_string_array
# =============================================================================

func test_shop_controller_no_await_on_save_string_array() -> void:
	var path: String = "res://src/ui/shop/shop_controller.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(f).is_not_null()
	var src: String = f.get_as_text()
	f.close()

	# Cherche pattern "await ... save_string_array"
	var lines: PackedStringArray = src.split("\n")
	var await_save_count: int = 0
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("await") and stripped.contains("save_string_array"):
			await_save_count += 1

	assert_int(await_save_count) \
		.override_failure_message("AC-SHP-20: await.*save_string_array attendu 0 match, obtenu %d" % await_save_count) \
		.is_equal(0)


# =============================================================================
# AC-SHP-20 — lint static : aucun call_deferred sur save_string_array
# =============================================================================

func test_shop_controller_no_call_deferred_on_save_string_array() -> void:
	var path: String = "res://src/ui/shop/shop_controller.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()

	var lines: PackedStringArray = src.split("\n")
	var deferred_count: int = 0
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("call_deferred") and stripped.contains("save_string_array"):
			deferred_count += 1

	assert_int(deferred_count) \
		.override_failure_message("AC-SHP-20: call_deferred.save_string_array attendu 0 match, obtenu %d" % deferred_count) \
		.is_equal(0)


# =============================================================================
# AC-SHP-21 — reload test : instance 2 retrouve upgrade owned post-instance 1 buy
# =============================================================================

## GIVEN shop1 instancié, achat double_jump effectué + persisté,
## WHEN shop1 free + shop2 instancié,
## THEN shop2._owned_upgrades.has(&"double_jump") == true (rehydraté du disk).
func test_purchase_persists_across_shop_reload() -> void:
	# Arrange — shop1
	_seed_credits(50)
	var shop1: Control = _ShopControllerScript.new()
	shop1._ready()

	# Act 1 — achat dans shop1
	shop1._on_buy_pressed(&"double_jump", 0)

	# Sanity — save persistée
	var saved_post_buy: Array[StringName] = SaveLoadSystem.load_string_array(
		_SAVE_KEY, [] as Array[StringName])
	assert_bool(&"double_jump" in saved_post_buy) \
		.override_failure_message("post-buy: SaveLoad doit contenir double_jump") \
		.is_true()

	# Cleanup shop1 (simule scene close)
	if CreditEconomy.credits_changed.is_connected(shop1._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(shop1._on_credits_changed)
	shop1.free()

	# Act 2 — shop2 boot frais
	var shop2: Control = _ShopControllerScript.new()
	shop2._ready()

	# Assert — shop2 rehydraté avec double_jump owned
	var owned_shop2: Array[StringName] = shop2.get_owned_upgrades()
	assert_bool(&"double_jump" in owned_shop2) \
		.override_failure_message("AC-SHP-21: shop2 boot doit avoir double_jump owned (rehydration)") \
		.is_true()
	assert_int(owned_shop2.size()).is_equal(1)

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(shop2._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(shop2._on_credits_changed)
	shop2.free()


# =============================================================================
# EC-SHP-22 — autoload SaveLoadSystem disponible dès Shop._ready()
# =============================================================================

func test_saveload_autoload_available_at_shop_ready() -> void:
	# Si autoload order incorrect, instantiation Shop crasherait au _ready()
	# (call SaveLoadSystem.load_string_array nécessaire). Sanity check basique.
	var s: Control = _ShopControllerScript.new()
	s._ready()    # ne doit pas crash

	# Verify autoload accessible via singleton lookup
	assert_object(SaveLoadSystem) \
		.override_failure_message("EC-SHP-22: SaveLoadSystem autoload doit exister") \
		.is_not_null()
	assert_object(CreditEconomy) \
		.override_failure_message("EC-SHP-22: CreditEconomy autoload doit exister") \
		.is_not_null()
	assert_object(Upgrade) \
		.override_failure_message("EC-SHP-22: Upgrade autoload doit exister") \
		.is_not_null()
	assert_object(GameStateManager) \
		.override_failure_message("EC-SHP-22: GameStateManager autoload doit exister") \
		.is_not_null()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()


# =============================================================================
# Save round-trip — write SYNC propage immédiatement (lecture suit)
# =============================================================================

## GIVEN shop1 achète double_jump,
## WHEN immédiatement load_string_array sur même clé,
## THEN retourne [&"double_jump"] (write SYNC complété avant return).
func test_save_string_array_sync_immediate_readback() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _ShopControllerScript.new()
	s._ready()

	# Act — buy + immediate readback (no await)
	s._on_buy_pressed(&"double_jump", 0)
	var read_back: Array[StringName] = SaveLoadSystem.load_string_array(
		_SAVE_KEY, [] as Array[StringName])

	# Assert — write SYNC complété, lecture immédiate cohérente
	assert_int(read_back.size()) \
		.override_failure_message("Write SYNC: load post-buy attendu size=1, obtenu %d" % read_back.size()) \
		.is_equal(1)
	assert_bool(&"double_jump" in read_back).is_true()

	# Cleanup
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.free()
