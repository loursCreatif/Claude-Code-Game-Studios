# ADR-0007: Game State Manager & Scene Transition Pattern

## Status
Accepted 2026-04-23 (promoted via `/architecture-review full` r2 — verdict PASS for promotion : 0 cross-ADR conflict, all upstream deps Accepted, Engine LOW risk, 5 TRs Level G-6 closed + TR-inp-006 consumer formalized)

## Date
2026-04-23 (Proposed) → 2026-04-23 (Accepted r2)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (autoload orchestration, SceneTree, Resource loading) |
| **Knowledge Risk** | LOW — Pattern autoload + SceneTree.paused + get_tree().change_scene_to_file() stable depuis Godot 4.0, aucun changement breaking 4.4/4.5/4.6 affectant ce domaine |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, ADR-0001/0003/0004/0005/0006, `design/gdd/input-system.md` D-5, `design/gdd/level-system.md` §Dependencies + T-1..T-4, `docs/architecture/architecture.md` §6.4 + §5.3 + §5.4 |
| **Post-Cutoff APIs Used** | Aucun — SceneTree, Autoload, process_mode, get_tree().paused, change_scene_to_file, ResourceLoader.load_threaded_* sont stables 4.0+. |
| **Verification Required** | (1) Ordre _ready() autoloads respecté (InputManager avant GSM) — assert in _ready(). (2) process_mode discipline vérifiée sous pause (InputManager + GSM + AudioSystem ALWAYS ; Movement/Camera/Combat/Level PAUSABLE héritent de root pause) — integration test GUT. (3) state_changed signal reçu par consumers MVP (Menu, HUD) avant 1er frame PLAYING — test fixture. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Physics Rate + _physics_process authority — GSM state transitions mutent état gameplay via request_pause), ADR-0004 (Input focus signal one-way — GSM consomme application_focus_lost), ADR-0005 (Movement signals — GSM consomme died/respawned pour orchestrer RESPAWNING state) |
| **Enables** | ADR-0009 (Checkpoint & Respawn — GSM orchestre transitions RESPAWNING), ADR-0011 (Level Scene Architecture — GSM appelle Level.load_etage()), ADR-0013 (HUD/Menu Framework — consumers state_changed), ADR-0014 (Save/Load Settings — GSM trigger save on state change) |
| **Blocks** | Epic `menu-system`, Epic `checkpoint-respawn-system`, Epic `level-system` (pending ADR-0011 aussi) |
| **Ordering Note** | Les 3 Accepted upstream (ADR-0001/0004/0005) sont toutes figées 2026-04-21. Aucun blocker amont. Cet ADR peut être promu Accepted dès `/architecture-review` fresh session validation. |

## Context

### Problem Statement

Le jeu a besoin d'un **orchestrateur unique** qui gère les transitions de phases (Menu → Playing → Paused → Respawning → Boss Defeated), coordonne les chargements de scènes (via Level System), et impose une discipline de pause cohérente. Sans cet orchestrateur :

- Chaque système (Input, Level, Checkpoint, Menu) implémenterait sa propre logique de "qui est responsable de pauser quoi" → race conditions et drift.
- Les transitions d'étages (menu → gameplay → menu) n'auraient pas de point unique de coordination → risque de peers qui reçoivent `level_active` avant que GSM ait transitionné à PLAYING.
- `get_tree().paused = true` serait positionné depuis plusieurs emplacements (Menu, focus handler, debug) → état incohérent.
- Le Level System (ADR-0011 à venir) n'aurait pas d'appelant défini pour `load_etage(id)` / `unload_current()` — l'interface reste provisoire.

### Constraints

- **Godot autoload constraints** : le GSM doit être un autoload singleton (pas instanciable ailleurs). Ordre autoload : InputManager → GameStateManager → SaveLoadSystem → AudioSystem (architecture.md §5.4).
- **Pillar 1 FLOW AVANT TOUT** : une transition d'état gameplay (PLAYING → PAUSED) doit être imperceptible en latence (≤ 1 frame, aucun stutter). La cascade de propagation via signal doit rester dans le budget frame 16.6 ms.
- **Pillar 4 PERFORMANCE CONSTANTE** : aucune allocation heap dans hot path (state_changed emit). Payload enum = value type, zero-alloc garanti.
- **Encapsulation** : GSM ne doit **jamais** modifier directement l'état interne des systèmes downstream (pas de mutation Movement.velocity, pas d'appel à Camera.set_fov). Il orchestre via signals + appels aux APIs publiques (ex: `Level.load_etage`, `Input.request_disable`).
- **Découplage upstream** : les Foundation autoloads (InputManager) ne doivent avoir **aucune** référence à GSM. Communication one-way uniquement (signal focus_lost émis par Input, consommé par GSM — déjà établi ADR-0004 D-5).
- **Détermination** : toutes les transitions d'état doivent être tracées depuis `_physics_process` ou un handler de signal émis depuis `_physics_process`, **jamais** depuis `_process` (ADR-0001 D-1 autorité).

### Requirements

- **REQ-1** : Machine à états finie avec 5 états MVP : `MENU`, `PLAYING`, `PAUSED`, `RESPAWNING`, `BOSS_DEFEATED`. Liste figée, toute extension = amendement ADR.
- **REQ-2** : Graphe de transitions légales explicite, transitions illégales rejetées en debug (assert) et silencieuses en release (push_error).
- **REQ-3** : Signal `state_changed(new_state: State)` typé, émis exactement une fois par transition effective.
- **REQ-4** : `request_pause()` / `request_resume()` idempotents — appel multiple ne cause pas de double-transition ni de fuite d'état.
- **REQ-5** : `request_scene_transition(scene_path: String)` pour transitions de scènes menu (main_menu.tscn ↔ hub_scene.tscn). **Ne couvre PAS** les étages gameplay — ceux-ci passent par `LevelSystem.load_etage(id)` appelé par GSM (ADR-0011 à venir).
- **REQ-6** : `get_current_state() -> State` introspection synchrone read-only pour debug / HUD / tests.
- **REQ-7** : Discipline `process_mode` : GSM lui-même + InputManager + AudioSystem en `PROCESS_MODE_ALWAYS` (continuent sous pause). Movement/Camera/Combat/Level en `PROCESS_MODE_PAUSABLE` (défaut, pause héritée via SceneTree.paused=true).
- **REQ-8** : Auto-pause sur focus loss — GSM consomme `InputManager.application_focus_lost` et pause uniquement si `current_state == PLAYING` (pas en MENU ni PAUSED déjà).
- **REQ-9** : Orchestration mort/respawn — GSM consomme `Player.died` (via CheckpointSystem proxy ou directement) → transition RESPAWNING. Consomme `Player.respawned` → retour à PLAYING. Le délai RESPAWN_DELAY reste owned par MovementController (ADR-0005 D-3) ; GSM ne fait que tracker l'état.
- **REQ-10** : GSM est outbound-only vers Foundation (signals consommés one-way) ; il peut appeler directement les APIs publiques des Core/Feature systems qu'il orchestre (Level, Checkpoint). Cela est **asymétrique intentionnel** : GSM = Core Orchestrator, pas Foundation.
- **REQ-11** : Zero-alloc hot path — aucun Dictionary literal, aucun `Array.push_back`, aucun `String.format` dans `_on_*` handlers ou `request_*` methods. Typed signal payload = enum value type.
- **REQ-12** : Thread-safety — toute mutation de `_current_state` depuis main thread uniquement. Assert `OS.get_thread_caller_id() == OS.get_main_thread_id()` en debug build dans `_transition_to(new_state)`.

## Decision

### D-1 — GameStateManager est un Node autoload singleton (pas Resource, pas custom scene)

`GameStateManager` extends `Node` et est déclaré comme autoload dans `project.godot` (`GameStateManager="*res://src/core/game_state_manager.gd"`). Ordre autoload :

1. `InputManager` (Foundation — no deps)
2. **`GameStateManager`** (Core Orchestrator — dépend de InputManager par signal consommé dans `_ready()`)
3. `SaveLoadSystem` (Foundation — no deps)
4. `AudioSystem` (Core — no autoload deps at `_ready`)

**Rejet `Resource`** : un Resource n'a pas de lifecycle `_process` / `_notification` ni de participation native à la SceneTree → pas d'accès à `get_tree().paused` sans wrapper. Un Node autoload est le pattern idiomatique Godot 4.x pour les singletons globaux.

**Rejet `custom scene`** : une scène custom autoloadée ajouterait une profondeur inutile et rendrait l'API publique plus difficile à atteindre (path traversal vs `GameStateManager.request_pause()` direct).

### D-2 — Machine à états finie 5 états, transitions whitelistées

```gdscript
enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }
```

**Graphe de transitions légales** (toute transition non listée = illégale, assert en debug) :

```
MENU ──(start_run / start_etage)──> PLAYING
MENU ──(exit_application)─────────> [process exits]

PLAYING ──(request_pause)─────────> PAUSED
PLAYING ──(player.died)───────────> RESPAWNING
PLAYING ──(etage_completed +
          boss_defeated=true)─────> BOSS_DEFEATED
PLAYING ──(etage_completed +
          boss_defeated=false)────> MENU  (hub / next etage selection)
PLAYING ──(request_scene_transition_to_menu)─> MENU

PAUSED  ──(request_resume)────────> PLAYING
PAUSED  ──(request_scene_transition_to_menu)─> MENU

RESPAWNING ──(player.respawned)───> PLAYING

BOSS_DEFEATED ──(request_new_run)─> MENU
BOSS_DEFEATED ──(request_scene_transition_to_menu)─> MENU
```

**Transitions figées MVP** : extension (ex: state `CUTSCENE`) = amendement ADR-0007.

### D-3 — Signal `state_changed(new_state: State)` typé, émission unique par transition

```gdscript
signal state_changed(new_state: State)
```

- Payload value type (enum = int) → zero-alloc par construction.
- Émis exactement une fois par `_transition_to(new_state)` effectif.
- Si `new_state == _current_state` (transition no-op), **aucun emit** (idempotence).
- Émission synchrone depuis `_transition_to()` — pas de `call_deferred` interne (les consumers qui ont besoin de deferred connectent via `CONNECT_DEFERRED`).
- Tracé depuis `_physics_process` ou handler de signal lui-même émis depuis `_physics_process` (ADR-0001 autorité). **Exception documentée** : transition MENU → PLAYING déclenchée depuis `_ready()` de boot — acceptable car pas de frame gameplay précédent.

### D-4 — Pause discipline : `get_tree().paused` + `process_mode`

**GSM seul a autorité pour muter `get_tree().paused`.** Aucun autre système ne doit écrire `get_tree().paused = true` ni `= false` directement (forbidden pattern).

```gdscript
func _transition_to(new_state: State) -> void:
    # ...
    if new_state == State.PAUSED:
        get_tree().paused = true
    elif _current_state == State.PAUSED and new_state == State.PLAYING:
        get_tree().paused = false
    # ...
```

**Discipline `process_mode`** :

| System | process_mode | Continue sous pause ? |
|--------|--------------|------------------------|
| GameStateManager (autoload) | `PROCESS_MODE_ALWAYS` | ✅ oui (doit recevoir request_resume) |
| InputManager (autoload) | `PROCESS_MODE_ALWAYS` | ✅ oui (doit recevoir ui_cancel pour unpause + focus events) |
| AudioSystem (autoload) | `PROCESS_MODE_ALWAYS` | ✅ oui (menu SFX, music fade) |
| SaveLoadSystem (autoload) | `PROCESS_MODE_ALWAYS` | ✅ oui (save on pause OK) |
| Player (MovementController) | `PROCESS_MODE_PAUSABLE` (défaut hérité) | ❌ non (gameplay gelé) |
| CameraSystem | `PROCESS_MODE_PAUSABLE` | ❌ non (pas de smoothing pendant pause) |
| CombatSystem | `PROCESS_MODE_PAUSABLE` | ❌ non (pas de swing actif pendant pause) |
| LevelSystem (scene) | `PROCESS_MODE_PAUSABLE` | ❌ non |
| Menu UI | `PROCESS_MODE_WHEN_PAUSED` | ✅ oui (réactif seulement en pause) |

**Rationale** : `PROCESS_MODE_ALWAYS` sur les autoloads Foundation/Core garantit que GSM peut orchestrer la sortie de pause. `PROCESS_MODE_PAUSABLE` est le défaut Godot et héritera automatiquement de `SceneTree.paused` pour les scenes gameplay.

### D-5 — `request_scene_transition(scene_path)` pour scenes menu ; `Level.load_etage(id)` pour étages gameplay

**Deux voies distinctes** selon le type de scène :

| Voie | API appelée | Usage |
|------|-------------|-------|
| Scene transition menu | `get_tree().change_scene_to_file(scene_path)` via `request_scene_transition()` | main_menu.tscn, hub_scene.tscn, credits.tscn — scènes "container" qui remplacent entièrement la scène courante |
| Etage gameplay | `LevelSystem.load_etage(etage_id)` (ADR-0011 à venir) | etage_01.tscn, etage_02.tscn — scène étage additive instanciée sous root, pas via change_scene_to_file (préserve autoloads + Player persistant) |

**Contrat GSM → Level** (ADR-0011 formalisera) :

```gdscript
# GSM appelle LevelSystem.load_etage(id) quand state transitionne vers PLAYING
# LevelSystem émet level_active(etage_id, player_start) → GSM consomme pour
# confirmer la transition PLAYING
func start_etage(etage_id: int) -> void:
    assert(_current_state == State.MENU, "start_etage only from MENU")
    LevelSystem.load_etage(etage_id)
    # Transition MENU → PLAYING se fait sur réception du signal LevelSystem.level_active
```

**Forbidden pattern** : `get_tree().change_scene_to_file()` appelé directement depuis Menu / Level / Combat. Toute transition de scène passe par `GameStateManager.request_scene_transition(path)`.

### D-6 — Consommation `InputManager.application_focus_lost` : auto-pause conditionnel

```gdscript
func _ready() -> void:
    InputManager.application_focus_lost.connect(_on_application_focus_lost)
    # Pas de CONNECT_DEFERRED : focus events sont rares (<1/s),
    # synchrone est acceptable et évite latence 1 frame.

func _on_application_focus_lost() -> void:
    if _current_state == State.PLAYING:
        _transition_to(State.PAUSED)
    # Si MENU / PAUSED / RESPAWNING / BOSS_DEFEATED : no-op
```

**Rationale** : focus lost en gameplay actif = user alt-tab pendant run, pause est attendue. Focus lost en menu = aucune action (menu reste réactif, pas besoin de pauser un menu). Focus lost pendant RESPAWNING = on ne pause pas pendant une transition imminente (RESPAWN_DELAY court, **0.05 s** = 3 ticks @ 60 Hz, valeur registry canonique entities.yaml l.220 — la mort puis le return à PLAYING se fait avant que user revienne ; correction réciproque suite à `/design-review` GDD r1 du 2026-04-23 — valeur ADR initiale 0.3s était stale, registry source-of-truth = 0.05s révisée Martin 2026-04-21).

### D-7 — Orchestration mort/respawn : GSM observe via signals, ne pilote pas le timing

GSM consomme `Player.died` et `Player.respawned` (ADR-0005 D-2 signals) pour tracker l'état RESPAWNING, **sans** piloter le délai RESPAWN_DELAY (qui reste owned par MovementController per ADR-0005 D-3).

```gdscript
# Dans _ready() — connexion après que Player est spawned via level_active
func _on_level_active(etage_id: int, player_start: Vector3) -> void:
    var player := get_tree().get_first_node_in_group("player")
    assert(player != null, "player missing after level_active")
    player.died.connect(_on_player_died, CONNECT_DEFERRED)
    player.respawned.connect(_on_player_respawned, CONNECT_DEFERRED)
    _transition_to(State.PLAYING)

func _on_player_died() -> void:
    if _current_state == State.PLAYING:
        _transition_to(State.RESPAWNING)

func _on_player_respawned(spawn_position: Vector3) -> void:
    if _current_state == State.RESPAWNING:
        _transition_to(State.PLAYING)
```

**Connection mode** : `CONNECT_DEFERRED` pour died/respawned. GSM ne fait qu'un state transition (pas de work lourd), mais puisque died est déjà SYNC-consommé par CombatSystem (ADR-0006 D-6), GSM en DEFERRED garantit ordre : Combat résout colliders tick N (SYNC) → GSM transitionne RESPAWNING au tick N+1 (DEFERRED) → CheckpointSystem consomme état RESPAWNING pour déclencher respawn visuals.

**Encapsulation stricte** : GSM ne mute pas `player.velocity`, n'appelle pas `player.die()` ni `player.respawn()`. Le reset de position/respawn_delay est entièrement owned par MovementController + CheckpointSystem. GSM n'est qu'un **tracker d'état** dans cette chaîne.

### D-8 — `BOSS_DEFEATED` terminal state, transition explicite `request_new_run()`

Après défaite du boss final, l'état devient `BOSS_DEFEATED`. Ce state est **terminal** : pas de transition auto vers PLAYING ou RESPAWNING. Sortie uniquement via :

- `request_new_run()` → MENU (user a cliqué "New Run" dans end-screen)
- `request_scene_transition("res://scenes/main_menu.tscn")` → MENU (user a cliqué "Main Menu")

**Rationale** : le user doit confirmer explicitement le new run (pas de loop auto). Préserve progression (crédits gagnés, upgrades achetés) via SaveLoadSystem séparé — GSM ne stocke pas la run state.

### D-9 — Boot sequence `_ready()` : init MENU, pas de load auto

```gdscript
extends Node

enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }

signal state_changed(new_state: State)

var _current_state: State = State.MENU  # initial value at autoload instantiation

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    # Connect to InputManager focus signal (ADR-0004 D-5)
    InputManager.application_focus_lost.connect(_on_application_focus_lost)
    # Post-MVP: SaveLoadSystem.load_settings() triggered here
    # MVP: boot directly to MENU, no scene change needed if project.godot main_scene = main_menu.tscn
    # PAS d'emit state_changed(MENU) au boot — aucun consumer n'est encore
    # dans l'arbre (Menu UI pas encore instancié). Les consumers lisent l'état
    # initial via get_current_state() dans leur propre _ready() (pattern pull).
```

**Boot state** = `MENU` par défaut (valeur initiale de `_current_state`). **Pattern pull au boot** : les consumers (Menu, HUD) lisent `GameStateManager.get_current_state()` dans leur propre `_ready()` pour se synchroniser sur l'état initial. Les émissions `state_changed` ne se produisent que sur transition effective (MENU → PLAYING, etc.). Ceci évite un emit no-op au boot reçu par zéro listeners (les autoloads post-GSM et les nodes de scène n'ont pas encore exécuté leur `_ready()`).

### D-10 — API publique figée (MVP)

```gdscript
# Introspection (read-only, thread-safe)
func get_current_state() -> State

# Transition requests (callable depuis main thread only)
func request_pause() -> void                            # PLAYING → PAUSED
func request_resume() -> void                           # PAUSED → PLAYING
func request_scene_transition(scene_path: String) -> void  # * → MENU (via change_scene_to_file)
func start_etage(etage_id: int) -> void                 # MENU → PLAYING (via Level.load_etage)
func request_new_run() -> void                          # BOSS_DEFEATED → MENU

# Signals (outbound)
signal state_changed(new_state: State)

# API privée (ne pas appeler de l'extérieur)
func _transition_to(new_state: State) -> void           # centralise toutes les transitions
```

**Convention** : tout appelant vérifie `get_current_state()` avant d'appeler `request_*()` s'il y a doute sur l'état. Les `request_*()` méthodes sont **idempotentes** (no-op si transition déjà faite ou illégale).

### Architecture Diagram

```
┌─────────────────────────┐
│     InputManager        │ (Foundation autoload — no deps)
│ ─ application_focus_lost│ ──────────┐
└─────────────────────────┘           │ signal (one-way)
                                      ▼
                 ┌────────────────────────────────────────┐
                 │        GameStateManager (autoload)     │
                 │                                        │
                 │  State: MENU / PLAYING / PAUSED /      │
                 │         RESPAWNING / BOSS_DEFEATED     │
                 │                                        │
                 │  Owns: get_tree().paused authority     │
                 │        state transition graph          │
                 │                                        │
                 │  signal state_changed(new_state)       │
                 └────────────────────────────────────────┘
                        │                          │
            direct call │                  signal  │ state_changed
                        ▼                          ▼
         ┌──────────────────────┐       ┌─────────────────────┐
         │    LevelSystem       │       │  Consumers:         │
         │  load_etage(id)      │       │  - Menu (show/hide) │
         │  unload_current()    │       │  - HUD (overlay)    │
         │  signal level_active │──┐    │  - SaveLoadSystem   │
         └──────────────────────┘  │    │    (trigger save)   │
                                   │    │  - AudioSystem      │
                                   │    │    (music fade)     │
                                   │    └─────────────────────┘
         ┌──────────────────────┐  │
         │ MovementController   │  │
         │  signal died         │──┼──► GSM → State.RESPAWNING
         │  signal respawned    │──┼──► GSM → State.PLAYING
         └──────────────────────┘  │
                                   │
         ┌──────────────────────┐  │
         │  CheckpointSystem    │  │
         │  (ADR-0009 à venir)  │  │
         │   consume level_active◄─┘
         │   trigger respawn    │
         └──────────────────────┘
```

### Key Interfaces

Voir D-10 pour l'API publique complète.

**Contract signals** enregistrés au registry :

| Signal | Producer | Consumer(s) | Pattern | Connection mode |
|--------|----------|-------------|---------|-----------------|
| `state_changed(new_state)` | GSM | Menu, HUD, SaveLoadSystem, AudioSystem, (future) VFX | signal (outbound) | `CONNECT_DEFERRED` recommandé pour consumers lourds (audio fade, HUD rebuild) ; sync OK pour flags bool (Menu.visible). Même critère que ADR-0005 D-5. |

**Contract direct calls** :

| Purpose | Producer | Consumer | API |
|---------|----------|----------|-----|
| Etage loading orchestration | GSM | LevelSystem | `LevelSystem.load_etage(etage_id)`, `LevelSystem.unload_current()` |
| Pause authority | GSM | SceneTree | `get_tree().paused = true/false` (GSM exclusif) |
| Scene transition menu | GSM | SceneTree | `get_tree().change_scene_to_file(path)` (GSM exclusif) |
| Application focus consumption | InputManager (emit) | GSM (consume) | `application_focus_lost` signal (déjà enregistré ADR-0004 D-5) |

## Alternatives Considered

### Alternative 1 : Event-Bus autoload `GameEvents`
- **Description** : Un autoload séparé `GameEvents` qui dispatche toutes les transitions (state_changed, scene_transition_requested, pause_requested). GSM consomme et mute son `_current_state`. Menu/HUD consomment les mêmes events.
- **Pros** : Découplage maximal (GSM, Menu, Level tous indépendants) ; facile de sniffer tous les events pour debug.
- **Cons** : Double-dispatch (Menu → GameEvents → GSM → GameEvents → HUD) ; ordre d'émission non-déterministe entre consumers ; introduit une couche intermédiaire sans utilité MVP ; risque de drift "qui émet quoi" entre systèmes.
- **Rejection Reason** : ADR-0005 a explicitement rejeté l'event bus pour les signals Movement (forbidden pattern `event_bus_autoload_for_movement_intra_gameplay_events`). Même logique s'applique ici : GSM **est** déjà l'autorité centrale, ajouter GameEvents par-dessus = redondance. Le pattern direct typed signals depuis le node qui porte le state est idiomatique Godot.

### Alternative 2 : State Machine Resource externe (`game_state.tres`)
- **Description** : Stocker l'état dans une `Resource` dédiée chargée par GSM. Les transitions sont des méthodes sur la Resource, GSM est un fin wrapper pour exposer l'API.
- **Pros** : Testabilité unitaire pure (Resource instantiable en test sans autoload) ; sérialisation directe si save/load state.
- **Cons** : Une `Resource` n'a pas de lifecycle `_process` / `_notification` ; impossible de consommer `InputManager.application_focus_lost` directement (Resource ne peut pas `connect` à un autoload node sans wrapper). Ajoute une indirection pour chaque appel. SceneTree.paused doit toujours être wrappé par un Node.
- **Rejection Reason** : complexité sans bénéfice MVP. La testabilité d'un autoload Node est acceptable via dependency injection (on peut instantier un GameStateManager non-autoload en test via `var gsm = GameStateManager.new(); gsm._ready()` si on mocke `InputManager`). Resource serait pertinent si on voulait sérialiser l'état, mais la progression run-level vit dans SaveLoadSystem (séparé).

### Alternative 3 : Pas de GSM — chaque système gère son propre state
- **Description** : Pas de singleton. Menu gère son visible/hidden. Level gère son loaded/unloaded. InputManager gère son enabled. Aucun orchestrateur central.
- **Pros** : Simplicité apparente ; aucun couplage via un singleton global.
- **Cons** : Aucun point unique pour `get_tree().paused` → race conditions ; aucune garantie d'ordre (ex: Level.load_etage() peut déclencher spawn Player avant que Menu soit hide() → 1 frame de flicker) ; transition BOSS_DEFEATED → MENU nécessite 3+ systèmes coordonnés sans orchestrateur = fragile.
- **Rejection Reason** : le GDD level-system.md décrit déjà explicitement un "Game State Manager" qui appelle `load_etage()` (§Dependencies ligne 605). Le GDD input-system.md consomme `application_focus_lost` vers un `GameStateManager` (D-5). Les GDDs downstream supposent son existence. Ne pas le créer = rebranding de l'orchestration à chaque nouveau système = dette croissante. Architecture.md §6.4 le pose déjà comme requis.

### Alternative 4 : SceneTree `change_scene_to_file()` pour étages (pas de Level autoload)
- **Description** : Les étages gameplay sont chargés via `get_tree().change_scene_to_file("res://scenes/etage_01.tscn")` au lieu de via un LevelSystem autoload.
- **Pros** : Simplicité maximale (API Godot standard) ; pas de LevelSystem à écrire.
- **Cons** : `change_scene_to_file()` remplace entièrement la scène courante → détruit le Player node, perd son state (credits, upgrades). Il faudrait persister tout dans autoloads (SaveLoadSystem) pour reconstruire post-transition. Bloque les patterns "retour au hub" où le hub est aussi un étage mais conceptuellement persistent. Load time ≤ 1000 ms (Formula 4 Level GDD) inclut un fade-in contrôlé — `change_scene_to_file` est instantané (blocker frame visible).
- **Rejection Reason** : le GDD level-system.md impose un state machine Unloaded/Loading/Active/Unloading avec signals level_active/level_unloading pour peer binding (Checkpoint, Enemy, Secret, HUD, Tutorial). `change_scene_to_file` ne permet pas cette orchestration. `ResourceLoader.load_threaded_request` + `add_child()` est le pattern correct pour étages additifs (ADR-0011 formalisera).

## Consequences

### Positive

- **Pause discipline cohérente** : un seul point de mutation `get_tree().paused`, pas de race condition inter-système.
- **Focus handling propre** : auto-pause en gameplay est gratuit (1 signal handler) ; InputManager reste Foundation zéro-dep-aval.
- **Orchestration explicite** : chaque transition de scène passe par une API documentée, pas de `change_scene_to_file()` sauvage dispersé.
- **Testabilité** : la machine à états est un graphe figé vérifiable par test GUT (transitions légales OK, illégales rejetées).
- **Découplage** : GSM est outbound-only vers Foundation (pas de call InputManager.*) ; il appelle directement Core (LevelSystem) parce qu'il est **au-dessus** de Core conceptuellement.
- **Extensibilité contrôlée** : ajouter un state (ex: `CUTSCENE`) requiert amendement ADR → visibilité sur l'impact des transitions (pas de drift silencieux).

### Negative

- **Autoload supplémentaire** : +1 autoload au boot (négligeable coût, mais ordre à respecter).
- **Couplage GSM → Level** : GSM appelle directement `LevelSystem.load_etage(id)`. Si un jour on veut plusieurs orchestrators (ex: replay system), il faudra refactorer l'appel direct en signal request_etage_load. Accepté au MVP (YAGNI).
- **Exception _ready() emit** : l'émission initiale de `state_changed(MENU)` dans `_ready()` n'est pas depuis `_physics_process` — exception documentée au principe ADR-0001 D-1, acceptable car boot-time one-shot.
- **`get_tree().paused` global** : impacte tous les nodes PAUSABLE. Tout node qui doit continuer sous pause doit être explicitement `PROCESS_MODE_ALWAYS` ou `PROCESS_MODE_WHEN_PAUSED` — une négligence = node gelé en pause. Mitigation : Control Manifest doit lister les process_mode obligatoires par layer.

### Risks

- **R-1 : Drift état via mutation externe `get_tree().paused`** — un développeur tenté d'écrire `get_tree().paused = true` dans Menu pour "test rapide" casse l'authority GSM. *Mitigation* : forbidden pattern `scene_tree_paused_set_outside_gsm` enregistré au registry ; lint grep statique sur `src/**/*.gd` cherchant `get_tree().paused = ` (autorisé uniquement dans `game_state_manager.gd`).
- **R-2 : Transition illegal acceptée silencieusement en release** — un appel `request_pause()` depuis `MENU` est illégal ; en debug ça assert, en release ça push_error. Si un test release ne catch pas ça, bug silencieux. *Mitigation* : couverture test GUT exhaustive de toutes les transitions légales + toutes les transitions illégales (via test fixture qui mock l'état initial et appelle `request_*()`).
- **R-3 : Ordre autoload incorrect** — si `GameStateManager` est déclaré avant `InputManager` dans project.godot, `InputManager.application_focus_lost.connect()` dans GSM._ready() crash parce que InputManager n'est pas encore autoloadé. *Mitigation* : assert `InputManager != null` en début de GSM._ready() + documentation ordre autoload explicite dans architecture.md §5.4 (déjà écrit).
- **R-4 : PROCESS_MODE divergence** — si un dev ajoute un nouvel autoload (ex: Telemetry) sans penser au process_mode, par défaut il est PAUSABLE → il fige sous pause. Si ce système doit continuer sous pause (ex: heartbeat server), bug silencieux. *Mitigation* : ajouter une règle au control manifest que tout autoload doit déclarer explicitement son `process_mode` en `_ready()` (pas juste hériter du défaut).
- **R-5 : Étage gameplay avec Level pas encore chargé quand GSM transitionne PLAYING** — si `start_etage(1)` déclenche immédiatement `_transition_to(PLAYING)` avant que `level_active` soit émis, les consumers de `state_changed(PLAYING)` (HUD, Audio) peuvent s'initialiser pour un état "playing" avant que le Player soit spawned. *Mitigation* : GSM attend le signal `LevelSystem.level_active(etage_id, player_start)` avant d'émettre `state_changed(PLAYING)`. Pattern confirmé D-7 + D-10 (transition déclenchée par handler `_on_level_active`, pas par `start_etage()` direct).
- **R-6 : `change_scene_to_file()` différé 1 frame Godot 4.6** — `get_tree().change_scene_to_file(path)` est processé en **fin de frame** par la SceneTree (pas synchrone). Conséquence : un consumer de `state_changed(MENU)` qui tenterait de lire des nodes de la scène précédente dans le même frame obtient des nodes marqués `queue_free`. *Mitigation* : tout consumer de `state_changed(MENU)` doit attendre 1 frame (`await get_tree().process_frame` ou connexion CONNECT_DEFERRED) avant de lire le nouvel état de scène. À documenter au Control Manifest et dans l'ADR-0013 (Menu UI). Ce gotcha est stable Godot 4.0→4.6, pas un changement post-cutoff.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `level-system.md` | TR-lvl-001 : Scene loading via GSM appelant `load_etage()` / `unload_current()` atomiquement — interface provisoire définie §Dependencies | D-5 + D-10 figent l'API `start_etage(etage_id)` de GSM qui appelle `LevelSystem.load_etage(etage_id)` ; transition PLAYING déclenchée sur `level_active` signal (D-7). |
| `level-system.md` | TR-lvl-028 : Reject concurrent load_etage(id2) when state==Active — GSM doit sérialiser atomiquement | D-5 + D-2 : GSM ne permet `start_etage()` qu'en état MENU. Transition MENU → PLAYING se fait uniquement sur confirmation `level_active`. Pas de concurrent load possible depuis GSM. |
| `level-system.md` | TR-lvl-029 : Reject load_etage() if scene file missing/corrupted — GSM doit router signal `level_load_failed` vers error screen | D-7 + D-10 (implicite) : GSM consomme `LevelSystem.level_load_failed` signal, transitionne vers MENU avec error payload. Implémentation exacte laissée à l'ADR-0011 (contrat signal existant côté Level). |
| `level-system.md` | TR-lvl-033 : Safe idempotence unload_current() when already unloaded — GSM appelle unload_current via request_scene_transition | D-5 : GSM appelle `LevelSystem.unload_current()` uniquement en transition * → MENU. Idempotence garantie côté Level (contrat GDD). |
| `level-system.md` | TR-lvl-034 : Complete reset on reload (quit-to-menu puis reload = fresh state) | D-8 : transition BOSS_DEFEATED → MENU via `request_new_run()` réinitialise GSM state ; chaque nouveau `start_etage()` repart d'un Level `Unloaded` frais. |
| `input-system.md` | TR-inp-006 : Signal `application_focus_lost` pour découplage Input ↔ GameStateManager | D-6 : GSM consomme ce signal en `_ready()` ; auto-pause conditionnel si state==PLAYING. InputManager reste Foundation zéro-dep-aval. |
| `game-concept.md` | TR-gc-001 : Pillar 1 FLOW AVANT TOUT — transitions d'état imperceptibles | D-3 : signal state_changed value-type zero-alloc ; transitions synchrones ≤ 1 frame. D-4 : pause via `get_tree().paused` idiomatique, 0 frame latence. |
| `player-combat-system.md` | (ref §Dependencies L277) : "Quand GameStateManager bascule en Paused, Input.enabled = false → Movement n'émet plus attacked() → Combat reçoit 0 trigger" | D-4 : PROCESS_MODE_PAUSABLE sur Player + Combat fige `_physics_process` sous pause. Aucun appel direct GSM → Combat requis (implicite via SceneTree.paused). |
| `architecture.md` §6.4 | API provisoire GSM déjà définie (enum State 5 valeurs, signal state_changed, request_pause, request_resume, request_scene_transition, get_current_state) | D-2 + D-10 : API publique figée correspond **exactement** à la spec §6.4 (aucune divergence), avec ajout `start_etage(etage_id)` et `request_new_run()` pour couvrir les cas non anticipés. |

## Performance Implications

- **CPU** : négligeable. State transitions sont des O(1) (enum compare + emit signal). `_physics_process` vide (GSM n'a pas de logique par-tick). Hot path : 0 opération. Signal handlers (focus_lost, died, respawned) : ~1-10 µs chacun, rares (<1/s). Budget CPU GSM : **< 0.05 ms/frame** (gratuit).
- **Memory** : statique. `_current_state: int` (4 bytes) + signal subscribers dict (Godot interne, ~1-3 KB total MVP). Zero-alloc hot path garanti (pas de Dictionary literal, pas de push_back). Pas de ring buffer ni cache.
- **Load Time** : l'autoload GSM s'instancie au boot en ~0.1 ms (simple Node + _ready() avec 1 connect). Négligeable.
- **Network** : N/A (solo game MVP).

## Migration Plan

Aucune migration requise — ADR créé avant toute implémentation d'un GameStateManager dans `src/core/`. Le fichier `src/core/game_state_manager.gd` sera créé lors de la story epic-menu-system / epic-level-system.

**Ordre d'implémentation recommandé** :

1. Sprint 1 — Créer `src/core/game_state_manager.gd` squelette (enum + `_current_state` + `_transition_to` privé + `state_changed` signal + `get_current_state()`).
2. Sprint 1 — Déclarer autoload dans `project.godot` après `InputManager`.
3. Sprint 1 — Connecter `InputManager.application_focus_lost` + handler auto-pause (D-6).
4. Sprint 1 — Tests GUT : toutes les transitions légales + toutes illégales (pas de démarrage sans Level attaché).
5. Sprint 2 (après ADR-0011) — Connecter `LevelSystem.level_active/level_load_failed` + implémenter `start_etage()`.
6. Sprint 2 — Connecter `Player.died/respawned` + implémenter `_on_player_died/_on_player_respawned` (D-7).
7. Sprint 3 — Connecter MenuSystem (state_changed consumer), implémenter `request_scene_transition()`.

## Validation Criteria

**VC-1 (Logic BLOCKING)** — Transitions légales : pour chaque transition listée D-2 (13 transitions), un test GUT qui starts from `from_state`, appelle la méthode `request_*()` / injecte le signal approprié, et asserte `get_current_state() == to_state` + 1 emit `state_changed(to_state)`.

**VC-2 (Logic BLOCKING)** — Transitions illégales : pour un sous-ensemble représentatif (ex: 10 cas) de transitions illégales (MENU → PAUSED, PAUSED → RESPAWNING, BOSS_DEFEATED → PLAYING), tester que `request_*()` depuis l'état interdit : (a) en debug build : assert fail ; (b) en release build mock (`OS.has_feature("debug") = false`) : no-op, pas d'emit `state_changed`, state inchangé.

**VC-3 (Integration BLOCKING)** — Pause flow e2e : GIVEN Player spawned dans etage_01 Active, state=PLAYING, WHEN `GameStateManager.request_pause()`, THEN (a) `get_tree().paused == true`, (b) `state_changed(PAUSED)` reçu par mock consumer, (c) MovementController `_physics_process` pas appelé sur 5 ticks suivants, (d) InputManager `_physics_process` toujours appelé (PROCESS_MODE_ALWAYS).

**VC-4 (Integration BLOCKING)** — Focus loss auto-pause : GIVEN state=PLAYING, WHEN `InputManager.application_focus_lost` émis, THEN state=PAUSED (transition effective) ET `get_tree().paused == true`. GIVEN state=MENU, WHEN même signal, THEN state=MENU (pas de transition). GIVEN state=PAUSED, WHEN même signal, THEN state=PAUSED (idempotent).

**VC-5 (Logic BLOCKING)** — Zero-alloc hot path : test GUT qui mesure `MEMORY_STATIC` delta sur 1000 emit `state_changed(PLAYING)` consécutifs → delta ≤ 16 KB (budget large, signal dispatch Godot peut avoir allocs internes mais pas GSM lui-même).

**VC-6 (Code Review BLOCKING)** — Lint grep `get_tree\(\)\.paused\s*=[^=]` sur `src/**/*.gd` (regex précise : exclut `==` lectures + à exécuter avec `grep -v '^[^:]*:[0-9]*:\s*#'` pour exclure commentaires) → exactement **3 matches** attendus (dans `game_state_manager.gd`) : (1) `request_pause` → `= true`, (2) `request_resume` → `= false`, (3) `request_scene_transition` → `= false` (libère pause flag avant Pause→MainMenu, anti-flicker). Tout autre fichier matchant = violation à fixer. Tout 4e write dans GSM = signal d'authority drift à escalader.

**Amendement 2026-05-02** : count passé de 2 à 3 pour refléter le 3e write `request_scene_transition` introduit pendant l'implémentation (nécessité fonctionnelle non anticipée par la rédaction initiale). Regex affinée `=[^=]` pour exclure les lectures (asserts read-only `==` autorisés hors GSM, ex : main_menu sanity check). Autorité unique D-4 respectée — toutes les mutations restent dans GSM.

**VC-7 (Integration advisory)** — Thread safety : appel `GameStateManager.request_pause()` depuis un `Thread.start(func(): GameStateManager.request_pause())` → assert fail en debug (main thread check). En release : comportement non-testé, documenté comme "ne pas faire" (forbidden pattern).

**VC-8 (Integration advisory)** — Etage lifecycle orchestration : GIVEN state=MENU, WHEN `start_etage(1)`, THEN (a) `LevelSystem.load_etage(1)` appelé, (b) state reste MENU jusqu'à émission `level_active(1, player_start)`, (c) à la réception, state → PLAYING et emit `state_changed(PLAYING)`. (Test reportable à Sprint 2 après ADR-0011 + impl Level.)

## Related Decisions

- **ADR-0001** Physics Rate 60 Hz — autorité _physics_process pour mutations d'état gameplay (inclut transitions GSM quand déclenchées par signals gameplay).
- **ADR-0003** Rendering & Display Latency — frame budget 16.6 ms ; GSM ≤ 0.05 ms/frame gratuit dans le budget.
- **ADR-0004** Input API & Focus Handling — D-5 signal `application_focus_lost` one-way consommé par GSM (D-6 de cet ADR).
- **ADR-0005** Movement Signals Architecture — signals `died` / `respawned` consommés par GSM (D-7 de cet ADR) ; pattern CONNECT_DEFERRED suivi.
- **ADR-0006** Combat Tick Model — D-6 CombatSystem consomme `died` SYNC ; GSM consomme DEFERRED → ordre tick-préservé.
- **ADR-0009 Checkpoint & Respawn** (à venir) — consumera GSM state pour orchestrer respawn visuals ; GSM ne pilote pas le timing RESPAWN_DELAY.
- **ADR-0011 Level Scene Architecture** (à venir) — formalisera `LevelSystem.load_etage()` / signals `level_active` que GSM appelle/consomme (D-5 de cet ADR).
- **ADR-0013 HUD + Menu UI Framework** (à venir) — MenuSystem consumera `state_changed` pour afficher/masquer.
- `design/gdd/level-system.md` §Dependencies + T-1..T-4 — source de l'API `load_etage/unload_current` + contrat signals.
- `design/gdd/input-system.md` D-5 + §Edge Cases focus handling — source du contrat signal application_focus_lost.
- `docs/architecture/architecture.md` §5.3 + §5.4 + §6.4 — prescription architecturale déjà existante figée par cet ADR.
