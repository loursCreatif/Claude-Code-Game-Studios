extends Node3D

# Init temporaire MVP — capture la souris + débloque abilities + ajoute bindings alternatifs.
# À retirer quand GSM `_on_level_active` + UpgradeSystem orchestrent (story Production).

func _ready() -> void:
	InputManager.set_mouse_captured(true)

	# MVP playtest : bindings alternatifs au cas où Shift gauche ne marche pas sur Mac.
	# Ajoute touche E pour dash, F pour saut alternatif.
	_add_key_binding(&"dash", KEY_E)
	_add_key_binding(&"jump", KEY_F)

	# MVP playtest : si etage_01 charge alors que le main_menu est encore affiché
	# (cas du flow Menu → Start → etage_01 en parallèle plutôt que change_scene),
	# free le main_menu pour libérer la vue gameplay.
	_dispose_main_menu_if_present()

	# Proto player a déjà toutes les abilities par défaut (can_dash=true, double-jump natif).

func _dispose_main_menu_if_present() -> void:
	# Cherche un Control nommé "MainMenuController" dans le scene tree root.
	for node: Node in get_tree().root.get_children():
		if node.name == "MainMenuController" or _has_descendant_named(node, "MainMenuController"):
			print("[etage_01_init] main_menu détecté — libération")
			if node.name == "MainMenuController":
				node.queue_free()
			else:
				node.find_child("MainMenuController", true, false).queue_free()
			return

func _has_descendant_named(node: Node, target_name: String) -> bool:
	return node.find_child(target_name, true, false) != null

func _add_key_binding(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		push_warning("[etage_01_init] action %s absente" % action)
		return
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	print("[etage_01_init] +binding action=%s keycode=%d" % [action, keycode])
