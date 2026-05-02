# Story 008: Refcount InputManager + Mouse Capture Coordination

> **Epic**: Menu System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: M (3-4 h)
> **Performance**: Pillar 1 critique — mouse capture timing influence pause/resume snap. `request_disable/release_enable_request` refcount idempotent (ADR-0004 D-4 zéro alloc). `tree_exiting` CONNECT_ONE_SHOT cleanup auto.

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

- [x] **AC-MNU-26** [Integration — BLOCKING] : Pause Overlay caché + zéro blocker pour `self` ; `_apply_visibility(true, false)` exécuté → `request_disable(self)` appelé 1× ; `_enable_blockers.has(self.get_instance_id()) == true`.
- [x] **AC-MNU-27** [Integration — BLOCKING] : Pause Overlay visible + blocker posé ; `_apply_visibility(false, true)` → `release_enable_request(self)` (via guard `_enable_blockers.has(id)`) ; blocker retiré ; `InputManager.enabled == true`.
- [x] **AC-MNU-28** [Integration — BLOCKING] : Pause Overlay visible + blocker posé ; `tree_exiting.emit()` manuel (simule scene change destructif) → handler `_on_tree_exiting` libère le blocker. Edge : idempotent si déjà release.
- [x] **AC-MNU-29** [Integration — BLOCKING] : 2 owners actifs (Pause + autre Node) ; `release_enable_request(_pause)` seul → InputManager reste `enabled == false` (autre owner toujours dans `_enable_blockers`).
- [x] **AC-MNU-30** [Integration — BLOCKING] : `_apply_visibility(true, false)` → `set_mouse_captured(false)` appelé 1× via test seam `_set_mouse_captured_handler` (headless rejette `Input.mouse_mode` direct).
- [x] **AC-MNU-31** [Integration — BLOCKING] : `_apply_visibility(false, true)` → `set_mouse_captured(true)` appelé 1× ; corollaire `(false, false)` → set_mouse_captured PAS appelé.

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

**Status**: [x] Created and passing — **8/8 PASSED 223 ms** (`reports/report_117`) ; suite menu complète **50/50 PASSED 1s 305ms** (`reports/report_118`) zero régression.

---

## Dependencies

- Depends on : Story 002 (Pause Overlay skeleton + `tree_exiting` connect placeholder) ; Story 005 (signature `_apply_visibility`) ; ADR-0004 Accepted (`request_disable` / `release_enable_request` / `set_mouse_captured` APIs disponibles InputManager).
- Unlocks : Story 010 (lint anti-pattern `Input.set_mouse_mode` direct), Story 011 (perf bench complète refcount cycle inclus).

## Completion Notes

**Completed** : 2026-05-01
**Criteria** : 6/6 BLOCKING passing (AC-MNU-26/27/28/29/30/31 — 100% test coverage par 8 tests integration ; +2 tests edge cases : AC-MNU-28 ext idempotence + AC-MNU-31 ext no-recapture).
**Test Evidence** : Integration — voir Test Evidence section. **8/8 PASSED 223 ms (`reports/report_117`)** ; suite menu complète **50/50 PASSED 1s 305ms (`reports/report_118`)**. Zero régression sur stories 001-007.
**Code Review** : Skipped — Solo mode (LP-CODE-REVIEW gate non triggered per `production/review-mode.txt`).
**Files livrés** :
- `src/gameplay/menu/pause_menu_controller.gd` (MODIFIED, +25 L net) — `_apply_visibility` étendu : show=true → `request_disable(self)` + `_set_mouse_captured_handler.call(false)` + `resume_button.grab_focus()` ; show=false → guard `_enable_blockers.has(id)` puis `release_enable_request(self)` + `_set_mouse_captured_handler.call(true)` si recapture_mouse. `_on_tree_exiting` auto-cleanup avec guard idempotence. Test seam Callable `_set_mouse_captured_handler` ajouté pour observabilité headless.
- `src/gameplay/menu/pause_menu_controller.gd` (story-007 callbacks adaptés) — `_on_main_menu_pressed` et `_on_quit_pressed` retirent le `release_enable_request(self)` explicite (maintenant délégué à `_apply_visibility(false, false)` interne — pas de double release / push_warning).
- `tests/integration/menu/input_refcount_mouse_capture_test.gd` (NEW 200 L) — 8 tests integration directs sur InputManager (pas de mock) : `_enable_blockers` dict + `enabled` getter + Input.mouse_mode via test seam.
**Deviations** : None blocking. **3 notes design** :
1. **Owner type API** (cohérent story-007) : `request_disable / release_enable_request(owner: Node)` pas StringName. On passe `self`. Le test AC-MNU-29 multi-owner utilise un autre `Node` quelconque pour vérifier l'invariant refcount.
2. **Test seam `_set_mouse_captured_handler`** : Godot `--headless` rejette silencieusement `Input.mouse_mode = MOUSE_MODE_CAPTURED` (rester `0=VISIBLE`). Donc lecture-arrière `Input.mouse_mode` ne valide pas le comportement de production. Test seam Callable wrap les appels `set_mouse_captured` pour permettre aux tests d'observer via spy. Default route strictement vers `InputManager.set_mouse_captured`. Cohérent pattern `_main_menu_handler` / `_quit_handler` story-007. Coût production : 1 niveau d'indirection Callable, négligeable hors hot path (Pillar 1 sauf).
3. **`is_blocker_active` API helper non implémentée** (Implementation Notes §2 mentionnait l'option) : On accède directement `InputManager._enable_blockers.has(get_instance_id())` (private dict accessible en GDScript). Acceptable pour un consumer interne au monorepo. Si ADR-0004 ajoute `is_blocker_active(Node) -> bool` API publique en story-009+, le call site sera trivialement adapté.
**Note story-007 follow-up** : Les callbacks Pause Menu `_on_main_menu_pressed` et `_on_quit_pressed` ont été simplifiés — le `release_enable_request(self)` explicite est retiré car `_apply_visibility(false, false)` interne le fait maintenant. Tests story-007 (6 tests) re-passent : invariant "blocker absent au seam" toujours vrai (release est juste exécuté plus tôt dans la chaîne, à l'intérieur de `_apply_visibility`).
**Tech debt logged** : 0 items.
**Unblocks** : Story 010 (lint anti-pattern `Input.set_mouse_mode` direct depuis menu — cover-all) ; Story 011 (perf bench complète refcount cycle inclus).
