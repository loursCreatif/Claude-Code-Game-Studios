# Menu — Anti-Patterns Lint Static

Le Menu System (Main Menu + Pause Menu) est un consommateur **outbound-only** de
GSM (ADR-0007 D-9 pull pattern + D-10 state_changed contract). Il ne mute jamais
`Engine.time_scale`, `get_tree().paused`, ne référence jamais SaveLoad, et n'a
aucun couplage cross-system (Level/Combat/Movement/Credit/Secret/Upgrade).

Ce lint statique enforce 11 patterns interdits comme garde-fou structurel — bien
plus rapide qu'un test runtime, et **independent de l'execution** (purement grep
+ parse `.tscn/.tres`).

## Scope

**Fichiers** : `src/gameplay/menu/**/*.gd` + `scenes/menus/**/*.tscn` + `scenes/menus/**/*.tres`.

**Cibles secondaires** : `scenes/levels/**/*.tscn` (AC-MNU-44 portée étages —
helper plus fin pour distinguer AudioStreamPlayer dans pause_overlay sub-tree
vs ambient track étage ; au MVP, dir vide → SKIP gracieux).

## Forbidden Patterns

Lint cover-all : si un fichier `src/gameplay/menu/` ou `scenes/menus/` matche un
des patterns ci-dessous (hors commentaires `#` et marqueur `# lint-menu-ok`), le
lint échoue.

| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-MNU-36 + AC-MNU-64 | `\b(Tween\|create_tween\|tween_property\|InterpolateValue\|AnimationPlayer\|AnimationTree)\b` | R-MNU-15 + GDD K.7 + K.9 reduce-motion | ADVISORY |
| AC-MNU-44 | `AudioStreamPlayer\|play_sfx\|audio_play` | GDD K.10 (zéro SFX menu MVP) | BLOCKING |
| AC-MNU-45 | `AcceptDialog\|ConfirmationDialog\|PopupPanel\|PopupMenu` | R-MNU-16 (zero confirm anti-Pillar 1 friction) | BLOCKING |
| AC-MNU-46 | `corner_radius` non-zero | Chrome Zen K.5 hard-edge | BLOCKING |
| AC-MNU-47 | `ParallaxBackground\|ParallaxLayer\|AnimationPlayer\|AnimationTree` | GDD K.7 | ADVISORY |
| AC-MNU-48 | `Gradient\|GradientTexture\|CanvasItemMaterial\|ShaderMaterial` | GDD K.8 (Chrome Zen flat) | ADVISORY |
| AC-MNU-49 | `Engine\.time_scale` | ADR-0007 D-4 (GSM seul autorité) | BLOCKING |
| AC-MNU-50 | `get_tree\(\)\.paused\|SceneTree.*paused` | ADR-0007 D-4 (autorité unique GSM) | BLOCKING |
| AC-MNU-57 | `SaveLoad\|\bsave_int\b\|\bsave_string_array\b\|save_now` | R-MNU-19 + ADR-0010 R-SAV-9 (délégation pure) | BLOCKING |
| AC-MNU-63 | `NOTIFICATION_WM_WINDOW_FOCUS\|_notification\b.*_focus` | R-MNU-18 anti-dep ADR-0004 D-5 | BLOCKING |
| Anti-deps R-MNU-18 | `\b(LevelSystem\|CombatSystem\|MovementController\|CreditSystem\|SecretSystem\|UpgradeSystem)\b` | R-MNU-18 (zéro couplage cross-system) | BLOCKING |

**Exception** : commentaire `# lint-menu-ok: <raison>` sur la ligne concernée
accepté (justification obligatoire pour audit trail). Analogue à
`# lint-emit-thread-ok` (level-signals), `# lint-input-thread-ok` (input-singleton),
`# lint-collision-layers-ok` (collision-layers).

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# AC-MNU-36 + 64 — anti-tween/anim
! grep -rE '\b(Tween|create_tween|tween_property|InterpolateValue|AnimationPlayer|AnimationTree)\b' src/gameplay/menu/ \
  | grep -v '#' \
  | grep -v 'lint-menu-ok' \
  || fail AC-MNU-36

# AC-MNU-44 — anti-SFX
! grep -rE 'AudioStreamPlayer|play_sfx|audio_play' scenes/menus/ src/gameplay/menu/ \
  | grep -v '#' \
  | grep -v 'lint-menu-ok' \
  || fail AC-MNU-44

# AC-MNU-45 — anti-confirm
! grep -rE 'AcceptDialog|ConfirmationDialog|PopupPanel|PopupMenu' scenes/menus/ src/gameplay/menu/ \
  | grep -v '#' \
  | grep -v 'lint-menu-ok' \
  || fail AC-MNU-45

# AC-MNU-46 — corner_radius zero
non_zero=$(grep -rE 'corner_radius' scenes/menus/ | grep -vE '=\s*0\b' || true)
[ -z "$non_zero" ] || fail AC-MNU-46

# AC-MNU-47 — anti-Parallax/Anim
! grep -rE 'ParallaxBackground|ParallaxLayer|AnimationPlayer|AnimationTree' scenes/menus/ \
  | grep -v '#' \
  | grep -v 'lint-menu-ok' \
  || fail AC-MNU-47

# AC-MNU-48 — anti-gradient/material
! grep -rE 'Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial' src/gameplay/menu/ \
  | grep -v '#' \
  | grep -v 'lint-menu-ok' \
  || fail AC-MNU-48

# AC-MNU-49 — Engine.time_scale
! grep -rE 'Engine\.time_scale' src/gameplay/menu/ \
  | grep -v '#' \
  || fail AC-MNU-49

# AC-MNU-50 — get_tree().paused mutation
! grep -rE 'get_tree\(\)\.paused|SceneTree.*paused' src/gameplay/menu/ \
  | grep -v '#' \
  || fail AC-MNU-50

# AC-MNU-57 — zero SaveLoad
! grep -rE 'SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now' src/gameplay/menu/ \
  | grep -v '#' \
  || fail AC-MNU-57

# AC-MNU-63 — zero focus notification
! grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/ \
  | grep -v '#' \
  || fail AC-MNU-63

# R-MNU-18 — anti-deps
! grep -rE '\b(LevelSystem|CombatSystem|MovementController|CreditSystem|SecretSystem|UpgradeSystem)\b' src/gameplay/menu/ \
  | grep -v '#' \
  || fail R-MNU-18

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-menu-anti-patterns`.
Le job inspecte `src/gameplay/menu/` + `scenes/menus/` + `scenes/levels/` et
échoue si un pattern interdit apparaît, sauf marquage `# lint-menu-ok: <raison>`.

Log artefact : `production/qa/evidence/menu-anti-patterns-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test (parité project-pattern)

`tests/static/menu_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes
greps (FileAccess + RegEx) pour exécution locale rapide via la suite menu :

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/menu_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode
```

Couvre AC-MNU-36/44/45/46/47/48/49/50/57/63/64 + R-MNU-18 — 11 tests static
(0 dépendance runtime). Note : AC-MNU-63 + 66 (story-009) restent dans leurs
fichiers respectifs (`menu_anti_focus_handler_lint_test.gd`, `menu_theme_lint_test.gd`)
— pas de duplication.

## Pattern recommandé

### Pause / Resume → délégation GSM stricte

```gdscript
# CORRECT — Menu lit GSM, ne mute jamais Engine.time_scale ni get_tree().paused
func _on_resume_pressed() -> void:
    GameStateManager.request_resume()  # GSM mute time_scale + paused

# INCORRECT — autorité usurpée
func _on_resume_pressed() -> void:
    Engine.time_scale = 1.0           # VIOLATION AC-MNU-49
    get_tree().paused = false         # VIOLATION AC-MNU-50
```

### Save-on-quit → délégation pure SaveLoad

```gdscript
# CORRECT — Menu n'appelle jamais SaveLoad APIs (NOTIFICATION_WM_CLOSE_REQUEST → SaveLoad gère)
func _on_quit_pressed() -> void:
    get_tree().quit()  # SaveLoad R-SAV-9 absorbe via NOTIFICATION_WM_CLOSE_REQUEST

# INCORRECT — couplage interdit
func _on_quit_pressed() -> void:
    SaveLoadSystem.save_now()         # VIOLATION AC-MNU-57
    get_tree().quit()
```

### Anti-deps cross-system

```gdscript
# CORRECT — Menu ne référence aucun système gameplay
func _on_start_pressed() -> void:
    GameStateManager.start_etage(1)  # GSM orchestre LevelSystem.load_etage en interne

# INCORRECT — couplage direct
func _on_start_pressed() -> void:
    LevelSystem.load_etage(1)         # VIOLATION R-MNU-18 (cross-system)
```

## Source

- R-MNU-15 (zero tween) + R-MNU-16 (zero confirm) + R-MNU-18 (anti-deps strictes) + R-MNU-19 (save-on-quit délégation pure) — `design/gdd/menu-system.md` Detailed Rules
- ADR-0007 D-4 (GSM seul autorité pause + time_scale + get_tree().paused) — `docs/architecture/adr-0007-game-state-manager.md`
- ADR-0010 R-SAV-9 (Menu ne référence jamais SaveLoad APIs) — `docs/architecture/adr-0010-save-load-serialization-format.md`
- Story 010 — `production/epics/menu-system/story-010-anti-patterns-lint-static.md`
