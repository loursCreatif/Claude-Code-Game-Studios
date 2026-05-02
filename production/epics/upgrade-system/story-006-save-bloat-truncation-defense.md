# Story 006: Save Bloat Truncation Defense (R-UPG-5 step 2)

> **Epic**: upgrade-system
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-5 step 2 r2 amendement B-6 (truncate `owned > MAX_CATALOG_SIZE_TIER_2 * 2 = 14`), EC-UPG-36 (save corrompue N=1M → freeze 2-10 s sans truncation).

**ADR Governing Implementation** : ADR-0010 Save/Load Persistence (ConfigFile Ratification).
**ADR Decision Summary** : ConfigFile peut retourner Array arbitrairement large si save corrompue ou edition manuelle. Upgrade défend MVP via cap dur 14 entrées (= 2× catalog Tier 2+ max planifié) — au-delà, push_warning + slice + continue.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : `Array.slice(0, 14)` est O(14) ~3 µs négligeable. La GDD documente budget total post-truncation : 14 × ~3 µs helper `_apply_flag` = 42 µs total, sous Pillar 1 budget 16.6 ms.

**Control Manifest Rules (Feature Layer)** :
- Required : truncation appliquée AVANT la boucle `apply_upgrade` (sinon le freeze a déjà commencé). Le warning doit contenir le substring `"bloat"` ou `"truncat"` pour matcher AC-44 + AC-45.
- Forbidden : tronquer silencieusement sans warning (le warning sert d'audit trail Tier 2+ pour détecter saves corrompues répétées).
- Guardrail : `_ready()` total < 5 ms même avec save 1000 entrées (AC-UPG-44).

---

## Acceptance Criteria

- [ ] **AC-UPG-44** [BLOCKING] : mock SaveLoad 1000 entrées valides → warning "bloat"/"truncat", `get_owned_count() ≤ 14`, `_is_hydrated == true`, `_ready()` total < 5 ms headless CI.
- [ ] **AC-UPG-45** [ADVISORY] : boundary 15 entrées → warning émis ; 14 entrées → aucun warning émis ; `get_owned_count() ≤ 14` dans les deux cas.

---

## Implementation Notes

### Patch dans `_ready()` body (entre step 1 type guard et step 3 loop)

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

    if _logger == null:
        _logger = UpgradeLogger.new()

    var owned: Variant = SaveLoad.load_string_array("owned_upgrades", [] as Array[StringName])

    if not (owned is Array):
        _logger.warn("UpgradeSystem: load_string_array returned non-Array (corrupt save), fallback to empty")
        owned = [] as Array[StringName]

    # Step 2 r2 B-6 — save bloat truncation defense (NEW story 006)
    var max_size: int = MAX_CATALOG_SIZE_TIER_2 * 2    # 14
    if owned.size() > max_size:
        _logger.warn("UpgradeSystem: save bloat (size=%d), truncating to %d" % [owned.size(), max_size])
        owned = owned.slice(0, max_size)

    # Step 3 : boucle apply_upgrade
    for id in owned:
        apply_upgrade(id)

    # Step 4 : hydration flag
    _is_hydrated = true
```

### Constante référence

`MAX_CATALOG_SIZE_TIER_2 = 7` déjà déclarée story 001 Section C.1 GDD. Le seuil truncation = `MAX_CATALOG_SIZE_TIER_2 * 2 = 14` calculé dynamiquement (pas de duplicate constante `MAX_OWNED_SIZE_TRUNCATE` au runtime — la GDD la documente comme valeur dérivée, pas comme const séparée).

### Note ordre des ids tronqués

Les 14 premiers ids de l'array sont gardés (pas de sort + dedupe préalable au MVP). Biais d'ordre admis Tier 1 : la save est déjà pathologique, l'ordre n'est pas une garantie. Tier 2+ pourrait préférer `sort + dedupe + slice` ; non requis MVP.

### Mock SaveLoad pour AC-44/45

```gdscript
# AC-UPG-44 — 1000 entrées valides (répétitions valides MVP)
mock.return_value = []
for i in 1000:
    mock.return_value.append(&"double_jump" if i % 2 == 0 else &"dash_horizontal")

# AC-UPG-45 — 15 entrées (juste au-dessus du seuil)
mock.return_value = []
for i in 15:
    mock.return_value.append(&"double_jump")

# AC-UPG-45 — 14 entrées (à la limite, no warning)
mock.return_value = []
for i in 14:
    mock.return_value.append(&"double_jump")
```

---

## Out of Scope

- Sort + dedupe avant truncate (Tier 2+, hors MVP).
- Validation cryptographique save anti-cheat (Tier 3, EC-UPG-30/31).
- Migration tool si MAX_CATALOG_SIZE_TIER_2 change (Tier 2+, hors MVP).

---

## QA Test Cases

**AC-UPG-44** — Integration test [headless CI]
- Given : instance bare `UpgradeSystem` + Logger DI ; mock SaveLoad return Array 1000 valides ; runner GUT headless ubuntu-latest.
- When : `s._ready()` ; mesure `Time.get_ticks_usec()` avant/après.
- Then : `_logger.captured_warnings` contient ≥1 message avec substring `"bloat"` OU `"truncat"`.
- And : `s.get_owned_count() <= 14`.
- And : `s._is_hydrated == true`.
- And : durée totale `_ready()` < 5 ms (5000 µs).
- Edge : sans truncation le test échouerait à >3 ms (1000 × ~3 µs helper) — la truncation est bien le path qui rend le test < 5 ms.

**AC-UPG-45** — Integration test boundary
- Given : instance bare + Logger DI.
- When (case 1) : mock retourne 15 entrées valides → `_ready()`.
- Then (case 1) : ≥1 warning bloat capturé, `get_owned_count() <= 14`.
- When (case 2) : mock retourne 14 entrées valides → `_ready()` (instance fraîche, pas réutiliser).
- Then (case 2) : **aucun** warning bloat capturé (`captured_warnings.filter(contains "bloat" OR "truncat").is_empty()`), `get_owned_count() <= 14`.
- When (case 3, optional regression) : mock retourne exactement 14 ids tous distincts catalog Tier 2+ stub → `get_owned_count() == 14` strict si tous matchent ; en MVP avec catalog 2 entrées, `get_owned_count() == 2` (idempotence dédoublonnage).

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/unit/upgrade/save_bloat_truncation_test.gd` couvrant AC-44 (1000 entrées + perf gate) + AC-45 boundary (15/14/edge cases). Headless CI required pour AC-44 perf gate.
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 005 (boot hydration `_ready()` body avec hooks step 2 placeholder), 002 (Logger DI pour capture warning).
- Unlocks : 010 (perf headless CI bénéficie de la garantie sub-5ms même worst-case).

---

## Completion Notes
**Completed**: 2026-04-28
**Criteria**: passing — AC-UPG-9 (cap dur 14 = `MAX_CATALOG_SIZE_TIER_2 × 2`) + warning sur troncature couverts par `tests/unit/upgrade/save_bloat_truncation_test.gd`.
**Deviations**: None
**Test Evidence**: Logic — `tests/unit/upgrade/save_bloat_truncation_test.gd` (PASSED suite 41/41).
**Code Review**: Skipped (Solo mode).
