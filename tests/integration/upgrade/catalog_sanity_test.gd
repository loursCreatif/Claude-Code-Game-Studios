# Integration test Story-008 — F-UPG-3 catalog sanity invariant.
# Couvre AC-UPG-6 (immutability runtime documentation) + AC-UPG-15 BLOCKING
# (chaque entrée _CATALOG → propriété existante / TYPE_BOOL / mutable round-trip).
# AC-UPG-6-bis grep statique : voir tests/static/upgrade_lint_test.gd.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration — instancie UpgradeSystem pour get_property_list().
#
# Décision OQ-UPG-10 RESOLVED : path = tests/integration/upgrade/catalog_sanity_test.gd
# (runtime introspection, pas pure-static).

extends GdUnitTestSuite

const _MVP_CATALOG_SIZE: int = 2    # Tier 1 — double_jump + dash_horizontal


# =============================================================================
# Helpers
# =============================================================================

func _make_clean_system() -> UpgradeSystem:
	var s: UpgradeSystem = UpgradeSystem.new()
	var log: TestUpgradeLogger = TestUpgradeLogger.new()
	s.set_logger_for_test(log)
	return s


func _collect_script_vars(s: UpgradeSystem) -> Array[StringName]:
	var props: Array[StringName] = []
	for p in s.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props.append(p.name)
	return props


# =============================================================================
# AC-UPG-15 BLOCKING — chaque entrée _CATALOG mappe à une property bool mutable
# =============================================================================

## GIVEN UpgradeSystem instance bare avec _CATALOG MVP réel,
## WHEN itération sur chaque entrée (id, flag_name),
## THEN (a) flag_name présent dans get_property_list filtré SCRIPT_VARIABLE,
##      (b) typeof(get(flag_name)) == TYPE_BOOL,
##      (c) round-trip set true / set false fonctionne (mutable).
## Source : AC-UPG-15 + F-UPG-3 + R-UPG-3.
func test_catalog_sanity_each_entry_maps_to_existing_bool_mutable_var() -> void:
	# Arrange
	var s: UpgradeSystem = _make_clean_system()
	var props: Array[StringName] = _collect_script_vars(s)

	# Sanity pré-test : isolation préservée (catalog Tier 1 = 2 entrées).
	assert_int(s._CATALOG.size()) \
		.override_failure_message("Catalog size != %d — isolation rompue par test précédent" % _MVP_CATALOG_SIZE) \
		.is_equal(_MVP_CATALOG_SIZE)

	# Act + Assert — itération
	for id: StringName in s._CATALOG.keys():
		var flag_name: StringName = s._CATALOG[id]

		# (a) propriété existe
		assert_bool(flag_name in props) \
			.override_failure_message("AC-UPG-15 (a): catalog id=%s flag_name=%s — property absente du script" % [id, flag_name]) \
			.is_true()

		# (b) typeof bool
		var initial: Variant = s.get(flag_name)
		assert_int(typeof(initial)) \
			.override_failure_message("AC-UPG-15 (b): catalog flag=%s typeof=%d (attendu TYPE_BOOL=%d)" % [flag_name, typeof(initial), TYPE_BOOL]) \
			.is_equal(TYPE_BOOL)

		# (c) round-trip set/get
		s.set(flag_name, true)
		assert_bool(s.get(flag_name)) \
			.override_failure_message("AC-UPG-15 (c): set(%s, true) ne prend pas effet" % flag_name) \
			.is_true()
		s.set(flag_name, false)
		assert_bool(s.get(flag_name)) \
			.override_failure_message("AC-UPG-15 (c): set(%s, false) ne prend pas effet" % flag_name) \
			.is_false()

		# Restore initial pour pas polluer assertions ultérieures
		s.set(flag_name, initial)

	# Cleanup
	s.free()


# =============================================================================
# AC-UPG-6 (b) — parse-time const enforcement (Godot 4.6 stricter than 4.5)
# =============================================================================
# OBSOLETE runtime test removed : Godot 4.6 enforce `const Dictionary` au parse-time,
# donc toute tentative `s._CATALOG[k] = v` est rejetée par le parser
# ("Cannot assign a new value to a constant"). La garantie d'immutabilité est
# désormais structurelle/build-time (plus forte que le test runtime original).
# Si Godot relâche cette contrainte dans une version future, restaurer le test.
