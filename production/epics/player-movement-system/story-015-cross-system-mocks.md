# Story 015: Cross-system integration mocks (Combat + Checkpoint)

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0005 (D-10 outbound-only — consumers self-connect depuis leur `_ready`)
**Decision Summary**: Mocks MockCombatSystem + MockCheckpointSystem valident que Movement API publique est consommable sans que MovementController ne les référence. Test AC-MV-80 (combat lit velocity pendant is_dashing) + AC-MV-81 (set_checkpoint + die respawn position).

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: mocks vivent dans `tests/integration/movement/mocks/` (pas `src/`) ; connectent signals depuis leur `_ready` ; ne mutent jamais état Movement (pattern D-7).
- Forbidden: mock qui mute `player.velocity = ...`, `player.die()`, `player._state = ...`.
- Guardrail: tests reproductibles, pas de dépendance à Combat/Checkpoint réels (epics downstream).

---

## Acceptance Criteria

*From GDD AC-MV-80 + AC-MV-81 :*

- [ ] **AC-MV-80 — MockCombat lit velocity pendant dash** : mock inline `MockCombatSystem extends Node` qui dans `_physics_process(delta)` : (a) récupère player via `get_node("../Player")`, (b) si `player.is_dashing == true`, écrit `last_sweep_velocity: Vector3 = player.velocity` ; initialisé à `Vector3.ZERO`. Lorsque joueur dashe avec `DASH_SPEED=30` forward, `MockCombatSystem.last_sweep_velocity.length() ≈ 30 ± 0.1` pendant `is_dashing == true`.
- [ ] **AC-MV-81 — Checkpoint set + respawn** : GIVEN trigger crossed (mock), WHEN `player.set_checkpoint(new_pos)` appelé, THEN `die()` suivant respawne à `new_pos ± 0.01`.
- [ ] **Mock Combat D-10 compliant** : MockCombat n'est PAS référencé depuis `movement_controller.gd`. MockCombat lit Movement API publique (`player.is_dashing`, `player.velocity`).
- [ ] **Signal consumer test** : MockCombat peut connecter `player.attacked.connect(_on_attack)` depuis son `_ready` sans que Movement ait la moindre référence à MockCombat.
- [ ] **Mock Checkpoint D-7 compliant** : MockCheckpoint n'appelle jamais `player.velocity = ...`, ni `player._state = ...`. Il appelle `player.set_checkpoint(pos)` (API publique).

---

## Implementation Notes

*Derived from AC-MV-80 r3 rewrite + ADR-0005 D-10 exemple camera_system.gd _ready :*

- `tests/integration/movement/mocks/mock_combat_system.gd` :
  ```gdscript
  # MockCombat — consumer conforme ADR-0005 D-10
  extends Node
  class_name MockCombatSystem
  
  var last_sweep_velocity: Vector3 = Vector3.ZERO
  var attack_count: int = 0
  @onready var player: CharacterBody3D = get_node("../Player")
  
  func _ready() -> void:
      player.attacked.connect(_on_attacked)
  
  func _physics_process(_delta: float) -> void:
      if player.is_dashing:
          last_sweep_velocity = player.velocity
  
  func _on_attacked() -> void:
      attack_count += 1
  ```
- `tests/integration/movement/mocks/mock_checkpoint_system.gd` :
  ```gdscript
  extends Node
  class_name MockCheckpointSystem
  
  @onready var player = get_node("../Player")
  
  func set_checkpoint_at(pos: Vector3) -> void:
      player.set_checkpoint(pos)
  ```
- Test integration `tests/integration/movement/cross_system_mocks_test.gd` :
  - Scène instanciée : Player + MockCombatSystem + MockCheckpointSystem comme siblings sous un parent test node.
  - AC-MV-80 : enable dash, set forward, dash, mesurer `last_sweep_velocity` pendant DASH_DURATION.
  - AC-MV-81 : `checkpoint.set_checkpoint_at(Vector3(42, 1, 7))` → `player.die()` → attendre respawn delay → assert position.
- Vérifier via grep statique que `movement_controller.gd` ne contient PAS `MockCombat` / `MockCheckpoint` (couvert Story 011 lint).

---

## Out of Scope

- Implémentations réelles Combat/Checkpoint (epics downstream)
- Camera consumer mock (pattern identique, traité Camera epic)
- Audio/VFX/HUD mocks (out of scope Movement tests)

---

## QA Test Cases

**AC-MV-80 — MockCombat reads velocity pendant dash** :
- Given : Player Grounded, `can_dash=true`, cooldown=0, spawn position, facing forward (-Z) ; MockCombat attached sibling
- When : `simulate_action_press(&"dash")` + 6 ticks physics (DASH_DURATION = 100ms = 6 ticks)
- Then : durant les 6 ticks, `mock_combat.last_sweep_velocity.length() ≈ 30 ± 0.1` ; à tick 7 (post-dash), `player.is_dashing == false` donc mock ne met plus à jour.

**AC-MV-81 — Checkpoint respawn** :
- Given : Player à `(0,0,0)`, checkpoint default `(0,0,0)`, MockCheckpoint attached
- When : `mock_checkpoint.set_checkpoint_at(Vector3(42, 1, 7))`, puis `player.die()`, attendre 4 ticks (RESPAWN_DELAY+1)
- Then : `abs(player.global_position.distance_to(Vector3(42, 1, 7))) < 0.01`.

**MockCombat D-10 compliance** :
- Given : MockCombat instantiated dans test scene
- When : grep `movement_controller.gd` pour `MockCombat` / `MockCombatSystem`
- Then : 0 match (Movement n'a aucune knowledge de Combat).

**attacked signal propagation** :
- Given : MockCombat `_ready()` a connecté `attacked`
- When : input `attack` pressed tick N
- Then : `mock_combat.attack_count == 1` après `_physics_process` tick N (signal émis fin de tick Story 009).

**MockCheckpoint D-7 compliance — no state mutation** :
- Given : MockCheckpoint code review
- When : grep body pour `player.velocity =`, `player._state =`, `player.die(`
- Then : 0 match (mock appelle uniquement `set_checkpoint` API publique).

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/movement/cross_system_mocks_test.gd` + mocks dans `tests/integration/movement/mocks/` — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-013 (API complète), Story 009 (signals)
- Unlocks: Story 016 (combo chain réutilise pattern mock)
