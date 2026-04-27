# Tests unitaires story-010 — LevelLint.validate_scene_hierarchy().
# Couvre AC-LVL-11 : hiérarchie canonique présente et types corrects.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test charge sa propre fixture — aucun état partagé.
#
# Story   : production/epics/level-system/story-010-canonical-hierarchy-validate-scene.md
# Req     : TR-lvl-006
# ADR     : ADR-0011 D-2

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Charge une fixture .tscn, l'instancie en Node3D et la retourne.
## Echoue le test si le chargement est impossible.
func _load_fixture(relative_path: String) -> Node3D:
	var full_path: String = "res://tests/fixtures/level/" + relative_path
	var packed: PackedScene = load(full_path) as PackedScene
	assert_object(packed) \
		.override_failure_message("Fixture introuvable : " + full_path) \
		.is_not_null()
	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	assert_object(root_3d) \
		.override_failure_message("La racine de la fixture n'est pas Node3D : " + full_path) \
		.is_not_null()
	add_child(auto_free(root_3d))
	return root_3d


# ---------------------------------------------------------------------------
# AC-LVL-11 — PASS : scène canonique complète
# ---------------------------------------------------------------------------

## Vérifie que validate_scene_hierarchy() retourne [] sur une scène canonique correcte.
## La fixture etage_canonical.tscn contient tous les 4 enfants requis avec les bons types.
func test_validate_scene_hierarchy_pass_on_canonical_scene() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_canonical.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_scene_hierarchy(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-11: validate_scene_hierarchy doit retourner [] sur scène canonique. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()



# ---------------------------------------------------------------------------
# AC-LVL-11 — FAIL : StaticEnvironment manquant
# ---------------------------------------------------------------------------

## Vérifie que validate_scene_hierarchy() signale le nœud StaticEnvironment manquant.
## La fixture etage_missing_static.tscn n'a pas de StaticEnvironment.
func test_validate_scene_hierarchy_fails_missing_static_environment() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_missing_static.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_scene_hierarchy(root)

	# Assert — au moins 1 erreur, contenant le message attendu
	assert_array(errors) \
		.override_failure_message("AC-LVL-11: erreurs attendues mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "missing required Node3D child: StaticEnvironment"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-11: message attendu '%s' absent. Erreurs reçues : %s"
			% [expected_msg, str(errors)]
		) \
		.is_true()



# ---------------------------------------------------------------------------
# AC-LVL-11 — FAIL : EtageExitTrigger de mauvais type (Node3D au lieu d'Area3D)
# ---------------------------------------------------------------------------

## Vérifie que validate_scene_hierarchy() signale EtageExitTrigger avec mauvais type.
## La fixture etage_wrong_type.tscn a EtageExitTrigger de type Node3D.
func test_validate_scene_hierarchy_fails_on_wrong_type() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_wrong_type.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_scene_hierarchy(root)

	# Assert — au moins 1 erreur, contenant le message attendu
	assert_array(errors) \
		.override_failure_message("AC-LVL-11: erreurs attendues mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "missing EtageExitTrigger as Area3D child of root"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-11: message attendu '%s' absent. Erreurs reçues : %s"
			% [expected_msg, str(errors)]
		) \
		.is_true()

