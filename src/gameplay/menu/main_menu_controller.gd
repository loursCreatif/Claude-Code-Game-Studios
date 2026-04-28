class_name MainMenuControllerScript
extends Control

## Main Menu controller — boot lifecycle + focus + mouse capture release.
##
## Source : ADR-0007 D-9 (pull pattern) + R-MNU-1/2/8 (zéro autoload, scène container, quit direct).
## Pattern : Menu lit GSM.get_current_state() au _ready(), jamais d'emit state_changed.
##
## Usage : attaché comme script root de scenes/menus/main_menu.tscn.
## Connections : start_button.pressed → _on_start_pressed (story-006 implémentation réelle)
##               quit_button.pressed  → _on_quit_pressed  (story-006 implémentation réelle)

const DEBUG_SHOW_VERSION: bool = false

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var version_label: Label = $VBoxContainer/VersionLabel


func _ready() -> void:
	# Sanity : on est censé être en MENU, donc pas de pause active.
	assert(get_tree().paused == false, "MainMenu loaded with tree paused — invalid state")
	# Sanity ADR-0007 D-9 pull pattern : on lit l'état initial sans le muter.
	assert(GameStateManager.get_current_state() == GameStateManager.State.MENU,
		"MainMenu expects GSM in MENU state at _ready (got %s)" % GameStateManager.State.keys()[GameStateManager.get_current_state()])

	# R-MNU-12 — mouse libre en menu (release toute capture héritée d'un étage précédent).
	InputManager.set_mouse_captured(false)

	# AC-MNU-2 — StartButton focus exactement 1× au boot.
	start_button.grab_focus()

	# Connexions boutons — handlers stubs (story-006 livrera l'implémentation réelle).
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# VersionLabel debug-gated (DEBUG_SHOW_VERSION = false MVP).
	version_label.visible = DEBUG_SHOW_VERSION


func _on_start_pressed() -> void:
	# TODO story-006 : appeler GameStateManager.start_etage(1).
	pass


func _on_quit_pressed() -> void:
	# TODO story-006 : implémentation finale (R-MNU-8 = get_tree().quit() direct, zéro confirm).
	pass
