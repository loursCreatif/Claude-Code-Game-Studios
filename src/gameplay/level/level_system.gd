class_name LevelSystemScript
extends Node

# class_name = LevelSystemScript pour éviter la collision avec le futur autoload
# `LevelSystem` (story 002, ADR-0011 l.460). Cf. mémoire feedback InputManager
# 2026-04-23. Code consommateur (post-autoload) utilise `LevelSystem.xxx` (autoload
# name) ; tests instancient via `LevelSystemScript.new()`.

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

## Reason string statique pour THREAD_LOAD_FAILED — évite toute alloc String en hot path
## (constante compilée, pas construite à la volée dans _process).
## Source : .claude/rules/no-alloc-hot-paths.md — forbidden pattern String concat en hot path.
const REASON_THREAD_LOAD_FAILED: String = "ResourceLoader returned THREAD_LOAD_FAILED"

## Seuil Y strict (exclusive) en-dessous duquel player est considéré hors monde (TR-lvl-018).
## Strict `<` : y = -1.99 → no trigger ; y = -2.0 exact → no trigger ; y = -2.001 → trigger.
## Aligné AC-LVL-25 edge cases (story-008).
const _Y_OUT_OF_WORLD_THRESHOLD: float = -2.0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis depuis _physics_process() quand un étage passe en état ACTIVE.
## Source : ADR-0005 D-4, ADR-0011 D-5, TR-lvl-002, TR-lvl-021.
## Peers connectent avec CONNECT_DEFERRED dans leur _ready() — l'handler peut
## instancier des Nodes, démarrer des streams, ou allouer > 256 B (ADR-0005 D-5).
signal level_active(etage_id: int, player_start: Vector3)

## Émis depuis unload_current() AVANT queue_free() de _current_scene_root.
## Source : ADR-0011 D-4 T-3, D-5 ; ADR-0005 D-3 (typed payload).
## Connection mode = sync (peers désabonnent body_entered handlers — alloc négligeable).
## Exception ADR-0005 D-4 : emit hors _physics_process autorisée car event-triggered
## par appel API direct GSM (ADR-0011 D-5), pas par observation continue d'état.
signal level_unloading(etage_id: int)

## Émis depuis _physics_process() quand le chargement d'un étage échoue (fichier
## absent, scène corrompue, ou ResourceLoader THREAD_LOAD_FAILED).
## Source : TR-lvl-026, TR-lvl-029, ADR-0005 D-4, ADR-0007 D-7.
## Exception ADR-0005 D-3 : payload String autorisé car error path non hot (1× par failure).
## GSM consomme ce signal sync pour transitionner MENU + afficher error screen (ADR-0007 D-7).
## État UNLOADED est garanti AVANT l'émission (ADR-0005 D-8 : mutation d'état avant emit).
signal level_load_failed(etage_id: int, reason: String)

## Émis depuis _physics_process() quand le temps de chargement dépasse 600 ms (advisory).
## Source : TR-lvl-027, ADR-0011 D-5.
## Non-bloquant : le chargement continue ; level_active sera quand même émis quand prêt.
## Gate hard = 1000 ms (story-017, distinct de ce seuil advisory).
signal level_load_slow(elapsed_ms: int)

## Émis quand le player entre dans EtageExitTrigger (Area3D), atteignant la sortie d'étage.
## Source : TR-lvl-023, ADR-0005 D-4 (emit depuis physics context Area3D.body_entered),
## ADR-0005 T-3 (emit signal transition AVANT mutation d'état via unload_current()).
## Fire-once semantics : `_on_etage_exit_body_entered` guard `_state != ACTIVE` empêche
## re-emission après 1er trigger ; EC-6 no back-out (transition UNLOADING immédiate).
signal etage_completed(etage_id: int)

## Émis quand le player entre dans un RoomTrigger_NN Area3D enfant d'InteractiveVolumes.
## Source : TR-lvl-022, TR-lvl-031, TR-lvl-032, ADR-0005 D-3 (typed int payload), D-4
## (emit depuis physics context Area3D.body_entered), D-8 (idempotent par entry —
## re-entry après exit = nouvelle transition = nouveau signal, pas de Level-side dedup).
## Payload : room_index 0-indexed (RoomTrigger_03 → 2), total_rooms = nombre de
## RoomTrigger_* trouvés au LOADING→ACTIVE.
signal room_entered(room_index: int, total_rooms: int)

## Émis quand le player sort du WorldBoundsVolume (Area3D body_exited) OU tombe
## sous Y=-2 (safety net dans _physics_process). Payload `last_valid_position`
## = dernière position connue dans bounds (capturée en physics process tick).
## Source : TR-lvl-017, TR-lvl-018, TR-lvl-024, ADR-0005 D-3 (Vector3 value-type),
## D-4 (emit depuis physics context), D-8 (idempotent par cycle vie — flag
## `_out_of_world_emitted_this_life` bloque re-emission jusqu'à respawn).
##
## Consumer = CheckpointSystem (epic futur) ; Level ne respawn PAS lui-même
## (encapsulation R-3 / TR-lvl-024). Reset du flag par caller externe via
## reset_out_of_world_flag() OU automatiquement à load_etage() fresh.
##
## Connection mode SYNC (CheckpointSystem handler léger = lookup checkpoint
## + teleport — pas de Node instantiation, pas d'AudioStreamPlayer, ADR-0005 D-5).
signal player_out_of_world(last_valid_position: Vector3)

# ---------------------------------------------------------------------------
# Export variables
# ---------------------------------------------------------------------------

## Chemin template pour les scènes d'étage. Surchargé en test via :
##   level.scene_path_template = "res://tests/fixtures/levels/test_etage_%02d.tscn"
## Doit être défini AVANT add_child() pour que load_etage() utilise le bon chemin.
@export var scene_path_template: String = _DEFAULT_SCENE_PATH_TEMPLATE

## Seuil advisory (ms) au-delà duquel level_load_slow est émis pendant un load (TR-lvl-027).
## Default 600 ms aligné GDD ; gate hard séparé = 1000 ms (story 017, hors scope ici).
## Surchargeable en test pour rendre le seuil franchissable de manière déterministe :
##   level.load_slow_threshold_ms = 1       # toute fixture > 1 ms déclenche
##   level.load_slow_threshold_ms = 60_000  # aucun load réel ne le franchira
## Valeur ≤ 0 désactive l'émission silencieusement (no-op poll branch).
@export var load_slow_threshold_ms: int = 600

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

var _state: LevelState = LevelState.UNLOADED
var _current_etage_id: int = -1
var _current_room_index: int = -1  # Reset par _reset_runtime_state (TR-lvl-034). Cf. get_current_room_index() pour sémantique.
var _total_rooms: int = 0  # Cached au LOADING→ACTIVE via find_children. Reset par _reset_runtime_state.
var _current_scene_root: Node3D = null  # Racine scène d'étage (get_tree().root child).
var _player_start: Vector3 = Vector3.ZERO  # Position spawn (via _discover_player_start).
var _loading_path: String = ""  # Path scène en cours de chargement threadé.
var _transition_to_active_pending: bool = false  # Set par _process (LOADED), consommé par _physics_process.
var _load_progress: Array[float] = []  # Buffer pré-alloué zero-alloc pour load_threaded_get_status.
var _load_started_msec: int = 0  # Horodatage début load pour advisory level_load_slow (TR-lvl-027).
var _load_slow_emitted: bool = false  # Flag one-shot level_load_slow par load ; reset en load_etage().
var _pending_load_failed_etage_id: int = -1  # Payload deferred level_load_failed (ADR-0005 D-4).
var _pending_load_failed_reason: String = ""  # String vide = pas de failure pending.
var _pending_load_slow_emit: bool = false  # Set par _process (seuil franchi), émis en _physics_process.
var _last_valid_position: Vector3 = Vector3.ZERO  # Mis à jour chaque _physics_process si player dans bounds + y >= -2 (TR-lvl-024).
var _out_of_world_emitted_this_life: bool = false  # Flag one-shot par life ; reset par reset_out_of_world_flag() ou load_etage() fresh.
var _world_bounds_volume: Area3D = null  # Cached au LOADING→ACTIVE pour test inclusion player dans bounds en _physics_process.
var _player_node: Node3D = null  # Cached lookup groupe "player" au LOADING→ACTIVE — re-cherché si null.

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _state != LevelState.LOADING:
		return

	var status: int = ResourceLoader.load_threaded_get_status(_loading_path, _load_progress)

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_transition_to_active_pending = true  # Commit dans _physics_process (ADR-0005 D-4).
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		push_error("ResourceLoader threaded load failed for %s" % _loading_path)
		_pending_load_failed_etage_id = _current_etage_id
		_pending_load_failed_reason = REASON_THREAD_LOAD_FAILED
		# Mutation d'état AVANT l'emit (ADR-0005 D-8).
		_state = LevelState.UNLOADED
		_current_etage_id = -1
		_loading_path = ""
		_transition_to_active_pending = false  # Ferme la race avec THREAD_LOAD_LOADED pending.
		_load_slow_emitted = true
		_pending_load_slow_emit = false
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# Advisory slow-load (TR-lvl-027) : flag one-shot si > seuil, seuil ≤ 0 désactive.
		if (
			not _load_slow_emitted
			and load_slow_threshold_ms > 0
			and (Time.get_ticks_msec() - _load_started_msec) > load_slow_threshold_ms
		):
			_load_slow_emitted = true
			_pending_load_slow_emit = true


func _physics_process(_delta: float) -> void:
	# UNLOADING → UNLOADED : confirme destruction scène au tick suivant queue_free (ADR-0011 D-4 T-3).
	# Reset complet runtime state (TR-lvl-034 EC-12) : double safety net avec load_etage().
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
	# Exécuté chaque tick quand ACTIVE — coût : 1 comparaison + 1 lookup + 1 Vector3 assign (zero-alloc).
	# Placé AVANT le guard LOADING→ACTIVE pour s'exécuter même si pas de transition en cours.
	if _state == LevelState.ACTIVE:
		_update_last_valid_position_and_check_y_threshold()

	# LOADING → ACTIVE : commit scène + emit level_active (ADR-0005 D-4).
	if not _transition_to_active_pending:
		return
	_transition_to_active_pending = false

	_assert_main_thread()  # Guard avant mutation (ADR-0011 D-5 / AC-LVL-29).

	var packed: PackedScene = ResourceLoader.load_threaded_get(_loading_path) as PackedScene
	if packed == null:
		push_error("load_threaded_get returned null for %s" % _loading_path)
		_state = LevelState.UNLOADED
		_loading_path = ""
		return

	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	if root_3d == null:
		push_error("level scene root must be Node3D, got %s" % instance.get_class())
		instance.queue_free()
		_state = LevelState.UNLOADED
		_loading_path = ""
		return

	# ADR-0011 REQ-8 + body l.127 : la scène d'étage est attachée à get_tree().root,
	# PAS au singleton Level (ownership tree naturel + queue_free sans tree-rewire).
	get_tree().root.add_child(root_3d)
	_current_scene_root = root_3d
	_player_start = _discover_player_start(root_3d)
	_connect_etage_exit_trigger(root_3d)
	_connect_room_triggers(root_3d)
	_connect_world_bounds_volume(root_3d)
	_state = LevelState.ACTIVE
	_loading_path = ""

	# Enemy GDD r2 Rule 9 / OQ-ENM-2 : LevelSystem est la factory directe des grunts.
	# Spawn AVANT level_active.emit pour que les consumers voient une scène populée.
	# Helper static pur — pas d'autoload, pas de state, allocation mineure 1× par boot étage.
	EnemySpawner.spawn_for_scene(_current_scene_root)

	level_active.emit(_current_etage_id, _player_start)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Retourne l'état courant du système de niveau.
func get_state() -> LevelState:
	return _state


## TEST/PERF-ONLY : initialise le LevelSystem pour un runner de performance en contournant
## le cycle de chargement threadé normal.
##
## Passe l'état interne à ACTIVE et connecte les room triggers de la scène `root` fournie.
## Remplace les accès privés `_state` + `_connect_room_triggers` du runner de perf
## (TD-009 — encapsulation breach supprimé). Conforme au pattern test-hook `_simulate_load_elapsed_ms`
## (story-004 Option A) et `_set_current_scene_root_for_test` (story-009).
##
## No-op en release (OS.has_feature("debug") false).
## Réservé aux runners de performance (level_frame_time_runner, level_draw_calls_runner, etc.)
## et aux tests unitaires/intégration. Ne jamais appeler depuis le code de production.
##
## [param root] : racine Node3D de la fixture chargée — doit déjà être dans le SceneTree.
## Source : TD-009, story-017, tests/performance/level_frame_time_runner.gd.
func prepare_for_perf_runner(root: Node3D) -> void:
	if not OS.has_feature("debug"):
		return
	_state = LevelState.ACTIVE
	_connect_room_triggers(root)


## Retourne l'id de l'étage courant (ou en cours de chargement), -1 si aucun.
## En LOADING, reflète déjà l'id cible (ADR-0007 D-7).
func get_current_etage_id() -> int:
	return _current_etage_id


## Retourne l'index 0-based de la room courante dans l'étage actif, -1 si aucune.
## Mute via room_entered handler (story-007). Reset à -1 par _reset_runtime_state()
## à chaque load_etage() et UNLOADING → UNLOADED (TR-lvl-034 EC-12).
func get_current_room_index() -> int:
	return _current_room_index


## Retourne la position de spawn du joueur dans le niveau actif.
## Vaut Vector3.ZERO tant qu'aucun niveau n'est chargé.
func get_player_start() -> Vector3:
	return _player_start


## Lance le chargement threadé de l'étage (UNLOADED → LOADING → ACTIVE).
## Guard : état doit être UNLOADED — appel concurrent rejeté avec push_error + assert (ADR-0011 D-4 T-1).
## Émet level_load_failed(id, reason) si scène manquante ou ResourceLoader fail (TR-lvl-026/029).
func load_etage(etage_id: int) -> void:
	if _state != LevelState.UNLOADED:
		var msg: String = "concurrent load rejected — unload first (state=%s)" % LevelState.keys()[_state]
		push_error(msg)  # Ordre push_error → assert : GdUnit4 capture is_push_error (story-001 B2).
		assert(false, msg)
		return

	# Reset complet runtime state (TR-lvl-034 EC-12 + AC-LVL-7 re-load + AC-LVL-9).
	# Idempotent : peut être appelé même si certains champs sont déjà à leur default.
	_reset_runtime_state()

	var path: String = scene_path_template % etage_id

	# Pré-check EC-3 (TR-lvl-029) : emit deferred level_load_failed si fichier absent.
	if not ResourceLoader.exists(path):
		push_error("level scene file not found: %s" % path)
		_pending_load_failed_etage_id = etage_id
		_pending_load_failed_reason = "scene file not found: " + path  # 1× par failure, exception ADR-0005 D-3.
		_state = LevelState.UNLOADED  # ADR-0005 D-8 : état avant emit.
		_current_etage_id = -1
		return

	_loading_path = path
	_current_etage_id = etage_id
	_state = LevelState.LOADING
	_load_started_msec = Time.get_ticks_msec()  # Capturé AVANT le thread (TR-lvl-027).

	var err: int = ResourceLoader.load_threaded_request(_loading_path)
	if err != OK:
		push_error("load_threaded_request failed for %s (err=%d)" % [_loading_path, err])
		_pending_load_failed_etage_id = etage_id
		_pending_load_failed_reason = "load_threaded_request failed (err=%d)" % err
		_state = LevelState.UNLOADED  # ADR-0005 D-8.
		_current_etage_id = -1
		_loading_path = ""


## Décharge le niveau courant. Idempotent depuis UNLOADED (no-op silencieux).
## Émet level_unloading(etage_id) AVANT queue_free() — 1 frame cleanup peers (ADR-0011 D-4 T-3).
## _current_etage_id resetté au tick physique suivant, pas ici (payload valide pendant handlers).
func unload_current() -> void:
	if _state == LevelState.UNLOADED:
		return
	_assert_main_thread()
	_state = LevelState.UNLOADING
	# Reset flags LOADING annulé : évite re-bascule ACTIVE après UNLOADING→UNLOADED.
	_transition_to_active_pending = false
	_loading_path = ""
	level_unloading.emit(_current_etage_id)
	if _current_scene_root != null:
		_current_scene_root.queue_free()
		_current_scene_root = null


## Retourne true si l'appelant s'exécute sur le main thread (AC-LVL-29 testabilité).
## API Godot 4.6 : OS.get_thread_caller_id() — pas Thread.get_caller_id() (inexistant static 4.6).
func is_on_main_thread() -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id()


## Reset le flag one-shot `_out_of_world_emitted_this_life` à false.
## Appelé par le CheckpointSystem (epic futur) après respawn pour permettre une
## nouvelle émission de `player_out_of_world` dans le prochain cycle de vie.
## Source : TR-lvl-024, story-008 implementation notes (consumer = CheckpointSystem).
##
## Idempotent : appelable depuis n'importe quel state, n'a d'effet que si le flag
## était à true. Pas de signal émis ici (reset = restauration, pas transition).
func reset_out_of_world_flag() -> void:
	_out_of_world_emitted_this_life = false


## Retourne tuples paired { volume: Area3D, anchor: Vector3 } pour chaque CheckpointVolume_NN
## ↔ CheckpointAnchor_NN authoré dans la scène d'étage active.
## Source : AC-LVL-30b, ADR-0005 D-10 (API publique read-only consommée par peers).
##
## Convention naming : CheckpointVolume_01 ↔ CheckpointAnchor_01 (zero-pad NN strict).
## Volume sans anchor paired → push_warning + skip (pas d'exception). 0 checkpoints = [].
##
## Appel typique : 1× par peer au handler `_on_level_active` (sync safe-point post-emission).
## Pas en hot path → coût find_children O(n) acceptable.
## Guard scene_root null → return [] + push_warning (état UNLOADED ou LOADING).
func get_checkpoint_slots() -> Array:
	if _current_scene_root == null:
		push_warning("get_checkpoint_slots called before level_active — returning empty array")
		return []
	var slots: Array = []
	var volumes: Array[Node] = _current_scene_root.find_children("CheckpointVolume_*", "Area3D", true, false)
	for v: Node in volumes:
		var area: Area3D = v as Area3D
		var idx: String = area.name.trim_prefix("CheckpointVolume_")
		var anchor_node: Node = _current_scene_root.find_child("CheckpointAnchor_" + idx, true, false)
		if anchor_node == null:
			push_warning("CheckpointVolume_%s missing paired CheckpointAnchor" % idx)
			continue
		var anchor: Marker3D = anchor_node as Marker3D
		if anchor == null:
			push_warning("CheckpointAnchor_%s exists but is not a Marker3D" % idx)
			continue
		slots.append({"volume": area, "anchor": anchor.global_position})
	return slots


## Retourne tous les EnemySlot_* Marker3D de la scène d'étage active (TR : enemy spawn).
## Source : AC-LVL-30b (apparenté), ADR-0005 D-10.
## Order = DFS preorder Godot (cohérent EC-5 TR-lvl-031 deterministic ordering).
## Guard scene_root null → return [] + push_warning.
func get_enemy_slots() -> Array[Marker3D]:
	if _current_scene_root == null:
		push_warning("get_enemy_slots called before level_active — returning empty array")
		return []
	var nodes: Array[Node] = _current_scene_root.find_children("EnemySlot_*", "Marker3D", true, false)
	var result: Array[Marker3D] = []
	for n: Node in nodes:
		result.append(n as Marker3D)
	return result


## Retourne tous les HazardSlot_* Marker3D de la scène d'étage active.
## Source : AC-LVL-30b (apparenté), ADR-0005 D-10.
## Guard scene_root null → return [] + push_warning.
func get_hazard_slots() -> Array[Marker3D]:
	if _current_scene_root == null:
		push_warning("get_hazard_slots called before level_active — returning empty array")
		return []
	var nodes: Array[Node] = _current_scene_root.find_children("HazardSlot_*", "Marker3D", true, false)
	var result: Array[Marker3D] = []
	for n: Node in nodes:
		result.append(n as Marker3D)
	return result


## Retourne le Marker3D dont le nom == tag (case-sensitive), null si introuvable.
## Source : AC-LVL-30, ADR-0005 D-10.
## Convention : tag = `name` exact du Marker3D (e.g. "first_dash", "first_wall").
## Tag introuvable → push_warning + null (pas d'exception). Tag matche le 1er résultat
## si plusieurs (cas non-canonique → invariant scène, pas couvert par lint AU MVP).
## Guard scene_root null → return null + push_warning.
func get_tutorial_anchor(tag: String) -> Marker3D:
	if _current_scene_root == null:
		push_warning("get_tutorial_anchor called before level_active — returning null")
		return null
	var markers: Array[Node] = _current_scene_root.find_children(tag, "Marker3D", true, false)
	if markers.is_empty():
		push_warning("tutorial anchor not found: %s" % tag)
		return null
	return markers[0] as Marker3D


## Retourne tous les triplets secret (lure, collect_volume, content_anchor, required_ability)
## de la scène d'étage active.
## Source : AC-LVL-46 / AC-LVL-53 (story-018 r2), ADR-0005 D-10 (API publique read-only
## consommée par peers).
##
## Convention naming : SecretLureMarker_01 ↔ SecretCollectVolume_01 ↔ SecretAnchor_01
## (zero-pad NN strict). Triplet incomplet (un des 3 manquant) → push_warning + skip
## (pas d'exception). 0 secrets = [].
##
## Appel typique : 1× par peer (Secret System) au handler `_on_level_active`.
## Pas en hot path → coût find_children O(n) acceptable.
## Guard scene_root null → return [] + push_warning (état UNLOADED ou LOADING).
##
## Clés du Dictionary retourné :
##   "lure"            : Marker3D   — SecretLureMarker_NN (spawn VFX lure)
##   "collect_volume"  : Area3D     — SecretCollectVolume_NN (détection collection)
##   "content_anchor"  : Vector3    — position globale du SecretAnchor_NN (spawn contenu)
##   "required_ability": StringName — valeur exportée du SecretLureMarker_NN
func get_secret_slots() -> Array[Dictionary]:
	if _current_scene_root == null:
		push_warning("get_secret_slots called before level_active — returning empty array")
		return []
	var slots: Array[Dictionary] = []
	var lures: Array[Node] = _current_scene_root.find_children("SecretLureMarker_*", "Marker3D", true, false)
	for l: Node in lures:
		var lure: Marker3D = l as Marker3D
		if lure == null:
			continue
		var idx: String = String(lure.name).trim_prefix("SecretLureMarker_")
		var collect_node: Node = _current_scene_root.find_child("SecretCollectVolume_" + idx, true, false)
		var anchor_node: Node = _current_scene_root.find_child("SecretAnchor_" + idx, true, false)
		if collect_node == null:
			push_warning("SecretLureMarker_%s missing paired SecretCollectVolume" % idx)
			continue
		if anchor_node == null:
			push_warning("SecretLureMarker_%s missing paired SecretAnchor" % idx)
			continue
		var collect: Area3D = collect_node as Area3D
		var anchor: Marker3D = anchor_node as Marker3D
		if collect == null or anchor == null:
			push_warning(
				"Secret triplet %s : type incorrect (volume=%s, anchor=%s)" % [
					idx, collect_node.get_class(), anchor_node.get_class()
				]
			)
			continue
		# Lookup permissif via Object.get() : `as SecretLureMarker` ne peut pas
		# être utilisé ici car level_system.gd est chargé comme autoload AVANT
		# que la SceneTree complète peuple le registry class_name (cf. pattern
		# `const Script: GDScript = preload(...)` adopté par level_lint.gd pour
		# la même raison). Si la scène contient un Marker3D nommé SecretLureMarker_NN
		# sans le script attaché, .get() retourne null → fallback &"" (lint
		# signalera la violation séparément AC-LVL-53).
		var ability: Variant = lure.get("required_ability")
		var ability_sn: StringName = &"" if ability == null else (ability as StringName)
		slots.append({
			"lure": lure,
			"collect_volume": collect,
			"content_anchor": anchor.global_position,
			"required_ability": ability_sn,
		})
	return slots


## Handler à connecter au signal Area3D.body_entered de l'EtageExitTrigger.
## Émet etage_completed(_current_etage_id) puis enchaîne unload_current() (T-3 ADR-0005).
## Source : TR-lvl-023, AC-LVL-24, ADR-0005 D-4 + T-3 + D-8.
##
## Idempotence garantie par guard `_state != ACTIVE` :
##   - re-entry après 1er trigger (state = UNLOADING) → no-op (EC-6 no back-out)
##   - body_entered pendant LOADING/UNLOADING/UNLOADED → no-op
##   - body sans groupe "player" (enemies, projectiles) → no-op
##
## Note : body_entered est émis par Godot dans le contexte physics step → conforme ADR-0005 D-4.
func _on_etage_exit_body_entered(body: Node3D) -> void:
	if _state != LevelState.ACTIVE:
		return  # Fire-once + EC-6 no back-out + state guards (LOADING/UNLOADING/UNLOADED)
	if not body.is_in_group("player"):
		return  # Filtre enemies/projectiles (groupe conventionnel posé par PlayerController)
	_assert_main_thread()
	etage_completed.emit(_current_etage_id)
	unload_current()  # Enchaîne T-3 immédiatement (ACTIVE → UNLOADING)


## Handler à connecter au signal Area3D.body_entered de chaque RoomTrigger_NN.
## Source : TR-lvl-022, TR-lvl-031, TR-lvl-032, AC-LVL-21..23 + AC-LVL-38, ADR-0005 D-4 + D-8.
##
## Guards :
##   - state != ACTIVE → no-op (LOADING/UNLOADING/UNLOADED, EC-2)
##   - body sans groupe "player" → no-op (filtre enemies/projectiles)
##   - body.global_position NaN ou Inf sur x/y/z → push_warning + no-op (EC-9, TR-lvl-032)
##
## Pas de Level-side dedup : re-entry après exit ré-émet (TR-lvl-022 ; HUD dedupliques si besoin).
## Tree order deterministic on simultaneous overlap par DFS preorder Godot (EC-5, TR-lvl-031).
func _on_room_trigger_body_entered(body: Node3D, room_index: int) -> void:
	if _state != LevelState.ACTIVE:
		return
	if not body.is_in_group("player"):
		return
	var pos: Vector3 = body.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		push_warning("room_entered ignored: body position contains NaN")
		return
	if is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z):
		push_warning("room_entered ignored: body position contains Inf")
		return
	_assert_main_thread()
	_current_room_index = room_index
	room_entered.emit(room_index, _total_rooms)


## Handler Area3D.body_exited de WorldBoundsVolume (path 1 primary).
## Source : TR-lvl-017, TR-lvl-024, AC-LVL-25 path 1, ADR-0005 D-4 + D-8.
##
## Guards :
##   - state != ACTIVE → no-op (LOADING/UNLOADING/UNLOADED, EC-2)
##   - body sans groupe "player" → no-op (filtre enemies/projectiles)
##   - flag `_out_of_world_emitted_this_life` true → no-op (idempotence)
##   - body.global_position NaN/Inf → push_warning + no-op (cohérent story-007 TR-lvl-032)
##
## Note : body_exited émis par Godot dans contexte physics step → conforme ADR-0005 D-4.
func _on_world_bounds_body_exited(body: Node3D) -> void:
	if _state != LevelState.ACTIVE:
		return
	if not body.is_in_group("player"):
		return
	if _out_of_world_emitted_this_life:
		return
	# NaN/Inf guard cohérent story-007 (TR-lvl-032)
	var pos: Vector3 = body.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		push_warning("player_out_of_world ignored: body position contains NaN")
		return
	if is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z):
		push_warning("player_out_of_world ignored: body position contains Inf")
		return
	_out_of_world_emitted_this_life = true  # ADR-0005 D-8 mutation avant emit
	_assert_main_thread()
	player_out_of_world.emit(_last_valid_position)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Connecte le signal body_entered de l'EtageExitTrigger (Area3D) au handler interne.
## Doit être appelé depuis le branch LOADING→ACTIVE APRÈS _discover_player_start et
## AVANT level_active.emit() pour que la connexion soit active dès le premier tick physique.
## Source : TR-lvl-023, AC-LVL-24, ADR-0005 D-4 + D-8.
##
## Comportement selon le nombre de triggers trouvés :
##   0 → push_warning (pas push_error) : story-010 gère l'invariant d'existence.
##   1 → connexion sync (handler léger : 2 guards + emit + unload_current).
##   >1 → push_error + assert(false) : hiérarchie corrompue (miroir _discover_player_start).
func _connect_etage_exit_trigger(root: Node3D) -> void:
	var areas: Array[Node] = root.find_children("EtageExitTrigger", "Area3D", true, false)
	if areas.size() == 0:
		push_warning("EtageExitTrigger Area3D not found in level scene — etage_completed will never fire")
		return
	if areas.size() > 1:
		var msg: String = "multiple EtageExitTrigger Area3D found in level scene — hierarchy violation"
		push_error(msg)
		assert(false, msg)
		return
	var area: Area3D = areas[0] as Area3D
	area.body_entered.connect(_on_etage_exit_body_entered)


## Connecte body_entered de chaque RoomTrigger_NN Area3D (enfant d'InteractiveVolumes)
## au handler `_on_room_trigger_body_entered`. Cache _total_rooms = nombre trouvé.
## Source : TR-lvl-022, TR-lvl-031.
##
## Convention nommage : RoomTrigger_NN avec @export var room_index: int (0-indexed,
## fallback parse name si absent). Tree order = ordre déclaration dans InteractiveVolumes
## → garantit deterministic ordering on simultaneous overlap (EC-5, TR-lvl-031).
func _connect_room_triggers(root: Node3D) -> void:
	var triggers: Array[Node] = root.find_children("RoomTrigger_*", "Area3D", true, false)
	_total_rooms = triggers.size()
	if _total_rooms == 0:
		push_warning("no RoomTrigger_* Area3D found in level scene — room_entered will never fire")
		return
	for node: Node in triggers:
		var area: Area3D = node as Area3D
		var idx: int = _extract_room_index(area)
		area.body_entered.connect(_on_room_trigger_body_entered.bind(idx))


## Connecte body_exited de WorldBoundsVolume (Area3D enfant InteractiveVolumes).
## Source : TR-lvl-017, AC-LVL-25 (path 1), ADR-0011 D-9 BoxShape3D obligatoire.
##
## Comportement selon le nombre trouvé :
##   0 → push_warning : safety net Y<-2 prend le relais (path 2).
##   1 → connexion sync (handler léger : 3 guards + 1 emit).
##   >1 → push_error + assert : hiérarchie corrompue.
func _connect_world_bounds_volume(root: Node3D) -> void:
	var areas: Array[Node] = root.find_children("WorldBoundsVolume", "Area3D", true, false)
	if areas.size() == 0:
		push_warning("WorldBoundsVolume Area3D not found — only Y<-2 safety net active")
		_world_bounds_volume = null
		return
	if areas.size() > 1:
		var msg: String = "multiple WorldBoundsVolume Area3D found — hierarchy violation"
		push_error(msg)
		assert(false, msg)
		return
	_world_bounds_volume = areas[0] as Area3D
	_world_bounds_volume.body_exited.connect(_on_world_bounds_body_exited)


## Extract 0-indexed room_index depuis Area3D : préfère @export property, fallback parse name.
## Convention nommage : RoomTrigger_03 → parts[1] = "03" → int("03") - 1 = 2 (0-indexed payload).
## En cas d'erreur de nommage (pas de "_" ou suffixe non numérique) : push_error + retourne -1.
func _extract_room_index(area: Area3D) -> int:
	if "room_index" in area:
		return area.get("room_index") as int
	var parts: PackedStringArray = area.name.split("_")
	if parts.size() < 2 or not parts[1].is_valid_int():
		push_error("RoomTrigger naming violation: %s (expected RoomTrigger_NN)" % area.name)
		return -1
	return int(parts[1]) - 1


## Cherche le Marker3D "PlayerStart" dans root. Exactement 1 requis.
## En debug : push_error → assert(false). En release : push_error + Vector3.ZERO.
func _discover_player_start(root: Node3D) -> Vector3:
	var markers: Array[Node] = root.find_children("PlayerStart", "Marker3D", true, false)
	if markers.size() != 1:
		push_error("missing PlayerStart marker")
		assert(false, "missing PlayerStart marker")
		return Vector3.ZERO
	return (markers[0] as Marker3D).global_position


## Update `_last_valid_position` chaque tick si y >= -2 ; emit `player_out_of_world`
## (path 2 safety net) si y < -2 et pas encore émis.
## Source : TR-lvl-018 (Y ≥ -2 trigger respawn gate), TR-lvl-024, ADR-0005 D-4 + D-8.
##
## Path 1 (primary) = Area3D `body_exited` handler `_on_world_bounds_body_exited`.
## Path 2 (safety net) = ce check `y < -2.0` ici dans _physics_process — couvre
## le cas où player tunnel au bord du WorldBoundsVolume sans déclencher body_exited.
##
## Pourquoi pas de check "dedans WorldBoundsVolume" ici (cf. story-008 spec l.39) :
## en Godot 4.6, `Area3D.body_exited` fire en fin de physics step, AVANT le
## `_physics_process` du step suivant. Donc lorsque player sort des bounds, path 1
## émet AVANT que ce helper ne mette à jour `_last_valid_position` — le payload
## émis correspond bien à la dernière position dans les bounds. Le check de
## containment serait redondant et coûteux (overlap query Jolt par tick).
##
## Zero-alloc hot path : seulement comparaisons + assignement Vector3 value-type
## + 1 emit gardé par flag (ADR-0005 D-9, .claude/rules/no-alloc-hot-paths.md).
func _update_last_valid_position_and_check_y_threshold() -> void:
	var player: Node3D = _resolve_player_node()
	if player == null:
		return  # Pas de player encore dans la scène — peut arriver pendant boot
	var pos: Vector3 = player.global_position
	# NaN/Inf guard cohérent story-007 (TR-lvl-032).
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		return
	if is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z):
		return
	# Path 2 safety net : y < -2 et pas déjà émis ce life → emit avec last valid pos.
	if pos.y < _Y_OUT_OF_WORLD_THRESHOLD and not _out_of_world_emitted_this_life:
		_out_of_world_emitted_this_life = true  # ADR-0005 D-8 mutation avant emit
		_assert_main_thread()
		player_out_of_world.emit(_last_valid_position)
		return
	# Update last valid position si y >= seuil.
	if pos.y >= _Y_OUT_OF_WORLD_THRESHOLD:
		_last_valid_position = pos


## Resolve & cache le node player via groupe "player". Re-lookup si null ou invalidé.
## Pattern peer lookup conventionnel (cohérent _connect_room_triggers find_children).
##
## Coût allocation :
##   - Cache hit (steady state gameplay) : zero-alloc, 1 comparaison + 1 is_instance_valid.
##   - Cache miss : `get_tree().get_nodes_in_group("player")` alloue 1 Array[Node].
##     Fenêtres miss bornées : (a) 1er tick post-`level_active` (cache vide) ;
##     (b) post-`_reset_runtime_state()` (load_etage / UNLOADING→UNLOADED) ;
##     (c) si player free + respawn par CheckpointSystem (rare).
##   Hors de ces fenêtres, l'hot-path `_update_last_valid_position` reste zero-alloc.
func _resolve_player_node() -> Node3D:
	if _player_node != null and is_instance_valid(_player_node):
		return _player_node
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	_player_node = players[0] as Node3D
	return _player_node


## Guard main-thread avant chaque emit (stories 002-008).
func _assert_main_thread() -> void:
	assert(is_on_main_thread(), "Level signals must emit on main thread")


## Reset complet du runtime state à l'état UNLOADED initial (TR-lvl-034 EC-12).
## Appelé en début de `load_etage()` (clear residual avant nouveau cycle) ET en fin
## de transition UNLOADING → UNLOADED dans `_physics_process` (double safety net
## idempotent garantissant fresh state quel que soit le chemin de sortie).
##
## Source : ADR-0007 D-8 (Level reset son propre state à chaque load_etage fresh ;
## progression jeu — secrets, kills, rooms_visited cumulés — owned par GSM).
##
## Champs NON resettés (intentionnel) :
##   - `_state` : géré par caller (LOADING / UNLOADED selon contexte).
##   - `scene_path_template`, `load_slow_threshold_ms` : config DI test/prod.
##   - `_load_progress` : Array[float] pré-alloué zero-alloc (pattern zero-alloc ADR-0011).
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
	_last_valid_position = Vector3.ZERO
	_out_of_world_emitted_this_life = false
	_world_bounds_volume = null
	_player_node = null


## TEST-ONLY : décale _load_started_msec en arrière de `ms` ms pour simuler un load lent.
## No-op en release (OS.has_feature("debug") false). Source : story-004 AC-LVL-7 Option A.
func _simulate_load_elapsed_ms(ms: int) -> void:
	if not OS.has_feature("debug"):
		return
	_load_started_msec = Time.get_ticks_msec() - ms


## Valide à l'exécution que les CheckpointAnchor_NN ne sont pas enfermés dans
## un StaticBody3D de la géométrie statique (LAYER_ENVIRONMENT).
##
## Principe : pour chaque CheckpointAnchor_NN Marker3D présent dans la scène active,
## un petit SphereShape3D (r=0.3) est testé en `intersect_shape` contre
## LAYER_ENVIRONMENT via `PhysicsDirectSpaceState3D`. Un résultat non-vide indique
## que l'anchor est à l'intérieur d'un StaticBody3D — l'authoring est invalide.
##
## Pré-requis : la scène doit être dans le scene tree AVANT l'appel pour que
## `get_world_3d().direct_space_state` soit disponible. En test, utiliser
## `_set_current_scene_root_for_test(root)` après `add_child(root)`.
##
## Guard `_current_scene_root == null` → push_warning + retourne [].
##
## Collision mask : `CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])`
## conforme ADR-0008 D-3 et rule `.claude/rules/collision-layer-api-1-indexed.md`.
## (La story propose `1 << 3` — interdit par le rule ; build_mask produit le même bitmask.)
##
## API non hot-path (debug utility / authoring check) : l'allocation d'un SphereShape3D
## et d'un PhysicsShapeQueryParameters3D réutilisés en boucle est intentionnelle
## (.claude/rules/no-alloc-hot-paths.md ne couvre pas ce chemin).
##
## [return] : Array[Dictionary] de violations, chaque entrée :
##   { "anchor_name": String, "position": Vector3, "reason": "inside_static_body" }
## Consumer = Checkpoint System (epic futur) pour valider la sécurité des respawns.
## Source : TR-lvl-038, ADR-0001 (Jolt physics space state), story-021 AC-LVL-40.
func validate_checkpoint_anchors() -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	if _current_scene_root == null or not is_instance_valid(_current_scene_root):
		push_warning("validate_checkpoint_anchors called before level_active — returning empty array")
		return results

	var anchor_nodes: Array[Node] = _current_scene_root.find_children(
		"CheckpointAnchor_*", "Marker3D", true, false
	)

	var space: PhysicsDirectSpaceState3D = _current_scene_root.get_world_3d().direct_space_state

	# Pré-allouer shape et query réutilisés dans la boucle (non hot-path).
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.3  # Approximation capsule player radius (authoring check)

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	# ADR-0008 D-3 + rule collision-layer-api-1-indexed : build_mask obligatoire,
	# jamais de bitmask littéral dans src/**/*.gd.
	query.collision_mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])

	for node: Node in anchor_nodes:
		var anchor: Marker3D = node as Marker3D
		var pos: Vector3 = anchor.global_position
		query.transform = Transform3D(Basis(), pos)
		var collisions: Array[Dictionary] = space.intersect_shape(query, 1)
		if not collisions.is_empty():
			results.append({
				"anchor_name": anchor.name,
				"position": pos,
				"reason": "inside_static_body",
			})

	return results


## Retourne le matériau de surface d'un StaticBody3D pour le routing Audio System.
##
## Lit la propriété `surface_material` du body (présente si StaticSurface.gd est attaché).
## Valide la valeur contre les valeurs reconnues : "concrete", "metal", "glass", "none".
##
## Comportement :
##   - Propriété absente (body non-tagué) → retourne "concrete" silencieusement.
##   - Propriété présente avec valeur invalide → push_warning + retourne "concrete".
##   - Propriété présente avec valeur valide → retourne la valeur telle quelle.
##
## L'Audio System (épic futur) appelle cette API au footstep event pour router vers
## le bon bus SFX (béton → gravel, métal → metal_clang, verre → glass_clink).
##
## [param body] : StaticBody3D sur lequel lire le tag de matériau.
## [return] : StringName du matériau (&"concrete" | &"metal" | &"glass" | &"none").
## Source : AC-LVL-44, TR-lvl-042, story-022.
func get_surface_material_for(body: StaticBody3D) -> StringName:
	const VALID_MATS: Array[StringName] = [&"concrete", &"metal", &"glass", &"none"]
	var prop: Variant = body.get("surface_material")
	if prop == null:
		# Body non-tagué (pas de StaticSurface.gd attaché) — default béton, silencieux.
		return &"concrete"
	var mat: StringName = StringName(str(prop))
	if not VALID_MATS.has(mat):
		push_warning(
			"get_surface_material_for: invalid surface_material '%s' on %s — defaulting to 'concrete'" % [
				mat, body.get_path()
			]
		)
		return &"concrete"
	return mat


## TEST-ONLY : injecte un Node3D racine synthétique comme _current_scene_root pour les tests
## unitaires des spatial lookups API (story-009, AC-LVL-30 / AC-LVL-30b / AC-LVL-30c).
## No-op en release (OS.has_feature("debug") false).
## Pattern cohérent avec _simulate_load_elapsed_ms (story-004 Option A).
## Source : story-009 implementation notes — Option 1 test-only setter.
func _set_current_scene_root_for_test(root: Node3D) -> void:
	if not OS.has_feature("debug"):
		return
	_current_scene_root = root


## Retourne les anchors d'onboarding Combat (FirstEnemySightline + SafeZoneCenter)
## de la scène d'étage active (étage 1 uniquement).
## Source : AC-LVL-54(c), story-019, ADR-0005 D-10 (API publique read-only consommée par peers).
##
## Convention authoring : sous-arbre OnboardingAnchors enfant direct du Level root.
##   OnboardingAnchors/FirstEnemySightline (Marker3D)
##   OnboardingAnchors/SafeZoneCenter      (Marker3D)
##
## Clés du Dictionary retourné :
##   "first_enemy_sightline" : Marker3D — point de ligne-de-vue premier ennemi
##   "safe_zone_center"      : Marker3D — centre de la zone safe défensive
##
## AC-LVL-54(c) : pour étage ≠ 1 (OnboardingAnchors absent), retourne {} — non-fatal.
## Sous-arbre présent mais incomplet (un Marker3D manquant) → push_warning + retourne {}.
## Guard scene_root null → push_warning + retourne {} (état UNLOADED ou LOADING).
func get_onboarding_anchors() -> Dictionary:
	if _current_scene_root == null:
		push_warning("get_onboarding_anchors called before level_active — returning empty dict")
		return {}
	var anchors: Node = _current_scene_root.find_child("OnboardingAnchors", false, false)
	if anchors == null:
		return {}  # Étage != 1 ou tutorial absent — non-fatal (AC-LVL-54(c))
	var sightline: Marker3D = anchors.find_child("FirstEnemySightline", false, false) as Marker3D
	var safe: Marker3D = anchors.find_child("SafeZoneCenter", false, false) as Marker3D
	if sightline == null or safe == null:
		push_warning("OnboardingAnchors incomplete")
		return {}
	return {
		"first_enemy_sightline": sightline,
		"safe_zone_center": safe,
	}
