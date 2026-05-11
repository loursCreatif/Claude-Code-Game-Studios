## LevelPlayerTracker — Suivi position player + safety net out-of-world.
##
## Possédé et instancié par LevelSystemScript (composition). Reçoit une
## référence injectée vers le Node LevelSystem pour émettre le signal
## `player_out_of_world` et accéder à `_assert_main_thread()`.
## PAS un autoload — PAS de class_name (référencé via preload binding local
## dans level_system.gd pour bypass class cache CI gdUnit4-action).
##
## Responsabilités :
##   - Découverte du Marker3D "PlayerStart" dans la scène d'étage
##   - Cache node player via groupe "player" (zero-alloc hit)
##   - Suivi `_last_valid_position` (pos.y >= -2.0)
##   - Safety net path 2 : emit player_out_of_world si pos.y < -2.0
##   - Reset flag one-shot après respawn
##
## ADR-0005 D-4 (emit depuis _physics_process), D-8 (mutation avant emit),
## D-9 (zero-alloc hot path), D-10 (outbound-only — ne mute que l'état interne).
## Source : TR-lvl-018, TR-lvl-024, AC-LVL-25 path 2, story-TD-008.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const LevelPlayerTracker := preload(...)`
# dans level_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à LevelSystemScript (Node) — pour émettre les signaux
## et appeler _assert_main_thread().
## Injectée dans LevelSystemScript._ready() après instanciation.
var _level: Node = null


# ---------------------------------------------------------------------------
# Private state — player tracking
# ---------------------------------------------------------------------------

## Seuil Y strict (exclusive) : valeur ≤ threshold → out-of-world.
## Aligné _Y_OUT_OF_WORLD_THRESHOLD dans level_system.gd (TR-lvl-018 EC-1).
const _Y_THRESHOLD: float = -2.0

## Dernière position player valide (y >= -2.0). Payload de player_out_of_world.
## Source : TR-lvl-024, ADR-0005 D-8.
var _last_valid_position: Vector3 = Vector3.ZERO

## Flag one-shot : emit player_out_of_world une seule fois par vie (TR-lvl-024).
## Remis à false via reset_out_of_world_flag() après respawn.
var _out_of_world_emitted_this_life: bool = false

## Cache node player groupe "player". Re-lookup si null ou instance invalide.
## Cache hit = zero-alloc hot path (ADR-0005 D-9).
var _player_node: Node3D = null

## Référence WorldBoundsVolume active — stocké pour usage potentiel futur.
## Injecté par LevelTriggerHandler via set_world_bounds_volume().
var _world_bounds_volume: Area3D = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Découvre le Marker3D "PlayerStart" dans root. Exactement 1 requis.
## Debug : push_error + assert(false). Release : push_error + Vector3.ZERO.
## Source : ADR-0011 D-5, TR-lvl-002.
func discover_player_start(root: Node3D) -> Vector3:
	var markers: Array[Node] = root.find_children("PlayerStart", "Marker3D", true, false)
	if markers.size() != 1:
		push_error("missing PlayerStart marker")
		assert(false, "missing PlayerStart marker")
		return Vector3.ZERO
	return (markers[0] as Marker3D).global_position


## Appelé depuis LevelSystemScript._physics_process() quand état == ACTIVE.
## Met à jour _last_valid_position si pos.y >= -2.0.
## Émet player_out_of_world (path 2 safety net) si pos.y < -2.0 et flag not set.
## Zero-alloc hot path (ADR-0005 D-9, .claude/rules/no-alloc-hot-paths.md).
## Source : TR-lvl-018, TR-lvl-024, ADR-0005 D-4 + D-8.
func tick(scene_tree: SceneTree) -> void:
	var player: Node3D = _resolve_player_node(scene_tree)
	if player == null:
		return
	var pos: Vector3 = player.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		return
	if is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z):
		return
	if pos.y < _Y_THRESHOLD and not _out_of_world_emitted_this_life:
		_out_of_world_emitted_this_life = true  # ADR-0005 D-8 mutation avant emit
		_level._assert_main_thread()
		_level.player_out_of_world.emit(_last_valid_position)
		return
	if pos.y >= _Y_THRESHOLD:
		_last_valid_position = pos


## Reset flag one-shot out_of_world après respawn. Source : TR-lvl-024.
func reset_out_of_world_flag() -> void:
	_out_of_world_emitted_this_life = false


## Reset complet du state tracker (appelé par LevelSystemScript._reset_runtime_state).
func reset() -> void:
	_last_valid_position = Vector3.ZERO
	_out_of_world_emitted_this_life = false
	_player_node = null
	_world_bounds_volume = null


## Accesseur last_valid_position — utilisé par LevelTriggerHandler._on_world_bounds_body_exited.
func get_last_valid_position() -> Vector3:
	return _last_valid_position


## Accesseur flag out_of_world — utilisé par LevelTriggerHandler._on_world_bounds_body_exited.
func get_out_of_world_emitted() -> bool:
	return _out_of_world_emitted_this_life


## Setter flag out_of_world — utilisé par LevelTriggerHandler._on_world_bounds_body_exited.
func set_out_of_world_emitted(value: bool) -> void:
	_out_of_world_emitted_this_life = value


## Injecte le WorldBoundsVolume depuis LevelTriggerHandler._connect_world_bounds_volume.
func set_world_bounds_volume(area: Area3D) -> void:
	_world_bounds_volume = area


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Résout et cache le node player via groupe "player".
## Cache hit = zero-alloc. Cache miss = 1 Array[Node] allouée (bornée à quelques ticks).
## Source : ADR-0005 D-9.
func _resolve_player_node(scene_tree: SceneTree) -> Node3D:
	if _player_node != null and is_instance_valid(_player_node):
		return _player_node
	var players: Array[Node] = scene_tree.get_nodes_in_group("player")
	if players.is_empty():
		return null
	_player_node = players[0] as Node3D
	return _player_node
