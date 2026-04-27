# Story 013: Capability gating (can_dash / can_air_jump / can_wall_run)

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (`_physics_process` autorité ; lecture flags via interface Upgrade API — Upgrade epic downstream)
**Decision Summary**: MovementController expose `can_dash`/`can_air_jump`/`can_wall_run` read-only comme mirrors ; défauts `false` sur save neuve ; gating strict dans logique state machine (pas d'entrée Dashing/double-jump/WallRunning si flag false).

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: properties read-only `can_dash`/`can_air_jump`/`can_wall_run` exposées via getter pattern ; valeurs défaut `false` au spawn fresh ; gating vérifié AVANT entrée des 3 états gated.
- Forbidden: flip `can_*` flags depuis signal handler consumer (D-7) ; lecture `Upgrade.can_*` direct (UpgradeSystem epic n'existe pas encore — placeholder variable interne).
- Guardrail: test save neuve = tous flags false (AC-MV-60).

---

## Acceptance Criteria

*From GDD Rule 10 + AC-MV-60/61/13/21 :*

- [ ] **AC-MV-60** : GIVEN save neuve (fresh start), THEN `can_air_jump=false`, `can_dash=false`, `can_wall_run=false`.
- [ ] **AC-MV-61** : GIVEN `player.can_dash = true` injecté directement (simulant Upgrade System), WHEN input `dash` exécuté au tick suivant, THEN `velocity.xz.length() == DASH_SPEED ± 0.1` pendant DASH_DURATION.
- [ ] **Gating dash** (rappel AC-MV-21) : GIVEN `can_dash=false`, WHEN `dash` pressed, THEN rien (pas de transition DASHING, pas de cooldown déclenché).
- [ ] **Gating double-jump** (rappel AC-MV-13) : GIVEN `can_air_jump=false`, WHEN Airborne + `jump` pressed, THEN `velocity.y` inchangée.
- [ ] **Gating wall-run** : GIVEN `can_wall_run=false`, Airborne, speed > WALL_RUN_MIN_SPEED, raycast hit, THEN aucune transition vers WallRunning (reste Airborne).
- [ ] **Properties read-only exposées** :
  ```gdscript
  var can_dash: bool : get: return _can_dash
  var can_air_jump: bool : get: return _can_air_jump
  var can_wall_run: bool : get: return _can_wall_run
  ```
  (pattern godot-specialist F7, identique à `state`/`wall_normal`/etc.)
- [ ] **Setter interne** (pas API publique) pour Upgrade system futur : méthode `set_capability(cap: StringName, enabled: bool) -> void` qui mute `_can_dash`/`_can_air_jump`/`_can_wall_run` selon `cap` (`&"dash"`, `&"air_jump"`, `&"wall_run"`). **Appelée uniquement par UpgradeSystem (ou mock en test)**.

---

## Implementation Notes

*Derived from GDD Rule 10 + Interactions table (Upgrade System amont) + Published API pattern F7 :*

- Refactor variables placeholder des stories 004/005/006 :
  ```gdscript
  # Private backing
  var _can_dash: bool = false
  var _can_air_jump: bool = false
  var _can_wall_run: bool = false
  
  # Read-only public API (pattern F7)
  var can_dash: bool : get: return _can_dash
  var can_air_jump: bool : get: return _can_air_jump
  var can_wall_run: bool : get: return _can_wall_run
  ```
- Method `set_capability(cap: StringName, enabled: bool) -> void` :
  ```gdscript
  func set_capability(cap: StringName, enabled: bool) -> void:
      match cap:
          &"dash": _can_dash = enabled
          &"air_jump": _can_air_jump = enabled
          &"wall_run": _can_wall_run = enabled
          _: push_error("Unknown capability %s" % cap)
  ```
- S'assurer que Stories 004/005/006 lisent `_can_dash` (ou `can_dash` public, identique en lecture) dans leurs checks de gating.
- Comportement save neuve : les defaults `false` sont les valeurs initiales des backing vars — pas de logique de save/load ici (celle-ci est G-2b post-MVP, TR-inp-009/TR-cam-006 Gap G-2).

---

## Out of Scope

- Interface UpgradeSystem concrète (epic downstream, pas encore créé)
- Save/Load capabilities (Feature layer post-MVP, Gap G-2b ADR-0014)
- Remapping dynamique runtime (Upgrade prompts, UI shop) → Feature epic

---

## QA Test Cases

**AC-MV-60 — fresh start defaults** :
- Given : Player scene fresh instantiate
- When : lecture `player.can_dash`, `player.can_air_jump`, `player.can_wall_run`
- Then : `false`, `false`, `false`.

**AC-MV-61 — dash enabled via setter** :
- Given : `player.set_capability(&"dash", true)` + cooldown=0
- When : `simulate_action_press(&"dash")` tick suivant, wish_dir forward
- Then : `velocity.xz.length() ≈ DASH_SPEED (=30) ± 0.1` pendant DASH_DURATION ; state transition DASHING.

**AC-MV-21 rappel — dash gated off** :
- Given : `can_dash=false` (fresh)
- When : `simulate_action_press(&"dash")`
- Then : pas de transition DASHING, pas de `_dash_cooldown_timer` déclenché.

**AC-MV-13 rappel — double-jump gated** :
- Given : Airborne, `air_jumps_used=0`, `can_air_jump=false`
- When : `jump` pressed
- Then : `velocity.y` inchangée, `air_jumps_used == 0`.

**Gating wall-run** :
- Given : Airborne, speed > 5, mur proche, `can_wall_run=false`
- When : raycasts hit
- Then : `_state == State.AIRBORNE` (pas WallRunning), gravité normale maintenue.

**set_capability unknown** :
- Given : `player.set_capability(&"unknown_cap", true)`
- When : call
- Then : push_error capturé, aucune mutation des `_can_*`.

**Read-only enforcement** :
- Given : debug build
- When : tentative `player.can_dash = true` (sans passer par set_capability)
- Then : erreur GDScript "setter not found" (read-only pattern F7).

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: `tests/unit/movement/capability_gating_test.gd` — must exist and pass ; également smoke check `production/qa/smoke-movement-capabilities-[date].md` avec fresh scene capture.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001, 004, 005, 006 (chaque stockait placeholder boolean to refactor ici)
- Unlocks: UpgradeSystem epic futur (peut appeler `player.set_capability(...)`)
