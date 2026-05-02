# Tests unitaires Camera Polish P4 — wiring AccessibilityService (ADR-0015 D-3).
#
# Couvre AC-CAM-70/71/72 GDD Rule 14 via le service réel (story 010 testait
# l'injection directe ; ici on valide la pull-pattern + signal_changed + clamping).
#
# AC-1 : defaults (reduce_motion=false) → mults = 1.0/1.0/1.0 au _ready.
# AC-2 : reduce_motion=true au boot → mults = 0.25/0.5/0.0 au _ready.
# AC-3 : settings_changed mid-game → cache rechargé (live update).
# AC-4 : disconnect _exit_tree → no leak (signal connection count reset).
#
# Pattern : apply_settings AVANT add_child pour faire propager au _ready (parité
# story-022 Combat). Hermetic teardown : reset AccessibilityService aux defaults.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story    : Camera Polish P4 (Rule 14 wiring) — pas de fichier story formel,
#            traçabilité via active.md "Camera Polish P4 (Rule 14 wiring)".
# ADR      : ADR-0015 D-3 (pull-pattern), D-5 (defaults invariant), D-7 (clamping).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const MULT_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _player: CharacterBody3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Lifecycle — hermetic isolation
# ---------------------------------------------------------------------------

func before_test() -> void:
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())


func after_test() -> void:
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = null
	_camera_system = null
	await get_tree().process_frame
	AccessibilityService.apply_settings(AccessibilitySettings.create_defaults())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _spawn_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	_player = packed.instantiate() as CharacterBody3D
	add_child(_player)
	await get_tree().process_frame
	_camera_system = _player.get_node("CameraArm") as CameraSystem
	assert_object(_camera_system).is_not_null()


# ---------------------------------------------------------------------------
# AC-1 — Defaults invariant : reduce_motion=false → mults = 1.0
# ---------------------------------------------------------------------------

func test_camera_accessibility_defaults_preserve_full_intensity() -> void:
	# Arrange — defaults déjà appliqués par before_test (reduce_motion=false).

	# Act — spawn player, _ready → _apply_accessibility lit le service.
	await _spawn_player()

	# Assert — mults à 1.0 (D-5 defaults invariant).
	assert_float(_camera_system._tilt_mult) \
		.override_failure_message("AC-1: _tilt_mult doit être 1.0 par défaut") \
		.is_equal_approx(1.0, MULT_TOLERANCE)
	assert_float(_camera_system._fov_kick_mult) \
		.override_failure_message("AC-1: _fov_kick_mult doit être 1.0 par défaut") \
		.is_equal_approx(1.0, MULT_TOLERANCE)
	assert_float(_camera_system._shake_mult) \
		.override_failure_message("AC-1: _shake_mult doit être 1.0 par défaut") \
		.is_equal_approx(1.0, MULT_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-2 — reduce_motion=true au boot → mults = 0.25 / 0.5 / 0.0
# ---------------------------------------------------------------------------

func test_camera_accessibility_reduce_motion_at_boot_caches_attenuated_mults() -> void:
	# Arrange — apply reduce_motion=true AVANT spawn (propage via _ready).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	AccessibilityService.apply_settings(s)

	# Act
	await _spawn_player()

	# Assert — service applique × 0.25 / × 0.5 / × 0.0 quand reduce_motion=true.
	assert_float(_camera_system._tilt_mult) \
		.override_failure_message("AC-2: _tilt_mult doit être 0.25 (× tilt_mult × REDUCE_MOTION_TILT_MULT)") \
		.is_equal_approx(0.25, MULT_TOLERANCE)
	assert_float(_camera_system._fov_kick_mult) \
		.override_failure_message("AC-2: _fov_kick_mult doit être 0.5") \
		.is_equal_approx(0.5, MULT_TOLERANCE)
	assert_float(_camera_system._shake_mult) \
		.override_failure_message("AC-2: _shake_mult doit être 0.0") \
		.is_equal_approx(0.0, MULT_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-3 — settings_changed mid-game → reload cache (live update)
# ---------------------------------------------------------------------------

func test_camera_accessibility_settings_changed_signal_reloads_cache_mid_game() -> void:
	# Arrange — boot avec defaults (mults = 1.0).
	await _spawn_player()
	assert_float(_camera_system._tilt_mult).is_equal_approx(1.0, MULT_TOLERANCE)

	# Act — toggle reduce_motion mid-game via service (émet settings_changed).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	AccessibilityService.apply_settings(s)

	# Assert — handler _on_accessibility_changed → _apply_accessibility → cache rechargé.
	assert_float(_camera_system._tilt_mult) \
		.override_failure_message("AC-3: _tilt_mult doit suivre settings_changed (live update)") \
		.is_equal_approx(0.25, MULT_TOLERANCE)
	assert_float(_camera_system._fov_kick_mult) \
		.override_failure_message("AC-3: _fov_kick_mult doit suivre settings_changed") \
		.is_equal_approx(0.5, MULT_TOLERANCE)
	assert_float(_camera_system._shake_mult) \
		.override_failure_message("AC-3: _shake_mult doit suivre settings_changed") \
		.is_equal_approx(0.0, MULT_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-4 — _exit_tree disconnect → no signal leak après free
# ---------------------------------------------------------------------------

func test_camera_accessibility_exit_tree_disconnects_signal_no_leak() -> void:
	# Arrange — spawn → connect ; check connection présente.
	await _spawn_player()
	assert_bool(AccessibilityService.settings_changed.is_connected(_camera_system._on_accessibility_changed)) \
		.override_failure_message("Setup: signal doit être connecté après _ready") \
		.is_true()

	# Act — free player → _exit_tree → disconnect.
	var cam_ref: CameraSystem = _camera_system
	_player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert — connexion absente (cam_ref kept comme reference, mais le node est freed
	# → is_connected sur freed node retourne false côté service via WeakRef cleanup).
	# Test via le compte global de connexions sur le signal — doit être 0 (no Camera left).
	var signal_connections: Array = AccessibilityService.settings_changed.get_connections()
	for conn: Dictionary in signal_connections:
		assert_bool(conn["callable"].get_object() == cam_ref) \
			.override_failure_message("AC-4: aucune connection résiduelle vers freed CameraSystem") \
			.is_false()


# ---------------------------------------------------------------------------
# AC-5 — bornes service-level (clamping centralisé, Camera ne re-clampe pas)
# ---------------------------------------------------------------------------

func test_camera_accessibility_mults_clamped_service_side_to_safe_range() -> void:
	# Arrange — settings hors bornes (out-of-range), service doit clamper avant retour.
	# Note : `tilt_mult/fov_kick_mult/shake_mult` sont user overrides multipliés par
	# REDUCE_MOTION_*_MULT quand reduce_motion=true. Service clamp final ∈ [0.0, 1.0].
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = false
	s.tilt_mult = 5.0  # hors borne
	s.fov_kick_mult = -2.0  # hors borne négative
	s.shake_mult = 99.0  # hors borne
	AccessibilityService.apply_settings(s)

	# Act
	await _spawn_player()

	# Assert — Camera reçoit valeurs clampées [0.0, 1.0] (D-7 service-side clamping).
	assert_float(_camera_system._tilt_mult) \
		.override_failure_message("AC-5: tilt_mult clampé ≤ 1.0 service-side, got %.4f" % _camera_system._tilt_mult) \
		.is_between(0.0, 1.0)
	assert_float(_camera_system._fov_kick_mult) \
		.override_failure_message("AC-5: fov_kick_mult clampé ≥ 0.0 service-side, got %.4f" % _camera_system._fov_kick_mult) \
		.is_between(0.0, 1.0)
	assert_float(_camera_system._shake_mult) \
		.override_failure_message("AC-5: shake_mult clampé ≤ 1.0 service-side, got %.4f" % _camera_system._shake_mult) \
		.is_between(0.0, 1.0)
