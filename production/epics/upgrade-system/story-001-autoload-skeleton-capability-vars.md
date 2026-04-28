# Story 001: Autoload Skeleton + Capability Vars + process_mode

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-1 (autoload), R-UPG-2 (3 vars publics typés), R-UPG-11 (ordre autoload `InputManager → GSM → SaveLoad → Audio → UpgradeSystem`).

**ADR Governing Implementation** : ADR-0007 GameStateManager + Scene Transition.
**ADR Decision Summary** : D-1 ordre canonique des autoloads + D-4 `PROCESS_MODE_ALWAYS` pour autoloads pause-resilient + D-9 GSM init MENU sans transition synchrone (garantit que tous les `_ready()` autoload se terminent avant le premier `start_etage`).

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `Node.PROCESS_MODE_ALWAYS` API stable Godot 4.x. `process_mode` declaré programmatiquement dans `_ready()` (R-UPG-18 r2 — pas de `.tscn` autoload).

**Control Manifest Rules (Feature Layer)** :
- Required : autoload registré dans `project.godot` après `SaveLoadSystem` (contrainte stricte unique R-UPG-11 + AC-UPG-3).
- Forbidden : aucune dépendance Movement/Combat/Shop/HUD côté Upgrade (anti-deps cf. epic § Anti-deps).
- Guardrail : `_ready()` < 1 ms headless CI (cf. story 010 AC-UPG-40).

---

## Acceptance Criteria

- [ ] **AC-UPG-1** : `Upgrade` global non-null, `Upgrade is UpgradeSystem` retourne `true` depuis n'importe quel script.
- [ ] **AC-UPG-2** : `can_air_jump`, `can_dash`, `can_wall_run` lus avant tout `apply_upgrade` retournent `false` ; `typeof(x) == TYPE_BOOL` pour les trois.
- [ ] **AC-UPG-3** [BLOCKING strict] : `index("SaveLoadSystem") < index("UpgradeSystem")` dans `project.godot`.
- [ ] **AC-UPG-3-bis** [ADVISORY] : ordre canonique complet `InputManager → GSM → SaveLoadSystem → AudioSystem → UpgradeSystem`.
- [ ] **AC-UPG-4** : `Upgrade.process_mode == Node.PROCESS_MODE_ALWAYS` après `_ready()`.

---

## Implementation Notes

Créer `src/gameplay/upgrade/upgrade_system.gd` (autoload script-only, pas de `.tscn`) :

```gdscript
extends Node
class_name UpgradeSystem

var can_air_jump: bool = false
var can_dash: bool = false
var can_wall_run: bool = false

var _owned: Dictionary = {}                # {StringName: bool}
const _CATALOG: Dictionary = {
    &"double_jump":     &"can_air_jump",
    &"dash_horizontal": &"can_dash",
}
const MAX_CATALOG_SIZE_TIER_2: int = 7

var _is_hydrated: bool = false             # observable transition test (story 005)
var _logger: Object = null                 # injected story 002

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # apply_upgrade + boot hydration câblés stories 003/005.
```

Enregistrer dans `project.godot` autoloads après `SaveLoadSystem`, avant la fin de la liste Foundation. Nom autoload exact : `Upgrade` (l'identifiant global utilisé partout dans la GDD est `Upgrade`, pas `UpgradeSystem`).

Ne **PAS** ajouter de logique `apply_upgrade` ni hydration ici — stories 003/005 les implémentent.

---

## Out of Scope

- **Story 002** : injection Logger + warning unknown id.
- **Story 003** : helper `_apply_flag` + body `apply_upgrade`.
- **Story 005** : boot hydration `_ready()` post-process_mode.
- **Story 006** : truncation save bloat.

---

## QA Test Cases

**AC-UPG-1** — Integration test
- Given : projet booté avec autoloads canoniques.
- When : un script accède à l'identifiant global `Upgrade`.
- Then : `Upgrade != null` ET `Upgrade is UpgradeSystem == true`.
- Edge : test exécuté depuis autre autoload (post-`_ready()` des deps) ET depuis scène gameplay.

**AC-UPG-2** — Unit test
- Given : `var s = UpgradeSystem.new()` (instance bare, pas autoload).
- When : lecture `s.can_air_jump`, `s.can_dash`, `s.can_wall_run` avant tout `apply_upgrade`.
- Then : trois retours `== false` ET `typeof(s.can_air_jump) == TYPE_BOOL` (idem dash/wall_run).

**AC-UPG-3 / AC-UPG-3-bis** — Integration test
- Given : parse `project.godot` (lecture brute du `[autoload]` block).
- When : extraire l'ordre des clés autoload.
- Then BLOCKING : `index("SaveLoadSystem") < index("UpgradeSystem")`.
- Then ADVISORY : ordre exact `["InputManager", "GameStateManager", "SaveLoadSystem", "AudioSystem", "UpgradeSystem"]` (sequence-equality).

**AC-UPG-4** — Unit test
- Given : autoload `Upgrade` initialisé.
- When : lecture `Upgrade.process_mode` post-`_ready()`.
- Then : `== Node.PROCESS_MODE_ALWAYS` (valeur `4` constante Godot 4.6).

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/upgrade/autoload_skeleton_test.gd` — must exist and pass (AC-UPG-1 + AC-UPG-3 + AC-UPG-3-bis + AC-UPG-4) + un test unit `tests/unit/upgrade/capability_vars_default_test.gd` (AC-UPG-2 sur instance bare).
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : ADR-0007 Accepted ✅, SaveLoad autoload existing in `project.godot` (Save/Load epic Sprint 1 prerequisite — vérifier que `SaveLoadSystem` est bien registré avant de positionner Upgrade après).
- Unlocks : 002, 003, 008.
