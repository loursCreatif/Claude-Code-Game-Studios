# UX Spec — Pause Menu

> **Status** : r1 (aligned with `design/gdd/menu-system.md` Designed r2 full — r2 cosmetic + r2 PRE-IMPL/POLISH session 2026-04-27 ; UX spec r1 reste aligné — §K.1-K.10 inchangés en r2 ; voir `reviews/menu-system-review-r2-fresh-2026-04-27.md` pour cross-session re-review note)
> **Owner** : ux-designer
> **Last Updated** : 2026-04-27
> **Related** : `design/gdd/menu-system.md` § K.2 / K.3 / K.4 / K.5 / K.6 / K.7 / K.8 / K.9 / K.10 ; `design/gdd/game-state-manager-system.md` r1 (ADR-0007 D-4 process_mode + 5 verbes) ; `design/gdd/input-system.md` r5 (ADR-0004 D-4 refcount + ui_cancel) ; `design/ux/interaction-patterns.md` (P-INP-003, P-INP-004) ; `design/accessibility-requirements.md` ; `design/art/art-bible.md`
> **Accessibility Tier** : Standard (Tier 1 obligatoire, Tier 2 AccessKit best-effort) — tiers définis par `docs/architecture/adr-0015-accessibility-interface-layer.md` D-1

---

## 1. Purpose & Player Experience

Le Pause Menu est l'**overlay `pause_overlay.tscn`** instancié dans chaque scène étage gameplay (`CanvasLayer.layer = 80`, `process_mode = ALWAYS`, `visible = false` par défaut). Son rôle UX :

- **Geler le monde sans le faire disparaître** : le DimRect alpha 0.65 (K.2) laisse voir le personnage figé, la géométrie, les ennemis pré-action. Le joueur reste connecté visuellement à sa run.
- **Permettre une reprise instantanée** : `[Reprendre]` snap, aucun fade, aucun délai. Pillar 1 FLOW.
- **Permettre une sortie sans friction** : `[Quitter vers Menu Principal]` et `[Quitter le jeu]` sans confirm modal (K.8 anti-pattern). Pillar 3 SECONDE CHANCE — la décision du joueur est respectée immédiatement.
- **Déléguer toute coordination système** : InputManager refcount (P-INP-004), GSM state (P-INP-003), Audio ducking (Audio r2.1 owned Audio peer), HUD hide (HUD r1 PAUSED hide owned HUD peer). Le Pause Menu UI ne mute aucun état non-UI directement.

Fantasy visée : « tu appuies sur ESC, le jeu s'arrête net, le monde reste là sous l'overlay, tu décides en zéro friction, tu reprends sans transition ».

---

## 2. Information Architecture

```
Pause Menu (pause_overlay.tscn — overlay node-local CanvasLayer layer 80, process_mode ALWAYS)
│
│  Activé uniquement quand GSM.state == PAUSED
│  Trigger : ESC depuis PLAYING → InputManager.ui_cancel_pressed → Menu controller → GSM.request_pause()
│
├─ [Reprendre]                          → GSM.request_resume() → PLAYING → PauseLayer.visible = false
├─ [Quitter vers Menu Principal]        → GSM.request_scene_transition("res://scenes/menus/main_menu.tscn") → run state purged → MAIN_MENU
└─ [Quitter le jeu]                     → get_tree().quit() → fermeture OS immédiate
```

**Hors scope MVP (différé Tier 2+)** :
- Sauvegarde de la run-in-progress (Save/Load r1 = upgrades persistents uniquement, aucun save mid-étage). Voir O-PM-1 / OQ-MNU-1.
- Settings inline (audio, sensitivity, accessibility, remap).
- Restart current étage (raccourci utile UX, mais hors scope MVP — différé).
- Stats current run (credits, kills, time elapsed).

---

## 3. Screen Flow

### 3.1 Entry — ESC depuis PLAYING

1. `MovementController` ou autre system gameplay actif. GSM.state = PLAYING.
2. Joueur appuie ESC → `InputManager.ui_cancel_pressed` signal émis (toujours émis même si InputManager refcount disabled, conformément ADR-0004 D-4 release pattern P-INP-004).
3. `PauseMenuControllerScript` (**node-local**, enfant direct de la scène étage — cf. GDD R-MNU-1 + R-MNU-3 + OQ-MNU-5 RESOLVED node-local, **pas autoload, pas node persistent cross-scene**) `_on_ui_cancel_pressed()` → `GSM.request_pause()`.
4. GSM transition state PLAYING → PAUSED (synchrone, < 100 ms cf. F-MNU-1) → `state_changed.emit(PAUSED)` (signal SYNC, consommé `CONNECT_DEFERRED` côté Pause).
5. `PauseMenuController._on_gsm_state_changed(PAUSED)` :
   - `PauseLayer.visible = true` snap (aucun tween).
   - `InputManager.request_disable(&"PauseMenu")` (refcount, P-INP-004).
   - `InputManager.set_mouse_captured(false)` (souris visible et libre).
   - `ResumeButton.grab_focus()` (focus initial — K.6).
6. **Première frame Pause visible ≤ 100 ms post-ESC** (Pillar 1, F-MNU-1).

### 3.2 Entry — alternative depuis menu pause programmatique (Tier 2+)

Réservé. MVP : ESC est l'unique trigger.

### 3.3 Interaction (Pause Menu actif)

- **Focus initial** : `ResumeButton`.
- **Tab order** : `ResumeButton` → `MainMenuButton` → `QuitButton` → wrap → `ResumeButton` (cf. K.6).
- **Souris** : visible et libre (mouse_mode VISIBLE). Hover affiche underline cyan K.5 ; clic active.
- **Clavier** :
  - `Tab` / `Shift+Tab` cycle.
  - `ui_confirm` (Enter / Space) active le bouton focused.
  - `ui_cancel` (ESC) **équivaut à clic Reprendre** (cf. K.6 ligne "ESC sur Pause = `GSM.request_resume()`"). Cohérence projet avec Shop r2 R-SHP-11 ("ESC = avancer").
- **Pendant Pause** : aucun input gameplay ne fonctionne (refcount disabled). Le scene tree est pausé (`get_tree().paused = true` owned GSM ou Menu — cf. OQ Pause GDD), seuls les nœuds `process_mode = ALWAYS` (Pause overlay, Audio bus ducker, GSM lui-même) tournent.

### 3.4 Exit — Reprendre

1. Clic sur `ResumeButton`, ou Enter focused, ou ESC → `GSM.request_resume()`.
2. GSM PAUSED → PLAYING → `state_changed.emit(PLAYING)` SYNC.
3. `PauseMenuController._on_gsm_state_changed(PLAYING)` :
   - `PauseLayer.visible = false` snap.
   - `InputManager.release_enable_request(&"PauseMenu")` (refcount).
   - `InputManager.set_mouse_captured(true)` (souris re-capturée gameplay).
4. **Première frame gameplay re-actif ≤ 100 ms post-input** (Pillar 1, F-MNU-1).

### 3.5 Exit — Quitter vers Menu Principal

1. Clic sur `MainMenuButton` ou Enter focused → `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")`.
2. GSM transition PAUSED → MAIN_MENU :
   - GSM fade-out 200 ms (CanvasLayer layer 100, owned GSM).
   - Pendant le fade : run state purgé par les owners (Credit reset, Movement despawn, etc. — chaque system consume `state_changed(MAIN_MENU)` et purge). Pause Menu ne fait que disparaître avec sa scène (`pause_overlay.tscn` est node-local, déchargé avec `level_XX.tscn`).
   - `main_menu.tscn` chargée → fade-in 200 ms.
3. **Aucun message "Run perdue / interrompue".** Cohérence Pillar 3.
4. **OQ-MNU-1 du GDD** : si Save/Load r2+ ajoute save run-in-progress, qui handle le save-on-quit côté UI (button click → save trigger) ? Cf. O-PM-1.

### 3.6 Exit — Quitter le jeu

1. Clic sur `QuitButton` ou Enter focused → `get_tree().quit()`.
2. Fermeture OS immédiate. Aucun confirm dialog (K.8 anti-pattern). Aucun "êtes-vous sûr ?".
3. **OQ-MNU-1 du GDD** : si Save/Load r2+ ajoute save run-in-progress, qui handle le save-on-quit ici ? Cf. O-PM-1.

---

## 4. Visual Layout

### 4.1 Wireframe (1920 × 1080 référence — overlay sur gameplay frozen)

```
┌──────────────────────────────────────────────────────────────────┐
│ [gameplay frozen visible behind DimRect — alpha 0.65]            │
│ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░  │  ← DimRect ColorRect fullscreen
│ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░  │     #000000 alpha 0.65
│ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ ┌────────────────────────────────────┐ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  PauseTitleLabel (optionnel)       │ ░ ░ ░ ░ ░ ░  │  ← PanelContainer width 360 px
│ ░ ░ ░ ░ ░ ░ ░ │  ─ "PAUSE" 13 px #6E6E8A           │ ░ ░ ░ ░ ░ ░  │     bg #0A0A12, border 1 px #2A2A3A
│ ░ ░ ░ ░ ░ ░ ░ │                                    │ ░ ░ ░ ░ ░ ░  │     padding 32 px haut/bas, 40 px gauche/droite
│ ░ ░ ░ ░ ░ ░ ░ │  ┌──────────────────────────────┐  │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  │       Reprendre              │  │ ░ ░ ░ ░ ░ ░  │  ← ResumeButton 15 px JetBrains Mono
│ ░ ░ ░ ░ ░ ░ ░ │  └──────────────────────────────┘  │ ░ ░ ░ ░ ░ ░  │     focus initial — bordure cyan rect
│ ░ ░ ░ ░ ░ ░ ░ │                                    │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  ┌──────────────────────────────┐  │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  │ Quitter vers Menu Principal  │  │ ░ ░ ░ ░ ░ ░  │  ← MainMenuButton
│ ░ ░ ░ ░ ░ ░ ░ │  └──────────────────────────────┘  │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │                                    │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  ┌──────────────────────────────┐  │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ │  │       Quitter le jeu         │  │ ░ ░ ░ ░ ░ ░  │  ← QuitButton
│ ░ ░ ░ ░ ░ ░ ░ │  └──────────────────────────────┘  │ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ └────────────────────────────────────┘ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░  │
│ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░ ░  │
└──────────────────────────────────────────────────────────────────┘
                                                          PanelContainer ancré centre-centre
                                                          ButtonContainer separation 12 px
```

### 4.2 Wireframe (1280 × 720 — résolution minimale supportée)

Identique à 4.1, sauf :
- Panel toujours width 360 px (ne rétrécit pas — sinon les 28 chars de "Quitter vers Menu Principal" ne tiennent plus).
- DimRect alpha inchangé 0.65.
- TitleLabel "PAUSE" gardé optionnellement.

### 4.3 Layout Zones

| Zone | Type | Composants | Notes |
|---|---|---|---|
| Dim layer | ColorRect fullscreen | `DimRect` | `MENU_BG_OVERLAY_ALPHA` = `Color(0,0,0,0.65)`, `mouse_filter = STOP` (capture clic-out hors panel pour empêcher le clic-through au gameplay) |
| Panel | PanelContainer ancré centre-centre | `PanelContainer` | Width 360 px, height auto. bg `MENU_PANEL_BG #0A0A12`, border 1 px `MENU_PANEL_BORDER #2A2A3A`, corner_radius = 0 |
| Title (optionnel) | Label dans PanelContainer | `PauseTitleLabel` "PAUSE" | 13 px `MENU_TEXT_SECONDARY #6E6E8A`. Décision MVP : **incluse** — aide la lisibilité 720p bas-contraste (cf. K.2 ligne "l'inclure aide la lisibilité"). Si Chrome Zen pureté préférée, supprimable Tier 2+ A/B test |
| Action area | VBoxContainer dans PanelContainer | `ButtonContainer` → `ResumeButton`, `MainMenuButton`, `QuitButton` | Separation 12 px |

### 4.4 Click-out behavior

Cliquer **hors du panel mais sur le DimRect** : aucun effet (pas de fermeture). Justification : éviter une fermeture accidentelle pendant que le joueur déplace la souris en l'air. La fermeture passe par `[Reprendre]`, ESC, ou les exits explicites.

---

## 5. States & Variants

| État | Trigger | Ce qui change |
|---|---|---|
| **Hidden (default)** | `_ready()`, ou `state_changed(state ≠ PAUSED)` | `PauseLayer.visible = false` ; `InputManager` refcount released ; `mouse_mode` géré par owner gameplay |
| **Visible (PAUSED active)** | `state_changed(PAUSED)` | Snap visible, `ResumeButton` focused, refcount disabled, mouse VISIBLE |
| **Hover (mouse)** | Souris sur un bouton | Underline cyan (K.5) |
| **Focus (clavier)** | `Tab` ou `grab_focus()` | Bordure cyan rect (K.5 distinct hover) |
| **Pressed** | `button_down` | Background bouton `#111120` 1 frame |
| **Disabled** | _N/A MVP_ | Réservé Tier 2+ (ex. Reprendre disabled si death animation owned Combat empêche resume) |
| **Resize pendant pause** | `viewport.size_changed` | Re-layout instantané, panel reste centré |
| **Focus lost** (alt-tab pendant pause) | `application_focus_lost` | Aucun changement (la pause reste pause). Au retour `application_focus_gained`, focus du dernier bouton préservé |

**Pas d'état "Loading"**, pas d'état "Error" MVP.

---

## 6. Interaction Map

Input methods : **Keyboard/Mouse primaire**. Gamepad partial Tier 2+.

| Composant | Action joueur | Input | Feedback immédiat | Outcome |
|---|---|---|---|---|
| _scène pause_ | Ouvrir | ESC depuis PLAYING | (refcount disable + visibility snap dans la frame suivante) | `GSM.request_pause()` |
| `ResumeButton` | Activer | Clic | Pressed bg | `GSM.request_resume()` |
| `ResumeButton` | Activer | Enter / Space (focused) | Idem | Idem |
| `ResumeButton` | Activer (raccourci) | ESC pendant Pause | (snap visibility off frame suivante) | `GSM.request_resume()` (cohérent K.6 + Shop R-SHP-11) |
| `ResumeButton` | Hover | Souris | Underline cyan | — |
| `ResumeButton` | Focus | `Tab`/wrap | Bordure cyan rect | — |
| `MainMenuButton` | Activer | Clic | Pressed bg | `GSM.request_scene_transition("...main_menu.tscn")` |
| `MainMenuButton` | Activer | Enter / Space (focused) | Idem | Idem |
| `MainMenuButton` | Hover | Souris | Underline cyan | — |
| `MainMenuButton` | Focus | `Tab` | Bordure cyan rect | — |
| `QuitButton` | Activer | Clic | Pressed bg | `get_tree().quit()` (immédiat) |
| `QuitButton` | Activer | Enter / Space (focused) | Idem | Idem |
| `QuitButton` | Hover | Souris | Underline cyan | — |
| `QuitButton` | Focus | `Tab` | Bordure cyan rect | — |
| `DimRect` (zone hors panel) | Clic | Clic souris | _aucun_ | _ignoré_ (cf. § 4.4 click-out behavior) |

**Patterns référencés** :
- P-INP-003 (menu navigation focus + ui_cancel)
- P-INP-004 (accessibility gating refcount — `request_disable(&"PauseMenu")` à open, `release_enable_request` à close, cleanup `tree_exited` CONNECT_ONE_SHOT)
- P-TRANS-001 (`MainMenuButton` → GSM scene transition)

**Pattern à formaliser plus tard** (cf. O-PM-2) :
- `P-MENU-PAUSE-SNAP-001` — overlay pause sans tween, propriété "le seul propriétaire d'animation est GSM (layer 100)".
- `P-MENU-NO-CONFIRM-001` — voir main-menu.md O-MM-1 (politique cross-screen).

---

## 7. Events Fired

MVP analytics scope = zéro. Hooks réservés Tier 2+ :

| Action joueur | Event Tier 2+ (réservé) | Payload | Persistent state ? |
|---|---|---|---|
| ESC déclenche Pause | `pause.opened` | `{etage_id, run_time_ms, current_credits}` | Non (Pause UI) |
| `[Reprendre]` activé | `pause.resumed` | `{paused_for_ms}` | Non |
| `[Quitter vers Menu Principal]` activé | `pause.quit_to_menu` | `{etage_id, run_time_ms, credits_lost}` | **Oui** — purge run state cross-systems (cf. § 3.5) |
| `[Quitter le jeu]` activé depuis Pause | `pause.app_quit_from_pause` | `{etage_id, run_time_ms}` | **Oui** — purge run state + OS quit |

**Persistent state writes flagged ↑** : `[Quitter vers Menu Principal]` et `[Quitter le jeu]` purgent une run en cours. **Aucun save run-in-progress MVP** (Save/Load r1 = upgrades persistents uniquement). Si Save/Load r2+ introduit save mid-étage, OQ-MNU-1 du GDD doit être résolu : qui écoute le click et déclenche le save ? Trois options évaluées dans O-PM-1 ci-dessous.

---

## 8. Transitions & Animations

**Règle K.7 absolue : aucune animation owned par le Menu.**

| Transition | Owned by | Durée | Behavior Pause |
|---|---|---|---|
| PLAYING → PAUSED (ESC) | _aucun fade_ | 0 ms (snap) | `PauseLayer.visible = true` instant. F-MNU-1 budget total < 100 ms input-to-frame |
| PAUSED → PLAYING (Reprendre) | _aucun fade_ | 0 ms (snap) | `PauseLayer.visible = false` instant |
| PAUSED → MAIN_MENU (MainMenuButton) | GSM (fade-out + load + fade-in) | 200 + load + 200 ms | Pause Menu disparait avec sa scène pendant le fade-out. Aucun feedback UI Pause pendant le fade |
| Hover (Default → Hover) | _aucune_ | 0 ms | Snap underline (K.5) |
| Focus (Default → Focus) | _aucune_ | 0 ms | Snap bordure rect (K.5) |
| Pressed | _aucune_ | 0 ms | Snap bg sombre 1 frame |
| Resize pendant Pause | _aucune_ | 0 ms | Re-layout instantané |

**Aucun spinner, aucun "Sauvegarde en cours…", aucun progress bar.** Si Save/Load r2+ introduit un save async > 16 ms, le button feedback "pressed" tient le temps du save (max ~50 ms attendu pour ConfigFile load_int_array Tier 2+ — cf. ADR-0010), puis transition GSM masque le reste.

**Reduce-motion (Tier 2+)** : aucun changement requis Pause Menu, aucune animation Menu existante. Cohérence native.

---

## 9. Data Requirements

| Donnée | Source | Read / Write | Notes |
|---|---|---|---|
| `GSM.state` | `GameStateManager.get_current_state()` (pull pattern ADR-0007 D-9) au `_ready()` | Read | Pour visibility initiale (Pause invisible si state ≠ PAUSED au boot) |
| `state_changed` signal | `GameStateManager` | Read (subscribe via CONNECT_DEFERRED) | Pour visibility toggle + focus initial |
| `ui_cancel_pressed` signal | `InputManager` | Read | Pour ESC trigger (open Pause depuis PLAYING, close Pause vers PLAYING) |
| `mouse_captured` setter | `InputManager.set_mouse_captured(bool)` | Write | Open Pause → `false` ; Close Pause → `true`. **Pas de lecture directe** — Pause owne la décision pendant son lifecycle |
| Refcount | `InputManager.request_disable(&"PauseMenu")` / `release_enable_request(&"PauseMenu")` | Write | Open / Close Pause. Cleanup auto via `tree_exited` ADR-0004 D-4 |

**Aucune donnée gameplay affichée Pause MVP** (pas de credits count, pas de timer, pas de stats). Tier 2+ pourra ajouter une mini-bandeau stats run via lecture HUD r1 controller ou Credit GDD `total_credits` (read-only).

**Save/Load r1** : Pause Menu ne consume aucun verbe SaveLoadSystem MVP. Les boutons "Quitter vers Menu Principal" et "Quitter le jeu" ne sauvegardent rien (pas de save mid-étage MVP). Cf. O-PM-1 pour évolution Tier 2+.

---

## 10. Accessibility (Tier 1 — obligatoire MVP)

Cohérent GDD § K.9. Tiers définis par ADR-0015 D-1 (`docs/architecture/adr-0015-accessibility-interface-layer.md` D-1) : **Tier 1** = baseline obligatoire MVP, **Tier 2** = expanded best-effort Sprint Polish, **Tier 3** = advanced hors scope MVP. `AccessibilityService` autoload (position #5) est la source canonique des préférences `reduce_motion` / `reduce_flash` ; le Pause Menu n'en consomme aucune directement (aucune animation à atténuer — natif conforme).

### Tier coverage par feature

| Critère | Tier ADR-0015 | Status | Implementation |
|---|---|---|---|
| Navigation clavier 100 % | Tier 1 | ✅ | `Tab`/`Shift+Tab` cycle 3 boutons, `ui_confirm` activate, `ui_cancel` = équivalent Reprendre |
| Focus initial sur action principale | Tier 1 | ✅ | `ResumeButton.grab_focus()` dans `_on_gsm_state_changed(PAUSED)` |
| Aucun élément mouse-only | Tier 1 | ✅ | Tous les boutons + sortie Pause accessibles clavier |
| Contraste texte/fond ≥ 7:1 (WCAG AAA) | Tier 1 | ✅ | `#E8E8F0` sur `#0A0A12` panel ≈ 14.8:1 ; `#3EE4FF` sur `#0A0A12` ≈ 8.6:1 ; texte sur DimRect+gameplay : panel opaque assure le contraste, jamais texte direct sur DimRect |
| Taille texte minimale | Tier 1 | ✅ | Boutons 15 px ; "PAUSE" label 13 px ; aucun texte fonctionnel < 12 px |
| Color-as-only-indicator | Tier 1 | ✅ | Focus = bordure rect (forme + couleur) ; Hover = underline (forme + couleur) |
| Aucune animation flash > 3 Hz | Tier 1 | ✅ | Aucune animation Pause (K.7) |
| `reduce_motion` | Tier 1 | ✅ natif | Pas d'animation à supprimer — Pause Menu est natif conforme sans consommer `AccessibilityService` |
| Visibilité du fait que c'est en pause | Tier 1 | ✅ | DimRect alpha 0.65 + Panel + (optionnel "PAUSE" label) — triple indicateur |
| Empêcher input gameplay accidentel | Tier 1 | ✅ | InputManager refcount disabled pendant Pause (P-INP-004) |
| ESC trapped (capture le focus système) | Tier 1 | ✅ | `process_mode = ALWAYS` + `ui_cancel_pressed` toujours émis ADR-0004 D-4 garantit que ESC ouvre Pause depuis PLAYING et ferme Pause depuis PAUSED |
| Screen reader (AccessKit best-effort) | Tier 2 | 🟡 | `Button.text` non-vide pour les 3 boutons. Si Tier 3 ajoute un label de contexte ("Menu de pause — étage X"), l'ajouter au `PauseTitleLabel.text` |
| Pause auto sur perte de focus fenêtre | Tier 2 | 🟡 | MVP : alt-tab depuis PLAYING ne déclenche pas Pause (gameplay continue de tourner sauf si focus_lost handler ailleurs). À évaluer Tier 2 — souvent attendu sur PC. Voir O-PM-3 |
| Font scaling 75-150 % | Tier 3 | ❌ | Hors scope MVP |
| Remap clavier | Tier 3 | ❌ | Hors scope MVP |

---

## 11. Localization Considerations

**Locales MVP** : FR uniquement. EN ajouté Tier 2+.

| Élément | FR | EN (provisoire Tier 2+) | Char count limit |
|---|---|---|---|
| `PauseTitleLabel.text` | "PAUSE" | "PAUSE" | 5 chars (mot identique FR/EN, retain) |
| `ResumeButton.text` | "Reprendre" | "Resume" | 9 chars FR, ~22 chars max (panel 360 px - padding 80 px = 280 px / 15 px monospace ≈ 18 chars confort) |
| `MainMenuButton.text` | "Quitter vers Menu Principal" | "Quit to Main Menu" | **27 chars FR** — proche de la limite (~28 chars max sans réduire font). Si EN→DE Tier 3 dépasse, augmenter `PanelContainer` width 360 → 420 px et re-tester breakpoint 720p |
| `QuitButton.text` | "Quitter le jeu" | "Quit game" | 14 chars FR safe |

**Risque expansion EN→DE Tier 3** :
- "Quit to Main Menu" → "Zum Hauptmenü" (13 chars) — MORE compact, safe.
- "Resume" → "Fortsetzen" (10 chars) — safe.
- Aucun risque ship-blocking immédiat.

**Élément layout-critique** : `MainMenuButton.text`. Surveillé en QA localisation Tier 2+.

**Format numérique** : aucun (Pause Menu n'affiche aucun nombre MVP). Si Tier 2+ ajoute timer run, format MM:SS locale-agnostique.

---

## 12. Acceptance Criteria

Critères UX-tester (vérifiables sans lire GDD ni code). Reformulent en perspective tester les ACs GDD § H pertinents (AC-MNU-2, AC-MNU-4, AC-MNU-5, AC-MNU-6, AC-MNU-15, AC-MNU-44 à 50).

- [ ] **AC-UX-PM-1 (perf input-to-visible)** : depuis PLAYING focus gameplay, presser ESC affiche Pause Menu visible avec `ResumeButton` focused ≤ 100 ms post-input. Mesure : timestamp ESC press → timestamp `PauseLayer.visible == true` first frame.
- [ ] **AC-UX-PM-2 (perf resume snap)** : depuis Pause active, presser Enter sur `ResumeButton` (ou ESC, ou clic) retourne à PLAYING avec input gameplay re-actif ≤ 100 ms. Pas de fade visible.
- [ ] **AC-UX-PM-3 (focus initial)** : à chaque ouverture Pause, focus est sur `ResumeButton` (pas sur le dernier bouton focused de la session précédente, pas sur le premier au sens du tree).
- [ ] **AC-UX-PM-4 (tab order)** : `Tab` cycle exactement 3 boutons dans l'ordre `Reprendre` → `Quitter vers Menu Principal` → `Quitter le jeu` → wrap → `Reprendre`. `Shift+Tab` cycle inverse. Le DimRect n'est pas focusable.
- [ ] **AC-UX-PM-5 (ESC = Reprendre)** : depuis Pause active, ESC déclenche exactement le même outcome que clic sur `ResumeButton` focused (resume PLAYING).
- [ ] **AC-UX-PM-6 (no-confirm)** : clic ou Enter sur `Quitter vers Menu Principal` ou `Quitter le jeu` n'affiche aucun dialog "Êtes-vous sûr ?". Vérification : aucun `AcceptDialog`, `ConfirmationDialog`, `PopupPanel` dans `pause_overlay.tscn`.
- [ ] **AC-UX-PM-7 (input refcount discipline)** : pendant Pause active, inputs gameplay ne fonctionnent pas (joueur ne se déplace pas, ne tire pas, etc.). Vérification : `InputManager._disable_refcount > 0` pendant Pause, retour à 0 après resume. Aucun leak refcount après plusieurs cycles open/close.
- [ ] **AC-UX-PM-8 (mouse capture coordination)** : pendant Pause active, souris est visible et libre (`mouse_mode == VISIBLE`). Après Resume, souris est re-capturée (`mouse_mode == CAPTURED`). Aucun frame intermédiaire avec mouse_mode incohérent.
- [ ] **AC-UX-PM-9 (DimRect alpha)** : DimRect color = `Color(0,0,0,0.65)` exact. Le joueur figé est partiellement visible derrière (test : capture screenshot, vérifier silhouette personnage discernable).
- [ ] **AC-UX-PM-10 (click-out ignoré)** : clic dans la zone DimRect mais hors du panel ne déclenche aucune action (pas de fermeture, pas de resume, pas de log).
- [ ] **AC-UX-PM-11 (contraste)** : `#E8E8F0` sur `#0A0A12` ≥ 7:1 ; `#3EE4FF` sur `#0A0A12` ≥ 7:1 (WCAG AAA).
- [ ] **AC-UX-PM-12 (résolutions)** : layout sans clipping ni scroll à 1280×720, 1920×1080, 2560×1440. Panel toujours centré, boutons "Quitter vers Menu Principal" entièrement visible.
- [ ] **AC-UX-PM-13 (Chrome Zen)** : aucun corner_radius > 0, aucun gradient, aucun glow, aucun parallax background dans `pause_overlay.tscn`. DimRect n'est pas un blur (alpha simple, pas de shader BackBufferCopy + blur).
- [ ] **AC-UX-PM-14 (silence)** : aucun `AudioStreamPlayer` dans `pause_overlay.tscn`. Aucun feedback sonore d'ouverture, fermeture, hover, focus, click. Cohérent Audio r2.1 (le ducking PAUSED est owned Audio peer, pas Pause Menu).
- [ ] **AC-UX-PM-15 (HUD coordination)** : pendant Pause active, le HUD r1 (layer 50) est masqué ou rendu inopérant (owned HUD peer via `state_changed(PAUSED)` consumer). Vérification : aucun élément HUD visible au-dessus du DimRect (Pause layer 80 > HUD layer 50, donc DimRect couvre HUD naturellement, et HUD doit aussi se hide).
- [ ] **AC-UX-PM-16 (process_mode discipline)** : `pause_overlay.tscn` root node `process_mode = ALWAYS`. Vérification : pendant Pause, `_unhandled_input` du Pause Menu reçoit bien les events ESC / clic / Tab. Aucun bouton "gelé".
- [ ] **AC-UX-PM-17 (purge à Quit-to-Main)** : après clic `Quitter vers Menu Principal`, run state purgé (Credit reset à 0, joueur despawné, ennemis despawnés). Vérification : retour Main Menu puis nouveau `Start Run` part d'un état initial propre.
- [ ] **AC-UX-PM-18 (no save mid-étage MVP)** : clic `Quitter le jeu` depuis Pause MVP ne déclenche AUCUN appel SaveLoadSystem. Vérification : grep `save_int\|save_string` non-appelé pendant le flow `QuitButton.pressed → get_tree().quit()`.

---

## 13. Open Questions

| ID | Question | Owner | Échéance | Notes |
|---|---|---|---|---|
| **O-PM-1** (= **OQ-MNU-1 du GDD, critique**) | Quand Save/Load r2+ ajoutera un save run-in-progress, qui handle le save-on-quit côté Pause Menu ? Trois options évaluées : (a) **Pause Menu invoque directement** `SaveLoadSystem.save_*` au click du Quit button, puis appelle `get_tree().quit()` (couple UI ↔ persistence — viole MenuSystem outbound-only ?). (b) **GSM intercepte** le scene transition via un middleware `request_quit()` qui appelle SaveLoadSystem en interne (cohérent ADR-0007 D-1 GSM autorité) — recommandé. (c) **Each system s'auto-save** sur `state_changed(MAIN_MENU)` ou `tree_exiting` (cohérent Save/Load r1 D-5 zero outbound mais requires atomic coordination). | game-designer + technical-director | **Sprint 1, AVANT** que Save/Load r2 ne propose run-mid-state save | Recommandation provisoire : option (b) — GSM owne `request_quit_with_save()` qui broadcast `state_changed(SAVING_AND_QUITTING)` → owners save → GSM `get_tree().quit()`. Pause Menu reste outbound-only (juste `request_*`) |
| O-PM-2 | Faut-il formaliser un pattern `P-MENU-PAUSE-SNAP-001` dans `interaction-patterns.md` documentant la règle "overlay pause sans tween, animations exclusively owned par GSM layer 100" ? | ux-designer | Avant `/create-epics menu-system` | Cohérence : Shop r2 et HUD r1 appliquent aussi le snap. Mérite formalisation cross-screen |
| O-PM-3 | Pause auto sur perte de focus fenêtre (`application_focus_lost`) ? Standard PC mais peut frustrer (alt-tab rapide pendant combat). MVP : non. Tier 2+ : settings toggle ? | ux-designer + game-designer | Sprint Polish Tier 2+ | Décision MVP figée : pas d'auto-pause |
| O-PM-4 | "PAUSE" title label dans le panel : conserver MVP ou supprimer pour Chrome Zen pureté ? Décision MVP : **conserver** (lisibilité 720p bas-contraste). A/B test Tier 2+ | art-director | Sprint Polish Tier 2+ | Cf. K.2 GDD — "incluse aide la lisibilité" |
| O-PM-5 | Restart-current-étage button (raccourci utile pour speedruns) Tier 2+ ? Position dans tab order ? | game-designer | Sprint Polish Tier 2+ | Hors scope MVP |

**Ship-blocking critique** : **O-PM-1 = OQ-MNU-1 du GDD**. Doit être tranché avant que Save/Load r2 ne soit lancé. **Pas ship-blocking Sprint 0 / Sprint 1 MVP** car Save/Load r1 ne save pas la run-in-progress.

---

## 14. References

- `design/gdd/menu-system.md` r1 § K.2 / K.3 / K.4 / K.5 / K.6 / K.7 / K.8 / K.9 (cahier des charges canonique)
- `design/gdd/menu-system.md` r1 § C.R-MNU-1..18 (rules), § F.F-MNU-1 (snap budget < 100 ms), § H AC-MNU-1..56 (acceptance criteria sources), § OQ-MNU-1 (save-on-quit handler ownership)
- `design/gdd/game-state-manager-system.md` r1 / ADR-0007 D-4 (process_mode discipline) / D-9 (pull state_changed pattern) / D-10 (5 verbes locked : `request_pause`, `request_resume`, `request_scene_transition`, `start_etage`)
- `design/gdd/input-system.md` r5 / ADR-0004 D-4 (refcount discipline `request_disable`/`release_enable_request`, action `ui_cancel`, `ui_cancel_pressed` signal toujours émis)
- `design/gdd/hud-system.md` r1 (HUD layer 50 — Pause overlay layer 80 garantit no conflict ; HUD hide owned HUD peer sur PAUSED)
- `design/gdd/audio-system.md` r2.1 (zéro SFX MVP ; ducking PAUSED owned Audio peer, pas Menu)
- `design/gdd/save-load-system.md` r1 / `docs/architecture/adr-0010-save-load-serialization-format.md` (ConfigFile MVP, pas de save mid-étage)
- `design/gdd/shop-system.md` r2 R-SHP-11 (cohérence "ESC = avancer" cross-surface)
- `design/ux/main-menu.md` r1 (cohérence cross-spec)
- `design/ux/interaction-patterns.md` P-INP-003, P-INP-004, P-TRANS-001
- `design/accessibility-requirements.md` Tier 1 obligatoire
- `docs/architecture/adr-0015-accessibility-interface-layer.md` D-1 (définition canonique Tier 1/2/3 — `AccessibilityService` autoload, `reduce_motion` / `reduce_flash` source-of-truth, tier coverage cross-system)
- `design/art/art-bible.md` § 1-4 Chrome Zen visual identity
