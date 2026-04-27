# PROTOTYPE - NOT FOR PRODUCTION
# Question: End-to-end feel of movement + katana in a tiny test arena
# Date: 2026-04-21
# Builds the test arena procedurally so the .tscn stays simple.

extends Node3D

const ENEMY_SCENE_PATH: String = "res://enemy.tscn"

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var katana: Node3D = $Player/Camera3D/Katana
@onready var enemies_root: Node3D = $Enemies

func _ready() -> void:
	_build_arena()
	_spawn_enemies()

	if hud.has_method("set_player"):
		hud.set_player(player)
	player.attacked.connect(func() -> void: hud.register_attack())
	player.died.connect(func() -> void: hud.register_death())
	katana.enemy_killed.connect(func(_e: Node) -> void: hud.register_kill())

func _build_arena() -> void:
	var level: Node3D = $Level

	# Floor 40x40
	_add_box(level, Vector3(0, -0.5, 0), Vector3(40, 1, 40), Color(0.15, 0.15, 0.18))

	# Parallel walls for wall-running — narrow corridor pour déclencher wall-run facilement
	_add_box(level, Vector3(-1.8, 2.0, -10), Vector3(0.5, 4, 16), Color(0.25, 0.25, 0.28))
	_add_box(level, Vector3( 1.8, 2.0, -10), Vector3(0.5, 4, 16), Color(0.25, 0.25, 0.28))

	# Back wall with high ledge to force double-jump
	_add_box(level, Vector3(0, 1.5, -20), Vector3(10, 3, 0.5), Color(0.3, 0.3, 0.3))
	_add_box(level, Vector3(0, 4.0, -22), Vector3(10, 0.5, 4), Color(0.35, 0.35, 0.35))

	# Dash gap — platform 7m away with pit between
	_add_box(level, Vector3(0, 0.0, 12), Vector3(6, 0.5, 4), Color(0.2, 0.4, 0.5))
	_add_box(level, Vector3(0, -4, 8), Vector3(6, 0.5, 6), Color(0.5, 0.15, 0.15))  # pit bottom (kills)

	# Ceiling-less — skybox handles the rest
	# Border walls to prevent falling off
	_add_box(level, Vector3(20, 3, 0), Vector3(0.5, 8, 40), Color(0.22, 0.22, 0.25))
	_add_box(level, Vector3(-20, 3, 0), Vector3(0.5, 8, 40), Color(0.22, 0.22, 0.25))

func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = pos
	parent.add_child(body)

	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	return body

func _spawn_enemies() -> void:
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	if enemy_scene == null:
		push_warning("Enemy scene missing")
		return
	var positions: Array[Vector3] = [
		Vector3(0, 1, -5),
		Vector3(1.5, 1, -12),
		Vector3(-1.5, 1, -16),
		Vector3(0, 1.2, 12),  # on dash platform
	]
	for p in positions:
		var inst: Node = enemy_scene.instantiate()
		enemies_root.add_child(inst)
		inst.position = p
