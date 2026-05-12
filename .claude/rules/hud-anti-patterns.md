# HUD System — Anti-Patterns Lint Static

Le HUD System est un consommateur **outbound-only** de GSM + CreditEconomy
(R-HUD-12 outbound-only contract). Il ne référence jamais les systèmes gameplay
downstream (Combat/Level/Movement/Enemy/Audio/Player/InputManager/SaveLoad), et
son CanvasLayer doit toujours rester sous `layer < 100` (GSM owns 100).

Ce lint statique enforce 7 patterns interdits comme garde-fou structurel — bien
plus rapide qu'un test runtime, et **independent de l'execution** (purement grep
+ parse `.tscn/.tres`).

## Scope

**Fichiers** : `src/gameplay/hud/**/*.gd` + `scenes/hud/**/*.tscn` + `scenes/hud/**/*.tres`.

**Note** : `scenes/hud/` peut ne pas exister (HUD instancié programmatiquement
en tant qu'autoload via `CanvasLayer.new()` dans story-001). Les lints sur
`scenes/hud/` passent triviaux (0 fichier = 0 match) si le répertoire est absent.

**Hors scope** : `tests/` (fixtures stub autorisées), `docs/` (documentation
mentionnant les symboles forbidden à fins d'audit trail).

## Forbidden Patterns

Lint cover-all : si un fichier `src/gameplay/hud/` ou `scenes/hud/` matche un
des patterns ci-dessous (hors commentaires `#` et marqueur `# lint-hud-ok`), le
lint échoue.

| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-HUD-LINT-1 | `CombatSystem\|LevelSystem\|MovementController\|EnemySystem\|Player\.\|AudioSystem\|AudioServer\|AudioStreamPlayer` | R-HUD-12 outbound-only + R-HUD-15 zero SFX | BLOCKING |
| AC-HUD-LINT-2 | `\bInputManager\b\|\bInput\.` | R-HUD-14 zero Input HUD MVP | BLOCKING |
| AC-HUD-LINT-3 | `SaveLoad\|\bsave_int\b\|\bsave_string_array\b\|save_now` | R-HUD-12 + ADR-0010 R-SAV-9 délégation pure | BLOCKING |
| AC-HUD-LINT-4 | `AnimationPlayer\|AnimationTree\|ParallaxBackground\|ParallaxLayer` | GDD K.7 anti-animation HUD | BLOCKING |
| AC-HUD-LINT-5 | `Gradient\|GradientTexture\|CanvasItemMaterial\|ShaderMaterial` | GDD K.8 Chrome Zen flat | ADVISORY |
| AC-HUD-LINT-6 | `corner_radius` non-zero dans `scenes/hud/` | Chrome Zen K.5 hard-edge | BLOCKING |
| AC-HUD-LINT-7 | `\.layer\s*=\s*(100\|10[1-9]\|1[1-9][0-9]\|[2-9][0-9][0-9])` | R-HUD-11 layer<100 strict — GSM owns 100 | BLOCKING |

Seules dépendances autorisées dans `src/gameplay/hud/` : `CreditEconomy` et
`GameStateManager`.

**Exception annotation** (ligne par ligne) :
- `# lint-hud-ok: <raison>` — autorise le pattern sur la ligne annotée
  (e.g. commentaire ADR mentionnant `AudioSystem` à fins documentaires)

Lignes commentaires pures (`#` au début de ligne après indentation) sont
automatiquement ignorées.

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# AC-HUD-LINT-1 — outbound-only zero cross-system + zero SFX (R-HUD-12 + R-HUD-15)
matches=$(grep -rnE 'CombatSystem|LevelSystem|MovementController|EnemySystem|Player\.|AudioSystem|AudioServer|AudioStreamPlayer' \
  src/gameplay/hud/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || { fail AC-HUD-LINT-1; echo "$matches"; }

# AC-HUD-LINT-2 — zero Input HUD MVP (R-HUD-14)
matches=$(grep -rnE '\bInputManager\b|\bInput\.' \
  src/gameplay/hud/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || { fail AC-HUD-LINT-2; echo "$matches"; }

# AC-HUD-LINT-3 — zero SaveLoad ref (R-HUD-12 + ADR-0010 R-SAV-9)
matches=$(grep -rnE 'SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now' \
  src/gameplay/hud/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || { fail AC-HUD-LINT-3; echo "$matches"; }

# AC-HUD-LINT-4 — anti-Animation/Parallax (GDD K.7)
hud_dirs=("src/gameplay/hud/")
[ -d scenes/hud ] && hud_dirs+=("scenes/hud/")
matches=$(grep -rnE 'AnimationPlayer|AnimationTree|ParallaxBackground|ParallaxLayer' \
  "${hud_dirs[@]}" 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || { fail AC-HUD-LINT-4; echo "$matches"; }

# AC-HUD-LINT-5 — anti-gradient/material ADVISORY (GDD K.8)
matches=$(grep -rnE 'Gradient|GradientTexture|CanvasItemMaterial|ShaderMaterial' \
  src/gameplay/hud/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || echo "ADVISORY AC-HUD-LINT-5: $matches"

# AC-HUD-LINT-6 — corner_radius zero (scenes/hud/ vide au MVP → SKIP gracieux)
if [ -d scenes/hud ]; then
  non_zero=$(grep -rnE 'corner_radius' scenes/hud/ 2>/dev/null \
    | grep -vE '=\s*0\b' \
    | grep -v '^[^:]*:[0-9]*:\s*#' \
    || true)
  [ -z "$non_zero" ] || { fail AC-HUD-LINT-6; echo "$non_zero"; }
fi

# AC-HUD-LINT-7 — layer < 100 strict (R-HUD-11 — GSM owns 100)
matches=$(grep -rnE '\.layer\s*=\s*(100|10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])' \
  src/gameplay/hud/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-hud-ok' \
  || true)
[ -z "$matches" ] || { fail AC-HUD-LINT-7; echo "$matches"; }

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

Zéro violation = lint pass.

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-hud-anti-patterns`.
Le job inspecte `src/gameplay/hud/` + `scenes/hud/` et échoue si un pattern
BLOCKING apparaît, sauf marquage `# lint-hud-ok: <raison>`.

Log artefact : `production/qa/evidence/hud-anti-patterns-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test (parité project-pattern)

`tests/static/hud_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes
greps (`FileAccess` + `RegEx`) pour exécution locale rapide via la suite test :

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/hud_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode
```

Couvre AC-HUD-LINT-1/2/3/4/5/6/7 — 7 tests static (0 dépendance runtime).

## Pattern recommandé

### Outbound-only — zéro référence cross-system (AC-HUD-LINT-1)

```gdscript
# CORRECT — HUD observe CreditEconomy via signal, sans référence cross-system
func _on_credits_changed(total: int, delta: int, source: int) -> void:
    _credit_counter_label.text = str(total)
    if delta > 0:
        _start_pulse_tween(source)  # HUD-interne uniquement

# INCORRECT — couplage interdit
func _on_credits_changed(total: int, delta: int, source: int) -> void:
    _credit_counter_label.text = str(total)
    AudioSystem.play_2d(sfx_stream, &"HUD")  # VIOLATION AC-HUD-LINT-1 (R-HUD-15)
    CombatSystem.notify_credit_displayed()   # VIOLATION AC-HUD-LINT-1 (R-HUD-12)
```

### Layer < 100 strict — GSM owns 100 (AC-HUD-LINT-7)

```gdscript
# CORRECT — layer=50, bien en dessous du seuil GSM fade overlay
const HUD_CANVAS_LAYER: int = 50
_canvas_layer.layer = HUD_CANVAS_LAYER  # 50 < 100 ✓

# INCORRECT — empiète sur GSM fade layer
_canvas_layer.layer = 100  # VIOLATION AC-HUD-LINT-7 (R-HUD-11)
_canvas_layer.layer = 150  # VIOLATION AC-HUD-LINT-7 (R-HUD-11)
```

### SaveLoad — délégation pure (AC-HUD-LINT-3)

```gdscript
# CORRECT — HUD ne gère jamais la persistence
func _on_quit_pressed() -> void:
    GameStateManager.request_quit()  # GSM + SaveLoad gèrent (ADR-0010 R-SAV-9)

# INCORRECT — couplage interdit
func _on_quit_pressed() -> void:
    SaveLoadSystem.save_now()  # VIOLATION AC-HUD-LINT-3 (ADR-0010 R-SAV-9)
    get_tree().quit()
```

## Source

- R-HUD-11 (layer<100 strict GSM owns 100) + R-HUD-12 (outbound-only zero couplage)
  + R-HUD-13 (zero alloc hot path) + R-HUD-14 (zero Input HUD MVP)
  + R-HUD-15 (zero SFX HUD MVP) — `design/gdd/hud-system.md` Detailed Rules
- ADR-0009 D-2 (Audio pool exclusive) — `docs/architecture/adr-0009-audio-system.md`
- ADR-0010 R-SAV-9 (HUD ne référence jamais SaveLoad APIs) — `docs/architecture/adr-0010-save-load-serialization-format.md`
- AC-HUD-25/26/27/28/31/32/33/34/35 — `design/gdd/hud-system.md` Acceptance Criteria
- Story 005 — `production/epics/hud-system/story-005-anti-patterns-lint-static.md`
