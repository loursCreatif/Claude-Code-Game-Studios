# Benchmark runner — Draw call budget gate story-015 (AC-LVL-31 + AC-LVL-31b).
#
# Valide que la scène niveau (étage N salles) ne dépasse pas le budget draw calls
# p99 sur 500 frames :
#   - N=10 salles (baseline) : p99 ≤ 350 (AC-LVL-31)
#   - N=8  salles (baseline) : p99 ≤ 290 (AC-LVL-31)
#   - N=10 + 3 peers + VFX   : delta p99 ≤ 170 ET global ≤ 500 (AC-LVL-31b)
#
# --- PATTERN HEADLESS ---
# Ce runner s'exécute via :
#   godot --headless --path . tests/performance/level_draw_calls_runner.tscn
# Il extends Node3D (pas SceneTree) pour disposer d'un SceneTree actif et
# donc d'une boucle de rendu fonctionnelle (await get_tree().process_frame).
# Même pattern que level_ccd_sweep_runner.gd (story-014).
#
# --- ZERO-ALLOC HOT PATH ---
# Conforme à .claude/rules/no-alloc-hot-paths.md :
#   - PackedInt32Array pré-alloué de 500 entrées dans _ready()
#   - Pas de push_back, pas de littéral Dictionary ou Array dans hot path
#   - Pas de String() cast ni de concat "foo" + bar en hot path
#   - Indexation directe : _dc_ring[i] = sample_value
#
# --- SORTIE JSON ---
# Format : {"config": "<nom>", "p99": <int>, "min": <int>, "max": <int>,
#           "mean": <float>, "frames_sampled": 500}
# Une ligne JSON par configuration, préfixée de "JSON_RESULT:"
#
# --- CODE DE SORTIE ---
# 0 si toutes les gates passent, 1 si au moins une gate échoue.
#
# Source : ADR-0003 (Rendering Latency), TR-lvl-003, TR-lvl-004,
#          story-015 AC-LVL-31 + AC-LVL-31b.
# Lancement CI : godot --headless --path . tests/performance/level_draw_calls_runner.tscn

extends Node3D

# ---------------------------------------------------------------------------
# Constantes de configuration
# ---------------------------------------------------------------------------

## Nombre de frames à échantillonner par configuration.
const FRAMES_SAMPLED: int = 500

## Index p99 dans un tableau de 500 valeurs trié : 499 * 0.99 = 494.01 → 494.
const P99_INDEX: int = 494

## Budget draw calls p99 pour N=10 salles (gate AC-LVL-31).
const BUDGET_10_ROOMS: int = 350

## Budget draw calls p99 pour N=8 salles (formule F2 : 290 + 60 = 350 at N=10).
const BUDGET_8_ROOMS: int = 290

## Budget delta peers p99 : p99_with_peers - p99_baseline ≤ 170 (AC-LVL-31b).
const BUDGET_PEERS_DELTA: int = 170

## Budget global absolu : p99_with_peers ≤ 500 (technical-preferences.md).
const BUDGET_GLOBAL_HARD_CAP: int = 500

## Espacement X entre les rooms peers dummy (mètres).
const PEER_SPACING_X: float = 5.0

## Chemin de la fixture étage 10 salles.
const FIXTURE_10_ROOMS: String = "res://tests/fixtures/level/etage_10_rooms.tscn"

## Chemin de la fixture étage 8 salles.
const FIXTURE_8_ROOMS: String = "res://tests/fixtures/level/etage_8_rooms.tscn"

# ---------------------------------------------------------------------------
# Variables privées
# ---------------------------------------------------------------------------

## Ring buffer pré-alloué 500 entrées (zero-alloc hot path).
## Pré-alloué dans _ready(), réutilisé pour chaque configuration.
var _dc_ring: PackedInt32Array

## Indique si toutes les gates ont passé.
var _all_gates_pass: bool = true

## Nœud de scène chargé dynamiquement (étage courant).
var _current_fixture: Node3D

## Nœuds peers dummy (config AC-LVL-31b).
var _peer_nodes: Array[Node3D] = []

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Pré-allocation du ring buffer : zero-alloc conforme à no-alloc-hot-paths.md
	_dc_ring = PackedInt32Array()
	_dc_ring.resize(FRAMES_SAMPLED)

	# Lancer la coroutine après le premier process frame pour que le SceneTree
	# soit entièrement actif avant de charger les fixtures.
	_run_all_configs.call_deferred()


# ---------------------------------------------------------------------------
# Orchestration principale
# ---------------------------------------------------------------------------

## Exécute les 3 configurations séquentiellement, puis quitte.
func _run_all_configs() -> void:
	print("=== Draw Call Budget Gate — Story-015 AC-LVL-31 + AC-LVL-31b ===")
	print("frames_per_config=%d, p99_index=%d" % [FRAMES_SAMPLED, P99_INDEX])
	print("")

	# Configuration (a) : étage 10 salles baseline (gate 350)
	var p99_10: int = await _run_config(
		FIXTURE_10_ROOMS,
		"10_rooms_baseline",
		false
	)
	_evaluate_gate(
		"10_rooms_baseline",
		p99_10,
		BUDGET_10_ROOMS,
		-1,
		-1
	)

	# Configuration (b) : étage 8 salles baseline (gate 290)
	var p99_8: int = await _run_config(
		FIXTURE_8_ROOMS,
		"8_rooms_baseline",
		false
	)
	_evaluate_gate(
		"8_rooms_baseline",
		p99_8,
		BUDGET_8_ROOMS,
		-1,
		-1
	)

	# Configuration (c) : étage 10 salles + 3 peers + VFX (gate delta ≤ 170, global ≤ 500)
	var p99_peers: int = await _run_config(
		FIXTURE_10_ROOMS,
		"10_rooms_peers_vfx",
		true
	)
	_evaluate_gate(
		"10_rooms_peers_vfx",
		p99_peers,
		BUDGET_GLOBAL_HARD_CAP,
		p99_10,
		BUDGET_PEERS_DELTA
	)

	print("")
	if _all_gates_pass:
		print("Draw call budget gate PASS — toutes les configs sous budget (AC-LVL-31 + AC-LVL-31b)")
	else:
		push_error("Draw call budget gate FAIL — voir messages ci-dessus (TR-lvl-004 / story-015)")

	get_tree().quit(0 if _all_gates_pass else 1)


# ---------------------------------------------------------------------------
# Échantillonnage d'une configuration
# ---------------------------------------------------------------------------

## Charge la fixture, optionnellement spawne les peers dummy, échantillonne
## FRAMES_SAMPLED frames de draw calls via Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
## décharge la fixture, et retourne la valeur p99.
##
## [param fixture_path] : chemin res:// de la scène fixture à charger.
## [param config_name] : identifiant lisible pour le log JSON.
## [param with_peers] : si true, spawne 3 MeshInstance3D dummy + VFX flags actifs.
## [return] : valeur p99 du nombre de draw calls sur FRAMES_SAMPLED frames.
func _run_config(
	fixture_path: String,
	config_name: String,
	with_peers: bool
) -> int:
	print("--- Config : %s ---" % config_name)

	# Charger et instancier la fixture
	var packed: PackedScene = load(fixture_path) as PackedScene
	if packed == null:
		push_error("Fixture non trouvée : %s" % fixture_path)
		_all_gates_pass = false
		return 0

	_current_fixture = packed.instantiate() as Node3D
	if _current_fixture == null:
		push_error("Impossible d'instancier la fixture : %s" % fixture_path)
		_all_gates_pass = false
		return 0

	add_child(_current_fixture)

	# Spawner les peers si demandé (AC-LVL-31b)
	if with_peers:
		_spawn_peers()

	# Attendre 2 frames pour laisser le renderer initialiser la scène
	await get_tree().process_frame
	await get_tree().process_frame

	# --- HOT PATH : zero-alloc 500 frames ---
	# Aucun push_back, aucun littéral Array/Dict, aucun String() cast.
	# Indexation directe sur PackedInt32Array pré-alloué.
	var i: int = 0
	while i < FRAMES_SAMPLED:
		await get_tree().process_frame
		# Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME : draw calls du frame courant.
		# get_monitor() retourne float — cast int pour PackedInt32Array.
		_dc_ring[i] = int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		))
		i += 1
	# --- FIN HOT PATH ---

	# Calculer les statistiques (hors hot path — allocations acceptées)
	var p99: int = _compute_p99()
	var stats_min: int = _compute_min()
	var stats_max: int = _compute_max()
	var stats_mean: float = _compute_mean()

	# Afficher JSON (hors hot path)
	var json_line: String = (
		'{"config": "%s", "p99": %d, "min": %d, "max": %d, "mean": %.1f, "frames_sampled": %d}'
	) % [config_name, p99, stats_min, stats_max, stats_mean, FRAMES_SAMPLED]
	print("JSON_RESULT:")
	print(json_line)

	# Décharger la fixture et les peers
	_despawn_peers()
	_current_fixture.queue_free()
	_current_fixture = null

	# Attendre que queue_free() soit traité avant la prochaine config
	await get_tree().process_frame

	return p99


# ---------------------------------------------------------------------------
# Peers dummy (AC-LVL-31b)
# ---------------------------------------------------------------------------

## Spawne 3 MeshInstance3D dummy simulant des ennemis et 2 MeshInstance3D
## simulant des VFX actifs (katana swing + dash).
## Ces nœuds n'ont pas de mesh assigné (stubs) mais comptent comme draw calls
## une fois que les meshes seront assignés en Sprint 1+.
##
## NOTE : les flags "katana_swing_vfx" et "dash_vfx" sont simulés par la
## présence de MeshInstance3D supplémentaires. Les systèmes VFX réels n'existant
## pas encore au MVP, les peers sont des placeholders conformes au spec story-015.
func _spawn_peers() -> void:
	# 3 ennemis dummy (MeshInstance3D stub)
	var j: int = 0
	while j < 3:
		var enemy: MeshInstance3D = MeshInstance3D.new()
		enemy.name = "DummyEnemy_%d" % j
		enemy.position = Vector3(float(j) * PEER_SPACING_X, 0.0, 0.0)
		add_child(enemy)
		_peer_nodes.append(enemy)
		j += 1

	# Katana swing VFX placeholder
	var katana_vfx: MeshInstance3D = MeshInstance3D.new()
	katana_vfx.name = "KatanaSwingVFX"
	katana_vfx.position = Vector3(0.0, 1.5, 0.0)
	add_child(katana_vfx)
	_peer_nodes.append(katana_vfx)

	# Dash VFX placeholder
	var dash_vfx: MeshInstance3D = MeshInstance3D.new()
	dash_vfx.name = "DashVFX"
	dash_vfx.position = Vector3(1.0, 1.0, 0.0)
	add_child(dash_vfx)
	_peer_nodes.append(dash_vfx)


## Supprime tous les nœuds peers spawned.
func _despawn_peers() -> void:
	for peer: Node3D in _peer_nodes:
		if is_instance_valid(peer):
			peer.queue_free()
	_peer_nodes.clear()


# ---------------------------------------------------------------------------
# Calculs statistiques (hors hot path)
# ---------------------------------------------------------------------------

## Calcule la valeur p99 (index 494 sur 500 après tri ascendant).
## Le tri est effectué sur une copie pour ne pas altérer _dc_ring.
## [return] : valeur au percentile 99.
func _compute_p99() -> int:
	var sorted: PackedInt32Array = _dc_ring.duplicate()
	sorted.sort()
	return sorted[P99_INDEX]


## Calcule la valeur minimale dans _dc_ring.
## [return] : valeur minimale.
func _compute_min() -> int:
	var result: int = _dc_ring[0]
	var k: int = 1
	while k < FRAMES_SAMPLED:
		if _dc_ring[k] < result:
			result = _dc_ring[k]
		k += 1
	return result


## Calcule la valeur maximale dans _dc_ring.
## [return] : valeur maximale.
func _compute_max() -> int:
	var result: int = _dc_ring[0]
	var k: int = 1
	while k < FRAMES_SAMPLED:
		if _dc_ring[k] > result:
			result = _dc_ring[k]
		k += 1
	return result


## Calcule la moyenne des valeurs dans _dc_ring.
## [return] : moyenne (float).
func _compute_mean() -> float:
	var total: int = 0
	var k: int = 0
	while k < FRAMES_SAMPLED:
		total += _dc_ring[k]
		k += 1
	return float(total) / float(FRAMES_SAMPLED)


# ---------------------------------------------------------------------------
# Évaluation des gates
# ---------------------------------------------------------------------------

## Évalue et affiche le résultat d'une gate de budget.
##
## [param config_name] : nom de la configuration (pour log).
## [param p99] : valeur p99 mesurée.
## [param budget_global] : budget global absolu (gate directe).
## [param p99_baseline] : p99 baseline pour calcul delta (-1 si pas de delta).
## [param budget_delta] : budget delta peers (-1 si pas de delta).
func _evaluate_gate(
	config_name: String,
	p99: int,
	budget_global: int,
	p99_baseline: int,
	budget_delta: int
) -> void:
	var pass_global: bool = p99 <= budget_global
	if not pass_global:
		push_error(
			"GATE FAIL [%s] : p99=%d > budget=%d (TR-lvl-004)"
			% [config_name, p99, budget_global]
		)
		_all_gates_pass = false
	else:
		print(
			"GATE PASS [%s] : p99=%d ≤ budget=%d"
			% [config_name, p99, budget_global]
		)

	# Évaluation delta peers si applicable (AC-LVL-31b)
	if p99_baseline >= 0 and budget_delta >= 0:
		var delta: int = p99 - p99_baseline
		var pass_delta: bool = delta <= budget_delta
		if not pass_delta:
			push_error(
				"GATE FAIL [%s] delta peers : delta=%d > budget=%d (AC-LVL-31b)"
				% [config_name, delta, budget_delta]
			)
			_all_gates_pass = false
		else:
			print(
				"GATE PASS [%s] delta peers : delta=%d ≤ budget=%d"
				% [config_name, delta, budget_delta]
			)
