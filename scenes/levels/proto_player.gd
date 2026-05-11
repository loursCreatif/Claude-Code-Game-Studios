# PROTOTYPE - NOT FOR PRODUCTION
# Question: Le feel du mouvement katana + parkour est-il atteignable en Godot 4.6 avec GDScript ?
# Date: 2026-04-21

extends CharacterBody3D

const MOVE_SPEED: float = 13.0
const COYOTE_TIME: float = 0.12
const SLIDE_SPEED: float = 22.0
const SLIDE_DURATION: float = 0.9
const SLIDE_CAPSULE_HEIGHT: float = 0.9
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
const WALL_JUMP_SIDE: float = 9.0
const WALL_JUMP_UP: float = 8.0
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

var _dash_trail: CPUParticles3D = null

const HIGHSCORE_PATH: String = "user://highscore.cfg"
var _best_kills: int = 0
var _best_wave: int = 1

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	respawn_point = global_position
	_load_highscore()
	_update_highscore_label()
	# Fade out onboarding controls label après 7s.
	var label: Label = get_node_or_null("HUDProto/ControlsLabel") as Label
	if label != null:
		var fade_tween: Tween = create_tween()
		fade_tween.tween_interval(7.0)
		fade_tween.tween_property(label, "modulate:a", 0.0, 1.5)
	# Setup dash trail particles (n'emit que pendant is_dashing).
	_dash_trail = CPUParticles3D.new()
	_dash_trail.emitting = false
	_dash_trail.amount = 40
	_dash_trail.lifetime = 0.3
	_dash_trail.local_coords = false
	_dash_trail.spread = 8.0
	_dash_trail.gravity = Vector3.ZERO
	_dash_trail.initial_velocity_min = 0.5
	_dash_trail.initial_velocity_max = 1.5
	_dash_trail.scale_amount_min = 0.08
	_dash_trail.scale_amount_max = 0.16
	_dash_trail.color = Color(0.3, 0.85, 0.95, 0.9)
	add_child(_dash_trail)
	_dash_trail.position = Vector3(0, 0.9, 0)

var _session_time: float = 0.0

func _process(delta: float) -> void:
	# Invuln timer decrement.
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
	# HP regen progressive : après 5s sans damage, regen 1 HP/s.
	if not _is_dead:
		if _hp_regen_cooldown > 0.0:
			_hp_regen_cooldown -= delta
		elif current_hp < MAX_HP:
			_hp_regen_accum += delta * HP_REGEN_RATE
			if _hp_regen_accum >= 1.0:
				current_hp = mini(current_hp + 1, MAX_HP)
				_hp_regen_accum = 0.0
				_update_hp_bar()
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
	var horiz_speed_kmh: float = Vector2(velocity.x, velocity.z).length() * 3.6
	if speed_label != null:
		speed_label.text = "%d km/h" % int(horiz_speed_kmh)
	# Speed vignette : lerp doux pour éviter flicker au saut/wall.
	var vignette: ColorRect = get_node_or_null("HUDProto/SpeedLinesContainer/SpeedVignette") as ColorRect
	if vignette != null:
		var target_intensity: float = clamp((horiz_speed_kmh - 40.0) / 60.0, 0.0, 0.18)
		var current_a: float = vignette.color.a
		var new_a: float = lerp(current_a, target_intensity, delta * 3.0)
		vignette.color = Color(0.0, 0.05, 0.10, new_a)
	# Exit indicator : distance + symbole direction vers EtageExitTrigger.
	var exit_label: Label = get_node_or_null("HUDProto/ExitIndicator") as Label
	if exit_label != null:
		var exit_node: Node3D = get_tree().current_scene.get_node_or_null("EtageExitTrigger") as Node3D
		if exit_node != null:
			var to_exit: Vector3 = exit_node.global_position - global_position
			var dist: float = to_exit.length()
			var local_dir: Vector3 = transform.basis.inverse() * to_exit.normalized()
			var arrow: String = "→"
			if local_dir.z < -0.5:
				arrow = "↑"
			elif local_dir.z > 0.5:
				arrow = "↓"
			elif local_dir.x > 0.3:
				arrow = "↗"
			elif local_dir.x < -0.3:
				arrow = "↖"
			exit_label.text = "%s EXIT  %dm" % [arrow, int(dist)]
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
		_toggle_pause()
	if event.is_action_pressed("restart"):
		if _is_dead:
			_reset_run()
		else:
			respawn()
	if event.is_action_pressed("attack"):
		if katana and katana.has_method("swing"):
			katana.swing()
			attacked.emit()

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _ctrl_was_pressed: bool = false
const JUMP_BUFFER_TIME: float = 0.12

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_update_wall_state()
	_update_camera_effects(delta)

	if is_on_floor():
		air_jumps_used = 0
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME

	if is_dashing:
		_dash_physics(delta)
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Horizontal move — snap au sol (Pillar 1 FLOW), air control limité en l'air
	var speed: float = MOVE_SPEED * SPRINT_MULT
	# Wall-run boost : speed ×1.5 (récompense parkour fluide).
	if is_wall_running:
		speed *= 1.5
	if is_on_floor():
		if wish_dir.length() > 0.01:
			velocity.x = wish_dir.x * speed
			velocity.z = wish_dir.z * speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		if wish_dir.length() > 0.01:
			# Air control augmenté pour parkour plus réactif (40 → 75).
			var air_accel: float = 75.0 * delta
			velocity.x = move_toward(velocity.x, wish_dir.x * speed, air_accel)
			velocity.z = move_toward(velocity.z, wish_dir.z * speed, air_accel)

	# Jump / air jump / wall jump (coyote time + jump buffer pour forgiving timing).
	if _jump_buffer_timer > 0.0:
		if is_wall_running and wall_normal != Vector3.ZERO:
			velocity = wall_normal * WALL_JUMP_SIDE
			velocity.y = WALL_JUMP_UP
			is_wall_running = false
			air_jumps_used = 0
			_jump_buffer_timer = 0.0
		elif is_on_floor() or _coyote_timer > 0.0:
			velocity.y = JUMP_VELOCITY
			_coyote_timer = 0.0
			_jump_buffer_timer = 0.0
		elif air_jumps_used < 1 and Input.is_action_just_pressed("jump"):
			# Air jump uniquement sur input frame (pas buffered — pour éviter consume buffer).
			velocity.y = AIR_JUMP_VELOCITY
			air_jumps_used += 1
			_jump_buffer_timer = 0.0

	# Dash — poll direct pour contourner bug macOS où Shift seul n'émet pas d'InputEvent
	var shift_now: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	var shift_just_pressed: bool = shift_now and not shift_was_pressed
	shift_was_pressed = shift_now

	# Slide — Ctrl maintenu + au sol + vitesse > 8 m/s.
	var ctrl_now: bool = Input.is_physical_key_pressed(KEY_CTRL)
	var ctrl_just_pressed: bool = ctrl_now and not _ctrl_was_pressed
	_ctrl_was_pressed = ctrl_now
	var current_horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if not _is_sliding and ctrl_just_pressed and is_on_floor() and current_horiz_speed > 8.0:
		_start_slide(wish_dir)
	if _is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0 or not ctrl_now or not is_on_floor():
			_end_slide()
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
		if _dash_trail != null:
			_dash_trail.emitting = true
		if dash_timer <= 0.0:
			is_dashing = false
			velocity = dash_dir * MOVE_SPEED
			if _dash_trail != null:
				_dash_trail.emitting = false
	else:
		if _dash_trail != null and _dash_trail.emitting:
			_dash_trail.emitting = false
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
	# FOV dynamique : amplitude réduite + lerp doux (anti-flicker au saut/wall).
	var horiz_v: float = Vector2(velocity.x, velocity.z).length()
	var speed_norm: float = clamp((horiz_v - MOVE_SPEED) / (DASH_SPEED - MOVE_SPEED), 0.0, 1.0)
	target_fov += speed_norm * 6.0
	if is_dashing:
		target_fov = BASE_FOV + CAMERA_DASH_FOV_KICK
	# Wall-run kick FOV léger.
	if is_wall_running:
		target_fov += 4.0
	camera.fov = lerp(camera.fov, target_fov, 4.0 * delta)

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

const MAX_HP: int = 5
var current_hp: int = MAX_HP
var _is_dead: bool = false
var _invuln_timer: float = 0.0
var _hp_regen_cooldown: float = 0.0
var _hp_regen_accum: float = 0.0
const INVULN_AFTER_HIT: float = 1.0
const HP_REGEN_DELAY: float = 5.0
const HP_REGEN_RATE: float = 1.0

func die() -> void:
	# Intercepté : Grunt laser → take_damage 1 (legacy compat).
	take_damage(1)

func take_damage(amount: int) -> void:
	if _is_dead or _invuln_timer > 0.0:
		return
	current_hp -= amount
	_invuln_timer = INVULN_AFTER_HIT
	_hp_regen_cooldown = HP_REGEN_DELAY
	_hp_regen_accum = 0.0
	_update_hp_bar()
	# Flash rouge écran.
	var flash: ColorRect = get_node_or_null("HUDProto/KillFlash") as ColorRect
	if flash != null:
		flash.color = Color(1.0, 0.1, 0.1, 0.5)
		var t: Tween = create_tween()
		t.tween_property(flash, "color:a", 0.0, 0.25)
	if current_hp <= 0:
		_trigger_game_over()
	else:
		died.emit()

func _update_hp_bar() -> void:
	var fill: ColorRect = get_node_or_null("HUDProto/HpBg/HpFill") as ColorRect
	if fill != null:
		fill.size.x = 200.0 * (float(current_hp) / float(MAX_HP))

func _trigger_game_over() -> void:
	_is_dead = true
	Engine.time_scale = 0.0001
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var overlay: ColorRect = get_node_or_null("HUDProto/GameOverOverlay") as ColorRect
	if overlay != null:
		overlay.visible = true
	# Record run scores depuis HUD counters.
	var kill_counter: Label = get_node_or_null("HUDProto/KillCounter") as Label
	var wave_counter: Label = get_node_or_null("HUDProto/WaveCounter") as Label
	var k: int = 0
	var w: int = 1
	if kill_counter != null:
		k = kill_counter.text.split("  ")[-1].to_int()
	if wave_counter != null:
		w = wave_counter.text.split("  ")[-1].to_int()
	record_run_score(k, w)

func _reset_run() -> void:
	_is_dead = false
	current_hp = MAX_HP
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var overlay: ColorRect = get_node_or_null("HUDProto/GameOverOverlay") as ColorRect
	if overlay != null:
		overlay.visible = false
	_update_hp_bar()
	respawn()


func _start_slide(wish_dir: Vector3) -> void:
	var dir: Vector3 = wish_dir
	if dir.length() < 0.01:
		dir = -transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	_slide_dir = dir
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	velocity.x = dir.x * SLIDE_SPEED
	velocity.z = dir.z * SLIDE_SPEED
	# Camera plus basse pendant slide.
	if camera:
		camera.position.y = 0.20
	# Camera shake léger
	if katana and katana.has_method("camera_shake_at"):
		katana.camera_shake_at(0.02, 2)

func _end_slide() -> void:
	_is_sliding = false
	_slide_timer = 0.0
	if camera:
		camera.position.y = 0.65


var _is_paused: bool = false

func _toggle_pause() -> void:
	# Utilise Engine.time_scale au lieu de tree.paused pour garder _input vivant
	# (process_mode subtleties évitées pour MVP).
	_is_paused = not _is_paused
	Engine.time_scale = 0.0001 if _is_paused else 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _is_paused else Input.MOUSE_MODE_CAPTURED
	var overlay: ColorRect = get_node_or_null("HUDProto/PauseOverlay") as ColorRect
	if overlay != null:
		overlay.visible = _is_paused


func _load_highscore() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(HIGHSCORE_PATH) == OK:
		_best_kills = cfg.get_value("score", "kills", 0)
		_best_wave = cfg.get_value("score", "wave", 1)

func _save_highscore() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("score", "kills", _best_kills)
	cfg.set_value("score", "wave", _best_wave)
	cfg.save(HIGHSCORE_PATH)

func _update_highscore_label() -> void:
	var label: Label = get_node_or_null("HUDProto/HighScoreLabel") as Label
	if label != null:
		label.text = "BEST  K%d  V%d" % [_best_kills, _best_wave]

func record_run_score(kills: int, wave: int) -> void:
	# Appelé par etage_01_init au Game Over avec current_run values.
	var improved: bool = false
	if kills > _best_kills:
		_best_kills = kills
		improved = true
	if wave > _best_wave:
		_best_wave = wave
		improved = true
	if improved:
		_save_highscore()
		_update_highscore_label()
