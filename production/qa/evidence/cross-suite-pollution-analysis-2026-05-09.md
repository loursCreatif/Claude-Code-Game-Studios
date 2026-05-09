# Cross-Suite Pollution Analysis — 2026-05-09

**Trigger** : Story W-4 tech-debt investigation — `production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md`
**Engine** : Godot 4.6.2 + GdUnit4 v5
**Branch** : `chore/story-014-tech-debt-cleanup`

## TL;DR

Le verdict du smoke 2026-05-05 (« autoload reuse pollution dominante ») est **obsolete**.
Mesure 2026-05-09 sur 1117 tests / 69 failures, 36 suites failing :

| Catégorie | Suites | % |
|---|---|---|
| **Régression intrinsèque** (fail iso ≥ fail sweep) | **32 / 36** | **89 %** |
| **Vraie pollution cross-suite** (fail sweep > fail iso) | **4 / 36** | **11 %** |

→ La majorité des failures **ne sont pas dues à de la pollution autoload**. Ce sont des bugs/régressions que `/team-qa` n'a jamais re-vérifié post-sprint Combat/Movement/Camera.

## Méthode

1. Run sweep complet : `--add tests/unit --add tests/integration` → 1117/69 fails / exit 100.
2. Pour chacune des 36 suites listées « failures > 0 » dans `reports/report_509/results.xml`,
   relance isolée : `--add <single-suite.gd>` → comptage fails iso.
3. Diff `sweep_fails - iso_fails` :
   - Diff = 0 → régression intrinsèque (la suite échoue pareil seule)
   - Diff > 0 → pollution réelle (suite passe seule, échoue avec voisins)
   - Diff < 0 → la sweep MASQUE des fails (autre pollution inverse)

## Matrice complète

| Suite | Sweep | Iso | Diff | Catégorie |
|---|---:|---:|---:|---|
| story_001_scene_skeleton_project_settings_test | 8 | 8 | 0 | régression |
| level_reload_reset_test | 6 | 6 | 0 | régression |
| level_unload_test | 5 | 5 | 0 | régression |
| level_etage_exit_test | 4 | 4 | 0 | régression |
| level_room_entered_test | 4 | 4 | 0 | régression |
| level_player_out_of_world_test | 3 | 3 | 0 | régression |
| mouse_capture_test | 2 | 2 | 0 | régression |
| level_frame_time_test | 2 | 2 | 0 | régression |
| focus_handling_test | 2 | 2 | 0 | régression |
| polling_same_tick_test | 2 | 2 | 0 | régression |
| level_load_failures_test | 2 | 2 | 0 | régression |
| visual_authoring_lint_test | 1 | 1 | 0 | régression |
| wall_run_door_lint_test | 1 | 1 | 0 | régression |
| secret_lures_lint_test | 1 | 1 | 0 | régression |
| level_formulas_lint_test | 1 | 1 | 0 | régression |
| onboarding_anchors_lint_test | 1 | 1 | 0 | régression |
| latency_ring_buffer_test | 1 | 1 | 0 | régression |
| was_pressed_this_tick_test | 1 | 1 | 0 | régression |
| story_002_yaw_pitch_raw_apply_test | 1 | 1 | 0 | régression |
| story_003_enabled_mouse_capture_gates_test | 1 | 1 | 0 | régression |
| gravity_airborne_test | 1 | 1 | 0 | régression |
| grounded_horizontal_test | 1 | 1 | 0 | régression |
| wall_jump_test | 1 | 1 | 0 | régression |
| level_state_machine_test | 1 | 1 | 0 | régression |
| level_signals_contract_test | 1 | 1 | 0 | régression |
| enable_refcount_test | 1 | 1 | 0 | régression |
| signal_order_exit_test | 1 | 1 | 0 | régression |
| cross_system_mocks_test | 1 | 1 | 0 | régression |
| level_onboarding_raycast_test | 1 | 1 | 0 | régression |
| level_load_etage_test | 1 | 1 | 0 | régression |
| jump_coyote_test | 1 | 2 | **−1** | régression (sweep masque) |
| wall_run_detection_test | 1 | 3 | **−2** | régression (sweep masque) |
| **main_menu_boot_test** | **1** | **0** | **+1** | **VRAIE POLLUTION** |
| **no_alloc_play_2d_test** | **1** | **0** | **+1** | **VRAIE POLLUTION** |
| **story_009_respawn_fade_flash_test** | **1** | **0** | **+1** | **VRAIE POLLUTION** |
| **test_movement_signals_typed_contract** | **1** | **0** | **+1** | **VRAIE POLLUTION** |

**Total Diff > 0** = 4 fails sur 1117 tests = **0.36 % du volume total**.

## Régressions intrinsèques par epic

Décomposition des 32 régression suites :

| Epic | Suites | Fails total | Note |
|---|---:|---:|---|
| Level (`level_*_test`) | 13 | 30 | level_reload_reset 6 + level_unload 5 + level_etage_exit 4 + level_room_entered 4 + level_player_out_of_world 3 + autres 8 |
| Camera (`story_001-003_*`) | 3 | 10 | story_001 scene_skeleton 8 + story_002 + story_003 |
| Movement (`*jump*` / `*wall_run*` / `*gravity*` / `grounded_*`) | 5 | 6 | jump_coyote + gravity_airborne + grounded_horizontal + wall_jump + wall_run_detection |
| Input (`mouse_capture` / `polling_*` / `latency_*` / `was_pressed_*` / `focus_*` / `enable_refcount`) | 7 | 11 | input system regression cluster |
| VFX (`secret_lures_lint` / `wall_run_door_lint` / `visual_authoring_lint` / `onboarding_anchors_lint` / `level_formulas_lint`) | 5 | 5 | lint cluster (ADR drift?) |
| Misc (`signal_order_exit_test` / `cross_system_mocks_test` / `level_signals_contract_test`) | 3 | 3 | signal contract drift |

**Conclusion** : ~30 fails pure régression Level (story-014 cleanup avait laissé Level dans état dégradé connu — confirmation tech-debt #2 sprint plan).

## Vraies pollutions cross-suite (4 cas)

| Suite | Cas observé | Hypothèse cause |
|---|---|---|
| `main_menu_boot_test` | Passe iso 3/3, fail 1/3 sweep | Une suite avant mute `GameStateManager._current_state` → pas restauré → boot test asserts MENU mais GSM en autre état |
| `no_alloc_play_2d_test` | Passe iso 3/3, fail 1/3 sweep | AudioSystem pool counters / static memory delta accumulé sur runs précédents (test mesure delta `MEMORY_STATIC` baseline biaisé) |
| `story_009_respawn_fade_flash_test` | Passe iso 5/5, fail 1/5 sweep | VFXSystem `_flash_active` ou pool decals laissé en état post-test précédent (régression pré-story-006 GSM gating ?) |
| `test_movement_signals_typed_contract` | Passe iso 20/20, fail 1/20 sweep | Mock signal connection refcount accumulé → contract assertion sur signal already-connected |

**Action ROI bas** : 4 fails sur 1117 tests. Fix infra autoload reset bénéfice marginal vs. effort. **Reporter post-régression cleanup**.

## Recommandation

1. **NE PAS** implémenter helper `AutoloadResetTestSuite` maintenant : ROI 0.36 % du volume fails.
2. **Prioriser** : 5 stories régression per-epic (Level / Camera / Movement / Input / Lint cluster).
3. **Workaround court terme CI** : split CI en jobs par-epic (déjà partiel via `lint-*` jobs séparés). Le full sweep reste fragile mais non-bloquant pour gates.
4. **Re-évaluer infra reset** post-cleanup régressions : si après fix régressions, les 4 vraies pollutions persistent → story dédiée pollution autoload.

## Source

- Smoke W-4 obsolete : `production/qa/smoke-2026-05-05.md`
- Sprint plan tech-debt #1 : `production/sprints/sprint-pre-production-2026-05-05.md` ligne 85
- Story diagnostic : `production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md`
- Sweep report ref : `reports/report_509/results.xml` (rotatif gitignored)
