# Story 007: Boutons PauseMenu — Reprendre + Quitter Menu Principal + Quitter le jeu

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 h)
> **Performance**: zéro impact — callbacks one-shot. Ordre release-avant-transition r2 vérifié via timestamp `Time.get_ticks_usec()` (assertion test, pas runtime overhead).

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-9`, `R-MNU-10` (release-avant-GSM), `R-MNU-11`, `R-MNU-17` (idempotence)

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-10 verbe `request_resume()` + `request_scene_transition(path)`. ADR-0004 D-4 refcount InputManager — `release_enable_request(&"PauseMenu")` doit être appelé STRICTEMENT AVANT `request_scene_transition` (ordre critique r2 — `release_called_before_transition` timestamp).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Time.get_ticks_usec()` stable pour timestamp ordering test. `get_tree().quit()` stable.

**Control Manifest Rules**:
- Required : Refcount discipline `release_enable_request` avant transition vers MENU.
- Forbidden : Confirm dialog (R-MNU-16) ; SFX (R-MNU-MVP zero audio).

---

## Acceptance Criteria

- [ ] **AC-MNU-21** [Integration — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `ResumeButton.pressed` → `request_resume()` appelé 1× ET après `state_changed(PLAYING)` `PauseLayer.visible == false`.
- [ ] **AC-MNU-22** [Integration — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `MainMenuButton.pressed` → (1) `release_enable_request(&"PauseMenu")` appelé AVANT (2) `request_scene_transition("res://scenes/menus/main_menu.tscn")` appelé 1× — vérifié via timestamp `release_called_before_transition`.
- [ ] **AC-MNU-23** [Logic — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `QuitButton.pressed` → `get_tree().quit()` appelé 1× ET `release_enable_request(&"PauseMenu")` appelé AVANT quit.
- [ ] **AC-MNU-24** [Logic — BLOCKING] : `ResumeButton.pressed` émis 2× consécutivement → `request_resume()` appelé 1× (idempotence GSM).
- [ ] **AC-MNU-25** [Logic — BLOCKING] : matrice ADR-0007 ; `request_scene_transition(main_menu_path)` depuis PAUSED → GSM transite vers MENU (`get_current_state() == MENU`).
- [ ] **AC-MNU-32** [Logic — BLOCKING] *(r2)* : transition PAUSED → MENU séquence `_apply_visibility(false, recapture_mouse=false)` puis GSM call ; (1) `set_mouse_captured(true)` PAS appelé ; (2) `release_enable_request(&"PauseMenu")` strictement avant `request_scene_transition` (timestamp comparison).

---

## Implementation Notes

*Derived from ADR-0007 D-10 + ADR-0004 D-4 + GDD R-MNU-10 / R-MNU-11 :*

1. Dans `PauseMenuControllerScript._ready()` :
   ```gdscript
   resume_button.pressed.connect(_on_resume_pressed)
   main_menu_button.pressed.connect(_on_main_menu_pressed)
   quit_button.pressed.connect(_on_quit_pressed)
   ```
2. Implémenter callbacks (ordre release-avant-GSM critique) :
   ```gdscript
   func _on_resume_pressed() -> void:
       GameStateManager.request_resume()
       # state_changed(PLAYING) déclenchera _apply_visibility(false, true) via Story 004 handler

   func _on_main_menu_pressed() -> void:
       _apply_visibility(false, false)  # hide overlay sans recapture mouse
       InputManager.release_enable_request(&"PauseMenu")  # ORDRE CRITIQUE r2
       GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")

   func _on_quit_pressed() -> void:
       InputManager.release_enable_request(&"PauseMenu")  # cleanup avant quit
       get_tree().quit()
       # save-on-quit délégué SaveLoad R-SAV-9 (R-MNU-19) — Menu ne référence pas SaveLoad
   ```
3. **Ordre release-avant-transition r2 (AC-MNU-22 + AC-MNU-32)** : si `request_scene_transition` est appelé d'abord, le `tree_exiting` du Pause Overlay (CONNECT_ONE_SHOT auto-cleanup ADR-0004) déclencherait le release au moment de la destruction — race fenêtre où InputManager pourrait être lu pendant transition avec un blocker fantôme. Release explicite avant la transition garantit l'ordre déterministe.
4. **AC-MNU-32 timestamp test** : MockInputManager + MockGSM enregistrent `last_call_timestamp_usec` via `Time.get_ticks_usec()` à chaque invocation. Assertion : `mock_input.release_timestamp_usec < mock_gsm.transition_timestamp_usec`.
5. **AC-MNU-32 `set_mouse_captured(true)` PAS appelé** : transition vers MENU = mouse libre ; `_apply_visibility(false, recapture_mouse=false)` (Story 005 signature) honore ce contrat.

---

## Out of Scope

- Story 002 : skeleton scène + boutons placement.
- Story 004 : handler `_on_gsm_state_changed` qui réagit au state PLAYING (Resume) ou MENU (Main Menu).
- Story 005 : implémentation `_apply_visibility(show, recapture_mouse)`.
- Story 008 : `request_disable(&"PauseMenu")` côté ouverture (cette story livre le release côté fermeture).

---

## QA Test Cases

**AC-MNU-21** : Resume → request_resume + visibility false
- Given : MockGSM `_state = PAUSED`, Pause Overlay visible.
- When : `resume_button.emit_signal("pressed")` ; MockGSM transite PLAYING + émet `state_changed(PLAYING)` ; `await process_frame`.
- Then : `assert_eq(MockGSM.request_resume_call_count, 1)` ET `assert_false(pause_layer.visible)`.

**AC-MNU-22** : MainMenu → release-before-transition
- Given : MockGSM `_state = PAUSED`, Pause Overlay visible, MockInputManager + MockGSM avec timestamps usec.
- When : `main_menu_button.emit_signal("pressed")`.
- Then : `assert_eq(MockInput.release_call_count, 1)` ET `assert_true(MockInput.release_timestamp_usec < MockGSM.transition_timestamp_usec)`.

**AC-MNU-23** : Quit → quit + release before
- Given : MockGSM `_state = PAUSED`, Pause Overlay visible.
- When : `quit_button.emit_signal("pressed")`.
- Then : `assert_eq(MockSceneTree.quit_call_count, 1)` ET `assert_true(MockInput.release_called_before_quit)`.

**AC-MNU-24** : double-clic Resume idempotent
- Given : MockGSM `_state = PAUSED`.
- When : `resume_button.emit_signal("pressed")` 2× même frame.
- Then : `assert_eq(MockGSM.request_resume_call_count, 1)`.

**AC-MNU-25** : transition PAUSED → MENU
- Given : MockGSM `_state = PAUSED`.
- When : `request_scene_transition(main_menu_path)` complète.
- Then : `assert_eq(MockGSM.get_current_state(), GameStateManager.State.MENU)`.

**AC-MNU-32** : ordre release strict + no recapture
- Given : Pause Overlay visible, MockInputManager + MockGSM timestamps actifs.
- When : `_apply_visibility(false, recapture_mouse=false)` puis `release_enable_request` puis `request_scene_transition`.
- Then : `assert_eq(MockInput.captured_true_call_count, 0)` ET `assert_true(MockInput.release_timestamp_usec < MockGSM.transition_timestamp_usec)`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/menu/pause_menu_buttons_test.gd` (6 ACs, MockGSM + MockInputManager avec timestamps + MockSceneTree)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 002 (skeleton + boutons placement) ; Story 005 (`_apply_visibility(show, recapture_mouse)` signature) ; Story 008 (`release_enable_request` API InputManager — peut courir en parallèle).
- Unlocks : Story 010 (anti-pattern lints sur les callbacks) ; Story 011 (perf bench resume cycle).
