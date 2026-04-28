class_name GameStateManagerScript
extends Node

## GameStateManager — orchestrateur unique des transitions d'états gameplay.
##
## Source : ADR-0007 (Accepted 2026-04-23) D-1..D-10. Autoload position 2 (après InputManager).
## class_name suffixé `Script` pour éviter la collision avec l'identifiant autoload `GameStateManager`.
##
## API publique figée (D-10) :
##   get_current_state() -> State
##   request_pause() / request_resume()                    # PLAYING ↔ PAUSED idempotents (D-2)
##   request_scene_transition(scene_path: String)          # * → MENU via change_scene_to_file (D-5)
##   start_etage(etage_id: int)                            # MENU → PLAYING via Level.load_etage (D-7 R-5)
##   request_new_run()                                     # BOSS_DEFEATED → MENU
##
## Signal outbound (D-3) :
##   state_changed(new_state: State)                       # 1× par transition effective
##
## Pattern pull au boot (D-9) : aucun emit `state_changed(MENU)` au _ready ;
## les consumers lisent `get_current_state()` dans leur propre _ready.

enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }

signal state_changed(new_state: State)

var _current_state: State = State.MENU

## Map des transitions légales (D-2). Toute transition hors de cette table est rejetée
## (assert debug, push_error release). Garder synchronisé avec le graphe ADR-0007 D-2.
const _LEGAL_TRANSITIONS: Dictionary = {
	State.MENU: [State.PLAYING],
	State.PLAYING: [State.PAUSED, State.RESPAWNING, State.BOSS_DEFEATED, State.MENU],
	State.PAUSED: [State.PLAYING, State.MENU],
	State.RESPAWNING: [State.PLAYING, State.MENU],
	State.BOSS_DEFEATED: [State.MENU],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # D-4 : GSM doit recevoir request_resume sous pause
	# D-6 : auto-pause sur perte de focus (uniquement si PLAYING)
	InputManager.application_focus_lost.connect(_on_application_focus_lost)
	# D-9 : pas d'emit state_changed(MENU) au boot — pull pattern uniquement.


# ─── API publique (D-10) ─────────────────────────────────────────────

func get_current_state() -> State:
	return _current_state


func request_pause() -> void:
	# Idempotent (REQ-4) : no-op si déjà pausé ou état non-pausable.
	if _current_state != State.PLAYING:
		return
	# D-4 : GSM possède l'autorité unique sur get_tree().paused.
	# ADR-0005 D-8 : mutation d'état complète AVANT emit — paused doit être
	# vrai quand un consumer reçoit state_changed(PAUSED).
	get_tree().paused = true
	_transition_to(State.PAUSED)


func request_resume() -> void:
	if _current_state != State.PAUSED:
		return
	# ADR-0005 D-8 : libérer le pause flag AVANT emit pour cohérence consumer.
	get_tree().paused = false
	_transition_to(State.PLAYING)


func request_scene_transition(scene_path: String) -> void:
	# D-5 : * → MENU via change_scene_to_file. Ne couvre PAS les étages gameplay.
	assert(scene_path.begins_with("res://"), "scene_path must be a res:// resource path")
	# Si on était en pause (Pause → Main Menu), libérer le pause flag avant transition.
	if get_tree().paused:
		get_tree().paused = false
	_transition_to(State.MENU)
	get_tree().change_scene_to_file(scene_path)


func start_etage(etage_id: int) -> void:
	# D-7 R-5 : MENU → PLAYING piloté par `LevelSystem.level_active`, pas direct.
	# GSM délègue le chargement à LevelSystem et écoute `level_active` pour transitionner.
	if _current_state != State.MENU:
		assert(false, "start_etage() only legal from MENU (current=%s)" % State.keys()[_current_state])
		return
	if not LevelSystem.level_active.is_connected(_on_level_active):
		LevelSystem.level_active.connect(_on_level_active, CONNECT_ONE_SHOT)
	LevelSystem.load_etage(etage_id)


func request_new_run() -> void:
	# D-8 : BOSS_DEFEATED → MENU explicite.
	if _current_state != State.BOSS_DEFEATED:
		return
	_transition_to(State.MENU)


# ─── Privé ───────────────────────────────────────────────────────────

func _transition_to(new_state: State) -> void:
	# D-2 : whitelist des transitions ; D-3 : émission unique par transition effective.
	if new_state == _current_state:
		return  # idempotent : pas de re-émission no-op
	var legal: Array[State] = _LEGAL_TRANSITIONS.get(_current_state, [] as Array[State])
	if not legal.has(new_state):
		assert(false, "illegal GSM transition: %s → %s" % [
			State.keys()[_current_state], State.keys()[new_state]
		])
		push_error("GSM: illegal transition %s → %s" % [
			State.keys()[_current_state], State.keys()[new_state]
		])
		return
	_current_state = new_state
	state_changed.emit(new_state)


func _on_application_focus_lost() -> void:
	# D-6 : auto-pause uniquement si on est en PLAYING.
	if _current_state == State.PLAYING:
		request_pause()


func _on_level_active(_etage_id: int, _player_start: Vector3) -> void:
	# D-7 R-5 : transition MENU → PLAYING confirmée par LevelSystem.
	if _current_state != State.MENU:
		return
	_transition_to(State.PLAYING)
