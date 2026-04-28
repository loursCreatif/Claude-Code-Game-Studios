# Story 012: Upgrade Card Visual States + Chrome Zen Palette

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature (Presentation styling)
> **Type**: UI
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-12` (état OWNED rendu différencié), §J.2 (états visuels NORMAL/HOVER/DISABLED/OWNED), §J.7 (palette Chrome Zen), `EC-SHP-25/27`
*Chaque UpgradeCard est un PanelContainer avec 4 états visuels via swap StyleBoxFlat : NORMAL (#111120 + bordure #2A2A3A), HOVER (#161628 + bordure #3EE4FF cyan), DISABLED (#0D0D18 + bordure #1A1A28 + cost #FF4455 rouge), OWNED (#0D0D18 + bordure #1E3A3A + cost #2A8A8A cyan désaturé + label "POSSÉDÉ"). Palette Chrome Zen stricte : zéro gradient, zéro blur, zéro corner_radius, zéro animation arrière-plan. Une seule couleur d'accent par écran (#3EE4FF). EC-SHP-27 : resize fenêtre via FULL_RECT + Container reflow auto.*

**ADR Governing Implementation**: ADR-0007 (orchestration UI Control hierarchy).
**ADR Decision Summary**: Pas d'ADR Shop-spécifique ; styling pure Godot stdlib StyleBoxFlat / Theme.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: StyleBoxFlat shadow_color/shadow_size stable. `mouse_entered` / `mouse_exited` / `focus_entered` signals sur Control stables 4.0+.

**Control Manifest Rules**:
- Required: lignes droites (StyleBoxFlat sans corner_radius)
- Required: marges généreuses 64 px min 1080p (MarginContainer)
- Forbidden: gradient, blur, AnimatedTexture, NinePatchRect texture complexe (J.7 anti-patterns Chrome Zen)
- Forbidden: corner_radius non-nul sur StyleBoxFlat (Chrome Zen lignes droites)

---

## Acceptance Criteria

- [ ] **AC-SHP-32 [ADVISORY]** : background ColorRect statique sans AnimationPlayer connecté.
- [ ] **AC-SHP-33 [ADVISORY]** : layout 1280×720, 1920×1080, 2560×1440 → BuyButtons visibles + cliquables sans scroll, pas de débordement.
- [ ] **R-SHP-12** : OWNED rendu = `BuyButton.disabled=true` + `text="POSSÉDÉ"` + `CostLabel="—"` + `UpgradeCard.modulate.a=0.6`.
- [ ] **§J.2** : 4 états visuels distincts NORMAL / HOVER / DISABLED / OWNED via StyleBoxFlat swap (couleurs exactes palette).
- [ ] **§J.4** : ContinueButton custom_minimum_size `Vector2(200, 48)` + label "CONTINUER" capitales monospace + bordure NORMAL `#2A2A3A` / HOVER `#E8E8F0` (PAS cyan — réservé achat).
- [ ] **§J.7** : zéro gradient, zéro corner_radius non-nul, zéro shader background (palette uniquement).
- [ ] **§J.8 Tier 1 a11y** : focus visible bordure `2 px #E8E8F0` distincte HOVER cyan ; `focus_mode = FOCUS_ALL`.
- [ ] **EC-SHP-25 tous owned** : `_owned_upgrades` complet → 2 cards OWNED, ContinueButton seul élément actif/focalisé.
- [ ] **EC-SHP-27 resize** : test à 3 résolutions, layout reflow propre.

---

## Implementation Notes

```gdscript
# Theme partagé : assets/themes/shop_theme.tres (ou resources inline scene)
# StyleBoxFlat tokens (Chrome Zen palette §J.7) :
#   normal    : bg=#111120, border=1px #2A2A3A
#   hover     : bg=#161628, border=1px #3EE4FF
#   disabled  : bg=#0D0D18, border=1px #1A1A28
#   owned     : bg=#0D0D18, border=1px #1E3A3A
#   focus     : bg=panel, border=2px #E8E8F0 (distinct hover)

func _refresh_card_visual_state(card: PanelContainer, id: StringName, n_index: int) -> void:
    var name_label: Label = card.get_node("HBoxContainer/VBoxContainer/NameLabel")
    var cost_label: Label = card.get_node("HBoxContainer/HBoxContainer/CostLabel")
    var buy_button: Button = card.get_node("HBoxContainer/BuyButton")

    if _owned_upgrades.has(id):
        card.add_theme_stylebox_override("panel", _stylebox_owned)
        card.modulate.a = 0.6
        cost_label.text = "—"
        cost_label.add_theme_color_override("font_color", Color("#2A8A8A"))
        buy_button.disabled = true
        buy_button.text = "POSSÉDÉ"
        buy_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
        return

    var cost: int = _compute_cost(n_index)
    var affordable: bool = CreditEconomy.get_total() >= cost
    if affordable:
        card.add_theme_stylebox_override("panel", _stylebox_normal)
        card.modulate.a = 1.0
        cost_label.text = str(cost)
        cost_label.add_theme_color_override("font_color", Color("#E8E8F0"))
        buy_button.disabled = false
        buy_button.text = "ACHETER"
        buy_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    else:
        card.add_theme_stylebox_override("panel", _stylebox_disabled)
        card.modulate.a = 1.0
        cost_label.text = str(cost)
        cost_label.add_theme_color_override("font_color", Color("#FF4455"))
        buy_button.disabled = true
        buy_button.text = "ACHETER"
        buy_button.mouse_default_cursor_shape = Control.CURSOR_ARROW

# HOVER swap via signals (pas de polling)
func _on_card_mouse_entered(card: PanelContainer, id: StringName) -> void:
    if _owned_upgrades.has(id):
        return  # OWNED ne hover pas
    if not _is_affordable_for(id):
        return  # DISABLED ne hover pas (mais shake géré story-013)
    card.add_theme_stylebox_override("panel", _stylebox_hover)

func _on_card_mouse_exited(card: PanelContainer, id: StringName) -> void:
    _refresh_card_visual_state(card, id, _n_index_for(id))
```

**Chrome Zen palette tokens** (cf. GDD §Tuning Knobs Visuels) :
```
SHOP_BG                   = #0A0A12  (background fullscreen)
SHOP_SURFACE              = #111120  (panel NORMAL)
SHOP_SURFACE_HOVER        = #161628  (panel HOVER)
SHOP_SURFACE_INACTIVE     = #0D0D18  (panel DISABLED / OWNED)
SHOP_SEPARATOR            = #2A2A3A  (HSeparator, bordures NORMAL)
SHOP_TEXT_PRIMARY         = #E8E8F0  (labels principaux)
SHOP_TEXT_SECONDARY       = #6E6E8A  (descriptions, tooltips)
SHOP_ACCENT               = #3EE4FF  (bordure HOVER, glow affordable)
SHOP_ACCENT_OWNED         = #2A8A8A  (cyan désaturé OWNED cost)
SHOP_COST_BLOCKED         = #FF4455  (cost DISABLED rouge sémantique)
```

---

## Out of Scope

- Story 013 : animations tween (counter 300 ms, pulse achat 150 ms, shake DISABLED 200 ms, glow affordable subtle).
- Story 014 : lint anti-patterns (zéro AnimationPlayer/AudioStreamPlayer/ScrollContainer/TabContainer).
- Story 016 : performance benchmarks rendu.

---

## QA Test Cases

- **AC-SHP-32** : Manual
  - Setup : ouvrir shop.tscn dans éditeur Godot
  - Verify : Background ColorRect inspecté, zéro AnimationPlayer connecté, zéro keyframe
  - Pass : screenshot évidence
- **AC-SHP-33** : Manual
  - Setup : run shop scene à 1280×720 puis 1920×1080 puis 2560×1440
  - Verify : layout reflow propre, BuyButtons visibles + cliquables, pas de scrollbar
  - Pass : 3 screenshots `production/qa/evidence/shop/story-012-resize-{720,1080,1440}.png`
- **R-SHP-12 OWNED visual** : UI manual
  - Setup : `_owned_upgrades = [&"double_jump"]`
  - Verify : carte double_jump bg=#0D0D18, modulate.a=0.6, cost="—", button.text="POSSÉDÉ", button.disabled=true
  - Pass : screenshot
- **§J.4 ContinueButton** : Manual
  - Setup : ouvrir shop.tscn
  - Verify : ContinueButton size 200×48, label "CONTINUER" capitales monospace, bordure NORMAL=#2A2A3A
  - Pass : screenshot + grep `custom_minimum_size = Vector2(200, 48)` dans tscn
- **§J.7 Chrome Zen lint** : Lint
  - Setup : ouvrir tous .tscn / .tres associés shop
  - Verify : grep `corner_radius` → 0 match ; grep `gradient` → 0 ; grep `shader` → 0
  - Pass : 3 grep retournent 0
- **§J.8 focus visible** : Manual
  - Setup : Tab navigation dans shop
  - Verify : élément focused → bordure 2px #E8E8F0 visible (distincte du HOVER cyan)
  - Pass : screenshot focus state
- **EC-SHP-25 tous owned** : UI
  - Setup : `_owned_upgrades = [&"double_jump", &"dash_horizontal"]`
  - Verify : 2 cards OWNED, ContinueButton seul actif et focalisé
  - Pass : screenshot
- **EC-SHP-27 resize fluide** : Manual (couvre AC-SHP-33, validation supplémentaire)
  - Setup : drag fenêtre runtime en cours de shop
  - Verify : pas de freeze, pas de débordement, cards restent dans bounds
  - Pass : screenshot avant/après resize

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/shop/story-012-card-states/` (screenshots NORMAL/HOVER/DISABLED/OWNED + 3 résolutions) + sign-off lead
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene skeleton), Story 002 (controller refs), Story 003 (`_owned_upgrades`)
- Unlocks: Story 013 (animations s'appuient sur StyleBoxFlat existants), Story 016 (perf rendu)
