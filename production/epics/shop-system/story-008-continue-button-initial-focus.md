# Story 008: Continue Button + Initial Focus + GSM Transition

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-10` (Continue → request_scene_transition), §J.4 + §J.8 Tier 1 accessibility, `AC-SHP-53` (initial focus ContinueButton)
*Le bouton "CONTINUER" est l'unique mécanisme de sortie clic au MVP. Toujours actif (jamais disabled par état upgrade). Au `_ready()`, focus initial UI = ContinueButton (élément le plus universellement accessible — Tier 1 a11y). Click → `GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")`. Flag `_closing: bool` (EC-SHP-18) bloque double-press.*

**ADR Governing Implementation**: ADR-0007 D-10 (verbe public `request_scene_transition`).
**ADR Decision Summary**: GSM expose `request_scene_transition(scene_path: String) -> void` SYNC (l'un des 5 verbes figés). Idempotence GSM rejette silencieusement second appel pendant transition.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control.grab_focus()`, `Button.pressed` signal, `Control.focus_mode = FOCUS_ALL` stables.

**Control Manifest Rules**:
- Required: `ContinueButton.disabled == false` permanent (R-SHP-10 toujours actif)
- Required: `_closing: bool` guard avant tout `request_scene_transition` (EC-SHP-18 double-safeguard)

---

## Acceptance Criteria

- [ ] **AC-SHP-25** : shop ACTIVE, click ContinueButton → `GSM.request_scene_transition(scene_path)` appelé exactement 1 fois avec scene_path non vide.
- [ ] **AC-SHP-28** : shop ACTIVE avec 0 achats → `ContinueButton.disabled == false`.
- [ ] **AC-SHP-53** : `_ready()` complété → `get_viewport().gui_get_focus_owner() == ContinueButton`.
- [ ] **EC-SHP-18** : double-click ContinueButton → 2e appel ignoré via flag `_closing`.
- [ ] Touche `Enter`/`Space` quand focus clavier → comportement identique au click (Godot stdlib).

---

## Implementation Notes

```gdscript
@onready var _continue_button: Button = %ContinueButton

var _closing: bool = false

func _ready() -> void:
    # ... (story-002/003/004/007) ...
    _continue_button.pressed.connect(_on_continue_pressed)
    _continue_button.focus_mode = Control.FOCUS_ALL
    _continue_button.disabled = false  # toujours actif R-SHP-10

    # AC-SHP-53 — initial focus on ContinueButton (universally accessible)
    await get_tree().process_frame  # focus_owner valide après 1 frame
    _continue_button.grab_focus()

func _on_continue_pressed() -> void:
    if _closing:
        return  # EC-SHP-18 double-safeguard
    _closing = true
    GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")
```

**Path MVP** : `"res://scenes/menus/main_menu.tscn"`. Tier 2+ : `RunContext.next_etage_id` chaîné (OQ-SHP-5 RESOLVED autoload pattern).

**Note focus async** : `grab_focus()` doit suivre `await get_tree().process_frame` car les Controls ne sont focusables qu'après l'idle frame initial post-ready. Acceptable car focus initial = before user interaction.

---

## Out of Scope

- Story 009 : ESC = Continue (handler distinct via `_unhandled_input`).
- Story 012 : styling Chrome Zen ContinueButton (StyleBoxFlat NORMAL/HOVER).
- Story 014 : lint anti-patterns (no tooltip sur ContinueButton — J.4).

---

## QA Test Cases

- **AC-SHP-25** : Logic
  - Given: mock GameStateManager avec compteur + path capture, shop ACTIVE
  - When: `_continue_button.pressed.emit()` (simulate click)
  - Then: `request_scene_transition.call_count == 1`, captured_path != ""
- **AC-SHP-28** : Logic
  - Given: shop ACTIVE, 0 achats
  - When: inspect ContinueButton
  - Then: `_continue_button.disabled == false`
- **AC-SHP-53** : Logic
  - Given: shop.tscn instancié
  - When: `_ready()` + `await get_tree().process_frame`
  - Then: `get_viewport().gui_get_focus_owner() == _continue_button`
- **EC-SHP-18** : Logic
  - Given: mock GSM compteur, shop ACTIVE
  - When: `_on_continue_pressed()` appelé 2× consécutifs
  - Then: `request_scene_transition.call_count == 1` (2e bloqué par `_closing`)
- **Keyboard activation** : Logic
  - Given: ContinueButton focused
  - When: simulate `InputEventAction(action="ui_accept", pressed=true)` via `Input.parse_input_event`
  - Then: same handler triggered (Godot stdlib button behavior)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/continue_button_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (ContinueButton existe), Story 002 (controller)
- Unlocks: Story 009 (ESC = même path), Story 015 (bidirectional)
