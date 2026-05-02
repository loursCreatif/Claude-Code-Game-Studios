extends GdUnitTestSuite

## AC-MNU-63 [Static — BLOCKING] : R-MNU-18 anti-dep — Menu ne pose JAMAIS son
## propre handler `_notification(NOTIFICATION_WM_WINDOW_FOCUS_*)`. InputManager
## (ADR-0004 D-7) est single source of truth pour mouse_mode + focus events.
##
## Pattern : scan tous les .gd files sous `src/gameplay/menu/` ; reject toute
## occurrence de `NOTIFICATION_WM_WINDOW_FOCUS` ou `_notification` combiné avec
## `_focus`/`focus_in`/`focus_out`.

const MENU_DIR: String = "res://src/gameplay/menu/"


func _collect_gd_files(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var content: String = f.get_as_text()
	f.close()
	return content


func test_ac_mnu_63_no_window_focus_notification_constant_in_menu() -> void:
	# AC-MNU-63 : aucun fichier sous src/gameplay/menu/ ne mentionne le constant
	# NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT.
	var files: Array = []
	_collect_gd_files(MENU_DIR, files)

	if files.is_empty():
		# src/gameplay/menu/ n'a pas encore de fichiers — invariant trivial pass.
		return

	var violations: Array[String] = []
	for path: Variant in files:
		var content: String = _read(path)
		if content.is_empty():
			continue
		# Strip commentaires ligne pour éviter faux positifs sur doc strings.
		# Note : approche simple line-by-line ; suffit pour la précision MVP.
		for line: String in content.split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("NOTIFICATION_WM_WINDOW_FOCUS"):
				violations.append("%s: %s" % [path, stripped])

	assert_array(violations) \
		.override_failure_message("AC-MNU-63: NOTIFICATION_WM_WINDOW_FOCUS forbidden in src/gameplay/menu/ — InputManager (ADR-0004 D-7) is the single source of truth for focus events. Violations:\n%s" % "\n".join(violations)) \
		.is_empty()


func test_ac_mnu_63_no_notification_method_handling_focus() -> void:
	# AC-MNU-63 : aucun fichier sous src/gameplay/menu/ ne définit `func _notification`
	# en lien avec focus (heuristique : présence de `_notification(` ET `focus` dans
	# une fenêtre proche — on flag tout `_notification` car la classe entière n'a
	# AUCUNE raison légitime d'override _notification dans le scope Menu).
	var files: Array = []
	_collect_gd_files(MENU_DIR, files)

	if files.is_empty():
		return

	var violations: Array[String] = []
	for path: Variant in files:
		var content: String = _read(path)
		if content.is_empty():
			continue
		for line: String in content.split("\n"):
			var stripped: String = line.strip_edges()
			if stripped.begins_with("#"):
				continue
			# Heuristique stricte : déclaration de la méthode override.
			if stripped.begins_with("func _notification("):
				violations.append("%s: %s" % [path, stripped])

	assert_array(violations) \
		.override_failure_message("AC-MNU-63: `func _notification(...)` forbidden in src/gameplay/menu/ — R-MNU-18 anti-dep. Violations:\n%s" % "\n".join(violations)) \
		.is_empty()
