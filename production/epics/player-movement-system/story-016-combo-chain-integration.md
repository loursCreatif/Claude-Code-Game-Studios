# Story 016: Combo chain full integration (dash→wall-run→wall-jump)

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (autorité `_physics_process`, Jolt CCD), ADR-0005 (signal order intra-tick D-6)
**Decision Summary**: Test integration bout-en-bout AC-MV-90 validant : dash → momentum → wall-run entry → wall-jump → double-jump bloqué (décision Martin r3 A). Assertions sur state sequence + velocity targets + signal order + air_jumps_used.

**Engine**: Godot 4.6 | **Risk**: MEDIUM (Jolt CCD à vitesse max dash + wall-run, no-tunneling à vmax)

**Control Manifest Rules**:
- Required: séquence scriptée déterministe (pas de random) ; assertions par étape (pas au post-seulement) ; chaîne valide toutes capabilities = true.
- Forbidden: relaxation assertions si intermediate state non-déterministe (si pb → fix implem, pas l'assertion).
- Guardrail: Jolt zero warnings (ADR-0001 VC-3 smoke).

---

## Acceptance Criteria

*From GDD AC-MV-90 r3 rewrite :*

- [ ] **AC-MV-90** : GIVEN `can_dash=true`, `can_wall_run=true`, `can_air_jump=true`, `air_jumps_used=0`, Player Grounded face à mur vertical à 4 m, capabilities actives. WHEN script GUT exécute :
  1. `simulate_action_press(&"dash")` (forward)
  2. attendre `DASH_DURATION + DASH_MOMENTUM_WINDOW = 0.3s`
  3. `simulate_action_press(&"move_right")` (vers mur, on suppose mur à droite)
  4. attendre wall-run activation (`_state == State.WALL_RUNNING`)
  5. `simulate_action_press(&"jump")`
  6. attendre `_state == State.AIRBORNE`
  
  THEN toutes les assertions passent :
  - **Après dash (post-0.3s)** : `_state ∈ {State.AIRBORNE, State.GROUNDED}`, `velocity.length() > 0`.
  - **Après wall-run entry (step 4)** : `_state == State.WALL_RUNNING` dans ≤ 3 physics ticks après step 3.
  - **Après wall-jump (step 5)** : `velocity.y ≈ WALL_JUMP_UP (6.5) ± 0.1`, `air_jumps_used == MAX_AIR_JUMPS (=1)` (décision Martin r3 A), `_state == State.AIRBORNE`.
  - **Double-jump suivant wall-jump (post step 6)** : `simulate_action_press(&"jump")` → rien (double-jump bloqué — AC-MV-35).
- [ ] **Signal order conforme** (via consumer stub) : `dash_started` → `dash_ended` → `wall_run_entered` → `wall_run_exited` → `wall_jumped`. Le 2e jump post-wall-jump → 0 signal (pas de double-jump).
- [ ] **Setup scène combo** : utilise scène `tests/scenes/combo_chain_test.tscn` — Player + mur vertical positionné pour wall-run reproductible + géométrie sol plate.
- [ ] **Deterministic** : seed fixe, 100 iterations reproductibles (même timings tick-à-tick).
- [ ] **Jolt smoke** (sous-ensemble VC-3 ADR-0001) : aucun `push_warning` Jolt capturé pendant la chaîne.

---

## Implementation Notes

*Derived from GDD AC-MV-90 r3 + décisions Martin r3 A :*

- Scène `tests/scenes/combo_chain_test.tscn` :
  - Player à `(0, 1, 0)` facing `-Z` (forward)
  - Sol plat `StaticBody3D` plane 20×20 à y=0
  - Mur vertical `StaticBody3D` à `x=4, z=-2` (sera touché par `%WallRayRight` après dash forward)
  - Toutes capabilities set via `player.set_capability(&"dash", true)`, etc.
- Test `tests/integration/movement/combo_chain_test.gd` :
  ```gdscript
  func test_combo_chain_dash_wallrun_walljump_blocks_doublejump():
      var player = preload("res://tests/scenes/combo_chain_test.tscn").instantiate()
      add_child(player)
      var sig_log := []
      for sig in ["dash_started", "dash_ended", "wall_run_entered", "wall_run_exited", "wall_jumped", "died", "respawned", "attacked"]:
          player.connect(sig, func(...args): sig_log.append(sig))
      
      # Enable all capabilities
      player.set_capability(&"dash", true)
      player.set_capability(&"air_jump", true)
      player.set_capability(&"wall_run", true)
      
      # Step 1 — dash forward
      simulate_action_press(&"dash")
      await wait_ticks(6)  # DASH_DURATION
      assert_eq(player.state, State.AIRBORNE) # post-dash
      assert_gt(player.velocity.length(), 0.0)
      
      # Step 2 — wait momentum end
      await wait_ticks(12)  # MOMENTUM_WINDOW = 200ms = 12 ticks
      
      # Step 3 — steer toward wall
      simulate_action_press(&"move_right")
      await wait_until_state(State.WALL_RUNNING, 3)
      assert_eq(player.state, State.WALL_RUNNING)
      var pre_walljump_air_jumps = player.air_jumps_used
      
      # Step 5 — wall-jump
      simulate_action_press(&"jump")
      await wait_ticks(1)
      assert_eq(player.state, State.AIRBORNE)
      assert_almost_eq(player.velocity.y, 6.5, 0.1)
      assert_eq(player.air_jumps_used, 1)  # MAX_AIR_JUMPS (décision Martin r3 A)
      
      # Step 6 — try double-jump (should be blocked)
      var velocity_before = player.velocity
      simulate_action_press(&"jump")
      await wait_ticks(1)
      # velocity.y should still be decaying from gravity, not jumped to AIR_JUMP_VELOCITY=6.5
      assert_lt(player.velocity.y, velocity_before.y + 1.0, "AC-MV-35 double-jump bloqué post wall-jump")
      
      # Signal order assertion
      var expected_order = ["dash_started", "dash_ended", "wall_run_entered", "wall_run_exited", "wall_jumped"]
      assert_eq(sig_log.slice(0, 5), expected_order)
  ```
- `wait_ticks(n)`, `wait_until_state(...)` sont helpers GUT basés sur `await get_tree().physics_frame`.
- Jolt smoke capture : wrap test dans `push_warning` redirect (ou check `Performance` debug monitor warnings count).

---

## Out of Scope

- Combat hitbox pendant dash → Combat epic
- Camera tilt pendant wall-run → Camera epic
- VFX trails → VFX epic
- Full moveset fuzz testing (multi-séquences alt) → post-MVP Polish

---

## QA Test Cases

**AC-MV-90 — full chain + double-jump bloqué** :
- Given : scène combo_chain_test, all capabilities true, Player facing -Z, mur à x=4
- When : dash forward + wait 0.3s + steer right + wait wall-run + jump + wait + jump (tentative double-jump)
- Then : state sequence {GROUNDED → DASHING → AIRBORNE → WALL_RUNNING → AIRBORNE} ; velocity.y post-wall-jump ≈ 6.5 ; air_jumps_used == 1 ; 2e jump fait rien.
- Edge cases : 100 itérations reproductibles (seed fixe Jolt).

**Signal order** :
- Given : consumer stub log chronological
- When : chaîne exécutée
- Then : séquence signals = ["dash_started", "dash_ended", "wall_run_entered", "wall_run_exited", "wall_jumped"] exactement.

**Jolt zero warnings** :
- Given : warning capture activé
- When : chaîne full
- Then : 0 Jolt push_warning.

---

## Test Evidence

**Story Type**: Integration (BLOCKING)
**Required evidence**: `tests/integration/movement/combo_chain_test.gd` + scène `tests/scenes/combo_chain_test.tscn` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-015 (all implementation + signals + mocks patterns)
- Unlocks: Story 017 (playtest valide feel de la chaîne)
