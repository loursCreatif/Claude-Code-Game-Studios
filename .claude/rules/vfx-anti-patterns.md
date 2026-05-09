# VFX System — Anti-Patterns Lint Static

Le VFX System est un autoload Presentation layer outbound-only terminal. Quatre invariants
structurels gardent la qualité de l'implémentation contre les régressions silencieuses :

- **Pool exclusive (R-VFX-1)** : seul `src/core/vfx_system.gd` instancie `GPUParticles3D` /
  `Decal` / `MeshInstance3D` runtime. Les consumers passent par l'API publique
  (`play_kill_at`, `start_katana_trail`, `flash_kill`, etc.).
- **Wall-clock fades (R-VFX-5/15)** : les fades temps-critiques (`color`, `modulate`,
  trail opacity) sont calculés dans `_physics_process` via `Time.get_ticks_msec()`.
  Tween est interdit sur effets time-critical car `time_scale`-dépendant (casse Pillar 1
  60 fps wall-clock indépendant slow-mo Combat AC-VFX-25/26).
- **CONNECT_DEFERRED (R-VFX-3)** : tous les `connect()` vers handlers `_on_*` VFXSystem
  doivent inclure le flag `CONNECT_DEFERRED` pour éviter les mutations cross-system
  mid-physics-frame. Exception SYNC justifiée OQ-VFX-4 (flash kill frame-precise) annotée.
- **Outbound-zero (R-VFX-14)** : VFX System ne mute aucun état amont, n'émet aucun signal,
  ne stocke aucune référence Node enemies/player. Terminal pur.

Pattern précédent epics : `audio-anti-patterns.md` / `menu-anti-patterns.md` /
`hud-anti-patterns.md` / `level-signals-main-thread-only.md` / `input-singleton-main-thread-only.md` /
`movement-emit-physics-only.md` / `no-alloc-hot-paths.md`.

## Scope

**Fichiers** :
- `src/core/vfx_system.gd` (VFXSystem autoload)
- `src/gameplay/vfx/**/*.gd` (handlers consumer futurs si extraction post-MVP)

**Hors scope** : `tests/` (fixtures stub `Decal.new()` autorisé), assets, scenes
(pas d'instanciation Particle runtime via `.new()` en `.tscn`).

## Forbidden Patterns

| AC | Pattern (regex) | Source | Niveau |
|----|-----------------|--------|--------|
| AC-VFX-05 | `GPUParticles3D\.new\(\)` / `Decal\.new\(\)` / `MeshInstance3D\.new\(\)` HORS `src/core/vfx_system.gd` | R-VFX-1 + ADR-0009 D-2 | BLOCKING |
| AC-NEW-09 | `Tween\.tween_property.*\b(color\|modulate\|opacity\|alpha)\b` dans `src/core/vfx_system.gd` + `src/gameplay/vfx/` | R-VFX-5/15 + ADR-0009 D-3 | BLOCKING |
| AC-NEW-10 | `\.connect\([^,)]+\)\s*$` (1 arg sans flag) sur ligne contenant `_on_*` handler | R-VFX-3 + ADR-0009 D-4 | BLOCKING |
| AC-VFX-23 | `emit_signal\b` ou `\.emit\(` dans `src/core/vfx_system.gd` + `src/gameplay/vfx/` | R-VFX-14 outbound-zero | BLOCKING |

**Exception annotation** (ligne par ligne) :
- `# lint-vfx-pool-ok: <raison>` — autorise instanciation hors `vfx_system.gd`
  (cas pathologique uniquement, justification obligatoire pour audit trail)
- `# lint-vfx-tween-ok: <raison>` — autorise Tween sur color/modulate
  (e.g. trail fade `time_scale==1.0` garanti par GSM autorité)
- `# lint-vfx-deferred-ok: <raison>` — autorise `connect()` sans `CONNECT_DEFERRED`
  (e.g. SYNC flash kill frame-precise OQ-VFX-4)
- `# lint-vfx-outbound-ok: <raison>` — autorise emit_signal dans VFXSystem
  (cas pathologique uniquement, ne devrait jamais arriver)

Lignes commentaires pures (`#` au début de ligne) sont automatiquement skipées.

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# AC-VFX-05 — pool exclusive (anti GPUParticles3D/Decal/MeshInstance3D.new() hors vfx_system.gd)
matches=$(grep -rnE 'GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)' src/ 2>/dev/null \
  | grep -v 'src/core/vfx_system.gd' \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v 'lint-vfx-pool-ok' \
  || true)
[ -z "$matches" ] || { fail AC-VFX-05; echo "$matches"; }

# AC-NEW-09 — anti-Tween sur color/modulate/opacity/alpha dans vfx_system.gd + vfx/
paths_tween=()
[ -f src/core/vfx_system.gd ] && paths_tween+=("src/core/vfx_system.gd")
[ -d src/gameplay/vfx ] && paths_tween+=("src/gameplay/vfx/")
if [ "${#paths_tween[@]}" -gt 0 ]; then
  matches=$(grep -rnE 'Tween\.tween_property.*\b(color|modulate|opacity|alpha)\b' \
    "${paths_tween[@]}" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:\s*#' \
    | grep -v 'lint-vfx-tween-ok' \
    || true)
  [ -z "$matches" ] || { fail AC-NEW-09; echo "$matches"; }
fi

# AC-NEW-10 — connect() sans CONNECT_DEFERRED dans handlers _on_*
paths_def=()
[ -f src/core/vfx_system.gd ] && paths_def+=("src/core/vfx_system.gd")
[ -d src/gameplay/vfx ] && paths_def+=("src/gameplay/vfx/")
if [ "${#paths_def[@]}" -gt 0 ]; then
  matches=$(grep -rnE '\.connect\([^,)]+\)\s*$' \
    "${paths_def[@]}" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:\s*#' \
    | grep -v 'lint-vfx-deferred-ok' \
    | grep -E '_on_[a-z_]+' \
    || true)
  [ -z "$matches" ] || { fail AC-NEW-10; echo "$matches"; }
fi

# AC-VFX-23 — outbound-zero (anti emit_signal / .emit dans vfx_system.gd + vfx/)
paths_emit=()
[ -f src/core/vfx_system.gd ] && paths_emit+=("src/core/vfx_system.gd")
[ -d src/gameplay/vfx ] && paths_emit+=("src/gameplay/vfx/")
if [ "${#paths_emit[@]}" -gt 0 ]; then
  matches=$(grep -rnE 'emit_signal\b|\.emit\(' \
    "${paths_emit[@]}" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:\s*#' \
    | grep -v 'lint-vfx-outbound-ok' \
    || true)
  [ -z "$matches" ] || { fail AC-VFX-23; echo "$matches"; }
fi

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

Zéro violation = lint pass.

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-vfx-anti-patterns`.
Le job échoue si un pattern interdit apparaît, sauf marquage explicite via
`lint-vfx-{pool,tween,deferred,outbound}-ok: <raison>`.

Log artefact : `production/qa/evidence/vfx-anti-patterns-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test (parité project-pattern)

`tests/static/vfx_anti_patterns_lint_test.gd` — wrapper GdUnit4 sur les mêmes
greps (`FileAccess` + `RegEx`) pour exécution locale rapide via la suite test.

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/static/vfx_anti_patterns_lint_test.gd \
  --ignoreHeadlessMode
```

Couvre AC-VFX-05/23 + AC-NEW-09/10 — 4 tests static (0 dépendance runtime).

## Pattern recommandé

### Pool exclusive (AC-VFX-05)

```gdscript
# CORRECT — consumer passe par VFXSystem API
func _on_combat_kill(_enemy: Node, position: Vector3) -> void:
    VFXSystem.play_kill_at(position)  # API publique VFXSystem

# INCORRECT — instanciation directe hors vfx_system.gd
func _on_combat_kill(_enemy: Node, position: Vector3) -> void:
    var p: GPUParticles3D = GPUParticles3D.new()  # VIOLATION AC-VFX-05
    add_child(p)
    p.global_position = position
    p.emitting = true
```

### Wall-clock fades (AC-NEW-09)

```gdscript
# CORRECT — _physics_process tick + Time.get_ticks_msec() injection wall-clock
func _physics_process(_delta: float) -> void:
    if _flash_kill_active:
        var elapsed_ms: int = _get_time_msec.call() - _flash_kill_start_msec
        var t: float = clampf(float(elapsed_ms) / FLASH_KILL_DURATION_MS, 0.0, 1.0)
        _flash_overlay_rect.color = Color(1.0, 1.0, 1.0, 1.0 - t)

# INCORRECT — Tween sur color (time_scale-scaled, casse Pillar 1 60 fps wall-clock)
func _trigger_flash_kill() -> void:
    var tween: Tween = create_tween()
    tween.tween_property(_flash_overlay_rect, "color:a", 0.0, 0.08)  # VIOLATION AC-NEW-09
```

### CONNECT_DEFERRED (AC-NEW-10)

```gdscript
# CORRECT — flag CONNECT_DEFERRED explicite sur handlers _on_*
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
    enemy_system.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)

# CORRECT — exception annotée pour SYNC flash kill (OQ-VFX-4 playtest)
enemy_system.enemy_killed.connect(_on_enemy_killed)  # SYNC frame-precise
# lint-vfx-deferred-ok: SYNC flash kill frame-precise (OQ-VFX-4 playtest validated)

# INCORRECT — connect sans flag (mutation cross-system mid-physics-frame possible)
func _connect_combat_signals() -> void:
    combat_system.swing_started.connect(_on_swing_started)        # VIOLATION AC-NEW-10
    enemy_system.enemy_killed.connect(_on_enemy_killed)           # VIOLATION AC-NEW-10
```

### Outbound-zero (AC-VFX-23)

```gdscript
# CORRECT — VFX consume, ne mute jamais, n'émet aucun signal
func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
    _spawn_blood_spurt(position)  # opération interne uniquement
    _spawn_decal_on_surface(position)

# INCORRECT — VFX émet signal observable par d'autres systèmes
signal vfx_played(event_type: StringName)
func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
    _spawn_blood_spurt(position)
    vfx_played.emit(&"kill")  # VIOLATION AC-VFX-23 — VFX terminal pur
```

## Source

- ADR-0009 D-2 (pool exclusive pattern) + D-3 (wall-clock fades pattern) + D-4 (CONNECT_DEFERRED pattern) — `docs/architecture/adr-0009-audio-system.md`
- R-VFX-1 + R-VFX-3 + R-VFX-5 + R-VFX-14/15 — `design/gdd/vfx-system.md` Detailed Rules
- AC-VFX-04/05/23/24 + AC-NEW-09/10/11/12 — `design/gdd/vfx-system.md` Acceptance Criteria
- Story 007 — `production/epics/vfx-system/story-007-anti-patterns-lint-static.md`
