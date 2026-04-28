# Story 002: ShopController + Catalogue Constants

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `R-SHP-1`, `R-SHP-3`, `R-SHP-14`, `F-SHP-1` (TR-SHP-??? à créer)
*Le ShopController est un node-local script (pas autoload). Catalogue MVP hardcodé `Array[Dictionary]` ; coûts dérivés F-CRD-3 0-based via Credit Economy.*

**ADR Governing Implementation**: ADR-0007 (D-5 deux voies — Shop = scène container, pas autoload).
**ADR Decision Summary**: Surface API minimale (`_on_continue_pressed`) ; Shop n'est pas autoload, donc pas de class_name autoload-collision (cohérent memory `feedback_godot_class_name_autoload_collision`).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Array[Dictionary]` typé strict, `StringName` literals via `&"..."`, stables 4.0+.

**Control Manifest Rules (Global / Foundation)**:
- Required: naming `PascalCase` classes, `snake_case` variables, `UPPER_SNAKE_CASE` constants
- Required: typed signals strictes ; typed `Array[T]` (compiler optimizations)
- Forbidden: `class_name` collision avec autoload (`feedback_godot_class_name_autoload_collision`) — utiliser suffixe `Script`

---

## Acceptance Criteria

- [ ] `ShopController` script créé `src/ui/shop/shop_controller.gd`, `class_name ShopControllerScript` (suffixe -Script anti-collision).
- [ ] `const _CATALOG: Array[Dictionary]` exactement 2 entrées : `{id=&"double_jump", display_name="Saut Double", n_index=0}` et `{id=&"dash_horizontal", display_name="Dash Horizontal", n_index=1}`.
- [ ] `const N_UPGRADES_MVP: int = 2` (R-SHP-14).
- [ ] `_ready()` assert `_CATALOG.size() == N_UPGRADES_MVP` (debug-only via `OS.has_feature("debug")`).
- [ ] `_compute_cost(n: int) -> int` retourne `BASE_UPGRADE_COST + TIER_COST_STEP * n` via lookup CreditEconomy (F-CRD-3 0-based) → `[20, 40]` MVP.
- [ ] Edge case : `_compute_cost(-1)` → `push_warning` + return `0` (F-SHP-1 EC).
- [ ] Edge case : `_compute_cost(99)` (> MAX_UPGRADE_INDEX) → `push_error` + return `0`.

---

## Implementation Notes

```gdscript
class_name ShopControllerScript
extends Control

const N_UPGRADES_MVP: int = 2
const _CATALOG: Array[Dictionary] = [
    { "id": &"double_jump",     "display_name": "Saut Double",     "n_index": 0 },
    { "id": &"dash_horizontal", "display_name": "Dash Horizontal", "n_index": 1 },
]

var _owned_upgrades: Array[StringName] = []

func _ready() -> void:
    if OS.has_feature("debug"):
        assert(_CATALOG.size() == N_UPGRADES_MVP,
               "Catalogue size %d != N_UPGRADES_MVP %d" % [_CATALOG.size(), N_UPGRADES_MVP])
    # Hydration owned_upgrades + credit display + signal connect → stories 003/004/007

func _compute_cost(n: int) -> int:
    if n < 0:
        push_warning("ShopSystem: _compute_cost called with negative n (%d)" % n)
        return 0
    if n >= N_UPGRADES_MVP:
        push_error("ShopSystem: _compute_cost n=%d > MAX_UPGRADE_INDEX=%d" % [n, N_UPGRADES_MVP - 1])
        return 0
    # F-CRD-3 0-based : cost_n = B + S × n. Lookup constants Credit Economy.
    return CreditEconomy.BASE_UPGRADE_COST + CreditEconomy.TIER_COST_STEP * n
```

**Note** : `CreditEconomy.BASE_UPGRADE_COST` / `TIER_COST_STEP` exposés en constantes publiques par story Credit Sprint 1. Si pas encore exposés au moment d'impl, fallback sur constantes locales `const _BASE_COST_FALLBACK = 20` + TODO Sprint 2 cleanup.

---

## Out of Scope

- Story 003 : hydration `_owned_upgrades` depuis SaveLoad.
- Story 004 : credit display init (pull `get_total()`).
- Story 005 : purchase cycle (`_on_buy_pressed`).
- Story 007 : connexion `credits_changed` CONNECT_DEFERRED.

---

## QA Test Cases

- **AC : catalogue size invariant**
  - Given: ShopController instancié en debug build
  - When: `_ready()` exécuté
  - Then: assert pass (`_CATALOG.size() == 2 == N_UPGRADES_MVP`)
  - Edge: si dev ajoute 3e entrée sans bumper N_UPGRADES_MVP → assert fail
- **AC : `_compute_cost(0)` → 20**
  - Given: CreditEconomy expose BASE_UPGRADE_COST=20, TIER_COST_STEP=20
  - When: `_compute_cost(0)`
  - Then: return `20`
- **AC : `_compute_cost(1)` → 40**
  - Given: idem
  - When: `_compute_cost(1)`
  - Then: return `40`
- **AC : `_compute_cost(-1)` → warning + 0**
  - Given: CreditEconomy ready
  - When: `_compute_cost(-1)`
  - Then: `push_warning` capturé, return `0`
  - Edge: assert via `assert_emit_warning` GUT helper
- **AC : `_compute_cost(99)` → error + 0**
  - Given: idem
  - When: `_compute_cost(99)`
  - Then: `push_error` capturé, return `0`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/shop_controller_catalogue_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene skeleton — script s'attache à ShopRoot)
- Unlocks: Stories 003, 004, 005, 007
