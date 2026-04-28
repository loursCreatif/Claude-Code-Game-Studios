# Autoload nom : Upgrade (registered project.godot après SaveLoadSystem — AC-UPG-3 BLOCKING)
# class_name UpgradeSystem (différent du nom autoload Upgrade — anti-collision Godot 4.6).
# Story-001 : skeleton + capability vars + process_mode.
# Story-002 : Logger DI + apply_upgrade step 1 (unknown id warning + early return).
# Stories 003/005 livrent body apply_upgrade complet + boot hydration.
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
	# apply_upgrade body complet + boot hydration câblés stories 003/005.


# =============================================================================
# Public API
# =============================================================================

## Applique un upgrade par identifiant catalogue.
## Story-002 : implémente uniquement step 1 — id inconnu → warning + early return.
## Stories 003/004 livrent steps 2 (resync guard) / 3 (helper _apply_flag) / 4 (idempotence).
func apply_upgrade(id: StringName) -> void:
	if not _CATALOG.has(id):
		_logger.warn("UpgradeSystem: unknown upgrade id '%s'" % id)
		return
	# Steps 2/3/4 livrés stories 003/004.


## Compteur d'upgrades possédés (helper observable test AC-UPG-10).
func get_owned_count() -> int:
	return _owned.size()


# =============================================================================
# Test-only API (debug builds uniquement — assert release)
# =============================================================================

## Setter Logger DI réservé aux tests. Asserté hors-debug pour empêcher
## l'usage en code production (R-UPG-9 + GDD r2 B-11 testabilité).
func set_logger_for_test(logger: UpgradeLogger) -> void:
	assert(OS.has_feature("debug"), "set_logger_for_test forbidden in release")
	_logger = logger
