# Story 008: `_prev_position` per-tick update + reach constant

> **Epic**: Player Combat System
> **Status**: Done
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-003` (`_prev_position` ownership exclusive Combat, mise à jour FIN de `_physics_process`)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) D-3
**ADR Decision Summary**: `_prev_position: Vector3` owned exclusivement par CombatSystem (pas Movement). Initialisé à `_ready()` = `player.global_position`. **Mise à jour à la FIN de `_physics_process` Combat** (capture position tick N pour delta tick N+1). Permet au tick suivant de balayer entre prev (tick N) et current (tick N+1) — base anti-tunneling story-009.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `_physics_process` ordering DFS + parent (Player) avant child (Combat) garantit que `player.global_position` au moment de Combat read = position post-Movement (ADR-0001 + ADR-0006 D-1).

**Control Manifest Rules (Feature layer)**:
- Required: `_prev_position` update à FIN de `_physics_process` (pas début, pas dans handler signal)
- Forbidden: lecture `_prev_position` depuis Movement ou autre système (Combat-private)
- Guardrail: reach constant `KATANA_REACH = 1.8 m` indépendant de `player.velocity` (Rule 11)

---

## Acceptance Criteria

*From GDD AC-CMB-43/44 + Rule 11/Rule 6 :*

- [ ] **AC-CMB-43** : `_state == SWINGING`, `player.velocity = Vector3(0, 0, -30)` (dash max) → `ShapeCast3D.shape.height == KATANA_REACH == 1.8 m ± 0.001` (constant, pas augmenté par velocity)
- [ ] **AC-CMB-44** : swing actif, joueur déplace `Vector3(0, 0, -0.5)` entre tick 2 et tick 3 → `ShapeCast3D.global_transform.origin` mis à jour au tick 3 (utilise `_prev_position` cached tick 2 + offset reach), pas figé au tick 0. `aim_forward` lu à jour chaque tick
- [ ] `_prev_position` initialisé à `_ready()` = `player.global_position`
- [ ] `_prev_position` mis à jour à la **FIN** de `_physics_process` (last statement) = `player.global_position` du tick courant
- [ ] **Forbidden grep** : aucune écriture `_prev_position` hors `combat_system.gd` (`grep -rE 'combat\._prev_position\s*=' src/` ne doit retourner que combat_system.gd)

---

## Implementation Notes

*Derived from ADR-0006 D-3 + GDD Rule 6 r1 ShapeCast tick-par-tick :*

- Variable : `var _prev_position: Vector3 = Vector3.ZERO`
- Dans `_ready()` : `_prev_position = player.global_position`
- Dans `_physics_process(delta)` :
  ```gdscript
  func _physics_process(delta: float) -> void:
      # ... cooldown decrement, state machine logic, sweep si Swinging
      # FIN OBLIGATOIRE : capture pour next tick
      _prev_position = player.global_position
  ```
- Pour positionner le sweep au tick courant pendant Swinging (avant le ShapeCast update) :
  ```gdscript
  var aim := camera_system.aim_forward  # lu à jour CHAQUE tick
  if not _validate_aim(aim):
      return
  var sweep_origin := player.global_position + aim * (KATANA_REACH / 2.0)
  $ShapeCast3D.global_transform = Transform3D(_build_capsule_basis(aim), sweep_origin)
  ```
- `KATANA_REACH = 1.8` constant — JAMAIS multiplié par `velocity.length()` ou similaire (pas de velocity lookahead, Rule 11)

---

## Out of Scope

- Story 009 : N_SUBSTEPS=3 anti-tunneling (substeps entre `_prev_position` et current)
- Story 010 : tick-0 overlap mitigation (intersect_shape pour overlap initial)

---

## QA Test Cases

- **AC-1** Reach constant under dash velocity
  - Given: Combat `Swinging`, `player.velocity = Vector3(0, 0, -30)` (dash 30 m/s)
  - When: ShapeCast3D config tick 0
  - Then: `$ShapeCast3D.shape.height == 1.8 ± 0.001` (constant)
  - Edge cases: velocity 0 m/s — même valeur ; velocity 1000 m/s (synthétique) — toujours 1.8

- **AC-2** Per-tick position update
  - Given: swing actif tick 2, `_prev_position = Vector3(0, 0, 0)` (capture fin tick 2 = origin), tick 3 commence avec `player.global_position = Vector3(0, 0, -0.5)` (joueur a bougé 0.5 m sur Z)
  - When: `_physics_process` tick 3 execute
  - Then: `$ShapeCast3D.global_transform.origin` calculé avec `player.global_position = Vector3(0, 0, -0.5)` (pas figé tick 0)
  - Edge cases: joueur immobile entre ticks — origin identique 2 ticks consécutifs

- **AC-3** _prev_position end-of-tick update
  - Given: tick N, `player.global_position = Vector3(1, 0, 0)` au début, joueur ne bouge pas pendant `_physics_process`
  - When: fin `_physics_process` Combat
  - Then: `_prev_position == Vector3(1, 0, 0)`
  - Edge cases: `_physics_process` early-return (Combat Dead) — `_prev_position` pas mis à jour ce tick (acceptable, tick suivant capture la nouvelle position)

- **AC-4** _prev_position init at ready
  - Given: scene boot, Player à `Vector3(5, 0, 0)`
  - When: Combat `_ready()`
  - Then: `_prev_position == Vector3(5, 0, 0)`
  - Edge cases: `_ready()` avant Player `_ready()` (DFS order garantit Player parent ready avant Combat child — pas un cas réel)

- **AC-5** Ownership grep
  - Given: codebase complet
  - When: `grep -rnE '\._prev_position\s*=' src/` (excluant `combat_system.gd`)
  - Then: zéro match (sauf combat_system.gd lui-même)
  - Edge cases: aucun système autre que Combat ne doit lire/écrire `_prev_position`

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/prev_position_per_tick_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (state machine), Story 007 (sweep position)
- Unlocks: Story 009 (anti-tunneling substeps), Story 010 (tick-0 overlap mitigation)
