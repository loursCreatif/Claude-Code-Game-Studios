extends GdUnitTestSuite

## Story-005 — HUD System anti-patterns static lint (parité GdUnit4 du job CI).
##
## Couvre AC-HUD-LINT-1 (outbound-only) + AC-HUD-LINT-2 (zero Input) +
## AC-HUD-LINT-3 (zero SaveLoad) + AC-HUD-LINT-4 (anti-Animation/Parallax) +
## AC-HUD-LINT-5 (anti-gradient/material) + AC-HUD-LINT-6 (corner_radius zero) +
## AC-HUD-LINT-7 (layer < 100 strict).
##
## Source : .claude/rules/hud-anti-patterns.md + design/gdd/hud-system.md.
## Exception : ligne contenant `lint-hud-ok` accepté comme marker de justification.


const SRC_HUD_DIR: String = "res://src/gameplay/hud/"
const SCENES_HUD_DIR: String = "res://scenes/hud/"


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


## Scanne `paths` (liste de fichiers) avec `pattern` regex. Retourne la liste des
## matches (path:line:content) en excluant : (a) lignes commentaires `#`,
## (b) lignes contenant `lint-hud-ok`.
func _scan_for_pattern(paths: Array[String], pattern: String) -> Array[String]:
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
			# Skip lignes commentaire pures.
			if stripped.begins_with("#"):
				continue
			# Skip lignes avec exception marker.
			if line.contains("lint-hud-ok"):
				continue
			if regex.search(line) != null:
				matches.append("%s:%d: %s" % [path, i + 1, stripped])
	return matches


# ────────── AC-HUD-LINT-1 — outbound-only zero cross-system ──────────

func test_hud_lint1_no_cross_system_dependency() -> void:
	# AC-HUD-LINT-1 [BLOCKING] — outbound-only, zéro référence cross-system.
	# Seules deps autorisées : CreditEconomy + GameStateManager.
	# Source : R-HUD outbound-only, hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SRC_HUD_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"CombatSystem|LevelSystem|MovementController|EnemySystem|Player\\.|AudioSystem|AudioServer|AudioStreamPlayer")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-1: forbidden cross-system symbol(s) in src/gameplay/hud/:\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-2 — zero Input HUD MVP ──────────

func test_hud_lint2_no_input_reference() -> void:
	# AC-HUD-LINT-2 [BLOCKING] — HUD ne lit jamais Input MVP.
	# Source : R-HUD zero Input HUD MVP, hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SRC_HUD_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"\\bInputManager\\b|\\bInput\\.")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-2: forbidden Input symbol(s) in src/gameplay/hud/:\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-3 — zero SaveLoad ref ──────────

func test_hud_lint3_no_save_load_reference() -> void:
	# AC-HUD-LINT-3 [BLOCKING] — HUD ne référence jamais SaveLoad.
	# Source : R-HUD zero SaveLoad, hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SRC_HUD_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"SaveLoad|\\bsave_int\\b|\\bsave_string_array\\b|save_now")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-3: forbidden SaveLoad symbol(s) in src/gameplay/hud/:\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-4 — anti-Animation/Parallax ──────────

func test_hud_lint4_no_animation_or_parallax() -> void:
	# AC-HUD-LINT-4 [BLOCKING] — anti-AnimationPlayer/Tree/Parallax (Chrome Zen K.7).
	# Source : hud-anti-patterns.md.
	var files: Array[String] = []
	files.append_array(_list_dir_files_recursive(SRC_HUD_DIR, [".gd"]))
	files.append_array(_list_dir_files_recursive(SCENES_HUD_DIR, [".tscn"]))
	# scenes/hud/ peut être vide au MVP — liste vide = lint trivially PASS.
	var matches: Array[String] = _scan_for_pattern(files,
		"AnimationPlayer|AnimationTree|ParallaxBackground|ParallaxLayer")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-4: forbidden Animation/Parallax symbol(s) in HUD dirs:\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-5 — anti-gradient/material (ADVISORY) ──────────

func test_hud_lint5_no_gradient_or_material() -> void:
	# AC-HUD-LINT-5 [ADVISORY] — Chrome Zen K.8 flat, zéro gradient/material.
	# Source : hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SRC_HUD_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-5: forbidden gradient/material symbol(s) in src/gameplay/hud/ (Chrome Zen K.8):\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-6 — corner_radius zero ──────────

func test_hud_lint6_corner_radius_all_zero_or_absent() -> void:
	# AC-HUD-LINT-6 [BLOCKING] — Chrome Zen K.5 hard-edge, corner_radius == 0.
	# scenes/hud/ vide au MVP → lint trivially PASS (0 fichier .tscn).
	# Source : hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SCENES_HUD_DIR, [".tscn"])
	var regex_corner := RegEx.new()
	regex_corner.compile("corner_radius")
	var regex_zero := RegEx.new()
	regex_zero.compile("=\\s*0\\b")
	var non_zero_matches: Array[String] = []
	for path in files:
		var content: String = _read_text_file(path)
		var lines: PackedStringArray = content.split("\n")
		for i in range(lines.size()):
			var line: String = lines[i]
			if regex_corner.search(line) == null:
				continue
			# Skip commentaires.
			if line.strip_edges().begins_with("#"):
				continue
			# Skip exception marker.
			if line.contains("lint-hud-ok"):
				continue
			# Pass condition : valeur explicitement 0.
			if regex_zero.search(line) != null:
				continue
			non_zero_matches.append("%s:%d: %s" % [path, i + 1, line.strip_edges()])
	assert_int(non_zero_matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-6: corner_radius non-zero in scenes/hud/ (Chrome Zen K.5):\n%s" \
			% "\n".join(non_zero_matches)) \
		.is_equal(0)


# ────────── AC-HUD-LINT-7 — layer < 100 strict ──────────

func test_hud_lint7_canvas_layer_below_100() -> void:
	# AC-HUD-LINT-7 [BLOCKING] — CanvasLayer.layer doit être < 100.
	# Refuse : layer = 100 / 101..199 / 200..999.
	# Autorise : layer = 50 (valeur canonique HUD), toute valeur < 100.
	# Source : ADR CanvasLayer ordering, hud-anti-patterns.md.
	var files: Array[String] = _list_dir_files_recursive(SRC_HUD_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"\\.layer\\s*=\\s*(100|10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])")
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-HUD-LINT-7: CanvasLayer.layer >= 100 detected in src/gameplay/hud/ (must be < 100):\n%s" \
			% "\n".join(matches)) \
		.is_equal(0)
