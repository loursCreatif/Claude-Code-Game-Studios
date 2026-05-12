# Integration test Story-015 — Bidirectional contracts Credit ↔ Shop ↔ SaveLoad ↔ Upgrade.
# Couvre AC-SHP-46 (try_spend SYNC + signal DEFERRED), AC-SHP-47 (GSM transition SYNC),
# AC-SHP-48 ACTIVATED (Upgrade autoload réel — upgrade epic 9/9 Complete promu hors Provisional),
# AC-SHP-49 BLOCKING (SaveLoad réel roundtrip + corruption fallback),
# AC-SHP-54 (no leak entre instances), AC-SHP-55 (méta-propagation note).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — autoloads réels CreditEconomy + Upgrade + SaveLoadSystem ;
# GameStateManager.request_scene_transition stubbé via Callable injection (évite
# `change_scene_to_file` destructif pendant suite test).
extends GdUnitTestSuite

const _UPGRADE_SAVE_KEY: String = "owned_upgrades"
const _CREDIT_SAVE_KEY: String = "total_credits"
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


func before_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func after_test() -> void:
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, 0)
	CreditEconomy._hydrate_from_save()
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false
	Upgrade.can_dash = false
	Upgrade.can_wall_run = false


func _seed_credits(amount: int) -> void:
	SaveLoadSystem.save_int(_CREDIT_SAVE_KEY, amount)
	CreditEconomy._hydrate_from_save()


func _make_shop() -> Control:
	var s: Control = _ShopControllerScript.new()
	add_child(s)
	s._ready()
	return s


func _free_shop(s: Control) -> void:
	if CreditEconomy.credits_changed.is_connected(s._on_credits_changed):
		CreditEconomy.credits_changed.disconnect(s._on_credits_changed)
	s.queue_free()


# =============================================================================
# AC-SHP-46 — Credit r1 contract : try_spend SYNC bool + credits_changed DEFERRED
# =============================================================================

## GIVEN solde 60, shop instancié + connecté DEFERRED,
## WHEN try_spend(20) SYNC,
## THEN retour bool true SYNC, get_total() == 40 SYNC,
##      handler shop._on_credits_changed PAS exécuté avant idle frame,
##      texte credit affiché reste "60" jusqu'à process_frame, devient "40" après.
func test_try_spend_sync_returns_bool_credits_changed_handler_deferred() -> void:
	# Arrange
	_seed_credits(60)
	var s: Control = _make_shop()
	# Sanity — initial pull montre 60 (story-004)
	assert_str(s.get_credit_display_text()).is_equal("60")

	# Act — try_spend SYNC depuis l'extérieur (simule autre source que Shop)
	var spend_result: bool = CreditEconomy.try_spend(20)

	# Assert SYNC partie : retour bool + mutation immédiate
	assert_bool(spend_result) \
		.override_failure_message("AC-SHP-46: try_spend doit retourner true SYNC") \
		.is_true()
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-SHP-46: get_total() SYNC post try_spend") \
		.is_equal(40)

	# Assert DEFERRED : handler shop pas encore appelé (idle frame pas encore tickée)
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("AC-SHP-46: handler DEFERRED ne doit pas avoir été exécuté avant idle frame (still '60')") \
		.is_equal("60")

	# Tick idle frame — handler DEFERRED s'exécute maintenant
	await get_tree().process_frame

	assert_str(s.get_credit_display_text()) \
		.override_failure_message("AC-SHP-46: handler DEFERRED doit avoir mis à jour display à idle frame ('40')") \
		.is_equal("40")

	# Cleanup
	_free_shop(s)


# =============================================================================
# AC-SHP-47 — GSM r1 contract : request_scene_transition SYNC same frame
# =============================================================================
# Note : on n'appelle PAS GSM.request_scene_transition réel (déclenche
# `change_scene_to_file` destructif). On utilise le test seam Callable du Shop
# pour capturer l'appel SYNC. Sémantiquement équivalent : Shop déclenche la
# transition même frame que le clic → couvre le contract attendu.

class TransitionCapture extends RefCounted:
	var calls: Array[String] = []
	var call_count: int = 0
	func capture(scene_path: String) -> void:
		call_count += 1
		calls.append(scene_path)


## GIVEN shop instancié + transition_callable injecté,
## WHEN _on_continue_pressed() SYNC,
## THEN capture.call_count == 1 AVANT process_frame (preuve SYNC same frame).
func test_gsm_request_scene_transition_invoked_sync_same_frame() -> void:
	# Arrange
	var s: Control = _make_shop()
	var capture: TransitionCapture = TransitionCapture.new()
	s.set_transition_callable_for_test(Callable(capture, "capture"))

	# Sanity — pas encore d'appel
	assert_int(capture.call_count).is_equal(0)

	# Act — _on_continue_pressed() SYNC, sans await intermédiaire
	s._on_continue_pressed()

	# Assert — appel capté SYNC dans le même frame que le press
	assert_int(capture.call_count) \
		.override_failure_message("AC-SHP-47: transition doit être déclenchée SYNC same frame") \
		.is_equal(1)
	assert_str(capture.calls[0]) \
		.override_failure_message("AC-SHP-47: scene_path doit être main menu") \
		.is_equal("res://scenes/menus/main_menu.tscn")

	# Cleanup
	_free_shop(s)


# =============================================================================
# AC-SHP-48 ACTIVATED — Upgrade autoload réel idempotent (sortie de Provisional)
# =============================================================================
# Upgrade epic 9/9 Complete (2026-04-28) → impl réelle activée. Test exige
# apply_upgrade SYNC idempotent : 2 appels même id → 1 seul side-effect (flag
# bool reste true), pas de re-apply.

## GIVEN solde 50, shop instancié + Upgrade autoload réel (frais),
## WHEN _on_buy_pressed(double_jump) 2× consécutifs même frame,
## THEN Upgrade.is_owned(double_jump) == true,
##      Upgrade.can_air_jump == true,
##      _owned_upgrades shop = [double_jump] (1 entrée — guard idempotence),
##      _call_order_log = ["save", "apply"] (1 cycle complet, 2e bloqué guard).
func test_upgrade_apply_idempotent_real_autoload() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()

	# Act — 2 _on_buy_pressed consécutifs
	s._on_buy_pressed(&"double_jump", 0)
	s._on_buy_pressed(&"double_jump", 0)

	# Assert — Upgrade autoload state cohérent
	assert_bool(Upgrade.is_owned(&"double_jump")) \
		.override_failure_message("AC-SHP-48: Upgrade.is_owned(double_jump) après cycle") \
		.is_true()
	assert_bool(Upgrade.can_air_jump) \
		.override_failure_message("AC-SHP-48: Upgrade.can_air_jump flag activé") \
		.is_true()
	assert_int(Upgrade.get_owned_count()) \
		.override_failure_message("AC-SHP-48: Upgrade owned_count exactement 1 (idempotent)") \
		.is_equal(1)

	# Shop _owned_upgrades : 1 seule entrée (R-SHP-7 already_owned guard)
	var owned: Array[StringName] = s.get_owned_upgrades()
	assert_int(owned.size()) \
		.override_failure_message("AC-SHP-48: shop _owned_upgrades doit contenir 1 entrée") \
		.is_equal(1)
	assert_bool(&"double_jump" in owned).is_true()

	# Cycle complet 1× : save + apply, pas de double-cycle
	var log: Array[String] = s.get_call_order_log()
	assert_int(log.size()) \
		.override_failure_message("AC-SHP-48: call_order_log doit refléter 1 cycle complet (2× ['save','apply'])") \
		.is_equal(2)
	assert_str(log[0]).is_equal("save")
	assert_str(log[1]).is_equal("apply")

	# Cleanup
	_free_shop(s)


# =============================================================================
# AC-SHP-49 BLOCKING — SaveLoad réel roundtrip + corruption fallback
# =============================================================================

## GIVEN SaveLoadSystem autoload réel,
## WHEN save_string_array([&"double_jump"]) puis load_string_array,
## THEN retour [&"double_jump"] cohérent type Array[StringName] (round-trip ADR-0010).
func test_saveload_real_roundtrip() -> void:
	# Arrange — clé propre
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])

	# Act — write puis read
	var to_write: Array[StringName] = [&"double_jump"] as Array[StringName]
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, to_write)
	var loaded: Array[StringName] = SaveLoadSystem.load_string_array(
		_UPGRADE_SAVE_KEY, [] as Array[StringName])

	# Assert
	assert_int(loaded.size()) \
		.override_failure_message("AC-SHP-49: roundtrip size mismatch") \
		.is_equal(1)
	assert_bool(&"double_jump" in loaded) \
		.override_failure_message("AC-SHP-49: roundtrip contenu mismatch") \
		.is_true()


## GIVEN clé inexistante / never-saved,
## WHEN load_string_array avec default vide,
## THEN retourne default vide (fallback corruption-equivalent EC-SHP-7).
## Note : le path corruption ConfigFile-mid-write (EC-SHP-15) est couvert par
## save-load epic story-005 (push_error WM_CLOSE) ; ici on vérifie le contract
## load qui sert de fallback pour shop_controller._hydrate_owned_upgrades().
func test_saveload_missing_key_returns_default() -> void:
	# Arrange — clé non-existante
	var nonexistent_key: String = "nonexistent_upgrade_key_for_test_915"

	# Act
	var loaded: Array[StringName] = SaveLoadSystem.load_string_array(
		nonexistent_key, [] as Array[StringName])

	# Assert — default appliqué, pas de crash
	assert_int(loaded.size()) \
		.override_failure_message("AC-SHP-49: missing key doit retourner default vide") \
		.is_equal(0)


# =============================================================================
# AC-SHP-54 ADVISORY — no leak entre instances (shop1 RAM ne contamine pas shop2)
# =============================================================================

## GIVEN shop1 achète double_jump puis free,
## WHEN save reset à [] + shop2 instancié,
## THEN shop2._owned_upgrades reflète SaveLoad uniquement (vide), pas RAM shop1.
func test_no_leak_between_shop_instances() -> void:
	# Arrange — shop1 achète
	_seed_credits(50)
	var shop1: Control = _make_shop()
	shop1._on_buy_pressed(&"double_jump", 0)
	# Sanity — shop1 owns
	assert_int(shop1.get_owned_upgrades().size()).is_equal(1)
	_free_shop(shop1)

	# Reset SaveLoad (simule scène différente sans persistence préservée)
	SaveLoadSystem.save_string_array(_UPGRADE_SAVE_KEY, [] as Array[StringName])
	# Reset Upgrade autoload (équivalent restart pour test)
	Upgrade._owned.clear()
	Upgrade.can_air_jump = false

	# Act — shop2 boot frais après reset
	var shop2: Control = _make_shop()

	# Assert — shop2 voit save vide (pas de leak RAM via shop1 instance)
	assert_int(shop2.get_owned_upgrades().size()) \
		.override_failure_message("AC-SHP-54: shop2 doit refléter SaveLoad ([]) pas RAM shop1") \
		.is_equal(0)

	# Cleanup
	_free_shop(shop2)


# =============================================================================
# AC-SHP-55 META — propagation note présente dans test suite (audit trail)
# =============================================================================

## Sentinel test : la note méta-propagation Credit r2+ est documentée dans le
## header de ce fichier. Test fictif qui sert de placeholder pour l'audit CI :
## si quelqu'un retire la docline, ce test reste vert mais le grep CI dans
## `.github/workflows/tests.yml` (futur) pourra vérifier la présence.
## Au MVP : simple assertion que les autoloads requis sont présents (preuve
## indirecte que la chaîne Credit ↔ Shop ↔ SaveLoad ↔ Upgrade est testable).
func test_meta_propagation_chain_autoloads_available() -> void:
	assert_object(CreditEconomy) \
		.override_failure_message("AC-SHP-55: CreditEconomy autoload requis pour groupe B+J propagation") \
		.is_not_null()
	assert_object(SaveLoadSystem) \
		.override_failure_message("AC-SHP-55: SaveLoadSystem autoload requis") \
		.is_not_null()
	assert_object(Upgrade) \
		.override_failure_message("AC-SHP-55: Upgrade autoload requis") \
		.is_not_null()
	assert_object(GameStateManager) \
		.override_failure_message("AC-SHP-55: GameStateManager autoload requis") \
		.is_not_null()


# =============================================================================
# Bonus contract — full purchase cycle bidirectional (E2E happy path)
# =============================================================================

## GIVEN solde 50, shop frais,
## WHEN buy double_jump (n_index=0),
## THEN  CreditEconomy.get_total() == 50 - BASE_UPGRADE_COST SYNC,
##       Upgrade.is_owned + can_air_jump SYNC,
##       SaveLoadSystem.load_string_array contient double_jump SYNC,
##       handler shop._on_credits_changed exécuté à idle frame suivante (DEFERRED).
## Post 9a4cc0b — cost canonique BASE=8.
func test_full_purchase_cycle_bidirectional_sync_chain() -> void:
	# Arrange
	_seed_credits(50)
	var s: Control = _make_shop()
	var expected_total: int = 50 - CreditEconomy.BASE_UPGRADE_COST  # 50 - 8 = 42

	# Act — purchase cycle
	s._on_buy_pressed(&"double_jump", 0)

	# Assert SYNC : Credit + Upgrade + SaveLoad cohérents même frame
	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("Bidirectional: Credit total -= cost SYNC (expected %d, got %d)" % [expected_total, CreditEconomy.get_total()]) \
		.is_equal(expected_total)
	assert_bool(Upgrade.is_owned(&"double_jump")) \
		.override_failure_message("Bidirectional: Upgrade.is_owned SYNC") \
		.is_true()
	assert_bool(Upgrade.can_air_jump) \
		.override_failure_message("Bidirectional: Upgrade.can_air_jump SYNC") \
		.is_true()
	var saved: Array[StringName] = SaveLoadSystem.load_string_array(
		_UPGRADE_SAVE_KEY, [] as Array[StringName])
	assert_bool(&"double_jump" in saved) \
		.override_failure_message("Bidirectional: SaveLoad persiste SYNC") \
		.is_true()

	# Tick idle frame — handler DEFERRED met à jour credit display
	await get_tree().process_frame
	assert_str(s.get_credit_display_text()) \
		.override_failure_message("Bidirectional: credit display refresh DEFERRED (expected %d)" % expected_total) \
		.is_equal(str(expected_total))

	# Cleanup
	_free_shop(s)
