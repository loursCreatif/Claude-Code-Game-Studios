extends GdUnitTestSuite

## Story-008 / Story-005 — No-alloc hot paths static lint (parité GdUnit4 du job CI).
##
## Couvre 6 patterns BLOCKING sur les fonctions hot path de InputManager et HUDSystem :
##   AC-PF-2 — zéro allocation heap dans les fonctions hot path suivantes :
##     InputManager : _unhandled_input, _physics_process, _record_latency_sample
##     HUDSystem    : _on_credits_changed, _start_pulse_tween
##
## Patterns interdits :
##   1. push_back(          — realloc potentielle Array/PackedArray
##   2. {a = ...}           — Dictionary literal, alloc heap à chaque eval
##   3. = [a, b]            — Array literal assigné, alloc heap à chaque eval
##   4. .new()              — alloc explicite Dict/Array/Object
##   5. String(             — boxing → alloc heap
##   6. "literal" +         — concaténation String, nouvelle alloc
##
## Source : .claude/rules/no-alloc-hot-paths.md + ADR-0004 D-8 + ADR-0004 VC-3.
## Exception markers : aucun au MVP (cf. règle "Exceptions" section).


const INPUT_MANAGER_PATH: String = "res://src/core/input_manager.gd"
const HUD_SYSTEM_PATH: String = "res://src/gameplay/hud/hud_system.gd"

## Fonctions hot path par fichier (substring match sur la signature `func <name>(`).
const INPUT_HOT_FUNCS: Array[String] = [
	"_unhandled_input",
	"_physics_process",
	"_record_latency_sample",
]
const HUD_HOT_FUNCS: Array[String] = [
	"_on_credits_changed",
	"_start_pulse_tween",
]


# ────────── Helpers ──────────

func _read_text_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("Cannot open %s for lint inspection" % path) \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()
	return content


## Extrait le body des fonctions nommées dans `hot_func_names` depuis `content`.
##
## Logique : copie les lignes à partir de `func <nom>(` jusqu'au prochain
## `func ` en début de ligne (top-level). Retourne un Array de lignes (sans
## numéro de fichier) avec le numéro de ligne original pour reporting.
##
## Format retourné : Array de "NNN: <line content>" pour chaque ligne de body.
func _extract_hot_path_bodies(content: String, hot_func_names: Array[String]) -> Array[String]:
	var lines: PackedStringArray = content.split("\n")
	var result: Array[String] = []
	var inside_hot: bool = false
	for i in range(lines.size()):
		var line: String = lines[i]
		# Détection début d'une hot function (top-level : commence par "func ")
		if line.begins_with("func "):
			inside_hot = false
			for fn_name in hot_func_names:
				# Substring match : "func _unhandled_input(" ou "func _unhandled_input\t("
				if line.contains("func " + fn_name + "(") or line.contains("func " + fn_name + "\t("):
					inside_hot = true
					break
			# On ne capture pas la ligne de signature elle-même, seulement le body
			continue
		# Toute autre top-level func ferme la capture
		# (les méthodes top-level commencent par "func " sans indentation)
		if line.begins_with("func "):
			inside_hot = false
		if inside_hot:
			result.append("%d: %s" % [i + 1, line])
	return result


## Scanne `body_lines` avec `pattern` regex.
## Skip : (a) lignes commentaire pures (stripped commence par #),
##         (b) lignes contenant `exception_marker`.
## Retourne les violations sous forme "NNN: <content>".
func _scan_body_for_pattern(
		body_lines: Array[String],
		pattern: String,
		exception_marker: String,
) -> Array[String]:
	var regex := RegEx.new()
	var compiled: int = regex.compile(pattern)
	assert_int(compiled).override_failure_message("Invalid regex: %s" % pattern).is_equal(OK)
	var matches: Array[String] = []
	for entry in body_lines:
		# entry = "NNN: <content>"
		var colon_pos: int = entry.find(": ")
		var line_content: String = entry.substr(colon_pos + 2) if colon_pos >= 0 else entry
		var stripped: String = line_content.strip_edges()
		# Skip commentaires pures
		if stripped.begins_with("#"):
			continue
		# Skip exception marker
		if exception_marker != "" and line_content.contains(exception_marker):
			continue
		if regex.search(line_content) != null:
			matches.append(entry)
	return matches


## Wrapper : extrait les bodies hot path d'un fichier et scanne avec un pattern.
## Retourne les violations sous forme "path:NNN: <content>".
func _scan_file_hot_paths(
		file_path: String,
		hot_func_names: Array[String],
		pattern: String,
		exception_marker: String,
) -> Array[String]:
	var content: String = _read_text_file(file_path)
	var body_lines: Array[String] = _extract_hot_path_bodies(content, hot_func_names)
	var raw_matches: Array[String] = _scan_body_for_pattern(body_lines, pattern, exception_marker)
	# Préfixer avec le chemin fichier pour le reporting
	var result: Array[String] = []
	for m in raw_matches:
		result.append("%s:%s" % [file_path, m])
	return result


## Agrège les violations sur les deux fichiers source pour un pattern donné.
func _check_pattern(
		pattern: String,
		exception_marker: String,
) -> Array[String]:
	var violations: Array[String] = []
	violations.append_array(_scan_file_hot_paths(INPUT_MANAGER_PATH, INPUT_HOT_FUNCS, pattern, exception_marker))
	violations.append_array(_scan_file_hot_paths(HUD_SYSTEM_PATH, HUD_HOT_FUNCS, pattern, exception_marker))
	return violations


# ────────── Tests ──────────

func test_no_alloc_hot_paths_no_push_back() -> void:
	# AC-PF-2 pattern 1 — push_back( sur Array/PackedArray : realloc potentielle
	# si capacité dépassée → heap growth non borné sur 1000 Hz hot path.
	var matches: Array[String] = _check_pattern(
		"\\bpush_back\\s*\\(",
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — push_back() dans hot path (realloc potentielle) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


func test_no_alloc_hot_paths_no_dict_literal() -> void:
	# AC-PF-2 pattern 2 — Dictionary literal { a = ... } : alloc heap à chaque
	# évaluation, incompatible avec 1000 Hz _unhandled_input.
	var matches: Array[String] = _check_pattern(
		"\\{[^}]*=[^}]*\\}",
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — Dictionary literal dans hot path (alloc heap) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


func test_no_alloc_hot_paths_no_array_literal_assigned() -> void:
	# AC-PF-2 pattern 3 — Array literal assigné `= [a, b]` : alloc heap à chaque
	# évaluation. Restreint à `= [...]` pour éviter faux positifs sur annotations
	# de type Dictionary[K, V] / Array[T] (les crochets sans `=` précédent).
	var matches: Array[String] = _check_pattern(
		"=\\s*\\[[^\\]]*,[^\\]]*\\]",
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — Array literal assigné dans hot path (alloc heap) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


func test_no_alloc_hot_paths_no_new_call() -> void:
	# AC-PF-2 pattern 4 — .new() : alloc explicite (Dict.new(), Array.new(),
	# tout Object.new()). InputEvent*.new() autorisé uniquement dans simulate_*
	# (D-9) qui est hors scope hot path.
	var matches: Array[String] = _check_pattern(
		"\\.new\\s*\\(\\s*\\)",
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — .new() dans hot path (alloc explicite) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


func test_no_alloc_hot_paths_no_string_cast() -> void:
	# AC-PF-2 pattern 5 — String( cast : boxing → alloc heap.
	# str() est autorisé (GDScript built-in, pas String()), seul `String(` est
	# interdit.
	var matches: Array[String] = _check_pattern(
		"\\bString\\s*\\(",
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — String() cast dans hot path (boxing → alloc heap) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)


func test_no_alloc_hot_paths_no_string_concat() -> void:
	# AC-PF-2 pattern 6 — "literal" + concaténation : crée une nouvelle String
	# allouée à chaque évaluation.
	var matches: Array[String] = _check_pattern(
		'"[^"]*"[\\t ]*\\+',
		"lint-no-alloc-ok",
	)
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-PF-2 violation — concaténation \"literal\" + dans hot path (alloc String) :\n%s" \
			% "\n".join(matches)
		) \
		.is_equal(0)
