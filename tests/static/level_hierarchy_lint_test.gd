extends GdUnitTestSuite

## Static lint — Level Scene hierarchy invariants (parité GdUnit4 du job CI).
##
## Délègue à LevelLint.validate_*() sur chaque scène etage_*.tscn trouvée sous
## res://scenes/levels/. Reproduit le comportement de run_level_lint.gd en contexte
## GdUnit4 pour exécution locale rapide (sans runner CLI séparé).
##
## Si aucune scène etage_*.tscn n'existe → test PASS trivial (skip gracieux,
## identique au runner CLI).
##
## Source : .claude/rules/level-hierarchy-invariants.md + ADR-0011 D-2/D-7/D-13.
## Couvre : validate_scene_hierarchy, validate_room_archetypes,
##           validate_room_archetype_invariants, validate_collision_layers,
##           validate_wall_thickness, validate_level_shapes, validate_door_widths,
##           validate_wall_run_surfaces, validate_static_body_count_per_room,
##           validate_checkpoint_pairs, validate_secret_lures, validate_level_formulas,
##           validate_onboarding_anchors, validate_visual_authoring,
##           validate_tuning_knobs_present, validate_enemy_slot_marker3d,
##           validate_enemy_slot_min_distance, validate_enemy_slot_clearance.


## preload explicite : class_name LevelLint non résolu en CI headless sans SceneTree.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")

const LEVELS_DIR: String = "res://scenes/levels/"
const SCENE_GLOB_PREFIX: String = "etage_"


# ────────── Helpers ──────────

## Découvre toutes les scènes etage_*.tscn sous LEVELS_DIR. Retourne liste triée.
func _discover_etage_scenes() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() \
				and filename.begins_with(SCENE_GLOB_PREFIX) \
				and filename.ends_with(".tscn"):
			paths.append(LEVELS_DIR + filename)
		filename = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Extrait l'etage_id entier depuis le chemin (convention etage_NN.tscn).
## Exemple : "res://scenes/levels/etage_01.tscn" → 1. Fallback : 1.
func _extract_etage_id_from_path(path: String) -> int:
	var filename: String = path.get_file().get_basename()
	var parts: PackedStringArray = filename.split("_")
	if parts.size() >= 2 and parts[1].is_valid_int():
		return parts[1].to_int()
	return 1


## Charge une scène, l'instancie, appelle tous les validate_*() et retourne
## la liste agrégée de violations (vide = PASS).
func _validate_scene(path: String) -> Array[String]:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return ["impossible de charger la scène : %s" % path]

	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	if root_3d == null:
		instance.queue_free()
		return [
			"la racine de la scène n'est pas Node3D : %s (classe: %s)" \
			% [path, instance.get_class()]
		]

	# Enregistre avec auto_free pour nettoyage GdUnit4.
	add_child(auto_free(root_3d))

	var errors: Array[String] = []
	errors.append_array(LevelLintScript.validate_scene_hierarchy(root_3d))
	errors.append_array(LevelLintScript.validate_room_archetypes(root_3d))
	errors.append_array(LevelLintScript.validate_room_archetype_invariants(root_3d))
	errors.append_array(LevelLintScript.validate_collision_layers(root_3d))
	errors.append_array(LevelLintScript.validate_wall_thickness(root_3d))
	errors.append_array(LevelLintScript.validate_level_shapes(root_3d))
	errors.append_array(LevelLintScript.validate_door_widths(root_3d))
	errors.append_array(LevelLintScript.validate_wall_run_surfaces(root_3d))
	errors.append_array(LevelLintScript.validate_static_body_count_per_room(root_3d))
	errors.append_array(LevelLintScript.validate_checkpoint_pairs(root_3d))
	errors.append_array(LevelLintScript.validate_secret_lures(root_3d))
	errors.append_array(LevelLintScript.validate_level_formulas(root_3d))

	var etage_id: int = _extract_etage_id_from_path(path)
	errors.append_array(LevelLintScript.validate_onboarding_anchors(root_3d, etage_id))

	errors.append_array(LevelLintScript.validate_visual_authoring(root_3d))
	errors.append_array(LevelLintScript.validate_tuning_knobs_present())
	errors.append_array(LevelLintScript.validate_enemy_slot_marker3d(root_3d))
	errors.append_array(LevelLintScript.validate_enemy_slot_min_distance(root_3d))
	errors.append_array(LevelLintScript.validate_enemy_slot_clearance(root_3d))

	return errors


# ────────── Test — hiérarchie canonique sur toutes les scènes ──────────

func test_level_hierarchy_all_etage_scenes_pass_all_invariants() -> void:
	# Couvre ADR-0011 D-2/D-7/D-13 — 11+ invariants pré-build sur chaque etage_*.tscn.
	# Skip gracieux si aucune scène trouvée (normal avant production).
	# Source : .claude/rules/level-hierarchy-invariants.md + run_level_lint.gd.
	var scene_paths: Array[String] = _discover_etage_scenes()

	if scene_paths.is_empty():
		# Aucune scène etage_*.tscn — PASS trivial (identique au runner CLI).
		assert_bool(true).is_true()
		return

	var all_violations: Array[String] = []
	for path: String in scene_paths:
		var violations: Array[String] = _validate_scene(path)
		for v: String in violations:
			all_violations.append("%s: %s" % [path, v])

	assert_int(all_violations.size()) \
		.override_failure_message(
			"Level hierarchy violations (%d) — %d scène(s) vérifiée(s) :\n%s" \
			% [all_violations.size(), scene_paths.size(), "\n".join(all_violations)]
		) \
		.is_equal(0)
