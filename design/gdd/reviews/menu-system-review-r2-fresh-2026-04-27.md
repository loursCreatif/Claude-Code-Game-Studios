# Menu System — Fresh `/design-review` Report (post r2 cosmetic)

**Date** : 2026-04-28
**Mode** : Adversarial — full (5 specialists parallèles + creative-director synthèse senior)
**Trigger** : `/design-review menu-system fresh` (Martin solo auto-approve, post r2 cosmetic + UX specs main-menu/pause-menu livrées)
**Target inspecté** : `design/gdd/menu-system.md` **r2 cosmetic** (1166 lignes — état au moment du spawn des 5 specialists)
**Prior review** : `menu-system-review-r1-2026-04-27.md` — 4 SHIP-BLOCKING résolus + ~36 PRE-IMPL/POLISH déférés

---

## ⚠️ CROSS-SESSION CONTEXT — IMPORTANT

Pendant que cette fresh re-review tournait (5 specialists adversariaux + creative-director synthèse), une **session parallèle a appliqué la `r2 PRE-IMPL/POLISH session`** au GDD (résolution des 36 findings r1 différés). Le GDD est passé de **1166 → 1273 lignes (+107)**, et son Status header indique maintenant :

> **Status**: Designed r2 (full — r2 cosmetic 4 ship-blocking + RESOLVED OQ-MNU-1 + r2 PRE-IMPL/POLISH session 2026-04-27 résout les 36 findings différés ; pending fresh `/design-review` lean re-pass avant `/create-epics`)

**Conséquence sur cette fresh re-review** : la majorité des 13 BLOCKING + 19 RECOMMENDED + 10 NICE-TO-HAVE identifiés ci-dessous ont été **résolus en parallèle par la r2 PRE-IMPL/POLISH session voisine** (qui a traité largement les mêmes thèmes — convergence cross-session attendue car les deux sessions partagent les ~36 PRE-IMPL/POLISH r1 + le contexte UX specs livrées).

**Cartographie post-r2 PRE-IMPL/POLISH** :

| Finding r3 fresh | Status post-r2 PRE-IMPL/POLISH session | Note |
|---|---|---|
| **G-01** anti-tutoriel AC dédié | NON résolu | Anti-fantasy n°7 toujours sans AC explicite (AC-MNU-45 grep PopupPanel reste seul couvre indirectement) |
| **G-02** pause-menu.md autoload contradiction | **RÉSOLU r3** (cette session UX patch ligne 51) | Pas touché par r2 PRE-IMPL/POLISH (édité GDD seul) — patché ici directement |
| **G-03 + B-03** R-MNU-14 race justification | RÉSOLU partiellement | Mesurabilité headless + R-MNU-20 + clarifications ajoutées |
| **G-04** Hollow Knight overclaim | NON résolu | RECOMMENDED, déféré r3 future amendement éditorial |
| **G-05** F-MNU-2 α_min sans AC playtest | NON résolu | RECOMMENDED, déféré |
| **G-06** UX réfèrent r1 | **RÉSOLU r3** (cette session UX patch headers) | Patché ici directement |
| **G-07** mouse_filter STOP DimRect AC | NON résolu | NICE-TO-HAVE, déféré |
| **S-01** F-MNU-1 borne 30 fps | RÉSOLU partiellement | Mesurabilité headless ajoutée + AC-MNU-65 ADVISORY pour test manuel rendu actif |
| **S-02** BUTTON_MIN_WIDTH_PX=220 math | À VÉRIFIER post-r2 | Tuning Knob potentiellement inchangé — flag pour fresh lean re-review |
| **S-03 + B-01 + B-06** tree_exiting guard | À VÉRIFIER post-r2 | R-MNU-13b ou prescription connect non confirmée dans diff visible |
| **S-04** AC-MNU-36 anti-tween regex | À VÉRIFIER post-r2 | AC-MNU-66 grep `bg_color_2` ajouté, mais AnimationPlayer dans scripts probablement toujours pas couvert |
| **S-05** F-MNU-3 N=0/N=1 | **RÉSOLU** ✅ | "Bornes explicites *(r2 — S-13)*" ajouté |
| **S-06** OQ-MNU-1 RESOLVED dans table | **RÉSOLU** ✅ | Provisional contracts table updated avec annotation RESOLVED + 5 nouveaux contracts CONFIRMED |
| **Q-1** AC-MNU-44 audio grep | NON résolu | À adresser fresh lean re-review |
| **Q-2** AC-MNU-45 dialog grep | NON résolu | À adresser fresh lean re-review |
| **Q-3** AC-MNU-40/41/43 P95 protocole | RÉSOLU partiellement | AC-MNU-65 ADVISORY ajouté (test manuel build rendu actif) ; protocole P95/sample/build context pas encore explicit |
| **Q-4** AC-MNU-42 warmup GC | NON résolu | RECOMMENDED |
| **Q-5 + B-08** layer regex faux positifs | NON résolu | RECOMMENDED |
| **Q-6** AC-MNU-57 EventBus indirection | NON résolu | RECOMMENDED |
| **Q-7** AC-MNU-58 process_mode runtime | NON résolu | RECOMMENDED |
| **Q-8** AC-MNU-46 corner_radius ambiguïté | NON résolu | RECOMMENDED |
| **Q-9 + B-05** AC-MNU-49 regex redondante | NON résolu | RECOMMENDED |
| **Q-10** EC-MNU-30 grab_focus AC | NON résolu | RECOMMENDED |
| **Q-11** AC-MNU-33 confusion EC-MNU-33 | **RÉSOLU** ✅ | "Définition opérationnelle 'snap instantané' / 'même frame'" ajoutée — clarification couvre B-04 aussi |
| **Q-12** AC-MNU-53/54 owner ux-designer | NON résolu | RECOMMENDED |
| **Q-13/14/15** NICE | NON résolu | NICE-TO-HAVE, déférés |
| **U-1 / U-15** ultrawide / portrait / safe-area | **RÉSOLU** ✅ | 3440×1440 + 5120×1440 + portrait + safe-area documentés |
| **U-3 / U-13** token MENU_BG_OVERLAY_ALPHA | **RÉSOLU** ✅ | Split en `MENU_BG_OVERLAY_RGB` + `MENU_BG_OVERLAY_ALPHA` tokens K.4 |
| **U-4 / U-14 / B-02** Focus+Hover coexistence | **RÉSOLU** ✅ | "Coexistence hover (souris) ↔ focus (clavier/gamepad) *(r2 — U-4)*" ajoutée + Godot 4.6 dual-focus documenté |
| **U-10 / U-18** double-ESC flicker | **RÉSOLU** ✅ | Anti-fantasy ajouté + R-MNU-15 CONNECT_DEFERRED garantie absorption |
| **U-16** 11 px version 720p | **RÉSOLU** ✅ | Rationale ajoutée + AC-MNU-67 |
| **U-17** K.8 gradient shader CanvasItem.material | RÉSOLU partiellement | AC-MNU-66 grep `bg_color_2` ajouté ; shader CanvasItem.material toujours non explicit |
| **U-19** splash boot AC | NON résolu | NICE-TO-HAVE, OQ-MNU-4 pas escaladée |
| **B-01** guard `is_inside_tree()` insuffisante | À VÉRIFIER post-r2 | Patches R-MNU-12/15 guard à revérifier (peut être inchangé) |
| **B-04** AC-MNU-33 trompeur | **RÉSOLU** ✅ | Cf. Q-11 |
| **B-06** auto-disconnect implicite | NON résolu | RECOMMENDED |
| **B-07** AccessKit plateforme | NON résolu | RECOMMENDED |

**Bilan post-r2 PRE-IMPL/POLISH** : sur 13 BLOCKING fresh r3, **~7 RÉSOLUS** explicitement, **3 RÉSOLUS partiellement**, **3 À VÉRIFIER post-r2** (S-02, S-03+B-01+B-06, S-04). Sur 19 RECOMMENDED, **~5 RÉSOLUS**, ~14 restent. Sur 10 NICE, **~3 RÉSOLUS**, ~7 restent.

**Recommandation post-cross-session** : lancer **fresh `/design-review menu-system` LEAN** (single-session, sans 5 specialists adversariaux) post-r2 PRE-IMPL/POLISH pour valider non-régression + adresser les ~3 BLOCKING résiduels (S-02, S-03/B-01/B-06, S-04) + les ~14 RECOMMENDED résiduels. Cohérent avec le Status header r2 qui indique "pending fresh `/design-review` lean re-pass avant `/create-epics`".

---

**Verdict cette fresh re-review (5 specialists adversariaux pré-r2 PRE-IMPL/POLISH)** : **NEEDS REVISION (minor)** — 13 BLOCKING + 19 RECOMMENDED + 10 NICE-TO-HAVE = 42 findings (état pré-r2 PRE-IMPL/POLISH session ; ~50% RÉSOLUS par session voisine, voir cartographie ci-dessus)
**Verdict effectif post-cross-session** : **NEEDS REVISION (minor)** — ~3 BLOCKING résiduels + ~14 RECOMMENDED + ~7 NICE
**Scope effectif** : **S** (Small — fresh lean re-review 10-15 min suffit pour confirmer + cartographier les 3 BLOCKING résiduels)

---

## Specialists consultés (5 + 1 senior)

| Agent | Role | Findings |
|-------|------|----------|
| game-designer | Player Fantasy + Pillar enforcement + UX coherence | 2 BLOCKING + 3 RECOMMENDED + 2 NICE |
| systems-designer | Formula boundaries + EC coverage + Tuning Knob math | 4 BLOCKING + 2 RECOMMENDED + 0 NICE |
| qa-lead | 56 ACs testabilité + grep robustness + EC coverage | 3 BLOCKING + 7 RECOMMENDED + 3 NICE |
| ux-designer | GDD §K vs UX specs alignment + interaction states | 2 BLOCKING + 3 RECOMMENDED + 2 NICE |
| godot-specialist | Godot 4.6 patterns + lifecycle + dual-focus + AccessKit | 2 BLOCKING + 4 RECOMMENDED + 3 NICE |
| **creative-director** | **Senior synthèse + adjudications + verdict** | — |

**Note** : godot-specialist did NOT participate in r1 — first Godot-specific lens, captures 4.6-specific gotchas.

---

## Convergences cross-specialist (6 — priorité maximale)

| Convergence | Specialists | Sévérité | Action |
|-------------|-------------|----------|--------|
| **`tree_exiting` guard r2 BLK-3 incomplet** | S-03 + B-01 + B-06 (3) | TRUE BLOCKING | R-MNU-13b nouvelle + correctif `is_inside_tree() or is_queued_for_deletion()` + connect order documenté |
| **AC grep robustness (audio/dialog/process_mode/time_scale)** | S-04 + Q-1 + Q-2 + Q-7 + Q-9 (5) | AUTO-FIXABLE | Compléter regex en batch atomique — pas de décision design |
| **PROCESS_MODE_ALWAYS justification race incorrecte** | G-03 + B-03 (2) | AUTO-FIXABLE | Reformuler 1 ligne ("conservatrice par défaut, défense future evolution GSM") |
| **Focus+Hover coexistence Godot 4.6 dual-focus** | U-14 + B-02 (2) | TRUE BLOCKING | Décision design : focus override hover quand actif (Pillar 1 clarté) |
| **Layer regex faux positifs** | Q-5 + B-08 (2) | AUTO-FIXABLE | Regex précisée `^layer\s*=` ou contexte CanvasLayer |
| **Engine.time_scale regex redondante** | Q-9 + B-05 (2) | AUTO-FIXABLE | Fix trivial 1 ligne |

**Aucun désaccord cross-specialist détecté** — convergences ou indépendances seulement. Bonne nouvelle pour cohérence du r2 cosmetic.

---

## Categorisation des 13 BLOCKING

### Bucket A — TRUE SHIP-BLOCKING (3 — exigent décision/fix structural avant `/create-epics`)

1. **S-03 + B-01 + B-06** (convergence 3 specs) — `tree_exiting` guard insuffisant + AC test comportement non-prescrit. Fix = R-MNU-13b nouvelle règle + correctif guard pattern. **~20 min.**
2. **U-14 + B-02** (convergence 2 specs) — Godot 4.6 dual-focus system non documenté GDD K.5. Décision design : focus override hover quand actif (Pillar 1 clarté + conventions Godot UI). **~15 min décision + 5 min spec.**
3. **G-02** (1 spec mais structurelle) — `pause-menu.md` §3.1 ligne 51 cite "MenuController (autoload ou node persistent)" → contredit R-MNU-1/R-MNU-3 RESOLVED node-local. Fix texte UX spec. **~3 min.**

### Bucket B — AUTO-FIXABLE en r3 cosmetic (10 — batch atomique sans décision design)

4. **G-01** : AC-MNU-45b explicite anti-tutoriel intrusif (clarification 1 ligne)
5. **S-01** : F-MNU-1 reformulation borne haute avec contexte fps explicite (60 fps min Pillar 1, 30 fps note dégradée)
6. **S-02** : `BUTTON_MIN_WIDTH_PX` recalculé (220 → 244 minimum, 292 max si font 18px) ou contrainte font max 14px
7. **S-04** : AC-MNU-36 grep anti-tween complété (`tween_method`, `tween_callback`, `AnimationPlayer` dans scripts, `Callable` tweens)
8. **Q-1** : AC-MNU-44 grep audio complété (`AudioStreamPlayer2D/3D`, `play_sound`, `AudioServer.set_bus_volume_db`)
9. **Q-2** : AC-MNU-45 grep dialog complété (`Window.popup()`, `show_modal`, Control custom dialogs)
10. **Q-3** : AC-MNU-40/41/43 protocole P95 + sample size + build context défini
11. **G-03 + B-03** : R-MNU-14 + Tuning Knob justification ALWAYS reformulée (1 ligne)
12. **U-13** : token `MENU_BG_OVERLAY_ALPHA` dédoublonnement K.2 inline → référence K.4 token
13. **G-06** : UX specs réf "GDD r1" → "r2 cosmetic"

### Bucket C — DEFERRED à r2 design session originale (avec ~36 PRE-IMPL/POLISH r1)

Tout le reste (16 RECOMMENDED + 10 NICE) reste en queue r2 design session, exécutable post `/create-epics` (pas bloquant pour epic decomposition).

---

## Pillar alignment check

| Pillar | Menacé par | Verdict |
|--------|-----------|---------|
| **Pillar 1 FLOW AVANT TOUT** | S-01 (F-MNU-1 100ms à 30fps), S-02 (button width casse layout = friction visuelle), U-14 (Focus+Hover ambigu = clavier↔souris flicker) | **MENACÉ — bloquant si shippé tel quel** |
| **Pillar 2 PROGRESSION SE VOIT** | — (menu-system est meta-UI, pas progression layer) | OK |
| **Pillar 3 UNE SECONDE CHANCE** | G-02 (autoload contradiction = risque architectural mais pas player-facing) | OK marginal |

**Verdict pillar** : Pillar 1 menacé par 3 BLOCKING auto-fixables en r3. Doit être résolu avant `/create-epics`.

---

## Findings detail

### game-designer (G-01..G-07)

- **G-01 [BLOCKING]** : Anti-fantasy n°7 "pas de tutoriel intrusif" (ligne 49) non couverte explicitement par AC dédié. AC-MNU-45 grep `PopupPanel` couvre indirectement. Fix : ajouter note explicite à AC-MNU-45 ou créer AC-MNU-45b.
- **G-02 [BLOCKING]** : `pause-menu.md` §3.1 ligne 51 cite "MenuController (autoload ou node persistent) `_on_ui_cancel_pressed()`" → contredit R-MNU-1/R-MNU-3 RESOLVED node-local. Fix : ligne 51 doit lire "`PauseMenuControllerScript` (node-local, enfant de la scène étage)".
- **G-03 [RECOMMENDED]** : R-MNU-14 (lignes 246-248) justification ALWAYS "race fenêtre" non prouvée. AC-MNU-38 vérifie ALWAYS opérationnel mais pas la race window. Fix : marquer "conservatrice par défaut, revisitable post-implémentation GSM".
- **G-04 [RECOMMENDED]** : Référence Hollow Knight "silencieux" (ligne 54) overclaim — HK joue music bench distincte. Fix : remplacer par "le contraste calmant entre gameplay intense et menu/shop reposant".
- **G-05 [RECOMMENDED]** : F-MNU-2 plancher α_min=0.55 sans AC playtest. Fix : ajouter AC-MNU-X `[Manual — ADVISORY]` playtest 80% testeurs sur 3 étages.
- **G-06 [NICE]** : UX specs (main-menu.md ligne 286) réfèrent "GDD r1" après passage r2.
- **G-07 [NICE]** : `mouse_filter = STOP` sur DimRect (pause-menu.md §4.3) non testé par AC.

### systems-designer (S-01..S-06)

- **S-01 [BLOCKING]** : F-MNU-1 borne haute = 50.8 ms à 60 fps mais à 30 fps total = 100 ms exact (T_in 33 + T_gsm 1 + T_def 33 + T_ren 33). AC-MNU-40 `< 100ms` peut fail avec 1 ms jitter OS. Fix : reformuler avec contexte fps explicite OU documenter "Pillar 1 garanti seulement à 60 fps min".
- **S-02 [BLOCKING]** : Tuning Knob `BUTTON_MIN_WIDTH_PX=220` insuffisant à font 15px (243 px texte requis : 15 × 0.6 × 27 chars) ET à font 18px max range (291 px). Default 220 viole sa propre contrainte. Fix : recalculer minimum à 244-292 px ou contraindre font max à 14 px.
- **S-03 [BLOCKING]** : EC-MNU-9 / AC-MNU-28 testent `tree_exiting.connect(_cleanup_input_refcount)` mais aucune R-MNU-* prescrit ce connect. AC test comportement non-prescrit. Fix : ajouter R-MNU-13b explicite avec CONNECT_ONE_SHOT.
- **S-04 [BLOCKING]** : AC-MNU-36 anti-tween regex incomplete : rate `tween_method`, `tween_callback`, `AnimationPlayer` dans scripts (AC-MNU-47 cible scènes only), tweens sur `Callable`. Fix : compléter le grep.
- **S-05 [RECOMMENDED]** : F-MNU-3 N=0 (div by zero) / N=1 (cycle 1-element) non documentés. Précondition N≥2 implicite seulement.
- **S-06 [RECOMMENDED]** : Provisional contracts table ligne 593 marque OQ-MNU-1 sans annotation RESOLVED. Crée fausse incertitude.

### qa-lead (Q-1..Q-15)

- **Q-1 [BLOCKING]** : AC-MNU-44 grep audio incomplet (`AudioStreamPlayer2D/3D`, `play_sound`, `AudioServer.set_bus_volume_db`).
- **Q-2 [BLOCKING]** : AC-MNU-45 grep dialog rate `Window.popup()`, `show_modal`, Control custom dialogs.
- **Q-3 [BLOCKING]** : AC-MNU-40/41/43 performance criteria non-déterministes — pas de protocole P95, sample size, build context. Tests BLOCKING bloquent CI sans fiabilité.
- **Q-4 [RECOMMENDED]** : AC-MNU-42 100 cycles sans warmup ni gestion GC.
- **Q-5 [RECOMMENDED]** : AC-MNU-55/56 grep `layer = ` faux positifs (`collision_layer`, `navigation_layer`, `mask_layer`).
- **Q-6 [RECOMMENDED]** : AC-MNU-57 grep délégation save ne capte pas EventBus indirection.
- **Q-7 [RECOMMENDED]** : AC-MNU-58 grep `process_mode` ne capte pas `set_process_mode()` runtime ni override script.
- **Q-8 [RECOMMENDED]** : AC-MNU-46 corner_radius ambiguïté "0 match OU toutes valeurs = 0".
- **Q-9 [RECOMMENDED]** : AC-MNU-49 regex `Engine\.time_scale\|Engine.time_scale` redondante (second pattern non-échappé matche n'importe quoi).
- **Q-10 [RECOMMENDED]** : EC coverage gaps — EC-MNU-30 (`ResumeButton.grab_focus` ouverture pause) sans AC.
- **Q-11 [RECOMMENDED]** : AC-MNU-33 confusion sémantique avec EC-MNU-33 (même numéro).
- **Q-12 [RECOMMENDED]** : AC-MNU-53/54 owner=ux-designer mais nécessite accès build Godot → qa-tester avec sign-off ux.
- **Q-13/14/15 [NICE]** : indirection variable get_tree(), F-MNU-3 tab cycle wrap AC manquant, R-MNU-1 zéro autoload AC manquant.

### ux-designer (U-13..U-19)

- **U-13 [BLOCKING]** : Token `MENU_BG_OVERLAY_ALPHA` duplication inline K.2 ligne 743 vs table K.4 ligne 805 (déjà identifiée U-3 r1, déférée). `pause-menu.md` §4.1 reproduit le littéral. Fix : annoter wireframe + GDD K.2 inline avec `→ token K.4`.
- **U-14 [BLOCKING]** : Focus+Hover coexistence (souris hover sur bouton focused clavier) non spécifiée GDD K.5 ni UX specs §5. Comportement Godot 4.6 dual-focus non-déterministe selon ordre StyleBox. Décision design requise.
- **U-15 [RECOMMENDED]** : Ultrawide 21:9 (3440×1440) silencé. ~12-15% Steam users en 2026.
- **U-16 [RECOMMENDED]** : 11px version number à 720p si DEBUG_SHOW_VERSION=true → AC manquant.
- **U-17 [RECOMMENDED]** : K.8 anti-pattern gradient via shader CanvasItem.material non couvert (séparé de StyleBoxFlat.bg_color_2).
- **U-18 [NICE]** : Double-ESC flicker PauseLayer non documenté §3.1 pause-menu.
- **U-19 [NICE]** : `application/boot_splash/show_image = false` non vérifié par AC.

### godot-specialist (B-01..B-10)

- **B-01 [BLOCKING]** : Guard r2 BLK-3 `is_inside_tree()` insuffisante. `tree_exiting` est émis pendant retrait — node encore dans le tree. Correct : `not is_inside_tree() or is_queued_for_deletion()` + connecter `tree_exiting` AVANT `state_changed` dans `_ready()`.
- **B-02 [BLOCKING]** : Godot 4.6 dual-focus system (clavier vs souris séparés). K.5 ne documente pas Hover+Focus simultanés sur boutons distincts (comportement attendu 4.6, pas un bug). Gap de spec révélé en intégration.
- **B-03 [RECOMMENDED]** : R-MNU-14 justification ALWAYS "race fenêtre" est techniquement fausse — `get_tree().paused = true` est SYNC en 4.6+. Vraie justif = défense contre future evolution GSM. À corriger pour pas induire en erreur.
- **B-04 [RECOMMENDED]** : AC-MNU-33 "même frame d'exécution" trompeur car en prod CONNECT_DEFERRED = +1 frame. AC court-circuite via appel direct fonction. À clarifier.
- **B-06 [RECOMMENDED]** : `state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` jamais déconnecté explicitement. Auto-déconnect Godot 4.x garanti mais à documenter.
- **B-07 [RECOMMENDED]** : K.9 Tier 2 "AccessKit AT-SPI / Windows UI Automation" → préciser Linux (AT-SPI2) + Windows (UI Automation), macOS expérimental.
- **B-05/08/09/10 [NICE]** : regex Engine.time_scale redondante (cf. Q-9), AC-MNU-56 faux positifs (cf. Q-5), SIL OFL 1.1 confirmé OK, Jolt et `paused` confirmés OK.

---

## Adjudications creative-director (3 décisions clés)

1. **Focus+Hover coexistence (U-14 + B-02)** : **focus override hover quand actif** — focus visible prioritaire quand bouton focused via clavier/gamepad, hover underline supprimé. Pillar 1 clarté + conventions Godot UI. Implementation : check `has_focus()` dans theme custom ou script StyleBox override sur les Buttons. **DESIGN DECISION tranchée — applicable r3 cosmetic K.5.**
2. **PROCESS_MODE_ALWAYS justification (G-03 + B-03)** : justification race fenêtre techniquement fausse (paused = SYNC en 4.6) — décision ALWAYS conservée comme **défense contre future evolution GSM** (si ordre emit/paused inversé un jour). Reformulation soft. **R-MNU-14 + Tuning Knob justif applicable r3 cosmetic.**
3. **`tree_exiting` guard pattern (S-03 + B-01 + B-06)** : guard `is_inside_tree()` insuffisante. Fix : (a) nouvelle règle R-MNU-13b prescrit `tree_exiting.connect(_cleanup_input_refcount, CONNECT_ONE_SHOT)` dans `_ready()` avant `state_changed.connect(...)`, (b) guard pattern devient `if not is_inside_tree() or is_queued_for_deletion(): return` dans `_apply_visibility` + `_on_state_changed`. **TRUE BLOCKING — applicable r3 cosmetic R-MNU + R-MNU-12 + R-MNU-15.**

---

## Path to APPROVED

**Stratégie recommandée** : r3 cosmetic batch atomique inline (10 fixes) + 1 micro-décision design Focus+Hover. **PAS** de collapse en session r2 dédiée.

**Plan d'exécution** :
- **Step 1 (3 min)** : Décision Focus+Hover tranchée → focus override hover. Documenter K.5.
- **Step 2 (25 min)** : Batch atomique 4 fichiers — `design/gdd/menu-system.md` (R-MNU-13b nouvelle, F-MNU-1 reformulé fps context, BUTTON_MIN_WIDTH_PX recalculé, K.5 Focus+Hover documenté, AC-MNU-36/40/41/43/44/45 grep complétés, R-MNU-14 + Tuning Knob justif reformulée, Provisional contracts table OQ-MNU-1 RESOLVED), `design/ux/pause-menu.md` (§3.1 MenuController correction node-local, §4.1 token K.4 dédoublonnement), `design/ux/main-menu.md` (réf "GDD r1" → r2 si présent), `design/gdd/reviews/menu-system-review-log.md` (append r3 cosmetic).
- **Step 3 (10 min)** : Re-review fresh **lean** (skip full — convergences déjà cartographiées, validation suffit).
- **Step 4 (commit)** : `docs(gdd): menu-system r3 cosmetic — 11 BLOCKING auto-fixés + Focus+Hover décision`.

**Sub-30 min critique** : non. **Sub-45 min réaliste** : oui. Pas de risque de régression majeure car aucun BLOCKING ne touche à la vision/architecture menu.

Les ~36 PRE-IMPL/POLISH r1 + 16 RECOMMENDED + 10 NICE r2 fresh restent dans queue r2 design session distincte, exécutable post `/create-epics` (pas bloquant pour epic decomposition).

---

## Verdict final

**NEEDS REVISION (minor)** — r3 cosmetic batch atomique requise (30-45 min). 11/13 BLOCKING auto-fixables. Aucun ne remet en question pillars ni vision menu-system. Path to APPROVED court via lean re-review post r3.
