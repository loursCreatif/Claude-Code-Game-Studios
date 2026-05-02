# Unit test Story-003 — UpgradeSystem.apply_upgrade body cas A/B + idempotence.
# Couvre AC-UPG-7, AC-UPG-8, AC-UPG-9, AC-UPG-13, AC-UPG-14.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare, pas l'autoload (évite contamination cross-test).

extends GdUnitTestSuite

# =============================================================================
# Helpers
# =============================================================================

func _make_clean_system() -> Array:
	# Instance bare + logger fixture injecté. État initial : tous flags false,
	# _owned vide, _logger capturable.
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]

# =============================================================================
# AC-UPG-7 — apply_upgrade(double_jump) cas A nominal
# =============================================================================

## GIVEN UpgradeSystem clean,
## WHEN apply_upgrade(&"double_jump"),
## THEN can_air_jump == true ET is_owned(&"double_jump") == true.
func test_upgrade_apply_double_jump_sets_air_jump_and_owned() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]

	# Act
	s.apply_upgrade(&"double_jump")

	# Assert
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-7: can_air_jump doit être true après apply double_jump") \
		.is_true()
	assert_bool(s.is_owned(&"double_jump")) \
		.override_failure_message("AC-UPG-7: is_owned(double_jump) doit être true") \
		.is_true()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-8 — apply_upgrade(dash_horizontal) cas A nominal
# =============================================================================

## GIVEN UpgradeSystem clean,
## WHEN apply_upgrade(&"dash_horizontal"),
## THEN can_dash == true ET is_owned(&"dash_horizontal") == true.
func test_upgrade_apply_dash_sets_dash_flag_and_owned() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]

	# Act
	s.apply_upgrade(&"dash_horizontal")

	# Assert
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-8: can_dash doit être true après apply dash_horizontal") \
		.is_true()
	assert_bool(s.is_owned(&"dash_horizontal")) \
		.override_failure_message("AC-UPG-8: is_owned(dash_horizontal) doit être true") \
		.is_true()

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-9 — double-call idempotent strict (cas B)
# =============================================================================

## GIVEN apply_upgrade(double_jump) déjà appelé,
## WHEN apply_upgrade(double_jump) rappelé,
## THEN can_air_jump reste true, owned_count == 1, ZÉRO warning émis.
func test_upgrade_apply_same_id_twice_idempotent_no_warning() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]
	s.apply_upgrade(&"double_jump")
	var warnings_after_first: int = log.captured_warnings.size()

	# Act
	s.apply_upgrade(&"double_jump")

	# Assert
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-9: can_air_jump doit rester true post-rerun") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-9: get_owned_count() doit rester 1 (idempotent)") \
		.is_equal(1)
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-9: aucun warning ne doit être émis sur double-call (cas B)") \
		.is_equal(warnings_after_first)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-13 — owned count tracking
# =============================================================================

## GIVEN UpgradeSystem clean,
## WHEN apply_upgrade(double_jump),
## THEN is_owned(double_jump) == true ET get_owned_count() == 1.
func test_upgrade_apply_increments_owned_count_to_one() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]

	# Act
	s.apply_upgrade(&"double_jump")

	# Assert
	assert_bool(s.is_owned(&"double_jump")) \
		.override_failure_message("AC-UPG-13: is_owned(double_jump) doit être true post-apply") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-13: get_owned_count() doit être 1 post-single apply") \
		.is_equal(1)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-14 — capabilities indépendantes (R-UPG-13)
# =============================================================================

## GIVEN UpgradeSystem clean,
## WHEN apply_upgrade(&"double_jump"),
## THEN can_dash et can_wall_run restent false (independance).
func test_upgrade_apply_double_jump_does_not_affect_other_flags() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]

	# Act
	s.apply_upgrade(&"double_jump")

	# Assert
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-14: can_dash ne doit PAS muter sur apply double_jump") \
		.is_false()
	assert_bool(s.can_wall_run) \
		.override_failure_message("AC-UPG-14: can_wall_run ne doit PAS muter sur apply double_jump") \
		.is_false()

	# Cleanup
	s.free()
