# Integration tests for Story 005 — Tilt wall-run (derive wall_side + lerp camera_effects.rotation.z).
# Covers AC-CAM-10 (wall-run droit entry), AC-CAM-11 (exit converge to zero),
# AC-CAM-12 (transition gauche→droit traverse zero sans overshoot).
# TR-cam-004, ADR-0002 (Camera scene tree), ADR-0005 (Movement signals — wall_normal read-only).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Setup : MockPlayerWithWallNormal (CharacterBody3D exposant wall_normal) joue le rôle
# du Player. CameraArm (Node3D + CameraSystem script) est enfant du mock.
# CameraEffects + Camera3D sont enfants du CameraArm — reproduit Player.tscn exactement.
# Ce pattern évite une dépendance à Player.tscn qui n'a pas encore wall_normal.

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Tolerances et constantes de timing
# ---------------------------------------------------------------------------

## Seuil de précision strict pour comparaisons scalaires.
const TOLERANCE_STRICT: float = 1e-5

## Seuil de convergence exit (AC-CAM-11) : |z| < 0.01 rad.
const TOLERANCE_EXIT_CONVERGE: float = 0.01

## Seuil d'overshoot AC-CAM-12 : pas plus de 0.05 rad au-delà de la cible.
const TOLERANCE_OVERSHOOT: float = 0.05

## 0.95 * WALL_RUN_TILT_ANGLE = 0.95 * 0.35 = 0.3325 rad (AC-CAM-10).
const EXPECTED_95_PERCENT: float = 0.3325

## 250 ms à 60 fps (AC-CAM-10).
const FRAMES_250MS: int = 15

## 300 ms à 60 fps (AC-CAM-11).
const FRAMES_300MS: int = 18

## 200 ms à 60 fps (AC-CAM-12 borne haute).
const FRAMES_200MS: int = 12

## Delta fixe déterministe (1/60 s).
const FIXED_DELTA: float = 1.0 / 60.0

# ---------------------------------------------------------------------------
# Variables de test
# ---------------------------------------------------------------------------

var _mock_player: MockPlayerWithWallNormal = null
var _camera_arm: Node3D = null
var _camera_effects: Node3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	_mock_player = MockPlayerWithWallNormal.new()
	_mock_player.wall_normal = Vector3.ZERO

	_camera_arm = Node3D.new()
	_camera_arm.set_script(preload("res://src/gameplay/camera/camera_system.gd"))
	_camera_arm.set_unique_name_in_owner(true)

	_camera_effects = Node3D.new()
	_camera_effects.name = "CameraEffects"
	_camera_effects.set_unique_name_in_owner(true)

	var camera3d: Camera3D = Camera3D.new()
	camera3d.name = "Camera3D"
	camera3d.set_unique_name_in_owner(true)

	_camera_effects.add_child(camera3d)
	_camera_arm.add_child(_camera_effects)
	_mock_player.add_child(_camera_arm)
	add_child(_mock_player)
	await get_tree().process_frame

	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm does not have CameraSystem script") \
		.is_not_null()

	_mock_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO
	_camera_effects.rotation = Vector3.ZERO
	_mock_player.wall_normal = Vector3.ZERO


func after_test() -> void:
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
	_mock_player.queue_free()
	_mock_player = null
	_camera_arm = null
	_camera_effects = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Helper — simule n frames en appelant _update_tilt_wall_run avec delta fixe
# ---------------------------------------------------------------------------

func _simulate_frames(n: int) -> void:
	for _i in range(n):
		_camera_system._update_tilt_wall_run(FIXED_DELTA)


# ---------------------------------------------------------------------------
# AC-CAM-10 — Entrée wall-run droit : z > 0 à frame+1
# ---------------------------------------------------------------------------

func test_tilt_wall_run_first_frame_positive() -> void:
	# Arrange — mur à droite : wall_normal=(-1,0,0)
	# dot(-(-1,0,0), (1,0,0)) = 1 > 0 → wall_side=+1 → target=+0.35
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)
	_camera_effects.rotation.z = 0.0

	# Act
	_simulate_frames(1)

	# Assert
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-10 : z doit être > 0 après 1 frame de wall-run droit — got %f"
			% _camera_effects.rotation.z
		) \
		.is_greater(0.0)


# ---------------------------------------------------------------------------
# AC-CAM-10 — 95% atteint à 250 ms (15 frames)
# ---------------------------------------------------------------------------

func test_tilt_wall_run_right_entry_reaches_95_percent_at_250ms() -> void:
	# Arrange — mur à droite
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)
	_camera_effects.rotation.z = 0.0

	# Act — 15 frames = 250 ms à 60 fps
	_simulate_frames(FRAMES_250MS)

	# Assert — z ≥ 0.3325 rad (0.95 * WALL_RUN_TILT_ANGLE)
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-10 : z doit être ≥ %f rad après 15 frames — got %f"
			% [EXPECTED_95_PERCENT, _camera_effects.rotation.z]
		) \
		.is_greater_equal(EXPECTED_95_PERCENT)


# ---------------------------------------------------------------------------
# AC-CAM-11 — Exit wall-run : |z| < 0.01 en ≤ 300 ms (18 frames)
# ---------------------------------------------------------------------------

func test_tilt_wall_run_exit_converges_to_zero_in_300ms() -> void:
	# Arrange — part d'un tilt plein, sort du wall-run
	_camera_effects.rotation.z = CameraSystem.WALL_RUN_TILT_ANGLE
	_mock_player.wall_normal = Vector3.ZERO

	# Act — 18 frames = 300 ms
	_simulate_frames(FRAMES_300MS)

	# Assert — |z| < 0.01 rad
	assert_float(absf(_camera_effects.rotation.z)) \
		.override_failure_message(
			"AC-CAM-11 : |z| doit être < 0.01 rad après 18 frames post-exit — got |%f|"
			% _camera_effects.rotation.z
		) \
		.is_less(TOLERANCE_EXIT_CONVERGE)


# ---------------------------------------------------------------------------
# AC-CAM-12 — Transition gauche→droit : passage par 0 dans ≤ 200 ms
# ---------------------------------------------------------------------------

func test_tilt_wall_run_left_to_right_transition_crosses_zero() -> void:
	# Arrange — commence en wall-run gauche (z=-0.35), bascule vers droit
	_mock_player.wall_normal = Vector3(1.0, 0.0, 0.0)
	_camera_effects.rotation.z = -CameraSystem.WALL_RUN_TILT_ANGLE
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)  # bascule en 1 frame

	# Act — cherche le passage par zéro dans 12 frames (200 ms)
	var zero_crossing_found: bool = false
	var prev_z: float = _camera_effects.rotation.z

	for _frame in range(FRAMES_200MS):
		_camera_system._update_tilt_wall_run(FIXED_DELTA)
		var current_z: float = _camera_effects.rotation.z
		if (prev_z < 0.0 and current_z >= 0.0) or (prev_z > 0.0 and current_z <= 0.0):
			zero_crossing_found = true
		prev_z = current_z

	# Assert
	assert_bool(zero_crossing_found) \
		.override_failure_message(
			"AC-CAM-12 : la transition gauche→droit doit traverser 0 dans ≤ 200 ms — z final = %f"
			% _camera_effects.rotation.z
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-CAM-12 — Pas d'overshoot > 0.05 rad en transition
# ---------------------------------------------------------------------------

func test_tilt_wall_run_left_to_right_no_overshoot() -> void:
	# Arrange — part du tilt gauche, bascule vers droit
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)
	_camera_effects.rotation.z = -CameraSystem.WALL_RUN_TILT_ANGLE

	# Act — 30 frames pour laisser converger, capture le max
	var max_z: float = _camera_effects.rotation.z
	for _frame in range(30):
		_camera_system._update_tilt_wall_run(FIXED_DELTA)
		if _camera_effects.rotation.z > max_z:
			max_z = _camera_effects.rotation.z

	# Assert — pas d'overshoot > WALL_RUN_TILT_ANGLE + TOLERANCE_OVERSHOOT
	var overshoot_limit: float = CameraSystem.WALL_RUN_TILT_ANGLE + TOLERANCE_OVERSHOOT
	assert_float(max_z) \
		.override_failure_message(
			"AC-CAM-12 : overshoot détecté — z_max=%f, limite=%f"
			% [max_z, overshoot_limit]
		) \
		.is_less_equal(overshoot_limit)


# ---------------------------------------------------------------------------
# Edge case — jitter wall_normal (alternance chaque frame, pas de runaway)
# ---------------------------------------------------------------------------

func test_tilt_wall_run_no_oscillation_on_alternating_wall_normal() -> void:
	# Arrange
	_camera_effects.rotation.z = 0.0

	# Act — alterne gauche/droit 60 frames (1 s), simule un jitter réseau
	for frame in range(60):
		_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0) if frame % 2 == 0 \
			else Vector3(1.0, 0.0, 0.0)
		_camera_system._update_tilt_wall_run(FIXED_DELTA)

	# Assert — pas d'amplification hors bornes
	assert_float(absf(_camera_effects.rotation.z)) \
		.override_failure_message(
			"Edge case jitter : |z| ne doit pas dépasser WALL_RUN_TILT_ANGLE — got |%f|"
			% _camera_effects.rotation.z
		) \
		.is_less_equal(CameraSystem.WALL_RUN_TILT_ANGLE)


# ---------------------------------------------------------------------------
# Edge case — wall_normal absent du script Player (lecture défensive via get())
# ---------------------------------------------------------------------------

func test_tilt_wall_run_no_crash_when_wall_normal_absent() -> void:
	# Arrange — CharacterBody3D nu sans wall_normal (Movement pas encore implémenté)
	var bare_player: CharacterBody3D = CharacterBody3D.new()
	var bare_effects: Node3D = Node3D.new()
	bare_effects.name = "CameraEffects"
	bare_effects.set_unique_name_in_owner(true)
	var bare_cam: Camera3D = Camera3D.new()
	bare_cam.name = "Camera3D"
	bare_cam.set_unique_name_in_owner(true)
	var bare_arm: Node3D = Node3D.new()
	bare_arm.set_script(preload("res://src/gameplay/camera/camera_system.gd"))
	bare_arm.set_unique_name_in_owner(true)
	bare_effects.add_child(bare_cam)
	bare_arm.add_child(bare_effects)
	bare_player.add_child(bare_arm)
	add_child(bare_player)
	await get_tree().process_frame

	var bare_system: CameraSystem = bare_arm as CameraSystem

	# Act — pas de crash attendu (get("wall_normal") retourne null → Vector3.ZERO)
	bare_system._update_tilt_wall_run(FIXED_DELTA)

	# Assert — tilt reste à zéro
	assert_float(bare_effects.rotation.z) \
		.override_failure_message(
			"Sans wall_normal, rotation.z doit rester 0.0 — got %f" % bare_effects.rotation.z
		) \
		.is_equal_approx(0.0, TOLERANCE_STRICT)

	# Teardown local
	if InputManager.mouse_motion.is_connected(bare_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(bare_system._on_mouse_motion)
	bare_player.queue_free()
	await get_tree().process_frame
