# Collision Layer API — 1-Indexed Obligatoire

Le code GDScript sous `src/` ne doit jamais manipuler `collision_layer` ou
`collision_mask` via des littéraux bitmask (décimal, hex `0x...`, binaire
`0b...`). La 1-indexation de l'API Godot (`set_collision_layer_value(N)` /
`get_collision_mask_value(N)`) est la seule forme autorisée.

**Rationale** : la manipulation bitmask directe a causé un bug en Level GDD r1
(`"bit 4 = layer 4"` → incorrect — Project Settings 1-indexe, donc Layer 4 = bit 3 =
`1 << 3 = 8`). Ce bug ne peut pas se reproduire avec `set_collision_layer_value(4, true)`
ni avec `CollisionLayers.build_mask([LAYER_ENVIRONMENT])`. ADR-0008 D-3 fige ce
contrat pour tout le projet.

## Scope

**Fichiers** : `src/**/*.gd`.

**Exclusions explicites** :
- `src/core/collision_layers.gd` — le helper lui-même est autorisé à calculer les
  décalages internes via `1 << (N - 1)` (implémentation de `build_mask`).
- Fichiers `.tscn` / `.tres` — Godot stocke la valeur entière décimale à la
  sérialisation scène. Ce n'est pas du code, pas d'intervention manuelle requise.
  (MVP : WARN seulement si layer > 31 dans `scenes/**`, upgrade FAIL post-MVP.)
- Lignes commentaires pures (`# ...` au début de ligne après indentation).
- Lignes annotées `# lint-collision-layers-ok: <raison>` (justification obligatoire
  pour audit trail).

## Forbidden Patterns

| Check | Pattern | Source | Niveau |
|-------|---------|--------|--------|
| Bitmask littéral GDScript | `\bcollision_(layer\|mask)\s*=\s*(0b[01]+\|0x[0-9a-fA-F]+\|[0-9]+)` dans `src/**/*.gd` hors `collision_layers.gd` | ADR-0008 D-3 | BLOCKING |
| Noms canoniques absents `project.godot` | `[layer_names]/3d_physics/layer_1..5` doivent être présents | ADR-0008 D-4 | BLOCKING |
| Layers 6+ non-canoniques dans `.tscn` | `collision_(layer\|mask)\s*=\s*[0-9]+` avec valeur décimale > 31 dans `scenes/` | ADR-0008 D-6 | WARN (MVP) |

### Noms canoniques obligatoires (`project.godot`)

```ini
[layer_names]

3d_physics/layer_1="LAYER_PLAYER"
3d_physics/layer_2="LAYER_ENEMY"
3d_physics/layer_3="LAYER_ENEMY_HITBOX"
3d_physics/layer_4="LAYER_ENVIRONMENT"
3d_physics/layer_5="LAYER_INTERACTIVE"
```

## Enforcement

### Local

```bash
set -euo pipefail
violations=0
fail() { echo "FAIL $1"; violations=$((violations + 1)); }

# Check 1 — bitmask littéral dans src/**/*.gd (ADR-0008 D-3)
matches=$(grep -rnE '\bcollision_(layer|mask)\s*=\s*(0b[01]+|0x[0-9a-fA-F]+|[0-9]+)' \
  src/ --include='*.gd' \
  | grep -v '^[^:]*:[0-9]*:\s*#' \
  | grep -v '^src/core/collision_layers\.gd:' \
  | grep -v 'lint-collision-layers-ok' \
  || true)
[ -z "$matches" ] || { fail "Check1-bitmask"; echo "$matches"; }

# Check 2 — project.godot layer_names canoniques (ADR-0008 D-4)
declare -a expected=(
  '3d_physics/layer_1="LAYER_PLAYER"'
  '3d_physics/layer_2="LAYER_ENEMY"'
  '3d_physics/layer_3="LAYER_ENEMY_HITBOX"'
  '3d_physics/layer_4="LAYER_ENVIRONMENT"'
  '3d_physics/layer_5="LAYER_INTERACTIVE"'
)
for line in "${expected[@]}"; do
  grep -qF "$line" project.godot || { fail "Check2-missing-${line}"; }
done
grep -q '^\[layer_names\]' project.godot || { fail "Check2-section-absent"; }

# Check 3 — .tscn sous scenes/** : WARN seulement au MVP
if [ -d scenes ]; then
  tscn_hits=$(grep -rnE 'collision_(layer|mask)\s*=\s*[0-9]+' \
    scenes/ --include='*.tscn' 2>/dev/null \
    | awk -F= '{ split($0, a, "="); val = a[2]+0; if (val > 31) print }' || true)
  [ -z "$tscn_hits" ] || echo "WARN — .tscn avec layer/mask > 31 (couvre layers 6+ non-canoniques)"
fi

[ "$violations" -eq 0 ] && echo "ALL PASS" || (echo "FAIL: $violations violations"; exit 1)
```

### CI (GitHub Actions)

Intégré dans `.github/workflows/tests.yml` — job `lint-collision-layers`.
- **Check 1** (bitmask littéral GDScript) : FAIL bloquant si regex matche dans `src/**/*.gd`.
- **Check 2** (`project.godot` layer names) : FAIL bloquant si les 5 noms canoniques sont absents.
- **Check 3** (`.tscn` layers 6+) : WARN seulement au MVP — `::warning::` GitHub, pas `exit 1`.

Exception : `# lint-collision-layers-ok: <raison>` sur la ligne concernée.

Log artefact : `production/qa/evidence/collision-layers-lint-YYYY-MM-DD.log`
(uploadé via `actions/upload-artifact@v4`).

### GdUnit4 static test

`tests/unit/collision/layer_mask_contract_test.gd` — smoke test runtime : spawn
minimal scene avec un de chaque archetype, assert `get_collision_layer_value(N) == true`
pour N attendu + `get_collision_mask_value(M) == true` pour chaque bit M attendu.

## Pattern recommandé

### API 1-indexée (ADR-0008 D-3)

```gdscript
# src/core/collision_layers.gd — helper canonique (non-autoload, static-only)
class_name CollisionLayersScript
extends RefCounted

const LAYER_PLAYER:       int = 1
const LAYER_ENEMY:        int = 2
const LAYER_ENEMY_HITBOX: int = 3
const LAYER_ENVIRONMENT:  int = 4
const LAYER_INTERACTIVE:  int = 5

## Construit un collision_mask entier depuis la liste de LAYER_* 1-indexés.
## Utilisation : CollisionLayers.build_mask([LAYER_ENEMY, LAYER_ENVIRONMENT])
static func build_mask(layers: Array[int]) -> int:
    var mask: int = 0
    for layer: int in layers:
        mask |= 1 << (layer - 1)
    return mask
```

```gdscript
# CORRECT — API 1-indexée
func _ready() -> void:
    body.set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)
    body.collision_mask = 0  # géométrie statique ne détecte rien

# CORRECT — build_mask pour PhysicsRayQueryParameters3D (pas d'API per-bit)
var query := PhysicsRayQueryParameters3D.create(from, to)
query.collision_mask = CollisionLayersScript.build_mask([CollisionLayersScript.LAYER_ENEMY])

# INCORRECT — bitmask littéral (VIOLATION ADR-0008 D-3)
body.collision_layer = 8              # FAIL Check 1
body.collision_layer = 0b01000        # FAIL Check 1
body.collision_layer |= (1 << 3)      # FAIL Check 1
body.collision_mask = 0b00010         # FAIL Check 1
```

### Decision Matrix des masks canoniques (ADR-0008 D-2)

| Archetype | Node type | `collision_layer` | `collision_mask` |
|-----------|-----------|-------------------|------------------|
| Player body | `CharacterBody3D` | Layer 1 | Layers 2, 4 |
| Katana ShapeCast | `ShapeCast3D` | Layer 1 | Layer 2 (Enemy body) + Layer 3 (Hitbox) |
| Enemy body | `CharacterBody3D` | Layer 2 | Layer 4 uniquement |
| Enemy lethal hitbox | `Area3D` | Layer 3 | Layer 1 (Player) |
| Environment static | `StaticBody3D` | Layer 4 | 0 (géométrie passive) |
| Interactive trigger | `Area3D` | Layer 5 | Layer 1 (Player) |

## Source

- ADR-0008 D-1 (taxonomie 5 layers) + D-2 (Decision Matrix) + D-3 (API 1-indexée)
  + D-4 (project.godot layer names) + D-6 (lint pre-build CI)
  — `docs/architecture/adr-0008-collision-layer-taxonomy.md`
- Level GDD r2 §R-5.5 + §InteractiveVolumes
  — `design/gdd/level-system.md`
- TR-lvl-007 (StaticBody3D LAYER_ENVIRONMENT), TR-lvl-008 (Area3D LAYER_INTERACTIVE)
- Story-013 AC-LVL-12 / AC-LVL-13 — `production/epics/level-system/story-013-*.md`
