# MockCombat — fixture minimale pour tests VFX story-001.
#
# Expose le contrat upstream Combat consommé par VFXSystem :
#   - signal swing_started(direction: Vector3)
#   - signal swing_ended()
#   - signal multi_kill(count: int)
#
# Pas de class_name — évite collision cache headless CI.
# Pattern : même convention que mock_gsm.gd (HUD epic).

extends Node


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal swing_started(direction: Vector3)
signal swing_ended()
signal multi_kill(count: int)


# ---------------------------------------------------------------------------
# Helpers test
# ---------------------------------------------------------------------------

func emit_swing_started(direction: Vector3 = Vector3.ZERO) -> void:
	swing_started.emit(direction)


func emit_swing_ended() -> void:
	swing_ended.emit()


func emit_multi_kill(count: int = 2) -> void:
	multi_kill.emit(count)
