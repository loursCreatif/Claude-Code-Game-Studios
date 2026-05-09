# MockAccessibility — fixture minimale pour tests VFX story-001.
#
# Expose le contrat upstream AccessibilityService consommé par VFXSystem :
#   - signal settings_changed()
#   - reduce_flash: bool — désactive effets flash (WCAG story-005)
#   - flash_mult: float — multiplicateur durée flash (default 1.0)
#   - reduce_motion: bool — désactive trail / animations (story-005)
#
# Pas de class_name — évite collision cache headless CI.

extends Node


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

signal settings_changed()


# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------

var reduce_flash: bool = false
var flash_mult: float = 1.0
var reduce_motion: bool = false


# ---------------------------------------------------------------------------
# Helpers test
# ---------------------------------------------------------------------------

func emit_settings_changed() -> void:
	settings_changed.emit()
