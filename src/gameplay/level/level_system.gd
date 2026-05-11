class_name LevelSystemScript
extends Node

# class_name = LevelSystemScript pour éviter la collision avec le futur autoload
# `LevelSystem` (story 002, ADR-0011 l.460). Cf. mémoire feedback InputManager
# 2026-04-23. Code consommateur (post-autoload) utilise `LevelSystem.xxx` (autoload
# name) ; tests instancient via `LevelSystemScript.new()`.
#
# Architecture : composition via 4 handlers RefCounted injectés
# (_triggers, _queries, _player_tracker, _loader).
# Chaque handler reçoit une référence vers ce Node pour accéder à l'état et aux signaux.
# Pattern miroir audio_system.gd (TD-008 split, voir audio_combat_handler.gd).

# Preload bindings locaux (bypass class cache CI gdUnit4-action, pattern audio_system.gd).
const LevelTriggerHandler := preload("res://src/gameplay/level/level_trigger_handler.gd")
const LevelSceneQueries := preload("res://src/gameplay/level/level_scene_queries.gd")
const LevelPlayerTracker := preload("res://src/gameplay/level/level_player_tracker.gd")
const LevelLoadingHandler := preload("res://src/gameplay/level/level_loading_handler.gd")

# ---------------------------------------------------------------------------
# Constants & Enums
# ---------------------------------------------------------------------------

## États canoniques du cycle de vie d'un niveau.
## L'ordre est défini par le GDD (level-system.md) — ne pas modifier.
enum LevelState {
	UNLOADED,
	LOADING,
	ACTIVE,
	UNLOADING,
}

## Chemin template par défaut pour les scènes d'étage (production).
## Override via scene_path_template pour les tests (DI principle).
const _DEFAULT_SCENE_PATH_TEMPLATE: String = "res://scenes/levels/etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis depuis _physics_process() quand un étage passe en état ACTIVE.
## Source : ADR-0005 D-4, ADR-0011 D-5, TR-lvl-002, TR-lvl-021.
signal level_active(etage_id: int, player_start: Vector3)

## Émis depuis unload_current() AVANT queue_free() de _current_scene_root.
## Source : ADR-0011 D-4 T-3, D-5 ; ADR-0005 D-3 (typed payload).
signal level_unloading(etage_id: int)

## Émis depuis _physics_process() quand le chargement échoue.
## Source : TR-lvl-026, TR-lvl-029, ADR-0005 D-4, ADR-0007 D-7.
signal level_load_failed(etage_id: int, reason: String)

## Émis depuis _physics_process() quand le temps de chargement dépasse le seuil advisory.
## Source : TR-lvl-027, ADR-0011 D-5. Non-bloquant : le chargement continue.
signal level_load_slow(elapsed_ms: int)

## Émis quand le player entre dans EtageExitTrigger.
## Source : TR-lvl-023, ADR-0005 D-4 + T-3.
signal etage_completed(etage_id: int)

## Émis quand le player entre dans un RoomTrigger_NN Area3D.
## Source : TR-lvl-022, TR-lvl-031, TR-lvl-032, ADR-0005 D-3 + D-4 + D-8.
signal room_entered(room_index: int, total_rooms: int)

## Émis quand le player sort du WorldBoundsVolume ou tombe sous Y=-2.
## Source : TR-lvl-017, TR-lvl-018, TR-lvl-024, ADR-0005 D-3 + D-4 + D-8.
signal player_out_of_world(last_valid_position: Vector3)

# ---------------------------------------------------------------------------
# Export variables
# ---------------------------------------------------------------------------

## Chemin template pour les scènes d'étage. Surchargé en test via DI.
@export var scene_path_template: String = _DEFAULT_SCENE_PATH_TEMPLATE

## Seuil advisory (ms) au-delà duquel level_load_slow est émis (TR-lvl-027).
## Surchargeable en test. Valeur ≤ 0 désactive l'émission.
@export var load_slow_threshold_ms: int = 600

# --- State machine ---
var _state: LevelState = LevelState.UNLOADED
var _current_etage_id: int = -1
var _current_room_index: int = -1
var _total_rooms: int = 0
var _current_scene_root: Node3D = null
var _player_start: Vector3 = Vector3.ZERO
var _loading_path: String = ""
var _transition_to_active_pending: bool = false
var _load_progress: Array[float] = []
var _load_started_msec: int = 0
var _load_slow_emitted: bool = false
var _pending_load_failed_etage_id: int = -1
var _pending_load_failed_reason: String = ""
var _pending_load_slow_emit: bool = false

# --- Composition handlers ---
var _triggers: LevelTriggerHandler = null
var _queries: LevelSceneQueries = null
var _player_tracker: LevelPlayerTracker = null
var _loader: LevelLoadingHandler = null

# ---------------------------------------------------------------------------
# Virtual methods + Public API + Internal accessors + Private helpers
# ---------------------------------------------------------------------------

func _ready() -> void:
	_triggers = LevelTriggerHandler.new()
	_triggers._level = self
	_queries = LevelSceneQueries.new()
	_queries._level = self
	_player_tracker = LevelPlayerTracker.new()
	_player_tracker._level = self
	_loader = LevelLoadingHandler.new()
	_loader._level = self


func _process(_delta: float) -> void:
	if _state != LevelState.LOADING:
		return
	_loader.poll_loading(_load_progress)


func _physics_process(_delta: float) -> void:
	# UNLOADING → UNLOADED : confirme destruction scène au tick suivant queue_free (ADR-0011 D-4 T-3).
	if _state == LevelState.UNLOADING and _current_scene_root == null:
		_state = LevelState.UNLOADED
		_reset_runtime_state()
		return

	# Emit deferred level_load_failed (ADR-0005 D-4 ; état déjà UNLOADED via ADR-0005 D-8).
	if _pending_load_failed_reason != "":
		_assert_main_thread()
		var failed_id: int = _pending_load_failed_etage_id
		var reason: String = _pending_load_failed_reason
		_pending_load_failed_reason = ""
		_pending_load_failed_etage_id = -1
		level_load_failed.emit(failed_id, reason)
		return

	# Emit deferred level_load_slow (ADR-0005 D-4) ; load continue, pas de return.
	if _pending_load_slow_emit:
		_pending_load_slow_emit = false
		var elapsed: int = Time.get_ticks_msec() - _load_started_msec
		level_load_slow.emit(elapsed)

	# ACTIVE : safety net player_out_of_world (TR-lvl-018 / EC-1, path 2).
	if _state == LevelState.ACTIVE:
		_player_tracker.tick(get_tree())

	# LOADING → ACTIVE : commit scène + emit level_active (ADR-0005 D-4).
	if not _transition_to_active_pending:
		return
	_transition_to_active_pending = false
	_assert_main_thread()
	_loader.commit_active(get_tree())

## Accesseurs état courant (read-only).
func get_state() -> LevelState: return _state
func get_current_etage_id() -> int: return _current_etage_id
func get_current_room_index() -> int: return _current_room_index
func get_player_start() -> Vector3: return _player_start

## TEST/PERF-ONLY : initialise le LevelSystem pour un runner de performance.
## Passe l'état à ACTIVE et connecte les room triggers de la scène `root` fournie.
## No-op en release. Source : TD-009, story-017.
func prepare_for_perf_runner(root: Node3D) -> void:
	if not OS.has_feature("debug"):
		return
	_state = LevelState.ACTIVE
	_triggers.connect_room_triggers_only(root)


## Lance le chargement threadé de l'étage (UNLOADED → LOADING → ACTIVE).
## Guard : état doit être UNLOADED (ADR-0011 D-4 T-1).
## Émet level_load_failed si scène manquante ou ResourceLoader fail.
func load_etage(etage_id: int) -> void:
	if _state != LevelState.UNLOADED:
		var msg: String = "concurrent load rejected — unload first (state=%s)" % LevelState.keys()[_state]
		push_error(msg)
		assert(false, msg)
		return

	_reset_runtime_state()

	var path: String = scene_path_template % etage_id

	# Pré-check EC-3 (TR-lvl-029) : emit deferred level_load_failed si fichier absent.
	if not ResourceLoader.exists(path):
		push_error("level scene file not found: %s" % path)
		_pending_load_failed_etage_id = etage_id
		_pending_load_failed_reason = "scene file not found: " + path
		_state = LevelState.UNLOADED
		_current_etage_id = -1
		return

	_loading_path = path
	_current_etage_id = etage_id
	_state = LevelState.LOADING
	_load_started_msec = Time.get_ticks_msec()

	var err: int = ResourceLoader.load_threaded_request(_loading_path)
	if err != OK:
		push_error("load_threaded_request failed for %s (err=%d)" % [_loading_path, err])
		_pending_load_failed_etage_id = etage_id
		_pending_load_failed_reason = "load_threaded_request failed (err=%d)" % err
		_state = LevelState.UNLOADED
		_current_etage_id = -1
		_loading_path = ""


## Décharge le niveau courant. Idempotent depuis UNLOADED (no-op silencieux).
## Émet level_unloading(etage_id) AVANT queue_free() (ADR-0011 D-4 T-3).
func unload_current() -> void:
	if _state == LevelState.UNLOADED:
		return
	_assert_main_thread()
	_state = LevelState.UNLOADING
	_transition_to_active_pending = false
	_loading_path = ""
	level_unloading.emit(_current_etage_id)
	if _current_scene_root != null:
		_current_scene_root.queue_free()
		_current_scene_root = null


## Retourne true si l'appelant s'exécute sur le main thread (AC-LVL-29).
func is_on_main_thread() -> bool: return OS.get_thread_caller_id() == OS.get_main_thread_id()
## Reset flag one-shot out_of_world après respawn. Source : TR-lvl-024.
func reset_out_of_world_flag() -> void: _player_tracker.reset_out_of_world_flag()

## Proxys LevelSceneQueries — docs dans level_scene_queries.gd.
## Sources : AC-LVL-30/30b/44/46/53/54(c).
func get_checkpoint_slots() -> Array: return _queries.get_checkpoint_slots()
func get_enemy_slots() -> Array[Marker3D]: return _queries.get_enemy_slots()
func get_hazard_slots() -> Array[Marker3D]: return _queries.get_hazard_slots()
func get_tutorial_anchor(tag: String) -> Marker3D: return _queries.get_tutorial_anchor(tag)
func get_secret_slots() -> Array[Dictionary]: return _queries.get_secret_slots()
func get_surface_material_for(body: StaticBody3D) -> StringName: return _queries.get_surface_material_for(body)
func validate_checkpoint_anchors() -> Array[Dictionary]: return _queries.validate_checkpoint_anchors()
func get_onboarding_anchors() -> Dictionary: return _queries.get_onboarding_anchors()

# Internal state accessors — usage handlers composition uniquement.
func _get_scene_root() -> Node3D: return _current_scene_root
func _get_last_valid_position() -> Vector3: return _player_tracker.get_last_valid_position()
func _get_out_of_world_emitted() -> bool: return _player_tracker.get_out_of_world_emitted()
func _set_out_of_world_emitted(value: bool) -> void: _player_tracker.set_out_of_world_emitted(value)
func _set_current_room_index(idx: int) -> void: _current_room_index = idx
func get_total_rooms() -> int: return _total_rooms
func _set_total_rooms(count: int) -> void: _total_rooms = count
func _set_world_bounds_volume(area: Area3D) -> void: _player_tracker.set_world_bounds_volume(area)

## Guard main-thread avant chaque emit (stories 002-008).
## Exposé semi-public pour les handlers composition.
func _assert_main_thread() -> void:
	assert(is_on_main_thread(), "Level signals must emit on main thread")


## Reset complet du runtime state à l'état UNLOADED initial (TR-lvl-034 EC-12).
## Appelé en début de load_etage() ET en fin de UNLOADING → UNLOADED.
##
## Champs NON resettés : _state, scene_path_template, load_slow_threshold_ms,
## _load_progress (zero-alloc pré-alloué).
func _reset_runtime_state() -> void:
	_current_etage_id = -1
	_current_room_index = -1
	_total_rooms = 0
	_player_start = Vector3.ZERO
	_current_scene_root = null
	_loading_path = ""
	_load_started_msec = 0
	_load_slow_emitted = false
	_pending_load_slow_emit = false
	_pending_load_failed_reason = ""
	_pending_load_failed_etage_id = -1
	_transition_to_active_pending = false
	_player_tracker.reset()


## TEST-ONLY : décale _load_started_msec pour simuler un load lent.
## No-op en release. Source : story-004 AC-LVL-7 Option A.
func _simulate_load_elapsed_ms(ms: int) -> void:
	if not OS.has_feature("debug"):
		return
	_load_started_msec = Time.get_ticks_msec() - ms


## TEST-ONLY : injecte un Node3D racine synthétique comme _current_scene_root.
## No-op en release. Source : story-009 Option 1.
func _set_current_scene_root_for_test(root: Node3D) -> void:
	if not OS.has_feature("debug"):
		return
	_current_scene_root = root
