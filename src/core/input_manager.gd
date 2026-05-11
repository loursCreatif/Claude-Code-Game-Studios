# InputManager — Point d'accès unique pour toutes les requêtes d'input.
# Tout le code jeu doit passer par cet autoload ; l'usage direct de Input.* est interdit.
# TR-inp-001 (tick polling), TR-inp-003 (singleton), TR-inp-004 (StringName discipline).
#
# Architecture (TD-008 split) :
#   InputLatencyTracker  — ring buffer zero-alloc + p99 (input_latency_tracker.gd)
#   InputEnableGate      — refcount enable/disable blockers (input_enable_gate.gd)
#   InputSettingsLoader  — load/save user://settings/input.tres (input_settings_loader.gd)
#
# Pas de class_name sur les 3 modules (bypass class cache CI, pattern preload binding).
# NOTE TAILLE : ce fichier reste ~380 lignes post-split. Les hot paths _unhandled_input
# + _physics_process + la totalité de l'API publique ne peuvent pas être délégués à un
# RefCounted sans introduire des appels indirects sur le chemin 1000 Hz souris, ce qui
# violerait ADR-0004 D-8 zero-alloc. 300 lignes n'est pas atteignable pour un autoload
# Node avec ces contraintes — le split a extrait le maximum sans dégrader les hot paths.
class_name InputManagerScript
extends Node

# Preload bindings (pas de class_name sur ces modules — voir header ci-dessus).
const InputLatencyTracker := preload("res://src/core/input_latency_tracker.gd")
const InputEnableGate := preload("res://src/core/input_enable_gate.gd")
const InputSettingsLoader := preload("res://src/core/input_settings_loader.gd")

# ---------------------------------------------------------------------------
# Constants & enums
# ---------------------------------------------------------------------------

## Toutes les actions MVP trackées par ce manager. Utiliser &"..." StringName literals
## ou cette constante — jamais de variables String brutes pour les noms d'action.
## Usage : InputManager.ACTIONS_MVP
const ACTIONS_MVP: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"dash", &"attack", &"restart",
	&"ui_cancel", &"ui_confirm",
]

const ACTION_DEBUG_TOGGLE: StringName = &"debug_toggle"

## Alias pour compatibilité externe (tests accèdent InputManager.LATENCY_SAMPLES_CAPACITY).
const LATENCY_SAMPLES_CAPACITY: int = InputLatencyTracker.CAPACITY

## Fenêtre d'absorption post-FOCUS_IN en microsecondes (50 ms par défaut).
## Story-010 (ADR-0014) : la valeur runtime active vit dans `_focus_regain_window_usec`.
const FOCUS_REGAIN_WINDOW_USEC: int = 50_000

## Fenêtre glissante en microsecondes pour le calcul p99 (1 s).
const LATENCY_WINDOW_USEC: int = InputLatencyTracker.WINDOW_USEC

# ---------------------------------------------------------------------------
# Composition modules
# ---------------------------------------------------------------------------

var _latency: InputLatencyTracker = null
var _gate: InputEnableGate = null

# ---------------------------------------------------------------------------
# Proxy property — tests accèdent InputManager._enable_blockers directement
# (input_refcount_mouse_capture_test.gd — pattern miroir AudioSystem proxy properties).
# ---------------------------------------------------------------------------

## Proxy transparent vers _gate._enable_blockers.
## Utilisé par les tests d'intégration pour observer l'état du refcount gate.
## Ne pas utiliser depuis le code gameplay — passer par request_disable / release_enable_request.
var _enable_blockers: Dictionary:
	get: return _gate._enable_blockers

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## État activé courant, dérivé du dictionnaire _gate._enable_blockers.
## Ne jamais assigner directement — utiliser _update_enabled_state().
var _enabled: bool = true

## Getter public read-only — les consumers lisent enabled, jamais _enabled.
## Usage : if InputManager.enabled: ...
var enabled: bool:
	get: return _enabled

var _pressed_this_tick: Dictionary[StringName, bool] = {}
var _consumed_this_tick: Dictionary[StringName, bool] = {}

## Horodatage (µs depuis boot) d'arrivée d'un event action pertinent dans
## _unhandled_input. Consommé par _physics_process après le swap pour calculer
## input→publish latency. 0 = pas d'event en attente.
var _event_arrival_ts_usec: int = 0

## Dernière latence input→publish mesurée en millisecondes (proxy sur _latency.last_latency_ms).
## Public var plate (pas de property getter) pour compat parser autoload typé.
## Usage : var ms := InputManager.last_input_to_publish_latency_ms
var last_input_to_publish_latency_ms: float = 0.0

## Story-009 — flag de désactivation de l'instanciation auto de l'overlay debug.
var suppress_debug_overlay: bool = false

## Fenêtre 50 ms post-FOCUS_IN (D-6). Armée sur NOTIFICATION_APPLICATION_FOCUS_IN.
var _focus_regained_until_ticks_usec: int = 0

## Mode souris sauvegardé à la perte de focus OS. Restauré à la reprise du focus.
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

## Test back-door — force is_mouse_captured() à retourner true en headless.
var _test_force_captured: bool = false

## Sensibilité souris MVP en rad/pixel. Lue chaque frame par CameraSystem.
var mouse_sensitivity: float = 0.0022

# ---------------------------------------------------------------------------
# Debug-only hot-path profiling (AC-PF-1 / AC-PF-5 — story-007)
# ---------------------------------------------------------------------------

## Coût InputManager sur le tick physique courant (µs accumulés). Guard debug.
var _hot_path_frame_usec: int = 0

## Valeur complétée du tick physique précédent (µs). Lue par le benchmark runner.
## Public var plate pour compat parser autoload typé.
## Usage : var cost_us := InputManager.hot_path_prev_frame_usec
var hot_path_prev_frame_usec: int = 0

## Inversion axe Y de la souris. false = standard, true = inversion (mode pilote/sim).
var mouse_y_inverted: bool = false

## Story-010 (ADR-0014) — préférences utilisateur Input persistées.
## null jusqu'à _ready() (ou si suppress_settings_load actif en test).
var settings: InputSettings = null

## Story-010 — fenêtre FOCUS_IN active en µs, dérivée de settings.focus_regain_window_ms.
var _focus_regain_window_usec: int = FOCUS_REGAIN_WINDOW_USEC

## Story-010 — flag de désactivation du chargement settings au boot.
var suppress_settings_load: bool = false

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis 1× par frame quand un InputEventMouseMotion est reçu.
## Usage : InputManager.mouse_motion.connect(_on_mouse_motion)
signal mouse_motion(delta: Vector2)

## Émis quand _enabled change d'état.
signal enabled_changed(new_state: bool)

## Signaux typés gameplay — émis uniquement quand _enabled == true (gated).
signal jump_pressed()
signal dash_pressed()
signal attack_pressed()
signal restart_pressed()

## Signaux typés UI — émis MÊME quand _enabled == false (ADR-0004 D-4, GDD règle 6).
signal ui_cancel_pressed()
signal ui_confirm_pressed()

## Émis sur NOTIFICATION_APPLICATION_FOCUS_OUT.
signal application_focus_lost()

## Émis sur NOTIFICATION_APPLICATION_FOCUS_IN.
signal application_focus_gained()

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Instancier les modules de composition.
	_latency = InputLatencyTracker.new()
	_latency.setup()
	_gate = InputEnableGate.new()

	# Pré-allouer les dicts — zéro allocation runtime après ce point (D-1).
	for a: StringName in ACTIONS_MVP:
		_pressed_this_tick[a] = false
		_consumed_this_tick[a] = false

	# AC-DBG-1 / D-9 : enregistrer debug_toggle uniquement en builds debug.
	if OS.has_feature("debug") and not InputMap.has_action(ACTION_DEBUG_TOGGLE):
		InputMap.add_action(ACTION_DEBUG_TOGGLE)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(ACTION_DEBUG_TOGGLE, ev)

	# story-009 — instancier l'overlay debug uniquement en build debug.
	if OS.has_feature("debug") and not suppress_debug_overlay:
		var overlay_scene := preload("res://src/core/input_debug_overlay.tscn")
		var overlay := overlay_scene.instantiate()
		get_tree().root.call_deferred(&"add_child", overlay)

	# Story-010 (ADR-0014) — charge user://settings/input.tres ou applique defaults.
	if not suppress_settings_load:
		settings = InputSettingsLoader.load_and_apply(self)

## Gestion du focus OS — découplage one-way Input → systèmes (ADR-0004 D-5).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_saved_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_focus_regained_until_ticks_usec = 0
		application_focus_lost.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Input.mouse_mode = _saved_mouse_mode
		_focus_regained_until_ticks_usec = Time.get_ticks_usec() + _focus_regain_window_usec
		application_focus_gained.emit()

func _physics_process(_delta: float) -> void:
	# story-007 : capture coût complet du tick précédent AVANT de démarrer le tick courant.
	if OS.has_feature("debug"):
		hot_path_prev_frame_usec = _hot_path_frame_usec
		_hot_path_frame_usec = 0
	var _pp_t0: int = Time.get_ticks_usec() if OS.has_feature("debug") else 0

	# D-3 : swap refs AVANT tout autre traitement — zéro alloc (ref swap).
	var tmp: Dictionary[StringName, bool] = _consumed_this_tick
	_consumed_this_tick = _pressed_this_tick
	_pressed_this_tick = tmp
	for a: StringName in ACTIONS_MVP:
		_pressed_this_tick[a] = false

	# ADR-0004 D-8 : mesure input→publish latency après le swap.
	if _event_arrival_ts_usec > 0:
		var now_usec: int = Time.get_ticks_usec()
		var latency_ms: float = float(now_usec - _event_arrival_ts_usec) / 1000.0
		_latency.record_sample(latency_ms, now_usec)
		last_input_to_publish_latency_ms = _latency.last_latency_ms
		_event_arrival_ts_usec = 0

	if OS.has_feature("debug"):
		_hot_path_frame_usec += Time.get_ticks_usec() - _pp_t0

func _unhandled_input(event: InputEvent) -> void:
	var _ui_t0: int = Time.get_ticks_usec() if OS.has_feature("debug") else 0

	# Filtrer les key repeats — les echo events ne doivent pas déclencher d'actions.
	if event is InputEventKey and event.is_echo():
		if OS.has_feature("debug"):
			_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
		return

	# Story-003 : republier les InputEventMouseMotion en signal typé zero-alloc.
	if event is InputEventMouseMotion:
		if not _enabled:
			if OS.has_feature("debug"):
				_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
			return
		if Time.get_ticks_usec() < _focus_regained_until_ticks_usec:
			if OS.has_feature("debug"):
				_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
			return
		mouse_motion.emit(event.relative)
		if OS.has_feature("debug"):
			_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
		return

	# Signaux UI traversent TOUJOURS — nécessaires pour unpause (ADR-0004 D-4, GDD règle 6).
	if event.is_action_pressed(&"ui_cancel"):
		_event_arrival_ts_usec = Time.get_ticks_usec()
		_pressed_this_tick[&"ui_cancel"] = true
		ui_cancel_pressed.emit()
	if event.is_action_pressed(&"ui_confirm"):
		_event_arrival_ts_usec = Time.get_ticks_usec()
		_pressed_this_tick[&"ui_confirm"] = true
		ui_confirm_pressed.emit()

	# Gate gameplay : si le manager est désactivé, aucun flag ni signal gameplay.
	if not _enabled:
		if OS.has_feature("debug"):
			_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
		return

	# AC1 : pour chaque action MVP gameplay, lever le flag + émettre signal typé.
	for a: StringName in ACTIONS_MVP:
		if a == &"ui_cancel" or a == &"ui_confirm":
			continue
		if event.is_action_pressed(a):
			_event_arrival_ts_usec = Time.get_ticks_usec()
			_pressed_this_tick[a] = true
			match a:
				&"jump":    jump_pressed.emit()
				&"dash":    dash_pressed.emit()
				&"attack":  attack_pressed.emit()
				&"restart": restart_pressed.emit()

	if OS.has_feature("debug"):
		_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Retourne true si [param action] a été pressée ce tick (edge-triggered).
## API canonique de polling gameplay (TR-inp-001, ADR-0004 D-1).
## Retourne false si le manager est désactivé.
## Usage : if InputManager.was_pressed_this_tick(&"jump"): ...
func was_pressed_this_tick(action: StringName) -> bool:
	if not _enabled:
		return false
	return _consumed_this_tick.get(action, false)

## Simule un press d'action en debug uniquement (D-9).
func simulate_action_press(action: StringName) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

## Simule un relâchement d'action en debug uniquement (D-9).
func simulate_action_release(action: StringName) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)

## Test-only bypass headless (D-9 complémentaire) : injecte un edge press one-tick
## sans passer par Input.parse_input_event (no-op en headless CLI).
## Usage : InputManager.inject_pressed_for_test(&"dash")
func inject_pressed_for_test(action: StringName) -> void:
	if not OS.has_feature("debug"):
		return
	_pressed_this_tick[action] = true

## Simule un déplacement souris en debug uniquement (story-008, D-9).
## Usage : simulate_mouse_motion(Vector2(1.0, 0.0))
func simulate_mouse_motion(delta: Vector2) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventMouseMotion.new()
	ev.relative = delta
	Input.parse_input_event(ev)

## Retourne le vecteur WASD pour mapping XZ Godot (-Z = forward).
## Usage : InputManager.get_move_input_vector()
func get_move_input_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.5)

## Verrouille ou libère le curseur. Main-thread only (ADR-0004 D-7).
## Usage : InputManager.set_mouse_captured(true)
func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

## Read-through sur Input.mouse_mode (AC-MC-3).
## Usage : if InputManager.is_mouse_captured(): ...
func is_mouse_captured() -> bool:
	if _test_force_captured:
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## Test back-door — force is_mouse_captured() à retourner true en headless.
func force_mouse_captured_for_test(captured: bool) -> void:
	if not OS.has_feature("debug"):
		return
	_test_force_captured = captured

# ---------------------------------------------------------------------------
# Public methods (refcount enable/disable — ADR-0004 D-4, TR-inp-005)
# ---------------------------------------------------------------------------

## Enregistre [param owner] comme bloqueur d'input. Idempotent.
## Auto-cleanup via CONNECT_ONE_SHOT si l'owner est détruit sans release.
## Usage : InputManager.request_disable(self)
func request_disable(owner: Node) -> void:
	if _gate.add_blocker(owner):
		owner.tree_exited.connect(_on_blocker_tree_exited.bind(owner.get_instance_id()), CONNECT_ONE_SHOT)
		_update_enabled_state()

## Retire [param owner] de la liste des bloqueurs d'input.
## Usage : InputManager.release_enable_request(self)
func release_enable_request(owner: Node) -> void:
	if owner == null:
		return
	if not _gate.remove_blocker(owner):
		push_warning(
			"release_enable_request: owner %s n'avait pas de requête active" % owner
		)
	_update_enabled_state()

# ---------------------------------------------------------------------------
# Public methods (latency metrics — ADR-0004 D-8, TR-inp-007)
# ---------------------------------------------------------------------------

## Retourne le p99 rolling des latences input→publish sur la fenêtre 1 s.
## Lecture rare (HUD debug F3 ~1 Hz). Délègue au ring buffer InputLatencyTracker.
## Usage : var p99 := InputManager.get_latency_p99_ms()
func get_latency_p99_ms() -> float:
	return _latency.get_p99_ms()

# ---------------------------------------------------------------------------
# Public methods (settings persistence — story-010, ADR-0014)
# ---------------------------------------------------------------------------

## Sauvegarde les settings courants. Trigger explicite uniquement (D-6).
## Usage : var err := InputManager.save_settings()
func save_settings() -> Error:
	return InputSettingsLoader.save(settings)

# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Handler auto-cleanup : appelé par tree_exited de l'owner (CONNECT_ONE_SHOT).
func _on_blocker_tree_exited(owner_id: int) -> void:
	if _gate.remove_blocker_by_id(owner_id):
		_update_enabled_state()

## Recalcule _enabled depuis l'état de _gate. Émet enabled_changed si changement.
## Vide les flags pressés à la transition disabled (évite les ghost presses).
func _update_enabled_state() -> void:
	var new_state: bool = _gate.is_enabled()
	if new_state == _enabled:
		return
	_enabled = new_state
	enabled_changed.emit(_enabled)
	# Clear flags à la transition disabled — évite les ghost presses (AC-DS-4, ADR-0004 D-4).
	if not _enabled:
		for a: StringName in ACTIONS_MVP:
			_pressed_this_tick[a] = false
			_consumed_this_tick[a] = false
