# Integration test Story-009 — AC-UPG-38 forward-compat unknown Tier 2+ ids.
# Save mocké contient mix MVP (double_jump) + ids Tier 2+ inconnus (wall_run_extended,
# tier2_special). Boot hydration : known appliqué, unknown skip+warn, no crash.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration (real SaveLoadSystem, instance bare avec Logger DI).

extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"


func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


# =============================================================================
# AC-UPG-38 BLOCKING — forward-compat unknown ids skip + known applied
# =============================================================================

## GIVEN save = [&"double_jump", &"wall_run_extended", &"tier2_special"],
## WHEN _ready() boot hydration,
## THEN can_air_jump true (double_jump appliqué),
## AND owned_count == 1 (unknowns skipped),
## AND ≥2 warnings unknown id capturés (wall_run_extended + tier2_special),
## AND aucun crash.
## Source : AC-UPG-38 + R-UPG-9 + EC-UPG-19 (forward-compat saves Tier 2+).
func test_upgrade_boot_unknown_tier2_ids_skip_and_known_applied() -> void:
	# Arrange — payload mix MVP + Tier 2+ futurs
	SaveLoadSystem.save_string_array(_SAVE_KEY, [
		&"double_jump",
		&"wall_run_extended",
		&"tier2_special",
	])
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)

	# Act
	s._ready()

	# Assert — known id appliqué
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-38: double_jump (known) doit être appliqué") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-38: owned_count == 1 (uniquement known appliqué)") \
		.is_equal(1)

	# Assert — ≥2 warnings unknown id
	var unknown_warnings: int = 0
	for msg in log.captured_warnings:
		if msg.contains("unknown") and (msg.contains("wall_run_extended") or msg.contains("tier2_special")):
			unknown_warnings += 1
	assert_int(unknown_warnings) \
		.override_failure_message("AC-UPG-38: ≥2 warnings unknown id attendus (wall_run_extended + tier2_special)") \
		.is_greater_equal(2)

	# Assert — _is_hydrated terminal (no crash mid-loop)
	assert_bool(s._is_hydrated) \
		.override_failure_message("AC-UPG-38: _is_hydrated true post-_ready() (no crash)") \
		.is_true()

	# Cleanup
	s.free()
