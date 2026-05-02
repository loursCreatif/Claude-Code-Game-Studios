# CLI — Compare CCD benchmark results against a locked baseline (story-023 AC-LVL-44).
#
# Usage :
#   godot --headless --script tools/perf/compare_ccd_baseline.gd \
#         -- <baseline_path> <current_json_path> <section>
#
# <section> : "sweep" ou "gameplay"
#
# Exit codes :
#   0 — tous les checks passent (no regression)
#   1 — regression détectée (clips_rate_pct delta > tolerance)
#   2 — erreur (file not found, parse error, args manquants)
#
# L'approche fonction pure (compare_results) permet aux tests GdUnit4 d'importer
# ce script et d'appeler la logique directement sans OS.execute (plus fiable en CI).
# Le _init() CI parse les args et appelle compare_results.
#
# Source : ADR-0001 EC-8, TR-lvl-039, story-023 AC-LVL-44.
# Pattern : conforme tools/lint/run_level_lint.gd (extends SceneTree, _init → quit).

extends SceneTree

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

## Tolérance en % de clips_rate pour la régression sweep (section "sweep").
## Une régression est détectée si current > baseline + TOLERANCE_PCT.
const TOLERANCE_PCT: float = 1.0

# ---------------------------------------------------------------------------
# Entry point CLI
# ---------------------------------------------------------------------------

func _init() -> void:
	var exit_code: int = _run_compare()
	quit(exit_code)


## Parse les arguments CLI et exécute la comparaison.
## [return] : exit code (0 = pass, 1 = regression, 2 = erreur).
func _run_compare() -> int:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if user_args.size() < 3:
		push_error(
			"compare_ccd_baseline: arguments manquants. "
			+ "Usage : -- <baseline_path> <current_json_path> <section>"
		)
		return 2

	var baseline_path: String = user_args[0]
	var current_path: String = user_args[1]
	var section: String = user_args[2]

	if section != "sweep" and section != "gameplay":
		push_error(
			"compare_ccd_baseline: section invalide '%s' — doit être 'sweep' ou 'gameplay'" % section
		)
		return 2

	# Charger le fichier baseline.
	var baseline_result: Dictionary = _load_json_file(baseline_path)
	if not bool(baseline_result["ok"]):
		push_error("compare_ccd_baseline: baseline not found or parse error — %s" % baseline_path)
		return 2

	# Charger le fichier current.
	var current_result: Dictionary = _load_json_file(current_path)
	if not bool(current_result["ok"]):
		push_error("compare_ccd_baseline: current not found or parse error — %s" % current_path)
		return 2

	var baseline_data: Dictionary = baseline_result["data"]
	var current_data: Dictionary = current_result["data"]

	# Tolérance optionnellement surchargeable depuis le fichier baseline.
	var tolerance: float = TOLERANCE_PCT
	if baseline_data.has("tolerance_pct"):
		tolerance = float(baseline_data["tolerance_pct"])

	# Déléguer à la fonction pure testable.
	var compare_out: Dictionary = compare_results(baseline_data, current_data, section, tolerance)

	# Afficher le rapport.
	for line: String in compare_out["log"]:
		print(line)

	if not bool(compare_out["pass"]):
		push_error(str(compare_out["message"]))
		return 1

	print("compare_ccd_baseline PASS — section=%s, tolerance=%.1f%%" % [section, tolerance])
	return 0


# ---------------------------------------------------------------------------
# Fonction pure testable (importable par GdUnit4)
# ---------------------------------------------------------------------------

## Compare les résultats CCD entre un baseline et un run courant.
##
## Pour section "sweep" :
##   Itère les clés du baseline.sweep (épaisseurs "0.2", "0.3", "0.5").
##   Fail si current.results[i].clips_rate_pct > baseline.sweep[t].clips_rate_pct + tolerance.
##
## Pour section "gameplay" :
##   Itère les clés du baseline.gameplay (4 noms de scénarios).
##   Fail si current.scenarios[i].clips > 0 ET clips_rate_pct delta > tolerance
##   (zéro tolérance sur les clips absolus si baseline = 0).
##
## [param baseline] : dict parsé depuis level-ccd-baseline.json.
## [param current] : dict parsé depuis le fichier de sortie JSON du runner.
## [param section] : "sweep" ou "gameplay".
## [param tolerance] : tolérance en % de clips_rate (ex. 1.0 = 1%).
## [return] : Dictionary {pass: bool, message: String, log: Array[String]}.
static func compare_results(
	baseline: Dictionary,
	current: Dictionary,
	section: String,
	tolerance: float
) -> Dictionary:
	var log_lines: Array[String] = []
	var failed: bool = false
	var failure_messages: Array[String] = []

	if section == "sweep":
		# Baseline format : {"sweep": {"0.3": {"clips_rate_pct": 0.0}, ...}}
		# Current format  : {"results": [{"thickness_m": 0.3, "clips_rate_pct": 0.0}, ...]}
		if not baseline.has("sweep"):
			return {
				"pass": false,
				"message": "baseline missing 'sweep' key",
				"log": log_lines,
			}
		if not current.has("results"):
			return {
				"pass": false,
				"message": "current missing 'results' key",
				"log": log_lines,
			}

		var baseline_sweep: Dictionary = baseline["sweep"]
		var current_results: Array = current["results"]

		for thickness_key: String in baseline_sweep.keys():
			var baseline_entry: Dictionary = baseline_sweep[thickness_key]
			var baseline_rate: float = float(baseline_entry.get("clips_rate_pct", 0.0))

			# Trouver la config correspondante dans current.results.
			var thickness_val: float = float(thickness_key)
			var current_rate: float = -1.0
			for entry: Dictionary in current_results:
				if is_equal_approx(float(entry.get("thickness_m", -999.0)), thickness_val):
					current_rate = float(entry.get("clips_rate_pct", 0.0))
					break

			if current_rate < 0.0:
				log_lines.append("  WARN  thickness=%s — not found in current results (skip)" % thickness_key)
				continue

			var delta: float = current_rate - baseline_rate
			var status: String = "OK"
			if delta > tolerance:
				status = "REGRESSION"
				failed = true
				failure_messages.append(
					"regression: thickness=%s clips_rate %.2f%% > baseline %.2f%% + tolerance %.1f%%"
					% [thickness_key, current_rate, baseline_rate, tolerance]
				)

			log_lines.append(
				"  %s  sweep[%sm] baseline=%.2f%% current=%.2f%% delta=%+.2f%%"
				% [status, thickness_key, baseline_rate, current_rate, delta]
			)

	elif section == "gameplay":
		# Baseline format : {"gameplay": {"dash_into_wall_03m": {"clips": 0, "passes": 50, ...}, ...}}
		# Current format  : {"scenarios": [{"name": "...", "clips": 0, "passes": 50, ...}, ...]}
		if not baseline.has("gameplay"):
			return {
				"pass": false,
				"message": "baseline missing 'gameplay' key",
				"log": log_lines,
			}
		if not current.has("scenarios"):
			return {
				"pass": false,
				"message": "current missing 'scenarios' key",
				"log": log_lines,
			}

		var baseline_gameplay: Dictionary = baseline["gameplay"]
		var current_scenarios: Array = current["scenarios"]

		for scenario_name: String in baseline_gameplay.keys():
			var baseline_entry: Dictionary = baseline_gameplay[scenario_name]
			var baseline_clips: int = int(baseline_entry.get("clips", 0))
			var baseline_passes: int = int(baseline_entry.get("passes", 50))
			var baseline_rate: float = float(baseline_entry.get(
				"clips_rate_pct",
				(float(baseline_clips) / float(baseline_passes)) * 100.0
			))

			# Trouver le scénario correspondant dans current.scenarios.
			var current_clips: int = -1
			var current_passes: int = 50
			var current_rate: float = -1.0
			for entry: Dictionary in current_scenarios:
				if str(entry.get("name", "")) == scenario_name:
					current_clips = int(entry.get("clips", 0))
					current_passes = int(entry.get("passes", 50))
					current_rate = float(entry.get(
						"clips_rate_pct",
						(float(current_clips) / float(current_passes)) * 100.0
					))
					break

			if current_clips < 0:
				log_lines.append("  WARN  %s — not found in current scenarios (skip)" % scenario_name)
				continue

			var delta: float = current_rate - baseline_rate
			var status: String = "OK"

			# Régression si delta > tolerance.
			# Cas spécial : si baseline = 0 clips et current > 0, c'est forcément une régression
			# (delta = clips_rate_pct > 0 > tolerance 0 → toujours fail si baseline=0 et current>0).
			if delta > tolerance:
				status = "REGRESSION"
				failed = true
				failure_messages.append(
					"regression: %s clips_rate %.2f%% > baseline %.2f%% + tolerance %.1f%%"
					% [scenario_name, current_rate, baseline_rate, tolerance]
				)

			log_lines.append(
				"  %s  gameplay[%s] baseline=%d clips (%.2f%%) current=%d clips (%.2f%%) delta=%+.2f%%"
				% [
					status, scenario_name,
					baseline_clips, baseline_rate,
					current_clips, current_rate,
					delta,
				]
			)

	else:
		return {
			"pass": false,
			"message": "section invalide: '%s'" % section,
			"log": log_lines,
		}

	var summary_message: String = ""
	if failed:
		summary_message = "; ".join(failure_messages)

	return {
		"pass": not failed,
		"message": summary_message,
		"log": log_lines,
	}


# ---------------------------------------------------------------------------
# Helper I/O
# ---------------------------------------------------------------------------

## Charge et parse un fichier JSON depuis le chemin donné.
## [param path] : chemin absolu ou res:// / user://.
## [return] : Dictionary {ok: bool, data: Dictionary}.
static func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}}

	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "data": {}}

	return {"ok": true, "data": parsed as Dictionary}
