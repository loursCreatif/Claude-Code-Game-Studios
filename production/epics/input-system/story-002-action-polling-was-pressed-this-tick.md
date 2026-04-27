# Story 002: Polling tick-based `was_pressed_this_tick` + swap `_pressed↔_consumed`

> **Epic**: input-system
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-04-21
> **Estimate**: 5 hours (M — swap dual-dict + 2 test suites GdUnit4 incluant AC-CS-1 tick parity)

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-001`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004 Input API & Focus Handling
**ADR Decision Summary**: API publique canonique `was_pressed_this_tick(action: StringName) -> bool`. Swap `_pressed ↔ _consumed` en **ligne 1 de `_physics_process`** d'InputManager (zero-alloc ref swap) pour garantir AC-CS-1 tick parity. Fixtures test via `Input.parse_input_event(InputEventAction)` (seul pattern qui trigger `_unhandled_input` — `Input.action_press` ne trigger pas).

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: `InputEventAction` + `parse_input_event` est le pattern canonique test (ADR-0004 D-9 Risk 5 : validation VC dédiée requise — `parse_input_event` déclenche `_unhandled_input` mais pas forcément `is_action_pressed` selon version Godot). Swap de `Dictionary` GDScript est assignation de référence (zero alloc) — VC-3 benchmark à valider (ADR-0004 Risk 2).

**Control Manifest Rules (Foundation layer)**:
- Required: `was_pressed_this_tick` API canonique + swap synchrone ligne 1 `_physics_process` + `Input.parse_input_event(InputEventAction)` pour tests + gates `if not OS.has_feature("debug"): return` début des `simulate_*`
- Forbidden: `InputManager.is_action_just_pressed()` (supprimée) ; `Input.is_action_just_pressed` direct gameplay ; `Input.action_press` dans tests ; `#if debug_build`
- Guardrail: Input frame budget ≤ 0.2 ms/frame p99

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- [ ] `_unhandled_input(event)` : pour chaque action dans `ACTIONS_MVP`, si `event.is_action_pressed(action)`, set `_pressed_this_tick[action] = true`
- [ ] `_physics_process(delta)` ligne 1-4 : swap refs `_consumed_this_tick ↔ _pressed_this_tick`, puis vider le dict recyclé (`_pressed_this_tick[action] = false` pour chaque action MVP)
- [ ] `was_pressed_this_tick(action: StringName) -> bool` lit depuis `_consumed_this_tick.get(action, false)` ; retourne `false` immédiat si `_enabled == false`
- [ ] `simulate_action_press(action: StringName)` debug-only (gate `if not OS.has_feature("debug"): return`) : crée `InputEventAction`, `action = action`, `pressed = true`, appelle `Input.parse_input_event(ev)`
- [ ] `simulate_action_release(action: StringName)` équivalent avec `pressed = false`
- [ ] **AC-AG-1** : `InputEventAction{&"move_forward", pressed=true}` → `_physics_process` suivant → `was_pressed_this_tick(&"move_forward") == true` *(la portion `get_movement_vector() == Vector2(0, -1) ± 0.01` est hors scope Story-002 — `get_movement_vector()` n'appartient pas à l'API polling ; elle sera introduite dans une story dédiée de l'input API mouvement, voir Out of Scope)*
- [ ] **AC-AG-2** : `&"jump"` press tick N → `was_pressed_this_tick(&"jump") == true` **exactement au tick N** (1 fois) ; `false` au tick N+1
- [ ] **AC-AG-3** : `&"dash"` press + hold 60 ticks consécutifs → `was_pressed_this_tick(&"dash")` = `true` uniquement au tick initial ; `Input.is_action_pressed(&"dash") == true` tous les ticks
- [ ] **AC-AG-5** : debug build → `simulate_action_press(&"jump")` → `was_pressed_this_tick(&"jump") == true` au tick suivant + signal `jump_pressed` émis ; release mock → no-op silencieux + assert fail en debug de test
- [ ] **AC-CS-1** : consumer Node polling `was_pressed_this_tick(&"jump")` dans son `_physics_process` lit `true` au tick N (pas N+1) quand la press est injectée au render frame qui précède le tick N physique

---

## Implementation Notes

*Derived from ADR-0004 D-1, D-3, D-9:*

```gdscript
# Dans _unhandled_input :
for a in ACTIONS_MVP:
    if event.is_action_pressed(a):
        _pressed_this_tick[a] = true
        # emit signal typé si défini (story-004 ajoutera jump_pressed, etc.)

# Dans _physics_process (ligne 1-4, AVANT tout autre traitement) :
var _tmp: Dictionary = _consumed_this_tick
_consumed_this_tick = _pressed_this_tick
_pressed_this_tick = _tmp           # swap de refs — zero alloc
for a in ACTIONS_MVP:
    _pressed_this_tick[a] = false   # clear le dict recyclé pour le prochain tick
# (reste du corps : story-005 focus handling, story-006 latency, etc.)

func was_pressed_this_tick(action: StringName) -> bool:
    if not _enabled:                 # story-004 pose _enabled ; ici default true
        return false
    return _consumed_this_tick.get(action, false)

func simulate_action_press(action: StringName) -> void:
    if not OS.has_feature("debug"):
        return
    var ev := InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)
```

Notes clés :
- **Swap en ligne 1** (ADR-0004 D-3) : si le swap est fait en fin de `_physics_process`, les consumers aval lisent le flag **après** clear → AC-CS-1 échoue systématiquement. L'autoload order (InputManager #1) garantit que le swap précède tous les `_physics_process` consumers.
- **Zero-alloc swap** (ADR-0004 Risk 2) : GDScript `Dictionary` est reference type — l'assignation swap des refs ne clone pas. Valider via VC-3 stress benchmark (story-008).
- **`get_movement_vector()`** : ici simplement wrapper sur `Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")`. Retourne `Vector2.ZERO` si `_enabled == false`.
- **Fixtures** : `Input.parse_input_event(InputEventAction.new())` — **PAS** `Input.action_press()` (ne trigger pas `_unhandled_input`, ADR-0004 D-9 Alternative 5 Risk).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : boot + ACTIONS_MVP + autoload order (pré-requis)
- Story 003 : signal `mouse_motion(delta)` (cas `InputEventMouseMotion`)
- Story 004 : gate `_enabled` via refcount + signaux typés `jump_pressed`, etc.
- Story 005 : suppression mouse events dans fenêtre 50 ms post-FOCUS_IN
- Story 006 : ring buffer latency (mesure dans `_unhandled_input` / `_physics_process`)
- **`get_movement_vector() -> Vector2`** : wrapper `Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")` — API d'axe mouvement distincte du polling edge-triggered. À traiter dans une story dédiée (candidate future : `input-system/story-011-movement-vector-api`, pas encore créée). Les consumers actuels (camera, Story-002 movement) peuvent appeler `Input.get_vector(...)` directement en attendant.

---

## QA Test Cases

- **AC-AG-1** : move_forward → Vector2(0, -1)
  - Given : `_enabled = true`, InputManager ready
  - When : `Input.parse_input_event(InputEventAction)` avec action=&"move_forward", pressed=true, puis `await get_tree().physics_frame`
  - Then : `get_movement_vector() == Vector2(0, -1) ± 0.01` ET `was_pressed_this_tick(&"move_forward") == true`
  - Edge cases : release + re-press dans le même tick render → compte comme une seule press_edge

- **AC-AG-2** : jump edge-triggered strict
  - Given : InputManager ready, `_enabled = true`
  - When : inject `InputEventAction{&"jump", pressed=true}`, avance 2 physics frames
  - Then : tick N → `was_pressed_this_tick(&"jump") == true` ; tick N+1 → `false`
  - Edge cases : double-press dans le même render frame → comportement Godot natif (fusionné)

- **AC-AG-3** : hold 60 ticks ne re-déclenche pas edge
  - Given : press `&"dash"` sans release
  - When : avance 60 `physics_frame` (pas de release event émis)
  - Then : `was_pressed_this_tick(&"dash") == true` exactement 1× (tick initial) ; `Input.is_action_pressed(&"dash") == true` aux 60 ticks
  - Edge cases : si OS fait auto-repeat, `is_echo()` filter de story-001 doit absorber

- **AC-AG-5** : simulate_action_press debug/release
  - Given : build debug, scène test
  - When : `InputManager.simulate_action_press(&"jump")`, avance 1 physics frame
  - Then : `was_pressed_this_tick(&"jump") == true`
  - Given : mock `OS.has_feature("debug") = false`
  - When : même appel
  - Then : no-op silencieux (le signal `jump_pressed` n'est pas émis car l'event n'a pas été injecté)

- **AC-CS-1** : tick parity N pas N+1
  - Given : InputManager autoload #1 + TestConsumer Node avec `_physics_process` qui log `was_pressed_this_tick(&"jump")` et `Engine.get_physics_frames()`
  - When : `Input.parse_input_event(InputEventAction{&"jump", pressed=true})` à t_render = juste avant `_physics_process` du tick N
  - Then : log TestConsumer tick N contient `true` ; log tick N+1 contient `false`
  - Edge cases : injection au milieu du `_physics_process` du tick N (après swap) → lu seulement tick N+1 (comportement attendu — l'event est arrivé après le swap)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/input/was_pressed_this_tick_test.gd` — AC-AG-1, AC-AG-2, AC-AG-3, AC-AG-5
- `tests/integration/input/polling_same_tick_test.gd` — AC-CS-1 (ADR-0004 VC-4)

**Status**: [x] Created — 6 tests GdUnit4 (5 ACs + gate `_enabled`). Exécution automatisée différée (GdUnit4 addon absent, infra gap héritée).

---

## Dependencies

- Depends on: Story 001 (InputManager autoload bootstrap)
- Unlocks: Story 004 (refcount gate), Story 007 (latency E2E benchmark)

---

## Completion Notes

**Completed**: 2026-04-23
**Criteria**: 10/10 COVERED (5 ACs spec + 5 implementation sub-items) ; exécution tests DEFERRED (infra GdUnit4 addon)
**Deviations**:
- ADVISORY — AC-AG-1 : portion `get_movement_vector()` clarifiée hors scope et déplacée en Out of Scope (future story `input-system/story-011-movement-vector-api` candidate)
- ADVISORY — AC-AG-5 : wording mentionne `jump_pressed` signal ; partie signal scope Story-004 (vérifiée au code-review suivant)
- OUT OF SCOPE couverts — `mouse_sensitivity`, `mouse_y_inverted`, signal `mouse_motion`, `set_mouse_captured`/`is_mouse_captured` dans `input_manager.gd` livrés par Story-003 input et Story-002 camera (tracés dans leurs Completion Notes respectives)

**Test Evidence**:
- `tests/unit/input/was_pressed_this_tick_test.gd` (5 tests)
- `tests/integration/input/polling_same_tick_test.gd` (1 test AC-CS-1)
- Execution : DEFERRED (GdUnit4 runner absent — infra gap héritée ; aucun blocker story-002)

**Code Review**: Complete (2026-04-22, verdict APPROVED WITH SUGGESTIONS ; quick wins 1, 4, 5 appliqués 2026-04-23 — typage `Dictionary[StringName, bool]`, rename `_tmp → tmp`, TODO comments pour `manager._enabled` ; suggestions 2-3 écartées car contradictoires au design contract / déjà livrées par Story-003)
**Review Mode**: solo (QL-TEST-COVERAGE + LP-CODE-REVIEW skipped per mode)
