extends GdUnitTestSuite

## Static lint — Collision Layer API 1-indexed contract (parité GdUnit4 du job CI).
##
## Couvre les checks de .claude/rules/collision-layer-api-1-indexed.md :
##   Check 1 (BLOCKING) — bitmask littéral (décimal, hex, binaire) dans src/**/*.gd
##                         hors src/core/collision_layers.gd.
##   Check 2 (BLOCKING) — project.godot doit contenir les 5 layer names canoniques
##                         sous [layer_names]/3d_physics/layer_1..5.
##   Check 3 (WARN MVP)  — .tscn sous scenes/** avec collision_layer/mask > 31
##                          (log seulement, pas de fail — upgrade FAIL post-MVP).
##
## Source : .claude/rules/collision-layer-api-1-indexed.md + ADR-0008 D-3/D-4/D-6.
## Exception : `# lint-collision-layers-ok: <raison>` sur la ligne concernée.


const SRC_DIR: String = "res://src/"
const COLLISION_LAYERS_PATH: String = "res://src/core/collision_layers.gd"
const PROJECT_GODOT_PATH: String = "res://project.godot"
const SCENES_DIR: String = "res://scenes/"


# ────────── Helpers ──────────

func _list_dir_files_recursive(dir_path: String, extensions: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full_path: String = dir_path + name
		if dir.current_is_dir():
			result.append_array(_list_dir_files_recursive(full_path + "/", extensions))
		else:
			for ext in extensions:
				if name.ends_with(ext):
					result.append(full_path)
					break
		name = dir.get_next()
	dir.list_dir_end()
	return result


func _read_text_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Cannot open %s for lint inspection" % path) \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()
	return content


## Scanne `paths` avec `pattern` regex. Retourne matches (path:line:content) en
## excluant (a) lignes commentaires pures `#`, (b) lignes contenant `exception_marker`.
func _scan_for_pattern(paths: Array[String], pattern: String, exception_marker: String) -> Array[String]:
	var regex := RegEx.new()
	var compiled: int = regex.compile(pattern)
	assert_int(compiled).override_failure_message("Invalid regex: %s" % pattern).is_equal(OK)
	var matches: Array[String] = []
	for path in paths:
		var content: String = _read_text_file(path)
		var lines: PackedStringArray = content.split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if line.contains(exception_marker):
				continue
			if regex.search(line) != null:
				matches.append("%s:%d: %s" % [path, i + 1, stripped])
	return matches


# ────────── Check 1 — bitmask littéral dans src/**/*.gd ──────────

func test_check1_no_bitmask_literal_in_src() -> void:
	# Check 1 [BLOCKING] — ADR-0008 D-3 : seule l'API 1-indexée est autorisée.
	# Patterns interdits : décimal, hex 0x..., binaire 0b...
	# Exception : src/core/collision_layers.gd (helper lui-même calcule les décalages).
	var all_src: Array[String] = _list_dir_files_recursive(SRC_DIR, [".gd"])
	var scanned: Array[String] = all_src.filter(
		func(path: String) -> bool: return path != COLLISION_LAYERS_PATH
	)
	var matches: Array[String] = _scan_for_pattern(
		scanned,
		"\\bcollision_(layer|mask)\\s*=\\s*(0b[01]+|0x[0-9a-fA-F]+|[0-9]+)",
		"lint-collision-layers-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"Check 1 violation — bitmask littéral collision_layer/mask détecté hors collision_layers.gd :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── Check 2 — project.godot layer names canoniques ──────────

func test_check2_project_godot_layer_names() -> void:
	# Check 2 [BLOCKING] — ADR-0008 D-4 : les 5 noms canoniques doivent être
	# présents dans project.godot sous [layer_names]/3d_physics/layer_1..5.
	var file: FileAccess = FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Cannot open project.godot for layer_names check") \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()

	var required_lines: Array[String] = [
		'3d_physics/layer_1="LAYER_PLAYER"',
		'3d_physics/layer_2="LAYER_ENEMY"',
		'3d_physics/layer_3="LAYER_ENEMY_HITBOX"',
		'3d_physics/layer_4="LAYER_ENVIRONMENT"',
		'3d_physics/layer_5="LAYER_INTERACTIVE"',
	]

	var missing: Array[String] = []
	for expected: String in required_lines:
		if not content.contains(expected):
			missing.append(expected)

	assert_int(missing.size()) \
		.override_failure_message(
			"Check 2 violation — layer names canoniques absents de project.godot :\n%s" \
			% "\n".join(missing)
		) \
		.is_equal(0)


# ────────── Check 3 — .tscn layers > 31 (WARN MVP, pas de fail) ──────────

func test_check3_tscn_collision_values_warn_only() -> void:
	# Check 3 [WARN MVP] — ADR-0008 D-6 : .tscn avec collision_layer/mask > 31
	# signalent des layers non-canoniques (6+). Pas de fail au MVP — upgrade post-MVP.
	# Ce test log les occurrences sans failer pour respecter le contrat WARN-only.
	var tscn_files: Array[String] = _list_dir_files_recursive(SCENES_DIR, [".tscn"])
	# Si scenes/ vide (avant production), test trivially PASS.
	if tscn_files.is_empty():
		return

	var regex := RegEx.new()
	regex.compile("collision_(layer|mask)\\s*=\\s*([0-9]+)")
	var warns: Array[String] = []
	for path in tscn_files:
		var content: String = _read_text_file(path)
		var lines: PackedStringArray = content.split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			var m: RegExMatch = regex.search(line)
			if m == null:
				continue
			var val: int = int(m.get_string(2))
			if val > 31:
				warns.append("%s:%d: %s (valeur=%d)" % [path, i + 1, line.strip_edges(), val])

	# MVP : log uniquement, pas d'assert fail.
	if not warns.is_empty():
		push_warning(
			"Check 3 WARN — collision_layer/mask > 31 dans .tscn (layers 6+ non-canoniques) :\n%s" \
			% "\n".join(warns)
		)
	# Test toujours PASS au MVP — le contrat est WARN only.
	assert_bool(true).is_true()
