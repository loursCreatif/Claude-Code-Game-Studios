# Story 001: Scene Skeleton `shop.tscn`

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature (UI presentation primitives)
> **Type**: UI
> **Manifest Version**: 2026-04-23
> **Estimate**: S (1-2 h)
> **Performance**: scène load < 50 ms (defaults Godot, ColorRect + containers, aucun asset lourd) — pas d'impact perf gameplay attendu (hors PLAYING state).

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-1`, `R-SHP-2`, `R-SHP-16` (TR-SHP-??? — registry à créer post-Sprint 1)
*Le shop est une scène transitoire (pas un autoload) ; sa hiérarchie de nœuds est figée par R-SHP-2 ; `ProcessMode=ALWAYS` + `CanvasLayer.layer=60` cohérents pattern projet (HUD=50, GSM=100).*

**ADR Governing Implementation**: ADR-0007 (GameStateManager) — D-5 two-path scene transition (Shop = scène container chargée via `request_scene_transition`).
**ADR Decision Summary**: Le shop est une scène container instanciée par GSM via `change_scene_to_file`, pas un autoload. PROCESS_MODE_ALWAYS cohérent ADR-0007 D-4.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Control + CanvasLayer + ProcessMode stables 4.0+, aucune API post-cutoff.

**Control Manifest Rules (Presentation layer)**:
- Required: `process_mode = PROCESS_MODE_ALWAYS` sur ShopRoot ; `CanvasLayer.layer = 60`
- Required: ancrage `Control.LayoutPreset.FULL_RECT` sur ShopRoot
- Forbidden: aucun script gameplay (pas de mutation gameplay state — Shop est UI pure)

---

## Acceptance Criteria

- [ ] **AC-SHP-29** : `shop.tscn` inspecté → `CanvasLayer.layer == 60`.
- [ ] **AC-SHP-30** : `shop.tscn` inspecté → `ShopRoot.process_mode == PROCESS_MODE_ALWAYS` (valeur sérialisée `3` en Godot 4.6 — `4` = `PROCESS_MODE_DISABLED`, ne JAMAIS asseyer `4`).
- [ ] Hiérarchie R-SHP-2 respectée : `ShopRoot(Control) → Background(ColorRect) → CreditDisplay(HBoxContainer) → UpgradeList(VBoxContainer × 2 cards) → ContinueButton(Button)`.
- [ ] `Background.color = #0A0A12` (SHOP_BG token Chrome Zen).
- [ ] Scene parse-clean : `godot --headless --check-only --script tools/lint/check_shop_scene.gd` (ou test GUT instancie scène, assert root != null).

---

## Implementation Notes

Créer `scenes/shop/shop.tscn` avec hiérarchie exacte R-SHP-2. Attacher `ShopController` (script story-002) sur `ShopRoot`. **Ne pas implémenter** la logique controller ici — uniquement la structure de scène + propriétés Control.

```
shop.tscn (ShopRoot : Control, FULL_RECT, layer=60, ALWAYS)
├── Background (ColorRect, color=#0A0A12)
├── MarginContainer (margin=64 px)
│   └── VBoxContainer
│       ├── shop_title (Label "SHOP" monospace)
│       ├── HSeparator (#2A2A3A)
│       ├── CreditDisplay (HBoxContainer aligned right)
│       │   ├── CreditLabel (Label "CRÉDITS : ")
│       │   └── CreditValueLabel (Label "0")
│       ├── UpgradeList (VBoxContainer separation=12)
│       │   ├── UpgradeCard_0 (PanelContainer)
│       │   └── UpgradeCard_1 (PanelContainer)
│       └── HBoxContainer footer
│           └── ContinueButton (Button "CONTINUER" 200×48)
```

Pas de StyleBoxFlat custom dans cette story (story-012 owne le styling). Utiliser defaults Godot — l'objectif est la structure parse-clean.

---

## Out of Scope

- Story 002 : catalogue constants & ShopController script attaché.
- Story 012 : styling Chrome Zen (StyleBoxFlat, couleurs, polices).
- Story 014 : lint static anti-patterns (no AudioStreamPlayer/AnimationPlayer/etc.).

---

## QA Test Cases

- **AC-SHP-29** : `Lint static — grep "layer = 60" scenes/shop/shop.tscn → 1 match`
  - Setup : ouvrir `shop.tscn`
  - Verify : `[node name="ShopRoot"]` parent CanvasLayer `layer = 60`
  - Pass : grep retourne exactement 1 match
- **AC-SHP-30** : `Lint static — grep "process_mode = 3" scenes/shop/shop.tscn → 1 match`
  - Setup : ouvrir `shop.tscn`
  - Verify : `process_mode = 3` (`Node.PROCESS_MODE_ALWAYS` en Godot 4.6) sur ShopRoot. **Attention** : `4` = `PROCESS_MODE_DISABLED` (désactive `_process`/`_input`/tweens) — bug runtime silencieux si erreur d'enum.
  - Pass : grep retourne exactement 1 match sur `process_mode = 3`
- **Manual hierarchy check** :
  - Setup : ouvrir scène dans éditeur Godot
  - Verify : tous les nœuds R-SHP-2 présents dans l'ordre exact
  - Pass : 0 nœud manquant, 0 nœud extra

---

## Test Evidence

**Story Type**: UI
**Required evidence**: `production/qa/evidence/shop/story-001-scene-skeleton.md` (screenshot éditeur + grep output)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None (Sprint 1 entry)
- Unlocks: Story 002, 012
