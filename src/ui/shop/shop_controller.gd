# ShopController — story-002 catalogue MVP + cost formula F-CRD-3 0-based.
# class_name ShopControllerScript : suffixe -Script anti-collision (memory
# `feedback_godot_class_name_autoload_collision`). Pas un autoload.
# Hydration / purchase / signals : stories 003-007.
class_name ShopControllerScript
extends Control

const N_UPGRADES_MVP: int = 2

const _CATALOG: Array[Dictionary] = [
	{ "id": &"double_jump",     "display_name": "Saut Double",     "n_index": 0 },
	{ "id": &"dash_horizontal", "display_name": "Dash Horizontal", "n_index": 1 },
]

# TODO Sprint 2 — replace fallbacks par CreditEconomy.BASE_UPGRADE_COST /
# TIER_COST_STEP quand exposés (Credit Economy story-008+).
const _BASE_COST_FALLBACK: int = 20
const _TIER_COST_STEP_FALLBACK: int = 20

const _SAVE_KEY: String = "owned_upgrades"

var _owned_upgrades: Array[StringName] = []
var _credit_display_text: String = ""    # story-004 — pull depuis CreditEconomy
var _purchase_in_progress: bool = false  # story-005/006 — double-click guard

# Test seam — journal d'ordre d'appels (5b → 5c) pour AC-SHP-8 séquencement strict.
# Production runtime : pas d'overhead (append seulement debug-introspectable).
var _call_order_log: Array[String] = []


func _ready() -> void:
	if OS.has_feature("debug"):
		assert(_CATALOG.size() == N_UPGRADES_MVP,
			"Catalogue size %d != N_UPGRADES_MVP %d" % [_CATALOG.size(), N_UPGRADES_MVP])
	_hydrate_owned_upgrades()
	_pull_initial_credit_display()
	# Story-007 : connect credits_changed CONNECT_DEFERRED


# Story-004 — boot pull pattern (ADR-0007 D-9, EC-SHP-4 BOOT_HYDRATE perdu protégé).
# Lecture passive non-mutante du total credits courant. À appeler dans _ready()
# AVANT toute connexion `credits_changed` ou `await`. Stocke le texte formaté
# pour assignation au CreditValueLabel quand le scene est ready (story-005+).
func _pull_initial_credit_display() -> void:
	_credit_display_text = str(CreditEconomy.get_total())


# Test seam — lecture publique du texte credit affiché (post-pull initial).
func get_credit_display_text() -> String:
	return _credit_display_text


# Story-003 : boot hydration depuis SaveLoadSystem.
# SaveLoadSystem.load_string_array filtre déjà les éléments non-StringName/String
# côté SaveLoad (ADR-0010 D-2 + R-SAV-12), donc le retour typé Array[StringName]
# est trusty. IDs inconnus (Tier 2+) conservés silencieusement (EC-SHP-8 forward-safe).
func _hydrate_owned_upgrades() -> void:
	_owned_upgrades = SaveLoadSystem.load_string_array(
		_SAVE_KEY, [] as Array[StringName])


# Test seam — get_owned_upgrades() lecture publique pour assert tests integration.
func get_owned_upgrades() -> Array[StringName]:
	return _owned_upgrades.duplicate() as Array[StringName]


func _compute_cost(n: int) -> int:
	if n < 0:
		push_warning("ShopSystem: _compute_cost called with negative n (%d)" % n)
		return 0
	if n >= N_UPGRADES_MVP:
		push_error("ShopSystem: _compute_cost n=%d > MAX_UPGRADE_INDEX=%d" % [n, N_UPGRADES_MVP - 1])
		return 0
	return _BASE_COST_FALLBACK + _TIER_COST_STEP_FALLBACK * n


# Story-005 — purchase cycle 6 étapes déterministes SYNC.
# (1) guard already_owned (R-SHP-7 silent no-op idempotence partielle)
# (2) guard _purchase_in_progress (story-006 double-click)
# (3) _compute_cost + EC-SHP-2 assert cost > 0
# (4) pre-check affordability passive get_total() < cost (F-SHP-2 non-mutant)
# (5a) try_spend SYNC atomique  (5b) _owned.append + save_string_array
# (5c) Upgrade.apply_upgrade SYNC (chain-blocked Upgrade r1 ✅ Sprint 1 ready)
# (6) BuyButton.disabled=true (test seam : skip if button absent)
# Aucun await/yield entre étapes — atomicité call stack EC-SHP-23.
func _on_buy_pressed(id: StringName, n_index: int) -> void:
	# Étape 1 — already owned silent no-op (R-SHP-7)
	if _owned_upgrades.has(id):
		return

	# Étape 2 — double-click guard (story-006 raffinement)
	if _purchase_in_progress:
		return

	# Étape 3 — cost computation + EC-SHP-2 guard.
	# `_compute_cost` retourne 0 sur n_index invalide (négatif/OOB) avec
	# warning/error. Early return sans crash : assert remplacé par soft guard
	# pour rester runtime-safe (debug + release identiques).
	var cost: int = _compute_cost(n_index)
	if cost <= 0:
		return    # EC-SHP-2: cost invalide ou n_index pathologique

	# Étape 4 — pre-check affordability passive (F-SHP-2 — pas de mutation)
	if CreditEconomy.get_total() < cost:
		# DISABLED click feedback story-013
		return

	_purchase_in_progress = true

	# Étape 5a — atomic try_spend SYNC (peut échouer si race solde EC-SHP-1)
	if not CreditEconomy.try_spend(cost):
		_purchase_in_progress = false
		return

	# Étape 5b — RAM mark + persist disk SYNC (ordre 5b AVANT 5c — EC-SHP-16/23 atomicity)
	_owned_upgrades.append(id)
	SaveLoadSystem.save_string_array(_SAVE_KEY, _owned_upgrades)
	_call_order_log.append("save")

	# Étape 5c — gameplay activation SYNC
	Upgrade.apply_upgrade(id)
	_call_order_log.append("apply")

	# Étape 6 — UI button disable (test seam — skip if not in scene tree)
	_disable_buy_button_for(id)

	_purchase_in_progress = false


# Story-005 helper — résout BuyButton via NodePath unique-name OU skip silently
# si pas attaché au scene (test seam pour unit tests hors scene tree).
func _disable_buy_button_for(id: StringName) -> void:
	var button_name: StringName = "BuyButton_%s" % id
	var button: Button = get_node_or_null(NodePath("%" + str(button_name))) as Button
	if button == null:
		return    # scene-attach context absent (story-005+ scene wiring)
	button.disabled = true
	button.text = "POSSÉDÉ"


# Test seam — lecture publique journal séquencement (AC-SHP-8 ordre 5b→5c).
func get_call_order_log() -> Array[String]:
	return _call_order_log.duplicate() as Array[String]


# Test seam — reset entre tests (autoload-free instance bare).
func reset_call_order_log_for_test() -> void:
	_call_order_log.clear()


# Test seams story-006 — accès `_purchase_in_progress` pour simuler race
# window in-flight (impossible en GDScript SYNC sans injection manuelle).
func set_purchase_in_progress_for_test(value: bool) -> void:
	_purchase_in_progress = value


func get_purchase_in_progress_for_test() -> bool:
	return _purchase_in_progress
