## InputLatencyTracker — Ring buffer zero-alloc pour les métriques input→publish.
##
## Extrait de input_manager.gd (TD-008 split). Pas de class_name : bypass class cache
## CI gdUnit4 (pattern preload binding, voir feedback_godot_class_name_autoload_collision).
##
## Instancié par InputManager._ready() et injecté en composition.
## Main-thread only — toutes les méthodes sont appelées depuis _physics_process
## ou lecture debug rare (get_latency_p99_ms). ADR-0004 D-7/D-8.

extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Capacité du ring buffer (2 s @ 60 Hz = 120 samples). Fenêtre rolling.
## Source : ADR-0004 D-8, TR-inp-007.
const CAPACITY: int = 120

## Fenêtre glissante en microsecondes pour le calcul p99 (1 s).
## Les samples plus vieux sont filtrés à la lecture (pas d'éviction active).
const WINDOW_USEC: int = 1_000_000

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Ring buffer zero-alloc pour les samples de latence input→publish (ADR-0004 D-8).
## Pré-alloués via .resize(CAPACITY) dans setup() — .resize garantit la contiguïté
## mémoire et l'absence d'allocation sur assignation indexée arr[i] = value.
var _values_ms: PackedFloat32Array = PackedFloat32Array()
var _timestamps_usec: PackedInt64Array = PackedInt64Array()

## Index d'écriture monotone — slot réel = _write_idx % CAPACITY (ring).
var _write_idx: int = 0

## Nombre de samples effectivement écrits (clampé à CAPACITY). Distinct de _write_idx
## pour que get_p99_ms n'itère pas sur des slots non-remplis après le boot.
var _sample_count: int = 0

## Buffer scratch pré-alloué pour le tri in-place lors du calcul p99 (read-rare @ HUD F3).
## Réutilisé à chaque appel de get_p99_ms : zéro realloc.
var _scratch: PackedFloat32Array = PackedFloat32Array()

## Dernière latence input→publish mesurée en millisecondes.
## Mise à jour à chaque record_sample(). Lue par InputManager.last_input_to_publish_latency_ms.
var last_latency_ms: float = 0.0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Pré-alloue les 3 PackedArrays. Doit être appelé une seule fois depuis
## InputManager._ready() avant tout appel à record_sample(). Zero-alloc après ce point.
## Usage : tracker.setup()
func setup() -> void:
	_values_ms.resize(CAPACITY)
	_timestamps_usec.resize(CAPACITY)
	_scratch.resize(CAPACITY)

# ---------------------------------------------------------------------------
# Hot-path write (appelé depuis _physics_process — zero-alloc impératif)
# ---------------------------------------------------------------------------

## Enregistre un sample dans le ring buffer (ADR-0004 D-8). Zero-alloc par
## construction : 2 indexed writes sur des PackedArrays pré-alloués + 2 ops int.
## Appelé uniquement depuis InputManager._physics_process après le swap.
## Usage : tracker.record_sample(latency_ms, Time.get_ticks_usec())
func record_sample(value_ms: float, ts_usec: int) -> void:
	var slot: int = _write_idx % CAPACITY
	_values_ms[slot] = value_ms
	_timestamps_usec[slot] = ts_usec
	_write_idx += 1
	if _sample_count < CAPACITY:
		_sample_count += 1
	last_latency_ms = value_ms

# ---------------------------------------------------------------------------
# Read-rare (HUD debug F3 ~1 Hz)
# ---------------------------------------------------------------------------

## Retourne le p99 rolling des latences input→publish sur la fenêtre WINDOW_USEC (1 s).
## Lecture rare (HUD debug F3 ~1 Hz) — tri effectué à la demande sur le buffer scratch
## pré-alloué, pas dans le hot path d'écriture.
##
## Comportement :
## - Filtre les samples dont timestamp < now - WINDOW_USEC.
## - Si 0 sample valide dans la fenêtre → retourne 0.0.
## - Si < 10 samples valides → retourne le max (p99 sans sens statistique sur peu d'échantillons).
## - Sinon, retourne la valeur au rang p99 (approximation discrète acceptable HUD).
##
## Technique zero-realloc : copie les valeurs valides dans _scratch[0..valid),
## zero-fill le reste, puis sort() in-place. Les 0.0 remontent en tête,
## les valeurs valides en queue (tri croissant) — p99 lu depuis la queue.
##
## Usage : var p99 := tracker.get_p99_ms()
func get_p99_ms() -> float:
	var now: int = Time.get_ticks_usec()
	var cutoff: int = now - WINDOW_USEC
	var valid: int = 0
	# Boucle for-range sur un int = zero-alloc en Godot 4.6 (itérateur intégré).
	for i: int in _sample_count:
		if _timestamps_usec[i] >= cutoff:
			_scratch[valid] = _values_ms[i]
			valid += 1
	if valid == 0:
		return 0.0
	# Zero-fill les slots non-utilisés pour que sort() mette les valeurs valides
	# en fin de buffer (0.0 < toute latence positive mesurée).
	for i: int in range(valid, CAPACITY):
		_scratch[i] = 0.0
	_scratch.sort()
	# Fallback max si < 10 samples — _scratch[CAPACITY - 1] = max après sort.
	if valid < 10:
		return _scratch[CAPACITY - 1]
	# P99 discret : depuis la fin, on recule de (valid-1)*0.01 positions.
	# Approximation acceptable pour HUD debug (cf. Implementation Notes story-006).
	var p99_idx: int = CAPACITY - 1 - int((valid - 1) * 0.01)
	return _scratch[p99_idx]
