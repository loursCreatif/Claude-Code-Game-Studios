# Integration tests for Story 008 — Respawn lifecycle (died/respawned handlers + state).
# Couvre AC-CAM-40 (died → Respawning + overlay + mouse gate),
#         AC-CAM-41 (respawned → reset effets sauf pitch/yaw),
#         AC-CAM-43 (died idempotence — early return si déjà RESPAWNING).
#
# TR-cam-001 (ownership séparé par étage scene tree) ;
# ADR-0002 (Camera Scene Tree) + ADR-0005 (D-2 signaux canoniques died/respawned ;
# D-6 ordre intra-tick ; D-7 no Movement mutation ; D-8 idempotence).
#
# Décision creative-director r1 2026-04-21 : pitch ET yaw préservés au respawn
# (Ghostrunner approach, évite désorientation Pillar 3 die-retry).
#
# Framework: GdUnit4 (extends GdUnitTestSuite).
#
# Setup : MockPlayerWithDashSignals exposant maintenant died() + respawned(Vector3)
# en plus de dash_started/dash_ended/wall_jumped.

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

## BASE_FOV miroir CameraSystem.BASE_FOV (90.0).
const EXPECTED_BASE_FOV: float = 90.0

## Couleur miroir CameraSystem.RESPAWN_OVERLAY_COLOR.
const EXPECTED_OVERLAY_COLOR: Color = Color(0.4, 0.0, 0.0, 0.6)

## Tolerance pour comparaisons floating-point sur scalaires reset (rad / fov).
const RESET_TOLERANCE: float = 0.0001


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
	await get_tree().process_frame

	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm does not have CameraSystem script") \
		.is_not_null()

	# Pattern test parity story_005/006/007 : `%CameraEffects` ne résout pas dans
	# le test setup (pas de scene owner), donc les @onready vars sont null et
	# l'assert dans `_ready()` plante AVANT que `_setup_overlay()` puisse tourner.
	# Manual injection ici garantit que tous les tests AC-CAM-40/41/43 trouvent
	# un état valide. En production runtime (Player.tscn complet avec scene owner),
	# `%CameraEffects` résout correctement et tout cela est inutile.
	_camera_system._camera_effects = _camera_effects
	_camera_system._camera3d = _camera3d
	_camera_system._player = _mock_player
	if _camera_system._overlay == null:
		_camera_system._setup_overlay()
	# Init explicite FOV (normalement fait par `_ready()` ligne 166).
	_camera3d.fov = 90.0
	# Idem pour les connexions died/respawned qui sont après `_setup_overlay()`
	# dans `_ready()` et n'ont pas non plus tourné.
	if not _mock_player.died.is_connected(_camera_system._on_died):
		_mock_player.died.connect(_camera_system._on_died)
	if not _mock_player.respawned.is_connected(_camera_system._on_respawned):
		_mock_player.respawned.connect(_camera_system._on_respawned)


func after_test() -> void:
	# Cleanup défensif des connexions story-008 + voisines pour éviter event leak.
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
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
	_mock_player.queue_free()
	_mock_player = null
	_camera_arm = null
	_camera_effects = null
	_camera3d = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-40 — died → Respawning + overlay + mouse gate
# ---------------------------------------------------------------------------

func test_ac_cam_40_died_enters_respawning_and_shows_overlay() -> void:
	# Arrange — Camera Active, overlay caché.
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("Setup: _state doit être ACTIVE avant died()") \
		.is_false()
	var overlay: ColorRect = _camera_system.get_respawn_overlay()
	assert_object(overlay) \
		.override_failure_message("Setup: overlay doit être pré-créé au _ready()") \
		.is_not_null()
	assert_bool(overlay.visible) \
		.override_failure_message("Setup: overlay.visible doit être false avant died()") \
		.is_false()

	# Act — Movement émet died().
	_mock_player.died.emit()

	# Assert — _state == RESPAWNING, overlay visible avec couleur attendue.
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("AC-CAM-40 : _state doit passer à RESPAWNING après died()") \
		.is_true()
	assert_bool(overlay.visible) \
		.override_failure_message("AC-CAM-40 : overlay.visible doit être true après died()") \
		.is_true()
	assert_object(overlay.color) \
		.override_failure_message(
			"AC-CAM-40 : overlay.color doit être Color(0.4, 0, 0, 0.6) — got %s"
			% str(overlay.color)
		) \
		.is_equal(EXPECTED_OVERLAY_COLOR)


func test_ac_cam_40_mouse_motion_during_respawning_does_not_rotate_player() -> void:
	# Arrange — pitch + yaw initiaux, bascule en Respawning.
	_camera_arm.rotation.x = -0.3
	_mock_player.rotation.y = 1.2
	var initial_pitch: float = _camera_arm.rotation.x
	var initial_yaw: float = _mock_player.rotation.y

	_mock_player.died.emit()
	assert_bool(_camera_system.is_respawning()).is_true()

	# Act — appel direct du handler avec un delta non-trivial.
	# (Évite la dépendance à InputManager.mouse_motion / mouse_captured pour
	# tester chirurgicalement le gate _state == RESPAWNING dans _on_mouse_motion.)
	_camera_system._on_mouse_motion(Vector2(100.0, 50.0))

	# Assert — pitch/yaw inchangés (gate Respawning bloque la rotation).
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"AC-CAM-40 : pitch doit rester %.4f pendant Respawning — got %.6f"
			% [initial_pitch, _camera_arm.rotation.x]
		) \
		.is_equal_approx(initial_pitch, RESET_TOLERANCE)
	assert_float(_mock_player.rotation.y) \
		.override_failure_message(
			"AC-CAM-40 : yaw doit rester %.4f pendant Respawning — got %.6f"
			% [initial_yaw, _mock_player.rotation.y]
		) \
		.is_equal_approx(initial_yaw, RESET_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-41 — respawned → reset effets SAUF pitch/yaw (Ghostrunner)
# ---------------------------------------------------------------------------

func test_ac_cam_41_respawned_resets_effects_but_preserves_pitch_yaw() -> void:
	# Arrange — pollue tous les états visuels + déclenche died.
	_mock_player.died.emit()
	_camera_effects.rotation.z = 0.35
	_camera3d.fov = 100.0
	_camera3d.rotation = Vector3(0.1, 0.0, 0.05)
	_camera_system._shake_offset = Vector3(0.0, 0.0, 0.05)
	_camera_arm.rotation.x = -0.7  # pitch — DOIT être préservé
	_mock_player.rotation.y = 1.5  # yaw — DOIT être préservé
	_camera_system._is_dashing = true  # cas edge : died pendant dash

	# Act — Movement émet respawned avec position arbitraire (ignorée par Camera).
	_mock_player.respawned.emit(Vector3(10.0, 2.0, 5.0))

	# Story 009 : _on_respawned déclenche maintenant une animation tween (flash 50 ms +
	# fade 100 ms). Les resets scalaires (tilt/fov/rotation/shake/_is_dashing/_state)
	# sont synchrones, mais l'overlay reste visible jusqu'à la fin du tween (callback
	# final hide). On attend la complétion pour vérifier l'état stable post-animation.
	if _camera_system._respawn_tween != null and _camera_system._respawn_tween.is_valid():
		await _camera_system._respawn_tween.finished

	# Assert — reset effets visuels.
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"AC-CAM-41 : tilt doit être reset à 0.0 — got %.6f" % _camera_effects.rotation.z
		) \
		.is_equal_approx(0.0, RESET_TOLERANCE)
	assert_float(_camera3d.fov) \
		.override_failure_message(
			"AC-CAM-41 : FOV doit être reset à BASE_FOV=90.0 — got %.6f" % _camera3d.fov
		) \
		.is_equal_approx(EXPECTED_BASE_FOV, RESET_TOLERANCE)
	assert_vector(_camera3d.rotation) \
		.override_failure_message(
			"AC-CAM-41 : camera3d.rotation doit être ZERO — got %s" % str(_camera3d.rotation)
		) \
		.is_equal(Vector3.ZERO)
	assert_vector(_camera_system._shake_offset) \
		.override_failure_message(
			"AC-CAM-41 : _shake_offset doit être ZERO — got %s" % str(_camera_system._shake_offset)
		) \
		.is_equal(Vector3.ZERO)
	assert_bool(_camera_system._is_dashing) \
		.override_failure_message("AC-CAM-41 : _is_dashing doit être false après respawn") \
		.is_false()
	assert_bool(_camera_system.get_respawn_overlay().visible) \
		.override_failure_message("AC-CAM-41 : overlay.visible doit être false après respawn") \
		.is_false()
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("AC-CAM-41 : _state doit revenir à ACTIVE après respawn") \
		.is_false()

	# Assert — pitch + yaw PRÉSERVÉS (Ghostrunner approach).
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message(
			"AC-CAM-41 : pitch (camera_arm.rotation.x) DOIT être préservé à -0.7 — got %.6f"
			% _camera_arm.rotation.x
		) \
		.is_equal_approx(-0.7, RESET_TOLERANCE)
	assert_float(_mock_player.rotation.y) \
		.override_failure_message(
			"AC-CAM-41 : yaw (player.rotation.y) DOIT être préservé à 1.5 — got %.6f"
			% _mock_player.rotation.y
		) \
		.is_equal_approx(1.5, RESET_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-43 — died idempotence (early return si déjà RESPAWNING)
# ---------------------------------------------------------------------------

func test_ac_cam_43_second_died_during_respawning_is_noop() -> void:
	# Arrange — premier died, Respawning actif.
	_mock_player.died.emit()
	assert_bool(_camera_system.is_respawning()).is_true()

	var overlay: ColorRect = _camera_system.get_respawn_overlay()
	# Mute color pour détecter une réinitialisation indésirable au second died.
	# Si le handler n'était pas idempotent, _on_died re-assignerait
	# _overlay.color = RESPAWN_OVERLAY_COLOR et écraserait notre sentinelle.
	var sentinel_color: Color = Color(0.123, 0.456, 0.789, 0.42)
	overlay.color = sentinel_color

	# Act — second died() émis pendant Respawning.
	_mock_player.died.emit()

	# Assert — _state inchangé, overlay.color sentinelle inchangée (early return effectif).
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("AC-CAM-43 : _state doit rester RESPAWNING après second died()") \
		.is_true()
	assert_object(overlay.color) \
		.override_failure_message(
			"AC-CAM-43 : overlay.color sentinelle doit être préservée (early return) — got %s"
			% str(overlay.color)
		) \
		.is_equal(sentinel_color)


func test_ac_cam_43_died_respawned_died_cycle_works_normally() -> void:
	# Arrange/Act — premier cycle complet died → respawned.
	_mock_player.died.emit()
	assert_bool(_camera_system.is_respawning()).is_true()
	_mock_player.respawned.emit(Vector3.ZERO)
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("AC-CAM-43 : _state doit revenir à ACTIVE après respawn") \
		.is_false()

	# Act — second died() après respawn → second cycle DOIT fonctionner.
	_mock_player.died.emit()

	# Assert — Respawning à nouveau actif, overlay visible.
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("AC-CAM-43 : second died() après respawn doit re-entrer Respawning") \
		.is_true()
	assert_bool(_camera_system.get_respawn_overlay().visible) \
		.override_failure_message("AC-CAM-43 : overlay doit être à nouveau visible au second cycle") \
		.is_true()
