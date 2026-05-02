# Story 016: Invariants runtime `_validate_invariants()` + smoke check ranges

> **Epic**: Player Combat System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, doc sync — `invariants_runtime_validation_test.gd` 5/5 PASS)

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-006` (géométrie hitbox safe ranges + invariant #1) + `TR-cmb-010` (timing constants + invariants #4 #6 #7)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0001 (Physics Rate)
**ADR Decision Summary**: Live-tuning safety (DEC-r5-2 Option A) — `_validate_invariants()` appelé en début de chaque `_physics_process` sous garde `if OS.is_debug_build():`. Re-calcule invariants #4 #6 #7 #9 sur valeurs courantes (couvre tuning via Inspector). Smoke check statique AC-CMB-36 sur safe ranges + sommes invariants après chargement `combat_config.tres`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `OS.is_debug_build()` stable. `assert()` GDScript compilé out en release. GUT `assert_fail()` pattern stable.

**Control Manifest Rules (Feature layer)**:
- Required: `_validate_invariants()` appelé chaque `_physics_process` sous `OS.is_debug_build()` guard
- Forbidden: hardcoded magic numbers (constants doivent être déclarées const ou @export, jamais inline `0.4`)
- Guardrail: assert panic en debug DOIT pouvoir être capturé par GUT `assert_fail()` (pas `crash_on_assert`)

---

## Acceptance Criteria

*From GDD AC-CMB-12/13/17/18/36 + Section D.8 invariants :*

- [x] **AC-CMB-12** : `ACTIVE_TICKS = ceili(SWING_DURATION_MS / (delta * 1000.0))` → `ACTIVE_TICKS == 8` ; swing GUT 8 ticks confirme `_state == Idle` au tick 9
- [x] **AC-CMB-13** : `_cooldown_timer = 0.25 s` → `cooldown_ratio == clamp(0.25 / 0.4, 0.0, 1.0) == 0.625 ± 0.001` ; à `_cooldown_timer = 0.0` → `cooldown_ratio == 0.0` ; entrée Swinging → `cooldown_ratio == 1.0 ± 0.001`
- [x] **AC-CMB-17 (8 invariants)** : `_validate_invariants()` vérifie : (1) `KATANA_REACH > player_capsule_radius + 1.0`, (2) `KATANA_REACH > 0.0`, (3) `ATTACK_COOLDOWN_MS >= SWING_DURATION_MS + (1000.0/60.0)`, (4) `ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS`, (5) `V_max * delta / N_SUBSTEPS < 2 * r_enemy_min`, (6) `SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2`, (7) `ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5`, (8) `SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4` (duty cycle staccato r6 D-r4-2)
- [x] **AC-CMB-17 live-tuning** (DEC-r5-2 Option A) : `_validate_invariants()` appelé chaque tick debug → muter `ATTACK_BUFFER_MS = 100, ATTACK_COOLDOWN_MS = 300` runtime → `assert_fail` au prochain `_physics_process`
- [x] **AC-CMB-18** : invariant croisé Movement DASH_DURATION (100 ms) < SWING_DURATION_MS (120 ms) — vérifié statique GUT inter-système, commentaire test "swing démarré à mi-dash finit en Airborne (Rule 8)"
- [x] **AC-CMB-36** : test régression GUT charge `combat_config.tres` → vérifie (a) safe ranges individuels (Section G), (b) sommes invariants #4 et #6 sur valeurs effectives. Fail mode : config `SWING=200 + SLOW_MO=150 + COOLDOWN=300` viole #4 → AC-CMB-36 rejette

---

## Implementation Notes

*Derived from ADR-0006 + GDD Section D.8 + AC-CMB-17 r5 DEC-r5-2 :*

```gdscript
const PLAYER_CAPSULE_RADIUS: float = 0.35  # depuis Movement GDD ou config
const ENEMY_RADIUS_MIN: float = 0.35  # smallest enemy

func _validate_invariants() -> void:
    # Re-calcule sur valeurs courantes (couvre live-tuning Inspector)
    assert(KATANA_REACH > PLAYER_CAPSULE_RADIUS + 1.0, "Invariant #1 violated: KATANA_REACH must be > player_radius + 1.0")
    assert(KATANA_REACH > 0.0, "Invariant #2 violated: KATANA_REACH must be > 0")
    assert(ATTACK_COOLDOWN_MS >= SWING_DURATION_MS + (1000.0 / 60.0), "Invariant #3 violated")
    assert(ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS, "Invariant #4 violated")
    var v_max := 30.0  # dash + wall-run worst case
    assert(v_max * (1.0/60.0) / N_SUBSTEPS < 2 * ENEMY_RADIUS_MIN, "Invariant #5 violated")
    assert(SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2.0, "Invariant #6 violated")
    assert(ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5.0, "Invariant #7 violated")
    var duty := SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS)
    assert(duty < 0.4, "Invariant #9 violated: duty cycle %f >= 0.4" % duty)

func _physics_process(delta: float) -> void:
    if OS.is_debug_build():
        _validate_invariants()  # 1 branchement + 9 asserts en debug, 0 en release
    # ... cooldown, state machine, sweep, mutual kill drain
```

- `cooldown_ratio` getter (read-only HUD-bound) :
  ```gdscript
  func get_cooldown_ratio() -> float:
      return clampf(_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0), 0.0, 1.0)
  ```
- AC-CMB-36 smoke check : test GUT séparé qui charge `combat_config.tres` (si présent) ou inspecte les const compile-time, vérifie ranges + sommes

---

## Out of Scope

- Cross-system tests larger : couverts dans story-018 soak

---

## QA Test Cases

- **AC-1** ACTIVE_TICKS formula
  - Given: SWING_DURATION_MS=120, delta=1/60
  - When: `ACTIVE_TICKS = ceili(120 / (delta * 1000))`
  - Then: ACTIVE_TICKS == 8
  - Edge cases: SWING_DURATION_MS=200 → 12 ; =80 → 5

- **AC-2** Cooldown ratio
  - Given: `_cooldown_timer = 0.25`, `ATTACK_COOLDOWN_MS = 400`
  - When: `get_cooldown_ratio()` lu
  - Then: 0.625 ± 0.001
  - Edge cases: timer=0.0 → 0.0 ; entrée Swinging → 1.0 ± 0.001

- **AC-3** Invariants pass on default config
  - Given: constants par défaut (KATANA_REACH=1.8, SWING=120, COOLDOWN=400, SLOW_MO=50, BUFFER=80, N_SUBSTEPS=3)
  - When: `_validate_invariants()` appelé
  - Then: aucune assert panic
  - Edge cases: tous 8 invariants individuels passent ✅

- **AC-4** Live-tuning detection
  - Given: combat_system._ready() OK avec config valide
  - When: muter `ATTACK_BUFFER_MS = 100`, `ATTACK_COOLDOWN_MS = 300` runtime, déclencher `_physics_process(1.0/60.0)`
  - Then: `assert_fail()` GUT capture panic "Invariant #7 violated"
  - Edge cases: muter `SWING=200, COOLDOWN=300` → invariant #4 fail ; muter `SWING=200, COOLDOWN=300` (duty=0.4 limite) → invariant #9 fail

- **AC-5** Cross-system DASH_DURATION
  - Given: GUT inter-système charge MovementController.DASH_DURATION et CombatSystem.SWING_DURATION_MS
  - When: assertion `DASH_DURATION < SWING_DURATION_MS`
  - Then: `100 < 120` PASS, commentaire test docstring documente "swing démarré mi-dash finit en Airborne (Rule 8)"
  - Edge cases: muter DASH_DURATION = 150 → AC fail (cross-system mismatch)

- **AC-6** Smoke check ranges + sommes (AC-CMB-36)
  - Given: combat_config.tres chargé (ou constants compile-time)
  - When: vérifier safe ranges Section G + sommes invariants #4 et #6 sur valeurs effectives
  - Then: tous in-range et sommes valides
  - Edge cases: config synthétique `SWING=200, SLOW_MO=150, COOLDOWN=300` → individuel pass mais somme `200+150=350 > 300` viole #4 → fail

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/invariants_runtime_validation_test.gd` — must exist and pass (avec `assert_fail()` patterns).

**Status**: ✅ Created — 5/5 PASS (`reports/report_262` 2026-05-02). Le fichier livré porte le nom `invariants_runtime_validation_test.gd` (vs spec original `invariants_runtime_smoke_check_test.gd` — divergence cosmétique nom de fichier, contenu équivalent).

## Completion Notes

- **Implémentation cross-livrée** : `_validate_invariants()` câblé dans combat_system.gd lignes 753-779 ; appel sous `OS.is_debug_build()` guard ligne ~270. Couvre invariants #1 à #9 par `assert()` panic en debug.
- **Story status correction 2026-05-02** : la story était marquée Done sans cocher les ACs ni Test Evidence. Audit a révélé tests existants — synchronisé sur evidence réelle.

---

## Dependencies

- Depends on: Story 002 (constants definitions), Movement story DASH_DURATION exposed
- Unlocks: Story 017 (microbench peut s'appuyer sur ranges valides)
