# InputManager — Point d'accès unique pour toutes les requêtes d'input.
# Tout le code jeu doit passer par cet autoload ; l'usage direct de Input.* est interdit.
# TR-inp-001 (tick polling), TR-inp-003 (singleton), TR-inp-004 (StringName discipline).
class_name InputManagerScript
extends Node

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

## Capacité du ring buffer de latence (2 s @ 60 Hz = 120 samples). Fenêtre rolling.
## Source : ADR-0004 D-8, TR-inp-007.
const LATENCY_SAMPLES_CAPACITY: int = 120

## Fenêtre d'absorption post-FOCUS_IN en microsecondes (50 ms).
## Les InputEventMouseMotion arrivant dans cette fenêtre sont silencieux —
## cela évite les sauts de caméra causés par les bursts Wayland/X11 à la
## reprise du focus (ADR-0004 D-6, story-005).
## MVP hard-codé ; rendu tunable post-ADR-0014 via input_settings.tres (story-010).
const FOCUS_REGAIN_WINDOW_USEC: int = 50_000

## Fenêtre glissante en microsecondes pour le calcul p99 (1 s).
## Les samples plus vieux sont filtrés à la lecture (pas d'éviction active).
const LATENCY_WINDOW_USEC: int = 1_000_000

# ---------------------------------------------------------------------------
# Private variables
# (_pressed_this_tick et _consumed_this_tick sont en lecture seule depuis
# l'extérieur — muter uniquement via l'API déclarée)
# ---------------------------------------------------------------------------

## Dictionnaire des blockers refcount. Clé : owner_id (int), Valeur : true.
## _enabled est dérivé de _enable_blockers.is_empty() — ne jamais assigner directement.
## Modifié uniquement via request_disable() / release_enable_request() / _on_blocker_tree_exited().
var _enable_blockers: Dictionary = {}

## État activé courant, dérivé du dictionnaire _enable_blockers.
## Ne jamais assigner directement — utiliser _update_enabled_state().
var _enabled: bool = true

## Getter public read-only — les consumers lisent enabled, jamais _enabled.
## Usage : if InputManager.enabled: ...
var enabled: bool:
	get: return _enabled

var _pressed_this_tick: Dictionary[StringName, bool] = {}
var _consumed_this_tick: Dictionary[StringName, bool] = {}

## Ring buffer zero-alloc pour les samples de latence input→publish (ADR-0004 D-8).
## Pré-allouées via .resize(CAPACITY) au _ready() — .resize garantit la contiguïté
## mémoire et l'absence d'allocation sur assignation indexée arr[i] = value.
## Jamais de push_back / literal Array : violerait le pattern zero-alloc hot path.
var _latency_values_ms: PackedFloat32Array = PackedFloat32Array()
var _latency_timestamps_usec: PackedInt64Array = PackedInt64Array()

## Index d'écriture monotone — slot réel = _latency_write_idx % CAPACITY (ring).
## int64 GDScript : ne déborde pas en pratique (2^63 ticks @ 60 Hz > 4 milliards d'années).
var _latency_write_idx: int = 0

## Nombre de samples effectivement écrits (clampé à CAPACITY). Distinct de write_idx
## pour que get_latency_p99_ms n'itère pas sur des slots non-remplis après le boot.
var _latency_sample_count: int = 0

## Buffer scratch pré-alloué pour le tri in-place lors du calcul p99 (read-rare @ HUD F3).
## Réutilisé à chaque appel de get_latency_p99_ms : zéro realloc.
var _latency_scratch: PackedFloat32Array = PackedFloat32Array()

## Horodatage (µs depuis boot) d'arrivée d'un event action pertinent dans
## _unhandled_input. Consommé par _physics_process après le swap pour calculer
## input→publish latency. 0 = pas d'event en attente.
var _event_arrival_ts_usec: int = 0

## Dernière latence input→publish mesurée en millisecondes (read-only convention).
## Mise à jour à chaque swap physics si un event pertinent est arrivé depuis le dernier tick.
## Valeur brute (pas un p99) — pour le percentile rolling 1 s, appeler get_latency_p99_ms().
## Public var plate (pas de property getter) pour compat parser autoload typé.
## Usage : var ms := InputManager.last_input_to_publish_latency_ms
var last_input_to_publish_latency_ms: float = 0.0

## Story-009 — flag de désactivation de l'instanciation auto de l'overlay debug.
## Les tests d'intégration qui instancient InputManagerScript.new() + add_child
## doivent setter ce flag à true AVANT l'add_child pour éviter la pollution de
## `get_tree().root` avec un overlay par instance de test. Protège VC-3 zero-alloc.
## Usage test : var im := InputManagerScript.new(); im.suppress_debug_overlay = true; add_child(im)
var suppress_debug_overlay: bool = false

## Fenêtre 50 ms post-FOCUS_IN (D-6). Story-005 arme cette valeur sur
## NOTIFICATION_APPLICATION_FOCUS_IN ; défaut 0 = gate inactif (toujours passant).
var _focus_regained_until_ticks_usec: int = 0

## Mode souris sauvegardé à la perte de focus OS (NOTIFICATION_APPLICATION_FOCUS_OUT).
## Restauré à la reprise du focus (NOTIFICATION_APPLICATION_FOCUS_IN).
## Stocké en int — Input.MouseMode est une enum int ; default = MOUSE_MODE_VISIBLE
## pour que le curseur soit visible quand aucune session de jeu n'est active.
## Main-thread only (ADR-0004 D-7).
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

## Sensibilité souris MVP en rad/pixel. Lue chaque frame par CameraSystem
## (hot-reload runtime). Plage safe : 0.0005 (très lent) – 0.012 (très rapide).
## Persistance via user://input_settings.tres = scope story-010.
## Ajoutée dans le cadre de Camera story-002 (consumer principal) — Foundation
## expose la propriété, story-010 ajoutera load/save.
var mouse_sensitivity: float = 0.0022

# ---------------------------------------------------------------------------
# Debug-only hot-path profiling (AC-PF-1 / AC-PF-5 — story-007)
# ---------------------------------------------------------------------------

## Coût InputManager uniquement sur le tick physique courant (µs accumulés).
## Incrémenté dans _unhandled_input et _physics_process (guards debug).
## Reset en début de chaque _physics_process ; valeur du tick précédent
## disponible via hot_path_prev_frame_usec pour lecture par le benchmark.
## Zéro coût release : toutes les écritures sont gardées par OS.has_feature("debug").
var _hot_path_frame_usec: int = 0

## Valeur complétée du tick physique précédent (µs). Lue par le benchmark runner
## après chaque swap — représente le coût complet _unhandled_input + _physics_process
## du tick N-1. Read-only par convention (écrit uniquement par _physics_process).
## Public var plate (pas de property getter) pour compat parser autoload typé.
## Usage : var cost_us := InputManager.hot_path_prev_frame_usec
var hot_path_prev_frame_usec: int = 0

## Inversion axe Y de la souris. false = pousser vers le haut → caméra monte.
## true = pousser vers le haut → caméra descend (préférence pilote/sim).
## Persistance scope story-010.
var mouse_y_inverted: bool = false

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis 1× par frame quand un InputEventMouseMotion est reçu (Godot fusionne les
## deltas intra-frame). Payload = delta brut Vector2 (value type, zero-alloc).
## Camera System applique sensitivity, invert_y, et clamp magnitude (TR-cam-001).
## Usage : InputManager.mouse_motion.connect(_on_mouse_motion)
signal mouse_motion(delta: Vector2)

## Émis quand _enabled change d'état. Consumers peuvent réagir (ex. UI pause).
## Usage : InputManager.enabled_changed.connect(_on_enabled_changed)
signal enabled_changed(new_state: bool)

## Signaux typés gameplay — émis uniquement quand _enabled == true (gated).
## Usage : InputManager.jump_pressed.connect(_on_jump_pressed)
signal jump_pressed()
signal dash_pressed()
signal attack_pressed()
signal restart_pressed()

## Signaux typés UI — émis MÊME quand _enabled == false (edge case ADR-0004 D-4,
## GDD règle 6 : nécessaire pour que unpause fonctionne depuis un menu pause).
## Usage : InputManager.ui_cancel_pressed.connect(_on_ui_cancel_pressed)
signal ui_cancel_pressed()
signal ui_confirm_pressed()

## Émis sur NOTIFICATION_APPLICATION_FOCUS_OUT (perte focus fenêtre OS).
## Couplage one-way : InputManager émet, les systèmes abonnés (pause, menu)
## décident de leur réaction sans que InputManager ne les connaisse.
## ADR-0004 D-5, story-005. Aucun payload — couplage one-way strict (D-5).
## Usage : InputManager.application_focus_lost.connect(_on_focus_lost)
signal application_focus_lost()

## Émis sur NOTIFICATION_APPLICATION_FOCUS_IN (reprise focus fenêtre OS).
## La fenêtre 50 ms FOCUS_REGAIN_WINDOW_USEC est armée simultanément pour
## absorber les bursts souris parasites (Wayland/X11) — gate dans _unhandled_input.
## ADR-0004 D-5, D-6, story-005.
## Usage : InputManager.application_focus_gained.connect(_on_focus_gained)
signal application_focus_gained()

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Pré-allouer les dicts — zéro allocation runtime après ce point (D-1).
	for a: StringName in ACTIONS_MVP:
		_pressed_this_tick[a] = false
		_consumed_this_tick[a] = false

	# Pré-allouer les 3 buffers latence (ADR-0004 D-8). .resize() garantit la
	# contiguïté mémoire et remplit à 0 — toutes les assignations arr[i] = x
	# ultérieures sont zero-alloc.
	_latency_values_ms.resize(LATENCY_SAMPLES_CAPACITY)
	_latency_timestamps_usec.resize(LATENCY_SAMPLES_CAPACITY)
	_latency_scratch.resize(LATENCY_SAMPLES_CAPACITY)

	# AC-DBG-1 / D-9 : enregistrer debug_toggle uniquement en builds debug.
	# Guard InputMap.has_action empêche la double-registration au rechargement de scène.
	if OS.has_feature("debug") and not InputMap.has_action(ACTION_DEBUG_TOGGLE):
		InputMap.add_action(ACTION_DEBUG_TOGGLE)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(ACTION_DEBUG_TOGGLE, ev)

	# story-005 — signaux focus OS gérés dans _notification() ci-dessous (DONE).

	# story-009 — instancier l'overlay debug uniquement en build debug.
	# call_deferred est impératif : _ready() de l'autoload s'exécute pendant
	# l'initialisation du SceneTree. À ce stade, get_tree().root n'est pas
	# fully initialized — add_child direct planterait. call_deferred reporte
	# l'ajout à la fin du frame courant, quand root est prêt.
	# L'overlay se queue_free() lui-même en release (binary gate dans _ready()).
	# `suppress_debug_overlay` permet aux tests d'intégration de désactiver
	# l'instanciation pour éviter la pollution de `/root`.
	if OS.has_feature("debug") and not suppress_debug_overlay:
		var overlay_scene := preload("res://src/core/input_debug_overlay.tscn")
		var overlay := overlay_scene.instantiate()
		get_tree().root.call_deferred(&"add_child", overlay)

## Gestion du focus OS — implémente le découplage one-way Input → systèmes (ADR-0004 D-5).
##
## FOCUS_OUT : sauvegarde le mode souris, bascule en MOUSE_MODE_VISIBLE (curseur
## visible à nouveau hors fenêtre), désarme la fenêtre burst, émet application_focus_lost.
##
## FOCUS_IN : restaure le mode souris sauvegardé, arme la fenêtre 50 ms
## (_focus_regained_until_ticks_usec) pour absorber les bursts parasites Wayland/X11,
## émet application_focus_gained.
##
## Godot 4.6 : NOTIFICATION_APPLICATION_FOCUS_IN/OUT couvrent le focus fenêtre OS
## (niveau Window), pas le focus intra-UI (FocusMode des Control). Sémantique stable
## pour la cible PC Steam/itch.io. Si des avertissements de dépréciation apparaissent
## lors des tests, migrer vers Window.focus_entered / Window.focus_exited (note engine-risk).
##
## Main-thread only — Input.mouse_mode écrit uniquement ici (D-7).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_saved_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_focus_regained_until_ticks_usec = 0
		application_focus_lost.emit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		Input.mouse_mode = _saved_mouse_mode
		_focus_regained_until_ticks_usec = Time.get_ticks_usec() + FOCUS_REGAIN_WINDOW_USEC
		application_focus_gained.emit()

func _physics_process(_delta: float) -> void:
	# story-007 : capture coût complet du tick précédent AVANT de démarrer le tick courant.
	# _hot_path_frame_usec contient l'accumulation _unhandled_input + fin-de-_physics_process
	# du tick N-1. On le bascule dans hot_path_prev_frame_usec pour lecture benchmark,
	# puis on repart à zéro. Guard debug : zéro coût release (dead-code path).
	if OS.has_feature("debug"):
		hot_path_prev_frame_usec = _hot_path_frame_usec
		_hot_path_frame_usec = 0
	var _pp_t0: int = Time.get_ticks_usec() if OS.has_feature("debug") else 0

	# D-3 : swap refs ligne 1 AVANT tout autre traitement — zéro alloc (ref swap).
	# _consumed_this_tick reçoit les flags pressés du render frame précédent ;
	# _pressed_this_tick est recyclé et vidé pour accumuler les events du frame courant.
	var tmp: Dictionary[StringName, bool] = _consumed_this_tick
	_consumed_this_tick = _pressed_this_tick
	_pressed_this_tick = tmp
	for a: StringName in ACTIONS_MVP:
		_pressed_this_tick[a] = false

	# ADR-0004 D-8 : mesure input→publish latency. Le swap ci-dessus matérialise
	# la "publication" — les consumers vont lire _consumed_this_tick dans leurs
	# _physics_process (autoloads déclarés après InputManager). Le délai event
	# arrival → swap est donc exactement input→publish latency.
	if _event_arrival_ts_usec > 0:
		var now_usec: int = Time.get_ticks_usec()
		var latency_ms: float = float(now_usec - _event_arrival_ts_usec) / 1000.0
		_record_latency_sample(latency_ms, now_usec)
		_event_arrival_ts_usec = 0

	# story-007 : clôture du timer _physics_process pour le tick courant.
	# S'ajoute au coût déjà accumulé par _unhandled_input pendant ce tick.
	if OS.has_feature("debug"):
		_hot_path_frame_usec += Time.get_ticks_usec() - _pp_t0

func _unhandled_input(event: InputEvent) -> void:
	# story-007 : mesure coût _unhandled_input pour le hot-path accumulator (AC-PF-1/5).
	# Guard debug : zéro coût release. Un seul appel Time.get_ticks_usec() par event.
	var _ui_t0: int = Time.get_ticks_usec() if OS.has_feature("debug") else 0

	# Filtrer les key repeats — les echo events ne doivent pas déclencher d'actions.
	if event is InputEventKey and event.is_echo():
		if OS.has_feature("debug"):
			_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0
		return

	# Story-003 : republier les InputEventMouseMotion en signal typé zero-alloc.
	# Gates dans l'ordre coût croissant : bool _enabled (story-004) puis
	# Time.get_ticks_usec() pour la fenêtre fenêtre-burst post-FOCUS_IN (story-005).
	# Valeurs par défaut (_enabled=true, _focus_regained_until_ticks_usec=0) = laissent passer.
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
	# Émis AVANT le gate _enabled pour éviter le deadlock menu pause ↔ ui_cancel.
	# _pressed_this_tick est set ici également pour que l'état interne reste cohérent
	# avec l'émission signal — was_pressed_this_tick() gate néanmoins sur _enabled,
	# donc le poll retourne false quand désactivé (UI = signal-only par contrat D-1).
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
	# ui_cancel / ui_confirm déjà traités au-dessus — skip pour éviter double-set.
	for a: StringName in ACTIONS_MVP:
		if a == &"ui_cancel" or a == &"ui_confirm":
			continue
		if event.is_action_pressed(a):
			# ADR-0004 D-8 : capture arrivée event pour mesure input→publish latency.
			# Si plusieurs actions MVP matchent le même event (rare), la dernière
			# écrase — pas de perte sémantique, c'est la même fenêtre temporelle.
			_event_arrival_ts_usec = Time.get_ticks_usec()
			_pressed_this_tick[a] = true
			match a:
				&"jump":    jump_pressed.emit()
				&"dash":    dash_pressed.emit()
				&"attack":  attack_pressed.emit()
				&"restart": restart_pressed.emit()

	# story-007 : clôture du timer _unhandled_input pour le chemin gameplay normal.
	if OS.has_feature("debug"):
		_hot_path_frame_usec += Time.get_ticks_usec() - _ui_t0

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Retourne true si [param action] a été pressée ce tick (edge-triggered, une seule fois par press).
## C'est l'API canonique de polling gameplay (TR-inp-001, ADR-0004 D-1).
## Ne jamais appeler Input.is_action_just_pressed() directement dans le code jeu.
## Retourne false si le manager est désactivé (_enabled == false).
## Les actions UI (&"ui_cancel", &"ui_confirm") sont traitées signal-only par contrat :
## même si le flag interne est set à l'émission, ce getter renvoie false quand disabled
## — consommer les signaux ui_cancel_pressed / ui_confirm_pressed pour l'UI pause/menu.
## Usage : if InputManager.was_pressed_this_tick(&"jump"): ...
func was_pressed_this_tick(action: StringName) -> bool:
	if not _enabled:
		return false
	return _consumed_this_tick.get(action, false)

## Simule un press d'action en debug uniquement (D-9).
## Crée un InputEventAction et l'injecte via Input.parse_input_event,
## ce qui déclenche _unhandled_input sur le prochain frame physique.
## Ne fait rien en build release (gate OS.has_feature).
## Usage : simulate_action_press(&"jump")
func simulate_action_press(action: StringName) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

## Simule un relâchement d'action en debug uniquement (D-9).
## Voir simulate_action_press pour les détails de comportement.
## Usage : simulate_action_release(&"jump")
func simulate_action_release(action: StringName) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)

## Simule un déplacement souris en debug uniquement (story-008, complémentaire D-9).
## Crée un InputEventMouseMotion avec [param delta] en relative et l'injecte via
## Input.parse_input_event, ce qui déclenche _unhandled_input sur le prochain frame.
## Utilisé par le stress runner zero-alloc pour couvrir le hot path souris — 1000 Hz
## en gameplay normal, cadence calibrée à 167/s dans le test.
## Ne fait rien en build release (gate OS.has_feature) — zero coût shipping.
## Usage : simulate_mouse_motion(Vector2(1.0, 0.0))
func simulate_mouse_motion(delta: Vector2) -> void:
	if not OS.has_feature("debug"):
		return
	var ev := InputEventMouseMotion.new()
	ev.relative = delta
	Input.parse_input_event(ev)

## Retourne le vecteur WASD pour mapping XZ Godot (-Z = forward).
##
## Mapping :
##   x = move_right − move_left   (positif = strafe droite, +X local)
##   y = move_back  − move_forward (positif = recul, +Z Godot = arrière)
##
## Le consumer MovementController construit `Vector3(v.x, 0, v.y)` puis applique
## `transform.basis * v` — `move_forward` enfoncé donne v.y < 0 → wish_dir_3d.z < 0
## → direction -Z = avant en Godot. Comportement correct (Godot forward = -Z).
##
## Point d'accès unique à Input.get_vector pour les held inputs de déplacement (ADR-0004).
## Jamais Input.get_vector directement depuis le code jeu (Control Manifest 2026-04-23
## Core layer forbidden). Deadzone 0.5 cohérente avec gamepad analogique stretch-goal.
## Story-002 — Movement controller consumer.
func get_move_input_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.5)

## Verrouille ou libère le curseur. true → MOUSE_MODE_CAPTURED (curseur invisible
## centré, deltas relatifs émis), false → MOUSE_MODE_VISIBLE.
## Main-thread only (ADR-0004 D-7) — appeler depuis _process / _physics_process /
## _ready / signal handlers uniquement, jamais depuis Thread ou WorkerThreadPool.
## Usage : InputManager.set_mouse_captured(true)
func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

## Read-through (pas de cache) sur Input.mouse_mode (AC-MC-3). Si du code externe
## modifie le mode, le prochain appel reflète la nouvelle valeur.
## Usage : if InputManager.is_mouse_captured(): ...
func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

# ---------------------------------------------------------------------------
# Public methods (refcount enable/disable — ADR-0004 D-4, TR-inp-005)
# ---------------------------------------------------------------------------

## Enregistre [param owner] comme bloqueur d'input. Idempotent — le même owner peut
## appeler cette méthode N fois sans drift : l'entrée dict [code]_enable_blockers[id][/code]
## est le verrou d'idempotence (early-return ligne ci-dessous), donc la connexion
## [signal Node.tree_exited] n'est créée qu'une fois par owner.
## Auto-cleanup : CONNECT_ONE_SHOT retire la connexion après le 1er firing, et le
## handler [method _on_blocker_tree_exited] retire le blocker si l'owner est détruit
## sans avoir appelé release_enable_request.
## Usage : InputManager.request_disable(self)
func request_disable(owner: Node) -> void:
	assert(owner != null, "request_disable: owner must not be null")
	var id: int = owner.get_instance_id()
	if _enable_blockers.has(id):
		return  # Idempotent — même owner déjà enregistré, pas de double-entry ni double-connect.
	_enable_blockers[id] = true
	# CONNECT_ONE_SHOT : Godot supprime la connexion après le 1er firing. Combiné au
	# guard dict ci-dessus, garantit une seule connexion active par owner à la fois.
	owner.tree_exited.connect(_on_blocker_tree_exited.bind(id), CONNECT_ONE_SHOT)
	_update_enabled_state()

## Retire [param owner] de la liste des bloqueurs d'input.
## Safe si owner est déjà null (l'auto-cleanup a tourné via tree_exited).
## Émet push_warning si owner n'avait pas de requête active (desynchro détectée).
## Usage : InputManager.release_enable_request(self)
func release_enable_request(owner: Node) -> void:
	if owner == null:
		return  # Auto-cleanup via tree_exited a déjà tourné — safe no-op.
	var id: int = owner.get_instance_id()
	if not _enable_blockers.erase(id):
		push_warning(
			"release_enable_request: owner %s n'avait pas de requête active" % owner
		)
	_update_enabled_state()

# ---------------------------------------------------------------------------
# Public methods (latency metrics — ADR-0004 D-8, TR-inp-007)
# ---------------------------------------------------------------------------

## Retourne le p99 rolling des latences input→publish sur la fenêtre
## LATENCY_WINDOW_USEC (1 s). Lecture rare (HUD debug F3 ~1 Hz) — tri effectué
## à la demande sur le buffer scratch pré-alloué, pas dans le hot path d'écriture.
##
## Comportement :
## - Filtre les samples dont [code]timestamp < now - LATENCY_WINDOW_USEC[/code].
## - Si 0 sample valide dans la fenêtre → retourne 0.0.
## - Si < 10 samples valides → retourne le [b]max[/b] (le p99 statistique n'a pas
##   de sens avec peu d'échantillons ; capturer le spike est plus utile pour debug).
## - Sinon, retourne la valeur au rang p99 (approximation discrète acceptable HUD).
##
## Technique zero-realloc : copie les valeurs valides dans _latency_scratch[0..valid),
## zero-fill le reste, puis [code]sort()[/code] in-place. Les 0.0 remontent en tête,
## les valeurs valides en queue (tri croissant) — p99 lu depuis la queue.
##
## Usage : var p99 := InputManager.get_latency_p99_ms()
func get_latency_p99_ms() -> float:
	var now: int = Time.get_ticks_usec()
	var cutoff: int = now - LATENCY_WINDOW_USEC
	var valid: int = 0
	# Itérer uniquement sur les slots effectivement remplis (cf. _latency_sample_count).
	# Boucle for-range sur un int = zero-alloc en Godot 4.6 (itérateur intégré).
	for i: int in _latency_sample_count:
		if _latency_timestamps_usec[i] >= cutoff:
			_latency_scratch[valid] = _latency_values_ms[i]
			valid += 1
	if valid == 0:
		return 0.0
	# Zero-fill les slots non-utilisés pour que sort() mette les valeurs valides
	# en fin de buffer (0.0 < toute latence positive mesurée).
	for i: int in range(valid, LATENCY_SAMPLES_CAPACITY):
		_latency_scratch[i] = 0.0
	_latency_scratch.sort()
	# Fallback max si < 10 samples — scratch[CAPACITY - 1] = max après sort.
	if valid < 10:
		return _latency_scratch[LATENCY_SAMPLES_CAPACITY - 1]
	# P99 discret : depuis la fin, on recule de (valid-1)*0.01 positions.
	# Approximation acceptable pour HUD debug (cf. Implementation Notes story-006).
	var p99_idx: int = LATENCY_SAMPLES_CAPACITY - 1 - int((valid - 1) * 0.01)
	return _latency_scratch[p99_idx]

# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Enregistre un sample dans le ring buffer (ADR-0004 D-8). Zero-alloc par
## construction : 2 indexed writes sur des PackedArrays pré-alloués + 2 ops int.
## Appelé uniquement depuis _physics_process après le swap — jamais depuis
## _unhandled_input (hot path mouse 1000 Hz).
func _record_latency_sample(value_ms: float, ts_usec: int) -> void:
	var slot: int = _latency_write_idx % LATENCY_SAMPLES_CAPACITY
	_latency_values_ms[slot] = value_ms
	_latency_timestamps_usec[slot] = ts_usec
	_latency_write_idx += 1
	if _latency_sample_count < LATENCY_SAMPLES_CAPACITY:
		_latency_sample_count += 1
	last_input_to_publish_latency_ms = value_ms

## Handler auto-cleanup : appelé par tree_exited de l'owner (CONNECT_ONE_SHOT).
## Retire le blocker correspondant et met à jour l'état enabled.
func _on_blocker_tree_exited(owner_id: int) -> void:
	if _enable_blockers.erase(owner_id):
		_update_enabled_state()

## Recalcule _enabled depuis l'état de _enable_blockers.
## Émet enabled_changed uniquement si l'état change réellement.
## Vide les flags pressés si on passe à l'état désactivé (évite les ghost presses).
func _update_enabled_state() -> void:
	var new_state: bool = _enable_blockers.is_empty()
	if new_state == _enabled:
		return
	_enabled = new_state
	enabled_changed.emit(_enabled)
	# Clear flags à la transition disabled → évite les ghost presses (AC-DS-4, ADR-0004 D-4).
	if not _enabled:
		for a: StringName in ACTIONS_MVP:
			_pressed_this_tick[a] = false
			_consumed_this_tick[a] = false
