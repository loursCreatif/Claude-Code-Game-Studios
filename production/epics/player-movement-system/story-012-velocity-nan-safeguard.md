# Story 012: Velocity NaN/Infinity safeguard

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Physics Rate 60 Hz + Jolt — autorité `_physics_process`)
**Decision Summary**: Dans `_physics_process`, après toute mutation velocity mais AVANT `move_and_slide()`, vérifier `velocity.is_finite()` et reset + push_error si invalid. Pas de clamp -50/+50 (godot-specialist F8 r3 — IEEE 754 : `clamp(NaN, ...) == NaN`, et cap artificiel casse chutes profondes légitimes + Jolt resolver sur surfaces inclinées à vmax).

**Engine**: Godot 4.6 | **Risk**: LOW (Vector3.is_finite() stable depuis 4.0)

**Control Manifest Rules**:
- Required: vérif `velocity.is_finite()` avant `move_and_slide()` dans `_physics_process` ; reset `Vector3.ZERO` + `push_error` sur détection.
- Forbidden: `clamp(velocity, -50, 50)` pattern obsolète r2 (IEEE 754 broken, cap légitime chute).
- Guardrail: `push_error` stdout/debugger non silencieux.

---

## Acceptance Criteria

*From GDD Edge Cases > "Vélocité NaN ou Infinity" + AC-MV-70 :*

- [ ] **AC-MV-70** : GIVEN un tick où `velocity = Vector3(INF, INF, INF)` est injecté après calcul mouvement, WHEN le tick se termine AVANT `move_and_slide()`, THEN `velocity.is_finite() == true` (le safeguard a remplacé par `Vector3.ZERO`) ET un `push_error` émis au stdout/debugger.
- [ ] Pattern `is_finite()` (pas `clamp`) — IEEE 754 compliant.
- [ ] Safeguard placé **avant** `move_and_slide()` mais **après** toutes les mutations velocity du tick (gravité, dash, wall-run fall cap, air control, jump).
- [ ] Test NaN : `velocity.x = 0.0/0.0` (NaN IEEE 754) détecté → reset + push_error.
- [ ] Test -INF : `velocity.y = -INF` détecté → reset + push_error.
- [ ] **Performance négligeable** : `is_finite()` coût ≤ 0.001 ms/tick (négligeable vs budget 4 ms).

---

## Implementation Notes

*Derived from GDD Edge Case + godot-specialist F8 (r3) :*

- Placement dans `_physics_process(delta)` :
  ```
  # ... toutes mutations velocity (gravité, dash, wall-run fall cap, air control, jump, wall-jump) ...
  
  if not velocity.is_finite():
      push_error("velocity NaN/Inf detected at tick %d — reset to zero (ADR-0001 autorité + GDD Edge Cases)" % Engine.get_physics_frames())
      velocity = Vector3.ZERO
  
  move_and_slide()
  ```
- `Vector3.is_finite()` retourne `false` si l'un des x/y/z est NaN, +INF, ou -INF. Méthode native Godot 4.0+.
- `push_error` déclenche `_ready() ; get_tree().debug_stop_at_error` si debug build ; stdout + tracker CI en release.
- Ne pas remplacer par `assert` — on veut recovery automatique en release, pas crash (robustesse > strictness).

---

## Out of Scope

- Root cause detection (quel système a produit le NaN) → debug manuel post-incident
- Telemetry / logging to analytics → Feature layer post-MVP

---

## QA Test Cases

**AC-MV-70 — INF reset** :
- Given : Player Grounded à position (0,0,0)
- When : script GUT force `player.velocity = Vector3(INF, INF, INF)` dans un tick custom AVANT `move_and_slide()`
- Then : tick finish → `velocity.is_finite() == true`, `velocity == Vector3.ZERO`, push_error capturé dans logger.
- Edge cases : vérifier position inchangée (reset velocity = pas de move).

**NaN detection** :
- Given : Player Grounded
- When : `player.velocity = Vector3(0.0/0.0, 1, 2)` (NaN × 0.0/0.0 Godot)
- Then : `velocity.is_finite() == false` AVANT safeguard → `velocity == Vector3.ZERO` APRÈS.

**-INF detection** :
- Given : Player Airborne
- When : `player.velocity.y = -INF`
- Then : reset Vector3.ZERO, push_error.

**Valid velocities pass through** :
- Given : `velocity = Vector3(30, -24, 0)` (valide, dash + gravité)
- When : tick complete
- Then : `velocity == Vector3(30, -24, 0)` (inchangé, safeguard ne trigger pas).
- Edge cases : chute profonde `velocity.y = -100` → autorisée (is_finite vrai).

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/movement/velocity_safeguard_test.gd` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene skeleton)
- Unlocks: None directes (safeguard est protection transversale, ne bloque pas autres stories)
