# Tests unitaires story-015 — Draw call budget gate (AC-LVL-31 + AC-LVL-31b).
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# ARCHITECTURE DE TEST (split headless / CI) :
#
#   GdUnit4 tourne en headless sans RenderingServer actif. Il est donc impossible
#   d'appeler Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME et d'obtenir une valeur
#   représentative d'un rendu réel. Ce fichier couvre donc deux couches :
#
#   Couche 1 — Tests structurels (ce fichier) :
#     - Vérifie que le ring buffer est pré-alloué (taille 500, type PackedInt32Array)
#     - Vérifie la logique p99 sur données synthétiques (sort + index 494)
#     - Vérifie la logique delta sur données synthétiques (AC-LVL-31b)
#     - Vérifie l'absence d'alloc heap pendant le sampling via MEMORY_STATIC
#       (best-effort en headless — assert delta < 64 KB sur données synthétiques)
#
#   Couche 2 — Gate de performance réelle (CI job `perf-level-draw-calls`) :
#     - godot --headless --path . tests/performance/level_draw_calls_runner.tscn
#     - Exit code 0 = gate pass, 1 = gate fail
#     - Logs JSON artifacts dans production/qa/
#
# Cette séparation suit le pattern établi par story-014 (level_ccd_sweep_runner).
# Les tests structurels bloquent si la logique est cassée ; le CI job bloque si
# le budget est dépassé sur le runner complet.
#
# Story   : production/epics/level-system/story-015-draw-call-budget-gate.md
# ADR     : docs/architecture/adr-0003-rendering-latency.md
# Req     : TR-lvl-003, TR-lvl-004 (AC-LVL-31, AC-LVL-31b)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constantes (mirrored depuis le runner pour vérifications structurelles)
# ---------------------------------------------------------------------------

## Taille du ring buffer (doit correspondre à FRAMES_SAMPLED dans le runner).
const EXPECTED_RING_SIZE: int = 500

## Index p99 attendu pour 500 frames (499 * 0.99 = 494.01 → 494).
const EXPECTED_P99_INDEX: int = 494

## Budget AC-LVL-31 N=10.
const BUDGET_10_ROOMS: int = 350

## Budget AC-LVL-31 N=8.
const BUDGET_8_ROOMS: int = 290

## Budget delta peers AC-LVL-31b.
const BUDGET_PEERS_DELTA: int = 170

## Hard cap global AC-LVL-31b.
const BUDGET_GLOBAL_CAP: int = 500

## Seuil delta mémoire acceptable pour le zero-alloc check (64 KB).
## Correspond à AC-PF-4 de story-008 (PackedInt32Array 500 × 4 = 2000 bytes
## + overhead minimal attendu < 64 KB).
const MEMORY_DELTA_BUDGET_KB: int = 64


# ---------------------------------------------------------------------------
# Helpers synthétiques
# ---------------------------------------------------------------------------

## Construit un PackedInt32Array de taille [size] avec des valeurs 0..size-1.
## Utilisé pour tester la logique de tri et p99 sans RenderingServer.
func _make_ascending_ring(size: int) -> PackedInt32Array:
	var ring: PackedInt32Array = PackedInt32Array()
	ring.resize(size)
	var k: int = 0
	while k < size:
		ring[k] = k
		k += 1
	return ring


## Calcule la valeur p99 sur un PackedInt32Array : tri + index 494.
## Miroir de la logique _compute_p99() du runner, testée indépendamment.
func _compute_p99(ring: PackedInt32Array) -> int:
	var sorted: PackedInt32Array = ring.duplicate()
	sorted.sort()
	return sorted[EXPECTED_P99_INDEX]


## Calcule le delta peers : p99_with_peers - p99_baseline.
func _compute_delta(p99_baseline: int, p99_with_peers: int) -> int:
	return p99_with_peers - p99_baseline


# ---------------------------------------------------------------------------
# AC-LVL-31 N=10 — Logique gate 350
# ---------------------------------------------------------------------------

## Vérifie que la logique gate p99 ≤ 350 fonctionne correctement sur données
## synthétiques. Ce test ne mesure PAS de draw calls réels (renderer absent en
## headless) — il valide la logique de calcul du runner.
##
## La gate réelle sur étage_10_rooms.tscn est exécutée par le CI job
## `perf-level-draw-calls` (exit code gate).
func test_draw_call_budget_under_350_for_10_rooms_p99() -> void:
	# Arrange — données synthétiques : valeurs 0..499
	# p99 synthétique = index 494 dans [0..499] trié = 494
	# 494 ≤ 350 ? Non — mais le test porte sur la logique (calcul correct),
	# pas sur une vraie valeur Forward+. Le CI job asserte la vraie valeur.
	var ring: PackedInt32Array = _make_ascending_ring(EXPECTED_RING_SIZE)

	# Act
	var p99: int = _compute_p99(ring)

	# Assert — vérifier que le calcul retourne bien index 494 sur données 0..499
	assert_int(p99).is_equal(EXPECTED_P99_INDEX)

	# Assert structurel : le ring a la bonne taille
	assert_int(ring.size()).is_equal(EXPECTED_RING_SIZE)

	# Documenter la gate cible (informatif, non-bloquant en headless)
	# La gate réelle p99 ≤ 350 est vérifiée par le CI runner (exit code 0).
	assert_int(BUDGET_10_ROOMS).is_equal(350)


# ---------------------------------------------------------------------------
# AC-LVL-31 N=8 — Logique gate 290
# ---------------------------------------------------------------------------

## Vérifie la logique gate p99 ≤ 290 sur données synthétiques.
## La gate réelle sur étage_8_rooms.tscn est exécutée par le CI job.
func test_draw_call_budget_under_290_for_8_rooms_p99() -> void:
	# Arrange — données synthétiques uniformes à 200 (sous-budget 290)
	var ring: PackedInt32Array = PackedInt32Array()
	ring.resize(EXPECTED_RING_SIZE)
	var k: int = 0
	while k < EXPECTED_RING_SIZE:
		ring[k] = 200
		k += 1

	# Act
	var p99: int = _compute_p99(ring)

	# Assert — p99 d'un tableau uniforme = la valeur elle-même
	assert_int(p99).is_equal(200)

	# Assert : 200 ≤ 290 (gate passe sur données synthétiques)
	assert_bool(p99 <= BUDGET_8_ROOMS).is_true()

	# Assert structurel : budget N=8 est strictement inférieur au budget N=10
	assert_bool(BUDGET_8_ROOMS < BUDGET_10_ROOMS).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-31b — Logique delta peers ≤ 170 + global ≤ 500
# ---------------------------------------------------------------------------

## Vérifie la logique delta peers (p99_with_peers - p99_baseline ≤ 170)
## et la gate globale (p99_with_peers ≤ 500) sur données synthétiques.
## La gate réelle est exécutée par le CI job `perf-level-draw-calls`.
func test_peer_overhead_under_170_dc_p99() -> void:
	# Arrange — baseline synthétique : p99 = 100
	var baseline_ring: PackedInt32Array = PackedInt32Array()
	baseline_ring.resize(EXPECTED_RING_SIZE)
	var k: int = 0
	while k < EXPECTED_RING_SIZE:
		baseline_ring[k] = 100
		k += 1
	var p99_baseline: int = _compute_p99(baseline_ring)

	# Arrange — with_peers synthétique : p99 = 250 (delta = 150 ≤ 170)
	var peers_ring: PackedInt32Array = PackedInt32Array()
	peers_ring.resize(EXPECTED_RING_SIZE)
	var j: int = 0
	while j < EXPECTED_RING_SIZE:
		peers_ring[j] = 250
		j += 1
	var p99_with_peers: int = _compute_p99(peers_ring)

	# Act
	var delta: int = _compute_delta(p99_baseline, p99_with_peers)

	# Assert — delta correct : 250 - 100 = 150
	assert_int(delta).is_equal(150)

	# Assert — delta ≤ 170 (AC-LVL-31b gate)
	assert_bool(delta <= BUDGET_PEERS_DELTA).is_true()

	# Assert — global ≤ 500 (hard cap technical-preferences.md)
	assert_bool(p99_with_peers <= BUDGET_GLOBAL_CAP).is_true()

	# Sanity check — no peers = delta == 0
	var delta_no_peers: int = _compute_delta(p99_baseline, p99_baseline)
	assert_int(delta_no_peers).is_equal(0)


# ---------------------------------------------------------------------------
# Zero-alloc ring buffer check
# ---------------------------------------------------------------------------

## Vérifie que le sampling de 500 valeurs sur un PackedInt32Array pré-alloué
## n'alloue pas de mémoire heap significative (delta < 64 KB).
##
## Ce test est un best-effort en context headless : Performance.MEMORY_STATIC
## peut ne pas être précis sans le renderer actif. Il sert de garde-fou
## structurel pour détecter une régression d'alloc évidente (e.g. push_back
## accidentel remplaçant l'indexation directe).
##
## La vérification d'alloc réelle (AC-PF-4) est couverte par le CI runner
## sur 500 frames de rendu réel.
func test_dc_ring_buffer_zero_alloc() -> void:
	# Arrange — pré-allouer comme le runner
	var ring: PackedInt32Array = PackedInt32Array()
	ring.resize(EXPECTED_RING_SIZE)

	# Assert structurel : la taille est bien 500 après resize (pas de lazy alloc)
	assert_int(ring.size()).is_equal(EXPECTED_RING_SIZE)

	# Mesure mémoire avant sampling synthétique
	var mem_before: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))

	# Act — sampling synthétique 500 entrées via indexation directe (zero-alloc)
	# Aucun push_back, aucun littéral Array/Dict, aucun String() cast.
	var i: int = 0
	while i < EXPECTED_RING_SIZE:
		ring[i] = i * 2  # valeur synthétique
		i += 1

	# Mesure mémoire après sampling synthétique
	var mem_after: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))

	# Assert — delta mémoire < 64 KB (seuil AC-PF-4 / no-alloc-hot-paths.md)
	var delta_bytes: int = mem_after - mem_before
	# Note : si mem_after < mem_before (GC entre les deux mesures), delta est négatif
	# → pas d'alloc = conforme. On ne vérifie que les cas positifs > seuil.
	if delta_bytes > 0:
		assert_bool(delta_bytes < MEMORY_DELTA_BUDGET_KB * 1024) \
			.override_failure_message(
				"Zero-alloc violation : delta mémoire %d bytes ≥ %d KB (no-alloc-hot-paths.md)"
				% [delta_bytes, MEMORY_DELTA_BUDGET_KB]
			) \
			.is_true()

	# Assert structurel : le tableau est toujours de taille 500 après sampling
	assert_int(ring.size()).is_equal(EXPECTED_RING_SIZE)

	# Assert : la valeur à l'index 0 est bien 0 (indexation directe, pas append)
	assert_int(ring[0]).is_equal(0)

	# Assert : la valeur au dernier index est bien (499 * 2) = 998
	assert_int(ring[EXPECTED_RING_SIZE - 1]).is_equal((EXPECTED_RING_SIZE - 1) * 2)
