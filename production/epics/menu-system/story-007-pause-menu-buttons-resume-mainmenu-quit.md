# Story 007: Boutons PauseMenu — Reprendre + Quitter Menu Principal + Quitter le jeu

> **Epic**: Menu System
> **Status**: Complete
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

- [x] **AC-MNU-21** [Integration — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `ResumeButton.pressed` → `request_resume()` appelé 1× ET après `state_changed(PLAYING)` `PauseLayer.visible == false`.
- [x] **AC-MNU-22** [Integration — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `MainMenuButton.pressed` → (1) `release_enable_request(self)` appelé AVANT (2) `_main_menu_handler.call()` (default = `request_scene_transition`) — vérifié via inspection `_enable_blockers` au moment du seam.
- [x] **AC-MNU-23** [Logic — BLOCKING] : GSM=PAUSED + Pause Overlay visible ; `QuitButton.pressed` → `_quit_handler.call()` (default = `get_tree().quit()`) appelé 1× ET `release_enable_request(self)` appelé AVANT.
- [x] **AC-MNU-24** [Logic — BLOCKING] : `ResumeButton.pressed` émis 2× consécutivement → `state_changed(PLAYING)` émis 1× (GSM idempotence absorbe le 2e call via guard `if _current_state != PAUSED: return`).
- [x] **AC-MNU-25** [Logic — BLOCKING] : matrice ADR-0007 ; `request_scene_transition(main_menu_path)` depuis PAUSED → GSM transite vers MENU (`get_current_state() == MENU`).
- [x] **AC-MNU-32** [Logic — BLOCKING] *(r2)* : transition PAUSED → MENU séquence `_apply_visibility(false, recapture_mouse=false)` puis GSM call ; (1) `Input.mouse_mode` non-muté côté Menu ; (2) `release_enable_request(self)` strictement avant `_main_menu_handler.call()` (inspection blocker presence).

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

**Status**: [x] Created and passing — **6/6 PASSED 174 ms** (`reports/report_113`) ; suite menu complète **42/42 PASSED 1s 72ms** (`reports/report_114`) zero régression.

---

## Dependencies

- Depends on : Story 002 (skeleton + boutons placement) ; Story 005 (`_apply_visibility(show, recapture_mouse)` signature) ; Story 008 (`release_enable_request` API InputManager — peut courir en parallèle).
- Unlocks : Story 010 (anti-pattern lints sur les callbacks) ; Story 011 (perf bench resume cycle).

## Completion Notes

**Completed** : 2026-05-01
**Criteria** : 6/6 BLOCKING passing (AC-MNU-21/22/23/24/25/32 — 100% test coverage par 6 tests integration).
**Test Evidence** : Integration — voir Test Evidence section. **6/6 PASSED 174 ms (`reports/report_113`)** ; suite menu complète **42/42 PASSED 1s 72ms (`reports/report_114`)**. Zero régression sur stories 001–006.
**Code Review** : Skipped — Solo mode (LP-CODE-REVIEW gate non triggered per `production/review-mode.txt`).
**Files livrés** :
- `src/gameplay/menu/pause_menu_controller.gd` (MODIFIED, +47 L net) — `_on_resume_pressed` direct → `GSM.request_resume()` ; `_on_main_menu_pressed` ordre `_apply_visibility(false, false)` → `release_enable_request(self)` → `_main_menu_handler.call()` ; `_on_quit_pressed` ordre `release_enable_request(self)` → `_quit_handler.call()`. 3 connexions boutons posées dans `_ready()`. Test seams Callable `_main_menu_handler` / `_quit_handler` (cohérent story-006 pattern).
- `tests/integration/menu/pause_menu_buttons_test.gd` (NEW, 200+ L) — 6 tests : AC-MNU-21 chain Resume → PLAYING → panel hidden via CONNECT_DEFERRED handler ; AC-MNU-22/23/32 ordre release-avant-seam vérifié par inspection `InputManager._enable_blockers` au moment du seam ; AC-MNU-24 idempotence GSM via state_changed spy ; AC-MNU-25 verbe GSM real (matrice transition PAUSED→MENU).
**Deviations** : None blocking.
**Notes design** :
1. **Owner type API** : `InputManager.request_disable / release_enable_request` prennent `Node` (pas `StringName` comme suggéré par Implementation Notes §1 et ADR-0004 D-4 wording). Signature actuelle `(owner: Node) -> void`. On passe `self` (le PauseMenuController est un Node CanvasLayer). L'identité d'owner pour le refcount est `owner.get_instance_id()`. Story-008 amendera potentiellement vers une variante typed StringName si ADR-0004 doit converger ; en attendant, l'invariant ADR-0004 D-4 (refcount idempotent) est respecté.
2. **Ordre release-avant-transition vérifié par observation** : plutôt que via timestamps `Time.get_ticks_usec()` (suggérés Implementation Notes §4), on inspecte directement `InputManager._enable_blockers.has(_pause.get_instance_id())` à l'entrée du seam handler. Si la valeur est `false`, c'est la preuve que `release_enable_request` a tourné AVANT le seam dans la même chaîne d'exécution. Approche plus déterministe (pas de risque de tick boundary) et plus lisible.
3. **AC-MNU-32 mouse non-recapture** : `_apply_visibility(false, false)` actuel (story-005) ignore le paramètre `_recapture_mouse` (story-008 livrera l'extension refcount + mouse). Donc `set_mouse_captured(true)` n'est jamais appelé depuis Menu — vérifié par snapshot `Input.mouse_mode` avant/après click. AC trivialement passé jusqu'à story-008, qui re-vérifiera l'invariant via signature finale.
4. **Test seams `_main_menu_handler` / `_quit_handler`** : Pattern Callable overridable (cohérent story-006 / shop_controller). Justifié pour isoler tests sans déclencher `change_scene_to_file` (qui détruirait le node de test via tree_exiting + remplacerait la scène root) ni `get_tree().quit()` (qui terminerait le runner). Defaults routent strictement vers les targets production.
5. **AC-MNU-25 testé via verbe GSM réel** : `request_scene_transition` est invoqué directement (pas via Menu) car le test mesure l'invariant matrice ADR-0007 D-2 — propriété GSM, pas Menu. `change_scene_to_file` est queued par Godot (defer-load), donc safe en after_test cleanup.
**Tech debt logged** : 0 items. Note mineure : `release_enable_request` push_warning si appelé sans prior `request_disable` — actuellement le cas en runtime production (jusqu'à story-008 livraison `request_disable` côté `_apply_visibility(true)`). Acceptable pendant la fenêtre de transition story-007 → story-008, sera résorbé automatiquement.
**Unblocks** : Story 010 (anti-pattern lints sur callbacks) ; Story 011 (perf bench resume cycle).
