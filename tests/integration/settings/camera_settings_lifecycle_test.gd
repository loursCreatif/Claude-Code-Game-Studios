# Tests d'intégration Story-013 — CameraSettings lifecycle via SettingsResource
# (ADR-0014 D-2 path canonique, D-4 corruption fallback, D-5 helper static class).
#
# Couvre :
# - AC-CAM-SAVE-1 (save serializes 3 values + _settings_version)
# - AC-CAM-SAVE-3 (corruption fallback : defaults + warning + pas de réécriture boot)
# - AC-CAM-SAVE-4 (first launch : defaults SILENT + sub-folder bootstrap idempotent)
# - bonus round-trip identity (full lifecycle)
#
# Framework : GdUnit4 (extends GdUnitTestSuite). Touche `user://settings/test_camera.tres`.
# Cleanup before+after pour isolation cross-test (ADR-0014 Risks « test pollution »).
#
# Convention : utilise `test_camera` comme system name (pas `camera`) pour ne pas
# polluer le fichier prod camera.tres si un dev lance les tests en local.

extends GdUnitTestSuite

const _TEST_SYSTEM: String = "test_camera"
const _TEST_FILE_PATH: String = "user://settings/test_camera.tres"


# ---------------------------------------------------------------------------
# Hermetic teardown — supprime le fichier de test avant et après chaque test
# ---------------------------------------------------------------------------

func before_test() -> void:
	_remove_test_file()


func after_test() -> void:
	_remove_test_file()


func _remove_test_file() -> void:
	if FileAccess.file_exists(_TEST_FILE_PATH):
		var dir: DirAccess = DirAccess.open("user://settings/")
		if dir != null:
			dir.remove("test_camera.tres")


# ---------------------------------------------------------------------------
# AC-CAM-SAVE-1 — save sérialise les 3 valeurs + _settings_version
# ---------------------------------------------------------------------------

## GIVEN custom values, WHEN save → reload, THEN values identiques + version stampée.
func test_camera_settings_save_serializes_three_values_with_version() -> void:
	# Arrange
	var s: CameraSettings = CameraSettings.create_defaults()
	s.mouse_sensitivity = 0.0040
	s.mouse_y_inverted = true
	s.fov_user_offset = 5.0

	# Act — save explicit puis reload via helper.
	var err: Error = SettingsResource.save(s, _TEST_SYSTEM)
	assert_int(err).is_equal(OK)
	var loaded: CameraSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings

	# Assert — round-trip identité + version cohérente.
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0040, 0.00001)
	assert_bool(loaded.mouse_y_inverted).is_true()
	assert_float(loaded.fov_user_offset).is_equal_approx(5.0, 0.001)
	assert_int(loaded._settings_version).is_equal(CameraSettings.CURRENT_VERSION)


# ---------------------------------------------------------------------------
# AC-CAM-SAVE-3 — corruption fallback : defaults + pas de réécriture boot
# ---------------------------------------------------------------------------

## GIVEN fichier corrompu (bytes garbage), WHEN load_or_default,
## THEN defaults retournés ET fichier corrompu reste sur disque (D-4 anti-debug).
func test_camera_settings_corruption_returns_defaults_and_does_not_rewrite() -> void:
	# Arrange — fabrique un fichier corrompu (header invalide).
	# DirAccess.make_dir_recursive_absolute pour s'assurer que le sub-folder existe.
	if not DirAccess.dir_exists_absolute("user://settings/"):
		DirAccess.make_dir_recursive_absolute("user://settings/")
	var fa: FileAccess = FileAccess.open(_TEST_FILE_PATH, FileAccess.WRITE)
	assert_object(fa).is_not_null()
	fa.store_string("not a valid godot resource — corrupted bytes [random garbage]")
	fa.close()
	# Capture longueur du fichier corrompu pour vérifier non-réécriture après load.
	var corrupted_size: int = FileAccess.get_file_as_bytes(_TEST_FILE_PATH).size()

	# Act
	var loaded: CameraSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings

	# Assert — defaults appliqués (D-4 fallback path).
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	assert_bool(loaded.mouse_y_inverted).is_false()
	assert_float(loaded.fov_user_offset).is_equal_approx(0.0, 0.001)
	assert_int(loaded._settings_version).is_equal(CameraSettings.CURRENT_VERSION)
	# Assert — fichier corrompu inchangé (D-4 : pas de rewrite-on-boot).
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_true()
	var post_size: int = FileAccess.get_file_as_bytes(_TEST_FILE_PATH).size()
	assert_int(post_size).is_equal(corrupted_size)


# ---------------------------------------------------------------------------
# AC-CAM-SAVE-4 — first launch silent defaults + sub-folder bootstrap idempotent
# ---------------------------------------------------------------------------

## GIVEN fichier absent, WHEN load_or_default, THEN defaults silencieux + dir créé.
func test_camera_settings_first_launch_returns_defaults_and_creates_subfolder() -> void:
	# Arrange — fichier absent garanti par before_test().
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_false()

	# Act
	var loaded: CameraSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings

	# Assert — defaults appliqués.
	assert_object(loaded).is_not_null()
	assert_float(loaded.mouse_sensitivity).is_equal_approx(0.0022, 0.00001)
	assert_int(loaded._settings_version).is_equal(CameraSettings.CURRENT_VERSION)
	# Assert — sub-folder créé idempotent (D-2 _ensure_dir).
	assert_bool(DirAccess.dir_exists_absolute("user://settings/")).is_true()
	# Assert — pas de fichier créé au load (création seulement au premier save explicit, D-6).
	assert_bool(FileAccess.file_exists(_TEST_FILE_PATH)).is_false()


## GIVEN call _ensure_dir() N fois, THEN aucune erreur (idempotent).
func test_settings_resource_ensure_dir_is_idempotent() -> void:
	# Act — 3 calls successifs ne doivent pas faire planter, ni warning bloquant.
	# Wrapper via load_or_default qui appelle _ensure_dir interne.
	for i: int in 3:
		var s: CameraSettings = SettingsResource.load_or_default(
			_TEST_SYSTEM,
			Callable(CameraSettings, "create_defaults"),
			Callable(CameraSettings, "migrate_from"),
		) as CameraSettings
		assert_object(s).is_not_null()
	assert_bool(DirAccess.dir_exists_absolute("user://settings/")).is_true()


# ---------------------------------------------------------------------------
# Bonus — round-trip identity full lifecycle
# ---------------------------------------------------------------------------

## Save custom values → load fresh helper → asserte égalité champ-à-champ.
func test_camera_settings_round_trip_identity_preserves_all_values() -> void:
	# Arrange
	var s: CameraSettings = CameraSettings.create_defaults()
	s.mouse_sensitivity = 0.0085
	s.mouse_y_inverted = true
	s.fov_user_offset = -7.5

	# Act
	var save_err: Error = SettingsResource.save(s, _TEST_SYSTEM)
	assert_int(save_err).is_equal(OK)
	var loaded: CameraSettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings

	# Assert — identité complète.
	assert_float(loaded.mouse_sensitivity).is_equal_approx(s.mouse_sensitivity, 0.00001)
	assert_bool(loaded.mouse_y_inverted).is_equal(s.mouse_y_inverted)
	assert_float(loaded.fov_user_offset).is_equal_approx(s.fov_user_offset, 0.001)
	assert_int(loaded._settings_version).is_equal(s._settings_version)
