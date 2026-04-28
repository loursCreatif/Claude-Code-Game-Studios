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
# AC-UPG-6 (b) — runtime documentation : in-place mutation Godot 4.6 succeeds
# =============================================================================

## GIVEN UpgradeSystem instance bare,
## WHEN tentative mutation in-place _CATALOG[&"injected"] = &"poison",
## THEN la mutation réussit (Godot 4.6 const freeze binding pas contenu).
## Cleanup obligatoire post-test pour préserver isolation.
## Source : AC-UPG-6 (b) — documentation comportement, pas validation immutability.
func test_catalog_inplace_mutation_succeeds_documented_godot46_behavior() -> void:
	# Arrange
	var s: UpgradeSystem = _make_clean_system()
	var initial_size: int = s._CATALOG.size()
	assert_int(initial_size).is_equal(_MVP_CATALOG_SIZE)

	# Act — mutation runtime (Godot 4.6 ne freeze que le binding)
	s._CATALOG[&"injected_test_key"] = &"poison"

	# Assert — mutation effective
	assert_int(s._CATALOG.size()) \
		.override_failure_message("AC-UPG-6 (b): mutation in-place doit succeed (Godot 4.6 documented)") \
		.is_equal(initial_size + 1)

	# Cleanup CRITIQUE — sans erase, le test suivant verra le catalog pollué
	# (le const Dictionary est partagé entre instances UpgradeSystem en Godot 4.6).
	s._CATALOG.erase(&"injected_test_key")
	assert_int(s._CATALOG.size()) \
		.override_failure_message("AC-UPG-6 (b): cleanup erase a échoué — isolation rompue pour tests suivants") \
		.is_equal(initial_size)

	# Cleanup
	s.free()
