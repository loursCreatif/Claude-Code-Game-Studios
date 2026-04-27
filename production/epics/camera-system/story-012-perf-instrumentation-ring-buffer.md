# Story 012: Perf instrumentation ring buffer (p50/p99 _process cost + E2E mouse→rendered latency)

> **Epic**: Camera System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration (sous-type Perf)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0003 (Rendering & Display Latency Strategy)
**ADR Decision Summary**: ADR-0002 VC-6 acte « Camera `_process` cost ≤ 0.2 ms p99 sur 1000 frames ». ADR-0003 acte budget rendering ≤ 8 ms, E2E latency input→display ≤ 50 ms default / ≤ 30 ms low-latency opt-in (VC-5 Polish phase). GDD AC-CAM-80/81 cible spécifique Camera : `p50 ≤ 0.2 ms`, `p99 ≤ 0.4 ms` sur 240 samples + latence mouse_motion event → rotation rendered ≤ 16 ms p99 sur 1000 samples. Pattern ring buffer pré-alloué canonique (ADR-0004 D-8 `PackedFloat32Array` via `.resize(CAPACITY)`).

**Engine**: Godot 4.6 | **Risk**: HIGH (ADR-0003 VR-2 D3D12 Windows default 4.6 advisory Sprint 1 — cette story porte la mesure requise)
**Engine Notes**: `Time.get_ticks_usec()` précision microseconde stable depuis 4.0. `PackedFloat32Array.resize(CAPACITY)` pré-alloue sans ré-alloc ultérieure (ADR-0004 D-8 pattern). `Performance.get_monitor(Performance.TIME_PROCESS)` existe mais mesure globale — pour isolation Camera, mesure manuelle delta `get_ticks_usec()` début/fin `_process`. VR-2 : frame stability test D3D12 sur 3 OS (Windows, macOS, Linux) attendu sur CI Sprint 1.

**Control Manifest Rules (Presentation layer + Foundation pattern)**:
- Required : ring buffer pré-alloué `PackedFloat32Array` pour coût `_process` (240 samples) + `PackedInt64Array` pour timestamps latence (1000 samples) ; `Time.get_ticks_usec()` pour mesure précise ; zero-alloc runtime après `_ready()` init
- Forbidden : `Array.push_back(Dictionary{ts=..., ms=...})` pattern (alloc hot-path, `allocating_signal_payload` forbidden équivalent) ; mesure composite via `Performance.TIME_PROCESS` globale (ne distingue pas Camera)
- Guardrail : overhead de la mesure elle-même ≤ 0.01 ms/frame (2 `get_ticks_usec` + 1 subtract + 1 array write) ; **anti-pattern self-defeating** : instrumentation qui alloue invalide sa propre mesure

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [ ] **AC-CAM-80** : `GIVEN` session 60 s scène test `tests/perf/camera-stress.tscn` (Player + 3 enemies + wall-run actif cycle + dash cycle), 60 Hz physique / 60 fps affichage (ADR-0001), `THEN` coût CPU `_process` Camera (pitch/yaw + shake + tilt + fov + aim_forward) : **`p50 ≤ 0.2 ms`, `p99 ≤ 0.4 ms`**, mesuré via ring buffer 240 samples. Evidence : `production/qa/evidence/camera-perf-[date].json` + script GUT.
- [ ] **AC-CAM-81** : `GIVEN` application d'un `mouse_motion`, `WHEN` instrumentation ring buffer active, `THEN` latence `t_event → t_applied_rendered` ≤ 16 ms en p99 sur 1000 samples (à 60 fps, = 1 frame max).

---

## Implementation Notes

*Derived from ADR-0004 D-8 pattern + GDD AC-CAM-80/81 + VR-2 advisory :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const PROCESS_COST_CAPACITY: int = 240      # ~4 sec à 60 fps
const LATENCY_CAPACITY: int = 1000          # 1000 events mesurés

# Ring buffer pré-alloué — zero alloc runtime après _ready()
var _process_cost_samples: PackedFloat32Array      # ms
var _process_cost_write_idx: int = 0
var _latency_samples: PackedFloat32Array            # ms
var _latency_write_idx: int = 0

func _ready() -> void:
    # ... existing setup ...
    _process_cost_samples.resize(PROCESS_COST_CAPACITY)
    _latency_samples.resize(LATENCY_CAPACITY)

func _process(delta: float) -> void:
    var t_start: int = Time.get_ticks_usec()
    # --- body Story 005/006/007/011 ---
    _safeguard_rotation()      # Story 011
    _update_tilt_wall_run(delta)   # Story 005
    _update_fov_dash(delta)         # Story 006
    _update_shake(delta)            # Story 007
    # --- end body ---
    var elapsed_ms: float = (Time.get_ticks_usec() - t_start) / 1000.0
    _process_cost_samples[_process_cost_write_idx] = elapsed_ms
    _process_cost_write_idx = (_process_cost_write_idx + 1) % PROCESS_COST_CAPACITY

# Wrapped autour de _on_mouse_motion pour mesure E2E latency
# Stratégie : InputManager timestamps les events (ADR-0004 D-8 pattern déjà appliqué côté Input)
# Camera lit ce timestamp et mesure delta jusqu'au moment où la rotation est applied
func _on_mouse_motion_instrumented(delta: Vector2, event_ts_usec: int) -> void:
    _on_mouse_motion(delta)  # Story 002/003 handler existant
    # Note : la rotation est appliquée dans le handler — pas de lag ajouté
    # Latency = maintenant - timestamp event
    var latency_ms: float = (Time.get_ticks_usec() - event_ts_usec) / 1000.0
    _latency_samples[_latency_write_idx] = latency_ms
    _latency_write_idx = (_latency_write_idx + 1) % LATENCY_CAPACITY

# API publique pour test GUT / QA dashboard
func get_process_cost_percentiles() -> Dictionary:
    return _compute_percentiles(_process_cost_samples)

func get_mouse_latency_percentiles() -> Dictionary:
    return _compute_percentiles(_latency_samples)

func _compute_percentiles(samples: PackedFloat32Array) -> Dictionary:
    var sorted := samples.duplicate()
    sorted.sort()
    var n := sorted.size()
    if n == 0:
        return {"p50": 0.0, "p99": 0.0}
    return {
        "p50": sorted[int(n * 0.5)],
        "p99": sorted[int(n * 0.99)],
    }
```

- **Alternative handler wrap** : si Input ne peut pas passer `event_ts_usec` comme second argument au signal `mouse_motion`, on peut wrapper côté InputManager (ADR-0004 D-8 latency ring buffer est Input-owned — la mesure E2E serait côté Input, et Camera ne fait que « signaler la finition du tick »). **À arbitrer avec gameplay-programmer lors de l'implémentation.** Cette story reste Ready avec cette ambiguïté documentée — si l'API Input n'expose pas le timestamp, faire une petite extension API (`mouse_motion_with_timestamp(delta: Vector2, ts_usec: int)` signal nouveau) ou router via `get_mouse_last_event_timestamp()` helper. Les deux chemins respectent contrats ADR-0004.
- **Mesure overhead** : 2 `get_ticks_usec()` + 1 subtract + 1 array write + 1 modulo = ~5 ns, négligeable.
- **Scène test `tests/perf/camera-stress.tscn`** : à créer — Player dans un niveau test avec mur à droite (wall-run déclenché cyclique via TestController script), 3 `Node3D` ennemis stubs pour simulate entities, Dash déclenché 1× / 2 sec via timer GUT.
- **Evidence JSON output** : test GUT écrit percentiles + samples raw à `production/qa/evidence/camera-perf-[date].json`.
- **Cross-OS VR-2** : le test doit tourner CI sur 3 OS (Windows D3D12, macOS Metal, Linux X11/Wayland) — advisory Sprint 1, non-blocker Accept mais requis Sprint 1 completion.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- InputManager latency ring buffer D-8 : owned par Input epic (story Input séparée).
- Rendering global budget `Performance.TIME_PROCESS` ≤ 8 ms : owned par Rendering/Engine epic (pas Camera spécifique).
- E2E latency hardware→pixel VC-5 (haute vitesse caméra 240 fps) : Polish phase, hors MVP.
- Dashboard vizualisation des percentiles (overlay F3 debug live) : nice-to-have, pas MVP.

---

## QA Test Cases

**AC-CAM-80 (_process cost p50/p99)** — Integration / Perf

- Given : scène `tests/perf/camera-stress.tscn` loaded, Player + 3 enemies stubs, wall-run cycle script actif (wall_normal alternance chaque 2s), dash cycle chaque 2s, 60 fps target
- When : 60 s de gameplay simulé via GUT (`SceneTreeTimer` + manual tick)
- Then : `CameraSystem.get_process_cost_percentiles()` retourne `{"p50": ≤ 0.2, "p99": ≤ 0.4}` (ms)
- Evidence : `production/qa/evidence/camera-perf-YYYY-MM-DD.json` contenant `{"p50": X, "p99": Y, "samples_raw": [...]}`
- Edge cases : scène plus chargée (10+ enemies) → stress au-delà du MVP budget, attendu dégradé — flag si p99 > 0.4 avec pop out

**AC-CAM-81 (latency mouse → rendered)** — Integration / Perf

- Given : instrumentation active, 1000 `mouse_motion` events générés sur 60 s
- When : lecture `CameraSystem.get_mouse_latency_percentiles()`
- Then : `{"p99": ≤ 16.0}` (ms) — correspond à 1 frame max à 60 fps
- Edge cases : scenario freeze-frame (`_process` manque un frame) → attendu 2× frame (33 ms) — test tolère flagging mais blocant si > 2 frames régulier

---

## Test Evidence

**Story Type** : Integration (Perf-oriented)
**Required evidence** : `tests/integration/camera/story-012-perf-instrumentation_test.gd` + scène stub `tests/perf/camera-stress.tscn` + JSON output `production/qa/evidence/camera-perf-[YYYY-MM-DD].json`

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : Stories 001-007 (tous les effets mesurés doivent exister), Story 011 (NaN safeguard compté dans le coût), InputManager latency timestamp API (ADR-0004 D-8 — à coordonner côté Input epic)
- Unlocks : Sprint 1 closure VR-2 advisory, Polish phase E2E VC-5 (caméra haute vitesse), health/perf dashboard
