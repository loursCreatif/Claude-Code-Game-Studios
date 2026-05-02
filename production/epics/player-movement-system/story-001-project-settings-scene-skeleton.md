# Story 001: Project Settings + Scene skeleton + State enum

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-002`, `TR-mov-004`, `TR-mov-007`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADRs Governing Implementation**: ADR-0001 (Physics Rate 60 Hz + Jolt), ADR-0002 (Camera Scene Tree CameraArm)
**Decision Summary**: Project settings `physics_ticks_per_second=60`, `max_physics_steps_per_frame=4`, `physics_engine="JoltPhysics3D"`, `default_gravity=0.0`. Scene tree 3-étages `CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D` avec `physics_interpolation_mode=OFF` sur root Player.

**Engine**: Godot 4.6 | **Risk**: HIGH (VR-2 D3D12 4.6 Windows default + Jolt 4.6 default — advisory Sprint 1)
**Engine Notes**: Jolt est default 4.6 mais mérite vérif explicite dans `project.godot`. `default_gravity=0.0` est un override critique (défaut 9.8). `%WallRayLeft/%WallRayRight` pattern unique-name requiert Godot 4.5+.

**Control Manifest Rules (Core layer)**:
- Required: project settings physics_ticks_per_second=60 + max_physics_steps_per_frame=4 + physics_engine="JoltPhysics3D" + default_gravity=0.0 ; `physics_interpolation_mode=OFF` root Player ; scene tree `CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D` ; `state: State` read-only via getter pattern.
- Forbidden: mutation `velocity/position/rotation` en `_process()` ; SpringArm3D pour FPS ; Movement écrit sur CameraArm/CameraEffects/Camera3D.
- Guardrail: tests GUT déterministes isolés, `tests/smoke/jolt_compatibility_test.gd` zéro warnings.

---

## Acceptance Criteria

*Scoped to cette story (subset GDD AC-MV-* + ADR VCs) :*

- [ ] `project.godot` contient les 4 settings physics (ticks=60, max_steps=4, engine="JoltPhysics3D", default_gravity=0.0) avec commentaires de traçabilité ADR-0001.
- [ ] Scene `Player.tscn` instanciable ; GUT `assert(player.get_node("CameraArm/CameraEffects/Camera3D/AudioListener3D") != null)` passe (ADR-0002 VC-1).
- [ ] `Player.physics_interpolation_mode == PHYSICS_INTERPOLATION_MODE_OFF`.
- [ ] `%WallRayLeft` et `%WallRayRight` présents en enfants directs du CharacterBody3D avec unique-name scope activé, longueur `capsule_radius + WALL_DETECT_MARGIN ≈ 0.8 m` (TR-mov-002).
- [ ] Script `movement_controller.gd` définit `enum State { GROUNDED, AIRBORNE, DASHING, WALL_RUNNING, DEAD }` et expose `state: State` read-only via `var _state: State = State.GROUNDED ; var state: State : get: return _state` (ADR-0005 REQ-8 + godot-specialist F7).
- [ ] Aucune logique gameplay encore — `_physics_process` vide ou stub `pass`. `_ready` contient assertion invariant `assert(RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE)` même si constantes définies en placeholder (ADR-0005 VC-7).

---

## Implementation Notes

*Derived from ADR-0001 + ADR-0002 Implementation Guidelines:*

- `project.godot` additions (bloc `[physics]`) cités verbatim ADR-0001 §Decision > Project Settings.
- Scene tree : créer `Player.tscn` avec racine CharacterBody3D nommée `Player`. Enfants directs : `CameraArm` (Node3D, position locale `Vector3(0, 1.6, 0)`), `CollisionShape3D` (capsule radius 0.35), `%WallRayLeft` (RayCast3D, unique-name scope on, target_position `Vector3(-0.8, 0, 0)`), `%WallRayRight` (target_position `Vector3(0.8, 0, 0)`). Sous `CameraArm` : `CameraEffects` (Node3D) → `Camera3D` (fov 90) → `AudioListener3D`.
- `CameraArm.position.y=1.6` ; `CameraEffects.position=Vector3.ZERO` ; `Camera3D.position=Vector3.ZERO`.
- State enum canonique 5 valeurs, stocke `_state` private, expose `state` read-only.
- Pas de logique state machine ici — juste la coquille.

---

## Out of Scope

- Grounded movement → Story 002
- Gravity & Airborne → Story 003
- Jump/Dash/Wall-run → Stories 004-007
- Signals → Story 009
- `is_dashing`, `wall_normal`, `dash_cooldown_*` properties → stories d'implémentation correspondantes

---

## QA Test Cases

**AC-1 — Project settings appliqués** :
- Given : `project.godot` parsé
- When : lecture via `ProjectSettings.get_setting()`
- Then : `physics/common/physics_ticks_per_second == 60`, `physics/common/max_physics_steps_per_frame == 4`, `physics/3d/physics_engine == "JoltPhysics3D"`, `physics/3d/default_gravity == 0.0`
- Edge cases : assert sur tous les 4 settings séparément ; message erreur explicite ADR-0001 référencé.

**AC-2 — Scene tree structure** :
- Given : `Player.tscn` instanciée en test scene
- When : navigation hiérarchique
- Then : `player.get_node("CameraArm") is Node3D`, `player.get_node("CameraArm/CameraEffects") is Node3D`, `player.get_node("CameraArm/CameraEffects/Camera3D") is Camera3D`, `player.get_node("CameraArm/CameraEffects/Camera3D/AudioListener3D") is AudioListener3D`.
- Edge cases : script également vérifie que `%WallRayLeft` et `%WallRayRight` résolvent via unique-name.

**AC-3 — Physics interpolation OFF root** :
- Given : Player instantiated
- When : `player.physics_interpolation_mode` lu
- Then : `== Node.PHYSICS_INTERPOLATION_MODE_OFF`

**AC-4 — State enum + read-only property** :
- Given : MovementController instance
- When : `var s := player.state` puis tentative `player.state = State.AIRBORNE` (sans setter)
- Then : lecture retourne `State.GROUNDED` (valeur initiale) ; tentative setter → erreur GDScript debug build (pas de setter exposé).

**AC-5 — `_ready` invariant assert RESPAWN_DELAY** :
- Given : script movement_controller.gd avec `const RESPAWN_DELAY_MS = 50.0`, `const DISPLAY_TICK_RATE = 60.0`
- When : `_ready()` exécuté
- Then : zéro `push_error` ; la condition `50.0 >= 1000.0/60.0 ≈ 16.66` passe.
- Edge cases : si RESPAWN_DELAY_MS configuré à 10 (invalide), `assert` doit faire crash en debug.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/movement/project_settings_and_scene_test.gd` — must exist and pass.

**Status**: [x] Implemented — `tests/integration/movement/project_settings_and_scene_test.gd` (8.5 KB, GdUnit4, AC-1→AC-6)

---

## Dependencies

- Depends on: None (première story Movement)
- Unlocks: 002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017
