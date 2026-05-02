# Unit test Story-004 — apply_upgrade step 2 resync guard cas C/D.
# Couvre AC-UPG-9-bis [BLOCKING] : injection désync `_owned=true ∧ flag=false`
# doit déclencher resync via re-application de _apply_flag.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — instance bare avec mutation directe simulant EC-UPG-13.

extends GdUnitTestSuite

# =============================================================================
# Helpers
# =============================================================================

func _make_clean_system() -> Array:
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]

# =============================================================================
# AC-UPG-9-bis Cas C — _owned=true ∧ flag=false → resync flag
# =============================================================================

## GIVEN UpgradeSystem injecté en désync EC-UPG-13 (_owned[id]=true ∧ flag=false),
## WHEN apply_upgrade(id),
## THEN flag re-synchronisé à true, _owned inchangé, owned_count == 1, zéro warning.
## Source : AC-UPG-9-bis BLOCKING + R-UPG-4 step 2 r2 amendement B-4.
func test_upgrade_apply_resync_owned_true_flag_false_re_sets_flag() -> void:
	# Arrange — injection désync (simulation EC-UPG-13 mutation externe / hot-reload)
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]
	s._owned[&"double_jump"] = true
	s.can_air_jump = false
	assert_bool(s._owned.has(&"double_jump")).is_true()
	assert_bool(s.can_air_jump).is_false()

	# Act — re-call apply_upgrade doit forcer resync
	s.apply_upgrade(&"double_jump")

	# Assert — flag resync forcé
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-9-bis Cas C: can_air_jump doit resync à true post-apply") \
		.is_true()
	assert_bool(s._owned.has(&"double_jump")) \
		.override_failure_message("AC-UPG-9-bis Cas C: _owned doit rester contenir double_jump") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-9-bis Cas C: owned_count doit rester 1") \
		.is_equal(1)
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-9-bis Cas C: aucun warning attendu (id valide)") \
		.is_equal(0)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-9-bis Cas D — pathologique : _owned=false ∧ flag=true
# =============================================================================

## GIVEN désync inverse (flag=true sans _owned correspondant — pathologique),
## WHEN apply_upgrade(id),
## THEN _owned marqué, flag reste true, owned_count == 1.
## Défense en profondeur — couvert même si scénario peu réaliste runtime.
func test_upgrade_apply_resync_owned_false_flag_true_marks_owned() -> void:
	# Arrange
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]
	s.can_dash = true    # désync : flag muté externe sans _owned
	assert_bool(s._owned.has(&"dash_horizontal")).is_false()
	assert_bool(s.can_dash).is_true()

	# Act
	s.apply_upgrade(&"dash_horizontal")

	# Assert
	assert_bool(s._owned.has(&"dash_horizontal")) \
		.override_failure_message("AC-UPG-9-bis Cas D: _owned doit contenir dash_horizontal post-apply") \
		.is_true()
	assert_bool(s.can_dash) \
		.override_failure_message("AC-UPG-9-bis Cas D: can_dash doit rester true") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-9-bis Cas D: owned_count doit être 1 post-marquage") \
		.is_equal(1)
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-9-bis Cas D: aucun warning attendu (id valide)") \
		.is_equal(0)

	# Cleanup
	s.free()

# =============================================================================
# AC-UPG-9-bis edge — rerun stable post-resync
# =============================================================================

## GIVEN état post-resync Cas C (both true),
## WHEN second apply_upgrade(id) (idempotent strict cas B),
## THEN aucune mutation, owned_count reste 1, zéro warning.
func test_upgrade_apply_post_resync_rerun_is_stable_idempotent() -> void:
	# Arrange — déclenche un resync Cas C puis rerun
	var pair: Array = _make_clean_system()
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]
	s._owned[&"double_jump"] = true
	s.can_air_jump = false
	s.apply_upgrade(&"double_jump")    # resync Cas C
	assert_bool(s.can_air_jump).is_true()    # sanity post-resync

	# Act
	s.apply_upgrade(&"double_jump")    # rerun → cas B early return

	# Assert
	assert_bool(s.can_air_jump) \
		.override_failure_message("AC-UPG-9-bis rerun: can_air_jump reste true") \
		.is_true()
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-9-bis rerun: owned_count reste 1") \
		.is_equal(1)
	assert_int(log.captured_warnings.size()) \
		.override_failure_message("AC-UPG-9-bis rerun: aucun warning sur rerun stable") \
		.is_equal(0)

	# Cleanup
	s.free()
