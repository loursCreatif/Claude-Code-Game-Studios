# Tests unitaires story-019 — LevelSystemScript.get_onboarding_anchors().
#
# Couvre :
#   AC-LVL-54 : get_onboarding_anchors() retourne un Dictionary avec les clés
#               "first_enemy_sightline" et "safe_zone_center" (Marker3D) quand
#               le sous-arbre OnboardingAnchors est présent et complet.
#   AC-LVL-54(c) : retourne {} quand OnboardingAnchors est absent (étage != 1).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Pattern   : injection scene_root via _set_current_scene_root_for_test (cf.
#             tests/unit/level/level_get_secret_slots_test.gd, story-018).
#
# Story : production/epics/level-system/story-019-onboarding-anchors-validate-api.md
# Req   : AC-LVL-54
# ADR   : ADR-0005 D-10 (API publique read-only consommée par peers)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript frais attaché au tree (déclenche _ready).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(level)
	return level


## Crée un Node3D racine synthétique attaché au tree (global_position disponible).
func _make_scene_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(root)
	return root


## Ajoute un sous-arbre OnboardingAnchors complet sous root.
## [param sightline_pos] : position locale de FirstEnemySightline.
## [param safe_pos]      : position locale de SafeZoneCenter.
func _add_onboarding_anchors(
	root: Node3D,
	sightline_pos: Vector3 = Vector3(5.0, 1.0, 0.0),
	safe_pos: Vector3 = Vector3(0.0, 1.0, 10.0)
) -> void:
	var anchors: Node3D = Node3D.new()
	anchors.name = "OnboardingAnchors"
	root.add_child(anchors)

	var sightline: Marker3D = Marker3D.new()
	sightline.name = "FirstEnemySightline"
	sightline.position = sightline_pos
	anchors.add_child(sightline)

	var safe: Marker3D = Marker3D.new()
	safe.name = "SafeZoneCenter"
	safe.position = safe_pos
	anchors.add_child(safe)


# ---------------------------------------------------------------------------
# AC-LVL-54 — happy path : Dictionary complet retourné sur étage 1
# ---------------------------------------------------------------------------

## Vérifie que get_onboarding_anchors() retourne un Dictionary avec les 2 clés
## attendues pointant sur des Marker3D valides quand la scène est active et complète.
## Source : story-019 AC-LVL-54, QA Test "test_get_onboarding_anchors_returns_dict_on_etage_1".
func test_get_onboarding_anchors_returns_dict_on_etage_1() -> void:
	# Arrange — scène étage 1 avec OnboardingAnchors complet
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	_add_onboarding_anchors(root, Vector3(5.0, 1.0, 0.0), Vector3(0.0, 1.0, 10.0))
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var anchors: Dictionary = level.get_onboarding_anchors()

	# Assert — Dictionary non vide avec les 2 clés attendues
	assert_bool(anchors.is_empty()) \
		.override_failure_message(
			"AC-LVL-54: get_onboarding_anchors() doit retourner un Dictionary non vide sur étage 1"
		) \
		.is_false()

	assert_bool(anchors.has("first_enemy_sightline")) \
		.override_failure_message(
			"AC-LVL-54: Dictionary doit contenir la clé 'first_enemy_sightline'. Reçu : %s" % str(anchors.keys())
		) \
		.is_true()

	assert_bool(anchors.has("safe_zone_center")) \
		.override_failure_message(
			"AC-LVL-54: Dictionary doit contenir la clé 'safe_zone_center'. Reçu : %s" % str(anchors.keys())
		) \
		.is_true()

	# Assert — les valeurs sont bien des Marker3D (pas null)
	var sightline: Marker3D = anchors["first_enemy_sightline"] as Marker3D
	assert_object(sightline) \
		.override_failure_message(
			"AC-LVL-54: 'first_enemy_sightline' doit être un Marker3D valide"
		) \
		.is_not_null()

	var safe: Marker3D = anchors["safe_zone_center"] as Marker3D
	assert_object(safe) \
		.override_failure_message(
			"AC-LVL-54: 'safe_zone_center' doit être un Marker3D valide"
		) \
		.is_not_null()

	# Assert — noms des nœuds corrects
	assert_str(String(sightline.name)) \
		.override_failure_message(
			"AC-LVL-54: sightline.name attendu 'FirstEnemySightline', reçu '%s'" % sightline.name
		) \
		.is_equal("FirstEnemySightline")

	assert_str(String(safe.name)) \
		.override_failure_message(
			"AC-LVL-54: safe.name attendu 'SafeZoneCenter', reçu '%s'" % safe.name
		) \
		.is_equal("SafeZoneCenter")

	# Cleanup
	level.free()
	root.free()


# ---------------------------------------------------------------------------
# AC-LVL-54(c) — étage sans OnboardingAnchors retourne {} vide
# ---------------------------------------------------------------------------

## Vérifie que get_onboarding_anchors() retourne {} quand le sous-arbre
## OnboardingAnchors est absent de la scène (cas étage != 1, non-fatal).
## Source : story-019 AC-LVL-54(c), QA Test "test_get_onboarding_anchors_returns_empty_dict_etage_2".
func test_get_onboarding_anchors_returns_empty_dict_etage_2() -> void:
	# Arrange — scène étage 2 sans OnboardingAnchors
	var level: LevelSystemScript = _make_level()
	var root: Node3D = _make_scene_root()
	# Pas de OnboardingAnchors ajouté
	level._set_current_scene_root_for_test(root)
	await get_tree().process_frame

	# Act
	var anchors: Dictionary = level.get_onboarding_anchors()

	# Assert — Dictionary vide (non-fatal AC-LVL-54(c))
	assert_bool(anchors.is_empty()) \
		.override_failure_message(
			"AC-LVL-54(c): get_onboarding_anchors() doit retourner {} quand OnboardingAnchors absent"
		) \
		.is_true()

	# Cleanup
	level.free()
	root.free()
