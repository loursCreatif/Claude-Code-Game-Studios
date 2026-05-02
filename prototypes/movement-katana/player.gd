# PROTOTYPE - NOT FOR PRODUCTION
# Question: Le feel du mouvement katana + parkour est-il atteignable en Godot 4.6 avec GDScript ?
# Date: 2026-04-21

extends CharacterBody3D

const MOVE_SPEED: float = 10.0
const SPRINT_MULT: float = 1.0
const JUMP_VELOCITY: float = 7.0
const AIR_JUMP_VELOCITY: float = 6.5
const GRAVITY: float = 28.0
const WALL_RUN_GRAVITY: float = 4.0
const DASH_SPEED: float = 28.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 0.8
const MOUSE_SENS: float = 0.0022
const WALL_RUN_MIN_SPEED: float = 5.0
const WALL_RUN_STICK_FORCE: float = 6.0
const WALL_JUMP_SIDE: float = 7.0
const WALL_JUMP_UP: float = 6.5
const CAMERA_TILT_WALL_RUN: float = 0.35
const CAMERA_TILT_LERP_SPEED: float = 12.0
const CAMERA_DASH_FOV_KICK: float = 10.0
const BASE_FOV: float = 90.0

@onready var camera: Camera3D = $Camera3D
@onready var katana: Node3D = $Camera3D/Katana
@onready var wall_ray_left: RayCast3D = $WallRayLeft
@onready var wall_ray_right: RayCast3D = $WallRayRight
@onready var respawn_point: Vector3 = global_position

var air_jumps_used: int = 0
var can_dash: bool = true
var is_dashing: bool = false
var dash_dir: Vector3 = Vector3.ZERO
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var is_wall_running: bool = false
var wall_normal: Vector3 = Vector3.ZERO
var wall_side: int = 0  # -1 = left, 0 = none, 1 = right
var shift_was_pressed: bool = false

signal attacked
signal died

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	respawn_point = global_position

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		camera.rotation.x -= event.relative.y * MOUSE_SENS
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("restart"):
		respawn()
	if event.is_action_pressed("attack"):
		if katana and katana.has_method("swing"):
			katana.swing()
			attacked.emit()

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_wall_state()
	_update_camera_effects(delta)

	if is_on_floor():
		air_jumps_used = 0

	if is_dashing:
		_dash_physics(delta)
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Horizontal move — snap au sol (Pillar 1 FLOW), air control limité en l'air
	var speed: float = MOVE_SPEED * SPRINT_MULT
	if is_on_floor():
		if wish_dir.length() > 0.01:
			velocity.x = wish_dir.x * speed
			velocity.z = wish_dir.z * speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		if wish_dir.length() > 0.01:
			var air_accel: float = 40.0 * delta
			velocity.x = move_toward(velocity.x, wish_dir.x * speed, air_accel)
			velocity.z = move_toward(velocity.z, wish_dir.z * speed, air_accel)

	# Jump / air jump / wall jump
	if Input.is_action_just_pressed("jump"):
		if is_wall_running and wall_normal != Vector3.ZERO:
			velocity = wall_normal * WALL_JUMP_SIDE
			velocity.y = WALL_JUMP_UP
			is_wall_running = false
			air_jumps_used = 0
		elif is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif air_jumps_used < 1:
			velocity.y = AIR_JUMP_VELOCITY
			air_jumps_used += 1

	# Dash — poll direct pour contourner bug macOS où Shift seul n'émet pas d'InputEvent
	var shift_now: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	var shift_just_pressed: bool = shift_now and not shift_was_pressed
	shift_was_pressed = shift_now
	if (shift_just_pressed or Input.is_action_just_pressed("dash")) and can_dash:
		_start_dash(wish_dir)

	# Gravity (reduced during wall-run)
	if not is_on_floor():
		if is_wall_running and velocity.y < 0.0:
			velocity.y -= WALL_RUN_GRAVITY * delta
			velocity.y = max(velocity.y, -3.0)
		else:
			velocity.y -= GRAVITY * delta

	move_and_slide()

func _tick_timers(delta: float) -> void:
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			velocity = dash_dir * MOVE_SPEED
	if not can_dash:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer <= 0.0:
			can_dash = true

func _update_wall_state() -> void:
	var hit_left: bool = wall_ray_left.is_colliding()
	var hit_right: bool = wall_ray_right.is_colliding()
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() and horiz_speed > WALL_RUN_MIN_SPEED and (hit_left or hit_right):
		is_wall_running = true
		if hit_left:
			wall_normal = wall_ray_left.get_collision_normal()
			wall_side = -1
		else:
			wall_normal = wall_ray_right.get_collision_normal()
			wall_side = 1
	else:
		is_wall_running = false
		wall_normal = Vector3.ZERO
		wall_side = 0

func _update_camera_effects(delta: float) -> void:
	var target_roll: float = 0.0
	if is_wall_running:
		target_roll = CAMERA_TILT_WALL_RUN * float(wall_side)
	camera.rotation.z = lerp(camera.rotation.z, target_roll, CAMERA_TILT_LERP_SPEED * delta)

	var target_fov: float = BASE_FOV
	if is_dashing:
		target_fov = BASE_FOV + CAMERA_DASH_FOV_KICK
	camera.fov = lerp(camera.fov, target_fov, 14.0 * delta)

func get_state_string() -> String:
	var state: String = "FLOOR"
	if is_dashing:
		state = "DASHING"
	elif is_wall_running:
		state = "WALL-RUN (" + ("L" if wall_side == -1 else "R") + ")"
	elif not is_on_floor():
		state = "AIR"
	var dash_str: String = "READY" if can_dash else "CD %.1fs" % dash_cooldown_timer
	var air_jumps_left: int = 1 - air_jumps_used
	return "State: %s  |  Dash: %s  |  Air jumps: %d/1" % [state, dash_str, air_jumps_left]

func _start_dash(wish_dir: Vector3) -> void:
	var dir: Vector3 = wish_dir
	if dir.length() < 0.01:
		dir = -transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	dash_dir = dir
	is_dashing = true
	dash_timer = DASH_DURATION
	can_dash = false
	dash_cooldown_timer = DASH_COOLDOWN

func _dash_physics(_delta: float) -> void:
	velocity = dash_dir * DASH_SPEED
	velocity.y = 0.0
	move_and_slide()

func respawn() -> void:
	global_position = respawn_point
	velocity = Vector3.ZERO
	air_jumps_used = 0
	is_dashing = false
	is_wall_running = false

func die() -> void:
	died.emit()
	respawn()
