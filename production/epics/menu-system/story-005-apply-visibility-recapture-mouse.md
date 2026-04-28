# Story 005: `_apply_visibility(show, recapture_mouse)` r2 BLK-2 + tree_exiting Lifecycle

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-15` (snap visibility binaire), r2 BLK-2 signature élargie `_apply_visibility(show, recapture_mouse: bool = true)`, r2 BLK-3 guard `is_inside_tree()`

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-4 process_mode discipline — Pause Overlay reçoit input sous tree paused. Lifecycle : `tree_exiting` émis avant `change_scene_to_file` complète, garantit CONNECT_ONE_SHOT cleanup refcount (ADR-0004).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Control.visible = bool` snap immédiat. `tree_exiting` signal stable.

**Control Manifest Rules**:
- Required : Snap visibility binaire (zéro tween, zéro animation — Pillar 1 FLOW Chrome Zen).
- Forbidden : `Tween` / `create_tween` / `tween_property` / `AnimationPlayer` dans menus.

---

## Acceptance Criteria

- [ ] **AC-MNU-7** [Logic — BLOCKING] : `PauseMenuControllerScript._ready()` exécute pull pattern + GSM=PAUSED → `PauseLayer.visible == true` immédiatement (resync via `_apply_visibility(true)`).
- [ ] **AC-MNU-8** [Integration — BLOCKING] : étage actif + `pause_overlay` instancié ; `GSM.request_scene_transition(main_menu_path)` complète → aucun node `PauseLayer` dans `get_tree().get_nodes_in_group("pause_overlay")` (lifecycle propre, no orphan).
- [ ] **AC-MNU-9** [Logic — BLOCKING] : étage avec Pause Overlay actif ; `change_scene_to_file` invoqué → `tree_exiting` émis par `PauseLayer` AVANT que la nouvelle scène ne soit prête.

---

## Implementation Notes

*Derived from R-MNU-15 r2 BLK-2 + GDD §C Lifecycle Pause Overlay :*

1. Implémenter `_apply_visibility(show: bool, recapture_mouse: bool = true) -> void` dans `PauseMenuControllerScript` :
   ```gdscript
   func _apply_visibility(show: bool, recapture_mouse: bool = true) -> void:
       if not is_inside_tree():  # r2 BLK-3 guard race CONNECT_DEFERRED
           return
       pause_panel.visible = show  # snap binaire — zéro tween (R-MNU-15 + AC-MNU-36)
       # Mouse capture + Input refcount = Story 008 (séquencement complet)
       # Cette story livre la signature stable + visibility binaire
   ```
2. **Signature `recapture_mouse: bool = true`** r2 BLK-2 : caller décide selon contexte :
   - Resume (`PLAYING`) : `_apply_visibility(false, true)` — recapture mouse car retour au gameplay
   - Quit to MainMenu (`request_scene_transition`) : `_apply_visibility(false, false)` — pas de recapture, mouse libre en menu
   - Quit App (`get_tree().quit()`) : `_apply_visibility(false, false)` — irrelevant (process exit)
3. **`tree_exiting` cleanup** (AC-MNU-9) : connect dans `_ready()` :
   ```gdscript
   tree_exiting.connect(_on_tree_exiting)
   ```
   `_on_tree_exiting` détaillé Story 008 (release refcount + cleanup mouse capture).
4. **AC-MNU-8 lifecycle propre** : par construction Godot, `change_scene_to_file` détruit la scène courante (avec son Pause Overlay enfant) avant la prochaine `_ready()` de la nouvelle scène. Aucun code Menu requis pour AC-MNU-8 — vérification par test integration que le node disparaît.
5. Group `"pause_overlay"` : ajouter `add_to_group(&"pause_overlay")` dans `_ready()` pour faciliter la query AC-MNU-8.

---

## Out of Scope

- Story 002 : scene skeleton.
- Story 004 : appelants `_on_gsm_state_changed` (cette story livre la méthode appelée).
- Story 008 : implémentation refcount Input + mouse capture séquencement complet.
- Pas de tween / animation / lerp — interdit Chrome Zen Pillar 1 (cf. AC-MNU-36 Story 010).

---

## QA Test Cases

**AC-MNU-7** : pull pattern resync au boot en PAUSED
- Given : MockGSM `_state = PAUSED` ; `pause_overlay.tscn` instancié.
- When : `_ready()` complète + `await process_frame`.
- Then : `assert_true(pause_layer.visible)` (via `_apply_visibility(true)` appelé depuis pull pattern Story 004).
- Edge cases : si guard `is_inside_tree()` retourne false avant set visible → AC fail.

**AC-MNU-8** : pas d'orphan après scene transition
- Given : `etage_01.tscn` chargée, `pause_overlay.tscn` instancié dans le tree, `add_to_group(&"pause_overlay")` posé.
- When : `MockGSM.request_scene_transition("res://scenes/menus/main_menu.tscn")` ; `await get_tree().process_frame` (×2 pour change_scene_to_file).
- Then : `assert_eq(get_tree().get_nodes_in_group("pause_overlay").size(), 0)`.

**AC-MNU-9** : tree_exiting émis avant change_scene
- Given : `etage_01.tscn` + Pause Overlay instancié ; `watch_signals(pause_layer)`.
- When : `get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")`.
- Then : `assert_signal_emitted(pause_layer, "tree_exiting")` avant `_ready()` de la prochaine scène.
- Edge cases : Godot guarantee — `tree_exiting` est émis dès que le node sort du tree.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/menu/apply_visibility_test.gd` (AC-MNU-7 logic snap)
- `tests/integration/menu/pause_overlay_lifecycle_test.gd` (AC-MNU-8/9 lifecycle scene transition)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : Story 002 (skeleton scene + scripts) ; ADR-0007 Accepted (request_scene_transition contract).
- Unlocks : Story 004 (handler appelle cette méthode) ; Story 007 (boutons appellent `_apply_visibility(false, recapture_mouse=...)` selon action) ; Story 008 (refcount Input séquencé sur visibility apply).
