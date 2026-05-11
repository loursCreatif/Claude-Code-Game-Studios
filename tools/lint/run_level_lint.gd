extends SceneTree

# Runner CI standalone — scanne res://scenes/levels/etage_*.tscn et valide
# la hiérarchie canonique via LevelLint.validate_scene_hierarchy().
#
# Usage CI :
#   godot --headless --script tools/lint/run_level_lint.gd
#
# Exit 0 = PASS (ou aucune scène d'étage trouvée — cas normal avant production).
# Exit 1 = FAIL (au moins une violation détectée dans une scène).
#
# Source : story-010 AC-LVL-11 + TR-lvl-006.

const LEVELS_DIR: String = "res://scenes/levels/"
const SCENE_GLOB_PREFIX: String = "etage_"

# preload explicite : `class_name LevelLint` n'est pas résolu quand le script
# tourne via `godot --headless --script` (registry class_name peuplé uniquement
# en contexte SceneTree complet). Le preload garantit l'accès au helper.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")

func _init() -> void:
	var exit_code: int = _run_lint()
	quit(exit_code)


func _run_lint() -> int:
	# Vérification de l'existence du répertoire scenes/levels/.
	# En dehors de la production (cas actuel — pas encore d'étages), on exit 0
	# avec un push_warning pour signaler l'absence sans bloquer le pipeline.
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(LEVELS_DIR)):
		push_warning(
			"lint-level-invariants: %s absent — aucune scène d'étage à valider (PASS)" % LEVELS_DIR
		)
		return 0

	var scene_paths: Array[String] = _discover_etage_scenes()
	if scene_paths.is_empty():
		push_warning(
			"lint-level-invariants: 0 scène etage_*.tscn dans %s — PASS (rien à valider)" % LEVELS_DIR
		)
		return 0

	var total_violations: int = 0

	for path: String in scene_paths:
		var violations: Array[String] = _validate_scene(path)
		if violations.is_empty():
			print("  PASS: %s" % path)
		else:
			total_violations += violations.size()
			push_error("  FAIL: %s — %d violation(s):" % [path, violations.size()])
			for v: String in violations:
				push_error("    - %s" % v)

	if total_violations > 0:
		push_error(
			"lint-level-invariants FAIL — %d violation(s) sur %d scène(s)" % [
				total_violations, scene_paths.size()
			]
		)
		return 1

	print("lint-level-invariants PASS — %d scène(s) validée(s)" % scene_paths.size())
	return 0


## Retourne la liste des chemins res:// des scènes etage_*.tscn dans LEVELS_DIR.
func _discover_etage_scenes() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir == null:
		return paths

	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.begins_with(SCENE_GLOB_PREFIX) and filename.ends_with(".tscn"):
			paths.append(LEVELS_DIR + filename)
		filename = dir.get_next()
	dir.list_dir_end()

	paths.sort()
	return paths


## Charge une scène, l'instancie, et appelle validate_scene_hierarchy(),
## validate_room_archetypes(), validate_room_archetype_invariants(),
## validate_collision_layers(), validate_wall_thickness(), validate_level_shapes(),
## validate_door_widths(), validate_wall_run_surfaces(),
## validate_static_body_count_per_room(), validate_secret_lures(),
## validate_level_formulas() (story-020 AC-LVL-18/20/46/47/48/49/51, F3/F5/F6/F7),
## validate_onboarding_anchors() (story-019 AC-LVL-54),
## validate_visual_authoring() (story-022 TR-lvl-040/041 Chrome Zen + atlas),
## et validate_tuning_knobs_present() (story-022 TR-lvl-043 AC-LVL-44).
## Retourne la liste de toutes les violations (vide = PASS).
func _validate_scene(path: String) -> Array[String]:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return ["impossible de charger la scène : %s" % path]

	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	if root_3d == null:
		instance.queue_free()
		return ["la racine de la scène n'est pas Node3D : %s (classe: %s)" % [path, instance.get_class()]]

	# Attache au SceneTree pour que get_global_transform() / get_path() fonctionnent
	# pendant la validation. Sans ça, tous les checks positionnels (Y plancher,
	# distances onboarding, wall-run height, door width F1, etage height F5)
	# retournent 0 spurieusement.
	root.add_child(root_3d)

	var errors: Array[String] = LevelLintScript.validate_scene_hierarchy(root_3d)
	var archetype_errors: Array[String] = LevelLintScript.validate_room_archetypes(root_3d)
	errors.append_array(archetype_errors)
	var budget_errors: Array[String] = LevelLintScript.validate_room_archetype_invariants(root_3d)
	errors.append_array(budget_errors)
	var collision_errors: Array[String] = LevelLintScript.validate_collision_layers(root_3d)
	errors.append_array(collision_errors)
	var wall_errors: Array[String] = LevelLintScript.validate_wall_thickness(root_3d)
	errors.append_array(wall_errors)
	var shape_errors: Array[String] = LevelLintScript.validate_level_shapes(root_3d)
	errors.append_array(shape_errors)
	var door_errors: Array[String] = LevelLintScript.validate_door_widths(root_3d)
	errors.append_array(door_errors)
	var wall_run_errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root_3d)
	errors.append_array(wall_run_errors)
	var sb_count_errors: Array[String] = LevelLintScript.validate_static_body_count_per_room(root_3d)
	errors.append_array(sb_count_errors)
	# story-018 AC-LVL-46 / AC-LVL-53 : cohérence triplet secret + contraintes GDD F7.
	var secret_errors: Array[String] = LevelLintScript.validate_secret_lures(root_3d)
	errors.append_array(secret_errors)
	# story-020 AC-LVL-18/20/46/47/48/49/51 : formules F3/F5/F6/F7, counts PlayerStart/Room/Secret/Checkpoint.
	var formula_errors: Array[String] = LevelLintScript.validate_level_formulas(root_3d)
	errors.append_array(formula_errors)
	# story-019 AC-LVL-54 : onboarding anchors étage 1 (FirstEnemySightline + SafeZoneCenter).
	# etage_id extrait du nom de fichier (convention etage_NN.tscn).
	# Production runner : dériver l'etage_id depuis les métadonnées de scène si disponible.
	var etage_id: int = _extract_etage_id_from_path(path)
	var onboarding_errors: Array[String] = LevelLintScript.validate_onboarding_anchors(root_3d, etage_id)
	errors.append_array(onboarding_errors)
	# story-022 TR-lvl-040/041 : visual authoring Chrome Zen (primitives + shader + atlas).
	var visual_errors: Array[String] = LevelLintScript.validate_visual_authoring(root_3d)
	errors.append_array(visual_errors)
	# story-022 TR-lvl-043 AC-LVL-44 : tuning knobs YAML file presence + required keys.
	# Appelé une fois par scène — idempotent (le fichier ne change pas entre les scènes).
	var tuning_errors: Array[String] = LevelLintScript.validate_tuning_knobs_present()
	errors.append_array(tuning_errors)

	root_3d.queue_free()
	return errors


## Extrait l'etage_id entier depuis le chemin de la scène (convention etage_NN.tscn).
## Exemple : "res://scenes/levels/etage_01.tscn" → 1.
## Si le parsing échoue (nom non-standard), retourne 1 par défaut — conservateur
## (valide les invariants étage 1 même sur scènes non-numérotées).
func _extract_etage_id_from_path(path: String) -> int:
	var filename: String = path.get_file().get_basename()  # ex. "etage_01"
	var parts: PackedStringArray = filename.split("_")
	if parts.size() >= 2 and parts[1].is_valid_int():
		return parts[1].to_int()
	# Fallback conservateur : retourne 1.
	return 1
