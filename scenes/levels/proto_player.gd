# PROTOTYPE - NOT FOR PRODUCTION
# Question: Le feel du mouvement katana + parkour est-il atteignable en Godot 4.6 avec GDScript ?
# Date: 2026-04-21

extends CharacterBody3D

const MOVE_SPEED: float = 12.0
const COYOTE_TIME: float = 0.1
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
	# Fade out onboarding controls label après 7s.
	var label: Label = get_node_or_null("HUDProto/ControlsLabel") as Label
	if label != null:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_interval(7.0)
		fade_tween.tween_property(label, "modulate:a", 0.0, 1.5)

var _session_time: float = 0.0

func _process(delta: float) -> void:
	# Auto-respawn si Player tombe sous Y=-5 (safety net out-of-world).
	if global_position.y < -5.0:
		respawn()
	# Session timer affiché en HUD.
	_session_time += delta
	var timer_label: Label = get_node_or_null("HUDProto/TimerLabel") as Label
	if timer_label != null:
		var mm: int = int(_session_time) / 60
		var ss: int = int(_session_time) % 60
		timer_label.text = "%02d:%02d" % [mm, ss]
	# Speed display (km/h) — vitesse horizontale.
	var speed_label: Label = get_node_or_null("HUDProto/SpeedLabel") as Label
	if speed_label != null:
		var horiz_speed: float = Vector2(velocity.x, velocity.z).length() * 3.6
		speed_label.text = "%d km/h" % int(horiz_speed)
	# Dash cooldown bar : fill scale.x = 1 - (cooldown_timer / DASH_COOLDOWN), full quand prêt.
	var fill: ColorRect = get_node_or_null("HUDProto/DashCooldownBg/DashCooldownFill") as ColorRect
	if fill != null:
		var ratio: float = 1.0 - clamp(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0)
		fill.size.x = 200.0 * ratio
		fill.color = Color(0.3, 0.85, 0.95, 0.9) if ratio >= 1.0 else Color(0.5, 0.5, 0.55, 0.7)

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

var _coyote_timer: float = 0.0

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_wall_state()
	_update_camera_effects(delta)

	if is_on_floor():
		air_jumps_used = 0
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

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

	# Jump / air jump / wall jump (avec coyote time 0.1s post-floor).
	if Input.is_action_just_pressed("jump"):
		if is_wall_running and wall_normal != Vector3.ZERO:
			velocity = wall_normal * WALL_JUMP_SIDE
			velocity.y = WALL_JUMP_UP
			is_wall_running = false
			air_jumps_used = 0
		elif is_on_floor() or _coyote_timer > 0.0:
			velocity.y = JUMP_VELOCITY
			_coyote_timer = 0.0
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
	# Nouvelle règle : dash recharge UNIQUEMENT au contact du sol (pas de cooldown temps).
	if not can_dash and is_on_floor() and not is_dashing:
		can_dash = true
		dash_cooldown_timer = 0.0

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
	# FOV dynamique : grow up to +12° quand vitesse haute (flow Mirror's Edge style).
	var horiz_v: float = Vector2(velocity.x, velocity.z).length()
	var speed_norm: float = clamp((horiz_v - MOVE_SPEED) / (DASH_SPEED - MOVE_SPEED), 0.0, 1.0)
	target_fov += speed_norm * 12.0
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
	# Nouvelle règle : dash en l'air = 1 max (recharge au sol seulement).
	# Cooldown timer placeholder pour HUD bar vide jusqu'à atterrissage.
	dash_cooldown_timer = DASH_COOLDOWN * 999.0
	# Étape 7/10 — Camera shake léger au dash pour punch.
	if katana and katana.has_method("camera_shake_at"):
		katana.camera_shake_at(0.025, 2)

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
