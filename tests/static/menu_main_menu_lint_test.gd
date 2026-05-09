extends GdUnitTestSuite

## AC-MNU-5/5b — anti-pattern static lint Main Menu.
##
## AC-MNU-5  [ADVISORY]  : seul GSM a le droit d'appeler change_scene_to_file pour main_menu.tscn ;
##                         src/gameplay/menu/ ne doit pas en contenir.
## AC-MNU-5b [BLOCKING]  : R-MNU-1 — zéro autoload Menu déclaré dans project.godot.
## AC-MNU-1  [lint static] : project.godot doit déclarer run/main_scene = main_menu.tscn.


func test_no_change_scene_to_file_outside_gsm() -> void:
	# AC-MNU-5 : src/gameplay/menu/ ne doit pas appeler change_scene_to_file,
	# additive, ou add_child targeting main_menu.
	var menu_dir: String = ProjectSettings.globalize_path("res://src/gameplay/menu/")
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -rE 'change_scene_to_file\\(|additive|add_child.*main_menu' %s || true" % menu_dir
	], output)
	var matches: String = "\n".join(output).strip_edges()
	assert_str(matches) \
		.override_failure_message(
			"AC-MNU-5: src/gameplay/menu/ must not call change_scene_to_file or additive add_child for main_menu (got: %s)" % matches
		) \
		.is_equal("")


func test_no_menu_autoload_declared() -> void:
	# AC-MNU-5b : project.godot ne doit déclarer aucun autoload Menu* / MenuSystem.
	var project_path: String = ProjectSettings.globalize_path("res://project.godot")
	var output: Array = []
	OS.execute("bash", ["-c",
		"awk '/\\[autoload\\]/,/^\\[/' %s" % project_path +
		" | grep -E '^(MenuSystem|MainMenuController|PauseMenuController|Menu)=' || true"
	], output)
	var matches: String = "\n".join(output).strip_edges()
	assert_str(matches) \
		.override_failure_message(
			"AC-MNU-5b: project.godot must declare zero Menu autoload (R-MNU-1) — got: %s" % matches
		) \
		.is_equal("")


func test_main_scene_points_to_main_menu() -> void:
	# AC-MNU-1 (lint static) : project.godot doit déclarer
	# run/main_scene = "res://scenes/menus/main_menu.tscn".
	var project_path: String = ProjectSettings.globalize_path("res://project.godot")
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -E '^run/main_scene=' %s || true" % project_path
	], output)
	var line: String = "\n".join(output).strip_edges()
	assert_str(line) \
		.override_failure_message(
			"AC-MNU-1: project.godot run/main_scene must point to main_menu.tscn (got: %s)" % line
		) \
		.is_equal('run/main_scene="res://scenes/menus/main_menu.tscn"')
