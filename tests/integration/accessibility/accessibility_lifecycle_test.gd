# Tests d'intégration Story-001 accessibility — AccessibilityService lifecycle
# (AC-6 apply_settings + signal, AC-7 save_settings round-trip, AC-8 OS bridge OR-merge,
# AC-9 outbound-zero static check).
#
# Framework : GdUnit4. Touche `user://settings/test_accessibility.tres` +
# `user://settings/accessibility.tres` pour le test save (cleanup before+after).

extends GdUnitTestSuite

const _TEST_SYSTEM: String = "test_accessibility"
const _TEST_FILE_PATH: String = "user://settings/test_accessibility.tres"
const _PROD_FILE_PATH: String = "user://settings/accessibility.tres"
const AccessibilityServicePath: String = "res://src/core/accessibility_service.gd"


# ---------------------------------------------------------------------------
# Hermetic teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	_remove("test_accessibility.tres")
	_remove("accessibility.tres")


func after_test() -> void:
	_remove("test_accessibility.tres")
	_remove("accessibility.tres")


func _remove(filename: String) -> void:
	var path: String = "user://settings/" + filename
	if FileAccess.file_exists(path):
		var dir: DirAccess = DirAccess.open("user://settings/")
		if dir != null:
			dir.remove(filename)


# ---------------------------------------------------------------------------
# AC-6 — apply_settings mute _settings + émet signal_changed
# ---------------------------------------------------------------------------

func test_accessibility_service_apply_settings_emits_settings_changed_once() -> void:
	# Arrange
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	auto_free(svc)
	# Closures GDScript capturent les primitifs par valeur — utiliser un Array
	# référence-typed pour incrémenter le compteur depuis la lambda.
	var emit_count: Array[int] = [0]
	svc.settings_changed.connect(func() -> void: emit_count[0] += 1)
	var new_settings: AccessibilitySettings = AccessibilitySettings.create_defaults()
	new_settings.reduce_motion = true

	# Act
	svc.apply_settings(new_settings)

	# Assert — signal émis exactement 1 fois, _settings muté.
	assert_int(emit_count[0]).is_equal(1)
	assert_bool(svc.is_reduce_motion_enabled()).is_true()


# ---------------------------------------------------------------------------
# AC-7 — save_settings round-trip identity (9 properties)
# ---------------------------------------------------------------------------

func test_accessibility_settings_round_trip_identity_preserves_nine_properties() -> void:
	# Arrange — settings avec valeurs custom sur 9 properties.
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	s.reduce_flash = true
	s.slow_mo_scale_mult = 2.5
	s.disable_slow_mo = true
	s.flash_mult = 0.3
	s.tilt_mult = 0.7
	s.fov_kick_mult = 0.6
	s.shake_mult = 0.2
	s.enemy_death_tween_ms_override = 350

	# Act
	var err: Error = SettingsResource.save(s, _TEST_SYSTEM)
	assert_int(err).is_equal(OK)
	var loaded: AccessibilitySettings = SettingsResource.load_or_default(
		_TEST_SYSTEM,
		Callable(AccessibilitySettings, "create_defaults"),
		Callable(AccessibilitySettings, "migrate_from"),
	) as AccessibilitySettings

	# Assert — 9 properties bit-identiques.
	assert_object(loaded).is_not_null()
	assert_bool(loaded.reduce_motion).is_true()
	assert_bool(loaded.reduce_flash).is_true()
	assert_float(loaded.slow_mo_scale_mult).is_equal_approx(2.5, 0.001)
	assert_bool(loaded.disable_slow_mo).is_true()
	assert_float(loaded.flash_mult).is_equal_approx(0.3, 0.001)
	assert_float(loaded.tilt_mult).is_equal_approx(0.7, 0.001)
	assert_float(loaded.fov_kick_mult).is_equal_approx(0.6, 0.001)
	assert_float(loaded.shake_mult).is_equal_approx(0.2, 0.001)
	assert_int(loaded.enemy_death_tween_ms_override).is_equal(350)
	assert_int(loaded._settings_version).is_equal(AccessibilitySettings.CURRENT_VERSION)


func test_accessibility_service_save_settings_writes_prod_file() -> void:
	# Arrange — service avec settings custom.
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	auto_free(svc)
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	s.flash_mult = 0.4
	svc._settings = s

	# Act
	var err: Error = svc.save_settings()

	# Assert — fichier écrit, content reload identique.
	assert_int(err).is_equal(OK)
	assert_bool(FileAccess.file_exists(_PROD_FILE_PATH)).is_true()
	var reloaded: AccessibilitySettings = SettingsResource.load_or_default(
		"accessibility",
		Callable(AccessibilitySettings, "create_defaults"),
		Callable(AccessibilitySettings, "migrate_from"),
	) as AccessibilitySettings
	assert_bool(reloaded.reduce_motion).is_true()
	assert_float(reloaded.flash_mult).is_equal_approx(0.4, 0.001)


func test_accessibility_service_save_settings_returns_unconfigured_when_suppressed() -> void:
	# Arrange — service avec settings null (suppress_settings_load=true, _settings reste null).
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	auto_free(svc)

	# Act
	var err: Error = svc.save_settings()

	# Assert
	assert_int(err).is_equal(ERR_UNCONFIGURED)


# ---------------------------------------------------------------------------
# AC-8 — OS bridge OR-merge (jamais downgrade)
# ---------------------------------------------------------------------------

func test_accessibility_service_or_merge_never_downgrades_user_toggle() -> void:
	# Arrange — user toggle reduce_motion=true, OS = peu importe.
	# Sémantique D-6 : OR-merge n'efface jamais user opt-in.
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	auto_free(svc)
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	s.reduce_motion = true
	svc._settings = s

	# Act — appel direct du bridge (cohérent _ready() flow).
	svc._apply_os_bridge()

	# Assert — reste true (jamais downgrade).
	assert_bool(svc.is_reduce_motion_enabled()).is_true()


func test_accessibility_service_or_merge_promotes_when_os_reports_reduce_motion() -> void:
	# Arrange — user toggle false, OS test-only :
	# si OS.is_reduce_motion_enabled() retourne true sur le runner CI, le bridge
	# doit promouvoir reduce_motion → true. Si OS retourne false, il reste false
	# (test conditionnel — vérifie sémantique OR-merge sans dépendre du host).
	var svc: AccessibilityServiceScript = load(AccessibilityServicePath).new()
	svc.suppress_settings_load = true
	auto_free(svc)
	var s: AccessibilitySettings = AccessibilitySettings.create_defaults()
	# user toggle = false (default)
	svc._settings = s
	var os_reports_reduce_motion: bool = (
		OS.has_method("is_reduce_motion_enabled")
		and bool(OS.call("is_reduce_motion_enabled"))
	)

	# Act
	svc._apply_os_bridge()

	# Assert — sémantique OR : effective == OS report (user=false).
	assert_bool(svc.is_reduce_motion_enabled()).is_equal(os_reports_reduce_motion)


# ---------------------------------------------------------------------------
# AC-9 — outbound-zero (static check sur file content)
# ---------------------------------------------------------------------------

func test_accessibility_service_does_not_reference_any_consumer() -> void:
	# Arrange — load file content.
	var fa: FileAccess = FileAccess.open(AccessibilityServicePath, FileAccess.READ)
	assert_object(fa).is_not_null()
	var content: String = fa.get_as_text()
	fa.close()
	var forbidden_refs: PackedStringArray = [
		"CameraSystem",
		"CombatSystem",
		"MovementController",
		"EnemySystem",
		"VFXManager",
		"HUDController",
	]

	# Act / Assert — D-8 outbound-zero : aucune référence consumer.
	for ref: String in forbidden_refs:
		assert_str(content).not_contains(ref)
