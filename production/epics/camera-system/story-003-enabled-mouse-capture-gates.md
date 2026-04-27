# Story 003: Enabled + is_mouse_captured() gates sur handler mouse_motion

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004 (Input API & Focus Handling)
**ADR Decision Summary**: ADR-0004 D-4 acte le pattern refcount `request_disable(owner)` / `release_enable_request(owner)` ; `InputManager.enabled` reste read-only dérivé de `_enable_blockers.is_empty()`. ADR-0004 D-1 acte `InputManager.is_mouse_captured()` comme contrat MouseFree (menu open sans pause global) — Camera doit gate.

**Engine**: Godot 4.6 | **Risk**: MEDIUM (dual-focus 4.6 advisory VR-3 consumer-side)
**Engine Notes**: Les deux gates (`enabled`, `is_mouse_captured()`) sont redondants pour certains états (Menu open = both false) mais orthogonaux pour MouseFree standalone (main menu pré-capture). La règle : skip silencieux — pas de warning, pas d'exception. Le comportement « Paused figement tilt/FOV courants » (GDD state table) relève des stories 005-006 (effets), pas de cette story qui ne gère que le gate du handler mouse.

**Control Manifest Rules (Presentation layer)**:
- Required : camera logic en `_process` cosmétique only ; InputManager `enabled` lu read-only ; `InputManager.is_mouse_captured()` gate avant apply (contrat Input GDD Rule 15)
- Forbidden : écrire `InputManager._enabled` direct ; appeler `InputManager.set_enabled(bool)` (supprimé) ; buffer `pending_delta` pour rejouer après transition disabled→enabled
- Guardrail : zéro allocation dans le handler skip path (early return)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-60** : `GIVEN` `InputManager.enabled == false`, `WHEN` `mouse_motion` émis (via API test), `THEN` ni `player.rotation.y` ni `camera_arm.rotation.x` ne bougent ; tilt/FOV courants figés (ne reviennent **pas** à 0 — autre story, mais vérifier pas de side-effect reset ici).
- [x] **AC-CAM-61** : `GIVEN` `InputManager.enabled` passe `false → true`, `WHEN` premier motion reçu post-transition, `THEN` rotation appliquée normalement sans saut visuel cumulé (pas de buffer d'events disabled — comportement GDD edge case « Input System ne republie pas les motions pendant enabled=false »).
- [x] **AC-CAM-62** : `GIVEN` `InputManager.is_mouse_captured() == false` (MouseFree, menu open), `WHEN` `mouse_motion` émis, `THEN` Camera ignore silencieusement — aucune rotation (GDD Rule 15 gate).

---

## Implementation Notes

*Derived from GDD Rule 15 + ADR-0004 D-4 :*

Modifier `_on_mouse_motion` dans `src/gameplay/camera/camera_system.gd` :

```gdscript
func _on_mouse_motion(delta: Vector2) -> void:
    # Gate #1 (Rule 15) : mouse captured requis
    if not InputManager.is_mouse_captured():
        return
    # Gate #2 : InputManager enabled (pause, respawn, cutscene)
    if not InputManager.enabled:
        return

    # (reste du handler — Story 002 code)
    var s: float = InputManager.mouse_sensitivity
    # ...
```

- **Ordre des gates** : `is_mouse_captured()` en premier (état OS/window-level), puis `enabled` (état logique InputManager). L'ordre est indifférent pour correctness — seulement pour lisibilité de diagnostic.
- **Aucun warning log** sur skip : pas de `push_warning` — le skip est normal en gameplay (menu open = 60× skip/sec × temps menu).
- **Aucun buffer** : pas de stockage du `delta` skippé. Au retour en enabled, seuls les events futurs sont appliqués.
- Test AC-CAM-60 vérifie que les effets visuels en cours (tilt, FOV, shake) **ne sont pas reset** par le passage disabled (leur propre logique d'entretien reste en `_process`, gérée par Stories 005-007 — cette story ne les touche pas).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Stories 005-007 : figement tilt/FOV/shake courants en Paused (comportement visuel, handlers `_process` séparés).
- Story 008 : état Respawning figeant rotation + overlay (handler `died` différent, pas ce gate).
- Story 011 : `_exit_tree()` disconnect symétrique.

---

## QA Test Cases

**AC-CAM-60 (gate enabled)** — Logic

- Given : Camera Active, `player.rotation.y = 0.5`, `camera_arm.rotation.x = 0.3`, `camera_effects.rotation.z = 0.2` (tilt en cours), `camera3d.fov = 95.0` (FOV en transition) ; puis `InputManager.request_disable(owner)` appelé → `enabled == false`
- When : `InputManager.mouse_motion.emit(Vector2(100, 100))`
- Then : `player.rotation.y == 0.5` inchangé ; `camera_arm.rotation.x == 0.3` inchangé ; effets courants `camera_effects.rotation.z` et `camera3d.fov` **non reset à 0** (le cas échéant, lerp continu en `_process` fait leur drift normal — acceptable, pas ce test)
- Edge cases : toggle disable→enable→disable rapide sans émettre motion → rotations inchangées ; multiple owners calling `request_disable` successivement → ignoré tous

**AC-CAM-61 (pas de buffer transitoire)** — Logic

- Given : `enabled == false` pendant 500 ms, 10 events `mouse_motion` émis pendant (Input en réalité ne les republie pas, mais test via API direct), puis `release_enable_request(owner)` → `enabled == true`
- When : un premier motion `Vector2(50, 0)` émis après la transition
- Then : `player.rotation.y` rotation de `-50 * sensitivity` exactement (pas cumulé avec les 10 events skippés)
- Edge cases : aucun buffer à draîner ; re-enable sans motion = pas de rotation fantôme

**AC-CAM-62 (gate is_mouse_captured)** — Integration

- Given : Camera Active, `InputManager.enabled == true`, mais `Input.mouse_mode = Input.MOUSE_MODE_VISIBLE` (→ `is_mouse_captured() == false`) simulé via test fixture
- When : `InputManager.mouse_motion.emit(Vector2(100, 0))`
- Then : `player.rotation.y` inchangé ; `camera_arm.rotation.x` inchangé
- Edge cases : transition `MOUSE_MODE_CAPTURED` ↔ `MOUSE_MODE_VISIBLE` au milieu d'une séquence d'events → chaque event gated indépendamment sur l'état courant

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/camera/story-003-enabled-mouse-capture-gates_test.gd` — AC-CAM-60/61/62 automatisés (mock `InputManager.is_mouse_captured()` + `request_disable/release_enable_request`)

**Status** : [x] Implemented — `tests/unit/camera/story_003_enabled_mouse_capture_gates_test.gd` (264 lignes, 7 fonctions GdUnit4)

---

## Dependencies

- Depends on : Story 002 (`_on_mouse_motion` handler existe)
- Unlocks : Story 008 (Respawning réutilise le pattern skip via `InputManager.request_disable`), Story 011 (disconnect symétrique au `_exit_tree`)

---

## Completion Notes

**Completed** : 2026-04-23
**Criteria** : 3/3 passing (AC-CAM-60, AC-CAM-61, AC-CAM-62 tous COVERED via 7 fonctions test GdUnit4 incluant edge cases + bonus dual-gate)
**Verdict** : COMPLETE WITH NOTES

**Files modifiés** :
- `src/gameplay/camera/camera_system.gd` — 2 early-return gates dans `_on_mouse_motion` : `is_mouse_captured()` (GDD Rule 15) en premier pour lisibilité diagnostic, `InputManager.enabled` (ADR-0004 D-4) en second. Skip silencieux zéro-alloc, pas de buffer `pending_delta`, pas de `push_warning`.

**Files créés** :
- `tests/unit/camera/story_003_enabled_mouse_capture_gates_test.gd` (264 lignes, 7 tests) — couvre AC-CAM-60 (2 tests), AC-CAM-61 (2 tests), AC-CAM-62 (2 tests), + 1 bonus dual-gate spam. Drive `InputManager` via l'API canonique `set_mouse_captured()` / `request_disable()` / `release_enable_request()` (jamais write direct sur `_enabled`). `after_test()` cleanup défensif via `release_enable_request(self)` pour éviter la contamination entre tests (autoload partagé).

**Deviations (ADVISORY)** :
- Nommage fichier test : story spécifiait `story-003-enabled-mouse-capture-gates_test.gd` (tirets), implementation utilise `story_003_enabled_mouse_capture_gates_test.gd` (underscores). Conforme convention snake_case du projet (`.claude/docs/technical-preferences.md`). Non bloquant.
- TR-cam-003 (registry text : "Logique caméra en _process — Mouse motion event-driven via signal") est plus large que la story (gates). L'ADR-0004 D-1 + D-4 couvre explicitement les gates. Envisager ajout TR-cam-NNN dédié aux gates camera pour traçabilité fine.

**Test Evidence** : Logic — `tests/unit/camera/story_003_enabled_mouse_capture_gates_test.gd` ✓
**Code Review** : r1 CHANGES REQUIRED (2 BLOCKING `input_manager.gd` + 1 GAP test cleanup) → fixes inline → **r2 APPROVED WITH SUGGESTIONS** (2026-04-23, `/code-review` manuel post-closure, hors cycle solo skip). Fichiers impactés par les fixes : `src/core/input_manager.gd` (tree_exited dead-guard retiré + symétrie `_pressed_this_tick` ui_cancel/ui_confirm pré-gate), `tests/unit/camera/story_003_enabled_mouse_capture_gates_test.gd` (`after_test` défensif `release_enable_request`).
**Untested criteria** : Aucune (3/3 COVERED).
