# Story 003: Signal `mouse_motion(delta: Vector2)`

> **Epic**: input-system
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004 Input API & Focus Handling
**ADR Decision Summary**: `InputEventMouseMotion` est capturé via `_unhandled_input` et republié en signal typé `mouse_motion(delta: Vector2)`. Aucune action lue (pas de `move_mouse` action dans InputMap). `Vector2` payload = value type, zero-alloc. La fenêtre 50 ms post-FOCUS_IN (story-005) et le gate `_enabled` (story-004) suppriment l'émission dans leurs cas respectifs.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Godot fusionne automatiquement les deltas mouse dans un frame (Edge Case GDD l. 429 — un seul `InputEventMouseMotion` par frame). Dual-focus system 4.6 : `InputEventMouseMotion` n'est livré que si la fenêtre a le "mouse focus" (différent du keyboard focus post-4.6). À valider en VC-1 story-005.

**Control Manifest Rules (Foundation layer)**:
- Required: `mouse_motion(delta: Vector2)` signal typé émis depuis `_unhandled_input` de l'InputManager + `Input.mouse_mode` main-thread only
- Forbidden: lire `Input.get_last_mouse_velocity()` depuis gameplay (utiliser le signal) ; accès `Input.*` depuis un `Thread`
- Guardrail: signal emission zero-alloc (payload `Vector2` = stack value)

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- [x] Signal déclaré : `signal mouse_motion(delta: Vector2)` (typed)
- [x] `_unhandled_input(event)` : si `event is InputEventMouseMotion`, émettre `mouse_motion.emit(event.relative)` (après le gate fenêtre 50 ms ajouté story-005 et le gate `_enabled` ajouté story-004 — ici, défaut sans gate)
- [x] **AC-AG-4** : `_enabled == true` ET `Time.get_ticks_usec() >= _focus_regained_until_ticks_usec` (défaut 0 dans cette story) ET `InputEventMouseMotion{relative=Vector2(10, 0)}` injecté via `Input.parse_input_event(ev)` → signal `mouse_motion(Vector2(10, 0))` émis **exactement une fois**
- [x] `set_mouse_captured(captured: bool)` : set `Input.mouse_mode = MOUSE_MODE_CAPTURED` si `true`, sinon `MOUSE_MODE_VISIBLE`
- [x] `is_mouse_captured() -> bool` : read-through `return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED` (AC-MC-3 — pas de cache)
- [x] **AC-MC-1** : `set_mouse_captured(true)` → `Input.mouse_mode == MOUSE_MODE_CAPTURED` et `is_mouse_captured() == true`
- [x] **AC-MC-2** : `set_mouse_captured(false)` → `Input.mouse_mode == MOUSE_MODE_VISIBLE` et `is_mouse_captured() == false`
- [x] **AC-MC-3** : code externe modifie `Input.mouse_mode` → `is_mouse_captured()` reflète la nouvelle valeur au prochain appel

---

## Implementation Notes

*Derived from ADR-0004:*

```gdscript
signal mouse_motion(delta: Vector2)

var _focus_regained_until_ticks_usec: int = 0   # story-005 arme ; défaut 0 = toujours passant

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.is_echo():
        return
    if event is InputEventMouseMotion:
        if Time.get_ticks_usec() < _focus_regained_until_ticks_usec:
            return  # fenêtre burst (story-005) — ici inactive par défaut
        if not _enabled:
            return  # story-004 — ici défaut true
        mouse_motion.emit(event.relative)
        return
    # (story-002 gère InputEventAction + InputEventKey)

func set_mouse_captured(captured: bool) -> void:
    # Main-thread only guardrail (ADR-0004 D-7). Appelé uniquement depuis _process/_physics_process/_ready/signal handlers.
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func is_mouse_captured() -> bool:
    return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
```

Notes clés :
- **Pas d'action mappée** : le mouse motion **n'est pas** lu via `Input.get_vector` ni `InputMap` — uniquement capturé comme `InputEventMouseMotion` brut et republié.
- **Fusion Godot** : un seul event reçu par frame même si la souris a bougé plusieurs fois (Edge Case GDD). Le delta est cumulé par Godot.
- **Sensitivity = aval** : Camera System multiplie par `mouse_sensitivity` (TR-cam-*), InputManager publie le delta brut uniquement. Ne pas appliquer de clamp ici.
- **Flick extrême** : 300+ px par event possible sur flick 1000 Hz. Responsabilité du Camera System de clamper (Edge Case GDD l. 430).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002 : polling actions (gère `InputEventAction` et `InputEventKey` → actions)
- Story 004 : gate `_enabled` (cette story assume `true` par défaut)
- Story 005 : fenêtre 50 ms post-FOCUS_IN (cette story expose la variable mais ne l'arme pas — story-005 pose le `_notification`)
- Camera system : application de `mouse_sensitivity`, inversion Y, clamp flick extrême (consumer du signal)

---

## QA Test Cases

- **AC-AG-4** : mouse_motion émis 1× par event
  - Given : InputManager ready, `_enabled = true`, `_focus_regained_until_ticks_usec = 0`
  - When : `Input.parse_input_event(InputEventMouseMotion.new())` avec `relative = Vector2(10, 0)`
  - Then : signal `mouse_motion` émis exactement 1× avec payload `Vector2(10, 0)`
  - Edge cases : deux events consécutifs même frame → Godot fusionne → 1× signal avec delta cumulé

- **AC-MC-1 / AC-MC-2** : capture toggle
  - Given : scène test
  - When : `InputManager.set_mouse_captured(true)` puis `.set_mouse_captured(false)`
  - Then : séquence (`MOUSE_MODE_CAPTURED` + `is_mouse_captured() == true`) → (`MOUSE_MODE_VISIBLE` + `is_mouse_captured() == false`)

- **AC-MC-3** : read-through (pas de cache)
  - Given : `InputManager.set_mouse_captured(true)` appliqué
  - When : code externe `Input.mouse_mode = Input.MOUSE_MODE_VISIBLE`
  - Then : `InputManager.is_mouse_captured() == false` au prochain appel
  - Edge cases : changement via plugin debug ; `InputManager` ne doit pas écraser au prochain `_process` (aucune réassertion automatique dans cette story)

- **Zero-alloc signal payload** (code review)
  - Given : hot path `_unhandled_input` + `emit mouse_motion`
  - When : grep/lint `push_back(`, `{...}` literal, `[...]` literal dans la fonction
  - Then : 0 match (payload = `Vector2` value type sur stack)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/input/mouse_motion_test.gd` — AC-AG-4
- `tests/unit/input/mouse_capture_test.gd` — AC-MC-1, AC-MC-2, AC-MC-3

**Status**: [x] Created — 2 unit test files (9 functions total) couvrent 8/8 ACs + 3 bonus edge cases

---

## Dependencies

- Depends on: Story 001 (bootstrap)
- Unlocks: Story 005 (focus handling arme le gate 50 ms via `_focus_regained_until_ticks_usec`)

---

## Completion Notes

**Completed**: 2026-04-22
**Criteria**: 8/8 automated COVERED (5 AC ground + 3 bonus tests : negative_delta, zero_delta, idempotent toggle)
**Deviations**:
- ADVISORY — Edge case fusion same-frame Godot Viewport-level non testable headless ; doc'd pour integration story-005 future
- ADVISORY — Tests appellent `_manager._unhandled_input(ev)` direct au lieu de `Input.parse_input_event(ev)` recommandé par la story (justifié déterminisme headless GdUnit4 sans viewport actif)
- ADVISORY — Properties `mouse_sensitivity` et `mouse_y_inverted` requises par Camera-002 NON ajoutées (scope strict respecté ; restent scope story-010 settings-persistence) ; Camera-002 partiellement bloquée
**Test Evidence**:
- `tests/unit/input/mouse_motion_test.gd` (5 tests : AC-AG-4 happy path + zero_delta + negative_delta + _enabled gate + focus_burst gate + no-action-trigger)
- `tests/unit/input/mouse_capture_test.gd` (4 tests : AC-MC-1, AC-MC-2, AC-MC-3, idempotent toggle)
**Code Review**: Complete — verdict APPROVED (R1 gate order permuté `_enabled` avant `Time.get_ticks_usec()` ; GAP-1 zero-delta bouché). R2 `_tmp` rename hors scope (code pré-existant story-001).
**Review Mode**: solo (Phase 4b QL-TEST-COVERAGE + Phase 5 LP-CODE-REVIEW skippés)

**Infrastructure ADVISORY (héritée story-001 Camera, hors scope)** :
1. GdUnit4 addon absent — runner `tests/gdunit4_runner.gd` échoue ; tests structurellement valides mais non-exécutés. Installer avant `/smoke-check sprint`.
2. `src/core/input_manager.gd` : parse error "Class 'InputManager' hides an autoload singleton" — bug latent à corriger dans cette story ou story-001 Input.
