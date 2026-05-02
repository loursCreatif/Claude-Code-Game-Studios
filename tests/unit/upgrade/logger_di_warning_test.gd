# Unit test Story-002 — UpgradeSystem Logger DI + unknown id warning.
# Couvre AC-UPG-10 (unknown id → warning capturé, zero flag muté, owned_count == 0)
# et AC-UPG-11 (StringName vide → no crash + warning capturé).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (instance bare, pas l'autoload — évite contamination cross-test).

extends GdUnitTestSuite

# =============================================================================
# Helpers
# =============================================================================

func _make_system_with_test_logger() -> Array:
	# Instance bare + logger fixture injecté avant tout apply_upgrade.
	# Skip _ready() autoload path : assignation directe _logger pour bypass
	# initialisation default UpgradeLogger.new() qui écraserait l'injection.
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]

# =============================================================================
# AC-UPG-10 — unknown upgrade id → warning capturé + zero mutation
# =============================================================================

## GIVEN UpgradeSystem instance bare avec TestUpgradeLogger injecté,
## WHEN apply_upgrade(&"nonexistent_id") sur id absent du _CATALOG,
## THEN logger capture exactement 1 warning contenant "unknown" + l'id,
## AND aucun flag capability ne mute, AND get_owned_count() == 0.
## Source : AC-UPG-10, R-UPG-9 (id inconnu → push_warning + early return).
func test_upgrade_apply_unknown_id_captures_warning_and_no_mutation() -> void:
	# Arrange
	var pair: Array = _make_system_with_test_logger()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	s.apply_upgrade(&"nonexistent_id")

	# Assert — exactement 1 warning capturé
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-10: doit capturer exactement 1 warning unknown id") \
		.is_equal(1)

	# Assert — message contient marqueur "unknown" (FR/EN tolérant) ET l'id source
	var msg: String = log.captured_warnings[0]
	var has_marker: bool = msg.contains("unknown") or msg.contains("inconnu")
	assert_bool(has_marker) \
		.override_failure_message("AC-UPG-10: warning doit contenir 'unknown' ou 'inconnu' — got: %s" % msg) \
		.is_true()
	assert_str(msg) \
		.override_failure_message("AC-UPG-10: warning doit contenir l'id source 'nonexistent_id'") \
		.contains("nonexistent_id")

	# Assert — zero flag muté
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-10: can_air_jump doit rester false") \
		.is_false()
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-10: can_dash doit rester false") \
		.is_false()
	assert_bool(s.can_wall_run) \
		.override_failure_message("AC-UPG-10: can_wall_run doit rester false") \
		.is_false()

	# Assert — owned count zéro (R-UPG-9 early return AVANT _owned mutation)
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-10: get_owned_count() doit être 0 sur id inconnu") \
		.is_equal(0)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-11 — StringName("") empty → no crash + warning capturé
# =============================================================================

## GIVEN UpgradeSystem instance bare avec TestUpgradeLogger injecté,
## WHEN apply_upgrade(StringName("")) sur StringName vide (edge),
## THEN aucun crash, AND logger capture >= 1 warning, AND aucun flag muté.
## Source : AC-UPG-11, R-UPG-9 (StringName vide traité comme id inconnu).
func test_upgrade_apply_empty_stringname_no_crash_and_warning() -> void:
	# Arrange
	var pair: Array = _make_system_with_test_logger()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act — StringName vide doit être traité comme id absent du catalog
	s.apply_upgrade(StringName(""))

	# Assert — pas de crash atteint cette ligne == passé
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-11: doit capturer au moins 1 warning sur StringName vide") \
		.is_greater_equal(1)

	# Assert — zero flag muté
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-11: can_air_jump doit rester false") \
		.is_false()
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-11: can_dash doit rester false") \
		.is_false()
	assert_bool(s.can_wall_run) \
		.override_failure_message("AC-UPG-11: can_wall_run doit rester false") \
		.is_false()

	# Cleanup
	s.free()
