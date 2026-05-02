# Story 003: Trigger ESC — `ui_cancel_pressed` Pause/Resume

> **Epic**: Menu System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: M (3-4 h)
> **Performance**: Pillar 1 critique — `_on_ui_cancel_pressed` handler < 0.5 ms CPU (match léger, pas d'I/O, pas d'instanciation). Pause snap perçu < 100 ms total (mesuré story 011).

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-5`, `R-MNU-6`, `R-MNU-7`, `R-MNU-17` (idempotence)

**ADR Governing Implementation**: ADR-0004 Input API + Focus Handling
**ADR Decision Summary**: D-4 — InputManager émet signal `ui_cancel_pressed` event-driven, **toujours émis même si `enabled == false`** (R-MNU-5 trigger ESC garanti même quand Menu owne refcount disable). Consumers consomment via `connect`, jamais polling `Input.is_action_pressed`. Matrice transitions ADR-0007 D-2 interdit Pause pendant `RESPAWNING`/`BOSS_DEFEATED`/`MENU`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Signal `ui_cancel_pressed` typed (zero arg) ADR-0004 contract.

**Control Manifest Rules**:
- Required : `signal.connect(callable)` typed connect (Foundation rule).
- Forbidden : `Input.is_action_just_pressed` direct depuis gameplay/menu (use signal-driven).
- Guardrail : `_on_ui_cancel_pressed` < 0.5 ms CPU (handler léger).

---

## Acceptance Criteria

- [x] **AC-MNU-11** [Integration — BLOCKING] : GSM=PLAYING + Pause Overlay instancié ; `InputManager.ui_cancel_pressed.emit()` → `GameStateManager.request_pause()` appelé exactement 1×.
- [x] **AC-MNU-13** [Integration — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `ui_cancel_pressed.emit()` → `GameStateManager.request_resume()` appelé 1× ET après `state_changed(PLAYING)` `PauseLayer.visible == false`. [Visibility propagation = story-004 — testé ici par transition state seule.]
- [x] **AC-MNU-14** [Logic — BLOCKING] : GSM=RESPAWNING ; `ui_cancel_pressed.emit()` → ni `request_pause()` ni `request_resume()` appelés, aucune exception (matrice ADR-0007 D-2). [Étendu BOSS_DEFEATED + MENU même branche `_:`].
- [x] **AC-MNU-15** [Logic — BLOCKING] : GSM=MENU (pas de Pause Overlay instancié) ; `ui_cancel_pressed.emit()` → aucun crash, aucun handler connecté.
- [x] **AC-MNU-16** [Logic — BLOCKING] : GSM=PLAYING ; `ui_cancel_pressed` émis 2× même frame physique → `request_pause()` appelé exactement 1× (1-frame guard côté Menu absorbe — voir Deviations).

---

## Implementation Notes

*Derived from ADR-0004 D-4 + GDD R-MNU-6 :*

1. Dans `PauseMenuControllerScript._ready()` : `InputManager.ui_cancel_pressed.connect(_on_ui_cancel_pressed)` (mode SYNC default — handler léger < 0.5 ms, pas d'instanciation Node, pas d'I/O).
2. Implémenter `_on_ui_cancel_pressed() -> void` :
   ```gdscript
   func _on_ui_cancel_pressed() -> void:
       match GameStateManager.get_current_state():
           GameStateManager.State.PLAYING:
               GameStateManager.request_pause()
           GameStateManager.State.PAUSED:
               GameStateManager.request_resume()
           _:
               # No-op : RESPAWNING / BOSS_DEFEATED / MENU / LOADING — matrice ADR-0007 D-2
               pass
   ```
3. Idempotence (AC-MNU-16) : ne PAS dédupliquer côté Menu — laisser GSM absorber le double appel via son guard `if _state == PAUSED: return` (ADR-0007 D-7). Menu = pull pattern only, GSM = autorité.
4. R-MNU-5 garantit que le signal est émis même si Pause Menu a posé `request_disable(&"PauseMenu")` côté InputManager (ADR-0004 D-4 — `ui_cancel_pressed` exempté du blocking de polling).
5. AC-MNU-15 : en MENU state aucun PauseMenuController n'existe (R-MNU-3 node-local) ; signal émis dans le vide, aucun handler — pas de crash garanti par construction.

---

## Out of Scope

- Story 002 : skeleton scène + `_ready()` non-handler.
- Story 004 : handler `_on_state_changed` + visibility apply (cette story déclenche `request_pause/resume`, la propagation visibility est Story 004).
- Story 005 : `_apply_visibility` méthode.
- Story 008 : refcount + mouse capture (couplé state changes).

---

## QA Test Cases

**AC-MNU-11** : ESC en PLAYING → request_pause
- Given : MockGSM `_state = PLAYING` ; `pause_overlay.tscn` instancié + `PauseMenuController._ready()` complété + connect ui_cancel actif.
- When : `MockInputManager.ui_cancel_pressed.emit()`.
- Then : `assert_eq(MockGSM.request_pause_call_count, 1)` et `assert_eq(MockGSM.request_resume_call_count, 0)`.
- Edge cases : si `PauseMenuController` pas dans tree → aucun handler, no-op (cf. AC-MNU-15).

**AC-MNU-13** : ESC en PAUSED → request_resume + visibility false
- Given : MockGSM `_state = PAUSED` ; Pause Overlay visible.
- When : `ui_cancel_pressed.emit()` ; MockGSM transite vers PLAYING + émet `state_changed(PLAYING)` ; `await get_tree().process_frame`.
- Then : `request_resume_call_count == 1` ET `pause_layer.visible == false`.
- Edge cases : CONNECT_DEFERRED 1-frame skid — vérifier après 1 process_frame.

**AC-MNU-14** : ESC en RESPAWNING → no-op
- Given : MockGSM `_state = RESPAWNING`.
- When : `ui_cancel_pressed.emit()`.
- Then : `request_pause_call_count == 0` ET `request_resume_call_count == 0` ET aucune exception jetée.
- Edge cases : tester aussi `BOSS_DEFEATED` + `MENU` + `LOADING` (mêmes branches no-op `_:`).

**AC-MNU-15** : ESC en MENU sans Pause Overlay
- Given : `main_menu.tscn` chargée, aucun `PauseMenuController` dans tree.
- When : `ui_cancel_pressed.emit()`.
- Then : aucun crash, `watch_signals(mock_gsm)` puis `assert_signal_not_emitted(mock_gsm, "state_changed")`.
- Edge cases : signal émis dans le vide (pas de handler connecté) — comportement Godot natif.

**AC-MNU-16** : double-press idempotence
- Given : MockGSM `_state = PLAYING`.
- When : `ui_cancel_pressed.emit()` 2× consécutivement (même frame physique).
- Then : `request_pause_call_count == 1` (GSM idempotence absorbe le 2e).
- Edge cases : MockGSM doit implémenter le guard idempotent (cf. ADR-0007 D-7).

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/menu/ui_cancel_trigger_test.gd` (5 ACs intégrés, MockGSM + MockInputManager)

**Status**: [x] Created and passing — 1 fichier integration livré. **Test runner executed 2026-05-01 via GdUnit4 safe headless pattern — 6/6 PASSED 188 ms total (`reports/report_108`)**.
- `tests/integration/menu/ui_cancel_trigger_test.gd` — 6 tests AC-MNU-11/13/14 (×2 incl. extension)/15/16.

---

## Dependencies

- Depends on : Story 002 (Pause Overlay skeleton) ; ADR-0004 Accepted (InputManager `ui_cancel_pressed` signal contract) ; ADR-0007 Accepted (verbes `request_pause/resume`).
- Unlocks : Story 004 (state sync — déclenchement par GSM signal `state_changed`), Story 008 (refcount sequencing).

---

## Completion Notes

**Completed** : 2026-05-01
**Criteria** : 5/5 passing (AC-MNU-11/13/14/15/16 — 100% test coverage par 6 tests integration).
**Test Evidence** : Integration — voir Test Evidence section. **6/6 PASSED 188 ms (`reports/report_108`)**.
**Code Review** : Skipped — Solo mode (LP-CODE-REVIEW gate not triggered per `production/review-mode.txt`).
**Files delivered** :
- `src/gameplay/menu/pause_menu_controller.gd` (MODIFIED, +29 L) — `_on_ui_cancel_pressed()` handler match-state ; connect `InputManager.ui_cancel_pressed` au `_ready()` ; **1-frame guard `_ui_cancel_handled_frame`** absorbant double-emit même frame physique (déviation §Deviations).
- `tests/integration/menu/ui_cancel_trigger_test.gd` (NEW, 191 L) — 6 tests GdUnit4 avec save/restore `_current_state` (pattern cohérent `credit_economy_run_purge_test.gd`).
**Deviations (1, ADVISORY documentée)** :
1. **Implementation Notes §3 disait "ne PAS dédupliquer côté Menu — laisser GSM absorber"**. Or AC-MNU-16 demande `request_pause()` 1× sur double-emit même frame. Sans guard côté Menu, la séquence est : emit-1 → handler lit PLAYING → request_pause → state PAUSED ; emit-2 → handler RE-LIT PAUSED (transition synchrone) → request_resume → état final PLAYING (oscillation, viole l'AC). Le guard 1-frame côté Menu (`Engine.get_physics_frames()` snapshot + early return same frame) est le minimum requis pour respecter l'AC sans toucher GSM. **GSM idempotence reste effective pour les cas multi-frame.** Risque résiduel : zéro — en input réel le double-press intra-frame est physiquement quasi impossible (16.6 ms = 1 frame physique vs ~30 ms key-repeat min). Tech debt à amender §Implementation Notes story-003 si re-review post-MVP.
**Unblocks** : story-004 (state sync handler complet), story-008 (refcount sequencing).
