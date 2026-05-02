class_name PauseMenuControllerScript
extends CanvasLayer

## Pause Menu controller — boot lifecycle + state sync.
##
## Source : ADR-0007 D-4 (process_mode discipline) + D-9 (pull pattern) + D-10
## (state_changed signal contract) ; ADR-0004 D-4 (ui_cancel_pressed always-fire) ;
## R-MNU-3/4/5/6/14/18 (CanvasLayer node-local, héritage process_mode, anti-deps).
##
## Pattern : CanvasLayer racine `PauseLayer` (G-14 r2 naming canonique), instancié
## node-local par chaque scène d'étage (pas autoload, R-MNU-1).
##
## Stories suivantes :
##   - 003 ✅ : trigger ESC ui_cancel_pressed connect → request_pause/resume
##   - 004 ✅ : handler _on_gsm_state_changed complet + CONNECT_DEFERRED + guard is_inside_tree()
##   - 005 : implémentation complète _apply_visibility(show, recapture_mouse) avec mouse capture
##   - 007 : callbacks boutons Resume / MainMenu / Quit
##   - 008 : refcount Input + tree_exiting cleanup détail
##   - 009 : Theme/palette/typo

## Story-009 — Chrome Zen palette tokens K.4 (anti-hex-hardcode AC-MNU-51).
## Source : design/gdd/menu-system.md §K.4 Palette et tokens.
const MENU_BG_BLACK: Color    = Color("050608")
const MENU_PANEL_BG: Color    = Color("0A0A12")
const MENU_TEXT_BASE: Color   = Color("E8E8F0")
const MENU_ACCENT_CYAN: Color = Color("3EE4FF")
const MENU_BG_OVERLAY_ALPHA: float = 0.65  # F-MNU-2 dim alpha (Story 005 use, range Tuning Knob [0.55, 0.75])

@onready var dim_rect: ColorRect = $DimRect
@onready var pause_panel: PanelContainer = $PausePanel
@onready var resume_button: Button = $PausePanel/VBoxContainer/ResumeButton
@onready var main_menu_button: Button = $PausePanel/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $PausePanel/VBoxContainer/QuitButton

## Story-007 — chemin canonique Main Menu (constante MVP, pas de Continue R-MNU-8).
const MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu.tscn"

## Story-003 AC-MNU-16 — 1-frame guard contre double-press même frame physique.
## En réalité ESC fire 1× par event, mais défensif contre re-emit synthétique
## qui oscillerait PLAYING ↔ PAUSED si on relit GSM entre deux .emit() synchrones.
var _ui_cancel_handled_frame: int = -1

## Story-008 — test seam pour `InputManager.set_mouse_captured`. Headless mode
## (godot --headless) rejette silencieusement les changements de `Input.mouse_mode`,
## donc la lecture-arrière ne valide pas le comportement de la production. Le seam
## permet aux tests d'observer les appels via spy, sans toucher l'API réelle.
## Default : route strictement vers `InputManager.set_mouse_captured(captured)`.
var _set_mouse_captured_handler: Callable = func(captured: bool) -> void:
	InputManager.set_mouse_captured(captured)

## Story-007 — test seams Callable pour isoler les callbacks dans les tests
## integration sans déclencher `change_scene_to_file` (terminerait le node de test
## via tree_exiting) ni `get_tree().quit()` (terminerait le runner).
## Defaults routent strictement vers `GSM.request_scene_transition(MAIN_MENU_SCENE_PATH)`
## et `get_tree().quit()` — production runtime inchangée. Cohérent story-006 pattern.
var _main_menu_handler: Callable = func() -> void:
	GameStateManager.request_scene_transition(MAIN_MENU_SCENE_PATH)
var _quit_handler: Callable = func() -> void:
	get_tree().quit()


func _ready() -> void:
	# AC-MNU-37 / R-MNU-18 — set programmatique défensif au-delà du .tscn (preuve runtime).
	# Godot 4.6 erratum 2026-04-28 : PROCESS_MODE_ALWAYS == 3 (PAS 4 = DISABLED).
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(process_mode == 3,
		"PauseLayer.process_mode must equal 3 (PROCESS_MODE_ALWAYS) — got %d" % process_mode)

	# Story-005 AC-MNU-8 — group helper pour query lifecycle scene transition.
	add_to_group(&"pause_overlay")

	# AC-MNU-6 / EC-MNU-32 / EC-MNU-40 — anti-flash : panel + dim cachés immédiat avant toute frame visible.
	pause_panel.visible = false
	dim_rect.visible = false

	# Story-004 — state sync. ADR-0007 D-10 : signal state_changed SYNC GSM-side, mais
	# CONNECT_DEFERRED côté Menu pour absorber la r2 BLK-1 race fenêtre où
	# `get_tree().paused = true` n'est pas encore propagé tree-wide quand le handler
	# tournerait synchrone. Le 1-frame skid garantit propagation complète.
	GameStateManager.state_changed.connect(_on_gsm_state_changed, CONNECT_DEFERRED)

	# ADR-0007 D-9 pull pattern boot resync (couvre EC-MNU-31 PRE_READY + AC-MNU-35 :
	# overlay ajouté à scène déjà PAUSED doit recevoir l'état initial sans attendre
	# la prochaine transition). Appel SYNC interne — pas via signal, donc pas de skid.
	_on_gsm_state_changed(GameStateManager.get_current_state())

	# Story-003 — ESC trigger pause/resume. ADR-0004 D-4 : ui_cancel_pressed est émis
	# même sous _enabled == false (R-MNU-5 garanti). Mode SYNC default — handler léger.
	InputManager.ui_cancel_pressed.connect(_on_ui_cancel_pressed)

	# Story-007 — connexions boutons Pause Menu. Resume/MainMenu/Quit callbacks
	# implémentent l'ordre release-avant-transition critique (R-MNU-10, ADR-0004 D-4).
	resume_button.pressed.connect(_on_resume_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Story-008 livrera le détail refcount Input ; ici on pose la connexion cleanup
	# pour garantir qu'aucune scène d'étage ne quitte sans libérer ses captures.
	tree_exiting.connect(_on_tree_exiting)


## Story-003 — ESC trigger handler.
##
## Idempotence (AC-MNU-16) : 1-frame guard côté Menu pour empêcher l'oscillation
## PLAYING → PAUSED → PLAYING quand 2 emits synchrones arrivent dans la même frame
## physique (le 2e emit re-lirait GSM déjà transitionné, et appellerait request_resume).
## Matrice ADR-0007 D-2 : RESPAWNING/BOSS_DEFEATED/MENU = no-op (`_:` branche).
func _on_ui_cancel_pressed() -> void:
	var current_frame: int = Engine.get_physics_frames()
	if _ui_cancel_handled_frame == current_frame:
		return  # Same-frame double-press absorbé (AC-MNU-16).
	_ui_cancel_handled_frame = current_frame

	match GameStateManager.get_current_state():
		GameStateManager.State.PLAYING:
			GameStateManager.request_pause()
		GameStateManager.State.PAUSED:
			GameStateManager.request_resume()
		_:
			# RESPAWNING / BOSS_DEFEATED / MENU — matrice ADR-0007 D-2, pas de transition légale.
			pass


## Story-004 — GSM state sync handler.
##
## Connecté via CONNECT_DEFERRED (r2 BLK-1) au signal `state_changed`. Le 1-frame
## skid garantit que `get_tree().paused` est propagé tree-wide avant que le handler
## tourne. Aussi appelé SYNC depuis `_ready()` pour le pull pattern boot resync
## (ADR-0007 D-9, couvre AC-MNU-35).
##
## Guard `is_inside_tree()` (r2 BLK-3) : pendant `change_scene_to_file` (ex. PAUSED →
## MENU), GSM émet `state_changed(MENU)` SYNC alors que le node est en cours de
## `tree_exiting`. Sans guard, `_apply_visibility` toucherait `pause_panel` orphelin.
##
## Matrice visibility (R-MNU-4 + Pillar 3 anti-flicker) :
##   PAUSED → show + no recapture mouse (Pause owne curseur libre)
##   PLAYING → hide + recapture mouse (Movement reprend autorité)
##   RESPAWNING / BOSS_DEFEATED / MENU → hide + no recapture (transitions tierces)
func _on_gsm_state_changed(new_state: GameStateManager.State) -> void:
	if not is_inside_tree():
		return  # r2 BLK-3 — node en cours de tree_exiting pendant change_scene_to_file.

	match new_state:
		GameStateManager.State.PAUSED:
			_apply_visibility(true, false)
		GameStateManager.State.PLAYING:
			_apply_visibility(false, true)
		GameStateManager.State.RESPAWNING, GameStateManager.State.BOSS_DEFEATED, GameStateManager.State.MENU:
			_apply_visibility(false, false)


## Story-005 r2 BLK-2 signature stable + Story-008 extension refcount Input + mouse.
##
## Snap visibility binaire (R-MNU-15 + AC-MNU-36) — zéro tween, zéro animation
## (Pillar 1 FLOW Chrome Zen). Guard `is_inside_tree()` r2 BLK-3 pour absorber
## la race CONNECT_DEFERRED pendant `change_scene_to_file` tree_exiting.
##
## Story-008 R-MNU-12 / R-MNU-13 — coordination refcount Input + mouse capture :
##   show=true  → request_disable(self) [refcount idempotent par owner]
##              + set_mouse_captured(false) [mouse libre menu]
##              + resume_button.grab_focus() [K.6 focus initial]
##   show=false → release_enable_request(self) [si blocker actif, sinon no-op]
##              + set_mouse_captured(true) si recapture_mouse [retour PLAYING]
##              (recapture_mouse=false → transition vers MENU/quit, mouse reste libre)
##
## Le guard `_enable_blockers.has(id)` côté hide évite le push_warning ADR-0004
## D-4 lors du boot pull resync où l'état initial est MENU/RESPAWNING (aucun
## blocker posé) mais `_apply_visibility(false, ...)` est tout de même appelé.
func _apply_visibility(show_overlay: bool, recapture_mouse: bool = true) -> void:
	if not is_inside_tree():
		return  # r2 BLK-3 — race CONNECT_DEFERRED pendant tree_exiting.
	# Story-013 D-1 fix : DimRect alpha 0.65 toggle synchrone avec PausePanel
	# (UX § 4.3 + GDD K.2). mouse_filter=STOP absorbe click-out (AC-UX-PM-10).
	dim_rect.visible = show_overlay
	pause_panel.visible = show_overlay
	if show_overlay:
		# Ouverture pause — refcount + mouse libre + focus initial.
		InputManager.request_disable(self)
		_set_mouse_captured_handler.call(false)
		resume_button.grab_focus()
	else:
		# Fermeture pause — release garde-fou (no-op si aucun blocker actif).
		if InputManager._enable_blockers.has(get_instance_id()):
			InputManager.release_enable_request(self)
		if recapture_mouse:
			_set_mouse_captured_handler.call(true)


## Story-007 R-MNU-9 — Reprendre la partie depuis Pause Overlay.
##
## Idempotence GSM (AC-MNU-24) : `request_resume()` a un guard interne
## `if _current_state != PAUSED: return` (ADR-0007 D-7). Pas de guard côté Menu —
## 2 clicks → 2 calls effectifs au verbe, mais une seule transition PAUSED→PLAYING
## émet `state_changed`. R-MNU-11 — zéro confirm dialog : exécute direct.
func _on_resume_pressed() -> void:
	GameStateManager.request_resume()


## Story-007 R-MNU-10 — Quitter vers Main Menu depuis Pause Overlay.
##
## ORDRE CRITIQUE r2 (AC-MNU-22 / AC-MNU-32) :
##   1. `_apply_visibility(false, false)` — hide overlay sans recapture mouse
##      (transition vers MENU = mouse libre, pas de retour PLAYING).
##   2. `release_enable_request(self)` — libère le blocker InputManager AVANT
##      la transition pour éviter une race fenêtre où InputManager pourrait
##      être lu pendant `change_scene_to_file` avec un blocker fantôme.
##   3. `_main_menu_handler.call()` — default appelle GSM.request_scene_transition.
##
## Implementation Notes §3 : si l'ordre est inversé, le `tree_exiting` du Pause
## Overlay (ADR-0004 CONNECT_ONE_SHOT auto-cleanup) déclencherait le release au
## moment de la destruction — race fenêtre indéterministe.
func _on_main_menu_pressed() -> void:
	# Story-008 — `_apply_visibility(false, false)` libère le blocker en interne.
	# Pas de double release (push_warning) ; ordre release-avant-transition r2 préservé.
	_apply_visibility(false, false)
	_main_menu_handler.call()


## Story-007 R-MNU-10 — Quitter le jeu depuis Pause Overlay.
##
## ORDRE CRITIQUE (AC-MNU-23) : `release_enable_request(self)` AVANT
## `get_tree().quit()` pour cleanup déterministe du blocker InputManager.
## Save-on-quit délégué intégralement à SaveLoad R-SAV-9 via
## `NOTIFICATION_WM_CLOSE_REQUEST` — Menu ne référence JAMAIS SaveLoad APIs.
func _on_quit_pressed() -> void:
	# Story-008 — `_apply_visibility(false, false)` libère le blocker + cache panel
	# en un seul appel cohérent. Mouse reste libre (recapture_mouse=false) car on
	# quitte l'app, pas de retour PLAYING.
	_apply_visibility(false, false)
	_quit_handler.call()


func _on_tree_exiting() -> void:
	# Story-008 AC-MNU-28 — auto-cleanup crash path : si Pause Overlay est détruit
	# (change_scene_to_file, queue_free externe) alors que blocker InputManager
	# est encore actif (callback story-007 non exécuté, ex. quit OS via Cmd-Q),
	# libère le blocker pour éviter un input désactivé orphelin.
	if InputManager._enable_blockers.has(get_instance_id()):
		InputManager.release_enable_request(self)
