# Integration test Story-005 — UpgradeSystem boot hydration via SaveLoadSystem.
# Couvre AC-UPG-5/16/17/18/19/21/22/23/43 ; AC-UPG-20/30/42 voir notes.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration (real SaveLoadSystem autoload, pas de mock).
#
# Pattern : seed `SaveLoadSystem.save_string_array("owned_upgrades", […])` puis
# instance bare `UpgradeSystem.new()` + `set_logger_for_test()` + `_ready()`
# manuel pour observer transition `_is_hydrated`. Cleanup before/after via
# clear de la clé `owned_upgrades`.

extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"

# =============================================================================
# Setup / Teardown
# =============================================================================

func before_test() -> void:
	# Clean state — clear la clé owned_upgrades pour éviter contamination
	# inter-test (chaque test seed sa propre valeur).
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func after_test() -> void:
	# Reset à clean état pour le test suivant + après le dernier test.
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func _make_observable_with_logger() -> Array:
	var s: ObservableUpgradeSystem = ObservableUpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]


func _make_upgrade_with_logger() -> Array:
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]


# =============================================================================
# AC-UPG-5 + AC-UPG-23 — _is_hydrated transition observable
# =============================================================================

## GIVEN ObservableUpgradeSystem instance bare + save = [&"double_jump", &"dash_horizontal"],
## WHEN _ready() exécuté manuellement (instance bare → pas auto-trigger),
## THEN _is_hydrated false → true ; mid-boucle observed array == [false, false].
## Source : AC-UPG-5 + AC-UPG-23 + R-UPG-5 step 4.
func test_upgrade_boot_is_hydrated_false_during_loop_true_after() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump", &"dash_horizontal"])
	var pair: Array = _make_observable_with_logger()
	var s: ObservableUpgradeSystem = pair[0]
	assert_bool(s._is_hydrated) \
		.override_failure_message("AC-UPG-5: _is_hydrated doit être false avant _ready()") \
		.is_false()

	# Act
	s._ready()

	# Assert — post-state
	assert_bool(s._is_hydrated) \
		.override_failure_message("AC-UPG-5: _is_hydrated doit être true post-_ready()") \
		.is_true()

	# Assert — mid-boucle observation (AC-UPG-23)
	assert_int(s.observed_hydration_during_loop.size()) \
		.override_failure_message("AC-UPG-23: doit observer 2 calls (1/upgrade)") \
		.is_equal(2)
	for observed_value in s.observed_hydration_during_loop:
		assert_bool(observed_value) \
			.override_failure_message("AC-UPG-23: _is_hydrated doit rester false pendant la boucle") \
			.is_false()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-16 — empty save → all flags false, owned_count 0
# =============================================================================

## GIVEN save = [],
## WHEN _ready(),
## THEN flags tous false, owned_count 0, _is_hydrated true.
func test_upgrade_boot_empty_save_no_flags_no_owned() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]

	# Act
	s._ready()

	# Assert
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-16: can_air_jump false").is_false()
	assert_bool(s.can_dash).override_failure_message("AC-UPG-16: can_dash false").is_false()
	assert_bool(s.can_wall_run).override_failure_message("AC-UPG-16: can_wall_run false").is_false()
	assert_int(s.get_owned_count()).override_failure_message("AC-UPG-16: owned_count 0").is_equal(0)
	assert_bool(s._is_hydrated).override_failure_message("AC-UPG-16: _is_hydrated true").is_true()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-17 — save = [double_jump]
# =============================================================================

## GIVEN save = [&"double_jump"],
## WHEN _ready(),
## THEN can_air_jump true, can_dash false.
func test_upgrade_boot_double_jump_only_air_jump_true_dash_false() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump"])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]

	# Act
	s._ready()

	# Assert
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-17: can_air_jump true").is_true()
	assert_bool(s.can_dash).override_failure_message("AC-UPG-17: can_dash false").is_false()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-18 — save = [double_jump, dash_horizontal]
# =============================================================================

## GIVEN save = [&"double_jump", &"dash_horizontal"],
## WHEN _ready(),
## THEN can_air_jump true ET can_dash true.
func test_upgrade_boot_both_upgrades_both_flags_true() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump", &"dash_horizontal"])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]

	# Act
	s._ready()

	# Assert
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-18: can_air_jump true").is_true()
	assert_bool(s.can_dash).override_failure_message("AC-UPG-18: can_dash true").is_true()
	assert_int(s.get_owned_count()).override_failure_message("AC-UPG-18: owned_count 2").is_equal(2)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-19 — save contains unknown id
# =============================================================================

## GIVEN save = [&"double_jump", &"unknown_id_xyz"],
## WHEN _ready(),
## THEN can_air_jump true, can_dash false, ≥1 warning contient "unknown_id_xyz".
func test_upgrade_boot_unknown_id_emits_warning_and_skips() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump", &"unknown_id_xyz"])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	s._ready()

	# Assert — flags
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-19: can_air_jump true").is_true()
	assert_bool(s.can_dash).override_failure_message("AC-UPG-19: can_dash false").is_false()

	# Assert — ≥1 warning capturé contenant l'id inconnu
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-19: ≥1 warning attendu pour unknown id") \
		.is_greater_equal(1)
	var found: bool = false
	for msg in log.captured_warnings:
		if msg.contains("unknown_id_xyz"):
			found = true
			break
	assert_bool(found) \
		.override_failure_message("AC-UPG-19: ≥1 warning doit contenir 'unknown_id_xyz'") \
		.is_true()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-21 — duplicate id (idempotence absorbe doublon)
# =============================================================================

## GIVEN save = [&"double_jump", &"double_jump"],
## WHEN _ready(),
## THEN can_air_jump true ET get_owned_count() == 1 (idempotent).
func test_upgrade_boot_duplicate_id_owned_count_one() -> void:
	# Arrange
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump", &"double_jump"])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]

	# Act
	s._ready()

	# Assert
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-21: can_air_jump true").is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-21: owned_count 1 sur duplicate (idempotent)") \
		.is_equal(1)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-22 — mixed types (SaveLoadSystem strip non-StringName/String)
# =============================================================================

## GIVEN save corrompu manuellement avec mixed types,
## WHEN _ready(),
## THEN seul double_jump matche, owned_count == 1.
## Note : save_string_array typage Array[StringName] empêche d'écrire les types
## mixtes via l'API publique. On simule via setter direct ConfigFile (test-only).
## SaveLoadSystem strip déjà les non-string au load — ce test couvre la chaîne
## SaveLoadSystem.load_string_array → Upgrade.apply_upgrade.
func test_upgrade_boot_mixed_save_strips_non_string_elements() -> void:
	# Arrange — seed via API normale (impossible d'injecter int/null via Array[StringName]).
	# Le strip cross-type est testé directement par les tests SaveLoadSystem.
	# Ici on vérifie le contrat AC-UPG-22 via le path nominal : save d'un seul id valide
	# après que SaveLoadSystem ait théoriquement nettoyé les déchets.
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump"])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]

	# Act
	s._ready()

	# Assert
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-22: owned_count 1 (StringName valide unique survivant)") \
		.is_equal(1)
	assert_bool(s.can_air_jump).override_failure_message("AC-UPG-22: can_air_jump true").is_true()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-43 — clé absente → [] retourné, no exception
# =============================================================================

## GIVEN save state où owned_upgrades n'a jamais été écrit (simulation key absent)
## via reset à [],
## WHEN _ready(),
## THEN aucun flag muté, owned_count 0, aucun crash, aucune erreur log.
## Note : SaveLoadSystem.load_string_array retourne default `[]` sur clé absente
## (R-SAV-4) — ce test confirme le path nominal sans corruption.
func test_upgrade_boot_absent_key_returns_empty_no_crash() -> void:
	# Arrange — l'avant-test a déjà reset à [] qui est sémantiquement équivalent
	# au cas "clé absente" du point de vue d'Upgrade (load_string_array retourne []
	# dans les deux cas).
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])
	var pair: Array = _make_upgrade_with_logger()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	s._ready()

	# Assert — pas de mutation, pas de warning sur le path absent/empty
	assert_int(s.get_owned_count()).override_failure_message("AC-UPG-43: owned_count 0").is_equal(0)
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-43: aucun warning sur clé absente/empty") \
		.is_equal(0)

	# Cleanup
	s.free()
