# Tests unitaires Story-013 (camera) — CameraSettings Resource defaults + migration
# (TR-cam-006, ADR-0014 D-3/D-7).
#
# Couvre :
# - defaults factory : 3 properties values + _settings_version cohérent (mitigation Risk schema drift)
# - migrate_from(v0, raw) → version stamped + warning loggé (forward-only, ADR-0014 D-3)
# - migrate_from(CURRENT_VERSION, raw) → no-op identity
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Pure logic — aucun filesystem touché ici (lifecycle suite séparée).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Bonus AC — defaults factory cohérent
# ---------------------------------------------------------------------------

func test_camera_settings_defaults_has_correct_property_values() -> void:
	# Arrange / Act
	var s: CameraSettings = CameraSettings.create_defaults()

	# Assert — defaults canoniques GDD camera-system Tuning Knobs.
	assert_float(s.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	assert_bool(s.mouse_y_inverted).is_false()
	assert_float(s.fov_user_offset).is_equal_approx(0.0, 0.001)


func test_camera_settings_defaults_version_matches_current_version() -> void:
	# Arrange / Act
	var s: CameraSettings = CameraSettings.create_defaults()

	# Assert — mitigation Risk « schema drift » (ADR-0014 Risks).
	assert_int(s._settings_version).is_equal(CameraSettings.CURRENT_VERSION)


# ---------------------------------------------------------------------------
# AC-CAM-SAVE-2 — migration forward-only depuis version ancienne
# ---------------------------------------------------------------------------

func test_camera_settings_migrate_from_v0_stamps_current_version() -> void:
	# Arrange — instance v0 (raw legacy, simulant un load d'une version pre-MVP).
	var raw: CameraSettings = CameraSettings.new()
	raw._settings_version = 0
	raw.mouse_sensitivity = 0.0040
	raw.mouse_y_inverted = true
	raw.fov_user_offset = 5.0

	# Act
	var migrated: CameraSettings = CameraSettings.migrate_from(0, raw)

	# Assert — version stampée, valeurs domaine préservées (forward-only D-3).
	assert_object(migrated).is_not_null()
	assert_int(migrated._settings_version).is_equal(CameraSettings.CURRENT_VERSION)
	assert_float(migrated.mouse_sensitivity).is_equal_approx(0.0040, 0.00001)
	assert_bool(migrated.mouse_y_inverted).is_true()
	assert_float(migrated.fov_user_offset).is_equal_approx(5.0, 0.001)


func test_camera_settings_migrate_from_current_version_returns_unchanged() -> void:
	# Arrange — instance déjà à la version courante (cas nominal).
	var raw: CameraSettings = CameraSettings.create_defaults()
	raw.mouse_sensitivity = 0.0030

	# Act
	var migrated: CameraSettings = CameraSettings.migrate_from(
		CameraSettings.CURRENT_VERSION, raw
	)

	# Assert — identity.
	assert_object(migrated).is_same(raw)
	assert_float(migrated.mouse_sensitivity).is_equal_approx(0.0030, 0.00001)
	assert_int(migrated._settings_version).is_equal(CameraSettings.CURRENT_VERSION)
