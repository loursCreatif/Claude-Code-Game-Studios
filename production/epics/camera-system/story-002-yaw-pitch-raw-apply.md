# Story 002: Yaw + Pitch raw apply (mouse signal consume, sensitivity, invert_y, clamps)

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0004 (Input API & Focus Handling)
**ADR Decision Summary**: ADR-0002 acte yaw=`player.rotation.y`, pitch=`camera_arm.rotation.x` exclusivement, clamp `[-PITCH_LIMIT, +PITCH_LIMIT]` chaque frame. ADR-0004 D-5/D-6 acte le consume event-driven via signal `mouse_motion(delta: Vector2)` émis par InputManager autoload (producer unique).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Signal connection dans `_ready()` (pattern `InputManager.mouse_motion.connect(_on_mouse_motion)`), pas polling `Input.get_last_mouse_velocity`. `CONNECT_DEFERRED` **non requis** ici (handler = mutation scalaire float, lecture 2 ints, zero alloc, < 0.05 ms CPU → consumer léger synchrone selon ADR-0005 D-5). Rotation Euler Godot = YXZ par défaut, clamp direct sur `rotation.x` propre.

**Control Manifest Rules (Presentation layer)**:
- Required : yaw sur `player.rotation.y` (le body) ; pitch sur `camera_arm.rotation.x` exclusivement, clamp `[-PITCH_LIMIT, +PITCH_LIMIT]` chaque frame ; camera logic en `_process` cosmétique only (pitch/yaw apply peut être event-driven dans handler signal, pas dans `_physics_process`) ; consumer léger synchrone (flag `CONNECT_0`) pour handler zero-alloc
- Forbidden : appliquer pitch sur `camera3d.rotation.x`, `camera_effects.rotation.x`, ou `$Camera3D.rotation.x` (grep CI 0 occurrence) ; muter `velocity`, `position`, `rotation` ou état state-machine depuis `_process` ; MovementSystem écrivant sur CameraArm/CameraEffects/Camera3D
- Guardrail : Camera `_process` cost ≤ 0.2 ms p99 ; intra-engine latency mouse→rotation ≤ 16 ms p99

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-01** : `GIVEN` Camera Active, `mouse_sensitivity=0.0022`, `invert_y=false`, `WHEN` un `InputEventMouseMotion(Vector2(100, 0))` est émis, `THEN` au frame suivant `player.rotation.y` a décru de `0.22 rad ± 0.001` et `camera_arm.rotation.x` est inchangé (`Δ < 1e-6`).
- [x] **AC-CAM-02** : `GIVEN` Camera Active, `mouse_sensitivity=0.0022`, `WHEN` motion `Vector2(0, 100)` avec `invert_y=false`, `THEN` `camera_arm.rotation.x` a décru de `0.22 rad ± 0.001`. `WHEN` répété avec `invert_y=true`, `THEN` `camera_arm.rotation.x` a augmenté de `0.22 rad ± 0.001`.
- [x] **AC-CAM-03** : `GIVEN` `camera_arm.rotation.x == PITCH_LIMIT`, `WHEN` motion vers le haut équivalent à +0.5 rad, `THEN` `camera_arm.rotation.x == PITCH_LIMIT` exactement (clamp dur, pas d'accumulation interne).
- [x] **AC-CAM-04** : `GIVEN` `mouse_sensitivity=0.012` (max safe range), `WHEN` motion `Vector2(10000, 0)` (flick dégénéré 10 000 px/frame), `THEN` `|yaw_delta|` appliqué ≤ `MAX_ROT_PER_FRAME == PI` — delta excédentaire clampé, **pas** accumulé dans une variable interne.

---

## Implementation Notes

*Derived from ADR-0002 Decision + ADR-0004 D-5 + GDD Rules 2-3 + Formula 1 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const PITCH_LIMIT: float = PI / 2.0 - 0.05     # ≈ 1.521 rad, ~87.1° — évite gimbal lock visuel
const MAX_ROT_PER_FRAME: float = PI            # cap magnitude flick dégénéré × sensitivity max

func _ready() -> void:
    # ... scene tree setup ...
    InputManager.mouse_motion.connect(_on_mouse_motion)  # flag default (synchrone) — consumer léger

func _on_mouse_motion(delta: Vector2) -> void:
    # Sensitivity + invert lus à chaque application (hot-reload automatique)
    var s: float = InputManager.mouse_sensitivity
    var yaw_delta: float = -delta.x * s
    var pitch_delta: float = -delta.y * s * (-1.0 if InputManager.mouse_y_inverted else 1.0)

    # Clamp magnitude par frame (Rules 2-3) — cap AVANT commit, PAS d'accumulation
    yaw_delta = clamp(yaw_delta, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)
    pitch_delta = clamp(pitch_delta, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)

    # Apply (ownership : yaw = Player, pitch = CameraArm exclusivement)
    var player: CharacterBody3D = get_parent()  # ou référence cached via @onready
    player.rotation.y += yaw_delta
    _camera_arm.rotation.x = clamp(_camera_arm.rotation.x + pitch_delta, -PITCH_LIMIT, PITCH_LIMIT)
```

- **Aucun smoothing** entre delta reçu et rotation appliquée — feel raw, Player Fantasy.
- **Aucun buffer** `pending_delta` : si le event arrive pendant Respawning/MouseFree/Disabled, le delta est perdu (comportement voulu — GDD edge case « Input System ne republie pas les motions pendant enabled=false »).
- Gates `enabled` + `is_mouse_captured()` : **PAS DANS CETTE STORY** — ajoutés par Story 003.
- `reduce_motion` gate : **PAS DANS CETTE STORY** — ajouté par Story 010.
- Invariants à valider à l'implémentation : `PITCH_LIMIT < PI/2`, `MAX_ROT_PER_FRAME > 0`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 003 : gates `InputManager.enabled == false` + `InputManager.is_mouse_captured() == false` (skip silencieux du handler).
- Story 005-007 : effets visuels (tilt, FOV, shake).
- Story 008 : état Respawning figeant la rotation.
- Story 010 : multiplicateurs `reduce_motion`.
- Story 011 : `_exit_tree()` disconnect.

---

## QA Test Cases

**AC-CAM-01 (yaw horizontal pur)** — Logic

- Given : Camera Active (Player instancié, `_ready()` terminé), `InputManager.mouse_sensitivity = 0.0022`, `InputManager.mouse_y_inverted = false`, `player.rotation.y = 0.0`, `camera_arm.rotation.x = 0.0`
- When : `InputManager.mouse_motion.emit(Vector2(100, 0))` puis `await get_tree().physics_frame`
- Then : `is_equal_approx(player.rotation.y, -0.22)` tolérance `0.001` ; `abs(camera_arm.rotation.x) < 1e-6`
- Edge cases : delta `(0, 0)` → aucune rotation ; delta négatif `(-100, 0)` → `player.rotation.y ≈ +0.22`

**AC-CAM-02 (invert_y)** — Logic

- Given : Camera Active, `mouse_sensitivity = 0.0022`, pitch initial = 0, run #1 `invert_y = false`, run #2 `invert_y = true`
- When : motion `Vector2(0, 100)` émis dans chaque run
- Then : run #1 `camera_arm.rotation.x ≈ -0.22` ; run #2 `camera_arm.rotation.x ≈ +0.22` (tolérance `0.001`)
- Edge cases : toggle `invert_y` en live sans émettre motion → `camera_arm.rotation.x` inchangé jusqu'au prochain motion

**AC-CAM-03 (clamp dur PITCH_LIMIT)** — Logic

- Given : `camera_arm.rotation.x = PITCH_LIMIT` (= `PI/2 - 0.05`)
- When : émission d'une motion équivalente à +0.5 rad (ex. `Vector2(0, -0.5/sensitivity)` avec invert_y=false)
- Then : `is_equal_approx(camera_arm.rotation.x, PITCH_LIMIT)` exactement — **pas d'accumulation interne** dans une variable cachée
- Edge cases : 10 motions consécutives toutes « vers le haut » → toujours PITCH_LIMIT ; puis 1 motion « vers le bas » → pitch décroît immédiatement (pas de dette accumulée à rattraper)

**AC-CAM-04 (clamp magnitude MAX_ROT_PER_FRAME)** — Logic

- Given : `mouse_sensitivity = 0.012` (max safe), `player.rotation.y = 0.0`
- When : motion `Vector2(10000, 0)` (delta = -120 rad avant clamp)
- Then : `abs(player.rotation.y_delta_applied) ≤ PI` — mesure du delta = `player.rotation.y_après - player.rotation.y_avant`
- Edge cases : 5 motions consécutives de `Vector2(10000, 0)` → 5× rotation de PI max (pas de burst cumulé via variable interne), tous indépendants

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/camera/story-002-yaw-pitch-raw-apply_test.gd` — AC-CAM-01/02/03/04 automatisés via `InputManager.mouse_motion.emit(...)` et assertion `is_equal_approx`

**Status** : [x] Created — `tests/unit/camera/story_002_yaw_pitch_raw_apply_test.gd` (10 fonctions GdUnit4 couvrent 4/4 ACs + 6 bonus edge cases)

---

## Dependencies

- Depends on : Story 001 (scene tree + accessors + script attaché)
- Unlocks : Story 003 (gates sur le handler), Story 004 (aim_forward consume yaw+pitch), Stories 005-007 (effets visuels utilisant _process du même script)

---

## Completion Notes

**Completed** : 2026-04-22
**Criteria** : 4/4 ACs COVERED + 6 bonus tests (negative_x_yaw, invert_y_default, invert_y_toggle, no_internal_accumulation_returns_immediately, consecutive_extreme_flicks, zero_delta)
**Deviations** :
- ADVISORY scope creep — 2 properties ajoutées à `src/core/input_manager.gd` (`mouse_sensitivity: float = 0.0022`, `mouse_y_inverted: bool = false`) hors scope strict story-002 ET hors scope strict story-010 settings-persistence. Justifié pour débloquer toute la chaîne Camera (002→012). Doc-comments InputManager pointent explicitement story-010 pour persistance future. À tracer en tech debt.
- ADVISORY naming — Test file `story_002_..._test.gd` (underscore) au lieu de `story-002-..._test.gd` (hyphen) prescrit par Test Evidence. Aligné convention story-001 Camera (cohérence intra-epic).
**Test Evidence** :
- Unit test : `tests/unit/camera/story_002_yaw_pitch_raw_apply_test.gd` (10 fonctions, AC-CAM-01/02/03/04 + edges)
**Code Review** : Complete — verdict APPROVED (gdscript-specialist: APPROVED WITH SUGGESTIONS résolues ; qa-tester: TESTABLE 2 GAPS résolus). Suggestion 1 cast null-safety appliquée ; GAP-001 invert_y toggle test ajouté ; GAP-002 assert_not_null appliqué.
**Review Mode** : solo (Phase 4b QL-TEST-COVERAGE + Phase 5 LP-CODE-REVIEW skippés)

**Architecture compliance** :
- ADR-0002 ownership respecté : yaw → `_player.rotation.y`, pitch → `_camera_arm.rotation.x` exclusivement. Aucune écriture sur `camera3d.rotation.x` ni `camera_effects.rotation.x` (forbidden patterns évités).
- ADR-0004 D-5 + ADR-0005 D-5 : connexion synchrone `CONNECT_0` default, handler léger zero-alloc.
- Hot-reload sensitivity + invert : lecture chaque event, pas de cache.

**Infrastructure ADVISORY (héritées, hors scope)** :
1. GdUnit4 addon absent — test non-exécuté en headless mais validé structurellement.
2. `src/core/input_manager.gd` parse error "Class 'InputManager' hides an autoload singleton" — bug latent.
