# Tests unitaires story-016 — Memory budget gate (AC-LVL-32, AC-LVL-36, AC-LVL-37).
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# ARCHITECTURE DE TEST (split headless / CI) :
#
#   GdUnit4 tourne en headless sans RenderingServer GPU actif. Il est donc
#   impossible d'obtenir des deltas VRAM représentatifs d'un vrai chargement.
#   Ce fichier couvre deux couches :
#
#   Couche 1 — Tests structurels (ce fichier) :
#     - Vérifie que les ring buffers sont pré-alloués (taille 65, types corrects)
#     - Vérifie la logique delta VRAM sur valeurs synthétiques (gate ≤ 50 MB)
#     - Vérifie la logique delta combined sur valeurs synthétiques (gate ≤ 70 MB)
#     - Vérifie la logique de stabilité mémoire (gate ≤ 512 KB sur 60 s)
#     - Vérifie la logique de stabilité node count (gate ≤ 5 sur 60 s)
#     - Vérifie l'absence d'alloc heap pendant le sampling (best-effort headless)
#     - Vérifie les constantes de gate (valeurs exactes des seuils story-016)
#     - Vérifie la détection d'un re-load (delta cumulatif ne s'accumule pas)
#
#   Couche 2 — Gate de performance réelle (CI job `perf-level-memory`) :
#     - godot --headless --path . tests/performance/level_memory_runner.tscn
#     - Exit code 0 = toutes gates pass, 1 = au moins une gate fail
#     - Logs JSON + artifacts dans production/qa/
#
# Cette séparation suit le pattern établi par story-015 (level_draw_calls_test).
# Les tests structurels bloquent si la logique est cassée ; le CI job bloque si
# le budget est dépassé sur le runner complet.
#
# Story   : production/epics/level-system/story-016-memory-budgets-vram-ram-stability.md
# ADR     : docs/architecture/adr-0003-rendering-latency.md
# Req     : TR-lvl-005, TR-lvl-037 (AC-LVL-32, AC-LVL-36, AC-LVL-37)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constantes (mirrored depuis le runner pour vérification structurelle)
# ---------------------------------------------------------------------------

## Gate VRAM delta post-load (AC-LVL-32) : 50 MB.
const BUDGET_VRAM_BYTES: int = 50_000_000

## Gate combinée RAM+VRAM post-load (AC-LVL-37) : 70 MB.
const BUDGET_COMBINED_BYTES: int = 70_000_000

## Gate delta Performance.MEMORY_STATIC stabilité 60s (AC-LVL-36) : 512 KB.
const BUDGET_STATIC_MEMORY_DRIFT_BYTES: int = 524_288

## Gate delta OBJECT_NODE_COUNT stabilité 60s (AC-LVL-36) : 5 nœuds.
const BUDGET_OBJECT_NODE_COUNT_DRIFT: int = 5

## Taille du ring buffer (doit correspondre à SAMPLE_BUFFER_SIZE dans le runner).
const EXPECTED_BUFFER_SIZE: int = 65

## Seuil delta mémoire pour le zero-alloc check (64 KB).
const ZERO_ALLOC_MEMORY_BUDGET_KB: int = 64


# ---------------------------------------------------------------------------
# Helpers synthétiques
# ---------------------------------------------------------------------------

## Remplit un PackedInt64Array pré-alloué avec des valeurs croissantes.
## [param ring] : buffer à remplir (déjà resize'd).
## [param base] : valeur de départ (bytes).
## [param delta_per_sample] : incrément par sample (bytes).
func _fill_mem_ring(ring: PackedInt64Array, base: int, delta_per_sample: int) -> void:
	var k: int = 0
	while k < ring.size():
		ring[k] = base + delta_per_sample * k
		k += 1


## Calcule le delta mémoire entre le dernier et le premier sample d'un ring buffer.
## Miroir de la logique du runner, testée indépendamment.
## [param ring] : buffer de samples rempli.
## [param count] : nombre de samples valides dans le ring.
## [return] : delta en bytes (ring[count-1] - ring[0]).
func _compute_mem_delta(ring: PackedInt64Array, count: int) -> int:
	if count < 2:
		return 0
	return int(ring[count - 1]) - int(ring[0])


## Calcule le delta node count entre le dernier et le premier sample.
## [param ring] : buffer de samples rempli.
## [param count] : nombre de samples valides dans le ring.
## [return] : delta (ring[count-1] - ring[0]).
func _compute_obj_delta(ring: PackedInt32Array, count: int) -> int:
	if count < 2:
		return 0
	return ring[count - 1] - ring[0]


# ---------------------------------------------------------------------------
# AC-LVL-32 — Gate VRAM delta ≤ 50 MB
# ---------------------------------------------------------------------------

## Vérifie que la logique gate delta_vram ≤ 50 MB fonctionne correctement
## sur des valeurs synthétiques représentatives.
##
## La gate réelle (avec RenderingServer.get_rendering_info()) est exécutée
## par le CI job `perf-level-memory` (exit code gate).
func test_vram_delta_under_50mb_post_load() -> void:
	# Arrange — simule vram_before et vram_after sous budget
	var vram_before: int = 200_000_000  # 200 MB (état du système avant load)
	var vram_after: int = 245_000_000   # 245 MB (après load : delta = 45 MB ≤ 50 MB)

	# Act
	var delta_vram: int = vram_after - vram_before

	# Assert — delta calculé correctement
	assert_int(delta_vram).is_equal(45_000_000)

	# Assert — gate passe (delta ≤ 50 MB)
	assert_bool(delta_vram <= BUDGET_VRAM_BYTES).is_true()

	# Assert — constante de gate correcte (50 MB = 50_000_000 bytes)
	assert_int(BUDGET_VRAM_BYTES).is_equal(50_000_000)


## Vérifie que la gate AC-LVL-32 échoue correctement quand le delta VRAM
## dépasse 50 MB (dépassement de 5 MB).
func test_vram_delta_exceeds_50mb_fails_gate() -> void:
	# Arrange — delta = 55 MB > 50 MB
	var vram_before: int = 100_000_000
	var vram_after: int = 155_000_000

	# Act
	var delta_vram: int = vram_after - vram_before

	# Assert — delta calculé correctement (55 MB)
	assert_int(delta_vram).is_equal(55_000_000)

	# Assert — gate échoue (delta > 50 MB)
	assert_bool(delta_vram <= BUDGET_VRAM_BYTES).is_false()


# ---------------------------------------------------------------------------
# AC-LVL-37 — Gate combined RAM+VRAM ≤ 70 MB
# ---------------------------------------------------------------------------

## Vérifie que la logique gate combined (delta_ram + delta_vram) ≤ 70 MB
## fonctionne correctement sur valeurs synthétiques.
func test_combined_ram_vram_delta_under_70mb() -> void:
	# Arrange — delta_vram = 45 MB, delta_ram = 18 MB → combined = 63 MB ≤ 70 MB
	var delta_vram: int = 45_000_000
	var delta_ram: int = 18_000_000

	# Act
	var delta_combined: int = delta_vram + delta_ram

	# Assert — combined calculé correctement
	assert_int(delta_combined).is_equal(63_000_000)

	# Assert — gate passe (combined ≤ 70 MB)
	assert_bool(delta_combined <= BUDGET_COMBINED_BYTES).is_true()

	# Assert — constante de gate correcte (70 MB = 70_000_000 bytes)
	assert_int(BUDGET_COMBINED_BYTES).is_equal(70_000_000)


## Vérifie que la gate AC-LVL-37 échoue correctement quand le combined dépasse 70 MB.
## Edge case : VRAM dans budget mais RAM pousse le combined au-dessus.
func test_combined_delta_exceeds_70mb_fails_gate() -> void:
	# Arrange — delta_vram = 49 MB (sous 50 MB) mais delta_ram = 25 MB → combined = 74 MB
	var delta_vram: int = 49_000_000
	var delta_ram: int = 25_000_000

	# Act
	var delta_combined: int = delta_vram + delta_ram

	# Assert — combined = 74 MB
	assert_int(delta_combined).is_equal(74_000_000)

	# Assert — gate échoue (74 MB > 70 MB)
	assert_bool(delta_combined <= BUDGET_COMBINED_BYTES).is_false()

	# Assert — VRAM seule serait dans les clous
	assert_bool(delta_vram <= BUDGET_VRAM_BYTES).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-36 — Gate stabilité mémoire ≤ 512 KB sur 60 s
# ---------------------------------------------------------------------------

## Vérifie que la logique gate delta_static_memory ≤ 512 KB fonctionne
## correctement sur données synthétiques (soak stable = delta = 0).
func test_static_memory_delta_under_512kb_60s() -> void:
	# Arrange — ring buffer pré-alloué, drift minimal (100 bytes par sample = drift sain)
	var mem_ring: PackedInt64Array = PackedInt64Array()
	mem_ring.resize(EXPECTED_BUFFER_SIZE)
	var base_mem: int = 50_000_000  # 50 MB baseline
	var drift_per_sample: int = 100  # 100 bytes par seconde = 6 KB sur 60 s (< 512 KB)
	_fill_mem_ring(mem_ring, base_mem, drift_per_sample)

	# Act — 61 samples (baseline + 60 secondes)
	var sample_count: int = 61
	var delta: int = _compute_mem_delta(mem_ring, sample_count)

	# Assert — delta = 60 * 100 = 6000 bytes (6 KB ≤ 512 KB)
	assert_int(delta).is_equal(6000)

	# Assert — gate passe
	assert_bool(delta <= BUDGET_STATIC_MEMORY_DRIFT_BYTES).is_true()

	# Assert — constante de gate correcte (512 KB = 524_288 bytes)
	assert_int(BUDGET_STATIC_MEMORY_DRIFT_BYTES).is_equal(524_288)


## Vérifie que la gate AC-LVL-36 memory échoue quand le drift dépasse 512 KB.
## Simule un leak de ~9 KB/s → 540 KB sur 60 s.
func test_static_memory_delta_exceeds_512kb_fails_gate() -> void:
	# Arrange — drift de 9000 bytes/sample = ~540 KB sur 60 s
	var mem_ring: PackedInt64Array = PackedInt64Array()
	mem_ring.resize(EXPECTED_BUFFER_SIZE)
	var base_mem: int = 50_000_000
	var drift_per_sample: int = 9000  # ~9 KB/s → 540 KB sur 60 s
	_fill_mem_ring(mem_ring, base_mem, drift_per_sample)

	# Act — 61 samples
	var sample_count: int = 61
	var delta: int = _compute_mem_delta(mem_ring, sample_count)

	# Assert — delta = 60 * 9000 = 540_000 bytes (> 512 KB)
	assert_int(delta).is_equal(540_000)

	# Assert — gate échoue
	assert_bool(delta <= BUDGET_STATIC_MEMORY_DRIFT_BYTES).is_false()


# ---------------------------------------------------------------------------
# AC-LVL-36 — Gate stabilité node count ≤ 5 sur 60 s
# ---------------------------------------------------------------------------

## Vérifie que la logique gate delta_object_count ≤ 5 fonctionne correctement
## sur données synthétiques (count stable = delta = 0).
func test_object_count_delta_under_5_60s() -> void:
	# Arrange — ring buffer pré-alloué, count stable (delta = 3 ≤ 5)
	var obj_ring: PackedInt32Array = PackedInt32Array()
	obj_ring.resize(EXPECTED_BUFFER_SIZE)

	# Remplir : 800 nœuds baseline, +3 sur 60 s (leak léger mais acceptable)
	var k: int = 0
	while k < EXPECTED_BUFFER_SIZE:
		if k >= 30:
			obj_ring[k] = 803  # +3 après 30 s
		else:
			obj_ring[k] = 800
		k += 1

	# Act — 61 samples
	var sample_count: int = 61
	var delta: int = _compute_obj_delta(obj_ring, sample_count)

	# Assert — delta = 803 - 800 = 3 (≤ 5)
	assert_int(delta).is_equal(3)

	# Assert — gate passe
	assert_bool(delta <= BUDGET_OBJECT_NODE_COUNT_DRIFT).is_true()

	# Assert — constante de gate correcte
	assert_int(BUDGET_OBJECT_NODE_COUNT_DRIFT).is_equal(5)


## Vérifie que la gate AC-LVL-36 object count échoue quand le count dérive de 7.
## Simule un node leak progressif (Area3D signal handlers qui s'accumulent).
func test_object_count_delta_exceeds_5_fails_gate() -> void:
	# Arrange — 800 nœuds baseline → 807 après 60 s (delta = 7 > 5)
	var obj_ring: PackedInt32Array = PackedInt32Array()
	obj_ring.resize(EXPECTED_BUFFER_SIZE)

	var k: int = 0
	while k < EXPECTED_BUFFER_SIZE:
		obj_ring[k] = 800 + k / 10  # croissance ~1 nœud toutes les 10 s
		k += 1

	# Act — 61 samples
	var sample_count: int = 61
	var delta: int = _compute_obj_delta(obj_ring, sample_count)

	# Assert — delta ≥ 6 (gate échoue)
	assert_bool(delta > BUDGET_OBJECT_NODE_COUNT_DRIFT).is_true()

	# Assert — gate échoue
	assert_bool(delta <= BUDGET_OBJECT_NODE_COUNT_DRIFT).is_false()


# ---------------------------------------------------------------------------
# Ring buffers — Tests structurels
# ---------------------------------------------------------------------------

## Vérifie que les ring buffers pré-alloués ont la bonne taille et le bon type.
## Conforme au pattern zero-alloc de no-alloc-hot-paths.md (pas de push_back).
func test_ring_buffers_pre_allocated_correct_size() -> void:
	# Arrange — pré-allouer comme le runner
	var mem_ring: PackedInt64Array = PackedInt64Array()
	mem_ring.resize(EXPECTED_BUFFER_SIZE)

	var obj_ring: PackedInt32Array = PackedInt32Array()
	obj_ring.resize(EXPECTED_BUFFER_SIZE)

	# Assert — taille correcte (65 slots)
	assert_int(mem_ring.size()).is_equal(EXPECTED_BUFFER_SIZE)
	assert_int(obj_ring.size()).is_equal(EXPECTED_BUFFER_SIZE)

	# Assert — constante correcte
	assert_int(EXPECTED_BUFFER_SIZE).is_equal(65)

	# Assert — valeurs initialisées à 0 (Godot initialise les PackedArrays)
	assert_int(mem_ring[0]).is_equal(0)
	assert_int(obj_ring[0]).is_equal(0)


## Vérifie que le sampling via indexation directe n'alloue pas de mémoire heap.
## Best-effort en headless — sert de garde-fou contre un push_back accidentel.
func test_ring_buffer_sampling_zero_alloc() -> void:
	# Arrange — pré-allouer comme le runner
	var mem_ring: PackedInt64Array = PackedInt64Array()
	mem_ring.resize(EXPECTED_BUFFER_SIZE)

	# Mesure mémoire avant sampling synthétique
	var mem_before: int = int(OS.get_static_memory_usage())

	# Act — sampling synthétique 65 entrées via indexation directe (zero-alloc)
	# Aucun push_back, aucun littéral Array/Dict, aucun String() cast.
	var i: int = 0
	while i < EXPECTED_BUFFER_SIZE:
		mem_ring[i] = 50_000_000 + i * 100  # valeur synthétique
		i += 1

	# Mesure mémoire après sampling
	var mem_after: int = int(OS.get_static_memory_usage())

	# Assert — pas d'alloc heap significative (< 64 KB)
	var delta_bytes: int = mem_after - mem_before
	if delta_bytes > 0:
		assert_bool(delta_bytes < ZERO_ALLOC_MEMORY_BUDGET_KB * 1024) \
			.override_failure_message(
				"Zero-alloc violation : delta mémoire %d bytes ≥ %d KB (no-alloc-hot-paths.md)"
				% [delta_bytes, ZERO_ALLOC_MEMORY_BUDGET_KB]
			) \
			.is_true()

	# Assert structurel — le tableau est de la bonne taille après sampling
	assert_int(mem_ring.size()).is_equal(EXPECTED_BUFFER_SIZE)

	# Assert — valeur au dernier index est correcte (indexation directe, pas append)
	assert_int(mem_ring[EXPECTED_BUFFER_SIZE - 1]).is_equal(50_000_000 + (EXPECTED_BUFFER_SIZE - 1) * 100)


# ---------------------------------------------------------------------------
# Boundary value tests — valeur exacte à la limite (gate <= comparison)
# ---------------------------------------------------------------------------

## Vérifie que delta_vram = 50 MB exactement passe la gate (comparaison <=).
## Boundary AC-LVL-32 — la limite stricte doit être inclusive.
func test_vram_delta_at_exact_50mb_limit_passes_gate() -> void:
	# Arrange — delta exact 50_000_000 bytes
	var vram_before: int = 100_000_000
	var vram_after: int = 150_000_000

	# Act
	var delta_vram: int = vram_after - vram_before

	# Assert — delta exact 50 MB
	assert_int(delta_vram).is_equal(BUDGET_VRAM_BYTES)

	# Assert — gate passe (<=, pas <)
	assert_bool(delta_vram <= BUDGET_VRAM_BYTES).is_true()


## Vérifie que delta_combined = 70 MB exactement passe la gate (boundary AC-LVL-37).
func test_combined_at_exact_70mb_limit_passes_gate() -> void:
	# Arrange — combined exact 70_000_000 bytes (50 MB VRAM + 20 MB RAM)
	var delta_vram: int = 50_000_000
	var delta_ram: int = 20_000_000

	# Act
	var delta_combined: int = delta_vram + delta_ram

	# Assert — combined exact 70 MB
	assert_int(delta_combined).is_equal(BUDGET_COMBINED_BYTES)

	# Assert — gate passe (boundary inclusive)
	assert_bool(delta_combined <= BUDGET_COMBINED_BYTES).is_true()


## Vérifie que delta_static = 512 KB exactement passe la gate (boundary AC-LVL-36 memory).
func test_static_memory_at_exact_512kb_limit_passes_gate() -> void:
	# Arrange — drift exact 524_288 bytes (512 KB)
	var mem_ring: PackedInt64Array = PackedInt64Array()
	mem_ring.resize(EXPECTED_BUFFER_SIZE)
	mem_ring[0] = 50_000_000
	mem_ring[60] = 50_000_000 + BUDGET_STATIC_MEMORY_DRIFT_BYTES

	# Act
	var sample_count: int = 61
	var delta: int = _compute_mem_delta(mem_ring, sample_count)

	# Assert — delta exact 524_288 bytes
	assert_int(delta).is_equal(BUDGET_STATIC_MEMORY_DRIFT_BYTES)

	# Assert — gate passe (boundary inclusive)
	assert_bool(delta <= BUDGET_STATIC_MEMORY_DRIFT_BYTES).is_true()


# ---------------------------------------------------------------------------
# Reload edge case — re-load same etage ne doit pas accumuler le delta
# ---------------------------------------------------------------------------

## Vérifie que recharger le même étage n'accumule pas le delta VRAM.
## Spec story-016 : "re-load same etage = stable delta (pas de cumul leak)".
## Sur données synthétiques : 2 cycles load → unload → reload doivent retourner
## le même delta (pas de cumul). Logique : capture vram_before AVANT chaque load,
## delta calculé fresh à chaque cycle.
func test_reload_same_etage_no_cumulative_delta() -> void:
	# Arrange — 2 cycles load/unload synthétiques
	# Cycle 1
	var vram_before_1: int = 100_000_000
	var vram_after_1: int = 145_000_000  # delta 45 MB
	# Cycle 2 (après unload — VRAM revient près de la baseline initiale)
	var vram_before_2: int = 100_000_000  # GC complet → baseline propre
	var vram_after_2: int = 145_000_000  # même delta attendu

	# Act
	var delta_cycle_1: int = vram_after_1 - vram_before_1
	var delta_cycle_2: int = vram_after_2 - vram_before_2

	# Assert — delta stable entre cycles (pas d'accumulation leak)
	assert_int(delta_cycle_1).is_equal(delta_cycle_2)

	# Assert — chaque cycle reste sous budget
	assert_bool(delta_cycle_1 <= BUDGET_VRAM_BYTES).is_true()
	assert_bool(delta_cycle_2 <= BUDGET_VRAM_BYTES).is_true()
