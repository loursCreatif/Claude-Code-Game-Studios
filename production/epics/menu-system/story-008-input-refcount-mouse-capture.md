# Story 008: Refcount InputManager + Mouse Capture Coordination

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-12` (set_mouse_captured), `R-MNU-13` (refcount), `R-MNU-20` (API publique InputManager r2 G-10)

**ADR Governing Implementation**: ADR-0004 Input API + Focus Handling
**ADR Decision Summary**: D-4 — `request_disable(owner: StringName)` / `release_enable_request(owner: StringName)` refcount idempotent. Auto-cleanup via `tree_exited.connect(..., CONNECT_ONE_SHOT)`. `set_mouse_captured(bool)` API publique r2 G-10 (typed signature stable cross-system).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED|VISIBLE)` stable. `tree_exiting` Godot signal natif.

**Control Manifest Rules**:
- Required : Refcount par owner StringName ; auto-cleanup CONNECT_ONE_SHOT.
- Forbidden : `Input.set_mouse_mode` direct depuis Menu (use `InputManager.set_mouse_captured`) — single source of truth ADR-0004 D-7.

---

## Acceptance Criteria

- [ ] **AC-MNU-26** [Integration — BLOCKING] : Pause Overlay caché + zéro blocker `"PauseMenu"` ; `state_changed(PAUSED)` reçu + `_apply_visibility(true)` exécuté → `request_disable(&"PauseMenu")` appelé 1× ; `MockInput.disable_owners.has(&"PauseMenu") == true`.
- [ ] **AC-MNU-27** [Integration — BLOCKING] : Pause Overlay visible + blocker posé ; `state_changed(PLAYING)` reçu + `_apply_visibility(false, true)` → `release_enable_request(&"PauseMenu")` appelé 1× ; `MockInput.disable_owners.has(&"PauseMenu") == false`.
- [ ] **AC-MNU-28** [Integration — BLOCKING] : Pause Overlay visible + blocker posé ; scène détruite via `change_scene_to_file` SANS `_apply_visibility(false)` explicite (crash path) → `tree_exiting` déclenche `release_enable_request(&"PauseMenu")` auto.
- [ ] **AC-MNU-29** [Integration — BLOCKING] : 2 owners actifs `&"PauseMenu"` + `&"CutsceneSystem"` ; `release_enable_request(&"PauseMenu")` seul → InputManager reste disabled (`_enable_blockers.size() == 1`).
- [ ] **AC-MNU-30** [Integration — BLOCKING] : GSM=PLAYING + mouse_mode=CAPTURED ; `state_changed(PAUSED)` → `set_mouse_captured(false)` appelé 1× ; `MockInput.last_captured == false`.
- [ ] **AC-MNU-31** [Integration — BLOCKING] : Pause Overlay visible + mouse libre ; `state_changed(PLAYING)` (Resume) → `set_mouse_captured(true)` appelé 1× ; `MockInput.last_captured == true`.

---

## Implementation Notes

*Derived from ADR-0004 D-4 + GDD R-MNU-12 / R-MNU-13 :*

1. Étendre `_apply_visibility` (signature livrée Story 005) avec coordination Input refcount + mouse :
   ```gdscript
   func _apply_visibility(show: bool, recapture_mouse: bool = true) -> void:
       if not is_inside_tree():
           return
       pause_panel.visible = show
       if show:
           # Ouverture pause
           InputManager.request_disable(&"PauseMenu")  # R-MNU-13
           InputManager.set_mouse_captured(false)       # R-MNU-12 mouse libre menu
           resume_button.grab_focus()                   # K.6 focus initial bouton 1
       else:
           # Fermeture pause
           InputManager.release_enable_request(&"PauseMenu")  # R-MNU-13
           if recapture_mouse:
               InputManager.set_mouse_captured(true)  # R-MNU-12 retour PLAYING
           # else : transition vers MENU/quit_app — mouse reste libre
   ```
2. **Auto-cleanup `tree_exiting`** (AC-MNU-28) : connecter dans `_ready()` :
   ```gdscript
   tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)

   func _on_tree_exiting() -> void:
       # Crash path : si Pause Overlay détruit alors que blocker actif
       if not InputManager.is_blocker_active(&"PauseMenu"):
           return  # déjà release par voie normale
       InputManager.release_enable_request(&"PauseMenu")
   ```
   Note : `InputManager.is_blocker_active(StringName) -> bool` est l'API ADR-0004 D-4 query helper. Si absente côté Input MVP, fallback : appeler release sans guard (idempotent par construction ADR-0004 D-4).
3. **AC-MNU-29 multi-owner** : test refcount valide la propriété ADR-0004 D-4 — un seul release ne réactive pas si un autre owner est actif. Comportement appartient à InputManager, Menu vérifie l'intégration.
4. **Main Menu exempté** (R-MNU-13) : `MainMenuController` ne pose JAMAIS `request_disable` (seul Pause Overlay le fait). Set mouse captured false au `_ready()` Main Menu (Story 001) suffit.
5. R-MNU-12 séquencement : ouverture pause = mouse libre ; fermeture vers PLAYING = mouse capturée ; fermeture vers MENU/quit = mouse libre (cf. table contextuelle Story 005 + Story 007).

---

## Out of Scope

- Story 002 : skeleton + `_ready()` skeleton.
- Story 004 : handler `_on_gsm_state_changed` qui appelle `_apply_visibility`.
- Story 005 : signature de base `_apply_visibility(show, recapture_mouse)` (cette story étend le corps avec input/mouse coordination).
- Story 007 : callbacks boutons (release manuel pré-transition).
- ADR-0004 InputManager APIs `request_disable` / `release_enable_request` / `set_mouse_captured` : owned Input epic, Menu consume only.

---

## QA Test Cases

**AC-MNU-26** : ouverture pause → request_disable
- Given : MockInputManager `_enable_blockers.is_empty() == true` ; Pause Overlay caché.
- When : `_apply_visibility(true)` exécuté.
- Then : `assert_eq(MockInput.disable_call_count, 1)` ET `assert_true(MockInput.disable_owners.has(&"PauseMenu"))`.

**AC-MNU-27** : fermeture pause → release_enable_request
- Given : MockInputManager avec `&"PauseMenu"` blocker actif ; Pause Overlay visible.
- When : `_apply_visibility(false, true)` exécuté.
- Then : `assert_eq(MockInput.release_call_count, 1)` ET `assert_false(MockInput.disable_owners.has(&"PauseMenu"))`.

**AC-MNU-28** : tree_exiting auto-cleanup
- Given : Pause Overlay visible avec blocker `&"PauseMenu"` actif.
- When : `pause_layer.tree_exiting.emit()` manuellement (simule scene change destructif).
- Then : `assert_false(MockInput.disable_owners.has(&"PauseMenu"))` (refcount cleanup automatique).
- Edge cases : si déjà release par voie normale, `tree_exiting` doit être idempotent (no-op via guard).

**AC-MNU-29** : multi-owner ne désactive pas
- Given : MockInputManager avec `&"PauseMenu"` ET `&"CutsceneSystem"` actifs (2 blockers).
- When : `release_enable_request(&"PauseMenu")` appelé seul.
- Then : `assert_eq(MockInput.disable_owners.size(), 1)` ET InputManager reste disabled (`enabled == false`).

**AC-MNU-30** : ouverture pause → mouse libre
- Given : MockInputManager `mouse_mode == MOUSE_MODE_CAPTURED` ; GSM transite PLAYING → PAUSED.
- When : `_apply_visibility(true)`.
- Then : `assert_eq(MockInput.set_mouse_captured_call_count, 1)` ET `assert_eq(MockInput.last_captured, false)`.

**AC-MNU-31** : Resume → mouse capturée
- Given : Pause Overlay visible + mouse libre ; GSM transite PAUSED → PLAYING (Resume).
- When : `_apply_visibility(false, recapture_mouse=true)`.
- Then : `assert_eq(MockInput.last_captured, true)`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/menu/input_refcount_mouse_capture_test.gd` (6 ACs, MockInputManager + MockGSM)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 002 (Pause Overlay skeleton + `tree_exiting` connect placeholder) ; Story 005 (signature `_apply_visibility`) ; ADR-0004 Accepted (`request_disable` / `release_enable_request` / `set_mouse_captured` APIs disponibles InputManager).
- Unlocks : Story 010 (lint anti-pattern `Input.set_mouse_mode` direct), Story 011 (perf bench complète refcount cycle inclus).
