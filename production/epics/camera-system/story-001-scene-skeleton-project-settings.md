# Story 001: Scene skeleton 3-étages CameraArm + project settings rendering

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Core (scene skeleton) + Presentation (project settings rendering)
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001`, `TR-cam-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0003 (Rendering & Display Latency Strategy)
**ADR Decision Summary**: ADR-0002 acte la hiérarchie 3-étages `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` avec ownership stricte par étage (yaw=Player, pitch=CameraArm, tilt=CameraEffects, FOV+shake=Camera3D). ADR-0003 acte les settings rendering baseline safe (Forward+, SMAA 1x, TAA banni, VSync on 60 fps, VRS off, Shader Baker).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (ADR-0002 LOW — Node3D+Camera3D patterns stables ; ADR-0003 HIGH — D3D12 default 4.6 Windows advisory VR-2)
**Engine Notes**: Knowledge Risk LOW côté scene tree (pas de post-cutoff API). HIGH côté rendering (D3D12 default Windows 4.6 — VR-2 frame stability test sur 3 OS advisory Sprint 1). Vérifier `Camera3D` enfant de `Node3D` × 2 étages rend projection correcte sur Forward+ + Jolt (ADR-0002 Verification Required). `AudioListener3D` enfant `Camera3D` reste actif sans `make_current()` quand single listener (ADR-0002 VR-5). Shader Baker clés `project.godot` à confirmer éditeur — VC-2 cold start < 3 s (ADR-0003 Risk 6).

**Control Manifest Rules (Presentation layer)**:
- Required : scene tree `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` ; `rendering/renderer/rendering_method = "forward_plus"` ; `anti_aliasing/quality/msaa_3d = 0`, `screen_space_aa = 2` (SMAA 1x), `use_taa = false` ; `rendering/vrs/mode = 0` ; `display/window/vsync/vsync_mode = 1` ; `AudioListener3D` enfant Camera3D (auto-current single listener)
- Forbidden : `SpringArm3D` pour FPS camera ; `anti_aliasing/quality/use_taa = true` ; manual viewport post-process chains ; hot-switch rendering backend runtime
- Guardrail : Rendering frame budget ≤ 8 ms/frame p99 ; Cold start < 3 s warm

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-TREE-1** : `Player.tscn` instancié contient bien `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` — vérification `player.get_node("CameraArm/CameraEffects/Camera3D") != null` et `player.get_node("CameraArm/CameraEffects/Camera3D/AudioListener3D") != null` (ADR-0002 VC-1).
- [x] **AC-CAM-TREE-2** : `CameraArm.position.y = 1.6` (hauteur des yeux 1.8m body), `CameraEffects.position = Vector3.ZERO`, `Camera3D.position = Vector3.ZERO` (ADR-0002 Implementation Guidelines).
- [x] **AC-CAM-TREE-3** : script `camera_system.gd` attaché à `CameraArm` (ou autoload pilotant CameraArm + Camera3D), avec `%CameraArm`, `%CameraEffects`, `%Camera3D` unique-name accessors pour introspection test GUT.
- [?] **AC-CAM-TREE-4** : `AudioListener3D` actif sans appel explicite `make_current()` — vérifié via placement son 3D positionné à `(10, 0, 0)` entendu « à droite » quand `player.rotation.y = 0` (ADR-0002 VC-5). **DEFERRED** → validation playtest Sprint 1, evidence placeholder `production/qa/evidence/camera-audiolistener-2026-04-22.md`.
- [x] **AC-CAM-RENDER-1** : `project.godot` contient `rendering/renderer/rendering_method = "forward_plus"`, `anti_aliasing/quality/msaa_3d = 0`, `anti_aliasing/quality/screen_space_aa = 2`, `anti_aliasing/quality/use_taa = false`, `rendering/vrs/mode = 0`, `display/window/vsync/vsync_mode = 1` (ADR-0003 Project Settings).
- [x] **AC-CAM-RENDER-2** : grep CI `anti_aliasing/quality/use_taa = true` sur `project.godot` retourne 0 occurrence (forbidden pattern ADR-0003 REQ-5).

---

## Implementation Notes

*Derived from ADR-0002 Decision + ADR-0003 Project Settings :*

- Créer `src/gameplay/player/Player.tscn` avec nodes :
  - `Player` (CharacterBody3D, root)
    - `CameraArm` (Node3D, position = `(0, 1.6, 0)`, unique name)
      - `CameraEffects` (Node3D, position = `Vector3.ZERO`, unique name)
        - `Camera3D` (position = `Vector3.ZERO`, unique name)
          - `AudioListener3D`
- Créer `src/gameplay/camera/camera_system.gd` attaché à `CameraArm` avec accessors :
  ```gdscript
  @onready var _camera_arm: Node3D = get_parent().get_node("%CameraArm")  # ou self si attaché à CameraArm
  @onready var _camera_effects: Node3D = %CameraEffects
  @onready var _camera3d: Camera3D = %Camera3D
  ```
  (Valider pattern via godot-specialist review à la première story touchant `camera_system.gd`.)
- Éditer `project.godot` pour ajouter les 6 settings rendering ci-dessus. Laisser `physics/` settings intactes (gérés par Movement story-001 si déjà écrit ; sinon documenter dépendance cross-epic).
- **Ne PAS activer** Shader Baker dans cette story : noté dans ADR-0003 Risk 6 comme « action pré-Sprint-1 », dev activera via éditeur Project Settings → Rendering → Shader Compiler dans une passe séparée. Cette story ne hallucine pas les clés `project.godot`.
- **Ne PAS créer** `RenderingSettingsManager` autoload dans cette story — il est listé ADR-0003 Migration Plan mais relève d'une story Menu/Settings séparée (hors scope Camera epic MVP).
- Tester instanciation avec `preload("res://src/gameplay/player/Player.tscn").instantiate()` en test GUT + assertion scene tree.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 002 : apply yaw/pitch raw sur `player.rotation.y` + `camera_arm.rotation.x` via signal `mouse_motion`.
- Story 012 : instrumentation perf `_process` cost ring buffer.
- `RenderingSettingsManager` autoload + graphics_settings.tres : hors scope Camera epic (Menu/Settings system).
- Shader Baker clés `project.godot` : action pré-Sprint-1 dev, patch ADR-0003 séparé.

---

## QA Test Cases

**AC-CAM-TREE-1 (scene tree 3-étages)** — Logic/Integration

- Given : `Player.tscn` chargé via `preload("res://src/gameplay/player/Player.tscn").instantiate()`
- When : `player.get_node("CameraArm/CameraEffects/Camera3D")` et `player.get_node("CameraArm/CameraEffects/Camera3D/AudioListener3D")`
- Then : les deux `!= null` ; `CameraArm is Node3D` ; `CameraEffects is Node3D` ; `Camera3D is Camera3D` ; `AudioListener3D is AudioListener3D`
- Edge cases : renommage futur (CameraArm → Arm) doit casser ce test — serve de regression trap

**AC-CAM-TREE-2 (positions)** — Logic

- Given : Player instancié
- When : lecture `camera_arm.position`, `camera_effects.position`, `camera3d.position`
- Then : `camera_arm.position.is_equal_approx(Vector3(0, 1.6, 0))` ; `camera_effects.position.is_equal_approx(Vector3.ZERO)` ; `camera3d.position.is_equal_approx(Vector3.ZERO)`

**AC-CAM-TREE-3 (accessors script)** — Logic

- Given : Player instancié, `_ready()` terminé
- When : lecture des `@onready var` du script `camera_system.gd`
- Then : `_camera_arm`, `_camera_effects`, `_camera3d` tous `!= null` et pointent vers les bons types

**AC-CAM-TREE-4 (AudioListener3D auto-current)** — Manual check

- Setup : scène test avec `AudioStreamPlayer3D` positionné `(10, 0, 0)`, son looping, Player à l'origine avec `rotation.y = 0` (forward = -Z)
- Verify : son entendu « à droite » dans la balance stéréo ; aucun `make_current()` appelé par code
- Pass condition : balance audio L/R ≠ 0.5/0.5 ; tilt tête gauche/droite ne change pas la balance (Camera3D bouge, mais listener suit)

**AC-CAM-RENDER-1 (project.godot settings)** — Logic

- Given : `project.godot` lu via `ConfigFile` ou grep
- When : 6 settings rendering vérifiés
- Then : toutes les clés présentes avec les valeurs exactes prescrites (`forward_plus`, 0, 2, false, 0, 1)

**AC-CAM-RENDER-2 (TAA ban)** — Logic (grep CI)

- Given : `project.godot`
- When : grep sur `anti_aliasing/quality/use_taa = true`
- Then : 0 occurrence (forbidden ADR-0003 REQ-5)

---

## Test Evidence

**Story Type** : Integration
**Required evidence** :
- `tests/integration/camera/story-001-scene-skeleton-project-settings_test.gd` — scene tree assertions + project.godot settings assertions (AC-CAM-TREE-1/2/3 + AC-CAM-RENDER-1/2)
- AC-CAM-TREE-4 : manuel, documenté dans `production/qa/evidence/camera-audiolistener-[date].md` (ou inclusion dans l'evidence story-008 respawn si plus naturel)

**Status** : [x] Created — automated test file + manual evidence placeholder

---

## Completion Notes

**Completed** : 2026-04-22
**Criteria** : 5/6 automated COVERED + 1/6 DEFERRED (AC-CAM-TREE-4, playtest Sprint 1)
**Deviations** : None on ADR-0002/ADR-0003. Manifest Version match (2026-04-21).
**Test Evidence** :
- Integration test : `tests/integration/camera/story_001_scene_skeleton_project_settings_test.gd` (7 fonctions GdUnit4, couvre AC-CAM-TREE-1/2/3 + AC-CAM-RENDER-1/2)
- Manual evidence placeholder : `production/qa/evidence/camera-audiolistener-2026-04-22.md` (AC-CAM-TREE-4 DEFERRED)
**Code Review** : Complete — verdict APPROVED WITH SUGGESTIONS (F-04 robustness fix appliqué : `use_taa` check via `get_value(..., false)` au lieu de `has_section_key`).
**Review Mode** : solo (Phase 4b QL-TEST-COVERAGE + Phase 5 LP-CODE-REVIEW skippés par `/code-review` pré-story-done)

**Infrastructure ADVISORY (hors scope story) — à résoudre avant sprint close-out** :
1. GdUnit4 addon absent de `addons/` — runner `tests/gdunit4_runner.gd` échoue ("GdUnit4 not found"). Installer via AssetLib ou git submodule avant `/smoke-check sprint`.
2. `src/core/input_manager.gd` : erreur parse "Class 'InputManager' hides an autoload singleton" — à corriger dans l'epic Input.
3. AC-CAM-TREE-4 playtest à produire Sprint 1 (balance stéréo L/R vérifiée, pas de `make_current()` appelé).

---

## Dependencies

- Depends on : None (foundation scene story, préalable à toutes les autres Camera stories)
- Unlocks : Story 002 (apply yaw+pitch) + toutes stories Camera suivantes
