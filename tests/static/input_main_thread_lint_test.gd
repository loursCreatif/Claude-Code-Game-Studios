# Tests de lint statique — Input singleton main-thread-only (ADR-0004 D-7 + VC-7).
#
# Ces tests scannent tous les fichiers src/**/*.gd via FileAccess et appliquent
# un cover-all grep pour détecter toute co-occurrence de :
#   - `Input.` dans le fichier (accès au singleton Input)
#   - ET une mention de Thread / WorkerThreadPool / call_deferred.*Input.
#
# Si co-occurrence sans annotation d'exception → FAIL (inspection manuelle requise).
#
# La règle interdit l'accès à Input.* depuis un thread non-main car :
#   - Data races silencieuses sur l'état mouse_mode
#   - Deadlocks sur le lock interne (non documenté thread-safe par Godot)
#   - État incohérent vu depuis le main thread post-switch
#
# Ce lint est un cover-all garde-fou. Au MVP, aucun fichier src/ n'utilise Thread
# ou WorkerThreadPool, donc tous les tests passent trivialement. Ils deviendront
# actifs dès qu'un développeur introduit un contexte thread dans src/ — exactement
# le cas de régression à détecter.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Rule      : .claude/rules/input-singleton-main-thread-only.md
# ADR       : ADR-0004 D-7 (main-thread only) + VC-7 (lint statique cover-all)
# Story     : chore/story-014-tech-debt-cleanup (Gap 4 — wrapper GdUnit4 manquant)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SRC_DIR: String = "res://src"

## Annotation d'exception ligne par ligne — autorise l'accès Input depuis thread
## uniquement si ce commentaire est présent dans le fichier avec une raison.
const EXCEPTION_MARKER: String = "lint-input-thread-ok"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Retourne la liste de tous les fichiers .gd sous SRC_DIR (récursif).
## Retourne un tableau vide si le répertoire est absent ou ne contient aucun .gd.
static func _collect_src_gd_files() -> Array[String]:
	var files: Array[String] = []
	var dir: DirAccess = DirAccess.open(SRC_DIR)
	if dir == null:
		return files
	_collect_recursive(SRC_DIR, files)
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
## Exception : `# lint-input-thread-ok: <raison>` justifie l'usage thread + Input.
static func _has_exception_marker(source: String) -> bool:
	return source.contains(EXCEPTION_MARKER)


# ---------------------------------------------------------------------------
# Test 1 — Collecte des fichiers src
# ---------------------------------------------------------------------------

## Vérifie que le répertoire src est accessible et contient au moins un .gd.
## Ce test sert de gate précoce : si SRC_DIR est absent ou vide, les tests
## suivants passent trivialement mais cette information doit être visible.
func test_src_dir_accessible_and_contains_gd_files() -> void:
	# Arrange / Act
	var files: Array[String] = _collect_src_gd_files()

	# Assert — le répertoire src doit exister et contenir du code
	assert_array(files) \
		.override_failure_message(
			"Src dir inaccessible ou vide : %s — vérifier que src/ existe." % SRC_DIR
		) \
		.is_not_empty()


# ---------------------------------------------------------------------------
# Test 2 — Cover-all : aucun fichier src ne co-mentionne Input.* + Thread context
# ---------------------------------------------------------------------------

## ADR-0004 D-7 + VC-7 cover-all : vérifie qu'aucun fichier de src/ ne contient
## simultanément un accès au singleton Input (\bInput\s*\.) ET une référence à un
## contexte thread (Thread / WorkerThreadPool / call_deferred.*Input\.).
##
## Algorithme (parité exacte avec le job CI lint-input-main-thread) :
##   1. Collecter tous les fichiers .gd sous src/.
##   2. Pré-filtrer : garder uniquement les fichiers qui mentionnent \bInput\s*\.
##   3. Pour chaque fichier candidat :
##      a. Skip si annotation d'exception présente dans le fichier entier.
##      b. Strip les lignes de commentaire pur.
##      c. Tester Pattern 1 : Thread(...) / Thread.new / Thread.start
##      d. Tester Pattern 2 : WorkerThreadPool.<méthode>
##      e. Tester Pattern 3 : call_deferred.*Input\. (cross-thread deferred — FAIL immédiat)
##      f. Si Pattern 1 ou 2 → REVIEW (inspection manuelle requise).
##      g. Si Pattern 3 → FAIL direct (co-occurrence sur même ligne).
##
## Limitation connue : cover-all fichier entier (pas function-scoped).
## Tout fichier src/ qui utilise à la fois Input.* et Thread doit être inspecté
## manuellement. Au MVP, aucun fichier ne déclenche ce check.
func test_no_input_access_in_thread_context() -> void:
	# Arrange
	var all_files: Array[String] = _collect_src_gd_files()
	assert_array(all_files) \
		.override_failure_message("Aucun fichier .gd trouvé dans %s" % SRC_DIR) \
		.is_not_empty()

	# Regex pré-filtre : fichiers qui touchent Input.*
	var input_rx: RegEx = RegEx.new()
	var err_input: int = input_rx.compile("\\bInput\\s*\\.")
	assert_int(err_input) \
		.override_failure_message("Regex Input\\. doit compiler") \
		.is_equal(OK)

	# Regex Pattern 1 : Thread instantiation / start
	var thread_rx: RegEx = RegEx.new()
	var err_thread: int = thread_rx.compile(
		"\\bThread\\s*(\\(|\\.new|\\.start)"
	)
	assert_int(err_thread) \
		.override_failure_message("Regex Thread context doit compiler") \
		.is_equal(OK)

	# Regex Pattern 2 : WorkerThreadPool.<méthode>
	var worker_rx: RegEx = RegEx.new()
	var err_worker: int = worker_rx.compile(
		"\\bWorkerThreadPool\\s*\\.\\w"
	)
	assert_int(err_worker) \
		.override_failure_message("Regex WorkerThreadPool context doit compiler") \
		.is_equal(OK)

	# Regex Pattern 3 : call_deferred avec Input.* (cross-thread deferred — FAIL immédiat)
	var deferred_rx: RegEx = RegEx.new()
	var err_deferred: int = deferred_rx.compile(
		"call_deferred.*Input\\."
	)
	assert_int(err_deferred) \
		.override_failure_message("Regex call_deferred Input. doit compiler") \
		.is_equal(OK)

	# Pré-filtre : garder uniquement les fichiers qui contiennent Input.*
	var input_files: Array[String] = []
	for file_path: String in all_files:
		var source: String = _read_file(file_path)
		if source.is_empty():
			continue
		if input_rx.search(source) != null:
			input_files.append(file_path)

	# Act — scan chaque fichier candidat (même logique que le job CI bash)
	var violations: Array[String] = []
	for file_path: String in input_files:
		var source: String = _read_file(file_path)
		if source.is_empty():
			continue

		# Skip si annotation d'exception présente dans le fichier
		if _has_exception_marker(source):
			continue

		var clean_source: String = _strip_pure_comment_lines(source)

		# Pattern 1 : Thread instantiation
		var has_thread: bool = thread_rx.search(clean_source) != null

		# Pattern 2 : WorkerThreadPool method call
		var has_worker: bool = worker_rx.search(clean_source) != null

		# Pattern 3 : call_deferred avec Input.* (cross-thread deferred)
		var has_deferred: bool = deferred_rx.search(clean_source) != null

		if has_thread or has_worker or has_deferred:
			# Identifier les lignes concernées pour le message d'erreur
			var lines: PackedStringArray = clean_source.split("\n")
			var input_lines: Array[String] = []
			var context_lines: Array[String] = []
			for i: int in lines.size():
				var line: String = lines[i]
				if line.is_empty():
					continue
				if input_rx.search(line) != null:
					input_lines.append("  L%d: %s" % [i + 1, line.strip_edges()])
				if thread_rx.search(line) != null or worker_rx.search(line) != null or deferred_rx.search(line) != null:
					context_lines.append("  L%d: %s" % [i + 1, line.strip_edges()])
			var reason: String = "REVIEW (inspection manuelle requise)"
			if has_deferred:
				reason = "FAIL (call_deferred + Input.* — cross-thread immédiat)"
			violations.append(
				"%s: %s\n" % [reason, file_path]
				+ "  Input.* lines:\n" + "\n".join(input_lines) + "\n"
				+ "  Thread context lines:\n" + "\n".join(context_lines)
			)

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"ADR-0004 D-7 FAIL : fichier(s) src/ co-mentionnent Input.* et contexte thread.\n"
			+ "Règle : .claude/rules/input-singleton-main-thread-only.md\n"
			+ "Si l'usage est intentionnel et sûr, ajouter `# lint-input-thread-ok: <raison>`.\n"
			+ "Violations détectées :\n" + "\n".join(violations)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# Test 3 — Tous les fichiers src/*.gd sont lisibles
# ---------------------------------------------------------------------------

## Sanity check : vérifie que FileAccess peut lire chaque .gd collecté.
## Un fichier illisible serait silencieusement ignoré par le test 2 — ce test
## rend l'anomalie visible.
func test_all_src_gd_files_are_readable() -> void:
	# Arrange
	var files: Array[String] = _collect_src_gd_files()

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
				SRC_DIR, "\n".join(unreadable)
			]
		) \
		.is_empty()
