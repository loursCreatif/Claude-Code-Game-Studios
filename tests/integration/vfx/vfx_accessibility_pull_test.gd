# Tests d'intégration Story-005 — VFXSystem accessibility pull ADR-0015 D-1 Option A.
# Couvre AC-VFX-12 + AC-VFX-20 + AC-VFX-21 + AC-NEW-07.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — injection mock AccessibilityService + wall-clock mock.
#
# Architecture :
# - _make_vfx() : helper hermétique retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility].
# - mock_accessibility.reduce_motion / reduce_flash / flash_mult writable directement.
# - await get_tree().process_frame × 2 pour laisser CONNECT_DEFERRED dispatcher.
# - vfx._flash_last_msec = -333 : convention bypass guard WCAG (story-004).

extends GdUnitTestSuite

var _VFXScript: GDScript = preload("res://src/core/vfx_system.gd")
var _MockCombat: GDScript = preload("res://tests/unit/vfx/mock_combat.gd")
var _MockEnemy: GDScript = preload("res://tests/unit/vfx/mock_enemy.gd")
var _MockCamera: GDScript = preload("res://tests/unit/vfx/mock_camera.gd")
var _MockAccessibility: GDScript = preload("res://tests/unit/vfx/mock_accessibility.gd")
var _MockGSM: GDScript = preload("res://tests/unit/vfx/mock_gsm.gd")


# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie VFXSystem + mocks Combat/Enemy/Camera/Accessibility/GSM.
## Retourne [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm].
## story-006 fix : mock_gsm en position 5 pour overrider autoload réel (retourne PLAYING=1
## → _is_active = true au boot). Indices 0-4 inchangés (mock_accessibility reste [4]).
func _make_vfx() -> Array:
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node
	var mock_accessibility: Node = _MockAccessibility.new() as Node
	var mock_gsm: Node = _MockGSM.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)
	add_child(mock_accessibility)
	add_child(mock_gsm)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	vfx.connect_accessibility_signals(mock_accessibility)  # story-005 — inject + re-pull
	vfx.connect_gsm_signals(mock_gsm)  # story-006 fix — inject + re-pull → _is_active = true

	return [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility, mock_gsm]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()


# =============================================================================
# AC-VFX-12 — reduce_motion appliqué sur le prochain kill après settings_changed
# =============================================================================

## GIVEN reduce_motion==false initial,
## WHEN 1er enemy_killed → _last_effective_cone_deg == 30.0 (plein cone),
## THEN après settings_changed(reduce_motion=true) + deferred dispatch,
##      2ème enemy_killed → _last_effective_cone_deg == 15.0 (cone × 0.5).
func test_reduce_motion_applied_on_next_kill_after_settings_changed() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_enemy: Node = nodes[2]
	var mock_accessibility: Node = nodes[4]

	# reduce_motion OFF au boot (default mock)
	mock_accessibility.reduce_motion = false
	# re-pull pour synchroniser (connect_accessibility_signals l'a déjà fait, réaffirmer)
	vfx._pull_accessibility_settings()

	# bypass guard WCAG pour enemy_killed → _trigger_flash_kill interne
	vfx._flash_last_msec = -333
	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec

	# Act — 1er kill (reduce_motion OFF)
	mock_enemy.enemy_killed.emit(null, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert 1er kill — cone plein 30°
	assert_float(vfx._last_effective_cone_deg) \
		.override_failure_message("AC-VFX-12: 1er kill reduce_motion=false → cone doit être 30.0°, got %f" % vfx._last_effective_cone_deg) \
		.is_equal_approx(30.0, 0.001)

	# Changer reduce_motion → true + émettre settings_changed
	mock_accessibility.reduce_motion = true
	mock_accessibility.settings_changed.emit()
	await get_tree().process_frame  # DEFERRED tick
	await get_tree().process_frame  # safety

	# Assert pull appliqué
	assert_bool(vfx._reduce_motion) \
		.override_failure_message("AC-VFX-12: vfx._reduce_motion doit être true après settings_changed(reduce_motion=true)") \
		.is_true()

	# Act — 2ème kill (reduce_motion ON) — bypass guard
	vfx._flash_last_msec = -333
	mocked_msec = 400
	vfx._get_time_msec = func() -> int: return mocked_msec
	mock_enemy.enemy_killed.emit(null, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert 2ème kill — cone réduit 15°
	assert_float(vfx._last_effective_cone_deg) \
		.override_failure_message("AC-VFX-12: 2ème kill reduce_motion=true → cone doit être 15.0° (30.0 × 0.5), got %f" % vfx._last_effective_cone_deg) \
		.is_equal_approx(15.0, 0.001)

	_free_all(nodes)


# =============================================================================
# AC-VFX-20 — reduce_flash live → gris sur le prochain flash
# =============================================================================

## GIVEN reduce_flash==false initial,
## WHEN 1er flash kill → color.r == 1.0 (blanc),
## THEN après settings_changed(reduce_flash=true) + deferred dispatch,
##      2ème flash kill → color.r ≈ 0.625 (gris REDUCE_FLASH_BRIGHTNESS).
func test_reduce_flash_live_update_grey_on_next_flash() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_accessibility: Node = nodes[4]

	mock_accessibility.reduce_flash = false
	vfx._pull_accessibility_settings()

	var mocked_msec: int = 0
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._flash_last_msec = -333  # bypass guard WCAG premier flash

	# Act — 1er flash (reduce_flash OFF → blanc)
	vfx._trigger_flash_kill()

	# Assert 1er flash blanc
	assert_float(vfx._flash_overlay_rect.color.r) \
		.override_failure_message("AC-VFX-20: 1er flash reduce_flash=false → color.r doit être 1.0 (blanc), got %f" % vfx._flash_overlay_rect.color.r) \
		.is_equal_approx(1.0, 0.001)

	# Changer reduce_flash → true + émettre settings_changed
	mock_accessibility.reduce_flash = true
	mock_accessibility.settings_changed.emit()
	await get_tree().process_frame  # DEFERRED tick
	await get_tree().process_frame  # safety

	# Assert pull appliqué
	assert_bool(vfx._reduce_flash) \
		.override_failure_message("AC-VFX-20: vfx._reduce_flash doit être true après settings_changed(reduce_flash=true)") \
		.is_true()

	# Terminer le 1er flash en cours (avancer wall-clock au-delà de 80 ms)
	mocked_msec = 400  # bien au-delà du guard 333 ms
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._physics_process(0.016)  # terminer flash en cours

	# Act — 2ème flash (reduce_flash ON → gris) — bypass guard via _flash_last_msec
	mocked_msec = 1000
	vfx._get_time_msec = func() -> int: return mocked_msec
	vfx._flash_last_msec = mocked_msec - 334  # bypass guard (delta 334 ≥ FLASH_MIN_INTERVAL_MS=333)
	vfx._trigger_flash_kill()

	# Assert 2ème flash gris
	assert_float(vfx._flash_overlay_rect.color.r) \
		.override_failure_message("AC-VFX-20: 2ème flash reduce_flash=true → color.r doit être ≈0.625 (gris), got %f" % vfx._flash_overlay_rect.color.r) \
		.is_equal_approx(0.625, 0.001)

	assert_float(vfx._flash_overlay_rect.color.g) \
		.override_failure_message("AC-VFX-20: color.g doit être ≈0.625 (gris uniforme)") \
		.is_equal_approx(0.625, 0.001)

	_free_all(nodes)


# =============================================================================
# AC-VFX-21 — boot defensive : defaults safe si AccessibilityService absent
# =============================================================================

## GIVEN VFXSystem instancié SANS mock accessibility injecté,
## WHEN _pull_accessibility_settings() appelé directement,
## THEN defaults safe : _reduce_flash==false, _flash_mult==1.0, _reduce_motion==false.
## WHEN mock injecté via connect_accessibility_signals avec reduce_motion=true,
## THEN correction live : vfx._reduce_motion==true.
func test_boot_defensive_no_accessibility_service_uses_defaults() -> void:
	# Arrange — VFX sans mock accessibility (autoload absent en headless)
	# Intentionally does not use _make_vfx() — no accessibility mock to test absent-service path.
	# Si _make_vfx() ajoute un mock futur, ce test reste valide (accessibility pas injecté).
	var mock_combat: Node = _MockCombat.new() as Node
	var mock_enemy: Node = _MockEnemy.new() as Node
	var mock_camera: Node = _MockCamera.new() as Node

	add_child(mock_combat)
	add_child(mock_enemy)
	add_child(mock_camera)

	var vfx: Node = _VFXScript.new() as Node
	add_child(vfx)

	vfx.connect_combat_signals(mock_combat)
	vfx.connect_enemy_signals(mock_enemy)
	vfx.connect_camera_signals(mock_camera)
	# PAS de connect_accessibility_signals → _accessibility_service_ref reste null
	# PAS de connect_gsm_signals — ce test teste l'absence de service.
	# story-006 fix : forcer _is_active = true pour ne pas gater les handlers post-pull.
	# (le vrai GSM autoload retourne MENU=0 en headless → _is_active = false sans mock)
	vfx._is_active = true

	# Forcer état arbitraire pour vérifier reset sur defaults
	vfx._reduce_flash = true
	vfx._flash_mult = 0.5
	vfx._reduce_motion = true

	# Act — pull sans service (autoload absent en headless, ref null)
	vfx._pull_accessibility_settings()

	# Assert defaults safe
	assert_bool(vfx._reduce_flash) \
		.override_failure_message("AC-VFX-21: _reduce_flash doit être false (default safe) quand AccessibilityService absent") \
		.is_false()

	assert_float(vfx._flash_mult) \
		.override_failure_message("AC-VFX-21: _flash_mult doit être 1.0 (default safe) quand AccessibilityService absent") \
		.is_equal_approx(1.0, 0.001)

	assert_bool(vfx._reduce_motion) \
		.override_failure_message("AC-VFX-21: _reduce_motion doit être false (default safe) quand AccessibilityService absent") \
		.is_false()

	# Vérifier correction live via injection mock post-boot
	var mock_accessibility: Node = _MockAccessibility.new() as Node
	mock_accessibility.reduce_motion = true
	mock_accessibility.reduce_flash = true
	mock_accessibility.flash_mult = 0.5
	add_child(mock_accessibility)

	vfx.connect_accessibility_signals(mock_accessibility)  # re-pull immédiat

	# Assert correction live
	assert_bool(vfx._reduce_motion) \
		.override_failure_message("AC-VFX-21: _reduce_motion doit être true après injection mock (correction live)") \
		.is_true()

	assert_bool(vfx._reduce_flash) \
		.override_failure_message("AC-VFX-21: _reduce_flash doit être true après injection mock (correction live)") \
		.is_true()

	assert_float(vfx._flash_mult) \
		.override_failure_message("AC-VFX-21: _flash_mult doit être 0.5 après injection mock (correction live)") \
		.is_equal_approx(0.5, 0.001)

	# Cleanup
	var all_nodes: Array = [vfx, mock_combat, mock_enemy, mock_camera, mock_accessibility]
	_free_all(all_nodes)


# =============================================================================
# AC-NEW-07 — live update mid-swing trail opacity × 0.5
# =============================================================================

## GIVEN reduce_motion==false, swing actif (_trail_active==true),
## WHEN settings_changed(reduce_motion=true) émis + deferred dispatch,
## THEN _trail_material.albedo_color.a ≈ 0.35 (KATANA_TRAIL_OPACITY_MAX × REDUCE_MOTION_TRAIL_MULT).
func test_live_update_mid_swing_trail_opacity_halves() -> void:
	# Arrange
	var nodes: Array = _make_vfx()
	var vfx: Node = nodes[0]
	var mock_combat: Node = nodes[1]
	var mock_accessibility: Node = nodes[4]

	# reduce_motion OFF au boot
	mock_accessibility.reduce_motion = false
	vfx._pull_accessibility_settings()

	# Activer swing — emit swing_started via mock signal DEFERRED
	mock_combat.swing_started.emit(Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert trail actif avec opacité max (reduce_motion=false → ×1.0)
	assert_bool(vfx._trail_active) \
		.override_failure_message("AC-NEW-07: _trail_active doit être true après swing_started") \
		.is_true()

	var opacity_before: float = vfx._trail_material.albedo_color.a
	assert_float(opacity_before) \
		.override_failure_message("AC-NEW-07: opacity avant settings_changed doit être ≈0.7 (KATANA_TRAIL_OPACITY_MAX × 1.0), got %f" % opacity_before) \
		.is_equal_approx(0.7, 0.001)

	# Changer reduce_motion → true + émettre settings_changed
	mock_accessibility.reduce_motion = true
	mock_accessibility.settings_changed.emit()
	await get_tree().process_frame  # DEFERRED tick
	await get_tree().process_frame  # safety

	# Assert vfx._reduce_motion mis à jour
	assert_bool(vfx._reduce_motion) \
		.override_failure_message("AC-NEW-07: _reduce_motion doit être true après settings_changed") \
		.is_true()

	# Assert trail opacity réduite à 0.35 (0.7 × 0.5 mid-swing live update)
	var opacity_after: float = vfx._trail_material.albedo_color.a
	assert_float(opacity_after) \
		.override_failure_message("AC-NEW-07: opacity après settings_changed(reduce_motion=true) doit être ≈0.35 (0.7 × 0.5), got %f" % opacity_after) \
		.is_equal_approx(0.35, 0.001)

	_free_all(nodes)
