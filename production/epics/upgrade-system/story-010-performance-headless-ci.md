# Story 010: Performance Budget Headless CI

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : F-UPG-2 boot hydration sequence + Invariant 5 (`_ready()` strictement SYNC), AC-UPG-40 (`_ready()` < 1 ms), AC-UPG-41 (`apply_upgrade` médiane < 100 µs).

**ADR Governing Implementation** : ADR-0001 Physics Rate 60 Hz.
**ADR Decision Summary** : 16.6 ms frame budget total. Upgrade `_ready()` boot one-shot consume max 1 ms (6% du frame budget). `apply_upgrade` runtime call (Shop purchase) consume max 100 µs (0.6% du frame budget). Helper `_apply_flag` réflexion documenté ~3 µs nominal.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : Mesure via `Time.get_ticks_usec()` (microseconde précision). Headless CI référence ubuntu-latest GitHub Actions. Median (pas mean) sur 1000 calls pour robust to GC pauses (R-UPG-14 amendement r2).

**Control Manifest Rules (Feature Layer)** :
- Required : tests perf passent en CI headless ubuntu-latest. Seuils calibrés worst-case CI hardware (5-10× plus lent que desktop dev local).
- Forbidden : tests perf en `tests/integration/` avec rendering loop — doivent être pure GUT headless.
- Guardrail global : `Performance.TIME_PHYSICS_PROCESS` ≤ 4 ms p99 (ADR-0001 VC-4) — Upgrade contribue 0 (pas de `_physics_process`).

---

## Acceptance Criteria

- [ ] **AC-UPG-40** [ADVISORY MVP] : instance bare + mock SaveLoad `[&"double_jump", &"dash_horizontal"]` (catalog complet) ; `_ready()` wall-clock < 1000 µs (1 ms) headless ubuntu-latest.
- [ ] **AC-UPG-41** [ADVISORY MVP] : 1000 calls `apply_upgrade(&"double_jump")` ; **médiane** < 100 µs (0.1 ms) headless ubuntu-latest.

---

## Implementation Notes

### AC-UPG-40 boot perf test

```gdscript
# tests/perf/upgrade/boot_perf_test.gd
extends GutTest

func test_AC_UPG_40_boot_under_1ms() -> void:
    var mock := MockSaveLoad.new()
    mock.return_value = [&"double_jump", &"dash_horizontal"]    # catalog MVP complet
    Engine.register_singleton("SaveLoad", mock)

    var s := UpgradeSystem.new()
    s._logger = UpgradeLogger.new()    # pas TestLogger — pas de capture overhead

    var t0: int = Time.get_ticks_usec()
    add_child(s)    # triggers _ready()
    var elapsed_us: int = Time.get_ticks_usec() - t0

    assert_lt(elapsed_us, 1000,
        "AC-UPG-40 FAIL : _ready() = %d µs, budget 1000 µs (1 ms) headless CI" % elapsed_us)

    s.queue_free()
    Engine.unregister_singleton("SaveLoad")
```

Note : la mesure inclut `add_child` (overhead Godot scene tree minimal ~10 µs). Si seuil 1000 µs frôlé sur dev local, considérer refactoriser pour mesure pure body `_ready()` sans `add_child`.

### AC-UPG-41 apply_upgrade médiane perf test

```gdscript
func test_AC_UPG_41_apply_upgrade_median_under_100us() -> void:
    var s := UpgradeSystem.new()
    s._logger = UpgradeLogger.new()
    add_child(s)
    # Premier call établit l'état owned (cas A nominal)
    s.apply_upgrade(&"double_jump")

    var samples: Array[int] = []
    samples.resize(1000)
    for i in 1000:
        var t0: int = Time.get_ticks_usec()
        s.apply_upgrade(&"double_jump")    # idempotent — cas B early return
        samples[i] = Time.get_ticks_usec() - t0

    samples.sort()
    var median_us: int = samples[500]    # median = 500e index sur 1000

    assert_lt(median_us, 100,
        "AC-UPG-41 FAIL : apply_upgrade median = %d µs, budget 100 µs headless CI" % median_us)

    # Diagnostic supplémentaire (logged but not asserted)
    print("AC-UPG-41 stats: min=%d µs, median=%d µs, p99=%d µs, max=%d µs" % [
        samples[0], samples[500], samples[990], samples[999]
    ])

    s.queue_free()
```

Note : la médiane sur idempotent path (cas B early return) est ~1-5 µs nominal. Test cas A (premier call avec helper `_apply_flag` réflexion) sépparément si besoin de baseline :

```gdscript
func test_AC_UPG_41_apply_upgrade_first_call_under_500us() -> void:
    # Premier call déclenche helper _apply_flag (réflexion ~3 µs).
    # Pas un strict AC mais utile pour caractériser la perf nominale.
    var s := UpgradeSystem.new()
    s._logger = UpgradeLogger.new()
    add_child(s)

    var t0: int = Time.get_ticks_usec()
    s.apply_upgrade(&"double_jump")
    var elapsed_us: int = Time.get_ticks_usec() - t0
    print("First call apply_upgrade: %d µs" % elapsed_us)
    assert_lt(elapsed_us, 500, "First call should be < 500 µs (helper réflexion ~3-50 µs nominal)")

    s.queue_free()
```

### CI headless workflow

`.github/workflows/tests.yml` job dédié :
```yaml
upgrade-perf-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: chickensoft-games/setup-godot@v2
      with:
        version: 4.6.0
    - name: Run perf tests headless
      run: |
        godot --headless --script tests/gdunit4_runner.gd \
          --test-suite tests/perf/upgrade/
```

### Régression budget si test fail

Si le seuil est dépassé en CI :
1. Vérifier que le helper `_apply_flag` n'a pas régressé (added asserts ?).
2. Vérifier que `_ready()` n'a pas gagné des étapes hors-scope (story 005/006 didn't add unbudgeted work).
3. Mesurer breakdown : `_ready()` = `process_mode set` + `_logger init` + `SaveLoad.load` + `truncation` + `loop apply_upgrade`. Identifier le pic.
4. Si CI hardware change (ubuntu-22 → ubuntu-24), recalibrer seuils avec marge.

---

## Out of Scope

- Tests perf sur Tier 2+ catalog 7 entrées (PROVISIONAL — story future).
- Tests perf desktop dev local (seuils CI ubuntu-latest = worst-case ; dev local sera 5-10× plus rapide naturellement).
- Profiling intra-call breakdown (helper réflexion vs Dictionary lookup) — diagnostic only, pas AC.

---

## QA Test Cases

**AC-UPG-40** — Perf test [ADVISORY headless CI]
- Given : instance bare + mock SaveLoad `[&"double_jump", &"dash_horizontal"]` ; runner GUT headless ubuntu-latest GitHub Actions.
- When : `add_child(s)` (triggers `_ready()`) ; mesure `Time.get_ticks_usec()` avant/après.
- Then : `elapsed_us < 1000` (1 ms).
- Edge : si dev local échoue à 200 µs et CI échoue à 1100 µs, c'est attendu (calibration CI worst-case).

**AC-UPG-41** — Perf test [ADVISORY headless CI]
- Given : instance bare initialisée + premier call `apply_upgrade(&"double_jump")` (établit owned).
- When : 1000 calls répétés `apply_upgrade(&"double_jump")` (idempotent path) ; mesure chaque call ; sort + median[500].
- Then : `median_us < 100` (0.1 ms).
- Edge : log min/median/p99/max pour diagnostic.

---

## Test Evidence

**Story Type** : Logic
**Required evidence** : `tests/perf/upgrade/boot_perf_test.gd` + `tests/perf/upgrade/apply_upgrade_perf_test.gd` ; CI workflow `.github/workflows/tests.yml` job dédié `upgrade-perf-tests` headless ubuntu-latest.
**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 003 (apply_upgrade body), 005 (boot hydration `_ready()`), 006 (truncation — protège AC-44 5ms gate qui partage l'infrastructure).
- Unlocks : aucune story directement — c'est le gate final perf avant Definition of Done epic.
