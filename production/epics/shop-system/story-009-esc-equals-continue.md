# Story 009: ESC = Continue (anti-friction Pillar 1)

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-11` (ESC = Continue direct), `EC-SHP-12` (ESC pendant shake), `EC-SHP-13` (ESC pendant tween counter), `EC-SHP-28` (ESC pendant LOADING)
*Décision tranchée Pillar 1 : ESC déclenche `_on_continue_pressed()` sans confirmation. Risque sortie accidentelle EC-SHP-41 assumé MVP. Action `ui_cancel` Godot stdlib. Handler `_unhandled_input` (Godot route automatiquement aux Controls focusés). ESC pendant LOADING (avant `_ready` complété) → input mis en queue par Godot, traité au premier `_unhandled_input` post-ready.*

**ADR Governing Implementation**: ADR-0004 (Input API) — pas de polling `Input.*` direct depuis gameplay, mais pour UI Control la consommation `_unhandled_input` est l'API standard Godot.
**ADR Decision Summary**: Shop = scène UI Control, consomme events via `_unhandled_input` (route Godot), action `ui_cancel` via InputMap. Cohérent Input GDD Core Rule 1 (no `Input.is_action_just_pressed` direct depuis gameplay — exemption legitime UI Control).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `InputEvent.is_action_pressed("ui_cancel")` stable. Action `ui_cancel` mappée à ESC + B/Circle gamepad par défaut.

**Control Manifest Rules**:
- Required: utiliser `event.is_action_pressed("ui_cancel")` (action InputMap)
- Forbidden: `Input.is_action_just_pressed` direct dans `_unhandled_input` UI (utiliser `event.is_action_pressed`)
- Forbidden: `Input.*` singleton hors `_unhandled_input` (AC-SHP-44 lint)

---

## Acceptance Criteria

- [ ] **AC-SHP-26** : shop ACTIVE + `_unhandled_input` reçoit ESC ou action `ui_cancel` → `request_scene_transition` appelé 1 fois — identique au click.
- [ ] **AC-SHP-27** : shop LOADING (avant `_ready` complété) → `_unhandled_input` ESC → `request_scene_transition` PAS appelé.
- [ ] **EC-SHP-12** : ESC pendant animation shake (DISABLED click) → fermeture immédiate, shake `tween.kill()`.
- [ ] **EC-SHP-13** : ESC pendant tween counter post-achat → fermeture immédiate, tween interrompu, état `_owned_upgrades` déjà persisté.
- [ ] **EC-SHP-28** : ESC pressé pendant LOADING → input queue Godot → traité au premier `_unhandled_input` post-ready (fermeture immédiate visuellement transparente).

---

## Implementation Notes

```gdscript
var _ready_completed: bool = false

func _ready() -> void:
    # ... (story-002 à 008) ...
    _ready_completed = true  # AC-SHP-27 guard

func _unhandled_input(event: InputEvent) -> void:
    if not _ready_completed:
        return  # AC-SHP-27 — ne pas traiter ESC pendant LOADING
    if event.is_action_pressed(&"ui_cancel"):
        get_viewport().set_input_as_handled()  # consume event
        _on_continue_pressed()  # délègue au handler story-008 (incl. _closing guard)
```

**ESC kills active tweens** (EC-SHP-12/13) : si story-013 implémente `_active_tween: Tween`, ajouter dans `_on_continue_pressed()` :

```gdscript
if _active_tween and _active_tween.is_valid():
    _active_tween.kill()
```

**Note Pattern Input GDD compliance** : Shop UI Control utilise `_unhandled_input` (handler Control standard) — c'est l'API recommandée Godot pour UI consume. AC-SHP-44 lint vérifie zéro `Input.*` hors `_unhandled_input` (cf. story-014).

---

## Out of Scope

- Story 008 : Continue button click handler (cette story réutilise via `_on_continue_pressed`).
- Story 013 : tween counter / shake (cette story documente le `tween.kill()` pattern).
- Story 014 : lint AC-SHP-44 (no `Input.*` hors `_unhandled_input`).

---

## QA Test Cases

- **AC-SHP-26** : Logic
  - Given: mock GSM, shop ACTIVE, `_ready_completed = true`
  - When: `_unhandled_input(InputEventKey ESC)` ou `event.is_action_pressed("ui_cancel")`
  - Then: `request_scene_transition.call_count == 1`, même path que click
- **AC-SHP-27** : Logic
  - Given: shop LOADING (forcer `_ready_completed = false`)
  - When: envoyer ESC via `_unhandled_input`
  - Then: `request_scene_transition.call_count == 0`
- **EC-SHP-12** : Integration
  - Given: shake tween actif (story-013), shop ACTIVE
  - When: ESC pressé
  - Then: `_active_tween.is_valid() == false` (killed), transition lancée
- **EC-SHP-13** : Integration
  - Given: counter tween actif post-achat, `_owned_upgrades` déjà persisté
  - When: ESC pressé
  - Then: tween killed, transition lancée, `_owned_upgrades` intact dans Save
- **EC-SHP-28 input queue** : Logic
  - Given: shop instancié, ESC injecté immédiatement (avant fin `_ready()`)
  - When: `_ready()` complète + tick suivant
  - Then: ESC consommé au tick suivant, transition lancée

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/esc_equals_continue_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 008 (`_on_continue_pressed` handler)
- Unlocks: Story 015 (bidirectional incl. ESC path)
