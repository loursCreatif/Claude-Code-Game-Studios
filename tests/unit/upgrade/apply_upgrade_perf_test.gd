# Unit test Story-003 — apply_upgrade SYNC perf budget AC-UPG-12-bis [ADVISORY].
# Mesure wall-clock 100 calls successifs (idempotent — 99 early returns step 2).
# Tolérance : moyenne < 1.0 µs par call (preuve indirecte SYNC + idempotence).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Status : ADVISORY — ne block pas merge si budget dépassé en CI bruyant.

extends GdUnitTestSuite

const _ITERATIONS: int = 100
const _BUDGET_US_PER_CALL: float = 1.0


## GIVEN UpgradeSystem avec double_jump déjà appliqué (état post-step-2 idempotent),
## WHEN 100 calls successifs apply_upgrade(double_jump),
## THEN moyenne wall-clock par call < 1 µs (early return cas B).
## Source : AC-UPG-12-bis ADVISORY — preuve SYNC + zero-alloc dans la boucle hot.
func test_upgrade_apply_idempotent_100_calls_under_1us_average() -> void:
	# Arrange — instance bare + logger fixture, premier apply pour entrer en cas B
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	s.apply_upgrade(&"double_jump")    # warmup — passe step 2 cas A
	assert_bool(s.can_air_jump).is_true()    # sanity pré-mesure

	# Act
	var t0: int = Time.get_ticks_usec()
	for i in _ITERATIONS:
		s.apply_upgrade(&"double_jump")    # idempotent — 100× early return cas B
	var elapsed_us: int = Time.get_ticks_usec() - t0
	var per_call_us: float = float(elapsed_us) / float(_ITERATIONS)

	# Assert — ADVISORY tolérant
	assert_float(per_call_us) \
		.override_failure_message("AC-UPG-12-bis ADVISORY: moyenne %.2f µs/call > budget %.1f µs (idempotent loop)" % [per_call_us, _BUDGET_US_PER_CALL]) \
		.is_less(_BUDGET_US_PER_CALL)
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-12-bis: owned_count doit rester 1 après %d calls idempotents" % _ITERATIONS) \
		.is_equal(1)

	# Cleanup
	s.free()
