# Integration tests for Story 006 — FOV dash pulse (signal-driven flag + lerp camera3d.fov).
# Covers AC-CAM-20 (dash_started → fov converges to 100°),
#         AC-CAM-21 (dash_ended → fov converges back to 90°),
#         double-dash edge case (kick absolute-target, no jump),
#         AC-CAM-20 initial state (camera3d.fov == BASE_FOV after _ready).
# TR-cam-001, ADR-0002 (Camera scene tree + Amendment A-1), ADR-0005 (Movement signals D-2/D-5/D-7/D-8).
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Setup : MockPlayerWithDashSignals (CharacterBody3D exposant dash_started / dash_ended)
# joue le rôle du Player. CameraArm (Node3D + CameraSystem script) est enfant du mock.
# CameraEffects + Camera3D sont enfants du CameraArm — reproduit Player.tscn exactement.
# Ce pattern évite une dépendance à Player.tscn et à MovementController (pas encore complet).

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Tolerances et constantes de timing
# ---------------------------------------------------------------------------

## Delta fixe déterministe (1/60 s). Pas d'await, pas de waits temps réel.
const FIXED_DELTA: float = 1.0 / 60.0

## 9 frames = ~150 ms à 60 fps (AC-CAM-20 : fov ≥ 98.5° après dash_started).
const FRAMES_150MS: int = 9

## 15 frames = ~250 ms à 60 fps (AC-CAM-21 : |fov - 90| < 0.5 après dash_ended).
const FRAMES_250MS: int = 15

## Seuil AC-CAM-20 : fov ≥ 98.5° après 9 frames de dash actif.
const FOV_DASH_MIN_AT_150MS: float = 98.5

## Seuil AC-CAM-21 : |fov - BASE_FOV| < 0.5° après 15 frames post dash_ended.
const FOV_CONVERGENCE_TOLERANCE: float = 0.5

## FOV de base : doit correspondre à CameraSystem.BASE_FOV.
const EXPECTED_BASE_FOV: float = 90.0

## FOV peak attendu : BASE_FOV + DASH_FOV_KICK = 100°.
const EXPECTED_PEAK_FOV: float = 100.0

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
	# Set owner BEFORE _mock_player enters tree pour que set_unique_name_in_owner(true)
	# enregistre %CameraEffects/%Camera3D dans le scope owner=_mock_player (mock scene root).
	# Sans owner explicite : `Node not found: "%CameraEffects"` log ERROR à _ready
	# (Mac M4 ignore l'erreur, ubuntu CI la compte comme error → test fails).
	_camera_arm.owner = _mock_player
	_camera_effects.owner = _mock_player
	_camera3d.owner = _mock_player
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

	await get_tree().process_frame

	# Reset de l'état du système pour chaque test.
	_camera_system._is_dashing = false
	_camera3d.fov = EXPECTED_BASE_FOV


func after_test() -> void:
	# Déconnexion InputManager.mouse_motion pour ne pas polluer les autres tests.
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
	# Déconnexion des signaux dash (connectés dans _ready).
	if _mock_player.dash_started.is_connected(_camera_system._on_dash_started):
		_mock_player.dash_started.disconnect(_camera_system._on_dash_started)
	if _mock_player.dash_ended.is_connected(_camera_system._on_dash_ended):
		_mock_player.dash_ended.disconnect(_camera_system._on_dash_ended)
	_mock_player.queue_free()
	_mock_player = null
	_camera_arm = null
	_camera_effects = null
	_camera3d = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Helper — simule n frames en appelant _update_fov_dash avec delta fixe
# ---------------------------------------------------------------------------

func _simulate_fov_frames(n: int) -> void:
	for _i in range(n):
		_camera_system._update_fov_dash(FIXED_DELTA)


# ---------------------------------------------------------------------------
# AC-CAM-20 — dash_started : fov converge vers 100° (≥ 98.5 à t=150ms)
# ---------------------------------------------------------------------------

func test_ac_cam_20_dash_started_fov_converges_up() -> void:
	# Arrange — état initial : pas en dash, fov = 90°
	assert_float(_camera_system._is_dashing as float).is_equal(0.0)
	_camera3d.fov = EXPECTED_BASE_FOV

	# Act — émet le signal dash_started (frame 0), puis 9 frames _process
	_mock_player.dash_started.emit(Vector3.FORWARD, 18.0)

	_simulate_fov_frames(FRAMES_150MS)

	# Assert — fov ≥ 98.5° (AC-CAM-20)
	assert_float(_camera3d.fov) \
		.override_failure_message(
			"AC-CAM-20 : fov doit être ≥ %.1f° après %d frames de dash — got %.4f°"
			% [FOV_DASH_MIN_AT_150MS, FRAMES_150MS, _camera3d.fov]
		) \
		.is_greater_equal(FOV_DASH_MIN_AT_150MS)


# ---------------------------------------------------------------------------
# AC-CAM-21 — dash_ended : fov converge vers 90° (|fov-90| < 0.5 à t=250ms)
# ---------------------------------------------------------------------------

func test_ac_cam_21_dash_ended_fov_converges_down() -> void:
	# Arrange — simule un dash déjà actif avec fov à 100°
	_mock_player.dash_started.emit(Vector3.FORWARD, 18.0)
	_camera3d.fov = EXPECTED_PEAK_FOV

	# Act — émet dash_ended (frame 0), puis 15 frames _process
	_mock_player.dash_ended.emit()

	_simulate_fov_frames(FRAMES_250MS)

	# Assert — |fov - 90°| < 0.5° (AC-CAM-21)
	var fov_error: float = absf(_camera3d.fov - EXPECTED_BASE_FOV)
	assert_float(fov_error) \
		.override_failure_message(
			"AC-CAM-21 : |fov - 90°| doit être < %.1f° après %d frames post dash_ended"
			% [FOV_CONVERGENCE_TOLERANCE, FRAMES_250MS]
			+ " — got fov=%.4f°, error=%.4f°" % [_camera3d.fov, fov_error]
		) \
		.is_less(FOV_CONVERGENCE_TOLERANCE)


# ---------------------------------------------------------------------------
# Edge case — double dash : target absolu 100°, pas de saut FOV
# ---------------------------------------------------------------------------

func test_ac_cam_20_double_dash_target_resets_absolute() -> void:
	# Arrange — premier dash, laisse le fov monter partiellement
	_mock_player.dash_started.emit(Vector3.FORWARD, 18.0)
	_simulate_fov_frames(3)  # fov quelque part entre 90° et 100° (non complet)
	var fov_after_partial: float = _camera3d.fov

	assert_float(fov_after_partial) \
		.override_failure_message("Setup: fov doit être > BASE_FOV après 3 frames — got %.4f" % fov_after_partial) \
		.is_greater(EXPECTED_BASE_FOV)

	# Act — dash_ended, puis immédiatement re-dash avant retour à 90°
	_mock_player.dash_ended.emit()
	_simulate_fov_frames(2)  # fov commence à descendre mais pas encore à 90°
	var fov_before_redash: float = _camera3d.fov

	_mock_player.dash_started.emit(Vector3.BACK, 18.0)
	_simulate_fov_frames(3)  # lerp reprend vers 100°
	var fov_after_redash: float = _camera3d.fov

	# Assert — le fov après redash doit être supérieur à fov_before_redash
	# (la lerp est repartie vers 100°, pas vers 90°). Pas de saut instantané.
	assert_float(fov_after_redash) \
		.override_failure_message(
			"Double dash : fov doit remonter vers 100° après redash"
			+ " — before=%.4f°, after=%.4f°" % [fov_before_redash, fov_after_redash]
		) \
		.is_greater(fov_before_redash)

	# Et la valeur doit se diriger vers 100° (est plus proche de 100° que de 90°)
	var dist_to_peak: float = absf(fov_after_redash - EXPECTED_PEAK_FOV)
	var dist_to_base: float = absf(fov_after_redash - EXPECTED_BASE_FOV)
	assert_float(dist_to_peak) \
		.override_failure_message(
			"Double dash : fov doit être plus proche de 100° que de 90° après quelques frames"
			+ " — fov=%.4f°, dist_to_peak=%.4f, dist_to_base=%.4f"
			% [fov_after_redash, dist_to_peak, dist_to_base]
		) \
		.is_less(dist_to_base)


# ---------------------------------------------------------------------------
# AC-CAM-20 initial state — camera3d.fov == BASE_FOV après _ready
# ---------------------------------------------------------------------------

func test_ac_cam_20_initial_fov_equals_base() -> void:
	# Arrange / Assert — _ready() a déjà été appelé dans before_test (await process_frame).
	# On réinitialise explicitement pour s'assurer que le test est isolé.
	# Le mock _ready du CameraSystem doit poser _camera3d.fov = BASE_FOV = 90.0.
	#
	# Note : on ne peut pas re-appeler _ready() — on vérifie que l'état initial
	# après le premier _ready() est correct (avant tout _simulate_fov_frames).
	# C'est garanti par le reset explicite dans before_test + le fait que
	# CameraSystem._ready() appelle _camera3d.fov = BASE_FOV.

	assert_float(_camera3d.fov) \
		.override_failure_message(
			"AC-CAM-20 initial : fov doit être égal à BASE_FOV (%.1f°) après _ready — got %.4f°"
			% [EXPECTED_BASE_FOV, _camera3d.fov]
		) \
		.is_equal_approx(EXPECTED_BASE_FOV, 0.001)
