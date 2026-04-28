# Perf test Story-010 — AC-UPG-40 ADVISORY : _ready() < 1 ms headless ubuntu-latest.
# Mock SaveLoad via SaveLoadSystem.save_string_array seed avec catalog MVP complet.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (perf budget headless CI).

extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"
const _BUDGET_US: int = 1000    # 1 ms — AC-UPG-40 budget headless ubuntu-latest


func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [&"double_jump", &"dash_horizontal"])


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


# =============================================================================
# AC-UPG-40 ADVISORY — _ready() < 1 ms avec catalog MVP complet (2 entrées)
# =============================================================================

## GIVEN save seedée avec MVP catalog complet [double_jump, dash_horizontal],
## WHEN UpgradeSystem.new() + s._ready() (instance bare, no add_child overhead),
## THEN elapsed < 1000 µs (1 ms) headless CI.
## Source : AC-UPG-40 + F-UPG-2 + Pillar 1 frame budget 16.6 ms.
func test_upgrade_boot_under_1ms_with_full_mvp_catalog() -> void:
	# Arrange — instance bare (pas d'add_child overhead, mesure pure body _ready())
	var s: UpgradeSystem = UpgradeSystem.new()

	# Act
	var t0: int = Time.get_ticks_usec()
	s._ready()
	var elapsed_us: int = Time.get_ticks_usec() - t0

	# Diagnostic systématique pour aider calibration cross-hardware
	print("AC-UPG-40 boot _ready() elapsed: %d µs (budget %d µs)" % [elapsed_us, _BUDGET_US])

	# Assert
	assert_int(elapsed_us) \
		.override_failure_message("AC-UPG-40 ADVISORY: _ready() = %d µs, budget %d µs (1 ms) headless CI" % [elapsed_us, _BUDGET_US]) \
		.is_less(_BUDGET_US)

	# Sanity — flags appliqués (vérifie que le test mesure bien le path complet)
	assert_bool(s.can_air_jump).is_true()
	assert_bool(s.can_dash).is_true()
	assert_bool(s._is_hydrated).is_true()

	# Cleanup
	s.free()
