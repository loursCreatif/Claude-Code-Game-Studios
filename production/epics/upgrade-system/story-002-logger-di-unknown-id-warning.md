# Story 002: Logger DI + Unknown Id Warning

> **Epic**: upgrade-system
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-9 (id inconnu → `push_warning` + early return), AC-UPG-10/11 (Logger DI pattern pour testabilité).

**ADR Governing Implementation** : ADR-0007 GameStateManager + Scene Transition (D-4 `PROCESS_MODE_ALWAYS`).
**ADR Decision Summary** : pas d'ADR Logger spécifique — le pattern Logger DI est documenté GDD r2 B-11 amendement et appliqué uniquement Upgrade (substitution `push_warning(msg)` direct → `_logger.warn(msg)` testable).

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : GUT 4 n'expose pas de hook natif sur `push_warning` (engine-level). DI via `RefCounted` sub-class capture `Array[String]` est le seul pattern testable confirmé godot-specialist B-11.

**Control Manifest Rules (Feature Layer)** :
- Required : `_logger.warn(msg)` au lieu de `push_warning(msg)` direct dans le code production Upgrade. Default `_logger` = wrapper `push_warning` (production behavior identique).
- Forbidden : appel direct `push_warning(...)` dans `apply_upgrade` body et `_ready()` body — AC-UPG-10 grep le détecterait sinon.

---

## Acceptance Criteria

- [x] **AC-UPG-10** : Logger DI capture warning unknown id ; message contient `"unknown"` ou `"inconnu"` ET substring `id` ; aucun flag ne mute ; `get_owned_count() == 0`.
- [x] **AC-UPG-11** : `apply_upgrade(StringName(""))` ne crash pas, capture ≥ 1 warning, aucun flag ne mute.

---

## Implementation Notes

### Default Logger wrapper (production)

```gdscript
# src/gameplay/upgrade/upgrade_logger.gd
class_name UpgradeLogger
extends RefCounted

func warn(msg: String) -> void:
    push_warning(msg)
```

### Injection point dans UpgradeSystem

```gdscript
var _logger: UpgradeLogger = null

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if _logger == null:
        _logger = UpgradeLogger.new()    # default production logger
    # ... boot hydration story 005

# Test setter (debug-only, pas exposé à code production)
func set_logger_for_test(logger: UpgradeLogger) -> void:
    assert(OS.has_feature("debug"), "set_logger_for_test forbidden in release")
    _logger = logger
```

### Warning emission dans apply_upgrade

Story 003 utilisera `_logger.warn(...)` à l'étape 1 :
```gdscript
func apply_upgrade(id: StringName) -> void:
    if not _CATALOG.has(id):
        _logger.warn("UpgradeSystem: unknown upgrade id '%s'" % id)
        return
    # ... reste story 003/004
```

### Test fixture

```gdscript
# tests/helpers/test_upgrade_logger.gd
class_name TestUpgradeLogger
extends UpgradeLogger

var captured_warnings: Array[String] = []

func warn(msg: String) -> void:
    captured_warnings.append(msg)
```

`set_logger_for_test()` est appelé en `before_each` test, `_logger = null` en `after_each` (autoload reset, mais on travaille typiquement sur instance bare ici donc cleanup naturel via `queue_free`).

---

## Out of Scope

- **Story 003** : implémentation complète `apply_upgrade` body (cette story livre uniquement le logger + step 1 unknown id).
- **Story 005** : warnings dans `_ready()` boot hydration (utiliseront le même `_logger`).
- ADR Logger générique cross-system : non requis MVP (autres systèmes utilisent `push_warning` direct ; pas de pattern global).

---

## QA Test Cases

**AC-UPG-10** — Unit test
- Given : `var s = UpgradeSystem.new()` ; `var log = TestUpgradeLogger.new()` ; `s.set_logger_for_test(log)` ; `s._ready()` mocké pour skip hydration (ou laisser hydration default `[]`).
- When : `s.apply_upgrade(&"nonexistent_id")`.
- Then : `log.captured_warnings.size() == 1` ET `log.captured_warnings[0]` contient `"unknown"` OU `"inconnu"` ET contient substring `"nonexistent_id"`. `s.can_air_jump == false`, `s.can_dash == false`, `s.can_wall_run == false`. `s.get_owned_count() == 0`.
- Edge : id avec accents (`&"capacité_inconnue"`) — comportement identique (R-9 + EC-8).

**AC-UPG-11** — Unit test
- Given : `var s = UpgradeSystem.new()` ; logger DI injecté.
- When : `s.apply_upgrade(StringName(""))`.
- Then : aucun crash levé. `log.captured_warnings.size() >= 1`. Aucun flag muté.
- Edge : `apply_upgrade(StringName())` (StringName uninit, équivalent `&""`) — comportement identique.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/upgrade/logger_di_warning_test.gd` couvrant AC-UPG-10 + AC-UPG-11 (instance bare, logger fixture injecté).
**Status** : [x] Created and passing — `tests/unit/upgrade/logger_di_warning_test.gd` (2/2 PASSED 29ms — `reports/report_178`)

---

## Dependencies

- Depends on : Story 001 (autoload skeleton existe + `_ready()` set process_mode).
- Unlocks : 003 (apply_upgrade utilise `_logger.warn` step 1), 005 (boot hydration utilise `_logger.warn` pour ids inconnus + corrupt save).

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: 2/2 passing (AC-UPG-10 unknown id warning + AC-UPG-11 empty StringName no-crash) — covered by `tests/unit/upgrade/logger_di_warning_test.gd`.
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/upgrade/logger_di_warning_test.gd` (PASSED dans suite globale 41/41 447 ms).
**Code Review**: Skipped (Solo mode).
