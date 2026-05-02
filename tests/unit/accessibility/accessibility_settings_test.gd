# Tests unitaires Story-001 accessibility — AccessibilitySettings Resource defaults + migration.
# Couvre AC-2 (schema 9 properties + factory + migration forward-only ADR-0014 D-3).
#
# Framework : GdUnit4. Pure logic — aucun filesystem touché.

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# AC-2 — defaults factory cohérent (schema 9 properties)
# ---------------------------------------------------------------------------

func test_accessibility_settings_defaults_has_safe_invariant_values() -> void:
	# Arrange / Act
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()

	# Assert — defaults D-5 invariant (tous flags OFF / multipliers=1.0 / override=0).
	assert_bool(s.reduce_motion).is_false()
	assert_bool(s.reduce_flash).is_false()
	assert_float(s.slow_mo_scale_mult).is_equal_approx(1.0, 0.001)
	assert_bool(s.disable_slow_mo).is_false()
	assert_float(s.flash_mult).is_equal_approx(1.0, 0.001)
	assert_float(s.tilt_mult).is_equal_approx(1.0, 0.001)
	assert_float(s.fov_kick_mult).is_equal_approx(1.0, 0.001)
	assert_float(s.shake_mult).is_equal_approx(1.0, 0.001)
	assert_int(s.enemy_death_tween_ms_override).is_equal(0)


func test_accessibility_settings_defaults_version_matches_current_version() -> void:
	# Arrange / Act
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()

	# Assert — mitigation Risk « schema drift » (ADR-0014 Risks).
	assert_int(s._settings_version).is_equal(AccessibilitySettings.CURRENT_VERSION)


# ---------------------------------------------------------------------------
# AC-2 — migration forward-only ADR-0014 D-3
# ---------------------------------------------------------------------------

func test_accessibility_settings_migrate_from_v0_stamps_current_version() -> void:
	# Arrange — instance v0 (raw legacy).
	var raw: AccessibilitySettings = AccessibilitySettings.new()
	raw._settings_version = 0
	raw.reduce_motion = true
	raw.flash_mult = 0.5

	# Act
	var migrated: AccessibilitySettings = AccessibilitySettings.migrate_from(0, raw)

	# Assert — version stampée, valeurs domaine préservées (forward-only D-3).
	assert_object(migrated).is_not_null()
	assert_int(migrated._settings_version).is_equal(AccessibilitySettings.CURRENT_VERSION)
	assert_bool(migrated.reduce_motion).is_true()
	assert_float(migrated.flash_mult).is_equal_approx(0.5, 0.001)


func test_accessibility_settings_migrate_from_current_version_returns_unchanged() -> void:
	# Arrange — instance déjà à version courante.
	var raw: AccessibilitySettings = AccessibilitySettings.create_defaults()
	raw.reduce_motion = true

	# Act
	var migrated: AccessibilitySettings = AccessibilitySettings.migrate_from(
		AccessibilitySettings.CURRENT_VERSION, raw
	)

	# Assert — identity.
	assert_object(migrated).is_same(raw)
	assert_bool(migrated.reduce_motion).is_true()
	assert_int(migrated._settings_version).is_equal(AccessibilitySettings.CURRENT_VERSION)
