# Story 007: Shake additif + wall_jump kick (sign_with_fallback, limit_length)

> **Epic**: Camera System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001` (shake sur camera3d ownership — couvert ADR-0002)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary**: ADR-0002 acte shake sur `camera3d.rotation` via **assignation** `camera3d.rotation = shake_offset` (pas `+=`) chaque frame — garantit reset implicite au-dessus de la transform CameraEffects. ADR-0005 D-2 fige signal canonique `wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)` ; D-3 payloads `Vector3` exclusivement ; D-7 consumer ne mute pas état Movement ; D-8 signal handler idempotent ; D-5 consumer synchrone iff léger — ici shake roll = assignation scalaire → flag default synchrone.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: `exp(-SHAKE_DECAY * delta)` stable GDScript ; `Vector3.limit_length(MAX_SHAKE_MAGNITUDE)` API standard. Pas de post-cutoff. Assignation `rotation = shake_offset` : `rotation` de `Camera3D` est un `Vector3` en Euler YXZ — assignation directe override totalement (pas cumul avec pitch/yaw appliqués ailleurs dans la chaîne, car ceux-ci vivent sur `CameraArm.rotation.x` et `player.rotation.y`, noeuds parents).

**Control Manifest Rules (Presentation layer + Core consumer)**:
- Required : shake additif via assignation `camera3d.rotation = shake_offset` (pas `+=`) ; consumer `CONNECT_0` synchrone pour handler léger
- Forbidden : additif via `camera3d.rotation += shake_offset` (drift visuel garanti — ADR-0002 Risk 3) ; payload non-Vector3/float (`allocating_signal_payload` forbidden) ; muter `player.velocity` depuis handler `wall_jumped` (`mutate_movement_state_from_signal_handler` forbidden)
- Guardrail : zero-alloc emit/handler ; shake `exp` decay retour < 5% en ~250 ms

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [ ] **AC-CAM-30** : `GIVEN` `CameraSystem.add_shake_roll(0.05)` appelé frame 0, `THEN` frame 1 : `shake_offset.z ≈ +0.05` ± décroissance 1 tick ; à `t=250 ms` : `|shake_offset.z| < 0.005 rad`.
- [ ] **AC-CAM-31** : `GIVEN` Movement émet `wall_jumped(wall_normal=Vector3(1,0,0), launch_velocity=Vector3(10,10,0))`, `THEN` Camera consume le signal (signature canon ADR-0005), appelle `add_shake_roll` avec signe dérivé de `sign_with_fallback(wall_normal.dot(-camera_arm.global_transform.basis.x))`, et `camera3d.rotation` final = `shake_offset` (pas d'addition `+=` sur la transform existante).
- [ ] **AC-CAM-32** : `GIVEN` 3 `add_shake_roll(0.05)` concurrents dans le même tick, `THEN` `shake_offset.length() ≤ MAX_SHAKE_MAGNITUDE == 0.2 rad` post-`limit_length()` — pas de cumul nauséeux non borné.

---

## Implementation Notes

*Derived from ADR-0002 Key Interfaces + GDD Rules 7-8 + Formula 4 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const SHAKE_DECAY: float = 12.0                       # /s — retour < 5% ~250 ms
const WALL_JUMP_KICK_MAGNITUDE: float = 0.05          # rad (~3°) — directionnel
const MAX_SHAKE_MAGNITUDE: float = 0.2                # rad (~11.5°) — cap cumul

var _shake_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
    # ... existing setup ...
    # Consumer léger synchrone (flag default) — handler = add scalaire + limit_length
    var player: CharacterBody3D = get_parent()
    player.wall_jumped.connect(_on_wall_jumped)

# API publique — consommée par VFX System en Feature layer post-MVP
func add_shake(offset_radians: Vector3) -> void:
    _shake_offset += offset_radians
    _shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)

func add_shake_roll(magnitude: float) -> void:
    add_shake(Vector3(0.0, 0.0, magnitude))

# Dérivation signe safe — dot == 0 exact (wall_normal ⊥ -basis.x) fallback +1 plutôt que 0
# (évite kick nul silencieux) — GDD Rule 7
func _sign_with_fallback(x: float) -> float:
    if x > 0.0:
        return 1.0
    elif x < 0.0:
        return -1.0
    else:
        return 1.0  # fallback

func _on_wall_jumped(wall_normal: Vector3, _launch_velocity: Vector3) -> void:
    # GDD Rule 7 : direction dérivée de wall_normal par rapport au forward caméra
    # (wall à gauche → kick vers la droite, wall à droite → kick vers la gauche)
    var dir: float = _sign_with_fallback(wall_normal.dot(-_camera_arm.global_transform.basis.x))
    add_shake_roll(WALL_JUMP_KICK_MAGNITUDE * dir)

func _process(delta: float) -> void:
    _update_tilt_wall_run(delta)          # Story 005
    _update_fov_dash(delta)                # Story 006
    _update_shake(delta)                   # this story

func _update_shake(delta: float) -> void:
    # Formula 4 : exp decay + limit_length + ASSIGNATION (pas += — Risk 3)
    _shake_offset *= exp(-SHAKE_DECAY * delta)
    _shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)
    _camera3d.rotation = _shake_offset  # ASSIGNATION — garantit reset implicite
```

- **API publique `add_shake` / `add_shake_roll`** : prête pour futurs consumers (VFX hit katana, boss impact). MVP : seul `_on_wall_jumped` l'appelle.
- **`_sign_with_fallback`** : alternative à `sign()` qui retourne 0 pour input 0. Nécessaire pour edge case GDD Rule 7 (wall_normal ⊥ basis.x exact — non pas reset kick silencieux).
- **Ordre `_process` effets** : shake **après** tilt + fov (convention : le shake s'applique par-dessus la transform « stable »). Dans l'implémentation, peu importe car shake vit sur `camera3d.rotation` (noeud enfant distinct), indépendant de tilt (`camera_effects.rotation.z`) et FOV (`camera3d.fov` — pas `rotation`).
- **Connexion signal synchrone** (`CONNECT_0` default, pas `CONNECT_DEFERRED`) : handler = 1 dot product + 1 sign + 1 add + 1 limit_length → < 0.05 ms, pas d'allocation, pas d'instanciation Node → consumer léger selon ADR-0005 D-5.
- **Zero-alloc** : `_shake_offset` est un `Vector3` value type, `*=` et `+=` sans allocation heap, `limit_length` retourne Vector3 stack. Respecte ADR-0005 VC-2 et Control Manifest zero-alloc.
- **Reduce_motion** : **PAS DANS CETTE STORY** — Story 010 ajoutera `shake_mult = 0.0 if reduce_motion` avant `add_shake_roll` (effectivement désactive le shake).
- **Respawn reset** : **PAS DANS CETTE STORY** — Story 008 ajoutera `_shake_offset = Vector3.ZERO` + `_camera3d.rotation = Vector3.ZERO` dans `respawned(position)` handler.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 008 : reset `_shake_offset = Vector3.ZERO` dans `respawned` handler.
- Story 010 : gate `reduce_motion` désactivant shake via `shake_mult = 0.0`.
- Story 011 : `_exit_tree()` disconnect `player.wall_jumped`.
- Future VFX Feedback System GDD : consumer appelant `add_shake()` pour hit katana, boss impact.

---

## QA Test Cases

**AC-CAM-30 (shake decay)** — Logic

- Given : `_shake_offset = Vector3.ZERO`, `_camera3d.rotation = Vector3.ZERO`
- When : frame 0 : `add_shake_roll(0.05)` ; loop `_process(1.0/60.0)` jusqu'à t=250ms (15 frames)
- Then : frame 1 : `_shake_offset.z ≈ 0.05 * exp(-12 * 1/60) ≈ 0.0490` ; frame 15 : `abs(_shake_offset.z) < 0.005`
- Edge cases : `add_shake_roll(0.0)` → aucun effet ; shake pendant `delta` élevé (freeze 100 ms) → decay plus agressif mais monotone décroissant

**AC-CAM-31 (wall_jumped consume + direction)** — Integration

- Given : Player à l'origine, `rotation.y = 0` (basis.x = Vector3(1,0,0), -basis.x = Vector3(-1,0,0)), `_shake_offset = Vector3.ZERO`
- When : `player.wall_jumped.emit(Vector3(1, 0, 0), Vector3(10, 10, 0))` (mur à gauche, normal pointe +x)
- Then : `wall_normal.dot(-basis.x) = 1 * -1 = -1` → `_sign_with_fallback(-1) = -1` → `add_shake_roll(-0.05)` → `_shake_offset.z ≈ -0.05` ; au frame suivant : `_camera3d.rotation == _shake_offset` (assignation, pas cumul)
- Edge cases :
  - `wall_jumped(Vector3(-1, 0, 0), ...)` (mur à droite) → direction `+1` → `_shake_offset.z ≈ +0.05`
  - `wall_jumped(Vector3(0, 0, 1), ...)` (mur en avant — dot avec -basis.x = 0) → fallback `+1` → `_shake_offset.z ≈ +0.05` (pas 0)
  - `camera3d.rotation` pré-existant `Vector3(0.1, 0.1, 0.1)` → overwritten à `_shake_offset` au frame suivant (assignation ≠ cumul)

**AC-CAM-32 (limit_length cap)** — Logic

- Given : `_shake_offset = Vector3.ZERO`
- When : 3× `add_shake_roll(0.05)` consécutifs même tick (aucun `_process` entre)
- Then : après injection, `_shake_offset.length() ≤ 0.2` (raw sum serait 0.15, sous le cap — test un scénario > cap : 10× `add_shake_roll(0.05)` → raw 0.5 → post `limit_length` exactement 0.2)
- Edge cases : `add_shake(Vector3(0.3, 0.3, 0.3))` (norme ≈ 0.52) seul → post limit exactement 0.2 ; mix roll + yaw `add_shake(Vector3(0, 0.15, 0.15))` → norme ≈ 0.212 → clamp à 0.2 dans la même direction

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-007-shake-wall-jump_test.gd` — AC-CAM-30/31/32 via émission `player.wall_jumped` + `add_shake_roll` + loop `_process` + assertions `_shake_offset` et `_camera3d.rotation`

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : Story 001 (scene tree Camera3D + CameraArm pour basis.x reference), Story 002 (_process + _ready setup)
- Unlocks : Story 008 (reset shake dans respawned), Story 010 (reduce_motion gate), Story 011 (_exit_tree disconnect wall_jumped), Future VFX epic (consumer API add_shake)
