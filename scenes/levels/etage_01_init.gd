extends Node3D

# Init temporaire MVP — capture la souris + débloque abilities + ajoute bindings alternatifs.
# À retirer quand GSM `_on_level_active` + UpgradeSystem orchestrent (story Production).

func _ready() -> void:
	InputManager.set_mouse_captured(true)

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
	# Affiche Victory label fade in + scale.
	var player: Node = find_child("Player", true, false)
	if player == null:
		return
	var label: Label = player.get_node_or_null("HUDProto/VictoryLabel") as Label
	if label == null:
		return
	label.add_theme_font_size_override(&"font_size", 96)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.6)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.6).from(Vector2.ONE)
	# Slow-mo dramatique à la victoire.
	Engine.time_scale = 0.3
	get_tree().create_timer(2.0, false).timeout.connect(func() -> void: Engine.time_scale = 1.0)

func _has_grunts_already() -> bool:
	return find_child("Grunt_*", true, false) != null

const GRUNT_WALK_SPEED: float = 2.0
const GRUNT_STOP_DISTANCE: float = 4.5

func _process(delta: float) -> void:
	# Grunts AI tracking : FacingPivot vers Player + walk slow toward Player.
	var player: Node3D = find_child("Player", true, false) as Node3D
	if player == null:
		return
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
		if dist > GRUNT_STOP_DISTANCE:
			var dir: Vector3 = to_player.normalized()
			grunt3d.global_position += dir * GRUNT_WALK_SPEED * delta

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
