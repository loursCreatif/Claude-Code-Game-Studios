# Smoke Check — Menu Anti-Patterns Lint (Story 010)

**Date** : 2026-05-02
**Story** : `production/epics/menu-system/story-010-anti-patterns-lint-static.md`
**Type** : Config/Data (smoke check serving as test evidence per coding-standards.md).

## Scope

11 anti-pattern lints couvrant AC-MNU-36/44/45/46/47/48/49/50/57/63/64 + R-MNU-18 anti-deps.

Sources :
- `R-MNU-15` (zero tween) + `R-MNU-16` (zero confirm) + `R-MNU-18` (anti-deps strictes) + `R-MNU-19` (save-on-quit délégation pure) — `design/gdd/menu-system.md`
- ADR-0007 D-4 (GSM seul autorité pause + time_scale + get_tree().paused) — Status: Accepted 2026-04-23
- ADR-0010 R-SAV-9 (Menu ne référence jamais SaveLoad APIs) — Status: Accepted 2026-04-27

## Implementation

- **CI workflow** : `.github/workflows/tests.yml` job `lint-menu-anti-patterns` ajouté.
- **Rule documentation** : `.claude/rules/menu-anti-patterns.md`.
- **Local GdUnit4 parity** : `tests/static/menu_anti_patterns_lint_test.gd` (10 tests static).
- **Exception markers acceptés** : commentaire `# lint-menu-ok: <raison>` sur la ligne concernée (analogue `lint-emit-thread-ok`/`lint-input-thread-ok`/`lint-collision-layers-ok`).

## Local Bash Smoke Check (CI parity)

Exécuté 2026-05-02T11:07:43+02:00 :

```text
=== Menu Anti-Patterns Lint — local smoke check 2026-05-02T11:07:43+02:00 ===
  AC-MNU-36+64 anti-tween PASS
  AC-MNU-44 anti-SFX PASS
  AC-MNU-45 anti-confirm PASS
  AC-MNU-46 corner_radius PASS
  AC-MNU-47 anti-Parallax/Anim PASS
  AC-MNU-48 anti-gradient/material PASS
  AC-MNU-49 Engine.time_scale PASS
  AC-MNU-50 get_tree().paused mutation PASS
  AC-MNU-57 SaveLoad ref PASS
  AC-MNU-63 focus notification PASS
  R-MNU-18 anti-deps PASS

TOTAL_VIOLATIONS=0 — ALL PASS
```

## GdUnit4 Static Test Run

```text
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/menu_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode

Statistics: 10 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED 127ms
Open XML Report at: file:///Users/magnes/Documents/TestClaudeGameStudio/reports/report_122/results.xml
Exit code: 0
```

Tests :
- `test_no_tween_or_animation_in_src_menu` (AC-MNU-36 + AC-MNU-64)
- `test_no_audio_stream_player_in_menu_assets` (AC-MNU-44)
- `test_no_confirm_dialogs_in_menu_assets` (AC-MNU-45)
- `test_corner_radius_values_all_zero_or_absent` (AC-MNU-46)
- `test_no_parallax_or_animation_player_in_menu_scenes` (AC-MNU-47)
- `test_no_gradient_or_material_in_src_menu` (AC-MNU-48)
- `test_no_engine_time_scale_in_src_menu` (AC-MNU-49)
- `test_no_get_tree_paused_mutation_in_src_menu` (AC-MNU-50)
- `test_no_save_load_reference_in_src_menu` (AC-MNU-57)
- `test_no_cross_system_dependency_in_src_menu` (R-MNU-18)

## Suite Menu Régression-Free

```text
Statistics: 68 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED 1s 445ms
reports/report_123
```

Couverture totale menu-system :
- 8 stories greenfield (001-008) : 50 tests intégration + unit
- Story 009 Theme : 8 tests static
- Story 010 anti-patterns : 10 tests static
- Total : **68 tests, 0 régression**.

## Exception Notée

`src/gameplay/menu/main_menu_controller.gd:47` — assert sanity `get_tree().paused == false` (lecture, pas mutation).
Marqué `# lint-menu-ok: read-only sanity assert (story-010 AC-MNU-50 forbids mutation, not lecture)`.
AC-MNU-50 spec ("retourne 0 match") interprété strictement par le grep regex broad ; sémantiquement la règle ADR-0007 D-4 cible la mutation (autorité unique GSM). Lecture pour assertion défensive ne viole pas D-4. Exception documentée pour audit trail.

## Verdict

**PASS** — 11/11 lints CI-parity green ; 10/10 GdUnit4 static green ; suite menu 68/68 régression-free.

Story-010 acceptance criteria satisfaites :
- ✅ AC-MNU-36 (anti-tween)
- ✅ AC-MNU-44 (anti-SFX) — scenes/menus + src/gameplay/menu strict, scenes/levels SKIP gracieux (dir vide MVP)
- ✅ AC-MNU-45 (anti-confirm)
- ✅ AC-MNU-46 (corner_radius zero)
- ✅ AC-MNU-47 (anti-Parallax/Anim)
- ✅ AC-MNU-48 (anti-gradient/material)
- ✅ AC-MNU-49 (Engine.time_scale)
- ✅ AC-MNU-50 (get_tree().paused mutation, 1 exception documentée)
- ✅ AC-MNU-57 (zero SaveLoad)
- ✅ AC-MNU-63 (zero focus notification — déjà couvert par story-004 `menu_anti_focus_handler_lint_test.gd`)
- ✅ AC-MNU-64 (superset anti-tween)
- ✅ Anti-deps R-MNU-18

CI workflow `lint-menu-anti-patterns` actif, gate effectif sur push/PR à main.
