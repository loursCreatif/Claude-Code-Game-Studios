# Unit tests for Story 010 — Reduce-motion gate (tilt × 0.25, fov × 0.5, shake × 0).
# Couvre AC-CAM-70 (tilt × 0.25), AC-CAM-71 (FOV kick × 0.5), AC-CAM-72 (shake × 0).
#
# GDD Rule 14 (creative-director r1 2026-04-21) accessibility floor MVP — évite
# exclusion 15-25% public motion-sensitive. Multipliers appliqués AU TARGET avant
# lerp (tilt + fov) ou en early-return point d'injection (shake).
#
# Story Type : Logic. Test Evidence path : tests/unit/camera/.
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# Pattern : load Player.tscn (cohérent stories 002/003/004 unit tests) — résout
# proprement %CameraEffects + %Camera3D via scene owner. Inject `_reduce_motion`
# directement sur le CameraSystem (var member, hardcoded false MVP, route via
# AccessibilitySettings post-MVP).

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"

## Tolerance pour assertions tilt convergence (lerp asymptotique 95% en t_95).
const TILT_TOLERANCE_RAD: float = 0.005

## Tolerance pour assertions FOV convergence.
const FOV_TOLERANCE_DEG: float = 0.2

## Frame count pour atteindre convergence lerp ≈ 95% (t_95).
const CONVERGENCE_FRAMES: int = 30
const FRAME_DELTA: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Variables de test
# ---------------------------------------------------------------------------

var _player: CharacterBody3D = null
var _camera_arm: Node3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Setup / teardown — pattern parity story_002 unit tests
# ---------------------------------------------------------------------------

func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as CharacterBody3D
	add_child(_player)
	await get_tree().process_frame

	_camera_arm = _player.get_node("CameraArm") as Node3D
	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm has no CameraSystem script") \
		.is_not_null()

	# État déterministe pour les tests.
	_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO

	# Active reduce_motion par défaut pour TOUS les tests de cette suite.
	# Tests baseline (reduce_motion=false) explicitent l'override.
	_camera_system._reduce_motion = true


func after_test() -> void:
	# Disconnect manuel — story-011 ajoutera _exit_tree symétrique dans CameraSystem.
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)

	_player.queue_free()
	_player = null
	_camera_arm = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-70 — tilt × 0.25 (target 0.0875 rad au lieu de 0.35)
# ---------------------------------------------------------------------------

func test_ac_cam_70_reduce_motion_attenuates_wall_run_tilt_to_quarter() -> void:
	# Arrange — wall_normal sur axe +X (mur à gauche du player) → wall_side calc.
	# Player rotation neutre → basis.x == Vector3.RIGHT. (-wall_normal).dot(basis.x)
	# = (-1, 0, 0).dot(1, 0, 0) = -1 → wall_side = -1.
	# target_roll = 0.35 * (-1) * 0.25 = -0.0875 rad (avec reduce_motion).
	# `wall_normal` est une getter-only property (MovementController), backed par `_wall_normal`.
	# Inject directement la backing variable pour le test.
	_player.set("_wall_normal", Vector3(1.0, 0.0, 0.0))

	# Act — 30 frames _process pour atteindre convergence lerp ≈ 95%.
	for i in range(CONVERGENCE_FRAMES):
		_camera_system._update_tilt_wall_run(FRAME_DELTA)

	# Assert — converge vers -0.0875 rad ± 0.005.
	var expected_target: float = -CameraSystem.WALL_RUN_TILT_ANGLE * CameraSystem.REDUCE_MOTION_TILT_MULT
	var camera_effects: Node3D = _camera_arm.get_node("CameraEffects") as Node3D
	assert_float(camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-70 : tilt doit converger vers %.4f rad (× 0.25) — got %.4f"
			% [expected_target, camera_effects.rotation.z]
		) \
		.is_equal_approx(expected_target, TILT_TOLERANCE_RAD)


func test_ac_cam_70_reduce_motion_disabled_keeps_full_tilt() -> void:
	# Arrange — baseline reduce_motion=false : tilt full magnitude (story 005).
	_camera_system._reduce_motion = false
	# `wall_normal` est une getter-only property (MovementController), backed par `_wall_normal`.
	# Inject directement la backing variable pour le test.
	_player.set("_wall_normal", Vector3(1.0, 0.0, 0.0))

	# Act — 30 frames pour convergence.
	for i in range(CONVERGENCE_FRAMES):
		_camera_system._update_tilt_wall_run(FRAME_DELTA)

	# Assert — converge vers -0.35 rad (full WALL_RUN_TILT_ANGLE × wall_side).
	var expected_target: float = -CameraSystem.WALL_RUN_TILT_ANGLE
	var camera_effects: Node3D = _camera_arm.get_node("CameraEffects") as Node3D
	assert_float(camera_effects.rotation.z) \
		.override_failure_message(
			"baseline : tilt doit converger vers %.4f rad sans reduce_motion — got %.4f"
			% [expected_target, camera_effects.rotation.z]
		) \
		.is_equal_approx(expected_target, TILT_TOLERANCE_RAD)


# ---------------------------------------------------------------------------
# AC-CAM-71 — FOV kick × 0.5 (peak 95° au lieu de 100°)
# ---------------------------------------------------------------------------

func test_ac_cam_71_reduce_motion_attenuates_dash_fov_kick_to_half() -> void:
	# Arrange — déclenche dash via signal canonique ADR-0005 (cache flag _is_dashing).
	_player.dash_started.emit(Vector3.FORWARD, 18.0)

	# Act — 30 frames pour convergence FOV.
	var camera3d: Camera3D = _camera_arm.get_node("CameraEffects/Camera3D") as Camera3D
	for i in range(CONVERGENCE_FRAMES):
		_camera_system._update_fov_dash(FRAME_DELTA)

	# Assert — converge vers BASE_FOV + DASH_FOV_KICK * 0.5 = 95.0° ± 0.2.
	var expected_fov: float = (
		CameraSystem.BASE_FOV
		+ CameraSystem.DASH_FOV_KICK * CameraSystem.REDUCE_MOTION_FOV_KICK_MULT
	)
	assert_float(camera3d.fov) \
		.override_failure_message(
			"AC-CAM-71 : FOV doit converger vers %.2f° (× 0.5) — got %.4f"
			% [expected_fov, camera3d.fov]
		) \
		.is_equal_approx(expected_fov, FOV_TOLERANCE_DEG)


func test_ac_cam_71_reduce_motion_disabled_keeps_full_fov_kick() -> void:
	# Arrange — baseline reduce_motion=false.
	_camera_system._reduce_motion = false
	_player.dash_started.emit(Vector3.FORWARD, 18.0)

	# Act — 30 frames.
	var camera3d: Camera3D = _camera_arm.get_node("CameraEffects/Camera3D") as Camera3D
	for i in range(CONVERGENCE_FRAMES):
		_camera_system._update_fov_dash(FRAME_DELTA)

	# Assert — converge vers 100° (BASE_FOV + DASH_FOV_KICK).
	var expected_fov: float = CameraSystem.BASE_FOV + CameraSystem.DASH_FOV_KICK
	assert_float(camera3d.fov) \
		.override_failure_message(
			"baseline : FOV doit converger vers %.2f° sans reduce_motion — got %.4f"
			% [expected_fov, camera3d.fov]
		) \
		.is_equal_approx(expected_fov, FOV_TOLERANCE_DEG)


# ---------------------------------------------------------------------------
# AC-CAM-72 — shake × 0 (early return dans add_shake)
# ---------------------------------------------------------------------------

func test_ac_cam_72_reduce_motion_disables_shake_injection() -> void:
	# Arrange — _shake_offset déjà à zero par défaut.
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message("Setup : _shake_offset doit être ZERO initial") \
		.is_equal(Vector3.ZERO)

	# Act — call add_shake_roll(0.05) → wrapper add_shake → early return.
	_camera_system.add_shake_roll(0.05)

	# Assert — _shake_offset reste ZERO (gate point d'injection).
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message(
			"AC-CAM-72 : _shake_offset doit rester ZERO avec reduce_motion — got %s"
			% str(_camera_system._shake_offset)
		) \
		.is_equal(Vector3.ZERO)


func test_ac_cam_72_reduce_motion_blocks_shake_via_wall_jumped_signal() -> void:
	# Arrange — connecte signal wall_jumped → handler appelle add_shake_roll en interne.
	# Aucun shake initial.
	assert_vector(_camera_system._shake_offset).is_equal(Vector3.ZERO)

	# Act — émet wall_jumped (handler _on_wall_jumped → add_shake_roll(WALL_JUMP_KICK)).
	_player.wall_jumped.emit(Vector3(1.0, 0.0, 0.0), Vector3(10.0, 10.0, 0.0))

	# Assert — shake_offset reste ZERO (gate effectif sur signal-driven path aussi).
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message(
			"AC-CAM-72 : wall_jumped → handler → add_shake_roll bloqué par reduce_motion — got %s"
			% str(_camera_system._shake_offset)
		) \
		.is_equal(Vector3.ZERO)


func test_ac_cam_72_reduce_motion_disabled_allows_shake_injection() -> void:
	# Arrange — baseline reduce_motion=false : shake injecté normalement.
	_camera_system._reduce_motion = false
	assert_vector(_camera_system._shake_offset).is_equal(Vector3.ZERO)

	# Act — inject 0.05 sur axe Z.
	_camera_system.add_shake_roll(0.05)

	# Assert — _shake_offset.z == 0.05 (pas de gate, story 007 baseline).
	assert_float(_camera_system._shake_offset.z) \
		.override_failure_message(
			"baseline : shake injecté sans reduce_motion — got %.4f"
			% _camera_system._shake_offset.z
		) \
		.is_equal_approx(0.05, 0.001)
