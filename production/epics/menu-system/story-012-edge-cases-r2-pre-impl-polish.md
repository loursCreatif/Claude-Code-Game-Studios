# Story 012: Edge Cases r2 PRE-IMPL/POLISH — EC-MNU-36..42 + Tab Cycle Wrap

> **Epic**: Menu System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: M (3-4 h, 7 ECs r2 + tab wrap + process_mode runtime + layer convention M)
> **Performance**: transitions OS (minimize/sleep/dual-monitor focus loss) hors hot path. AC-MNU-38/39 process_mode runtime check zéro alloc (lecture propriété).

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `EC-MNU-36..42` (r2 PRE-IMPL/POLISH NEW), `F-MNU-3` (tab cycle wrap déterministe)

**ADR Governing Implementation**: ADR-0007 D-2 matrice transitions (LOADING/quit pendant change_scene_to_file) ; ADR-0004 D-7 mouse_mode single source of truth (focus events fenêtre) ; ADR-0010 R-SAV-8 PROCESS_MODE_ALWAYS SaveLoad reçoit notification quel que soit `paused`.

**Engine**: Godot 4.6 | **Risk**: LOW (test coverage edge cases — code Menu déjà livré stories précédentes)
**Engine Notes**: `NOTIFICATION_WM_WINDOW_FOCUS_OUT/IN` Godot natif ; `MOUSE_MODE_*` enum stable.

---

## Acceptance Criteria

*Couverture des 7 NEW r2 ECs + tab cycle wrap :*

- [ ] **EC-MNU-36 (S-3)** : quit pendant `change_scene_to_file` LOADING phase ; `get_tree().quit()` reçu pendant transition → SaveLoad R-SAV-9 handler reçoit `NOTIFICATION_WM_CLOSE_REQUEST`, flush state, quit propre. Aucun crash, aucun double save.
- [ ] **EC-MNU-37 (S-5)** : window minimize pendant Pause Menu visible ; mouse_mode reste libre (InputManager D-7 respecte `application_focus_lost` signal) ; au restore mouse_mode pas auto-recapturée par Menu (responsabilité InputManager).
- [ ] **EC-MNU-38 (S-6)** : OS sleep/wake pendant Pause Menu visible ; mêmes contraintes que minimize — Menu ne pose pas son handler focus (AC-MNU-63 enforce).
- [ ] **EC-MNU-39 (S-7)** : controller hot-plug pendant Pause Menu visible ; `Input` natif Godot recharge mappings ; Menu ne fait rien de spécifique (Tier 2+ remap = OQ-MNU-3).
- [ ] **EC-MNU-40 (S-12)** : lifecycle PRE_READY (visible state transient avant `_ready()`) ; Pause Overlay instancié + GSM=PAUSED ; `_ready()` exécute pull pattern + `_apply_visibility(true)` AVANT premier rendu — pas de flash 1-frame.
- [ ] **EC-MNU-41 (G-6 + G-9)** : étage gameplay sans Pause Overlay instancié → ESC silencieux (signal émis dans le vide) ; lint AC-MNU-59 enforce zero/double-instance authoring (couvert Story 002).
- [ ] **EC-MNU-42 (Q-11)** : dual-monitor focus loss pendant Pause Menu visible ; mouse_mode délégué InputManager D-7 ; Menu ne pose pas son propre handler focus (AC-MNU-63 enforce).
- [ ] **AC-MNU-61** [Logic — BLOCKING] *(r2 — F-MNU-3 tab cycle wrap)* : Pause Overlay visible (N=3 boutons) + `ResumeButton.has_focus()` ; Shift+Tab → `QuitButton.has_focus()` (wrap inverse vers dernier).
- [ ] **AC-MNU-38** [Logic — ADVISORY] : GSM applique `get_tree().paused = true` ; `PauseLayer.process_mode == PROCESS_MODE_ALWAYS` ; `PauseLayer._process(delta)` est appelé sous tree paused — confirme que ALWAYS est opérationnel runtime, pas seulement déclaré .tscn.
- [ ] **AC-MNU-39** [Logic — ADVISORY] : grep `process_mode` sur nodes gameplay (`MovementController`, `CombatSystem`, `LevelSystem`) dans `etage_*.tscn` retourne `process_mode = 1` (PAUSABLE) OU absence (héritage INHERIT) — confirme que le gameplay se fige bien pendant PAUSED.
- [ ] **Layer convention M cross-overlay runtime** : pendant Pause Menu visible, vérifier que `HUD CanvasLayer.layer = 50 < Shop = 60 < Pause = 80 < GSM-fade = 100` ; Pause Overlay couvre HUD/Shop, GSM-fade couvre Pause (transition vers MENU).

---

## Implementation Notes

*Couverture par tests + behavior verification — code menu existe déjà via Stories 002-008 :*

1. **EC-MNU-36 quit pendant LOADING** :
   - Test integration : MockGSM en transition `change_scene_to_file` (LOADING phase simulée) ; `get_tree().quit()` déclenché en parallèle.
   - Vérifier : MockSaveLoad reçoit `NOTIFICATION_WM_CLOSE_REQUEST` (R-SAV-9 + R-SAV-8 PROCESS_MODE_ALWAYS), flush_call_count == 1.
   - Aucun code Menu ajouté — comportement par construction délégation pure (R-MNU-19).
2. **EC-MNU-37/38/42 focus events fenêtre** :
   - AC-MNU-63 (Story 004 + Story 010 lint) garantit que Menu ne pose pas son `_notification` focus handler.
   - Test integration : simuler `NOTIFICATION_WM_WINDOW_FOCUS_OUT` envoyé au tree ; vérifier que mouse_mode actuel n'est pas modifié par Menu (mais peut l'être par InputManager — owned ailleurs).
3. **EC-MNU-39 controller hot-plug** :
   - Test : Pause Overlay visible + `joy_connection_changed` signal Godot natif émis.
   - Vérifier : aucun crash, aucun changement d'état Menu, focus reste sur le bouton actuel.
4. **EC-MNU-40 PRE_READY anti-flash** :
   - Test : MockGSM `_state = PAUSED` AVANT instanciation Pause Overlay ; `_apply_visibility(true)` doit être appelé dans `_ready()` AVANT première frame rendue (vérification via `await get_tree().process_frame` ne montre jamais visible == false).
   - Cette story re-vérifie ce que Story 005 AC-MNU-7 + AC-MNU-35 livrent — gate explicite anti-flash.
5. **EC-MNU-41 zero-instance silent ESC** :
   - Test : étage gameplay sans `pause_overlay.tscn` instancié (cas erreur authoring) ; `ui_cancel_pressed.emit()` → aucun crash, signal émis dans le vide.
   - Lint AC-MNU-59 (Story 002) enforce qu'en authoring, chaque étage en a exactement 1 — donc test runtime + lint authoring complémentaires.
6. **AC-MNU-38 process_mode runtime opérationnel** : test integration vérifie que `PauseLayer._process()` est bien appelé alors que `get_tree().paused == true`. Méthode : flag `_process_call_count_under_paused` incrémenté dans `_process(delta)` ; assertion `> 0` après `MockGSM.request_pause()` + `await process_frame` ×3.
7. **AC-MNU-39 gameplay nodes PAUSABLE** : test static parse `etage_*.tscn` ; pour chaque `[node ...]` qui inherite/hérite de `MovementController`/`CombatSystem`/`LevelSystem`, vérifier `process_mode = 1` ou absence.
8. **Layer convention M cross-overlay runtime** : test integration instancie HUD + Shop + Pause + GSM-fade simultanément (cas edge transition Shop → Pause → MainMenu), vérifie ordering visuel via `get_canvas_layer()`. Cohérence avec AC-MNU-55 (static `layer = 80`) + AC-MNU-56 (static unique values {50,60,80,100}) couverts Stories 002 + 009.
9. **AC-MNU-61 tab cycle wrap inverse F-MNU-3** :
   ```gdscript
   func test_pause_menu_shift_tab_wraps_to_last_button() -> void:
       _show_pause_overlay()
       resume_button.grab_focus()
       await get_tree().process_frame
       assert_true(resume_button.has_focus())
       # Simuler Shift+Tab via InputEventKey
       var ev := InputEventKey.new()
       ev.keycode = KEY_TAB
       ev.shift_pressed = true
       ev.pressed = true
       Input.parse_input_event(ev)
       await get_tree().process_frame
       assert_true(quit_button.has_focus())  # wrap vers dernier
   ```
   F-MNU-3 formule : `next_index = (current + 1) mod N` ; bornes N=0 (no-op) + N=1 (idempotent) + N=3 wrap forward+inverse.

---

## Out of Scope

- Stories 001-008 : code menu lui-même (cette story consomme et teste).
- Story 010 : lints AC-MNU-59 + AC-MNU-63 + AC-MNU-64 (cette story se base sur leur enforcement).
- Settings Menu OQ-MNU-3 Tier 2+ (input remap controller).

---

## QA Test Cases

**EC-MNU-36** : quit pendant LOADING
- Given : MockGSM `_state = LOADING` (transition en cours) ; MockSaveLoad PROCESS_MODE_ALWAYS.
- When : `get_tree().quit()` déclenché ; SceneTree émet `NOTIFICATION_WM_CLOSE_REQUEST`.
- Then : `assert_eq(MockSaveLoad.flush_call_count, 1)` ET aucun crash.
- Edge cases : si SaveLoad pos-3 autoload pas vivant → assert fail (mais GSM D-1 garantit ordre).

**EC-MNU-37 / 38 / 42** : focus events fenêtre
- Given : Pause Overlay visible ; mouse_mode = MOUSE_MODE_VISIBLE (libre en pause).
- When : `NOTIFICATION_WM_WINDOW_FOCUS_OUT` émis sur tree (simule minimize/sleep/dual-monitor).
- Then : `MockInputManager.set_mouse_mode_call_count` peut varier (owned ailleurs) ; Menu n'a pas de handler — `assert_eq(menu.focus_handler_call_count, 0)` ; aucun crash.
- Edge cases : InputManager D-7 owne la logique mouse_mode — Menu ne fait rien.

**EC-MNU-39** : controller hot-plug
- Given : Pause Overlay visible avec ResumeButton focused.
- When : `Input.joy_connection_changed.emit(0, true)` simulé (controller branché).
- Then : `assert_true(resume_button.has_focus())` (focus persiste) ; aucun crash.

**EC-MNU-40** : anti-flash PRE_READY
- Given : MockGSM `_state = PAUSED` AVANT `pause_overlay.tscn` instancié.
- When : instancier ; `_ready()` exécute pull + `_apply_visibility(true)` ; capturer `pause_layer.visible` à chaque process_frame depuis instanciation.
- Then : aucun frame où `visible == false` (anti-flash 1-frame).

**EC-MNU-41** : étage sans Pause Overlay (silent ESC)
- Given : étage chargé SANS `pause_overlay.tscn` instancié (cas erreur authoring) ; GSM=PLAYING.
- When : `ui_cancel_pressed.emit()`.
- Then : aucun crash ; `request_pause_call_count == 0` (aucun handler connecté côté Menu) ; lint AC-MNU-59 fail authoring time.

**AC-MNU-38** : process_mode opérationnel runtime
- Given : MockGSM `_state = PLAYING`, Pause Overlay instancié avec `process_mode = PROCESS_MODE_ALWAYS = 3`, flag `_process_call_count_under_paused = 0`.
- When : `MockGSM.request_pause()` ; `get_tree().paused = true` ; `await get_tree().process_frame` ×3.
- Then : `assert_gt(pause_layer._process_call_count_under_paused, 0)`.
- Edge cases : si `process_mode = WHEN_PAUSED (2)` ou `DISABLED (4)` → `_process` non appelé → assertion fail.

**AC-MNU-39** : gameplay nodes PAUSABLE
- Setup : pour chaque `etage_*.tscn`, parser les nodes inheriting `MovementController`/`CombatSystem`/`LevelSystem`.
- Verify : chacun a `process_mode = 1` (PAUSABLE) OU absence de propriété.
- Pass condition : aucun node gameplay avec ALWAYS (3) ou DISABLED (4) — sinon le gameplay continuerait pendant Pause.

**Layer convention M cross-overlay runtime** :
- Given : étage avec HUD layer=50 + Shop layer=60 + PauseLayer layer=80 + GSM-fade layer=100 instanciés.
- When : Pause Overlay visible (state PAUSED) ; transition vers MENU déclenche GSM-fade.
- Then : ordre visuel runtime cohérent — Pause couvre HUD+Shop ; GSM-fade couvre Pause pendant transition.
- Pass condition : pas de bleed-through visuel (vérification screenshot manuel + check `CanvasLayer.layer` runtime).

**AC-MNU-61** : Shift+Tab wrap inverse
- Given : Pause Overlay visible (3 boutons : Resume, MainMenu, Quit) ; `ResumeButton.has_focus()`.
- When : Shift+Tab via `Input.parse_input_event(InputEventKey.shift_tab)`.
- Then : `assert_true(quit_button.has_focus())`.
- Edge cases : N=0 → no-op ; N=1 → idempotent (focus stable).

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/integration/menu/edge_cases_r2_test.gd` (EC-MNU-36..42, MockGSM + MockSaveLoad + simulation focus events)
- `tests/integration/menu/tab_cycle_wrap_test.gd` (AC-MNU-61 F-MNU-3 wrap forward + inverse + N=0/1 bornes)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Stories 002, 004, 005, 007, 008 (Pause Overlay + state sync + apply_visibility + boutons + refcount livrés) ; Story 010 (lints AC-MNU-59/63/64 actifs).
- Unlocks : Story 013 (playtest manuel peut couvrir EC-37/38/42 sur hardware réel — confirmation cross-OS).

---

## Completion Notes

**Completed** : 2026-05-02
**Criteria** : 10/11 COVERED automatic + 1 SKIP gracieux MVP (AC-MNU-39 etage_*.tscn empty — lint activates Sprint 1).
**Mode review** : Solo — QL-TEST-COVERAGE + LP-CODE-REVIEW gates skipped. Manual `/code-review` pass 2026-05-02 → APPROVED.
**Test Evidence** :
- `tests/integration/menu/edge_cases_r2_test.gd` (NEW) — 10 tests GdUnit4 (EC-MNU-36/37/38/39/40/41/42 + AC-MNU-38 process_mode + AC-MNU-39 PAUSABLE static parse + Layer M cross-overlay × 2).
- `tests/integration/menu/tab_cycle_wrap_test.gd` (NEW) — 7 tests GdUnit4 (AC-MNU-61 Shift+Tab inverse wrap + Tab forward wrap + N=0/1/3 bornes + 3 boutons cycle).
**Tests run** : 17/17 PASSED (nouveaux fichiers) + suite menu complète **89/89 PASSED 0 régression** (50 integration + 8 theme + 10 anti-patterns + 4 perf + 17 story-012 = 89 total cumulé).

**Deviations ADVISORY** :
1. **EC-MNU-36 quit during LOADING** : test ne peut pas appeler `get_tree().quit()` (tuerait le runner). Couverture hybride : (a) runtime check MockSaveLoad inside_tree + process_mode = ALWAYS (conditions nécessaires R-SAV-9), (b) static check Menu non-comment code ne contient pas `NOTIFICATION_WM_CLOSE_REQUEST` (delegation pure R-MNU-19). Conforme à la note story Implementation §1 : "Aucun code Menu ajouté".
2. **AC-MNU-39 etage_*.tscn glob** : MVP `scenes/levels/` ne contient que `primitives/` (pas de `etage_*.tscn`). Test SKIP gracieux avec print informatif — réactivé Sprint 1 quand etage_01.tscn arrivera.
3. **Helper `_has_non_comment_pattern`** ajouté pour exclure les commentaires (`##` ou `#`) du grep AC pattern check — le `pause_menu_controller.gd` mentionne `NOTIFICATION_WM_CLOSE_REQUEST` dans des `##` doc strings. Workaround propre, cohérent avec project lint patterns.
4. **Workaround InputManager bug story-011** réutilisé : `_force_clean_input_blocker_connection(owner)` dans cleanup. Tech debt potentiel ADR-0004 amendement déjà flagué Sprint 1.

**Tech debt logged** : 0 nouveaux items. Tech debt InputManager déjà tracé story-011.
