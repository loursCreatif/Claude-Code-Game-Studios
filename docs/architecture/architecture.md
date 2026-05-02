# CHROME://ASCENT — Master Architecture

## Document Status

| Field | Value |
|-------|-------|
| **Version** | 1.0 |
| **Last Updated** | 2026-04-21 |
| **Engine** | Godot 4.6 (Jolt default, Forward+, D3D12 Windows) |
| **Language** | GDScript |
| **GDDs Covered** | game-concept, systems-index, player-movement-system, input-system, camera-system |
| **ADRs Referenced** | ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0005 (all Accepted) |
| **Technical Director Sign-Off** | 2026-04-21 — APPROVED (solo mode — self-review) |
| **Lead Programmer Feasibility** | N/A — Solo mode (LP-FEASIBILITY skipped) |
| **Review Mode** | solo |

---

## 1. Architecture Principles

Five principes directeurs dérivés du game concept (4 pillars) et des ADRs Accepted. Toute décision technique doit pouvoir être rattachée à au moins un de ces principes.

1. **FLOW AVANT TOUT — Input latency intra-engine ≤ 16 ms p99.** Zero-alloc hot path. Autorité gameplay figée à `_physics_process` 60 Hz. VSync default ON + opt-in low-latency 144 Hz/G-Sync. (Pillar 1, ADR-0001, ADR-0003, ADR-0004.)
2. **PERFORMANCE CONSTANTE — Frame budget 16.6 ms hard-cap.** Physics ≤ 4 ms + Rendering ≤ 8 ms + Input ≤ 0.2 ms + Camera ≤ 0.5 ms + Signal dispatch ≤ 0.1 ms. Cible entry-level gaming laptop. (Pillar 4, ADR-0001, ADR-0002, ADR-0003, ADR-0005.)
3. **AUTORITÉ SYSTÈME EXCLUSIVE.** Chaque donnée mutable a un unique owner qui possède le write-access ; les autres systèmes lisent via signal ou getter read-only. Pas de mutation croisée. (ADR-0001, ADR-0002, ADR-0005 D-7 D-10.)
4. **COMMUNICATION PAR SIGNAUX TYPÉS DIRECTS.** Pas d'EventBus autoload pour les événements intra-gameplay. Pattern canonique : le producteur émet un signal typé, les consumers `connect()` explicitement. CONNECT_DEFERRED si lourd (critères a-d d'ADR-0005 D-5). (ADR-0004, ADR-0005.)
5. **DATA-DRIVEN TUNING.** Valeurs gameplay externalisées (`movement_tuning.tres`, `input_settings.tres`, `camera_settings.tres`). Aucune valeur gameplay hardcodée en `.gd`. (Coding standards, GDDs.)

---

## 2. Engine Knowledge Gap Summary

**Engine** : Godot 4.6 (Jan 2026). **LLM cutoff** : ≈ Godot 4.3 (May 2025).

### HIGH RISK Domains (verified against engine-reference)

| Domain | Change | ADR Coverage | Status |
|--------|--------|--------------|--------|
| Physics (Jolt default 4.6) | Jolt remplace GodotPhysics3D par défaut | ADR-0001 | ✅ Verified |
| Rendering Latency / D3D12 Windows default 4.6 | D3D12 launch-time only | ADR-0003 | ✅ Verified |
| Window dual-focus 4.6 (`focus_entered/exited` Controls vs `NOTIFICATION_APPLICATION_FOCUS_IN/OUT`) | 2 système focus distincts | ADR-0004 | ✅ Verified (3 HIGH advisory à lever Sprint 1) |
| Shader Baker 4.6 (export) | Sémantique baker conservatrice | ADR-0003 | ✅ Verified advisory |
| Accessibility AccessKit 4.5 | Nouveau TTS screen reader | — | Post-MVP (G-4) |

### MEDIUM RISK Domains

| Domain | Change | ADR Coverage |
|--------|--------|--------------|
| SDL3 gamepad 4.5 | Hors scope MVP | ADR-0004 note |
| FileAccess return types 4.4 | Save/Load impacte Feature tier | Post-MVP (G-2a/b) |
| @abstract class 4.5 | Optionnel | — |

### LOW RISK Domains

`Node`/`Node3D`/`Camera3D`/signaux/StringName/`_physics_process`/`_process` : API stable 4.0-4.6, inchangée.

### Advisory Engine Items à lever Sprint 1

- **VR-1** Valider Shader Baker 4.6 sémantique sur 1ère material custom (ADR-0003).
- **VR-2** Valider D3D12 launch-time Windows sur target laptop (ADR-0003).
- **VR-3** Valider dual-focus Godot 4.6 vs `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` OS-level (ADR-0004 VC-1).

---

## 3. System Layer Map

Les 22 systèmes de `systems-index.md` mappés en 5 couches. Dépendances strictement descendantes (foundation → platform jamais inverse).

```
┌────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                        │
│  HUD System · Menu System · VFX & Feedback System          │
├────────────────────────────────────────────────────────────┤
│  FEATURE LAYER                                             │
│  Player Combat · Checkpoint & Respawn · Enemy · Hazard     │
│  Level · Credit Economy · Upgrade · Shop · Secret · Boss   │
│  Tutorial · Accessibility · Speedrun                       │
├────────────────────────────────────────────────────────────┤
│  CORE LAYER                                                │
│  Player Movement · Camera · Audio                          │
├────────────────────────────────────────────────────────────┤
│  FOUNDATION LAYER                                          │
│  Input System · Game State Manager · Save/Load System      │
├────────────────────────────────────────────────────────────┤
│  PLATFORM LAYER (Godot 4.6 API surface)                    │
│  SceneTree · Input singleton · Jolt physics · Renderer     │
└────────────────────────────────────────────────────────────┘
```

### Layer assignments

| System | Layer | Priority | ADR(s) governing | Engine Risk |
|--------|-------|----------|-----------------|-------------|
| Input System | Foundation | MVP | ADR-0004 | HIGH (focus burst, Wayland) |
| Game State Manager | Foundation | MVP | — (to create) | LOW |
| Save/Load System | Foundation | MVP | — (G-2a/b, post-MVP) | MEDIUM (FileAccess 4.4) |
| Player Movement | Core | MVP | ADR-0001, ADR-0005 | HIGH (Jolt default) |
| Camera | Core | MVP | ADR-0002 | LOW |
| Audio | Core | MVP | — (to create) | LOW |
| Player Combat | Feature | MVP | — (to create, depends ADR-0001/0005) | MEDIUM (CCD Jolt) |
| Checkpoint & Respawn | Feature | MVP | — (depends ADR-0005 died/respawned) | LOW |
| Enemy | Feature | MVP | — (to create) | LOW |
| Hazard | Feature | MVP | — (to create) | LOW |
| Level | Feature | MVP | — (to create) | LOW |
| Credit Economy | Feature | MVP | — (to create) | LOW |
| Upgrade | Feature | MVP | — (to create) | LOW |
| Shop | Feature | MVP | — (to create) | LOW |
| Secret | Feature | MVP | — (to create) | LOW |
| Boss | Feature | Full Vision | — (post-MVP) | LOW |
| HUD | Presentation | MVP | — (to create, UX spec first) | LOW |
| Menu | Presentation | MVP | — (to create, UX spec first) | LOW |
| VFX & Feedback | Presentation | MVP | ADR-0003 Forward+ default | MEDIUM (Shader Baker) |
| Tutorial | Feature | VS | — | LOW |
| Accessibility | Feature | Full Vision | — (G-4, post-MVP) | MEDIUM (AccessKit) |
| Speedrun & Leaderboards | Feature | Full Vision | — (post-MVP) | LOW |

---

## 4. Module Ownership Map

### 4.1 Foundation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **InputManager** (autoload singleton) | `_pressed`/`_consumed` dicts, 3-owner refcount Set, ring buffer latence (`PackedFloat32Array`+`PackedInt64Array`), 6 StringName constants | `was_pressed_this_tick(action)`, `request_disable(owner)`, `release_enable_request(owner)`, signals `mouse_motion(delta)`, `application_focus_lost()`, `application_focus_gained()` | `Input.*` singleton (main thread only), `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` | `Input`, `Node._unhandled_input`, `Input.parse_input_event`, `Time.get_ticks_usec` |
| **GameStateManager** (autoload singleton) | Run lifecycle state (`MENU`/`PLAYING`/`PAUSED`/`RESPAWNING`/`BOSS_DEFEATED`), pause toggle, scene transition queue | `state_changed(new_state)` signal, `request_pause()`, `request_resume()` | `InputManager.application_focus_lost` | `SceneTree`, `get_tree().paused` |
| **SaveLoadSystem** (autoload singleton, ADR-0010 Accepted) | Run/checkpoint state ConfigFile (`user://savegame.cfg`), API verbs typés scalaires/arrays/Tier2 | `save_int/get_int/save_string_array/get_string_array/save_now`, `NOTIFICATION_WM_CLOSE_REQUEST` flush | — | `FileAccess`, `ConfigFile` |
| **AccessibilityService** (autoload singleton, ADR-0015 Accepted) | Cache `_settings: AccessibilitySettings` (9 flags), OR-merge OS bridge (`OS.is_reduce_motion_enabled()`) | Pull-pattern getters typés (`get_disable_slow_mo`, `get_camera_*_mult`, `get_enemy_death_tween_ms`…), signal `settings_changed` | Persistance déléguée `SettingsResource` (ADR-0014) | `OS.call("is_reduce_motion_enabled")` (Godot 4.5+ AccessKit) |

### 4.2 Core Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **MovementController** (CharacterBody3D script) | `velocity`, `state` (8 states + die/respawn), `air_jumps_used`, `dash_cooldown_timer`, `wall_run_timer`, `%WallRayLeft`/`%WallRayRight` ShapeCast3D | 8 signals typés (dash_started, dash_ended, wall_run_entered, wall_run_exited, wall_jumped, died, respawned, attacked), read-only `get_velocity()`, `get_state()`, `get_capabilities()` | `InputManager.was_pressed_this_tick`, `InputManager.application_focus_lost` (via GameStateManager) | `CharacterBody3D.move_and_slide`, `ShapeCast3D`, `Jolt`, `_physics_process` |
| **CameraSystem** (scene: `CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D`) | `camera_arm.rotation.x` (pitch), `camera_effects.rotation.z` (tilt), `camera3d.fov`, shake state (`add_shake()`/`add_shake_roll()`) | `aim_forward: Vector3` (roll-corrected), `get_camera3d() -> Camera3D` | `InputManager.mouse_motion`, `MovementController.wall_run_entered/exited`, `MovementController.dash_started/ended`, `MovementController.died/respawned`, `MovementController.wall_jumped` | `Node3D.rotation`, `Camera3D.fov`, `Tween`, `_process` |
| **AudioSystem** (autoload singleton) | `AudioStreamPlayer` pool, music stream, mix bus assignments | `play_sfx(stream, position)`, `play_music(stream)`, `fade_music()` | All Movement signals (SFX binding) | `AudioStreamPlayer3D`, `AudioServer` |
| **SettingsResource** (RefCounted helper static, **zero autoload**, ADR-0014 Accepted) | Pas d'état runtime — fonctions pures `load_or_default<T>(name, factory) -> T`, `save<T>(name, resource) -> Error` | API statique consommée par chaque owner system (CameraSystem, InputManager, AccessibilityService…) | `FileAccess`, `ResourceLoader/Saver`, `DirAccess` (`user://settings/`) | `Resource` (.tres typé par owner), `_settings_version` migration forward-only |

### 4.3 Feature Layer (MVP)

Détails complets à écrire en ADRs dédiés. Résumé ownership :

| Module | Owns | Consumes |
|--------|------|----------|
| PlayerCombat | katana hitbox state, combo timer | MovementController.attacked, CameraSystem.aim_forward |
| CheckpointRespawnSystem | checkpoint positions, respawn target | MovementController.died, LevelSystem |
| EnemySystem | enemy pool, AI state per enemy | LevelSystem, HazardSystem |
| HazardSystem | hazard instances (spikes, fall-kill) | LevelSystem |
| LevelSystem | level grid, secret anchors, checkpoint anchors | GameStateManager |
| CreditEconomy | `credits` counter, per-run + permanent | EnemySystem.killed, SecretSystem.found |
| UpgradeSystem | `capabilities` flags (can_air_jump, can_dash, can_wall_run, katana tier) | SaveLoadSystem, ShopSystem.purchased |
| ShopSystem | shop inventory per hub, price curves | CreditEconomy, UpgradeSystem, MenuSystem |
| SecretSystem | secret definitions per level, found state | LevelSystem, CreditEconomy |
| BossSystem | boss HP multi-hit, attack patterns | PlayerCombat, EnemySystem |

### 4.4 Presentation Layer

| Module | Owns | Consumes |
|--------|------|----------|
| HUD | credits display, combo indicator, dash cooldown UI, debug F3 | CreditEconomy, MovementController (read-only), InputManager latency p99 |
| MenuSystem | main menu, pause menu, settings menus | GameStateManager, InputManager, SaveLoadSystem |
| VFXFeedback | trails, impacts, respawn flash (distinct des overlay Camera), particles | PlayerCombat, Enemy, Checkpoint |

### 4.5 Dependency diagram (MVP scope)

```
                    [InputManager]  [GameStateManager]
                         │               │
                         ▼               ▼
              ┌──────[MovementController]───┐
              │               │              │
              ▼               ▼              ▼
       [CameraSystem]  [PlayerCombat]  [CheckpointRespawn]
              │               │              │
              └──────────┬────┴──────┬───────┘
                         ▼           ▼
                   [AudioSystem] [VFXFeedback]
                         │           │
                         └─────┬─────┘
                               ▼
                           [HUD] [MenuSystem]
```

Aucun cycle. Foundation → Core → Feature → Presentation strictement descendant.

---

## 5. Data Flow

### 5.1 Frame update path (60 Hz physics + display-rate render)

```
[Input OS event]
     ▼
Input._unhandled_input(event)
     ▼
InputManager._unhandled_input() → store into _pressed dict + emit mouse_motion
     ▼  (start of next physics tick N)
InputManager._physics_process() → swap _pressed↔_consumed (D-3)
     ▼
MovementController._physics_process(delta=1/60)
  → reads InputManager.was_pressed_this_tick(&"jump") etc
  → mutates velocity/state
  → emits 0..N typed signals (dash_started, wall_run_entered, etc)
     ▼  (signals dispatched sync or DEFERRED per D-5 criteria a-d)
[consumers: Camera, Audio, VFX, HUD, Combat] react
     ▼
move_and_slide() → Jolt integration
     ▼  (end of physics tick)
GameStateManager polls states if needed
     ▼  (next frame render)
CameraSystem._process(delta)
  → apply yaw (Player.rotation.y), pitch (CameraArm.rotation.x)
  → lerp tilt on CameraEffects.rotation.z
  → decay shake on Camera3D
  → apply FOV interp on Camera3D.fov
     ▼
Renderer (Forward+ D3D12/Vulkan) → framebuffer
     ▼
VSync ≤ 16.6 ms OR opt-in low-latency path
```

### 5.2 Event/signal path

Pattern canonique figé par **ADR-0004** (InputManager direct signals) + **ADR-0005** (MovementController direct signals) :

- Producteur déclare signal typé dans son script (`signal dash_started(power: float)`).
- Consumer appelle `movement_controller.dash_started.connect(_on_dash_started)` dans `_ready()`.
- Emit uniquement depuis `_physics_process` pour Movement/Combat (ADR-0001 autorité).
- CONNECT_DEFERRED si handler : instantie Node, play AudioStream, alloue > 256 bytes, ou coûte > 0.5 ms (ADR-0005 D-5 critères a-d). Sinon sync.
- **Interdit** : EventBus autoload pour events intra-gameplay (`forbidden_pattern: event_bus_autoload_for_movement_intra_gameplay_events`).
- **Interdit** : consumer mute l'état du producteur depuis handler (`forbidden_pattern: mutate_movement_state_from_signal_handler`).

### 5.3 Persistence patterns (3 paths distincts)

Le projet ratifie **3 patterns persistence orthogonaux** — chacun couvre un domaine
disjoint avec un owner distinct. Toute confusion entre les 3 = anti-pattern (bug).

| Pattern | ADR | Domaine | Stockage | Owner runtime |
|---------|-----|---------|----------|---------------|
| **Run/checkpoint** | ADR-0010 | État de partie (credits, capabilities, checkpoint) | `user://savegame.cfg` (ConfigFile, scalar verbs) | Autoload `SaveLoadSystem` (Foundation #3) |
| **Settings per-system** | ADR-0014 | Préférences user (mouse sens, FOV offset, key bindings) | `user://settings/<system>.tres` (Resource typé) | Helper static `SettingsResource` (zero autoload) |
| **Accessibility** | ADR-0015 | Flags cross-system (reduce_motion, slow_mo overrides) | `user://settings/accessibility.tres` *via ADR-0014* | Autoload `AccessibilityService` (#4) — délègue persist à ADR-0014 |

#### 5.3.1 Run/checkpoint path (ADR-0010 — autoload, ConfigFile)

```
[Checkpoint trigger / GameStateManager BOSS_DEFEATED]
     ▼
Owner system → SaveLoadSystem.save_int(section, key, value)
                                     .save_string_array(section, key, list)
                                     ... [verbs typés ADR-0010 D-2]
     ▼
SaveLoadSystem.save_now()          [explicit flush — pas d'auto-save MVP]
  → ConfigFile.save("user://savegame.cfg")
     ▼
NOTIFICATION_WM_CLOSE_REQUEST [autoload handler ADR-0010 D-8]
  → save_now() best-effort flush
     ▼
On game start: GameStateManager._ready() → SaveLoadSystem.load_or_init()
                                          → owner systems pull via get_int/...
```

**Anti-pattern** : un owner qui sérialise des préférences user (Settings Menu)
via SaveLoadSystem au lieu de ADR-0014. Le `savegame.cfg` est purgé entre runs ;
les settings doivent survivre.

#### 5.3.2 Settings per-system path (ADR-0014 — zero autoload, Resource typé)

```
[CameraSystem._ready / InputManager._ready / future Settings Menu apply]
     ▼
SettingsResource.load_or_default<T>("camera", CameraSettings.create_defaults)
  → FileAccess existence check user://settings/camera.tres
  → ResourceLoader.load() ; on parse error : defaults + warning + fichier inchangé (D-4)
  → Migration forward-only via T.migrate_from(version, raw) (D-3)
     ▼
Owner pousse les valeurs dans son propre runtime (mouse_sensitivity, fov_user_offset...)
     ▼
[Settings Menu apply / debug command / quit handler]
     ▼
SettingsResource.save<T>("camera", current_settings)
  → DirAccess.make_dir_recursive_absolute("user://settings/")
  → ResourceSaver.save() à user://settings/camera.tres (atomic via Godot)
```

**Pattern critique** : zero autoload (D-5) — pas de gather centralisé. Chaque owner
load/save SA Resource indépendamment. Last-write-wins inter-systèmes documenté
(ex : Camera est autorité sur `mouse_sensitivity` GDD Tuning Knobs souris ; load
Camera après InputManager le réécrit dans `InputManager.mouse_sensitivity`).

**Anti-pattern** : un système qui pousse des state run (credits, checkpoint)
dans `user://settings/` au lieu de ADR-0010.

#### 5.3.3 Accessibility path (ADR-0015 — autoload, délégué à ADR-0014)

```
[AccessibilityService._ready, autoload position #4]
     ▼
SettingsResource.load_or_default("accessibility", AccessibilitySettings.create_defaults)
  → ADR-0014 path (cf. 5.3.2)
     ▼
OR-merge OS bridge (D-6) :
  if OS.has_method("is_reduce_motion_enabled") and OS.call("is_reduce_motion_enabled"):
      _settings.reduce_motion = true   # OS prend autorité si user toggle off
     ▼
[6 consumers : Movement, Camera, Combat, Enemy, VFX, HUD]
each: AccessibilityService.settings_changed.connect(_on_accessibility_changed)
      → cache local lu via getters typés (pull-pattern D-3)
     ▼
[Settings Menu apply / QA debug]
AccessibilityService.apply_settings(new_settings)
  → mute _settings + emit settings_changed (consumers reload cache mid-game)
AccessibilityService.save_settings() [explicit, parité ADR-0014 D-6]
  → SettingsResource.save("accessibility", _settings)
```

**Justification autoload** vs ADR-0014 zero-autoload (ADR-0015 D-1) : 6 consumers
+ live update mid-game requis (story-022 AC-4) + bridge OS centralisé + OR-merge
source-of-truth. Helper static ne supporte pas ces 4 contraintes simultanément.

**Anti-pattern** : un consumer qui lit `OS.is_reduce_motion_enabled()` directement
au lieu de passer par `AccessibilityService.get_*()`. Cassé l'OR-merge user toggle.

### 5.4 Initialisation order

1. Autoload singletons (order figé par `project.godot`, vérifié 2026-05-02) :
   1. `InputManager` (Foundation — no deps) — load `user://settings/input.tres` via ADR-0014
   2. `GameStateManager` (Foundation — no deps)
   3. `SaveLoadSystem` (Foundation — no deps) — ConfigFile run/checkpoint (ADR-0010)
   4. `AccessibilityService` (Foundation — depends on FileAccess pour délégation ADR-0014) — load + OR-merge OS bridge
   5. `CreditEconomy` (Core — depends on SaveLoadSystem hydration au boot)
   6. `Upgrade` (Feature — depends on SaveLoadSystem hydration au boot)
   7. `LevelSystem` (Feature — no deps autoloads, scene root)
2. Scene initiale (`res://scenes/main_menu.tscn`) chargée.
3. Scenes gameplay chargées on demand par `GameStateManager.request_*()`.
4. Per-system settings load (ADR-0014) : déclenché par chaque owner dans son propre `_ready()`
   (CameraSystem au spawn Player, etc.) — pas de dispatch centralisé.

---

## 6. API Boundaries

Pseudocode GDScript — contrats stables que les programmers implémentent.

### 6.1 InputManager (autoload)

```gdscript
# docs/architecture/adr-0004-input-api-focus-handling.md D-1..D-9
extends Node

signal mouse_motion(delta: Vector2)
signal application_focus_lost()
signal application_focus_gained()

func was_pressed_this_tick(action: StringName) -> bool
func request_disable(owner: Node) -> void  # refcount, idempotent
func release_enable_request(owner: Node) -> void  # refcount, auto-cleanup on owner.tree_exited
func get_latency_p99_ms() -> float  # debug HUD only

# FORBIDDEN: Input.* access outside this singleton (lint rule)
# FORBIDDEN: set_enabled(bool) without refcount
# FORBIDDEN: any call from non-main thread
```

### 6.2 MovementController (CharacterBody3D script)

```gdscript
# docs/architecture/adr-0005-movement-signals-architecture.md D-1..D-10
extends CharacterBody3D

signal dash_started(direction: Vector3)
signal dash_ended()
signal wall_run_entered(normal: Vector3)
signal wall_run_exited()
signal wall_jumped(launch_velocity: Vector3)
signal died(cause: StringName)
signal respawned(position: Vector3)
signal attacked()
# reserved post-MVP: signal falling()

func get_velocity() -> Vector3  # read-only accessor
func get_state() -> StringName
func get_capabilities() -> Dictionary  # {can_air_jump: bool, can_dash: bool, can_wall_run: bool}

# Emit from _physics_process ONLY (ADR-0001 authority)
# MovementController is outbound-only: zero references to consumers (D-10)
# Consumers MUST NOT mutate velocity/position/rotation/die()/respawn() from handlers (D-7)
```

### 6.3 CameraSystem (Camera3D root or Node wrapper)

```gdscript
# docs/architecture/adr-0002-camera-scene-tree-cameraarm.md
extends Node3D  # CameraArm

@onready var camera_effects: Node3D = $CameraEffects
@onready var camera3d: Camera3D = $CameraEffects/Camera3D

func add_shake(amplitude: float, duration: float) -> void
func add_shake_roll(amplitude: float, duration: float) -> void
func get_aim_forward() -> Vector3  # roll-corrected for combat hitbox stability
func get_camera3d() -> Camera3D

# Yaw is applied to Player (parent), not camera — see ADR-0002
# FORBIDDEN: direct mutation of camera3d.rotation outside CameraSystem
```

### 6.4 GameStateManager (autoload)

```gdscript
extends Node

enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }

signal state_changed(new_state: State)

func request_pause() -> void
func request_resume() -> void
func request_scene_transition(scene_path: String) -> void
func get_current_state() -> State

# Consumes InputManager.application_focus_lost for auto-pause in gameplay
```

### 6.5 Invariants communs

- **StringName discipline** : toutes actions / states / cause-enums référencés par StringName préalloué (const), jamais de littéral String chaud.
- **Zero-alloc hot path** : pas de `Dictionary` literal, pas de `Array.push_back()`, pas de `String.format()` dans `_physics_process` ou handler de signal emis chaque tick. Usage de `PackedFloat32Array`/`PackedInt64Array` pour buffers.
- **Typed payloads** : tous les signaux déclarent leurs types de paramètres.
- **Autorité unique** : chaque variable d'état mutable appartient à un unique module (write), les autres lisent via getter ou signal.

---

## 7. ADR Audit

### 7.1 Qualité structurelle des ADRs existants

| ADR | Title | Status | Engine Compat | Version | GDD Linkage | Deps section | Valid |
|-----|-------|--------|--------------|---------|-------------|--------------|-------|
| ADR-0001 | Physics Rate 60 Hz + Jolt | Accepted | ✅ | 4.6 | ✅ | ✅ None | ✅ |
| ADR-0002 | Camera Scene Tree 3-stages | Accepted | ✅ | 4.6 | ✅ | ✅ None | ✅ |
| ADR-0003 | Rendering & Display Latency | Accepted | ✅ | 4.6 | ✅ | ✅ ADR-0001 | ✅ |
| ADR-0004 | Input API & Focus Handling | Accepted | ✅ | 4.6 | ✅ | ✅ ADR-0001 | ✅ |
| ADR-0005 | Movement Signals Architecture | Accepted | ✅ | 4.6 | ✅ | ✅ ADR-0001 | ✅ |

**Résultat** : 5/5 ADRs complets structurellement. Aucun conflit inter-ADR (vérifié par 5 rapports `/architecture-review` 2026-04-21).

### 7.2 DAG de dépendances

```
              ADR-0001 (Foundation: Physics Rate + Jolt)
                    │
         ┌──────────┼──────────┬──────────┐
         ▼          ▼          ▼          ▼
     ADR-0002   ADR-0003   ADR-0004   ADR-0005
     (Camera)   (Render)   (Input)    (MoveSig)
```

Aucun cycle. Foundation → Core pattern.

### 7.3 Coverage TR-ID → ADR

Voir `docs/architecture/architecture-traceability.md` pour la matrice complète.

Résumé : **20/21 ✅ covered** (incluant TR-cam-006 + TR-inp-009 ADR-0014 Accepted 2026-05-02 et TR-mov-008 ADR-0015 Accepted 2026-05-02) / **2/21 ⚠️ N/A intentionnel** (TR-mov-005 post-MVP, TR-cam-004 tuning) / **0/21 ❌ gaps**.

**Foundation layer coverage** : ✅ zero gaps (gate requirement satisfied).

---

## 8. Required New ADRs

Listes des ADRs à créer, groupés par tier et par couche.

### 8.1 Must-have avant coding MVP (Foundation gaps — 0)

**Aucun**. Les 5 ADRs existants couvrent toute la Foundation layer requise pour les 2 premiers sprints (Input + Movement + Camera).

### 8.2 Must-have avant 1ère story du système concerné (Core layer gaps)

Aucun bloquant Sprint 1-2. Les systèmes suivants auront besoin d'un ADR **avant leur 1ère story** :

- **ADR-0006 Audio System Architecture** — mix buses, pooling AudioStreamPlayer, ducking rules, binding signals Movement. *Avant Sprint Audio*.
- **ADR-0007 Game State Manager + Scene Transition Pattern** — state machine, transition queue, pause semantics. *Avant Sprint Menu / Checkpoint*.
- **ADR-0008 Player Combat Hitbox Architecture** — ShapeCast3D swept hitbox, CCD à vitesse max dash+wall-run, fenêtre temporelle + `attacked` trigger. *Avant Sprint Combat*.

### 8.3 Should-have avant Feature tier (MVP étendu)

- **ADR-0009 Checkpoint & Respawn Pattern** — consommation `died`/`respawned` signals, atomicité reset state.
- **ADR-0010 Upgrade Capabilities Interface** — flags pattern (can_air_jump, can_dash, can_wall_run), propagation à MovementController via setter explicite.
- **ADR-0011 Level System Grid + Secret Anchors** — scene structure, instantiation strategy, memory budget.
- **ADR-0012 Enemy State Machine + Hazard Pattern** — AI base class, hazard vs enemy distinction.
- **ADR-0013 HUD + Menu UI Framework** — Control node hierarchy, Theme resource pattern, Focus handling (dual-focus 4.6 advisory VR-3 applicable).

### 8.4 Can defer to Polish phase

- ~~**ADR-0014 Save/Load Settings Infrastructure**~~ ✅ **Accepted 2026-05-02** (résout TR-cam-006 + TR-inp-009).
- ~~**ADR-0015 Accessibility Interface Layer**~~ ✅ **Accepted 2026-05-02** (résout TR-mov-008 + TR-cmb-016 : `reduce_flash`, `reduce_motion` propagation cross-system via autoload `AccessibilityService` + `accessibility_settings.tres` délégué ADR-0014).
- **ADR-0016 VFX & Feedback Architecture** (Niagara-equivalent Godot particles, shader budget).

### 8.5 Post-MVP / Full Vision

- **ADR-0017 Boss System Asymmetric Combat** (HP multi-hits, window-based).
- **ADR-0018 Speedrun & Leaderboards** (deterministic replay, timestamp integrity).

---

## 9. Validation Requirements (VRs) hérités des ADRs

À lever Sprint 1 (non-blocker Accept, mais CI requis) :

| VR | Source ADR | Test | Gate |
|----|-----------|------|------|
| VR-1 Shader Baker 4.6 sémantique | ADR-0003 | 1ère material custom compile + render sans diff visuel | Sprint 1 advisory |
| VR-2 D3D12 default Windows 4.6 launch-time | ADR-0003 | Launch build Windows target laptop, profil D3D12 vs Vulkan | Sprint 1 advisory |
| VR-3 Dual-focus 4.6 `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` | ADR-0004 VC-1 | Integration test alt-tab 3 OS (Windows/macOS/Linux Wayland+X11) | Sprint 1 advisory |
| VC-1..8 ADR-0005 | ADR-0005 | Typed signals CI debug, zero-alloc < 64 KB, ordre die-during-dash, idempotence, lint outbound-only, lint no-emit-from-_process, assertion RESPAWN_DELAY invariant, benchmark dispatch ≤ 0.1 ms/frame | Sprint 1 blocking |

---

## 10. Open Questions

À résoudre avant la couche correspondante :

1. **Audio mix buses** — nombre de buses (Master/SFX/Music/UI ?), ducking règles. *Résolu par ADR-0006.*
2. **Scene transition pattern** — blocking load vs async vs double-buffered. *Résolu par ADR-0007.*
3. **Hitbox sweep Jolt CCD** — configuration ShapeCast vs built-in Jolt CCD. *Résolu par ADR-0008.*
4. **Input-to-HUD latency p99** — `InputManager.get_latency_p99_ms()` exposé au HUD : ring buffer suffit pour debug F3, ou besoin exporter pour telemetry post-MVP ? *Décision ADR-0013 ou inline Sprint HUD.*
5. **Accessibility propagation** — interface Observer/Signal centralisée ou setter-per-system ? *Résolu par ADR-0015 post-MVP.*

---

## 11. Cross-References

- Game concept : `design/gdd/game-concept.md`
- Systems index : `design/gdd/systems-index.md`
- GDDs Foundation/Core : `design/gdd/input-system.md`, `design/gdd/player-movement-system.md`, `design/gdd/camera-system.md`
- ADRs Accepted : `docs/architecture/adr-0001..adr-0005.md`
- Traceability matrix : `docs/architecture/architecture-traceability.md`
- TR Registry : `docs/architecture/tr-registry.yaml`
- Architecture reviews : `docs/architecture/architecture-review-2026-04-21*.md` (5 rapports)
- Technical preferences : `.claude/docs/technical-preferences.md`
- Engine reference : `docs/engine-reference/godot/VERSION.md` + modules
- Coding standards : `.claude/docs/coding-standards.md`
- Coordination rules : `.claude/docs/coordination-rules.md`
