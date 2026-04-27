# Menu System — Review Log

> Continuous trace of all `/design-review` and review-related amendments to `design/gdd/menu-system.md`.
> Newest entries on top.

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
