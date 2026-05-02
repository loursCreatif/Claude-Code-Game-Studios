# ADR-0011: Level Scene Architecture — Single-Scene Etage, Canonical Hierarchy & Lint-Gated Authoring Invariants

## Status
Accepted 2026-04-23 r3 (promoted via `/architecture-review single-gdd level-system.md` focused — verdict PASS for promotion as design-contract ADR : 0 cross-ADR conflict vs ADR-0001/0003/0005/0006/0007, upstream deps Accepted, Engine MEDIUM risk avec tous les APIs documentés engine-reference, 19 TRs G-8 + 6 co-covered. Les 8 VC-LVL + 5 Verification Required §Engine Compatibility sont des gates implémentation Sprint 1 — pattern design-contract ADR-0005/ADR-0007.)

## Date
2026-04-23 (Proposed) → 2026-04-23 (Accepted r3)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Scene / Level / Rendering / Physics |
| **Knowledge Risk** | MEDIUM — D3D12 default (4.6), Shader Baker (4.5+), Jolt broad-phase (4.6 default). Aucun nouvel API 4.5/4.6 critique pour la scène elle-même (Node3D / Area3D / StaticBody3D / Marker3D stables). |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/modules/rendering.md` (D3D12 launch-time, SMAA, Shader Baker), `docs/engine-reference/godot/modules/physics.md` (Jolt default + BoxShape3D broad-phase), `docs/engine-reference/godot/modules/navigation.md` (NavigationRegion3D baked), `docs/engine-reference/godot/breaking-changes.md` (aucun breaking scene-tree 4.4-4.6), `docs/engine-reference/godot/deprecated-apis.md` (aucun Node3D/Area3D deprecated), `design/gdd/level-system.md` r2 (R-1 hiérarchie, F1-F8 formules, AC-LVL-1..55, Tuning Knobs authoring + runtime), `design/gdd/level-system.md` addendum Godot 4.6 (godot-specialist — OQ-1 + OQ-5 CLOSED, Tech-Risk-1/2/3 résolus), `docs/architecture/adr-0001-physics-rate-60hz.md` (Jolt + _physics_process authority), `docs/architecture/adr-0003-rendering-latency.md` (Forward+, budget 8 ms, SMAA, Shader Baker), `docs/architecture/adr-0005-movement-signals-architecture.md` (pattern direct typed signals — référence), `docs/registry/architecture.yaml` (state_ownership, forbidden_patterns). |
| **Post-Cutoff APIs Used** | `ResourceLoader.load_threaded_request(path)` + `.load_threaded_get_status()` (stable pré-4.3, confirmé 4.6) ; Shader Baker Project Settings (4.5+) ; D3D12 rendering backend default Windows (4.6) ; NavigationRegion3D `bake_navigation_mesh()` authoring-time uniquement (4.6 — pas d'usage runtime côté Level). |
| **Verification Required** | (1) Valider `ResourceLoader.load_threaded_request` retourne `THREAD_LOAD_LOADED` dans ≤ 1000 ms sur `etage_01.tscn` MVP (≤ 50 MB) sur Tier 1 testbed — AC-LVL-3. (2) Valider Shader Baker précompilation globale élimine le freeze 50-150 ms D3D12 première frame post-`level_active` — VR-LVL-1. (3) Valider `BoxShape3D` WorldBoundsVolume Jolt broad-phase reste O(1) overlap query sur 5800 m³ — AC-LVL-38 addendum + `validate_level_shapes()` runtime lint. (4) Valider draw calls statique p99 ≤ 350 sur scène Level isolée (500 frames minimum par salle) — AC-LVL-31. (5) Valider zero major allocation après `level_active` (60 s exploration, delta_static ≤ 512 KB, delta_object_count ≤ +5) — AC-LVL-36. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Jolt physics + `_physics_process` authority — Level System `_physics_process` exécute signal dispatch sur même tick) ; ADR-0003 (Forward+ rendering backend + budget 8 ms — Level respecte sous-budget draw calls ≤ 350 pour scène isolée) ; ADR-0005 (direct typed signals pattern — Level publie 7 signals typés suivant le même pattern que MovementController). |
| **Enables** | Implémentation `src/gameplay/level/level_system.gd` + `res://scenes/levels/etage_01.tscn` (Sprint 1 prévisible) ; implémentation Checkpoint System (consomme `get_checkpoint_slots()` + `player_out_of_world`) ; implémentation Enemy System (consomme `get_enemy_slots()` + NavigationRegion3D baked) ; implémentation Hazard System (consomme `get_hazard_slots()`) ; implémentation Secret System (consomme `get_secret_slots()`) ; implémentation HUD System (consomme `room_entered`) ; implémentation Audio System (consomme `room_entered` + `level_active` pour ambient layer swap) ; tool de lint `tools/lint/level_lint.gd` (authoring-time gates). |
| **Blocks** | Epic `level-system` (contrat scène + hiérarchie + signaux non-stables sans cet ADR) ; epic `checkpoint-respawn-system` (lookup `get_checkpoint_slots()` signature non figée) ; epic `enemy-system` (réciprocité NavigationRegion3D + `get_enemy_slots()`) ; tool `level_lint.gd` (11 invariants à implémenter — sans cet ADR, pas de contrat sur quels invariants sont gate pré-build vs advisory). |
| **Ordering Note** | ADR-0011 peut être Accepted en parallèle avec ADR-0007 (GameStateManager — Proposed 2026-04-23) et ADR-0008 (Collision Layer Taxonomy — planifié G-5, pas encore écrit). Dépendance indirecte : `load_etage(id)` est appelé par GSM (ADR-0007 `scene_transition_api` registry confirme le pattern additif `LevelSystem.load_etage + ResourceLoader.load_threaded_request`). Acceptation ADR-0011 figée indépendamment ; ADR-0007 promu Accepted en parallèle ou séquentiel. Acceptation Accepted ne dépend PAS de la finalisation ADR-0005 puisqu'ADR-0005 est déjà Accepted (base signals). |

## Context

### Problem Statement

Le GDD `design/gdd/level-system.md` (r2 post-revisions CD 5 fixes, 1271 lignes) définit **21 TRs architecturalement non-couverts** par les ADRs existants (gap G-8 identifié par `/architecture-review` du 2026-04-23, verdict CONCERNS). Sans ADR dédié :

- **Structure de scène non-stable** : la hiérarchie R-1 (`StaticEnvironment / InteractiveVolumes / SpawnMarkers / OnboardingAnchors / EtageExitTrigger`) n'a pas d'autorité figée. Un développeur peut aplatir la hiérarchie ou inverser les ownerships par pragmatisme, cassant les 3 specialists downstream (Checkpoint / Enemy / Secret) qui s'attendent à des lookups nommés exacts.
- **Stratégie de chargement non-décidée** : scene unique vs split-per-room vs streaming inter-étage (Tier 2+). OQ-1 a été **fermée dans le GDD** (scene unique MVP), mais sans ADR, la décision n'est pas propagée aux stories ni au lint pré-build.
- **Contrat signal non-figé** : 7 signals (`level_active`, `level_unloading`, `etage_completed`, `level_load_failed`, `level_load_slow`, `room_entered`, `player_out_of_world`) sont listés en §Dependencies + §Signals §Detailed Design mais sans pattern architectural canonique (typage, ordre d'émission, idempotence, connect-mode par défaut). 21 ACs du Groupe C en dépendent.
- **Authoring invariants non-gate-able** : 11 invariants pré-build (door width ≥ 3.6 m, wall-run height ≥ 4 m, Y ≥ -2, PlayerStart unique, secret tuple cohérent, archetype @export obligatoire, budget draw calls par archetype, etc.) sont décrits en prose mais sans owner d'exécution (CI job `lint-level-invariants` est mentionné AC-LVL-51 mais pas architecturalement confirmé).
- **Memory & load budgets non-figés** : 50 MB VRAM par étage, 1000 ms load-time, 350 draw calls, 25 StaticBody3D par salle sont numérotés en formules F2/F4/F6 + Tuning Knobs sans ADR-level commitment. Un system-designer qui prototype au-delà peut casser silencieusement le budget Pillar 4.
- **Scene Node ownership ambiguë** : le GDD dit "Level System singleton autoload" (AC-LVL-1) mais ne précise pas si la scène `etage_NN.tscn` est fille directe de `/root` ou fille du singleton Level. Conséquence : `queue_free()` timing différent, réfs dangling possibles.
- **Reciprocity forward non-contractée** : la §Dependencies §Notes de réciprocité liste Enemy / Hazard / Secret / HUD / Tutorial / Audio comme Not Started mais l'ADR doit figer leurs points d'intégration (signal + API surface) pour qu'ils soient écrits en cohérence sans re-négociation.

Sans ADR-0011 figé, 21 TRs G-8 restent gap, l'epic `level-system` ne peut pas démarrer (stories sans contrat stable), et les 5 autres epics downstream (Checkpoint, Enemy, Hazard, Secret, HUD) sont bloquées sur `get_*_slots()` signatures. Coût cumulé estimé de divergence sans ADR : 3-4× re-review cross-GDD pour chaque nouveau peer, soit ~12-16h de retouches.

### Constraints

- **Engine** : Godot 4.6 + GDScript + Jolt + Forward+ D3D12 Windows. Scene tree API stable pré-4.0 (Node3D, Area3D, StaticBody3D, Marker3D, CollisionShape3D). `ResourceLoader.load_threaded_request` stable pré-4.3. Shader Baker 4.5+ disponible. NavigationRegion3D 4.6 stable. D3D12 launch-time only — pas de hot-switch (ADR-0003).
- **ADR-0001 acquis** : autorité gameplay `_physics_process`. Signal dispatch Level (`room_entered`, `player_out_of_world`) doit se produire depuis `_physics_process` ou handler direct de `body_entered` (Area3D → `_physics_process` frame suivante).
- **ADR-0003 acquis** : Forward+ + SMAA 1x + Compositor. Level respecte sous-budget 350 draw calls statiques (budget rendering 8 ms cumulé).
- **ADR-0005 acquis** : pattern direct typed signals, CONNECT_DEFERRED pour consumers lourds (critères a-d), outbound-only (aucune référence aval), lint forbidden pattern `event_bus_autoload_*`. Level doit suivre le **même pattern** que MovementController.
- **Pillar 1 — Zero-alloc hot path** : signaux Level émis depuis `room_entered` (RoomTrigger body_entered handler) et `player_out_of_world` (WorldBounds body_exited handler) ne doivent pas allouer. Payloads = value types (int, Vector3, String pré-alloué).
- **Pillar 4 — Performance constante** : budgets verrouillés — VRAM ≤ 50 MB / étage, draw calls ≤ 350 / étage isolé, load-time ≤ 1000 ms Tier 1, frame time p99 ≤ 14 ms intra-salle (headroom Jolt ~2.6 ms).
- **OQ-1 CLOSED** : scene unique MVP, pas de sub-scene instantiation runtime, pas de streaming inter-étage. Réouverture conditionnée Tier 2+ (>40 MB VRAM ou >800 ms load).
- **OQ-5 CLOSED** : pas d'ambient audio layer swap per-room MVP ; route activation 1-ligne via `AudioServer.set_bus_volume_db()` depuis handler `room_entered` quand Audio System est écrit.
- **Solo mode** : TD-ADR gate + engine-specialist gate skipped (cohérent `production/review-mode.txt`). Validation indépendante par `/architecture-review` fresh session obligatoire avant Accepted.
- **Foundation discipline** : LevelSystem est un système Feature (dépend de GameStateManager Foundation + ADR-0001/0003/0005). Il ne doit référencer aucun consumer par nom. Communication sortante exclusivement par signal + `get_*_slots()` read-only.

### Requirements

- **REQ-1** — Un seul `.tscn` par étage MVP. Pas de `PackedScene.instantiate()` runtime intra-étage (les primitives Mezzanine / Atrium / ShaftConnector / VerticalShaftRoom sont **inline** dans le fichier de scène, pas chargées à la demande).
- **REQ-2** — Hiérarchie canonique figée : 4 sous-arbres top-level mandatoires (`StaticEnvironment`, `InteractiveVolumes`, `SpawnMarkers`, `EtageExitTrigger`) + sous-arbre optionnel `OnboardingAnchors` (étage 1 uniquement). `Level.get_node("StaticEnvironment") != null` est un invariant runtime (AC-LVL-11).
- **REQ-3** — 7 signals typés figés (`level_active(etage_id: int, player_start: Vector3)`, `level_unloading(etage_id: int)`, `etage_completed(etage_id: int)`, `level_load_failed(etage_id: int, reason: String)`, `level_load_slow(elapsed_ms: int)`, `room_entered(room_index: int, total_rooms: int)`, `player_out_of_world(last_valid_position: Vector3)`). Signatures **immutables** sans amendement. Changement = amendement ADR-0011 + propagation cross-peers.
- **REQ-4** — 6 lookups spatiaux figés (`get_checkpoint_slots() -> Array`, `get_enemy_slots() -> Array[Marker3D]`, `get_hazard_slots() -> Array[Marker3D]`, `get_secret_slots() -> Array`, `get_tutorial_anchor(tag: String) -> Marker3D`, `get_onboarding_anchors() -> Dictionary`). Read-only. Publiés au moment de `level_active`. Zero-alloc runtime (arrays préconstruites en fin `_load_etage_scene`).
- **REQ-5** — State machine 4 états (`UNLOADED`, `LOADING`, `ACTIVE`, `UNLOADING`). Transitions atomiques T-1..T-4 (GDD §States). `load_etage(id)` n'est callable qu'en `UNLOADED` (assert en debug, push_error + no-op en release — AC-LVL-4).
- **REQ-6** — 11 invariants pré-build gate-ables par lint authoring-time : door width ≥ 3.6 m (F1), wall-run height ≥ 4 m + length ≥ 3 m + slope ±5° (F8/R-2.U.2), Y ≥ -2 m absolu (R-2.U.3), PlayerStart unique (R-5.3), checkpoint pair naming `_NN` (R-5.2), N_rooms ∈ [8, 10] (F2), archetype @export obligatoire (R-2.6), secret tuple Lure↔Volume↔Anchor même NN (R-4 r2 fix #4), onboarding anchors line-of-sight + distance contraintes étage 1 (R-4 r2 fix #5), budget draw calls / StaticBody3D / Area3D / Marker3D par archetype (R-4 r2), spacing checkpoints `floor(N_rooms/K) ∈ [2, 3]` (F3 + AC-LVL-51). Tous enforced par `tools/lint/level_lint.gd` CI job `lint-level-invariants`.
- **REQ-7** — Chargement async via `ResourceLoader.load_threaded_request` + polling `load_threaded_get_status` ≤ 1000 ms. Signal `level_load_slow(elapsed_ms)` advisory dès elapsed ≥ 600 ms (non-bloquant). Signal `level_load_failed(etage_id, reason)` fatal sur scène absente ou corrompue.
- **REQ-8** — LevelSystem = **autoload singleton** (cohérent avec InputManager, GameStateManager). La scène d'étage chargée est **attachée à l'arbre comme fille de `get_tree().root`** (pas fille du singleton Level, pour laisser Godot gérer `queue_free()` sans tree-rewire). Level singleton conserve une référence `_current_etage_root: Node3D` pour introspection.
- **REQ-9** — `WorldBoundsVolume` utilise **obligatoirement** `BoxShape3D` (pas ConcavePolygonShape3D, pas TrimeshShape). Enforced par `validate_level_shapes()` runtime lint debug (AC-LVL-38 + R-5.6). Raison : Jolt broad-phase O(1) sur box, O(N) sur concave 5800 m³.
- **REQ-10** — `SHADER_BAKER_ENABLED = true` Project Settings obligatoire + précompilation boot global (scène dummy invisible, 1 frame) pour éviter freeze 50-150 ms première frame post-`level_active` (Tech-Risk-2 Godot addendum — VR-LVL-1).
- **REQ-11** — `NavigationRegion3D` baked **en éditeur** (authoring-time) et exporté avec `etage_NN.tscn`. Enemy System ne rebake **jamais runtime** (coût 200-800 ms exploserait F4 budget load-time). Contrat bilatéral avec Enemy System à acter dans son GDD quand il est écrit.
- **REQ-12** — Zero major allocation post-`level_active` : delta `OS.get_static_memory_usage()` ≤ 512 KB sur 60 s d'exploration + delta `Performance.OBJECT_COUNT` ≤ +5 (AC-LVL-36). Aucun `Array.push_back()` hot path `room_entered` / `player_out_of_world` (les arrays sont pré-construites à `_load_etage_scene`).
- **REQ-13** — Discipline outbound-only — Level System ne référence aucun consumer par nom (pas de `CheckpointSystem.notify()`, pas de `HUDSystem.update()`). Communication sortante exclusivement via 7 signaux + 6 lookups (patron ADR-0005 REQ-5 généralisé).
- **REQ-14** — Aucune mutation d'état Level depuis un signal handler consumer (pas de `level.unload_current()` depuis un callback Checkpoint). Write access exclusif au Level singleton lui-même + au GameStateManager orchestrateur (via `load_etage` / `unload_current`).

## Decision

Adopter les décisions D-1..D-13 ci-dessous comme pattern canonique pour l'architecture de scène Level. Elles forment la base implémentable du GDD Level r2 (confirment §Detailed Rules R-1..R-5) et servent de **référence verrouillée** pour les ADRs ultérieurs Checkpoint / Enemy / Hazard / Secret / HUD qui consommeront le contrat Level.

### D-1 — Single `.tscn` par étage, pas de streaming ni instantiation runtime (OQ-1 CLOSED)

Un étage MVP = un fichier `res://scenes/levels/etage_NN.tscn` unique contenant **toutes les salles inline** (primitives Mezzanine / Atrium / ShaftConnector / VerticalShaftRoom composées en sous-scene PackedScene authoring-time). Pas de `PackedScene.instantiate()` runtime intra-étage. Pas de room-streaming. Pas de sub-scene dynamic load.

- **Chargement** : `ResourceLoader.load_threaded_request("res://scenes/levels/etage_NN.tscn")` + polling `load_threaded_get_status()` jusqu'à `THREAD_LOAD_LOADED`. Budget ≤ 1000 ms Tier 1 (F4). Advisory `level_load_slow(elapsed)` émis dès elapsed ≥ 600 ms.
- **Justification** : 250 nœuds max par étage MVP (8-10 salles × ~25 nœuds moyens), bien sous le seuil traversal Godot. `ResourceLoader.load_threaded_request` n'a aucun overhead sur sub-scenes inline vs un `.tscn` monolithique. Aucun unload intra-étage → pas de leaks VRAM, pas de pop-in visuel.
- **Réouverture Tier 2+** : conditionnée par empirique `>40 MB VRAM` ou `>800 ms load` sur étage géant. Si déclenchée, ouverture ADR successeur (ADR-0019+ Level Streaming Tier 2+).
- **Forbidden** : `PackedScene.instantiate()` runtime pour contenu statique (mur, rampe, plafond). **Autorisé** : instantiation runtime par **peers** sur leurs slots (Enemy spawn sur `EnemySlot_NN`, Hazard spawn sur `HazardSlot_NN`, Secret content spawn sur `SecretAnchor_NN`) — ce n'est pas du contenu Level.

### D-2 — Hiérarchie de scène canonique (5 groupes top-level)

Tout `etage_NN.tscn` respecte strictement cette structure :

```
etage_NN.tscn (Node3D — racine étage)
├── StaticEnvironment      (Node3D — géométrie non-interactive, layer 4 LAYER_ENVIRONMENT)
│   ├── Room_01..Room_N    (Node3D avec @export archetype: RoomArchetype)
│   │   ├── Floor_01, Wall_01..M, Ramp_01..R  (StaticBody3D + CollisionShape3D)
│   │   ├── Primitives     (Node3D — PackedScene inline : Mezzanine / Atrium / ShaftConnector / VerticalShaftRoom)
│   │   └── MeshInstance3D + shader_chrome_zen_flat
│   └── NavigationRegion3D (baked authoring-time, NavMesh intra-étage)
├── InteractiveVolumes     (Node3D — triggers, layer 5 LAYER_INTERACTIVE)
│   ├── RoomTrigger_01..N       (Area3D — détection entrée salle)
│   ├── CheckpointVolume_01..K  (Area3D — ancre Checkpoint)
│   ├── SecretCollectVolume_01..M (Area3D — zone collection secret)
│   └── WorldBoundsVolume       (Area3D + BoxShape3D obligatoire — R-5.6)
├── SpawnMarkers           (Node3D — points nommés pour peers)
│   ├── PlayerStart                  (Marker3D — unique par étage, R-5.3)
│   ├── EnemySlot_01..P              (Marker3D — Enemy System lookup)
│   ├── HazardSlot_01..H             (Marker3D — Hazard System lookup)
│   ├── CheckpointAnchor_01..K       (Marker3D — Checkpoint respawn position)
│   ├── SecretLureMarker_01..M       (Marker3D — visuel pur, aucun collider)
│   └── SecretAnchor_01..M           (Marker3D — content spawn Secret)
├── OnboardingAnchors      (Node3D — optionnel, étage 1 uniquement)
│   ├── FirstEnemySightline          (Marker3D — contrat Combat Rule 16)
│   └── SafeZoneCenter               (Marker3D — zone ≥ 3 m rayon safe)
└── EtageExitTrigger       (Area3D — fin d'étage)
```

- **Invariant runtime** : `Level.get_current_etage_root().get_node_or_null(group) != null` pour chaque groupe top-level mandatoire (AC-LVL-11). Gate `_validate_scene_hierarchy()` appelé en fin de transition `Loading → Active` (avant émission `level_active`). Fail = `level_load_failed(etage_id, "invalid hierarchy: <group> missing")`.
- **Conventions nommage** : zero-padded 2 chiffres `_NN`. Cohérence indexée `CheckpointVolume_NN ↔ CheckpointAnchor_NN` et `SecretLureMarker_NN ↔ SecretCollectVolume_NN ↔ SecretAnchor_NN` enforced par lint pré-build (AC-LVL-19, AC-LVL-53).
- **Forbidden** : ajout de sous-arbres top-level hors des 5 canoniques (ex: `Doodads`, `Decorations`) — ces éléments appartiennent à `StaticEnvironment/Room_NN`. Ajout = amendement ADR-0011.

### D-3 — LevelSystem = autoload singleton (Foundation-adjacent)

`LevelSystem` (classe GDScript `class_name LevelSystem extends Node`) est enregistré comme **autoload singleton** Godot, cohérent avec InputManager, GameStateManager, SaveLoadSystem. Ordre d'autoload : après GameStateManager (dépend de GSM pour orchestration), après InputManager (pas de dépendance directe mais même layer Foundation/Core boot). Path : `res://src/gameplay/level/level_system.gd` (Feature layer par taxonomy, mais boot pattern = autoload pour accès global peers).

- **Référence runtime** : `_current_etage_root: Node3D` (membre privé). Initialisé à `null` en `UNLOADED`. Pointe vers la racine `etage_NN.tscn` chargée une fois `ACTIVE`.
- **Scene Node attachment** : lors de la transition `Loading → Active`, la racine étage chargée est ajoutée à l'arbre via `get_tree().root.add_child(_current_etage_root)`. **Pas** `self.add_child(...)` — le singleton Level ne possède pas l'ownership du tree, il orchestre et référence.
- **Unload** : lors de `Active → Unloading`, `_current_etage_root.queue_free()` puis `_current_etage_root = null` à la frame suivante. 1 frame de délai garanti pour que les peers reçoivent `level_unloading` et désabonnent leurs Area3D.body_entered (T-3 GDD).
- **Forbidden** : accès à `LevelSystem` depuis un `Thread` non-main ou `WorkerThreadPool.add_task` callback. Même pattern que `input_singleton_access_from_non_main_thread` (ADR-0004). Assert debug build `Thread.get_caller_id() == OS.get_main_thread_id()` sur méthodes publiques.

### D-4 — State machine `LevelState` : enum typé, 4 états, transitions atomiques

```gdscript
class_name LevelSystem
extends Node

enum LevelState {
    UNLOADED,    # Boot initial / post-Unloading
    LOADING,     # ResourceLoader.load_threaded_request en cours
    ACTIVE,      # Scène attachée, peers câblés
    UNLOADING,   # queue_free() en cours
}
```

- **Transitions** : `UNLOADED → LOADING` (sur `load_etage`), `LOADING → ACTIVE` (sur resources_ready), `ACTIVE → UNLOADING` (sur `unload_current` OR `EtageExitTrigger.body_entered`), `UNLOADING → UNLOADED` (1 frame après queue_free).
- **Transitions atomiques** : chaque transition est traitée en un seul call-path synchrone (pas de state intermédiaire "Transitioning"). Les signals `level_active` / `level_unloading` sont émis **immédiatement après** le `_state = ...` assignment, jamais avant (`state_changed` implicite lu via `get_state()`).
- **T-1** — `load_etage(id)` n'est callable qu'en `UNLOADED`. En `LOADING` / `ACTIVE` / `UNLOADING` : debug build `assert()` fail + message "concurrent load: unload first" ; release build `push_error` + no-op (AC-LVL-4, AC-LVL-39).
- **T-2** — `LOADING → ACTIVE` : publie `level_active(etage_id, player_start)` **après** `add_child(_current_etage_root)` et **après** `_validate_scene_hierarchy()` PASS. Peers reçoivent le signal dans la frame où la scène est attachée (lookup spatial disponible).
- **T-3** — `ACTIVE → UNLOADING` : publie `level_unloading(etage_id)` **avant** `queue_free()`. Peers déconnectent leurs `body_entered` dans le handler `_on_level_unloading`. Frame suivante : `queue_free()` effectif, `_state = UNLOADED`.
- **T-4** — Room transitions (`RoomTrigger_NN.body_entered`) n'affectent PAS l'état Level. Elles émettent `room_entered(index, total_rooms)` uniquement. Aucune salle n'est unloadée intra-étage.
- **Introspection** : `func get_state() -> LevelState` + `func get_current_etage_id() -> int` (retourne `-1` si `UNLOADED`). Both read-only, synchrones, gratuits. Pas de `state_changed` signal séparé (redondant avec `level_active` / `level_unloading`).
- **Forbidden** : mutation de `_state` depuis un handler consumer (ex: HUD qui appelle `level._state = UNLOADED` pour forcer un reset). Write access exclusif interne `LevelSystem`.

### D-5 — 7 signals typés figés (contract immutable sans amendement)

```gdscript
signal level_active(etage_id: int, player_start: Vector3)
signal level_unloading(etage_id: int)
signal etage_completed(etage_id: int)
signal level_load_failed(etage_id: int, reason: String)
signal level_load_slow(elapsed_ms: int)
signal room_entered(room_index: int, total_rooms: int)
signal player_out_of_world(last_valid_position: Vector3)
```

- **Typed payloads** : tous les paramètres sont typés explicitement (int / Vector3 / String). Debug build vérifie la connexion (godot-specialist F5 — mismatch silencieux en release). Test CI `tests/unit/level/test_level_signals_typed.gd` introspecte `get_signal_list()` et vérifie signatures exactes (AC-LVL-27).
- **Ordre d'émission intra-tick déterministe** :
  - `level_active` après `_validate_scene_hierarchy()` PASS + `add_child` complet.
  - `level_unloading` avant `queue_free()`, jamais après.
  - `etage_completed` sur `EtageExitTrigger.body_entered` — fires-once (flag `_exit_fired: bool`), même si le joueur ressort et re-rentre (`_state` est déjà `UNLOADING`). AC-LVL-24.
  - `player_out_of_world` sur `WorldBoundsVolume.body_exited` — 1 émission par sortie, reset implicite sur respawn Checkpoint. AC-LVL-25.
  - `room_entered` sur `RoomTrigger_NN.body_entered` — non-idempotent par design (re-entry émet un autre signal, HUD décide dédup). AC-LVL-22. Ordre déterministe sur triggers chevauchants = ordre de l'arbre `InteractiveVolumes` (AC-LVL-23).
  - `level_load_slow` advisory — émis au moins une fois quand elapsed ≥ 600 ms ; peut être émis plusieurs fois si le seuil est re-franchi (ex: burst disk I/O).
  - `level_load_failed` fatal — scène absente, corrompue, ou `_validate_scene_hierarchy()` FAIL. État reste `UNLOADED`. AC-LVL-6.
- **Connection mode par défaut** (suivant ADR-0005 D-5 critères a-d) :
  - `level_active` → CONNECT_DEFERRED recommandé (consumers peers instancient ennemis, hazards, VFX — alloc heavy).
  - `level_unloading` → sync (consumers désabonnent `body_entered` — alloc négligeable).
  - `etage_completed` → CONNECT_DEFERRED (HUD flash + GSM scene transition — heavy).
  - `level_load_failed` → sync (Menu affiche erreur — simple toggle UI).
  - `level_load_slow` → sync (HUD toggle spinner — light).
  - `room_entered` → sync pour HUD (toggle label), CONNECT_DEFERRED pour Audio / Tutorial (instantiate AudioStreamPlayer / Panel).
  - `player_out_of_world` → sync pour Checkpoint (read Vector3 + appel `respawn()` qui est idempotent via ADR-0005 pattern).
- **Émission depuis main thread uniquement** — Assert `Thread.get_caller_id() == OS.get_main_thread_id()` avant chaque `emit_signal` en debug build (AC-LVL-29). Même pattern qu'`input_singleton_access_from_non_main_thread`.
- **Zero-alloc payloads** : tous les arguments sont value types ou StringName pré-alloué. Pas de Dictionary literal, pas d'Array construit inline, pas de concat String chaud.
- **Ajout d'un nouveau signal = amendement ADR-0011** (pas de drift silencieux GDD→impl).

### D-6 — 6 lookups spatiaux read-only (publiés à `level_active`)

```gdscript
func get_checkpoint_slots() -> Array           # Array[CheckpointSlot] — dict { volume: Area3D, anchor: Vector3 }
func get_enemy_slots() -> Array[Marker3D]
func get_hazard_slots() -> Array[Marker3D]
func get_secret_slots() -> Array               # Array[SecretSlot] — dict { lure: Marker3D, collect_volume: Area3D, content_anchor: Vector3, required_ability: StringName }
func get_tutorial_anchor(tag: String) -> Marker3D   # null si tag inconnu (push_warning debug)
func get_onboarding_anchors() -> Dictionary    # { "first_enemy_sightline": Marker3D, "safe_zone_center": Marker3D } — vide si étage ≠ 1
```

- **Construction** : les 4 Arrays `_checkpoint_slots`, `_enemy_slots`, `_hazard_slots`, `_secret_slots` sont pré-construites **une fois** en fin de `_load_etage_scene` (scan `find_children("EnemySlot_*", "Marker3D", true)` etc.) et cachées en membre privé. Lookups sont `return _enemy_slots` (zero-alloc, zero-traversal runtime).
- **Lifetime** : valides de `level_active` émis jusqu'à `level_unloading` reçu. Peers doivent invalider leurs références dans leur handler `_on_level_unloading` (avant `queue_free` effectif).
- **`get_tutorial_anchor(tag)`** : lookup `find_child("TutorialAnchor_" + tag, true)` synchrone. Null si absent — pas de crash, `push_warning` en debug. AC-LVL-30.
- **`get_onboarding_anchors()`** : retourne `{}` vide pour étage ≠ 1. Combat / Enemy consomment via existence-check non-fatal (`if anchors.has("first_enemy_sightline")`).
- **Forbidden** : mutation des arrays retournées par les consumers (`slots.push_back(...)`). Les arrays sont partagées par référence ; mutation casse les lookups ultérieurs. Convention : les consumers itèrent read-only. Lint runtime debug : `_checkpoint_slots.make_read_only()` appelé à la construction (Godot 4.6 `Array.make_read_only()`).
- **Structures internes** : `CheckpointSlot` et `SecretSlot` sont des `Dictionary` GDScript (pas `class_name`) — choix pragmatique solo mode, évite class boilerplate. Clés canoniques figées : `{volume, anchor}` pour Checkpoint ; `{lure, collect_volume, content_anchor, required_ability}` pour Secret. Amendement ADR-0011 si clés changent.

### D-7 — 11 invariants pré-build gate-ables par lint `level_lint.gd`

`tools/lint/level_lint.gd` (script éditeur Godot, appelé par CI job `lint-level-invariants` sur chaque `etage_*.tscn` commité) vérifie les 11 invariants listés REQ-6. Chaque fail = lint exit code non-zero, blocking merge.

| # | Invariant | Source | AC gate |
|---|-----------|--------|---------|
| 1 | Porte width ≥ 3.6 m | Formula 1 (2× KATANA_REACH) | AC-LVL-14 |
| 2 | Wall-run height ≥ 4 m + length ≥ 3 m + slope ±5° | Formula 8, R-2.U.2 | AC-LVL-15 |
| 3 | Y ≥ -2.0 m absolu | R-2.U.3 | AC-LVL-16 |
| 4 | PlayerStart unique | R-5.3 | AC-LVL-18 |
| 5 | CheckpointVolume_NN ↔ CheckpointAnchor_NN appariement + distance ≤ 10 m | R-5.2 | AC-LVL-19 |
| 6 | N_rooms ∈ [8, 10] | Formula 2, Tuning Knob `ROOM_COUNT` | AC-LVL-20 |
| 7 | `archetype: RoomArchetype` @export obligatoire | R-2.6 | AC-LVL-52 |
| 8 | Secret tuple Lure↔Volume↔Anchor même NN + `required_ability ∈ {none, dash, double_jump, wall_run, wall_run_long}` | R-4 r2 fix #4 | AC-LVL-53 |
| 9 | Onboarding anchors (étage 1) : sightline non obstruée + distance ≤ 15 m + SafeZone ≥ 6 m de EnemySlot + ≥ 4 m de HazardSlot | R-4 r2 fix #5 | AC-LVL-54 |
| 10 | Budget par archetype : DC / StaticBody3D / Area3D / Marker3D dans les ranges R-4 r2 | R-4 r2 | AC-LVL-55 |
| 11 | Spacing checkpoint `floor(N_rooms/K) ∈ [2, 3]` | Formula 3, AC-LVL-51 | AC-LVL-51 |

- **Implementation** : `tools/lint/level_lint.gd` charge chaque `etage_*.tscn`, itère les nœuds, applique les 11 vérifications. Message d'erreur standardisé : `"level_lint: <etage> <invariant_name> FAIL — <detail>"`. Exit 1 sur ≥ 1 fail.
- **CI job** : `.github/workflows/tests.yml` ajout job `lint-level-invariants` : `godot --headless --script tools/lint/level_lint.gd --path .`. Échoue le pipeline.
- **Pas runtime** : les 11 invariants sont **authoring-time**. Runtime, seul `_validate_scene_hierarchy()` (5 groupes top-level) + `validate_level_shapes()` (WorldBoundsVolume = BoxShape3D) sont exécutés en debug build. Les invariants #1-#11 ne sont pas re-vérifiés runtime (coût load-time).

### D-8 — Chargement async `ResourceLoader.load_threaded_request` + budget 1000 ms

Séquence `load_etage(id)` :

```gdscript
func load_etage(id: int) -> void:
    assert(_state == LevelState.UNLOADED, "Level: concurrent load, call unload_current() first")
    _state = LevelState.LOADING
    _load_start_ms = Time.get_ticks_msec()
    _pending_etage_id = id
    var path := "res://scenes/levels/etage_%02d.tscn" % id
    var err := ResourceLoader.load_threaded_request(path)
    if err != OK:
        _emit_level_load_failed(id, "load_threaded_request error: %d" % err)
        return
    # Poll chaque frame _process (safe - pas de mutation gameplay)
    set_process(true)

func _process(_delta: float) -> void:
    if _state != LevelState.LOADING:
        set_process(false)
        return
    var elapsed := Time.get_ticks_msec() - _load_start_ms
    if elapsed >= LOAD_SLOW_THRESHOLD_MS and not _slow_emitted:
        _slow_emitted = true
        level_load_slow.emit(elapsed)
    var status := ResourceLoader.load_threaded_get_status(_pending_path)
    match status:
        ResourceLoader.THREAD_LOAD_LOADED:
            _finalize_active()
        ResourceLoader.THREAD_LOAD_FAILED:
            _emit_level_load_failed(_pending_etage_id, "THREAD_LOAD_FAILED")
        ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            _emit_level_load_failed(_pending_etage_id, "INVALID_RESOURCE")
        # IN_PROGRESS — continue polling
```

- **Budget** : 1000 ms ligne dure (F4 Tuning Knob `LOAD_TIME_BUDGET_MS`). Dépassement = advisory signal `level_load_slow(elapsed_ms)` répété à chaque poll tant que elapsed ≥ 600 ms. Le load continue, pas interrompu.
- **Failure** : `THREAD_LOAD_FAILED` ou `THREAD_LOAD_INVALID_RESOURCE` ou scène absente → `level_load_failed(id, reason)` + `_state = UNLOADED`. Menu System affiche écran d'erreur.
- **Polling via `_process`** : exception explicite à la règle `mutate_gameplay_state_in_process` (ADR-0001) — le polling ne mute pas d'état gameplay, il orchestre la transition de state machine Level. `set_process(false)` dès que `_state != LOADING`.
- **Alternative rejetée** : `ResourceLoader.load(path)` synchrone (bloque 300-1000 ms, freeze main thread, casse Pillar 1). `PackedScene.instantiate()` sans preload (aucun async API, bloquant aussi).

### D-9 — `WorldBoundsVolume = BoxShape3D` obligatoire (Jolt broad-phase)

`InteractiveVolumes/WorldBoundsVolume` est un `Area3D` avec **exactement un** `CollisionShape3D` enfant dont la `shape: Shape3D` est une `BoxShape3D`. Pas `ConcavePolygonShape3D`, pas `ConvexPolygonShape3D`, pas `TrimeshShape3D`.

- **Raison** : Jolt physics broad-phase (ADR-0001 Jolt default 4.6) gère efficacement une Area3D convex box (1 shape = O(1) overlap query), mais explose en coût CPU sur concave shape de 5800 m³ (traversal polygon-par-polygon à chaque physics tick). Mesure typique : BoxShape3D ~5 μs / tick vs ConcavePolygonShape3D ~1.5 ms / tick sur étage MVP.
- **Enforcement runtime** : `validate_level_shapes(root: Node) -> Array[ValidationError]` appelé en fin de transition `Loading → Active` en debug build. Scan du WorldBoundsVolume, assert `shape is BoxShape3D`. Fail = `push_error("level: WorldBoundsVolume must use BoxShape3D (Jolt broad-phase) — found %s" % shape.get_class())` + `level_load_failed` en release build strict.
- **Enforcement authoring** : `level_lint.gd` invariant #12 (advisory — pas blocking merge MVP, promu BLOCKING si VR-LVL-3 révèle régression perf).
- **Alternative rejetée** : ConcavePolygonShape3D (perf 300× pire). ConvexHullShape3D (fonctionne mais perd l'avantage de l'AABB broad-phase pure).

### D-10 — Shader Baker + précompilation boot (Tech-Risk-2 mitigation)

Project Settings → Rendering → Shader Compiler → **Enable Shader Baker = true** (Godot 4.5+, disponible 4.6 confirmé engine-ref `rendering.md`). Plus : précompilation **boot-time globale** :

- **Boot sequence** : au `GameStateManager._ready()` (autoload #2 après InputManager), instancier une scène dummy invisible `res://scenes/internal/shader_warmup.tscn` qui contient 1 `MeshInstance3D` + 1 `ShaderMaterial` utilisant `shader_chrome_zen_flat.gdshader`. Rendre 1 frame via `RenderingServer.force_sync()` puis `queue_free()`. Latence totale < 200 ms acceptable (pendant écran de chargement initial).
- **Raison** : sans précompilation, la première frame après `level_active` (première fois que le pipeline D3D12 rencontre le shader) freeze 50-150 ms (compilation JIT pipeline state object D3D12 first-use). Cela casse la lecture du `level_active` + spawn peers (spike visible utilisateur). ADR-0003 avait flaggé ce risque en advisory ; ADR-0011 le résout par précompilation obligatoire.
- **CI gate** : `lint-project-settings` job vérifie `rendering/shader_compiler/enable_shader_baker = true` dans `project.godot`. Fail merge si absent.
- **Forbidden** : désactiver Shader Baker (= violation F4 budget load). Amendement ADR-0011 requis si exception est envisagée (ex: debug build sans Shader Baker pour itération rapide).

### D-11 — NavigationRegion3D baked authoring-time uniquement (réciprocité Enemy)

Chaque `etage_NN.tscn` contient une `NavigationRegion3D` **pré-bakée en éditeur** avec le NavMesh calculé sur `StaticEnvironment`. Le bake est exporté dans le `.tscn` (ressource persistée).

- **Level responsibility** : inclure une `NavigationRegion3D` dans la hiérarchie (sous-enfant de `StaticEnvironment` ou top-level — TBD par Enemy System GDD). Bake en éditeur avant commit. NavMesh includes walkable floor surfaces + ramps.
- **Enemy System responsibility** (contrat bilateral — à formaliser dans `design/gdd/enemy-system.md` quand écrit) : **jamais** appeler `NavigationRegion3D.bake_navigation_mesh()` runtime. Utiliser la NavMesh baked telle qu'incluse dans la scène.
- **Raison** : bake runtime sur étage 5000 m³ coûte 200-800 ms (Tech-Risk-1 Godot addendum GDD r2). Cela viendrait **directement** sur le budget F4 (1000 ms load) — violation Pillar 4 garantie. Bake authoring-time = coût 0 runtime.
- **Forbidden** : modification runtime de la NavMesh (ajout d'obstacles dynamiques, carving). Si Enemy System Tier 2+ a besoin (ennemis destructibles), ouverture ADR successeur + amendement réciprocité.
- **Lint** : `level_lint.gd` invariant #13 (advisory) vérifie présence d'une `NavigationRegion3D` avec `navigation_mesh != null` dans `etage_NN.tscn`.

### D-12 — Discipline outbound-only + mutation forbidden (patron ADR-0005 REQ-5/6)

LevelSystem singleton est **outbound-only** : aucune référence directe à Checkpoint / Enemy / Hazard / Secret / HUD / Tutorial / Audio / VFX. Pas de `class_name CheckpointSystem`, pas de `$/root/CheckpointSystem`, pas de `get_node("CheckpointSystem").notify(...)`. Communication sortante exclusivement via 7 signals D-5 + 6 lookups D-6.

- **Alignement avec forbidden_patterns ADR-0005** :
  - `event_bus_autoload_for_movement_intra_gameplay_events` → généralisation : pas d'EventBus pour events Level (les signaux sont émis **directement** sur le singleton Level).
  - `mutate_movement_state_from_signal_handler` → généralisation : les consumers (Checkpoint, HUD, etc.) ne doivent JAMAIS muter l'état Level depuis un signal handler (pas de `level.unload_current()` depuis `_on_room_entered`). Write access `_state` exclusif à LevelSystem + GameStateManager orchestrateur.
  - `emit_movement_signal_from_process_not_physics_process` → adapté : les signaux Level sont émis depuis `_physics_process` (via body_entered callbacks Area3D qui sont sync 60 Hz) OU depuis le polling `_process` du loading (exception D-8 documentée).
- **Forbidden pattern à enregistrer au registry** :
  - `level_system_direct_reference_to_peers` : LevelSystem referencing Checkpoint/Enemy/Hazard/Secret/HUD/Tutorial/Audio/VFX by class_name, NodePath, or static method call.
  - `mutate_level_state_from_peer_signal_handler` : peer mutating `Level._state`, `Level._current_etage_root`, or calling `Level.load_etage()` / `Level.unload_current()` from a signal handler. Only GameStateManager is authorized for the latter two calls (via ADR-0007).
- **Authorized mutations** : `GameStateManager.request_scene_transition(etage_N)` → `LevelSystem.load_etage(N)` (direct call). `GameStateManager.request_quit_to_menu()` → `LevelSystem.unload_current()` (direct call). `Checkpoint._on_player_out_of_world(last_pos)` → read `last_pos`, trigger respawn **on Checkpoint's own anchor**, never touch Level state.

### D-13 — Budgets perf verrouillés (contrat Pillar 4)

| Budget | Limite MVP | Enforcement | AC |
|--------|-----------|-------------|-----|
| Load time étage | ≤ 1000 ms Tier 1 | Mesure runtime `level_active_elapsed` | AC-LVL-3 |
| VRAM statique étage | ≤ 50 MB | `RenderingServer.get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)` delta post-load | AC-LVL-32 |
| RAM statique étage | ≤ 20 MB | `OS.get_static_memory_usage()` delta post-load | AC-LVL-37 |
| Draw calls étage isolé | p99 ≤ 350 / 500 frames | `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` | AC-LVL-31 |
| Draw calls combat normal (3 enemies + 1 swing + VFX) | p99 ≤ 500 (global cap ADR-0003) | même | AC-LVL-31b |
| StaticBody3D par salle | ≤ 25 | lint pré-build | AC-LVL-33 |
| Frame time intra-salle | p50 ≤ 12 ms / p99 ≤ 14 ms | mesure 500 frames | AC-LVL-34 |
| Frame time room transition | p99 ≤ 14 ms sur fenêtre ±200 ms `room_entered` | mesure ciblée | AC-LVL-35a |
| Allocation delta post-`level_active` (60 s) | ≤ 512 KB static + ≤ +5 object_count | `OS.get_static_memory_usage()` + `Performance.OBJECT_COUNT` | AC-LVL-36 |

- **Pillar 4** : dépassement = build fail CI OR feature freeze jusqu'à retouche. Pas de graceful degradation silencieuse.
- **Registry registration** : budget `level` = contrat Pillar 4 implicite. Ajout au `performance_budgets` registry en phase 6 du skill.

## Alternatives Considered

### Alternative 1: Room-split streaming (une `.tscn` par salle, load/unload intra-étage)

- **Description** : chaque salle est un fichier `room_NN.tscn` séparé, chargé async quand le joueur approche et unloadé quand il s'éloigne. Level System orchestre le streaming.
- **Pros** : VRAM footprint plus petit par tick (1-2 salles en mémoire au lieu de 10). Permet étages Tier 2+ de 50+ salles.
- **Cons** :
  - **Overhead ResourceLoader** : chaque transition de salle déclenche une `load_threaded_request` (50-200 ms). Risque de stutter visible aux portes.
  - **Complexité state machine** : 10 salles × 4 états par salle = 40 états interactifs, chacun avec timing de bake NavMesh distinct. Explosion combinatoire de bugs.
  - **NavigationRegion3D fragmentation** : chaque salle a sa propre nav mesh, les pathfinders ennemis traversant les portes se perdent. Nécessite NavigationServer3D multi-map sync — hors scope MVP.
  - **Pop-in visuel** : les salles adjacentes doivent être visibles au loin (lure secrets cross-room, puits 40 m) — requiert LOD persistant + streaming asymétrique → complexité x10.
- **Rejection Reason** : OQ-1 fermée par godot-specialist (GDD addendum) — 250 nœuds max par étage MVP est largement sous le seuil traversal Godot, pas de gain mesurable de streaming vs scene unique. La complexité ajoutée casse le Pillar 4 constance perf sans bénéfice. Réouverture conditionnée Tier 2+ (>40 MB VRAM ou >800 ms load) via ADR successeur.

### Alternative 2: LevelSystem fils de la scène d'étage (pas autoload)

- **Description** : `LevelSystem` est un node enfant de `etage_NN.tscn` lui-même, pas un autoload. GameStateManager charge `etage_NN.tscn` dans `/root`, et le script Level attaché à la racine orchestre.
- **Pros** : pas de singleton global (plus testable isolément). Ownership scene tree naturel (racine gère ses enfants).
- **Cons** :
  - **Race au boot** : tant que `etage_NN.tscn` n'est pas chargé, `LevelSystem` n'existe pas. Les peers qui veulent s'y connecter au `_ready()` doivent polling ou écouter un signal GSM. Complexité x2.
  - **Inconsistance avec pattern Foundation** : InputManager, GameStateManager, SaveLoadSystem sont autoloads. Peers se connectent via `InputManager.mouse_motion.connect(...)` partout. Casser le pattern pour Level = friction dev.
  - **Lookup spatial avant load_etage** : `get_checkpoint_slots()` appelé avant que l'étage soit chargé → crash nil reference. Avec autoload, retourne Array vide proprement.
- **Rejection Reason** : pattern inconsistent avec Foundation autoload convention. AC-LVL-1 GDD r2 confirme autoload. Solo mode productivity > testability (GUT peut mocker un autoload via injection Node temp dans tree).

### Alternative 3: EventBus autoload `LevelEvents` centralisant les 7 signals

- **Description** : un autoload `LevelEvents` expose les 7 signaux. LevelSystem émet via `LevelEvents.level_active.emit(...)`. Peers se connectent à `LevelEvents.level_active.connect(...)`.
- **Pros** : découplage apparent (peers ne dépendent pas de LevelSystem directement). Facilite refactor multi-Level parallèle (coop Tier 4+).
- **Cons** :
  - **Double dispatch** : emit → LevelEvents → re-dispatch. Overhead 60 Hz × 7 signals × 3-6 consumers.
  - **Coupling caché via singleton** : les consumers paraissent découplés mais dépendent tous d'un shared singleton. Cascade bug quand LevelEvents change de nom ou est renommé.
  - **Aggregation prématurée** : empêche des ADRs ultérieurs d'introduire un 2e Level parallèle (coop Tier 4+ hypothétique). Mais le coop n'est pas MVP — YAGNI.
  - **Inconsistant ADR-0005** : MovementController émet directement sur le Player node. EventBus pour Level casserait le pattern canonique Godot direct-signal posé par ADR-0005 D-1.
- **Rejection Reason** : ADR-0005 a déjà rejeté ce pattern pour Movement (forbidden_pattern `event_bus_autoload_for_movement_intra_gameplay_events`). Appliquer le même raisonnement à Level = cohérence. Direct signals sur LevelSystem autoload est idiomatique, testable, zero-overhead.

## Consequences

### Positive

- **21 TRs G-8 débloqués** → epic `level-system` peut démarrer Sprint 1.
- **5 epics downstream débloquées partiellement** (Checkpoint, Enemy, Hazard, Secret, HUD) — signatures `get_*_slots()` + signals figées.
- **Lint authoring-time gate les 11 invariants critiques** → pas de drift silencieux design → scène.
- **Scene loading budget 1000 ms verrouillé** → Pillar 4 constance perf protégé.
- **Pattern direct signals cohérent avec ADR-0005** → pas de dérive architecturale entre systèmes.
- **Shader Baker précompilation éliminé stutter première frame** → Pillar 1 protégé.
- **NavigationRegion3D baked authoring-time** → protège F4 load budget contre Enemy System futur.
- **Outbound-only discipline** → Level testable isolément (GUT), peers testables isolément (mock LevelSystem singleton).
- **WorldBoundsVolume = BoxShape3D figé** → Jolt broad-phase reste O(1).

### Negative

- **Scene unique MVP contraint** : si un étage atteint 40 MB VRAM ou 800 ms load, ADR-0011 doit être révisé OU ADR-0019+ Level Streaming Tier 2+ ouvert. Pas de graceful degradation intra-MVP.
- **7 signals + 6 lookups = 13 points d'intégration figés** : amendement ADR-0011 requis pour chaque nouveau (pas de drift). Coût dev ~2h par amendement (révision + propagation).
- **11 invariants lint = maintenance continue** : ajout d'un archetype ou d'un budget = ajout lint rule + régression test. Coût ~4h par ajout.
- **Autoload singleton LevelSystem = état global** : testabilité requiert injection pattern (mock via `LevelSystem._instance = mock_level` ou équivalent). Boilerplate test.
- **Shader Baker précompilation obligatoire** : ~200 ms ajoutés au boot (invisible utilisateur pendant écran de chargement initial, mais réel). Acceptable MVP.

### Risks

- **Risk 1 — ResourceLoader.load_threaded_request timing variable sur SSD SATA vs NVMe** : le budget 1000 ms Tier 1 est mesuré sur SSD SATA entry-level. NVMe load en 200-400 ms (marge confortable). Mais HDD mécanique (Tier 0 non-MVP) peut atteindre 3-5 s. Mitigation : `level_load_slow(elapsed_ms)` advisory, HDD = out-of-spec, pas gate MVP. VR-LVL-2.
- **Risk 2 — Shader Baker compatibilité builds export** : Godot 4.5+ Shader Baker est nouveau, comportement en build export Windows D3D12 pas empiriquement vérifié sur target laptop. Mitigation : VR-LVL-1 test first export build Sprint 1 ; fallback activé Project Settings `shader_compiler/enable_shader_baker = false` si crash export (n'est pas MVP gate).
- **Risk 3 — NavigationRegion3D bake authoring-time régression Godot 4.7+** : bake API peut changer post-MVP. Mitigation : pin engine version 4.6 dans `project.godot`, upgrade intentionnel seulement (avec re-bake forcé).
- **Risk 4 — BoxShape3D WorldBoundsVolume layer 5 shape too large** : si le level designer crée une boîte 100×100×100 m englobant trop, Jolt broad-phase reste O(1) mais peut overlap avec tous les player movements légitimes → trigger `body_exited` permanent. Mitigation : `validate_level_shapes()` runtime vérifie que WorldBoundsVolume.AABB n'englobe pas au-delà de `AABB_union(StaticEnvironment) + WORLD_BOUNDS_PAD` (Tuning Knob). AC-LVL-49.
- **Risk 5 — 11 invariants lint trop stricts bloquent itération** : le level-designer peut être bloqué par lint fail sur contraintes marginales (ex: archetype @export manquant sur salle prototype). Mitigation : mode `godot --headless --script tools/lint/level_lint.gd --warn-only` pour itération locale (CI reste strict). Lint rules numérotées pour skip ciblé.
- **Risk 6 — Signal `room_entered` émis 60×/s sur joueur frais dans trigger overlap zone** : si deux RoomTriggers se chevauchent significativement et le joueur s'y déplace lentement, plusieurs `body_entered`/`body_exited` par seconde → spam HUD. Mitigation : `ROOM_TRIGGER_PAD = 0.3 m` Tuning Knob garantit overlap minimal (0.3 m) sans zone morte ; EC-5 GDD couvre ordre déterministe.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| level-system.md | R-1 hiérarchie canonique (§Detailed Rules) | D-2 fige 5 sous-arbres top-level + invariants runtime `_validate_scene_hierarchy()` (AC-LVL-11) |
| level-system.md | R-2.U / R-2.A invariants placement géométrique | D-7 lint `level_lint.gd` 11 invariants (AC-LVL-14/15/16/18/19/20/52/53/54/55) |
| level-system.md | R-2.6 enum RoomArchetype + @export | D-7 invariant #7 lint pré-build (AC-LVL-52) |
| level-system.md | R-3 layers collision 4 & 5 | Non adressé directement (layers taxonomy = G-5, ADR-0008 planifié) — noté en ADR Dependencies. D-2 structure les sous-arbres par layer mais la taxonomie formelle est hors scope. |
| level-system.md | R-4 budgets perf par archetype | D-7 invariant #10 (AC-LVL-55) + D-13 budget agrégé ≤ 350 DC (AC-LVL-31) |
| level-system.md | R-4 r2 fix #4 SecretLureMarker ≠ SecretCollectVolume ≠ SecretAnchor | D-2 hiérarchie fige les 3 marker types séparés + D-7 invariant #8 tuple cohérence (AC-LVL-53) |
| level-system.md | R-4 r2 fix #5 OnboardingAnchors étage 1 | D-2 sous-arbre optionnel + D-7 invariant #9 (AC-LVL-54) |
| level-system.md | R-5.1 single .tscn | D-1 OQ-1 CLOSED figé |
| level-system.md | R-5.2 naming convention `_NN` | D-7 invariants #5 + #8 (AC-LVL-19, AC-LVL-53) |
| level-system.md | R-5.3 PlayerStart unique | D-7 invariant #4 (AC-LVL-18) + assert runtime `_validate_scene_hierarchy()` |
| level-system.md | R-5.4 Area3D monitorable/monitoring | Non adressé directement (convention authoring GDD) — lint advisory possible successeur ADR |
| level-system.md | R-5.5 convex collision shapes | Non adressé directement (ADR-0001 Jolt contrainte — covered upstream) |
| level-system.md | R-5.6 WorldBoundsVolume BoxShape3D | D-9 + `validate_level_shapes()` runtime (AC-LVL-38) |
| level-system.md | States UNLOADED/LOADING/ACTIVE/UNLOADING + T-1..T-4 | D-4 state machine + D-5 signals émission ordre |
| level-system.md | §Interactions Checkpoint/Enemy/Hazard/Secret/HUD/Tutorial/Audio/VFX | D-5 signals + D-6 lookups = contrat complet peers |
| level-system.md | §Combat Onboarding Contract CO-1/CO-2/CO-3 | D-2 sous-arbre OnboardingAnchors + D-6 `get_onboarding_anchors()` + D-7 invariant #9 |
| level-system.md | Formula 1 door width 3.6 m | D-7 invariant #1 (AC-LVL-14) |
| level-system.md | Formula 2 draw calls ≤ 350 | D-13 + D-7 invariant #10 (AC-LVL-31, AC-LVL-55) |
| level-system.md | Formula 3 checkpoint spacing ∈ [2, 3] | D-7 invariant #11 (AC-LVL-51) |
| level-system.md | Formula 4 load time ≤ 1000 ms | D-8 `ResourceLoader.load_threaded_request` + polling `_process` (AC-LVL-3) |
| level-system.md | Formula 5 etage height [15, 30] m | Non gate-able authoring pure (AC-LVL-48 runtime) — noté hors scope ADR |
| level-system.md | Formula 6 WorldBoundsVolume AABB | D-9 + `validate_level_shapes()` runtime (AC-LVL-49) |
| level-system.md | Formula 7 secret density | D-7 invariant #8 tuple (AC-LVL-46) partiel ; density count = runtime AC |
| level-system.md | Formula 8 wall-run height 4 m | D-7 invariant #2 (AC-LVL-15) |
| level-system.md | Signals level_active/level_unloading/etage_completed/load_failed/load_slow/room_entered/player_out_of_world | D-5 fige 7 signals + typing + ordre (AC-LVL-21..27) |
| level-system.md | Lookups get_checkpoint_slots/get_enemy_slots/get_hazard_slots/get_secret_slots/get_tutorial_anchor/get_onboarding_anchors | D-6 fige 6 API (signatures AC-LVL-Interactions §Dependencies) |
| level-system.md | Tuning Knob SHADER_BAKER_ENABLED | D-10 obligatoire + précompilation boot + CI gate `lint-project-settings` |
| level-system.md | EC-1 player out-of-world | D-5 signal `player_out_of_world(last_valid_position)` ; D-9 WorldBoundsVolume (AC-LVL-25) |
| level-system.md | EC-2 concurrent load_etage | D-4 T-1 assert debug + push_error release (AC-LVL-4, AC-LVL-39) |
| level-system.md | EC-3 scène absente | D-8 `level_load_failed` (AC-LVL-6) |
| level-system.md | EC-4 PlayerStart absent | D-4 `_validate_scene_hierarchy` + D-7 invariant #4 (AC-LVL-8, AC-LVL-18) |
| level-system.md | EC-5 triggers chevauchants ordre | D-5 ordre DFS InteractiveVolumes (AC-LVL-23) |
| level-system.md | EC-6 annulation EtageExit | D-5 `_exit_fired` flag (AC-LVL-24) |
| level-system.md | EC-10 frame drop pendant Loading | D-8 polling `_process` non-bloquant + advisory `level_load_slow` |
| level-system.md | EC-11 peer race condition `level_active` | D-5 CONNECT_DEFERRED recommandé pour `level_active` (AC-LVL-26) |
| level-system.md | EC-12 quit-to-menu + re-load fresh state | D-3 `_current_etage_root = null` post-queue_free + D-4 `UNLOADING → UNLOADED` atomique (AC-LVL-9, AC-LVL-42) |
| player-combat-system.md | Rule 16 combat onboarding sightline | D-2 sous-arbre `OnboardingAnchors` + D-6 `get_onboarding_anchors()` — contrat Level → Combat figé |
| player-movement-system.md | LAYER_ENVIRONMENT = 4 (layer collision statique) | Non adressé (G-5, ADR-0008 planifié) — ADR-0011 respecte l'usage documenté GDD |

## Performance Implications

- **CPU** :
  - Scene load : ~300-800 ms Tier 1 SSD SATA (ResourceLoader thread). Main thread reste réactif via polling `_process`.
  - Signal dispatch Level (7 signals × 3-6 consumers × émission selon événement) : cumulé < 0.05 ms / frame stable. `room_entered` émis ~10×/étage (négligeable). `player_out_of_world` émis 0-1 fois / run.
  - `get_*_slots()` lookups : O(1) après construction initiale (arrays cachées). Zero alloc.
  - `_validate_scene_hierarchy()` : ~0.5 ms single-shot à `Loading → Active` transition.
  - Polling `_process` pendant LOADING : ~0.1 ms / frame pendant < 1 s — négligeable.
- **Memory** :
  - Runtime : 7 signals + 6 arrays cachées + 1 `_current_etage_root` ref + state enum = ~1 KB singleton footprint.
  - Scene étage : 30-50 MB VRAM + 15-20 MB RAM Tier 1 (Chrome Zen primitives + atlas partagé 1024×1024).
  - Zero-alloc runtime post-`level_active` : arrays immutables (Array.make_read_only()), signaux value-type payloads. Delta 60 s ≤ 512 KB gate AC-LVL-36.
- **Load Time** :
  - Budget dur 1000 ms Tier 1 (F4). Typique observé : 300-600 ms pour scène MVP 8-10 salles. Marge 400 ms pour variance.
  - Boot Shader Baker précompilation : ~200 ms additionnels au boot global (éviter freeze 50-150 ms première frame post-`level_active`).
- **Network** : N/A (pas de multiplayer MVP).

## Migration Plan

Pas de code existant Level System à migrer — épic starts at Sprint 1 post-ADR Accepted.

Code existant impacté :
- **`src/core/input_manager.gd`** : aucune modif (pas de couplage Input ↔ Level).
- **`src/core/game_state_manager.gd`** (à créer Sprint 1, gouverné par ADR-0007 Proposed 2026-04-23) : intégrera l'appel `LevelSystem.load_etage(id)` / `unload_current()`. Pattern additif confirmé par ADR-0007 registry `scene_transition_api` (préserve autoloads + orchestre `level_active`/`level_unloading`). L'interface est documentée dans le GDD Level §Dependencies + ce présent ADR + ADR-0007.
- **`tests/`** : nouveaux tests unité/intégration Level à écrire Sprint 1 (pas de migration).
- **`project.godot`** : ajout autoload `LevelSystem = "*res://src/gameplay/level/level_system.gd"` (après `InputManager`, `GameStateManager`, `SaveLoadSystem`). Ajout `rendering/shader_compiler/enable_shader_baker = true` si absent.

## Validation Criteria

L'ADR est considéré comme empiriquement valide quand :

- **VC-LVL-1** : scène test `etage_01_minimal.tscn` (4 salles) charge en < 500 ms sur Tier 1 testbed, émet `level_active(1, player_start)` avec signatures exactes, et `get_state() == ACTIVE`. AC-LVL-2 + AC-LVL-3.
- **VC-LVL-2** : scène test `etage_01_invalid.tscn` (PlayerStart absent) émet `level_load_failed(1, reason contains "PlayerStart")`, état reste UNLOADED. AC-LVL-6 + AC-LVL-8.
- **VC-LVL-3** : `level_lint.gd` détecte 11 invariants sur scène test délibérément cassée (une violation par invariant) avec exit code 1 et 11 messages d'erreur distincts. CI job `lint-level-invariants` FAIL propagé.
- **VC-LVL-4** : 500 frames draw calls sur scène Level isolée (sans peer) : p99 ≤ 350. AC-LVL-31.
- **VC-LVL-5** : 60 s exploration post-`level_active` : delta `OS.get_static_memory_usage()` ≤ 512 KB + delta `Performance.OBJECT_COUNT` ≤ +5. AC-LVL-36.
- **VC-LVL-6** : WorldBoundsVolume détecte `body_exited` player position Y=-3, émet `player_out_of_world(last_valid_position)` avec `last_valid_position.y ≠ -3`. AC-LVL-25.
- **VC-LVL-7** : 10 transitions de salle Tier 1 : frame time p99 ≤ 14 ms sur fenêtre ±200 ms autour `room_entered`. AC-LVL-35a.
- **VC-LVL-8** : boot global avec Shader Baker précompilation mesure freeze première frame post-`level_active` < 16.6 ms (pas de spike visible). VR-LVL-1.

Gate final : 8/8 VC-LVL pass OU 7/8 + 1 advisory documenté → promotion `Proposed` → `Accepted` via fresh-session `/architecture-review`.

## Related Decisions

- **ADR-0001** (Physics Rate 60 Hz + Jolt) — Accepted — Level respecte `_physics_process` autorité pour signal dispatch. Jolt broad-phase dicte D-9 BoxShape3D WorldBoundsVolume.
- **ADR-0003** (Rendering Latency) — Accepted — Level respecte budget 8 ms rendering, sous-budget 350 draw calls statiques. Shader Baker 4.5+ prerequisite exécuté D-10.
- **ADR-0005** (Movement Signals Architecture) — Accepted — pattern direct typed signals + CONNECT_DEFERRED par critères + outbound-only + forbidden EventBus = référence pour D-5 / D-12.
- **ADR-0006** (Combat Tick Model) — Accepted — pas de couplage direct, mais Combat Rule 16 (combat onboarding) consommé par D-2 `OnboardingAnchors` + D-6 `get_onboarding_anchors()`.
- **ADR-0007** (Game State Manager) — Proposed 2026-04-23 — `scene_transition_api` registry entry confirme le pattern additif `LevelSystem.load_etage + ResourceLoader.load_threaded_request` (Registry API decision cohérent avec D-1 / D-8 ADR-0011). ADR-0011 et ADR-0007 sont indépendamment figeables.
- **ADR-0008** (Collision Layer Taxonomy — planifié G-5, non écrit) — complètera la taxonomie `LAYER_ENVIRONMENT = 4` / `LAYER_INTERACTIVE = 5` / `LAYER_PLAYER`. ADR-0011 respecte l'usage documenté GDD mais ne fige pas la taxonomie formelle.
- **ADR-0016** (VFX & Feedback Architecture — planifié, G-? post-MVP) — consommera `SecretLureMarker` position pour rendre la lueur cyan #3EE4FF (cross-room visibility).
- **`design/gdd/level-system.md`** r2 (1271 lignes) — Designed r2, pending fresh `/design-review`. Source de vérité pour les 21 TRs G-8 + 55 ACs.
- **`docs/architecture/architecture.md`** §8.3 — ADR-0011 planifié "Level System Grid + Secret Anchors" ; scope élargi par ADR-0011 (inclut scene loading + signals + lint).
- **`docs/architecture/architecture-traceability.md`** §2.6 — 21 TRs G-8 → 21 TRs Covered par ADR-0011 après acceptation.
- **`docs/architecture/tr-registry.yaml`** v2 — TRs TR-lvl-004/006/009/010/012/015/017/018/020/022/025/027/030/032/037/040/041/043 à marquer Covered après ADR-0011 Accepted. TR-lvl-008 reste Gap G-5 (layers). TR-lvl-028/029/033/034 restent Gap G-6 (GSM interface).
- **Forward reciprocity** : ADRs futurs Checkpoint / Enemy / Hazard / Secret / HUD / Tutorial / Audio / VFX référenceront D-5 / D-6 comme contrat d'entrée Level.
