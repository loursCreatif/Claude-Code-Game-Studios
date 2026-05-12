# Tests d'intégration story-019 — Raycast ligne-de-vue FirstEnemySightline.
#
# Couvre :
#   AC-LVL-54(a) LOS runtime : raycast PlayerStart → FirstEnemySightline via
#     PhysicsDirectSpaceState3D.intersect_ray(). Si un StaticBody3D (LAYER_ENVIRONMENT)
#     obstrue la ligne, le raycast est hitté → violation détectée.
#     Si aucun obstacle → raycast libre → PASS.
#
# Principe :
#   - Scene root synthétique construit programmatiquement (pas de fixture .tscn).
#   - StaticBody3D optionnel ajouté entre PlayerStart et FirstEnemySightline.
#   - root ajouté au scene tree AVANT le raycast pour que get_world_3d().direct_space_state
#     soit disponible (Jolt physics doit avoir un World3D propagé — ADR-0001).
#   - await get_tree().physics_frame (x2) pour que Jolt enregistre la géométrie statique.
#   - Raycast via PhysicsRayQueryParameters3D.create(start, end, mask).
#   - Collision mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])
#     (ADR-0008 D-3 + rule collision-layer-api-1-indexed.md — pas de bitmask littéral).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# Story : production/epics/level-system/story-019-onboarding-anchors-validate-api.md
# Req   : AC-LVL-54(a) line-of-sight runtime
# ADR   : ADR-0001 (Jolt physics space state), ADR-0008 D-1/D-3 (collision layer API)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un Node3D racine synthétique ajouté au scene tree (auto_free).
## Le root doit être dans le tree AVANT le raycast pour que World3D soit propagé.
func _make_scene_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))
	return root


## Ajoute un Marker3D à la position donnée sous root.
func _add_marker(name_str: String, pos: Vector3, root: Node3D) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = name_str
	marker.position = pos
	root.add_child(marker)
	return marker


## Ajoute un StaticBody3D avec une BoxShape3D sur LAYER_ENVIRONMENT entre deux points.
## Centré à `center_pos`, size = box_size. Collision_mask = 0 (géométrie statique passive).
## [param center_pos] : position locale du StaticBody3D.
## [param box_size]   : taille de la BoxShape3D.
## [param root]       : Node3D parent.
## [return] : StaticBody3D créé.
func _add_wall(center_pos: Vector3, box_size: Vector3, root: Node3D) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.position = center_pos
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
# AC-LVL-54(a) LOS — mur entre PlayerStart et Sightline → raycast hitté
# ---------------------------------------------------------------------------

## Vérifie que le raycast PlayerStart → FirstEnemySightline retourne un hit non vide
## quand un StaticBody3D (LAYER_ENVIRONMENT) obstrue la ligne entre les deux points.
## Un hit = obstruction = violation de la contrainte ligne-de-vue.
##
## Edge case contrôlé dans le même test : sans mur, le raycast est libre (empty hit).
##
## Setup avec mur :
##   - PlayerStart à (0, 1, 0)
##   - FirstEnemySightline à (10, 1, 0)
##   - StaticBody3D BoxShape3D size (1, 2, 1) centré à (5, 1, 0) — mur entre les deux
##     → raycast de (0,1,0) vers (10,1,0) traverse le mur → hit non vide = obstruction
##
## Setup sans mur (edge case clear) :
##   - Mêmes positions, aucun StaticBody3D → raycast libre → hit vide = pas d'obstruction
##
## Source : story-019 AC-LVL-54(a), QA Test "test_first_enemy_sightline_obstructed_raycast_fails".
func test_first_enemy_sightline_obstructed_raycast_fails() -> void:
	# --- Setup avec mur (obstruction) ---
	var root_wall: Node3D = _make_scene_root()
	var player_start_wall: Marker3D = _add_marker("PlayerStart", Vector3(0.0, 1.0, 0.0), root_wall)
	var sightline_wall: Marker3D = _add_marker("FirstEnemySightline", Vector3(10.0, 1.0, 0.0), root_wall)
	_add_wall(Vector3(5.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0), root_wall)

	# Attendre 2 physics frames pour que Jolt enregistre la géométrie statique.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Raycast avec mur : PlayerStart → Sightline, mask = LAYER_ENVIRONMENT
	var space_wall: PhysicsDirectSpaceState3D = root_wall.get_world_3d().direct_space_state
	var query_wall: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		player_start_wall.global_position,
		sightline_wall.global_position,
		CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])
	)
	var result_wall: Dictionary = space_wall.intersect_ray(query_wall)

	# Assert — raycast hitté = obstruction présente = violation LOS
	assert_bool(result_wall.is_empty()) \
		.override_failure_message(
			"AC-LVL-54(a): raycast avec mur doit retourner un hit (obstruction). Résultat : %s" % str(result_wall)
		) \
		.is_false()

	# Free immédiat du 1er setup AVANT le 2nd : auto_free n'opère qu'en fin de test.
	# Si on ne free pas immédiatement, le mur du 1er setup persiste dans le World3D
	# partagé du SceneTree de la suite, polluant le raycast clear du 2nd setup.
	root_wall.free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- Edge case : sans mur (ligne libre) ---
	var root_clear: Node3D = _make_scene_root()
	var player_start_clear: Marker3D = _add_marker("PlayerStart", Vector3(0.0, 1.0, 0.0), root_clear)
	var sightline_clear: Marker3D = _add_marker("FirstEnemySightline", Vector3(10.0, 1.0, 0.0), root_clear)
	# Pas de StaticBody3D — ligne libre

	await get_tree().physics_frame
	await get_tree().physics_frame

	var space_clear: PhysicsDirectSpaceState3D = root_clear.get_world_3d().direct_space_state
	var query_clear: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		player_start_clear.global_position,
		sightline_clear.global_position,
		CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])
	)
	var result_clear: Dictionary = space_clear.intersect_ray(query_clear)

	# Assert — raycast vide = ligne libre = pas d'obstruction = PASS
	assert_bool(result_clear.is_empty()) \
		.override_failure_message(
			"AC-LVL-54(a) clear: raycast sans mur doit retourner {} (ligne libre). Résultat : %s" % str(result_clear)
		) \
		.is_true()
