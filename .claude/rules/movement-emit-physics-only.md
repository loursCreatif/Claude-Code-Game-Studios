---
name: movement-emit-physics-only
scope_files:
  - src/gameplay/player/movement_controller.gd
scope_functions_forbidden:
  - _process
  - _input
  - _unhandled_input
  - _ready
  - _notification
registry_forbidden_pattern: movement_emit_outside_physics_process
source:
  - ADR-0005 D-4
  - ADR-0005 VC-6
  - story-011 TR-mov-006
---

# Movement — Emit From _physics_process Only

Tous les `.emit(...)` de Movement signals doivent être appelés depuis
`_physics_process` ou une fonction appelée depuis lui. Émettre depuis
`_process` / `_input` / `_unhandled_input` / `_ready` / `_notification`
viole l'autorité gameplay ADR-0001 et casse la cohérence avec l'état.

## Scope

**Fichier** : `src/gameplay/player/movement_controller.gd`

**Signaux** : `dash_started`, `dash_ended`, `wall_run_entered`, `wall_run_exited`,
`wall_jumped`, `died`, `respawned`, `attacked` (ADR-0005 D-2 canonical list).

## Forbidden Patterns

`.emit(` dans le body de :

- `func _process(...)`
- `func _input(...)`
- `func _unhandled_input(...)`
- `func _ready(...)`
- `func _notification(...)`

**Autorisé** : `_physics_process`, fonctions appelées depuis lui (`die`,
`_respawn`, `_try_start_dash`, `_apply_dash_state`, `_try_start_wall_run`,
`_exit_wall_run`, `_update_wall_run`, helpers internes).

## Enforcement

### CI

Intégré dans `tests/static/movement_lint_test.gd` (parse function blocks +
regex `\.emit\(`).

### Local approximatif

```bash
awk '
/^func _(process|input|unhandled_input|ready|notification)\(/ { in_bad=1 }
/^func / && !/^func _(process|input|unhandled_input|ready|notification)\(/ { in_bad=0 }
in_bad && /\.emit\(/ { print NR": "$0 }
' src/gameplay/player/movement_controller.gd || echo "CLEAN"
```

Zéro match = lint pass.

## Rationale

ADR-0001 désigne `_physics_process` comme l'unique autorité pour toutes les
mutations d'état gameplay (60 Hz, thread principal garanti, Jolt step synced).
Émettre un signal dans `_ready` (pre-physics) ou `_process` (visual tick) crée
une désynchronisation entre l'état du MovementController et ce que les consumers
reçoivent, menant à des handlers qui lisent un état incohérent.

## Source

- ADR-0005 D-4 (emit physics process only)
- ADR-0005 VC-6 (lint static)
- story-011 TR-mov-006
