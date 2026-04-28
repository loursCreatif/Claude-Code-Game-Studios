# Story 003: `_apply_flag` Helper + `apply_upgrade` SYNC Idempotent (Cas A/B)

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-4 (`apply_upgrade` SYNC idempotent steps 1+3+4) + Section C.1 helper `_apply_flag(flag_name)` (3 asserts : existence + `typeof == TYPE_BOOL` + post-set), R-UPG-13 (capabilities indépendantes), R-UPG-14 (single responsibility — pas de coût/persistance/UI).

**ADR Governing Implementation** : ADR-0001 Physics Rate 60 Hz (le call stack Shop → Upgrade reste SYNC dans le même tick `_physics_process`, pas d'`await`).
**ADR Decision Summary** : Movement lit `Upgrade.can_*` à 60 Hz pull dans `_physics_process` ; conséquence stricte : `apply_upgrade` doit être SYNC pour que la mutation soit visible au tick suivant sans race intermediate.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `set(flag_name, value)` reflection bypasse le static type checker GDScript 4.6 (B-3 review). Le helper `_apply_flag` centralise les guards runtime via `get_property_list()` + `typeof()` + assert post-set. `assert` strippé en build release — admis Tier 1 (R-UPG-9 path warning absorbe partiellement).

**Control Manifest Rules (Feature Layer)** :
- Required : tous les sets de capability flag passent par `_apply_flag(flag_name)` (pas de `set(flag_name, true)` direct ni `can_air_jump = true` hardcodé dans `apply_upgrade`).
- Forbidden : `await` ou `yield` dans le body de `apply_upgrade` (R-UPG-4 SYNC contract — AC-UPG-12 grep statique le verrouille).
- Guardrail : `apply_upgrade` médiane < 100 µs sur 1000 calls headless CI (story 010 AC-UPG-41).

---

## Acceptance Criteria

- [ ] **AC-UPG-7** : `apply_upgrade(&"double_jump")` depuis état clean → `can_air_jump == true` ET `is_owned(&"double_jump") == true`.
- [ ] **AC-UPG-8** : `apply_upgrade(&"dash_horizontal")` depuis état clean → `can_dash == true` ET `is_owned(&"dash_horizontal") == true`.
- [ ] **AC-UPG-9** : double-call `apply_upgrade(&"double_jump")` → `can_air_jump` reste `true`, `get_owned_count() == 1`, aucun warning émis.
- [ ] **AC-UPG-12** [grep statique] : zéro `\bawait\b|\byield\b` dans le body de `apply_upgrade` (lignes commentaires `^\s*#` exclues).
- [ ] **AC-UPG-12-bis** [ADVISORY] : wall-clock < 1 µs moyenne sur 100 calls (preuve indirecte SYNC + idempotence).
- [ ] **AC-UPG-13** : après `apply_upgrade(&"double_jump")`, `is_owned(&"double_jump") == true` ET `get_owned_count() == 1`.
- [ ] **AC-UPG-14** : `apply_upgrade(&"double_jump")` n'affecte pas `can_dash` ni `can_wall_run` (independance R-UPG-13).

---

## Implementation Notes

### Helper `_apply_flag(flag_name)` — Section C.1 GDD

```gdscript
## Applique `true` à la propriété booléenne identifiée par [param flag_name].
## Validation runtime : la propriété doit exister, doit être de type `bool`, et le
## set() doit prendre effet (assert post-set).
## Source : r2 review B-3 adjudication creative-director.
func _apply_flag(flag_name: StringName) -> void:
    var props: Array[StringName] = []
    for p in get_property_list():
        if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
            props.append(p.name)
    assert(flag_name in props,
           "UpgradeSystem._apply_flag: catalog points to unknown property '%s' (catalog/source desync — F-UPG-3 should have caught this in CI)" % flag_name)

    var current_type: int = typeof(get(flag_name))
    assert(current_type == TYPE_BOOL,
           "UpgradeSystem._apply_flag: catalog target '%s' is not bool (typeof=%d) — Tier 2+ var declared with wrong type ?" % [flag_name, current_type])

    set(flag_name, true)

    assert(get(flag_name) == true,
           "UpgradeSystem._apply_flag: set(%s, true) failed silently — property may be read-only or shadowed" % flag_name)
```

### Body `apply_upgrade` — R-UPG-4 steps 1, 3, 4 (Cas A/B)

```gdscript
## Applique un upgrade identifié par [param id].
## SYNC — aucun await ni yield. Idempotent — deux appels même id = même état.
func apply_upgrade(id: StringName) -> void:
    # Step 1 : id validation (Logger DI story 002)
    if not _CATALOG.has(id):
        _logger.warn("UpgradeSystem: unknown upgrade id '%s'" % id)
        return

    var flag_name: StringName = _CATALOG[id]

    # Step 2 (story 004 implémente le guard resync complet) — version cas A/B :
    if _owned.has(id) and get(flag_name) == true:
        return    # Cas B idempotent strict

    # Step 3 : marquer owned (idempotent au niveau Dictionary)
    _owned[id] = true

    # Step 4 : appliquer le flag via helper validé
    _apply_flag(flag_name)


## Retourne true si [param id] est possédé, false sinon.
func is_owned(id: StringName) -> bool:
    return _owned.has(id)


## Retourne le nombre total d'upgrades possédés. Debug-only.
func get_owned_count() -> int:
    return _owned.size()
```

### Note Cas C/D resync

Le step 2 livré ici **ne couvre que les cas A (nominal) et B (idempotent strict)**. Les cas C (resync `_owned=true ∧ flag=false`) et D (resync inverse) sont implémentés dans **Story 004** (AC-UPG-9-bis BLOCKING). Le test AC-UPG-9-bis échouera tant que story 004 n'est pas mergée — c'est attendu.

### Grep statique AC-UPG-12

Test bash :
```bash
awk '/^func apply_upgrade\(/,/^func [a-z]/' src/gameplay/upgrade/upgrade_system.gd \
  | grep -nE '\bawait\b|\byield\b' \
  | grep -v '^[0-9]*:\s*#' \
  || echo "CLEAN"
```
Zéro match non-commenté = pass.

### Wall-clock AC-UPG-12-bis

```gdscript
var t0 := Time.get_ticks_usec()
for i in 100:
    s.apply_upgrade(&"double_jump")    # idempotent — 99 early returns
var elapsed_us := Time.get_ticks_usec() - t0
assert_lt(elapsed_us / 100.0, 1.0)    # < 1 µs moyenne
```

---

## Out of Scope

- **Story 002** : Logger DI (déjà implémenté — cette story le consomme).
- **Story 004** : R-UPG-4 step 2 guard resync cas C/D (AC-UPG-9-bis).
- **Story 005** : appel `apply_upgrade` dans boot hydration `_ready()`.
- **Story 008** : `_apply_flag` validé build-time par F-UPG-3 catalog sanity (test runtime équivalent ici via `_apply_flag` asserts).

---

## QA Test Cases

**AC-UPG-7 / AC-UPG-8 / AC-UPG-13 / AC-UPG-14** — Unit tests
- Given : `var s = UpgradeSystem.new()` (instance bare propre, état initial false × 3, `_owned == {}`).
- When : `s.apply_upgrade(&"double_jump")` (AC-7) puis assertions ; rerun avec `&"dash_horizontal"` (AC-8).
- Then AC-7 : `s.can_air_jump == true` ET `s.is_owned(&"double_jump") == true` ET `s.can_dash == false` ET `s.can_wall_run == false` (AC-14 indépendance).
- Then AC-8 : `s.can_dash == true` ET `s.is_owned(&"dash_horizontal") == true`.
- Then AC-13 : `s.get_owned_count() == 1` après chaque call simple.

**AC-UPG-9** — Unit test
- Given : `s.apply_upgrade(&"double_jump")` déjà appelé (état post-AC-7).
- When : `s.apply_upgrade(&"double_jump")` rappelé.
- Then : `s.can_air_jump == true` (no-op silencieux), `s.get_owned_count() == 1`, `_logger.captured_warnings.size() == 0` (no warning).
- Edge : 100 calls successifs même id → `get_owned_count() == 1`, perf < 100 µs total.

**AC-UPG-12** — Static lint test
- Given : fichier `src/gameplay/upgrade/upgrade_system.gd` parsé.
- When : extraction body `apply_upgrade` (awk `^func apply_upgrade(` jusqu'au prochain `^func [a-z]`) puis grep `\bawait\b|\byield\b` excluant `^\s*#`.
- Then : zéro match. Pass condition : exit 1 du grep (no match).

**AC-UPG-12-bis** — Perf unit test [ADVISORY]
- Given : autoload Upgrade initialisé.
- When : 100 calls `apply_upgrade(&"double_jump")` séquentiels.
- Then : `(t1-t0) / 100 < 1.0 µs`. Pass tolérant — ADVISORY, ne block pas merge.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/upgrade/apply_upgrade_test.gd` (AC-UPG-7/8/9/13/14) + `tests/unit/upgrade/apply_upgrade_perf_test.gd` (AC-UPG-12-bis) + `tests/static/apply_upgrade_no_await_test.gd` ou shell script CI (AC-UPG-12).
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 001 (autoload + capability vars), 002 (`_logger.warn` API).
- Unlocks : 004 (resync guard sur step 2 existant), 005 (boot hydration appelle `apply_upgrade`), 007 (Movement pull verifies flags mutés), 010 (perf budget mesure ce body).
