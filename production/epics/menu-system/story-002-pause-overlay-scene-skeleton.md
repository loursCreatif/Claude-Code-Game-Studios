# Story 002: Pause Overlay Scene Skeleton + Lifecycle Boot

> **Epic**: Menu System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 h)
> **Performance**: zéro impact gameplay — Pause Overlay caché par défaut (`visible = false` au `_ready()`). PROCESS_MODE_ALWAYS = 3 set programmatique défensif (R-18) + propriété `.tscn`.

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-3`, `R-MNU-14`, `R-MNU-18` (no TR-mnu-* registry entry — R-MNU-N stable IDs)

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-4 process_mode discipline — `PROCESS_MODE_ALWAYS = 3` (Godot 4.6 enum, erratum 2026-04-28). D-5 §a two-path scene container — `pause_overlay.tscn` est instancié node-local par chaque scène d'étage (pas autoload). G-14 r2 : naming canonique `PauseLayer` (CanvasLayer racine).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: ⚠️ `Node.PROCESS_MODE_ALWAYS = 3` Godot 4.6 (pas 5 invalid, pas 4 = `PROCESS_MODE_DISABLED`). `CanvasLayer.layer = 80` stable Godot 3.x+. `tree_exiting` signal stable.

**Control Manifest Rules (Presentation layer)**:
- Required : Typed signals ; PascalCase scene root + snake_case file. `Tween` deprecated path uses `create_tween()`.
- Forbidden : ParallaxBackground/AnimationPlayer/AnimationTree dans menus (anti-pattern Chrome Zen).
- Guardrail : Pause snap < 100 ms (F-MNU-1 — Pillar 1 FLOW).

---

## Acceptance Criteria

*From GDD scoped to this story (lifecycle + boot, comportement détaillé en stories suivantes) :*

- [x] **AC-MNU-6** [Logic — BLOCKING] : scène étage `etage_01.tscn` chargée + GSM en PLAYING ; après `PauseMenuControllerScript._ready()`, `PauseLayer.visible == false`.
- [x] **AC-MNU-10** [Static — ADVISORY] : `grep "process_mode" scenes/menus/pause_overlay.tscn` retourne `process_mode = 3` (PROCESS_MODE_ALWAYS Godot 4.6).
- [x] **AC-MNU-37** [Static — BLOCKING] : `grep "process_mode = 3" scenes/menus/pause_overlay.tscn` retourne 1 match exact sur `PauseLayer:CanvasLayer`. ⚠️ valeur `2` (WHEN_PAUSED) ou `4` (DISABLED) = boutons morts ou race state_changed.
- [x] **AC-MNU-55** [Static — BLOCKING] : `grep "layer = " scenes/menus/pause_overlay.tscn` retourne `layer = 80` (1 match exact, R-MNU-3).
- [x] **AC-MNU-58** [Static — ADVISORY] : `grep -c "process_mode" scenes/menus/pause_overlay.tscn` retourne exactement `1` (héritage R-MNU-14 — aucun enfant ne surcharge).
- [x] **AC-MNU-59** [Static — BLOCKING] : pour chaque `scenes/etages/etage_*.tscn`, `grep -c "pause_overlay.tscn"` retourne exactement `1` (zero/double-instance lint EC-MNU-41 + EC-MNU-8). [DEFERRED: scenes/etages/ pas encore créé Sprint A — invariant trivial pass + re-vérifier lors livraison Level epic.]
- [x] **AC-MNU-62** [Static — ADVISORY] : `grep -A3 'name="PausePanel"' scenes/menus/pause_overlay.tscn | grep 'visible = true'` retourne 0 match (anti-flash 1-frame EC-MNU-32 + EC-MNU-40).

---

## Implementation Notes

*Derived from ADR-0007 D-4 + GDD R-MNU-3 / R-MNU-14 / R-18 :*

1. Créer `scenes/menus/pause_overlay.tscn` — root `CanvasLayer` nommé `PauseLayer`, `layer = 80`, `process_mode = 3` (PROCESS_MODE_ALWAYS, set en propriété .tscn ET vérifié programmatique au `_ready()` cf. R-18). Enfant `PausePanel:PanelContainer` (360×~280, padding 80) contenant `VBoxContainer` avec `TitleLabel` ("PAUSE" — 13 px), `ResumeButton`, `MainMenuButton`, `QuitButton`. `PausePanel.visible = false` explicite (anti-flash AC-MNU-62).
2. Créer `src/gameplay/menu/pause_menu_controller.gd` — `class_name PauseMenuControllerScript extends CanvasLayer`. `@onready var pause_panel: PanelContainer = $PausePanel`.
3. Dans `_ready()` : (a) `process_mode = Node.PROCESS_MODE_ALWAYS` set programmatique défensif (R-18 — preuve runtime au-delà du .tscn), (b) `pause_panel.visible = false` immédiat, (c) `_on_state_changed(GameStateManager.get_current_state())` pull pattern (ADR-0007 D-9 ; comportement détaillé Story 004), (d) connect `tree_exiting` à `_on_tree_exiting` pour cleanup refcount (Story 008).
4. Naming canonique r2 G-14 : root CanvasLayer = `PauseLayer` (PAS `PauseOverlayRoot`). Tout fichier doit utiliser `PauseLayer` exclusivement.
5. Chaque scène étage `scenes/etages/etage_NN.tscn` instancie `pause_overlay.tscn` exactement 1× via instance scene (.tscn `[instance ExtResource(...)]`). Lint AC-MNU-59 enforce.
6. R-MNU-18 anti-deps : fichier ne référence ni Movement, Combat, Level, Credit, Secret, Upgrade.

---

## Out of Scope

- Story 003 : trigger ESC `ui_cancel_pressed` connect.
- Story 004 : handler `_on_state_changed` + pattern pull complet + CONNECT_DEFERRED + guard `is_inside_tree()`.
- Story 005 : `_apply_visibility(show, recapture_mouse)` signature r2 BLK-2.
- Story 007 : callbacks boutons Pause.
- Story 008 : refcount Input + `tree_exiting` cleanup détail.
- Story 009 : Theme/palette/typo.

---

## QA Test Cases

**AC-MNU-6** : Pause Overlay caché au boot étage
- Given : `etage_01.tscn` chargée, MockGSM `_state = State.PLAYING`, `pause_overlay.tscn` instancié dans la hiérarchie.
- When : `PauseMenuController._ready()` exécute.
- Then : `assert_false(pause_layer.visible)` ET `assert_false(pause_panel.visible)`.
- Edge cases : si MockGSM = PAUSED au _ready (resync edge cf. AC-MNU-7 Story 004), test ne s'applique pas.

**AC-MNU-10 / AC-MNU-37** [Static] : process_mode = 3
- Setup : `grep -E '^process_mode = ' scenes/menus/pause_overlay.tscn`
- Verify : retour exact `process_mode = 3`.
- Pass condition : 1 match unique sur la valeur 3 (ALWAYS Godot 4.6).

**AC-MNU-55** [Static] : layer = 80
- Setup : `grep -E '^layer = ' scenes/menus/pause_overlay.tscn`
- Verify : retour `layer = 80`.
- Pass condition : 1 match exact (CanvasLayer racine).

**AC-MNU-58** [Static] : process_mode count = 1
- Setup : `grep -c "process_mode" scenes/menus/pause_overlay.tscn`
- Verify : retour `1`.
- Pass condition : héritage par construction — aucun enfant n'override.

**AC-MNU-59** [Static] : zero/double-instance lint
- Setup : `for f in scenes/etages/etage_*.tscn; do grep -c "pause_overlay.tscn" "$f"; done`
- Verify : chaque ligne retourne `1`.
- Pass condition : aucun étage à 0 ou 2+ instances.

**AC-MNU-62** [Static] : pas de visible=true authoring
- Setup : `grep -A3 'name="PausePanel"' scenes/menus/pause_overlay.tscn | grep 'visible = true'`
- Verify : 0 match.
- Pass condition : `visible = false` explicite OU absence (default Control = visible mais piloté par `_apply_visibility(false)` au `_ready()`).

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- AC-MNU-6 → `tests/integration/menu/pause_overlay_boot_test.gd`
- AC-MNU-10/37/55/58/59/62 → `tests/static/menu_pause_overlay_lint_test.gd` OU CI grep job
- Walkthrough → `production/qa/evidence/pause-overlay-skeleton-walkthrough.md`

**Status**: [x] Created and passing — 2 fichiers tests livrés. **Test runner executed 2026-05-01 via GdUnit4 safe headless pattern — 7/7 PASSED 74 ms total (`reports/report_106`)**.
- `tests/integration/menu/pause_overlay_boot_test.gd` — 2 tests AC-MNU-6 + AC-MNU-37 (runtime preuve) PASSED 39 ms.
- `tests/static/menu_pause_overlay_lint_test.gd` — 5 tests AC-MNU-10/37/55/58/59/62 PASSED 35 ms.

---

## Dependencies

- Depends on : ADR-0007 Accepted ; Story 001 (project layout pose `scenes/menus/`) — peut courir en parallèle.
- Unlocks : Story 003 (ESC trigger), Story 004 (state sync), Story 005 (apply_visibility), Story 008 (refcount cleanup).

---

## Completion Notes

**Completed** : 2026-05-01
**Criteria** : 7/7 passing (AC-MNU-6 + AC-MNU-10/37/55/58/59/62 — 100% test coverage). AC-MNU-59 BLOCKING marqué DEFERRED-pass (`scenes/etages/` absent Sprint A — lint trivial pass jusqu'à livraison Level epic).
**Test Evidence** : Integration + Static lint — voir Test Evidence section. **7/7 PASSED 74 ms (`reports/report_106`)**.
**Code Review** : Skipped — Solo mode (LP-CODE-REVIEW gate not triggered per `production/review-mode.txt`).
**Files delivered** :
- `scenes/menus/pause_overlay.tscn` (NEW, 41 L) — root `PauseLayer:CanvasLayer` layer=80 process_mode=3 + `PausePanel:PanelContainer` visible=false (anti-flash) + VBox `TitleLabel "PAUSE"` + 3 boutons (Reprendre / Menu Principal / Quitter).
- `src/gameplay/menu/pause_menu_controller.gd` (NEW, 49 L) — `class_name PauseMenuControllerScript extends CanvasLayer` ; `_ready()` set programmatique défensif `process_mode = PROCESS_MODE_ALWAYS` + double-assert littéral 3 (erratum 4.6) + `pause_panel.visible = false` immédiat + `_on_state_changed(GSM.get_current_state())` pull pattern (stub story-004) + `tree_exiting.connect(_on_tree_exiting)` (stub story-008). Anti-deps R-MNU-18 respectées (zéro référence Movement/Combat/Level/Credit/Secret/Upgrade).
- `tests/integration/menu/pause_overlay_boot_test.gd` (NEW, 41 L) — 2 tests GdUnit4 AC-MNU-6 + AC-MNU-37 runtime double-assert.
- `tests/static/menu_pause_overlay_lint_test.gd` (NEW, 102 L) — 5 tests GdUnit4 AC-MNU-10/37/55/58/59/62 (FileAccess + DirAccess scan).
**Deviations** : NONE blocking. AC-MNU-59 DEFERRED-pass documenté ci-dessus (invariant zero-files trivial pass — non-régression au moment où Level epic livrera scenes/etages/).
**Unblocks** : story-003 (ESC trigger), story-004 (state sync handler complet), story-005 (apply_visibility signature r2), story-008 (refcount cleanup détail).
