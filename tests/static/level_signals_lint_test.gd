# Tests de lint statique — Level signals main-thread-only (ADR-0005 D-4).
#
# Ces tests scannent tous les fichiers src/gameplay/level/**/*.gd via FileAccess
# et appliquent un cover-all grep pour détecter toute co-occurrence de :
#   - .emit( ou emit_signal( dans le fichier
#   - ET une mention de Thread / WorkerThreadPool / call_deferred.*emit pattern
#
# Si co-occurrence sans annotation d'exception → FAIL (inspection manuelle requise).
#
# La règle interdit l'émission de signaux depuis un thread non-main car :
#   - Data races sur les handlers connectés qui mutent l'état de scène
#   - Deadlocks sur les locks internes de Godot
#   - Comportement indéfini lors de queue_free() / add_child() depuis un handler
#
# Ce lint est un cover-all garde-fou. Au MVP, aucun fichier src/gameplay/level/
# n'utilise Thread ou WorkerThreadPool, donc tous les tests passent trivialement.
# Ils deviendront actifs dès qu'un développeur introduit un contexte thread dans
# ce répertoire — exactement le cas de régression à détecter.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Rule      : .claude/rules/level-signals-main-thread-only.md
# ADR       : ADR-0005 D-4 (emit depuis physics process uniquement)
# Story     : chore/story-014-tech-debt-cleanup (Gap 1 — CI gate manquant)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const LEVEL_DIR: String = "res://src/gameplay/level"

## Annotation d'exception ligne par ligne — autorise l'émission depuis un contexte
## thread uniquement si ce commentaire est présent dans le fichier avec une raison.
const EXCEPTION_MARKER: String = "lint-emit-thread-ok"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Retourne la liste de tous les fichiers .gd sous LEVEL_DIR (récursif).
## Retourne un tableau vide si le répertoire est absent ou ne contient aucun .gd.
static func _collect_level_gd_files() -> Array[String]:
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(LEVEL_DIR)
	if dir == null:
		return files
	_collect_recursive(LEVEL_DIR, files)
	return files


## Collecte récursivement les fichiers .gd dans dir_path et ses sous-répertoires.
static func _collect_recursive(dir_path: String, files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path + "/" + entry
		if dir.current_is_dir():
			_collect_recursive(full_path, files)
		elif entry.ends_with(".gd"):
			files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Lit le contenu d'un fichier .gd. Retourne "" si illisible.
static func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## Retourne une copie du source avec les lignes de commentaire pur remplacées
## par des lignes vides. Préserve les numéros de ligne pour les messages d'erreur.
## Ligne commentaire pur = ligne dont le premier caractère non-espace est '#'.
static func _strip_pure_comment_lines(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var result: PackedStringArray = PackedStringArray()
	result.resize(lines.size())
	for i: int in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.begins_with("#"):
			result[i] = ""
		else:
			result[i] = lines[i]
	return "\n".join(result)


## Retourne true si le fichier contient un marqueur d'exception valide.
## Exception : `# lint-emit-thread-ok: <raison>` justifie l'usage thread + emit.
static func _has_exception_marker(source: String) -> bool:
	return source.contains(EXCEPTION_MARKER)


# ---------------------------------------------------------------------------
# Test 1 — Collecte des fichiers level
# ---------------------------------------------------------------------------

## Vérifie que le répertoire level est accessible et contient au moins un .gd.
## Ce test sert de gate précoce : si LEVEL_DIR est absent ou vide, les tests
## suivants passent trivialement mais cette information doit être visible.
func test_level_dir_accessible_and_contains_gd_files() -> void:
	# Arrange / Act
	var files: Array[String] = _collect_level_gd_files()

	# Assert — le répertoire level doit exister et contenir du code
	assert_array(files) \
		.override_failure_message(
			"Level dir inaccessible ou vide : %s — vérifier que src/gameplay/level/ existe." % LEVEL_DIR
		) \
		.is_not_empty()


# ---------------------------------------------------------------------------
# Test 2 — Cover-all : aucun fichier level ne co-mentionne emit + Thread
# ---------------------------------------------------------------------------

## ADR-0005 D-4 cover-all : vérifie qu'aucun fichier de src/gameplay/level/
## ne contient simultanément une émission de signal (.emit( ou emit_signal()
## ET une référence à un contexte thread (Thread / WorkerThreadPool /
## call_deferred.*\.emit\().
##
## Algorithme :
##   1. Pour chaque fichier .gd, lire le source.
##   2. Strip les lignes de commentaire pur.
##   3. Tester la présence d'un emit pattern.
##   4. Tester la présence d'un thread context pattern.
##   5. Si les deux sont présents ET pas d'annotation exception → FAIL.
##
## Limitation connue : cover-all fichier entier (pas function-scoped).
## Tout fichier level qui utilise à la fois emit et Thread doit être inspecté
## manuellement. Au MVP, aucun fichier ne déclenche ce check.
func test_no_emit_in_thread_context_in_level_files() -> void:
	# Arrange
	var files: Array[String] = _collect_level_gd_files()
	assert_array(files) \
		.override_failure_message("Aucun fichier .gd trouvé dans %s" % LEVEL_DIR) \
		.is_not_empty()

	var emit_rx: RegEx = RegEx.new()
	var err_emit: int = emit_rx.compile("\\.emit\\s*\\(|\\bemit_signal\\s*\\(")
	assert_int(err_emit) \
		.override_failure_message("Regex emit doit compiler") \
		.is_equal(OK)

	var thread_rx: RegEx = RegEx.new()
	# Couvre : Thread(.new/.start), WorkerThreadPool., call_deferred avec .emit
	var err_thread: int = thread_rx.compile(
		"\\bThread\\s*(\\(|\\.new|\\.start)|\\bWorkerThreadPool\\s*\\.|call_deferred.*\\.emit\\s*\\("
	)
	assert_int(err_thread) \
		.override_failure_message("Regex thread context doit compiler") \
		.is_equal(OK)

	# Act — scan chaque fichier
	var violations: Array[String] = []
	for file_path: String in files:
		var source: String = _read_file(file_path)
		if source.is_empty():
			continue

		# Skip si annotation d'exception présente dans le fichier
		if _has_exception_marker(source):
			continue

		var clean_source: String = _strip_pure_comment_lines(source)

		var has_emit: bool = emit_rx.search(clean_source) != null
		var has_thread: bool = thread_rx.search(clean_source) != null

		if has_emit and has_thread:
			# Identifier les lignes concernées pour le message d'erreur
			var lines: PackedStringArray = clean_source.split("\n")
			var emit_lines: Array[String] = []
			var thread_lines: Array[String] = []
			for i: int in lines.size():
				var line: String = lines[i]
				if line.is_empty():
					continue
				if emit_rx.search(line) != null:
					emit_lines.append("  L%d: %s" % [i + 1, line.strip_edges()])
				if thread_rx.search(line) != null:
					thread_lines.append("  L%d: %s" % [i + 1, line.strip_edges()])
			violations.append(
				"REVIEW: %s — contient .emit() ET contexte thread (inspection manuelle requise).\n"
				% file_path
				+ "  Emit lines:\n" + "\n".join(emit_lines) + "\n"
				+ "  Thread context lines:\n" + "\n".join(thread_lines)
			)

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"ADR-0005 D-4 FAIL : fichier(s) level co-mentionnent .emit() et Thread context.\n"
			+ "Règle : .claude/rules/level-signals-main-thread-only.md\n"
			+ "Si l'usage est intentionnel et sûr, ajouter `# lint-emit-thread-ok: <raison>`.\n"
			+ "Violations détectées :\n" + "\n".join(violations)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# Test 3 — Tous les fichiers level sont lisibles
# ---------------------------------------------------------------------------

## Sanity check : vérifie que FileAccess peut lire chaque .gd collecté.
## Un fichier illisible serait silencieusement ignoré par le test 2 — ce test
## rend l'anomalie visible.
func test_all_level_gd_files_are_readable() -> void:
	# Arrange
	var files: Array[String] = _collect_level_gd_files()

	# Act
	var unreadable: Array[String] = []
	for file_path: String in files:
		var source: String = _read_file(file_path)
		if source.is_empty():
			unreadable.append(file_path)

	# Assert
	assert_array(unreadable) \
		.override_failure_message(
			"Fichier(s) .gd présents dans %s mais illisibles par FileAccess :\n%s" % [
				LEVEL_DIR, "\n".join(unreadable)
			]
		) \
		.is_empty()
