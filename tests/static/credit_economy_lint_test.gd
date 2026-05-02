# Tests de lint statique story-007 — Credit Economy System architectural invariants.
#
# Couvre 6 ACs (BLOCKING — Logic/Lints gate) :
#   AC-CRD-20 — try_spend body : zero await / call_deferred / Thread.start /
#               WorkerThreadPool.add_task (atomicite synchrone ADR-0001).
#   AC-CRD-41 — autoload singleton unique : deux lookups /root/CreditEconomy
#               retournent le meme get_instance_id() (NE PAS utiliser
#               Engine.has_singleton — reserve aux singletons C++ engine).
#   AC-CRD-42 — signal credits_changed : params types (total: int, delta: int,
#               source: SourceKind). Grep regex exact sur le source.
#   AC-CRD-43 — enum SourceKind : exactement 4 valeurs MVP {KILL, SECRET,
#               SPEND_SHOP, BOOT_HYDRATE}. BOSS_BONUS / ROOM_CLEAR_BONUS absents.
#   AC-CRD-44 — typage strict signatures publiques : try_spend(amount: int) -> bool
#               ET get_total() -> int. Zero Variant implicite.
#   AC-CRD-45 — credits_changed.emit( uniquement dans fonctions whitelistees.
#               JAMAIS dans _ready / _process / _input / _unhandled_input /
#               _notification.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# ADRs      : ADR-0001 (physics authority 60Hz), ADR-0007 (autoload singleton pattern).
# Source    : src/core/credit_economy.gd
# CI        : TODO — integrer job lint-credit-economy dans .github/workflows/tests.yml
#             (pattern --script, jamais --main-scene, per CLAUDE.md Godot CLI Safety).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SOURCE_PATH: String = "res://src/core/credit_economy.gd"

## Fonctions dont le body a le droit d'emettre credits_changed (AC-CRD-45).
## ADR-0001 : emission depuis _physics_process ou handlers signal uniquement.
const ALLOWED_EMIT_FUNCS: Array[String] = [
	"_physics_process",
	"try_spend",
	"_on_state_changed",
	"_on_enemy_killed",
	"_on_secret_collected",
	"_hydrate_from_save",
]

## Fonctions lifecycle dans lesquelles credits_changed.emit( est interdit.
const FORBIDDEN_EMIT_FUNCS: Array[String] = [
	"_ready",
	"_process",
	"_input",
	"_unhandled_input",
	"_notification",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Lit le source de credit_economy.gd et retourne le texte brut.
## Retourne "" si le fichier n'est pas accessible — les tests le detecteront.
static func _load_source() -> String:
	var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Remplace les lignes de pur commentaire (commencant par # apres whitespace)
## par des lignes vides. Preserve les numeros de ligne pour les messages d'erreur.
static func _strip_comments(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var result: PackedStringArray = PackedStringArray()
	result.resize(lines.size())
	for i: int in lines.size():
		if lines[i].strip_edges().begins_with("#"):
			result[i] = ""
		else:
			result[i] = lines[i]
	return "\n".join(result)


## Extrait le body de la fonction `fn_name` (du top-level func jusqu'au
## prochain top-level func ou fin de fichier). La ligne de signature est exclue.
## Retourne "" si la fonction n'est pas trouvee.
static func _extract_function_body(source: String, fn_name: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var in_target: bool = false
	var body_lines: PackedStringArray = PackedStringArray()

	var fn_pattern: RegEx = RegEx.new()
	fn_pattern.compile("^func\\s+" + fn_name + "\\s*\\(")

	var any_fn_pattern: RegEx = RegEx.new()
	any_fn_pattern.compile("^func\\s+\\w+")

	for line: String in lines:
		if not in_target:
			if fn_pattern.search(line) != null:
				in_target = true
			continue
		# in_target == true — on est dans le body
		if any_fn_pattern.search(line) != null and (not line.begins_with("\t") and not line.begins_with(" ")):
			break  # Prochain top-level func — fin du body
		body_lines.append(line)

	return "\n".join(body_lines)


# ---------------------------------------------------------------------------
# AC-CRD-20 — atomicite try_spend : zero pattern async dans le body
# ---------------------------------------------------------------------------

## GIVEN src/core/credit_economy.gd valide,
## WHEN extraction du body de try_spend + grep patterns async interdits,
## THEN 0 match hors commentaires (ADR-0001 — try_spend doit etre synchrone,
##      pas de await / call_deferred / Thread / WorkerThreadPool).
func test_credit_economy_try_spend_body_has_no_async_patterns() -> void:
	# Arrange
	var source: String = _load_source()
	assert_str(source) \
		.override_failure_message(
			"AC-CRD-20 : impossible de lire %s — verifier le path." % SOURCE_PATH
		) \
		.is_not_empty()

	var body: String = _extract_function_body(source, "try_spend")
	assert_str(body) \
		.override_failure_message(
			"AC-CRD-20 : fonction try_spend introuvable dans %s." % SOURCE_PATH
		) \
		.is_not_empty()

	var clean_body: String = _strip_comments(body)

	# Patterns async interdits (AC-CRD-20 / ADR-0001)
	var forbidden_patterns: Array[String] = [
		"\\bawait\\b",
		"\\.call_deferred\\s*\\(",
		"\\bThread\\s*\\.\\s*start\\s*\\(",
		"\\bWorkerThreadPool\\s*\\.\\s*add_task\\s*\\(",
	]
	var pattern_labels: Array[String] = [
		"await",
		".call_deferred(",
		"Thread.start(",
		"WorkerThreadPool.add_task(",
	]

	# Act + Assert
	for i: int in forbidden_patterns.size():
		var rx: RegEx = RegEx.new()
		var err: int = rx.compile(forbidden_patterns[i])
		assert_int(err) \
			.override_failure_message(
				"AC-CRD-20 : pattern '%s' doit compiler." % forbidden_patterns[i]
			) \
			.is_equal(OK)

		var matches: Array[RegExMatch] = rx.search_all(clean_body)
		assert_array(matches) \
			.override_failure_message(
				"AC-CRD-20 FAIL : pattern async '%s' trouve dans body de try_spend (ADR-0001 — synchrone requis)." % pattern_labels[i]
			) \
			.is_empty()


# ---------------------------------------------------------------------------
# AC-CRD-41 — autoload singleton unique (runtime)
# ---------------------------------------------------------------------------

## GIVEN CreditEconomy enregistre comme autoload dans project.godot,
## WHEN deux lookups Engine.get_main_loop().root.get_node("CreditEconomy"),
## THEN les deux refs sont non-null ET ont le meme get_instance_id().
## NOTE : les autoloads GDScript ne sont PAS exposes via Engine.has_singleton()
##        (reserve aux singletons C++ engine — Input, OS, Time, etc.).
func test_credit_economy_autoload_singleton_is_unique() -> void:
	# Act
	var ref_a: Node = Engine.get_main_loop().root.get_node_or_null("CreditEconomy")
	var ref_b: Node = Engine.get_main_loop().root.get_node_or_null("CreditEconomy")

	# Assert — existence
	assert_object(ref_a) \
		.override_failure_message(
			"AC-CRD-41 FAIL : CreditEconomy introuvable a /root/CreditEconomy — verifier [autoload] dans project.godot."
		) \
		.is_not_null()

	assert_object(ref_b) \
		.override_failure_message(
			"AC-CRD-41 FAIL : second lookup de CreditEconomy retourne null."
		) \
		.is_not_null()

	# Assert — unicite (meme instance). assert_object().is_not_null() ci-dessus
	# stoppe le test si un ref est null — pas besoin de garde defensive.
	var id_a: int = ref_a.get_instance_id()
	var id_b: int = ref_b.get_instance_id()
	assert_int(id_a) \
		.override_failure_message(
			"AC-CRD-41 FAIL : deux lookups retournent des instances differentes (id_a=%d, id_b=%d) — singleton unique requis." % [id_a, id_b]
		) \
		.is_equal(id_b)


# ---------------------------------------------------------------------------
# AC-CRD-42 — signal credits_changed : params types statiquement
# ---------------------------------------------------------------------------

## GIVEN src/core/credit_economy.gd,
## WHEN grep regex `signal credits_changed(total: int, delta: int, source: <type>)`,
## THEN exactement 1 match (signal declare avec tous les types explicites).
func test_credit_economy_credits_changed_signal_has_typed_params() -> void:
	# Arrange
	var source: String = _load_source()
	assert_str(source).is_not_empty()

	# Pattern : accepte tout identifier de type pour source (SourceKind)
	# mais exige total: int et delta: int.
	var rx: RegEx = RegEx.new()
	var err: int = rx.compile(
		"signal\\s+credits_changed\\s*\\(\\s*total\\s*:\\s*int\\s*,\\s*delta\\s*:\\s*int\\s*,\\s*source\\s*:\\s*\\w+"
	)
	assert_int(err) \
		.override_failure_message("AC-CRD-42 : regex signal credits_changed doit compiler.") \
		.is_equal(OK)

	# Act
	var matches: Array[RegExMatch] = rx.search_all(source)

	# Assert
	assert_array(matches) \
		.override_failure_message(
			"AC-CRD-42 FAIL : signal credits_changed(total: int, delta: int, source: <type>) introuvable ou mal type dans credit_economy.gd (AC-CRD-42)."
		) \
		.has_size(1)


# ---------------------------------------------------------------------------
# AC-CRD-43 — enum SourceKind : exactement 4 valeurs MVP
# ---------------------------------------------------------------------------

## GIVEN le script credit_economy.gd charge,
## WHEN inspection de SourceKind via acces enum statique,
## THEN size == 4 ET noms exacts {KILL, SECRET, SPEND_SHOP, BOOT_HYDRATE}
##      ET BOSS_BONUS + ROOM_CLEAR_BONUS absents (Tier 2+ locked AC-CRD-43).
func test_credit_economy_source_kind_enum_has_exactly_four_mvp_values() -> void:
	# Arrange
	var credit_script: GDScript = load(SOURCE_PATH) as GDScript
	assert_object(credit_script) \
		.override_failure_message(
			"AC-CRD-43 : impossible de charger le script %s." % SOURCE_PATH
		) \
		.is_not_null()

	# Act — acces a l'enum statique via le script
	var enum_dict: Dictionary = credit_script.SourceKind

	# Assert — taille exacte
	assert_int(enum_dict.size()) \
		.override_failure_message(
			"AC-CRD-43 FAIL : SourceKind doit avoir exactement 4 valeurs MVP. Trouvees : %s" % str(enum_dict.keys())
		) \
		.is_equal(4)

	# Assert — valeurs requises presentes
	var required_keys: Array[String] = ["KILL", "SECRET", "SPEND_SHOP", "BOOT_HYDRATE"]
	for key: String in required_keys:
		assert_bool(enum_dict.has(key)) \
			.override_failure_message(
				"AC-CRD-43 FAIL : valeur MVP '%s' absente de SourceKind. Trouvees : %s" % [key, str(enum_dict.keys())]
			) \
			.is_true()

	# Assert — valeurs Tier 2+ absentes au MVP
	var tier2_keys: Array[String] = ["BOSS_BONUS", "ROOM_CLEAR_BONUS"]
	for key: String in tier2_keys:
		assert_bool(enum_dict.has(key)) \
			.override_failure_message(
				"AC-CRD-43 FAIL : '%s' ne doit PAS etre dans SourceKind au MVP (locked Tier 2+)." % key
			) \
			.is_false()


# ---------------------------------------------------------------------------
# AC-CRD-44 — typage strict signatures publiques
# ---------------------------------------------------------------------------

## GIVEN src/core/credit_economy.gd,
## WHEN grep signatures des methodes publiques try_spend et get_total,
## THEN try_spend matche `func try_spend(amount: int) -> bool` exactement
##      ET get_total matche `func get_total() -> int` exactement.
##      Zero Variant implicite dans ces APIs publiques.
func test_credit_economy_public_api_signatures_are_strictly_typed() -> void:
	# Arrange
	var source: String = _load_source()
	assert_str(source).is_not_empty()

	# --- try_spend ---
	var try_spend_rx: RegEx = RegEx.new()
	var err_a: int = try_spend_rx.compile(
		"func\\s+try_spend\\s*\\(\\s*amount\\s*:\\s*int\\s*\\)\\s*->\\s*bool"
	)
	assert_int(err_a) \
		.override_failure_message("AC-CRD-44 : regex try_spend doit compiler.") \
		.is_equal(OK)

	assert_array(try_spend_rx.search_all(source)) \
		.override_failure_message(
			"AC-CRD-44 FAIL : try_spend(amount: int) -> bool introuvable ou mal type (Variant implicite interdit)."
		) \
		.has_size(1)

	# --- get_total ---
	var get_total_rx: RegEx = RegEx.new()
	var err_b: int = get_total_rx.compile(
		"func\\s+get_total\\s*\\(\\s*\\)\\s*->\\s*int"
	)
	assert_int(err_b) \
		.override_failure_message("AC-CRD-44 : regex get_total doit compiler.") \
		.is_equal(OK)

	assert_array(get_total_rx.search_all(source)) \
		.override_failure_message(
			"AC-CRD-44 FAIL : get_total() -> int introuvable ou mal type (Variant implicite interdit)."
		) \
		.has_size(1)


# ---------------------------------------------------------------------------
# AC-CRD-45 — credits_changed.emit( uniquement dans fonctions whitelistees
# ---------------------------------------------------------------------------

## GIVEN src/core/credit_economy.gd,
## WHEN parse ligne-par-ligne en trackant la fonction courante,
## THEN credits_changed.emit( n'apparait que dans ALLOWED_EMIT_FUNCS.
##      JAMAIS dans _ready / _process / _input / _unhandled_input / _notification.
##      Commentaires exclus.
func test_credit_economy_emit_credits_changed_only_in_allowed_functions() -> void:
	# Arrange
	var source: String = _load_source()
	assert_str(source).is_not_empty()

	var lines: PackedStringArray = source.split("\n")

	# Regex de detection d'un top-level func (non indente).
	var func_rx: RegEx = RegEx.new()
	func_rx.compile("^func\\s+(\\w+)\\s*\\(")

	# Act — mini-parser line-based
	var current_function: String = ""
	var violations: Array[String] = []

	for i: int in lines.size():
		var line: String = lines[i]
		var line_stripped: String = line.strip_edges()

		# Detection debut d'un top-level func (pas indente).
		if not line.begins_with("\t") and not line.begins_with(" "):
			var fn_match: RegExMatch = func_rx.search(line)
			if fn_match != null:
				current_function = fn_match.get_string(1)
				continue

		# Exclure les lignes de commentaire.
		if line_stripped.begins_with("#"):
			continue

		# Chercher credits_changed.emit(
		if "credits_changed.emit(" in line:
			if current_function not in ALLOWED_EMIT_FUNCS:
				violations.append("L%d [func %s]: %s" % [i + 1, current_function, line_stripped])

	# Assert
	assert_array(violations) \
		.override_failure_message(
			"AC-CRD-45 FAIL : credits_changed.emit( dans fonction non-whitelistee (ADR-0001). Violations : %s" % str(violations)
		) \
		.is_empty()


## GIVEN src/core/credit_economy.gd,
## WHEN scan des fonctions forbidden (FORBIDDEN_EMIT_FUNCS),
## THEN zero credits_changed.emit( dans ces corps de fonctions.
## Test complementaire AC-CRD-45 — verifie explicitement les fonctions interdites.
func test_credit_economy_emit_credits_changed_absent_from_forbidden_functions() -> void:
	# Arrange
	var source: String = _load_source()
	assert_str(source).is_not_empty()

	# Act + Assert — un check par fonction interdite
	for fn_name: String in FORBIDDEN_EMIT_FUNCS:
		var body: String = _extract_function_body(source, fn_name)
		# Si la fonction n'existe pas dans le fichier, le body est vide — pas de violation.
		if body.is_empty():
			continue
		var clean_body: String = _strip_comments(body)
		assert_bool("credits_changed.emit(" in clean_body) \
			.override_failure_message(
				"AC-CRD-45 FAIL : credits_changed.emit( dans func %s — interdit dans lifecycle non-physique (ADR-0001)." % fn_name
			) \
			.is_false()
