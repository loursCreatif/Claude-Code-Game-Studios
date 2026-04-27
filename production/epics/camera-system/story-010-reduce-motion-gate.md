# Story 010: Reduce_motion gate (tilt × 0.25, fov_kick × 0.5, shake × 0)

> **Epic**: Camera System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: aucun TR-cam direct (accessibility floor MVP, GDD Rule 14 — décision creative-director r1 2026-04-21 « floor accessibility — évite exclusion 15-25% public motion-sensitive »)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm — ownership des effets modulés est sur les noeuds prescrits)
**ADR Decision Summary**: Pas d'ADR direct pour `reduce_motion` (décision design-level creative-director). Lu chaque frame depuis `InputManager.reduce_motion` (ou équivalent settings — ownership TBD dans entities registry). Applique multiplicateurs AVANT commit : tilt × 0.25, fov_kick × 0.5, shake × 0.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Simple lecture bool + multiplication scalaire chaque frame — coût négligeable. Pas de post-cutoff API. Hot-reload (pas de cache) — toggle ON/OFF runtime depuis Menu a effet immédiat au prochain frame.

**Control Manifest Rules (Presentation layer)**:
- Required : multiplicateurs appliqués dans les 3 handlers d'effets (Stories 005, 006, 007) avant commit sur leurs noeuds respectifs ; lecture `InputManager.reduce_motion` (ou équivalent) chaque frame
- Forbidden : cacher `reduce_motion` dans variable locale Camera (perd hot-reload) ; appliquer multiplicateur sur une mesure composite (ex. tilt déjà commit puis rétro-multiplié) — doit modifier le target AVANT lerp
- Guardrail : cost ≤ 0.01 ms par frame (3 lectures bool + 3 multiplications)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [ ] **AC-CAM-70** : `GIVEN` `reduce_motion == true`, `WHEN` Player entre en WallRunning, `THEN` target_roll effectif = `WALL_RUN_TILT_ANGLE * wall_side * 0.25` (= 0.0875 rad au lieu de 0.35).
- [ ] **AC-CAM-71** : `GIVEN` `reduce_motion == true`, `WHEN` Player dashe, `THEN` `camera3d.fov` converge vers `BASE_FOV + DASH_FOV_KICK * 0.5 = 95°` (peak) au lieu de 100°.
- [ ] **AC-CAM-72** : `GIVEN` `reduce_motion == true`, `WHEN` `add_shake_roll(0.05)` appelé, `THEN` `_shake_offset` reste à `Vector3.ZERO` (shake désactivé, multiplier = 0).

---

## Implementation Notes

*Derived from GDD Rule 14 :*

Patcher les 3 handlers dans `src/gameplay/camera/camera_system.gd` :

```gdscript
# Patch Story 005 _update_tilt_wall_run
func _update_tilt_wall_run(delta: float) -> void:
    var player: CharacterBody3D = get_parent()
    var wall_side: int = int(sign((-player.wall_normal).dot(player.global_transform.basis.x)))
    var target_roll: float = WALL_RUN_TILT_ANGLE * wall_side
    # reduce_motion gate — lu chaque frame (hot-reload), pas caché
    if InputManager.reduce_motion:
        target_roll *= 0.25   # Rule 14 : tilt_mult
    _camera_effects.rotation.z = lerp(
        _camera_effects.rotation.z,
        target_roll,
        min(TILT_LERP_SPEED * delta, 1.0)
    )

# Patch Story 006 _update_fov_dash
func _update_fov_dash(delta: float) -> void:
    var player: CharacterBody3D = get_parent()
    var dash_kick: float = DASH_FOV_KICK
    # reduce_motion gate
    if InputManager.reduce_motion:
        dash_kick *= 0.5   # Rule 14 : fov_kick_mult → peak 95° au lieu de 100°
    var target_fov: float = BASE_FOV + (dash_kick if player.is_dashing else 0.0)
    _camera3d.fov = lerp(
        _camera3d.fov,
        target_fov,
        min(DASH_FOV_LERP_SPEED * delta, 1.0)
    )

# Patch Story 007 add_shake — gate au point d'injection, pas à chaque frame
func add_shake(offset_radians: Vector3) -> void:
    # Rule 14 : shake_mult = 0.0 → effectivement désactive le shake
    if InputManager.reduce_motion:
        return  # no-op : shake désactivé complètement
    _shake_offset += offset_radians
    _shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)
```

- **Où appliquer** : **AU TARGET avant lerp**, pas après commit. Motivation : lerp doit converger vers la cible atténuée, pas appliquer une atténuation post-lerp qui créerait un drift subtil quand `reduce_motion` toggle en cours de wall-run.
- **Shake** : gate au point d'injection (`add_shake`) plutôt que multiplicateur `0.0` — plus économique (évite inject + clamp à 0 répété). Comportement équivalent pour `add_shake_roll` qui est wrapper `add_shake`.
- **Hot-reload** : lecture `InputManager.reduce_motion` chaque frame — si Menu toggle ON pendant un wall-run actif, le tilt converge vers target atténué au frame suivant (lerp smooth la transition).
- **Ownership de `reduce_motion`** : GDD Rule 14 dit « Owned par Input System (ou équivalent settings — ownership registry) ». Placeholder `InputManager.reduce_motion` — si Input GDD ne l'expose pas encore, peut-être besoin d'étendre l'API Input OU de passer par un autre singleton (AccessibilitySettings). **Décision** : utiliser `InputManager.reduce_motion` si présent au moment de l'impl ; sinon flag TODO pour story AccessibilitySettings ultérieure. Si absent MVP, fallback `const REDUCE_MOTION = false` hardcoded dans Camera temporaire + TODO comment pour router via settings quand disponible.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Future AccessibilitySettings story : exposition UI toggle dans Menu Settings ; persistance via resource ; router vers `InputManager.reduce_motion` ou équivalent.
- Future Mouse smoothing option (GDD Open Question) : option séparée, pas bundled avec `reduce_motion`.

---

## QA Test Cases

**AC-CAM-70 (tilt × 0.25)** — Logic

- Given : `InputManager.reduce_motion = true` (mock), Player WallRunning avec `wall_normal = Vector3(-1, 0, 0)` (wall_side = +1), `_camera_effects.rotation.z = 0`
- When : 30 frames `_process(1.0/60.0)` (t=500ms, largement au-delà de t_95)
- Then : `_camera_effects.rotation.z` converge vers ≈ `0.35 * 1 * 0.25 = 0.0875` rad, tolérance ±0.005
- Edge cases : toggle `reduce_motion` false → true mid-wall-run → lerp adapte vers nouveau target 0.0875 smoothément ; `reduce_motion = false` → back to 0.35 target (baseline Story 005)

**AC-CAM-71 (FOV kick × 0.5)** — Logic

- Given : `reduce_motion = true`, `player.is_dashing = false`, `_camera3d.fov = 90.0`
- When : `player.is_dashing = true` ; 30 frames `_process(1.0/60.0)`
- Then : `_camera3d.fov` converge vers ≈ `90.0 + 10.0 * 0.5 = 95.0`, tolérance ±0.2
- Edge cases : `reduce_motion` toggle mid-dash → lerp adapte ; `reduce_motion = false` → back to 100 target

**AC-CAM-72 (shake × 0)** — Logic

- Given : `reduce_motion = true`, `_shake_offset = Vector3.ZERO`
- When : `add_shake_roll(0.05)` appelé ; puis `player.wall_jumped.emit(Vector3(1,0,0), Vector3(10,10,0))` (trigger indirect via handler)
- Then : `_shake_offset == Vector3.ZERO` après l'appel et après le signal ; `_camera3d.rotation == Vector3.ZERO`
- Edge cases : `reduce_motion = false` après injection d'un shake → le shake initial pré-toggle continue son decay naturel (pas reset immédiat — acceptable, le gate est sur injection, pas decay)

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/camera/story-010-reduce-motion-gate_test.gd` — AC-CAM-70/71/72 via mock `InputManager.reduce_motion` + assertions sur chaque effet

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : Story 005 (tilt handler), Story 006 (FOV handler), Story 007 (shake injection point)
- Unlocks : Future Accessibility Settings menu (UI exposition), Polish/Accessibility review sign-off
