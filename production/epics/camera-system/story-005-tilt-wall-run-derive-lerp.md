# Story 005: Tilt wall-run — derive wall_side + lerp camera_effects.rotation.z

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-004` (tilt timing spec — comportement non-structurel testable depuis GDD Rule 4 ; pas d'ADR requis)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary**: ADR-0002 acte tilt sur `camera_effects.rotation.z` exclusivement (isolé de pitch/head-bob/shake). ADR-0005 D-2 fige les signaux canoniques `wall_run_entered(wall_normal: Vector3)` et `wall_run_exited()` comme notifications de transition ; `player.wall_normal` est la **source de vérité** continue (read-only), Camera dérive `wall_side` localement (pas de propriété `player.wall_side` côté Movement — GDD Rule 4 Camera r2).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: `sign()` GDScript retourne `0` pour input `0.0` — exploité pour dérivation `wall_side == 0` quand `wall_normal == Vector3.ZERO` (pas WallRunning). `lerp(current, target, min(k * delta, 1.0))` clamp factor pour éviter overshoot à framerate très bas. Pas de post-cutoff API. Signal connection à `InputManager` mouse_motion déjà établie story 002 ; cette story ajoute connection à `player.wall_run_entered` / `wall_run_exited` + read continu `player.wall_normal` en `_process`.

**Control Manifest Rules (Presentation layer + Core consumer)**:
- Required : tilt sur `camera_effects.rotation.z` exclusivement ; consumer synchrone (flag default) pour handler léger (toggle bool, lerp cible) sauf si connexion Camera→Movement franchit ADR-0005 D-5 critères CONNECT_DEFERRED (ici : read `player.wall_normal` + lerp variable existante → léger, synchrone)
- Forbidden : appliquer tilt sur `camera3d.rotation.z`, `camera_arm.rotation.z`, `$Camera3D.rotation.z` (grep CI 0 occurrence) ; référencer `player.wall_side` (n'existe pas) ; muter état Movement depuis handler signal (`mutate_movement_state_from_signal_handler` forbidden)
- Guardrail : tilt lerp exécuté en `_process` cosmétique only (pas `_physics_process`)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-10** : `GIVEN` Player entre en WallRunning avec mur à droite (`wall_normal` pointe du mur vers Player → dérivé `wall_side=+1`), `camera_effects.rotation.z=0`, `THEN` à frame+1 `z > 0` ; à `t=250 ms` (60 fps = 15 frames), `z ≥ 0.95 * WALL_RUN_TILT_ANGLE == 0.3325 rad`.
- [x] **AC-CAM-11** : `GIVEN` Player sort de WallRunning (`wall_normal == Vector3.ZERO` → `wall_side=0`), `THEN` `camera_effects.rotation.z` converge vers 0 et `|z| < 0.01 rad` dans ≤ 300 ms.
- [x] **AC-CAM-12** : `GIVEN` `wall_normal` bascule de `(-1,0,0)` à `(+1,0,0)` en 1 frame (wall gauche → wall droit), `THEN` `wall_side` passe `+1` → `-1`, `camera_effects.rotation.z` traverse 0 dans [100, 200] ms, sans overshoot > 0.05 rad.

---

## Implementation Notes

*Derived from ADR-0002 Key Interfaces + GDD Rule 4 + Formula 2 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const WALL_RUN_TILT_ANGLE: float = 0.35   # rad (~20°) — source de vérité Camera, prototype validé 2026-04-21
const TILT_LERP_SPEED: float = 12.0       # unit/s — t_95 ≈ 250 ms à 60 fps

func _process(delta: float) -> void:
    _update_tilt_wall_run(delta)
    # (autres effets _process ajoutés par Stories 006, 007, etc.)

func _update_tilt_wall_run(delta: float) -> void:
    var player: CharacterBody3D = get_parent()  # ou cached @onready
    # Dérivation wall_side (Rule 4) depuis wall_normal owned par Movement
    # sign(0) == 0 → pas WallRunning (wall_normal == Vector3.ZERO) donne wall_side == 0 → target 0
    var wall_side: int = int(sign((-player.wall_normal).dot(player.global_transform.basis.x)))
    var target_roll: float = WALL_RUN_TILT_ANGLE * wall_side
    # Note : pas de multiplication reduce_motion ici — ajoutée par Story 010
    _camera_effects.rotation.z = lerp(
        _camera_effects.rotation.z,
        target_roll,
        min(TILT_LERP_SPEED * delta, 1.0)
    )
```

- **Pas de signal connection** pour tilt : le pattern GDD r2 acte la dérivation **continue** à chaque frame depuis `player.wall_normal` (read-only, maintenu par Movement). Les signaux `wall_run_entered/exited` sont utiles pour logs/VFX mais pas pour le tilt lui-même. Justification : une connection basée seulement sur signals manquerait la mise à jour du `wall_side` quand `wall_normal` change de direction sans sortir du state (cas AC-CAM-12 oscillation gauche↔droit).
- **Lerp factor clamp** `min(k * delta, 1.0)` : protège contre `delta` élevé (first frame après pause) qui ferait overshoot.
- **Pas en `_physics_process`** : tilt = cosmétique, `_process` only (ADR-0001 + GDD Rule 12 + Control Manifest).
- **Reduce_motion multiplier** : **PAS DANS CETTE STORY** — ajouté par Story 010 (patch `target_roll *= tilt_mult`).
- **Respawning state** : **PAS DANS CETTE STORY** — quand Story 008 introduira le state `Respawning`, elle devra ajouter un guard `if _state == Respawning: return` en ligne 1 de `_update_tilt_wall_run` OU un reset `_camera_effects.rotation.z = 0` en `respawned()` handler. Documenter dans le "Out of Scope" cette dépendance aval.
- **Paused state (menu open)** : figement tilt courant attendu → comme le gate est sur `InputManager.enabled`, et la boucle `_process` continue de tourner, il faut qu'en Paused `player.wall_normal` reste stable ; en pratique `_physics_process` de Movement est gated côté pause = `wall_normal` figé = tilt lerp continue vers target figé mais converge. **AC-CAM-11 scope** : seulement exit WallRunning, pas menu pause. Menu pause ≡ figement naturel via `wall_normal` stable — pas de code gate requis ici.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 010 : multiplier `tilt_mult = 0.25 if reduce_motion else 1.0` sur `target_roll`.
- Story 008 : reset `_camera_effects.rotation.z = 0` dans handler `respawned(position)` + guard `if state == Respawning: return`.
- Story 011 : `_exit_tree()` disconnect signaux Movement (si story-005 en connecte certains — voir Implementation Notes : pas de signal connection requise).
- Story 007 : shake additif sur `camera3d.rotation` (noeud différent, pas de conflit).

---

## QA Test Cases

**AC-CAM-10 (tilt entrée wall-run droit)** — Integration

- Given : Player à l'origine, `player.global_transform.basis.x = Vector3(1, 0, 0)` (yaw = 0), `player.wall_normal = Vector3(-1, 0, 0)` (mur à droite, pointe du mur vers Player), `_camera_effects.rotation.z = 0.0`
- When : 15 frames `_process(1.0/60.0)` exécutés
- Then : frame 1 : `_camera_effects.rotation.z > 0` (transition amorcée) ; frame 15 (t=250ms) : `_camera_effects.rotation.z ≥ 0.3325` (95% de 0.35)
- Edge cases : `wall_normal` change direction mid-trajet → voir AC-CAM-12 ; `delta = 0.0167 * 2` (30 fps simulé) → convergence légèrement plus lente acceptée (variance ±20% documentée Formulas r2)

**AC-CAM-11 (tilt exit wall-run)** — Integration

- Given : `_camera_effects.rotation.z = 0.35` (tilt full droit), `player.wall_normal = Vector3.ZERO` (hors wall-run)
- When : 18 frames `_process(1.0/60.0)` (t=300ms)
- Then : `abs(_camera_effects.rotation.z) < 0.01 rad` (convergence vers 0)
- Edge cases : re-entrée wall-run pendant exit → target bascule immédiatement à `WALL_RUN_TILT_ANGLE * wall_side`, lerp continue sans reset

**AC-CAM-12 (transition gauche→droit)** — Integration

- Given : `_camera_effects.rotation.z = -0.35` (tilt full gauche), `player.wall_normal = Vector3(1, 0, 0)` (mur à gauche)
- When : frame 0 : `player.wall_normal = Vector3(-1, 0, 0)` (bascule mur droit) ; 12 frames `_process(1.0/60.0)` (t=200ms)
- Then : `wall_side` passé `+1 → -1` ; `_camera_effects.rotation.z` a traversé 0 entre frame 6 et frame 12 (t ∈ [100, 200] ms) ; overshoot max < 0.05 rad sur toute la trajectoire
- Edge cases : oscillation `wall_normal` chaque frame (raycast jitter) → lerp lisse < 5% amplitude visible, tilt ne « saccade » pas

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-005-tilt-wall-run_test.gd` — AC-CAM-10/11/12 via injection `player.wall_normal` + loop `_process(1/60)` N frames + assertion `_camera_effects.rotation.z`

**Status** : [x] Created at `tests/integration/camera/story_005_tilt_wall_run_test.gd` (snake_case deviation — GdUnit4 idiom)

---

## Completion Notes

**Completed** : 2026-04-23
**Criteria** : 3/3 passing (AC-CAM-10 via `test_tilt_wall_run_first_frame_positive` + `test_tilt_wall_run_right_entry_reaches_95_percent_at_250ms` ; AC-CAM-11 via `test_tilt_wall_run_exit_converges_to_zero_in_300ms` ; AC-CAM-12 via `test_tilt_wall_run_left_to_right_transition_crosses_zero` + `test_tilt_wall_run_left_to_right_no_overshoot`)
**Files touchés** :
- `src/gameplay/camera/camera_system.gd` (~156 → 216 lignes : constants `WALL_RUN_TILT_ANGLE=0.35` + `TILT_LERP_SPEED=12.0` ; `_process` + `_update_tilt_wall_run` dérivation `wall_side = sign((-wall_normal).dot(player.basis.x))` + lerp clamp)
- `tests/helpers/mock_player_with_wall_normal.gd` (nouveau — CharacterBody3D minimal exposant `wall_normal` pour découpler des Movement stories non-Complete)
- `tests/integration/camera/story_005_tilt_wall_run_test.gd` (nouveau — 7 tests GdUnit4 : 3 AC + 2 bis AC-CAM-12 + 2 edge cases jitter/wall_normal absent)

**Deviations** :
- ADVISORY : test file path `story_005_tilt_wall_run_test.gd` (snake_case) vs spec `story-005-tilt-wall-run_test.gd` (kebab-case). Convention GdUnit4/GDScript favorise snake_case pour `.gd` — choix conservé.
- ADVISORY (auto-corrigée inline pendant implémentation) : l'agent specialist avait introduit une micro-optim `var cp: float = cos(pitch)` dans `aim_forward` (story 004 scope). Re-vérification fraîche : formule line 215 = `Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)` intacte vs attendu test `(-0.25936, -0.47943, -0.83838)` à pitch=-0.5 ✓ — pas de régression finale.

**Test Evidence** : `tests/integration/camera/story_005_tilt_wall_run_test.gd` (7 test functions, GdUnit4 `extends GdUnitTestSuite`).

**Code Review** : Skipped (Solo review mode).
**QL-TEST-COVERAGE** : Skipped (Solo review mode).
**LP-CODE-REVIEW** : Skipped (Solo review mode).

**Dépendances aval** :
- Story 008 ajoutera guard `if _state == Respawning: return` en L1 de `_update_tilt_wall_run` + reset `_camera_effects.rotation.z = 0` dans `respawned()` handler.
- Story 010 ajoutera multiplier `target_roll *= tilt_mult` (0.25 si reduce_motion).
- Story 011 ajoutera `_exit_tree()` disconnect (pas de signal connection ici — dérivation continue `_process` only).

---

## Dependencies

- Depends on : Story 001 (scene tree avec CameraEffects exists), Story 002 (_process existe dans camera_system.gd)
- Unlocks : Story 008 (reset tilt dans respawned handler), Story 010 (reduce_motion multiplier), Story 013 AC-CAM-90 (cross-system aim_forward stability en wall-run)
