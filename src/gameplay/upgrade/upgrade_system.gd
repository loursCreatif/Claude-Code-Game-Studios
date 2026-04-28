# Autoload nom : Upgrade (registered project.godot après SaveLoadSystem — AC-UPG-3 BLOCKING)
# class_name UpgradeSystem (différent du nom autoload Upgrade — anti-collision Godot 4.6).
# Story-001 : skeleton + capability vars + process_mode.
# Story-002 : Logger DI + apply_upgrade step 1 (unknown id warning + early return).
# Story-003 : apply_upgrade body steps 2 (cas A/B idempotent strict) + 3 + 4 +
#             helper _apply_flag (3 asserts) + is_owned. R-UPG-4 SYNC contract.
# Story-004 : step 2 r2 cas C/D resync (couvert par formulation existante).
# Story-005 : boot hydration _ready() via SaveLoadSystem.load_string_array →
#             boucle apply_upgrade idempotente → _is_hydrated=true.
# Story-006 : save bloat truncation defense (cap dur 14 = MAX_CATALOG_SIZE_TIER_2 × 2).
extends Node
class_name UpgradeSystem

# =============================================================================
# Public capability vars (R-UPG-2)
# =============================================================================

var can_air_jump: bool = false
var can_dash: bool = false
var can_wall_run: bool = false

# =============================================================================
# Private state (stories 003/005 hydratent davantage)
# =============================================================================

var _owned: Dictionary = {}                 # {StringName: bool}
var _is_hydrated: bool = false              # observable transition test (story 005)
var _logger: UpgradeLogger = null           # story-002 Logger DI (default = wrapper push_warning)

# =============================================================================
# Constants — catalogue figé Tier 1
# =============================================================================

const _CATALOG: Dictionary = {
	&"double_jump":     &"can_air_jump",
	&"dash_horizontal": &"can_dash",
}
const MAX_CATALOG_SIZE_TIER_2: int = 7

# =============================================================================
# Built-in virtual methods
# =============================================================================

func _ready() -> void:
	# ADR-0007 D-4 : process_mode ALWAYS pour autoload pause-resilient.
	# Erratum 1649049 (commit 2026-04-28) : PROCESS_MODE_ALWAYS == 3 en Godot 4.6
	# (PAS 4 qui est PROCESS_MODE_DISABLED — double-assert AC-UPG-4 protège la régression).
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(process_mode == 3,
		"UpgradeSystem: process_mode != 3 (PROCESS_MODE_ALWAYS Godot 4.6 erratum 1649049)")
	# Story-002 : Logger DI default (production = wrapper push_warning).
	# Tests injectent un TestUpgradeLogger via set_logger_for_test() avant set-up.
	if _logger == null:
		_logger = UpgradeLogger.new()
	_hydrate_from_save()


# =============================================================================
# Boot hydration (R-UPG-5 + ADR-0010 — story-005)
# =============================================================================

## Charge `owned_upgrades` via SaveLoadSystem et applique chaque upgrade SYNC.
## Garantit `_is_hydrated == true` à la sortie (R-UPG-5 step 4 + AC-UPG-5/23).
## Story-006 livrera la truncation save bloat pré-boucle (EC-UPG-36).
func _hydrate_from_save() -> void:
	# Step 1 — load via SaveLoadSystem (R-UPG-5 step 1 + ADR-0010 R-SAV-4).
	# Le verbe est typé `Array[StringName]` côté SaveLoadSystem — valeur returnée
	# toujours conforme au type, mais on défense malgré tout (EC-UPG-3).
	var owned: Variant = SaveLoadSystem.load_string_array(
		"owned_upgrades", [] as Array[StringName])

	# EC-UPG-3 type guard belt-and-suspenders. SaveLoadSystem garde déjà le type
	# en interne (push_warning + return default si raw non-Array), mais Upgrade
	# se protège indépendamment au cas où la signature serait régressée Tier 2+.
	if not (owned is Array):
		_logger.warn("UpgradeSystem: load_string_array returned non-Array (corrupt save), fallback to empty")
		owned = [] as Array[StringName]

	# Step 2 — save bloat truncation defense (story-006 + EC-UPG-36).
	# Cap dur 14 = MAX_CATALOG_SIZE_TIER_2 (7) × 2. Au-delà, save corrompue ou
	# édition manuelle ; on évite le freeze 2-10 s sur 1M entrées en tronquant
	# silencieusement les 14 premières + warning audit. AC-UPG-44/45.
	var max_size: int = MAX_CATALOG_SIZE_TIER_2 * 2
	if owned.size() > max_size:
		_logger.warn("UpgradeSystem: save bloat (size=%d), truncating to %d" % [owned.size(), max_size])
		owned = owned.slice(0, max_size)

	# Step 3 — boucle apply_upgrade idempotent (R-UPG-5 step 3).
	# `_is_hydrated` reste `false` pendant toute la boucle (AC-UPG-23 mid-execution).
	for id: Variant in owned:
		# R-UPG-9 : skip silencieux les éléments non-StringName (SaveLoadSystem
		# normalise String→StringName mais d'autres types passeraient skip ici).
		if typeof(id) != TYPE_STRING_NAME:
			continue
		apply_upgrade(id)

	# Step 4 — flag d'hydration final (R-UPG-5 step 4 + R-1 rename _boot_complete).
	_is_hydrated = true


# =============================================================================
# Public API
# =============================================================================

## Applique un upgrade identifié par [param id]. SYNC — aucun await ni yield.
## Idempotent — deux appels même id = même état (R-UPG-4 + AC-UPG-9).
## Story-003 : steps 1 + 2 (cas A/B) + 3 + 4. Story-004 livrera cas C/D resync.
func apply_upgrade(id: StringName) -> void:
	# Step 1 — id validation (Logger DI story-002).
	if not _CATALOG.has(id):
		_logger.warn("UpgradeSystem: unknown upgrade id '%s'" % id)
		return

	var flag_name: StringName = _CATALOG[id]

	# Step 2 — cas A (nominal) + cas B (idempotent strict).
	# Cas C/D resync (_owned vs flag mismatch) : story-004 AC-UPG-9-bis.
	if _owned.has(id) and get(flag_name) == true:
		return

	# Step 3 — marquer owned (idempotent au niveau Dictionary).
	_owned[id] = true

	# Step 4 — appliquer le flag via helper validé.
	_apply_flag(flag_name)


## Retourne true si [param id] est possédé, false sinon (R-UPG-4 step 3 observable).
func is_owned(id: StringName) -> bool:
	return _owned.has(id)


## Compteur d'upgrades possédés (helper observable test AC-UPG-10/13).
func get_owned_count() -> int:
	return _owned.size()


# =============================================================================
# Private helpers
# =============================================================================

## Applique [code]true[/code] à la propriété booléenne identifiée par [param flag_name].
## Validation runtime : la propriété doit exister sur self, doit être de type [code]bool[/code],
## et le set() doit prendre effet (assert post-set). Source : GDD r2 review B-3 Section C.1.
## Asserts strippés en build release — admis Tier 1 (F-UPG-3 catalog sanity test couvre build-time).
func _apply_flag(flag_name: StringName) -> void:
	var props: Array[StringName] = []
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props.append(p.name)
	assert(flag_name in props,
		"UpgradeSystem._apply_flag: catalog points to unknown property '%s' (catalog/source desync — F-UPG-3 should have caught this in CI)" % flag_name)

	var current_type: int = typeof(get(flag_name))
	assert(current_type == TYPE_BOOL,
		"UpgradeSystem._apply_flag: catalog target '%s' is not bool (typeof=%d) — Tier 2+ var declared with wrong type ?" % [flag_name, current_type])

	set(flag_name, true)

	assert(get(flag_name) == true,
		"UpgradeSystem._apply_flag: set(%s, true) failed silently — property may be read-only or shadowed" % flag_name)


# =============================================================================
# Test-only API (debug builds uniquement — assert release)
# =============================================================================

## Setter Logger DI réservé aux tests. Asserté hors-debug pour empêcher
## l'usage en code production (R-UPG-9 + GDD r2 B-11 testabilité).
func set_logger_for_test(logger: UpgradeLogger) -> void:
	assert(OS.has_feature("debug"), "set_logger_for_test forbidden in release")
	_logger = logger
