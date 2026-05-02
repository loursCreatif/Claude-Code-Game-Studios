extends GdUnitTestSuite

## Story-009 — Chrome Zen Theme + typography static lint.
##
## AC-MNU-51 [ADVISORY] : grep tokens K.4 const Color dans src/gameplay/menu/*.gd → ≥ 4 const déclarés.
## AC-MNU-52 [ADVISORY] : ls assets/fonts/JetBrainsMono-Regular.ttf exit 0 (font embarquée).
## AC-MNU-55 [BLOCKING] : grep "layer = " pause_overlay.tscn → "layer = 80" (re-vérifié post-Theme).
## AC-MNU-56 [ADVISORY r2] : CanvasLayer.layer top-level dans scenes/ ⊆ {50, 60, 80, 100}.
## AC-MNU-66 [ADVISORY r2 U-7] : grep bg_color_2|gradient|GradientTexture dans scenes/menus/ + assets/themes/menu* → 0 match.
## AC-MNU-67 [ADVISORY r2 U-2] : grep DEBUG_SHOW_VERSION = false dans main_menu_controller.gd → ≥ 1 match.


const MAIN_MENU_CTRL_PATH: String = "res://src/gameplay/menu/main_menu_controller.gd"
const PAUSE_MENU_CTRL_PATH: String = "res://src/gameplay/menu/pause_menu_controller.gd"
const PAUSE_OVERLAY_TSCN_PATH: String = "res://scenes/menus/pause_overlay.tscn"
const FONT_TTF_PATH: String = "res://assets/fonts/JetBrainsMono-Regular.ttf"
const THEME_TRES_PATH: String = "res://assets/themes/menu_chrome_zen.tres"
const SCENES_MENUS_DIR: String = "res://scenes/menus/"
const SCENES_ROOT_DIR: String = "res://scenes/"
const ASSETS_THEMES_DIR: String = "res://assets/themes/"

const ALLOWED_LAYERS: Array[int] = [50, 60, 80, 100]
const REQUIRED_TOKENS: Array[String] = [
	"MENU_BG_BLACK",
	"MENU_PANEL_BG",
	"MENU_TEXT_BASE",
	"MENU_ACCENT_CYAN",
]


func _read_text_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Cannot open %s for lint inspection" % path) \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()
	return content


func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)


func _list_dir_files_recursive(dir_path: String, extensions: Array[String]) -> Array[String]:
	# Arrange : recursive scan filtré par suffixes (ex. .tscn, .tres, .gd).
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


# ────────── AC-MNU-51 ──────────

func test_menu_palette_tokens_declared_in_main_menu_controller() -> void:
	# AC-MNU-51 — chaque token K.4 doit être déclaré const Color dans main_menu_controller.gd.
	var content: String = _read_text_file(MAIN_MENU_CTRL_PATH)
	for token in REQUIRED_TOKENS:
		var pattern: String = "const %s: Color" % token
		assert_bool(content.contains(pattern)) \
			.override_failure_message("AC-MNU-51: main_menu_controller.gd must declare 'const %s: Color = ...' (got no match)" % token) \
			.is_true()


func test_menu_palette_tokens_declared_in_pause_menu_controller() -> void:
	# AC-MNU-51 — chaque token K.4 doit être déclaré const Color dans pause_menu_controller.gd.
	var content: String = _read_text_file(PAUSE_MENU_CTRL_PATH)
	for token in REQUIRED_TOKENS:
		var pattern: String = "const %s: Color" % token
		assert_bool(content.contains(pattern)) \
			.override_failure_message("AC-MNU-51: pause_menu_controller.gd must declare 'const %s: Color = ...' (got no match)" % token) \
			.is_true()


# ────────── AC-MNU-52 ──────────

func test_jetbrains_mono_font_embedded() -> void:
	# AC-MNU-52 — fichier TTF doit exister à res://assets/fonts/JetBrainsMono-Regular.ttf.
	assert_bool(_file_exists(FONT_TTF_PATH)) \
		.override_failure_message("AC-MNU-52: %s must exist (font embedded for build distribution)" % FONT_TTF_PATH) \
		.is_true()


func test_chrome_zen_theme_resource_exists() -> void:
	# AC-MNU-52 (extension) — Theme resource doit exister et référencer le font.
	assert_bool(_file_exists(THEME_TRES_PATH)) \
		.override_failure_message("AC-MNU-52: %s must exist (Theme resource Chrome Zen)" % THEME_TRES_PATH) \
		.is_true()
	var content: String = _read_text_file(THEME_TRES_PATH)
	assert_bool(content.contains("JetBrainsMono-Regular.ttf")) \
		.override_failure_message("AC-MNU-52: theme resource must reference JetBrainsMono-Regular.ttf as default font") \
		.is_true()


# ────────── AC-MNU-55 ──────────

func test_pause_overlay_layer_remains_80_post_theme() -> void:
	# AC-MNU-55 — re-vérification layer = 80 après application Theme (story 002 enforce déjà,
	# ce test garantit l'invariant n'est pas cassé pendant l'authoring scenes story-009).
	var content: String = _read_text_file(PAUSE_OVERLAY_TSCN_PATH)
	assert_bool(content.contains("layer = 80")) \
		.override_failure_message("AC-MNU-55: pause_overlay.tscn must contain 'layer = 80' (R-MNU-3 invariant)") \
		.is_true()


# ────────── AC-MNU-56 ──────────

func test_canvas_layer_values_subset_of_allowed_set() -> void:
	# AC-MNU-56 — toutes les valeurs `layer = N` rencontrées dans scenes/ ⊆ {50, 60, 80, 100}.
	# Cohérent HUD=50, Shop=60, Pause=80, GSM-fade=100.
	var tscn_files: Array[String] = _list_dir_files_recursive(SCENES_ROOT_DIR, [".tscn"])
	var found_layers: Array[int] = []
	var regex := RegEx.new()
	regex.compile("^layer\\s*=\\s*(\\d+)$")
	for path in tscn_files:
		var content: String = _read_text_file(path)
		for line in content.split("\n"):
			var match: RegExMatch = regex.search(line.strip_edges())
			if match != null:
				var value: int = match.get_string(1).to_int()
				if not found_layers.has(value):
					found_layers.append(value)
	for value in found_layers:
		assert_bool(ALLOWED_LAYERS.has(value)) \
			.override_failure_message("AC-MNU-56: CanvasLayer.layer = %d found in scenes/ not in allowed set %s (HUD=50, Shop=60, Pause=80, GSM-fade=100)" % [value, str(ALLOWED_LAYERS)]) \
			.is_true()


# ────────── AC-MNU-66 ──────────

func test_no_gradient_or_bg_color_2_in_menu_assets() -> void:
	# AC-MNU-66 — anti-gradient natif dans scenes/menus/ + assets/themes/menu*.
	var menu_scenes: Array[String] = _list_dir_files_recursive(SCENES_MENUS_DIR, [".tscn"])
	var theme_files: Array[String] = []
	var dir: DirAccess = DirAccess.open(ASSETS_THEMES_DIR)
	if dir != null:
		dir.list_dir_begin()
		var name: String = dir.get_next()
		while name != "":
			if name.begins_with("menu") and (name.ends_with(".tres") or name.ends_with(".res")):
				theme_files.append(ASSETS_THEMES_DIR + name)
			name = dir.get_next()
		dir.list_dir_end()
	var all_files: Array[String] = []
	all_files.append_array(menu_scenes)
	all_files.append_array(theme_files)
	var forbidden: Array[String] = ["bg_color_2", "gradient", "GradientTexture"]
	for path in all_files:
		var content: String = _read_text_file(path)
		for needle in forbidden:
			assert_bool(content.contains(needle)) \
				.override_failure_message("AC-MNU-66: '%s' found in %s — anti-gradient Chrome Zen rule violated (K.8)" % [needle, path]) \
				.is_false()


# ────────── AC-MNU-67 ──────────

func test_debug_show_version_const_false_in_main_menu() -> void:
	# AC-MNU-67 — DEBUG_SHOW_VERSION const bool = false dans main_menu_controller.gd.
	var content: String = _read_text_file(MAIN_MENU_CTRL_PATH)
	var regex := RegEx.new()
	regex.compile("const\\s+DEBUG_SHOW_VERSION\\s*:?\\s*bool\\s*=\\s*false")
	var match: RegExMatch = regex.search(content)
	assert_object(match) \
		.override_failure_message("AC-MNU-67: main_menu_controller.gd must declare 'const DEBUG_SHOW_VERSION: bool = false' (release-only safe K.9)") \
		.is_not_null()
