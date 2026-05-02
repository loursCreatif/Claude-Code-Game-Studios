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

## Story-006 — MVP MainMenu lance toujours l'étage 1 (R-MNU-8 pas de Continue MVP).
const MVP_START_ETAGE_ID: int = 1

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var version_label: Label = $VBoxContainer/VersionLabel

## Test seams — overridables pour isoler les callbacks dans les tests integration.
## Default routent vers les autoloads / get_tree() comme prévu R-MNU-7/8.
##   _start_handler : appelle GSM.start_etage(MVP_START_ETAGE_ID) — story-006 R-MNU-7.
##   _quit_handler  : appelle get_tree().quit() — story-006 R-MNU-8.
##
## Tests les remplacent par des spies (Callable) pour observer call count + args sans
## déclencher LevelSystem.load_etage (file inexistant Sprint A) ou get_tree().quit()
## qui terminerait le runner.
var _start_handler: Callable = func() -> void:
	GameStateManager.start_etage(MVP_START_ETAGE_ID)
var _quit_handler: Callable = func() -> void:
	get_tree().quit()


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


## Story-006 R-MNU-7 — Start Run lance toujours l'étage 1 (pas de Continue MVP).
## Pas de guard côté Menu (Implementation Notes §4) — GSM ADR-0007 D-7 absorbe via
## `if not LevelSystem.level_active.is_connected: connect` (no double-connect).
## R-MNU-11 — zéro confirm dialog : exécute direct (anti-Pillar 1 friction).
func _on_start_pressed() -> void:
	_start_handler.call()


## Story-006 R-MNU-8 — Quit direct via get_tree().quit().
## Save-on-quit délégué intégralement à SaveLoad R-SAV-9 (NOTIFICATION_WM_CLOSE_REQUEST).
## Menu ne référence JAMAIS SaveLoad APIs (AC-MNU-57 enforce).
func _on_quit_pressed() -> void:
	_quit_handler.call()
