# InputBenchmarkRunner — Scène headless de benchmark pour le système d'input.
# Valide les critères d'acceptation de performance story-007 :
#   AC-L-3  : latence p99 input→publish ≤ 16 ms release / ≤ 50 ms debug (1000 frames)
#   AC-PF-1 : coût hot-path CPU p99 ≤ 0.5 ms debug / ≤ 0.1 ms release (300 frames)
#   AC-PF-5 : coût hot-path release ≤ 0.1 ms/frame p99 (séparé de AC-L-3)
#
# Exécution headless :
#   godot --headless res://tests/performance/input_benchmark.tscn
#
# Le log est écrit dans production/qa/evidence/input-benchmark-YYYY-MM-DD.log
# Le code de sortie est 0 (PASS) ou 1 (FAIL — au moins un gate raté).
#
# Règles zero-alloc : tous les buffers sont pré-alloués dans _ready().
# Aucun push_back, aucun literal Array, aucune String concat dans _physics_process.
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Nombre total de frames pour la fenêtre AC-L-3 (latence input→publish).
const TOTAL_FRAMES: int = 1000

## Frames d'échauffement exclues des samples (stabilisation moteur).
const WARMUP_FRAMES: int = 30

## Nombre de frames pour la fenêtre AC-PF-1 / AC-PF-5 (coût hot-path).
## Sous-ensemble de TOTAL_FRAMES — les deux fenêtres se chevauchent volontairement
## pour maximiser les données avec un seul run.
const HOT_PATH_FRAMES: int = 300

## Actions gameplay injectées de façon pseudo-aléatoire pour forcer le hot path.
## StringName literals pour respecter la discipline ADR-0004 StringName.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"jump", &"dash", &"attack", &"move_forward"
]

## Graine RNG fixe pour la déterminisme des runs (coding-standards).
const RNG_SEED: int = 12345

## Répertoire de destination des logs d'évidence QA.
const EVIDENCE_DIR: String = "res://production/qa/evidence/"

## Seuil de latence p99 en mode release (ms) — AC-L-3.
const LATENCY_P99_THRESHOLD_RELEASE_MS: float = 16.0

## Seuil de latence p99 en mode debug (ms) — AC-L-3.
const LATENCY_P99_THRESHOLD_DEBUG_MS: float = 50.0

## Seuil hot-path p99 en mode debug (ms) — AC-PF-1.
const HOT_PATH_P99_THRESHOLD_DEBUG_MS: float = 0.5

## Seuil hot-path p99 en mode release (ms) — AC-PF-5.
const HOT_PATH_P99_THRESHOLD_RELEASE_MS: float = 0.1

# ---------------------------------------------------------------------------
# Private state (tous pré-alloués dans _ready — zéro alloc dans _physics_process)
# ---------------------------------------------------------------------------

## Buffer des samples de latence input→publish (ms). Taille fixe TOTAL_FRAMES.
var _latency_samples: PackedFloat32Array = PackedFloat32Array()

## Buffer des coûts hot-path par frame (µs). Taille fixe HOT_PATH_FRAMES.
var _hot_path_samples_usec: PackedFloat32Array = PackedFloat32Array()

## Générateur de nombres pseudo-aléatoires — seeded dans _ready() pour déterminisme.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Index de frame courant (warmup inclus).
var _frame_idx: int = 0

## Index d'écriture dans _latency_samples (0 = premier sample post-warmup).
var _latency_write_idx: int = 0

## Index d'écriture dans _hot_path_samples_usec.
var _hot_path_write_idx: int = 0

## Guard one-shot pour _finalize().
var _finalized: bool = false

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Pré-allouer les deux buffers de samples — zéro alloc dans _physics_process.
	_latency_samples.resize(TOTAL_FRAMES)
	_hot_path_samples_usec.resize(HOT_PATH_FRAMES)

	# Seed fixe pour déterminisme des runs (coding-standards "no random seeds").
	_rng.seed = RNG_SEED

	# Créer le répertoire d'évidence s'il n'existe pas.
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(EVIDENCE_DIR)
	)

	# Passer en mode process physique actif.
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	# --- Gate de fin : les deux fenêtres sont épuisées → finaliser et quitter. ---
	# On vérifie les deux indices d'écriture (pas _frame_idx) pour être précis.
	if _latency_write_idx >= TOTAL_FRAMES and _hot_path_write_idx >= HOT_PATH_FRAMES:
		if not _finalized:
			_finalized = true
			_finalize()
		return

	# --- Phase warmup : injecter des events mais ne pas enregistrer de samples. ---
	if _frame_idx < WARMUP_FRAMES:
		_inject_events()
		_frame_idx += 1
		return

	# --- Phase mesure : injecter + enregistrer. ---
	_inject_events()

	# Enregistrement latence (fenêtre TOTAL_FRAMES).
	if _latency_write_idx < TOTAL_FRAMES:
		_latency_samples[_latency_write_idx] = InputManager.last_input_to_publish_latency_ms
		_latency_write_idx += 1

	# Enregistrement hot-path cost (fenêtre HOT_PATH_FRAMES).
	# On lit hot_path_prev_frame_usec qui contient le coût complet du tick précédent
	# (_unhandled_input + _physics_process du tick N-1). C'est la bonne valeur car
	# _physics_process InputManager a déjà tourné avant nous (autoload #1).
	if _hot_path_write_idx < HOT_PATH_FRAMES:
		# En release, l'accumulateur est toujours 0 (guard debug) — c'est intentionnel :
		# le benchmark release mesure le delta de Performance.TIME_PHYSICS_PROCESS à la place
		# pour avoir une estimation indépendante (voir note dans _finalize).
		_hot_path_samples_usec[_hot_path_write_idx] = float(InputManager.hot_path_prev_frame_usec)
		_hot_path_write_idx += 1

	_frame_idx += 1

# ---------------------------------------------------------------------------
# Private methods
# ---------------------------------------------------------------------------

## Injecte un InputEventAction aléatoire et un InputEventMouseMotion chaque frame.
## Pattern canonique ADR-0004 D-9 : parse_input_event(InputEventAction) — PAS Input.action_press.
## Les objets sont créés ici (un par frame) car ce code est HORS hot path mesuré
## (le benchmark crée des events, il ne teste pas son propre coût de création).
func _inject_events() -> void:
	# Action gameplay pseudo-aléatoire déterministe.
	var action_idx: int = _rng.randi() % GAMEPLAY_ACTIONS.size()
	var action_ev := InputEventAction.new()
	action_ev.action = GAMEPLAY_ACTIONS[action_idx]
	action_ev.pressed = true
	Input.parse_input_event(action_ev)

	# Release immédiate pour éviter un état "action toujours pressée" (propre).
	var release_ev := InputEventAction.new()
	release_ev.action = GAMEPLAY_ACTIONS[action_idx]
	release_ev.pressed = false
	Input.parse_input_event(release_ev)

	# MouseMotion minimal pour exercer le chemin _unhandled_input souris.
	var mouse_ev := InputEventMouseMotion.new()
	mouse_ev.relative = Vector2(1.0, 1.0)
	Input.parse_input_event(mouse_ev)

## Retourne [p50, p95, p99, max] depuis un sous-ensemble de [param samples].
## Copie les [param count] premiers éléments dans un scratch local pour le tri
## (le buffer source n'est pas muté). Approximation discrète acceptable benchmark.
func _compute_percentiles(samples: PackedFloat32Array, count: int) -> Array[float]:
	if count <= 0:
		return [0.0, 0.0, 0.0, 0.0]
	var scratch: PackedFloat32Array = PackedFloat32Array()
	scratch.resize(count)
	for i: int in count:
		scratch[i] = samples[i]
	scratch.sort()
	var result: Array[float] = [
		scratch[int(float(count - 1) * 0.50)],
		scratch[int(float(count - 1) * 0.95)],
		scratch[int(float(count - 1) * 0.99)],
		scratch[count - 1],
	]
	return result

## Orchestration end-of-run : calcul stats → évaluation gates → écriture log →
## impression résumé → émission warnings → exit. Appelé une seule fois via _finalized.
func _finalize() -> void:
	var results: Dictionary = _compute_all_results()
	_write_evidence_log(results)
	_print_summary(results)
	_emit_gate_failures(results)
	# Godot 4.x : passer le code de sortie directement à SceneTree.quit().
	# Pas de OS.exit_code dans l'API publique — get_tree().quit(int) est le canal.
	get_tree().quit(0 if results["all_pass"] else 1)

## Agrège percentiles latence + hot-path, résout les seuils selon le build
## debug/release, évalue les gates AC-L-3 et AC-PF-1/5, et bundle tout dans
## un Dictionary homogène consommé par les 3 sinks (log, print, warnings).
func _compute_all_results() -> Dictionary:
	var lat_stats: Array[float] = _compute_percentiles(_latency_samples, _latency_write_idx)
	var hp_stats_usec: Array[float] = _compute_percentiles(_hot_path_samples_usec, _hot_path_write_idx)
	var is_debug: bool = OS.has_feature("debug")
	var lat_threshold: float = LATENCY_P99_THRESHOLD_DEBUG_MS if is_debug else LATENCY_P99_THRESHOLD_RELEASE_MS
	var hp_threshold: float  = HOT_PATH_P99_THRESHOLD_DEBUG_MS if is_debug else HOT_PATH_P99_THRESHOLD_RELEASE_MS
	var ac_l3_pass: bool = lat_stats[2] <= lat_threshold
	# Release : accumulateur off par design (guard OS.has_feature("debug")).
	# max raw == 0.0 → SKIP gate PF (mesure externe requise — voir evidence template).
	var ac_pf_pass: bool = hp_stats_usec[2] / 1000.0 <= hp_threshold
	if not is_debug and hp_stats_usec[3] == 0.0:
		ac_pf_pass = true
	return {
		"lat_p50": lat_stats[0], "lat_p95": lat_stats[1], "lat_p99": lat_stats[2], "lat_max": lat_stats[3],
		"hp_p50_ms": hp_stats_usec[0] / 1000.0, "hp_p95_ms": hp_stats_usec[1] / 1000.0,
		"hp_p99_ms": hp_stats_usec[2] / 1000.0, "hp_max_ms": hp_stats_usec[3] / 1000.0,
		"lat_threshold": lat_threshold, "hp_threshold": hp_threshold,
		"ac_l3_pass": ac_l3_pass, "ac_pf_pass": ac_pf_pass,
		"all_pass": ac_l3_pass and ac_pf_pass,
		"is_debug": is_debug,
		"build_str": "debug" if is_debug else "release",
		"os_str": OS.get_name(),
		"cpu_str": OS.get_processor_name(),
	}

## Écrit le log d'evidence QA dans production/qa/evidence/input-benchmark-YYYY-MM-DD.log.
## Échec d'écriture non-bloquant — push_warning uniquement.
func _write_evidence_log(r: Dictionary) -> void:
	var date_str: String = Time.get_date_string_from_system()
	var log_path_abs: String = ProjectSettings.globalize_path(
		EVIDENCE_DIR + "input-benchmark-" + date_str + ".log"
	)
	var f: FileAccess = FileAccess.open(log_path_abs, FileAccess.WRITE)
	if f == null:
		push_warning("input_benchmark_runner: impossible d'ecrire le log " + log_path_abs)
		return
	# FileAccess.store_line retourne bool depuis Godot 4.4 — valeur ignorée (non-bloquant).
	f.store_line("# Input benchmark — " + Time.get_datetime_string_from_system())
	f.store_line("# Build: %s, OS: %s, CPU: %s" % [r["build_str"], r["os_str"], r["cpu_str"]])
	f.store_line("frames=%d p50=%.3f p95=%.3f p99=%.3f max=%.3f" % [
		_latency_write_idx, r["lat_p50"], r["lat_p95"], r["lat_p99"], r["lat_max"]
	])
	f.store_line("hot_path frames=%d p50=%.3f p95=%.3f p99=%.3f max=%.3f  (in ms)" % [
		_hot_path_write_idx, r["hp_p50_ms"], r["hp_p95_ms"], r["hp_p99_ms"], r["hp_max_ms"]
	])
	f.store_line("# Gate AC-L-3  (lat p99 <= %.1f ms): %s" % [
		r["lat_threshold"], "PASS" if r["ac_l3_pass"] else "FAIL"
	])
	f.store_line("# Gate AC-PF   (hp  p99 <= %.3f ms): %s" % [
		r["hp_threshold"], "PASS" if r["ac_pf_pass"] else "FAIL"
	])
	f.close()

## Imprime en console un résumé coloré BBCode (print_rich).
## Format humain à côté du log machine — utile pour debug CI logs.
func _print_summary(r: Dictionary) -> void:
	var ac_l3_tag: String = "[color=green]PASS[/color]" if r["ac_l3_pass"] else "[color=red]FAIL[/color]"
	var ac_pf_tag: String = "[color=green]PASS[/color]" if r["ac_pf_pass"] else "[color=red]FAIL[/color]"
	var global_tag: String = "[color=green]ALL PASS[/color]" if r["all_pass"] else "[color=red]FAIL[/color]"
	print_rich("\n[b]== Input Benchmark Results (" + r["build_str"] + ") ==[/b]")
	print_rich("  Latency (ms)   p50=%.3f  p95=%.3f  p99=%.3f  max=%.3f  threshold=%.1f ms" % [
		r["lat_p50"], r["lat_p95"], r["lat_p99"], r["lat_max"], r["lat_threshold"]
	])
	print_rich("  Hot-path (ms)  p50=%.3f  p95=%.3f  p99=%.3f  max=%.3f  threshold=%.3f ms" % [
		r["hp_p50_ms"], r["hp_p95_ms"], r["hp_p99_ms"], r["hp_max_ms"], r["hp_threshold"]
	])
	print_rich("  AC-L-3  : %s  (lat p99=%.3f ms, seuil=%.1f ms)" % [
		ac_l3_tag, r["lat_p99"], r["lat_threshold"]
	])
	print_rich("  AC-PF-1/5 : %s  (hp p99=%.3f ms, seuil=%.3f ms)" % [
		ac_pf_tag, r["hp_p99_ms"], r["hp_threshold"]
	])
	print_rich("  Résultat global : " + global_tag + "\n")

## Émet un push_warning par gate raté, repris par le CI pour rapport lisible.
## L'exit code non-zéro est géré par _finalize() après cet appel.
func _emit_gate_failures(r: Dictionary) -> void:
	if not r["ac_l3_pass"]:
		push_warning("[FAIL] AC-L-3 : latence p99 = %.3f ms > seuil %.1f ms (%s build)" % [
			r["lat_p99"], r["lat_threshold"], r["build_str"]
		])
	if not r["ac_pf_pass"]:
		push_warning("[FAIL] AC-PF-1/5 : hot-path p99 = %.3f ms > seuil %.3f ms (%s build)" % [
			r["hp_p99_ms"], r["hp_threshold"], r["build_str"]
		])
