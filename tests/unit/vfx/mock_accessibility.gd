# MockAccessibility — fixture minimale pour tests VFX story-001/005.
#
# Expose le contrat upstream AccessibilityService consommé par VFXSystem :
#   - signal settings_changed()
#   - Properties direct (test setup) : reduce_flash, flash_mult, reduce_motion
#   - Methods getter (delegate properties — API surface canonique real service) :
#     is_reduce_flash_enabled(), is_reduce_motion_enabled(), get_flash_mult()
#
# Tests setters : `mock.reduce_flash = true` puis `mock.emit_settings_changed()`.
# VFX consume via methods (cohérent avec accessibility_service.gd).
#
# Pas de class_name — évite collision cache headless CI.

extends Node


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

signal settings_changed()


# ---------------------------------------------------------------------------
# Properties — settables directement par les tests pour mocking
# ---------------------------------------------------------------------------

var reduce_flash: bool = false
var flash_mult: float = 1.0
var reduce_motion: bool = false


# ---------------------------------------------------------------------------
# Methods getter — API surface canonique real AccessibilityService
# (story-005 — VFX consume via methods, pas accès direct properties)
# ---------------------------------------------------------------------------

func is_reduce_flash_enabled() -> bool:
	return reduce_flash


func is_reduce_motion_enabled() -> bool:
	return reduce_motion


func get_flash_mult() -> float:
	return flash_mult


# ---------------------------------------------------------------------------
# Helpers test
# ---------------------------------------------------------------------------

func emit_settings_changed() -> void:
	settings_changed.emit()
