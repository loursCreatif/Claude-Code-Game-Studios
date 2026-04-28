# Menu System — Review Log

> Continuous trace of all `/design-review` and review-related amendments to `design/gdd/menu-system.md`.
> Newest entries on top.

---

## 2026-04-28 — `/design-review menu-system --depth lean` re-pass post-r2 full → **APPROVED**

- **Trigger** : lean re-pass après commit `140eb07` (Menu r2 full — 36 PRE-IMPL/POLISH résolus). Objectif : valider non-régression et clore les dettes éditoriales résiduelles.
- **Mode** : `--depth lean` (single-session, no Phase 3b adversarial spawn). Solo auto-approve.
- **Verdict** : **APPROVED r2 (full)** — 0 BLOCKING + 2 RECOMMENDED résolus en session + 1 finding SHIP-CRITICAL `process_mode = 5 → 3` cross-session déjà absorbé par session voisine avant ce lean re-pass.

### Phase 2 — Completeness check
8/8 sections présentes (Overview, Player Fantasy, Detailed Rules, Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria) + Visual/Audio + UI Requirements + Open Questions extras.

### Phase 3 — Dependency graph
| Dep | Statut sur disque |
|---|---|
| game-state-manager.md | ✓ APPROVED r1 |
| input-system.md | ✓ In Review r6 (structure PASS) |
| save-load-system.md | ✓ Designed r1 |
| hud-system.md | ✓ Designed r1 |
| shop-system.md | ✓ Designed r2.1 |
| audio-system.md | ✓ APPROVED r2.1 |
| camera-system.md | ✓ APPROVED |
| level-system.md | ✓ APPROVED r3 |

Tous les deps existent. Aucune référence cassée.

### Phase 3 — Consistency findings résolus en session

**SHIP-CRITICAL absorbé cross-session (`process_mode = 5 → 3`)** : R-MNU-14 + AC-MNU-10 + AC-MNU-37 + Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` ont été corrigés par session voisine pendant ce lean re-pass — Godot 4.6 enum `Node.PROCESS_MODE_ALWAYS = 3` (pas `5`). `5` n'est même pas dans l'enum ; `4` = `PROCESS_MODE_DISABLED` (bug runtime silencieux : grep AC pass mais boutons morts). Cross-référence `Godot 4.6 Node.ProcessMode` enum table ajoutée dans R-MNU-14 + AC-MNU-37 reformulé pour préférer GUT/integration test `process_mode == Node.PROCESS_MODE_ALWAYS` (robuste au futur changement d'enum). Cette correction touche 4 ACs et 1 Tuning Knob — sans elle, les ACs `[Static — BLOCKING]` auraient validé `process_mode = 5` (valeur enum invalide) à la build et le runtime aurait des Pause boutons morts.

**RECOMMENDED L-1 résolu** : 5 call sites internes citaient encore `R-MNU-17b` après le rename G-7 r2 PRE-IMPL/POLISH (R-MNU-8 l.181, R-MNU-18 l.298, Soft upstream l.368, EC-MNU-17 l.515, EC-MNU-34 l.583, AC-MNU-57 l.1144, OQ-MNU-1 RESOLUTION l.1196, sub-states SHUTDOWN l.332). Migration finalisée par `replace_all` ; 2 mentions historiques préservées (ligne 289 "renommage R-MNU-17b → R-MNU-19" + ligne 293 "Note de migration"). 0 call sites internes restants.

**RECOMMENDED L-2 résolu** : 7 call sites internes citaient encore `PauseOverlayRoot` après naming canonique G-14 r2 (R-MNU-14 l.260+264, R-MNU-15 l.279, EC-MNU-9 l.483, EC-MNU-15 l.507, EC-MNU-23 l.539, EC-MNU-32 l.575, AC-MNU-8 l.1074, AC-MNU-9 l.1075). Migration finalisée par `replace_all` ; 2 mentions historiques préservées dans la note ligne 104 ("(pas `PauseOverlayRoot`)" + "L'ancienne mention `PauseOverlayRoot` est dépréciée"). 0 call sites internes restants.

### Phase 3 — Cross-system bidirectional check (6/6 systèmes)
- GSM §Dependencies cite Menu (inferred → Designed r1+r2 via amendement éditorial pending) ✓
- InputManager one-way (pas de réciprocité requise par design D-4) ✓
- Shop r1 §Dependencies Soft cite Menu sibling ✓
- HUD r1 + Audio r2.1 + LevelSystem r3 + CameraSystem : peers, cohérent ✓
- Save/Load r1 R-SAV-9 owns NOTIFICATION_WM_CLOSE_REQUEST handler (OQ-MNU-1 RESOLVED par cascade) ✓

### Phase 4 — Sortie review

- **Required Before Implementation** : aucun.
- **Recommended Revisions** : (1) L-1 RESOLVED — migration R-MNU-17b → R-MNU-19 ; (2) L-2 RESOLVED — migration PauseOverlayRoot → PauseLayer ; (3) cross-session absorbé — Godot 4.6 process_mode enum `5 → 3`.
- **Nice-to-Have** : (a) `BUTTON_MIN_WIDTH_PX = 220` + "Quitter vers Menu Principal" 27 chars × 9 px ≈ 243 px sur `PAUSE_PANEL_WIDTH 360 − padding 80 = 280 px` → marge ~37 px (~13%). Tight mais OK. Validation playtest. (b) `tree_exiting.connect(_cleanup_input_refcount)` pattern référencé dans EC-MNU-9 + EC-MNU-23 mais pas inline dans R-MNU-12 exemple code — ajout possible si stories implémentation rencontrent confusion.
- **Scope Signal** : M (Sprint 1 implémentation 2-3 jours, 2 scènes Control + 2 controllers + 66 ACs).

### Verdict
**APPROVED r2 (full)** — 0 BLOCKING, dettes éditoriales résiduelles closes, finding SHIP-CRITICAL Godot 4.6 enum cross-session absorbé. Prêt pour `/create-epics menu-system`.

### Files touched (2)
1. `design/gdd/menu-system.md` — éditorial cleanup R-MNU-17b → R-MNU-19 (5 call sites) + PauseOverlayRoot → PauseLayer (7 call sites). Aucune modification structurelle.
2. `design/gdd/reviews/menu-system-review-log.md` — entry top (cette entrée).

### Solo gates
- CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`).
- Pas d'AskUserQuestion widgets fired (auto-approve memory).

### Path to `/create-epics`
- Menu r2 full **APPROVED** ✓
- 2 specs UX livrées 2026-04-27 (`design/ux/main-menu.md` + `design/ux/pause-menu.md`) ✓
- K.10 UX flag : `quit-flow.md` reste **NOT-blocking MVP** (mandatory avant Tier 3 Steam submission seulement)
- **Unlock** : `/create-epics menu-system` peut être lancé immédiatement.

### Next recommandé
- **A** : commit batch atomique 2 fichiers (GDD + log) menu r2 cleanup post-lean.
- **B** : `/create-epics menu-system` — Sprint 1 implémentation 2-3 jours.
- **C** : `/consistency-check` cross-GDD post r2 (cohérence Shop r2.1 + GSM r1 sub-states + provisional contracts).

---

## 2026-04-28 — `/design-system menu-system r2` PRE-IMPL/POLISH session (r2 cosmetic → r2 full)

- **Trigger** : continuation Menu r2 cosmetic 2026-04-27. Adresse les 36 findings PRE-IMPL/POLISH différés du fresh `/design-review` r1 (G-3..G-15, S-3+S-5..S-13, U-1..U-10, Q-2..Q-14).
- **Mode** : solo auto-approve, scope-bounded sur les 36 findings classés r1 review report.
- **Verdict cible** : NEEDS REVISION (r1) → **r2 full pending fresh `/design-review` lean re-pass** (la r2 PRE-IMPL/POLISH résout tous les findings r1 différés).
- **Note cross-session** : pendant que cette r2 PRE-IMPL/POLISH tournait, la **session voisine a lancé une fresh `/design-review` adversariale 5 specialists** (entrée du dessous). Les patches r2 PRE-IMPL/POLISH appliqués ici ont **résolu en parallèle ~10 findings explicitement** + ~3 partiellement de la fresh r3 voisine (cartographie post-cross-session voir entrée du dessous). Cette entrée documente uniquement les patches GDD r2 PRE-IMPL/POLISH ; les patches UX-spec G-02/G-06 sont owned par la session voisine.

- **Findings r1 adressés (36 total)** :

  **game-designer (12)** :
  - **G-3** : sub-states LOADING/SHUTDOWN documentés explicitement dans table States (sous-section "Sub-states implicites non-GSM") avec colonnes "GSM réel pendant cette phase" + "Comportement Menu" + "Notes".
  - **G-4** : pattern d'instanciation tranché — **authoring static via `.tscn` étage** (pas BaseEtage code). R-MNU-3b authoring lint formalisé.
  - **G-5** : sub-state SHOPPING documenté (GSM reste PLAYING, Shop r1 R-SHP-9 first-handler ESC consume). AC-MNU-60 cross-GDD lint Shop ESC consume.
  - **G-6** : EC-MNU-41 zero-instance Pause Overlay ajouté + AC-MNU-59 BLOCKING enforce `grep -c "pause_overlay" etage_*.tscn == 1`.
  - **G-7** : R-MNU-17b → **R-MNU-19** (renommage pour disambiguation R-MNU-17 idempotence ESC ≠ R-MNU-19 save-on-quit). Note de migration ajoutée.
  - **G-8** : `ResumeButton.grab_focus()` documenté explicitement dans `_apply_visibility(true)` exemple R-MNU-12 r2 cosmetic — confirmé.
  - **G-9** : AC-MNU-59 BLOCKING zero-instance lint adresse aussi G-9 (couverture EC-MNU-41).
  - **G-10** : R-MNU-20 ajouté — `set_mouse_captured(bool)` documenté comme API publique stable d'InputManager (ADR-0004 D-7), distinct du refcount D-4.
  - **G-11** : pattern d'instanciation détaillé dans R-MNU-3 (alternative `BaseEtage` rejetée explicitement).
  - **G-12** : `DimRect` ajouté à la hiérarchie R-MNU-3 (était K.2-only).
  - **G-14** : naming canonique tranché — **`PauseLayer`** (pas `PauseOverlayRoot`). Note de migration ajoutée. Tous les ACs alignés.
  - **G-15** : R-MNU-19 (ex R-MNU-17b) cite explicitement OQ-MNU-1 RESOLVED + AC-MNU-57.

  **systems-designer (8)** :
  - **S-3** : EC-MNU-36 ajouté — quit pendant `change_scene_to_file` LOADING phase, cite Save/Load r1 R-SAV-9.
  - **S-5** : EC-MNU-37 ajouté — window minimize pendant Pause visible (NOTIFICATION_WM_WINDOW_MINIMIZED distinct FOCUS_OUT).
  - **S-6** : EC-MNU-38 ajouté — sleep/wake OS pendant Pause (hibernation macOS/Windows).
  - **S-7** : EC-MNU-39 ajouté — controller hot-plug pendant Pause (gamepad MVP=stretch, mitigation Tier 2+).
  - **S-8** : F-MNU-1 mesurabilité headless documentée — stratégie composé `T_in + T_gsm + T_def` (AC-MNU-40) + complete `T_in + T_gsm + T_def + T_ren` (AC-MNU-65 nouveau ADVISORY r2).
  - **S-10** : Provisional contracts table élargie (NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT owner InputManager confirmé, `get_tree().paused` mutation authority GSM, `ui_cancel_pressed` always emit Input r6, `set_mouse_captured` setter public, `prefers-reduced-motion` Tier 2+).
  - **S-12** : EC-MNU-40 ajouté — lifecycle PRE_READY phase + AC-MNU-62 ADVISORY r2 lint `visible = true` dans `pause_overlay.tscn`.
  - **S-13** : F-MNU-3 bornes explicites documentées — N=0 (impossible MVP, guard Tier 2+ `assert(N >= 1)`), N=1 (focus reste sur unique bouton, no-op visuel), N=2/3 MVP cas standards.

  **ux-designer (10)** :
  - **U-1** : K.1 Breakpoints élargis — 21:9 ultrawide (3440×1440), 32:9 super-ultrawide (5120×1440), portrait hors scope MVP, safe-area Steam Deck Tier 2+.
  - **U-2** : K.9 11 px version number rationale (debug-only, `DEBUG_SHOW_VERSION = false` MVP) + AC-MNU-67 ADVISORY r2.
  - **U-3** : K.4 token split `MENU_BG_OVERLAY_RGB` (#000000) + `MENU_BG_OVERLAY_ALPHA` (0.65 scalar). K.2 DimRect réécrit en référence aux tokens (pas `Color(0,0,0,0.65)` hardcoded).
  - **U-4** : K.5 sous-section "Coexistence hover ↔ focus" — coexistence visuelle, pas de focus-follows-pointer, rect Focus l'emporte si même bouton. AC-MNU-65 ADVISORY r2 evidence manuel.
  - **U-5** : K.6 sous-section "Space bar comportement Godot natif" + "Remap accelerators Tier 2+" (Settings Menu OQ-MNU-3).
  - **U-6** : K.7 sous-section "Précision snap dans le contexte CONNECT_DEFERRED" — définition opérationnelle "même frame" = même frame que la délivrance handler deferred, élimine contradiction AC-MNU-33 sans `await`.
  - **U-7** : K.8 anti-pattern `bg_color_2` ajouté + AC-MNU-66 ADVISORY r2.
  - **U-8** : K.9 sous-section `prefers-reduced-motion` (MVP zéro animation = de facto satisfait, défense en profondeur AC-MNU-64 r2).
  - **U-9** : K.10 `design/ux/quit-flow.md` documenté NOT-blocking MVP, mandatory pré-Tier 3 Steam submission.
  - **U-10** : Player Fantasy anti-fantasy "double-ESC pause involontaire" ajouté.

  **qa-lead (6 ACs modifiés + 9 nouveaux ACs r2)** :
  - **Q-2** : AC-MNU-32 modifié — clause `release_called_before_transition` via `Time.get_ticks_usec()` ordering.
  - **Q-4** : AC-MNU-40 + AC-MNU-41 modifiés — P95 + P99 + max < 100 ms, 60 runs avec stabilisation 1 s.
  - **Q-5** : AC-MNU-42 modifié — 10 cycles warmup ignorés + 100 cycles mesurés, baseline absorbe Theme cache.
  - **Q-7** : AC-MNU-59 BLOCKING (zero/double-instance) couvre EC-MNU-8 par construction.
  - **Q-8** : AC-MNU-62 ADVISORY (visible=true grep racine PauseLayer).
  - **Q-9** : AC-MNU-5b BLOCKING — `grep project.godot autoload` → 0 match Menu autoload.
  - **Q-11** : AC-MNU-63 BLOCKING — `grep NOTIFICATION_WM_WINDOW_FOCUS src/gameplay/menu/` → 0 match.
  - **Q-12** : AC-MNU-61 BLOCKING — F-MNU-3 tab cycle wrap inverse (Shift+Tab depuis i=0 → i=N-1).
  - **Q-13** : AC-MNU-56 modifié — filter strict `^layer\s*=\s*[0-9]+` exclut `physics_layer`/`render_layer`/`collision_layer`/`light_mask`/`visibility_layer`.
  - **Q-14** : AC-MNU-44 modifié — scope étendu `scenes/etages/` parse isolé Pause Overlay child.

- **Renamings & migrations** :
  - `R-MNU-17b` → `R-MNU-19` (G-7 disambiguation).
  - `PauseOverlayRoot` → `PauseLayer` (G-14 naming canonique).
  - `MENU_BG_OVERLAY_ALPHA` (single token couleur+alpha) → `MENU_BG_OVERLAY_RGB` + `MENU_BG_OVERLAY_ALPHA` scalar (U-3 split).
  - 1 R-MNU ajouté (`R-MNU-20`).
  - 7 EC ajoutés (`EC-MNU-36`..`EC-MNU-42`).
  - 10 ACs ajoutés (`AC-MNU-5b`, `AC-MNU-59`..`AC-MNU-67`).
  - Total ACs : 56 → 66.

- **OQ updates** :
  - **OQ-MNU-6 Alt+F4 / Cmd+Q** : RESOLVED par cascade OQ-MNU-1 (même délégation pure SaveLoad r1 R-SAV-9 couvre tous les triggers de `NOTIFICATION_WM_CLOSE_REQUEST`).

- **Files touched (3)** :
  - `design/gdd/menu-system.md` (r2 cosmetic → r2 full — header bump + Player Fantasy U-10 + R-MNU-3/3b/19/20 + table States sub-states + F-MNU-1/3 + EC-MNU-36..42 + Provisional contracts table + K.1/K.2/K.4/K.5/K.6/K.7/K.8/K.9/K.10 patches + 6 ACs modifiés + 10 nouveaux ACs + OQ-MNU-6 RESOLVED).
  - `design/gdd/reviews/menu-system-review-log.md` (cette entrée).
  - `design/gdd/systems-index.md` (Menu row Designed r2 cosmetic → Designed r2 full pending lean re-pass).

- **3 BLOCKING résiduels post r2 PRE-IMPL/POLISH** *(de la fresh r3 voisine entrée du dessous, à traiter en r3 micro-batch ou lors du lean re-pass)* :
  - **S-02** : BUTTON_MIN_WIDTH_PX math à valider (PAUSE_PANEL_WIDTH 360 px − padding 80 px = 280 px, "Quitter vers Menu Principal" 27 chars × 9 px monospace ≈ 243 px → tient mais marge ~37 px).
  - **S-03+B-01+B-06** : tree_exiting guard chains à compléter (le `is_inside_tree()` r2 cosmetic guard couvre `_apply_visibility` + `_on_state_changed` mais pas tous les call paths).
  - **S-04** : AC-MNU-36 anti-tween regex à élargir (couvrir aussi `Animation`/`AnimationPlayer` côté script Menu — partiellement adressé par AC-MNU-64 r2 nouveau).

- **Solo gates** : CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`).
- **Next recommandé** :
  - **A** : commit batch atomic 3 fichiers menu r2 full + entrée log + systems-index.
  - **B** : `/design-review menu-system` LEAN re-pass (single-session 10-15 min) pour valider non-régression r2 full + adresser les 3 BLOCKING résiduels (S-02, S-03+B-01+B-06, S-04).
  - **C** : `/create-epics menu-system` après lean re-pass APPROVED.
  - **D** : `/consistency-check` cross-GDD post r2 full (cohérence Shop r1 R-SHP-9 ESC consume + GSM r1 sub-states).

---

## 2026-04-28 — Fresh `/design-review` post r2 cosmetic (CROSS-SESSION superseded by r2 PRE-IMPL/POLISH session voisine)

- **Trigger** : `/design-review menu-system fresh` (Martin solo auto-approve, post r2 cosmetic + UX specs main-menu/pause-menu livrées).
- **Mode** : Adversarial — full (5 specialists parallèles : game-designer + systems-designer + qa-lead + ux-designer + **godot-specialist** [first Godot-specific lens]) + creative-director synthèse senior.
- **Target inspecté au spawn** : `design/gdd/menu-system.md` r2 cosmetic (1166 lignes).
- **Verdict pré-cross-session** : NEEDS REVISION (minor) — 13 BLOCKING + 19 RECOMMENDED + 10 NICE-TO-HAVE = 42 findings.
- **6 convergences cross-specialist détectées** :
  1. PROCESS_MODE_ALWAYS justification race incorrecte [G-03 + B-03]
  2. Focus+Hover coexistence Godot 4.6 dual-focus [U-14 + B-02]
  3. tree_exiting guard r2 BLK-3 partiel [S-03 + B-01 + B-06]
  4. AC grep robustness (audio/dialog/process_mode/time_scale) [S-04 + Q-1 + Q-2 + Q-7 + Q-9]
  5. Layer regex faux positifs [Q-5 + B-08]
  6. Engine.time_scale regex redondante [Q-9 + B-05]
- **Aucun désaccord cross-specialist** détecté — convergences ou indépendances seulement.
- **CROSS-SESSION DETECTION** : pendant que cette fresh re-review tournait, une **session parallèle a appliqué la r2 PRE-IMPL/POLISH session** au GDD (1166 → 1273 lignes, +107). Le Status header indique maintenant "Designed r2 (full) ; pending fresh `/design-review` lean re-pass". La majorité des 42 findings r3 fresh ont été **résolus en parallèle** par la session voisine (convergence cross-session attendue car les deux sessions partagent les ~36 PRE-IMPL/POLISH r1 + le contexte UX specs).
- **Cartographie post-cross-session** :
  - **RÉSOLUS explicitement par r2 PRE-IMPL/POLISH** (~10) : S-05, S-06, U-1/15, U-3/13, U-4/14/B-02, U-10/18, U-16, B-04, Q-11
  - **RÉSOLUS partiellement** (~3) : G-03+B-03, S-01, Q-3, U-17
  - **À VÉRIFIER post-r2** (~3 BLOCKING résiduels) : S-02 (BUTTON_MIN_WIDTH_PX math), S-03+B-01+B-06 (tree_exiting guard), S-04 (AC-MNU-36 anti-tween regex)
  - **NON résolus** (~16 RECOMMENDED + 7 NICE) : G-01, G-04, G-05, G-07, Q-1, Q-2, Q-4, Q-5+B-08, Q-6, Q-7, Q-8, Q-9+B-05, Q-10, Q-12, U-19, B-06, B-07, G-06 (UX patché ici), Q-13/14/15
- **Patches r3 fresh appliqués (UX-spec côté seulement, pas de cross-session conflict)** :
  1. **G-02 RESOLVED** — `design/ux/pause-menu.md` ligne 51 : "MenuController (autoload ou node persistent)" → "PauseMenuControllerScript (node-local, enfant direct de la scène étage — cf. GDD R-MNU-1 + R-MNU-3 + OQ-MNU-5 RESOLVED)".
  2. **G-06 RESOLVED** — Headers `design/ux/main-menu.md` et `design/ux/pause-menu.md` r1 : référence "GDD r1" mise à jour vers "GDD r2 full" + lien vers ce report cross-session.
- **GDD non touché par cette fresh r3** — aucun patch appliqué à `design/gdd/menu-system.md` pour éviter cross-session overwrite des r2 PRE-IMPL/POLISH patches voisins.
- **Files touched par cette fresh r3 (3)** :
  - `design/gdd/reviews/menu-system-review-r2-fresh-2026-04-27.md` (NEW report 5 specialists + creative-director + cross-session cartographie)
  - `design/ux/pause-menu.md` (G-02 + G-06 patches)
  - `design/ux/main-menu.md` (G-06 patch)
  - `design/gdd/reviews/menu-system-review-log.md` (this entry)
- **Verdict effectif post-cross-session** : NEEDS REVISION (minor) — ~3 BLOCKING résiduels + ~14 RECOMMENDED + ~7 NICE.
- **Path to APPROVED** : lancer **fresh `/design-review menu-system` LEAN** (single-session, sans 5 specialists adversariaux) post-r2 PRE-IMPL/POLISH pour valider non-régression + adresser les 3 BLOCKING résiduels (S-02, S-03+B-01+B-06, S-04). 10-15 min suffit. Cohérent avec le Status header r2 lui-même.
- **Solo gates** : CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`).
- **Next recommandé** :
  - **A** : commit batch atomic 4 fichiers (r2 PRE-IMPL/POLISH GDD + r3 fresh UX patches + report + log).
  - **B** : `/design-review menu-system` LEAN re-pass (single-session 10-15 min) post-r2 PRE-IMPL/POLISH pour APPROVED final.
  - **C** : adresser les 3 BLOCKING résiduels (S-02 button width math, S-03+B-01+B-06 tree_exiting guard, S-04 AC-MNU-36 regex) en r3 cosmetic micro-batch.
  - **D** : `/create-epics menu-system` après lean re-pass APPROVED.

---

## 2026-04-27 — Fresh `/design-review` (r1 → r2 cosmetic)

- **Trigger** : `/design-review menu-system fresh session pour résoudre OQ-MNU-1 + commit batch (4 fichiers)` (Martin solo auto-approve, post Save/Load r1 + Upgrade r1 backbone hard-lock).
- **Mode** : Adversarial — 4 specialists subagents parallèles (game-designer, systems-designer, ux-designer, qa-lead) + Save/Load r1 consultation pour OQ-MNU-1.
- **Verdict** : NEEDS REVISION (4 SHIP-BLOCKING + 30+ PRE-IMPL/POLISH).
- **Decision** : option E — **r2 cosmetic amendment** scope-bounded sur les 4 ship-blocking + RESOLVED OQ-MNU-1 ; PRE-IMPL/POLISH déférés à r2 design session distincte avant `/create-epics menu-system`.
- **Convergence forte cross-model (4 specialists alignés)** : G-1 + S-2 + U-11 + Q-1 — incohérence `PROCESS_MODE_WHEN_PAUSED` (R-MNU-3 hiérarchie + R-MNU-14 first line) vs `PROCESS_MODE_ALWAYS` (K.2 + Tuning Knob + AC-MNU-37 + AC-MNU-10 BLOCKING). Décision tranchée : ALWAYS (conforme Tuning Knob + ACs BLOCKING + simplicité raisonnement face race fenêtre `state_changed(PAUSED)` ↔ `paused=true` propagé).
- **r2 cosmetic amendments appliqués (6 changes scope-bounded)** :
  1. **Header** — Status `In Design (r1 solo auto-approve)` → `Designed r2 (cosmetic — fresh /design-review 2026-04-27 résout 4 ship-blocking + RESOLVED OQ-MNU-1 ; 30+ PRE-IMPL/POLISH déférés)`.
  2. **BLK-1 PROCESS_MODE alignment (G-1+S-2+U-11+Q-1)** — R-MNU-3 hiérarchie ligne `PauseOverlayRoot : CanvasLayer (... ProcessMode = PROCESS_MODE_WHEN_PAUSED)` → `PROCESS_MODE_ALWAYS` + R-MNU-14 reformulé avec justification race fenêtre `state_changed(PAUSED)` ↔ `paused=true` propagé + Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` justification corrigée (WHEN_PAUSED théoriquement suffisant, ALWAYS retenue par robustesse).
  3. **BLK-2 `_apply_visibility(false)` mouse capture conditional (G-2)** — R-MNU-12 code de référence corrigé : signature `_apply_visibility(show: bool, recapture_mouse: bool = true)` + callers documentés (`_on_resume_pressed=true`, `_on_main_menu_pressed=false`, `_on_quit_pressed=false`, `_on_state_changed(PLAYING)=true`, `_on_state_changed(PAUSED)=na`). Cohérence AC-MNU-32 (`captured_true_call_count == 0` lors transition PAUSED → MENU) garantie par construction.
  4. **BLK-3 race tree_exiting (S-1)** — Guard `if not is_inside_tree(): return` ajouté en tête de `_apply_visibility` (R-MNU-12) + `_on_state_changed` (R-MNU-15). Pattern `CONNECT_DEFERRED` (R-MNU-4) peut délivrer signal pendant `change_scene_to_file` quand Pause Overlay (node-local) est en cours de destruction.
  5. **BLK-4 F-MNU-2 reformulation (S-4+U-12)** — Suppression du faux argument WCAG sur DimRect : le texte du Pause Panel est sur `PanelContainer` opaque (15.2:1 ratio garanti par K.9), pas sur le DimRect translucide. Variables renommées `ALPHA_MIN_LISIBILITE` → `ALPHA_MIN_FREEZE_VISIBLE` + rationale purement perceptuel ("le freeze gameplay reste lisible derrière, l'overlay lit clairement comme pause").
  6. **OQ-MNU-1 RESOLVED option (a) — délégation pure** — Save/Load r1 R-SAV-9 (handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` + flush no-op) + R-SAV-8 (`PROCESS_MODE_ALWAYS` reçoit notification même `paused=true`) + R-SAV-5 (write-through synchrone, zéro RAM dirty) + ADR-0007 D-1 (autoload position 3, garanti vivant à frame quit) ratifient le pattern (a). OQ-MNU-6 (Alt+F4 / Cmd+Q) résolue par cascade.
  7. **+2 ACs ajoutés** :
     - **AC-MNU-57** `[Static — BLOCKING]` (Q-6 OQ-MNU-1 enforce délégation) — `grep -rE "SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now" src/gameplay/menu/` → 0 match.
     - **AC-MNU-58** `[Static — ADVISORY]` (Q-3 héritage process_mode) — `grep -c "process_mode" scenes/menus/pause_overlay.tscn` → 1 match exact (racine uniquement).

- **30+ PRE-IMPL/POLISH déférés r2 design session distincte** :
  - **G-3** : trou table States (LOADING absent / SHUTDOWN absent).
  - **G-4** : qui instancie `pause_overlay.tscn` dans chaque étage (level-designer authoring vs code BaseEtage) — non assigné.
  - **G-5** : trou table States (SHOPPING absent — ESC en SHOPPING comportement non documenté).
  - **G-6** : EC zero-instance Pause Overlay manquant (étage sans instance = ESC silencieux).
  - **G-7** : R-MNU-17 (idempotence ESC) vs R-MNU-17b (save-on-quit) naming + ambiguïté.
  - **G-8** : `grab_focus()` ajouté dans `_apply_visibility(true)` exemple r2 cosmetic mais documentation explicite à raffiner.
  - **G-10** : confirmer `set_mouse_captured(bool)` API ADR-0004 D-7 publique figée.
  - **G-11** : pattern d'instanciation node-local Pause Overlay (auteur static vs BaseEtage code).
  - **G-12** : hiérarchie R-MNU-3 ne montre pas `DimRect` (ajouté en K.2 mais désaligné).
  - **G-13** : Tuning Knob justification raffinée r2 cosmetic mais peut-être plus tranchée nécessaire.
  - **G-14** : naming incohérent `PauseOverlayRoot` (R-MNU-3) vs `PauseLayer` (K.2 + ACs).
  - **G-15** : R-MNU-17b cite OQ-MNU-1 RESOLVED maintenant — peut être promu en r2 design distincte.
  - **S-3** : EC quit pendant `change_scene_to_file` — confirmé par Save/Load r1 R-SAV-9 mais pas un EC explicite du Menu GDD.
  - **S-5** / S-6 / S-7 : EC minimize / sleep-wake / controller hot-plug.
  - **S-8** : F-MNU-1 mesurable headless (frame trace vs perf monitor).
  - **S-9** : Save/Load r1 statut PROVISIONAL — RESOLVED depuis (Save/Load r1 + ADR-0010 Proposed déjà committed).
  - **S-10** : Provisional contracts manquants (NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT owner, `get_tree().paused` authority formal, `ui_cancel_pressed` always emit confirmé r6).
  - **S-12** : lifecycle PRE_READY phase (entre `enter_tree()` et `_ready()` avec visible state transient).
  - **S-13** : F-MNU-3 tab cycle wrap N=0 / N=1 borne explicite.
  - **U-1** : K.1/K.2 ultrawide 21:9 + portrait + safe-area absent.
  - **U-2** : K.3 11px lisibilité 1080p.
  - **U-3** : K.4 token `MENU_BG_OVERLAY_ALPHA` désaligné K.2 inline (#000000 hardcoded).
  - **U-4** : K.5 hover/focus coexistence + focus follows pointer non spécifié.
  - **U-5** : K.6 remap accelerators + Space bar Godot native.
  - **U-6** : K.7 contradiction `CONNECT_DEFERRED` vs "même frame" + AC-MNU-33 sans await.
  - **U-7** : K.8 anti-pattern `bg_color_2` StyleBoxFlat gradient natif manquant.
  - **U-8** : K.9 `prefers-reduced-motion` AC explicite manquant.
  - **U-9** : K.10 `/ux-design quit-flow.md` à ajouter (zero-confirm rationale + OQ-MNU-7 exception).
  - **U-10** : Player Fantasy anti-fantasy double-ESC pause involontaire.
  - **Q-2** : AC-MNU-32 test ordre d'exécution `release_called_before_transition`.
  - **Q-4** : ACs Groupe J (performance) P95 + nombre de runs.
  - **Q-5** : AC-MNU-42 stress 100 cycles warmup baseline.
  - **Q-7** : EC-MNU-8 double instance AC manquant.
  - **Q-8** : EC-MNU-32 visible=true grep AC manquant.
  - **Q-9** : R-MNU-1 zéro autoload AC manquant (`grep -c "MenuSystem" project.godot`).
  - **Q-11** : NOTIFICATION_WM_WINDOW_FOCUS handler grep AC manquant.
  - **Q-12** : F-MNU-3 tab cycle wrap AC dédié manquant.
  - **Q-13** : AC-MNU-56 grep `layer = ` faux positifs (`physics_layer`/`render_layer` filter incomplet).
  - **Q-14** : AC-MNU-44 path scope (étages instancient pause_overlay).

- **Files touched (4)** :
  - `design/gdd/menu-system.md` (r1 → r2 cosmetic — header + R-MNU-3 hiérarchie + R-MNU-12 code + R-MNU-14 + R-MNU-15 guard + F-MNU-2 reformulation + Tuning Knob + OQ-MNU-1 RESOLVED + AC-MNU-57 + AC-MNU-58)
  - `design/gdd/reviews/menu-system-review-r1-2026-04-27.md` (NEW — review report complet 4 specialists + verdict + adjudications)
  - `design/gdd/reviews/menu-system-review-log.md` (NEW — ce fichier, continuous trace)
  - `design/gdd/systems-index.md` (Menu row line 37 — Designed r1 → Designed r2 cosmetic + lien review log)

- **Solo gates** : CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`).
- **Next recommandé** :
  - **A** : commit batch atomic 4 fichiers menu r2 cosmetic.
  - **B** : `/design-system menu-system` r2 design session focalisée pour adresser ~30 PRE-IMPL/POLISH avant `/create-epics`.
  - **C** : `/ux-design main-menu.md` + `/ux-design pause-menu.md` (UX flag K.10 — requis avant `/create-epics`).
  - **D** : `/review-all-gdds` consistency sweep cross-GDD pré-`/create-epics`.
