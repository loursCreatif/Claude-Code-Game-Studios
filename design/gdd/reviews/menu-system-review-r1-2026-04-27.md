# Menu System — Fresh `/design-review` r1 — 2026-04-27

> **Source GDD** : `design/gdd/menu-system.md` r1 (1133 lignes, Designed r1 2026-04-27 solo auto-approve, post Save/Load r1 + Upgrade r1).
> **Trigger** : `/design-review menu-system fresh session pour résoudre OQ-MNU-1 + commit batch (4 fichiers)`.
> **Mode** : Adversarial — 4 specialists subagents parallèles (game-designer + systems-designer + ux-designer + qa-lead) + Save/Load r1 consultation pour OQ-MNU-1 résolution.
> **Verdict global** : **NEEDS REVISION** (4 SHIP-BLOCKING + ~30 PRE-IMPL/POLISH déférés).
> **Decision** : option E — **r2 cosmetic amendment** scope-bounded sur les 4 ship-blocking + RESOLVED OQ-MNU-1 ; PRE-IMPL/POLISH déférés à r2 design session distincte avant `/create-epics menu-system`.

---

## 1. Synthèse executive

### Compte par specialist

| Specialist | SHIP-BLOCKING | PRE-IMPL | POLISH | Verdict | Total |
|---|---|---|---|---|---|
| game-designer (rules + interactions) | 2 (G-1, G-2) | 9 (G-3..G-11) | 4 (G-12..G-15) | NEEDS REVISION | 15 |
| systems-designer (EC + formulas + lifecycle) | 4 (S-1..S-4) | 7 (S-5..S-11) | 2 (S-12, S-13) | NEEDS REVISION | 13 |
| ux-designer (UI K.1-K.10 + Player Fantasy) | 0 | 11 (U-1..U-11) | 1 (U-12) | NEEDS REVISION | 12 |
| qa-lead (56 ACs + couverture R/EC) | 3 (Q-1, Q-2, Q-6) | 9 (Q-3..Q-12) | 2 (Q-13, Q-14) | NEEDS REVISION | 14 |
| **Total brut (avant déduplication)** | **9** | **36** | **9** | **NEEDS REVISION** | **54** |

### Convergence cross-model (findings convergents)

| Finding convergent | IDs alignés | # Specialists | Sévérité agrégée |
|---|---|---|---|
| **PROCESS_MODE_WHEN_PAUSED vs ALWAYS incohérence** (R-MNU-3 hiérarchie + R-MNU-14 first line vs K.2 + Tuning Knob + AC-MNU-37 + AC-MNU-10) | G-1 + S-2 + U-11 + Q-1 | **4** | SHIP-BLOCKING |
| **F-MNU-2 alpha 0.65 justification WCAG fausse** (DimRect translucide ≠ texte sur PanelContainer opaque) | S-4 + U-12 | **2** | SHIP-BLOCKING |
| **`_apply_visibility(false)` mouse capture inconditionnel buggy** (R-MNU-12 vs EC-MNU-10 vs AC-MNU-32) | G-2 (+ U-4 partiel) | **1+1** | SHIP-BLOCKING |
| **Race tree_exiting `is_inside_tree()` guard manquant** (CONNECT_DEFERRED + change_scene_to_file) | S-1 | 1 | SHIP-BLOCKING |
| **OQ-MNU-1 sans AC test délégation save-on-quit** | Q-6 | 1 | SHIP-BLOCKING (résolvable) |

### Adjudications appliquées r2 cosmetic (6 changes scope-bounded)

1. **Header** Status `In Design (r1)` → `Designed r2 (cosmetic)`.
2. **BLK-1** : R-MNU-3 hiérarchie + R-MNU-14 + Tuning Knob alignés sur `PROCESS_MODE_ALWAYS` avec justification race fenêtre `state_changed(PAUSED)` ↔ `paused=true`.
3. **BLK-2** : R-MNU-12 `_apply_visibility(show, recapture_mouse=true)` — caller décide selon contexte (resume=true, quit_to_menu=false, quit_app=false). Cohérence AC-MNU-32 par construction.
4. **BLK-3** : guard `is_inside_tree()` ajouté `_apply_visibility` + `_on_state_changed` (CONNECT_DEFERRED race during change_scene_to_file).
5. **BLK-4** : F-MNU-2 reformulation perceptuelle (suppression faux argument WCAG sur DimRect — texte sur PanelContainer opaque garde 15.2:1 indépendamment de l'alpha).
6. **OQ-MNU-1 RESOLVED option (a)** : Save/Load r1 R-SAV-9 + R-SAV-8 + R-SAV-5 + ADR-0007 D-1 ratifient délégation pure ; OQ-MNU-6 (Alt+F4 / Cmd+Q) résolue par cascade ; AC-MNU-57 grep enforce délégation ajouté.

### ~30 findings PRE-IMPL/POLISH déférés r2 design session distincte

Voir §4 ci-dessous + le review log `menu-system-review-log.md`.

---

## 2. Findings détaillés par specialist

### 2.1 game-designer — règles + interactions + cohérence cross-GDD

#### SHIP-BLOCKING

**G-1 — Contradiction PROCESS_MODE : R-MNU-14 vs K.2 vs AC-MNU-37 (4 specialists convergent)**
*Severity* : SHIP-BLOCKING. *Lignes* : 92 (R-MNU-3 hiérarchie), 235 (R-MNU-14 first bullet), 725 (K.2 hiérarchie), 982 (AC-MNU-37).
*Problème* : R-MNU-3 hiérarchie ligne 92 et R-MNU-14 first bullet (ligne 235) déclarent `PROCESS_MODE_WHEN_PAUSED`. K.2 ligne 725 + Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` ligne 601 + AC-MNU-37 BLOCKING ligne 982 + AC-MNU-10 ADVISORY ligne 934 testent `PROCESS_MODE_ALWAYS`. Un programmeur lit R-MNU-3 en premier → implémente WHEN_PAUSED → AC-MNU-37 fail à la première CI run.
*Fix r2* : aligner R-MNU-3 + R-MNU-14 + Tuning Knob sur ALWAYS avec justification race fenêtre. **Appliqué r2 cosmetic.**

**G-2 — `_apply_visibility(false)` capture mouse inconditionnel — viole AC-MNU-32**
*Severity* : SHIP-BLOCKING. *Lignes* : 214-223 (R-MNU-12), 432 (EC-MNU-10), 971 (AC-MNU-32).
*Problème* : Code R-MNU-12 ligne 222 appelle `InputManager.set_mouse_captured(true)` inconditionnel quand `show=false`. Mais EC-MNU-10 (transition PAUSED → MainMenu) précise qu'il NE faut PAS recapturer (`main_menu._ready()` fera son propre `set_mouse_captured(false)`). AC-MNU-32 BLOCKING gate `captured_true_call_count == 0` sur ce path → fail garanti.
*Fix r2* : signature `_apply_visibility(show, recapture_mouse=true)` — caller décide. **Appliqué r2 cosmetic.**

#### PRE-IMPL (déférés r2 design session distincte)

**G-3** Trou table States : LOADING absent (Pause overlay reçoit-il state_changed(LOADING) ? `_:` pass mais comportement non documenté explicitement).
**G-4** Qui instancie `pause_overlay.tscn` dans chaque scène étage ? (level-designer authoring static vs BaseEtage code) — non assigné R-MNU-3.
**G-5** Trou table States : SHOPPING + SHUTDOWN absents (ESC en SHOPPING comportement non documenté — Shop r1 a son propre handler ESC, conflit potentiel).
**G-6** EC zero-instance Pause Overlay manquant (étage sans instance = ESC silencieux, jamais détecté en CI).
**G-7** R-MNU-17 (idempotence ESC) vs R-MNU-17b (save-on-quit) naming proche + ambiguïté quit/save.
**G-8** R-MNU-12 `_apply_visibility` ne montre pas `ResumeButton.grab_focus()` après `visible=true` (Godot ignore grab sur invisible). EC-MNU-30 + K.6 le mentionnent, R-MNU-12 doit l'inclure dans le code de référence. **Adressé partiellement r2 cosmetic** (commentaire ajouté dans le code patché).
**G-9** Pas d'AC pour zero-instance Pause Overlay (lié G-6).
**G-10** `set_mouse_captured(bool)` API ADR-0004 D-7 non confirmée publique figée (table Interactions cite ADR-0004 D-4 refcount, pas D-7 set_mouse_captured).
**G-11** R-MNU-3 node-local impose N instances identiques par étage — pattern d'instanciation pratique (authoring static vs `BaseEtage` parent class) non documenté.

#### POLISH

**G-12** Hiérarchie R-MNU-3 ne montre pas `DimRect` (ajouté en K.2 ligne 726 mais désaligné).
**G-13** Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` justification "WHEN_PAUSED marche aussi en théorie" reformulée r2 cosmetic. **Appliqué.**
**G-14** Naming incohérent `PauseOverlayRoot` (R-MNU-3) vs `PauseLayer` (K.2 + ACs `pause_layer`). Choisir un.
**G-15** R-MNU-17b ne renvoie pas explicitement à OQ-MNU-1. **Adressé r2 cosmetic** via OQ-MNU-1 RESOLVED block qui pointe R-MNU-17b.

---

### 2.2 systems-designer — EC + formulas + dependencies + lifecycle

#### SHIP-BLOCKING

**S-1 — Race tree_exiting `is_inside_tree()` guard manquant**
*Severity* : SHIP-BLOCKING. *Lignes* : 215, 246, EC-MNU-9.
*Problème* : Pause Overlay node-local de la scène étage en cours de destruction. `state_changed(PLAYING)` arrive depuis GSM *après* `change_scene_to_file` démarré mais *avant* `_exit_tree()` exécuté. Pattern pull CONNECT_DEFERRED aggrave : handler peut être délivré pendant la fenêtre de destruction → `_apply_visibility(false)` appelle `release_enable_request` + `set_mouse_captured(true)` sur scène en déchargement. Risque non-déterministe.
*Fix r2* : `if not is_inside_tree(): return` en tête de `_on_state_changed` et `_apply_visibility`. **Appliqué r2 cosmetic.**

**S-2 — Incohérence PROCESS_MODE WHEN_PAUSED vs ALWAYS dans le même GDD** (cf. G-1)
*Severity* : SHIP-BLOCKING (convergent G-1 + U-11 + Q-1). **Appliqué r2 cosmetic.**

**S-3 — Quit pendant `change_scene_to_file` (LOADING) — EC manquant**
*Severity* : SHIP-BLOCKING (résolu par cascade Save/Load r1).
*Problème* : Joueur clique "Quitter le jeu" depuis Main Menu pendant qu'une transition vers étage est déjà engagée → `NOTIFICATION_WM_CLOSE_REQUEST` émis pendant LOADING. Save/Load r1 R-SAV-9 + R-SAV-8 + ADR-0007 D-1 confirme que SaveLoadSystem (autoload pos-3 PROCESS_MODE_ALWAYS) reçoit le notification avant destruction de l'arbre.
*Fix* : EC-MNU-X "Quit pendant change_scene_to_file en cours" déféré r2 design session distincte (référencer Save/Load r1 R-SAV-9). **Adjudication r2 cosmetic** : OQ-MNU-1 RESOLVED résout le pattern, EC explicite déféré.

**S-4 — F-MNU-2 alpha 0.65 justification WCAG fausse sur fond gameplay variable**
*Severity* : SHIP-BLOCKING (convergent U-12).
*Problème* : F-MNU-2 utilise variables `ALPHA_MIN_LISIBILITE` ("texte blanc se confond"). Mais le texte du Pause Panel est sur `PanelContainer` opaque (`MENU_PANEL_BG #0A0A12` ratio 15.2:1 K.9), pas sur le DimRect translucide. La formule confond perception du freeze (vrai sujet) avec lisibilité texte (gouvernée par K.9, indépendante de l'alpha).
*Fix r2* : reformulation purement perceptuelle, variables renommées `ALPHA_MIN_FREEZE_VISIBLE`. **Appliqué r2 cosmetic.**

#### PRE-IMPL (déférés)

**S-5** EC minimize fenêtre pendant Pause visible (NOTIFICATION_WM_WINDOW_MINIMIZED distinct de FOCUS_OUT).
**S-6** EC sleep/wake OS pendant Pause visible (hibernation macOS/Windows).
**S-7** EC controller hot-plug pendant Pause visible (gamepad MVP=stretch — bouton parasite à connexion).
**S-8** F-MNU-1 mesurable headless (frame trace vs perf monitor — `Time.get_ticks_msec()` non équivalent au timing rendu).
**S-9** Save/Load r1 statut RESOLVED depuis (Save/Load r1 + ADR-0010 Proposed déjà committed) → OQ-MNU-1 RESOLVED valide. **Adressé r2 cosmetic.**
**S-10** Provisional contracts manquants : `NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT` owner, `get_tree().paused` authority formal, `ui_cancel_pressed` always emit confirmé r6.
**S-11** Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` justification raffinée r2 cosmetic. **Appliqué partiellement.**

#### POLISH

**S-12** Lifecycle PRE_READY phase (entre `enter_tree()` et `_ready()` avec visible state transient — flash 1 frame possible si `.tscn` mal sauvegardé).
**S-13** F-MNU-3 tab cycle wrap N=0 / N=1 borne explicite manquante.

---

### 2.3 ux-designer — UI K.1-K.10 + Player Fantasy

#### PRE-IMPL (12 findings, déférés r2 design session distincte)

**U-1** K.1 / K.2 ultrawide (21:9) + portrait + safe-area absents (breakpoints 720p/1080p/1440p uniquement).
**U-2** K.3 11px lisibilité 1080p (~2.9mm en deçà du seuil WCAG 1.4.4 confort 12px).
**U-3** K.4 token `MENU_BG_OVERLAY_ALPHA` désaligné K.2 inline (#000000 hardcoded vs token K.4).
**U-4** K.5 hover/focus coexistence (souris survole un bouton, focus clavier sur autre — lequel "gagne" visuellement ?) + focus follows pointer non spécifié.
**U-5** K.6 remap accelerators Tier 2+ + Space bar Godot Button native non documenté.
**U-6** K.7 contradiction `CONNECT_DEFERRED` vs "même frame" (AC-MNU-33 sans await passera uniquement avec connexion directe non-deferred).
**U-7** K.8 anti-pattern `bg_color_2` StyleBoxFlat gradient natif manquant (AC-MNU-48 couvre `GradientTexture`/`ShaderMaterial` mais pas `bg_color_2`).
**U-8** K.9 `prefers-reduced-motion` AC explicite manquant (zero animation MVP de facto satisfait, mais pas testé).
**U-9** K.10 `/ux-design quit-flow.md` à ajouter (zero-confirm rationale + OQ-MNU-7 exception épilepsie/parental).
**U-10** Player Fantasy anti-fantasy "double-ESC pause involontaire" manquante (flash overlay non désiré).
**U-11** K.2 process_mode incohérence (cf. G-1 / S-2 — convergent). **Appliqué r2 cosmetic.**

#### POLISH

**U-12** F-MNU-2 alpha plancher non justifié objectivement (cf. S-4). **Appliqué r2 cosmetic.**

---

### 2.4 qa-lead — 56 ACs + couverture R/EC + classifications

**Compte précis** : 56 ACs déclarés. Vérification par groupe : A=5, B=5, C=6, D=4, E=5, F=4, G=3, H=4, I=3, J=4, K=7, L=4, M=2 = **56 ✓**.
**Décompte par gate** : 36 BLOCKING + 20 ADVISORY ✓.
**Décompte par mécanisme** : ~38 AUTO + 11 STATIC + 2 MANUAL = ~68% AUTO + ~29% STATIC + ~4% MANUAL. Le ~70% AUTO + 30% MANUAL/STATIC annoncé tient.

#### SHIP-BLOCKING

**Q-1** AC-MNU-10 + AC-MNU-37 + AC-MNU-38 testent `process_mode = 5` (ALWAYS) mais R-MNU-3 hiérarchie + R-MNU-14 first bullet déclarent WHEN_PAUSED (4) → décision à trancher (cf. G-1). **Appliqué r2 cosmetic.**
**Q-2** AC-MNU-32 ne teste pas l'ordre d'exécution (`release_called_before_transition`) — seulement le side-effect (pas de `set_captured(true)`).
**Q-6** OQ-MNU-1 RESOLVED côté design mais aucun AC ne valide la délégation `grep -r "save\|SaveLoad" src/gameplay/menu/` → 0 match. **Appliqué r2 cosmetic via AC-MNU-57.**

#### PRE-IMPL

**Q-3** R-MNU-14 héritage `process_mode` (corollaire) AC manquant. **Appliqué r2 cosmetic via AC-MNU-58.**
**Q-4** AC-MNU-40 + AC-MNU-41 (perf snap < 100ms) sans P95 ni nombre de runs.
**Q-5** AC-MNU-42 stress 100 cycles sans warmup baseline (faux positifs alloc GUT).
**Q-7** EC-MNU-8 (double instance pause overlay) sans AC formalisé.
**Q-8** EC-MNU-32 (visible=true par erreur dans .tscn) sans AC formalisé.
**Q-9** R-MNU-1 (zéro autoload Menu) sans AC `grep -c "MenuSystem\|MainMenuController\|PauseMenuController" project.godot` → 0 match section autoload.
**Q-11** Dual-monitor focus loss : aucun AC vérifie que Menu ne pose pas son propre `_notification(NOTIFICATION_WM_WINDOW_FOCUS)` qui doublerait InputManager.
**Q-12** F-MNU-3 (tab cycle wrap) sans AC dédié (Tab depuis dernier wrap vers premier, Shift+Tab depuis premier wrap vers dernier).

#### POLISH

**Q-13** AC-MNU-56 grep `layer = ` faux positifs (filter `physics_layer\|render_layer` incomplet — peut matcher d'autres propriétés).
**Q-14** AC-MNU-44 path scope `scenes/menus/` exclut étages instancient pause_overlay (audio dans `etage_*.tscn` non détecté).

---

## 3. Adjudications & justifications r2 cosmetic

### 3.1 PROCESS_MODE_ALWAYS retenue (BLK-1 cross-model 4/4)

**Question** : `PROCESS_MODE_WHEN_PAUSED` (4 — exécute QUE si `paused=true`) ou `PROCESS_MODE_ALWAYS` (5 — toujours actif) sur Pause Overlay ?

**Décision r2** : **ALWAYS**. Raisons :
1. Tuning Knob structurel + AC-MNU-37 + AC-MNU-10 + K.2 testent ALWAYS — alignement par majorité (4 sources vs 2 R-MNU-3 + R-MNU-14 first bullet).
2. ALWAYS robuste face race fenêtre `state_changed(PAUSED)` reçu vs `paused=true` propagé par GSM (asynchrone). Si `paused=true` n'est pas encore positionné quand le handler `_on_state_changed(PAUSED)` est appelé, WHEN_PAUSED ne s'exécute pas → boutons morts. ALWAYS exécute toujours, jamais de race.
3. Simplicité de raisonnement : "le Pause Overlay tourne toujours" est un invariant plus simple que "le Pause Overlay tourne uniquement si paused=true qui doit avoir été propagé".
4. Coût négligeable : Pause Overlay invisible la plupart du temps (visibility=false) → `_process` no-op, `_input` ignoré (no input bindings). Aucun overhead measurable.

### 3.2 OQ-MNU-1 RESOLVED option (a) délégation pure (Save/Load r1 ratifie)

**Pattern figé** : Menu appelle `get_tree().quit()` direct, SaveLoadSystem intercepte via `NOTIFICATION_WM_CLOSE_REQUEST`. Aucun appel `SaveLoad.*` côté Menu.

**Garanties Save/Load r1** :
1. **R-SAV-9** — SaveLoadSystem possède son propre handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` qui flush l'état (no-op MVP grâce au write-through).
2. **R-SAV-8** — SaveLoadSystem `PROCESS_MODE_ALWAYS` : reçoit le notification même si quit déclenché depuis Pause Menu (`get_tree().paused == true`).
3. **R-SAV-5** — write-through synchrone : zéro état RAM dirty au moment du quit. Flush no-op = filet de sécurité Tier 2+.
4. **ADR-0007 D-1** — autoload pos-3 (`InputManager → GameStateManager → SaveLoadSystem → AudioSystem`) garanti vivant à frame quit (Godot délivre `NOTIFICATION_WM_CLOSE_REQUEST` avant destruction de l'arbre, autoloads détruits **après** scene root).

**OQ-MNU-6 (Alt+F4 / Cmd+Q) résolue par cascade** : même pattern (a) couvre toutes les sources de `NOTIFICATION_WM_CLOSE_REQUEST`.

**Lint enforce** : AC-MNU-57 BLOCKING ajouté (Q-6) — `grep -rE "SaveLoad|save_int|save_string_array|save_now" src/gameplay/menu/` → 0 match.

### 3.3 Pourquoi r2 cosmetic et pas r2 full design session ?

Les 4 SHIP-BLOCKING sont **éditoriaux** (corrections ciblées de spec interne sans changer le design intent) :
- BLK-1 : valeur enum à aligner — pas de changement architectural.
- BLK-2 : signature de fonction interne `_apply_visibility` à élargir — pas de changement contract public.
- BLK-3 : guard défensif à ajouter — pattern standard Godot.
- BLK-4 : reformulation rationale F-MNU-2 — la valeur 0.65 reste, justification corrigée.
- OQ-MNU-1 : confirmé par downstream Save/Load r1, pas une nouvelle décision design.

Les ~30 PRE-IMPL/POLISH méritent une r2 design session distincte (couverture EC manquants, ACs additionnels, raffinements UX K.1-K.10) avant `/create-epics menu-system`. Pattern cohérent avec credit-economy r2 cosmetic + 7 ship-blocking déférés r2 design distincte.

---

## 4. PRE-IMPL/POLISH déférés r2 design session distincte

Liste exhaustive (pour traçabilité dans la prochaine session `/design-system menu-system r2`) :

**game-designer (9)** : G-3, G-4, G-5, G-6, G-7, G-9, G-10, G-11, G-14.
**systems-designer (9)** : S-3 (EC explicite à ajouter), S-5, S-6, S-7, S-8, S-10, S-12, S-13.
**ux-designer (10)** : U-1, U-2, U-3, U-4, U-5, U-6, U-7, U-8, U-9, U-10.
**qa-lead (8)** : Q-2, Q-4, Q-5, Q-7, Q-8, Q-9, Q-11, Q-12, Q-13, Q-14.

**Total** : ~36 findings (avec quelques recouvrements G-12/G-13 partiellement adressés r2 cosmetic).

---

## 5. Files touched (4)

1. `design/gdd/menu-system.md` (r1 → r2 cosmetic)
   - Header status r1 → r2.
   - R-MNU-3 hiérarchie : `WHEN_PAUSED` → `ALWAYS`.
   - R-MNU-12 code : signature `_apply_visibility(show, recapture_mouse=true)` + guard `is_inside_tree()` + `grab_focus()` + callers documentés.
   - R-MNU-14 reformulé avec justification race fenêtre.
   - R-MNU-15 (`_on_state_changed`) ajouté guard `is_inside_tree()`.
   - F-MNU-2 reformulation perceptuelle (variables renommées + rationale corrigé).
   - Tuning Knob `PAUSE_OVERLAY_PROCESS_MODE` justification corrigée.
   - OQ-MNU-1 RESOLVED block complet ajouté.
   - +AC-MNU-57 (save-on-quit délégation grep) BLOCKING.
   - +AC-MNU-58 (process_mode héritage grep) ADVISORY.

2. `design/gdd/reviews/menu-system-review-r1-2026-04-27.md` (NEW — ce fichier).

3. `design/gdd/reviews/menu-system-review-log.md` (NEW — continuous trace).

4. `design/gdd/systems-index.md` (Menu row line 37 — Designed r1 → Designed r2 cosmetic + lien review log).

---

## 6. Solo gates

CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`). Specialists subagents adversariaux exécutés en parallèle sans round de consensus humain.

---

## 7. Next recommandé

- **A** : commit batch atomic 4 fichiers menu r2 cosmetic.
- **B** : `/design-system menu-system` r2 design session focalisée pour adresser ~36 PRE-IMPL/POLISH avant `/create-epics`.
- **C** : `/ux-design main-menu.md` + `/ux-design pause-menu.md` (UX flag K.10 — requis avant `/create-epics`).
- **D** : `/review-all-gdds` consistency sweep cross-GDD (14 GDDs Designed) pré-`/create-epics`.
- **E** : `/design-system checkpoint-respawn-system` continuation backbone (débloque Tier 2+ Secret/Combat snapshot/restore).
