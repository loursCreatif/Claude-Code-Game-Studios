# Story 006: Boutons MainMenu — Start Run + Quitter le jeu

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-7`, `R-MNU-8`, `R-MNU-17` (idempotence)

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-10 5 verbes figés — `start_etage(etage_id: int)` + `request_scene_transition` + ADR-0010 R-SAV-9 délégation save-on-quit autonome côté SaveLoad. D-5 §b transition MENU → LOADING → PLAYING via signal `level_active` Level System.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `get_tree().quit()` stable. Signal `Button.pressed` stable.

**Control Manifest Rules**:
- Required : Typed signal connect `button.pressed.connect(_on_method)`.
- Forbidden : Confirm dialog (AC-MNU-45) ; SFX (AC-MNU-44) ; SaveLoad direct référence (AC-MNU-57).

---

## Acceptance Criteria

- [ ] **AC-MNU-17** [Integration — BLOCKING] : `main_menu.tscn` active + GSM=MENU ; `StartButton.pressed` émis → `GameStateManager.start_etage(1)` appelé exactement 1× avec arg `1`.
- [ ] **AC-MNU-18** [Integration — BLOCKING] : `start_etage(1)` appelé + GSM orchestre `etage_01.tscn` ; `LevelSystem.level_active` émis + GSM `_transition_to(PLAYING)` → `state_changed(PLAYING)` émis.
- [ ] **AC-MNU-19** [Logic — BLOCKING] : `main_menu.tscn` active ; `QuitButton.pressed` → `get_tree().quit()` appelé exactement 1×.
- [ ] **AC-MNU-20** [Logic — BLOCKING] : `StartButton.pressed` émis 2× consécutivement (double-clic simulé) → `start_etage` appelé 1× (idempotence GSM).

---

## Implementation Notes

*Derived from ADR-0007 D-10 + GDD R-MNU-7 / R-MNU-8 :*

1. Dans `MainMenuControllerScript._ready()` :
   ```gdscript
   start_button.pressed.connect(_on_start_pressed)
   quit_button.pressed.connect(_on_quit_pressed)
   ```
2. Implémenter callbacks :
   ```gdscript
   func _on_start_pressed() -> void:
       GameStateManager.start_etage(1)  # MVP : un seul étage MVP, hardcoded id=1

   func _on_quit_pressed() -> void:
       get_tree().quit()  # save-on-quit délégué intégralement à SaveLoad R-SAV-9 (R-MNU-19)
       # Menu ne référence JAMAIS SaveLoad APIs (AC-MNU-57 enforce grep zero)
   ```
3. AC-MNU-18 = chain integration : Menu déclenche `start_etage(1)` → GSM gère le reste (LOADING → level_active signal → PLAYING). Cette story ne livre PAS le code GSM ; elle vérifie que le déclenchement Menu produit le bon résultat downstream via integration test avec MockLevelSystem qui émet `level_active`.
4. AC-MNU-20 idempotence : pas de guard côté Menu. GSM ADR-0007 D-7 absorbe via `if _state != MENU: return` interne au verbe `start_etage`.
5. R-MNU-8 : "Start Run" toujours fresh — pas de Continue MVP, pas de save state run-in-progress (OQ-MNU-1 résolue).
6. R-MNU-11 : zéro confirm dialog "Êtes-vous sûr ?" — boutons exécutent direct (anti-Pillar 1 friction).

---

## Out of Scope

- Story 001 : skeleton scene + boutons placement.
- Story 009 : Theme/typo/palette tokens K.4.
- Story 010 : grep statiques (AC-MNU-44/45/57 enforce).
- GSM verbe `start_etage` lui-même : owned par GSM epic — Menu consume uniquement.

---

## QA Test Cases

**AC-MNU-17** : Start Run → start_etage(1)
- Given : MockGSM `_state = MENU` ; `main_menu.tscn` chargée.
- When : `start_button.emit_signal("pressed")`.
- Then : `assert_eq(MockGSM.start_etage_call_count, 1)` ET `assert_eq(MockGSM.start_etage_last_arg, 1)`.

**AC-MNU-18** : signal chain start → PLAYING
- Given : MockGSM + MockLevelSystem ; `start_etage(1)` déclenché par Story 006 ; `watch_signals(mock_gsm)`.
- When : MockLevelSystem émet `level_active(1, Vector3.ZERO)` ; `await process_frame` ; MockGSM transite vers PLAYING.
- Then : `assert_signal_emitted_with_parameters(mock_gsm, "state_changed", [GameStateManager.State.PLAYING])`.
- Edge cases : ce test vérifie l'intégration end-to-end — fail si MockGSM ne route pas correctement le verbe.

**AC-MNU-19** : Quit → get_tree().quit()
- Given : `main_menu.tscn` chargée ; MockSceneTree pour intercepter `quit()`.
- When : `quit_button.emit_signal("pressed")`.
- Then : `assert_eq(MockSceneTree.quit_call_count, 1)`.
- Edge cases : `NOTIFICATION_WM_CLOSE_REQUEST` n'est pas testé ici (owned SaveLoad R-SAV-9 — cf. OQ-MNU-1 RESOLVED).

**AC-MNU-20** : double-clic Start Run idempotent
- Given : MockGSM `_state = MENU` (puis transitionnera LOADING au 1er appel).
- When : `start_button.emit_signal("pressed")` 2× consécutivement même frame.
- Then : `assert_eq(MockGSM.start_etage_call_count, 1)` (GSM idempotence absorbe le 2e appel).
- Edge cases : MockGSM doit implémenter le guard `if _state != MENU: push_warning(...); return`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/menu/main_menu_buttons_test.gd` (4 ACs, MockGSM + MockLevelSystem + MockSceneTree)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 001 (Main Menu skeleton + boutons placement) ; ADR-0007 Accepted (verbe `start_etage` + matrice transitions).
- Unlocks : (none direct — peut courir en parallèle des stories 002-008).
