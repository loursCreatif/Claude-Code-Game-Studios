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

## TD-005 migration 2026-05-02 : MockPlayerWithDashSignals expose tous les signaux
## ADR-0005 D-2 (dash_started/dash_ended/wall_jumped/died/respawned) + wall_normal,
## permettant à CameraSystem._ready() de connecter sans crash. Pattern parity story-008.
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
	_mock_player.wall_normal = Vector3.ZERO

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

	# TD-005 manual injection AVANT le premier process_frame : %CameraEffects/%Camera3D
	# ne résolvent pas sans scene owner, donc les @onready vars sont null après _ready().
	# Si on awaitait avant, _process() tournerait avec _camera_effects null → crash.
	# Pattern parity story-008 : on injecte explicitement et on appelle _setup_overlay()
	# si nécessaire pour que _safeguard_rotation/_update_tilt_wall_run ne crashent pas.
	_camera_system._camera_effects = _camera_effects
	_camera_system._camera3d = _camera3d
	_camera_system._player = _mock_player
	if _camera_system._overlay == null:
		_camera_system._setup_overlay()

	# TD-004 connexions wall_run_entered/exited (signal-driven cache) — _ready()
	# early-return skip ces connexions dans test harness sans scene owner.
	if not _mock_player.wall_run_entered.is_connected(_camera_system._on_wall_run_entered):
		_mock_player.wall_run_entered.connect(_camera_system._on_wall_run_entered)
	if not _mock_player.wall_run_exited.is_connected(_camera_system._on_wall_run_exited):
		_mock_player.wall_run_exited.connect(_camera_system._on_wall_run_exited)

	await get_tree().process_frame

	_mock_player.rotation = Vector3.ZERO
	_camera_arm.rotation = Vector3.ZERO
	_camera_effects.rotation = Vector3.ZERO
	_mock_player.wall_normal = Vector3.ZERO
	_camera_system._wall_side_cached = 0
	_camera_system._is_wall_running = false


func after_test() -> void:
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
	# TD-005 cleanup défensif des signaux player connectés par _ready().
	if _mock_player != null and is_instance_valid(_mock_player):
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
# Helpers — TD-004 signal-driven cache : wall_normal n'est plus poll, le cache
# _wall_side_cached est mis à jour exclusivement par _on_wall_run_entered/exited.
# ---------------------------------------------------------------------------

func _enter_wall_run(wall_normal: Vector3) -> void:
	_mock_player.wall_normal = wall_normal  # legacy var, conservée pour cohérence
	_mock_player.wall_run_entered.emit(wall_normal)


func _exit_wall_run() -> void:
	_mock_player.wall_normal = Vector3.ZERO
	_mock_player.wall_run_exited.emit()


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
	_enter_wall_run(Vector3(-1.0, 0.0, 0.0))
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
	_enter_wall_run(Vector3(-1.0, 0.0, 0.0))
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
	_exit_wall_run()

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
	# Arrange — commence en wall-run gauche (z=-0.35), bascule vers droit.
	# TD-004 : transition wall-to-wall en production passe par AIRBORNE intermédiaire,
	# donc Movement émet wall_run_exited puis wall_run_entered (nouveau normal).
	_enter_wall_run(Vector3(1.0, 0.0, 0.0))
	_camera_effects.rotation.z = -CameraSystem.WALL_RUN_TILT_ANGLE
	_exit_wall_run()
	_enter_wall_run(Vector3(-1.0, 0.0, 0.0))

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
	_enter_wall_run(Vector3(-1.0, 0.0, 0.0))
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
	# TD-004 : alternance via signaux wall_run_exited/entered (chaque flip = exit+entrée).
	for frame in range(60):
		var normal: Vector3 = Vector3(-1.0, 0.0, 0.0) if frame % 2 == 0 else Vector3(1.0, 0.0, 0.0)
		_exit_wall_run()
		_enter_wall_run(normal)
		_camera_system._update_tilt_wall_run(FIXED_DELTA)

	# Assert — pas d'amplification hors bornes
	assert_float(absf(_camera_effects.rotation.z)) \
		.override_failure_message(
			"Edge case jitter : |z| ne doit pas dépasser WALL_RUN_TILT_ANGLE — got |%f|"
			% _camera_effects.rotation.z
		) \
		.is_less_equal(CameraSystem.WALL_RUN_TILT_ANGLE)


# ---------------------------------------------------------------------------
# Edge case — TD-004 : sans signal wall_run_entered émis, _wall_side_cached
# reste à 0 → tilt à 0 (lerp vers target=0 reste à 0). Substitue l'ancien test
# "wall_normal absent du script Player" qui validait le polling défensif via get().
# ---------------------------------------------------------------------------

func test_tilt_wall_run_zero_when_no_signal_emitted() -> void:
	# Arrange — pas d'émission wall_run_entered, cache reste à zéro
	_camera_effects.rotation.z = 0.0

	# Act — 1 frame de _update_tilt_wall_run sans signal préalable
	_camera_system._update_tilt_wall_run(FIXED_DELTA)

	# Assert — tilt reste à zéro (target_roll = WALL_RUN_TILT_ANGLE * 0 = 0)
	assert_float(_camera_effects.rotation.z) \
		.override_failure_message(
			"Sans wall_run_entered émis, rotation.z doit rester 0.0 — got %f"
			% _camera_effects.rotation.z
		) \
		.is_equal_approx(0.0, TOLERANCE_STRICT)
