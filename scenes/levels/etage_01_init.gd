extends Node3D

# Init temporaire MVP — capture la souris en gameplay quand etage_01 charge.
# À retirer quand GSM `_on_level_active` orchestre proprement (story Production).

func _ready() -> void:
	InputManager.set_mouse_captured(true)
