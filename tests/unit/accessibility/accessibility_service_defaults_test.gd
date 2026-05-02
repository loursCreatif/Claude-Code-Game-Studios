# Tests unitaires Story-001 accessibility — AccessibilityService defaults invariant
# (AC-3) + reduce_motion derived getters (AC-4) + bornes clamping service-level (AC-5).
#
# Framework : GdUnit4. Pure logic — service instancié direct (suppress_settings_load=true)
# avec _settings injecté manuellement (defaults factory) — pas de filesystem touché.

extends GdUnitTestSuite

const AccessibilityServicePath: String = "res://src/core/accessibility_service.gd"


func _make_service_with_settings(settings: AccessibilitySettings) -> AccessibilityServiceScript:
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	svc._settings = settings
	auto_free(svc)
	return svc


# ---------------------------------------------------------------------------
# AC-3 — defaults invariant : 7 getters retournent valeurs neutres
# ---------------------------------------------------------------------------

func test_accessibility_service_defaults_invariant_neutral_getters() -> void:
	# Arrange
	var svc: AccessibilityServiceScript = _make_service_with_settings(
		AccessibilitySettings.create_defaults()
	)

	# Act / Assert — comportement bit-identique MVP non-accessibility (D-5).
	assert_bool(svc.is_reduce_motion_enabled()).is_false()
	assert_bool(svc.is_reduce_flash_enabled()).is_false()
	assert_bool(svc.get_disable_slow_mo()).is_false()
	assert_float(svc.get_slow_mo_scale_mult()).is_equal_approx(1.0, 0.001)
	assert_float(svc.get_flash_mult()).is_equal_approx(1.0, 0.001)
	assert_float(svc.get_camera_tilt_mult()).is_equal_approx(1.0, 0.001)
	assert_float(svc.get_camera_fov_kick_mult()).is_equal_approx(1.0, 0.001)
	assert_float(svc.get_camera_shake_mult()).is_equal_approx(1.0, 0.001)
	assert_int(svc.get_enemy_death_tween_ms()).is_equal(150)


func test_accessibility_service_null_settings_falls_back_to_neutral() -> void:
	# Arrange — service sans settings chargés (path "_settings == null").
	var svc: AccessibilityServiceScript = _make_service_with_settings(null)

	# Act / Assert — fallback gracieux (jamais crash, valeurs neutres).
	assert_bool(svc.is_reduce_motion_enabled()).is_false()
	assert_float(svc.get_slow_mo_scale_mult()).is_equal_approx(1.0, 0.001)
	assert_float(svc.get_camera_tilt_mult()).is_equal_approx(1.0, 0.001)
	assert_int(svc.get_enemy_death_tween_ms()).is_equal(150)


# ---------------------------------------------------------------------------
# AC-4 — reduce_motion derived getters (Camera Rule 14 + Enemy)
# ---------------------------------------------------------------------------

func test_accessibility_service_reduce_motion_derives_camera_multipliers() -> void:
	# Arrange — reduce_motion=true, autres defaults (multipliers=1.0).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	var svc: AccessibilityServiceScript = _make_service_with_settings(s)

	# Act / Assert — Camera Rule 14 (D-3 / D-7).
	assert_float(svc.get_camera_tilt_mult()).is_equal_approx(0.25, 0.001)
	assert_float(svc.get_camera_fov_kick_mult()).is_equal_approx(0.5, 0.001)
	assert_float(svc.get_camera_shake_mult()).is_equal_approx(0.0, 0.001)


func test_accessibility_service_reduce_motion_derives_enemy_death_tween_ms() -> void:
	# Arrange — reduce_motion=true, override=0 (sentinelle).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	var svc: AccessibilityServiceScript = _make_service_with_settings(s)

	# Act / Assert — 400 ms si reduce_motion (D-3).
	assert_int(svc.get_enemy_death_tween_ms()).is_equal(400)


func test_accessibility_service_enemy_death_tween_override_primes_over_derived() -> void:
	# Arrange — override=300, reduce_motion=true (override doit primer).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	s.enemy_death_tween_ms_override = 300
	var svc: AccessibilityServiceScript = _make_service_with_settings(s)

	# Act / Assert — override Tier 2+ prime sur derived rule.
	assert_int(svc.get_enemy_death_tween_ms()).is_equal(300)


# ---------------------------------------------------------------------------
# AC-5 — bornes clamping service-level (D-7)
# ---------------------------------------------------------------------------

func test_accessibility_service_slow_mo_scale_mult_clamps_above_max() -> void:
	# Arrange — out-of-range above (5.0 > 3.33).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 5.0
	var svc: AccessibilityServiceScript = _make_service_with_settings(s)

	# Act / Assert
	assert_float(svc.get_slow_mo_scale_mult()).is_equal_approx(3.33, 0.001)


func test_accessibility_service_slow_mo_scale_mult_clamps_below_min() -> void:
	# Arrange — out-of-range below (0.5 < 1.0, atténuation négative interdite).
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.slow_mo_scale_mult = 0.5
	var svc: AccessibilityServiceScript = _make_service_with_settings(s)

	# Act / Assert
	assert_float(svc.get_slow_mo_scale_mult()).is_equal_approx(1.0, 0.001)


func test_accessibility_service_flash_mult_clamps_to_unit_interval() -> void:
	# Arrange — 2 cas : above + below.
	var s_above: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s_above.flash_mult = 2.0
	var s_below: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s_below.flash_mult = -0.5

	# Act / Assert
	assert_float(_make_service_with_settings(s_above).get_flash_mult()).is_equal_approx(1.0, 0.001)
	assert_float(_make_service_with_settings(s_below).get_flash_mult()).is_equal_approx(0.0, 0.001)
