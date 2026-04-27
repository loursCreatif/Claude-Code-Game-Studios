# Story 009: Signals declaration + typed contract test (CI debug blocking)

> **Epic**: player-movement-system
> **Status**: Done
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0005 (Movement Signals Architecture) — D-2 liste canonique 8 signaux, D-3 typage strict, D-4 emit physics_process only, D-1 direct typed signals sur MovementController
**Decision Summary**: 8 signaux typés directs sur MovementController (pas EventBus, pas sub-node). Payloads Vector3/float exclusivement, interdits Dictionary/Array/String/Node/Resource/StringName. Emit uniquement depuis `_physics_process` ou fonctions appelées depuis lui. Test de contrat typed strictness en CI debug build (VC-1).

**Engine**: Godot 4.6 | **Risk**: LOW (signals typés stables 4.0+ ; strictness debug-only documenté ADR-0005 REQ-1)

**Control Manifest Rules**:
- Required: liste canonique figée 8 signaux MVP ; payloads Vector3/float exclusivement ; emit ONLY depuis `_physics_process` ; test contrat typed signatures en CI debug (`tests/integration/movement/test_movement_signals_typed_contract.gd`).
- Forbidden: emit signal Movement depuis `_process`/`_input`/`_unhandled_input`/`_ready`/Timer signals ; Dictionary/Array/String/Node/Resource/StringName comme payload ; `emit_signal("name", {...})` Dict literal ; ajout d'un signal sans amendement ADR-0005.
- Guardrail: signal dispatch ≤ 0.1 ms/frame amorti (ADR-0005 VC-8, testé Story 014).

---

## Acceptance Criteria

*From ADR-0005 D-2 / D-3 / D-4 + VC-1 + Published API GDD l.82-91 :*

- [ ] **Déclaration 8 signaux MVP** exactement dans `movement_controller.gd`, signatures verbatim :
  ```gdscript
  signal dash_started(dash_dir: Vector3, dash_speed: float)
  signal dash_ended()
  signal wall_run_entered(wall_normal: Vector3)
  signal wall_run_exited()
  signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)
  signal died()
  signal respawned(spawn_position: Vector3)
  signal attacked()
  ```
- [ ] **Header commentaire** au-dessus des signals : `# Canonical list per ADR-0005 D-2. Ajout d'un signal = amendement ADR-0005.`
- [ ] **Emit points branchés** dans le code Stories 005-008 :
  - Story 005 Dash entry → `dash_started.emit(_dash_dir, DASH_SPEED)` au tick de transition `* → State.DASHING`.
  - Story 005 Dash exit → `dash_ended.emit()` au tick de transition `DASHING → *`.
  - Story 006 Wall-run entry → `wall_run_entered.emit(_wall_normal)` au tick `Airborne → WallRunning`.
  - Story 006 Wall-run exit → `wall_run_exited.emit()` au tick `WallRunning → *`.
  - Story 007 Wall-jump → `wall_jumped.emit(_wall_normal, launch_vel)` (payload CAPTURÉ avant le reset `_wall_normal=Vector3.ZERO`).
  - Story 008 `die()` → `died.emit()` après state transition.
  - Story 008 `respawn()` → `respawned.emit(pos)` après state transition.
  - Nouveau ici : `attacked.emit()` émis après state machine dans `_physics_process` si `was_pressed_this_tick(&"attack")` ET `_state != State.DEAD`.
- [ ] **Lieu d'émission** : chaque emit est à l'intérieur d'une fonction appelée depuis `_physics_process` (exclusivement). Vérifié par lint rule.
- [ ] **Test de contrat typed strictness (ADR-0005 VC-1)** : `tests/integration/movement/test_movement_signals_typed_contract.gd` — debug build mandatory, connecte Callable avec mauvaise signature (e.g. `func(dir: Vector3)` au lieu de `(dir: Vector3, speed: float)` pour `dash_started`), vérifie `push_error` / test `expect_error` passe.
- [ ] **Attacked idempotence** : `was_pressed_this_tick(&"attack")` retourne true max 1× par tick (garantie ADR-0004 D-1) → max 1 `attacked` par tick (ADR-0005 D-8).
- [ ] **`attacked` bloqué si Dead** : pas d'emit si `_state == State.DEAD` (ADR-0005 D-6 règle 2).

---

## Implementation Notes

*Derived from ADR-0005 D-1..D-4 + Published API GDD :*

- Positionner le bloc signals en section header immédiatement après `extends CharacterBody3D` et la doc de classe.
- Pour Story 007 wall-jump : capturer `launch_vel` et `_wall_normal` dans des locals AVANT la mutation `velocity = ... ; _wall_normal = Vector3.ZERO` ; emit avec les locals.
- Pour Story 008 `die()` : ordre D-6 (cf. Story 010 détaille l'ordre intra-tick) — ici ce qui compte : `died.emit()` appelé 1× par transition vers DEAD, protégé par early return idempotent.
- `attacked` forward : en fin de `_physics_process` (après state machine), `if _state != State.DEAD and InputManager.was_pressed_this_tick(&"attack"): attacked.emit()`.
- Signatures respectées strictement — types Vector3/float, JAMAIS Dictionary/Array/String.
- Aucune allocation dans les emits (Story 011 teste VC-2 zero-alloc).
- Test de contrat : utiliser `GutTest.watch_signals(player)` + `GutTest.assert_error_emitted` ou `push_error` redirect pour capturer. Alternative : `assert_signal_emitted_with_parameters`. Construire mock consumer avec 2 signatures (bonne + mauvaise), connect les deux, vérifier que mauvaise produit erreur debug.

---

## Out of Scope

- Ordre d'émission intra-tick (sortie avant entrée) + idempotence transitions → Story 010
- Zero-alloc benchmark + lint outbound-only → Story 011
- Dispatch performance cumul ≤ 0.1 ms → Story 014
- Ajout d'un 9e signal (interdit par D-2 sans amendement ADR)

---

## QA Test Cases

**AC-1 — déclaration 8 signaux signatures exactes** :
- Given : parse `movement_controller.gd`
- When : inspection `signal_list` via `Object.get_signal_list()`
- Then : exactement 8 signals avec noms + types payload conformes à ADR-0005 D-2.

**AC-2 — emit points branchés (état machine) par signal** :
- Given : Player + consumer stub qui enregistre tous signals reçus via `.connect()`
- When : séquence scripted (dash, wall-run entry/exit, wall-jump, die, respawn, attack)
- Then : chaque signal reçu avec payload typé correct ; ordre attendu respecté.

**AC-3 — typed contract mismatch déclenche `push_error` (VC-1)** :
- Given : debug build, consumer avec signature `func(dir: Vector3) -> void` connecté à `dash_started`
- When : test runtime fait `player.dash_started.connect(bad_callable)`
- Then : Godot push_error détecté (pattern `assert_error_emitted` ou interception logger).
- Edge cases : en release build, l'erreur est silencieuse — ce test ne tourne QU'EN DEBUG (ci config `godot --headless --debug`). Release build doit passer sans exécuter ce test (gate par `OS.has_feature("debug")`).

**AC-4 — emit lieu `_physics_process` only** :
- Given : grep static sur `movement_controller.gd`
- When : recherche `<signal_name>.emit(` à l'intérieur des blocs `func _process(`, `func _input(`, `func _unhandled_input(`, `func _ready(`
- Then : 0 match (lint vérifiera Story 011 VC-6).

**AC-5 — `attacked` forward et Dead gate** :
- Given : Player `_state=GROUNDED`, mock InputManager retourne true pour `was_pressed_this_tick(&"attack")` au tick N
- When : `_physics_process` tick N
- Then : `attacked` émis 1×. Tick N+1 (no attack press) : 0 emit.
- Edge cases : `_state=DEAD` + attack pressed → 0 emit.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/movement/test_movement_signals_typed_contract.gd` — must exist and pass in debug build CI.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-008 (state transitions existent avant de les émettre)
- Unlocks: Story 010 (ordre intra-tick + idempotence), Story 011 (zero-alloc + lint outbound-only), Story 015 (consumers mock)
