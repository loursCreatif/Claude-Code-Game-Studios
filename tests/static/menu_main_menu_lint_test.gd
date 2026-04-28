extends GutTest

## AC-MNU-5/5b — anti-pattern static lint Main Menu.
##
## AC-MNU-5  [ADVISORY]  : seul GSM a le droit d'appeler change_scene_to_file pour main_menu.tscn ;
##                         src/gameplay/menu/ ne doit pas en contenir.
## AC-MNU-5b [BLOCKING]  : R-MNU-1 — zéro autoload Menu déclaré dans project.godot.


func test_no_change_scene_to_file_outside_gsm() -> void:
	# AC-MNU-5 : src/gameplay/menu/ ne doit pas appeler change_scene_to_file,
	# additive, ou add_child targeting main_menu.
	var output: Array = []
	OS.execute("bash", ["-c",
		"grep -rE 'change_scene_to_file|additive|add_child.*main_menu'" +
		" /Users/magnes/Documents/TestClaudeGameStudio/src/gameplay/menu/ || true"
	], output)
	var matches: String = "\n".join(output).strip_edges()
	assert_eq(
		matches,
		"",
		"AC-MNU-5: src/gameplay/menu/ must not call change_scene_to_file or additive add_child for main_menu (got: %s)" % matches
	)


func test_no_menu_autoload_declared() -> void:
	# AC-MNU-5b : project.godot ne doit déclarer aucun autoload Menu* / MenuSystem.
	var output: Array = []
	OS.execute("bash", ["-c",
		"awk '/\\[autoload\\]/,/^\\[/' /Users/magnes/Documents/TestClaudeGameStudio/project.godot" +
		" | grep -E '^(MenuSystem|MainMenuController|PauseMenuController|Menu)=' || true"
	], output)
	var matches: String = "\n".join(output).strip_edges()
	assert_eq(
		matches,
		"",
		"AC-MNU-5b: project.godot must declare zero Menu autoload (R-MNU-1) — got: %s" % matches
	)
