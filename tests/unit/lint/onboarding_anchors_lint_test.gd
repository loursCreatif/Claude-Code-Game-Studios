# Tests unitaires story-019 — LevelLint.validate_onboarding_anchors().
#
# Couvre :
#   AC-LVL-54(a) presence  : étage 1 sans OnboardingAnchors → violation.
#   AC-LVL-54(a) distance  : FirstEnemySightline à > 15m → violation.
#   AC-LVL-54(b) enemy     : SafeZoneCenter à < 6m d'un EnemySlot → violation.
#   AC-LVL-54(b) hazard    : SafeZoneCenter à < 4m d'un HazardSlot → violation.
#   AC-LVL-54(c) etage != 1 : absence OnboardingAnchors non-fatale → [].
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
#
# Story : production/epics/level-system/story-019-onboarding-anchors-validate-api.md
# Req   : AC-LVL-54

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un Node3D racine minimal attaché au tree.
## Optionnellement ajoute un PlayerStart à la position donnée.
func _make_root(player_start_pos: Vector3 = Vector3.ZERO) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var ps: Marker3D = Marker3D.new()
	ps.name = "PlayerStart"
	ps.position = player_start_pos
	root.add_child(ps)

	return root


## Ajoute un sous-arbre OnboardingAnchors avec FirstEnemySightline et SafeZoneCenter
## aux positions données. Retourne l'objet OnboardingAnchors Node3D.
func _add_onboarding_anchors(
	root: Node3D,
	sightline_pos: Vector3,
	safe_pos: Vector3
) -> Node3D:
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

	return anchors


## Ajoute un EnemySlot_NN Marker3D directement sous root à la position donnée.
func _add_enemy_slot(root: Node3D, idx: String, pos: Vector3) -> void:
	var slot: Marker3D = Marker3D.new()
	slot.name = "EnemySlot_" + idx
	slot.position = pos
	root.add_child(slot)


## Ajoute un HazardSlot_NN Marker3D directement sous root à la position donnée.
func _add_hazard_slot(root: Node3D, idx: String, pos: Vector3) -> void:
	var slot: Marker3D = Marker3D.new()
	slot.name = "HazardSlot_" + idx
	slot.position = pos
	root.add_child(slot)


# ---------------------------------------------------------------------------
# AC-LVL-54(a) presence — FAIL : étage 1 sans OnboardingAnchors
# ---------------------------------------------------------------------------

## Vérifie que validate_onboarding_anchors signale l'absence du sous-arbre
## OnboardingAnchors quand etage_id == 1.
## Source : story-019 AC-LVL-54(a), QA Test "AC-LVL-54(a) presence".
func test_validate_onboarding_anchors_fails_missing_on_etage_1() -> void:
	# Arrange — fixture étage 1 sans OnboardingAnchors
	var root: Node3D = _make_root()
	# Pas de OnboardingAnchors ajouté

	# Act
	var errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root, 1)

	# Assert — violation "etage 1 requires OnboardingAnchors sub-tree"
	var found: bool = false
	for e: String in errors:
		if "etage 1 requires OnboardingAnchors sub-tree" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-54: violation 'etage 1 requires OnboardingAnchors sub-tree' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-54(a) distance — FAIL : FirstEnemySightline > 15m
# ---------------------------------------------------------------------------

## Vérifie que validate_onboarding_anchors signale une distance > 15m entre
## PlayerStart et FirstEnemySightline.
## Source : story-019 AC-LVL-54(a), QA Test "AC-LVL-54(a) distance".
func test_first_enemy_sightline_distance_over_15m_fails() -> void:
	# Arrange — PlayerStart à l'origine, FirstEnemySightline à (20, 0, 0) → dist = 20m > 15m
	var root: Node3D = _make_root(Vector3.ZERO)
	_add_onboarding_anchors(root, Vector3(20.0, 0.0, 0.0), Vector3(0.0, 0.0, 5.0))

	# Act
	var errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root, 1)

	# Assert — violation "distance 20.00m > 15m"
	var found: bool = false
	for e: String in errors:
		if "FirstEnemySightline distance" in e and "> 15m" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-54: violation distance > 15m attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-54(b) enemy — FAIL : SafeZoneCenter < 6m d'un EnemySlot
# ---------------------------------------------------------------------------

## Vérifie que validate_onboarding_anchors signale SafeZoneCenter trop proche
## d'un EnemySlot_01 (distance 5m < 6m requis).
## Source : story-019 AC-LVL-54(b), QA Test "AC-LVL-54(b) enemy distance".
func test_safe_zone_too_close_to_enemy_slot_fails() -> void:
	# Arrange — SafeZoneCenter à (0,0,0), EnemySlot_01 à (5,0,0) → dist = 5m < 6m
	var root: Node3D = _make_root(Vector3.ZERO)
	# FirstEnemySightline dans les 15m (dist = 10m → OK, pas de violation distance)
	_add_onboarding_anchors(root, Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
	_add_enemy_slot(root, "01", Vector3(5.0, 0.0, 0.0))

	# Act
	var errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root, 1)

	# Assert — violation "distance 5.00m < 6m from EnemySlot_01"
	var found: bool = false
	for e: String in errors:
		if "SafeZoneCenter distance" in e and "< 6m from EnemySlot_01" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-54: violation 'SafeZoneCenter distance X < 6m from EnemySlot_01' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-54(b) hazard — FAIL : SafeZoneCenter < 4m d'un HazardSlot
# ---------------------------------------------------------------------------

## Vérifie que validate_onboarding_anchors signale SafeZoneCenter trop proche
## d'un HazardSlot_01 (distance 3.5m < 4m requis).
## Source : story-019 AC-LVL-54(b), QA Test "AC-LVL-54(b) hazard distance".
func test_safe_zone_too_close_to_hazard_fails() -> void:
	# Arrange — SafeZoneCenter à (0,0,0), HazardSlot_01 à (3.5,0,0) → dist = 3.5m < 4m
	var root: Node3D = _make_root(Vector3.ZERO)
	_add_onboarding_anchors(root, Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0))
	_add_hazard_slot(root, "01", Vector3(3.5, 0.0, 0.0))

	# Act
	var errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root, 1)

	# Assert — violation "distance 3.50m < 4m from HazardSlot_01"
	var found: bool = false
	for e: String in errors:
		if "SafeZoneCenter distance" in e and "< 4m from HazardSlot_01" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-54: violation 'SafeZoneCenter distance X < 4m from HazardSlot_01' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-54(c) — PASS : étage != 1 sans OnboardingAnchors retourne []
# ---------------------------------------------------------------------------

## Vérifie que validate_onboarding_anchors retourne [] pour étage_id == 2
## quand le sous-arbre OnboardingAnchors est absent (non-fatal).
## Source : story-019 AC-LVL-54(c), QA Test "test_onboarding_absent_on_etage_non_1_passes".
func test_onboarding_absent_on_etage_non_1_passes() -> void:
	# Arrange — fixture étage 2 sans OnboardingAnchors
	var root: Node3D = _make_root()
	# Pas de OnboardingAnchors — non-fatal pour étage != 1

	# Act
	var errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root, 2)

	# Assert — aucune violation
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-54(c): validate_onboarding_anchors(root, 2) doit retourner [] quand OnboardingAnchors absent. Erreurs : %s" % str(errors)
		) \
		.is_empty()
