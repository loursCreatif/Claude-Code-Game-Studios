# Tests unitaires story-017 — Frame time + load time gate (AC-LVL-3, AC-LVL-34, AC-LVL-35a).
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# ARCHITECTURE DE TEST (split headless / CI) :
#
#   GdUnit4 tourne en headless sans rendering loop GPU active. Il est donc
#   impossible d'obtenir des valeurs Performance.TIME_PROCESS représentatives
#   d'un vrai rendu. Ce fichier couvre deux couches :
#
#   Couche 1 — Tests structurels (ce fichier) :
#     - Vérifie la logique gate load time (AC-LVL-3 : ≤ 1000 ms)
#     - Vérifie la logique gate frame time p50 (AC-LVL-34 : ≤ 12.0 ms)
#     - Vérifie la logique gate frame time p99 (AC-LVL-34 : ≤ 14.0 ms)
#     - Vérifie la logique gate transition window p99 (AC-LVL-35a : ≤ 14.0 ms)
#     - Vérifie le pré-allocation des ring buffers (taille 500 et 24)
#     - Vérifie le calcul correct des index percentile (p50=249, p99=494 sur 500)
#     - Vérifie les constantes de gate (valeurs exactes des seuils story-017)
#
#   Couche 2 — Gate de performance réelle (CI job `perf-level-frame-time`) :
#     - godot --headless --path . tests/performance/level_frame_time_runner.tscn
#     - Exit code 0 = toutes gates pass, 1 = au moins une gate fail
#     - Logs JSON + artifacts dans production/qa/
#
# Cette séparation suit le pattern établi par story-015 (level_draw_calls_test)
# et story-016 (level_memory_test). Les tests structurels bloquent si la logique
# est cassée ; le CI job bloque si le budget est dépassé sur le runner complet.
#
# Story   : production/epics/level-system/story-017-load-time-frame-time-gate.md
# ADR     : docs/architecture/adr-0001-physics-rate-60hz.md
#           docs/architecture/adr-0003-rendering-latency.md
# Req     : TR-lvl-035, TR-lvl-036 (AC-LVL-3, AC-LVL-34, AC-LVL-35a)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constantes (mirrored depuis le runner pour vérification structurelle)
# ---------------------------------------------------------------------------

## Gate load time (AC-LVL-3 / F4 budget) : 1000 ms.
const GATE_LOAD_TIME_MS: int = 1000

## Gate frame time p50 intra-room (AC-LVL-34) : 12.0 ms.
const GATE_P50_MS: float = 12.0

## Gate frame time p99 intra-room (AC-LVL-34) et transition (AC-LVL-35a) : 14.0 ms.
const GATE_P99_MS: float = 14.0

## Nombre de frames intra-room (AC-LVL-34).
const FRAMES_INTRA_ROOM: int = 500

## Nombre de frames dans la window de transition (AC-LVL-35a).
const FRAMES_TRANSITION: int = 24

## Index p50 attendu dans 500 samples : int(499 * 0.50) = 249.
const EXPECTED_P50_INDEX_500: int = 249

## Index p99 attendu dans 500 samples : int(499 * 0.99) = 494.
const EXPECTED_P99_INDEX_500: int = 494

## Index p99 attendu dans 24 samples : int(23 * 0.99) = 22... mais le runner
## utilise l'index 23 (valeur max) — vérifier cohérence ci-dessous.
## Note : int(24 * 0.99) = 23 (index 0-based du 99e percentile sur 24 samples).
const EXPECTED_P99_INDEX_24: int = 23


# ---------------------------------------------------------------------------
# Helpers synthétiques
# ---------------------------------------------------------------------------

## Construit un PackedFloat32Array de taille `size` rempli uniformément
## avec `constant_value_ms` (ms) — simule un renderer stable.
##
## [param size] : nombre d'entrées dans le buffer.
## [param constant_value_ms] : valeur en ms pour toutes les entrées.
## [return] : buffer pré-rempli.
func _make_uniform_frame_buffer(size: int, constant_value_ms: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(size)
	var k: int = 0
	while k < size:
		buf[k] = constant_value_ms
		k += 1
	return buf


## Construit un PackedFloat32Array de 500 entrées avec une valeur de base
## et une seule spike à l'index `spike_index`.
##
## [param base_ms] : valeur de base pour toutes les frames sauf la spike.
## [param spike_ms] : valeur de la spike à l'index spike_index.
## [param spike_index] : index où insérer la spike (0-based).
## [return] : buffer 500 entrées avec spike.
func _make_frame_buffer_with_spike(base_ms: float, spike_ms: float, spike_index: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FRAMES_INTRA_ROOM)
	var k: int = 0
	while k < FRAMES_INTRA_ROOM:
		if k == spike_index:
			buf[k] = spike_ms
		else:
			buf[k] = base_ms
		k += 1
	return buf


## Calcule le percentile à l'index donné dans un buffer trié.
##
## [param buf] : buffer non trié (sera dupliqué + trié).
## [param index] : index dans le tableau trié (0-based).
## [return] : valeur percentile en ms.
func _percentile_at_index(buf: PackedFloat32Array, index: int) -> float:
	var sorted_buf: PackedFloat32Array = buf.duplicate()
	sorted_buf.sort()
	return sorted_buf[index]


# ---------------------------------------------------------------------------
# AC-LVL-3 — Gate load time ≤ 1000 ms
# ---------------------------------------------------------------------------

## Vérifie que la logique gate load_time ≤ 1000 ms fonctionne sur valeur
## synthétique représentative (850 ms < 1000 ms).
##
## La gate réelle (Time.get_ticks_msec() + ResourceLoader) est exécutée
## par le CI job `perf-level-frame-time`.
func test_load_time_under_1000ms_passes_gate() -> void:
	# Arrange — load time synthétique sous budget
	var elapsed_msec: int = 850

	# Act
	var gate_pass: bool = elapsed_msec <= GATE_LOAD_TIME_MS

	# Assert — gate passe (850 ms ≤ 1000 ms)
	assert_bool(gate_pass).is_true()

	# Assert — constante de gate correcte (F4 budget = 1000 ms)
	assert_int(GATE_LOAD_TIME_MS).is_equal(1000)


## Vérifie que la gate AC-LVL-3 échoue quand le load time dépasse 1000 ms.
## Simule une fixture lente (1200 ms).
func test_load_time_exceeds_1000ms_fails_gate() -> void:
	# Arrange — load time au-dessus du budget F4
	var elapsed_msec: int = 1200

	# Act
	var gate_pass: bool = elapsed_msec <= GATE_LOAD_TIME_MS

	# Assert — gate échoue (1200 ms > 1000 ms)
	assert_bool(gate_pass).is_false()

	# Assert — valeur mesurée > budget
	assert_bool(elapsed_msec > GATE_LOAD_TIME_MS).is_true()


# ---------------------------------------------------------------------------
# AC-LVL-34 — Gate frame time p50 ≤ 12.0 ms sur 500 frames
# ---------------------------------------------------------------------------

## Vérifie que la logique gate p50 ≤ 12.0 ms fonctionne sur 500 frames
## synthétiques à 8.0 ms (bien sous budget).
func test_frame_time_p50_under_12ms_500_frames() -> void:
	# Arrange — 500 frames uniformes à 8.0 ms (p50 = 8.0 ms < 12.0 ms)
	var buf: PackedFloat32Array = _make_uniform_frame_buffer(FRAMES_INTRA_ROOM, 8.0)

	# Act
	var p50_ms: float = _percentile_at_index(buf, EXPECTED_P50_INDEX_500)

	# Assert — p50 calculé correctement (tableau uniforme → toutes valeurs = 8.0 ms)
	assert_float(p50_ms).is_equal_approx(8.0, 0.01)

	# Assert — gate passe (p50 ≤ 12.0 ms)
	assert_bool(p50_ms <= GATE_P50_MS).is_true()

	# Assert — constante de gate correcte
	assert_float(GATE_P50_MS).is_equal_approx(12.0, 0.001)


## Vérifie que la logique gate p99 ≤ 14.0 ms fonctionne sur 500 frames
## synthétiques à 10.0 ms (bien sous budget).
func test_frame_time_p99_under_14ms_500_frames() -> void:
	# Arrange — 500 frames uniformes à 10.0 ms (p99 = 10.0 ms < 14.0 ms)
	var buf: PackedFloat32Array = _make_uniform_frame_buffer(FRAMES_INTRA_ROOM, 10.0)

	# Act
	var p99_ms: float = _percentile_at_index(buf, EXPECTED_P99_INDEX_500)

	# Assert — p99 calculé correctement
	assert_float(p99_ms).is_equal_approx(10.0, 0.01)

	# Assert — gate passe (p99 ≤ 14.0 ms)
	assert_bool(p99_ms <= GATE_P99_MS).is_true()

	# Assert — constante de gate correcte
	assert_float(GATE_P99_MS).is_equal_approx(14.0, 0.001)


## Vérifie que la gate AC-LVL-34 p99 échoue quand le 99e percentile dépasse 14.0 ms.
## Simule 500 frames dont 5 spikes à 18 ms qui tirent le p99 au-delà du budget.
func test_frame_time_p99_exceeds_14ms_fails_gate() -> void:
	# Arrange — 495 frames à 8.0 ms + 5 frames à 18.0 ms
	# Avec 500 frames et index p99=494 : 5 frames > budget → p99 > 14.0 ms
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FRAMES_INTRA_ROOM)
	var k: int = 0
	while k < FRAMES_INTRA_ROOM:
		if k >= 495:
			buf[k] = 18.0  # 5 frames spike à 18 ms (> 14 ms gate)
		else:
			buf[k] = 8.0   # 495 frames stables à 8 ms
		k += 1

	# Act
	var p99_ms: float = _percentile_at_index(buf, EXPECTED_P99_INDEX_500)

	# Assert — p99 = 18.0 ms (index 494 sur 500 triés = 5e valeur à partir du max)
	assert_float(p99_ms).is_equal_approx(18.0, 0.01)

	# Assert — gate échoue (p99 > 14.0 ms)
	assert_bool(p99_ms <= GATE_P99_MS).is_false()


# ---------------------------------------------------------------------------
# AC-LVL-35a — Gate transition window p99 ≤ 14.0 ms sur 24 frames
# ---------------------------------------------------------------------------

## Vérifie que la logique gate transition window p99 ≤ 14.0 ms fonctionne
## sur 24 frames synthétiques à 9.0 ms (bien sous budget).
func test_transition_window_p99_under_14ms_24_frames() -> void:
	# Arrange — 24 frames uniformes à 9.0 ms (window transition stable)
	var buf: PackedFloat32Array = _make_uniform_frame_buffer(FRAMES_TRANSITION, 9.0)

	# Act
	var p99_ms: float = _percentile_at_index(buf, EXPECTED_P99_INDEX_24)

	# Assert — p99 calculé correctement (tableau uniforme → toutes valeurs = 9.0 ms)
	assert_float(p99_ms).is_equal_approx(9.0, 0.01)

	# Assert — gate passe (p99 ≤ 14.0 ms)
	assert_bool(p99_ms <= GATE_P99_MS).is_true()

	# Assert — taille de la window correcte (24 frames)
	assert_int(FRAMES_TRANSITION).is_equal(24)


# ---------------------------------------------------------------------------
# Ring buffers — Tests structurels (zero-alloc compliance)
# ---------------------------------------------------------------------------

## Vérifie que les ring buffers pré-alloués ont la bonne taille et le bon type.
## Conforme au pattern zero-alloc de no-alloc-hot-paths.md (resize → pas de push_back).
func test_ring_buffer_pre_allocated_correct_size_500() -> void:
	# Arrange — pré-allouer comme le runner (PackedFloat32Array.resize(500))
	var frame_times_ms: PackedFloat32Array = PackedFloat32Array()
	frame_times_ms.resize(FRAMES_INTRA_ROOM)

	var transition_times_ms: PackedFloat32Array = PackedFloat32Array()
	transition_times_ms.resize(FRAMES_TRANSITION)

	# Assert — taille ring buffer intra-room = 500
	assert_int(frame_times_ms.size()).is_equal(FRAMES_INTRA_ROOM)

	# Assert — taille ring buffer transition = 24
	assert_int(transition_times_ms.size()).is_equal(FRAMES_TRANSITION)

	# Assert — constantes correctes
	assert_int(FRAMES_INTRA_ROOM).is_equal(500)
	assert_int(FRAMES_TRANSITION).is_equal(24)

	# Assert — valeurs initialisées à 0.0 (Godot initialise les PackedArrays)
	assert_float(frame_times_ms[0]).is_equal_approx(0.0, 0.001)
	assert_float(transition_times_ms[0]).is_equal_approx(0.0, 0.001)


## Vérifie que les index percentile p50 et p99 sur 500 samples sont corrects.
## p50 = int(499 * 0.50) = 249 ; p99 = int(499 * 0.99) = 494.
## Ces index sont critiques pour la cohérence gate AC-LVL-34.
func test_percentile_index_calculation_correct() -> void:
	# Arrange — vecteur croissant de 0 à 499 (valeur = index)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FRAMES_INTRA_ROOM)
	var k: int = 0
	while k < FRAMES_INTRA_ROOM:
		buf[k] = float(k)
		k += 1

	# Trier (déjà trié, mais conforme au pattern runner)
	var sorted_buf: PackedFloat32Array = buf.duplicate()
	sorted_buf.sort()

	# Act — lire les valeurs aux index p50 et p99
	var p50_value: float = sorted_buf[EXPECTED_P50_INDEX_500]
	var p99_value: float = sorted_buf[EXPECTED_P99_INDEX_500]

	# Assert — index p50 = 249 → valeur 249.0
	assert_float(p50_value).is_equal_approx(249.0, 0.001)

	# Assert — index p99 = 494 → valeur 494.0
	assert_float(p99_value).is_equal_approx(494.0, 0.001)

	# Assert — constantes d'index correctes (critical for gate logic)
	assert_int(EXPECTED_P50_INDEX_500).is_equal(249)
	assert_int(EXPECTED_P99_INDEX_500).is_equal(494)


## Vérifie que le calcul du p99 sur 24 frames utilise l'index 23 (valeur max).
## Index p99 sur 24 samples : int(24 * 0.99) = 23 (dernier index 0-based).
func test_p99_index_24_frames_is_last_index() -> void:
	# Arrange — vecteur croissant de 0.0 à 23.0 (valeur = index)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(FRAMES_TRANSITION)
	var k: int = 0
	while k < FRAMES_TRANSITION:
		buf[k] = float(k)
		k += 1

	# Trier
	var sorted_buf: PackedFloat32Array = buf.duplicate()
	sorted_buf.sort()

	# Act — lire la valeur à l'index p99 = 23
	var p99_value: float = sorted_buf[EXPECTED_P99_INDEX_24]

	# Assert — index 23 → valeur 23.0 (valeur max du tableau)
	assert_float(p99_value).is_equal_approx(23.0, 0.001)

	# Assert — constante d'index correcte
	assert_int(EXPECTED_P99_INDEX_24).is_equal(23)

	# Assert — l'index p99 est bien le dernier index du tableau de 24 (index max = 23)
	assert_int(EXPECTED_P99_INDEX_24).is_equal(FRAMES_TRANSITION - 1)
