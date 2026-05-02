# Runner empirique headless — Gap 8 ADR-0006
# Test : comportement ShapeCast3D.margin sous Godot 4.6 + Jolt.
# Question : la marge etend-elle la forme pour la detection de collision,
# ou Jolt l'ignore-t-il silencieusement ?
#
# Geometrie calibree :
#   StaticBody3D BoxShape3D 1x1x1 centre a z=-1.5 → face avant a z=-1.0.
#   Capsule radius=0.4, a z=0 : surface avant initiale = z=-0.4.
#   Gap entre surface avant capsule et face box = 1.0 - 0.4 = 0.6 m.
#   target_position=(0,0,-0.55) → capsule front final = -0.4 - 0.55 = -0.95 m.
#   Gap residuel = 1.0 - 0.95 = 0.05 m → pas de contact sans marge.
#   Avec margin=0.1 : front effectif = -0.95 - 0.1 = -1.05 m → penetre box → contact attendu.
#   Avec margin=0.2 : -1.15 m → contact plus franc.
#   Si margin=0.0 retourne true : geometrie test invalide (revoir calcul).
#
# Lancement : godot --headless --path /path/to/project tests/performance/gap8_shapecast_margin_runner.tscn
# Exit code : 0 (toujours — test one-shot, pas de gate CI)
extends Node3D

func _ready() -> void:
	# -- Setup : StaticBody3D BoxShape3D 1x1x1 centre a z=-1.5 --
	var static_body := StaticBody3D.new()
	static_body.name = "TargetBox"
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	col_shape.shape = box
	static_body.add_child(col_shape)
	static_body.global_position = Vector3(0.0, 0.0, -1.5)
	add_child(static_body)

	# -- Setup : ShapeCast3D capsule radius=0.4 a l'origine --
	var shape_cast := ShapeCast3D.new()
	shape_cast.name = "TestShapeCast"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 2.0
	shape_cast.shape = capsule
	shape_cast.collision_mask = 2
	shape_cast.exclude_parent = false
	shape_cast.global_position = Vector3(0.0, 0.0, 0.0)
	# target=-0.55 : capsule front final = -0.4 - 0.55 = -0.95 m, gap box = 0.05 m
	shape_cast.target_position = Vector3(0.0, 0.0, -0.55)
	add_child(shape_cast)

	# -- Test margin=0.0 (baseline, pas de contact attendu) --
	shape_cast.margin = 0.0
	shape_cast.force_shapecast_update()
	var col_m0: bool = shape_cast.is_colliding()
	print("[GAP8-DEBUG] margin=0.0 colliding=%s (expected=false)" % str(col_m0).to_lower())

	# -- Test margin=0.1 (front effectif = -1.05, penetre box de 0.05m) --
	shape_cast.margin = 0.1
	shape_cast.force_shapecast_update()
	var col_m1: bool = shape_cast.is_colliding()
	print("[GAP8-DEBUG] margin=0.1 colliding=%s (expected=true if Jolt respects margin)" % str(col_m1).to_lower())

	# -- Test margin=0.2 (front effectif = -1.15, penetre box de 0.15m) --
	shape_cast.margin = 0.2
	shape_cast.force_shapecast_update()
	var col_m2: bool = shape_cast.is_colliding()
	print("[GAP8-DEBUG] margin=0.2 colliding=%s (expected=true if Jolt respects margin)" % str(col_m2).to_lower())

	# -- Deduction --
	var baseline_valid: bool = not col_m0
	var jolt_respects_margin: bool = col_m1 or col_m2
	var recommendation: String
	if not baseline_valid:
		recommendation = "GEOMETRY_ERROR_baseline_already_colliding"
	elif jolt_respects_margin:
		recommendation = "margin_respected_use_default"
	else:
		recommendation = "margin_ignored_force_zero"

	# -- Log resultat parsable --
	print("[GAP8-RESULT] margin=0.0 colliding=%s ; margin=0.1 colliding=%s ; margin=0.2 colliding=%s ; baseline_valid=%s ; jolt_respects_margin=%s ; recommendation=%s" % [
		str(col_m0).to_lower(),
		str(col_m1).to_lower(),
		str(col_m2).to_lower(),
		str(baseline_valid).to_lower(),
		str(jolt_respects_margin).to_lower(),
		recommendation
	])

	get_tree().quit(0)
