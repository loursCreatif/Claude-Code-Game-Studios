# Story 016: Performance Benchmarks (Load / Cycle / Handler)

> **Epic**: Shop System
> **Status**: Ready
> **Layer**: Feature (CI perf gate)
> **Type**: Logic (perf assertions)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: Groupe H ACs (AC-SHP-34/35/36/38) performance budgets
*Cinq budgets perf : (1) load + instanciation + `_ready()` < 200 ms CI Ubuntu (baseline locale dev < 100 ms — révisé r2 pour absorber jitter runner GitHub Actions) ; (2) cycle achat complet < 16.6 ms (1 frame 60 fps) ; (3) handler `credits_changed` < 5 ms ; (4) shop statique contribution `_process` < 0.5 ms (advisory). Cohérent Pillar 1 FLOW + perf budgets globaux 60 fps locked.*

**ADR Governing Implementation**: ADR-0003 (Rendering & Display Latency budget 16.6 ms).
**ADR Decision Summary**: Frame budget 60 fps = 16.6 ms total ; sub-budgets négociés par layer. Shop UI contribution doit rester négligeable (≤ 0.5 ms statique, ≤ 5 ms handler peak).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (CI runner variance — baseline locale + tolerance ±50% dans baseline file).
**Engine Notes**: `Time.get_ticks_msec()` / `Time.get_ticks_usec()` stables. `Performance.TIME_PHYSICS_PROCESS` monitor disponible.

**Control Manifest Rules**:
- Required: tests perf déterministes (aucune dépendance random ou wall-clock external)
- Required: mocks SYNC pour isoler shop logic (pas de I/O réseau, pas de disk lent)
- Performance Guardrails (global) : Frame budget 16.6 ms, Camera _process ≤ 0.2 ms, Input ≤ 0.2 ms

---

## Acceptance Criteria

- [ ] **AC-SHP-34 [BLOCKING]** : `load("res://scenes/shop/shop.tscn")` + instanciation + `_ready()` complet → < 200 ms en CI headless Ubuntu 22.04 4-core (runner GitHub Actions standard). Baseline dev local < 100 ms enregistrée dans `tests/performance/baselines/shop_load_baseline.json` (tolerance ±50% absorbe variance hardware).
- [ ] **AC-SHP-35 [BLOCKING]** : cycle achat (`_on_buy_pressed → try_spend → save → apply → render`) → < 16.6 ms wall-clock (1 frame 60 fps).
- [ ] **AC-SHP-36 [BLOCKING]** : handler `credits_changed` invoqué → update complète (label + affordability recalcul + bouton states) < 5 ms.
- [ ] **AC-SHP-38 [ADVISORY]** : shop ACTIVE statique sans tween → contribution `_process` ShopController < 0.5 ms (manual profiler 100 frames).

---

## Implementation Notes

```gdscript
# tests/performance/shop_perf_test.gd
extends GutTest

const PATH_TEMP_SAVE = "user://test_perf_savegame.cfg"

func test_load_under_200ms_ci():
    SaveLoad.SAVE_FILE_PATH = PATH_TEMP_SAVE
    var t0_us: int = Time.get_ticks_usec()
    var packed: PackedScene = load("res://scenes/shop/shop.tscn")
    var shop: Node = packed.instantiate()
    add_child(shop)
    await get_tree().process_frame  # _ready() complet
    var elapsed_ms: float = (Time.get_ticks_usec() - t0_us) / 1000.0
    assert_lt(elapsed_ms, 200.0, "Shop load took %.2f ms (budget 200 ms CI)" % elapsed_ms)
    # Baseline locale recorded :
    if not OS.has_feature("ci"):
        _record_baseline("shop_load_ms", elapsed_ms, target=100.0, tolerance=50.0)

func test_purchase_cycle_under_16_6ms():
    var shop = _setup_shop_with_credits(60)
    var t0_us: int = Time.get_ticks_usec()
    shop._on_buy_pressed(&"double_jump", 0)  # full cycle
    var elapsed_ms: float = (Time.get_ticks_usec() - t0_us) / 1000.0
    assert_lt(elapsed_ms, 16.6, "Purchase cycle took %.2f ms (budget 16.6 ms)" % elapsed_ms)

func test_credits_changed_handler_under_5ms():
    var shop = _setup_shop_with_credits(100)
    var t0_us: int = Time.get_ticks_usec()
    shop._on_credits_changed(50, -50, 0)  # appel direct (pas signal — mesure handler isolé)
    var elapsed_ms: float = (Time.get_ticks_usec() - t0_us) / 1000.0
    assert_lt(elapsed_ms, 5.0, "credits_changed handler took %.2f ms (budget 5 ms)" % elapsed_ms)

func _setup_shop_with_credits(amount: int) -> Node:
    SaveLoad.SAVE_FILE_PATH = PATH_TEMP_SAVE
    CreditEconomy.set_total_for_test(amount)
    var shop = preload("res://scenes/shop/shop.tscn").instantiate()
    add_child(shop)
    await get_tree().process_frame
    return shop
```

**Baseline file** : `tests/performance/baselines/shop_load_baseline.json` :
```json
{
    "shop_load_ms": {
        "target": 100.0,
        "tolerance_pct": 50,
        "ci_budget_ms": 200,
        "last_recorded": null,
        "notes": "Run on dev SSD baseline ; CI Ubuntu 22.04 4-core absorbe jitter ±50%"
    }
}
```

**AC-SHP-38 manual profiler** : steps documentés dans `production/qa/evidence/shop/story-016-static-frame-cost.md` :
1. Run shop scene en éditeur Godot, profiler ouvert
2. Capture 100 frames shop ACTIVE statique (pas de hover, pas de tween)
3. Filter ShopController._process call
4. Compute mean — assert < 0.5 ms

---

## Out of Scope

- Story 015 : correctness integration (cette story = perf isolée).
- Story 014 : lint (cette story = runtime measurement).
- Profiler complet GDD HUD/Audio peers (séparé).

---

## QA Test Cases

- **AC-SHP-34 load < 200 ms CI** : Performance
  - Setup : CI Ubuntu 22.04 4-core, mocks SaveLoad/Credit en place
  - When: `load + instantiate + _ready()` mesuré via `Time.get_ticks_usec()`
  - Then: elapsed_ms < 200
  - Edge: baseline locale dev recordée pour tracking dérive
- **AC-SHP-35 cycle < 16.6 ms** : Performance
  - Setup : shop ready, solde 60, mock UpgradeSystem SYNC
  - When: `_on_buy_pressed` mesuré
  - Then: elapsed_ms < 16.6
  - Edge: SaveLoad réel SSD ; HDD spinning hors scope perf gate
- **AC-SHP-36 handler < 5 ms** : Performance
  - Setup : shop ready
  - When: `_on_credits_changed(50, -50, 0)` mesuré
  - Then: elapsed_ms < 5
  - Edge: mesurer hors signal (appel direct méthode) pour isoler coût handler
- **AC-SHP-38 static frame < 0.5 ms** : Manual
  - Setup : profiler Godot, shop ACTIVE statique
  - When: capture 100 frames
  - Then: mean ShopController._process < 0.5 ms
  - Edge: documenter mesure dans evidence file

---

## Test Evidence

**Story Type**: Logic (perf assertions automated)
**Required evidence**: `tests/performance/shop_perf_test.gd` + `tests/performance/baselines/shop_load_baseline.json` + `production/qa/evidence/shop/story-016-static-frame-cost.md` (AC-SHP-38 manual)
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001 à 013 (toute la stack shop fonctionnelle)
- Unlocks: gate perf CI Sprint 1 — bloque merge si budget dépassé
