# Tests unitaires story-018 — LevelSystemScript.get_secret_slots().
#
# Couvre :
#   AC-LVL-46 / AC-LVL-53 (story-018) : API runtime get_secret_slots() retourne
#   un Array de Dictionary {lure, collect_volume, content_anchor, required_ability}
#   pour chaque triplet complet (Lure + Volume + Anchor) dans la scène d'étage active.
#   Triplet incomplet → push_warning + skip.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Pattern   : injection scene_root via _set_current_scene_root_for_test (cf. story-009
#             tests/unit/level/level_spatial_lookups_test.gd).
#
# Story : production/epics/level-system/story-018-secret-split-contract-validate-lures.md
# Req   : AC-LVL-46, AC-LVL-53
# ADR   : ADR-0005 D-10 (API publique read-only consommée par peers)

extends GdUnitTestSuite

const SecretLureMarkerScript: GDScript = preload("res://src/gameplay/level/secret_lure_marker.gd")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript frais attaché au tree (déclenche _ready).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(level)
	return level


## Crée une Node3D racine attachée au tree (global_position disponible pour anchor).
func _make_scene_root() -> Node3D:
	var root: Node3D = Node3D.new()
	add_child(root)
	return root


## Ajoute un triplet complet (Lure + Volume + Anchor) sous `root` à `pos` (anchor position).
## Le SecretLureMarker_NN porte le script `secret_lure_marker.gd` avec required_ability.
func _add_triplet(
	root: Node3D,
	idx: String,
	ability: StringName,
	pos: Vector3 = Vector3.ZERO
) -> void:
	var lure: Marker3D = Marker3D.new()
	lure.name = "SecretLureMarker_" + idx
	lure.set_script(SecretLureMarkerScript)
	lure.required_ability = ability
	root.add_child(lure)

	var volume: Area3D = Area3D.new()
	volume.name = "SecretCollectVolume_" + idx
	root.add_child(volume)

	var anchor: Marker3D = Marker3D.new()
	anchor.name = "SecretAnchor_" + idx
	anchor.position = pos
	root.add_child(anchor)


## Ajoute uniquement un SecretLureMarker_NN (Lure orphelin — pas de Volume ni Anchor).
func _add_orphan_lure(root: Node3D, idx: String, ability: StringName) -> void:
	var lure: Marker3D = Marker3D.new()
	lure.name = "SecretLureMarker_" + idx
	lure.set_script(SecretLureMarkerScript)
	lure.required_ability = ability
	root.add_child(lure)


# ---------------------------------------------------------------------------
# AC-LVL-46 / AC-LVL-53 — happy path : 3 triplets complets retournés typés
# ---------------------------------------------------------------------------

## Vérifie que get_secret_slots() retourne exactement 3 entrées Dictionary
## avec les 4 clés attendues et les types corrects pour chaque entry.
## Source : story-018 AC-LVL-46 / AC-LVL-53, ADR-0005 D-10.
func test_get_secret_slots_returns_typed_tuples() -> void:
	# Arrange — 3 triplets complets dans la scène
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_triplet(root, "01", &"dash", Vector3(1.0, 0.0, 2.0))
	_add_triplet(root, "02", &"wall_run", Vector3(3.0, 0.0, 4.0))
	_add_triplet(root, "03", &"none", Vector3(5.0, 0.0, 6.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array = level.get_secret_slots()

	# Assert — taille
	assert_int(slots.size()) \
		.override_failure_message("Expected 3 slots, got %d" % slots.size()) \
		.is_equal(3)

	# Assert — chaque entry a les 4 clés et les bons types
	for slot: Variant in slots:
		var d: Dictionary = slot as Dictionary
		assert_bool(d.has("lure")) \
			.override_failure_message("slot missing 'lure' key: %s" % str(d)) \
			.is_true()
		assert_bool(d.has("collect_volume")) \
			.override_failure_message("slot missing 'collect_volume' key: %s" % str(d)) \
			.is_true()
		assert_bool(d.has("content_anchor")) \
			.override_failure_message("slot missing 'content_anchor' key: %s" % str(d)) \
			.is_true()
		assert_bool(d.has("required_ability")) \
			.override_failure_message("slot missing 'required_ability' key: %s" % str(d)) \
			.is_true()
		# Types
		assert_object(d["lure"] as Marker3D) \
			.override_failure_message("'lure' not Marker3D: %s" % str(d["lure"])) \
			.is_not_null()
		assert_object(d["collect_volume"] as Area3D) \
			.override_failure_message("'collect_volume' not Area3D: %s" % str(d["collect_volume"])) \
			.is_not_null()
		# Vector3 + StringName ne sont pas des objects (value types) — vérifier via typeof
		assert_int(typeof(d["content_anchor"])) \
			.override_failure_message("'content_anchor' not Vector3 (typeof=%d)" % typeof(d["content_anchor"])) \
			.is_equal(TYPE_VECTOR3)
		assert_int(typeof(d["required_ability"])) \
			.override_failure_message("'required_ability' not StringName (typeof=%d)" % typeof(d["required_ability"])) \
			.is_equal(TYPE_STRING_NAME)


# ---------------------------------------------------------------------------
# AC-LVL-53 — incomplete tuples skipped with warning
# ---------------------------------------------------------------------------

## Vérifie que get_secret_slots() ignore les triplets incomplets (Lure orphelin
## sans Volume) et retourne uniquement les triplets complets — la taille reflète
## le nombre de triplets valides, pas le nombre total de Lures.
## Source : story-018 AC-LVL-53.
func test_get_secret_slots_skips_incomplete_tuples_with_warning() -> void:
	# Arrange — 2 triplets complets + 1 lure orphelin (sans Volume ni Anchor)
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_triplet(root, "01", &"dash", Vector3(1.0, 0.0, 2.0))
	_add_triplet(root, "02", &"wall_run_long", Vector3(3.0, 0.0, 4.0))
	_add_orphan_lure(root, "03", &"none")
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array = level.get_secret_slots()

	# Assert — orphan ignoré → seuls 2 triplets retournés
	assert_int(slots.size()) \
		.override_failure_message("Expected 2 complete slots (orphan skipped), got %d" % slots.size()) \
		.is_equal(2)

	# Assert — les 2 slots correspondent bien aux indices 01 et 02 (pas 03)
	var indices_found: Array[String] = []
	for slot: Variant in slots:
		var d: Dictionary = slot as Dictionary
		var lure: Marker3D = d["lure"] as Marker3D
		var idx: String = String(lure.name).trim_prefix("SecretLureMarker_")
		indices_found.append(idx)

	assert_array(indices_found) \
		.override_failure_message("Indices found: %s" % str(indices_found)) \
		.contains(["01", "02"])
	assert_bool("03" in indices_found) \
		.override_failure_message("Orphan lure 03 should NOT be in returned slots: %s" % str(indices_found)) \
		.is_false()


# ---------------------------------------------------------------------------
# AC-LVL-30c (pattern) — retourne [] quand scene_root est null
# ---------------------------------------------------------------------------

## Vérifie que get_secret_slots() retourne un Array vide (et non une erreur)
## quand _current_scene_root == null (état UNLOADED — pas de load_etage appelé).
## Cohérent avec le contrat AC-LVL-30c appliqué aux autres lookups spatiaux.
## Source : story-018 AC-LVL-46, pattern ADR-0005 D-10.
func test_get_secret_slots_returns_empty_when_scene_root_null() -> void:
	# Arrange — level instancié sans injection de scene_root
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	# Act
	var slots: Array = level.get_secret_slots()

	# Assert — Array vide, aucune exception levée
	assert_array(slots) \
		.override_failure_message("get_secret_slots() sans scene_root doit retourner [] (AC-LVL-30c pattern)") \
		.is_empty()

	level.free()


# ---------------------------------------------------------------------------
# AC-LVL-46 — propagation correcte des StringName required_ability
# ---------------------------------------------------------------------------

## Vérifie que get_secret_slots() propage fidèlement la valeur required_ability
## de chaque SecretLureMarker dans le Dictionary retourné, sans conversion
## ni perte de type (StringName equality stricte vs les constantes SecretAbilities.*).
## Source : story-018 AC-LVL-46, ADR-0005 D-10.
func test_get_secret_slots_propagates_required_ability_string_name() -> void:
	# Arrange — 3 triplets avec des required_ability différentes
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_triplet(root, "01", SecretAbilities.NONE, Vector3(1.0, 0.0, 0.0))
	_add_triplet(root, "02", SecretAbilities.DASH, Vector3(2.0, 0.0, 0.0))
	_add_triplet(root, "03", SecretAbilities.WALL_RUN, Vector3(3.0, 0.0, 0.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var slots: Array = level.get_secret_slots()

	# Assert — taille
	assert_int(slots.size()) \
		.override_failure_message("Expected 3 slots for ability propagation test, got %d" % slots.size()) \
		.is_equal(3)

	# Assert — construire un map lure.name → required_ability pour vérifier par indice
	var ability_map: Dictionary = {}
	for slot: Variant in slots:
		var d: Dictionary = slot as Dictionary
		var lure: Marker3D = d["lure"] as Marker3D
		ability_map[String(lure.name)] = d["required_ability"]

	assert_bool(ability_map.has("SecretLureMarker_01")) \
		.override_failure_message("SecretLureMarker_01 absent du résultat") \
		.is_true()
	assert_bool(ability_map.has("SecretLureMarker_02")) \
		.override_failure_message("SecretLureMarker_02 absent du résultat") \
		.is_true()
	assert_bool(ability_map.has("SecretLureMarker_03")) \
		.override_failure_message("SecretLureMarker_03 absent du résultat") \
		.is_true()

	# Vérification StringName equality stricte vs constantes canoniques
	assert_bool(ability_map["SecretLureMarker_01"] == SecretAbilities.NONE) \
		.override_failure_message(
			"AC-LVL-46: lure_01 required_ability='%s', attendu SecretAbilities.NONE='%s'"
			% [ability_map["SecretLureMarker_01"], SecretAbilities.NONE]
		) \
		.is_true()
	assert_bool(ability_map["SecretLureMarker_02"] == SecretAbilities.DASH) \
		.override_failure_message(
			"AC-LVL-46: lure_02 required_ability='%s', attendu SecretAbilities.DASH='%s'"
			% [ability_map["SecretLureMarker_02"], SecretAbilities.DASH]
		) \
		.is_true()
	assert_bool(ability_map["SecretLureMarker_03"] == SecretAbilities.WALL_RUN) \
		.override_failure_message(
			"AC-LVL-46: lure_03 required_ability='%s', attendu SecretAbilities.WALL_RUN='%s'"
			% [ability_map["SecretLureMarker_03"], SecretAbilities.WALL_RUN]
		) \
		.is_true()

	level.free()
	root.free()
