# Story 007: `credits_changed` CONNECT_DEFERRED + Affordability Recalc

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-9` (signal connect DEFERRED + recalc affordability live), `F-SHP-2` (affordability check), `EC-SHP-5/14/40`
*Au `_ready()`, Shop connecte `CreditEconomy.credits_changed` avec `CONNECT_DEFERRED` **OBLIGATOIRE et VERROUILLÉ**. Sans DEFERRED, un autre handler de `credits_changed` (Tier 2+ telemetry, GSM transition) pourrait s'exécuter ENTRE `try_spend` et `apply_upgrade` côté Shop, cassant l'atomicité du cycle (cf. EC-SHP-23). Handler met à jour `CreditValueLabel.text` + recalcule affordability F-SHP-2 pour chaque BuyButton non-owned.*

**ADR Governing Implementation**: ADR-0007 (signal patterns), ADR-0005 D-5 (CONNECT_DEFERRED critère).
**ADR Decision Summary**: CONNECT_DEFERRED quand consumer alloue ou exécute > 0.5 ms. Shop = UI Control, pas de contrainte frame-precise → DEFERRED acceptable. **Critère anti-réentrance** est la justification primaire ici (cf. EC-SHP-23 + AC-SHP-4 verrouillage).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Signal flags `CONNECT_DEFERRED` stable Godot 4.0+. `signal.get_connections()` API stable.

**Control Manifest Rules**:
- Required: signal `credits_changed` connecté avec flag `CONNECT_DEFERRED` (verrou AC-SHP-4)
- Forbidden: passage à `CONNECT_SYNC` ou flag 0 sur `credits_changed` côté Shop sans audit chaîne d'appel + amendement Shop r3

---

## Acceptance Criteria

- [ ] **AC-SHP-4** : connexion à `credits_changed` utilise flag `CONNECT_DEFERRED` (lint static + GUT `signal.get_connections()` assert flag bitmask).
- [ ] **AC-SHP-12** : émission `credits_changed(15, -5, SPEND_SHOP)` → après `await get_tree().process_frame` (idle frame DEFERRED), `CreditValueLabel.text == "15"`, `BuyButton_double_jump.disabled == true`, `BuyButton_dash_horizontal.disabled == true`.
- [ ] **AC-SHP-16** : solde 19 + `_owned_upgrades == []` → BuyButton_double_jump disabled, BuyButton_dash_horizontal disabled (19<20, 19<40).
- [ ] **AC-SHP-17** : solde 20 + double_jump acheté (Credit net=0) → solde effectif=0, dash_horizontal disabled (0<40).
- [ ] **AC-SHP-18** : solde 60 + double_jump acheté (40 reste) → dash_horizontal disabled=false NORMAL (40>=40).
- [ ] **AC-SHP-19** : solde 60 + 2 upgrades achetées séquentiellement → solde final=0, `_owned_upgrades == [&"double_jump", &"dash_horizontal"]`, 2 boutons OWNED.
- [ ] **EC-SHP-14** : 1 frame achat → toutes cartes restantes recalculent `affordable_n` dans même handler (pas de fenêtre cliquable inter-tick).
- [ ] **EC-SHP-40** : 2 handlers DEFERRED de `credits_changed` (Shop + autre) → exécution séquentielle idle frame, aucune réentrance possible.

---

## Implementation Notes

```gdscript
func _ready() -> void:
    # ... (story-002/003/004) ...
    var err: int = CreditEconomy.credits_changed.connect(_on_credits_changed, CONNECT_DEFERRED)
    assert(err == OK, "Failed to connect credits_changed: %d" % err)

func _on_credits_changed(total: int, _delta: int, _source: int) -> void:
    # Update label
    _credit_value_label.text = str(total)
    # Tween 300 ms animation handled by story-013

    # Recalc affordability for each non-owned upgrade (F-SHP-2)
    for entry in _CATALOG:
        var id: StringName = entry.id
        var n_index: int = entry.n_index
        var button: Button = _get_button_for_id(id)
        if _owned_upgrades.has(id):
            continue  # already disabled OWNED
        var cost: int = _compute_cost(n_index)
        button.disabled = total < cost
```

**Justification CONNECT_DEFERRED verrou (AC-SHP-4)** : si dev futur passe à SYNC, créer un audit-time check :

```gdscript
func _ready() -> void:
    # Verrou défensif AC-SHP-4
    var conns: Array = CreditEconomy.credits_changed.get_connections()
    for conn in conns:
        if conn.callable.get_object() == self:
            assert(conn.flags & CONNECT_DEFERRED != 0,
                   "credits_changed must be CONNECT_DEFERRED côté Shop (cf. AC-SHP-4)")
```

---

## Out of Scope

- Story 010 : SaveLoad write SYNC (signal flow distinct).
- Story 013 : tween counter 300 ms animation post-credits_changed.
- Story 015 : bidirectional integration test full Credit ↔ Shop ↔ Save/Load ↔ Upgrade.

---

## QA Test Cases

- **AC-SHP-4** : Lint
  - Given: ShopController source
  - When: `grep "credits_changed.connect" src/ui/shop/shop_controller.gd`
  - Then: ligne contient `CONNECT_DEFERRED`
  - Edge: GUT alternatif → `signal.get_connections()` itère + assert flags bitmask
- **AC-SHP-12** : Integration scene
  - Given: shop ACTIVE, mocks Credit
  - When: `CreditEconomy.credits_changed.emit(15, -5, SPEND_SHOP)` puis `await get_tree().process_frame`
  - Then: label "15", 2 boutons disabled
  - Edge: vérifier que pré-await, label + boutons sont encore dans état précédent (DEFERRED non encore exécuté)
- **AC-SHP-16** : Logic
  - Given: mock get_total=19, _owned_upgrades=[]
  - When: `_on_credits_changed(19, ...)` invoqué directement
  - Then: 2 boutons disabled
- **AC-SHP-17** : Logic
  - Given: solde 20, double_jump acheté → credits_changed(0, -20, SPEND_SHOP) émis
  - When: handler exécuté
  - Then: dash_horizontal.disabled == true (0<40)
- **AC-SHP-18** : Logic
  - Given: solde 60, double_jump acheté → credits_changed(40, -20, SPEND_SHOP)
  - When: handler exécuté
  - Then: dash_horizontal.disabled == false (40>=40, NORMAL)
- **AC-SHP-19** : Integration
  - Given: solde 60, _owned_upgrades=[]
  - When: 2 cycles séquentiels (avec await process_frame entre)
  - Then: solde 0, _owned_upgrades=[&"double_jump",&"dash_horizontal"], 2 OWNED
- **EC-SHP-40 réentrance prouvée non** : Logic
  - Given: 2 handlers DEFERRED connectés
  - When: 1 emit `credits_changed`
  - Then: handlers exécutés séquentiellement à idle frame ; aucune mutation concurrente prouvée par log d'ordre

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/shop/credits_changed_deferred_affordability_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002, 003, 004 (controller + label initialisé)
- Unlocks: Story 013 (tween 300 ms branche dans même handler), Story 015 (bidirectional)
