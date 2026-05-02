# Tests d'intégration story-021 — LevelSystemScript.validate_checkpoint_anchors().
#
# Couvre :
#   AC-LVL-40 : validate_checkpoint_anchors() runtime — anchor dans un StaticBody3D
#               (layer LAYER_ENVIRONMENT) → retourne array avec
#               { anchor_name, position, reason: "inside_static_body" }.
#   AC-LVL-40 clear : tous les anchors en espace libre → retourne [].
#
# Principe :
#   - Scene root synthétique construit programmatiquement (pas de fixture .tscn).
#   - root ajouté au scene tree via add_child(auto_free(root)) AVANT l'appel à
#     validate_checkpoint_anchors() pour que get_world_3d().direct_space_state
#     soit disponible (Jolt physics doit avoir un World3D propagé — ADR-0001).
#   - _set_current_scene_root_for_test(root) injecte le root dans le LevelSystem.
#   - 2 physics frames attendues pour que Jolt enregistre la géométrie statique.
#   - Cleanup explicite en fin de chaque test (queue_free level + root).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# Story : production/epics/level-system/story-021-validate-checkpoint-anchors-ec7.md
# Req   : TR-lvl-038
# ADR   : ADR-0001 (Jolt physics space state), ADR-0008 D-3 (collision layer API)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript attaché au scene tree.
## Retourne l'instance (caller doit queue_free en cleanup).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(level)
	return level


## Crée un Node3D racine synthétique ajouté au scene tree (auto_free).
## Le root doit être dans le tree AVANT l'appel à validate_checkpoint_anchors()
## pour que World3D soit propagé et direct_space_state disponible.
## [return] : Node3D racine.
func _make_scene_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))
	return root


## Ajoute un CheckpointAnchor_NN Marker3D à la position donnée sous root.
## [param idx]  : suffix zero-pad (ex. "01") → "CheckpointAnchor_01".
## [param pos]  : position locale (= globale si root à l'origine).
## [param root] : Node3D parent.
## [return] : Marker3D créé.
func _add_anchor(idx: String, pos: Vector3, root: Node3D) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = "CheckpointAnchor_" + idx
	marker.position = pos
	root.add_child(marker)
	return marker


## Ajoute un StaticBody3D avec une BoxShape3D (size donnée) centré à la position
## donnée sous root. Applique LAYER_ENVIRONMENT via l'API 1-indexée (ADR-0008 D-3).
## collision_mask = 0 (géométrie statique passive, AC-LVL-12).
## [param pos]      : position locale du StaticBody3D.
## [param box_size] : taille de la BoxShape3D.
## [param root]     : Node3D parent.
## [return] : StaticBody3D créé.
func _add_static_wall(pos: Vector3, box_size: Vector3, root: Node3D) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = pos
	# API 1-indexée obligatoire (ADR-0008 D-3, rule collision-layer-api-1-indexed.md).
	sb.collision_layer = 0
	sb.set_collision_layer_value(CollisionLayers.LAYER_ENVIRONMENT, true)
	sb.collision_mask = 0

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	cs.shape = box
	sb.add_child(cs)
	root.add_child(sb)
	return sb


# ---------------------------------------------------------------------------
# AC-LVL-40 — anchor à l'intérieur d'un mur détectée
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_anchors() retourne une violation
## quand CheckpointAnchor_01 est placé à l'intérieur d'un StaticBody3D
## BoxShape3D centré au même point (size 2×4×2 — anchor enfermée).
##
## Setup :
##   - CheckpointAnchor_01 à (5, 0, 0)
##   - StaticBody3D BoxShape3D size (2, 4, 2) centré à (5, 0, 0)
##     → anchor est au centre exact du mur → intersect_shape retourne ≥ 1 collision
## Source : TR-lvl-038, ADR-0001, story-021 AC-LVL-40.
func test_validate_checkpoint_anchors_detects_anchor_inside_wall() -> void:
	# Arrange
	var root: Node3D = _make_scene_root()
	_add_anchor("01", Vector3(5.0, 0.0, 0.0), root)
	_add_static_wall(Vector3(5.0, 0.0, 0.0), Vector3(2.0, 4.0, 2.0), root)

	# Attendre 2 physics frames pour que Jolt enregistre la géométrie statique.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var level: LevelSystemScript = _make_level()
	level._set_current_scene_root_for_test(root)

	# Act
	var violations: Array[Dictionary] = level.validate_checkpoint_anchors()

	# Assert — au moins une violation, anchor "CheckpointAnchor_01" détectée
	assert_array(violations) \
		.override_failure_message(
			"AC-LVL-40: validate_checkpoint_anchors() doit retourner ≥ 1 violation quand anchor dans mur"
		) \
		.has_size(1)

	if violations.size() >= 1:
		var v: Dictionary = violations[0]
		assert_str(v.get("anchor_name", "")) \
			.override_failure_message(
				"AC-LVL-40: anchor_name doit être 'CheckpointAnchor_01', reçu : %s" % str(v.get("anchor_name"))
			) \
			.is_equal("CheckpointAnchor_01")

		assert_str(v.get("reason", "")) \
			.override_failure_message(
				"AC-LVL-40: reason doit être 'inside_static_body', reçu : %s" % str(v.get("reason"))
			) \
			.is_equal("inside_static_body")

		var pos: Vector3 = v.get("position", Vector3.INF)
		assert_vector(pos) \
			.override_failure_message(
				"AC-LVL-40: position doit être ≈ (5, 0, 0), reçue : %s" % str(pos)
			) \
			.is_equal_approx(Vector3(5.0, 0.0, 0.0), Vector3(0.01, 0.01, 0.01))

	# Cleanup
	level.queue_free()


# ---------------------------------------------------------------------------
# AC-LVL-40 clear — aucun obstacle → retourne []
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_anchors() retourne [] quand
## CheckpointAnchor_01 est en espace libre (aucun StaticBody3D proche).
##
## Setup :
##   - CheckpointAnchor_01 à (5, 0, 0)
##   - Aucun StaticBody3D dans la scène
## Source : TR-lvl-038, ADR-0001, story-021 AC-LVL-40.
func test_validate_checkpoint_anchors_empty_when_all_clear() -> void:
	# Arrange
	var root: Node3D = _make_scene_root()
	_add_anchor("01", Vector3(5.0, 0.0, 0.0), root)
	# Pas de StaticBody3D — anchor en espace libre

	# Attendre 2 physics frames.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var level: LevelSystemScript = _make_level()
	level._set_current_scene_root_for_test(root)

	# Act
	var violations: Array[Dictionary] = level.validate_checkpoint_anchors()

	# Assert — aucune violation
	assert_array(violations) \
		.override_failure_message(
			"AC-LVL-40 clear: validate_checkpoint_anchors() doit retourner [] quand anchor en espace libre. Violations : "
			+ str(violations)
		) \
		.is_empty()

	# Cleanup
	level.queue_free()
