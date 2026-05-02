extends GdUnitTestSuite

## Story-010 — Menu System anti-patterns static lint (parité GdUnit4 du job CI).
##
## Couvre AC-MNU-36/44/45/46/47/48/49/50/57/64 + R-MNU-18 anti-deps.
## AC-MNU-63 (focus notification) → tests/static/menu_anti_focus_handler_lint_test.gd (story-004).
## AC-MNU-66 (gradient) → tests/static/menu_theme_lint_test.gd (story-009).
##
## Source : .claude/rules/menu-anti-patterns.md + R-MNU-15/16/18/19 + ADR-0007 D-4 + ADR-0010 R-SAV-9.
## Exception : ligne contenant `lint-menu-ok` accepted comme marker de justification.


const SRC_MENU_DIR: String = "res://src/gameplay/menu/"
const SCENES_MENUS_DIR: String = "res://scenes/menus/"


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
## (b) lignes contenant `lint-menu-ok`.
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
			if line.contains("lint-menu-ok"):
				continue
			if regex.search(line) != null:
				matches.append("%s:%d: %s" % [path, i + 1, stripped])
	return matches


# ────────── AC-MNU-36 + AC-MNU-64 — anti-tween/anim ──────────

func test_no_tween_or_animation_in_src_menu() -> void:
	# AC-MNU-36 + AC-MNU-64 — R-MNU-15 + GDD K.7 + K.9 reduce-motion.
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"\\b(Tween|create_tween|tween_property|InterpolateValue|AnimationPlayer|AnimationTree)\\b")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-36 + AC-MNU-64: forbidden tween/anim symbol(s) in src/gameplay/menu/:\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-44 — anti-SFX ──────────

func test_no_audio_stream_player_in_menu_assets() -> void:
	# AC-MNU-44 — GDD K.10 zéro SFX menu MVP.
	var files: Array[String] = []
	files.append_array(_list_dir_files_recursive(SCENES_MENUS_DIR, [".tscn"]))
	files.append_array(_list_dir_files_recursive(SRC_MENU_DIR, [".gd"]))
	var matches: Array[String] = _scan_for_pattern(files,
		"AudioStreamPlayer|play_sfx|audio_play")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-44: forbidden audio symbol(s) in scenes/menus/ or src/gameplay/menu/:\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-45 — anti-confirm dialogs ──────────

func test_no_confirm_dialogs_in_menu_assets() -> void:
	# AC-MNU-45 — R-MNU-16 zero confirm anti-Pillar 1 friction.
	var files: Array[String] = []
	files.append_array(_list_dir_files_recursive(SCENES_MENUS_DIR, [".tscn"]))
	files.append_array(_list_dir_files_recursive(SRC_MENU_DIR, [".gd"]))
	var matches: Array[String] = _scan_for_pattern(files,
		"AcceptDialog|ConfirmationDialog|PopupPanel|PopupMenu")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-45: forbidden confirm dialog(s):\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-46 — corner_radius zero ──────────

func test_corner_radius_values_all_zero_or_absent() -> void:
	# AC-MNU-46 — Chrome Zen K.5 hard-edge.
	var files: Array[String] = _list_dir_files_recursive(SCENES_MENUS_DIR, [".tscn"])
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
			# Pass condition : valeur explicitement 0.
			if regex_zero.search(line) != null:
				continue
			non_zero_matches.append("%s:%d: %s" % [path, i + 1, line.strip_edges()])
	assert_int(non_zero_matches.size()) \
		.override_failure_message("AC-MNU-46: corner_radius non-zero in scenes/menus/:\n%s" % "\n".join(non_zero_matches)) \
		.is_equal(0)


# ────────── AC-MNU-47 — anti-Parallax/Animation ──────────

func test_no_parallax_or_animation_player_in_menu_scenes() -> void:
	# AC-MNU-47 — GDD K.7 anti-animation menus.
	var files: Array[String] = _list_dir_files_recursive(SCENES_MENUS_DIR, [".tscn"])
	var matches: Array[String] = _scan_for_pattern(files,
		"ParallaxBackground|ParallaxLayer|AnimationPlayer|AnimationTree")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-47: forbidden Parallax/Animation symbol(s) in scenes/menus/:\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-48 — anti-gradient/material ──────────

func test_no_gradient_or_material_in_src_menu() -> void:
	# AC-MNU-48 — GDD K.8 Chrome Zen flat.
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-48: forbidden gradient/material symbol(s) in src/gameplay/menu/:\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-49 — Engine.time_scale ──────────

func test_no_engine_time_scale_in_src_menu() -> void:
	# AC-MNU-49 — ADR-0007 D-4 GSM seul autorité.
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files, "Engine\\.time_scale")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-49: Engine.time_scale mutated from src/gameplay/menu/ (ADR-0007 D-4 violation):\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-50 — get_tree().paused ──────────

func test_no_get_tree_paused_mutation_in_src_menu() -> void:
	# AC-MNU-50 — ADR-0007 D-4 autorité unique GSM.
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"get_tree\\(\\)\\.paused|SceneTree.*paused")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-50: get_tree().paused mutation in src/gameplay/menu/ (ADR-0007 D-4 violation):\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── AC-MNU-57 — zero SaveLoad ref ──────────

func test_no_save_load_reference_in_src_menu() -> void:
	# AC-MNU-57 — R-MNU-19 + ADR-0010 R-SAV-9 délégation pure.
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"SaveLoad|\\bsave_int\\b|\\bsave_string_array\\b|save_now")
	assert_int(matches.size()) \
		.override_failure_message("AC-MNU-57: SaveLoad symbol(s) referenced from src/gameplay/menu/ (R-MNU-19 + R-SAV-9 violation):\n%s" % "\n".join(matches)) \
		.is_equal(0)


# ────────── R-MNU-18 — anti-deps cross-system ──────────

func test_no_cross_system_dependency_in_src_menu() -> void:
	# R-MNU-18 — Menu ne référence aucun système gameplay (Level/Combat/Movement/Credit/Secret/Upgrade).
	var files: Array[String] = _list_dir_files_recursive(SRC_MENU_DIR, [".gd"])
	var matches: Array[String] = _scan_for_pattern(files,
		"\\b(LevelSystem|CombatSystem|MovementController|CreditSystem|SecretSystem|UpgradeSystem)\\b")
	assert_int(matches.size()) \
		.override_failure_message("R-MNU-18: cross-system dependency in src/gameplay/menu/:\n%s" % "\n".join(matches)) \
		.is_equal(0)
