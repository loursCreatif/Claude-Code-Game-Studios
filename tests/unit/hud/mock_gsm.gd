# MockGSM — fixture minimale pour tests HUD (story-001).
#
# Expose le même contrat que GameStateManagerScript :
#   - enum State identique (MENU=0, PLAYING=1, ...)
#   - signal state_changed(new_state: int)
#   - get_current_state() avec compteur d'appels
#   - set_state() pour setup de test
#
# Pas de class_name — évite collision cache headless CI.
# Pattern : même convention que mock_audio_handler.gd (combat).

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

var _current_state: int = State.MENU

## Spy : nombre de fois que get_current_state() a été appelé. Réinitialisé manuellement par les tests.
var get_current_state_call_count: int = 0

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func get_current_state() -> int:
	get_current_state_call_count += 1
	return _current_state

## Configure l'état courant du mock pour le setup de test.
func set_state(s: int) -> void:
	_current_state = s

## Émet state_changed pour simuler une transition d'état en test.
func emit_state_changed(new_state: int) -> void:
	_current_state = new_state
	state_changed.emit(new_state)
