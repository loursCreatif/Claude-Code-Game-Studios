# Unit tests for Story 004 — Camera aim_forward forme close trigonométrique.
# Covers AC-CAM-50 (roll ignoré par construction), AC-CAM-51 (valeurs numériques
# exactes + VC-4 cross-check Basis.from_euler, 100 cas randomisés).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Note d'archi : aim_forward est un property getter pur (pas side-effect),
# consommé par Future Combat epic. Tilt (camera_effects.rotation.z) est
# explicitement ignoré — la formule close ne contient pas roll par construction.

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const TOLERANCE_STRICT: float = 1e-5
const TOLERANCE_NUMERIC: float = 1e-4

var _player: CharacterBody3D = null
var _camera_arm: Node3D = null
var _camera_effects: Node3D = null
var _camera_system: CameraSystem = null


func before_test() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as CharacterBody3D
	add_child(_player)
	await get_tree().process_frame

	_camera_arm = _player.get_node("CameraArm") as Node3D
	_camera_system = _camera_arm as CameraSystem
	_camera_effects = _camera_arm.get_node("CameraEffects") as Node3D

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm node has no CameraSystem script attached") \
		.is_not_null()
	assert_object(_camera_effects) \
		.override_failure_message("Setup error: CameraEffects node not found") \
		.is_not_null()

	# État déterministe.
	_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO
	_camera_effects.rotation = Vector3.ZERO


func after_test() -> void:
	# Disconnect manuel (story-011 ajoutera le _exit_tree symétrique).
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)

	_player.queue_free()
	_player = null
	_camera_arm = null
	_camera_effects = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-50 — Roll (tilt) est ignoré par construction closed-form
# ---------------------------------------------------------------------------

func test_aim_forward_ignores_positive_tilt_wall_right() -> void:
	# Arrange — wall-run droit : tilt +0.35, yaw=0, pitch=0
	_camera_effects.rotation.z = 0.35
	_camera_arm.rotation.x = 0.0
	_player.rotation.y = 0.0

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert — aim forward = (0, 0, -1), invariant au roll
	assert_float(aim.distance_to(Vector3(0.0, 0.0, -1.0))) \
		.override_failure_message(
			"aim_forward must equal (0,0,-1) despite tilt=+0.35 — got %s" % str(aim)
		) \
		.is_less(TOLERANCE_STRICT)


func test_aim_forward_ignores_negative_tilt_wall_left() -> void:
	# Arrange — wall-run gauche : tilt -0.35
	_camera_effects.rotation.z = -0.35
	_camera_arm.rotation.x = 0.0
	_player.rotation.y = 0.0

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert
	assert_float(aim.distance_to(Vector3(0.0, 0.0, -1.0))) \
		.override_failure_message(
			"aim_forward must equal (0,0,-1) despite tilt=-0.35 — got %s" % str(aim)
		) \
		.is_less(TOLERANCE_STRICT)


func test_aim_forward_ignores_absurd_tilt_value() -> void:
	# Arrange — valeur absurde (ne devrait jamais arriver en gameplay mais prouve l'invariance)
	_camera_effects.rotation.z = 2.0
	_camera_arm.rotation.x = 0.0
	_player.rotation.y = 0.0

	# Act + Assert
	var aim: Vector3 = _camera_system.aim_forward
	assert_float(aim.distance_to(Vector3(0.0, 0.0, -1.0))) \
		.override_failure_message(
			"aim_forward must stay (0,0,-1) even with absurd tilt=2.0 rad — got %s" % str(aim)
		) \
		.is_less(TOLERANCE_STRICT)


# ---------------------------------------------------------------------------
# AC-CAM-51 — Valeurs numériques exactes + tilt contaminant ignoré
# ---------------------------------------------------------------------------

func test_aim_forward_exact_numeric_values_with_tilt_contaminant() -> void:
	# Arrange — pitch=-0.5, yaw=0.3, tilt=0.2 (doit être ignoré)
	_camera_arm.rotation.x = -0.5
	_player.rotation.y = 0.3
	_camera_effects.rotation.z = 0.2

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert — valeurs précalculées depuis Vector3(-sin(0.3)*cos(-0.5), sin(-0.5), -cos(0.3)*cos(-0.5))
	# = (-0.29552 * 0.87758, -0.47943, -0.95534 * 0.87758) = (-0.25936, -0.47943, -0.83838)
	var expected: Vector3 = Vector3(-0.25936, -0.47943, -0.83838)
	assert_float(aim.distance_to(expected)) \
		.override_failure_message(
			"aim_forward must equal %s ± 1e-4 — got %s" % [str(expected), str(aim)]
		) \
		.is_less(TOLERANCE_NUMERIC)


# ---------------------------------------------------------------------------
# AC-CAM-51 — VC-4 cross-check : équivalence analytique avec Basis.from_euler
# ---------------------------------------------------------------------------

func test_aim_forward_vc4_basis_equivalence_single_case() -> void:
	# Arrange
	_camera_arm.rotation.x = -0.5
	_player.rotation.y = 0.3
	_camera_effects.rotation.z = 0.2

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert — aim_forward == -Basis.from_euler(Vector3(pitch, yaw, 0), YXZ).z
	# (roll=0 dans Basis — on vérifie que la formule close ignore roll comme Basis le ferait si on mettait roll=0)
	var basis_forward: Vector3 = -Basis.from_euler(Vector3(-0.5, 0.3, 0.0), EULER_ORDER_YXZ).z
	assert_float(aim.distance_to(basis_forward)) \
		.override_failure_message(
			"VC-4 cross-check failed : aim_forward %s vs Basis forward %s" % [str(aim), str(basis_forward)]
		) \
		.is_less(TOLERANCE_NUMERIC)


func test_aim_forward_vc4_basis_equivalence_100_randomized_cases() -> void:
	# Arrange — 100 cas randomisés dans safe range yaw ∈ [-2π, 2π], pitch ∈ [-PITCH_LIMIT, PITCH_LIMIT]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345  # déterministe
	var failures: Array[String] = []

	for i in range(100):
		var yaw: float = rng.randf_range(-TAU, TAU)
		var pitch: float = rng.randf_range(-CameraSystem.PITCH_LIMIT, CameraSystem.PITCH_LIMIT)
		var tilt: float = rng.randf_range(-1.0, 1.0)  # contaminant à ignorer

		_player.rotation.y = yaw
		_camera_arm.rotation.x = pitch
		_camera_effects.rotation.z = tilt

		# Act
		var aim: Vector3 = _camera_system.aim_forward
		var basis_forward: Vector3 = -Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ).z
		var dist: float = aim.distance_to(basis_forward)

		# Collect
		if dist >= TOLERANCE_NUMERIC:
			failures.append(
				"Case #%d yaw=%.3f pitch=%.3f tilt=%.3f : aim=%s basis=%s dist=%.6f"
				% [i, yaw, pitch, tilt, str(aim), str(basis_forward), dist]
			)

	# Assert — zéro divergence sur 100 cas
	assert_int(failures.size()) \
		.override_failure_message(
			"VC-4 cross-check failures (%d/100) : %s" % [failures.size(), ", ".join(failures)]
		) \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Edge cases — limites de pitch, yaw périodique
# ---------------------------------------------------------------------------

func test_aim_forward_at_positive_pitch_limit_points_near_up() -> void:
	# Arrange — pitch = +PITCH_LIMIT (≈ +87.1°, caméra tilt back = regarde quasi vertical haut,
	# convention Godot standard FPS : mouse-up → pitch-up → aim.y positif).
	_camera_arm.rotation.x = CameraSystem.PITCH_LIMIT
	_player.rotation.y = 0.0

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert — aim_forward.y ≈ +sin(PITCH_LIMIT) ≈ +0.9988 (quasi vertical haut)
	var expected_y: float = sin(CameraSystem.PITCH_LIMIT)
	assert_float(aim.y) \
		.override_failure_message(
			"aim_forward.y at +PITCH_LIMIT must equal +sin(PITCH_LIMIT) — got %f, expected %f"
			% [aim.y, expected_y]
		) \
		.is_equal_approx(expected_y, TOLERANCE_STRICT)


func test_aim_forward_at_negative_pitch_limit_points_near_down() -> void:
	# Arrange — pitch = -PITCH_LIMIT (caméra tilt forward = regarde quasi vertical bas).
	_camera_arm.rotation.x = -CameraSystem.PITCH_LIMIT
	_player.rotation.y = 0.0

	# Act
	var aim: Vector3 = _camera_system.aim_forward

	# Assert — aim_forward.y ≈ -sin(PITCH_LIMIT) ≈ -0.9988 (quasi vertical bas)
	var expected_y: float = -sin(CameraSystem.PITCH_LIMIT)
	assert_float(aim.y) \
		.override_failure_message(
			"aim_forward.y at -PITCH_LIMIT must equal -sin(PITCH_LIMIT) — got %f, expected %f"
			% [aim.y, expected_y]
		) \
		.is_equal_approx(expected_y, TOLERANCE_STRICT)


func test_aim_forward_yaw_periodic_wrap() -> void:
	# Arrange — yaw > 2π doit donner le même résultat que yaw mod 2π (sin/cos périodiques)
	_camera_arm.rotation.x = 0.1
	_camera_effects.rotation.z = 0.0

	_player.rotation.y = 0.5
	var aim_base: Vector3 = _camera_system.aim_forward

	_player.rotation.y = 0.5 + TAU
	var aim_wrapped: Vector3 = _camera_system.aim_forward

	# Assert
	assert_float(aim_base.distance_to(aim_wrapped)) \
		.override_failure_message(
			"yaw=0.5 and yaw=0.5+2π must produce identical aim_forward (sin/cos periodic) — got delta %s"
			% str(aim_base.distance_to(aim_wrapped))
		) \
		.is_less(TOLERANCE_STRICT)
