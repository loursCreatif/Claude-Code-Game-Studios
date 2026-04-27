# Unit tests for Story 002 — Camera yaw + pitch raw apply.
# Covers AC-CAM-01 (yaw horizontal), AC-CAM-02 (pitch + invert_y),
# AC-CAM-03 (clamp dur PITCH_LIMIT), AC-CAM-04 (clamp magnitude MAX_ROT_PER_FRAME).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Note d'archi : InputManager est autoload — accessible globalement.
# Le signal mouse_motion est émis via InputManager.mouse_motion.emit(Vector2),
# CameraSystem._on_mouse_motion est appelé synchrone (CONNECT_0 default).

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const TOLERANCE: float = 0.001

var _player: CharacterBody3D = null
var _camera_arm: Node3D = null
var _camera_system: CameraSystem = null

# Sauvegardes pour restauration entre tests (autoload state global).
var _saved_sensitivity: float = 0.0022
var _saved_y_inverted: bool = false


func before_test() -> void:
	# Sauvegarder l'état autoload (autoload InputManager est partagé entre tests).
	_saved_sensitivity = InputManager.mouse_sensitivity
	_saved_y_inverted = InputManager.mouse_y_inverted

	# Instancier Player (déclenche _ready de CameraSystem → connect signal).
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as CharacterBody3D
	add_child(_player)
	await get_tree().process_frame

	_camera_arm = _player.get_node("CameraArm") as Node3D
	_camera_system = _camera_arm as CameraSystem

	# Fail-fast si le cast échoue (CameraArm n'a pas le script CameraSystem attaché).
	# Sans cet assert, un null silencieux ferait passer tous les tests par accident.
	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm node has no CameraSystem script attached") \
		.is_not_null()

	# Reset rotations à zéro pour partir d'un état déterministe.
	_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO


func after_test() -> void:
	# Disconnect manuel pour éviter fuite handler entre tests
	# (story-011 ajoutera le _exit_tree symétrique dans CameraSystem).
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)

	_player.queue_free()
	_player = null
	_camera_arm = null
	_camera_system = null
	await get_tree().process_frame

	# Restaurer autoload state.
	InputManager.mouse_sensitivity = _saved_sensitivity
	InputManager.mouse_y_inverted = _saved_y_inverted


# ---------------------------------------------------------------------------
# AC-CAM-01 — Yaw horizontal pur via signal mouse_motion
# ---------------------------------------------------------------------------

func test_mouse_motion_horizontal_rotates_player_yaw() -> void:
	# Arrange
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_y_inverted = false

	# Act — Vector2(100, 0) = curseur droite → yaw_delta = -100 * 0.0022 = -0.22 rad
	InputManager.mouse_motion.emit(Vector2(100.0, 0.0))

	# Assert — player.rotation.y a décru de 0.22 rad ± tolérance
	assert_float(_player.rotation.y) \
		.override_failure_message(
			"player.rotation.y must equal -0.22 rad (got %f)" % _player.rotation.y
		) \
		.is_equal_approx(-0.22, TOLERANCE)

	# Assert — camera_arm.rotation.x inchangé (delta < 1e-6)
	assert_bool(absf(_camera_arm.rotation.x) < 1e-6) \
		.override_failure_message(
			"camera_arm.rotation.x must remain ~0 (got %f)" % _camera_arm.rotation.x
		) \
		.is_true()


func test_mouse_motion_negative_x_rotates_player_yaw_positive() -> void:
	# Arrange
	InputManager.mouse_sensitivity = 0.0022

	# Act — Vector2(-100, 0) = curseur gauche → yaw_delta = +0.22 rad
	InputManager.mouse_motion.emit(Vector2(-100.0, 0.0))

	# Assert
	assert_float(_player.rotation.y) \
		.override_failure_message("Negative delta.x must rotate yaw positive") \
		.is_equal_approx(0.22, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-02 — Pitch + invert_y
# ---------------------------------------------------------------------------

func test_mouse_motion_vertical_rotates_camera_arm_pitch_default() -> void:
	# Arrange — invert_y false : delta.y positif (curseur bas) → pitch décroît
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_y_inverted = false

	# Act
	InputManager.mouse_motion.emit(Vector2(0.0, 100.0))

	# Assert — camera_arm.rotation.x = -100 * 0.0022 * 1.0 = -0.22 (default invert factor 1.0)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"camera_arm.rotation.x must equal -0.22 (default invert) — got %f" % _camera_arm.rotation.x
		) \
		.is_equal_approx(-0.22, TOLERANCE)


func test_mouse_motion_vertical_with_invert_y_inverts_pitch_sign() -> void:
	# Arrange — invert_y true : sens inversé
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_y_inverted = true

	# Act — même delta.y=100 mais avec invert
	InputManager.mouse_motion.emit(Vector2(0.0, 100.0))

	# Assert — formule : -100 * 0.0022 * (-1.0) = +0.22 rad
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"With invert_y=true, camera_arm.rotation.x must equal +0.22 — got %f"
			% _camera_arm.rotation.x
		) \
		.is_equal_approx(0.22, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-03 — Clamp dur PITCH_LIMIT, pas d'accumulation interne
# ---------------------------------------------------------------------------

func test_pitch_clamps_hard_at_limit_no_accumulation() -> void:
	# Arrange — placer pitch à la limite supérieure
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_y_inverted = false
	_camera_arm.rotation.x = CameraSystem.PITCH_LIMIT

	# Act — émettre une motion équivalente à +0.5 rad de pitch (au-dessus du clamp)
	# Avec invert_y=false : pitch_delta = -delta.y * sensitivity = -(0.5 / -sensitivity) * sensitivity
	# Pour obtenir pitch_delta = +0.5 rad : delta.y = -0.5 / 0.0022 ≈ -227.27
	InputManager.mouse_motion.emit(Vector2(0.0, -0.5 / 0.0022))

	# Assert — clamp dur exact à PITCH_LIMIT (pas dépassement)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"camera_arm.rotation.x must be clamped exactly to PITCH_LIMIT — got %f vs %f"
			% [_camera_arm.rotation.x, CameraSystem.PITCH_LIMIT]
		) \
		.is_equal_approx(CameraSystem.PITCH_LIMIT, 1e-5)


func test_pitch_clamp_no_internal_accumulation_returns_immediately() -> void:
	# Arrange — saturer pitch en haut avec 10 motions « vers le haut »
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_y_inverted = false
	_camera_arm.rotation.x = CameraSystem.PITCH_LIMIT

	for i in range(10):
		InputManager.mouse_motion.emit(Vector2(0.0, -100.0))  # tente +0.22 chaque fois

	# Assert toujours PITCH_LIMIT (pas de dette interne)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("After 10 saturating motions, pitch must remain at PITCH_LIMIT") \
		.is_equal_approx(CameraSystem.PITCH_LIMIT, 1e-5)

	# Act — 1 motion vers le bas → pitch décroît IMMÉDIATEMENT
	# (pas de dette accumulée à rattraper côté interne)
	InputManager.mouse_motion.emit(Vector2(0.0, 100.0))  # pitch_delta = -0.22 rad

	# Assert — pitch a baissé de 0.22 rad par rapport au limit, pas masqué par buffer
	var expected: float = CameraSystem.PITCH_LIMIT - 0.22
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"After saturation puis 1 motion bas, pitch doit décroître immédiatement — got %f, expected %f"
			% [_camera_arm.rotation.x, expected]
		) \
		.is_equal_approx(expected, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-04 — Clamp magnitude MAX_ROT_PER_FRAME, pas d'accumulation
# ---------------------------------------------------------------------------

func test_extreme_flick_clamps_yaw_delta_to_max_rot_per_frame() -> void:
	# Arrange — sensitivity max safe + flick dégénéré
	InputManager.mouse_sensitivity = 0.012  # max safe range (story Implementation Notes)
	_player.rotation.y = 0.0

	# Act — Vector2(10000, 0) → yaw_delta naïf = -10000 * 0.012 = -120 rad
	# Doit être clamped à -PI (~-3.14)
	InputManager.mouse_motion.emit(Vector2(10000.0, 0.0))

	# Assert — |yaw appliqué| ≤ PI (= MAX_ROT_PER_FRAME)
	var applied_delta: float = absf(_player.rotation.y)  # rotation initiale 0 → applied = abs(rot après)
	assert_bool(applied_delta <= CameraSystem.MAX_ROT_PER_FRAME + 1e-6) \
		.override_failure_message(
			"|yaw_delta| must not exceed MAX_ROT_PER_FRAME (PI) — got %f" % applied_delta
		) \
		.is_true()
	# Le clamp est exactement à PI puisque le delta naïf (-120) dépasse largement
	assert_float(_player.rotation.y) \
		.override_failure_message("Extreme flick yaw must clamp exactly to -PI") \
		.is_equal_approx(-PI, 1e-5)


func test_consecutive_extreme_flicks_apply_max_each_no_burst_accumulation() -> void:
	# Arrange — vérifier qu'aucun excès n'est accumulé entre events
	InputManager.mouse_sensitivity = 0.012
	_player.rotation.y = 0.0

	# Act — 5 flicks consécutifs Vector2(10000, 0) → 5× -PI exactement
	for i in range(5):
		_player.rotation.y = 0.0  # reset pour mesurer chaque flick indépendamment
		InputManager.mouse_motion.emit(Vector2(10000.0, 0.0))
		assert_float(_player.rotation.y) \
			.override_failure_message(
				"Flick #%d must clamp to -PI exactly (no leftover from prior burst)" % i
			) \
			.is_equal_approx(-PI, 1e-5)


# ---------------------------------------------------------------------------
# Edge cases (bonus)
# ---------------------------------------------------------------------------

func test_invert_y_toggle_without_motion_does_not_change_pitch() -> void:
	# Arrange — pitch initial fixé, invert_y false
	_camera_arm.rotation.x = 0.5
	InputManager.mouse_y_inverted = false

	# Act — toggle invert_y en live, AUCUNE motion émise
	InputManager.mouse_y_inverted = true

	# Assert — pitch inchangé (la lecture de invert_y se fait à l'event, pas en watch)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"Toggle invert_y without motion must not mutate pitch — got %f" % _camera_arm.rotation.x
		) \
		.is_equal_approx(0.5, 1e-6)

	# Sanity check : l'event suivant utilise bien la nouvelle valeur invert_y
	InputManager.mouse_sensitivity = 0.0022
	InputManager.mouse_motion.emit(Vector2(0.0, 100.0))
	# Avec invert=true : pitch_delta = -100 * 0.0022 * (-1.0) = +0.22 → 0.5 + 0.22 = 0.72
	assert_float(_camera_arm.rotation.x).is_equal_approx(0.72, TOLERANCE)


func test_zero_delta_does_not_change_rotation() -> void:
	# Arrange
	_player.rotation.y = 1.5
	_camera_arm.rotation.x = 0.3

	# Act
	InputManager.mouse_motion.emit(Vector2.ZERO)

	# Assert — aucune mutation
	assert_float(_player.rotation.y).is_equal_approx(1.5, 1e-6)
	assert_float(_camera_arm.rotation.x).is_equal_approx(0.3, 1e-6)
