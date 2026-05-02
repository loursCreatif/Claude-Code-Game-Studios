# Epic: Menu System

> **Layer**: Presentation (UI)
> **GDD**: `design/gdd/menu-system.md` (Designed r2 full → APPROVED r2 par fresh `/design-review` lean 2026-04-28 commit `3c518a3` — header GDD à bumper en cosmetic follow-up)
> **Architecture Module**: `MenuSystem` (`docs/architecture/architecture.md` ligne 159 — Feature Layer Game Systems table : "main menu, pause menu, settings menus")
> **Status**: Ready
> **Stories**: 13 created (all Ready — 7 Integration + 3 Logic + 2 UI + 1 Config/Data + 1 Visual/Feel)

## Stories

| # | Story | Type | Status | ADR governing |
|---|-------|------|--------|---------------|
| 001 | [Main Menu scene skeleton + boot lifecycle](story-001-main-menu-scene-skeleton.md) | UI | **Complete** (2026-04-28) | ADR-0007 D-5 §a + D-9 |
| 002 | [Pause Overlay scene skeleton + lifecycle boot](story-002-pause-overlay-scene-skeleton.md) | UI | Ready | ADR-0007 D-4 |
| 003 | [Trigger ESC `ui_cancel_pressed` pause/resume](story-003-ui-cancel-trigger-pause-resume.md) | Integration | Ready | ADR-0004 D-4 + ADR-0007 D-2 |
| 004 | [State sync `state_changed` CONNECT_DEFERRED + guard](story-004-state-sync-connect-deferred.md) | Integration | Ready | ADR-0007 D-9 + r2 BLK-1/BLK-3 |
| 005 | [`_apply_visibility(show, recapture_mouse)` r2 BLK-2 + tree_exiting](story-005-apply-visibility-recapture-mouse.md) | Logic | Ready | ADR-0007 + r2 BLK-2 |
| 006 | [Boutons MainMenu — Start Run + Quitter le jeu](story-006-main-menu-buttons-start-quit.md) | Integration | Ready | ADR-0007 D-10 + ADR-0010 R-SAV-9 |
| 007 | [Boutons PauseMenu — Resume + MainMenu + Quit (release-before-transition)](story-007-pause-menu-buttons-resume-mainmenu-quit.md) | Integration | Ready | ADR-0007 D-10 + ADR-0004 D-4 |
| 008 | [Refcount InputManager + Mouse capture coordination](story-008-input-refcount-mouse-capture.md) | Integration | Ready | ADR-0004 D-4 + r2 G-10 |
| 009 | [Chrome Zen Theme — Typography + Palette + Button states](story-009-chrome-zen-theme-typography.md) | UI | Ready | (none Menu-specific) |
| 010 | [Anti-patterns lint static — 8 grep + anti-deps + SaveLoad zero-ref](story-010-anti-patterns-lint-static.md) | Config/Data | Ready | ADR-0007 D-4 + ADR-0010 R-SAV-9 |
| 011 | [Performance F-MNU-1 — pause/resume headless P95+P99 < 100 ms](story-011-performance-headless-pause-resume.md) | Logic | Ready | ADR-0001 + ADR-0007 D-9 + ADR-0004 D-3 |
| 012 | [Edge cases r2 PRE-IMPL/POLISH — EC-MNU-36..42 + tab cycle wrap](story-012-edge-cases-r2-pre-impl-polish.md) | Logic | Ready | ADR-0007 D-2 + ADR-0004 D-7 + ADR-0010 R-SAV-8 |
| 013 | [Bidirectional integration playtest + UX specs alignment](story-013-bidirectional-integration-playtest.md) | Visual/Feel | Ready | (manual sign-off) |

**Pickup order recommandé** : 001+002 parallèle (skeletons) → 005 (signature `_apply_visibility`) → 003+004 parallèle (trigger ESC + state sync) → 006+007+008 parallèle (boutons + refcount) → 009 (Theme) → 010 (lints CI activated) → 011 (perf bench) → 012 (edge cases) → 013 (playtest finalize).

## Overview

Menu System orchestre les **deux surfaces de friction structurées** entre le joueur et le moteur de jeu : le **Main Menu** (scène-container `res://scenes/menus/main_menu.tscn` chargée via `GSM.request_scene_transition` ADR-0007 D-5 §a — 2 boutons : Start Run + Quitter le jeu) et le **Pause Overlay** (scène-locale `res://scenes/menus/pause_overlay.tscn` instanciée par chaque scène d'étage en `CanvasLayer.layer = 80` `PROCESS_MODE_ALWAYS` — 3 boutons : Reprendre + Quitter vers Menu Principal + Quitter le jeu). Le Menu est un **consommateur d'API et un afficheur passif** — zéro logique gameplay, zéro signal outbound, zéro persistance, zéro SFX MVP. Il consume 4 des 5 verbes figés GSM (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`) + signal `state_changed` CONNECT_DEFERRED + signal `ui_cancel_pressed` ADR-0004 D-4 + APIs Input refcount `request_disable/release_enable_request(&"PauseMenu")` + `set_mouse_captured(bool)`. Trigger ESC = signal `ui_cancel_pressed` (event-driven, pas polling). Le Pause Overlay est node-local (R-MNU-3) — pas autoload — instancié par la scène d'étage. Save-on-quit délégué intégralement à Save/Load r1 (R-MNU-19 — handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` autonome côté SaveLoad). Sert **Pillar 1 FLOW AVANT TOUT** primaire (pause/resume snap < 100 ms — F-MNU-1 ; anti-friction ESC ; zero confirm dialog ; zero tween) + **Pillar 3 UNE SECONDE CHANCE** par soustraction (matrice ADR-0007 D-2 interdit Pause pendant `RESPAWNING`). Composition zero-gameplay-logic = contrainte architecturale dure (R-MNU-18 anti-deps strictes Level/Combat/Movement/Credit/Secret/Upgrade).

## Governing ADRs

Aucun ADR Menu-spécifique n'est requis MVP — le Menu est un **système UI orchestré par contrats upstream** (cf. décision analogue Shop epic 2026-04-28). La surface architecturale est minimale : 2 scènes Control + 5 boutons + 1 handler `state_changed` + 1 handler `ui_cancel_pressed`. Trigger ADR escalation : si introduction Settings Menu Tier 2+ (OQ-MNU-3 — input remap, audio sliders, fullscreen toggle) avec persistance custom, OU si Pause Menu devient autoload (rejeté MVP par R-MNU-3, OQ-MNU-5 RESOLVED).

ADRs hérités gouvernant l'implémentation Menu :

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| **ADR-0004** Input API + Focus Handling | D-3 swap pattern InputManager (T_in ≤ 1 tick physique pour F-MNU-1) ; D-4 signal `ui_cancel_pressed` toujours émis même `enabled == false` (R-MNU-5 trigger ESC) ; refcount `request_disable/release_enable_request(&"PauseMenu")` (R-MNU-13) ; tree_exiting auto-cleanup CONNECT_ONE_SHOT ; `set_mouse_captured(bool)` API (R-MNU-12) | LOW |
| **ADR-0007** GameStateManager + Scene Transition | D-2 matrice états interdit Pause pendant `RESPAWNING`/`BOSS_DEFEATED`/`MENU` (R-MNU-7 + EC-MNU-1/4) ; D-4 process_mode discipline (`PROCESS_MODE_ALWAYS = 3` Godot 4.6 enum — erratum 2026-04-28 commit `3c518a3` ; Pause Overlay reçoit input sous tree paused) ; D-5 §a two-path scene container (main_menu.tscn via `change_scene_to_file`) ; D-9 pull pattern `get_current_state() -> State` au `_ready()` (R-MNU-1) ; D-10 5 verbes publics figés (Menu utilise 4) ; signal `state_changed(new_state: State)` SYNC consommé via CONNECT_DEFERRED côté Menu (R-MNU-4 race fenêtre `paused=true` propagation asynchrone) | LOW |
| **ADR-0010** Save/Load Persistence (ConfigFile Ratification) | R-SAV-9 handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` autonome SaveLoad (R-MNU-19 délégation pure save-on-quit) + R-SAV-8 PROCESS_MODE_ALWAYS reçoit notification même `paused=true` + R-SAV-5 write-through synchrone zéro RAM dirty + ADR-0007 D-1 autoload pos-3 garanti vivant frame quit. **Le Menu ne référence jamais SaveLoad APIs** (AC-MNU-57 BLOCKING grep enforce). | MEDIUM |

**Engine Risk global Epic** : LOW (architecture.md ligne 111 confirms ; aucune API Godot post-cutoff utilisée — `Control` + `Button` + `CanvasLayer` + `change_scene_to_file` + `get_tree().paused` + `Input.set_mouse_mode` stables Godot 3.x ; `Theme` + `StyleBoxFlat` stables Godot 4.0+ ; **risque Godot 4.6** : `PROCESS_MODE_ALWAYS = 3` enum value vérifié post-erratum cross-session — AC-MNU-58 ADVISORY grep `process_mode` count exact + AC-MNU-37 BLOCKING valeur enum littérale).

## GDD Requirements

Note registry : aucune entrée `TR-mnu-*` n'existe dans `docs/architecture/tr-registry.yaml` (registry contient seulement `cam`/`cmb`/`gc`/`inp`/`lvl`/`mov` — peuplé par `/architecture-review` r1-r5 sur systèmes Foundation/Core déjà traversés ; cohérent avec Shop epic + Upgrade epic récents). Stories devront référencer directement les sections GDD (`R-MNU-N`, `F-MNU-N`, `EC-MNU-N`, `AC-MNU-N`, `K.N`) plutôt que des TR-IDs registry. **Action follow-up post-Sprint 1** : ajouter `TR-mnu-001` à `TR-mnu-018` (mapping 1-pour-1 sur R-MNU-1..18) au registry lors d'une prochaine `/architecture-review` rotation.

### Core Rules (18 R-MNU)

| Section GDD | Requirement | Couverture |
|-------------|-------------|------------|
| R-MNU-1 | MainMenuController node-local scène container `main_menu.tscn` ; PauseMenuController node-local enfant scène étage (R-MNU-3) — pas autoload | GDD seul ✅ |
| R-MNU-2 | Two-path scene architecture : `main_menu.tscn` Control fullscreen via `GSM.request_scene_transition` ; `pause_overlay.tscn` overlay node-local CanvasLayer.layer=80 | ADR-0007 D-5 §a ✅ |
| R-MNU-3 | Pause Overlay node-local — instancié par chaque scène étage à son `_ready()`, `PROCESS_MODE_ALWAYS = 3` set programmatique (R-18) | ADR-0007 D-4 ✅ |
| R-MNU-4 | Signal `state_changed` consommé via CONNECT_DEFERRED côté Menu (race fenêtre `paused=true` propagation asynchrone GSM) | ADR-0007 D-10 + r2 BLK-1 ✅ |
| R-MNU-5 | Trigger ESC = signal `ui_cancel_pressed` ADR-0004 D-4 (event-driven, pas `Input.is_action_pressed` polling). Toujours émis même `enabled == false`. | ADR-0004 D-4 ✅ |
| R-MNU-6 | Pull pattern `GSM.get_current_state() -> State` au `_ready()` Menu (pas lecture directe `State.*`) | ADR-0007 D-9 ✅ |
| R-MNU-7 | Matrice transitions interdites — Menu inerte pendant `RESPAWNING`/`BOSS_DEFEATED`/`MENU` (EC-MNU-1/4) | ADR-0007 D-2 ✅ |
| R-MNU-8 | Pas de Continue MVP — bouton "Start Run" appelle `GSM.start_etage(1)` toujours fresh ; pas de save state run-in-progress | GDD r2 + R-MNU-19 ✅ |
| R-MNU-9 | Pas de Settings Menu MVP — input remap + audio sliders + fullscreen toggle = OQ-MNU-3 Tier 2+ | OQ-MNU-3 latent ✅ |
| R-MNU-10 | Visibility snap zero tween (R-MNU-15) — Pause Overlay `visible = true/false` immédiat ; pas de fade in/out | F-MNU-4 ✅ |
| R-MNU-11 | Boutons sans confirm dialog (R-MNU-16 — anti-Pillar 1 friction) — "Quitter vers Menu Principal" + "Quitter le jeu" exécutent direct | GDD seul ✅ |
| R-MNU-12 | `set_mouse_captured(bool)` coordination — `false` à ouverture menu, `true` à fermeture vers PLAYING (R-MNU-20 API publique r2) | ADR-0004 D-4 ✅ |
| R-MNU-13 | Refcount InputManager `request_disable(&"PauseMenu")` à open + `release_enable_request(&"PauseMenu")` à close — Pause Overlay uniquement, Main Menu exempté | ADR-0004 D-4 ✅ |
| R-MNU-14 | Pause Overlay `PauseLayer` (canonique r2 G-14, ex-`PauseOverlayRoot`) `CanvasLayer.layer = 80` `PROCESS_MODE_ALWAYS = 3` set programmatique au `_ready()` (pas dans .tscn — AC-MNU-58 ADVISORY) | ADR-0007 D-4 + r2 G-14 ✅ |
| R-MNU-15 | Pause/Resume snap visibility binaire — `_apply_visibility(show: bool, recapture_mouse: bool = true)` signature élargie r2 BLK-2 (caller décide selon contexte) | r2 BLK-2 ✅ |
| R-MNU-16 | Pas de confirm dialog ("Êtes-vous sûr ?") — anti-Pillar 1 friction. AC-MNU-45 BLOCKING grep `AcceptDialog\|ConfirmationDialog` = 0 match | AC-MNU-45 ✅ |
| R-MNU-17 | (rejeté r2) — ID disambiguation R-MNU-17b → R-MNU-19 (G-7 r2 finalisé commit `3c518a3` lean re-pass) | r2 G-7 ✅ |
| R-MNU-18 | Anti-dependencies strictes — Menu ne référence, n'écoute, ne mute aucun de Level/Combat/Movement/Credit/Secret/Upgrade (R-MNU-18 hard contrainte architecturale) | AC-MNU-49/50 ✅ |
| R-MNU-19 | Save-on-quit délégué intégralement Save/Load r1 R-SAV-9 — Menu ne référence jamais SaveLoad APIs (rename r2 G-7 ex-R-MNU-17b). AC-MNU-57 BLOCKING grep enforce | OQ-MNU-1 RESOLVED ✅ |
| R-MNU-20 | `set_mouse_captured(bool)` API publique InputManager r2 G-10 (typed signature stable cross-system) | ADR-0004 r2 G-10 ✅ |

### Formulas (4 F-MNU)

| Formule | Description | Couverture |
|---------|-------------|------------|
| F-MNU-1 | Pause/resume snap budget : `pause_perceived_ms = T_in + T_gsm + T_def + T_ren ∈ [16.6, 50.8]` ms — Pillar 1 cible < 100 ms ; mesurabilité headless documentée r2 S-8 (T_in + T_gsm + T_def composé < 50 ms en CI sans T_ren ; AC-MNU-65 ADVISORY xvfb avec T_ren) | F-MNU-1 r2 ✅ |
| F-MNU-2 | DimRect alpha `dim_alpha = CLAMP(MENU_BG_OVERLAY_ALPHA, ALPHA_MIN_FREEZE_VISIBLE, ALPHA_MAX_CONTACT_MONDE)` — perception du freeze, **PAS lisibilité texte** (texte sur PanelContainer opaque garde 15.2:1 K.9 indépendamment) — reformulation r2 BLK-4 | F-MNU-2 r2 ✅ |
| F-MNU-3 | Tab cycle wrap déterministe `next_index = (current + 1) mod N` ; bornes N=0 (no-op) + N=1 (idempotent) explicites r2 S-13 | F-MNU-3 r2 ✅ |
| F-MNU-4 | Aucune formule de feel par négation — zero tween, zero parallax, zero gradient, zero corner_radius, zero AnimationPlayer (8 anti-patterns testables AC-MNU-44/45/46/47/48/49/50/36) | F-MNU-4 + Groupe K ✅ |

### Edge Cases (42 EC-MNU, 9 catégories)

Couvertes par GDD §Edge Cases — Catégories : ESC Triggers ×8 (EC-MNU-1..8 — RESPAWNING/transition/loading/BOSS_DEFEATED/double-press/Tab cycle/Shop ESC consume cross-GDD/double-instance), Lifecycle Pause Overlay ×7 (EC-MNU-9..15 — instanciation manuelle/queue_free/visibility manuelle/tree_exiting race/PauseLayer naming canonique r2), Mouse Capture ×4 (EC-MNU-16..19 — capture pendant transition/recapture timing/Tier 2+ hover toggle/quit_app pas recapture), State Sync ×6 (EC-MNU-20..25 — CONNECT_DEFERRED 1-frame skid/state non-state_changed event/PRE_READY connect race), Performance ×4 (EC-MNU-26..29 — frame drop spike pause / first-frame Theme load), Anti-patterns Cross-GDD ×4 (EC-MNU-30..33 — Shop ESC ownership / HUD layer collision / Audio ducking peer / Save/Load handler peer), **r2 PRE-IMPL/POLISH NEW ×7 (EC-MNU-36..42)** : quit pendant LOADING (S-3), minimize OS (S-5), sleep/wake OS (S-6), controller hot-plug (S-7), PRE_READY connect race (S-12), zero-instance lint (G-6/G-9), dual-monitor focus loss.

### Acceptance Criteria (68 ACs r2 finalisé, 13 catégories A-M)

49 BLOCKING + 20 ADVISORY (1 PROVISIONAL Tier 2+ K.10 quit-flow.md NOT-blocking MVP). Couvertes par GDD §Acceptance Criteria — Groupes : A Boot & Lifecycle Main Menu ×6 (AC-MNU-1..6 incl. AC-MNU-5b autoload grep r2), B Lifecycle Pause Overlay ×7 (AC-MNU-7..13 incl. PauseLayer renaming r2), C Trigger ESC / ui_cancel ×8 (AC-MNU-14..21), D Boutons MainMenu ×6 (AC-MNU-22..27), E Boutons PauseMenu ×7 (AC-MNU-28..34 incl. AC-MNU-32 release_called_before_transition timestamp r2), F Input refcount discipline ×6 (AC-MNU-35..40), G Mouse capture coordination ×5 (AC-MNU-41..45), H State sync via state_changed ×6 (AC-MNU-46..51), I Process_mode discipline ×5 (AC-MNU-52..56), J Performance & timing ×4 (AC-MNU-40 Logic + AC-MNU-41 P95 + AC-MNU-42 warmup baseline + AC-MNU-65 manual rendu actif), K Anti-patterns testables ×8 (AC-MNU-44..50 + AC-MNU-36 zero tween), L Cohérence Chrome Zen ×4 (AC-MNU-66 bg_color_2 lint resources r2), M Layer convention ×3, **+r2 NEW ACs** : AC-MNU-57 BLOCKING grep zero `SaveLoad|save_int|save_string_array|save_now` enforce R-MNU-19 délégation + AC-MNU-58 ADVISORY grep `process_mode` exact 1 match (R-MNU-14 héritage corollaire) + AC-MNU-59 zero/double-instance lint + AC-MNU-60 Shop ESC consume cross-GDD + AC-MNU-61 tab cycle wrap inverse + AC-MNU-62 visible=true authoring + AC-MNU-63 NOTIFICATION_WM_WINDOW_FOCUS + AC-MNU-64 Animation/Tween defense profondeur + AC-MNU-65 ADVISORY perf rendu actif xvfb + AC-MNU-66 bg_color_2 lint + AC-MNU-67 DEBUG_SHOW_VERSION lint.

### UI Requirements (10 sous-thèmes K.1-K.10)

Couvertes par GDD §UI Requirements — K.1 Layout Main Menu (1080p + 720p + ultrawide 21:9/32:9 + portrait + safe-area r2 U-1), K.2 Layout Pause Menu (PanelContainer 360×~280 padding 80), K.3 Typographie JetBrains Mono 28/15/13/11 px (11px debug-only r2 U-2 + AC-MNU-67), K.4 Palette tokens MENU_BG_BLACK #050608 / MENU_PANEL_BG #0A0A12 / MENU_TEXT_BASE #E8E8F0 / MENU_ACCENT_CYAN #3EE4FF + token split RGB/ALPHA r2 U-3, K.5 États boutons 5 états max snap (Normal/Hover/Focus/Pressed/Disabled) + Hover↔Focus coexistence Godot 4.6 dual r2 U-4, K.6 Navigation Tab+ESC + Space bar natif + remap accelerators Tier 2+ r2 U-5, K.7 Transitions snap CONNECT_DEFERRED précision r2 U-6, K.8 Cohérence Chrome Zen 8 anti-patterns testables (zero corner_radius / gradient / glow / parallax / SFX / confirm / Engine.time_scale / get_tree().paused hors GSM) + bg_color_2 anti-pattern r2 U-7, K.9 Accessibilité Tier 1 WCAG AAA 15.2:1 + prefers-reduced-motion r2 U-8, K.10 UX flag specs UX requises avant `/create-epics` — **K.10 SATISFAIT** : `design/ux/main-menu.md` r1 (294 lignes, 11 AC-UX-MM) + `design/ux/pause-menu.md` r1 (357 lignes, 18 AC-UX-PM) livrés 2026-04-27 (`d6279a7`) ; `quit-flow.md` Tier 3 Steam-only NOT-blocking MVP (commit `3c518a3` confirmation).

## Dependencies

### Hard (Menu ne peut pas fonctionner sans)

| Système | Direction | Status | Contrat |
|---------|-----------|--------|---------|
| **GameStateManager** | Bidir (Hard) | ✅ APPROVED r1 | **Out** : 4 verbes consumés (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`). **In** : `state_changed(new_state: State)` SYNC consommé via CONNECT_DEFERRED + pull `get_current_state()` au `_ready()` (ADR-0007 D-9). Verbe `request_new_run` non utilisé MVP. |
| **Input System (InputManager)** | Bidir (Hard) | ✅ ADR-0004 Accepted (r6 NEEDS REVISION mineur — structure PASS) | **In** : signal `ui_cancel_pressed` toujours émis (R-MNU-5 trigger ESC). **Out** : `set_mouse_captured(bool)` (R-MNU-12, R-MNU-20) + `request_disable/release_enable_request(&"PauseMenu")` refcount Pause Overlay seul (R-MNU-13). |
| **Godot SceneTree** | In (Hard) | ✅ Stable | `change_scene_to_file("res://scenes/menus/main_menu.tscn")` + `get_tree().paused` lecture seule (mutation ownership GSM uniquement, AC-MNU-50) + `tree_exiting` auto-cleanup signal Pause Overlay tear-down. |

### Soft

| Système | Direction | Status | Lien |
|---------|-----------|--------|------|
| **Save/Load System** | Peer (Indirect) | ✅ Designed r1 + ADR-0010 Accepted | Save-on-quit délégation pure R-MNU-19 — `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` autonome côté SaveLoad ; `get_tree().quit()` Menu déclenche notification mais Menu ne référence jamais APIs SaveLoad (AC-MNU-57 BLOCKING grep enforce). OQ-MNU-1 RESOLVED par cascade. |
| **Audio System** | Peer (None) | ✅ APPROVED r2.1 | Audio écoute `state_changed` pour ducking Music −12 dB en PAUSED (audio-system.md r2.1) — **owned Audio**, pas Menu. Menu zéro SFX MVP (AC-MNU-44 BLOCKING grep `AudioStreamPlayer*` = 0). Tier 2+ amendement Audio r2.2 bus `MENU_UI` latent (OQ-MNU-2). |

### Peers (no-conflict)

| Système | Direction | Status | Note |
|---------|-----------|--------|------|
| **HUD System** | Peer | ✅ Designed r1 | HUD masque `CreditCounterLabel` en PAUSED via son propre handler (HUD r1 Rule 10) — Menu ne coordonne rien. Layer convention HUD=50 < Pause=80 (AC-MNU-mn Layer convention). |
| **Shop System** | Peer | ✅ Designed r2.1 | Shop bouton Continuer appelle `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")` — Menu reçoit transition passive. Shop ESC consume ownership cross-GDD AC-MNU-60 (Pause Overlay pas spawn pendant Shop modal). |
| **Camera System** | Peer | ✅ APPROVED | `main_menu.tscn` sans Camera3D MVP (fond ColorRect 2D suffisant). Tier 2+ Camera décorative ownée Menu local. |

### Anti-deps (zéro reference — R-MNU-18 contrainte architecturale dure)

Level System, Player Combat, Player Movement, Credit Economy, Secret System, Upgrade System — lint statique cover-all (AC-MNU-49/50 grep + Q-7 process_mode runtime override + Q-9 regex grep redondante). Toute future référence requiert amendement GDD r3.

### Bidirectional Check (4/4 PASS)

- GSM r1 §Dependencies Downstream cite "MenuSystem inferred Not Started" — réciprocité formelle confirmée par Menu r2 (GSM peut promote en amendement éditorial cosmétique post-`/create-epics`)
- InputManager r6 one-way consumer ADR-0004 D-4
- HUD r1 peer no-conflict layer convention
- Shop r2.1 cite Menu sibling target `main_menu.tscn`

## Definition of Done

This epic is complete when :

- [ ] All stories implémentées, reviewed, et closed via `/story-done`
- [ ] All 68 ACs vérifiés (49 BLOCKING + 20 ADVISORY)
- [ ] **Lifecycle Main Menu** : `main_menu.tscn` chargé via `change_scene_to_file` (R-MNU-2) + 2 boutons Start Run/Quitter le jeu fonctionnels — AC-MNU-1..6 + AC-MNU-22..27 PASS
- [ ] **Lifecycle Pause Overlay** : `pause_overlay.tscn` instancié node-local par scène étage (R-MNU-3) avec `PauseLayer.layer = 80` `PROCESS_MODE_ALWAYS = 3` set programmatique au `_ready()` (R-MNU-14 + R-18) — AC-MNU-7..13 + AC-MNU-58 ADVISORY PASS
- [ ] **Trigger ESC discipline** : signal `ui_cancel_pressed` consommé par PauseMenuController uniquement (R-MNU-5) ; pas de `Input.is_action_pressed("ui_cancel")` polling — AC-MNU-14..21 PASS
- [ ] **State sync CONNECT_DEFERRED** : handler `_on_state_changed` connecté via `CONNECT_DEFERRED` au `state_changed` GSM (R-MNU-4 r2 BLK-1 race fenêtre) + pull `get_current_state()` au `_ready()` (R-MNU-6 ADR-0007 D-9) — AC-MNU-46..51 PASS
- [ ] **`_apply_visibility(show, recapture_mouse=true)` signature élargie r2 BLK-2** : caller décide selon contexte (resume=true, quit_to_menu=false, quit_app=false) ; AC-MNU-32 release_called_before_transition timestamp PASS
- [ ] **Guard `is_inside_tree()` r2 BLK-3** ajouté dans `_apply_visibility` + `_on_state_changed` (race CONNECT_DEFERRED pendant `change_scene_to_file` tree_exiting)
- [ ] **Refcount InputManager** : `request_disable(&"PauseMenu")` à open + `release_enable_request(&"PauseMenu")` à close ; Main Menu exempté (R-MNU-13) — AC-MNU-35..40 PASS
- [ ] **Mouse capture coordination** : `set_mouse_captured(false)` à open Pause + `set_mouse_captured(true)` à resume ; main_menu→Pause exempté (R-MNU-12 + R-MNU-20) — AC-MNU-41..45 PASS
- [ ] **Save-on-quit délégation pure (R-MNU-19)** : aucune référence SaveLoad APIs côté Menu — AC-MNU-57 BLOCKING grep `SaveLoad|save_int|save_string_array|save_now` = 0 match dans `src/gameplay/menu/`
- [ ] **Anti-patterns testables (Groupe K)** : 8 grep statiques PASS — zero SFX (AC-MNU-44), zero confirm dialog (AC-MNU-45), zero corner_radius (AC-MNU-46), zero Parallax/AnimationPlayer (AC-MNU-47), zero gradient (AC-MNU-48), zero Engine.time_scale (AC-MNU-49), zero get_tree().paused mutation hors GSM (AC-MNU-50), zero tween (AC-MNU-36)
- [ ] **Performance F-MNU-1** : AC-MNU-40 Logic headless `T_in + T_gsm + T_def < 50 ms` 60 runs P95 + AC-MNU-41 P95+P99+max < 100 ms + AC-MNU-42 warmup baseline 10+100 + AC-MNU-65 ADVISORY rendu actif xvfb (T_in + T_gsm + T_def + T_ren < 100 ms)
- [ ] **Tab cycle wrap (F-MNU-3)** : navigation déterministe N=0 no-op + N=1 idempotent + N=3 wrap forward+inverse — AC-MNU-61 PASS
- [ ] **Cohérence Chrome Zen Groupe L** : palette tokens K.4 + JetBrains Mono 28/15/13/11 px K.3 + 11px debug-only AC-MNU-67 DEBUG_SHOW_VERSION + bg_color_2 anti-pattern AC-MNU-66 lint resources
- [ ] **Layer convention (Groupe M)** : `PauseLayer.layer = 80` exact ; HUD=50 < Pause=80 < GSM fade=100 — vérification cross-GDD
- [ ] **r2 PRE-IMPL/POLISH NEW ECs (EC-MNU-36..42)** : 7 ECs couverts par tests ou par playtest manuel (quit pendant LOADING / minimize / sleep-wake / controller hot-plug / PRE_READY race / zero-instance lint / dual-monitor focus loss)
- [ ] **Anti-deps R-MNU-18** : grep statique zero match Level/Combat/Movement/Credit/Secret/Upgrade dans `src/gameplay/menu/`
- [ ] **UX specs alignment** : implémentation conforme aux 11 AC-UX-MM + 18 AC-UX-PM des fichiers `design/ux/main-menu.md` + `design/ux/pause-menu.md`
- [ ] **Bidirectional check post-impl** : amendement éditorial GSM r1 §Dependencies Downstream (MenuSystem inferred Not Started → APPROVED r2 / Implemented Sprint A) — cosmetic non-blocker

## Open Items / Follow-ups

- **OQ-MNU-1 RESOLVED r2** : save-on-quit délégation pure ratifiée Save/Load r1 R-SAV-9 + ADR-0010. Aucune action.
- **OQ-MNU-2 Bus audio `MENU_UI` Tier 2+** : amendement Audio r2.2 latent. Hors scope Sprint A.
- **OQ-MNU-3 Settings Menu Tier 2+ scope** : input remap + audio sliders + fullscreen toggle. Latent — décision creative-director Sprint Tier 2+.
- **OQ-MNU-4 Splash screen Godot logo** : décision boot first impression. Latent — Polish phase.
- **OQ-MNU-5 RESOLVED r1** : Pause Menu node-local pas autoload (R-MNU-3). Aucune action.
- **OQ-MNU-6 RESOLVED r2** : Quit shortcut Alt+F4 / Cmd+Q par cascade OQ-MNU-1. Aucune action.
- **OQ-MNU-7 Confirm dialog future-proof exception (épilepsie / parental advisory)** : Latent. Hors scope MVP.
- **OQ-MNU-8 Localization fallback strategy** : Latent. Hors scope MVP. Risque flagué : "Quitter vers Menu Principal" 27 chars FR proche limite Tier 2+ monitoring.
- **OQ-MNU-9 Pause overlay layer collision avec future cinematic / cutscene Tier 2+** : Latent.
- **OQ-MNU-10 Boot directement sur étage gameplay (skip Main Menu) — debug feature** : Latent. CLI flag dev-only Polish phase.
- **3 BLOCKING résiduels lean re-pass r2 (commit 3c518a3 commentaires)** : (a) S-02 BUTTON_MIN_WIDTH_PX=220 math marge ~37 px à font 15px texte le plus long "Quitter vers Menu Principal" 27 chars × 9px = 243 px ; (b) S-03+B-01+B-06 tree_exiting guard chains à compléter ; (c) S-04 AC-MNU-36 anti-tween regex AnimationPlayer scripts. Lean re-pass commit `3c518a3` les a fermés en éditorial cosmétique — vérification post-impl pour confirmer non-régression.
- **SHIP-CRITICAL résolu cross-session 2026-04-28** : Godot 4.6 enum `Node.PROCESS_MODE_ALWAYS = 3` (pas 5 — invalid value, pas 4 = `PROCESS_MODE_DISABLED`) ; R-MNU-14 + AC-MNU-10 + AC-MNU-37 + Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` corrigés par session voisine pendant lean re-pass — sans ce fix, ACs Static BLOCKING auraient validé valeur enum invalide build et runtime aurait Pause boutons morts. Cf. commit `a25514f` (shop story-001 erratum) + `3c518a3` (Menu lean re-pass).
- **Action follow-up post-Sprint A** : amendement éditorial GSM r1 §Dependencies Downstream (MenuSystem inferred → APPROVED r2 / Implemented).
- **Action follow-up post-Sprint 1** : ajouter TR-mnu-001..018 au tr-registry.yaml lors de prochaine `/architecture-review` rotation pour cohérence cross-system.
- **Action follow-up cosmetic** : bumper status header GDD `design/gdd/menu-system.md` ligne 3 — "Designed r2 (full) ; pending fresh `/design-review` lean re-pass" → "APPROVED r2 (full — 2026-04-28 fresh lean re-pass commit `3c518a3`)" + bump systems-index.md row 18 cohérent. Pre-`/create-stories` ou pre-`/dev-story` selon préférence.

## Next Step

Run `/create-stories menu-system` to break this epic into implementable stories. Décomposition prévisionnelle ~10-14 stories cluster :

- **C1 Architecture & Boot** — `main_menu.tscn` skeleton + `pause_overlay.tscn` skeleton + autoload check zero-instance (AC-MNU-5b) + PauseLayer canonical naming + R-MNU-1/2/3/14 + R-18 process_mode programmatique
- **C2 Trigger ESC + State Sync** — `ui_cancel_pressed` connect + `state_changed` CONNECT_DEFERRED + pull `get_current_state()` au `_ready()` + matrice transitions interdites EC-MNU-1/4 + R-MNU-4/5/6/7
- **C3 Pause Overlay Lifecycle** — `_apply_visibility(show, recapture_mouse)` signature élargie r2 BLK-2 + guard `is_inside_tree()` r2 BLK-3 + tree_exiting auto-cleanup + R-MNU-15
- **C4 Boutons MainMenu** — Start Run + Quitter le jeu callbacks + AC-MNU-22..27
- **C5 Boutons PauseMenu** — Reprendre + Quitter vers Menu Principal + Quitter le jeu callbacks + release_called_before_transition timestamp r2 + AC-MNU-28..34
- **C6 Refcount InputManager + Mouse capture** — `request_disable/release_enable_request(&"PauseMenu")` + `set_mouse_captured(bool)` coordination + R-MNU-12/13/20 + AC-MNU-35..45
- **C7 Visual Chrome Zen** — Theme + StyleBoxFlat + JetBrains Mono 28/15/13/11 px + palette tokens K.4 RGB/ALPHA split + 5 états boutons K.5 + Tab navigation K.6 + AC-MNU-66..67
- **C8 Anti-patterns lint** — 8 grep statiques (zero SFX/confirm/corner_radius/Parallax/gradient/Engine.time_scale/get_tree().paused/tween) + AC-MNU-49/50 anti-deps + AC-MNU-57 SaveLoad zero-ref + AC-MNU-58 process_mode count + AC-MNU-59 zero/double-instance lint
- **C9 Performance F-MNU-1** — AC-MNU-40 headless Logic + AC-MNU-41 P95+P99+max + AC-MNU-42 warmup + AC-MNU-65 ADVISORY xvfb rendu actif
- **C10 Edge Cases r2 PRE-IMPL/POLISH** — EC-MNU-36..42 (quit pendant LOADING / minimize / sleep-wake / controller hot-plug / PRE_READY race / zero-instance / dual-monitor focus loss) + AC-MNU-60..67 batch
- **C11 Bidirectional integration** — playtest manuel boucle complète (Main Menu → Start Run → étage → ESC → Pause → Resume → ESC → Quitter Menu Principal → Quit) + UX specs alignment AC-UX-MM/AC-UX-PM
