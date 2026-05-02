# Tests unitaires Story-010 (input) — InputSettings Resource defaults + migration
# (TR-inp-009, ADR-0014 D-3/D-7).
#
# Couvre :
# - AC-INP-SAVE-1 schema : 6 properties + _settings_version + factory + migration
# - bonus : defaults version match (mitigation schema drift)
# - bonus : migrate_from(v0) stamping forward-only
#
# Framework : GdUnit4 (extends GdUnitTestSuite). Pure logic — aucun filesystem.

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# AC-INP-SAVE-1 schema — 6 properties typées + factory defaults
# ---------------------------------------------------------------------------

func test_input_settings_defaults_has_six_properties_with_correct_values() -> void:
	# Arrange / Act
	var s: InputSettings = InputSettings.create_defaults()

	# Assert — defaults canoniques GDD input-system Tuning Knobs.
	assert_float(s.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	assert_bool(s.mouse_y_inverted).is_false()
	assert_bool(s.mouse_capture_at_boot).is_false()
	assert_int(s.focus_regain_window_ms).is_equal(50)
	assert_bool(s.debug_overlay_default).is_false()
	assert_float(s.latency_anomaly_threshold_ms).is_equal_approx(0.1, 0.001)


func test_input_settings_defaults_version_matches_current_version() -> void:
	# Arrange / Act
	var s: InputSettings = InputSettings.create_defaults()

	# Assert — mitigation Risk « schema drift » (ADR-0014 Risks).
	assert_int(s._settings_version).is_equal(InputSettings.CURRENT_VERSION)


# ---------------------------------------------------------------------------
# Migration forward-only (ADR-0014 D-3)
# ---------------------------------------------------------------------------

func test_input_settings_migrate_from_v0_stamps_current_version() -> void:
	# Arrange — instance legacy v0 avec valeurs custom.
	var raw: InputSettings = InputSettings.new()
	raw._settings_version = 0
	raw.mouse_sensitivity = 0.0035
	raw.mouse_y_inverted = true
	raw.focus_regain_window_ms = 80
	raw.debug_overlay_default = true

	# Act
	var migrated: InputSettings = InputSettings.migrate_from(0, raw)

	# Assert — forward-only : version stampée, domaine préservé.
	assert_object(migrated).is_not_null()
	assert_int(migrated._settings_version).is_equal(InputSettings.CURRENT_VERSION)
	assert_float(migrated.mouse_sensitivity).is_equal_approx(0.0035, 0.00001)
	assert_bool(migrated.mouse_y_inverted).is_true()
	assert_int(migrated.focus_regain_window_ms).is_equal(80)
	assert_bool(migrated.debug_overlay_default).is_true()


func test_input_settings_migrate_from_current_version_returns_unchanged() -> void:
	# Arrange — version courante (cas nominal).
	var raw: InputSettings = InputSettings.create_defaults()
	raw.focus_regain_window_ms = 75

	# Act
	var migrated: InputSettings = InputSettings.migrate_from(
		InputSettings.CURRENT_VERSION, raw
	)

	# Assert — identity, version inchangée.
	assert_object(migrated).is_same(raw)
	assert_int(migrated.focus_regain_window_ms).is_equal(75)
	assert_int(migrated._settings_version).is_equal(InputSettings.CURRENT_VERSION)
