# Unit tests for Story 003 — Camera gates enabled + is_mouse_captured.
# Couvre AC-CAM-60 (gate enabled), AC-CAM-61 (pas de buffer transitoire),
# AC-CAM-62 (gate is_mouse_captured).
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# Stratégie : drive `InputManager.is_mouse_captured()` via `set_mouse_captured()`
# (API publique), et `InputManager.enabled` (property read-only) via
# `request_disable(owner) / release_enable_request(owner)` (ADR-0004 D-4
# refcount API canonique — write direct sur `_enabled` interdit par le manifest
# Foundation).

extends GdUnitTestSuite

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const TOLERANCE: float = 0.001

var _player: CharacterBody3D = null
var _camera_arm: Node3D = null
var _camera_system: CameraSystem = null

# Sauvegardes pour restauration entre tests (autoload state global).
var _saved_sensitivity: float = 0.0022
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func before_test() -> void:
	# Sauvegarder l'état autoload (InputManager est partagé entre tests).
	_saved_sensitivity = InputManager.mouse_sensitivity
	_saved_mouse_mode = Input.mouse_mode

	# Prérequis par défaut pour tester la logique de gate :
	# mouse captured = true, enabled = true. Chaque test désactive
	# ce qu'il veut tester via l'API publique.
	InputManager.set_mouse_captured(true)

	# Instancier Player (déclenche _ready de CameraSystem → connect signal).
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as CharacterBody3D
	add_child(_player)
	await get_tree().process_frame

	_camera_arm = _player.get_node("CameraArm") as Node3D
	_camera_system = _camera_arm as CameraSystem

	assert_object(_camera_system) \
		.override_failure_message("Setup error: CameraArm node has no CameraSystem script attached") \
		.is_not_null()

	# Reset rotations à zéro pour partir d'un état déterministe.
	_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO


func after_test() -> void:
	# Cleanup défensif : si un test a `request_disable(self)` et échoue avant
	# son `release_enable_request(self)`, le blocker contamine le test suivant
	# (InputManager est un autoload partagé). Safe no-op si aucun blocker actif
	# (push_warning potentiel silencieux — acceptable en teardown).
	InputManager.release_enable_request(self)

	# Disconnect handler camera (story-011 ajoutera _exit_tree symétrique).
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)

	# Restaurer l'état Input global.
	InputManager.mouse_sensitivity = _saved_sensitivity
	Input.mouse_mode = _saved_mouse_mode

	_player.queue_free()
	_player = null
	_camera_arm = null
	_camera_system = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-CAM-60 — gate enabled : disabled → aucune rotation, effets courants non reset
# ---------------------------------------------------------------------------

func test_gate_enabled_disabled_does_not_rotate_player_or_camera_arm() -> void:
	# Arrange — état initial non-zero, puis désactiver via API refcount.
	_player.rotation.y = 0.5
	_camera_arm.rotation.x = 0.3
	InputManager.request_disable(self)

	# Sanity check : enabled property doit refléter la requête.
	assert_bool(InputManager.enabled) \
		.override_failure_message("AC-CAM-60 sanity: InputManager.enabled doit être false après request_disable") \
		.is_false()

	# Act — émettre un motion qui normalement rotationne.
	InputManager.mouse_motion.emit(Vector2(100.0, 100.0))

	# Assert — rotations strictement inchangées (aucune application).
	assert_float(_player.rotation.y) \
		.override_failure_message("AC-CAM-60: player.rotation.y doit rester inchangé quand enabled=false") \
		.is_equal_approx(0.5, TOLERANCE)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("AC-CAM-60: camera_arm.rotation.x doit rester inchangé quand enabled=false") \
		.is_equal_approx(0.3, TOLERANCE)

	# Cleanup — libérer le blocker pour ne pas polluer les tests suivants.
	InputManager.release_enable_request(self)


func test_gate_enabled_toggle_rapidly_without_motion_keeps_rotations_untouched() -> void:
	# Arrange — position initiale non-zero.
	_player.rotation.y = 0.2
	_camera_arm.rotation.x = -0.1

	# Act — toggle disable → enable → disable → enable sans émettre motion.
	InputManager.request_disable(self)
	InputManager.release_enable_request(self)
	InputManager.request_disable(self)
	InputManager.release_enable_request(self)

	# Assert — les rotations ne doivent pas avoir bougé du tout.
	assert_float(_player.rotation.y) \
		.override_failure_message("AC-CAM-60 edge: toggle rapide sans motion ne doit pas toucher rotation") \
		.is_equal_approx(0.2, TOLERANCE)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("AC-CAM-60 edge: toggle rapide sans motion ne doit pas toucher pitch") \
		.is_equal_approx(-0.1, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-61 — pas de buffer transitoire : re-enable → motion suivant = exactement 1 delta
# ---------------------------------------------------------------------------

func test_re_enable_after_disable_applies_only_next_motion_without_cumulated_buffer() -> void:
	# Arrange — état initial stable, désactiver.
	_player.rotation.y = 0.0
	_camera_arm.rotation.x = 0.0
	var sensitivity: float = InputManager.mouse_sensitivity  # 0.0022 default
	InputManager.request_disable(self)

	# Act #1 — émettre 10 events pendant disabled (en pratique, Input ne les
	# republie pas, mais on les émet directement en test pour prouver l'absence
	# de buffer interne côté Camera).
	for _i: int in range(10):
		InputManager.mouse_motion.emit(Vector2(50.0, 0.0))

	# Assert intermédiaire — aucune rotation pendant disabled.
	assert_float(_player.rotation.y) \
		.override_failure_message("AC-CAM-61: 10 events disabled ne doivent pas rotationner") \
		.is_equal_approx(0.0, TOLERANCE)

	# Act #2 — re-enable puis émettre UN seul motion.
	InputManager.release_enable_request(self)
	InputManager.mouse_motion.emit(Vector2(50.0, 0.0))

	# Assert — rotation exactement -50 * sensitivity (pas cumulé avec les 10 skippés).
	var expected_yaw: float = -50.0 * sensitivity
	assert_float(_player.rotation.y) \
		.override_failure_message(
			"AC-CAM-61: post-enable, 1er motion doit appliquer exactement -50*sensitivity=%f, pas cumuler les 10 events skippés" % expected_yaw
		) \
		.is_equal_approx(expected_yaw, TOLERANCE)


func test_re_enable_without_motion_does_not_produce_ghost_rotation() -> void:
	# Arrange — état stable, désactiver puis réactiver sans émettre motion.
	_player.rotation.y = 0.1
	_camera_arm.rotation.x = 0.05
	InputManager.request_disable(self)
	InputManager.release_enable_request(self)

	# Act — aucune émission. Seul le toggle.

	# Assert — pas de rotation fantôme générée par le toggle.
	assert_float(_player.rotation.y) \
		.override_failure_message("AC-CAM-61 edge: re-enable sans motion = pas de rotation fantôme") \
		.is_equal_approx(0.1, TOLERANCE)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("AC-CAM-61 edge: re-enable sans motion = pas de pitch fantôme") \
		.is_equal_approx(0.05, TOLERANCE)


# ---------------------------------------------------------------------------
# AC-CAM-62 — gate is_mouse_captured : MouseFree → aucune rotation
# ---------------------------------------------------------------------------

func test_gate_mouse_captured_false_skips_motion_silently() -> void:
	# Arrange — état initial non-zero, enabled=true, puis libérer le curseur.
	_player.rotation.y = 0.4
	_camera_arm.rotation.x = -0.2
	InputManager.set_mouse_captured(false)

	# Sanity check : is_mouse_captured() == false.
	assert_bool(InputManager.is_mouse_captured()) \
		.override_failure_message("AC-CAM-62 sanity: is_mouse_captured() doit être false après set_mouse_captured(false)") \
		.is_false()

	# Act — émettre un motion qui normalement rotationne.
	InputManager.mouse_motion.emit(Vector2(100.0, 0.0))

	# Assert — rotations strictement inchangées.
	assert_float(_player.rotation.y) \
		.override_failure_message("AC-CAM-62: player.rotation.y inchangé quand mouse_mode=VISIBLE") \
		.is_equal_approx(0.4, TOLERANCE)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("AC-CAM-62: camera_arm.rotation.x inchangé quand mouse_mode=VISIBLE") \
		.is_equal_approx(-0.2, TOLERANCE)


func test_gate_mouse_captured_transition_mid_sequence_gates_each_event_independently() -> void:
	# Arrange — captured=true, sensitivity connue.
	_player.rotation.y = 0.0
	var sensitivity: float = InputManager.mouse_sensitivity

	# Act #1 — 1 event avec captured=true → appliqué.
	InputManager.set_mouse_captured(true)
	InputManager.mouse_motion.emit(Vector2(50.0, 0.0))
	var yaw_after_first: float = _player.rotation.y

	# Act #2 — libérer capture, émettre 1 event → non appliqué.
	InputManager.set_mouse_captured(false)
	InputManager.mouse_motion.emit(Vector2(50.0, 0.0))
	var yaw_after_gated: float = _player.rotation.y

	# Act #3 — ré-armer capture, émettre 1 event → appliqué à nouveau.
	InputManager.set_mouse_captured(true)
	InputManager.mouse_motion.emit(Vector2(50.0, 0.0))
	var yaw_after_third: float = _player.rotation.y

	# Assert — chaque event gated indépendamment sur l'état courant.
	var expected_one_apply: float = -50.0 * sensitivity
	assert_float(yaw_after_first) \
		.override_failure_message("AC-CAM-62 transition: 1er event captured doit appliquer rotation") \
		.is_equal_approx(expected_one_apply, TOLERANCE)
	assert_float(yaw_after_gated) \
		.override_failure_message("AC-CAM-62 transition: event gated doit pas changer rotation depuis step 1") \
		.is_equal_approx(expected_one_apply, TOLERANCE)
	assert_float(yaw_after_third) \
		.override_failure_message("AC-CAM-62 transition: 3e event captured doit appliquer un nouveau delta") \
		.is_equal_approx(expected_one_apply * 2.0, TOLERANCE)


# ---------------------------------------------------------------------------
# Bonus — zero-alloc early return : skip path ne touche pas player.rotation
# (sanity sur le fait que les gates sont vraiment des early-returns sans side-effect)
# ---------------------------------------------------------------------------

func test_both_gates_failing_simultaneously_does_nothing_silently() -> void:
	# Arrange — enabled=false ET mouse_mode=VISIBLE (deux gates ferment).
	_player.rotation.y = 0.7
	_camera_arm.rotation.x = 0.3
	InputManager.request_disable(self)
	InputManager.set_mouse_captured(false)

	# Act — spammer 100 events ; aucun ne doit passer.
	for _i: int in range(100):
		InputManager.mouse_motion.emit(Vector2(1000.0, 1000.0))

	# Assert — aucune mutation.
	assert_float(_player.rotation.y) \
		.override_failure_message("Bonus: 100 events avec 2 gates fermés ne doivent rien changer") \
		.is_equal_approx(0.7, TOLERANCE)
	assert_float(_camera_arm.rotation.x) \
		.override_failure_message("Bonus: 100 events avec 2 gates fermés ne doivent rien changer au pitch") \
		.is_equal_approx(0.3, TOLERANCE)

	# Cleanup
	InputManager.release_enable_request(self)
