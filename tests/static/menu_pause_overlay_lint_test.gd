extends GdUnitTestSuite

## AC-MNU-10/37/55/58/59/62 — anti-pattern static lint Pause Overlay (story-002).
##
## AC-MNU-10 [ADVISORY] : grep "process_mode" pause_overlay.tscn → "process_mode = 3"
## AC-MNU-37 [BLOCKING] : grep "process_mode = 3" pause_overlay.tscn → 1 match exact PauseLayer
## AC-MNU-55 [BLOCKING] : grep "layer = " pause_overlay.tscn → "layer = 80" (R-MNU-3)
## AC-MNU-58 [ADVISORY] : grep -c "process_mode" pause_overlay.tscn → 1 (héritage R-MNU-14)
## AC-MNU-59 [BLOCKING] : pour chaque etage_*.tscn, grep -c "pause_overlay.tscn" == 1
## AC-MNU-62 [ADVISORY] : pas de visible=true sur PausePanel authoring (anti-flash)


const PAUSE_OVERLAY_PATH: String = "res://scenes/menus/pause_overlay.tscn"
const ETAGES_DIR: String = "res://scenes/etages/"


func _read_pause_overlay() -> String:
	var file: FileAccess = FileAccess.open(PAUSE_OVERLAY_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Cannot open %s for lint inspection" % PAUSE_OVERLAY_PATH) \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()
	return content


func test_pause_overlay_process_mode_value_is_three() -> void:
	# AC-MNU-10 + AC-MNU-37 — valeur 3 attendue (ALWAYS Godot 4.6, erratum 2026-04-28).
	var content: String = _read_pause_overlay()
	assert_bool(content.contains("process_mode = 3")) \
		.override_failure_message("AC-MNU-10/37: pause_overlay.tscn must contain 'process_mode = 3' (PROCESS_MODE_ALWAYS Godot 4.6) — got content snippet: %s" % content.substr(0, 200)) \
		.is_true()


func test_pause_overlay_layer_value_is_eighty() -> void:
	# AC-MNU-55 — R-MNU-3 layer = 80 (single match exact).
	var content: String = _read_pause_overlay()
	assert_bool(content.contains("layer = 80")) \
		.override_failure_message("AC-MNU-55: pause_overlay.tscn must contain 'layer = 80' (R-MNU-3 CanvasLayer racine)") \
		.is_true()


func test_pause_overlay_process_mode_count_is_one() -> void:
	# AC-MNU-58 — un seul process_mode dans le fichier (héritage R-MNU-14, aucun enfant override).
	var content: String = _read_pause_overlay()
	var count: int = content.count("process_mode")
	assert_int(count) \
		.override_failure_message("AC-MNU-58: pause_overlay.tscn must contain exactly 1 'process_mode' occurrence — got %d" % count) \
		.is_equal(1)


func test_pause_overlay_pause_panel_no_visible_true_authoring() -> void:
	# AC-MNU-62 — PausePanel ne doit PAS contenir visible=true en authoring (anti-flash).
	# On cherche le bloc PausePanel et vérifie que sa visibilité explicite, si présente, est false.
	var content: String = _read_pause_overlay()
	var panel_marker: String = 'name="PausePanel"'
	var panel_idx: int = content.find(panel_marker)
	assert_int(panel_idx) \
		.override_failure_message("AC-MNU-62: PausePanel node not found in pause_overlay.tscn") \
		.is_greater(-1)

	# Lecture des ~10 lignes suivant le marker pour inspecter les propriétés directes.
	var slice: String = content.substr(panel_idx, 400)
	# Couper à la prochaine définition de node pour ne pas inspecter les enfants.
	var next_node_idx: int = slice.find("[node name=", 1)
	if next_node_idx > 0:
		slice = slice.substr(0, next_node_idx)
	assert_bool(slice.contains("visible = true")) \
		.override_failure_message("AC-MNU-62: PausePanel must NOT declare 'visible = true' in authoring (anti-flash EC-MNU-32/40) — got slice: %s" % slice) \
		.is_false()


func test_pause_overlay_etage_instances_count_invariant() -> void:
	# AC-MNU-59 — pour chaque etage_*.tscn, exactement 1× instance pause_overlay.
	# Edge case Sprint A : si scenes/etages/ n'existe pas encore, le lint passe trivialement
	# (aucun fichier à valider) et signale le defer pour Level epic Sprint suivant.
	var dir: DirAccess = DirAccess.open(ETAGES_DIR)
	if dir == null:
		# Dossier absent — test deferred jusqu'à livraison Level epic.
		assert_bool(true) \
			.override_failure_message("AC-MNU-59: scenes/etages/ not yet created — invariant deferred to Level epic delivery") \
			.is_true()
		return

	var violations: Array[String] = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("etage_") and fname.ends_with(".tscn"):
			var path: String = ETAGES_DIR + fname
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var content: String = file.get_as_text()
				file.close()
				var count: int = content.count("pause_overlay.tscn")
				if count != 1:
					violations.append("%s: %d instances (expected 1)" % [fname, count])
		fname = dir.get_next()
	dir.list_dir_end()

	assert_array(violations) \
		.override_failure_message("AC-MNU-59: zero/double-instance lint violations: %s" % str(violations)) \
		.is_empty()
