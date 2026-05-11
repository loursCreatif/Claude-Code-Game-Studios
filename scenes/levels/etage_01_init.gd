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
	# Hide (pas queue_free) le main_menu — le free de la main scene casserait
	# get_tree().current_scene et les inputs ne seraient plus routés correctement.
	# hide() rend invisible + désactive le process Control (mouse_filter input).
	for node: Node in get_tree().root.get_children():
		if node.name == "MainMenuController":
			print("[etage_01_init] main_menu hide()")
			(node as Control).visible = false
			# Désactive aussi le process pour éviter que le menu réagisse aux inputs.
			node.process_mode = Node.PROCESS_MODE_DISABLED
			return

func _add_key_binding(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		push_warning("[etage_01_init] action %s absente" % action)
		return
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	print("[etage_01_init] +binding action=%s keycode=%d" % [action, keycode])
