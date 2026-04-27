# Integration tests for Story 001 — Camera System Scene Skeleton + Project Settings.
# Covers AC-CAM-TREE-1, AC-CAM-TREE-2, AC-CAM-TREE-3, AC-CAM-RENDER-1, AC-CAM-RENDER-2.
# AC-CAM-TREE-4 (AudioListener3D auto-current) is MANUAL — evidence placeholder in
# production/qa/evidence/camera-audiolistener-2026-04-22.md
# Framework: GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const PROJECT_GODOT_PATH: String = "res://project.godot"


# ---------------------------------------------------------------------------
# AC-CAM-TREE-1 — Player.tscn contains the 3-tier camera tree
# ---------------------------------------------------------------------------

func test_player_scene_has_three_tier_camera_tree() -> void:
	# Arrange
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	# Act
	var player: Node = packed.instantiate()
	assert_object(player).is_not_null()

	# Assert — CharacterBody3D root
	assert_bool(player is CharacterBody3D) \
		.override_failure_message("Player root must be CharacterBody3D") \
		.is_true()

	# Assert — CameraArm exists and is Node3D
	var camera_arm: Node = player.get_node("CameraArm")
	assert_object(camera_arm) \
		.override_failure_message("CameraArm not found in Player scene") \
		.is_not_null()
	assert_bool(camera_arm is Node3D) \
		.override_failure_message("CameraArm must be Node3D") \
		.is_true()

	# Assert — CameraEffects exists and is Node3D (child of CameraArm)
	var camera_effects: Node = player.get_node("CameraArm/CameraEffects")
	assert_object(camera_effects) \
		.override_failure_message("CameraEffects not found at CameraArm/CameraEffects") \
		.is_not_null()
	assert_bool(camera_effects is Node3D) \
		.override_failure_message("CameraEffects must be Node3D") \
		.is_true()

	# Assert — Camera3D exists (child of CameraEffects)
	var camera3d: Node = player.get_node("CameraArm/CameraEffects/Camera3D")
	assert_object(camera3d) \
		.override_failure_message("Camera3D not found at CameraArm/CameraEffects/Camera3D") \
		.is_not_null()
	assert_bool(camera3d is Camera3D) \
		.override_failure_message("Camera3D must be of type Camera3D") \
		.is_true()

	# Assert — AudioListener3D exists (child of Camera3D)
	var audio_listener: Node = player.get_node("CameraArm/CameraEffects/Camera3D/AudioListener3D")
	assert_object(audio_listener) \
		.override_failure_message("AudioListener3D not found at CameraArm/CameraEffects/Camera3D/AudioListener3D") \
		.is_not_null()
	assert_bool(audio_listener is AudioListener3D) \
		.override_failure_message("AudioListener3D must be of type AudioListener3D") \
		.is_true()

	# Teardown
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-TREE-2 — Node positions match ADR-0002 spec
# ---------------------------------------------------------------------------

func test_camera_arm_position_is_eye_height() -> void:
	# Arrange
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Node = packed.instantiate()

	# Act
	var camera_arm: Node3D = player.get_node("CameraArm") as Node3D

	# Assert — Vector3(0, 1.6, 0) eye height (ADR-0002)
	assert_bool(camera_arm.position.is_equal_approx(Vector3(0.0, 1.6, 0.0))) \
		.override_failure_message(
			"CameraArm.position must be Vector3(0, 1.6, 0) — got: %s" % camera_arm.position
		) \
		.is_true()

	# Teardown
	player.queue_free()
	await get_tree().process_frame


func test_camera_effects_position_is_zero() -> void:
	# Arrange
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Node = packed.instantiate()

	# Act
	var camera_effects: Node3D = player.get_node("CameraArm/CameraEffects") as Node3D

	# Assert — Vector3.ZERO (ADR-0002)
	assert_bool(camera_effects.position.is_equal_approx(Vector3.ZERO)) \
		.override_failure_message(
			"CameraEffects.position must be Vector3.ZERO — got: %s" % camera_effects.position
		) \
		.is_true()

	# Teardown
	player.queue_free()
	await get_tree().process_frame


func test_camera3d_position_is_zero() -> void:
	# Arrange
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Node = packed.instantiate()

	# Act
	var camera3d: Node3D = player.get_node("CameraArm/CameraEffects/Camera3D") as Node3D

	# Assert — Vector3.ZERO (ADR-0002)
	assert_bool(camera3d.position.is_equal_approx(Vector3.ZERO)) \
		.override_failure_message(
			"Camera3D.position must be Vector3.ZERO — got: %s" % camera3d.position
		) \
		.is_true()

	# Teardown
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-TREE-3 — CameraSystem script accessors resolve after _ready()
# ---------------------------------------------------------------------------

func test_camera_system_script_accessors_resolve() -> void:
	# Arrange — add to scene tree so _ready() fires and @onready vars resolve
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	var player: Node = packed.instantiate()
	add_child(player)
	await get_tree().process_frame

	# Act — get the CameraArm which has CameraSystem script attached
	var camera_arm: Node3D = player.get_node("CameraArm") as Node3D
	assert_object(camera_arm) \
		.override_failure_message("CameraArm not found") \
		.is_not_null()

	# The script instance is the camera_arm node itself (script attached to CameraArm)
	var camera_system: CameraSystem = camera_arm as CameraSystem
	assert_object(camera_system) \
		.override_failure_message("CameraArm does not have CameraSystem script attached") \
		.is_not_null()

	# Assert — all getters return non-null typed refs (verifies @onready resolution)
	var arm_ref: Node3D = camera_system.get_camera_arm()
	assert_object(arm_ref) \
		.override_failure_message("get_camera_arm() returned null") \
		.is_not_null()
	assert_bool(arm_ref is Node3D) \
		.override_failure_message("get_camera_arm() must return Node3D") \
		.is_true()

	var effects_ref: Node3D = camera_system.get_camera_effects()
	assert_object(effects_ref) \
		.override_failure_message("get_camera_effects() returned null") \
		.is_not_null()
	assert_bool(effects_ref is Node3D) \
		.override_failure_message("get_camera_effects() must return Node3D") \
		.is_true()

	var cam3d_ref: Camera3D = camera_system.get_camera3d()
	assert_object(cam3d_ref) \
		.override_failure_message("get_camera3d() returned null") \
		.is_not_null()
	assert_bool(cam3d_ref is Camera3D) \
		.override_failure_message("get_camera3d() must return Camera3D") \
		.is_true()

	# Teardown
	player.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-RENDER-1 — project.godot contains all 6 required rendering settings
# ---------------------------------------------------------------------------

func test_project_godot_contains_rendering_settings() -> void:
	# Arrange — read project.godot via ConfigFile (parses INI sections)
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(PROJECT_GODOT_PATH)
	assert_int(err) \
		.override_failure_message("Could not load project.godot — error code: %d" % err) \
		.is_equal(OK)

	# Assert — renderer/rendering_method = "forward_plus"
	assert_bool(config.has_section_key("rendering", "renderer/rendering_method")) \
		.override_failure_message("rendering/renderer/rendering_method missing from project.godot") \
		.is_true()
	assert_str(config.get_value("rendering", "renderer/rendering_method", "") as String) \
		.override_failure_message("renderer/rendering_method must be 'forward_plus'") \
		.is_equal("forward_plus")

	# Assert — anti_aliasing/quality/msaa_3d = 0
	assert_bool(config.has_section_key("rendering", "anti_aliasing/quality/msaa_3d")) \
		.override_failure_message("rendering/anti_aliasing/quality/msaa_3d missing from project.godot") \
		.is_true()
	assert_int(config.get_value("rendering", "anti_aliasing/quality/msaa_3d", -1) as int) \
		.override_failure_message("anti_aliasing/quality/msaa_3d must be 0 (MSAA disabled)") \
		.is_equal(0)

	# Assert — anti_aliasing/quality/screen_space_aa = 2 (SMAA 1x — new in 4.5)
	assert_bool(config.has_section_key("rendering", "anti_aliasing/quality/screen_space_aa")) \
		.override_failure_message("rendering/anti_aliasing/quality/screen_space_aa missing from project.godot") \
		.is_true()
	assert_int(config.get_value("rendering", "anti_aliasing/quality/screen_space_aa", -1) as int) \
		.override_failure_message("anti_aliasing/quality/screen_space_aa must be 2 (SMAA 1x)") \
		.is_equal(2)

	# Assert — anti_aliasing/quality/use_taa must resolve to false.
	# Godot elides keys at engine default on re-save, so only check the effective value
	# (default=false mirrors Godot 4.6 engine default). The raw-text scan in
	# test_project_godot_does_not_contain_taa_true catches any explicit `true` variant.
	assert_bool(config.get_value("rendering", "anti_aliasing/quality/use_taa", false) as bool) \
		.override_failure_message("anti_aliasing/quality/use_taa must be false (TAA forbidden)") \
		.is_false()

	# Assert — vrs/mode = 0
	assert_bool(config.has_section_key("rendering", "vrs/mode")) \
		.override_failure_message("rendering/vrs/mode missing from project.godot") \
		.is_true()
	assert_int(config.get_value("rendering", "vrs/mode", -1) as int) \
		.override_failure_message("vrs/mode must be 0 (VRS disabled)") \
		.is_equal(0)

	# Assert — display/window/vsync/vsync_mode = 1 (in [display] section)
	assert_bool(config.has_section_key("display", "window/vsync/vsync_mode")) \
		.override_failure_message("display/window/vsync/vsync_mode missing from project.godot") \
		.is_true()
	assert_int(config.get_value("display", "window/vsync/vsync_mode", -1) as int) \
		.override_failure_message("window/vsync/vsync_mode must be 1 (vsync enabled)") \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-CAM-RENDER-2 — project.godot must NOT contain use_taa = true
# ---------------------------------------------------------------------------

func test_project_godot_does_not_contain_taa_true() -> void:
	# Arrange — read raw text to catch any formatting variant (with or without spaces)
	var file: FileAccess = FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Could not open project.godot for raw text scan") \
		.is_not_null()

	# Act
	var content: String = file.get_as_text()
	file.close()

	# Assert — neither "use_taa=true" nor "use_taa = true" must appear
	var has_taa_no_spaces: bool = content.contains("use_taa=true")
	var has_taa_with_spaces: bool = content.contains("use_taa = true")

	assert_bool(has_taa_no_spaces) \
		.override_failure_message("project.godot contains forbidden 'use_taa=true'") \
		.is_false()
	assert_bool(has_taa_with_spaces) \
		.override_failure_message("project.godot contains forbidden 'use_taa = true'") \
		.is_false()
