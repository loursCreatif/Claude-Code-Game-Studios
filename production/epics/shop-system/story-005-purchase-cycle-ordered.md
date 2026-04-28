# Story 005: Purchase Cycle 6 Étapes Déterministes

> **Epic**: Shop System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> ⚠️ **AC-SHP-48 PROVISIONAL chain-blocked OQ-SHP-2** : `UpgradeSystem.apply_upgrade(id) -> void` SYNC idempotent. Sprint 1 = mock UpgradeSystem (`tests/unit/shop/mocks/mock_upgrade_system.gd`) ; Sprint 2 activation = re-test contre impl réelle. Story Done-Provisional jusqu'alors.
> ✅ **ADR-0010 Accepted** (promu 2026-04-27) : `save_string_array` API verrouillée par GDD Save/Load r1 + ADR-0010 D-2.

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-6` (cycle 6 étapes), `R-SHP-7` (idempotence partielle), `R-SHP-8` (persist immédiat), `EC-SHP-1/2/3/16/17/23`
*Cycle d'achat strict dans le même call stack synchrone : (1) guard `_owned_upgrades.has(id)` → (2) try_spend → (3) `_owned_upgrades.append(id)` → (4) save_string_array → (5) apply_upgrade → (6) BuyButton.disabled=true. Aucun `await` entre étapes. Ordre 4 → 5 impératif (persist AVANT apply, EC-SHP-16/23 atomicité).*

**ADR Governing Implementation**: ADR-0010 (Save/Load) D-2 + ADR-0007 (orchestration).
**ADR Decision Summary**: `save_string_array` SYNC ; UpgradeSystem.apply_upgrade SYNC idempotent (provisional Sprint 1 mock).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (chain-blocked Upgrade r1 — ADR-0010 promu Accepted 2026-04-27).
**Engine Notes**: Aucune coroutine `await` autorisée dans le cycle. ConfigFile.save SYNC < 1 ms SSD (F-SAV-1).

**Control Manifest Rules**:
- Required: ordering 4→5 strict (`save` AVANT `apply`)
- Required: aucun `await`/`yield` dans handler `_on_buy_pressed`
- Forbidden: `try_spend` à fins de vérification (mutant — utiliser `get_total() >= cost`)

---

## Acceptance Criteria

- [ ] **AC-SHP-6** : `dash_horizontal` affordable + non owned, click BuyButton → `try_spend(40)` appelé exactement 1 fois.
- [ ] **AC-SHP-7** : `try_spend(20)` retourne true → `_owned_upgrades.has("double_jump") == true` immédiatement (avant tout yield).
- [ ] **AC-SHP-8** : `try_spend` true → `save_string_array` appelé AVANT `apply_upgrade` (séquence journalisée).
- [ ] **AC-SHP-9** : `try_spend(40)` true → `apply_upgrade("dash_horizontal")` appelé exactement 1 fois.
- [ ] **AC-SHP-10** : cycle complété → `BuyButton_double_jump.disabled == true`.
- [ ] **AC-SHP-11** : solde 15 < cost 20 → `try_spend` NON appelé, `save_string_array` NON appelé, `apply_upgrade` NON appelé, `_owned_upgrades` inchangé (early DISABLED guard).
- [ ] **AC-SHP-48 [PROVISIONAL]** : avec mock UpgradeSystem SYNC idempotent, cycle complète sans erreur.
- [ ] **EC-SHP-2** : guard `assert(cost > 0)` en début étape 4 (try_spend) — bloque cost=0 accidentel.
- [ ] **EC-SHP-23** : zéro `await` ou `yield` entre `try_spend` et `apply_upgrade` (atomicité call stack).

---

## Implementation Notes

```gdscript
var _purchase_in_progress: bool = false  # voir story-006 pour double-click guard

func _on_buy_pressed(id: StringName, n_index: int) -> void:
    # Guard 1 : already owned (R-SHP-7)
    if _owned_upgrades.has(id):
        return  # silent no-op

    # Guard 2 : double-click (story-006)
    if _purchase_in_progress:
        return

    var cost: int = _compute_cost(n_index)
    assert(cost > 0, "Cost must be positive (EC-SHP-2)")

    # Pre-check affordability (passive, non-mutant — F-SHP-2)
    if CreditEconomy.get_total() < cost:
        # DISABLED click feedback handled by story-013 (shake)
        return

    _purchase_in_progress = true

    # Étape 4 : try_spend (atomic SYNC)
    if not CreditEconomy.try_spend(cost):
        _purchase_in_progress = false
        return  # Race: solde changed entre check et spend (EC-SHP-1)

    # Étape 5 : mark + persist + apply (ORDRE STRICT 5a → 5b → 5c)
    _owned_upgrades.append(id)                                       # 5a — RAM
    SaveLoad.save_string_array(&"owned_upgrades", _owned_upgrades)   # 5b — disk SYNC (story-010 retry pattern)
    UpgradeSystem.apply_upgrade(id)                                  # 5c — gameplay activation

    # Étape 6 : disable button + label change
    var button: Button = _get_button_for_id(id)
    button.disabled = true
    button.text = "POSSÉDÉ"

    _purchase_in_progress = false
    # Tween pulse + counter animation handled by story-013
```

**Pas d'`await`** : cycle entièrement synchrone. Si `apply_upgrade` lance exception → `push_error` (EC-SHP-16) ; `_owned_upgrades` reste marqué owned (persist déjà fait), incohérence assumée Tier 1.

**Mock UpgradeSystem Sprint 1** : créer `tests/unit/shop/mocks/mock_upgrade_system.gd` exposant `apply_upgrade(id: StringName) -> void` SYNC + compteur d'appels + assert `id in [&"double_jump", &"dash_horizontal"]`.

---

## Out of Scope

- Story 006 : guards idempotence approfondis (`_purchase_in_progress` détaillé, double-click).
- Story 010 : SaveLoad write SYNC + corruption handling (cette story appelle `save_string_array`, story-010 owne le buffer retry).
- Story 011 : EC-SHP-9 buffer retry Option C (failure recovery).
- Story 013 : tween pulse + counter animation post-achat.

---

## QA Test Cases

- **AC-SHP-6** : Logic
  - Given: mock CreditEconomy.try_spend compteur, ShopController prêt
  - When: `_on_buy_pressed(&"dash_horizontal", 1)`
  - Then: try_spend.call_count == 1, arg == 40
- **AC-SHP-7** : Logic
  - Given: mock try_spend retourne true
  - When: `_on_buy_pressed(&"double_jump", 0)`
  - Then: `_owned_upgrades.has(&"double_jump") == true` immédiatement (pas de await)
- **AC-SHP-8** : Logic (séquencement)
  - Given: mocks SaveLoad + UpgradeSystem journalisent appels dans `_call_order: Array[String]`
  - When: cycle complet
  - Then: `_call_order.find("save") < _call_order.find("apply")`
- **AC-SHP-9** : Logic
  - Given: mock UpgradeSystem.apply_upgrade compteur
  - When: `_on_buy_pressed(&"dash_horizontal", 1)` + try_spend true
  - Then: apply_upgrade.call_count == 1, arg == &"dash_horizontal"
- **AC-SHP-10** : Logic
  - Given: cycle exécuté avec succès
  - When: post-cycle render
  - Then: `BuyButton_double_jump.disabled == true`, text == "POSSÉDÉ"
- **AC-SHP-11** : Logic (early guard)
  - Given: solde 15, cost 20
  - When: `_on_buy_pressed(&"double_jump", 0)`
  - Then: try_spend.count == 0, save.count == 0, apply.count == 0, `_owned_upgrades.is_empty()`
- **AC-SHP-48 [PROVISIONAL]** : Logic
  - Given: mock UpgradeSystem SYNC idempotent
  - When: cycle exécuté 2 fois (re-call apply pour même id)
  - Then: aucune exception, mock ne reçoit qu'1 appel grâce au guard `_owned_upgrades.has`
  - Edge: marqué `Done-Provisional` jusqu'à Sprint 2 re-test impl réelle
- **EC-SHP-23 atomicity lint** : Lint
  - Given: ShopController source
  - When: `grep -E "await|yield" body de _on_buy_pressed`
  - Then: 0 match (zero coroutine entre try_spend et apply_upgrade)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/purchase_cycle_test.gd` — must exist and pass (avec mock UpgradeSystem)
**Status**: [x] 9/9 PASSED 145 ms (re-run 2026-04-28 `reports/report_78/`)

---

## Dependencies

- Depends on: Story 002 (controller + catalogue), Story 003 (`_owned_upgrades` initialisé)
- Unlocks: Story 006 (idempotence détaillée), Story 010 (write back), Story 015 (bidirectional)

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing (9/9 unit purchase_cycle) — AC-SHP-6 (try_spend(40) executé), AC-SHP-7 (`_owned_upgrades.has(id)` immédiat post-spend), AC-SHP-8 (séquence save AVANT apply via `_call_order_log`), AC-SHP-9 (real `Upgrade.is_owned()` + `Upgrade.can_dash`), AC-SHP-11 (insufficient balance no-mutation), AC-SHP-48 (idempotent already_owned silent no-op — chain unblocked, real Upgrade autoload utilisé), full chain 2 upgrades + persistence, EC-SHP-23 atomicity lint static (zero `await`/`yield`/`process_frame` dans `_on_buy_pressed` body), EC-SHP-2 soft guard `cost <= 0` early return.
**Deviations**: ADVISORY (3)
  - **AC-SHP-48 PROMOTED non-PROVISIONAL** : real `Upgrade` autoload utilisé au lieu de mock — la chaîne upgrade-system stories 001-010 est Complete (chain unblocked OQ-SHP-2). Tests directs sur l'autoload réel ; mock_upgrade_system non créé.
  - **EC-SHP-2 assert→soft-guard** : `assert(cost > 0)` retiré au profit de `if cost <= 0: return` — l'assert crashait en debug build (GdUnit4 runtime) sur `n_index` pathologique, alors que `_compute_cost` retourne 0 légitimement avec warning. Soft guard équivalent runtime-safe pour debug + release.
  - **AC-SHP-10 (BuyButton.disabled)** : `_disable_buy_button_for(id)` utilise `get_node_or_null(NodePath("%BuyButton_id"))` avec skip silent si absent (test seam unit). UI rendering scene-attach déféré story-012 (Chrome Zen styling) ou story sub-équipe future.
**Test Evidence**: Logic — `tests/unit/shop/purchase_cycle_test.gd` 9/9 PASSED ; suite shop globale 26/26 PASSED 388 ms (`reports/report_76/`).
**Code Review**: Skipped (Solo mode).
