## LevelTriggerHandler — Connexion et dispatch des Area3D triggers d'un étage.
##
## Possédé et instancié par LevelSystemScript (composition). Reçoit une
## référence injectée vers le Node LevelSystem pour accéder à l'état et
## émettre les signaux via l'API publique.
## PAS un autoload — PAS de class_name (référencé via preload binding local
## dans level_system.gd pour bypass class cache CI gdUnit4-action).
##
## Responsabilités :
##   - Connexion EtageExitTrigger, RoomTrigger_*, WorldBoundsVolume
##   - Handlers body_entered / body_exited correspondants
##   - Extraction room_index depuis nom ou @export property
##
## ADR-0005 D-4 (emit depuis physics context), D-8 (mutation avant emit),
## D-10 (outbound-only — ne mute que l'état exposé via _level).
## Source : TR-lvl-022/023/024/031/032, AC-LVL-21..25.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const LevelTriggerHandler := preload(...)`
# dans level_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à LevelSystemScript (Node) — pour accéder à l'état,
## émettre les signaux, et appeler unload_current().
## Injectée dans LevelSystemScript._ready() après instanciation.
var _level: Node = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Connecte les triggers EtageExit, Rooms et WorldBounds depuis la scène root.
## Appelé depuis LevelSystemScript au moment de la transition LOADING→ACTIVE.
## Source : TR-lvl-022/023/031, ADR-0005 D-4.
func connect_triggers(root: Node3D) -> void:
	_connect_etage_exit_trigger(root)
	_connect_room_triggers(root)
	_connect_world_bounds_volume(root)


## Connecte uniquement les RoomTriggers (utilisé par prepare_for_perf_runner).
## Source : TD-009, story-017.
func connect_room_triggers_only(root: Node3D) -> void:
	_connect_room_triggers(root)


# ---------------------------------------------------------------------------
# Signal handlers (body_entered / body_exited)
# ---------------------------------------------------------------------------

## Handler Area3D.body_entered de l'EtageExitTrigger.
## Émet etage_completed puis enchaîne unload_current() (T-3 ADR-0005).
## Source : TR-lvl-023, AC-LVL-24, ADR-0005 D-4 + T-3 + D-8.
##
## Idempotence garantie par guard `_level.get_state() != ACTIVE` :
##   - re-entry (state = UNLOADING) → no-op (EC-6 no back-out)
##   - body sans groupe "player" → no-op
func _on_etage_exit_body_entered(body: Node3D) -> void:
	if _level.get_state() != _level.LevelState.ACTIVE:
		return
	if not body.is_in_group("player"):
		return
	_level._assert_main_thread()
	_level.etage_completed.emit(_level.get_current_etage_id())
	_level.unload_current()


## Handler Area3D.body_entered de chaque RoomTrigger_NN.
## Source : TR-lvl-022, TR-lvl-031, TR-lvl-032, AC-LVL-21..23 + AC-LVL-38.
##
## Guards : state != ACTIVE → no-op ; body sans groupe "player" → no-op ;
## position NaN/Inf → push_warning + no-op (EC-9, TR-lvl-032).
func _on_room_trigger_body_entered(body: Node3D, room_index: int) -> void:
	if _level.get_state() != _level.LevelState.ACTIVE:
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
	_level._assert_main_thread()
	_level._set_current_room_index(room_index)
	_level.room_entered.emit(room_index, _level.get_total_rooms())


## Handler Area3D.body_exited de WorldBoundsVolume (path 1 primary).
## Source : TR-lvl-017, TR-lvl-024, AC-LVL-25 path 1, ADR-0005 D-4 + D-8.
##
## Guards : state != ACTIVE → no-op ; body sans groupe "player" → no-op ;
## flag out_of_world_emitted → no-op (idempotence) ; NaN/Inf → no-op.
func _on_world_bounds_body_exited(body: Node3D) -> void:
	if _level.get_state() != _level.LevelState.ACTIVE:
		return
	if not body.is_in_group("player"):
		return
	if _level._get_out_of_world_emitted():
		return
	var pos: Vector3 = body.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		push_warning("player_out_of_world ignored: body position contains NaN")
		return
	if is_inf(pos.x) or is_inf(pos.y) or is_inf(pos.z):
		push_warning("player_out_of_world ignored: body position contains Inf")
		return
	_level._set_out_of_world_emitted(true)
	_level._assert_main_thread()
	_level.player_out_of_world.emit(_level._get_last_valid_position())


# ---------------------------------------------------------------------------
# Private — connexion triggers
# ---------------------------------------------------------------------------

## Connecte body_entered de l'EtageExitTrigger.
## 0 → push_warning ; 1 → connexion ; >1 → push_error + assert.
## Source : TR-lvl-023, AC-LVL-24.
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


## Connecte body_entered de chaque RoomTrigger_NN Area3D. Cache _total_rooms.
## Source : TR-lvl-022, TR-lvl-031.
##
## Convention nommage : RoomTrigger_NN avec @export var room_index: int (0-indexed,
## fallback parse name si absent). Tree order = DFS preorder Godot.
func _connect_room_triggers(root: Node3D) -> void:
	var triggers: Array[Node] = root.find_children("RoomTrigger_*", "Area3D", true, false)
	_level._set_total_rooms(triggers.size())
	if triggers.size() == 0:
		push_warning("no RoomTrigger_* Area3D found in level scene — room_entered will never fire")
		return
	for node: Node in triggers:
		var area: Area3D = node as Area3D
		var idx: int = _extract_room_index(area)
		area.body_entered.connect(_on_room_trigger_body_entered.bind(idx))


## Connecte body_exited de WorldBoundsVolume.
## 0 → push_warning ; 1 → connexion ; >1 → push_error + assert.
## Source : TR-lvl-017, AC-LVL-25 (path 1), ADR-0011 D-9 BoxShape3D obligatoire.
func _connect_world_bounds_volume(root: Node3D) -> void:
	var areas: Array[Node] = root.find_children("WorldBoundsVolume", "Area3D", true, false)
	if areas.size() == 0:
		push_warning("WorldBoundsVolume Area3D not found — only Y<-2 safety net active")
		_level._set_world_bounds_volume(null)
		return
	if areas.size() > 1:
		var msg: String = "multiple WorldBoundsVolume Area3D found — hierarchy violation"
		push_error(msg)
		assert(false, msg)
		return
	var wb: Area3D = areas[0] as Area3D
	_level._set_world_bounds_volume(wb)
	wb.body_exited.connect(_on_world_bounds_body_exited)


## Extrait 0-indexed room_index depuis Area3D : préfère @export property, fallback parse name.
## Convention : RoomTrigger_03 → parts[1] = "03" → int("03") - 1 = 2 (0-indexed payload).
## Erreur de nommage → push_error + retourne -1.
func _extract_room_index(area: Area3D) -> int:
	if "room_index" in area:
		return area.get("room_index") as int
	var parts: PackedStringArray = area.name.split("_")
	if parts.size() < 2 or not parts[1].is_valid_int():
		push_error("RoomTrigger naming violation: %s (expected RoomTrigger_NN)" % area.name)
		return -1
	return int(parts[1]) - 1
