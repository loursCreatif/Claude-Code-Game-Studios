# Story 005: Boot Hydration `_ready()` via SaveLoad

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-5 steps 1 + 3 + 4 (load_string_array → boucle apply_upgrade → `_is_hydrated = true`), R-UPG-9 (id inconnu warning), R-UPG-10 (Upgrade ne persiste jamais), F-UPG-2 boot hydration sequence INVARIANT D'ORDRE, EC-UPG-1/2/3/4/15/16/17/19.

**ADR Governing Implementation** : ADR-0010 Save/Load Persistence (ConfigFile Ratification) — Accepted 2026-04-27.
**ADR Decision Summary** : `SaveLoad.load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` (R-SAV-4). Corruption type retourne default + push_warning (R-SAV-12 + EC-SAV-8). Upgrade ne persiste jamais (R-UPG-10) — seul Shop écrit la clé `"owned_upgrades"`.

**Engine** : Godot 4.6 | **Risk** : MEDIUM (ADR-0010 inherit) — médium parce que dépendance externe SaveLoad autoload + interaction ConfigFile native Godot. Risk Upgrade-side reste LOW (pure consumer).
**Engine Notes** : Godot 4.6 garantit que tous les autoloads `_ready()` s'exécutent séquentiellement avant le démarrage de toute scène (ADR-0007 D-9). `Array[StringName]` typage strict évite coercion silencieuse (B14 review r1).

**Control Manifest Rules (Feature Layer)** :
- Required : `_is_hydrated = true` à la dernière ligne de `_ready()` (post-boucle hydration). Default = `[]` MVP.
- Forbidden : `SaveLoad.save_*` ou `SaveLoad.write_*` n'importe où dans `upgrade_system.gd` (R-UPG-10 — verrouillé par AC-UPG-28 grep static, story 009).

---

## Acceptance Criteria

- [ ] **AC-UPG-5** : instance bare + mock SaveLoad `[]` ; observable `_is_hydrated == false` avant `_ready()`, `== true` après ; trois flags restent `false`.
- [ ] **AC-UPG-16** : mock `[]` → `can_*` tous `false`, `get_owned_count() == 0`.
- [ ] **AC-UPG-17** : mock `[&"double_jump"]` → `can_air_jump == true`, `can_dash == false`.
- [ ] **AC-UPG-18** : mock `[&"double_jump", &"dash_horizontal"]` → `can_air_jump == true` ET `can_dash == true`.
- [ ] **AC-UPG-19** : mock `[&"double_jump", &"unknown_id_xyz"]` + Logger DI → `can_air_jump == true`, `can_dash == false`, ≥1 warning contient `"unknown_id_xyz"`, no crash.
- [ ] **AC-UPG-20** : mock retourne non-Array (ex. `null` ou `"corrupted"`) → fallback `[]`, no crash, ≥1 warning contient `"corrupt"`.
- [ ] **AC-UPG-21** : mock `[&"double_jump", &"double_jump"]` → `can_air_jump == true`, `get_owned_count() == 1` (idempotence absorbe doublon).
- [ ] **AC-UPG-22** : mock `[&"double_jump", 42, null, "string_plain"]` → seul `&"double_jump"` matche, `get_owned_count() == 1`, autres skippés via R-UPG-9.
- [ ] **AC-UPG-23** : observation `_is_hydrated` mid-execution → `false` pendant boucle, `true` uniquement après dernier `apply_upgrade`.
- [ ] **AC-UPG-30** : session avec upgrades sauvegardée puis reload → flags restaurés identiquement post-`_ready()`.
- [ ] **AC-UPG-42** : signature publique `SaveLoad.load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` vérifiée (locked R-SAV-4).
- [ ] **AC-UPG-43** : clé absente → `[]` retourné, no exception, no error log.

---

## Implementation Notes

### Body `_ready()` complet (story 001 + 002 + 005, sans truncation story 006)

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    if _logger == null:
        _logger = UpgradeLogger.new()

    # Step 1 : load via SaveLoad (R-UPG-5 step 1)
    var owned: Variant = SaveLoad.load_string_array("owned_upgrades", [] as Array[StringName])

    # EC-UPG-3 type guard : si SaveLoad retourne autre chose qu'un Array (corrupt save), fallback []
    if not (owned is Array):
        _logger.warn("UpgradeSystem: load_string_array returned non-Array (corrupt save), fallback to empty")
        owned = [] as Array[StringName]

    # Step 2 truncation : implémenté story 006 — placeholder pour ordre.

    # Step 3 : boucle apply_upgrade idempotent (story 003)
    for id in owned:
        apply_upgrade(id)

    # Step 4 : flag d'hydration (R-1 rename)
    _is_hydrated = true
```

### Test fixtures — mock SaveLoad

```gdscript
# tests/helpers/mock_save_load.gd
class_name MockSaveLoad
extends Node

var return_value: Variant = [] as Array[StringName]

func load_string_array(key: String, default: Array[StringName]) -> Variant:
    if key == "owned_upgrades":
        return return_value
    return default
```

Injection via `Engine.register_singleton("SaveLoad", mock)` en `before_each`, `Engine.unregister_singleton("SaveLoad")` en `after_each` (Godot 4.1+ API confirmée godot-specialist r1.2 — voir EC-UPG-32).

### Pattern test instance bare AC-UPG-5

```gdscript
func test_is_hydrated_transition() -> void:
    var mock := MockSaveLoad.new()
    Engine.register_singleton("SaveLoad", mock)

    var s := UpgradeSystem.new()
    add_child(s)    # pas autoload — instance bare
    # PAS encore _ready() invoqué automatiquement par Godot car add_child triggers _ready

    # Note implémentation : dans Godot 4.6, add_child() fait _ready() immédiatement
    # → l'observation false → true requiert override _ready() en test ou
    # introspection __debug__ via override dans une sous-classe TestUpgradeSystem.
    # Voir doc helper tests/helpers/observable_upgrade_system.gd

    assert_eq(s._is_hydrated, true)    # post add_child, _ready() done
    assert_eq(s.can_air_jump, false)
    assert_eq(s.can_dash, false)
    assert_eq(s.can_wall_run, false)

    s.queue_free()
    Engine.unregister_singleton("SaveLoad")
```

Pour AC-UPG-5 transition observable : créer `tests/helpers/observable_upgrade_system.gd extends UpgradeSystem` qui override `_ready()` avec un signal `pre_hydration_started` / `post_hydration_complete` purement test pour mesurer le flag aux deux instants.

### AC-UPG-23 mid-execution observation

Helper test override de `apply_upgrade` qui asserte `_is_hydrated == false` à chaque call dans la boucle :

```gdscript
class TestObservableUpgrade extends UpgradeSystem:
    var observed_hydration_during_loop: Array[bool] = []
    func apply_upgrade(id: StringName) -> void:
        observed_hydration_during_loop.append(_is_hydrated)
        super.apply_upgrade(id)
```

Run avec mock retournant 2-3 ids → assert `observed == [false, false, false]`, post-`_ready()` `_is_hydrated == true`.

---

## Out of Scope

- **Story 006** : truncation save bloat step 2 (`if owned.size() > 14`).
- **Story 003/004** : `apply_upgrade` body (déjà implémenté — cette story consomme).
- **Story 002** : Logger DI (déjà implémenté — utilisé pour AC-19/20).
- Migration tool save renaming (EC-UPG-19 — Tier 2+ scope, hors MVP).

---

## QA Test Cases

**AC-UPG-5 / AC-UPG-23** — Integration test (instance bare + observable subclass)
- Given : `TestObservableUpgrade` + mock SaveLoad return `[&"double_jump", &"dash_horizontal"]`.
- When : `add_child(s)` (triggers `_ready()`).
- Then AC-5 : `_is_hydrated` observable `false → true` post-`_ready()`, mid-execution `false`.
- Then AC-23 : `observed_hydration_during_loop == [false, false]` puis post `_ready() → true`.

**AC-UPG-16** — Integration test
- Given : mock SaveLoad return `[]`.
- When : `s._ready()` exécuté.
- Then : `s.can_air_jump == false ∧ s.can_dash == false ∧ s.can_wall_run == false`, `s.get_owned_count() == 0`, `s._is_hydrated == true`.

**AC-UPG-17 / AC-UPG-18 / AC-UPG-21 / AC-UPG-22** — Integration tests paramétrés
- Sweep mock returns : `[&"double_jump"]` / `[&"double_jump", &"dash_horizontal"]` / `[&"double_jump", &"double_jump"]` / `[&"double_jump", 42, null, "string_plain"]`.
- Then : flags + `get_owned_count()` matchent table GDD.

**AC-UPG-19** — Integration test [Logger DI]
- Given : Logger DI injecté + mock return `[&"double_jump", &"unknown_id_xyz"]`.
- When : `s._ready()`.
- Then : `s.can_air_jump == true`, `s.can_dash == false`, `_logger.captured_warnings.size() >= 1`, ≥1 warning contient substring `"unknown_id_xyz"`, aucun crash.

**AC-UPG-20** — Integration test [corrupt save]
- Given : Logger DI + mock retournant `null` puis re-test avec `"corrupted_string"`.
- When : `s._ready()` chaque cas.
- Then : aucun crash, fallback `[]`, ≥1 warning contient `"corrupt"`, tous les flags `false`.

**AC-UPG-30** — Integration test (true save round-trip via Save/Load réel)
- Given : SaveLoad réel ; appel `SaveLoad.save_string_array("owned_upgrades", [&"double_jump"])` (simule Shop).
- When : nouvelle instance Upgrade `_ready()` re-lit la save.
- Then : `Upgrade.can_air_jump == true` (round-trip Shop write → Upgrade read).
- Edge : test cleanup save file post-test.

**AC-UPG-42 / AC-UPG-43** — Static/Integration test
- AC-42 : reflection sur `SaveLoad.load_string_array` signature → params `(key: String, default: Array[StringName])`, return type `Array[StringName]`.
- AC-43 : mock SaveLoad clé absente → retourne `default == []`, no exception, no error log.

---

## Test Evidence

**Story Type** : Integration
**Required evidence** :
- `tests/integration/upgrade/boot_hydration_test.gd` couvrant AC-5/16/17/18/19/20/21/22/23/43.
- `tests/integration/upgrade/saveload_round_trip_test.gd` couvrant AC-30 (real SaveLoad).
- `tests/integration/upgrade/saveload_signature_test.gd` couvrant AC-42 (reflection).

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 001 (autoload), 002 (Logger DI), 003 (`apply_upgrade` body), Save/Load epic R-SAV-4 implémenté + autoload registré dans `project.godot`.
- Unlocks : 006 (truncation step 2 dans `_ready()` body livré ici), 007 (Movement pull verifies post-boot state), 009 (anti-pattern grep `SaveLoad.save_*` zero — testé directement, mais cette story a livré le seul `SaveLoad.*` autorisé).
