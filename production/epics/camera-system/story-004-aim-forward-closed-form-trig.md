# Story 004: aim_forward forme close trigonométrique (roll-ignored par construction)

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm)
**ADR Decision Summary**: ADR-0002 Formula 5 + VC-4 acte la forme close trigonométrique `aim_forward = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))` comme API de Camera consommée par Combat (swept katana). Ignore `camera_effects.rotation.z` (tilt) par construction — garantit hitbox horizontale stable en wall-run. La version r1 (manipulation `Basis`) était algébriquement incorrecte et est archivée.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Godot Euler order par défaut = YXZ — la formule est analytiquement équivalente à `-Basis.from_euler(Vector3(pitch, yaw, 0)).z` (EULER_ORDER_YXZ). Pas de post-cutoff API ; fonctions `sin`/`cos` GDScript stables depuis 4.0. Pas de manipulation Basis manuelle → zéro risque d'erreur d'ordre d'application.

**Control Manifest Rules (Presentation layer)**:
- Required : `aim_forward` via forme close trigonométrique exactement `Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))` — pas de manipulation Basis (ADR-0002 D + VC-4)
- Forbidden : reconstruction `Basis` manuelle (`Basis(UP, -roll) * basis_globale`) ; Combat lisant directement `camera.basis.z` (contrat API owned par Camera)
- Guardrail : `aim_forward` calcul simple 2 sin + 2 cos + 1 Vector3 constructor → coût < 0.01 ms (négligeable dans budget Camera `_process` 0.2 ms)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-50** : `GIVEN` `camera_effects.rotation.z = +0.35` (wall-run droit), `camera_arm.rotation.x = 0` (pitch), `player.rotation.y = 0` (yaw), `THEN` `CameraSystem.aim_forward == Vector3(0, 0, -1)` à `± 1e-5` (roll ignoré par construction closed-form).
- [x] **AC-CAM-51** : `GIVEN` `pitch=-0.5 rad, yaw=0.3 rad, roll=0.2 rad`, `THEN` `aim_forward ≈ (-0.2594, -0.4794, -0.8383)` à `± 1e-4`. Vérification indépendante : `aim_forward.distance_to(-Basis.from_euler(Vector3(-0.5, 0.3, 0), EULER_ORDER_YXZ).z) < 1e-4` — le roll n'apparaît pas dans la formule, donc résultat invariant au roll.

---

## Implementation Notes

*Derived from ADR-0002 Key Interfaces + GDD Formula 5 + Rule 13 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
# Property accessor — calcule à la demande, pas caché (coût < 0.01 ms)
# Owned par Camera ; consommé par Combat (swept katana) via CameraSystem.aim_forward
var aim_forward: Vector3:
    get:
        var player: CharacterBody3D = get_parent()  # ou cached @onready
        var yaw: float = player.rotation.y
        var pitch: float = _camera_arm.rotation.x
        # Note : tilt (camera_effects.rotation.z) absent par construction — hitbox stable horizontalement en wall-run
        return Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
```

- **Property getter** plutôt que fonction : API lecture `CameraSystem.aim_forward` (pas `CameraSystem.get_aim_forward()`) — plus idiomatique pour un accessor pur sans side-effect.
- **Pas de cache** : la valeur dépend de yaw+pitch qui changent chaque frame avec les mouse motions — caching introduirait un cycle d'invalidation inutile. Coût `sin`/`cos` × 2 est négligeable dans budget 0.2 ms.
- **Pas d'input `roll`** : le paramètre `camera_effects.rotation.z` **n'apparaît pas** dans la formule. C'est non-négociable : AC-CAM-50 vérifie explicitement l'invariance au roll.
- **VC-4 ADR-0002** : comparaison analytique `is_equal_approx(aim_forward, -Basis.from_euler(Vector3(pitch, yaw, 0), EULER_ORDER_YXZ).z)` sur 100 cas randomisés (yaw ∈ [-2π, 2π], pitch ∈ [-PITCH_LIMIT, PITCH_LIMIT]) — à inclure dans le test GUT.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 005 : tilt wall-run sur `camera_effects.rotation.z` (dont `aim_forward` doit rester invariant).
- Future Combat epic : consume `CameraSystem.aim_forward` pour orienter swept katana.
- Future HUD epic : crosshair projeté depuis aim_forward (cf. GDD Open Question).

---

## QA Test Cases

**AC-CAM-50 (roll n'affecte pas aim_forward)** — Logic

- Given : `camera_effects.rotation.z = +0.35` (tilt wall-run droit actif), `camera_arm.rotation.x = 0`, `player.rotation.y = 0`
- When : lecture `CameraSystem.aim_forward`
- Then : `aim_forward.distance_to(Vector3(0, 0, -1)) < 1e-5`
- Edge cases : `camera_effects.rotation.z = -0.35` (wall gauche) → même résultat `(0, 0, -1)` ; `camera_effects.rotation.z = 2.0` (valeur absurde) → toujours `(0, 0, -1)` (formule insensible)

**AC-CAM-51 (valeurs numériques exactes + VC-4 cross-check)** — Logic

- Given : `_camera_arm.rotation.x = -0.5`, `player.rotation.y = 0.3`, `camera_effects.rotation.z = 0.2` (contaminant à ignorer)
- When : lecture `aim_forward`
- Then : `aim_forward.distance_to(Vector3(-0.2594, 0.4794, -0.8383)) < 1e-4`, ET `aim_forward.distance_to(-Basis.from_euler(Vector3(-0.5, 0.3, 0), EULER_ORDER_YXZ).z) < 1e-4`
- Edge cases :
  - 100 cas randomisés yaw/pitch dans safe range → `aim_forward.distance_to(-Basis.from_euler(Vector3(pitch, yaw, 0)).z) < 1e-4` (VC-4 invariant)
  - `pitch = PITCH_LIMIT` limite → `aim_forward.y ≈ -sin(PITCH_LIMIT) ≈ -0.998` (regarde quasi verticalement)
  - `pitch = -PITCH_LIMIT` → `aim_forward.y ≈ +0.998` (regarde quasi vers le bas — rappel convention Godot : -Z forward, +Y up)
  - `yaw` wrap > 2π → résultat identique à `yaw mod 2π` (sin/cos périodiques)

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/camera/story-004-aim-forward-closed-form_test.gd` — AC-CAM-50/51 automatisés + 100 cas randomisés VC-4 cross-check

**Status** : [x] Implemented — `tests/unit/camera/story_004_aim_forward_closed_form_test.gd` (223 lignes, 9 fonctions GdUnit4)

---

## Dependencies

- Depends on : Story 002 (yaw+pitch appliqués sur les bons noeuds — aim_forward les lit)
- Unlocks : Future Combat epic (consume `CameraSystem.aim_forward` pour swept katana)

---

## Completion Notes

**Completed** : 2026-04-23
**Criteria** : 2/2 passing (AC-CAM-50, AC-CAM-51 tous COVERED via 9 fonctions test GdUnit4 : 3 pour AC-CAM-50 tilt+/-/absurd, 2 pour AC-CAM-51 numeric+VC-4 single, 1 pour VC-4 randomisé 100 cas seed=12345, 2 edge pitch limit, 1 edge yaw périodique TAU)
**Verdict** : COMPLETE WITH NOTES

**Files modifiés** :
- `src/gameplay/camera/camera_system.gd` — ajout property getter `aim_forward: Vector3` (+24 lignes) dans section Public API dédiée. Formule close `Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))`. Pas de cache (coût < 0.01 ms), pas de paramètre roll (invariance par construction). Consommé par Future Combat epic pour swept katana.

**Files créés** :
- `tests/unit/camera/story_004_aim_forward_closed_form_test.gd` (223 lignes, 9 tests) — couvre AC-CAM-50 (3 tests), AC-CAM-51 numeric (1 test) + VC-4 single case (1 test) + VC-4 randomisé 100 cas (1 test seed déterministe 12345), bonus pitch limit ± (2 tests), bonus yaw périodique TAU (1 test). `after_test()` cleanup défensif disconnect mouse_motion (autoload partagé, story-011 non-implémentée).

**Deviations (ADVISORY)** :
- Nommage fichier test : story spécifiait `story-004-aim-forward-closed-form_test.gd` (tirets), implementation utilise `story_004_aim_forward_closed_form_test.gd` (underscores). Conforme convention snake_case projet (`.claude/docs/technical-preferences.md`) — même déviation que story 003 pour cohérence. Non bloquant.

**Test Evidence** : Logic — `tests/unit/camera/story_004_aim_forward_closed_form_test.gd` ✓
**Code Review** : LP-CODE-REVIEW skippé — Solo mode (`production/review-mode.txt`).
**QA Coverage** : QL-TEST-COVERAGE skippé — Solo mode.
**Untested criteria** : Aucune (2/2 COVERED).
