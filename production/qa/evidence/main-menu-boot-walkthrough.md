# Main Menu Boot Walkthrough — story-001 Evidence

> **Story** : production/epics/menu-system/story-001-main-menu-scene-skeleton.md
> **Story Type** : UI
> **Status** : Pending QA execution

## Scénario testé manuellement

1. Lancer le jeu (Godot Editor F5 ou export build).
2. Première frame visible doit être Main Menu (CHROME://ASCENT title + Start Run + Quitter).
3. StartButton est focus par défaut (rectangle de focus visible autour).
4. Souris est libre (curseur visible, pas captured).
5. Aucun crash, aucun warning console autre que les expected.

## Checklist AC

- [ ] AC-MNU-1 — Boot retourne State.MENU (vérifié via test integration `tests/integration/menu/main_menu_boot_test.gd::test_boot_state_is_menu`)
- [ ] AC-MNU-2 — StartButton focus 1× (vérifié via test integration + observation visuelle ci-dessous)
- [ ] AC-MNU-3 — zéro emit state_changed (vérifié via `tests/integration/menu/main_menu_boot_test.gd::test_no_state_changed_emitted_at_boot`)
- [ ] AC-MNU-5 — grep static lint pass (vérifié via `tests/static/menu_main_menu_lint_test.gd::test_no_change_scene_to_file_outside_gsm`)
- [ ] AC-MNU-5b — zéro autoload Menu (vérifié via `tests/static/menu_main_menu_lint_test.gd::test_no_menu_autoload_declared`)

## Screenshot

[À ajouter : screenshot de la scène Main Menu au boot, focus visible sur StartButton]

## Autoload table observée (post-boot)

| # | Name | Path |
|---|------|------|
| 1 | InputManager | res://src/core/input_manager.gd |
| 2 | GameStateManager | res://src/core/game_state_manager.gd |
| 3 | LevelSystem | res://src/gameplay/level/level_system.gd |

Aucun MenuSystem / MainMenuController / PauseMenuController autoload — R-MNU-1 respecté.

## QA Sign-off

- [ ] QA tester : ___________ Date : ___________
- [ ] Lead approval : ___________ Date : ___________
