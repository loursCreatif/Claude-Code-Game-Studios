# Story 002: State machine + cooldown + active_tick lifecycle

> **Epic**: Player Combat System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-010` (timing constants + invariants)
*(Voir `docs/architecture/tr-registry.yaml` pour les valeurs nominales)*

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0001 (Physics Rate 60 Hz)
**ADR Decision Summary**: Combat tourne exclusivement en `_physics_process` @ 60 Hz (ADR-0001 autorité). `_active_tick` incrémenté chaque tick de la window active jusqu'à `ACTIVE_TICKS=8` ; `_cooldown_timer` décrémenté chaque tick.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `_physics_process(delta)` stable Godot 4.0+. `delta = 1.0/60.0` constant grâce à `physics/common/physics_ticks_per_second=60` (ADR-0001).

**Control Manifest Rules (Feature layer)**:
- Required: aucune Feature-layer ; respecter ADR-0001 `_physics_process` autorité simulation
- Forbidden: never écrire game logic dans `_process` (cosmétique only)
- Guardrail: timing constants en const ou @export, jamais magic numbers

---

## Acceptance Criteria

*From GDD, AC-CMB-01/02/03/04 + constantes Section D.8 :*

- [x] **AC-CMB-01** : `Player.attacked()` reçu en `Idle` avec `_cooldown_timer == 0` → tick suivant `_state == SWINGING`, `_active_tick == 0`, `_cooldown_timer == ATTACK_COOLDOWN_MS / 1000.0 ± 0.001`, `ShapeCast3D.enabled == true`
- [x] **AC-CMB-02** : `Player.attacked()` reçu en `Idle` avec `_cooldown_timer == 0.1` (cooldown actif) → `_state` reste `Idle`, `_cooldown_timer > 0.0` (pas de reset)
- [x] **AC-CMB-03** : `Player.attacked()` reçu en `Dead` → `_state` reste `Dead`, aucun sweep, `ShapeCast3D.enabled == false`
- [x] **AC-CMB-04** : `Swinging` à `_active_tick == ACTIVE_TICKS - 1` (tick 7) → tick suivant `_state == Idle`, `_active_tick == 0`, `_hit_this_swing.is_empty()`, `ShapeCast3D.enabled == false`, `swing_ended` émis 1 fois
- [x] Constantes : `SWING_DURATION_MS=120`, `ATTACK_COOLDOWN_MS=400`, `ACTIVE_TICKS = ceili(SWING_DURATION_MS / (delta * 1000.0)) == 8`

---

## Implementation Notes

*Derived from ADR-0006 D-3 + GDD §Detailed Design Rules 2-3 + Formula 4:*

- Définir `enum State { IDLE, SWINGING, DEAD }`
- Variables d'état : `_state: State = State.IDLE`, `_active_tick: int = 0`, `_cooldown_timer: float = 0.0`, `_hit_this_swing: Array[int] = []`
- Constantes (Section G GDD) :
  ```gdscript
  const SWING_DURATION_MS: float = 120.0
  const ATTACK_COOLDOWN_MS: float = 400.0
  const ACTIVE_TICKS: int = int(ceil(SWING_DURATION_MS / (1000.0 / 60.0)))  # = 8
  ```
- `_physics_process(delta)` :
  - Décrémenter `_cooldown_timer = maxf(0.0, _cooldown_timer - delta)`
  - Si `_state == SWINGING` : incrémenter `_active_tick`, exécuter sweep (story-007/009/011), si `_active_tick >= ACTIVE_TICKS` → transition Idle (clear `_hit_this_swing`, `_active_tick = 0`, `ShapeCast3D.enabled = false`, emit `swing_ended`)
  - Si `_state == DEAD` : skip toute logique sauf `_death_pending` handling (story-014)
- Signal `swing_ended` déclaré : `signal swing_ended()`

---

## Out of Scope

- Story 003 : transition Dead/respawn full reset
- Story 004 : `attacked()` handler + buffer
- Story 011/012 : sweep collider resolution

---

## QA Test Cases

- **AC-1** Idle → Swinging trigger
  - Given: Combat `Idle`, `_cooldown_timer == 0.0`
  - When: signal `Player.attacked()` injecté + 1 `_physics_process(1.0/60.0)`
  - Then: `_state == SWINGING`, `_active_tick == 0`, `_cooldown_timer == 0.4 ± 0.001`, `ShapeCast3D.enabled == true`
  - Edge cases: trigger pendant `_active_tick = 0` même tick (ordre signal/process)

- **AC-2** Cooldown gate
  - Given: `_cooldown_timer = 0.1`, `_state == IDLE`
  - When: `Player.attacked()` injecté
  - Then: `_state == IDLE`, `_cooldown_timer > 0.0` (inchangé par signal)
  - Edge cases: `_cooldown_timer = 0.0001` (bord inférieur) — accepté ; `0.0` exact — accepté (AC-23)

- **AC-3** Dead state immune
  - Given: `_state == DEAD`
  - When: `Player.attacked()` injecté
  - Then: `_state == DEAD`, `ShapeCast3D.enabled == false`
  - Edge cases: 100 attacks consécutifs en Dead → tous ignorés

- **AC-4** Active window expiration
  - Given: `_state == SWINGING`, `_active_tick == 7`
  - When: 1 `_physics_process` supplémentaire
  - Then: `_state == IDLE`, `_active_tick == 0`, `_hit_this_swing.is_empty()`, signal `swing_ended` reçu 1 fois
  - Edge cases: muter `ACTIVE_TICKS = 1` → window 1 tick (boundary)

- **AC-5** ACTIVE_TICKS formula
  - Given: `SWING_DURATION_MS = 120.0`, `delta = 1.0/60.0`
  - When: `ACTIVE_TICKS = ceili(120.0 / (delta * 1000.0))`
  - Then: `ACTIVE_TICKS == 8`
  - Edge cases: muter `SWING_DURATION_MS = 200` → `ACTIVE_TICKS == 12`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/state_machine_lifecycle_test.gd` — must exist and pass

**Status**: [x] Created — `tests/unit/combat/state_machine_lifecycle_test.gd` (241 lignes, 6 tests, GdUnit4)

---

## Dependencies

- Depends on: Story 001 (scene skeleton)
- Unlocks: Story 003 (death/respawn), Story 004 (attacked handler), Story 011 (kill resolution)

---

## Completion Notes

**Completed** : 2026-04-27 (solo auto-approve)
**Criteria** : 5/5 passing — 0 deferred
**Test Evidence** : `tests/unit/combat/state_machine_lifecycle_test.gd` — 6 tests GdUnit4 couvrant AC-CMB-01/02/02b/03/04 + ACTIVE_TICKS constant
**Code Review** : COMPLETE — verdict `APPROVED WITH SUGGESTIONS` (godot-gdscript-specialist + qa-tester en parallèle, solo mode)
**Mode** : solo → QL-TEST-COVERAGE + LP-CODE-REVIEW gates skipped

**Deviations** :
- ADVISORY (Code Review nits, non-bloquantes) :
  1. `combat_system.gd:158` — comparaison float exacte `_cooldown_timer == 0.0` (sûr via `maxf`, non documenté). Recommande `<= 0.0` + commentaire invariant.
  2. `state_machine_lifecycle_test.gd:194` — lambda `swing_ended.connect(...)` non déconnectée avant `queue_free`. Recommande `CONNECT_ONE_SHOT` (signal émis 1× par design).
  3. `combat_system.gd:40` — `60.0` hardcodé dans formule `ACTIVE_TICKS`. Extraire `const PHYSICS_HZ: float = 60.0` avec ref ADR-0001.
  4. `combat_system.gd:154` — doc comment `attacked()` ne mentionne pas l'émission aval `swing_ended`.
  5. **GAP-1 (qa-tester)** : edge case "muter ACTIVE_TICKS=1" untestable (`const` non-injectable). Backlog : extraire `static calc_active_ticks(duration_ms) -> int` testable séparément (story-017 hardening). AC-CMB-04 elle-même COVERED.
  6. **GAP-2 (qa-tester)** : DEAD mid-swing comportement (`_hit_this_swing` non clear) untested. À valider lors de story-003 (death/respawn) qui doit garantir clear sur transition DEAD.
  7. **GAP-3 (qa-tester, LOW)** : "100 attacks in DEAD all ignored" testé 1× au lieu de loop — trivial à ajouter en follow-up.
  8. **GAP-4/5 (LOW)** : boundary `_cooldown_timer = 0.0001` + same-tick signal/process ordering untested.
- **TR-cmb-010 partiel attendu** : SWING/COOLDOWN ✓ ; SLOW_MO_* + invariant asserts #4/#6/#7 hors scope (story-013 / future story). Conforme "Out of Scope" du header.

**Scope** : Aucune modification hors `src/gameplay/combat/combat_system.gd` + `tests/unit/combat/state_machine_lifecycle_test.gd`. Scène existante story-001 inchangée.

**Manifest staleness** : 2026-04-23 = control-manifest 2026-04-23 ✓ no drift.

**Stories débloquées** :
- story-003 (death/respawn lifecycle reset)
- story-004 (attacked handler + buffer single-slot)
- story-011 (single-hit kill dedup)
