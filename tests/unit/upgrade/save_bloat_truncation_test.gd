# Unit test Story-006 — UpgradeSystem save bloat truncation defense.
# Couvre AC-UPG-44 BLOCKING (1000 entrées + perf gate) + AC-UPG-45 ADVISORY
# boundary 15 (warning) / 14 (no warning).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (instance bare + seed via SaveLoadSystem real autoload).

extends GdUnitTestSuite

const _SAVE_KEY: String = "owned_upgrades"
const _MAX_TRUNCATE: int = 14    # MAX_CATALOG_SIZE_TIER_2 * 2
const _BUDGET_US: int = 5000     # 5 ms — AC-UPG-44 headless CI gate


# =============================================================================
# Setup / Teardown
# =============================================================================

func before_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func after_test() -> void:
	SaveLoadSystem.save_string_array(_SAVE_KEY, [] as Array[StringName])


func _make_seeded(payload: Array[StringName]) -> Array:
	SaveLoadSystem.save_string_array(_SAVE_KEY, payload)
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return [s, log]


func _has_bloat_warning(log: TestUpgradeLogger) -> bool:
	for msg in log.captured_warnings:
		if msg.contains("bloat") or msg.contains("truncat"):
			return true
	return false


# =============================================================================
# AC-UPG-44 BLOCKING — 1000 entrées + perf gate
# =============================================================================

## GIVEN save mocké à 1000 entrées valides (alternées),
## WHEN _ready(),
## THEN warning "bloat"/"truncat" capturé, owned_count ≤ 14, _is_hydrated true,
## AND durée _ready() < 5 ms.
## Source : AC-UPG-44 + EC-UPG-36 + Pillar 1 frame budget.
func test_upgrade_boot_1000_entries_truncates_under_5ms() -> void:
	# Arrange — 1000 entrées valides alternant double_jump / dash_horizontal
	var payload: Array[StringName] = []
	for i in 1000:
		payload.append(&"double_jump" if i % 2 == 0 else &"dash_horizontal")
	var pair: Array = _make_seeded(payload)
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	var t0: int = Time.get_ticks_usec()
	s._ready()
	var elapsed_us: int = Time.get_ticks_usec() - t0

	# Assert — warning émis
	assert_bool(_has_bloat_warning(log)) \
		.override_failure_message("AC-UPG-44: warning 'bloat' ou 'truncat' attendu sur save 1000 entrées") \
		.is_true()

	# Assert — owned_count borné par catalog Tier 1 (idempotence dédoublonne sur 2 ids)
	assert_int(s.get_owned_count()) \
		.override_failure_message("AC-UPG-44: owned_count <= 14 après truncation") \
		.is_less_equal(_MAX_TRUNCATE)

	# Assert — _is_hydrated terminal
	assert_bool(s._is_hydrated) \
		.override_failure_message("AC-UPG-44: _is_hydrated == true post-_ready()") \
		.is_true()

	# Assert — perf gate
	assert_int(elapsed_us) \
		.override_failure_message("AC-UPG-44: _ready() doit prendre < 5 ms (got %d µs)" % elapsed_us) \
		.is_less(_BUDGET_US)

	# Cleanup
	s.free()


# =============================================================================
# AC-UPG-45 ADVISORY — boundary 15 entrées → warning émis
# =============================================================================

## GIVEN save mocké à 15 entrées valides (1 au-dessus du seuil 14),
## WHEN _ready(),
## THEN ≥1 warning bloat capturé.
func test_upgrade_boot_15_entries_emits_truncate_warning() -> void:
	# Arrange — 15 × double_jump
	var payload: Array[StringName] = []
	for i in 15:
		payload.append(&"double_jump")
	var pair: Array = _make_seeded(payload)
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	s._ready()

	# Assert — warning bloat émis
	assert_bool(_has_bloat_warning(log)) \
		.override_failure_message("AC-UPG-45: warning bloat attendu pour 15 entrées (>14)") \
		.is_true()

	# Cleanup
	s.free()


# =============================================================================
# AC-UPG-45 ADVISORY — boundary 14 entrées → no warning bloat
# =============================================================================

## GIVEN save mocké à 14 entrées valides (à la limite stricte),
## WHEN _ready(),
## THEN aucun warning bloat capturé.
func test_upgrade_boot_14_entries_no_truncate_warning() -> void:
	# Arrange — 14 × double_jump
	var payload: Array[StringName] = []
	for i in 14:
		payload.append(&"double_jump")
	var pair: Array = _make_seeded(payload)
	var s: UpgradeSystem = pair[0]
	var log: TestUpgradeLogger = pair[1]

	# Act
	s._ready()

	# Assert — aucun warning bloat
	assert_bool(_has_bloat_warning(log)) \
		.override_failure_message("AC-UPG-45: aucun warning bloat attendu pour 14 entrées (= seuil)") \
		.is_false()

	# Cleanup
	s.free()
