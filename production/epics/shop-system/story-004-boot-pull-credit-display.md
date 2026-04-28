# Story 004: Boot Pull Credit Display

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-9` (cas initial pull pattern), `EC-SHP-4` (BOOT_HYDRATE signal perdu)
*Au `_ready()`, avant tout signal `credits_changed`, le shop initialise `CreditValueLabel` via pull synchrone `CreditEconomy.get_total()`. Pattern cohérent ADR-0007 D-9 (consumers lisent état initial via getter, pas signal).*

**ADR Governing Implementation**: ADR-0007 (D-9 boot sequence pull pattern).
**ADR Decision Summary**: Les consumers lisent l'état initial via `get_*()` getter dans leur `_ready()` ; les signals ne se déclenchent que sur transition effective. Couvre EC-SHP-4 (signal BOOT_HYDRATE perdu si Shop pas encore connecté).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Aucune API post-cutoff.

**Control Manifest Rules**:
- Required: pattern pull au boot (ADR-0007 D-9 — pattern projet)
- Required: lecture passive non-mutante (`get_total()` ne déclenche aucun side-effect Credit)

---

## Acceptance Criteria

- [ ] **AC-SHP-3** : `CreditEconomy.get_total()` retourne 35 → `CreditValueLabel.text == "35"` avant tout signal reçu.
- [ ] Pull se fait dans `_ready()` AVANT tout `await get_tree().process_frame`.
- [ ] Pas d'appel à `try_spend` ou autre méthode mutante côté Credit.
- [ ] Affichage initial `CreditEconomy.get_total() == 0` → label `"0"` (pas de placeholder vide).

---

## Implementation Notes

```gdscript
@onready var _credit_value_label: Label = %CreditValueLabel

func _ready() -> void:
    # ... (story-002 asserts, story-003 hydrate) ...
    _credit_value_label.text = str(CreditEconomy.get_total())
    # Story-007 connectera ensuite credits_changed CONNECT_DEFERRED
```

**Note pull-vs-signal** : EC-SHP-4 documente que si CreditEconomy émet `credits_changed(BOOT_HYDRATE)` avant que Shop ait connecté son handler, le signal est perdu. Le pull `get_total()` rend Shop indépendant de cet ordre. Cohérent Credit r1 R-CRD-7 boot hydration.

---

## Out of Scope

- Story 007 : connexion `credits_changed` CONNECT_DEFERRED + handler updates live.
- Story 013 : tween décrément animation 300 ms (purement présentation post-achat).

---

## QA Test Cases

- **AC-SHP-3** : Logic
  - Given: mock CreditEconomy `get_total()` retourne `35`
  - When: ShopController `_ready()` exécuté
  - Then: `_credit_value_label.text == "35"` immédiatement (avant tout await)
- **Edge : solde 0**
  - Given: mock `get_total()` retourne `0`
  - When: `_ready()` exécuté
  - Then: label text == `"0"` (pas vide, pas placeholder)
- **Edge : solde élevé**
  - Given: mock `get_total()` retourne `9999`
  - When: `_ready()` exécuté
  - Then: label text == `"9999"`
- **Pull pattern enforcement** : Lint
  - Given: ShopController source
  - When: grep `CreditEconomy\.get_total` dans `_ready` body
  - Then: au moins 1 match (preuve du pull pattern)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/shop/boot_pull_credit_display_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (controller boot)
- Unlocks: Story 007 (credits_changed handler updates même label)
