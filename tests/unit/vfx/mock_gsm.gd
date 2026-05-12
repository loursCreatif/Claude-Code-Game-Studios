# MockGSM — fixture minimale pour tests VFX story-001.
#
# Expose le même contrat que GameStateManagerScript :
#   - signal state_changed(new_state: int)
#   - get_current_state() → int (retourne PLAYING=1 par défaut pour boot ADR-0007 D-9)
#   - set_state() pour setup de test
#
# Pas de class_name — évite collision cache headless CI.
# Pattern : miroir du mock_gsm.gd HUD epic.

extends Node


# ---------------------------------------------------------------------------
# Enum (miroir GameStateManagerScript.State)
# ---------------------------------------------------------------------------

enum State {
	MENU        = 0,
	PLAYING     = 1,
	PAUSED      = 2,
	RESPAWNING  = 3,
	BOSS_DEFEATED = 4,
}


# ---------------------------------------------------------------------------
# Signal
# ---------------------------------------------------------------------------

signal state_changed(new_state: int)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Défaut PLAYING=1 (pull pattern boot ADR-0007 D-9 — VFXSystem active au boot).
var _current_state: int = State.PLAYING


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func get_current_state() -> int:
	return _current_state


func set_state(s: int) -> void:
	_current_state = s


func emit_state_changed(new_state: int) -> void:
	_current_state = new_state
	state_changed.emit(new_state)
