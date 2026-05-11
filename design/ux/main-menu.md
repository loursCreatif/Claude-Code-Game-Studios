# UX Spec — Main Menu

> **Status** : r1 (aligned with `design/gdd/menu-system.md` Designed r2 full — r2 cosmetic + r2 PRE-IMPL/POLISH session 2026-04-27 ; UX spec r1 reste aligné — §K.1-K.10 inchangés en r2 ; voir `reviews/menu-system-review-r2-fresh-2026-04-27.md` pour cross-session re-review note)
> **Owner** : ux-designer
> **Last Updated** : 2026-04-28 (r1 cosmetic — référence GDD r1 → r2 full)
> **Supersedes** : baseline draft 2026-04-21 (4-button + Press Any Key + confirm-modal version — incompatible avec GDD r1 § K.1, K.5, K.8)
> **Related** : `design/gdd/menu-system.md` § K.1 / K.3 / K.4 / K.5 / K.6 / K.7 / K.8 / K.9 / K.10 ; `design/ux/interaction-patterns.md` (P-INP-003, P-INP-004, P-TRANS-001) ; `design/accessibility-requirements.md` ; `design/art/art-bible.md` (Chrome Zen)
> **Accessibility Tier** : Standard (Tier 1 obligatoire, Tier 2 AccessKit best-effort)

---

## 1. Purpose & Player Experience

Le Main Menu est la **scène container `main_menu.tscn`** chargée par GameStateManager au boot et après chaque sortie de run (Quit-to-Menu, Game Over Tier 2+). Son rôle UX :

- Permettre de **lancer une run en 1 clic / 1 key** depuis l'état Main Menu (`StartButton` focused au boot → `ui_confirm` → `GSM.start_etage(1)`).
- **Communiquer Chrome Zen** dès la première frame : monospace, palette tokens K.4, zéro animation gratuite.
- Respecter Pillar 1 FLOW : aucun délai, aucun confirm, aucun écran intermédiaire entre boot et menu interactif (pas de "Press Any Key", pas de splash studio).
- Respecter Pillar 3 SECONDE CHANCE : `[Quitter le jeu]` est immédiat (pas de "Êtes-vous sûr ?" modal — anti-pattern K.8 explicite).

Fantasy visée : « le menu principal ressemble au jeu, sonne comme le jeu (silence), réagit comme le jeu (snap). La première frame interactive arrive avant que tu aies eu le temps de poser ta main sur la souris. »

---

## 2. Information Architecture

```
Main Menu (main_menu.tscn — scène container, CanvasLayer 0)
│
├─ [Start Run]          → GSM.start_etage(1) → request_scene_transition(level_01.tscn) → PLAYING
└─ [Quitter le jeu]     → get_tree().quit() → fermeture OS immédiate
```

**Hors scope MVP (différé Tier 2+)** :
- Continue (suspend/resume run-in-progress) — aucun save run mid-étage MVP (Save/Load r1 = upgrades persistents uniquement).
- Settings → audio / sensitivity / accessibility / remap.
- Credits.
- New Game vs Continue distinction.

Ces items ne sont **pas masqués** ni "disabled" dans le UI MVP — ils n'existent simplement pas dans l'arbre de la scène. Quand le scope élargit, ajouter les boutons en respectant le tab order K.6 (intercaler avant `[Quitter le jeu]`, qui reste en dernier).

---

## 3. Screen Flow

### 3.1 Entry — boot

1. `boot.tscn` (autoloads + GSM init) → `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")`.
2. GSM fade-out 200 ms (CanvasLayer layer 100, owned GSM) → scène déchargée.
3. `main_menu.tscn` chargée → `MainMenuRoot._ready()` → `StartButton.grab_focus()`.
4. GSM fade-in 200 ms → menu interactif. **Première frame interactive ≤ 500 ms post-boot fade complete** (cible Pillar 4).

### 3.2 Entry — depuis Pause Menu "Quitter vers Menu Principal"

1. Pause Menu : clic `[Quitter vers Menu Principal]` → `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")`.
2. GSM purge run state (Credit reset 0, Movement despawn, etc. — owned systems via `state_changed` signal).
3. GSM fade owned (layer 100) → scène déchargée → `main_menu.tscn` chargée → `_ready()` → focus reset `StartButton`.

**Aucun "Welcome back" overlay, aucun message "Run interrompue".** Cohérence Pillar 3.

### 3.3 Interaction

- **Focus initial** : `StartButton`.
- **Tab order** : `StartButton` → `QuitButton` → wrap → `StartButton` (cf. K.6).
- **Souris** : hover affiche underline cyan K.5 ; clic active. Aucun click-and-hold, aucun double-clic.
- **Clavier** : `Tab` / `Shift+Tab` cycle ; `ui_confirm` (Enter / Space) active ; `ui_cancel` (ESC) **ignoré** (anti-pattern : pas de "fermer le menu racine" — il n'y a rien derrière). Cohérence GDD K.6 ligne "Main Menu : ESC est ignoré".

### 3.4 Exit — Start Run

1. Clic / `ui_confirm` sur `StartButton` → `GSM.start_etage(1)`.
2. GSM transition (fade-out owned layer 100) → `main_menu.tscn` déchargée → `level_01.tscn` chargée.
3. Pas de feedback Menu pendant le fade. Le Menu n'a pas son propre tween d'apparition / disparition (anti-double-fade Pillar 1, K.7).

### 3.5 Exit — Quitter le jeu

1. Clic / `ui_confirm` sur `QuitButton` → `get_tree().quit()`.
2. Fermeture OS immédiate. Aucun confirm dialog (K.8 anti-pattern explicite).

---

## 4. Visual Layout

### 4.1 Wireframe (1920 × 1080 référence)

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│                                                                  │
│                                                                  │
│                       CHROME://ASCENT                            │  ← TitleLabel, JetBrains Mono Bold 28 px
│                                                                  │     letter-spacing 2 px, color #E8E8F0
│                                                                  │     ancré TOP_WIDE, padding-top 80 px
│                                                                  │
│                                                                  │
│                                                                  │
│                       ┌──────────────────┐                       │
│                       │    Start Run     │  ← StartButton, JetBrains Mono 15 px
│                       └──────────────────┘     min-width 220 px, focus = bordure cyan rect
│                                                                  │
│                       ┌──────────────────┐                       │
│                       │ Quitter le jeu   │  ← QuitButton, idem
│                       └──────────────────┘                       │
│                                                                  │
│                                                                  │
│                                                                  │
│                                                                  │
│                                                                  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
   ColorRect Background = MENU_BG_BLACK #050608 (fullscreen, alpha 1.0)
```

### 4.2 Wireframe (1280 × 720 — résolution minimale supportée)

Identique à 4.1, sauf :
- TitleLabel font-size 28 px → **22 px** si la condition `TitleLabel.size.x > viewport.size.x - 160` est vraie au `_ready()`.
- ButtonContainer width ≤ 320 px (déjà respecté à 220 px min-width, marge 480 px de chaque côté).
- TitleLabel padding-top : 60 px au lieu de 80 px (économie verticale).

Aucun scroll, aucun rétrécissement de bouton, aucune wrap de texte.

### 4.3 Layout Zones

| Zone | Type | Composants | Notes |
|---|---|---|---|
| Background | ColorRect fullscreen | `Background` | `MENU_BG_BLACK #050608`, alpha 1.0, `mouse_filter = IGNORE` |
| Title | Label ancré TOP_WIDE | `TitleLabel` "CHROME://ASCENT" | Padding-top 80 px (1080p) / 60 px (720p), centré horizontalement |
| Action area | VBoxContainer ancré centre | `ButtonContainer` → `StartButton`, `QuitButton` | Centre viewport −40 px, separation 16 px |
| Footer (optionnel) | Label ancré BOTTOM_RIGHT | `VersionLabel` (visible si `DEBUG_SHOW_VERSION = true`) | 11 px, `MENU_VERSION_TEXT #3C3C50`, padding 12 px droite / 8 px bas |

---

## 5. States & Variants

| État | Trigger | Ce qui change |
|---|---|---|
| **Default (loaded)** | `_ready()` après GSM transition | `StartButton` focused, layout K.1, fond plein |
| **Hover (mouse)** | Souris sur un bouton | Underline cyan `#3EE4FF` 1 px sous le label (K.5) |
| **Focus (clavier)** | `Tab` ou `grab_focus()` | Bordure cyan `#3EE4FF` 1 px rect entier (distinct du hover) |
| **Pressed** | `button_down` (souris ou ui_confirm tenu) | Background bouton `#111120` + bordure cyan |
| **Disabled** | _N/A MVP_ | Réservé Tier 2+ |
| **Window-resize** | `viewport.size_changed` | Re-layout instant : titre ré-évalué pour breakpoint 22/28 px, ButtonContainer recentré |
| **Focus lost** (alt-tab) | `application_focus_lost` | Aucun changement visuel (pas de gameplay à pauser). Focus du bouton préservé au retour |

**Pas d'état "Loading"**, pas d'état "Error". Si le fichier scène n'existe pas, c'est un crash editor / build — out of scope UX.

---

## 6. Interaction Map

Input methods : **Keyboard/Mouse primaire** (cohérent technical-preferences.md). Gamepad partial Tier 2+.

| Composant | Action joueur | Input | Feedback immédiat | Outcome |
|---|---|---|---|---|
| `StartButton` | Activer | Clic souris | Pressed bg #111120 1 frame → `pressed` signal | `GSM.start_etage(1)` |
| `StartButton` | Activer | Enter / Space (focused) | Idem | Idem |
| `StartButton` | Hover | Souris dans son rect | Underline cyan apparait au pixel 1 (K.7 hover_delay = 0 ms) | — |
| `StartButton` | Focus | `Tab` depuis QuitButton (wrap) ou `grab_focus()` | Bordure cyan rect | — |
| `QuitButton` | Activer | Clic souris | Pressed bg | `get_tree().quit()` (immédiat, pas de modal) |
| `QuitButton` | Activer | Enter / Space (focused) | Idem | Idem |
| `QuitButton` | Hover | Souris | Underline cyan | — |
| `QuitButton` | Focus | `Tab` depuis StartButton | Bordure cyan rect | — |
| _scène_ | `ui_cancel` (ESC) | Clavier | _aucun_ | _ignoré_ — Main Menu n'a pas de "fermer" (cf. K.6 ligne "Main Menu : ESC est ignoré") |

**Patterns référencés** :
- P-INP-003 (menu navigation — focus_mode + ui_up/ui_down/ui_confirm)
- P-TRANS-001 (scene transition Main Menu → PLAYING via GSM, owned GSM)

**Pattern à formaliser plus tard** (Open Question O-1) : `P-MENU-NO-CONFIRM-001` — politique projet "le clic EST la décision pour les actions Quit-Game et Quit-to-Menu", documentant l'absence de confirm modal comme choix design (K.8 anti-pattern).

---

## 7. Events Fired

MVP analytics scope = zéro (Tier 2+). Aucun event fire MVP. La table ci-dessous documente les hooks réservés pour Tier 2+ analytics si jamais ajoutés.

| Action joueur | Event Tier 2+ (réservé) | Payload | Persistent state ? |
|---|---|---|---|
| StartButton activé | `menu.run_started` | `{run_id, build_version, time_in_menu_ms}` | Non (run state created par GSM, pas par Menu) |
| QuitButton activé depuis Main Menu | `menu.app_quit_from_main` | `{time_in_menu_ms}` | Non (immédiat OS quit) |

**Aucune action ne modifie de save data depuis le Main Menu MVP.** Save/Load r1 ne touche que les upgrades persistents et n'a pas de trigger UI ici. OQ-MNU-1 du GDD (save-on-quit handler ownership) ne concerne PAS le Main Menu — concerne le Pause Menu `[Quitter le jeu]` quand un run est in-progress (cf. `pause-menu.md` § 7).

---

## 8. Transitions & Animations

**Règle K.7 absolue : aucune animation owned par le Menu.** Toutes les transitions visibles entre états-jeu sont owned par GSM (CanvasLayer layer 100, fade noir).

| Transition | Owned by | Durée | Behavior Menu |
|---|---|---|---|
| Boot → Main Menu visible | GSM (fade-in) | 200 ms | `MainMenuRoot.visible = true` direct, aucun tween Menu |
| Main Menu → PLAYING | GSM (fade-out + fade-in) | 200 + 200 ms | Aucun feedback Menu pendant le fade |
| Hover (Default → Hover) | _aucune_ | 0 ms | Snap underline pixel 1 |
| Focus (Default → Focus) | _aucune_ | 0 ms | Snap rect cyan |
| Pressed (Hover/Focus → Pressed) | _aucune_ | 0 ms | Snap bg sombre, 1 frame |
| Resize | _aucune_ | 0 ms | Re-layout instantané |

**Aucun spinner, aucun "Chargement…", aucun progress bar.** Si le chargement de `level_01.tscn` excède le budget GSM, le fade noir GSM masque l'attente (pas le Menu).

**Reduce-motion (Tier 2+)** : aucun changement requis Main Menu, car aucune animation Menu existante. Cohérence native.

---

## 9. Data Requirements

| Donnée | Source | Read / Write | Notes |
|---|---|---|---|
| Build version (optionnel footer) | `ProjectSettings.get_setting("application/config/version")` | Read | MVP : masqué sauf `DEBUG_SHOW_VERSION = true` |
| _aucune autre_ | — | — | Le Main Menu n'affiche AUCUNE donnée gameplay (pas de save slot list, pas de "last run", pas de stats). Tier 2+ pourra ajouter Save/Load r2+ "Continue" et "Stats" via lecture SaveLoadSystem |

**Cohérence Save/Load r1** : Main Menu ne consume aucun verbe SaveLoadSystem MVP. Pas de `load_int(&"current_run_seed")` ni autre.

---

## 10. Accessibility (Tier 1 — obligatoire MVP)

Cohérent GDD § K.9. Tier coverage défini par ADR-0015 D-1 (`AccessibilityService` single-source-of-truth) — voir `docs/architecture/adr-0015-accessibility-interface-layer.md`.

| Critère | Status | Tier (ADR-0015 D-1) | Implementation |
|---|---|---|---|
| Navigation clavier 100 % | ✅ | Tier 1 — obligatoire MVP | `Tab`/`Shift+Tab` cycle, `ui_confirm` activate, focus visible bordure cyan rect (K.5 distinct du hover underline) |
| Focus initial sur action principale | ✅ | Tier 1 — obligatoire MVP | `StartButton.grab_focus()` dans `_ready()` |
| Aucun élément mouse-only | ✅ | Tier 1 — obligatoire MVP | Tous les boutons sont aussi accessibles clavier |
| Contraste texte/fond ≥ 7:1 (WCAG AAA) | ✅ | Tier 1 — obligatoire MVP | `#E8E8F0` sur `#050608` ≈ 15.2:1 ; `#3EE4FF` sur `#050608` ≈ 8.9:1 |
| Taille texte minimale | ✅ | Tier 1 — obligatoire MVP | Boutons 15 px ; titre 22-28 px ; aucun texte fonctionnel < 12 px |
| Color-as-only-indicator | ✅ | Tier 1 — obligatoire MVP | Focus = bordure rect (forme + couleur) ; Hover = underline (forme + couleur) ; Pressed = background (forme + couleur). Le bordure cyan n'est jamais le seul indicateur |
| Aucune animation flash > 3 Hz | ✅ | Tier 1 — obligatoire MVP | Aucune animation Menu (K.7) |
| `reduce_motion` | ✅ natif | Tier 1 — obligatoire MVP | Pas d'animation à supprimer ; `AccessibilityService.is_reduce_motion_enabled()` sans effet côté Menu (natif par construction — K.7) |
| Screen reader (AccessKit best-effort) | 🟡 | Tier 2 — expanded | Tous les `Button.text` sont non-vides, `TitleLabel.text` non-vide. Si Godot 4.6 expose AccessKit fonctionnel, cela suffit. Sinon, différer Tier 3 |
| Settings Menu accessibility section | ❌ | Tier 2 — expanded | Hors scope MVP — `AccessibilityService.apply_settings()` + `save_settings()` prêts pour branchement Settings Menu Tier 2+ (ADR-0015 D-3) |
| Font scaling 75-150 % | ❌ | Tier 3 — advanced | Hors scope MVP (pas de Settings Menu) |
| Remap clavier | ❌ | Tier 3 — advanced | Hors scope MVP |

---

## 11. Localization Considerations

**Locales MVP** : FR uniquement (langue projet). EN ajouté Tier 2+ (publication Steam EN-US).

| Élément | FR | EN (provisoire Tier 2+) | Char count limit |
|---|---|---|---|
| `TitleLabel` | "CHROME://ASCENT" | "CHROME://ASCENT" | Identique (titre marque, non-traduit) |
| `StartButton.text` | "Start Run" | "Start Run" | 9 chars FR (anglicisme volontaire — gameplay loop term cohérent Pillar 1) |
| `QuitButton.text` | "Quitter le jeu" | "Quit game" | 14 chars FR — limite confort à 18 chars (min-width bouton 220 px à 15 px monospace ≈ 24 chars max) |

**Risque expansion EN→DE Tier 3** : "Quit game" → "Spiel beenden" (13 chars) safe. Aucun risque immédiat.

**Élément layout-critique** : `QuitButton.text`. Si une locale dépasse 22 chars, augmenter `custom_minimum_size.x` de 220 → 280 px et re-tester breakpoint 720p (margin libre 320 → 240 px, encore safe).

**Format numérique** : aucun (Main Menu n'affiche aucun nombre MVP).

---

## 12. Acceptance Criteria

Critères UX-tester (vérifiables sans lire GDD ni code). Reformulent en perspective tester les ACs GDD § H pertinents (AC-MNU-1, AC-MNU-3, AC-MNU-15, AC-MNU-44, AC-MNU-46).

- [ ] **AC-UX-MM-1 (perf)** : depuis cold boot exécutable, la première frame avec `StartButton` interactif et focus visible apparait ≤ 2.0 s sur target hardware (entry-level laptop, profil 1080p). Mesure : timestamp `_ready()` Main Menu - timestamp `OS.get_ticks_msec()` au lancement.
- [ ] **AC-UX-MM-2 (input clavier)** : depuis le Main Menu fraichement chargé, `Tab` cycle exactement 2 boutons dans l'ordre `Start Run` → `Quitter le jeu` → wrap → `Start Run`. `Shift+Tab` cycle inverse. Aucun élément focusable non-bouton.
- [ ] **AC-UX-MM-3 (input souris)** : hover souris sur `Start Run` affiche underline cyan dans la frame suivante (≤ 16.6 ms). Sortie souris du rect bouton retire l'underline frame suivante. Aucune persistance de hover après mouvement souris.
- [ ] **AC-UX-MM-4 (action principale)** : clic ou Enter sur `Start Run` focused initie une transition GSM vers le premier étage. Aucune confirmation, aucun modal, aucun délai > 100 ms entre input et début fade-out GSM.
- [ ] **AC-UX-MM-5 (action quit)** : clic ou Enter sur `Quitter le jeu` ferme l'application immédiatement (`get_tree().quit()`). Aucun dialog "Êtes-vous sûr ?". Vérification : aucun nœud `AcceptDialog`, `ConfirmationDialog`, `PopupPanel` dans `main_menu.tscn`.
- [ ] **AC-UX-MM-6 (ESC ignoré)** : presser ESC pendant que le Main Menu est affiché ne déclenche aucune action visible. Aucun changement de focus, aucune fermeture, aucun modal.
- [ ] **AC-UX-MM-7 (contraste)** : capture du Main Menu chargé. Outil Coblis ou WCAG checker valide : `#E8E8F0` sur `#050608` ≥ 7:1. `#3EE4FF` sur `#050608` ≥ 7:1.
- [ ] **AC-UX-MM-8 (résolutions)** : layout sans clipping ni scroll à 1280×720 (titre éventuellement réduit à 22 px), 1920×1080, 2560×1440. Boutons toujours intégralement visibles, centrés.
- [ ] **AC-UX-MM-9 (Chrome Zen)** : aucun corner_radius > 0, aucun gradient, aucun glow, aucun parallax background dans `main_menu.tscn` (vérification grep + inspecteur scène).
- [ ] **AC-UX-MM-10 (silence)** : aucun `AudioStreamPlayer` dans `main_menu.tscn`. Aucun feedback sonore de hover, focus, click, transition. Cohérent Audio r2.1 zéro SFX MVP.
- [ ] **AC-UX-MM-11 (boucle Quit-to-Main)** : depuis Pause Menu en gameplay, `[Quitter vers Menu Principal]` retourne au Main Menu avec `StartButton` focused. Aucun message "Run interrompue".

---

## 13. Open Questions

| ID | Question | Owner | Échéance | Notes |
|---|---|---|---|---|
| O-MM-1 | Faut-il formaliser un pattern `P-MENU-NO-CONFIRM-001` dans `interaction-patterns.md` documentant la politique "le clic EST la décision pour Quit" ? Ou rester comme anti-pattern GDD K.8 sans pattern positif ? | ux-designer | Avant `/create-epics menu-system` | Cohérence projet : Shop r2 confirme aussi "ESC = avancer" sans confirm. Trois surfaces (Menu, Shop, Pause) appliquent la règle — mérite formalisation |
| O-MM-2 | Logo "CHROME://ASCENT" : laisser typographique pur monospace (statut MVP), ou intégrer un signe graphique discret type "://" stylisé Tier 2+ ? | art-director | Sprint Polish Tier 2+ | Hors scope playtest 1 |
| O-MM-3 | Activer `DEBUG_SHOW_VERSION = true` en build distribuable ou réserver dev-only ? | release-manager | Avant build playtest 1 | Argument pour : crash reports utilisateur. Argument contre : Chrome Zen pureté visuelle |

**Pas d'OQ critique ship-blocking côté UX.** OQ-MNU-1 du GDD (save-on-quit handler ownership) concerne le Pause Menu, pas le Main Menu (`pause-menu.md` § 13 O-PM-1).

---

## 14. References

- `design/gdd/menu-system.md` r1 § K.1 / K.3 / K.4 / K.5 / K.6 / K.7 / K.8 / K.9 (cahier des charges canonique)
- `design/gdd/menu-system.md` r1 § C.R-MNU-1..18 (rules), § H AC-MNU-1..56 (acceptance criteria sources)
- `design/gdd/game-state-manager-system.md` r1 § verbes `start_etage`, `request_scene_transition` (ADR-0007 D-10 5 verbes locked)
- `design/gdd/input-system.md` r5 / ADR-0004 D-4 (refcount discipline, action `ui_cancel`, `ui_cancel_pressed` signal)
- `design/gdd/hud-system.md` r1 (cohérence layer 50, palette `#E8E8F0`)
- `design/gdd/shop-system.md` r2 (cohérence accent `#3EE4FF`, layer 60, anti-confirm pattern)
- `design/ux/interaction-patterns.md` P-INP-003, P-INP-004, P-TRANS-001
- `design/accessibility-requirements.md` Tier 1 obligatoire
- `design/art/art-bible.md` § 1-4 Chrome Zen visual identity
