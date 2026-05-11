extends Node3D

# Init temporaire MVP — capture la souris + débloque abilities + ajoute bindings alternatifs.
# À retirer quand GSM `_on_level_active` + UpgradeSystem orchestrent (story Production).

func _ready() -> void:
	InputManager.set_mouse_captured(true)
	_spawn_boss_marker()

func _spawn_boss_marker() -> void:
	# Label3D "BOSS" flottant rouge au-dessus de la zone boss (Z=80 Y=4).
	var label: Label3D = Label3D.new()
	label.text = "BOSS"
	label.font_size = 96
	label.modulate = Color(1.0, 0.15, 0.15, 1)
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	add_child(label)
	label.global_position = Vector3(0, 4.5, 80.0)
	# Pulse infinite scale.
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(label, "scale", Vector3(1.1, 1.1, 1.1), 0.8)
	tw.tween_property(label, "scale", Vector3(1.0, 1.0, 1.0), 0.8)

	# MVP playtest : bindings alternatifs au cas où Shift gauche ne marche pas sur Mac.
	# Ajoute touche E pour dash, F pour saut alternatif.
	_add_key_binding(&"dash", KEY_E)
	_add_key_binding(&"jump", KEY_F)

	# MVP playtest : si etage_01 charge alors que le main_menu est encore affiché
	# (cas du flow Menu → Start → etage_01 en parallèle plutôt que change_scene),
	# free le main_menu pour libérer la vue gameplay.
	_dispose_main_menu_if_present()

	# MVP playtest : spawn enemies sur les EnemySlot_* Marker3D présents dans la scène.
	# Normalement appelé par LevelSystem.commit_active() — mais bypass si lancement direct.
	# Idempotent : si déjà appelé (load_etage flow), spawn rien (Grunts déjà existants).
	if not _has_grunts_already():
		EnemySpawner.spawn_for_scene(self)
		_scale_boss_grunt()
		print("[etage_01_init] EnemySpawner.spawn_for_scene appelé")

	# Proto player a déjà toutes les abilities par défaut (can_dash=true, double-jump natif).

	# Étape 3/10 — EtageExitTrigger Victory : connecte body_entered au handler local.
	var exit_trigger: Area3D = get_node_or_null("EtageExitTrigger") as Area3D
	if exit_trigger != null and not exit_trigger.body_entered.is_connected(_on_etage_exit):
		exit_trigger.body_entered.connect(_on_etage_exit)

var _victory_triggered: bool = false

func _on_etage_exit(body: Node) -> void:
	if _victory_triggered:
		return
	if not (body is CharacterBody3D):
		return
	_victory_triggered = true
	# Affiche Victory label fade in + scale + stats.
	var player: Node = find_child("Player", true, false)
	if player == null:
		return
	var label: Label = player.get_node_or_null("HUDProto/VictoryLabel") as Label
	if label == null:
		return
	# Récupère stats.
	var k: int = 0
	var w: int = _wave_number
	var kill_l: Label = player.get_node_or_null("HUDProto/KillCounter") as Label
	if kill_l != null:
		k = kill_l.text.split("  ")[-1].to_int()
	var tim_l: Label = player.get_node_or_null("HUDProto/TimerLabel") as Label
	var time_text: String = "00:00"
	if tim_l != null:
		time_text = tim_l.text
	label.text = "VICTOIRE\nKILLS  %d\nVAGUE  %d\nTEMPS  %s" % [k, w, time_text]
	label.add_theme_font_size_override(&"font_size", 56)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.6)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.6).from(Vector2.ONE)
	# Slow-mo dramatique à la victoire.
	Engine.time_scale = 0.3
	get_tree().create_timer(2.0, false).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	# Save high score.
	if player.has_method("record_run_score"):
		player.record_run_score(k, w)

func _has_grunts_already() -> bool:
	return find_child("Grunt_*", true, false) != null

func _spawn_next_wave() -> void:
	_wave_number += 1
	# Update HUD wave counter.
	var player: Node = find_child("Player", true, false)
	if player:
		var wave_label: Label = player.get_node_or_null("HUDProto/WaveCounter") as Label
		if wave_label != null:
			wave_label.text = "VAGUE  %d" % _wave_number
			wave_label.pivot_offset = wave_label.size / 2.0
			wave_label.scale = Vector2(1.3, 1.3)
			create_tween().tween_property(wave_label, "scale", Vector2.ONE, 0.3)
	# Spawn EnemySpawner relance (basé sur EnemySlots existants).
	EnemySpawner.spawn_for_scene(self)
	# Scale boss à 1.8× (grunt le plus proche de Z=80).
	_scale_boss_grunt()
	print("[etage_01_init] Wave %d spawned" % _wave_number)

func _scale_boss_grunt() -> void:
	# Trouve le grunt dont Z est le plus proche de 80 et le scale ×1.8.
	var best_grunt: Node3D = null
	var best_diff: float = 999.0
	for g: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not (g is Node3D):
			continue
		if g.has_method("is_dead") and g.is_dead():
			continue
		var diff: float = absf((g as Node3D).global_position.z - 80.0)
		if diff < best_diff and diff < 5.0:
			best_diff = diff
			best_grunt = g as Node3D
	if best_grunt != null:
		best_grunt.scale = Vector3(1.8, 1.8, 1.8)
		# Tint plus rouge sur le mesh.
		var mesh_node: MeshInstance3D = best_grunt.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_node != null and mesh_node.material_override == null:
			var boss_mat: StandardMaterial3D = StandardMaterial3D.new()
			boss_mat.albedo_color = Color(0.6, 0.05, 0.05, 1)
			boss_mat.emission_enabled = true
			boss_mat.emission = Color(0.9, 0.10, 0.10, 1)
			boss_mat.emission_energy_multiplier = 1.2
			mesh_node.material_override = boss_mat

const GRUNT_WALK_SPEED: float = 1.2
const GRUNT_STOP_DISTANCE: float = 6.0
const WAVE_RESPAWN_DELAY: float = 3.0

var _wave_number: int = 1
var _wave_respawn_timer: float = 0.0
var _wave_pending: bool = false

func _process(delta: float) -> void:
	# Grunts AI tracking : FacingPivot vers Player + walk slow toward Player.
	var player: Node3D = find_child("Player", true, false) as Node3D
	if player == null:
		return
	# Wave system : count alive grunts, respawn wave si tous morts.
	var alive_count: int = 0
	for g: Node in get_tree().get_nodes_in_group(&"enemies"):
		if g.has_method("is_dead") and not g.is_dead():
			alive_count += 1
	if alive_count == 0:
		if not _wave_pending:
			_wave_pending = true
			_wave_respawn_timer = WAVE_RESPAWN_DELAY
		else:
			_wave_respawn_timer -= delta
			if _wave_respawn_timer <= 0.0:
				_spawn_next_wave()
				_wave_pending = false
	for grunt: Node in get_tree().get_nodes_in_group(&"enemies"):
		if not (grunt is Node3D):
			continue
		# Skip si DYING / DEAD (grunt.is_dead() exposé Rule 13).
		if grunt.has_method("is_dead") and grunt.is_dead():
			continue
		var grunt3d: Node3D = grunt as Node3D
		var to_player: Vector3 = player.global_position - grunt3d.global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist < 0.01:
			continue
		# Rotate FacingPivot vers Player (LaserCone aim live).
		var pivot: Node3D = grunt.get_node_or_null("%FacingPivot") as Node3D
		if pivot != null:
			var target_yaw: float = atan2(to_player.x, to_player.z) + PI
			pivot.global_rotation.y = lerp_angle(pivot.global_rotation.y, target_yaw, 0.05)
		# Walk vers Player si distance > GRUNT_STOP_DISTANCE (sinon stationary pour shoot).
		# Utilise move_and_collide pour respecter walls (anti-traverse-murs).
		if dist > GRUNT_STOP_DISTANCE:
			var dir: Vector3 = to_player.normalized()
			var motion: Vector3 = dir * GRUNT_WALK_SPEED * delta
			if grunt3d.has_method("move_and_collide"):
				grunt3d.move_and_collide(motion)
			else:
				grunt3d.global_position += motion

func _dispose_main_menu_if_present() -> void:
	# Hide (pas queue_free) le main_menu — le free de la main scene casserait
	# get_tree().current_scene et les inputs ne seraient plus routés correctement.
	# hide() rend invisible + désactive le process Control (mouse_filter input).
	for node: Node in get_tree().root.get_children():
		if node.name == "MainMenuController":
			print("[etage_01_init] main_menu hide()")
			(node as Control).visible = false
			# Désactive aussi le process pour éviter que le menu réagisse aux inputs.
			node.process_mode = Node.PROCESS_MODE_DISABLED
			return

func _add_key_binding(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		push_warning("[etage_01_init] action %s absente" % action)
		return
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
	print("[etage_01_init] +binding action=%s keycode=%d" % [action, keycode])
