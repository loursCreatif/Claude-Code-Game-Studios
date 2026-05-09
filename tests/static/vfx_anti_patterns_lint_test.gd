extends GdUnitTestSuite

## Story-007 — VFX System anti-patterns static lint (parité GdUnit4 du job CI).
##
## Couvre AC-VFX-05/23 + AC-NEW-09/10 — 4 lints BLOCKING :
##   AC-VFX-05  lint-vfx-pool      — GPUParticles3D/Decal/MeshInstance3D.new() hors vfx_system.gd (R-VFX-1 + ADR-0009 D-2)
##   AC-NEW-09  lint-vfx-tween     — Tween sur color/modulate/opacity/alpha interdit (R-VFX-5/15 + ADR-0009 D-3)
##   AC-NEW-10  lint-vfx-deferred  — connect() sans CONNECT_DEFERRED interdit dans _on_* (R-VFX-3 + ADR-0009 D-4)
##   AC-VFX-23  lint-vfx-outbound  — emit_signal/.emit interdit dans VFXSystem (R-VFX-14 outbound-zero)
##
## Source : .claude/rules/vfx-anti-patterns.md + ADR-0009 D-2/D-3/D-4.
## Exception markers : `lint-vfx-{pool,tween,deferred,outbound}-ok: <raison>` ligne par ligne.


const VFX_SYSTEM_PATH: String = "res://src/core/vfx_system.gd"
const VFX_HANDLERS_DIR: String = "res://src/gameplay/vfx/"
const SRC_DIR: String = "res://src/"


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
## (b) lignes contenant `exception_marker` (e.g. `lint-vfx-tween-ok`).
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
			# Skip lignes commentaire pures.
			if stripped.begins_with("#"):
				continue
			# Skip lignes avec exception marker.
			if line.contains(exception_marker):
				continue
			if regex.search(line) != null:
				matches.append("%s:%d: %s" % [path, i + 1, stripped])
	return matches


# ────────── AC-VFX-05 — pool exclusive : zero *.new() hors vfx_system.gd ──────────

func test_lint_vfx_pool_no_node_new_outside_vfx_system() -> void:
	# AC-VFX-05 — R-VFX-1 + ADR-0009 D-2 : seul `src/core/vfx_system.gd` instancie
	# GPUParticles3D / Decal / MeshInstance3D. Les consumers passent par l'API publique.
	# Scan récursif `src/` excluant `src/core/vfx_system.gd` (pool boot autorisé).
	# `tests/` autorisé hors scope (fixtures stub).
	var all_src_files: Array[String] = _list_dir_files_recursive(SRC_DIR, [".gd"])
	var scanned: Array[String] = all_src_files.filter(
		func(path: String) -> bool: return path != VFX_SYSTEM_PATH
	)
	var matches: Array[String] = _scan_for_pattern(
		scanned,
		"GPUParticles3D\\.new\\(\\)|Decal\\.new\\(\\)|MeshInstance3D\\.new\\(\\)",
		"lint-vfx-pool-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-VFX-05 violation — VFX node instancié hors src/core/vfx_system.gd :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── AC-NEW-09 — anti-Tween sur color/modulate/opacity/alpha ──────────

func test_lint_vfx_tween_no_color_modulate_in_vfx_system() -> void:
	# AC-NEW-09 — R-VFX-5/15 + ADR-0009 D-3 : wall-clock fades exclusivement via
	# `_get_time_msec` Callable injection dans `_physics_process`. Tween sur
	# `color`/`modulate`/`opacity`/`alpha` est `time_scale`-scaled donc casse
	# Pillar 1 60 fps wall-clock indépendant slow-mo (AC-VFX-25/26).
	var paths: Array[String] = []
	var file_check: FileAccess = FileAccess.open(VFX_SYSTEM_PATH, FileAccess.READ)
	if file_check != null:
		file_check.close()
		paths.append(VFX_SYSTEM_PATH)
	paths.append_array(_list_dir_files_recursive(VFX_HANDLERS_DIR, [".gd"]))
	# Protection refactor : si vfx_system.gd renamed/déplacé sans update VFX_SYSTEM_PATH,
	# tests passeraient trivialement vert. FAIL bruyant à la place (qa-tester gap fix).
	assert_int(paths.size()) \
		.override_failure_message("AC-NEW-09/10/AC-VFX-23 — VFX_SYSTEM_PATH=%s introuvable + vfx/ vide. vfx_system.gd a-t-il été renommé/déplacé ?" % VFX_SYSTEM_PATH) \
		.is_greater(0)
	var matches: Array[String] = _scan_for_pattern(
		paths,
		"Tween\\.tween_property.*\\b(color|modulate|opacity|alpha)\\b",
		"lint-vfx-tween-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-NEW-09 violation — Tween sur color/modulate/opacity/alpha détecté hors exception annotée :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── AC-NEW-10 — connect sans CONNECT_DEFERRED dans handlers _on_* ──────────

func test_lint_vfx_deferred_handlers_use_connect_deferred() -> void:
	# AC-NEW-10 — R-VFX-3 + ADR-0009 D-4 : tous les `connect()` vers handlers
	# `_on_*` VFXSystem doivent inclure le flag `CONNECT_DEFERRED` pour éviter
	# mutations cross-system mid-physics-frame.
	#
	# Pattern : `\.connect\([^,)]+\)\s*$` capture les `.connect(arg)` à 1 seul
	# argument (donc sans flag). Filter `_on_*` retient uniquement les handlers
	# VFXSystem consumer (pas le pool tracker interne éventuel avec CONNECT_ONE_SHOT).
	var paths: Array[String] = []
	var file_check: FileAccess = FileAccess.open(VFX_SYSTEM_PATH, FileAccess.READ)
	if file_check != null:
		file_check.close()
		paths.append(VFX_SYSTEM_PATH)
	paths.append_array(_list_dir_files_recursive(VFX_HANDLERS_DIR, [".gd"]))
	if paths.is_empty():
		return
	var raw_matches: Array[String] = _scan_for_pattern(
		paths,
		"\\.connect\\([^,)]+\\)\\s*$",
		"lint-vfx-deferred-ok",
	)
	# Filter : ne garder que les lignes contenant `_on_*` handler (signature consumer).
	var on_handler_regex := RegEx.new()
	var on_compiled: int = on_handler_regex.compile("_on_[a-z_]+")
	assert_int(on_compiled).override_failure_message("Invalid filter regex _on_[a-z_]+").is_equal(OK)
	var matches: Array[String] = raw_matches.filter(
		func(line: String) -> bool: return on_handler_regex.search(line) != null
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-NEW-10 violation — connect() sans CONNECT_DEFERRED dans handler _on_* :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── AC-VFX-23 — outbound-zero : zero emit_signal / .emit dans VFXSystem ──────────

func test_lint_vfx_outbound_no_emit_in_vfx_system() -> void:
	# AC-VFX-23 — R-VFX-14 : VFX System outbound-zero terminal pur. N'émet aucun signal,
	# ne mute aucun état amont. Les consumers (Combat, Enemy, GSM) émettent VERS VFX,
	# jamais l'inverse. Zéro `emit_signal` / `.emit(` dans le scope VFX.
	var paths: Array[String] = []
	var file_check: FileAccess = FileAccess.open(VFX_SYSTEM_PATH, FileAccess.READ)
	if file_check != null:
		file_check.close()
		paths.append(VFX_SYSTEM_PATH)
	paths.append_array(_list_dir_files_recursive(VFX_HANDLERS_DIR, [".gd"]))
	if paths.is_empty():
		return
	var matches: Array[String] = _scan_for_pattern(
		paths,
		"emit_signal\\b|\\.emit\\(",
		"lint-vfx-outbound-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-VFX-23 violation — VFXSystem émet signal (R-VFX-14 outbound-zero terminal) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)
