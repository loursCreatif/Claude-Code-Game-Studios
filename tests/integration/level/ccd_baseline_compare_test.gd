# Tests d'intégration story-023 — Régression CCD baseline compare (AC-LVL-44).
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# ARCHITECTURE DE TEST :
#
#   On utilise l'approche "fonction pure" : preload du script compare_ccd_baseline.gd
#   et appel direct à compare_results() (static func). Plus fiable et rapide
#   que OS.execute en CI — pas de dépendance au binaire godot ni au PATH.
#
#   4 tests couvrent les cas QA :
#   - Régression détectée (delta > tolerance → exit équivalent 1)
#   - Pass dans la tolérance (delta < tolerance → exit équivalent 0)
#   - Pass quand current < baseline (amélioration → exit équivalent 0)
#   - Erreur sur fichier baseline manquant (key absente → message "missing")
#
#   Tests nommés : test_[system]_[scenario]_[expected_result] (test-standards.md).
#   Structure : Arrange / Act / Assert.
#
# Story   : production/epics/level-system/story-023-ccd-gate-automated.md
# ADR     : docs/architecture/adr-0001-physics-rate-60hz.md (EC-8)
# Req     : TR-lvl-039 (AC-LVL-43, AC-LVL-44)

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Import du script compare (approche fonction pure)
# ---------------------------------------------------------------------------

## Script compare importé — accès à compare_results() static.
const CompareCCDScript: GDScript = preload(
	"res://tools/perf/compare_ccd_baseline.gd"
)

# ---------------------------------------------------------------------------
# Constantes (mirrored depuis compare_ccd_baseline.gd)
# ---------------------------------------------------------------------------

## Tolérance par défaut (%) — doit correspondre à TOLERANCE_PCT du script compare.
const TOLERANCE_PCT: float = 1.0

## Nombre de passes par scénario (conforme baseline JSON story-023).
const PASSES_PER_SCENARIO: int = 50


# ---------------------------------------------------------------------------
# Helpers de fixtures synthétiques
# ---------------------------------------------------------------------------

## Construit un dict baseline sweep avec une épaisseur et un clips_rate donné.
## [param thickness_key] : clé string ex. "0.3".
## [param clips_rate] : clips_rate_pct baseline (%).
## [return] : dict baseline format {"sweep": {...}}.
func _make_baseline_sweep(thickness_key: String, clips_rate: float) -> Dictionary:
	return {
		"sweep": {
			thickness_key: {"clips_rate_pct": clips_rate},
		},
		"tolerance_pct": TOLERANCE_PCT,
	}


## Construit un dict current sweep avec une épaisseur et un clips_rate donné.
## [param thickness_m] : valeur float ex. 0.3.
## [param clips_rate] : clips_rate_pct courant (%).
## [return] : dict current format {"results": [...]}.
func _make_current_sweep(thickness_m: float, clips_rate: float) -> Dictionary:
	return {
		"results": [
			{"thickness_m": thickness_m, "clips_rate_pct": clips_rate},
		],
	}


## Construit un dict baseline gameplay avec un scénario et des clips donnés.
## [param scenario_name] : nom du scénario ex. "dash_into_wall_03m".
## [param clips] : nombre de clips baseline.
## [return] : dict baseline format {"gameplay": {...}}.
func _make_baseline_gameplay(scenario_name: String, clips: int) -> Dictionary:
	var clips_rate: float = (float(clips) / float(PASSES_PER_SCENARIO)) * 100.0
	return {
		"gameplay": {
			scenario_name: {
				"clips": clips,
				"passes": PASSES_PER_SCENARIO,
				"clips_rate_pct": clips_rate,
			},
		},
		"tolerance_pct": TOLERANCE_PCT,
	}


## Construit un dict current gameplay avec un scénario et des clips donnés.
## [param scenario_name] : nom du scénario.
## [param clips] : nombre de clips courant.
## [return] : dict current format {"scenarios": [...]}.
func _make_current_gameplay(scenario_name: String, clips: int) -> Dictionary:
	var clips_rate: float = (float(clips) / float(PASSES_PER_SCENARIO)) * 100.0
	return {
		"scenarios": [
			{
				"name": scenario_name,
				"clips": clips,
				"passes": PASSES_PER_SCENARIO,
				"clips_rate_pct": clips_rate,
			},
		],
	}


# ---------------------------------------------------------------------------
# AC-LVL-44 — Test 1 : régression détectée (clips_rate dépasse baseline + tolerance)
# ---------------------------------------------------------------------------

## Vérifie que compare_results retourne pass=false quand clips_rate courant dépasse
## baseline + tolerance (régression CCD avérée).
##
## Fixture : baseline 0.3m clips_rate=0%, current 0.3m clips_rate=5%.
## Delta = 5% > tolerance 1% → FAIL attendu, message contient "regression".
func test_compare_ccd_baseline_sweep_fails_on_regression() -> void:
	# Arrange
	var baseline: Dictionary = _make_baseline_sweep("0.3", 0.0)
	var current: Dictionary = _make_current_sweep(0.3, 5.0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate fail
	assert_bool(bool(result["pass"])).is_false()

	# Assert — message contient "regression"
	var message: String = str(result["message"])
	assert_bool(message.contains("regression")).is_true()


## Vérifie que compare_results retourne pass=false pour un scénario gameplay
## où les clips passent de 0 à 5 (5/50 = 10% clips_rate >> tolerance 1%).
##
## Fixture : baseline "dash_into_wall_03m" clips=0, current clips=5.
## Delta = 10% > tolerance 1% → FAIL attendu, message contient "regression".
func test_compare_ccd_baseline_gameplay_fails_on_regression() -> void:
	# Arrange
	var scenario: String = "dash_into_wall_03m"
	var baseline: Dictionary = _make_baseline_gameplay(scenario, 0)
	var current: Dictionary = _make_current_gameplay(scenario, 5)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "gameplay", TOLERANCE_PCT
	)

	# Assert — gate fail
	assert_bool(bool(result["pass"])).is_false()

	# Assert — message contient "regression"
	var message: String = str(result["message"])
	assert_bool(message.contains("regression")).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-44 — Test 2 : pass dans la tolérance (delta < tolerance)
# ---------------------------------------------------------------------------

## Vérifie que compare_results retourne pass=true quand clips_rate courant est
## sous baseline + tolerance (pas de régression, variation admissible).
##
## Fixture : baseline 0.3m clips_rate=0%, current 0.3m clips_rate=0.5%.
## Delta = 0.5% < tolerance 1% → PASS attendu.
func test_compare_ccd_baseline_sweep_passes_within_tolerance() -> void:
	# Arrange
	var baseline: Dictionary = _make_baseline_sweep("0.3", 0.0)
	var current: Dictionary = _make_current_sweep(0.3, 0.5)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate pass
	assert_bool(bool(result["pass"])).is_true()

	# Assert — message vide (pas de régression)
	var message: String = str(result["message"])
	assert_bool(message.is_empty()).is_true()


## Vérifie que compare_results retourne pass=true pour un scénario gameplay
## avec 0 clips (baseline 0, current 0 — résultat parfait).
##
## Fixture : baseline "wallrun_into_corner_03m" clips=0, current clips=0.
## Delta = 0% ≤ tolerance 1% → PASS attendu.
func test_compare_ccd_baseline_gameplay_passes_zero_clips() -> void:
	# Arrange
	var scenario: String = "wallrun_into_corner_03m"
	var baseline: Dictionary = _make_baseline_gameplay(scenario, 0)
	var current: Dictionary = _make_current_gameplay(scenario, 0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "gameplay", TOLERANCE_PCT
	)

	# Assert — gate pass
	assert_bool(bool(result["pass"])).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-44 — Test 3 : pass quand current < baseline (amélioration)
# ---------------------------------------------------------------------------

## Vérifie que compare_results retourne pass=true quand le current est inférieur
## au baseline (amélioration de performance — aucune régression).
##
## Fixture : baseline 0.3m clips_rate=2%, current 0.3m clips_rate=0%.
## Delta = -2% < tolerance 1% → PASS attendu (amélioration).
func test_compare_ccd_baseline_sweep_passes_when_below_baseline() -> void:
	# Arrange
	var baseline: Dictionary = _make_baseline_sweep("0.3", 2.0)
	var current: Dictionary = _make_current_sweep(0.3, 0.0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate pass (amélioration = pas de régression)
	assert_bool(bool(result["pass"])).is_true()

	# Assert — message vide (pas de régression)
	var message: String = str(result["message"])
	assert_bool(message.is_empty()).is_true()


## Vérifie que compare_results retourne pass=true pour un scénario gameplay
## où baseline avait des clips mais current en a moins (amélioration).
##
## Fixture : baseline "dash_wallrun_combo_03m" clips=3 (6%), current clips=1 (2%).
## Delta = 2% - 6% = -4% < tolerance → PASS attendu.
func test_compare_ccd_baseline_gameplay_passes_when_improved() -> void:
	# Arrange
	var scenario: String = "dash_wallrun_combo_03m"
	var baseline: Dictionary = _make_baseline_gameplay(scenario, 3)
	var current: Dictionary = _make_current_gameplay(scenario, 1)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "gameplay", TOLERANCE_PCT
	)

	# Assert — gate pass (amélioration)
	assert_bool(bool(result["pass"])).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-44 — Test 4 : erreur sur section ou clé manquante
# ---------------------------------------------------------------------------

## Vérifie que compare_results retourne pass=false avec message d'erreur
## quand la clé "sweep" est absente du dict baseline (simule un fichier corrompu
## ou un baseline qui ne contient pas la section demandée).
##
## Analogue à un fichier baseline inexistant (la logique _load_json_file → ok=false
## est couverte par la vérification de clé manquante dans compare_results).
func test_compare_ccd_baseline_errors_on_missing_sweep_key() -> void:
	# Arrange — baseline sans clé "sweep" (section sweep requise)
	var baseline: Dictionary = {"gameplay": {}}
	var current: Dictionary = _make_current_sweep(0.3, 0.0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate fail (section manquante = erreur configuration)
	assert_bool(bool(result["pass"])).is_false()

	# Assert — message contient "missing" (clé absente)
	var message: String = str(result["message"])
	assert_bool(message.contains("missing")).is_true()


## Vérifie que compare_results retourne pass=false avec message d'erreur
## quand la clé "gameplay" est absente du dict baseline.
func test_compare_ccd_baseline_errors_on_missing_gameplay_key() -> void:
	# Arrange — baseline sans clé "gameplay" (section gameplay requise)
	var baseline: Dictionary = {"sweep": {}}
	var current: Dictionary = _make_current_gameplay("dash_into_wall_03m", 0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "gameplay", TOLERANCE_PCT
	)

	# Assert — gate fail
	assert_bool(bool(result["pass"])).is_false()

	# Assert — message contient "missing"
	var message: String = str(result["message"])
	assert_bool(message.contains("missing")).is_true()


## Vérifie que compare_results retourne pass=false avec message d'erreur
## quand la section fournie est invalide (ni "sweep" ni "gameplay").
func test_compare_ccd_baseline_errors_on_invalid_section() -> void:
	# Arrange — section invalide
	var baseline: Dictionary = {"sweep": {}, "gameplay": {}}
	var current: Dictionary = {}

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "invalid_section", TOLERANCE_PCT
	)

	# Assert — gate fail
	assert_bool(bool(result["pass"])).is_false()

	# Assert — message contient "invalide"
	var message: String = str(result["message"])
	assert_bool(message.contains("invalide")).is_true()


# ---------------------------------------------------------------------------
# Boundary value tests — tolérance exacte
# ---------------------------------------------------------------------------

## Vérifie que compare_results retourne pass=true quand le delta est
## exactement égal à la tolérance (boundary inclusive).
##
## Fixture : baseline 0% → current 1.0% — delta = 1.0% = tolerance 1%.
## La règle est "fail si delta > tolerance" → delta == tolerance passe.
func test_compare_ccd_baseline_sweep_passes_at_exact_tolerance_boundary() -> void:
	# Arrange — delta exact = tolerance
	var baseline: Dictionary = _make_baseline_sweep("0.5", 0.0)
	var current: Dictionary = _make_current_sweep(0.5, 1.0)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate passe (delta == tolerance, pas >)
	assert_bool(bool(result["pass"])).is_true()


## Vérifie que compare_results retourne pass=false quand le delta dépasse
## la tolérance d'un centième de % (boundary exclusive).
##
## Fixture : baseline 0% → current 1.01% — delta = 1.01% > tolerance 1%.
## Gate doit fail (delta strictement supérieur à tolerance).
func test_compare_ccd_baseline_sweep_fails_just_above_tolerance() -> void:
	# Arrange — delta légèrement au-dessus de la tolérance
	var baseline: Dictionary = _make_baseline_sweep("0.5", 0.0)
	var current: Dictionary = _make_current_sweep(0.5, 1.01)

	# Act
	var result: Dictionary = CompareCCDScript.compare_results(
		baseline, current, "sweep", TOLERANCE_PCT
	)

	# Assert — gate fail (1.01% > 1.0%)
	assert_bool(bool(result["pass"])).is_false()
