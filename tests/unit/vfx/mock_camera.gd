# MockCamera — fixture minimale pour tests VFX story-001.
#
# Expose le contrat upstream Camera consommé par VFXSystem :
#   - signal died()
#   - signal respawned(position: Vector3)
#
# Pas de class_name — évite collision cache headless CI.

extends Node


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal died()
signal respawned(position: Vector3)


# ---------------------------------------------------------------------------
# Helpers test
# ---------------------------------------------------------------------------

func emit_died() -> void:
	died.emit()


func emit_respawned(position: Vector3 = Vector3.ZERO) -> void:
	respawned.emit(position)
