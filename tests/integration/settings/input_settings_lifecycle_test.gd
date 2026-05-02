# Tests d'intégration Story-010 (input) — InputSettings lifecycle via SettingsResource
# (TR-inp-009, ADR-0014 D-2/D-4/D-5).
#
# Couvre :
# - AC-INP-SAVE-2 (boot load via InputManager._ready propage aux runtime properties)
# - AC-INP-SAVE-3 (save_settings() écrit le fichier)
# - AC-P-1 (round-trip identity 6 properties)
# - AC-P-2 (first launch defaults silent)
# - AC-P-3 (corruption fallback : defaults + warning + pas de réécriture boot)
#
# Framework : GdUnit4. Touche `user://settings/test_input.tres` + `user://settings/input.tres`
# pour le test boot-via-InputManager (cleanup before+after).

extends GdUnitTestSuite

const _TEST_SYSTEM: String = "test_input"
const _TEST_FILE_PATH: String = "user://settings/test_input.tres"
const _PROD_FILE_PATH: String = "user://settings/input.tres"


# ---------------------------------------------------------------------------
# Hermetic teardown — cleanup test_input.tres + input.tres (boot test)
# ---------------------------------------------------------------------------

func before_test() -> void:
	_remove("test_input.tres")
	_remove("input.tres")


func after_test() -> void:
	_remove("test_input.tres")
	_remove("input.tres")


func _remove(filename: String) -> void:
	var path: String = "user://settings/" + filename
	if FileAccess.file_exists(path):
		var dir: DirAccess = DirAccess.open("user://settings/")
		if dir != null:
			dir.remove(filename)


# ---------------------------------------------------------------------------
# AC-P-1 — round-trip identity sur les 6 properties
# ---------------------------------------------------------------------------

func test_input_settings_round_trip_identity_preserves_six_properties() -> void:
	# Arrange — instance avec valeurs custom sur les 6 properties.
	var s: InputSettings = InputSettings.create_defaults()
	s.mouse_sensitivity = 0.0050
	s.mouse_y_inverted = true
	s.mouse_capture_at_boot = true
	s.focus_regain_window_ms = 90
	s.debug_overlay_default = true
	s.latency_anomaly_threshold_ms = 0.25

	# Act
	var err: Error = SettingsResource.save(s, _TEST_SYSTEM)
	assert_int(err).is_equal(OK)
	var loaded: InputSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(InputSettings, "create_defaults"),
		Callable(InputSettings, "migrate_from"),
	) as InputSettings

	# Assert
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0050, 0.00001)
	assert_bool(loaded.mouse_y_inverted).is_true()
	assert_bool(loaded.mouse_capture_at_boot).is_true()
	assert_int(loaded.focus_regain_window_ms).is_equal(90)
	assert_bool(loaded.debug_overlay_default).is_true()
	assert_float(loaded.latency_anomaly_threshold_ms).is_equal_approx(0.25, 0.001)
	assert_int(loaded._settings_version).is_equal(InputSettings.CURRENT_VERSION)


# ---------------------------------------------------------------------------
# AC-P-2 — first launch silent defaults
# ---------------------------------------------------------------------------

func test_input_settings_first_launch_returns_silent_defaults() -> void:
	# Arrange — fichier absent.
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_false()

	# Act
	var loaded: InputSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(InputSettings, "create_defaults"),
		Callable(InputSettings, "migrate_from"),
	) as InputSettings

	# Assert — defaults canoniques GDD.
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	assert_int(loaded.focus_regain_window_ms).is_equal(50)
	# Pas de fichier créé au load — D-6 save explicit only.
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_false()


# ---------------------------------------------------------------------------
# AC-P-3 — corruption fallback sans réécriture boot
# ---------------------------------------------------------------------------

func test_input_settings_corruption_returns_defaults_and_does_not_rewrite() -> void:
	# Arrange — fichier corrompu.
	if not DirAccess.dir_exists_absolute("user://settings/"):
		DirAccess.make_dir_recursive_absolute("user://settings/")
	var fa: FileAccess = FileAccess.open(_TEST_FILE_PATH, FileAccess.WRITE)
	assert_object(fa).is_not_null()
	fa.store_string("garbage bytes — not a valid resource header")
	fa.close()
	var corrupted_size: int = FileAccess.get_file_as_bytes(_TEST_FILE_PATH).size()

	# Act
	var loaded: InputSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(InputSettings, "create_defaults"),
		Callable(InputSettings, "migrate_from"),
	) as InputSettings

	# Assert — defaults retournés.
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	# Fichier corrompu reste sur disque (D-4 anti-debug).
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_true()
	var post_size: int = FileAccess.get_file_as_bytes(_TEST_FILE_PATH).size()
	assert_int(post_size).is_equal(corrupted_size)


# ---------------------------------------------------------------------------
# AC-INP-SAVE-2 — boot load via InputManager propage aux runtime properties
# ---------------------------------------------------------------------------

## GIVEN un fichier user://settings/input.tres avec valeurs custom,
## WHEN un InputManager frais est instancié et atteint _ready(),
## THEN les Tuning Knobs persistés sont propagés à `mouse_sensitivity`,
## `mouse_y_inverted` et `_focus_regain_window_usec`.
func test_input_manager_ready_propagates_persisted_settings_to_runtime_properties() -> void:
	# Arrange — écris un input.tres custom AVANT instanciation InputManager.
	var persisted: InputSettings = InputSettings.create_defaults()
	persisted.mouse_sensitivity = 0.0070
	persisted.mouse_y_inverted = true
	persisted.focus_regain_window_ms = 120
	var save_err: Error = SettingsResource.save(persisted, "input")
	assert_int(save_err).is_equal(OK)

	# Act — instancier un InputManager frais (ne pas réutiliser l'autoload qui a
	# déjà loadé au boot du test runner). suppress_debug_overlay évite la pollution.
	var manager: InputManagerScript = InputManagerScript.new()
	manager.suppress_debug_overlay = true
	add_child(manager)
	# _ready() s'exécute sur add_child().

	# Assert — runtime properties propagées depuis InputSettings.
	assert_object(manager.settings).is_not_null()
	assert_float(manager.mouse_sensitivity).is_equal_approx(0.0070, 0.00001)
	assert_bool(manager.mouse_y_inverted).is_true()
	# focus_regain_window_ms (120) → _focus_regain_window_usec (120_000).
	assert_int(manager._focus_regain_window_usec).is_equal(120_000)

	# Cleanup
	manager.queue_free()


# ---------------------------------------------------------------------------
# AC-INP-SAVE-3 — save_settings() délégué à SettingsResource
# ---------------------------------------------------------------------------

## GIVEN un InputManager avec settings modifiés en runtime,
## WHEN save_settings() invoqué, THEN le fichier prod est écrit ET reload identique.
func test_input_manager_save_settings_writes_file_with_runtime_values() -> void:
	# Arrange
	var manager: InputManagerScript = InputManagerScript.new()
	manager.suppress_debug_overlay = true
	add_child(manager)
	# Modifie une property persistée puis sauvegarde.
	manager.settings.mouse_sensitivity = 0.0095
	manager.settings.focus_regain_window_ms = 60

	# Act
	var err: Error = manager.save_settings()

	# Assert — write success + content reload identique.
	assert_int(err).is_equal(OK)
	assert_bool(FileAccess.file_exists(_PROD_FILE_PATH)).is_true()
	var reloaded: InputSettings = SettingsResource.load_or_default(
		"input",
		Callable(InputSettings, "create_defaults"),
		Callable(InputSettings, "migrate_from"),
	) as InputSettings
	assert_float(reloaded.mouse_sensitivity).is_equal_approx(0.0095, 0.00001)
	assert_int(reloaded.focus_regain_window_ms).is_equal(60)

	# Cleanup
	manager.queue_free()


## GIVEN un InputManager avec suppress_settings_load=true (settings == null),
## WHEN save_settings() invoqué, THEN retourne ERR_UNCONFIGURED, pas de crash.
func test_input_manager_save_settings_returns_unconfigured_when_suppressed() -> void:
	# Arrange
	var manager: InputManagerScript = InputManagerScript.new()
	manager.suppress_debug_overlay = true
	manager.suppress_settings_load = true
	add_child(manager)

	# Act
	var err: Error = manager.save_settings()

	# Assert
	assert_int(err).is_equal(ERR_UNCONFIGURED)
	assert_object(manager.settings).is_null()

	# Cleanup
	manager.queue_free()
