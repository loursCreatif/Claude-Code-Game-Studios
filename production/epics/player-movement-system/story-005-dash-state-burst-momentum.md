# Story 005: Dash state — burst + exit momentum + cooldown

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt)
**Decision Summary**: Autorité gameplay `_physics_process`, timing déterministe via `Engine.get_physics_frames()` ou compteurs `-= delta`. Pas de `Timer` node (ADR-0005 D-4).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Jolt + CCD à vitesse max 40 m/s dash — pas de tunneling requis)

**Control Manifest Rules**:
- Required: `_physics_process` autorité ; timing via compteurs `-= delta` (pas `Timer.timeout.connect`) ; assertion invariants `DASH_SPEED ≥ MOVE_SPEED × 2.5`, `DASH_COOLDOWN ≥ 4 × DASH_DURATION`.
- Forbidden: utiliser `Timer` node signals pour driver Movement state.
- Guardrail: input→velocity p99 ≤ 16 ms (ADR-0001 VC-2) ; physics p99 ≤ 4 ms (VC-4).

---

## Acceptance Criteria

*From GDD :*

- [ ] **AC-MV-20** : GIVEN `can_dash=true` + cooldown expiré, WHEN `dash` pressed avec wish_dir non-nul, THEN position avance `DASH_SPEED * DASH_DURATION = 2.80 m` ± 0.15 m en `DASH_DURATION`s dans wish_dir. À `t=DASH_DURATION`, `velocity.xz == dash_dir * DASH_EXIT_SPEED ± 0.5`. À `t=DASH_DURATION + DASH_MOMENTUM_WINDOW`, `velocity.xz.length() == MOVE_SPEED ± 0.3`.
- [ ] **AC-MV-21** : GIVEN `can_dash=false`, WHEN `dash` pressed, THEN rien (pas de déplacement, pas de cooldown déclenché).
- [ ] **AC-MV-22** : GIVEN dash vient de finir, WHEN `dash` repressé avant `DASH_COOLDOWN` écoulé, THEN input ignoré + son `dash_reject.wav` déclenché (son = ADVISORY hors scope MVP code, hook d'appel uniquement).
- [ ] **AC-MV-23** : GIVEN dash en cours, WHEN `move_left/right` pressé, THEN direction dash inchangée (input horizontal ignoré).
- [ ] **AC-MV-25** : GIVEN `can_dash=true`, cooldown expiré, Airborne avec `velocity.y=8.0` (jump en cours), WHEN `dash` pressed, THEN au 1er tick Dashing : `velocity.y == 0.0 ± 0.001` (reset explicite Rule 6).
- [ ] **Invariant runtime `_ready`** : `assert(DASH_SPEED >= MOVE_SPEED * 2.5, "DASH_SPEED viole l'invariant × 2.5")` + `assert(DASH_COOLDOWN >= 4.0 * DASH_DURATION, "DASH_COOLDOWN viole l'invariant × 4")`.
- [ ] **Fallback wish_dir vide** : si `dash` pressed et `|wish_dir_xz| < 0.01`, direction = forward horizontal du CharacterBody3D (`-transform.basis.z` projeté XZ).

---

## Implementation Notes

*Derived from GDD Rule 6 + Formulas > Dash + Edge Cases "Dash direction par défaut" :*

- Constantes : `const DASH_SPEED = 30.0 ; const DASH_DURATION = 0.10 ; const DASH_EXIT_SPEED = 15.0 ; const DASH_MOMENTUM_WINDOW = 0.20 ; const DASH_COOLDOWN = 0.8`.
- Variables : `var dash_timer: float = 0.0`, `var _dash_cooldown_timer: float = 0.0`, `var dash_cooldown_timer: float : get: return _dash_cooldown_timer`, `var dash_cooldown_ratio: float : get: return 1.0 - clamp(_dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0)`, `var is_dashing: bool : get: return _state == State.DASHING`, `var _dash_dir: Vector3 = Vector3.ZERO`, `var _momentum_timer: float = 0.0`.
- Placeholder `var can_dash: bool = false` (câblé Story 013).
- Dans `_physics_process(delta)` :
  - Décrémenter `_dash_cooldown_timer` (min 0) et `_momentum_timer` (min 0) chaque tick.
  - Check `dash` pressed (ADR-0004 polling) : si `_dash_cooldown_timer <= 0.0` ET `can_dash` ET `_state != State.DEAD` ET `_state != State.DASHING` →
    - Calculer `dash_dir` : `wish_dir_horizontal = wish_dir_3d` projeté XZ normalisé ; si `|wish_dir_horizontal| < 0.01` : `dash_dir = -transform.basis.z.normalized() * Vector3(1, 0, 1)` (body forward horizontal).
    - `_dash_dir = dash_dir.normalized()`
    - `_state = State.DASHING` (transition)
    - `dash_timer = DASH_DURATION`
    - `_dash_cooldown_timer = DASH_COOLDOWN`
    - `velocity.y = 0.0` (reset AC-MV-25)
    - *(signal `dash_started` sera émis Story 009 — ici juste state change)*
  - Si `_state == State.DASHING` :
    - `velocity.x = _dash_dir.x * DASH_SPEED ; velocity.z = _dash_dir.z * DASH_SPEED`
    - `velocity.y = 0.0` (gravité désactivée)
    - `dash_timer -= delta`
    - Si `dash_timer <= 0.0` → transition vers Airborne ou Grounded selon `is_on_floor()` ; set `velocity.xz = _dash_dir * DASH_EXIT_SPEED` ; `_momentum_timer = DASH_MOMENTUM_WINDOW`.
  - Si `_momentum_timer > 0.0` ET `_state != State.DASHING` ET `_state != State.DEAD` :
    - Décélération linéaire : `speed(t) = DASH_EXIT_SPEED - (DASH_EXIT_SPEED - MOVE_SPEED) * (1 - _momentum_timer / DASH_MOMENTUM_WINDOW)`
    - Appliquer `velocity.xz = _dash_dir.xz * speed(t)` (override si pas d'input actif — si input actif, utiliser move_toward vers air_wish mais capé par speed(t) — simpler: laisser le momentum écrire la vélocité, l'input air control reprend naturellement après).
    - Quand `_momentum_timer <= 0.0` : laisser air/ground control reprendre.
  - Hook `dash_reject` : si `dash` pressed mais `_dash_cooldown_timer > 0.0`, appeler fonction stub `_on_dash_rejected()` (body vide MVP, sera câblé Audio post-MVP).

---

## Out of Scope

- Signal `dash_started(dir, speed)` + `dash_ended()` émission → Story 009
- Combat hitbox active pendant dash → Combat epic (out of Movement scope)
- `can_dash` flag depuis UpgradeSystem → Story 013
- Audio `dash_whoosh.wav` / `dash_reject.wav` playback → Audio epic post-MVP

---

## QA Test Cases

**AC-MV-20 — dash distance + exit momentum** :
- Given : Grounded, `can_dash=true`, cooldown=0, wish_dir forward, spawn=Vector3.ZERO
- When : `simulate_action_press(&"dash")` + 30 physics ticks (0.5s, englobe DASH_DURATION + MOMENTUM_WINDOW)
- Then :
  - Position à `t=DASH_DURATION` : `abs(position.z - (-2.80)) < 0.15`
  - Vélocité à `t=DASH_DURATION` : `velocity.xz.length() ≈ 15.0 ± 0.5`
  - Vélocité à `t=DASH_DURATION+MOMENTUM_WINDOW=0.3s` : `velocity.xz.length() ≈ 10.0 ± 0.3`
- Edge cases : DASH_SPEED=30 (range min r3), MOVE_SPEED=10.

**AC-MV-21 — gated off** :
- Given : `can_dash=false`
- When : `simulate_action_press(&"dash")`
- Then : `_state != State.DASHING`, `_dash_cooldown_timer == 0.0` (pas déclenché).

**AC-MV-22 — cooldown rejette** :
- Given : Dashing finished il y a 0.1s (cooldown=0.7s restant)
- When : `simulate_action_press(&"dash")`
- Then : `_state != State.DASHING` (pas ré-entry), `_on_dash_rejected()` appelé 1×.

**AC-MV-23 — direction lock pendant dash** :
- Given : Dashing `_dash_dir=(1,0,0)` à t=0.03s
- When : `simulate_action_press(&"move_left")` (wish_dir=(-1,0,0))
- Then : `_dash_dir == (1,0,0)` (inchangée), `velocity.x == DASH_SPEED (=30)`

**AC-MV-25 — velocity.y reset entry** :
- Given : Airborne, `velocity=(0, 8, 0)`, `can_dash=true`, cooldown=0
- When : `simulate_action_press(&"dash")` + 1 tick
- Then : `abs(velocity.y - 0.0) < 0.001`.

**Invariants** :
- Given : `_ready()` exécuté
- When : DASH_SPEED=30, MOVE_SPEED=10
- Then : zéro assert failure (30 >= 25 ✓, 0.8 >= 0.4 ✓).
- Edge cases : tuning invalide (DASH_SPEED=20 avec MOVE_SPEED=10) → crash debug build explicite.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/dash_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001, 002, 003, 004 (state machine + transitions + jump interactions)
- Unlocks: Story 008 (die during dash → partial cooldown AC-MV-24), Story 009 (emit dash_started/ended), Story 016 (combo chain)
