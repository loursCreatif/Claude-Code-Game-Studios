# Godot Physics — Quick Reference

Last verified: 2026-02-12 | Engine: Godot 4.6

## What Changed Since ~4.3 (LLM Cutoff)

### 4.6 Changes
- **Jolt Physics is the DEFAULT 3D engine** for new projects
  - Existing projects keep their current physics engine setting
  - Better determinism, stability, and performance than GodotPhysics3D
  - Some HingeJoint3D properties (`damp`) only work with GodotPhysics3D
  - 2D physics UNCHANGED (still Godot Physics 2D)

### 4.5 Changes
- **3D physics interpolation rearchitected**: Moved from RenderingServer to SceneTree
  - User-facing API unchanged, but internal behavior may differ in edge cases

## Physics Engine Selection (4.6)

```
Project Settings → Physics → 3D → Physics Engine:
- Jolt Physics (DEFAULT for new projects)
- GodotPhysics3D (legacy, still available)
```

### Jolt vs GodotPhysics3D

| Feature | Jolt (default) | GodotPhysics3D |
|---------|---------------|----------------|
| Determinism | Better | Inconsistent |
| Stability | Better | Adequate |
| Performance | Better for complex scenes | Adequate |
| HingeJoint3D `damp` | NOT supported | Supported |
| Runtime warnings | Yes, for unsupported properties | No |
| Collision margins | May behave differently | Original behavior |

## Current API Patterns

### Basic Physics Setup (unchanged)
```gdscript
# CharacterBody3D movement — API unchanged across engines
extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity += get_gravity() * delta

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_velocity

    var input_dir: Vector2 = Input.get_vector("left", "right", "forward", "back")
    var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    velocity.x = direction.x * speed
    velocity.z = direction.z * speed

    move_and_slide()
```

### Raycasting (unchanged)
```gdscript
var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
var query := PhysicsRayQueryParameters3D.create(from, to)
query.collision_mask = collision_mask
var result: Dictionary = space_state.intersect_ray(query)
if result:
    var hit_point: Vector3 = result.position
    var hit_normal: Vector3 = result.normal
```

## Common Mistakes
- Assuming GodotPhysics3D is the default (Jolt since 4.6)
- Using HingeJoint3D `damp` property without checking physics engine (Jolt ignores it)
- Not testing collision edge cases when switching between physics engines

---

## CapsuleShape3D Basis Orientation — Godot 4.6 Convention

*Gap 7 — ADR-0006 D-7 documentation support. Lead-programmer 2026-04-23.*

### Convention Godot

Le grand axe d'une `CapsuleShape3D` est l'**axe Y local** du noeud qui la porte. Pour orienter une capsule le long d'un vecteur `forward` arbitraire (ex: `aim_forward` de la caméra), la basis doit satisfaire :

```
(basis * Vector3.UP).angle_to(forward) < 0.001 rad
```

### Pattern correct — cross product direct

```gdscript
const PITCH_LIMIT_EPSILON: float = 0.01
const BASIS_DETERMINANT_MIN: float = 0.001

func _build_capsule_basis(forward: Vector3) -> Basis:
    var fwd: Vector3 = forward.normalized()
    var up_ref: Vector3 = Vector3.UP
    # Fallback si forward colinéaire UP/DOWN (regard zénith/nadir) :
    if abs(fwd.dot(up_ref)) > 1.0 - PITCH_LIMIT_EPSILON:
        up_ref = Vector3.FORWARD
    var right: Vector3 = up_ref.cross(fwd).normalized()
    var local_z: Vector3 = fwd.cross(right).normalized()
    var basis: Basis = Basis(right, fwd, local_z)
    if abs(basis.determinant()) < BASIS_DETERMINANT_MIN:
        push_error("_build_capsule_basis: basis quasi-singulière — forward=%s" % forward)
        return Basis.IDENTITY
    return basis
```

### Pattern incorrect — à proscrire

```gdscript
# NE PAS FAIRE :
var basis = Basis.looking_at(target, up) * Basis.from_euler(Vector3(PI/2, 0, 0))
```

`Basis.looking_at` oriente **-Z local** sur le target. La rotation +PI/2 sur X permute
Y et Z de telle façon que l'axe +Y local pointe **antiparallèle** à target. Résultat :
`ShapeCast3D.target_position = basis.inverse() * sweep_delta` propage une inversion
180° → tunneling garanti dès que `aim_forward != Vector3(0, 0, -1)`.

Ce bug a été découvert lors de la review r5.2 du GDD player-combat-system (CONV-1) et
corrigé en r6. Cf. ADR-0006 D-7.

### Guards

| Cas | Comportement |
|-----|-------------|
| `forward` colinéaire `Vector3.UP` ou `DOWN` | `up_ref` bascule sur `Vector3.FORWARD` (fallback stable) |
| Déterminant quasi-singulier (< 0.001) | `push_error` + retourne `Basis.IDENTITY` |

---

## ShapeCast3D Overlap at Origin — Godot 4.6 + Jolt Empirical Test

*Gap 2 — ADR-0006 VC-GAP2 / AC-CMB-47-Prelim. Empirical test 2026-04-23.*

### Question

Quand `ShapeCast3D.target_position = Vector3.ZERO` (cas tick 0 d'un swing où
`sweep_delta = Vector3.ZERO` car `_prev_position` vient d'être initialisé), est-ce
que Jolt retourne les colliders qui **chevauchent déjà** la capsule à l'origine, ou
retourne-t-il `is_colliding() == false` ?

### Méthode

- `StaticBody3D` sphère radius=0.35 à (0,0,0), collision_layer=2.
- `ShapeCast3D` capsule radius=0.4 height=2.0, même position (0,0,0),
  `target_position = Vector3.ZERO`, `collision_mask = 2`, `exclude_parent = false`.
- `force_shapecast_update()` appelé au `_ready()`.
- Runner : `tests/performance/gap2_shapecast_origin_runner.gd`

### Résultat brut (stdout)

```
[GAP2-RESULT] variant=A origin_colliding=true origin_count=1 delta_colliding=true delta_count=1
```

### Conclusion — Variante A confirmée

Godot 4.6 + Jolt : `ShapeCast3D` retourne bien les overlaps à l'origine même avec
`target_position = Vector3.ZERO`. `is_colliding() == true`, `get_collision_count() == 1`.

**Implication ADR-0006** : `_tick0_intersect_shape_overlap()` (qui utilise
`PhysicsDirectSpaceState3D.intersect_shape()`) est une **sécurité redondante** —
le chemin unique `ShapeCast3D` couvre déjà le tick 0. Elle peut être retirée au
Sprint 1 si le test AC-CMB-47-Prelim confirme en intégration.

---

## ShapeCast3D.margin — Jolt vs GodotPhysics3D Behavior

*Gap 8 — ADR-0006 VC-GAP8. Empirical test 2026-04-23.*

### Question

`ShapeCast3D.margin` étend-il la forme détectable (détection sur approche proche
sans contact physique réel), ou Jolt l'ignore-t-il silencieusement ?

### Méthode

- `StaticBody3D` BoxShape3D 1×1×1 centré à z=-1.5 → face avant à z=-1.0.
- `ShapeCast3D` capsule radius=0.4 à z=0, `target_position = (0,0,-0.55)`.
- Capsule front final = z=-0.4-0.55 = z=-0.95 ; gap résiduel au box = 0.05 m.
- Sans marge : pas de contact attendu. Avec margin≥0.06 : contact attendu si respecté.
- Testé avec margin=0.0, 0.1, 0.2. Runner : `tests/performance/gap8_shapecast_margin_runner.gd`

### Résultat brut (stdout)

```
[GAP8-RESULT] margin=0.0 colliding=false ; margin=0.1 colliding=false ; margin=0.2 colliding=false ; baseline_valid=true ; jolt_respects_margin=false ; recommendation=margin_ignored_force_zero
```

### Conclusion — Jolt ignore ShapeCast3D.margin

Sous Godot 4.6 + Jolt, `ShapeCast3D.margin` est **ignoré** : même avec margin=0.2
(suffisant pour pénétrer le box de 0.15 m selon la géométrie du test), `is_colliding()`
retourne `false`. La baseline (margin=0.0) est correctement `false` — la géométrie
de test est valide, et la valeur de `margin` n'affecte pas le résultat.

**Recommandation pour le code Combat (ADR-0006)** : définir `shape_cast.margin = 0.0`
explicitement dans `CombatSystem._ready()` pour éviter toute dépendance sur un
comportement non-documenté. Ne pas utiliser `margin` comme levier de tuning hitbox.
