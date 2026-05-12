# Level Scene — Hiérarchie Canonique et Invariants Pré-Build

Chaque `etage_*.tscn` sous `scenes/levels/` doit respecter la hiérarchie
canonique de 4 sous-arbres top-level et passer les 11 invariants pré-build
enforced par `tools/lint/level_lint.gd`. Ces invariants garantissent la
conformité aux formules du Level GDD r2 et la compatibilité Jolt 4.6.

Tout fail d'invariant = `exit 1` CI job `lint-level-invariants`, blocking merge.
Si aucune scène `etage_*.tscn` n'existe : exit 0 (valide avant production).

## Scope

**Fichiers** : `scenes/levels/etage_*.tscn` (loader Godot 4.6, instanciation runtime).

**Hors scope** : `scenes/levels/prototypes/`, fichiers `.tscn` non-préfixés `etage_`,
tests GdUnit4 dans `tests/` (fixtures stub autorisées).

## Hiérarchie canonique (ADR-0011 D-2)

```
etage_NN.tscn (root Node3D)
├── StaticEnvironment      (Node3D — géométrie passive, layer LAYER_ENVIRONMENT=4)
│   └── Room_NN            (Node3D — rooms zeropaddées, @export archetype requis)
│       └── VerticalShaftRoom*  (si archetype == SHAFT — au moins 1)
├── InteractiveVolumes     (Node3D — triggers Area3D, layer LAYER_INTERACTIVE=5)
│   ├── RoomTrigger_NN          (Area3D — doorways via meta is_doorway=true pour F1)
│   └── WorldBoundsVolume       (Area3D + BoxShape3D obligatoire — R-5.6)
├── SpawnMarkers           (Node3D — points nommés Marker3D)
│   ├── PlayerStart             (Marker3D unique par étage — R-5.3)
│   └── CheckpointAnchor_NN     (Marker3D appairé à CheckpointVolume_NN — R-5.2)
└── EtageExitTrigger       (Area3D — fin d'étage, fires-once — AC-LVL-24)
```

**Sous-arbre optionnel (étage 1 uniquement)** :
```
OnboardingAnchors          (Node3D)
├── FirstEnemySightline    (Marker3D)
└── SafeZoneCenter         (Marker3D)
```

**Forbidden** : sous-arbres top-level hors des 4 mandatoires (`Doodads`,
`Decorations`, etc.). Ces éléments appartiennent à `StaticEnvironment/Room_NN`.
Tout ajout = amendement ADR-0011.

## Invariants Pré-Build (ADR-0011 D-7 — 11 checks)

| # | Invariant | Formule/Règle | AC |
|---|-----------|--------------|-----|
| 1 | Door width : max(size.x, size.z) ≥ 3.6 m sur RoomTrigger_NN `is_doorway=true` | F1 = 2 × KATANA_REACH (1.8 m) | AC-LVL-14 |
| 2 | Wall-run height ≥ 4.0 m, length ≥ 3.0 m, orientation ≤ ±5° | F8 = jump_apex (1.68) + vertical_reach (2.3) = 3.98 → 4.0 | AC-LVL-15 |
| 3 | Y plancher ≥ -2.0 m absolu | R-2.U.3 | AC-LVL-16 |
| 4 | PlayerStart unique (exactement 1) | R-5.3 | AC-LVL-18 |
| 5 | CheckpointVolume_NN ↔ CheckpointAnchor_NN appairé, distance ≤ 10 m | R-5.2 | AC-LVL-19 |
| 6 | N_rooms ∈ [8, 10] + espacement checkpoints floor(N_rooms/K) ∈ [2, 3] | F2/F3 | AC-LVL-20/51 |
| 7 | `archetype: RoomArchetype` @export obligatoire sur chaque Room_NN | R-2.6 | AC-LVL-52 |
| 8 | Secret tuple : Lure↔Volume↔Anchor même NN, `required_ability ∈ {none, dash, double_jump, wall_run, wall_run_long}` | R-4 r2 | AC-LVL-53 |
| 9 | Onboarding anchors étage 1 : sightline non obstruée, distance ≤ 15 m, SafeZone ≥ 6 m de EnemySlot, ≥ 4 m de HazardSlot | R-4 r2 fix #5 | AC-LVL-54 |
| 10 | Budget par archetype : DC / StaticBody3D / Area3D / Marker3D dans ranges R-4 r2 + Σ DC + 20 overhead ≤ 350 (F2) | R-4 r2 | AC-LVL-55 |
| 11 | Collision layers discipline : StaticBody3D (layer=4, mask=0), Area3D triggers (layer=5, mask⊃LAYER_PLAYER=1, monitorable=false) | ADR-0008 D-2 | AC-LVL-12/13 |

### Budgets par archetype (ADR-0011 D-13 R-4 r2)

| Archetype | DC max | StaticBody3D | Area3D | Marker3D |
|-----------|--------|-------------|--------|---------|
| TRAVERSAL (0) | 22 | 18 | 4 | 10 |
| COMBAT (1) | 38 | 32 | 10 | 30 |
| SHAFT (2) | 32 | 28 | 6 | 18 |
| SECRET_HUB (3) | 34 | 25 | 12 | 24 |

Agrégat : Σ DC_rooms + 20 (overhead fixe) ≤ 350.

### Archetype diversity (AC-LVL-50 S-1..S-5)

- **S-1** : ≥ 3 archétypes distincts sur l'étage.
- **S-2** : pas de salles COMBAT consécutives.
- **S-3** : ≥ 1 SHAFT.
- **S-4** : salle finale ∈ {SECRET_HUB, TRAVERSAL}.
- **S-5** : ≥ 1 SECRET_HUB.

### Contrainte WorldBoundsVolume (ADR-0011 REQ-9)

Tous les `Area3D` nommés `WorldBoundsVolume` utilisent **obligatoirement**
`BoxShape3D` — jamais `ConcavePolygonShape3D` ni `TrimeshShape3D`
(Jolt broad-phase O(N) sur concave, O(1) sur box).

## Enforcement

### CI (GitHub Actions)

Job `lint-level-invariants` dans `.github/workflows/tests.yml` :

1. **Build class cache** : `godot --headless --editor --quit-after 2` — prérequis
   `.godot/global_script_class_cache.cfg` (résolution `class_name` autoloads).
2. **Run lint** : `godot --headless --script tools/lint/run_level_lint.gd`
3. Exit 0 = PASS (ou 0 scène trouvée). Exit 1 = au moins 1 violation — blocking merge.

Le runner découvre toutes les `scenes/levels/etage_*.tscn`, les instancie, appelle
les 12 fonctions `validate_*()` de `tools/lint/level_lint.gd` et agrège les violations.

### Local (via GdUnit4)

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/unit/lint/ \
  --ignoreHeadlessMode
```

Pré-requis : `.godot/global_script_class_cache.cfg` existant (ouvrir le projet
une fois dans l'éditeur Godot).

### Local (runner CLI direct)

```bash
godot --headless --script tools/lint/run_level_lint.gd
```

PASS si 0 scène ou 0 violation. Sortie de chaque scène : `PASS: <path>` ou
`FAIL: <path> — N violation(s)` avec détail par violation.

### Mode warn-only (itération locale authoring)

Pour itération locale sans bloquer sur invariants marginaux (ex. salle prototype
sans archetype @export), le runner accepte en CLI `--warn-only` :
`godot --headless --script tools/lint/run_level_lint.gd --warn-only`
(CI reste strict, sans ce flag).

## Pattern recommandé

### Hiérarchie scène minimale valide (authoring)

```
etage_01.tscn
└── Node3D (root)
    ├── StaticEnvironment (Node3D)
    │   ├── Room_01 (Node3D, @export archetype = TRAVERSAL)
    │   ├── Room_02 (Node3D, @export archetype = COMBAT)
    │   ├── Room_03 (Node3D, @export archetype = SHAFT)
    │   │   └── VerticalShaftRoom (instance)
    │   └── ... (Room_04..Room_08)
    ├── InteractiveVolumes (Node3D)
    │   ├── RoomTrigger_01 (Area3D, meta is_doorway=true si doorway)
    │   └── WorldBoundsVolume (Area3D + BoxShape3D)
    ├── SpawnMarkers (Node3D)
    │   └── PlayerStart (Marker3D — unique)
    └── EtageExitTrigger (Area3D)
```

### Collision layers discipline (AC-LVL-12/13)

```gdscript
# CORRECT — StaticBody3D sous StaticEnvironment
func _ready() -> void:
    set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)  # layer 4
    collision_mask = 0  # géométrie statique ne détecte rien

# CORRECT — Area3D sous InteractiveVolumes
func _ready() -> void:
    set_collision_layer_value(CollisionLayersScript.LAYER_INTERACTIVE, true)  # layer 5
    monitorable = false  # signal-only, pas de détection inverse
    monitoring = true   # détecte les corps entrants
    set_collision_mask_value(CollisionLayersScript.LAYER_PLAYER, true)  # détecte joueur
```

## Source

- ADR-0011 D-2 (hiérarchie canonique 5 groupes) + D-7 (11 invariants pré-build)
  + D-13 (budgets par archetype R-4 r2) + REQ-2/REQ-6/REQ-9
  — `docs/architecture/adr-0011-level-scene-architecture.md`
- ADR-0008 D-1/D-2/D-3 (collision layer discipline)
  — `docs/architecture/adr-0008-collision-layer-taxonomy.md`
- Level GDD r2 §R-1/R-2/R-4/R-5, Formules F1/F2/F3/F8
  — `design/gdd/level-system.md`
- TR-lvl-006 (hiérarchie canonique), TR-lvl-007 (LAYER_ENVIRONMENT), TR-lvl-008 (LAYER_INTERACTIVE)
- TR-lvl-010 (door width F1), TR-lvl-011 (wall-run F8), TR-lvl-013 (StaticBody3D count)
- TR-lvl-019 (wall thickness EC-8), TR-lvl-039 (wall-run length)
- Story-010 AC-LVL-11, Story-011 AC-LVL-50/52/52b, Story-012 AC-LVL-55,
  Story-013 AC-LVL-12/13/17, Story-014 AC-LVL-14/15
- `tools/lint/level_lint.gd` + `tools/lint/run_level_lint.gd`
