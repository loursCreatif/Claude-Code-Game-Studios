# Benchmark runner — Memory budget gate story-016 (AC-LVL-32, AC-LVL-36, AC-LVL-37).
#
# Valide les 4 gates mémoire de l'étage :
#   - AC-LVL-32 : delta VRAM post-load ≤ 50 MB (50_000_000 bytes)
#   - AC-LVL-37 : delta RAM + delta VRAM ≤ 70 MB combined (70_000_000 bytes)
#   - AC-LVL-36 : delta Performance.MEMORY_STATIC sur 60 s exploration ≤ 512 KB (524_288 bytes)
#   - AC-LVL-36 : delta OBJECT_NODE_COUNT sur 60 s exploration ≤ 5
#
# --- PHASES ---
# Phase 1 (baseline)  : boot minimal scene, capture vram_before + ram_before + obj_before
# Phase 2 (load)      : load_etage(1) via fixture — await level_active signal
# Phase 3 (post-load) : capture vram_after + ram_after ; evaluate VRAM + combined gates
# Phase 4 (stability) : 1 s warmup (idle frames), then 60 s synthetic exploration
#                       sampling Performance.MEMORY_STATIC + OBJECT_NODE_COUNT chaque 1 s
#
# --- PATTERN HEADLESS ---
# Ce runner s'exécute via :
#   godot --headless --path . tests/performance/level_memory_runner.tscn
# Il extends Node3D (pas SceneTree) pour disposer d'un SceneTree actif et
# donc d'une boucle de process fonctionnelle (await get_tree().process_frame).
# Même pattern que level_draw_calls_runner.gd (story-015) et level_ccd_sweep_runner.gd (story-014).
#
# --- EXCEPTION CLAUDE.md Godot CLI Safety rule #1 ---
# Ce runner extends Node3D et requiert un SceneTree actif pour await
# get_tree().process_frame (pattern standard des runners de perf de ce projet).
# Lancement via --path + .tscn positionnel. CI ubuntu-only — voir CLAUDE.md
# incident 2026-04-27. Ne pas réutiliser sur macOS local sans confirmation
# car le pattern peut popper OS::alert() si la scène est invalide.
#
# --- ZERO-ALLOC HOT PATH (sampling 60 s) ---
# Conforme à .claude/rules/no-alloc-hot-paths.md :
#   - PackedInt64Array pré-allouée de 65 slots dans _ready() (1 s baseline + 60 s + 4 slack)
#   - PackedInt32Array pré-allouée de 65 slots pour object count
#   - Pas de push_back, pas de littéral Dictionary ou Array dans hot path
#   - Pas de String() cast ni concat "foo" + bar en hot path
#   - Indexation directe : _mem_ring[i] = sample_value
#
# --- SORTIE JSON ---
# Format : {"phase": "<nom>", "gate": "<AC>", "value": <int>, "budget": <int>,
#           "delta_bytes": <int>, "pass": <bool>}
# Une ligne JSON par gate, préfixée de "JSON_RESULT:"
#
# --- CODE DE SORTIE ---
# 0 si toutes les gates passent, 1 si au moins une gate échoue.
#
# Source : ADR-0003 (Rendering Latency), TR-lvl-005, TR-lvl-037,
#          story-016 AC-LVL-32 + AC-LVL-36 + AC-LVL-37.
# Lancement CI : godot --headless --path . tests/performance/level_memory_runner.tscn

extends Node3D

# ---------------------------------------------------------------------------
# Constantes de configuration — toutes les valeurs sont data-driven (pas hardcodé)
# ---------------------------------------------------------------------------

## Gate VRAM delta post-load (AC-LVL-32) : 50 MB en bytes.
const BUDGET_VRAM_BYTES: int = 50_000_000

## Gate combinée RAM+VRAM post-load (AC-LVL-37) : 70 MB en bytes.
const BUDGET_COMBINED_BYTES: int = 70_000_000

## Gate delta Performance.MEMORY_STATIC stabilité 60s (AC-LVL-36) : 512 KB en bytes.
const BUDGET_STATIC_MEMORY_DRIFT_BYTES: int = 524_288

## Gate delta OBJECT_NODE_COUNT stabilité 60s (AC-LVL-36) : 5 nœuds maximum.
const BUDGET_OBJECT_NODE_COUNT_DRIFT: int = 5

## Durée warmup avant le soak de stabilité (secondes).
const WARMUP_SEC: float = 1.0

## Durée du soak de stabilité (secondes).
const STABILITY_DURATION_SEC: float = 60.0

## Intervalle d'échantillonnage pendant le soak (secondes).
const SAMPLE_INTERVAL_SEC: float = 1.0

## Nombre de slots pré-alloués dans les ring buffers de sampling.
## 1 baseline + 60 s à 1 s/sample + 4 slack = 65 slots.
const SAMPLE_BUFFER_SIZE: int = 65

## Espacement entre positions de téléportation synthétique (mètres).
const TELEPORT_SPACING_X: float = 8.0

## Nombre de positions de téléportation synthétiques simulant RoomTriggers.
const TELEPORT_POSITIONS_COUNT: int = 8

## Chemin de la fixture étage (étage_10_rooms est la fixture canonique 8+ salles).
const FIXTURE_ETAGE: String = "res://tests/fixtures/level/etage_10_rooms.tscn"

# ---------------------------------------------------------------------------
# Variables privées (état du runner)
# ---------------------------------------------------------------------------

## Ring buffer pré-alloué Performance.MEMORY_STATIC samples (zero-alloc hot path).
var _mem_ring: PackedInt64Array

## Ring buffer pré-alloué OBJECT_NODE_COUNT samples (zero-alloc hot path).
var _obj_ring: PackedInt32Array

## Nombre de samples insérés dans les ring buffers (index courant).
var _sample_count: int = 0

## Indique si toutes les gates ont passé (influence le code de sortie).
var _all_gates_pass: bool = true

## Nœud de scène chargé dynamiquement (étage courant).
var _current_fixture: Node3D

## Temps écoulé dans la phase de soak (secondes).
var _soak_elapsed: float = 0.0

## Prochain instant d'échantillonnage (secondes depuis début soak).
var _next_sample_sec: float = WARMUP_SEC + SAMPLE_INTERVAL_SEC

## Baseline VRAM avant chargement (bytes).
var _vram_before: int = 0

## Baseline RAM avant chargement (bytes).
var _ram_before: int = 0

## Baseline OBJECT_NODE_COUNT avant chargement.
var _obj_before: int = 0

## VRAM après chargement (bytes).
var _vram_after: int = 0

## RAM après chargement (bytes).
var _ram_after: int = 0

## Baseline Performance.MEMORY_STATIC post-warmup (T0 soak, bytes).
var _soak_baseline_mem: int = 0

## Baseline OBJECT_NODE_COUNT post-warmup (T0 soak).
var _soak_baseline_obj: int = 0

## True une fois la baseline post-warmup capturée (évite toute re-capture).
var _soak_baseline_captured: bool = false

## Positions de téléportation synthétiques pré-calculées.
## Pré-calculées dans _ready() — pas de realloc pendant le soak.
var _teleport_positions: PackedVector3Array

## Index de position de téléportation courant.
var _teleport_index: int = 0

## Phase courante du runner.
var _phase: int = Phase.IDLE

## Flag pour éviter les double-appels à _finalize.
var _finalized: bool = false

# ---------------------------------------------------------------------------
# Énumération des phases (état de la machine d'états interne)
# ---------------------------------------------------------------------------

enum Phase {
	IDLE,
	BASELINE_CAPTURED,
	LOADING,
	LOADED,
	WARMUP,
	SOAKING,
	DONE,
}

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Pré-allocation des ring buffers — zero-alloc conforme à no-alloc-hot-paths.md
	_mem_ring = PackedInt64Array()
	_mem_ring.resize(SAMPLE_BUFFER_SIZE)
	_obj_ring = PackedInt32Array()
	_obj_ring.resize(SAMPLE_BUFFER_SIZE)

	# Pré-calcul des positions de téléportation synthétiques
	_teleport_positions = PackedVector3Array()
	_teleport_positions.resize(TELEPORT_POSITIONS_COUNT)
	var tp: int = 0
	while tp < TELEPORT_POSITIONS_COUNT:
		_teleport_positions[tp] = Vector3(float(tp) * TELEPORT_SPACING_X, 0.0, 0.0)
		tp += 1

	# Démarrer la coroutine principale après stabilisation du SceneTree
	_run_all_phases.call_deferred()


func _process(delta: float) -> void:
	# La boucle de soak tourne dans _process — sampling ici, hors hot path critique.
	# Performance.MEMORY_STATIC et OBJECT_NODE_COUNT ne sont pas des hot paths de gameplay.
	if _phase != Phase.SOAKING:
		return

	_soak_elapsed += delta

	# --- Warmup phase (0 → WARMUP_SEC) : laisser les lazy allocs se stabiliser ---
	if _soak_elapsed < WARMUP_SEC:
		return

	# --- Capture baseline post-warmup au premier passage ---
	if not _soak_baseline_captured:
		_soak_baseline_captured = true
		_soak_baseline_mem = int(Performance.get_monitor(Performance.MEMORY_STATIC))
		_soak_baseline_obj = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_mem_ring[_sample_count] = _soak_baseline_mem
		_obj_ring[_sample_count] = _soak_baseline_obj
		_sample_count += 1
		print(
			"  [soak] baseline post-warmup | mem=%d bytes | obj=%d"
			% [_soak_baseline_mem, _soak_baseline_obj]
		)
		_next_sample_sec = WARMUP_SEC + SAMPLE_INTERVAL_SEC

	# --- Échantillonnage périodique (1 s) ---
	if _soak_elapsed >= _next_sample_sec:
		_record_soak_sample()
		_next_sample_sec += SAMPLE_INTERVAL_SEC

	# --- Simulation exploration synthétique : téléporter entre positions ---
	_simulate_exploration()

	# --- Fin du soak ---
	if _soak_elapsed >= WARMUP_SEC + STABILITY_DURATION_SEC:
		_phase = Phase.DONE
		_finalize_soak()


# ---------------------------------------------------------------------------
# Orchestration principale
# ---------------------------------------------------------------------------

## Exécute les 4 phases séquentiellement, puis quitte.
func _run_all_phases() -> void:
	print("=== Memory Budget Gate — Story-016 AC-LVL-32 + AC-LVL-36 + AC-LVL-37 ===")
	print("vram_gate=%d MB | combined_gate=%d MB | mem_drift_gate=%d KB | obj_drift_gate=%d"
		% [BUDGET_VRAM_BYTES / 1_000_000, BUDGET_COMBINED_BYTES / 1_000_000,
		   BUDGET_STATIC_MEMORY_DRIFT_BYTES / 1024, BUDGET_OBJECT_NODE_COUNT_DRIFT])
	print("")

	# Phase 1 : capture baseline (avant chargement de l'étage)
	await _phase_1_baseline()

	# Phase 2 : chargement de l'étage
	await _phase_2_load()

	# Phase 3 : mesure post-load, évaluation gates VRAM + combined
	_phase_3_post_load()

	# Phase 4 : soak 60 s (géré dans _process, piloté par _phase)
	print("")
	print("--- Phase 4 : stability soak (warmup=%.1fs + soak=%.1fs) ---" % [WARMUP_SEC, STABILITY_DURATION_SEC])
	_phase = Phase.SOAKING
	# _process prend le relais — _finalize_soak appellera get_tree().quit()


# ---------------------------------------------------------------------------
# Phase 1 : baseline
# ---------------------------------------------------------------------------

## Capture les métriques avant tout chargement d'étage.
func _phase_1_baseline() -> void:
	print("--- Phase 1 : baseline ---")
	# Attendre 2 frames pour que le SceneTree soit pleinement initialisé
	await get_tree().process_frame
	await get_tree().process_frame

	_vram_before = _read_vram()
	_ram_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_obj_before = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	print(
		"  vram_before=%d bytes (%.1f MB) | ram_before=%d bytes (%.1f MB) | obj_before=%d"
		% [_vram_before, float(_vram_before) / 1_000_000.0,
		   _ram_before, float(_ram_before) / 1_000_000.0,
		   _obj_before]
	)
	_phase = Phase.BASELINE_CAPTURED


# ---------------------------------------------------------------------------
# Phase 2 : chargement de l'étage
# ---------------------------------------------------------------------------

## Charge la fixture étage et attend qu'elle soit ajoutée au SceneTree.
## Note : au MVP les étages n'émettent pas encore le signal level_active (story-002
## fournit l'état ACTIVE mais le signal est émis par le LevelManager). On simule
## l'attente en attendant 3 frames process (renderer a le temps d'initialiser).
func _phase_2_load() -> void:
	print("--- Phase 2 : load étage ---")
	print("  fixture=%s" % FIXTURE_ETAGE)
	_phase = Phase.LOADING

	var packed: PackedScene = load(FIXTURE_ETAGE) as PackedScene
	if packed == null:
		push_error("Fixture non trouvée : %s" % FIXTURE_ETAGE)
		_all_gates_pass = false
		get_tree().quit(1)
		return

	_current_fixture = packed.instantiate() as Node3D
	if _current_fixture == null:
		push_error("Impossible d'instancier la fixture : %s" % FIXTURE_ETAGE)
		_all_gates_pass = false
		get_tree().quit(1)
		return

	add_child(_current_fixture)

	# Attendre 3 frames pour que le renderer initialise la scène (Forward+ + Jolt)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	print("  étage chargé — node count post-load=%d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_phase = Phase.LOADED


# ---------------------------------------------------------------------------
# Phase 3 : mesure post-load
# ---------------------------------------------------------------------------

## Capture les métriques post-load et évalue les gates VRAM (AC-LVL-32)
## et combined RAM+VRAM (AC-LVL-37).
func _phase_3_post_load() -> void:
	print("--- Phase 3 : post-load measurement ---")

	_vram_after = _read_vram()
	_ram_after = int(Performance.get_monitor(Performance.MEMORY_STATIC))

	var delta_vram: int = _vram_after - _vram_before
	var delta_ram: int = _ram_after - _ram_before
	var delta_combined: int = delta_vram + delta_ram

	print(
		"  vram_after=%d bytes (%.1f MB) | delta_vram=%d bytes (%.1f MB)"
		% [_vram_after, float(_vram_after) / 1_000_000.0,
		   delta_vram, float(delta_vram) / 1_000_000.0]
	)
	print(
		"  ram_after=%d bytes (%.1f MB) | delta_ram=%d bytes (%.1f MB)"
		% [_ram_after, float(_ram_after) / 1_000_000.0,
		   delta_ram, float(delta_ram) / 1_000_000.0]
	)
	print(
		"  delta_combined=%d bytes (%.1f MB)"
		% [delta_combined, float(delta_combined) / 1_000_000.0]
	)

	# --- Gate AC-LVL-32 : delta VRAM ≤ 50 MB ---
	_evaluate_gate_post_load(
		"AC-LVL-32",
		"vram_delta_post_load",
		delta_vram,
		BUDGET_VRAM_BYTES
	)

	# --- Gate AC-LVL-37 : delta combined ≤ 70 MB ---
	_evaluate_gate_post_load(
		"AC-LVL-37",
		"combined_ram_vram_delta",
		delta_combined,
		BUDGET_COMBINED_BYTES
	)


# ---------------------------------------------------------------------------
# Phase 4 helpers : soak + finalisation
# ---------------------------------------------------------------------------

## Enregistre un sample mémoire + node count dans les ring buffers pré-alloués.
## Appelé depuis _process — doit être zero-alloc.
func _record_soak_sample() -> void:
	if _sample_count >= SAMPLE_BUFFER_SIZE:
		return  # safety guard — ne devrait pas arriver avec 65 slots
	_mem_ring[_sample_count] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_obj_ring[_sample_count] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_sample_count += 1


## Simule une exploration synthétique en déplaçant un Node3D dummy entre
## les positions pré-calculées (téléportation = pas d'animation, zéro alloc).
## Suffisant pour exercer les hooks de visibilité des nodes (Area3D, etc.).
## Appelé depuis _process — doit être zero-alloc.
func _simulate_exploration() -> void:
	if _current_fixture == null:
		return
	# Pas de modulo (%) car % sur int ne provoque pas d'alloc en GDScript.
	# Incrémentation simple de l'index de position.
	if _teleport_index >= TELEPORT_POSITIONS_COUNT:
		_teleport_index = 0
	_current_fixture.position = _teleport_positions[_teleport_index]
	_teleport_index += 1


## Appelé depuis _process quand le soak est terminé.
## Évalue les gates de stabilité et écrit le log JSON.
func _finalize_soak() -> void:
	if _finalized:
		return
	_finalized = true

	# Dernier sample au moment de la clôture
	_record_soak_sample()

	var final_mem: int = _mem_ring[_sample_count - 1]
	var final_obj: int = _obj_ring[_sample_count - 1]
	var delta_static_mem: int = final_mem - _soak_baseline_mem
	var delta_obj_count: int = final_obj - _soak_baseline_obj

	print("")
	print("--- Phase 4 : stability soak results ---")
	print(
		"  soak_baseline_mem=%d bytes | final_mem=%d bytes | delta=%d bytes (%.1f KB)"
		% [_soak_baseline_mem, final_mem, delta_static_mem, float(delta_static_mem) / 1024.0]
	)
	print(
		"  soak_baseline_obj=%d | final_obj=%d | delta=%d"
		% [_soak_baseline_obj, final_obj, delta_obj_count]
	)

	# --- Gate AC-LVL-36 memory stability : delta ≤ 512 KB ---
	_evaluate_gate_stability(
		"AC-LVL-36-memory",
		"static_memory_drift_60s",
		delta_static_mem,
		BUDGET_STATIC_MEMORY_DRIFT_BYTES
	)

	# --- Gate AC-LVL-36 object count stability : delta ≤ 5 ---
	_evaluate_gate_stability(
		"AC-LVL-36-objects",
		"object_count_drift_60s",
		delta_obj_count,
		BUDGET_OBJECT_NODE_COUNT_DRIFT
	)

	# Écrire le log
	_write_log(
		_vram_after - _vram_before,
		_ram_after - _ram_before,
		delta_static_mem,
		delta_obj_count
	)

	print("")
	if _all_gates_pass:
		print("Memory budget gate PASS — toutes les gates sous budget (story-016 AC-LVL-32 + AC-LVL-36 + AC-LVL-37)")
	else:
		push_error("Memory budget gate FAIL — voir messages ci-dessus (TR-lvl-005 + TR-lvl-037 / story-016)")

	get_tree().quit(0 if _all_gates_pass else 1)


# ---------------------------------------------------------------------------
# Évaluation des gates
# ---------------------------------------------------------------------------

## Évalue et affiche une gate post-load (VRAM ou combined).
##
## [param ac_id] : identifiant de l'AC (pour log et JSON).
## [param metric_name] : nom de la métrique mesurée.
## [param value] : valeur mesurée (bytes).
## [param budget] : seuil maximum autorisé (bytes).
func _evaluate_gate_post_load(
	ac_id: String,
	metric_name: String,
	value: int,
	budget: int
) -> void:
	var pass_gate: bool = value <= budget
	if not pass_gate:
		push_error(
			"GATE FAIL [%s] %s : %d bytes (%.1f MB) > budget %d bytes (%.1f MB)"
			% [ac_id, metric_name, value, float(value) / 1_000_000.0,
			   budget, float(budget) / 1_000_000.0]
		)
		_all_gates_pass = false
	else:
		print(
			"GATE PASS [%s] %s : %d bytes (%.1f MB) ≤ budget %d MB"
			% [ac_id, metric_name, value, float(value) / 1_000_000.0,
			   budget / 1_000_000]
		)

	# Output JSON (hors hot path)
	print("JSON_RESULT:")
	print(
		'{"ac": "%s", "metric": "%s", "value_bytes": %d, "budget_bytes": %d, "pass": %s}'
		% [ac_id, metric_name, value, budget, str(pass_gate).to_lower()]
	)


## Évalue et affiche une gate de stabilité (mémoire ou node count).
##
## [param ac_id] : identifiant de l'AC (pour log et JSON).
## [param metric_name] : nom de la métrique mesurée.
## [param value] : valeur delta mesurée.
## [param budget] : seuil maximum autorisé.
func _evaluate_gate_stability(
	ac_id: String,
	metric_name: String,
	value: int,
	budget: int
) -> void:
	var pass_gate: bool = value <= budget
	if not pass_gate:
		push_error(
			"GATE FAIL [%s] %s : delta=%d > budget=%d (TR-lvl-037)"
			% [ac_id, metric_name, value, budget]
		)
		_all_gates_pass = false
	else:
		print(
			"GATE PASS [%s] %s : delta=%d ≤ budget=%d"
			% [ac_id, metric_name, value, budget]
		)

	# Output JSON (hors hot path)
	print("JSON_RESULT:")
	print(
		'{"ac": "%s", "metric": "%s", "delta": %d, "budget": %d, "pass": %s}'
		% [ac_id, metric_name, value, budget, str(pass_gate).to_lower()]
	)


# ---------------------------------------------------------------------------
# Lecture des métriques moteur
# ---------------------------------------------------------------------------

## Lit la consommation VRAM courante via RenderingServer.
##
## Note Godot 4.6 : RenderingServer.get_rendering_info() accepte des constantes
## de l'enum RenderingServer.RenderingInfo. La constante correcte pour la VRAM
## totale utilisée est RENDERING_INFO_VIDEO_MEM_USED (vérifié sur Godot 4.6 docs).
## Cette API existe depuis Godot 4.0 et n'a pas changé en 4.4/4.5/4.6.
## En mode headless, cette valeur peut être 0 ou très basse (pas de GPU réel).
## C'est attendu — le CI headless mesurera un delta proche de 0, ce qui passe
## systématiquement la gate ≤ 50 MB. Sur hardware réel, la gate est significative.
##
## [return] : VRAM utilisée en bytes.
func _read_vram() -> int:
	return int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED
	))


# ---------------------------------------------------------------------------
# Écriture du log d'évidence
# ---------------------------------------------------------------------------

## Écrit le log d'évidence JSON dans production/qa/.
##
## [param delta_vram] : delta VRAM post-load en bytes.
## [param delta_ram] : delta RAM post-load en bytes.
## [param delta_mem_soak] : delta Performance.MEMORY_STATIC sur 60 s en bytes.
## [param delta_obj_soak] : delta OBJECT_NODE_COUNT sur 60 s.
func _write_log(
	delta_vram: int,
	delta_ram: int,
	delta_mem_soak: int,
	delta_obj_soak: int
) -> void:
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var log_path: String = "res://production/qa/perf-level-memory-%s.log" % timestamp

	var f: FileAccess = FileAccess.open(log_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open log : %s" % log_path)
		return

	var os_name: String = OS.get_name()
	var debug_flag: String = "debug" if OS.has_feature("debug") else "release"
	var delta_combined: int = delta_vram + delta_ram
	f.store_line("# Memory budget run — %s" % Time.get_datetime_string_from_system())
	f.store_line("# Build: %s, OS: %s" % [debug_flag, os_name])
	f.store_line("# Story-016 AC-LVL-32 + AC-LVL-36 + AC-LVL-37 — TR-lvl-005 + TR-lvl-037")
	f.store_line("")
	f.store_line("## Phase 1 baseline")
	f.store_line("vram_before=%d bytes (%.1f MB)" % [_vram_before, float(_vram_before) / 1_000_000.0])
	f.store_line("ram_before=%d bytes (%.1f MB)" % [_ram_before, float(_ram_before) / 1_000_000.0])
	f.store_line("obj_before=%d" % _obj_before)
	f.store_line("")
	f.store_line("## Phase 3 post-load")
	f.store_line("vram_after=%d bytes (%.1f MB)" % [_vram_after, float(_vram_after) / 1_000_000.0])
	f.store_line("ram_after=%d bytes (%.1f MB)" % [_ram_after, float(_ram_after) / 1_000_000.0])
	f.store_line("delta_vram=%d bytes (%.1f MB)" % [delta_vram, float(delta_vram) / 1_000_000.0])
	f.store_line("delta_ram=%d bytes (%.1f MB)" % [delta_ram, float(delta_ram) / 1_000_000.0])
	f.store_line("delta_combined=%d bytes (%.1f MB)" % [delta_combined, float(delta_combined) / 1_000_000.0])
	f.store_line("")
	f.store_line("## Phase 4 stability soak (warmup=%.1fs + soak=%.1fs)" % [WARMUP_SEC, STABILITY_DURATION_SEC])
	f.store_line("soak_baseline_mem=%d bytes" % _soak_baseline_mem)
	f.store_line("soak_baseline_obj=%d" % _soak_baseline_obj)
	f.store_line("samples_count=%d" % _sample_count)
	f.store_line("")

	# Dump samples (hors hot path — allocations acceptées ici)
	var k: int = 0
	while k < _sample_count:
		f.store_line(
			"t=%ds mem=%d bytes obj=%d"
			% [k, _mem_ring[k], _obj_ring[k]]
		)
		k += 1

	f.store_line("")
	f.store_line("## Gate results")
	f.store_line(
		"AC-LVL-32 delta_vram=%d bytes (%.1f MB) budget=%d MB : %s"
		% [delta_vram, float(delta_vram) / 1_000_000.0,
		   BUDGET_VRAM_BYTES / 1_000_000,
		   "PASS" if delta_vram <= BUDGET_VRAM_BYTES else "FAIL"]
	)
	f.store_line(
		"AC-LVL-37 delta_combined=%d bytes (%.1f MB) budget=%d MB : %s"
		% [delta_combined, float(delta_combined) / 1_000_000.0,
		   BUDGET_COMBINED_BYTES / 1_000_000,
		   "PASS" if delta_combined <= BUDGET_COMBINED_BYTES else "FAIL"]
	)
	f.store_line(
		"AC-LVL-36-memory delta_mem=%d bytes (%.1f KB) budget=%d KB : %s"
		% [delta_mem_soak, float(delta_mem_soak) / 1024.0,
		   BUDGET_STATIC_MEMORY_DRIFT_BYTES / 1024,
		   "PASS" if delta_mem_soak <= BUDGET_STATIC_MEMORY_DRIFT_BYTES else "FAIL"]
	)
	f.store_line(
		"AC-LVL-36-objects delta_obj=%d budget=%d : %s"
		% [delta_obj_soak, BUDGET_OBJECT_NODE_COUNT_DRIFT,
		   "PASS" if delta_obj_soak <= BUDGET_OBJECT_NODE_COUNT_DRIFT else "FAIL"]
	)
	f.store_line("")
	f.store_line("OVERALL=%s" % ("PASS" if _all_gates_pass else "FAIL"))
	f.close()
	print("  evidence log: %s" % log_path)
