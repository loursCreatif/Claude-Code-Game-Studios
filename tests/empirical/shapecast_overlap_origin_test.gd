extends SceneTree

# Empirical investigation — story-010 Gap 2 / AC-CMB-47-Prelim
#
# Question : Godot 4.6 + Jolt — un ShapeCast3D détecte-t-il un body en overlap
# à son origine (avant tout déplacement) ou faut-il un pass séparé via
# PhysicsDirectSpaceState3D.intersect_shape() ?
#
# Result drives ADR-0006 D-? (Combat tick 0 mitigation : Variante A vs B).
#
# Run via :
#   godot --headless --script tests/empirical/shapecast_overlap_origin_test.gd
#
# Output sur stdout — lit verdict via grep "[verdict]".

const FRAMES_TO_WAIT: int = 3
const SHAPE_CAPSULE_RADIUS: float = 0.45
const SHAPE_CAPSULE_HEIGHT: float = 1.8
const SHAPE_SPHERE_RADIUS: float = 0.35
const ENEMY_OVERLAP_OFFSET_Z: float = -0.3
const TARGET_DISTANCE_Z: float = -0.5
const ENEMY_LAYER_BIT: int = 0b00010

var _frame_count: int = 0
var _shape_cast: ShapeCast3D = null
var _root_3d: Node3D = null


func _initialize() -> void:
	_root_3d = Node3D.new()
	root.add_child(_root_3d)

	_shape_cast = ShapeCast3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = SHAPE_CAPSULE_RADIUS
	capsule.height = SHAPE_CAPSULE_HEIGHT
	_shape_cast.shape = capsule
	_shape_cast.target_position = Vector3(0.0, 0.0, TARGET_DISTANCE_Z)
	_shape_cast.collision_mask = ENEMY_LAYER_BIT
	_shape_cast.enabled = true
	_root_3d.add_child(_shape_cast)

	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.collision_layer = ENEMY_LAYER_BIT
	enemy.collision_mask = 0
	enemy.position = Vector3(0.0, 0.0, ENEMY_OVERLAP_OFFSET_Z)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SHAPE_SPHERE_RADIUS
	collision.shape = sphere
	enemy.add_child(collision)
	_root_3d.add_child(enemy)

	var version_info: Dictionary = Engine.get_version_info()
	var godot_version: String = String(version_info.get("string", "unknown"))
	var physics_engine: String = String(ProjectSettings.get_setting(
		"physics/3d/physics_engine", "DEFAULT"
	))

	print("[setup] ShapeCast3D + MockEnemy overlap origin scene built")
	print("[meta] Godot version: %s" % godot_version)
	print("[meta] Physics 3D engine: %s" % physics_engine)
	print("[meta] ShapeCast capsule radius=%s height=%s target_z=%s mask=%d" % [
		str(SHAPE_CAPSULE_RADIUS), str(SHAPE_CAPSULE_HEIGHT),
		str(TARGET_DISTANCE_Z), ENEMY_LAYER_BIT
	])
	print("[meta] Enemy sphere radius=%s position_z=%s layer=%d" % [
		str(SHAPE_SPHERE_RADIUS), str(ENEMY_OVERLAP_OFFSET_Z), ENEMY_LAYER_BIT
	])


func _physics_process(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count < FRAMES_TO_WAIT:
		return false

	_shape_cast.force_shapecast_update()
	var hits: int = _shape_cast.get_collision_count()

	print("[result] ShapeCast3D.get_collision_count() = %d (after %d physics frames)" % [
		hits, _frame_count
	])

	if hits == 0:
		print("[verdict] Variante A — intersect_shape requis (overlap initial NON détecté par ShapeCast3D + Jolt)")
	else:
		var collider: Object = _shape_cast.get_collider(0)
		var collider_class: String = "null"
		if collider != null:
			collider_class = collider.get_class()
		print("[verdict] Variante B — force_shapecast_update suffit (overlap détecté, count=%d, collider[0].class=%s)" % [
			hits, collider_class
		])

	# Defense-in-depth : run intersect_shape via PhysicsDirectSpaceState3D pour comparer
	var space_state: PhysicsDirectSpaceState3D = _root_3d.get_world_3d().direct_space_state
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _shape_cast.shape
	query.transform = _shape_cast.global_transform
	query.collision_mask = _shape_cast.collision_mask
	var intersect_results: Array[Dictionary] = space_state.intersect_shape(query, 8)
	print("[cross-check] intersect_shape() returned %d hit(s)" % intersect_results.size())

	quit(0)
	return true
