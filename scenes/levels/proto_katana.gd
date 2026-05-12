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
			_kill_feedback(col)
		elif col.has_method("die"):
			# Production Grunt utilise die() (Enemy GDD r2 Rule 14).
			col.die()
			_kill_feedback(col)

var _last_kill_time_msec: int = 0
var _streak: int = 0
const STREAK_TIMEOUT_MSEC: int = 1500

func _kill_feedback(col: Object) -> void:
	enemy_killed.emit(col)
	_trigger_kill_flash()
	var kill_pos: Vector3 = (col as Node3D).global_position if col is Node3D else Vector3.ZERO
	_spawn_kill_particles(kill_pos)
	_trigger_camera_shake()
	_increment_kill_counter()
	_spawn_kill_popup(kill_pos)
	_check_multi_kill_slowmo()
	_apply_player_knockback()
	_trigger_hitmarker()
	_update_streak()
	_spawn_credit_pickup(kill_pos)
	_refresh_dash_on_kill()

func _refresh_dash_on_kill() -> void:
	# Dash recharge instant sur kill (Apex Legends récompense agression).
	var player: Node = get_parent().get_parent().get_parent()
	if player == null:
		return
	if player.has_method("get") and "can_dash" in player:
		player.can_dash = true
		player.dash_cooldown_timer = 0.0

func _spawn_credit_pickup(pos: Vector3) -> void:
	# Spawn un Area3D cyan rotating à la position du kill. Player walks over → pickup.
	var area: Area3D = Area3D.new()
	area.collision_layer = 16  # LAYER_INTERACTIVE
	area.collision_mask = 1   # LAYER_PLAYER
	area.monitorable = false
	area.monitoring = true
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var s: SphereShape3D = SphereShape3D.new()
	s.radius = 1.8
	shape_node.shape = s
	area.add_child(shape_node)
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(0.3, 0.3, 0.3)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.95, 1.0, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.95, 1.0, 1)
	mat.emission_energy_multiplier = 2.0
	m.material = mat
	mesh_node.mesh = m
	area.add_child(mesh_node)
	get_tree().current_scene.add_child(area)
	area.global_position = pos + Vector3(0, 0.3, 0)
	print("[pickup] spawned at %s, radius 1.8" % area.global_position)
	# Rotation continue via Tween infini.
	var rot_tween: Tween = create_tween().set_loops()
	rot_tween.tween_property(area, "rotation:y", TAU, 1.5)
	# Sphere body_entered → increment counter Player.
	area.body_entered.connect(func(body: Node) -> void:
		print("[pickup] body_entered: %s (in player group=%s)" % [body.name, body.is_in_group(&"player")])
		if body.is_in_group(&"player"):
			_increment_credit_counter()
			rot_tween.kill()
			area.queue_free()
	)
	# Auto cleanup après 15s pour éviter accumulation.
	get_tree().create_timer(15.0, false).timeout.connect(func() -> void:
		if is_instance_valid(area):
			rot_tween.kill()
			area.queue_free()
	)

func _increment_credit_counter() -> void:
	var player: Node = get_parent().get_parent().get_parent()
	var label: Label = player.get_node_or_null("HUDProto/CreditCounter") as Label
	if label == null:
		return
	var current: int = label.text.split("  ")[-1].to_int()
	label.text = "CRÉDITS  %d" % (current + 1)
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(1.2, 1.2)
	create_tween().tween_property(label, "scale", Vector2.ONE, 0.2)

func _update_streak() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_kill_time_msec < STREAK_TIMEOUT_MSEC and _last_kill_time_msec > 0:
		_streak += 1
	else:
		_streak = 1
	var player: Node = get_parent().get_parent().get_parent()
	var label: Label = player.get_node_or_null("HUDProto/StreakLabel") as Label
	if label == null:
		return
	if _streak >= 2:
		label.text = "x%d STREAK" % _streak
		label.modulate.a = 1.0
		# Pulse scale + fade out après timeout.
		label.pivot_offset = label.size / 2.0
		var pulse: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		label.scale = Vector2(1.25, 1.25)
		pulse.tween_property(label, "scale", Vector2.ONE, 0.25)
		# Streak milestone : +1 HP tous les 5 kills.
		if _streak % 5 == 0:
			_grant_streak_reward()
		# Reset auto après STREAK_TIMEOUT_MSEC.
		get_tree().create_timer(STREAK_TIMEOUT_MSEC / 1000.0, false).timeout.connect(
			func() -> void:
				if Time.get_ticks_msec() - _last_kill_time_msec >= STREAK_TIMEOUT_MSEC:
					_streak = 0
					var fade: Tween = create_tween()
					fade.tween_property(label, "modulate:a", 0.0, 0.4)
		)

func _trigger_hitmarker() -> void:
	# Flash hitmarker croix jaune 150ms au kill.
	var player: Node = get_parent().get_parent().get_parent()
	var marker: Control = player.get_node_or_null("HUDProto/Hitmarker") as Control
	if marker == null:
		return
	marker.modulate = Color(1, 1, 1, 1)
	marker.scale = Vector2(0.7, 0.7)
	marker.pivot_offset = marker.size / 2.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(marker, "scale", Vector2.ONE, 0.12)
	tween.tween_property(marker, "modulate:a", 0.0, 0.18)

func _check_multi_kill_slowmo() -> void:
	# Étape 11 — Hit-stop : freeze 40ms wall-clock sur chaque kill (punch impact).
	# Puis si multi-kill (≤500ms), slow-mo 0.5× pendant 300ms.
	var now: int = Time.get_ticks_msec()
	var is_multi_kill: bool = (now - _last_kill_time_msec < 500 and _last_kill_time_msec > 0)
	# Hit-stop systematic.
	Engine.time_scale = 0.05
	if is_multi_kill:
		# Multi-kill : hit-stop 40ms puis slow-mo 0.5× 300ms.
		get_tree().create_timer(0.04 * 0.05, false).timeout.connect(func() -> void:
			Engine.time_scale = 0.5
			get_tree().create_timer(0.3 * 0.5, false).timeout.connect(func() -> void: Engine.time_scale = 1.0)
		)
	else:
		# Solo kill : juste hit-stop 40ms.
		get_tree().create_timer(0.04 * 0.05, false).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	_last_kill_time_msec = now

func _apply_player_knockback() -> void:
	# Étape 5/10 — recul léger du Player au kill (weight feedback).
	var player: Node3D = get_parent().get_parent().get_parent() as Node3D
	if player == null or not player.has_method("move_and_slide"):
		return
	var forward: Vector3 = -player.transform.basis.z
	forward.y = 0.0
	# Set velocity directement — CharacterBody3D suivra physics next tick.
	if player.has_method("get") and "velocity" in player:
		player.velocity -= forward.normalized() * 1.5

func _increment_kill_counter() -> void:
	var player: Node = get_parent().get_parent().get_parent()
	var counter: Label = player.get_node_or_null("HUDProto/KillCounter") as Label
	if counter == null:
		return
	var current: int = counter.text.split("  ")[-1].to_int()
	counter.text = "KILLS  %d" % (current + 1)
	# Pulse scale
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	counter.pivot_offset = counter.size / 2.0
	counter.scale = Vector2(1.3, 1.3)
	tween.tween_property(counter, "scale", Vector2.ONE, 0.25)

func _spawn_kill_popup(world_pos: Vector3) -> void:
	# Popup 3D "+1" qui flotte vers le haut puis fade out.
	var label: Label3D = Label3D.new()
	label.text = "+1"
	label.font_size = 64
	label.modulate = Color(1.0, 0.95, 0.3, 1)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	get_tree().current_scene.add_child(label)
	label.global_position = world_pos + Vector3(0, 1.8, 0)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.2, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

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


func _spawn_kill_particles(pos: Vector3) -> void:
	# Burst CPUParticles3D MVP — débris rouge/blanc autour du grunt mort.
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.emitting = false
	particles.amount = 24
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.spread = 180.0
	particles.gravity = Vector3(0, -9.8, 0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 7.0
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.18
	particles.color = Color(1.0, 0.95, 0.3, 1)
	get_tree().current_scene.add_child(particles)
	particles.global_position = pos + Vector3(0, 1.0, 0)
	particles.emitting = true
	# Auto-cleanup après lifetime + epsilon.
	var timer: SceneTreeTimer = get_tree().create_timer(particles.lifetime + 0.1)
	timer.timeout.connect(func() -> void: if is_instance_valid(particles): particles.queue_free())


func _trigger_camera_shake() -> void:
	# Quick camera shake — juicy kill feedback MVP.
	camera_shake_at(0.04, 3)

func camera_shake_at(intensity: float, count: int) -> void:
	# Public — appelable depuis proto_player pour dash shake (étape 7/10).
	var player: Node = get_parent().get_parent().get_parent()
	var camera: Node3D = player.get_node_or_null("Camera3D") as Node3D
	if camera == null:
		return
	var orig: Vector3 = camera.position
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE)
	for i in count:
		var offset: Vector3 = Vector3(randf_range(-intensity, intensity), randf_range(-intensity, intensity), 0)
		tween.tween_property(camera, "position", orig + offset, 0.025)
	tween.tween_property(camera, "position", orig, 0.05)


func _grant_streak_reward() -> void:
	# +1 HP au Player + popup HUD.
	var player: Node = get_parent().get_parent().get_parent()
	if player == null:
		return
	if player.has_method("get") and "current_hp" in player and "MAX_HP" in player:
		if player.current_hp < player.MAX_HP:
			player.current_hp += 1
			if player.has_method("_update_hp_bar"):
				player._update_hp_bar()
	# Spawn popup "+HP" doré au centre écran.
	var hud: CanvasLayer = player.get_node_or_null("HUDProto") as CanvasLayer
	if hud == null:
		return
	var bonus: Label = Label.new()
	bonus.text = "+1 HP"
	bonus.modulate = Color(1.0, 0.85, 0.25, 1)
	bonus.add_theme_font_size_override(&"font_size", 56)
	bonus.anchor_left = 0.5
	bonus.anchor_top = 0.5
	bonus.anchor_right = 0.5
	bonus.anchor_bottom = 0.5
	bonus.offset_left = -120.0
	bonus.offset_top = -180.0
	bonus.offset_right = 120.0
	bonus.offset_bottom = -100.0
	bonus.horizontal_alignment = 1
	bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bonus)
	bonus.pivot_offset = bonus.size / 2.0
	bonus.scale = Vector2(0.5, 0.5)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(bonus, "scale", Vector2.ONE, 0.3)
	tw.tween_property(bonus, "modulate:a", 0.0, 1.2)
	tw.chain().tween_callback(bonus.queue_free)
