# Integration tests for Story 011 — _exit_tree cleanup + NaN safeguard + focus-loss behavior.
# Couvre AC-CAM-63 (disconnect explicite _exit_tree symétrie _ready),
#         AC-CAM-64 (focus-loss pendant wall-run → tilt continue sans glitch),
#         AC-CAM-NAN-1 (NaN sur camera_effects.rotation.z → reset 0 + push_warning).
#
# GDD Rule 16 (symétrie connect ↔ disconnect) ;
# ADR-0002 Amendment A-1 (signal-driven consumption) ;
# ADR-0004 D-5 (focus-loss gate via InputManager.enabled).
#
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Pattern : même setup manuel que story_008/009 (injection @onready vars + connexions
# explicites) — `%CameraEffects` ne résout pas sans scene owner dans ce harness.

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

## Angle de tilt full wall-run (miroir CameraSystem.WALL_RUN_TILT_ANGLE).
const EXPECTED_TILT_ANGLE: float = 0.35

## Tolérance flottant pour comparaisons de lerp.
const TILT_TOLERANCE: float = 0.001

## Vitesse lerp tilt (miroir CameraSystem.TILT_LERP_SPEED) — pour simuler convergence.
const TILT_LERP_SPEED: float = 12.0

## Delta standard 60 fps.
const DELTA_60FPS: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Variables de test
# ---------------------------------------------------------------------------

var _mock_player: MockPlayerWithDashSignals = null
var _camera_arm: Node3D = null
var _camera_effects: Node3D = null
var _camera3d: Camera3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Setup / teardown — pattern parity story_008/009
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
	await get_tree().process_frame

	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm does not have CameraSystem script") \
		.is_not_null()

	# Pattern test parity story_008/009 : `%CameraEffects` ne résout pas dans
	# le test setup (pas de scene owner), donc les @onready vars sont null et
	# l'assert dans `_ready()` plante AVANT que `_setup_overlay()` puisse tourner.
	# Manual injection ici garantit que tous les tests AC-CAM-63/64/NAN-1 trouvent
	# un état valide. En production runtime (Player.tscn complet avec scene owner),
	# `%CameraEffects` résout correctement et tout cela est inutile.
	_camera_system._camera_effects = _camera_effects
	_camera_system._camera3d = _camera3d
	_camera_system._player = _mock_player
	if _camera_system._overlay == null:
		_camera_system._setup_overlay()
	# Init explicite FOV (normalement fait par `_ready()` ligne 223).
	_camera3d.fov = 90.0
	# Connexions signaux qui n'ont pas pu tourner dans _ready() faute d'injection.
	# InputManager connections :
	if not InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.connect(_camera_system._on_mouse_motion)
	# Movement signals :
	if not _mock_player.dash_started.is_connected(_camera_system._on_dash_started):
		_mock_player.dash_started.connect(_camera_system._on_dash_started)
	if not _mock_player.dash_ended.is_connected(_camera_system._on_dash_ended):
		_mock_player.dash_ended.connect(_camera_system._on_dash_ended)
	if not _mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped):
		_mock_player.wall_jumped.connect(_camera_system._on_wall_jumped)
	if not _mock_player.died.is_connected(_camera_system._on_died):
		_mock_player.died.connect(_camera_system._on_died)
	if not _mock_player.respawned.is_connected(_camera_system._on_respawned):
		_mock_player.respawned.connect(_camera_system._on_respawned)


func after_test() -> void:
	# Cleanup défensif InputManager.enabled FIRST — un test AC-CAM-64 qui échoue
	# avant son cleanup inline laisserait enabled=false, corrompant les tests suivants.
	# Filet de sécurité pour isolation (coding-standards : "each test sets up and
	# tears down its own state").
	if not InputManager.enabled:
		InputManager.release_enable_request(self)

	# Cleanup défensif signaux — déconnecte tout signal encore actif pour éviter leaks.
	if _camera_system != null and is_instance_valid(_camera_system):
		if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
			InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
	if _mock_player != null and is_instance_valid(_mock_player) and _camera_system != null:
		if _mock_player.dash_started.is_connected(_camera_system._on_dash_started):
			_mock_player.dash_started.disconnect(_camera_system._on_dash_started)
		if _mock_player.dash_ended.is_connected(_camera_system._on_dash_ended):
			_mock_player.dash_ended.disconnect(_camera_system._on_dash_ended)
		if _mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped):
			_mock_player.wall_jumped.disconnect(_camera_system._on_wall_jumped)
		if _mock_player.died.is_connected(_camera_system._on_died):
			_mock_player.died.disconnect(_camera_system._on_died)
		if _mock_player.respawned.is_connected(_camera_system._on_respawned):
			_mock_player.respawned.disconnect(_camera_system._on_respawned)
	if _mock_player != null:
		_mock_player.queue_free()
	_mock_player = null
	_camera_arm = null
	_camera_effects = null
	_camera3d = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-63 — _exit_tree disconnect : aucun "Signal target was freed" au respawn
# ---------------------------------------------------------------------------

func test_ac_cam_63_exit_tree_disconnects_input_manager_signal() -> void:
	# Arrange — connexion InputManager.mouse_motion confirmée.
	assert_bool(InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion)) \
		.override_failure_message(
			"Setup AC-CAM-63 : mouse_motion doit être connecté avant _exit_tree"
		) \
		.is_true()

	# Act — simuler _exit_tree en l'appelant directement (évite queue_free + await
	# qui rendrait _camera_system inaccessible post-free).
	_camera_system._exit_tree()

	# Assert — signal déconnecté.
	assert_bool(InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion)) \
		.override_failure_message(
			"AC-CAM-63 : mouse_motion doit être déconnecté après _exit_tree()"
		) \
		.is_false()


func test_ac_cam_63_exit_tree_disconnects_all_player_signals() -> void:
	# Arrange — toutes les connexions player confirmées.
	assert_bool(_mock_player.dash_started.is_connected(_camera_system._on_dash_started)) \
		.override_failure_message("Setup : dash_started doit être connecté") \
		.is_true()
	assert_bool(_mock_player.dash_ended.is_connected(_camera_system._on_dash_ended)) \
		.override_failure_message("Setup : dash_ended doit être connecté") \
		.is_true()
	assert_bool(_mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped)) \
		.override_failure_message("Setup : wall_jumped doit être connecté") \
		.is_true()
	assert_bool(_mock_player.died.is_connected(_camera_system._on_died)) \
		.override_failure_message("Setup : died doit être connecté") \
		.is_true()
	assert_bool(_mock_player.respawned.is_connected(_camera_system._on_respawned)) \
		.override_failure_message("Setup : respawned doit être connecté") \
		.is_true()

	# Act — simule _exit_tree en injectant un parent valide (le test harness a le
	# _mock_player comme parent de _camera_arm, donc get_parent() renvoie _mock_player).
	_camera_system._exit_tree()

	# Assert — tous les signaux player déconnectés.
	assert_bool(_mock_player.dash_started.is_connected(_camera_system._on_dash_started)) \
		.override_failure_message("AC-CAM-63 : dash_started doit être déconnecté") \
		.is_false()
	assert_bool(_mock_player.dash_ended.is_connected(_camera_system._on_dash_ended)) \
		.override_failure_message("AC-CAM-63 : dash_ended doit être déconnecté") \
		.is_false()
	assert_bool(_mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped)) \
		.override_failure_message("AC-CAM-63 : wall_jumped doit être déconnecté") \
		.is_false()
	assert_bool(_mock_player.died.is_connected(_camera_system._on_died)) \
		.override_failure_message("AC-CAM-63 : died doit être déconnecté") \
		.is_false()
	assert_bool(_mock_player.respawned.is_connected(_camera_system._on_respawned)) \
		.override_failure_message("AC-CAM-63 : respawned doit être déconnecté") \
		.is_false()


func test_ac_cam_63_exit_tree_idempotent_double_call() -> void:
	# Arrange — premier appel déconnecte tout.
	_camera_system._exit_tree()

	# Act — second appel sur des signaux déjà déconnectés ne doit pas erreur.
	# (Les guards is_connected empêchent le disconnect d'un signal non-connecté.)
	# Si le test passe sans crash GDScript "Attempt to disconnect...", les guards fonctionnent.
	_camera_system._exit_tree()

	# Assert — aucun signal connecté (double appel = no-op propre).
	assert_bool(InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion)) \
		.override_failure_message("AC-CAM-63 idempotence : mouse_motion doit rester déconnecté") \
		.is_false()
	assert_bool(_mock_player.wall_jumped.is_connected(_camera_system._on_wall_jumped)) \
		.override_failure_message("AC-CAM-63 idempotence : wall_jumped doit rester déconnecté") \
		.is_false()


func test_ac_cam_63_no_stale_signal_after_player_respawn() -> void:
	# Arrange — simule un cycle complet died → respawned (Camera en vie).
	_mock_player.died.emit()
	_mock_player.respawned.emit(Vector3.ZERO)

	# Vérification : _exit_tree() exécuté (simule free Player).
	_camera_system._exit_tree()

	# Assert — aucun signal résiduel vers les handlers Camera sur l'instance _mock_player.
	# Si un signal était connecté, queue_free de _mock_player au after_test lèverait
	# "Signal target was freed" à la prochaine émission. Cette assertion statique
	# couvre le cas structurellement sans attendre l'émission post-free.
	assert_bool(_mock_player.died.is_connected(_camera_system._on_died)) \
		.override_failure_message(
			"AC-CAM-63 : aucun handler died résiduel ne doit rester après _exit_tree"
		) \
		.is_false()
	assert_bool(_mock_player.respawned.is_connected(_camera_system._on_respawned)) \
		.override_failure_message(
			"AC-CAM-63 : aucun handler respawned résiduel ne doit rester après _exit_tree"
		) \
		.is_false()


# ---------------------------------------------------------------------------
# AC-CAM-64 — focus-loss pendant wall-run : tilt continue sans glitch
# ---------------------------------------------------------------------------

func test_ac_cam_64_tilt_converges_while_input_disabled() -> void:
	# Arrange — tilt à 0 (départ), player en wall-run droite (wall_normal=-1,0,0).
	# wall_side = sign((-wall_normal).dot(player.basis.x)) = sign((1,0,0).(1,0,0)) = +1
	# target_roll = WALL_RUN_TILT_ANGLE * 1 = 0.35
	_camera_effects.rotation.z = 0.0
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)

	# Act — simule focus-out : InputManager désactivé.
	InputManager.request_disable(self)
	assert_bool(InputManager.enabled) \
		.override_failure_message("Setup AC-CAM-64 : InputManager.enabled doit être false après request_disable") \
		.is_false()

	# Simule plusieurs frames _process pendant focus-out.
	# On appelle _update_tilt_wall_run directement car _process est cosmétique
	# et non trigué automatiquement dans le harness sans scene running.
	var tilt_after_frames: float = _camera_effects.rotation.z
	for _i in range(10):
		_camera_system._safeguard_rotation()
		_camera_system._update_tilt_wall_run(DELTA_60FPS)
		tilt_after_frames = _camera_effects.rotation.z

	# Assert — tilt a convergé vers 0.35 (lerp depuis 0 vers 0.35 en 10 frames à 60 fps).
	# Après 10 frames : lerp factor = min(12 * 1/60, 1) ≈ 0.2 par frame.
	# Valeur approx : 0.35 * (1 - (1-0.2)^10) ≈ 0.35 * 0.893 ≈ 0.312
	# On vérifie simplement que la convergence est en cours (> 0) sans glitch saut.
	assert_float(tilt_after_frames) \
		.override_failure_message(
			"AC-CAM-64 : tilt doit converger (> 0) pendant focus-out — got %.6f" % tilt_after_frames
		) \
		.is_greater(0.0)
	assert_float(tilt_after_frames) \
		.override_failure_message(
			"AC-CAM-64 : tilt ne doit pas dépasser WALL_RUN_TILT_ANGLE — got %.6f" % tilt_after_frames
		) \
		.is_less_equal(EXPECTED_TILT_ANGLE + TILT_TOLERANCE)

	# Cleanup — restore InputManager.
	InputManager.release_enable_request(self)
	assert_bool(InputManager.enabled) \
		.override_failure_message("Teardown AC-CAM-64 : InputManager.enabled doit revenir true") \
		.is_true()


func test_ac_cam_64_tilt_continues_convergence_after_focus_restore() -> void:
	# Arrange — tilt à 0.1 (mi-chemin), player en wall-run, focus coupé.
	_camera_effects.rotation.z = 0.1
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)
	InputManager.request_disable(self)

	# Act pendant focus-out — avance convergence 5 frames.
	for _i in range(5):
		_camera_system._update_tilt_wall_run(DELTA_60FPS)
	var tilt_at_focus_out: float = _camera_effects.rotation.z

	# Restore focus.
	InputManager.release_enable_request(self)

	# Act pendant focus-in — 5 frames supplémentaires.
	for _i in range(5):
		_camera_system._update_tilt_wall_run(DELTA_60FPS)
	var tilt_after_focus_in: float = _camera_effects.rotation.z

	# Assert — tilt continue de progresser (pas de jump / reset) dans les deux états.
	assert_float(tilt_after_focus_in) \
		.override_failure_message(
			"AC-CAM-64 : tilt doit progresser après focus restore (%.4f → %.4f)" \
			% [tilt_at_focus_out, tilt_after_focus_in]
		) \
		.is_greater_equal(tilt_at_focus_out - TILT_TOLERANCE)

	# Cleanup.
	if not InputManager.enabled:
		InputManager.release_enable_request(self)


func test_ac_cam_64_tilt_no_glitch_on_focus_restore_with_wall_run_active() -> void:
	# Arrange — tilt full (tilt = WALL_RUN_TILT_ANGLE), focus-out brève.
	_camera_effects.rotation.z = EXPECTED_TILT_ANGLE
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)

	InputManager.request_disable(self)

	# 1 seul frame _process pendant focus-out (simule 1 frame glitch potentiel).
	_camera_system._safeguard_rotation()
	_camera_system._update_tilt_wall_run(DELTA_60FPS)

	var tilt_during_focus_out: float = _camera_effects.rotation.z

	InputManager.release_enable_request(self)

	# 1 frame après focus-in.
	_camera_system._safeguard_rotation()
	_camera_system._update_tilt_wall_run(DELTA_60FPS)

	var tilt_after_focus_in: float = _camera_effects.rotation.z

	# Assert — pas de saut brutal (glitch > 1 frame) : la différence entre
	# tilt_during_focus_out et tilt_after_focus_in doit être ≤ lerp max d'1 frame.
	# Max variation 1 frame = WALL_RUN_TILT_ANGLE * lerp_factor = 0.35 * 0.2 = 0.07
	var delta_tilt: float = abs(tilt_after_focus_in - tilt_during_focus_out)
	assert_float(delta_tilt) \
		.override_failure_message(
			"AC-CAM-64 : delta tilt entre focus-out et focus-in doit être ≤ 1 frame lerp (%.4f) — got %.6f"
			% [EXPECTED_TILT_ANGLE * TILT_LERP_SPEED * DELTA_60FPS, delta_tilt]
		) \
		.is_less_equal(EXPECTED_TILT_ANGLE * TILT_LERP_SPEED * DELTA_60FPS + TILT_TOLERANCE)

	# Cleanup.
	if not InputManager.enabled:
		InputManager.release_enable_request(self)


# ---------------------------------------------------------------------------
# AC-CAM-NAN-1 — NaN sur camera_effects.rotation.z → reset 0 + push_warning
# ---------------------------------------------------------------------------

func test_ac_cam_nan_1_nan_rotation_reset_to_zero() -> void:
	# Arrange — injecte NaN sur rotation.z.
	_camera_effects.rotation = Vector3(0.0, 0.0, NAN)
	assert_bool(not is_finite(_camera_effects.rotation.z)) \
		.override_failure_message("Setup AC-CAM-NAN-1 : rotation.z doit être NaN avant _process") \
		.is_true()

	# Act — appel direct _safeguard_rotation (chemin appelé en début de _process).
	_camera_system._safeguard_rotation()

	# Assert — reset à 0.
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-NAN-1 : rotation.z doit être reset à 0.0 — got %s" % str(_camera_effects.rotation.z)
		) \
		.is_equal_approx(0.0, TILT_TOLERANCE)


func test_ac_cam_nan_1_inf_rotation_reset_to_zero() -> void:
	# Arrange — INF positif (même traitement que NaN via is_finite).
	_camera_effects.rotation = Vector3(0.0, 0.0, INF)

	# Act.
	_camera_system._safeguard_rotation()

	# Assert — reset à 0.
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-NAN-1 (INF) : rotation.z doit être reset à 0.0 — got %s" % str(_camera_effects.rotation.z)
		) \
		.is_equal_approx(0.0, TILT_TOLERANCE)


func test_ac_cam_nan_1_neg_inf_rotation_reset_to_zero() -> void:
	# Arrange — INF négatif.
	_camera_effects.rotation = Vector3(0.0, 0.0, -INF)

	# Act.
	_camera_system._safeguard_rotation()

	# Assert.
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-NAN-1 (-INF) : rotation.z doit être reset à 0.0 — got %s" % str(_camera_effects.rotation.z)
		) \
		.is_equal_approx(0.0, TILT_TOLERANCE)


func test_ac_cam_nan_1_normal_rotation_not_modified() -> void:
	# Arrange — valeur normale (pas de NaN).
	_camera_effects.rotation.z = 0.25

	# Act.
	_camera_system._safeguard_rotation()

	# Assert — valeur non touchée par le safeguard.
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-NAN-1 : rotation.z normale (0.25) ne doit PAS être modifiée — got %.6f"
			% _camera_effects.rotation.z
		) \
		.is_equal_approx(0.25, TILT_TOLERANCE)


func test_ac_cam_nan_1_process_frame_with_nan_resets_before_tilt_lerp() -> void:
	# Arrange — NaN + player en wall-run (target_roll = 0.35).
	_camera_effects.rotation = Vector3(0.0, 0.0, NAN)
	_mock_player.wall_normal = Vector3(-1.0, 0.0, 0.0)

	# Act — simule un _process complet.
	_camera_system._safeguard_rotation()
	_camera_system._update_tilt_wall_run(DELTA_60FPS)

	# Assert — après reset + lerp, z doit être fini et positif (convergence vers 0.35).
	assert_bool(is_finite(_camera_effects.rotation.z)) \
		.override_failure_message(
			"AC-CAM-NAN-1 : après _process, rotation.z doit être fini — got %s"
			% str(_camera_effects.rotation.z)
		) \
		.is_true()
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-NAN-1 : après reset + lerp, z doit être > 0 (convergence vers 0.35) — got %.6f"
			% _camera_effects.rotation.z
		) \
		.is_greater(0.0)
