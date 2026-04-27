# Story 006: FOV dash pulse — lerp camera3d.fov sur is_dashing

> **Epic**: Camera System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001` (FOV sur camera3d ownership — couvert ADR-0002)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary**: ADR-0002 acte FOV sur `camera3d.fov` (lerp `BASE_FOV ± DASH_FOV_KICK`). ADR-0005 D-2 fige le signal `dash_started(Vector3, float)` + `dash_ended()` + propriété read-only `player.is_dashing` comme source de vérité continue. Camera consume via read `player.is_dashing` chaque frame en `_process` (pattern dérivation continue — comme tilt story-005).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: `Camera3D.fov` : assignation frame-per-frame OK sur macOS Metal (validé prototype, GDD Edge Case #14). D3D12 Windows 4.6 : prototype encore à vérifier — flag MEDIUM. Pas de post-cutoff API. Valeur FOV en degrés (Godot convention).

**Control Manifest Rules (Presentation layer)**:
- Required : FOV sur `camera3d.fov` (via lerp BASE_FOV ± DASH_FOV_KICK) ; camera logic en `_process` cosmétique only
- Forbidden : muter `camera3d.fov` depuis `_physics_process` ou handler Movement signal directement (toujours via lerp target)
- Guardrail : Camera `_process` cost ≤ 0.2 ms p99

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [ ] **AC-CAM-20** : `GIVEN` `player.is_dashing == false` puis devient `true`, `THEN` `camera3d.fov` converge vers `BASE_FOV + DASH_FOV_KICK = 100°` ; à `t=150 ms`, `fov ≥ 98.5°`.
- [ ] **AC-CAM-21** : `GIVEN` `player.is_dashing == true` puis devient `false`, `THEN` `camera3d.fov` converge vers `BASE_FOV = 90°` et `|fov - 90| < 0.5°` dans ≤ 250 ms.

---

## Implementation Notes

*Derived from ADR-0002 Key Interfaces + GDD Rule 6 + Formula 3 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const BASE_FOV: float = 90.0                  # degrés — prototype validé
const DASH_FOV_KICK: float = 10.0             # degrés
const DASH_FOV_LERP_SPEED: float = 14.0       # unit/s — snap-in ease-out, attrape ~150 ms, relâche ~100 ms

func _ready() -> void:
    # ... existing setup ...
    _camera3d.fov = BASE_FOV  # initialisation explicite

func _process(delta: float) -> void:
    _update_tilt_wall_run(delta)   # Story 005
    _update_fov_dash(delta)         # this story
    # (autres _process effets ajoutés par Story 007 etc.)

func _update_fov_dash(delta: float) -> void:
    var player: CharacterBody3D = get_parent()  # ou cached @onready
    var target_fov: float = BASE_FOV + (DASH_FOV_KICK if player.is_dashing else 0.0)
    # Note : pas de multiplication reduce_motion ici — ajoutée par Story 010
    _camera3d.fov = lerp(
        _camera3d.fov,
        target_fov,
        min(DASH_FOV_LERP_SPEED * delta, 1.0)
    )
```

- **Pattern dérivation continue** depuis `player.is_dashing` — cohérent avec tilt story-005. Ne connecte **pas** à `dash_started` / `dash_ended` (signals) car la lerp cible dépend de l'état courant, pas de la transition. Si jamais le signal est manqué (ne devrait pas arriver, mais guard), le read continu corrigera au tick suivant.
- **Pas de cache** : `player.is_dashing` est une propriété read-only Movement (ADR-0005 D-10 contrat no-mutation depuis consumer), lue à coût nul.
- **Reduce_motion multiplier** : **PAS DANS CETTE STORY** — ajouté par Story 010 (`DASH_FOV_KICK * 0.5 if reduce_motion` → peak 95° au lieu de 100°).
- **Double dash** (Edge Case GDD) : dash #2 avant retour complet à `BASE_FOV` → `target_fov` repasse à 100, lerp reprend depuis valeur courante. **Kick absolute-target, pas additif.** Comportement voulu, pas de logique spéciale.
- **Respawn reset** : **PAS DANS CETTE STORY** — Story 008 ajoutera `_camera3d.fov = BASE_FOV` dans handler `respawned(position)`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 010 : multiplier `fov_kick_mult = 0.5 if reduce_motion else 1.0` sur `DASH_FOV_KICK`.
- Story 008 : reset `_camera3d.fov = BASE_FOV` dans `respawned(position)`.
- Story 012 : mesure perf `_process` incluant `_update_fov_dash`.
- Future Settings menu : FOV slider utilisateur (GDD Open Question, MVP « recommandé mais à acter Menu GDD »).

---

## QA Test Cases

**AC-CAM-20 (dash start → FOV up)** — Integration

- Given : `player.is_dashing = false`, `_camera3d.fov = 90.0`
- When : frame 0 : `player.is_dashing = true` ; 9 frames `_process(1.0/60.0)` (t=150ms)
- Then : `_camera3d.fov >= 98.5`
- Edge cases : dash déclenché en plein wall-run (tilt actif) → les deux effets coexistent sur noeuds différents (`_camera_effects.rotation.z` et `_camera3d.fov`), pas de conflit ; dash déclenché en Respawning → Story 008 gère le gate, pas ce test

**AC-CAM-21 (dash end → FOV down)** — Integration

- Given : `player.is_dashing = true`, `_camera3d.fov = 100.0`
- When : frame 0 : `player.is_dashing = false` ; 15 frames `_process(1.0/60.0)` (t=250ms)
- Then : `abs(_camera3d.fov - 90.0) < 0.5`
- Edge cases : double dash avant retour complet → target repasse à 100, lerp reprend sans « saut » ; `delta` variable 30-144 fps → variance ±20% documentée acceptable

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-006-fov-dash-pulse_test.gd` — AC-CAM-20/21 via toggle `player.is_dashing` + loop `_process(1/60)` N frames + assertion `_camera3d.fov`

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : Story 001 (scene tree Camera3D), Story 002 (_process existe)
- Unlocks : Story 008 (reset fov dans respawned), Story 010 (reduce_motion multiplier), Story 022 visuel AC-CAM-22 screenshot before/peak/after (relève d'une story Visual/Feel séparée post-MVP, hors scope ce epic)
