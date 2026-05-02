# Integration tests for Story 007 — Shake additif + wall_jump kick.
# Couvre AC-CAM-30 (shake decay 250 ms < 5%), AC-CAM-31 (wall_jumped consume +
# direction sign + assignation rotation), AC-CAM-32 (limit_length cap 0.2 rad).
# TR-cam-001, ADR-0002 (Risk 3 : assignation rotation, pas +=) + ADR-0005
# (D-2 wall_jumped(Vector3, Vector3) ; D-5 SYNC ; D-7 no Movement mutation ; D-8 idempotent).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Setup : MockPlayerWithDashSignals (CharacterBody3D exposant dash_started /
# dash_ended / wall_jumped) joue le rôle du Player. Pattern identique à story-006
# pour reproduire Player.tscn (CameraArm enfant, CameraEffects + Camera3D dans CameraArm).

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Tolerances et constantes de timing
# ---------------------------------------------------------------------------

## Delta fixe déterministe (1/60 s). Pas d'await, pas de waits temps réel.
const FIXED_DELTA: float = 1.0 / 60.0

## 15 frames = ~250 ms à 60 fps (AC-CAM-30 : retour shake < 5% magnitude initiale).
const FRAMES_250MS: int = 15

## Magnitude initiale du shake roll injectée (rad). Doit matcher
## CameraSystem.WALL_JUMP_KICK_MAGNITUDE pour AC-CAM-30 (vérification realiste).
const SHAKE_ROLL_INIT: float = 0.05

## Seuil AC-CAM-30 : 5% de SHAKE_ROLL_INIT après 250 ms.
const SHAKE_DECAY_THRESHOLD: float = 0.05 * 0.05  # 0.0025 rad

## Cap absolu — doit matcher CameraSystem.MAX_SHAKE_MAGNITUDE.
const EXPECTED_MAX_SHAKE: float = 0.2

## Tolerance pour comparaison floating-point sur _shake_offset (rad).
const SHAKE_TOLERANCE: float = 0.0005

## Tolerance pour cap limit_length (rad).
const LIMIT_LENGTH_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Variables de test
# ---------------------------------------------------------------------------

var _mock_player: MockPlayerWithDashSignals = null
var _camera_arm: Node3D = null
var _camera_effects: Node3D = null
var _camera3d: Camera3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	_mock_player = MockPlayerWithDashSignals.new()

	_camera_arm = Node3D.new()
	_camera_arm.set_script(preload("res://src/gameplay/camera/camera_system.gd"))
	_camera_arm.set_unique_name_in_owner(true)

	_camera_effects = Node3D.new()
	_camera_effects.name = "CameraEffects"
	_camera_effects.set_unique_name_in_owner(true)

	_camera3d = Camera3D.new()
	_camera3d.name = "Camera3D"
	_camera3d.set_unique_name_in_owner(true)

	_camera_effects.add_child(_camera3d)
	_camera_arm.add_child(_camera_effects)
	_mock_player.add_child(_camera_arm)
	add_child(_mock_player)

	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm does not have CameraSystem script") \
		.is_not_null()

	# TD-005 manual injection AVANT process_frame — pattern parity story-008.
	_camera_system._camera_effects = _camera_effects
	_camera_system._camera3d = _camera3d
	_camera_system._player = _mock_player
	if _camera_system._overlay == null:
		_camera_system._setup_overlay()

	# TD-005 connexions signaux que _ready() aurait faites — early-return skip
	# si _camera_effects == null à l'entrée. Pattern parity story-008.
	if not _mock_player.dash_started.is_connected(_camera_system._on_dash_started):
		_mock_player.dash_started.connect(_camera_system._on_dash_started)
	if not _mock_player.dash_ended.is_connected(_camera_system._on_dash_ended):
		_mock_player.dash_ended.connect(_camera_system._on_dash_ended)
	if not _mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped):
		_mock_player.wall_jumped.connect(_camera_system._on_wall_jumped)

	await get_tree().process_frame

	# Reset état pour isolation des tests.
	_camera_system._shake_offset = Vector3.ZERO
	_camera3d.rotation = Vector3.ZERO


func after_test() -> void:
	# Déconnexion explicite : Godot auto-disconnect au queue_free, mais on évite
	# toute fuite d'event entre tests (cleanup défensif).
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
	if _mock_player.dash_started.is_connected(_camera_system._on_dash_started):
		_mock_player.dash_started.disconnect(_camera_system._on_dash_started)
	if _mock_player.dash_ended.is_connected(_camera_system._on_dash_ended):
		_mock_player.dash_ended.disconnect(_camera_system._on_dash_ended)
	if _mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped):
		_mock_player.wall_jumped.disconnect(_camera_system._on_wall_jumped)
	_mock_player.queue_free()
	_mock_player = null
	_camera_arm = null
	_camera_effects = null
	_camera3d = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Helper — simule n frames en appelant _update_shake avec delta fixe
# ---------------------------------------------------------------------------

func _simulate_shake_frames(n: int) -> void:
	for _i in range(n):
		_camera_system._update_shake(FIXED_DELTA)


# ---------------------------------------------------------------------------
# AC-CAM-30 — shake decay : retour < 5% magnitude initiale en ~250 ms
# ---------------------------------------------------------------------------

func test_ac_cam_30_shake_decay_returns_under_5_percent_at_250ms() -> void:
	# Arrange — état initial : shake = 0
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message("Setup: _shake_offset doit être zéro avant injection") \
		.is_equal(Vector3.ZERO)

	# Act — frame 0 : injecte shake roll, puis 15 frames de _update_shake
	_camera_system.add_shake_roll(SHAKE_ROLL_INIT)
	# Vérifie injection avant decay : _shake_offset.z ≈ +SHAKE_ROLL_INIT
	assert_float(_camera_system._shake_offset.z) \
		.override_failure_message(
			"AC-CAM-30 setup : _shake_offset.z post add_shake_roll doit être ≈ %.4f — got %.6f"
			% [SHAKE_ROLL_INIT, _camera_system._shake_offset.z]
		) \
		.is_equal_approx(SHAKE_ROLL_INIT, SHAKE_TOLERANCE)

	_simulate_shake_frames(FRAMES_250MS)

	# Assert — |_shake_offset.z| < 5% magnitude initiale (AC-CAM-30)
	assert_float(absf(_camera_system._shake_offset.z)) \
		.override_failure_message(
			"AC-CAM-30 : |_shake_offset.z| doit être < %.6f rad (5%% × %.4f) après %d frames — got %.6f"
			% [SHAKE_DECAY_THRESHOLD, SHAKE_ROLL_INIT, FRAMES_250MS, absf(_camera_system._shake_offset.z)]
		) \
		.is_less(SHAKE_DECAY_THRESHOLD)


# ---------------------------------------------------------------------------
# AC-CAM-30 edge — add_shake_roll(0.0) : aucun effet
# ---------------------------------------------------------------------------

func test_ac_cam_30_add_shake_roll_zero_has_no_effect() -> void:
	# Arrange
	_camera_system._shake_offset = Vector3.ZERO

	# Act
	_camera_system.add_shake_roll(0.0)

	# Assert — _shake_offset reste à zéro
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message(
			"add_shake_roll(0.0) ne doit pas changer _shake_offset — got %s"
			% str(_camera_system._shake_offset)
		) \
		.is_equal(Vector3.ZERO)


# ---------------------------------------------------------------------------
# AC-CAM-31 — wall_jumped (mur à gauche, normal=+x) : direction négative
# ---------------------------------------------------------------------------

func test_ac_cam_31_wall_jumped_wall_left_kicks_negative() -> void:
	# Arrange — _camera_arm rotation par défaut (basis.x = (1,0,0), -basis.x = (-1,0,0))
	# wall_normal=(1,0,0) → dot(-basis.x) = 1 * -1 = -1 → sign = -1 → kick négatif
	_camera_system._shake_offset = Vector3.ZERO

	# Act — émet wall_jumped avec mur à gauche (normal pointe +x vers le joueur)
	_mock_player.wall_jumped.emit(Vector3(1, 0, 0), Vector3(10, 10, 0))

	# Assert — _shake_offset.z ≈ -WALL_JUMP_KICK_MAGNITUDE (-0.05)
	assert_float(_camera_system._shake_offset.z) \
		.override_failure_message(
			"AC-CAM-31 : wall_normal=(+1,0,0) → kick devrait être -%.4f — got %.6f"
			% [SHAKE_ROLL_INIT, _camera_system._shake_offset.z]
		) \
		.is_equal_approx(-SHAKE_ROLL_INIT, SHAKE_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-31 edge — wall_jumped (mur à droite, normal=-x) : direction positive
# ---------------------------------------------------------------------------

func test_ac_cam_31_wall_jumped_wall_right_kicks_positive() -> void:
	# Arrange
	_camera_system._shake_offset = Vector3.ZERO

	# Act — wall_normal=(-1,0,0) → dot(-basis.x) = -1 * -1 = +1 → sign = +1
	_mock_player.wall_jumped.emit(Vector3(-1, 0, 0), Vector3(-10, 10, 0))

	# Assert — _shake_offset.z ≈ +WALL_JUMP_KICK_MAGNITUDE (+0.05)
	assert_float(_camera_system._shake_offset.z) \
		.override_failure_message(
			"AC-CAM-31 : wall_normal=(-1,0,0) → kick devrait être +%.4f — got %.6f"
			% [SHAKE_ROLL_INIT, _camera_system._shake_offset.z]
		) \
		.is_equal_approx(SHAKE_ROLL_INIT, SHAKE_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-31 edge — wall_jumped perpendiculaire (dot==0 exact) : fallback +1
# ---------------------------------------------------------------------------

func test_ac_cam_31_wall_jumped_perpendicular_uses_fallback_positive() -> void:
	# Arrange — wall en avant : normal=(0,0,1), -basis.x=(-1,0,0) → dot=0 exact
	# _sign_with_fallback(0) = +1 → kick positif (pas zéro silencieux)
	_camera_system._shake_offset = Vector3.ZERO

	# Act
	_mock_player.wall_jumped.emit(Vector3(0, 0, 1), Vector3(0, 10, -10))

	# Assert — _shake_offset.z ≈ +WALL_JUMP_KICK_MAGNITUDE (fallback +1)
	assert_float(_camera_system._shake_offset.z) \
		.override_failure_message(
			"AC-CAM-31 : wall perpendiculaire (dot=0) → fallback +1 → kick devrait être +%.4f — got %.6f"
			% [SHAKE_ROLL_INIT, _camera_system._shake_offset.z]
		) \
		.is_equal_approx(SHAKE_ROLL_INIT, SHAKE_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-31 — assignation : camera3d.rotation overwrite, pas cumul
# ---------------------------------------------------------------------------

func test_ac_cam_31_camera3d_rotation_assigned_not_added() -> void:
	# Arrange — camera3d.rotation pré-existant non-zéro (état "polluté")
	_camera3d.rotation = Vector3(0.1, 0.1, 0.1)
	_camera_system._shake_offset = Vector3.ZERO

	# Act — émet wall_jumped (mur à droite → kick +0.05) puis 1 frame _update_shake
	_mock_player.wall_jumped.emit(Vector3(-1, 0, 0), Vector3(-10, 10, 0))
	_camera_system._update_shake(FIXED_DELTA)

	# Assert — camera3d.rotation == _shake_offset (assignation, pas Vector3(0.1,0.1,0.1)+offset)
	# Si l'implémentation utilisait += au lieu de =, on verrait rotation ≈ (0.1, 0.1, 0.1+kick).
	# Avec assignation, rotation = _shake_offset (sans rapport à la valeur initiale).
	assert_vector(_camera3d.rotation) \
		.override_failure_message(
			"AC-CAM-31 : camera3d.rotation doit être assigné à _shake_offset (pas cumul) — "
			+ "got rotation=%s, expected ~_shake_offset=%s"
			% [str(_camera3d.rotation), str(_camera_system._shake_offset)]
		) \
		.is_equal_approx(_camera_system._shake_offset, Vector3.ONE * LIMIT_LENGTH_TOLERANCE)

	# Assert complémentaire — rotation.x et rotation.y restent ≈ 0 (preuve de l'overwrite,
	# pas du cumul avec la valeur initiale 0.1).
	assert_float(absf(_camera3d.rotation.x)) \
		.override_failure_message(
			"AC-CAM-31 : si assignation, rotation.x doit être ≈ 0 (pas 0.1 cumulé) — got %.6f"
			% _camera3d.rotation.x
		) \
		.is_less(LIMIT_LENGTH_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-32 — limit_length cap : 10× add_shake_roll(0.05) → length() ≈ 0.2
# ---------------------------------------------------------------------------

func test_ac_cam_32_limit_length_caps_at_max_magnitude() -> void:
	# Arrange
	_camera_system._shake_offset = Vector3.ZERO

	# Act — 10× add_shake_roll(0.05) → raw sum 0.5, cap à 0.2
	for _i in range(10):
		_camera_system.add_shake_roll(0.05)

	# Assert — length() == MAX_SHAKE_MAGNITUDE (0.2) à la tolérance flottante près
	assert_float(_camera_system._shake_offset.length()) \
		.override_failure_message(
			"AC-CAM-32 : length() doit être cappé à %.4f rad — got %.6f (raw sum aurait été 0.5)"
			% [EXPECTED_MAX_SHAKE, _camera_system._shake_offset.length()]
		) \
		.is_equal_approx(EXPECTED_MAX_SHAKE, LIMIT_LENGTH_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-32 — sous-cap : 3× add_shake_roll(0.05) → length() == 0.15 (pas cappé)
# ---------------------------------------------------------------------------

func test_ac_cam_32_no_cap_under_max_magnitude() -> void:
	# Arrange
	_camera_system._shake_offset = Vector3.ZERO

	# Act — 3× add_shake_roll(0.05) → raw sum 0.15, sous le cap 0.2
	for _i in range(3):
		_camera_system.add_shake_roll(0.05)

	# Assert — length() == 0.15 (pas modifié par limit_length puisque sous le cap)
	assert_float(_camera_system._shake_offset.length()) \
		.override_failure_message(
			"AC-CAM-32 : 3× 0.05 → length() doit être ≈ 0.15 (sous cap 0.2) — got %.6f"
			% _camera_system._shake_offset.length()
		) \
		.is_equal_approx(0.15, LIMIT_LENGTH_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-32 — add_shake mixte (yaw + roll) : clamp dans la même direction
# ---------------------------------------------------------------------------

func test_ac_cam_32_mixed_axes_clamp_preserves_direction() -> void:
	# Arrange
	_camera_system._shake_offset = Vector3.ZERO

	# Act — Vector3(0, 0.15, 0.15) : norme ≈ 0.212 (au-dessus du cap 0.2)
	# limit_length doit ramener à 0.2 dans la MÊME direction (ratio préservé)
	_camera_system.add_shake(Vector3(0.0, 0.15, 0.15))

	# Assert — length() ≈ 0.2 ET ratio y/z préservé (0.15/0.15 == 1.0)
	assert_float(_camera_system._shake_offset.length()) \
		.override_failure_message(
			"AC-CAM-32 mix : length() doit être cappé à %.4f — got %.6f"
			% [EXPECTED_MAX_SHAKE, _camera_system._shake_offset.length()]
		) \
		.is_equal_approx(EXPECTED_MAX_SHAKE, LIMIT_LENGTH_TOLERANCE)

	# Ratio y/z doit rester ≈ 1.0 (direction préservée par limit_length).
	var ratio: float = _camera_system._shake_offset.y / _camera_system._shake_offset.z
	assert_float(ratio) \
		.override_failure_message(
			"AC-CAM-32 mix : limit_length doit préserver direction (y/z=1.0) — got y=%.6f, z=%.6f, ratio=%.6f"
			% [_camera_system._shake_offset.y, _camera_system._shake_offset.z, ratio]
		) \
		.is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------------------
# Initial state — _shake_offset zéro après _ready, camera3d.rotation zéro
# ---------------------------------------------------------------------------

func test_initial_state_shake_offset_and_camera_rotation_zero() -> void:
	# Setup before_test reset _shake_offset et _camera3d.rotation explicitement.
	# On vérifie que l'état initial post-_ready est cohérent.
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message(
			"Initial state : _shake_offset doit être zéro après _ready — got %s"
			% str(_camera_system._shake_offset)
		) \
		.is_equal(Vector3.ZERO)

	assert_vector(_camera3d.rotation) \
		.override_failure_message(
			"Initial state : camera3d.rotation doit être zéro avant _update_shake — got %s"
			% str(_camera3d.rotation)
		) \
		.is_equal(Vector3.ZERO)
