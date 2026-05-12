class_name CameraPerfMetrics
extends RefCounted

## Helper perf ring buffers — extrait de CameraSystem (TD-008 SPLIT #3).
## Stocke et calcule les percentiles p50/p99 pour deux métriques :
##   - process_cost : coût _process en ms (GDD AC-CAM-80 : p50 ≤ 0.2 ms, p99 ≤ 0.4 ms)
##   - latency      : latence mouse_motion→rotation en ms (GDD AC-CAM-81 : p99 ≤ 16 ms)
## Zero-alloc runtime : ring buffers pré-alloués à l'init, aucune allocation par tick.
## ADR-0004 D-8 (zero-alloc hot path) / ADR-0002 / Story 012.

# Ring buffer — process cost
var process_cost_samples: PackedFloat32Array = PackedFloat32Array()
var process_cost_write_idx: int = 0

# Ring buffer — mouse latency
var latency_samples: PackedFloat32Array = PackedFloat32Array()
var latency_write_idx: int = 0


## Initialise et pré-alloue les ring buffers. Appeler depuis CameraSystem._ready().
## Idempotent : skip si déjà alloué (support injection tests GdUnit4).
func init(process_cost_capacity: int, latency_capacity: int) -> void:
	if process_cost_samples.size() == 0:
		process_cost_samples.resize(process_cost_capacity)
	if latency_samples.size() == 0:
		latency_samples.resize(latency_capacity)


## Enregistre un échantillon de coût _process (ms). Appelé depuis CameraSystem._process.
## Zero-alloc : écriture directe dans le ring buffer pré-alloué.
func record_process_cost(value_ms: float) -> void:
	process_cost_samples[process_cost_write_idx] = value_ms
	process_cost_write_idx = (process_cost_write_idx + 1) % process_cost_samples.size()


## Enregistre un échantillon de latence mouse (ms). Appelé depuis _on_mouse_motion.
## Zero-alloc : écriture directe dans le ring buffer pré-alloué.
func record_latency(value_ms: float) -> void:
	latency_samples[latency_write_idx] = value_ms
	latency_write_idx = (latency_write_idx + 1) % latency_samples.size()


## Retourne {p50, p99} du coût _process en ms.
func get_process_cost_percentiles() -> Dictionary:
	return _compute_percentiles(process_cost_samples)


## Retourne {p50, p99} de la latence mouse_motion→rotation en ms.
func get_mouse_latency_percentiles() -> Dictionary:
	return _compute_percentiles(latency_samples)


## Tri sur duplicate() — zero-alloc côté caller. n==0 → zeros.
func _compute_percentiles(samples: PackedFloat32Array) -> Dictionary:
	var n: int = samples.size()
	if n == 0:
		return {"p50": 0.0, "p99": 0.0}
	var sorted: PackedFloat32Array = samples.duplicate()
	sorted.sort()
	return {
		"p50": sorted[int(float(n) * 0.50)],
		"p99": sorted[int(float(n) * 0.99)],
	}


## Remet à zéro les deux ring buffers (utile pour les tests).
func clear() -> void:
	process_cost_samples.fill(0.0)
	process_cost_write_idx = 0
	latency_samples.fill(0.0)
	latency_write_idx = 0
