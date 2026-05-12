extends GdUnitTestSuite

## Story-010 — AC-AUD-14 (c) BLOCKING headless assertion : 1 AudioListener3D unique
## scene tree, enfant Camera3D per ADR-0002 chain (Camera epic VC-5).
##
## Auto-current Godot 4.6 : si exactement 1 AudioListener3D présent dans scene tree,
## il est utilisé automatiquement comme listener actif sans `make_current()` explicite.
## Cf. note `Player.tscn` ligne 55 : "AC-CAM-TREE-4: AudioListener3D is auto-current".
##
## AC-AUD-14 (a) panning + (b) distance attenuation : ADVISORY playtest sound-designer
## (manuel casque audio) — DEFERRED Sprint Audio. Voir
## production/qa/evidence/audio-listener3d-verification-2026-05-04.md.
##
## Source : ADR-0009 D-6 (1 listener unique) + ADR-0002 chain VC-5 (Camera ownership).


const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"


# ────────── AC-AUD-14 (c) — Single listener assertion ──────────

func test_single_audio_listener_3d_in_player_scene_tree() -> void:
	# AC-AUD-14 (c) — `find_children("*", "AudioListener3D", true).size() == 1`.
	# Player.tscn embarque la chaîne ADR-0002 :
	#   Player → CameraArm → CameraEffects → Camera3D → AudioListener3D
	var scene_resource: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	assert_object(scene_resource) \
		.override_failure_message("Player.tscn introuvable à %s" % PLAYER_SCENE_PATH) \
		.is_not_null()

	var player: Node = scene_resource.instantiate()
	add_child(player)
	# Pas besoin d'attendre physics_frame : la scène est statique au moment du add.

	var listeners: Array[Node] = player.find_children("*", "AudioListener3D", true)

	assert_int(listeners.size()) \
		.override_failure_message(
			"AC-AUD-14 (c) violation — attendu 1 AudioListener3D unique " \
			+ "(ADR-0002 chain enfant Camera3D), trouvé %d" % listeners.size()
		) \
		.is_equal(1)

	player.queue_free()


func test_audio_listener_3d_parent_is_camera_3d() -> void:
	# AC-AUD-14 (c) renforcé : le listener doit être enfant direct d'un Camera3D
	# (chain ADR-0002 VC-5 : `... → Camera3D → AudioListener3D`).
	var scene_resource: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Node = scene_resource.instantiate()
	add_child(player)

	var listeners: Array[Node] = player.find_children("*", "AudioListener3D", true)
	assert_int(listeners.size()).is_equal(1)

	var listener: AudioListener3D = listeners[0] as AudioListener3D
	var parent: Node = listener.get_parent()

	assert_object(parent) \
		.override_failure_message(
			"AC-AUD-14 (c) violation — listener parent attendu Camera3D " \
			+ "(ADR-0002 chain), trouvé %s (%s)" % [parent.name, parent.get_class()]
		) \
		.is_instanceof(Camera3D)

	player.queue_free()


func test_audio_system_does_not_instantiate_second_listener() -> void:
	# Defense-in-depth : AudioSystem autoload ne doit JAMAIS posséder un
	# AudioListener3D (sinon conflit current avec Camera3D listener ADR-0002).
	# Lint statique story-009 enforce `AudioListener3D.new()` interdit dans
	# audio_system.gd, mais on vérifie ici l'invariant runtime côté autoload.
	var audio_system: Node = get_node_or_null("/root/AudioSystem")
	assert_object(audio_system) \
		.override_failure_message("AudioSystem autoload absent — préreq story-001") \
		.is_not_null()

	var audio_listeners_in_autoload: Array[Node] = audio_system.find_children(
		"*", "AudioListener3D", true
	)
	assert_int(audio_listeners_in_autoload.size()) \
		.override_failure_message(
			"R-AUD-9 / D-6 violation — AudioSystem possède %d AudioListener3D (attendu 0, ownership exclusive Camera3D ADR-0002 chain)" \
				% audio_listeners_in_autoload.size()
		) \
		.is_equal(0)
