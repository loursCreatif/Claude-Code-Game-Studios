# Story 006: Idempotence Guards (Double-Click + Re-Entry)

> **Epic**: Shop System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-7` (idempotence 3 niveaux : UI guard + Save/Load re-entry + UpgradeSystem contract), `EC-SHP-10` (double-clic rapide), `EC-SHP-11` (click sur OWNED)
*Trois niveaux d'idempotence. Niveau UI : guard `_purchase_in_progress: bool` posé au premier clic, libéré en fin de cycle (couvre fenêtre 1-frame avant `BuyButton.disabled = true` propagée). Niveau Save/Load : `_ready()` re-charge `_owned_upgrades` → upgrades déjà owned marquées dès rendu initial. Niveau UpgradeSystem : `apply_upgrade(id)` contractuellement idempotent (re-apply = no-op).*

**ADR Governing Implementation**: ADR-0007 (orchestration patterns).
**ADR Decision Summary**: Patterns Godot stdlib (bool flag guard, signal-driven button.disabled).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Aucune API post-cutoff.

**Control Manifest Rules**:
- Required: guard prioritaire sur `BuyButton.disabled` (Godot peut livrer 2 events avant prochain `_process`)
- Forbidden: dépendance unique sur `BuyButton.disabled` pour anti-double-click (race window)

---

## Acceptance Criteria

- [ ] **AC-SHP-13** : `_on_buy_pressed("double_jump")` appelé 2 fois en succession immédiate → `try_spend` appelé exactement 1 fois total.
- [ ] **AC-SHP-14** : `_owned_upgrades == ["double_jump"]` + `_on_buy_pressed("double_jump")` → `try_spend` NON appelé (early return guard `has(id)`).
- [ ] **EC-SHP-10** : double-clic dans même frame avant `disabled=true` propagé → second event no-op silencieux.
- [ ] **EC-SHP-11** : click forcé sur upgrade OWNED (spam input, tests externes) → guard `_owned_upgrades.has(id)` intercepte avant try_spend.
- [ ] `_purchase_in_progress` libéré dans tous les cas (succès, échec try_spend, exception apply) — pas de deadlock guard.

---

## Implementation Notes

```gdscript
var _purchase_in_progress: bool = false

func _on_buy_pressed(id: StringName, n_index: int) -> void:
    # Guard 1 : already owned (priorité absolue, intercepte EC-SHP-11)
    if _owned_upgrades.has(id):
        return

    # Guard 2 : double-click in-flight (priorité sur button.disabled — EC-SHP-10)
    if _purchase_in_progress:
        return

    _purchase_in_progress = true
    # try { cycle story-005 } finally { _purchase_in_progress = false }

    var cost: int = _compute_cost(n_index)
    if cost <= 0 or CreditEconomy.get_total() < cost:
        _purchase_in_progress = false
        return

    if not CreditEconomy.try_spend(cost):
        _purchase_in_progress = false
        return

    _owned_upgrades.append(id)
    SaveLoad.save_string_array(&"owned_upgrades", _owned_upgrades)
    UpgradeSystem.apply_upgrade(id)

    var button: Button = _get_button_for_id(id)
    button.disabled = true
    button.text = "POSSÉDÉ"

    _purchase_in_progress = false  # libération garantie en succès
```

**Pattern try-finally** : GDScript n'a pas `try/finally` natif — assurer reset `_purchase_in_progress = false` dans tous les early-return paths. Code review obligatoire pour valider tous chemins.

---

## Out of Scope

- Story 003 : niveau Save/Load re-entry (déjà couvert par hydration).
- Story 005 : cycle achat principal (cette story renforce les guards autour).
- Story 015 : test bidirectional avec impl Upgrade réelle (idempotence contract niveau 3).

---

## QA Test Cases

- **AC-SHP-13** : Logic
  - Given: mock CreditEconomy.try_spend compteur, double_jump affordable + non owned
  - When: `_on_buy_pressed(&"double_jump", 0)` appelé 2× consécutifs (sans yield)
  - Then: try_spend.count == 1 (le 2e bloqué par `_purchase_in_progress`)
- **AC-SHP-14** : Logic
  - Given: mock CreditEconomy compteur, init `_owned_upgrades = [&"double_jump"]`
  - When: `_on_buy_pressed(&"double_jump", 0)`
  - Then: try_spend.count == 0 (early return guard `has(id)`)
- **EC-SHP-10 race window** : Logic
  - Given: simuler 2 events `pressed` dans même `_process` tick
  - When: handler invoqué deux fois
  - Then: 1 cycle complet, 1 no-op silencieux
- **EC-SHP-11 spam click OWNED** : Logic
  - Given: bouton OWNED + 5 events `pressed` injectés
  - When: handler invoqué 5×
  - Then: 0 try_spend, 0 save, 0 apply, 0 log error
- **Guard release on failure** : Logic
  - Given: mock try_spend retourne false (race solde)
  - When: `_on_buy_pressed`
  - Then: `_purchase_in_progress == false` après return (deuxième click ultérieur fonctionne)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/idempotence_guards_test.gd` — must exist and pass
**Status**: [x] 6/6 PASSED 49 ms (re-run 2026-04-28 `reports/report_80/`)

---

## Dependencies

- Depends on: Story 005 (cycle achat — cette story renforce les guards)
- Unlocks: Story 015 (bidirectional avec contracts validés)

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing (6/6) — AC-SHP-13 (2 calls consécutifs → 1 spend total), AC-SHP-14 (already owned → 0 spend), EC-SHP-10 (race window via `set_purchase_in_progress_for_test(true)` simule in-flight), EC-SHP-11 (5 spam clicks owned → 0 mutation), guard release garanti post-succès, guard untouched sur insufficient balance early return.
**Deviations**: ADVISORY (1)
  - **Test seam `set_purchase_in_progress_for_test`** : GDScript SYNC ne permet pas un vrai concurrent double-call ; le 1er call complète intégralement avant le 2e (qui voit alors `_owned_upgrades.has(id)==true` Étape 1, pas Étape 2). Pour vraiment tester EC-SHP-10 race window, test seam expose `_purchase_in_progress` en write/read. Limitation par construction GDScript SYNC, pas un défaut du guard.
**Test Evidence**: Logic — `tests/unit/shop/idempotence_guards_test.gd` 6/6 PASSED 56 ms (`reports/report_79/`).
**Code Review**: Skipped (Solo mode).
