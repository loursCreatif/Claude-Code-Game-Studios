# Story 004: `apply_upgrade` Step 2 Resync Guard (Cas C/D)

> **Epic**: upgrade-system
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-4 step 2 r2 amendement B-4 (`_owned.has(id) AND get(flag_name) == true` — les **deux** vrais → return ; sinon resync). EC-UPG-13 (mutation externe), EC-UPG-14 (désynchro résiduelle), EC-UPG-5 (hot-reload Godot editor).

**ADR Governing Implementation** : ADR-0001 Physics Rate 60 Hz (le resync continue en SYNC dans le même call stack — pas d'`await` ajouté).
**ADR Decision Summary** : aucun ADR Upgrade-spécifique requis. Le helper `_apply_flag` (story 003) absorbe le re-set idempotent par construction.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `get(flag_name)` retourne `Variant`, comparé à `true` literal — coercion booléenne implicite GDScript 4.6 attendue. Pas de risque de drift API.

**Control Manifest Rules (Feature Layer)** :
- Required : guard step 2 `_owned.has(id) AND get(flag_name) == true` (les **deux** vrais → return). Toute désynchro tombe dans steps 3-4.
- Forbidden : early return strict r1 (`if _owned.has(id): return`) — c'était la formulation r1 que la review B-4 a rejetée. Toute future PR qui retourne au strict-has = régression bloquée par AC-UPG-9-bis.

---

## Acceptance Criteria

- [ ] **AC-UPG-9-bis** [BLOCKING] : injection désync `_owned[id]=true ∧ flag=false` ; `apply_upgrade(id)` resync `flag → true`.

---

## Implementation Notes

### Patch sur le body `apply_upgrade` (modifie story 003 step 2)

Remplacer dans `apply_upgrade` :

```gdscript
# Avant (story 003 stub) :
if _owned.has(id) and get(flag_name) == true:
    return    # Cas B idempotent strict
```

par la version **r2 finale** documentant les 4 cas :

```gdscript
# Step 2 r2 (B-4 reconciliation EC-UPG-14)
# Guard : les DEUX vrais → no-op silencieux (Cas B idempotent strict).
# Sinon (l'un est false), continuer steps 3-4 pour FORCER la re-synchronisation.
# Le helper _apply_flag est idempotent par construction (set true sur déjà-true reste true).
if _owned.has(id) and get(flag_name) == true:
    return
# Cas A (nominal premier achat) : _owned=false ∧ flag=false → continue
# Cas C (resync GDScript→bool) : _owned=true ∧ flag=false → continue (re-set flag)
# Cas D (resync inverse) : _owned=false ∧ flag=true → continue (re-set _owned, flag stays true)
```

### Mécanisme de test injection désync

Sur instance bare (pas autoload réel) :

```gdscript
var s := UpgradeSystem.new()
add_child_autofree(s)
# Pas de _ready() — ou s._ready() puis on désynchronise manuellement :
s._owned[&"double_jump"] = true
s.can_air_jump = false        # mutation externe directe (EC-UPG-13)
assert_eq(s._owned.has(&"double_jump"), true)
assert_eq(s.can_air_jump, false)

# Action testée :
s.apply_upgrade(&"double_jump")

# Resync forcé :
assert_eq(s.can_air_jump, true)             # flag re-synchronisé
assert_eq(s._owned.has(&"double_jump"), true)
assert_eq(s.get_owned_count(), 1)
```

### Couverture des 4 cas R-UPG-4 r2

Étoffer le test pour vérifier les 4 cas de la table GDD :
- **Cas A** : `_owned={}` + `flag=false` → continue, both → true. (Couvert AC-UPG-7 story 003.)
- **Cas B** : `_owned={id}` + `flag=true` → early return. (Couvert AC-UPG-9 story 003.)
- **Cas C** : `_owned={id}` + `flag=false` → continue, flag → true. (NEW — AC-UPG-9-bis.)
- **Cas D** : `_owned={}` + `flag=true` → continue, _owned → {id}, flag stays true. (Pathologique mais couvert défense en profondeur.)

### Note sur la non-détection runtime de désync

Cette story résout le resync **via le path `apply_upgrade`** (re-call). Elle ne détecte PAS la désynchro au moment où elle apparaît (ex. lecture Movement qui voit flag=false alors que `_owned=true`) — la GDD admet ce délai d'un tick (EC-UPG-13 mutation transitoire). Aucun setter privé runtime introduit MVP (reporté Tier 2 si playtest révèle des cas non couverts).

---

## Out of Scope

- Story 003 (apply_upgrade body steps 1+3+4 + Cas A/B existant).
- Setter privé runtime avec assert (Tier 2+, hors scope MVP).
- Détection désynchro automatique pendant lecture Movement (Movement absorbe le tick — EC-UPG-23).

---

## QA Test Cases

**AC-UPG-9-bis** — Unit test
- Given : `var s = UpgradeSystem.new() ; add_child_autofree(s) ; s._logger = TestUpgradeLogger.new()` (skip `_ready()` ou laisser default `[]`).
- And : injection désync `s._owned[&"double_jump"] = true` ET `s.can_air_jump = false` (EC-UPG-13 simulation hot-reload + mutation externe).
- When : `s.apply_upgrade(&"double_jump")`.
- Then : `s.can_air_jump == true` (resync flag) ; `s._owned.has(&"double_jump") == true` (inchangé) ; `s.get_owned_count() == 1` ; aucun warning émis (`_logger.captured_warnings.size() == 0` — id valide).
- Edge case Cas D (pathologique) : `s._owned == {} ∧ s.can_dash = true` ; `apply_upgrade(&"dash_horizontal")` → `s._owned.has(&"dash_horizontal") == true`, `s.can_dash` reste `true`, `get_owned_count() == 1`.
- Edge case rerun stable : après resync Cas C, second call `apply_upgrade(&"double_jump")` → early return (Cas B), aucune mutation, perf < 1 µs.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/upgrade/apply_upgrade_resync_test.gd` couvrant AC-UPG-9-bis Cas C principal + Cas D edge + rerun stable post-resync.
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 003 (`apply_upgrade` body steps 1+3+4 existant + helper `_apply_flag`).
- Unlocks : aucune story directement bloquée — le resync est défense en profondeur. Story 005 boot hydration bénéficie indirectement (EC-UPG-12 `_owned` rehydraté + flag re-set par helper SI désynchro résiduelle entre sessions).

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing — AC-UPG-3 (resync guard cas C/D, owned dict + flag désynchro recovery) couvert par `tests/unit/upgrade/apply_upgrade_resync_test.gd`.
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/upgrade/apply_upgrade_resync_test.gd` (PASSED suite 41/41).
**Code Review**: Skipped (Solo mode).
