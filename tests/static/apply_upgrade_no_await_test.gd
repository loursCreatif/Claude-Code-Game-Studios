# Static lint test Story-003 — AC-UPG-12 : apply_upgrade body SYNC contract.
# Extrait le body de `func apply_upgrade(...)` jusqu'au prochain top-level `func`,
# puis grep `\bawait\b|\byield\b` excluant lignes commentaires (^\s*#).
# Zéro match non-commenté = pass.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Source    : AC-UPG-12 + R-UPG-4 SYNC contract + ADR-0001 60 Hz pull pattern.

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const UPGRADE_PATH: String = "res://src/gameplay/upgrade/upgrade_system.gd"

## Mots-clés interdits dans le body de apply_upgrade (R-UPG-4 SYNC contract).
## `await` casse SYNC contract — Movement pull à 60 Hz risque race intermediate.
## `yield` est legacy GDScript 3.x mais grep défensif (lecture humaine confuse).
const FORBIDDEN_KEYWORDS: Array[String] = [
	"await",
	"yield",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Lit le source upgrade_system.gd. Échoue le test si fichier absent / illisible.
static func _read_upgrade_source() -> String:
	var file: FileAccess = FileAccess.open(UPGRADE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Extrait le body de la fonction nommée [param func_name] du source [param src].
## Body défini comme : ligne `func <name>(` jusqu'à la prochaine ligne `func ` ou EOF.
## Retourne le body INCLUDING la ligne signature (utile pour parsing line-numbered).
static func _extract_function_body(src: String, func_name: String) -> String:
	var lines: PackedStringArray = src.split("\n")
	var start_idx: int = -1
	var end_idx: int = lines.size()
	var sig_prefix: String = "func %s(" % func_name

	for i in lines.size():
		var line: String = lines[i]
		if line.begins_with(sig_prefix):
			start_idx = i
			# Chercher la prochaine ligne `func ` au top-level (sans indent)
			for j in range(i + 1, lines.size()):
				var next_line: String = lines[j]
				if next_line.begins_with("func "):
					end_idx = j
					break
			break

	if start_idx == -1:
		return ""

	var body_lines: PackedStringArray = lines.slice(start_idx, end_idx)
	return "\n".join(body_lines)


## Strip lignes commentaires (^\s*#...) du body retenu.
## Évite faux positifs : un commentaire mentionnant `await` n'est pas une violation.
static func _strip_comment_lines(body: String) -> String:
	var lines: PackedStringArray = body.split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line in lines:
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


# ---------------------------------------------------------------------------
# AC-UPG-12 — zéro await / yield dans body apply_upgrade
# ---------------------------------------------------------------------------

## GIVEN src/gameplay/upgrade/upgrade_system.gd source brut,
## WHEN extraction body apply_upgrade + strip commentaires,
## THEN aucune occurrence de `await` ni `yield` (R-UPG-4 SYNC contract).
func test_upgrade_apply_upgrade_body_contains_no_await_or_yield() -> void:
	# Arrange
	var src: String = _read_upgrade_source()
	assert_str(src) \
		.override_failure_message("AC-UPG-12: impossible de lire %s" % UPGRADE_PATH) \
		.is_not_empty()

	# Act — extraction body
	var body: String = _extract_function_body(src, "apply_upgrade")
	assert_str(body) \
		.override_failure_message("AC-UPG-12: func apply_upgrade(...) introuvable dans %s" % UPGRADE_PATH) \
		.is_not_empty()
	var body_no_comments: String = _strip_comment_lines(body)

	# Assert — zéro keyword interdit
	for kw in FORBIDDEN_KEYWORDS:
		# Boundary word match approximatif via regex via simple contains après strip.
		# Recherche `\b<kw>\b` : on regarde occurrences entourées de non-word chars.
		var pattern: RegEx = RegEx.new()
		var compile_err: int = pattern.compile("\\b%s\\b" % kw)
		assert_int(compile_err) \
			.override_failure_message("AC-UPG-12: regex compile failed for %s" % kw) \
			.is_equal(OK)
		var matches: Array[RegExMatch] = pattern.search_all(body_no_comments)
		assert_int(matches.size()) \
			.override_failure_message("AC-UPG-12 VIOLATION: keyword '%s' trouvé dans body apply_upgrade — R-UPG-4 SYNC contract violé" % kw) \
			.is_equal(0)
