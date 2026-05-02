# Perf test Story-010 — AC-UPG-41 ADVISORY : apply_upgrade médiane < 100 µs.
# 1000 calls idempotent (cas B early return) ; sort + median[500].
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (perf budget headless CI).

extends GdUnitTestSuite

const _SAMPLES: int = 1000
const _BUDGET_MEDIAN_US: int = 100    # 0.1 ms — AC-UPG-41 médiane headless CI


# =============================================================================
# AC-UPG-41 ADVISORY — apply_upgrade médiane < 100 µs sur 1000 calls
# =============================================================================

## GIVEN UpgradeSystem instance bare avec double_jump déjà appliqué,
## WHEN 1000 calls successifs apply_upgrade(double_jump) (idempotent cas B),
## THEN samples sortés ; samples[500] (médiane) < 100 µs.
## Source : AC-UPG-41 + ADR-0001 frame budget 16.6 ms.
func test_apply_upgrade_idempotent_median_under_100us() -> void:
	# Arrange
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	s.apply_upgrade(&"double_jump")    # warmup — passe step 2 cas A

	var samples: Array[int] = []
	samples.resize(_SAMPLES)

	# Act — mesure individuelle de chaque call
	for i in _SAMPLES:
		var t0: int = Time.get_ticks_usec()
		s.apply_upgrade(&"double_jump")
		samples[i] = Time.get_ticks_usec() - t0

	samples.sort()
	var median_us: int = samples[_SAMPLES / 2]
	var min_us: int = samples[0]
	var p99_us: int = samples[_SAMPLES * 99 / 100]
	var max_us: int = samples[_SAMPLES - 1]

	# Diagnostic systématique
	print("AC-UPG-41 stats: min=%d µs, median=%d µs, p99=%d µs, max=%d µs (budget median %d µs)" \
		% [min_us, median_us, p99_us, max_us, _BUDGET_MEDIAN_US])

	# Assert
	assert_int(median_us) \
		.override_failure_message("AC-UPG-41 ADVISORY: median = %d µs, budget %d µs headless CI" % [median_us, _BUDGET_MEDIAN_US]) \
		.is_less(_BUDGET_MEDIAN_US)

	# Cleanup
	s.free()
