# Audio System — Anti-Patterns Lint Static

L'Audio System est un autoload Core layer encapsulé. Trois invariants structurels
gardent la qualité de l'implémentation contre les régressions silencieuses :

- **D-2 Pool exclusive** : seul `src/core/audio_system.gd` instancie `AudioStreamPlayer*`.
  Les consumers passent par l'API publique (`play_2d`, `play_3d_at`, `play_music`,
  `duck_bus`, `set_paused`).
- **D-3 Wall-clock fades** : les fades temps-critiques (`volume_db`) sont calculés
  dans `_physics_process` via `_get_time_msec.call()` Callable injection. Tween est
  interdit sur `volume_db` car `time_scale`-dépendant (casse Pillar 1 60 fps wall-clock).
- **D-4 CONNECT_DEFERRED** : tous les `connect()` vers handlers `_on_*` AudioSystem
  doivent inclure le flag `CONNECT_DEFERRED` pour éviter les mutations cross-system
  mid-physics-frame.

Ce lint statique enforce 3 patterns interdits comme garde-fou structurel — bien plus
rapide qu'un test runtime, et **independent de l'execution** (purement grep + parse `.gd`).

Pattern précédent epics : `level-signals-main-thread-only.md` /
`input-singleton-main-thread-only.md` / `menu-anti-patterns.md` /
`movement-emit-physics-only.md` / `no-alloc-hot-paths.md`.

## Scope

**Fichiers** :
- `src/core/audio_system.gd` (AudioSystem autoload)
- `src/gameplay/audio/**/*.gd` (handlers consumer futurs si extraction post-MVP)

**Hors scope** : `tests/` (fixtures stub `AudioStreamWAV.new()` autorisé), assets,
scenes (pas d'instanciation Player runtime via `.new()` en `.tscn`).

## Forbidden Patterns

| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-AUD-10 | `Tween\.tween_property.*volume_db` ou `tween\..*audio.*volume_db` | R-AUD-4 + ADR-0009 D-3 | BLOCKING |
| AC-AUD-11 | `\.connect\([^,)]+\)\s*$` (1 arg sans flag) sur ligne contenant `_on_*` handler | R-AUD-5 + ADR-0009 D-4 | BLOCKING |
| AC-AUD-12 | `AudioStreamPlayer\.new\(\)` / `AudioStreamPlayer3D\.new\(\)` / `AudioListener3D\.new\(\)` HORS `src/core/audio_system.gd` | R-AUD-1 + ADR-0009 D-2 | BLOCKING |

**Exception annotation** (ligne par ligne) :
- `# lint-audio-tween-ok: <raison>` — autorise Tween volume_db (e.g. ambient
  crossfade `time_scale==1.0` garanti par GSM autorité)
- `# lint-audio-deferred-ok: <raison>` — autorise `connect()` sans `CONNECT_DEFERRED`
  (e.g. signal interne pool tracker `finished` `CONNECT_ONE_SHOT` story-007)
- `# lint-audio-pool-ok: <raison>` — autorise instanciation hors `audio_system.gd`
  (cas pathologique uniquement, justification obligatoire pour audit trail)

Lignes commentaires pures (`#` au début de ligne) sont automatiquement skipées.

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# AC-AUD-10 — anti-Tween volume_db
matches=$(grep -rnE 'Tween\.tween_property.*volume_db|tween\..*audio.*volume_db' \
  src/core/audio_system.gd src/gameplay/audio/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-audio-tween-ok' \
  || true)
[ -z "$matches" ] || { fail AC-AUD-10; echo "$matches"; }

# AC-AUD-11 — connect() sans CONNECT_DEFERRED dans handlers _on_*
matches=$(grep -rnE '\.connect\([^,)]+\)\s*$' \
  src/core/audio_system.gd src/gameplay/audio/ 2>/dev/null \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-audio-deferred-ok' \
  | grep -E '_on_[a-z_]+' \
  || true)
[ -z "$matches" ] || { fail AC-AUD-11; echo "$matches"; }

# AC-AUD-12 — AudioStreamPlayer.new() hors audio_system.gd
matches=$(grep -rnE 'AudioStreamPlayer\.new\(\)|AudioStreamPlayer3D\.new\(\)|AudioListener3D\.new\(\)' src/ 2>/dev/null \
  | grep -v 'src/core/audio_system.gd' \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-audio-pool-ok' \
  || true)
[ -z "$matches" ] || { fail AC-AUD-12; echo "$matches"; }

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

Zéro violation = lint pass.

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-audio-anti-patterns`.
Le job échoue si un pattern interdit apparaît, sauf marquage explicite via
`lint-audio-{tween,deferred,pool}-ok: <raison>`.

Log artefact : `production/qa/evidence/audio-anti-patterns-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test (parité project-pattern)

`tests/static/audio_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes
greps (`FileAccess` + `RegEx`) pour exécution locale rapide via la suite test.

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/audio_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode
```

Couvre AC-AUD-10/11/12 — 3 tests static (0 dépendance runtime).

## Pattern recommandé

### Pool exclusive (AC-AUD-12)

```gdscript
# CORRECT — consumer passe par AudioSystem API
func _on_enemy_killed(_enemy: Node) -> void:
    AudioSystem.play_3d_at(clac_stream, enemy.global_position, &"COMBAT_KILL")

# INCORRECT — instanciation directe hors audio_system.gd
func _on_enemy_killed(_enemy: Node) -> void:
    var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()  # VIOLATION AC-AUD-12
    add_child(player)
    player.stream = clac_stream
    player.play()
```

### Wall-clock fades (AC-AUD-10)

```gdscript
# CORRECT — _physics_process tick + Callable injection wall-clock
func _physics_process(_delta: float) -> void:
    if _swoosh_fade_active:
        var elapsed_ms: int = _get_time_msec.call() - _swoosh_fade_start_msec
        var t: float = clampf(float(elapsed_ms) / SWOOSH_FADE_DURATION_MS, 0.0, 1.0)
        AudioServer.set_bus_volume_db(_swoosh_bus_idx, lerpf(NOMINAL_DB, FADED_DB, t))

# INCORRECT — Tween sur volume_db (time_scale-scaled, casse 60 fps wall-clock)
func _on_swing_started() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(player, "volume_db", -80.0, 0.5)  # VIOLATION AC-AUD-10
```

### CONNECT_DEFERRED (AC-AUD-11)

```gdscript
# CORRECT — flag CONNECT_DEFERRED explicite sur handlers _on_*
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
    combat_system.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)

# CORRECT — exception annotée pour signal interne pool tracker (story-007)
clac_player.finished.connect(_on_clac_slot_finished.bind(slot_idx), CONNECT_ONE_SHOT)
# lint-audio-deferred-ok: signal interne pool tracker, dispatch immediate one-shot

# INCORRECT — connect sans flag (mutation cross-system mid-physics-frame possible)
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started)        # VIOLATION AC-AUD-11
    combat_system.enemy_killed.connect(_on_enemy_killed)          # VIOLATION AC-AUD-11
```

## Source

- ADR-0009 D-2 (pool exclusive) + D-3 (wall-clock fades) + D-4 (CONNECT_DEFERRED)
  — `docs/architecture/adr-0009-audio-system.md`
- R-AUD-1 + R-AUD-4 + R-AUD-5 — `design/gdd/audio-system.md` Detailed Rules
- AC-AUD-10/11/12 + VC-6 — `design/gdd/audio-system.md` Acceptance Criteria
- Story 009 — `production/epics/audio-system/story-009-anti-patterns-lint-static-pool-tween-deferred.md`
