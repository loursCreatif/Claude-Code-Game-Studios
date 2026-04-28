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


func _ready() -> void:
	if OS.has_feature("debug"):
		assert(_CATALOG.size() == N_UPGRADES_MVP,
			"Catalogue size %d != N_UPGRADES_MVP %d" % [_CATALOG.size(), N_UPGRADES_MVP])
	_hydrate_owned_upgrades()
	# Story-004 : credit display init via CreditEconomy.get_total_credits()
	# Story-007 : connect credits_changed CONNECT_DEFERRED


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
