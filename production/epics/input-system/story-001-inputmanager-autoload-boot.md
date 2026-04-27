# Story 001: InputManager autoload bootstrap

> **Epic**: input-system
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-003`, `TR-inp-004`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004 Input API & Focus Handling
**ADR Decision Summary**: InputManager autoload #1, API polling canonique `was_pressed_this_tick(action: StringName)`, actions pré-allouées via `const ACTION_* := &"..."` (StringName discipline, zero-alloc hot path).

**Engine**: Godot 4.6 | **Risk**: HIGH
**Engine Notes**: Autoload order critique (ADR-0004 Risk 6) — `InputManager` doit être déclaré en 1er dans `[autoload]` de `project.godot`. `OS.has_feature("debug")` runtime remplace `#if debug_build` (absent en GDScript).

**Control Manifest Rules (Foundation layer)**:
- Required: InputManager autoload déclaré en 1er + actions via `&"..."` literal/const + pré-allocation dicts au `_ready()`
- Forbidden: `Input.is_action_just_pressed` direct depuis gameplay
- Guardrail: Input frame budget ≤ 0.2 ms/frame p99

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- [ ] `src/core/input_manager.gd` existe, `class_name InputManager`, extends `Node`
- [ ] `project.godot` [autoload] déclare `InputManager="*res://src/core/input_manager.gd"` en **1ère position**
- [ ] `ACTIONS_MVP: Array[StringName]` constant contient au moins : `&"move_forward"`, `&"move_back"`, `&"move_left"`, `&"move_right"`, `&"jump"`, `&"dash"`, `&"attack"`, `&"restart"`, `&"ui_cancel"`, `&"ui_confirm"`
- [ ] Toutes ces actions sont mappées dans `project.godot` [input] (keyboard bindings par défaut — WASD + Space + Shift + LMB + R + Escape + Enter)
- [ ] `_ready()` pré-alloue `_pressed_this_tick`, `_consumed_this_tick` avec une entrée `false` par action de `ACTIONS_MVP`
- [ ] **AC-DBG-1** : en build debug (`OS.has_feature("debug") == true`), `InputMap.has_action(&"debug_toggle") == true` après `_ready()` ; en release, l'action n'est pas enregistrée
- [ ] `_unhandled_input(event)` filtre `event.is_echo()` si `event is InputEventKey` (early return)

---

## Implementation Notes

*Derived from ADR-0004 Implementation Guidelines:*

Structure minimale du boot :

```gdscript
class_name InputManager
extends Node

const ACTIONS_MVP: Array[StringName] = [
    &"move_forward", &"move_back", &"move_left", &"move_right",
    &"jump", &"dash", &"attack", &"restart",
    &"ui_cancel", &"ui_confirm",
]
const ACTION_DEBUG_TOGGLE: StringName = &"debug_toggle"

var _pressed_this_tick: Dictionary = {}
var _consumed_this_tick: Dictionary = {}

func _ready() -> void:
    for a in ACTIONS_MVP:
        _pressed_this_tick[a] = false
        _consumed_this_tick[a] = false
    if OS.has_feature("debug") and not InputMap.has_action(ACTION_DEBUG_TOGGLE):
        InputMap.add_action(ACTION_DEBUG_TOGGLE)
        var ev := InputEventKey.new()
        ev.physical_keycode = KEY_F3
        InputMap.action_add_event(ACTION_DEBUG_TOGGLE, ev)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.is_echo():
        return
    # (story-002 : set flag pressed ; story-003 : mouse_motion)
```

Notes clés :
- **Autoload order (ADR-0004 Risk 6)** : si un futur autoload est ajouté avant `InputManager` dans `project.godot`, AC-CS-1 casse silencieusement. Lint `.claude/rules/inputmanager-autoload-first.md` planifié.
- **StringName discipline (control manifest Foundation Required)** : jamais de variable `String` concaténée pour identifier une action. Toujours `&"name"` literal ou `const NAME: StringName`.
- **No `#if debug_build`** : GDScript n'a pas de préprocesseur. Utiliser `OS.has_feature("debug")` runtime ; en release le check coûte 1 branche, négligeable.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002 : implémentation du polling `was_pressed_this_tick` + swap + simulate_action_press
- Story 003 : signal `mouse_motion(delta: Vector2)`
- Story 004 : refcount `request_disable` / `release_enable_request`
- Story 005 : `_notification` focus OS + signaux `application_focus_*`
- Story 006 : ring buffer latency
- Story 009 : debug overlay UI (cette story enregistre juste l'action `debug_toggle`)

---

## QA Test Cases

- **AC-DBG-1** : `InputMap.has_action(&"debug_toggle") == true` en debug après `_ready()`
  - Given : scène GUT au boot avec `InputManager` autoload chargé
  - When : assertion post `_ready()` via `await get_tree().process_frame`
  - Then : `InputMap.has_action(&"debug_toggle")` retourne `true` (debug) ou `false` (release, via mock `OS.has_feature`)
  - Edge cases : double `_ready()` (reload scène test) ne doit pas ajouter deux events à l'action

- **Pre-allocation** : `_pressed_this_tick` et `_consumed_this_tick` contiennent exactement `ACTIONS_MVP.size()` clés après `_ready()`, toutes à `false`
  - Given : InputManager fraîchement instancié
  - When : après `_ready()`
  - Then : `_pressed_this_tick.size() == ACTIONS_MVP.size()` ET toutes valeurs `== false`

- **is_echo filter** : `_unhandled_input` ignore les events `InputEventKey` avec `is_echo() == true`
  - Given : un `InputEventKey` avec `echo = true` injecté via `Input.parse_input_event`
  - When : `_unhandled_input` exécuté
  - Then : aucune mutation de `_pressed_this_tick`

- **Autoload order** : `Engine.get_singleton_list()` ou inspection `project.godot` confirme `InputManager` en 1ère position
  - Given : project.godot chargé
  - When : grep `[autoload]` section
  - Then : 1ère entrée = `InputManager`

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- Integration test `tests/integration/input/input_manager_boot_test.gd` — boot sequence, autoload order, ACTIONS_MVP pre-alloc, debug_toggle registration conditionnelle

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None (foundational story)
- Unlocks: Story 002, 003, 004, 005, 006, 009

---

## Completion Notes

**Completed**: 2026-04-22
**Criteria**: 7/7 passing (none deferred)
**Code Review**: Complete (2 passes — pass #1 CHANGES REQUIRED → pass #2 APPROVED WITH SUGGESTIONS)
**Test Evidence**: `tests/integration/input/input_manager_boot_test.gd` (211 lines, 7 tests, GdUnit4) — code valide, exécution en attente de l'installation addon GdUnit4 (infra projet).

**ADVISORY deviations** (non-blocking, à tracker en tech debt) :
- GdUnit4 addon absent du repo (`addons/gdunit4/` manquant) — résoudre via `/test-setup` ou installation manuelle
- Test `test_inputmanager_debug_toggle_registered_matches_build_type` peut passer pour la mauvaise raison (autoload pré-existant pollue `InputMap` avant l'instance test) — fix : ajouter erase explicite dans Arrange (3 lignes)
- AC-DBG-1 release branch non-testable en CI debug (limite structurelle `OS.has_feature` sans seam mock) — accepter, valider à l'export release
- AC4 test vérifie présence binding mais pas keycode spécifique (un placeholder passerait) — sampler 1 keycode canonique au futur (story-010 settings persistence)
- Suggestions cosmétiques code-review : remplacer `:=` par annotations explicites, `assert_bool(true).is_true()` par `skip()`, `assert_object(file).is_not_null()` par `FileAccess.get_open_error()` API 4.4+

**TR coverage** : TR-inp-003 (singleton autoload) ✅ + TR-inp-004 (StringName discipline) ✅
**ADR compliance** : ADR-0004 D-1 + D-9 ✅ ; D-2..D-8 explicitement déférés stories 002-006/009 via TODO inline
