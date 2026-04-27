# PROTOTYPE - NOT FOR PRODUCTION
# Question: Target one-shot + kill feedback timing
# Date: 2026-04-21

extends StaticBody3D

@onready var mesh: MeshInstance3D = $Mesh
@onready var laser_area: Area3D = $LaserArea

var is_alive: bool = true

signal killed

func _ready() -> void:
	laser_area.body_entered.connect(_on_laser_hit)

func kill() -> void:
	if not is_alive:
		return
	is_alive = false
	if mesh:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.1, 0.1)
		mat.emission_energy_multiplier = 2.0
		mesh.material_override = mat
	killed.emit()
	var tween: Tween = create_tween()
	tween.tween_property(mesh, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
	tween.tween_callback(queue_free)

func _on_laser_hit(body: Node) -> void:
	if not is_alive:
		return
	if body.has_method("die"):
		body.die()
