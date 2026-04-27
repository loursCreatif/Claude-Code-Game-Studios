# Tests de lint statique story-011 — Outbound-only + emit-physics-only (VC-5 + VC-6).
#
# Ces tests lisent le source de movement_controller.gd via FileAccess et appliquent
# des regex line-based pour détecter les violations de l'ADR-0005. Ils constituent
# le CI gate statique (blocking) pour les règles suivantes :
#
#   VC-5 — Lint outbound-only : MovementController ne référence aucun consumer
#           downstream (CameraSystem, CombatSystem, VFXManager, AudioManager, HUDController).
#           Rule : .claude/rules/movement-no-consumer-refs.md
#
#   VC-6 — Lint emit-physics-only : aucun .emit( dans les fonctions lifecycle
#           _process / _input / _unhandled_input / _ready / _notification.
#           Rule : .claude/rules/movement-emit-physics-only.md
#
#   Payloads — Aucun Dict literal / Array literal / emit_signal() deprecated.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story     : production/epics/player-movement-system/story-011-zero-alloc-outbound-lint.md
# ADR       : ADR-0005 D-10 (VC-5) + D-4 (VC-6) + D-9 (payloads value-types)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MOVEMENT_PATH: String = "res://src/gameplay/player/movement_controller.gd"

## Noms des consumers downstream interdits dans movement_controller.gd.
## ADR-0005 D-10 : MovementController est outbound-only — zéro connaissance
## des consumers. Chaque consumer se connecte depuis son propre _ready().
const CONSUMER_NAMES: Array[String] = [
	"CameraSystem",
	"CombatSystem",
	"VFXManager",
	"AudioManager",
	"HUDController",
]

## Fonctions lifecycle dans lesquelles .emit( est interdit (ADR-0005 D-4).
## Les emits doivent être dans _physics_process ou fonctions appelées depuis lui.
const FORBIDDEN_EMIT_FUNCS: Array[String] = [
	"_process",
	"_input",
	"_unhandled_input",
	"_ready",
	"_notification",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Lit le source de movement_controller.gd et retourne le texte brut.
## Échoue le test si le fichier n'est pas lisible (path incorrect ou absent).
static func _read_movement_source() -> String:
	var file: FileAccess = FileAccess.open(MOVEMENT_PATH, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content


## Retourne une copie du source avec les lignes de commentaire (commençant par #
## après les espaces) remplacées par des lignes vides. Préserve les numéros de
## ligne pour que les messages d'erreur pointent vers les bonnes lignes.
##
## Exclut les pure-comment lines uniquement. Les commentaires en fin de ligne
## (code + # ...) sont conservés — le pattern de lint est assez précis pour
## ne pas faire de faux positifs dans cette zone.
static func _strip_comments(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var result: PackedStringArray = PackedStringArray()
	result.resize(lines.size())
	for i: int in lines.size():
		var stripped: String = lines[i].strip_edges()
		if stripped.begins_with("#"):
			result[i] = ""  # ligne commentaire — neutralisée
		else:
			result[i] = lines[i]
	return "\n".join(result)


# ---------------------------------------------------------------------------
# VC-5a — Aucune référence consumer par nom
# ---------------------------------------------------------------------------

## VC-5 ADR-0005 D-10 : vérifie qu'aucun des noms de consumer downstream
## (CameraSystem, CombatSystem, VFXManager, AudioManager, HUDController)
## n'apparaît dans le source de movement_controller.gd (hors commentaires).
##
## Les commentaires doc-comment (lignes commençant par #) sont exclus pour
## éviter les faux positifs sur des références pédagogiques dans les docs.
func test_no_consumer_references_in_movement_controller() -> void:
	# Arrange
	var source: String = _read_movement_source()
	assert_str(source) \
		.override_failure_message(
			"VC-5 : impossible de lire %s — vérifier le path." % MOVEMENT_PATH
		) \
		.is_not_empty()

	var clean_source: String = _strip_comments(source)
	var lines: PackedStringArray = clean_source.split("\n")

	var regex: RegEx = RegEx.new()
	# Pattern : word-boundary pour éviter les faux positifs sur des sous-chaînes.
	var compile_err: int = regex.compile(
		"\\b(CameraSystem|CombatSystem|VFXManager|AudioManager|HUDController)\\b"
	)
	assert_int(compile_err) \
		.override_failure_message("VC-5 : regex de consumer names doit compiler") \
		.is_equal(OK)

	# Act — scan ligne par ligne
	var violations: Array[String] = []
	for i: int in lines.size():
		var line: String = lines[i]
		if line.is_empty():
			continue
		if regex.search(line) != null:
			violations.append("L%d: %s" % [i + 1, source.split("\n")[i].strip_edges()])

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"VC-5 ADR-0005 D-10 FAIL : movement_controller.gd référence des consumers "
			+ "downstream (outbound-only interdit). Violations :\n"
			+ "\n".join(violations)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# VC-5b — Aucun get_node/preload/$ vers consumer path
# ---------------------------------------------------------------------------

## VC-5 (cont) ADR-0005 D-10 : vérifie l'absence de patterns de lookup direct
## vers des consumers (get_node "/root/...", preload path, dollar NodePath).
func test_no_node_path_or_preload_to_consumer_path() -> void:
	# Arrange
	var source: String = _read_movement_source()
	assert_str(source).is_not_empty()

	var clean_source: String = _strip_comments(source)
	var lines: PackedStringArray = clean_source.split("\n")

	# Trois patterns couvrant les formes de lookup interdit vers consumers.
	var patterns: Array[String] = [
		'get_node\\("/root/(CameraSystem|CombatSystem|VFXManager|AudioManager)',
		'preload\\("res://src/gameplay/(camera|combat|vfx|audio|hud)',
		'\\$(CameraSystem|CombatSystem|VFXManager|HUDController)\\b',
	]

	var regexes: Array[RegEx] = []
	for p: String in patterns:
		var rx: RegEx = RegEx.new()
		var err: int = rx.compile(p)
		assert_int(err) \
			.override_failure_message("VC-5b : pattern '%s' doit compiler" % p) \
			.is_equal(OK)
		regexes.append(rx)

	# Act
	var violations: Array[String] = []
	for i: int in lines.size():
		var line: String = lines[i]
		if line.is_empty():
			continue
		for rx: RegEx in regexes:
			if rx.search(line) != null:
				violations.append("L%d: %s" % [i + 1, source.split("\n")[i].strip_edges()])
				break  # une seule entrée par ligne

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"VC-5b ADR-0005 D-10 FAIL : movement_controller.gd contient des lookups directs "
			+ "vers des consumers (get_node/preload/$ interdits). Violations :\n"
			+ "\n".join(violations)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# VC-6 — Aucun .emit( dans les fonctions lifecycle interdites
# ---------------------------------------------------------------------------

## VC-6 ADR-0005 D-4 : vérifie qu'aucun .emit( n'apparaît dans le body des
## fonctions _process, _input, _unhandled_input, _ready, _notification.
##
## Algorithme mini-parser :
##   - Détecte les débuts de fonction via regex `^func <name>(`.
##   - Suit si la fonction courante est dans la liste interdite.
##   - Sur chaque ligne du body, cherche `\.emit\(`.
##   - Une nouvelle ligne `^func ` ferme le body précédent.
##
## Limitation connue : le parser suppose une indentation cohérente (top-level
## func déclarée sans indentation). Fonctions imbriquées (lambdas) non couvertes
## — acceptable au MVP (MovementController n'en utilise pas).
func test_no_emit_in_lifecycle_methods() -> void:
	# Arrange
	var source: String = _read_movement_source()
	assert_str(source).is_not_empty()

	var lines: PackedStringArray = source.split("\n")

	# Regex de détection des débuts de top-level func.
	var func_start_rx: RegEx = RegEx.new()
	func_start_rx.compile("^func (\\w+)\\s*\\(")

	# Regex de détection des appels .emit(.
	var emit_rx: RegEx = RegEx.new()
	emit_rx.compile("\\.emit\\s*\\(")

	# Act — mini-parser line-based
	var in_forbidden_func: bool = false
	var current_func_name: String = ""
	var violations: Array[String] = []

	for i: int in lines.size():
		var line: String = lines[i]

		# Détection d'un nouveau top-level func (pas indenté).
		var func_match: RegExMatch = func_start_rx.search(line)
		if func_match != null and not line.begins_with("\t") and not line.begins_with(" "):
			current_func_name = func_match.get_string(1)
			in_forbidden_func = current_func_name in FORBIDDEN_EMIT_FUNCS

		# Si dans une fonction interdite, chercher .emit(.
		if in_forbidden_func:
			var line_stripped: String = line.strip_edges()
			# Exclure les lignes de commentaire.
			if line_stripped.begins_with("#"):
				continue
			if emit_rx.search(line) != null:
				violations.append(
					"L%d [func %s]: %s" % [i + 1, current_func_name, line_stripped]
				)

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"VC-6 ADR-0005 D-4 FAIL : .emit( trouvé dans une fonction lifecycle interdite "
			+ "(_process/_input/_unhandled_input/_ready/_notification). "
			+ "Tous les emits doivent être dans _physics_process ou fonctions appelées depuis lui.\n"
			+ "Violations :\n" + "\n".join(violations)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# Payloads — Aucun Dict/Array literal ni emit_signal() deprecated
# ---------------------------------------------------------------------------

## Payloads ADR-0005 D-3 : vérifie l'absence de Dict literal, Array literal
## et emit_signal() (forme dépréciée) dans movement_controller.gd.
##
## Patterns :
##   .emit({   → Dict literal en payload (alloue heap, interdit D-9)
##   .emit([   → Array literal en payload (alloue heap, interdit D-9)
##   emit_signal( → forme dépréciée GDScript 1.x (interdit, aussi alloc-unsafe)
func test_no_dict_or_array_literal_payload() -> void:
	# Arrange
	var source: String = _read_movement_source()
	assert_str(source).is_not_empty()

	var clean_source: String = _strip_comments(source)
	var lines: PackedStringArray = clean_source.split("\n")

	var patterns: Array[String] = [
		"\\.emit\\s*\\(\\s*\\{",    # Dict literal : .emit({
		"\\.emit\\s*\\(\\s*\\[",    # Array literal : .emit([
		"\\bemit_signal\\s*\\(",    # Deprecated form : emit_signal(
	]
	var pattern_labels: Array[String] = [
		"Dict literal payload .emit({",
		"Array literal payload .emit([",
		"Deprecated emit_signal()",
	]

	var regexes: Array[RegEx] = []
	for p: String in patterns:
		var rx: RegEx = RegEx.new()
		var err: int = rx.compile(p)
		assert_int(err) \
			.override_failure_message("Payload pattern '%s' doit compiler" % p) \
			.is_equal(OK)
		regexes.append(rx)

	# Act
	var violations: Array[String] = []
	for i: int in lines.size():
		var line: String = lines[i]
		if line.is_empty():
			continue
		for j: int in regexes.size():
			if regexes[j].search(line) != null:
				violations.append(
					"L%d [%s]: %s" % [i + 1, pattern_labels[j], source.split("\n")[i].strip_edges()]
				)
				break

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"Payload ADR-0005 D-3/D-9 FAIL : Dict/Array literal ou emit_signal() deprecated "
			+ "détecté dans movement_controller.gd. "
			+ "Utiliser uniquement des value types (Vector3, float) comme payload.\n"
			+ "Violations :\n" + "\n".join(violations)
		) \
		.is_empty()
