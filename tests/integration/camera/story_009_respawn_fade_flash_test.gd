# Integration tests for Story 009 — Respawn fade rouge → flash blanc → clear.
# Story Type : Visual/Feel (test évidence ADVISORY) — ce smoke test fournit
# l'évidence OBJECTIVE pour AC-CAM-FLASH-2 (timing total ≤ 400 ms) + couvre
# l'engagement structurel d'AC-CAM-42 (séquence 3 phases : flash blanc snap,
# fade vers transparent, hide final). La perception visuelle (« 3 phases
# distinctes », « pas de jump cut ») reste manuelle via screenshots Martin
# evidence doc — ce test ne la remplace pas.
#
# ADR-0002 (overlay owned par Camera) ; GDD Rule 9 + Visual/Audio Requirements
# (Mirror's Edge reference) ; Pillar 3 ≤ 400 ms.
#
# Framework: GdUnit4 (extends GdUnitTestSuite + AutoloadResetHelper composition — TD-010 opt-in).

extends GdUnitTestSuite

const AutoloadResetHelper := preload("res://tests/helpers/autoload_reset_helper.gd")

var _autoload_snap: Dictionary = {}


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

## Couleur du flash blanc (miroir CameraSystem.RESPAWN_FLASH_COLOR).
const EXPECTED_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

## Cible Pillar 3 — séquence respawn totale ≤ 400 ms.
const PILLAR3_TIMING_BUDGET_MS: int = 400

## Tolérance overhead test framework (process_frame / await scheduling).
const TIMING_OVERHEAD_TOLERANCE_MS: int = 50

## Total animation expected (flash 50 ms + fade 100 ms).
const EXPECTED_ANIMATION_DURATION_MS: int = 150


# ---------------------------------------------------------------------------
# Variables de test
# ---------------------------------------------------------------------------

var _mock_player: MockPlayerWithDashSignals = null
var _camera_arm: Node3D = null
var _camera_effects: Node3D = null
var _camera3d: Camera3D = null
var _camera_system: CameraSystem = null


# ---------------------------------------------------------------------------
# Setup / teardown — pattern parity story_008
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Snapshot autoloads (GSM + Engine + AudioSystem + VFXSystem) avant mutations
	# pour éviter pollution cross-suite (TD-010).
	_autoload_snap = AutoloadResetHelper.snapshot(get_tree())
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
	await get_tree().process_frame

	_camera_system = _camera_arm as CameraSystem

	# Manual injection — pattern hérité story_005/006/007/008 (tech debt
	# `%CameraEffects` non-résolu sans scene owner). Voir story_008 setup notes.
	_camera_system._camera_effects = _camera_effects
	_camera_system._camera3d = _camera3d
	_camera_system._player = _mock_player
	if _camera_system._overlay == null:
		_camera_system._setup_overlay()
	_camera3d.fov = 90.0
	if not _mock_player.died.is_connected(_camera_system._on_died):
		_mock_player.died.connect(_camera_system._on_died)
	if not _mock_player.respawned.is_connected(_camera_system._on_respawned):
		_mock_player.respawned.connect(_camera_system._on_respawned)


func after_test() -> void:
	# Restaure autoloads — évite pollution VFX._flash_respawn_active cross-suite (TD-010).
	AutoloadResetHelper.restore(get_tree(), _autoload_snap)
	# Kill tween si encore actif (cas test interrompu mid-animation).
	if _camera_system._respawn_tween != null and _camera_system._respawn_tween.is_valid():
		_camera_system._respawn_tween.kill()
	if InputManager.mouse_motion.is_connected(_camera_system._on_mouse_motion):
		InputManager.mouse_motion.disconnect(_camera_system._on_mouse_motion)
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
# AC-CAM-42 — séquence flash blanc → fade rouge → clear (structure objective)
# ---------------------------------------------------------------------------

func test_ac_cam_42_respawn_animation_starts_with_white_flash() -> void:
	# Arrange — entre en Respawning (overlay rouge plein écran).
	_mock_player.died.emit()
	var overlay: ColorRect = _camera_system.get_respawn_overlay()
	assert_object(overlay.color) \
		.override_failure_message("Phase 0 : overlay doit être rouge avant respawned()") \
		.is_equal(Color(0.4, 0.0, 0.0, 0.6))

	# Act — Movement respawned déclenche l'animation.
	_mock_player.respawned.emit(Vector3.ZERO)

	# Assert immédiat — Phase 1 flash blanc snap-in (durée 0).
	# Le tween de Tween_property avec duration=0 exécute le set au premier process,
	# donc on attend 1 frame pour que la valeur soit appliquée.
	await get_tree().process_frame

	assert_object(overlay.color) \
		.override_failure_message(
			"AC-CAM-42 Phase 1 : overlay doit être flash blanc (1,1,1,0.9) immédiatement post-respawned — got %s"
			% str(overlay.color)
		) \
		.is_equal(EXPECTED_FLASH_COLOR)
	assert_bool(overlay.visible) \
		.override_failure_message("AC-CAM-42 Phase 1 : overlay doit rester visible pendant flash") \
		.is_true()


func test_ac_cam_42_respawn_animation_ends_with_overlay_hidden() -> void:
	# Arrange/Act — cycle complet died → respawned.
	_mock_player.died.emit()
	_mock_player.respawned.emit(Vector3.ZERO)

	# Wait for tween completion (flash 50 ms + fade 100 ms = 150 ms).
	await _camera_system._respawn_tween.finished

	# Assert Phase 3 (clear) — overlay caché, séquence terminée proprement.
	var overlay: ColorRect = _camera_system.get_respawn_overlay()
	assert_bool(overlay.visible) \
		.override_failure_message("AC-CAM-42 Phase 3 : overlay doit être hidden post-tween") \
		.is_false()


func test_ac_cam_42_tween_is_valid_during_animation() -> void:
	# Arrange/Act — déclenche l'animation.
	_mock_player.died.emit()
	_mock_player.respawned.emit(Vector3.ZERO)
	await get_tree().process_frame

	# Assert — tween créé et actif (séquence 3 phases en cours).
	assert_object(_camera_system._respawn_tween) \
		.override_failure_message("AC-CAM-42 : _respawn_tween doit être créé après respawned()") \
		.is_not_null()
	assert_bool(_camera_system._respawn_tween.is_valid()) \
		.override_failure_message("AC-CAM-42 : _respawn_tween doit être valid pendant animation") \
		.is_true()


# ---------------------------------------------------------------------------
# AC-CAM-FLASH-2 — total duration ≤ 400 ms (Pillar 3 budget)
# ---------------------------------------------------------------------------

func test_ac_cam_flash_2_total_animation_duration_under_pillar3_budget() -> void:
	# Arrange — état initial.
	_mock_player.died.emit()

	# Act — mesure timing de respawned.emit() à tween.finished.
	var start_ms: int = Time.get_ticks_msec()
	_mock_player.respawned.emit(Vector3.ZERO)
	await _camera_system._respawn_tween.finished
	var elapsed_ms: int = Time.get_ticks_msec() - start_ms

	# Assert — sous budget Pillar 3 ≤ 400 ms (incluant tolerance overhead).
	assert_int(elapsed_ms) \
		.override_failure_message(
			"AC-CAM-FLASH-2 : séquence respawn totale doit être ≤ %d ms (Pillar 3) — got %d ms"
			% [PILLAR3_TIMING_BUDGET_MS, elapsed_ms]
		) \
		.is_less_equal(PILLAR3_TIMING_BUDGET_MS)

	# Assert — proche de la cible théorique 150 ms (50 flash + 100 fade) avec
	# tolérance overhead test framework (process_frame scheduling).
	assert_int(elapsed_ms) \
		.override_failure_message(
			"AC-CAM-FLASH-2 : durée doit être proche de %d ms ± %d ms — got %d ms"
			% [EXPECTED_ANIMATION_DURATION_MS, TIMING_OVERHEAD_TOLERANCE_MS, elapsed_ms]
		) \
		.is_greater_equal(EXPECTED_ANIMATION_DURATION_MS - TIMING_OVERHEAD_TOLERANCE_MS)


# ---------------------------------------------------------------------------
# Edge case — died→respawned→died rapide (< 200 ms) kill tween sans conflit
# ---------------------------------------------------------------------------

func test_died_during_respawn_animation_kills_tween_and_resets_overlay() -> void:
	# Arrange — premier cycle, tween en cours.
	_mock_player.died.emit()
	_mock_player.respawned.emit(Vector3.ZERO)
	await get_tree().process_frame

	var first_tween: Tween = _camera_system._respawn_tween
	assert_bool(first_tween.is_valid()) \
		.override_failure_message("Setup : premier tween doit être valid avant second died()") \
		.is_true()

	# Act — second died() pendant animation (< 150 ms après respawned).
	_mock_player.died.emit()

	# Assert — tween précédent killed, overlay réinitialisé au rouge respawn.
	assert_bool(first_tween.is_valid()) \
		.override_failure_message("Edge : premier tween doit être killed par second died()") \
		.is_false()
	var overlay: ColorRect = _camera_system.get_respawn_overlay()
	assert_object(overlay.color) \
		.override_failure_message(
			"Edge : overlay.color doit être reset à RESPAWN_OVERLAY_COLOR après second died() — got %s"
			% str(overlay.color)
		) \
		.is_equal(Color(0.4, 0.0, 0.0, 0.6))
	assert_bool(overlay.visible) \
		.override_failure_message("Edge : overlay doit être visible après second died()") \
		.is_true()
	assert_bool(_camera_system.is_respawning()) \
		.override_failure_message("Edge : _state doit être RESPAWNING après second died()") \
		.is_true()
