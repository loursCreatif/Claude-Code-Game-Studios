# MockEnemy — fixture minimale pour tests VFX story-001.
#
# Expose le contrat upstream Enemy consommé par VFXSystem :
#   - signal enemy_killed(enemy: Node, position: Vector3)
#
# Pas de class_name — évite collision cache headless CI.

extends Node


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal enemy_killed(enemy: Node, position: Vector3)


# ---------------------------------------------------------------------------
# Helpers test
# ---------------------------------------------------------------------------

func emit_enemy_killed(enemy: Node = null, position: Vector3 = Vector3.ZERO) -> void:
	enemy_killed.emit(enemy, position)
