# Story 023: TR-lvl-039 full automated CCD gate (gameplay scenario + baseline lock)

> **Epic**: Level System
> **Status**: Ready
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: 6h (first empirical CI run + JSON capture 0.5h + PlayerController gameplay scenario runner 2.5h + baseline lock + regression gate 1h + ADR-0001 amendment evaluation 1h + 4 GdUnit4 tests 1h)

## Context

**GDD**: `design/gdd/level-system.md`
**Requirements**: `TR-lvl-039`

**ADR Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt CCD)
**ADR Decision Summary** : ADR-0001 EC-8 declares "no_tunneling at v >20 m/s via Jolt CCD + wall_thickness ≥0.3m" as **CLAIM-UNVERIFIED**. Story-014 livré le sub-gate microbench (synthetic CharacterBody3D vs synthetic walls). Cette story clôture le claim avec : (a) première run CI empirique sur runner story-014 → JSON output dans benchmark doc, (b) gate gameplay scenario réaliste (PlayerController state machine complet, dash+wall-run combo, vs walls de production), (c) baseline JSON locked → regression gate sur runs subséquents.

**Engine**: Godot 4.6 | **Risk**: HIGH (résultat empirique inconnu — peut requérir amendement ADR-0001 si clip à 0.3m)
**Engine Notes** : Si first CI run montre `clips_rate > 0` à thickness ≥ 0.3 m → amendement ADR-0001 obligatoire (activer `CharacterBody3D.safe_margin`, threshold CCD enforcement, ou élargir wall_thickness floor). Se référer à `docs/engine-reference/godot/modules/physics.md` pour Jolt CCD parameters Godot 4.6.

---

## Acceptance Criteria

- [ ] **AC-LVL-42** : First empirical CI run captured — `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md` (créé STATUS EN ATTENTE par story-014) updated avec JSON output réel des 3 thicknesses × 100 passes ; STATUS = PASS ou FAIL avec interprétation
- [ ] **AC-LVL-43** : Gameplay scenario runner — `tests/performance/level_ccd_gameplay_runner.gd` simule PlayerController complet (dash + wall-run + wall-jump combo) sur fixture etage avec walls 0.3m / 0.5m ; 50 passes par scenario ; exit 0 si 0 clips observés
- [ ] **AC-LVL-44** : Baseline lock + regression gate — JSON sub-gate output (story-014 microbench + cette story gameplay) committé en `tests/baselines/level-ccd-baseline.json` ; CI job échoue si clip_rate augmente vs baseline (regression detection)
- [ ] **AC-LVL-45** : ADR-0001 EC-8 status updated — soit "VERIFIED via story-023" si toutes runs passent, soit amendement ADR-0001 (activate `CharacterBody3D.safe_margin` ou nouveau threshold) si clipping observé. TR-lvl-039 status passe à `verified` dans `tr-registry.yaml`

---

## Implementation Notes

### Phase 1 : First empirical CI run (AC-LVL-42)

- Push minimal change qui touche le runner story-014 (ex. comment update) pour déclencher CI job `perf-level-ccd`.
- Récupérer artifact JSON output ; mettre à jour `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md` avec :
  - Tableau résultats : `thickness | passes | clips | clips_rate_pct`
  - Interpretation : PASS si 0.3m + 0.5m clips_rate == 0 ; FAIL sinon
  - Si FAIL : trigger Phase 4 (amendement ADR-0001) avant Phase 2/3

### Phase 2 : Gameplay scenario runner (AC-LVL-43)

```gdscript
# tests/performance/level_ccd_gameplay_runner.gd
# extends Node3D + .tscn companion (même pattern que level_ccd_sweep_runner)
# Pas de --main-scene direct (CLAUDE.md Godot CLI Safety #2) ; --path . + .tscn

extends Node3D

const SCENARIOS = [
    {"name": "dash_into_wall_03m", "thickness": 0.3, "combo": ["dash"]},
    {"name": "dash_into_wall_05m", "thickness": 0.5, "combo": ["dash"]},
    {"name": "wallrun_into_corner_03m", "thickness": 0.3, "combo": ["wall_run", "wall_jump"]},
    {"name": "dash_wallrun_combo_03m", "thickness": 0.3, "combo": ["dash", "wall_run"]},
]
const PASSES_PER_SCENARIO = 50

func _ready() -> void:
    call_deferred("_run_scenarios")

func _run_scenarios() -> void:
    # Spawn PlayerController (réel) + scene fixture + capture clips via Area3D
    # plane derrière chaque mur (signal body_entered).
    # ...
    var exit_code := 0 if _all_scenarios_zero_clips() else 1
    get_tree().quit(exit_code)
```

- Fixture `tests/fixtures/level/etage_ccd_gameplay.tscn` — etage minimal avec 4 walls disposés selon scenarios
- Réutilise `PlayerController.tscn` réel (pas mock) pour valider state machine + Jolt body settings de production
- Detection tunneling : `Area3D` plane placée derrière chaque mur, signal `body_entered` → counter++
- CI job `perf-level-ccd-gameplay` ajouté à `.github/workflows/tests.yml`, timeout 5 min, exit 0/1

### Phase 3 : Baseline lock + regression gate (AC-LVL-44)

- Commit `tests/baselines/level-ccd-baseline.json` agrégeant outputs des 2 runners (sweep + gameplay)
- Format :
  ```json
  {
    "version": 1,
    "captured": "2026-MM-DD",
    "godot_version": "4.6.x",
    "jolt_version": "4.6 default",
    "sweep": {
      "0.2": {"clips_rate_pct": 78.0},
      "0.3": {"clips_rate_pct": 0.0},
      "0.5": {"clips_rate_pct": 0.0}
    },
    "gameplay": {
      "dash_into_wall_03m": {"clips": 0, "passes": 50},
      "dash_into_wall_05m": {"clips": 0, "passes": 50},
      "wallrun_into_corner_03m": {"clips": 0, "passes": 50},
      "dash_wallrun_combo_03m": {"clips": 0, "passes": 50}
    }
  }
  ```
- CI step `compare-ccd-baseline.gd` lit baseline + current run output → fail si `current.clips_rate_pct > baseline.clips_rate_pct + tolerance` (tolerance = 1% pour absorber micro-flake Jolt)

### Phase 4 : ADR-0001 EC-8 verification (AC-LVL-45)

**Si Phase 1 PASS** :
- Editer `docs/architecture/adr-0001-physics-rate-60hz.md` EC-8 section : `CLAIM-UNVERIFIED` → `VERIFIED via story-023, baseline `tests/baselines/level-ccd-baseline.json``
- Editer `docs/architecture/tr-registry.yaml` TR-lvl-039 entry : `status: active` → `status: verified` + ajout `verified_by: [story-023]` field

**Si Phase 1 FAIL** :
- Run `/architecture-decision` pour amendement ADR-0001 :
  - Option A : activer `CharacterBody3D.safe_margin = 0.04` (Jolt-compatible, 4cm collision shell extension)
  - Option B : élever wall_thickness floor de 0.3m → 0.5m (impact level design — coordination level-designer requise)
  - Option C : implémenter `ShapeCast3D` manuel anti-tunneling sur murs critiques meta-tagged (pattern combat story-009)
- Re-run Phase 1 après amendement ; baseline locked sur configuration corrigée

---

## Out of Scope

- Story 014 : sub-gate microbench (déjà livré ; cette story consume son output)
- Modifications Jolt physics engine (out of project scope)
- Amendements ADR sur d'autres EC-claims (uniquement EC-8)

---

## QA Test Cases

- **AC-LVL-42 first run** : Manual check — vérifier `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md` STATUS update post-CI run
  - Setup : Push commit triggering `perf-level-ccd` CI job ; download artifact JSON
  - Verify : Doc updated avec results table + interpretation PASS/FAIL

- **AC-LVL-43 gameplay scenario PASS** : Test `test_level_ccd_gameplay_runner_exits_zero_for_03m_walls`
  - Setup : Local run `godot --headless --path . tests/performance/level_ccd_gameplay_runner.tscn`
  - Verify : Exit code 0 ; JSON output 4 scenarios @ 50 passes each, all clips==0

- **AC-LVL-43 gameplay scenario FAIL** : Test `test_level_ccd_gameplay_runner_exits_one_when_clip_detected`
  - Setup : Wall thickness 0.1m injection (force regression) → expected clips
  - Verify : Exit code 1

- **AC-LVL-44 baseline regression detection** : Test `test_compare_ccd_baseline_fails_on_regression`
  - Setup : Baseline JSON with 0.3m clips_rate=0% ; current run output 0.3m clips_rate=5%
  - Verify : `compare-ccd-baseline.gd` exit code 1 + stderr message "regression: 0.3m clips_rate 5.00% > baseline 0.00% + tolerance 1%"

- **AC-LVL-44 baseline tolerance** : Test `test_compare_ccd_baseline_passes_within_tolerance`
  - Setup : Baseline 0% ; current 0.5% (under 1% tolerance)
  - Verify : Exit code 0

- **AC-LVL-45 TR registry update** : Manual check
  - Setup : `grep -A 8 "TR-lvl-039" docs/architecture/tr-registry.yaml`
  - Verify : `status: verified` + `verified_by: [story-023]` (PASS path) OR ADR-0001 amendement présent (FAIL path)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/performance/level_ccd_gameplay_runner.gd` + `.tscn` companion — runner gameplay scenario (Phase 2)
- `tests/fixtures/level/etage_ccd_gameplay.tscn` — fixture 4 walls
- `tests/baselines/level-ccd-baseline.json` — baseline locked (Phase 3)
- `tests/integration/level/ccd_baseline_compare_test.gd` — 2 GdUnit4 regression tests (Phase 3)
- `docs/architecture/benchmarks/level-ccd-sweep-2026-04-27.md` — update STATUS section (Phase 1)
- `docs/architecture/adr-0001-physics-rate-60hz.md` — EC-8 status update OU amendement (Phase 4)
- `docs/architecture/tr-registry.yaml` — TR-lvl-039 status update (Phase 4)

**Status**: [ ] To be created during implementation per Required evidence paths listed above

---

## Dependencies

- Depends on: **Story 014** (sub-gate microbench runner livré ; cette story consume), **Story 010** (hiérarchie etage), **Story 013** (LAYER_ENVIRONMENT pour walls), **Story 015** (PlayerController.tscn fixture utilisable — verify ready)
- Unlocks: ADR-0001 EC-8 status → VERIFIED ; TR-lvl-039 → verified ; clôt risk HIGH "Jolt CCD comportement à haute vélocité CLAIM-UNVERIFIED"
- Coordination requise: si Phase 4 chemin FAIL → coordination level-designer (option B wall_thickness floor) ou gameplay-programmer (option C ShapeCast3D manuel)

---

## Risk & Mitigation

- **R-1 (HIGH)** : First empirical CI run révèle clipping à 0.3m → amendement ADR-0001 + impact level design. **Mitigation** : Phase 4 documentée 3 options (safe_margin / thickness floor / ShapeCast3D manuel) ; option A (safe_margin) la moins invasive.
- **R-2 (MEDIUM)** : CI flake Jolt physics_frame instabilité → false positive regression detection. **Mitigation** : tolerance 1% absorbée dans baseline compare ; si flake observé, augmenter to 2-3% ou répéter run × 3.
- **R-3 (LOW)** : Gameplay runner timeout en CI (50 passes × 4 scenarios × ~30 frames = ~6000 physics ticks). **Mitigation** : timeout job 5 min avec early-exit sur clip détecté.
