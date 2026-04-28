# Autoload nom : Upgrade (registered project.godot après SaveLoadSystem — AC-UPG-3 BLOCKING)
# class_name UpgradeSystem (différent du nom autoload Upgrade — anti-collision Godot 4.6).
# Story-001 : skeleton + capability vars + process_mode. Stories 002/003/005 livrent
# Logger injection / apply_upgrade body / boot hydration.
extends Node
class_name UpgradeSystem

# =============================================================================
# Public capability vars (R-UPG-2)
# =============================================================================

var can_air_jump: bool = false
var can_dash: bool = false
var can_wall_run: bool = false

# =============================================================================
# Private state (stories 002/003/005 hydratent)
# =============================================================================

var _owned: Dictionary = {}                 # {StringName: bool}
var _is_hydrated: bool = false              # observable transition test (story 005)
var _logger: Object = null                  # injected story 002

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
	# apply_upgrade + boot hydration câblés stories 003/005.
