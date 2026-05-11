extends Node3D

# Init temporaire MVP — capture la souris + débloque abilities + ajoute bindings alternatifs.
# À retirer quand GSM `_on_level_active` + UpgradeSystem orchestrent (story Production).

func _ready() -> void:
	InputManager.set_mouse_captured(true)

	# MVP playtest : bindings alternatifs au cas où Shift gauche ne marche pas sur Mac.
	# Ajoute touche E pour dash, F pour saut alternatif.
	_add_key_binding(&"dash", KEY_E)
	_add_key_binding(&"jump", KEY_F)

	# Proto player a déjà toutes les abilities par défaut (can_dash=true, double-jump natif).

func _add_key_binding(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		push_warning("[etage_01_init] action %s absente" % action)
		return
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	print("[etage_01_init] +binding action=%s keycode=%d" % [action, keycode])
