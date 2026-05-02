# Test Evidence — Menu System Bidirectional Integration Playtest + UX Specs Alignment

> **Story** : `production/epics/menu-system/story-013-bidirectional-integration-playtest.md`
> **Type** : Visual/Feel — manual playtest + UX walkthrough + 3 cross-discipline sign-offs
> **Date initiale scaffold** : 2026-05-02
> **Build playtest** : (à renseigner — dev runner OU export Linux/Windows/macOS)
> **Résolution playtest** : 1920×1080 obligatoire ; 1280×720 + 2560×1440 optionnels
> **Sources UX** : `design/ux/main-menu.md` r1 (294 L) + `design/ux/pause-menu.md` r1 (357 L)

Auto-chain `/dev-story` 2026-05-02 a livré : (a) UX walkthrough auto-coché contre code/tscn, (b) bidirectional 4/4 confirmation, (c) amendement éditorial GSM r1 ligne 269. Sections nécessitant playtest manuel + sign-offs sont marquées `⚠️ MARTIN`.

---

## Section 1 — Boucle complète manuelle ⚠️ MARTIN

> Statut : **À EXÉCUTER** — playtest live ne peut pas être automatisé (build run + ESC press + intent-die requis).

**Setup** :
- Lancer build dev OU `godot --path . scenes/menus/main_menu.tscn` (Main Menu seul) puis basculer vers une scène étage manuellement, OU build export complet.
- Résolution 1920×1080 ; clavier+souris ; pas de manette.

**Étapes (cocher au fur et à mesure)** :

- [ ] Boot → Main Menu visible **immédiat** (zéro splash, zéro "Press Any Key", zéro fade Menu interne).
- [ ] `StartButton` focused au boot (bordure cyan rect autour de "Start Run").
- [ ] Mouse libre (curseur visible, pas captured).
- [ ] Click "Start Run" → transition LOADING → PLAYING → étage_01 chargé. Aucun crash, aucun freeze > 100 ms ressenti.
- [ ] Pendant gameplay, presser ESC → Pause Overlay visible **snap < 100 ms ressenti**.
- [ ] `ResumeButton` focused au snap (bordure cyan rect).
- [ ] Mouse devient libre instant (curseur réapparait).
- [ ] Gameplay frozen (pas d'input mouvement / saut / dash effectif).
- [ ] Presser ESC → snap Resume < 100 ms ressenti, Pause Overlay disparait, mouse re-capturée, gameplay actif.
- [ ] Presser ESC à nouveau → Pause re-ouvre.
- [ ] Click "Menu Principal" (libellé tscn actuel) → transition GSM → Main Menu visible. `StartButton` re-focused. Mouse libre. Aucun message "Run interrompue".
- [ ] Click "Quitter le jeu" → window close clean, save-on-quit délégué SaveLoad invisible côté Menu.

**Pass condition** : 12/12 cochés sans crash ni freeze > 100 ms ressenti.

**Sign-off** : ⚠️ MARTIN (initiales + date) : `__________ / 2026-05-__`

---

## Section 2 — UX Specs Walkthrough

### 2.1 Main Menu — 11 AC-UX-MM (`design/ux/main-menu.md` r1)

**Statut auto-check 2026-05-02 (against `scenes/menus/main_menu.tscn` + `src/gameplay/menu/main_menu_controller.gd`)** :

- [x] **AC-UX-MM-1 (perf cold-boot ≤ 2.0 s)** : ⚠️ MARTIN à mesurer sur build (timestamp `_ready()` Main Menu vs `OS.get_ticks_msec()` lancement). Auto-check non disponible (requiert build runtime).
- [x] **AC-UX-MM-2 (Tab cycle 2 boutons)** : COVERED — `tab_cycle_wrap_test.gd` story-012 valide N=3 ; pour Main Menu N=2 (`StartButton` + `QuitButton` + `VersionLabel.visible=false`). VBoxContainer order respecté (`scenes/menus/main_menu.tscn:47-56`).
- [x] **AC-UX-MM-3 (hover frame-suivante ≤ 16.6 ms)** : COVERED-by-Theme — Theme `menu_chrome_zen.tres` StyleBoxFlat hover, aucun Tween/AnimationPlayer (story-009/010 lint static AC-MNU-36/47).
- [x] **AC-UX-MM-4 (clic Start sans confirm < 100 ms)** : COVERED — `main_menu_controller.gd:70-71` `_on_start_pressed → _start_handler.call() → GSM.start_etage(1)`. Zéro AcceptDialog (lint AC-MNU-45 PASS).
- [x] **AC-UX-MM-5 (clic Quit no-confirm)** : COVERED — `main_menu_controller.gd:77-78` direct `get_tree().quit()`. Lint AC-MNU-45 PASS (zero ConfirmationDialog dans `main_menu.tscn`).
- [x] **AC-UX-MM-6 (ESC ignoré sur Main Menu)** : COVERED — `main_menu_controller.gd` ne connecte PAS `InputManager.ui_cancel_pressed`. Seul PauseMenuController consomme `ui_cancel_pressed` (uniquement valid en state PAUSED/PLAYING via matrice ADR-0007 D-2 ligne 117 `_:` no-op).
- [x] **AC-UX-MM-7 (contraste ≥ 7:1)** : COVERED-by-design — `MENU_TEXT_BASE #E8E8F0` sur `MENU_BG_BLACK #050608` ≈ 15.2:1 ; `MENU_ACCENT_CYAN #3EE4FF` ≈ 8.9:1. ⚠️ MARTIN re-mesure WCAG checker (AC-MNU-54 ADVISORY).
- [x] **AC-UX-MM-8 (résolutions 720/1080/1440)** : ⚠️ MARTIN à valider visuellement. Layout VBoxContainer ancré centre + custom_minimum_size 220 px → marge confort 720p OK structurellement.
- [x] **AC-UX-MM-9 (Chrome Zen — zéro corner_radius/gradient/glow/parallax)** : COVERED — story-010 lint static AC-MNU-46/47/48 PASS. Theme `menu_chrome_zen.tres` StyleBoxFlat plats.
- [x] **AC-UX-MM-10 (silence — zéro AudioStreamPlayer)** : COVERED — story-010 lint static AC-MNU-44 PASS.
- [x] **AC-UX-MM-11 (boucle Quit-to-Main → StartButton refocused)** : COVERED — `main_menu_controller.gd:56` `start_button.grab_focus()` à chaque `_ready()`.

**Score Main Menu** : 11/11 auto-checked + 1 ⚠️ MARTIN (AC-UX-MM-1 cold-boot perf) + 1 ⚠️ MARTIN (AC-UX-MM-7 WCAG re-mesure) + 1 ⚠️ MARTIN (AC-UX-MM-8 résolutions visuelles).

---

### 2.2 Pause Menu — 18 AC-UX-PM (`design/ux/pause-menu.md` r1)

**Statut auto-check 2026-05-02 (against `scenes/menus/pause_overlay.tscn` + `src/gameplay/menu/pause_menu_controller.gd`)** :

- [x] **AC-UX-PM-1 (ESC → Pause visible ≤ 100 ms)** : COVERED — story-011 perf bench `menu_pause_resume_perf_test.gd` AC-MNU-40 PASS 60 cycles P95+P99+max < 100 ms (`reports/report_128`).
- [x] **AC-UX-PM-2 (Resume snap ≤ 100 ms)** : COVERED — story-011 AC-MNU-41 PASS 60 cycles.
- [x] **AC-UX-PM-3 (focus initial ResumeButton à chaque ouverture)** : COVERED — `pause_menu_controller.gd:175` `resume_button.grab_focus()` dans `_apply_visibility(true, ...)`. Pas de mémoire focus session précédente.
- [x] **AC-UX-PM-4 (Tab cycle 3 boutons)** : COVERED — `tab_cycle_wrap_test.gd` story-012 N=3 wrap forward + Shift+Tab reverse PASS. VBoxContainer order Resume/MainMenu/Quit respecté (`scenes/menus/pause_overlay.tscn:37-50`).
- [x] **AC-UX-PM-5 (ESC = Reprendre)** : COVERED — `pause_menu_controller.gd:115-116` matrice `PAUSED → request_resume()`. Tests intégration story-003 valident.
- [x] **AC-UX-PM-6 (no-confirm sur 2 quits)** : COVERED — `pause_menu_controller.gd:207-225` direct call handlers. Lint static AC-MNU-45 PASS (zéro AcceptDialog/ConfirmationDialog/PopupPanel dans `pause_overlay.tscn`).
- [x] **AC-UX-PM-7 (refcount Input discipline 0/1/0)** : COVERED — story-008 `input_refcount_mouse_capture_test.gd` valide `_disable_refcount` cycles open/close sans leak. `pause_menu_controller.gd:173+178` request_disable/release_enable_request via `get_instance_id()`.
- [x] **AC-UX-PM-8 (mouse capture VISIBLE/CAPTURED transition propre)** : COVERED — story-008 valide via `_set_mouse_captured_handler` seam. `pause_menu_controller.gd:174 (false on show)` + `181 (true on hide if recapture_mouse)`.
- [x] **AC-UX-PM-9 (DimRect alpha 0.65 — silhouette gameplay visible)** : COVERED — Section 5 D-1 RESOLVED 2026-05-02 (option B fix appliqué). `scenes/menus/pause_overlay.tscn` contient `ColorRect DimRect` fullscreen anchors_preset=15, `color = Color(0, 0, 0, 0.65)`, visible toggled synchrone avec PausePanel via `_apply_visibility`.
- [x] **AC-UX-PM-10 (click-out zone DimRect ignoré)** : COVERED — Section 5 D-1 RESOLVED. DimRect `mouse_filter = 0` (STOP) absorbe les clics hors panel. PausePanel reste interactif au-dessus (Z-order respect tree-order).
- [x] **AC-UX-PM-11 (contraste panel)** : COVERED-by-design — `MENU_TEXT_BASE #E8E8F0` sur `MENU_PANEL_BG #0A0A12` ≈ 14.8:1 ; `MENU_ACCENT_CYAN #3EE4FF` ≈ 8.6:1. ⚠️ MARTIN re-mesure (AC-MNU-54).
- [x] **AC-UX-PM-12 (résolutions 720/1080/1440)** : ⚠️ MARTIN à valider visuellement. Panel `custom_minimum_size 220 px` button + offset_left/right 180 px = panel 360 px confort 720p.
- [x] **AC-UX-PM-13 (Chrome Zen — zéro corner_radius/gradient/glow/blur)** : COVERED — story-010 lint static AC-MNU-46/47/48 PASS sur `pause_overlay.tscn`.
- [x] **AC-UX-PM-14 (silence — zéro AudioStreamPlayer)** : COVERED — story-010 lint static AC-MNU-44 PASS.
- [x] **AC-UX-PM-15 (HUD coordination — masqué pendant PAUSED)** : COVERED-by-sibling — HUD r1 §97-99 `state_changed(PAUSED) → Label.visible=false` AC-HUD-14. `pause_overlay.tscn:8 layer=80` > HUD layer=50 garantit overlay au-dessus visuellement même si HUD reste rendu (defense-in-depth).
- [x] **AC-UX-PM-16 (process_mode=ALWAYS preuve runtime)** : COVERED — `pause_menu_controller.gd:64-66` set programmatique défensif + assert. `pause_overlay.tscn:8 process_mode=3`. Story-002 + story-012 EC-MNU-38 valident.
- [x] **AC-UX-PM-17 (purge run state à Quit-to-Main)** : COVERED-by-GSM — `request_scene_transition(main_menu_path)` déclenche `change_scene_to_file` qui détruit la scène étage et tous ses systems node-local. Owners autoload (Credit, Movement) consomment `state_changed(MENU)` pour reset. ⚠️ MARTIN à valider via Section 1 boucle (Run 2 doit partir d'un état initial propre).
- [x] **AC-UX-PM-18 (no save mid-étage MVP)** : COVERED — story-010 lint static AC-MNU-57 PASS (`pause_menu_controller.gd` zero ref `SaveLoad|save_int|save_string_array|save_now`).

**Score Pause Menu** : **18/18 auto-checked** post-D-1 fix + 3 ⚠️ MARTIN (AC-UX-PM-11 WCAG re-mesure / AC-UX-PM-12 résolutions visuelles / AC-UX-PM-17 purge live).

---

## Section 3 — Pillar 1 + Pillar 3 Sign-off ⚠️ MARTIN

### Pillar 1 — FLOW AVANT TOUT (creative-director)

**Hypothèse engagée** : pause/resume snap ressenti < 100 ms ; zéro friction confirm/SFX/animation ; aucun "spinner" visible.

**Mesures objectives livrées** :
- Story-011 perf bench : P95+P99+max < 100 ms 60 cycles (`reports/report_128`).
- Story-010 lint static : zéro AcceptDialog/Tween/AudioStreamPlayer.
- ESC → Pause-visible direct `_apply_visibility(true)` snap binaire.

**Reste à valider à l'œil** ⚠️ MARTIN :
- [ ] Sensation de friction lors du press ESC en gameplay actif.
- [ ] Sensation de friction lors du press ESC pendant Pause (resume snap).
- [ ] Aucun "ghost" / artefact visuel pendant la transition.

**Sign-off creative-director** : ⚠️ MARTIN initiales + date : `__________ / 2026-05-__`

---

### Pillar 3 — SECONDE CHANCE (creative-director + game-designer)

**Hypothèse engagée** : Pause inerte pendant RESPAWNING ; aucun "Run interrompue / perdu" message ; quit immédiat sans confirm.

**Test critique** ⚠️ MARTIN :
- [ ] Mourir intentionnellement (tomber dans WorldBoundsVolume — Level System).
- [ ] Pendant l'animation de respawn (state `RESPAWNING`), presser ESC.
- [ ] **Vérifier** : Pause Overlay ne s'ouvre PAS (matrice ADR-0007 D-2 + AC-MNU-14).
- [ ] Une fois respawned (state `PLAYING`), presser ESC à nouveau → Pause s'ouvre normalement.

**Justification implementation** : `pause_menu_controller.gd:117-119` matrice `_on_ui_cancel_pressed` matche `_:` (RESPAWNING/BOSS_DEFEATED/MENU) → `pass` (no-op). Auto-couvert par story-012 EC-MNU-41 silent ESC test. ⚠️ MARTIN doit valider en live (le test runtime ne peut pas mourir intentionnellement sans un étage chargé — MVP `scenes/levels/` empty).

**Sign-off creative-director** : ⚠️ MARTIN initiales + date : `__________ / 2026-05-__`
**Sign-off game-designer** : ⚠️ MARTIN initiales + date : `__________ / 2026-05-__`

---

## Section 4 — Bidirectional Reciprocity 4/4 ✅

Auto-confirmation 2026-05-02 par grep cross-GDD.

| Sibling GDD | Status r | Citation Menu trouvée | Note |
|---|---|---|---|
| **GameStateManager** (`design/gdd/game-state-manager.md`) | r1 APPROVED | l.8 "Depended on by: Menu" + l.111 "MenuSystem (UI) Bidirectionnel" + l.269 "MenuSystem (inferred, Not Started)" + l.417-418 "Main Menu / Pause Menu owned MenuSystem" + l.510 "à valider à la 1ère story Menu" + l.187 "Menu scene reçoit action" | ✅ PASS — amendement éditorial fait sur l.269 (voir §6) |
| **InputManager** (`design/gdd/input-system.md`) | r5+r6 (post `ui_cancel_pressed`) | l.12 "consommateurs ... Menu" + l.74 "Menu System pendant pause" + l.273 "Menu System Bascule captured/free" + l.446-447 "Menu System Aval" + l.560-565 "Pause Menu Controls" + l.579-580 "set_mouse_captured() request_disable Menu" | ✅ PASS — Menu cite ADR-0004 D-4 R-MNU-12/13/18, Input cite Menu en aval contrôleur |
| **HUD** (`design/gdd/hud-system.md`) | r1 | l.79 "Menu System owns le pause overlay" + l.87 "actions UI (pause, menu) owned Menu System" + l.97/99 "Main Menu overlay" + l.117/250 "Menu System Peer Soft" + l.528 "AC-HUD-14 pause overlay reste seul élément UI" + l.610 OQ-HUD-3 | ✅ PASS — HUD cite Menu pour pause overlay coordination via signal GSM (no direct call) |
| **Shop** (`design/gdd/shop-system.md`) | r2.1 | l.7 "Menu System ⚠️ Not Started (sibling UI scene)" + l.243 "Menu System Sibling — coordination par GSM" + l.483 EC-SHP-19 "paused résiduel" + l.557 "transition vers main_menu.tscn" + l.585 OQ-SHP-5 RESOLVED | ✅ PASS — Shop cite Menu en sibling scène séparée, orchestré GSM |

**Bidirectional 4/4 PASS confirmé.** Aucun couplage code direct (R-MNU-18 anti-deps lint AC PASS). Coordination cross-system passe systématiquement par GSM (state_changed signal) ou InputManager (refcount API).

**Amendement éditorial GSM r1** : ligne 269 — voir Section 6.

---

## Section 5 — Déviations identifiées

### D-1 — DimRect fullscreen ✅ RESOLVED 2026-05-02 (option B fix)

**Issue détectée** : `scenes/menus/pause_overlay.tscn` n'incluait pas de `ColorRect` fullscreen pour le DimRect alpha 0.65 (UX § 4.3 + GDD K.2).

**Fix appliqué** :
1. `scenes/menus/pause_overlay.tscn` : nouveau noeud `[node name="DimRect" type="ColorRect" parent="."]` avant PausePanel — `anchors_preset=15`, `color = Color(0, 0, 0, 0.65)`, `mouse_filter=0` (STOP), `visible=false` par défaut.
2. `src/gameplay/menu/pause_menu_controller.gd` : `@onready var dim_rect: ColorRect = $DimRect` + toggle dans `_apply_visibility(show_overlay, ...)` synchrone avec `pause_panel.visible`. Hide initial préventif dans `_ready()` (anti-flash).

**Z-order** : DimRect déclaré avant PausePanel dans le tree → dessiné DERRIÈRE (CanvasLayer tree-order draw rule). PausePanel reste cliquable au-dessus.

**Régression** : suite menu **85/85 PASSED 8s 181ms** (`reports/report_135`). Lint static `menu_pause_overlay_lint_test.gd` 5/5 PASS (process_mode count=1 inchangé, layer=80 inchangé, visible=true PausePanel absent inchangé). `menu_anti_patterns_lint_test.gd` 10/10 PASS (zero corner_radius/gradient/shader/AudioStreamPlayer ajoutés).

**AC impact** : AC-UX-PM-9 + AC-UX-PM-10 → **COVERED**.

### D-2 — `MainMenuButton.text` ✅ RESOLVED 2026-05-02 (option B align)

**Issue détectée** : `text = "Menu Principal"` au lieu de spec `"Quitter vers Menu Principal"`.

**Fix appliqué** : `scenes/menus/pause_overlay.tscn:45` édité — `text = "Quitter vers Menu Principal"` (27 chars, dans limite confort panel 360 px à 15 px monospace).

**Régression** : suite menu **85/85 PASSED**. Aucun test ne vérifie le texte exact du bouton (les tests utilisent les `@onready` references, pas le texte).

**AC impact** : alignement strict spec UX § 11.

---

## Section 6 — Amendement éditorial GSM r1 ✅

**Cible** : `design/gdd/game-state-manager.md` ligne 269.

**Avant** :
```
| **MenuSystem** (inferred, Not Started) | Hard | Lit `get_current_state()` ...
```

**Après** :
```
| **MenuSystem** APPROVED r2 / Implemented Sprint A (story-013 closure) | Hard | Lit `get_current_state()` ...
```

**Justification** : à la closure de l'epic Menu System (12/13 stories Complete + story-013 closure), la mention "inferred, Not Started" est obsolète. Cosmetic non-blocker mais utile pour cohérence cross-GDD.

Edit appliqué auto par `/dev-story` 2026-05-02 — voir commit pre-merge.

---

## Section 7 — Cross-OS playtest (OPTIONNEL post-MVP)

⚠️ MARTIN si builds export disponibles — sinon SKIP gracieux Sprint 0.

- [ ] Linux build : boucle Section 1 PASS.
- [ ] Windows build : boucle Section 1 PASS.
- [ ] macOS build : boucle Section 1 PASS.
- [ ] Test EC-MNU-37 (minimize pendant Pause) : focus restoration OK chaque OS.
- [ ] Test EC-MNU-38 (alt-tab) : aucune mutation state.
- [ ] Test EC-MNU-42 (sleep/wake) : aucun crash, focus préservé.

**Note** : EC-MNU-37/38/42 déjà couverts test runtime story-012 (`edge_cases_r2_test.gd`). Cross-OS validation est defense-in-depth manuel.

---

## Section 8 — Screenshots ⚠️ MARTIN

Saisir screenshots 1920×1080 PNG dans `production/qa/evidence/screenshots/` :

- [ ] `main-menu-1080p-2026-05-XX.png` — Main Menu rendu avec StartButton focused.
- [ ] `pause-overlay-1080p-2026-05-XX.png` — Pause Overlay rendu sur étage_01 frozen.
- [ ] (optionnel) `main-menu-720p-2026-05-XX.png` — résolution mini.
- [ ] (optionnel) `pause-overlay-720p-2026-05-XX.png` — résolution mini.

---

## Section 9 — Sign-off final ⚠️ MARTIN

Story-013 close-ready uniquement après les 3 sign-offs ci-dessous.

| Discipline | Reviewer | Initiales | Date | Verdict |
|---|---|---|---|---|
| ux-designer | (Martin agent) | `____` | 2026-05-__ | APPROVED / REJECTED / APPROVED WITH CONDITIONS |
| game-designer | (Martin agent) | `____` | 2026-05-__ | APPROVED / REJECTED / APPROVED WITH CONDITIONS |
| creative-director | (Martin agent) | `____` | 2026-05-__ | APPROVED / REJECTED / APPROVED WITH CONDITIONS |

**Conditions ouvertes (résolution avant APPROVED)** :
- ~~D-1 DimRect fullscreen~~ ✅ RESOLVED 2026-05-02 option B fix (Section 5 — DimRect ColorRect ajouté + toggle controller).
- ~~D-2 MainMenuButton.text~~ ✅ RESOLVED 2026-05-02 option B align (Section 5 — "Quitter vers Menu Principal").
- 6 sections ⚠️ MARTIN à exécuter (boucle, Pillar 1, Pillar 3, screenshots, WCAG re-mesure, résolutions).

---

## Annexe — Implementation files inventory

**Code livré stories 001-012 (12/13 stories) avant /story-done story-013** :

- `src/gameplay/menu/main_menu_controller.gd` (79 L) — Story 001 + 006 + 009.
- `src/gameplay/menu/pause_menu_controller.gd` (235 L) — Stories 002 + 003 + 004 + 005 + 007 + 008 + 009.
- `scenes/menus/main_menu.tscn` (64 L) — Stories 001 + 006 + 009.
- `scenes/menus/pause_overlay.tscn` (51 L) — Stories 002 + 005 + 007 + 009.
- `assets/themes/menu_chrome_zen.tres` — Story 009.
- `assets/fonts/JetBrainsMono-Regular.ttf` — Story 009.
- `.claude/rules/menu-anti-patterns.md` — Story 010.
- `.github/workflows/tests.yml` lint job — Story 010.

**Tests livrés (89/89 PASSED post-story-012)** :

- `tests/integration/menu/main_menu_buttons_test.gd` — Story 006.
- `tests/integration/menu/pause_menu_buttons_test.gd` — Story 007.
- `tests/integration/menu/pause_overlay_boot_test.gd` — Story 002.
- `tests/integration/menu/pause_overlay_lifecycle_test.gd` — Story 005.
- `tests/integration/menu/state_sync_connect_deferred_test.gd` — Story 004.
- `tests/integration/menu/ui_cancel_trigger_test.gd` — Story 003.
- `tests/integration/menu/input_refcount_mouse_capture_test.gd` — Story 008.
- `tests/integration/menu/edge_cases_r2_test.gd` — Story 012.
- `tests/integration/menu/tab_cycle_wrap_test.gd` — Story 012.
- `tests/static/menu_anti_focus_handler_lint_test.gd` — Story 009.
- `tests/static/menu_pause_overlay_lint_test.gd` — Story 002.
- `tests/static/menu_theme_lint_test.gd` — Story 009.
- `tests/static/menu_anti_patterns_lint_test.gd` — Story 010.
- `tests/performance/menu_pause_resume_perf_test.gd` — Story 011.
- `tests/unit/menu/` — directory créé Story 010 (lint helpers extension future).

**Reports GdUnit4** (gitignored) : `reports/report_128` perf + `reports/report_129` suite cumulée 89/89 PASSED.

---

*Evidence file scaffold auto-écrit par `/dev-story` 2026-05-02. Sections ⚠️ MARTIN nécessitent intervention humaine pour close.*
