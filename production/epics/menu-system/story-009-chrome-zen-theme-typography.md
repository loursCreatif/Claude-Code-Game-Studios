# Story 009: Chrome Zen Theme — Typography + Palette + Button States

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-04-23
> **Estimate**: M (3-4 h, dont sourcing JetBrainsMono-Regular.ttf)
> **Performance**: Theme + StyleBoxFlat resources one-shot load au boot/instanciation — pas d'impact runtime. Font preload absorbé warmup AC-MNU-42.

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: K.3 (typo JetBrains Mono 28/15/13/11 px), K.4 (palette tokens MENU_BG_BLACK / MENU_PANEL_BG / MENU_TEXT_BASE / MENU_ACCENT_CYAN + RGB/ALPHA split r2 U-3), K.5 (5 états boutons + Hover↔Focus coexistence Godot 4.6 dual r2 U-4), K.6 (Tab navigation), K.9 (WCAG AAA 15.2:1)

**ADR Governing Implementation**: aucun ADR Menu-spécifique (système UI orchestré par contrats upstream — cf. EPIC §Governing ADRs). ADR-0003 Rendering & Graphics héritage : Forward+ + flat shaders + zéro post-processing onéreux.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Theme` + `StyleBoxFlat` stables Godot 4.0+. `JetBrainsMono-Regular.ttf` font asset embarqué. Hover↔Focus coexistence : Godot 4.6 supporte les deux états ensemble (hover dominant visuellement + focus marqué en surimpression).

**Control Manifest Rules (Presentation layer)**:
- Required : Forward+ renderer ; SMAA 1x ; flat shaders.
- Forbidden : `Tween` / `AnimationPlayer` dans menus ; gradients ; `corner_radius_*` non-zéro ; bg_color_2 (anti-pattern Chrome Zen).

---

## Acceptance Criteria

- [ ] **AC-MNU-51** [Static — ADVISORY] : `grep -E 'const MENU_BG_BLACK|const MENU_PANEL_BG|const MENU_TEXT_BASE|const MENU_ACCENT_CYAN' src/gameplay/menu/*.gd` retourne ≥ 4 const Color déclarés en tête fichier (pas hex hardcodés inline).
- [ ] **AC-MNU-52** [Static — ADVISORY] : `ls assets/fonts/JetBrainsMono-Regular.ttf` exit code 0 (font embarquée).
- [ ] **AC-MNU-53** [Manual — ADVISORY] : inspecteur Godot lit `TitleLabel = 28 px`, `Button = 15 px`, `SubtitleLabel = 13 px`, `VersionLabel = 11 px` (K.3). Evidence : screenshot inspecteur.
- [ ] **AC-MNU-54** [Manual — ADVISORY] : ratio contraste mesuré WCAG : `MENU_TEXT_BASE #E8E8F0` sur `MENU_BG_BLACK #050608` ≥ 15.2:1 ; `MENU_ACCENT_CYAN #3EE4FF` ≥ 8.9:1.
- [ ] **AC-MNU-55** [Static — BLOCKING] : `grep "layer = " scenes/menus/pause_overlay.tscn` retourne `layer = 80` (M Layer convention — déjà couvert Story 002 mais re-vérifié comme part Theme).
- [ ] **AC-MNU-56** [Static — ADVISORY] *(r2)* : grep CanvasLayer.layer top-level dans `scenes/`, valeurs uniques `{50, 60, 80, 100}` (HUD/Shop/Pause/GSM-fade).
- [ ] **AC-MNU-66** [Static — ADVISORY] *(r2 U-7)* : `grep -rE '\bbg_color_2\b|\bgradient\b|\bGradientTexture\b' scenes/menus/ assets/themes/menu*` retourne 0 match (anti-gradient natif).
- [ ] **AC-MNU-67** [Static — ADVISORY] *(r2 U-2)* : `grep -E 'const\s+DEBUG_SHOW_VERSION\s*:?\s*bool\s*=\s*false' src/gameplay/menu/main_menu_controller.gd` retourne ≥ 1 match (label 11 px masqué release MVP).

---

## Implementation Notes

*Derived from GDD §UI Requirements K.3-K.9 + Chrome Zen direction :*

1. **Tokens palette K.4** — déclarer en tête de `main_menu_controller.gd` ET `pause_menu_controller.gd` :
   ```gdscript
   const MENU_BG_BLACK: Color    = Color("050608")
   const MENU_PANEL_BG: Color    = Color("0A0A12")
   const MENU_TEXT_BASE: Color   = Color("E8E8F0")
   const MENU_ACCENT_CYAN: Color = Color("3EE4FF")
   const MENU_BG_OVERLAY_ALPHA: float = 0.85  # F-MNU-2 dim alpha (Story 005 use)
   const DEBUG_SHOW_VERSION: bool = false  # K.9 release-only safe
   ```
2. **Theme resource** — créer `assets/themes/menu_chrome_zen.tres` (Theme resource) qui définit :
   - `Button` styles : Normal (StyleBoxFlat MENU_PANEL_BG, border MENU_TEXT_BASE 1 px, corner_radius_* = 0), Hover (border 2 px MENU_ACCENT_CYAN), Focus (overlay 2 px outset MENU_ACCENT_CYAN — coexiste avec Hover), Pressed (BG MENU_ACCENT_CYAN/0.20), Disabled (text 50%, border 50%)
   - Font : `JetBrainsMono-Regular.ttf` embarqué `assets/fonts/`
   - Font sizes : default Theme override per-Label
3. **Font sizes (K.3)** — éditeur Godot inspector pour `TitleLabel.font_size = 28`, `Button.font_size = 15`, `SubtitleLabel.font_size = 13`, `VersionLabel.font_size = 11`. Si `DEBUG_SHOW_VERSION == false`, `VersionLabel.visible = false`.
4. **Contraste WCAG AAA (AC-MNU-54)** : ratios cibles validés au design lean re-pass (commit `3c518a3`) :
   - `#E8E8F0` sur `#050608` = 15.2:1 ≥ 14.0 (WCAG AAA — texte normal)
   - `#3EE4FF` sur `#050608` = 8.9:1 ≥ 4.5 (WCAG AA — bordure focus)
   Validation : screenshot inspecteur Godot + outil contraste WCAG (ex. axe Devtools, OXY contrast online, ou GDScript helper qui calcule luminance relative).
5. **Layer convention M (AC-MNU-55/56)** : `PauseLayer.layer = 80` strict ; ne créer aucun autre CanvasLayer dans Menu ≠ 80. Cross-GDD : HUD=50, Shop=60, Pause=80, GSM-fade=100.
6. **Anti-gradient (AC-MNU-66)** : aucun StyleBoxFlat avec `bg_color_2` (gradient natif) ; aucun GradientTexture en background. Tous styles flat couleur unique.

---

## Out of Scope

- Story 001/002 : structures `.tscn` (cette story livre Theme + tokens applied).
- Story 010 : grep statiques anti-patterns (cette story livre les ressources, Story 010 enforce la non-violation).
- Settings Menu : OQ-MNU-3 Tier 2+ (input remap, sliders).

---

## QA Test Cases

**AC-MNU-51** [Static] : tokens K.4 const Color
- Setup : `grep -E 'const MENU_BG_BLACK|const MENU_PANEL_BG|const MENU_TEXT_BASE|const MENU_ACCENT_CYAN' src/gameplay/menu/*.gd`
- Verify : 4+ matches détectés (chaque token au moins 1× déclaré const Color).
- Pass condition : tous tokens déclarés ; aucun hex hardcodé dans le corps des fonctions (manual review supplémentaire).

**AC-MNU-52** [Static] : font embarquée
- Setup : `test -f assets/fonts/JetBrainsMono-Regular.ttf`
- Verify : exit code 0.
- Pass condition : font asset présent.

**AC-MNU-53** [Manual] : inspecteur typo
- Setup : ouvrir `scenes/menus/main_menu.tscn` + `pause_overlay.tscn` dans éditeur Godot 4.6 à résolution 1920×1080.
- Verify : inspector → TitleLabel.font_size=28, Button.font_size=15, SubtitleLabel.font_size=13, VersionLabel.font_size=11.
- Pass condition : screenshot inspecteur sauvé `production/qa/evidence/menu-typography-[date].png` + sign-off ux-designer.

**AC-MNU-54** [Manual] : contraste WCAG
- Setup : Main Menu rendu 1920×1080, mesure WCAG via outil externe (axe, contrast checker).
- Verify : `#E8E8F0` sur `#050608` ≥ 15.2:1 ; `#3EE4FF` sur `#050608` ≥ 8.9:1.
- Pass condition : valeurs documentées `production/qa/evidence/menu-contrast-[date].md` + sign-off ux-designer.

**AC-MNU-55** [Static] : layer = 80
- Setup : `grep "^layer = " scenes/menus/pause_overlay.tscn`
- Verify : `layer = 80` exact.

**AC-MNU-56** [Static] : layer convention {50,60,80,100}
- Setup : script awk/GDScript helper parse `.tscn` — pour chaque `[node ... type="CanvasLayer"]` lit `layer = N`.
- Verify : valeurs uniques agrégées ⊆ {50, 60, 80, 100}.
- Pass condition : aucun layer hors set ; aucun doublon (cohérent HUD/Shop/Pause/fade).

**AC-MNU-66** [Static] : zéro gradient
- Setup : `grep -rE '\bbg_color_2\b|\bgradient\b|\bGradientTexture\b' scenes/menus/ assets/themes/menu*`
- Verify : 0 match.

**AC-MNU-67** [Static] : DEBUG_SHOW_VERSION = false
- Setup : `grep -E 'const\s+DEBUG_SHOW_VERSION\s*:?\s*bool\s*=\s*false' src/gameplay/menu/main_menu_controller.gd`
- Verify : ≥ 1 match.

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- AC-MNU-51/52/55/56/66/67 → `tests/static/menu_theme_lint_test.gd` ou CI grep job
- AC-MNU-53/54 → `production/qa/evidence/menu-typography-[date].png` + `menu-contrast-[date].md` + sign-off ux-designer
- Walkthrough → `production/qa/evidence/chrome-zen-theme-walkthrough.md` (screenshots Main Menu + Pause Menu rendus à 1920×1080)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 001 + Story 002 (scenes structurelles existantes pour appliquer Theme).
- Unlocks : Story 010 (lints anti-patterns vérifient absence d'overrides incohérents post-Theme).
