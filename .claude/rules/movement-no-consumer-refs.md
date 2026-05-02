---
name: movement-no-consumer-refs
scope_files:
  - src/gameplay/player/movement_controller.gd
registry_forbidden_pattern: movement_consumer_reference
source:
  - ADR-0005 D-10
  - ADR-0005 VC-5
  - story-011 TR-mov-006
---

# Movement — Outbound-Only Consumer References

MovementController est outbound-only (ADR-0005 D-10) : zéro référence aux consumers
downstream (Camera, Combat, VFX, Audio, HUD). Les consumers se connectent depuis
leur propre `_ready()` via référence scene tree, sans que Movement les connaisse.

## Scope

**Fichier** : `src/gameplay/player/movement_controller.gd`

## Forbidden Patterns

| Pattern | Regex | Raison |
|---------|-------|--------|
| Référence consumer par nom | `\b(CameraSystem\|CombatSystem\|VFXManager\|AudioManager\|HUDController)\b` | Couplage interdit ADR-0005 D-10 |
| get_node /root/ vers autoload consumer | `get_node\("/root/(CameraSystem\|CombatSystem\|VFXManager\|AudioManager)` | Lookup direct interdit |
| preload de consumer path | `preload\("res://src/gameplay/(camera\|combat\|vfx\|audio\|hud)` | Dépendance compile-time interdite |
| NodePath dollar vers consumer | `\$(CameraSystem\|CombatSystem\|VFXManager\|HUDController)` | Tree path interdit |

## Enforcement

### Local

```bash
grep -nE '\b(CameraSystem|CombatSystem|VFXManager|AudioManager|HUDController)\b' src/gameplay/player/movement_controller.gd | grep -v '^[^:]*:\s*#' || echo "CLEAN"
```

Zéro match (hors commentaires) = lint pass.

### CI

Intégré dans `tests/static/movement_lint_test.gd` (GdUnit4 runner CI).

## Pattern recommandé : self-connect depuis le consumer

```gdscript
# CORRECT — dans CameraSystem._ready()
func _ready() -> void:
    var player: MovementController = get_tree().get_first_node_in_group("player") as MovementController
    if player:
        player.dash_started.connect(_on_player_dash_started)
        player.wall_run_entered.connect(_on_player_wall_run_entered)

# INCORRECT — depuis MovementController (couplage interdit)
func _ready() -> void:
    var cam: CameraSystem = get_node("/root/CameraSystem")  # VIOLATION
    dash_started.connect(cam._on_player_dash_started)       # VIOLATION
```

## Source

- ADR-0005 D-10 (outbound-only)
- ADR-0005 VC-5 (lint static)
- story-011 TR-mov-006
