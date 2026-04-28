# Story 001: Main Menu Scene Skeleton + Boot Lifecycle

> **Epic**: Menu System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: UI
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 h)
> **Performance**: zéro impact gameplay — Main Menu hors PLAYING (game frozen, GSM=MENU). Theme + StyleBoxFlat one-shot load au boot.

## Context

**GDD**: `design/gdd/menu-system.md`
**Requirement**: `R-MNU-1`, `R-MNU-2`, `R-MNU-8` (no TR-mnu-* registry entry — use R-MNU-N stable IDs jusqu'à `/architecture-review` post-Sprint 1)

**ADR Governing Implementation**: ADR-0007 Game State Manager + Scene Transition
**ADR Decision Summary**: D-5 §a two-path scene container — `main_menu.tscn` est une scène fullscreen Control chargée via `GSM.request_scene_transition` / `change_scene_to_file`. D-9 pull pattern : Menu lit `GSM.get_current_state()` au `_ready()`, jamais lecture directe `State.*`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `change_scene_to_file` API stable Godot 3.x+. `Control.grab_focus()` stable. Aucune API post-cutoff utilisée.

**Control Manifest Rules (Presentation layer)**:
- Required : Naming PascalCase scene root + snake_case file (`main_menu.tscn` ↔ `MainMenuController` root). Typed signals strictly.
- Forbidden : `instance()` (use `instantiate()`), `connect("sig", obj, "method")` (use `signal.connect(callable)`).
- Guardrail : Frame budget 16.6 ms, draw calls < 500.

---

## Acceptance Criteria

*From GDD `design/gdd/menu-system.md`, scoped to this story:*

- [ ] **AC-MNU-1** [Logic — BLOCKING] : projet Godot configuré avec `main_scene = "res://scenes/menus/main_menu.tscn"` ; au boot `MainMenuControllerScript._ready()` exécute et `GameStateManager.get_current_state()` retourne `State.MENU` avant toute interaction.
- [ ] **AC-MNU-2** [Logic — BLOCKING] : `StartButton.grab_focus()` appelé exactement 1× au `_ready()` ; `assert_eq(StartButton.has_focus(), true)` après `await get_tree().process_frame`.
- [ ] **AC-MNU-3** [Logic — BLOCKING] : aucun signal `state_changed` émis depuis Menu au boot — Menu utilise pull pattern uniquement (ADR-0007 D-9).
- [ ] **AC-MNU-5** [Static — ADVISORY] : `grep -c "change_scene_to_file\|additive\|add_child.*main_menu" src/gameplay/**/*.gd` retourne 0 hors GSM (seul GSM charge `main_menu.tscn`).
- [ ] **AC-MNU-5b** [Static — BLOCKING] : `awk '/\[autoload\]/,/^\[/' project.godot | grep -E '^(MenuSystem|MainMenuController|PauseMenuController|Menu)'` retourne 0 match (R-MNU-1 zéro autoload Menu MVP).

---

## Implementation Notes

*Derived from ADR-0007 + GDD Detailed Rules §C Lifecycle Main Menu :*

1. Créer `scenes/menus/main_menu.tscn` — root `Control` fullscreen (anchors 0/0/1/1) avec ColorRect `MENU_BG_BLACK = #050608` plein écran, `VBoxContainer` centré contenant `TitleLabel` ("CHROME://ASCENT" — JetBrains Mono 28 px), `StartButton` ("Start Run"), `QuitButton` ("Quitter le jeu"), `VersionLabel` (11 px, gardé par `DEBUG_SHOW_VERSION = false` const).
2. Créer `src/gameplay/menu/main_menu_controller.gd` — `class_name MainMenuControllerScript extends Control`. `@onready var start_button: Button = $VBoxContainer/StartButton`.
3. Dans `_ready()` : (a) `assert(get_tree().paused == false)` (sanity en MENU), (b) `start_button.grab_focus()`, (c) appeler `InputManager.set_mouse_captured(false)` (R-MNU-12 — mouse libre en menu), (d) connecter `start_button.pressed.connect(_on_start_pressed)` + `quit_button.pressed.connect(_on_quit_pressed)`.
4. Définir `project.godot [application] run/main_scene = "res://scenes/menus/main_menu.tscn"`.
5. Le Menu N'ÉMET PAS `state_changed` au boot — c'est GSM qui possède l'autorité (ADR-0007 D-10 verbe figé). Menu pull only via `GSM.get_current_state()`.
6. Aucun autoload Menu — `MainMenuController` vit uniquement dans la scène.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002 : Pause Overlay scene skeleton.
- Story 006 : implémentation callbacks `_on_start_pressed` / `_on_quit_pressed` (boutons MainMenu).
- Story 009 : Theme + StyleBoxFlat + palette tokens K.4 (cette story livre layout structurel uniquement).
- Story 010 : grep statiques anti-patterns Chrome Zen.

---

## QA Test Cases

**AC-MNU-1** : projet boot retourne State.MENU
- Given : `project.godot` `run/main_scene = "res://scenes/menus/main_menu.tscn"` ; `MockGameStateManager` autoload initialisé `_state = State.MENU`.
- When : Godot boot exécute la scène main_scene par défaut.
- Then : `assert_eq(GameStateManager.get_current_state(), GameStateManager.State.MENU)` après `await get_tree().process_frame`.
- Edge cases : autoload order — InputManager pos-1 + GSM pos-2 doivent exister avant `MainMenuController._ready()`.

**AC-MNU-2** : StartButton focus au boot
- Given : `main_menu.tscn` chargée.
- When : `_ready()` complète + 1 frame.
- Then : `assert_eq(start_button.has_focus(), true)`.
- Edge cases : si `Control.visible == false` au moment du grab_focus → focus silencieusement ignoré ; vérifier visible == true.

**AC-MNU-3** : zéro emit state_changed au boot
- Given : `watch_signals(mock_gsm)` posé avant boot.
- When : `MainMenuController._ready()` complète.
- Then : `assert_signal_not_emitted(mock_gsm, "state_changed")` (ADR-0007 D-9 — Menu pull only).
- Edge cases : si Menu appelle un verbe GSM modifiant l'état au _ready (ex `start_etage`), test fail.

**AC-MNU-5** [Static] : grep change_scene_to_file outside GSM
- Setup : `grep -nE "change_scene_to_file|additive|add_child.*main_menu" src/gameplay/menu/`
- Verify : retour 0 match.
- Pass condition : exit code 1 (grep miss).

**AC-MNU-5b** [Static] : zéro autoload Menu
- Setup : `awk '/\[autoload\]/,/^\[/' project.godot | grep -E '^(MenuSystem|MainMenuController|PauseMenuController|Menu)'`
- Verify : retour 0 match.
- Pass condition : aucune entrée autoload Menu déclarée.

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- AC-MNU-1/2/3 → `tests/integration/menu/main_menu_boot_test.gd` (GUT integration avec MockGSM + MockInputManager)
- AC-MNU-5 + AC-MNU-5b → `tests/static/menu_main_menu_lint_test.gd` OU CI grep job
- Walkthrough doc → `production/qa/evidence/main-menu-boot-walkthrough.md` (screenshot Main Menu + checklist focus + autoload table)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on : ADR-0007 Accepted ; GameStateManager autoload existant (pos-2) ; InputManager autoload existant (pos-1) ; `set_mouse_captured` API r2 G-10 (livré côté InputManager story-XXX upstream).
- Unlocks : Story 002 (pause overlay scene skeleton — peut démarrer en parallèle), Story 006 (boutons MainMenu callbacks).
