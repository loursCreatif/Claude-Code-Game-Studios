# Unit test Story-001 — UpgradeSystem capability vars defaults.
# Couvre AC-UPG-2 : trois vars publics typés bool, defaults false sur instance bare.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (story type Integration mais ce test est unit pur sur instance bare).

extends GdUnitTestSuite

# =============================================================================
# AC-UPG-2 — capability vars defaults sur instance bare
# =============================================================================

## GIVEN var s = UpgradeSystem.new() (instance bare, pas le singleton autoload),
## WHEN lecture can_air_jump / can_dash / can_wall_run avant tout apply_upgrade,
## THEN trois retours == false ET typeof == TYPE_BOOL pour les trois.
## Source : AC-UPG-2, R-UPG-2 (3 vars publics typés bool).
func test_upgrade_capability_vars_default_false_and_typed_bool() -> void:
	# Arrange — instance bare (PAS le singleton autoload qui pourrait être hydraté
	# par un autre test). UpgradeSystem.new() crée un Node neuf non-attaché.
	var s: UpgradeSystem = UpgradeSystem.new()

	# Act + Assert — defaults
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-2: can_air_jump default doit être false") \
		.is_false()
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-2: can_dash default doit être false") \
		.is_false()
	assert_bool(s.can_wall_run) \
		.override_failure_message("AC-UPG-2: can_wall_run default doit être false") \
		.is_false()

	# Assert — typage strict TYPE_BOOL
	assert_int(typeof(s.can_air_jump)) \
		.override_failure_message("AC-UPG-2: typeof(can_air_jump) doit être TYPE_BOOL") \
		.is_equal(TYPE_BOOL)
	assert_int(typeof(s.can_dash)) \
		.override_failure_message("AC-UPG-2: typeof(can_dash) doit être TYPE_BOOL") \
		.is_equal(TYPE_BOOL)
	assert_int(typeof(s.can_wall_run)) \
		.override_failure_message("AC-UPG-2: typeof(can_wall_run) doit être TYPE_BOOL") \
		.is_equal(TYPE_BOOL)

	# Cleanup
	s.free()
