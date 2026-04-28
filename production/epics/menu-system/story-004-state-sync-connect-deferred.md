# Story 004: State Sync via `state_changed` (CONNECT_DEFERRED + guard `is_inside_tree()`)

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-4`, `R-MNU-6` (pull pattern), r2 BLK-1 race fenêtre, r2 BLK-3 guard `is_inside_tree()`

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-9 pull pattern — Menu lit `GSM.get_current_state()` au `_ready()`. D-10 5 verbes figés — signal `state_changed(new_state: State)` SYNC consommé via `CONNECT_DEFERRED` côté Menu (race fenêtre `paused=true` propagation asynchrone GSM, r2 BLK-1).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Flag `CONNECT_DEFERRED` stable Godot 3.x+. `Object.is_inside_tree()` stable.

**Control Manifest Rules**:
- Required : Typed signals strictly ; `signal.connect(callable, CONNECT_DEFERRED)` quand instancie Node OU > 0.5 ms CPU OU > 256 B alloc.
- Forbidden : Polling `GSM._state` direct (D-9 viole pull pattern).

---

## Acceptance Criteria

- [ ] **AC-MNU-12** [Integration — BLOCKING] : GSM=PLAYING ; `request_pause()` transite vers PAUSED ; `state_changed(PAUSED)` reçu ; après `await process_frame` (CONNECT_DEFERRED) `PauseLayer.visible == true`.
- [ ] **AC-MNU-33** [Logic — BLOCKING] : Pause Overlay hidden ; `_on_gsm_state_changed(State.PAUSED)` appelé direct → `PauseLayer.visible == true` même frame (sync interne handler).
- [ ] **AC-MNU-34** [Logic — BLOCKING] : Pause Overlay visible ; `_on_gsm_state_changed(State.RESPAWNING)` appelé → `PauseLayer.visible == false` (anti-flicker Pillar 3).
- [ ] **AC-MNU-35** [Logic — BLOCKING] : Pause Overlay vient d'être instancié + GSM=PAUSED ; `_ready()` exécute `_apply_visibility(get_current_state())` (pull pattern) → `PauseLayer.visible == true` après 1 process_frame (ADR-0007 D-9 resync).
- [ ] **AC-MNU-63** [Static — BLOCKING] : `grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/` retourne 0 match (R-MNU-18 anti-dep — InputManager seul handle focus).

---

## Implementation Notes

*Derived from ADR-0007 D-9 + r2 BLK-1 / BLK-3 :*

1. Dans `PauseMenuControllerScript._ready()` :
   ```gdscript
   func _ready() -> void:
       process_mode = Node.PROCESS_MODE_ALWAYS  # R-18 défensif (Story 002)
       pause_panel.visible = false  # snap default
       GameStateManager.state_changed.connect(_on_gsm_state_changed, CONNECT_DEFERRED)
       # Pull pattern boot resync (ADR-0007 D-9 — couvre EC-MNU-31 PRE_READY)
       _on_gsm_state_changed(GameStateManager.get_current_state())
   ```
2. Implémenter `_on_gsm_state_changed(new_state: GameStateManager.State) -> void` :
   ```gdscript
   func _on_gsm_state_changed(new_state: GameStateManager.State) -> void:
       if not is_inside_tree():  # r2 BLK-3 race CONNECT_DEFERRED pendant change_scene_to_file tree_exiting
           return
       match new_state:
           GameStateManager.State.PAUSED:
               _apply_visibility(true)  # Story 005 livre la signature complète
           GameStateManager.State.PLAYING:
               _apply_visibility(false, true)  # recapture mouse
           GameStateManager.State.RESPAWNING, GameStateManager.State.BOSS_DEFEATED, GameStateManager.State.MENU, GameStateManager.State.LOADING:
               _apply_visibility(false, false)  # no recapture (cf. matrice Story 005)
   ```
3. **CONNECT_DEFERRED critique r2 BLK-1** : GSM applique `get_tree().paused = true` SYNC dans son `request_pause()` ; l'émission `state_changed(PAUSED)` est SYNC. Sans `CONNECT_DEFERRED`, le handler Menu peut s'exécuter alors que `get_tree().paused == true` n'est pas encore propagé à tous les nœuds — race fenêtre 1 frame. `CONNECT_DEFERRED` garantit que le handler tourne au prochain idle frame, après propagation tree-wide.
4. **Guard `is_inside_tree()` r2 BLK-3** : pendant `change_scene_to_file` (transition PAUSED → MENU), GSM émet `state_changed(MENU)` SYNC, mais le node est en cours de `tree_exiting`. Sans guard, `_apply_visibility` peut accéder à `pause_panel` orphelin → crash. Le guard return-early prévient ce path.
5. AC-MNU-63 anti-dep : Menu ne pose JAMAIS son propre `_notification(NOTIFICATION_WM_WINDOW_FOCUS_*)` — InputManager (ADR-0004 D-7) est single source of truth pour mouse_mode et focus events.

---

## Out of Scope

- Story 002 : skeleton non-handler.
- Story 003 : trigger ESC (déclenche `request_pause/resume` qui causent `state_changed`).
- Story 005 : implémentation complète `_apply_visibility(show, recapture_mouse)` (cette story appelle la méthode mais Story 005 livre la signature et le mouse capture).
- Story 008 : refcount Input + mouse capture détail.

---

## QA Test Cases

**AC-MNU-12** : state_changed PAUSED via CONNECT_DEFERRED
- Given : MockGSM `_state = PLAYING` ; `pause_overlay` instancié, `_ready()` complète, signal connecté avec CONNECT_DEFERRED.
- When : `MockGSM.request_pause()` puis `await get_tree().process_frame`.
- Then : `assert_true(pause_layer.visible)`.
- Edge cases : sans `await`, le handler deferred n'a pas encore tourné — assertion immédiate fail attendu.

**AC-MNU-33** : sync direct call PAUSED
- Given : Pause Overlay instancié, `pause_layer.visible = false`.
- When : `pause_menu_controller._on_gsm_state_changed(GameStateManager.State.PAUSED)` appelé direct.
- Then : `assert_true(pause_layer.visible)` immédiat (sync interne, pas de await).

**AC-MNU-34** : RESPAWNING → visible false
- Given : Pause Overlay visible.
- When : `_on_gsm_state_changed(GameStateManager.State.RESPAWNING)`.
- Then : `assert_false(pause_layer.visible)` immédiat.
- Edge cases : Pillar 3 anti-flicker — Pause ne survit pas pendant RESPAWNING.

**AC-MNU-35** : pull resync au _ready en PAUSED
- Given : MockGSM `_state = PAUSED` AVANT instanciation Pause Overlay (cas edge : overlay ajouté à scène déjà pausée).
- When : `pause_overlay.tscn` instancié, `_ready()` complète, `await process_frame`.
- Then : `assert_true(pause_layer.visible)`.
- Edge cases : ADR-0007 D-9 resync pull — sans pull au _ready, l'overlay raterait l'état initial.

**AC-MNU-63** [Static] : pas de handler focus côté Menu
- Setup : `grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/`
- Verify : 0 match.
- Pass condition : exit code 1 (grep miss).

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/menu/state_sync_connect_deferred_test.gd` (4 ACs intégrés, MockGSM)
- `tests/static/menu_anti_focus_handler_lint_test.gd` ou CI grep pour AC-MNU-63

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 002 (skeleton + `_ready()` skeleton) ; Story 005 (méthode `_apply_visibility(show, recapture_mouse)` — peut courir en parallèle, signature stable r2 BLK-2).
- Unlocks : Story 008 (refcount Input — déclenchement coordonné aux state changes), Story 011 (perf — vérifie le pipeline complet).
