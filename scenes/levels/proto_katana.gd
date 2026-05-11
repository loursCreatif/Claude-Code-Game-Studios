# PROTOTYPE - NOT FOR PRODUCTION
# Question: Hitbox katana en mouvement rapide sans tunneling ?
# Date: 2026-04-21

extends Node3D

const SWING_DURATION: float = 0.18
const SWING_RANGE: float = 2.6
const SWING_RADIUS: float = 0.9

@onready var shape_cast: ShapeCast3D = $ShapeCast3D
@onready var mesh: MeshInstance3D = $Mesh

var is_swinging: bool = false
var swing_timer: float = 0.0
var hit_this_swing: Array[Node] = []

signal enemy_killed(enemy: Node)

func _ready() -> void:
	shape_cast.enabled = false
	if mesh:
		mesh.rotation.z = 0.0

func swing() -> void:
	if is_swinging:
		return
	is_swinging = true
	swing_timer = SWING_DURATION
	hit_this_swing.clear()
	shape_cast.enabled = true

func _physics_process(delta: float) -> void:
	if not is_swinging:
		if mesh:
			mesh.rotation.z = lerp(mesh.rotation.z, 0.0, 12.0 * delta)
		return

	swing_timer -= delta
	var t: float = 1.0 - (swing_timer / SWING_DURATION)
	if mesh:
		mesh.rotation.z = lerp(-0.6, 0.6, t)

	shape_cast.force_shapecast_update()
	for i in shape_cast.get_collision_count():
		var col: Object = shape_cast.get_collider(i)
		if col == null:
			continue
		if col in hit_this_swing:
			continue
		hit_this_swing.append(col)
		if col.has_method("kill"):
			col.kill()
			enemy_killed.emit(col)
			_trigger_kill_flash()
		elif col.has_method("die"):
			# Production Grunt utilise die() (Enemy GDD r2 Rule 14).
			col.die()
			enemy_killed.emit(col)
			_trigger_kill_flash()

	if swing_timer <= 0.0:
		is_swinging = false
		shape_cast.enabled = false


func _trigger_kill_flash() -> void:
	# Flash blanc 0.1s pour feedback kill MVP.
	var player: Node = get_parent().get_parent().get_parent()  # Player root
	var flash: ColorRect = player.get_node_or_null("HUDProto/KillFlash") as ColorRect
	if flash == null:
		return
	flash.color = Color(1, 1, 1, 0.5)
	var tween: Tween = create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.12)
