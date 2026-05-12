extends GdUnitTestSuite

## Story-009 — Audio System anti-patterns static lint (parité GdUnit4 du job CI).
##
## Couvre AC-AUD-10/11/12 — 3 lints BLOCKING :
##   AC-AUD-10 lint-audio-tween     — Tween volume_db interdit (R-AUD-4 + ADR-0009 D-3)
##   AC-AUD-11 lint-audio-deferred  — connect() sans CONNECT_DEFERRED interdit dans _on_* (R-AUD-5 + D-4)
##   AC-AUD-12 lint-audio-pool      — AudioStreamPlayer.new() hors audio_system.gd interdit (R-AUD-1 + D-2)
##
## Source : .claude/rules/audio-anti-patterns.md + ADR-0009 D-2/D-3/D-4.
## Exception markers : `lint-audio-{tween,deferred,pool}-ok: <raison>` ligne par ligne.


const AUDIO_SYSTEM_PATH: String = "res://src/core/audio_system.gd"
const AUDIO_HANDLERS_DIR: String = "res://src/gameplay/audio/"
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
## (b) lignes contenant `exception_marker` (e.g. `lint-audio-tween-ok`).
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


# ────────── AC-AUD-10 — anti-Tween volume_db ──────────

func test_lint_audio_tween_no_volume_db_tween() -> void:
	# AC-AUD-10 — R-AUD-4 + ADR-0009 D-3 : wall-clock fades exclusivement via
	# `_get_time_msec` Callable injection dans `_physics_process`. Tween sur
	# `volume_db` est `time_scale`-scaled donc casse Pillar 1 60 fps wall-clock.
	var paths: Array[String] = [AUDIO_SYSTEM_PATH]
	paths.append_array(_list_dir_files_recursive(AUDIO_HANDLERS_DIR, [".gd"]))
	var matches: Array[String] = _scan_for_pattern(
		paths,
		"Tween\\.tween_property.*volume_db|tween\\..*audio.*volume_db",
		"lint-audio-tween-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-AUD-10 violation — Tween volume_db détecté hors exception annotée :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── AC-AUD-11 — connect sans CONNECT_DEFERRED dans handlers _on_* ──────────

func test_lint_audio_deferred_handlers_use_connect_deferred() -> void:
	# AC-AUD-11 — R-AUD-5 + ADR-0009 D-4 : tous les `connect()` vers handlers
	# `_on_*` AudioSystem doivent inclure le flag `CONNECT_DEFERRED` pour éviter
	# mutations cross-system mid-physics-frame.
	#
	# Pattern : `\.connect\([^,)]+\)\s*$` capture les `.connect(arg)` à 1 seul
	# argument (donc sans flag). Filter `_on_*` retient uniquement les handlers
	# AudioSystem / consumer (pas le pool tracker `finished` interne sur
	# `_on_clac_slot_finished` story-007 qui utilise `CONNECT_ONE_SHOT`).
	var paths: Array[String] = [AUDIO_SYSTEM_PATH]
	paths.append_array(_list_dir_files_recursive(AUDIO_HANDLERS_DIR, [".gd"]))
	var raw_matches: Array[String] = _scan_for_pattern(
		paths,
		"\\.connect\\([^,)]+\\)\\s*$",
		"lint-audio-deferred-ok",
	)
	# Filter : ne garder que les lignes contenant `_on_*` handler (signature consumer).
	var on_handler_regex := RegEx.new()
	on_handler_regex.compile("_on_[a-z_]+")
	var matches: Array[String] = raw_matches.filter(
		func(line: String) -> bool: return on_handler_regex.search(line) != null
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-AUD-11 violation — connect() sans CONNECT_DEFERRED dans handler _on_* :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


# ────────── AC-AUD-12 — AudioStreamPlayer.new() hors audio_system.gd ──────────

func test_lint_audio_pool_no_streamplayer_new_outside_audio_system() -> void:
	# AC-AUD-12 — R-AUD-1 + ADR-0009 D-2 : seul `src/core/audio_system.gd` instancie
	# `AudioStreamPlayer*` / `AudioListener3D`. Les consumers passent par l'API
	# publique (`play_2d`, `play_3d_at`, `play_music`, `duck_bus`, `set_paused`).
	#
	# Scan récursif `src/` excluant `src/core/audio_system.gd` (pool boot autorisé).
	# `tests/` autorisé hors scope (fixtures stub).
	var all_src_files: Array[String] = _list_dir_files_recursive(SRC_DIR, [".gd"])
	var scanned: Array[String] = all_src_files.filter(
		func(path: String) -> bool: return path != AUDIO_SYSTEM_PATH
	)
	var matches: Array[String] = _scan_for_pattern(
		scanned,
		"AudioStreamPlayer\\.new\\(\\)|AudioStreamPlayer3D\\.new\\(\\)|AudioListener3D\\.new\\(\\)",
		"lint-audio-pool-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-AUD-12 violation — AudioStreamPlayer.new() instancié hors src/core/audio_system.gd :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)
