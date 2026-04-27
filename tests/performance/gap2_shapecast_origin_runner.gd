# Runner empirique headless — Gap 2 ADR-0006
# Test : ShapeCast3D overlap à l'origine sous Godot 4.6 + Jolt.
# Question : quand target_position = Vector3.ZERO, Jolt retourne-t-il les
# colliders qui chevauchent déjà la capsule, ou is_colliding() == false ?
# Détermine Variante A (ShapeCast retourne overlaps à origine) vs
# Variante B (ne retourne pas — _tick0_intersect_shape_overlap load-bearing).
#
# Lancement : godot --headless --path /path/to/project tests/performance/gap2_shapecast_origin_runner.tscn
# Exit code : 0 (toujours — test one-shot, pas de gate CI)
extends Node3D

func _ready() -> void:
	# -- Setup : StaticBody3D avec SphereShape3D radius 0.35, layer 2 --
	var static_body := StaticBody3D.new()
	static_body.name = "TargetBody"
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	col_shape.shape = sphere
	static_body.add_child(col_shape)
	static_body.global_position = Vector3(0.0, 0.0, 0.0)
	add_child(static_body)

	# -- Setup : ShapeCast3D avec CapsuleShape3D radius 0.4 height 2.0 --
	var shape_cast := ShapeCast3D.new()
	shape_cast.name = "TestShapeCast"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.0
	shape_cast.shape = capsule
	shape_cast.collision_mask = 2
	shape_cast.exclude_parent = false
	shape_cast.global_position = Vector3(0.0, 0.0, 0.0)
	add_child(shape_cast)

	# -- Test 1 : target_position = Vector3.ZERO --
	shape_cast.target_position = Vector3.ZERO
	shape_cast.force_shapecast_update()
	var origin_colliding: bool = shape_cast.is_colliding()
	var origin_count: int = shape_cast.get_collision_count()
	print("[GAP2-DEBUG] origin test: is_colliding=%s count=%d" % [origin_colliding, origin_count])
	if origin_count > 0:
		for i in origin_count:
			var c = shape_cast.get_collider(i)
			print("[GAP2-DEBUG]   collider[%d] = %s" % [i, c.name if c != null else "null"])

	# -- Test 2 : target_position minimal non-nul (delta 0.01 m) --
	shape_cast.target_position = Vector3(0.0, 0.0, -0.01)
	shape_cast.force_shapecast_update()
	var delta_colliding: bool = shape_cast.is_colliding()
	var delta_count: int = shape_cast.get_collision_count()
	print("[GAP2-DEBUG] delta test: is_colliding=%s count=%d" % [delta_colliding, delta_count])

	# -- Déduction Variante A / B --
	var variant: String = "A" if origin_colliding else "B"

	# -- Log résultat parsable --
	print("[GAP2-RESULT] variant=%s origin_colliding=%s origin_count=%d delta_colliding=%s delta_count=%d" % [
		variant,
		str(origin_colliding).to_lower(),
		origin_count,
		str(delta_colliding).to_lower(),
		delta_count
	])

	get_tree().quit(0)
