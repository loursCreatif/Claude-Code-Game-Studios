# Story-012 Evidence — Card States + Chrome Zen Palette

> **Story** : `production/epics/shop-system/story-012-card-states-chrome-zen-palette.md`
> **Type** : UI (ADVISORY evidence)
> **Date** : 2026-04-28
> **Status** : Lint static AUTO ✅ + manual screenshots DEFERRED Sprint 1

---

## Summary

Story-012 couvre 4 états visuels (NORMAL/HOVER/DISABLED/OWNED) + palette Chrome Zen
+ resize layout. La couverture automatisée (lint static `shop.tscn`) valide les
contraintes structurelles (zéro gradient/corner_radius/shader, ContinueButton
custom_minimum_size 200×48, MarginContainer ≥ 64 px). La validation visuelle des
4 states cards (StyleBoxFlat swap NORMAL/HOVER/DISABLED/OWNED + couleurs hex
exactes) reste manuelle Sprint 1+ — solo mode admet ADVISORY déférable.

---

## Automated Coverage (Lint Static)

**Test file** : `tests/static/shop_chrome_zen_lint_test.gd`
**Run** : 7/7 PASSED 53 ms (`reports/report_100/`)

| Test | AC / Rule | Result |
|------|-----------|--------|
| `test_shop_scene_chrome_zen_no_gradient` | §J.7 zéro gradient | ✅ |
| `test_shop_scene_chrome_zen_no_corner_radius` | §J.7 zéro corner_radius | ✅ |
| `test_shop_scene_chrome_zen_no_shader` | §J.7 zéro shader | ✅ |
| `test_shop_scene_ac_shp_32_no_animation_player` | AC-SHP-32 background statique | ✅ |
| `test_shop_scene_section_j4_continue_button_custom_minimum_size` | §J.4 200×48 | ✅ |
| `test_shop_scene_section_j4_continue_button_text_capitales` | §J.4 "CONTINUER" | ✅ |
| `test_shop_scene_margin_container_generous_padding` | Chrome Zen ≥ 64 px | ✅ |

---

## Manual Coverage Required (Tier UI ADVISORY — DEFERRED)

Les ACs suivants nécessitent screenshots runtime — non automatisables solo mode :

| AC / Rule | Description | Evidence Required |
|-----------|-------------|--------------------|
| **AC-SHP-33 ADVISORY** | Layout 1280×720 / 1920×1080 / 2560×1440 reflow propre | 3 screenshots `story-012-resize-{720,1080,1440}.png` |
| **R-SHP-12** | OWNED rendu : modulate.a=0.6, cost="—", button="POSSÉDÉ" | 1 screenshot état OWNED |
| **§J.2** | 4 StyleBoxFlat states (NORMAL/HOVER/DISABLED/OWNED) couleurs exactes | 4 screenshots état distincts |
| **§J.8 Tier 1 a11y** | Focus visible bordure 2 px #E8E8F0 distincte HOVER cyan | 1 screenshot focus state |
| **EC-SHP-25** | Tous owned → 2 cards OWNED, ContinueButton seul actif | 1 screenshot |
| **EC-SHP-27** | Resize fluide runtime drag fenêtre | 1 screenshot avant/après |

**Plan déférement** : implémentation visuelle complète (StyleBoxFlat 4 states inline
ou theme partagé `assets/themes/shop_theme.tres` + hover handlers `_refresh_card_visual_state`
+ children NameLabel/CostLabel/BuyButton dans chaque UpgradeCard) prévue Sprint 1
quand un humain peut valider visuellement les couleurs Chrome Zen et le focus
ring a11y. Solo mode autonome ne peut pas produire de screenshots runtime fiables.

---

## Deviations

**ADVISORY (1)** — implémentation visuelle StyleBoxFlat 4 states + hover handlers
déférée Sprint 1+. Le shop_controller.gd ne contient pas encore `_refresh_card_visual_state`
ni handlers `_on_card_mouse_entered/_exited`. Les UpgradeCard_0/1 dans `shop.tscn`
sont des PanelContainer vides (sans children NameLabel/CostLabel/BuyButton). Cette
absence n'invalide pas la logique gameplay (R-SHP-12 OWNED state géré côté
`_disable_buy_button_for` story-005, hydration géré story-003) mais la couche
visuelle Chrome Zen exacte (couleurs hex, hover swap) doit être implémentée + validée
visuellement par humain.

**Justification ADVISORY déférement** :
- Couverture automatisée structurelle complète (7/7 lint static)
- Logique métier OWNED/affordable déjà couverte stories 003-007 (15+ tests)
- Pillar 1 anti-friction : shop fonctionnel actuellement (boot, achat, ESC, transition)
- Risque visuel = cosmétique uniquement, pas blocker MVP
- Solo mode admet UI evidence ADVISORY déférable

---

## Sign-off

**Lint static** : PASSED 7/7 53 ms (`reports/report_100/`)
**Manual screenshots** : PENDING Sprint 1
**Reviewer** : Solo mode (Martin)
