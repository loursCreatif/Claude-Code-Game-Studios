# Control Manifest

> **Engine** : Godot 4.6
> **Last Updated** : 2026-04-23
> **Manifest Version** : 2026-04-23
> **ADRs Covered** : ADR-0001, ADR-0002 (+ Amendment A-1 2026-04-23), ADR-0003, ADR-0004, ADR-0005 (+ Amendment r2 2026-04-23)
> **Status** : Active — regenerate with `/create-control-manifest` when ADRs change

`Manifest Version` est la date de génération du manifest. Les stories créées l'embarquent dans leur header ; `/story-readiness` compare la version embarquée à ce champ pour détecter les stories écrites contre des règles obsolètes. Le champ matche toujours `Last Updated`.

Ce manifest est la référence **programmers' quick-reference** extraite des 5 ADRs Accepted (incl. Amendments A-1 / r2 2026-04-23), de `.claude/docs/technical-preferences.md`, et des engine-reference docs (`deprecated-apis.md`, `current-best-practices.md`). Pour le **why** derrière chaque règle, consulter l'ADR source référencé.

---

## Foundation Layer Rules

*Applies to : InputManager (autoload), event architecture, scene management, engine initialisation, project settings boot-critical.*

### Required Patterns

- **Project setting `physics/common/physics_ticks_per_second = 60`** — source : ADR-0001
- **Project setting `physics/common/max_physics_steps_per_frame = 4`** (override défaut 8) — source : ADR-0001
- **Project setting `physics/3d/physics_engine = "JoltPhysics3D"`** (explicite, défaut 4.6) — source : ADR-0001
- **Project setting `physics/3d/default_gravity = 0.0`** (override défaut 9.8 — MovementController applique gravité custom) — source : ADR-0001
- **`InputManager.was_pressed_this_tick(action: StringName) -> bool`** est l'API polling canonique pour les consumers gameplay — source : ADR-0004 D-1
- **InputManager est autoload déclaré en 1er** dans `project.godot` — source : ADR-0004 D-3 + Risk 6
- **Reset du dict `_pressed_this_tick` via swap `_pressed ↔ _consumed` SYNCHRONE en ligne 1 de `_physics_process` d'InputManager** (zero-alloc ref swap) — source : ADR-0004 D-3
- **`InputManager.request_disable(owner: Node)` / `release_enable_request(owner: Node)`** (refcount idempotent, auto-cleanup via `tree_exited.connect(..., CONNECT_ONE_SHOT)`) — source : ADR-0004 D-4
- **`InputManager.enabled`** reste propriété **read-only** (getter, derived from `_enable_blockers.is_empty()`) — source : ADR-0004 D-4
- **`application_focus_lost()` / `application_focus_gained()`** signals émis dans `_notification(NOTIFICATION_APPLICATION_FOCUS_OUT/IN)`. GameStateManager (aval) connecte et consume one-way — source : ADR-0004 D-5
- **Focus re-acquisition : fenêtre absolue 50 ms via `Time.get_ticks_usec()`** pour absorber burst Wayland `InputEventMouseMotion` post-FOCUS_IN — source : ADR-0004 D-6
- **Pré-allocation dicts au `_ready()`** avec `ACTIONS_MVP` : `_pressed_this_tick`, `_consumed_this_tick` — source : ADR-0004 D-1
- **Latency ring buffer : 2× `PackedFloat32Array` / `PackedInt64Array` pré-alloués via `.resize(CAPACITY)`** — source : ADR-0004 D-8
- **Actions référencées par `&"..."` literal StringName ou `const`** (jamais via variable `String`) — source : ADR-0004 (GDD Input règle 8 acquise)
- **Test fixtures : `Input.parse_input_event(InputEventAction)`** pour déclencher `_unhandled_input` en GUT — source : ADR-0004 D-9
- **Debug-only gates : `if not OS.has_feature("debug"): return`** en début de `simulate_*` fixtures (no-op release) — source : ADR-0004 D-9

### Forbidden Approaches

- **Never appeler `InputManager.is_action_just_pressed()`** — supprimée, utiliser `was_pressed_this_tick()` — source : ADR-0004 D-2
- **Never appeler `Input.is_action_just_pressed` direct depuis gameplay `_physics_process`** — forbidden pattern `is_action_just_pressed_direct_in_gameplay_physics_process` — source : ADR-0001 + ADR-0004 D-2
- **Never appeler `InputManager.set_enabled(bool)`** — supprimée, utiliser `request_disable(owner)` / `release_enable_request(owner)` — source : ADR-0004 D-4
- **Never utiliser `#if debug_build`** — n'existe pas en GDScript, remplacer par `OS.has_feature("debug")` runtime — source : ADR-0004 D-9
- **Never accéder `Input.*` singleton (y.c. `mouse_mode`, `is_action_pressed`, `get_vector`) depuis un `Thread`, `WorkerThreadPool.add_task`, ou `Callable.call_deferred` from non-main** — forbidden pattern `input_singleton_access_from_non_main_thread` — source : ADR-0004 D-7
- **Never faire un appel direct `GameStateManager.request_pause()` depuis InputManager** — signal `application_focus_lost` one-way uniquement (principe Foundation no-upstream-dep) — source : ADR-0004 D-5
- **Never utiliser `Input.action_press()` dans les tests** — ne trigger pas `_unhandled_input` ; utiliser `parse_input_event(InputEventAction)` — source : ADR-0004 D-9

### Performance Guardrails

- **Input frame budget** : ≤ 0.2 ms/frame p99 — source : ADR-0004 (Performance Implications)
- **Zero-alloc hot path** : 10 000 `simulate_action_press` + 10 000 `simulate_mouse_motion` sur 60 s → `Performance.get_monitor(MEMORY_STATIC)` delta < 64 KB — source : ADR-0004 VC-3

---

## Core Layer Rules

*Applies to : MovementController, player state machine, combat/hitbox, checkpoint/respawn, physics-authored systems.*

### Required Patterns

- **`_physics_process(delta)` est l'UNIQUE autorité de mutation gameplay** : velocity, position, rotation, hitbox, transitions state-machine, damage, timing tick-based (jump buffer, coyote time, dash cooldown, combo window, iframes) — source : ADR-0001 (Règle d'autorité)
- **Comptage tick via `Engine.get_physics_frames()`** pour timing déterministe — source : ADR-0001
- **`physics_interpolation_mode = OFF` sur le root Player uniquement** (pas projet-wide) — source : ADR-0001
- **MovementController applique gravité custom (`GRAVITY = 24.0`) manuellement dans `_physics_process`** (hors WallRunning) — default Jolt gravity désactivé pour éviter double-cumul — source : ADR-0001 (Migration Plan, TR-mov-007)
- **RigidBody3D ponctuels nécessitant gravité activent leur propre `gravity_scale`** — source : ADR-0001
- **Signals Movement directs typés sur MovementController** (pas EventBus autoload, pas sub-node `MovementEventEmitter`) — source : ADR-0005 D-1
- **Liste canonique figée de 8 signals MVP** : `dash_started(Vector3, float)`, `dash_ended()`, `wall_run_entered(Vector3)`, `wall_run_exited()`, `wall_jumped(Vector3, Vector3)`, `died()`, `respawned(Vector3)`, `attacked()` — source : ADR-0005 D-2
- **Ajout d'un signal Movement = amendement ADR-0005** (pas de drift silencieux) — source : ADR-0005 D-2
- **Payloads signals = `Vector3` / `float` exclusivement** (value types, zero-alloc) — source : ADR-0005 D-3
- **Emit signal Movement ONLY depuis `_physics_process`** du MovementController (ou fonctions appelées depuis lui) — source : ADR-0005 D-4
- **Ordre d'émission intra-tick déterministe** : sortie d'état avant entrée ; `died` terminal ; `respawned` reset implicite ; `attacked` en fin de `_physics_process` après state machine — source : ADR-0005 D-6
- **Signaux d'entrée d'état idempotents** (1× par transition) : chaque transition met à jour `_state` AVANT l'emit, avec guard `if _state == NEW: return` — source : ADR-0005 D-8
- **`state: State` propriété read-only est la source de vérité canonique** ; signals = notifications de transition — source : ADR-0005 REQ-8
- **Invariant runtime `assert(RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE)`** au `_ready()` du MovementController — source : ADR-0005 VC-7
- **Test de contrat typed signatures en CI debug build** : `tests/integration/movement/test_movement_signals_typed_contract.gd` — source : ADR-0005 D-3 + VC-1
- **Combat handler SYNC sur `died` Movement** : `_on_player_died()` set `_death_pending: bool = true` puis return immédiat. Aucune mutation de l'état Movement (D-7 respecté), aucune allocation, logique ≤ 0.5 ms. Nécessaire pour la séquence Rule 17 Hybrid : Combat doit connaître `_death_pending` AVANT son propre `_physics_process` (sinon résolution colliders pré-Dead rompue) — source : ADR-0005 Amendment r2

### Forbidden Approaches

- **Never muter `velocity`, `position`, `rotation`, `health`, ou état state-machine depuis `_process()`** — forbidden pattern `mutate_gameplay_state_in_process` — source : ADR-0001
- **Never émettre signal Movement depuis `_process`, `_input`, `_unhandled_input`, `_ready`, Timer.timeout** — forbidden pattern `emit_movement_signal_from_process` — source : ADR-0005 D-4
- **Never utiliser EventBus autoload pour events intra-gameplay Movement** — source : ADR-0005 D-1 (Alternative 1 rejected)
- **Never créer sub-node `MovementEventEmitter` child** — source : ADR-0005 D-1 (Alternative 2 rejected)
- **Never mettre `Dictionary`, `Array`, `String`, `Node`, `Resource`, `StringName` comme payload signal Movement** — forbidden pattern `allocating_signal_payload` — source : ADR-0005 D-3
- **Never utiliser `emit_signal("name", {...})` ou `Dict literal` en payload** — alloc hot path — source : ADR-0005 D-9
- **Never référencer depuis `movement_controller.gd` un consumer par nom** : `CameraSystem`, `CombatSystem`, `VFXManager`, `AudioManager`, `HUD`, `HUDController` — source : ADR-0005 D-10
- **Never utiliser `$NodePath` ou `get_node("/root/...")` depuis MovementController vers système aval** — source : ADR-0005 D-10
- **Never `preload("res://src/gameplay/camera.gd")` ou équivalent depuis MovementController** — source : ADR-0005 D-10
- **Never muter l'état Movement depuis un signal handler consumer** : `player.velocity = ...`, `player.die()`, `player.respawn()`, `player._state = ...`, `movement_tuning.tres` runtime — forbidden pattern `mutate_movement_state_from_signal_handler` — source : ADR-0005 D-7
- **Never faire `CONNECT_DEFERRED` par précaution sur consumers légers** (ajoute 1 frame latence cascadée) — source : ADR-0005 Risk 3
- **Never utiliser `Timer` node signals pour driver Movement state** (dash_timer, respawn_timer) — utiliser compteurs `-= delta` lus en `_physics_process` — source : ADR-0005 D-4

### Performance Guardrails

- **Intra-engine latency p99** : `input → velocity mutation` ≤ 16 ms release, ≤ 50 ms debug interpreter — source : ADR-0001 VC-2
- **Physics frame budget** : `Performance.TIME_PHYSICS_PROCESS` ≤ 4 ms/frame p99 sur entry-level laptop, scène MVP + 10 ennemis — source : ADR-0001 VC-4
- **Signal dispatch Movement cumulé** : ≤ 0.1 ms/frame amorti (8 signals × N consumers) — source : ADR-0005 VC-8
- **Zero-alloc signals** : 1000 emits / 60 s → `MEMORY_STATIC` delta < 64 KB — source : ADR-0005 VC-2

---

## Feature Layer Rules

*Applies to : systèmes secondaires, AI, features de niveau post-MVP.*

### Required Patterns

- *(Aucune règle Feature-layer dans les 5 ADRs Accepted — couche encore vide. Futurs ADRs Combat / AI / Audio / VFX ajouteront ici.)*

### Forbidden Approaches

- **Never introduire un 2e Player node sans refactor EventBus** (couplage N:1 direct signals MovementController ne scale pas coop local) — source : ADR-0005 Consequences.Negative

### Performance Guardrails

- *(À définir post-MVP.)*

---

## Presentation Layer Rules

*Applies to : rendering, audio, UI/HUD, VFX, shaders, Camera system, animations.*

### Required Patterns

- **Scene tree Camera** : `CharacterBody3D (Player) → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` — source : ADR-0002 Decision
- **Yaw** sur `player.rotation.y` (le body) — source : ADR-0002
- **Pitch** sur `camera_arm.rotation.x` **exclusivement**, clamp `[-PITCH_LIMIT, +PITCH_LIMIT]` chaque frame — source : ADR-0002
- **Tilt (roll)** sur `camera_effects.rotation.z` **exclusivement** — source : ADR-0002
- **FOV** sur `camera3d.fov` (lerp `BASE_FOV ± DASH_FOV_KICK`) — source : ADR-0002
- **Shake additif** via assignation `camera3d.rotation = shake_offset` (pas `+=`) chaque frame — source : ADR-0002 Risk 3
- **Head-bob (Tier 2, OFF MVP)** : sur `camera_arm.position.y` uniquement — pas sur rotation — source : ADR-0002
- **`aim_forward`** via forme close trigonométrique : `Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))` — pas de manipulation Basis — source : ADR-0002 D + VC-4
- **AudioListener3D** enfant de Camera3D (auto-current single listener, pas `make_current()` requis) — source : ADR-0002
- **Camera mute trois noeuds distincts** : CameraArm (pitch + head-bob), CameraEffects (tilt), Camera3D (fov + shake). Player mute uniquement `rotation.y` — source : ADR-0002
- **Project setting `rendering/renderer/rendering_method = "forward_plus"`** — source : ADR-0003
- **Project setting `anti_aliasing/quality/msaa_3d = 0`, `screen_space_aa = 2` (SMAA 1x), `use_taa = false`** — source : ADR-0003
- **Project setting `rendering/vrs/mode = 0`** (VRS off MVP) — source : ADR-0003
- **Project setting `display/window/vsync/vsync_mode = 1`** (baseline safe) — source : ADR-0003
- **Post-processing via `Compositor` (4.3+)** uniquement — source : ADR-0003 + current-best-practices
- **Shaders utilisent `Texture` base type** (pas `Texture2D`, changé 4.4) — source : ADR-0003 + deprecated-apis
- **SubViewport (si introduit) déclare `render_target_update_mode = ALWAYS` explicitement** — sinon défaut `ONCE` ajoute 1 frame de latence — source : ADR-0003 Risk 7
- **Backend rendering switch launch-time only** via CLI `--rendering-driver {vulkan|d3d12|opengl3}` — pas d'API runtime, restart requis — source : ADR-0003
- **Fallback 60 Hz si `DisplayServer.screen_get_refresh_rate() == -1`** + `push_warning` log — source : ADR-0003 VC-6
- **`RenderingSettingsManager` autoload** charge `user://graphics_settings.tres` au boot, expose `apply_settings(GraphicsSettings)` au menu — source : ADR-0003
- **Camera logic en `_process` cosmétique only** : yaw/pitch, VFX particles, shake decay, FOV interp, HUD, tween UI, debug F3, AudioStreamPlayer trigger (la décision de jouer reste `_physics_process`) — source : ADR-0001 (Règle d'autorité)
- **Consumer `CONNECT_DEFERRED`** iff : instancie Node (GPUParticles3D, AudioStreamPlayer, MeshInstance3D, scene `.instantiate()`), démarre sampler/stream, alloue GDScript > 256 B, OU exécute > 0.5 ms CPU — source : ADR-0005 D-5
- **Sinon connection synchrone (flag `CONNECT_0` / default)** pour consumers légers : toggle bool, lecture read-only, lerp cible de variable existante — source : ADR-0005 D-5
- **Camera System : consommation Movement signal-driven uniquement** — dans `_ready()`, connecter EXACTEMENT les 6 handlers requis : `player.wall_run_entered.connect(_on_wall_run_entered)`, `player.wall_run_exited.connect(_on_wall_run_exited)`, `player.dash_started.connect(_on_dash_started)`, `player.dash_ended.connect(_on_dash_ended)`, `player.died.connect(_on_died)`, `player.respawned.connect(_on_respawned)`. Flags mode SYNC (pas `CONNECT_DEFERRED`). Handlers `_on_*` mettent à jour des flags privés Camera (`_is_wall_running`, `_wall_side_cached`, `_is_dashing`, etc.) ; `_process` lit ces flags — jamais `player.state` ni `player.is_dashing`. Source : ADR-0002 Amendment A-1 (VC-7 + VC-8) + renvoi ADR-0005 D-2
- **VFX flash ColorRect SYNC sur Combat `enemy_killed`** (exemption r2, non-normative ADR-0005) : toggle `ColorRect.visible = true` + `Tween.tween_property(alpha)` sur Node pré-existant dans VFXLayer. Nécessaire pour frame-précis Pillar 1 (flash rendu même frame que kill tick). Les autres consumers `enemy_killed` (GPUParticles sang, Decal, AudioStreamPlayer3D) restent `CONNECT_DEFERRED`. Autorité canonique future = Pending ADR Combat Tick Model — source : ADR-0005 Amendment r2 (cross-ref GDD Combat Section VFX 2a)

### Forbidden Approaches

- **Never appliquer pitch** sur `camera3d.rotation.x`, `$Camera3D.rotation.x`, `camera_effects.rotation.x` — source : ADR-0002 VC-2
- **Never appliquer tilt** sur `camera3d.rotation.z`, `$Camera3D.rotation.z`, `camera_arm.rotation.z` — source : ADR-0002 VC-3
- **Never que le MovementSystem écrive sur CameraArm, CameraEffects, ou Camera3D** ; never que la CameraSystem écrive sur Player sauf `rotation.y` — source : ADR-0002 Implementation Guidelines
- **Never utiliser `SpringArm3D` pour la FPS camera** — sur-dimensionné (usage 3rd-person) — source : ADR-0002 Alternative 2
- **Never activer `anti_aliasing/quality/use_taa = true`** — ghosting sur fast motion anti-Pillar-1 — source : ADR-0003 REQ-5
- **Never créer manual viewport post-process chains** — utiliser Compositor — source : ADR-0003 + deprecated-apis
- **Never hot-switch rendering backend runtime** — `DisplayServer.switch_backend()` n'existe pas — restart requis — source : ADR-0003
- **Never poller `player.state ==`, `player.state !=`, `player.is_dashing`, `match player.state`** depuis `src/gameplay/camera/` — forbidden pattern `camera_polls_movement_state_transitions`. Whitelist : handlers `_on_*` peuvent lire leurs payloads typés. CI grep `grep -rE '(player\.state\s*[!=]=|player\.is_dashing|match\s+player\.state)' src/gameplay/camera/ | grep -v '_on_' ; assert exit 1`. Raison : Camera consomme les transitions Movement via signaux ADR-0005 exclusivement, évite couplage au enum interne `State` de MovementController — source : ADR-0002 Amendment A-1 (VC-7)
- **Never faire `CONNECT_DEFERRED` sur les 6 connexions Camera ↔ Movement** (wall_run_entered/exited, dash_started/ended, died, respawned) — mode SYNC requis pour cohérence visuelle frame-précise (VC-8 assert `connection.flags == 0`) — source : ADR-0002 Amendment A-1

### Performance Guardrails

- **Rendering frame budget** : ≤ 8 ms/frame p99 sur entry-level laptop, scène MVP + 10 ennemis + VFX minimal — source : ADR-0003 VC-1
- **Camera `_process` cost** : ≤ 0.2 ms p99 sur 1000 frames — source : ADR-0002 VC-6
- **Cold start** : < 3 s warm (shader cache valide), ≤ 30 s premier lancement (Shader Baker compile). Zero hitching visible post-boot — source : ADR-0003 VC-2
- **E2E latency p99** : ≤ 50 ms default VSync on 60 fps ; ≤ 30 ms low-latency opt-in (VSync off + 144 Hz + G-Sync) — source : ADR-0003 VC-5

---

## Global Rules (All Layers)

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `PlayerController` |
| Variables | snake_case | `move_speed` |
| Signals / Events | snake_case past tense | `health_changed`, `credit_collected`, `dash_started` |
| Files | snake_case matching class | `player_controller.gd` |
| Scenes / Prefabs | PascalCase matching root node | `PlayerController.tscn` |
| Constants | UPPER_SNAKE_CASE | `MAX_HEALTH`, `DASH_DISTANCE`, `RESPAWN_DELAY` |

Source : `.claude/docs/technical-preferences.md`

### Performance Budgets

| Target | Value | Source |
|--------|-------|--------|
| Framerate | 60 fps min (vsync locked), 120+ fps desirable | technical-preferences + Pillar 4 |
| Frame budget | 16.6 ms total (60 fps) | technical-preferences + ADR-0001 |
| Physics | ≤ 4 ms/frame p99 | ADR-0001 VC-4 |
| Rendering | ≤ 8 ms/frame p99 | ADR-0003 VC-1 |
| Camera `_process` | ≤ 0.2 ms p99 | ADR-0002 VC-6 |
| Input | ≤ 0.2 ms/frame p99 | ADR-0004 |
| Movement signals cumul | ≤ 0.1 ms/frame amorti | ADR-0005 VC-8 |
| Draw calls | < 500 par frame | technical-preferences (Chrome Zen) |
| Memory ceiling | 2 GB RAM / 1 GB VRAM | technical-preferences (entry-level laptop) |

### Approved Libraries / Addons

- *(Aucun addon approuvé pour l'instant — `.claude/docs/technical-preferences.md`. Ajouter via ADR quand une dépendance sera validée.)*

### Forbidden APIs (Godot 4.6)

Ces APIs sont deprecated ou ne doivent plus être utilisées. Source : `docs/engine-reference/godot/deprecated-apis.md`.

**Nodes & Classes** (déprécié → remplacer par) :
- `TileMap` → `TileMapLayer` (4.3)
- `VisibilityNotifier2D` → `VisibleOnScreenNotifier2D` (4.0)
- `VisibilityNotifier3D` → `VisibleOnScreenNotifier3D` (4.0)
- `YSort` → `Node2D.y_sort_enabled` (4.0)
- `Navigation2D` / `Navigation3D` → `NavigationServer2D` / `NavigationServer3D` (4.0)
- `EditorSceneFormatImporterFBX` → `EditorSceneFormatImporterFBX2GLTF` (4.3)

**Methods & Properties** (déprécié → remplacer par) :
- `yield()` → `await signal` (4.0)
- `connect("signal", obj, "method")` → `signal.connect(callable)` (4.0)
- `instance()` → `instantiate()` (4.0)
- `PackedScene.instance()` → `PackedScene.instantiate()` (4.0)
- `get_world()` → `get_world_3d()` (4.0)
- `OS.get_ticks_msec()` → `Time.get_ticks_msec()` (4.0)
- `duplicate()` (pour nested resources) → `duplicate_deep()` (4.5)
- `Skeleton3D.bone_pose_updated` → `skeleton_updated` (4.3)
- `AnimationPlayer.method_call_mode` → `AnimationMixer.callback_mode_method` (4.3)
- `AnimationPlayer.playback_active` → `AnimationMixer.active` (4.3)

**Patterns** (déprécié → remplacer par) :
- String-based `connect()` → typed signal connections (type-safe, refactor-friendly)
- `$NodePath` in `_process()` → `@onready var` cached reference (perf : path lookup every frame)
- Untyped `Array` / `Dictionary` → `Array[Type]`, typed variables (compiler optimizations)
- `Texture2D` in shader parameters → `Texture` base type (changed 4.4)
- Manual post-process viewport chains → `Compositor` + `CompositorEffect` (4.3+)
- GodotPhysics3D pour nouveaux projets → Jolt Physics 3D (défaut 4.6, meilleure stabilité)

### Cross-Cutting Constraints

- **Typed signals strictement** : Godot 4.x vérifie les signatures à la connexion **en debug build seulement**. Tout signal publié (Input, Movement, Camera, futurs) doit avoir un test de contrat GUT en CI debug. Mismatches silencieux en release = ship bloqué sans ce test. Source : ADR-0004, ADR-0005 D-3.
- **Zero-alloc hot path** (Pillar 1) : aucune allocation heap dans `_unhandled_input`, `_physics_process`, signal emit. Pas de `{...}` literal, pas de `Array` construit à la volée, pas de `String` concat. Source : ADR-0004 REQ-4, ADR-0005 D-9.
- **Autoload ordering discipline** : InputManager déclaré **en 1er** dans `project.godot`. Nouvel autoload ajouté avant = bug. Lint rule `.claude/rules/inputmanager-autoload-first.md` planifié. Source : ADR-0004 Risk 6.
- **Thread safety** : `Input.*` singleton main-thread only. `Input.mouse_mode`, `is_action_pressed`, `get_vector` jamais depuis `Thread`, `WorkerThreadPool`, ou deferred from non-main. Source : ADR-0004 D-7.
- **Coding standards** (CLAUDE.md) : doc comments sur public APIs ; chaque système a un ADR dédié dans `docs/architecture/` ; gameplay values data-driven (external config, jamais hardcoded) ; dependency injection over singletons ; verification-driven development.
- **Testing** : framework GUT ; couverture min 80% sur gameplay systems (movement, katana hitbox, shop economy) ; tests déterministes (pas de random seed, pas de time-dependent assertions) ; isolation (setup/teardown own state) ; pas de hardcoded data (factory / constants) ; pas d'I/O externe (dependency injection). Source : `.claude/docs/coding-standards.md`.
- **Signal-driven consumption Movement → consumers Presentation/Core** : tout consumer non-Movement des 8 signaux canoniques ADR-0005 infère les transitions d'état exclusivement via signaux typés, jamais par polling `player.state` / `player.is_dashing`. Exemptions SYNC (hors `CONNECT_DEFERRED` par défaut D-5) documentées : (a) Camera : 6 handlers signaux état (A-1, règle Presentation) ; (b) Combat `_on_player_died` flag `_death_pending` (r2) ; (c) VFX flash ColorRect sur `enemy_killed` (r2 non-normative). Toute autre exemption SYNC = amendment explicite requis. Source : ADR-0002 Amendment A-1 + ADR-0005 Amendment r2.

---

*Manifest généré par `/create-control-manifest` le 2026-04-21, mis à jour chirurgicalement le 2026-04-23 pour intégrer ADR-0002 Amendment A-1 (signal-driven Camera consumption, VC-7 + VC-8, forbidden pattern `camera_polls_movement_state_transitions`) et ADR-0005 Amendment r2 (exemptions SYNC Combat `_on_player_died` + VFX flash ColorRect). Mode review : solo (TD-MANIFEST gate skipped). Regenerate complet avec `/create-control-manifest` dès qu'un nouvel ADR passe Accepted ou qu'une technical preference change de fond.*
