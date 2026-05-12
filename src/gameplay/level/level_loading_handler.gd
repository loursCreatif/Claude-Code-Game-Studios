## LevelLoadingHandler — Poll ResourceLoader + commit LOADING→ACTIVE.
##
## Possédé et instancié par LevelSystemScript (composition). Reçoit une
## référence injectée vers le Node LevelSystem pour lire/écrire l'état
## et émettre les signaux level_load_failed, level_load_slow, level_active.
## PAS un autoload — PAS de class_name (référencé via preload binding local
## dans level_system.gd pour bypass class cache CI gdUnit4-action).
##
## Responsabilités :
##   - Poll ResourceLoader.load_threaded_get_status() à chaque tick _process
##   - Détection THREAD_LOAD_FAILED + THREAD_LOAD_LOADED
##   - Advisory slow-load (TR-lvl-027) : flag one-shot si > seuil
##   - Commit LOADING→ACTIVE dans _physics_process : instantiation + connexion triggers
##   - Dispatch level_active.emit après spawn ennemis
##
## ADR-0005 D-4 (emit exclusivement depuis _physics_process),
## D-8 (mutation état AVANT emit), D-10 (outbound-only via _level).
## Source : TR-lvl-002, TR-lvl-026, TR-lvl-027, TR-lvl-029,
##          AC-LVL-2/3/4/5/6/7/8, story-TD-008.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const LevelLoadingHandler := preload(...)`
# dans level_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.

## Reason string statique pour THREAD_LOAD_FAILED — évite toute alloc String en hot path.
## Source : .claude/rules/no-alloc-hot-paths.md.
const REASON_THREAD_LOAD_FAILED: String = "ResourceLoader returned THREAD_LOAD_FAILED"


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à LevelSystemScript (Node) — pour accéder à l'état
## et émettre les signaux.
## Injectée dans LevelSystemScript._ready() après instanciation.
var _level: Node = null


# ---------------------------------------------------------------------------
# Public API — appelé depuis LevelSystemScript
# ---------------------------------------------------------------------------

## Sonde ResourceLoader et met à jour les flags pending sur le _level.
## Appelé depuis LevelSystemScript._process(). Lit _state, _loading_path,
## _load_started_msec, load_slow_threshold_ms depuis _level.
## Source : TR-lvl-026/027, ADR-0005 D-4.
func poll_loading(load_progress: Array[float]) -> void:
	var status: int = ResourceLoader.load_threaded_get_status(
		_level._loading_path, load_progress
	)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_level._transition_to_active_pending = true  # Commit dans _physics_process.
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		push_error("ResourceLoader threaded load failed for %s" % _level._loading_path)
		_level._pending_load_failed_etage_id = _level._current_etage_id
		_level._pending_load_failed_reason = REASON_THREAD_LOAD_FAILED
		# Mutation d'état AVANT emit (ADR-0005 D-8).
		_level._state = _level.LevelState.UNLOADED
		_level._current_etage_id = -1
		_level._loading_path = ""
		_level._transition_to_active_pending = false
		_level._load_slow_emitted = true
		_level._pending_load_slow_emit = false
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# Advisory slow-load (TR-lvl-027) : flag one-shot si > seuil, ≤ 0 désactive.
		if (
			not _level._load_slow_emitted
			and _level.load_slow_threshold_ms > 0
			and (Time.get_ticks_msec() - _level._load_started_msec) > _level.load_slow_threshold_ms
		):
			_level._load_slow_emitted = true
			_level._pending_load_slow_emit = true


## Commit la transition LOADING→ACTIVE dans le contexte _physics_process.
## Appelé depuis LevelSystemScript._physics_process() quand
## _transition_to_active_pending == true.
## Source : ADR-0005 D-4, ADR-0011 REQ-8, TR-lvl-002.
func commit_active(scene_tree: SceneTree) -> void:
	var packed: PackedScene = ResourceLoader.load_threaded_get(
		_level._loading_path
	) as PackedScene
	if packed == null:
		push_error("load_threaded_get returned null for %s" % _level._loading_path)
		_level._state = _level.LevelState.UNLOADED
		_level._loading_path = ""
		return

	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	if root_3d == null:
		push_error("level scene root must be Node3D, got %s" % instance.get_class())
		instance.queue_free()
		_level._state = _level.LevelState.UNLOADED
		_level._loading_path = ""
		return

	# ADR-0011 REQ-8 : la scène d'étage est attachée à get_tree().root (ownership naturel).
	scene_tree.root.add_child(root_3d)
	_level._current_scene_root = root_3d
	_level._player_start = _level._player_tracker.discover_player_start(root_3d)
	_level._triggers.connect_triggers(root_3d)
	_level._state = _level.LevelState.ACTIVE
	_level._loading_path = ""

	# Enemy GDD r2 Rule 9 / OQ-ENM-2 : LevelSystem est la factory directe des grunts.
	# Spawn AVANT level_active.emit pour que les consumers voient une scène populée.
	EnemySpawner.spawn_for_scene(_level._current_scene_root)

	_level.level_active.emit(_level._current_etage_id, _level._player_start)
