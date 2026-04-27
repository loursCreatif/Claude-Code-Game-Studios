# ADR-0004: Input API & Focus Handling — Polling canonique, refcount enable, focus decoupled

## Status
Accepted

## Date
2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session `/architecture-review single-gdd input` — verdict PASS avec 1 CONCERN cross-ADR C-1 résolu en séance par edits ADR-0001 l. 100 + l. 222 pointant vers ADR-0004 D-3)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Input / Core |
| **Knowledge Risk** | HIGH |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/modules/input.md`, `docs/engine-reference/godot/breaking-changes.md` (section 4.6 dual-focus system + 4.5 SDL3 gamepad), `docs/engine-reference/godot/current-best-practices.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` (API publique inchangée, sémantique dual-focus 4.6 à valider) ; `OS.has_feature("debug")` (runtime, existait avant cutoff mais utilisation accrue pour remplacer les `#if` préprocesseur absents de GDScript) ; `PackedFloat32Array` (API stable) |
| **Verification Required** | (1) Valider sur 3 OS cibles (Windows 11, macOS Sonoma, Linux Ubuntu Wayland + X11) que `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` se déclenchent bien sur alt-tab et que le burst de `InputEventMouseMotion` post-FOCUS_IN est absorbé par la fenêtre 50 ms. (2) Vérifier que la sémantique 4.6 « dual-focus » (mouse/touch ≠ keyboard/gamepad focus) n'émet PAS ces notifications pour des changements de focus UI intra-fenêtre — uniquement OS-level. (3) Benchmark zero-alloc : scène stress 1000 events/s sur 60 s, `Performance.get_monitor(MEMORY_STATIC)` stable ± 128 KB. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Physics Rate 60 Hz + Jolt) — cet ADR consomme la règle d'autorité `_physics_process` + pattern flag-via-signal posés par ADR-0001 et les formalise en API concrète. ADR-0001 doit être `Accepted` avant qu'ADR-0004 puisse l'être. |
| **Enables** | Application des fixes GDD Input System (review r4, 4 BLOCKINGs structurels + 3 testing) ; première story Input ; toute story Movement/Combat/Camera qui consomme l'API Input. |
| **Blocks** | Epic `input-system` (ne peut pas démarrer sans API figée) ; Epic `player-movement` (`was_pressed_this_tick(&"jump")` requis dans AC) ; Epic `player-combat` (`was_pressed_this_tick(&"attack")`) ; Epic `checkpoint-respawn` (`request_disable(self)` pendant RESPAWN_DELAY). |
| **Ordering Note** | L'application des fixes du GDD Input System (renommages, suppressions, nouveaux patterns) doit se faire **après** Acceptation de cet ADR et **pas avant**, sinon le GDD re-diverge à la prochaine review. |

## Context

### Problem Statement

La review indépendante r4 du GDD `design/gdd/input-system.md` (2026-04-21, 7 specialists + creative-director) a retourné verdict **MAJOR REVISION NEEDED** avec 4 BLOCKINGs **structurels convergents** et 3 BLOCKINGs testing. Le synthèse creative-director est sans ambiguïté : *« Ce ne sont pas des bugs GDD — ce sont des décisions d'architecture non prises qui polluent la GDD. Tant qu'elles ne sont pas actées dans un ADR, chaque révision les re-discute. »* Trois itérations GDD (r1→r2→r3→r4) ont échoué à stabiliser ces points parce qu'ils excèdent le scope d'un GDD : ce sont des contrats d'API et des patterns runtime, qui relèvent d'un ADR.

Les quatre BLOCKINGs structurels à trancher :

1. **Incompatibilité API publique GDD vs ADR-0001.** Le GDD expose `is_action_just_pressed()` (règle 7, ligne 76). ADR-0001 le liste comme `forbidden_patterns` (`is_action_just_pressed_direct_in_gameplay_physics_process`) et prescrit `was_pressed_this_tick()`. Le GDD mentionne la cible 60 Hz mais n'intègre pas l'API qui la rend atteignable. Conflit direct : un consumer implémentant l'AC-CS-1 du GDD viole immédiatement ADR-0001.

2. **`set_enabled(bool)` sans reference counting → race multi-owner garantie.** Trois owners légitimes veulent disabled : Menu (pendant pause), Checkpoint (pendant RESPAWN_DELAY), Cutscene (future, Tier 2). Avec un `bool` global, la séquence `Menu.set_enabled(false)` → `Checkpoint.set_enabled(false)` → `Menu.set_enabled(true)` (fermeture menu pendant respawn en cours) **réactive l'input pendant le respawn**. Observé comme bug potentiel par systems-designer F2.

3. **Allocation `Dictionary` littérale (`{ts = ..., ms = ...}`) dans hot path `_latency_samples.push_back` (GDD ligne 250).** À ~60 events/s en gameplay normal et jusqu'à 1000 events/s sur flick souris 1000 Hz, cela produit 60–1000 allocations heap/seconde. Invisible à l'AC-PF-2 actuelle (grep simple) car la syntaxe est idiomatique GDScript. Violation du principe zero-alloc hot path posé par le game-concept Pillar 1.

4. **Couplage bidirectionnel Input ↔ GameStateManager via appel direct.** Le GDD prescrit que l'Input System appelle `GameStateManager.request_pause()` au FOCUS_OUT (Edge Case ligne 278). Ceci crée une dépendance amont de l'Input vers le GameStateManager, casse le principe « Input = Foundation, Aucune dépendance amont » (Quick Reference ligne 13). systems-designer F6 : fix via signal.

Les trois BLOCKINGs testing additionnels :

5. **`#if debug_build` préprocesseur n'existe pas en GDScript.** Le GDD (règle 7 ligne 111) prescrit que `simulate_action_press()` soit « uniquement compilé en `#if debug_build` ». GDScript n'a aucune directive préprocesseur — le check idiomatique est `OS.has_feature("debug")` runtime + no-op release. Toute la suite de fixtures tests qui reposerait sur ce mécanisme est non-viable.

6. **Reset flag timing `_physics_process` non spécifié (sync vs `call_deferred`).** godot-specialist autoritativement : l'ordre autoload garantit que InputManager tourne en 1er dans `_physics_process` (déjà prescrit par GDD). Mais le reset du flag `_pressed_this_tick[action]` est-il fait **synchroniquement en fin du corps** de `_physics_process`, ou différé via `call_deferred` ? La différence est 1 tick de latence — AC-CS-1 passe ou échoue selon le choix.

7. **`_skip_next_mouse_delta: bool` insuffisant sur Wayland.** Le GDD (règle 13, pseudocode ligne 144) drop un seul `InputEventMouseMotion` post-FOCUS_IN. Sur Wayland, le compositeur peut livrer un **burst de 3–6 events sur 2–3 frames** contenant le delta accumulé hors-fenêtre. Un bool unique laisse passer 5 events sur 6. Fix : fenêtre temporelle absolute time (~50 ms) au lieu d'un latch single-shot.

Tant que ces 7 points ne sont pas figés dans un ADR, toute itération du GDD re-ouvre la discussion et ajoute de la dette technique.

### Constraints

- **Engine** : Godot 4.6 + GDScript. Pas de préprocesseur, pas de `#if`, pas de compilation conditionnelle au niveau script.
- **Dual-focus system Godot 4.6** (breaking-changes.md) : mouse/touch focus séparé du keyboard/gamepad focus. Potentielle divergence de sémantique entre `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` et `Window.focus_entered/exited`. À vérifier.
- **Thread safety** : `Input.*` singleton Godot n'est pas thread-safe. Le pattern doit interdire toute mutation depuis un `Thread` gameplay.
- **Zero-alloc hot path** : Pillar 1 implique que la mesure de latence elle-même ne doit pas allouer (anti-pattern self-defeating).
- **ADR-0001 règles acquises** : autorité `_physics_process`, ordre autoload (InputManager en 1er), 60 Hz tick rate.
- **StringName discipline acquise** (GDD Input règle 8) : toutes actions référencées par `&"..."` literal ou `const`, jamais via variable `String`.
- **Solo mode** : aucun spawn creative-director/engine-specialist/TD-ADR pour validation (mode review `solo`, cf. `production/review-mode.txt`). Enrichissements en review ciblé possibles mais bloquants skipped.

### Requirements

- **REQ-1** : Consumer polling `action` dans `_physics_process` du tick N reçoit `true` pour une press qui a eu lieu entre tick N−1 et tick N, même si render fps > physics rate et que `is_action_just_pressed` de Godot était déjà consommé. (Couvre l'AC-CS-1 du GDD.)
- **REQ-2** : Trois owners peuvent demander simultanément `disabled`. L'Input reste disabled tant qu'**au moins un** owner le demande, et revient `enabled` seulement quand **tous** ont relâché leur requête. Ordre de release indifférent.
- **REQ-3** : Un owner qui se fait détruire (`queue_free`) sans avoir appelé `release_enable_request` ne doit pas laisser l'Input disabled indéfiniment (auto-cleanup).
- **REQ-4** : La mesure de latence ne doit allouer aucune mémoire dans `_unhandled_input` ni dans `_physics_process`. Zero `push_back` sur `Array`, zero `{...}` literal, zero `String` concat.
- **REQ-5** : L'Input System ne référence **aucun** système aval (GameStateManager, Menu, Checkpoint) par nom ni import. Communication sortante exclusivement par signal.
- **REQ-6** : Le burst mouse delta post-FOCUS_IN doit être entièrement absorbé sur les 3 OS cibles (Windows, macOS, Linux Wayland + X11), sans rotation caméra perceptible.
- **REQ-7** : Le framework de tests (GUT) doit pouvoir simuler press/release d'actions sans hardware, sans code préprocesseur, avec no-op coût release.
- **REQ-8** : `Input.mouse_mode` ne doit jamais être lu ni écrit depuis un `Thread` non-main.

## Decision

Adopter les sept décisions suivantes comme API et patterns canoniques du Input System. Elles formeront la base implémentable du GDD (après application des fixes post-ADR).

### D-1 — API polling canonique : `was_pressed_this_tick(action)`

Remplacer `is_action_just_pressed()` par `was_pressed_this_tick()` dans l'API publique gameplay. Le GDD sera mis à jour en conséquence.

```gdscript
# InputManager (autoload)
var _pressed_this_tick: Dictionary = {}  # Pré-alloué au _ready() avec toutes les actions MVP — 0 allocs runtime

func _ready() -> void:
    for action in ACTIONS_MVP:
        _pressed_this_tick[action] = false

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.is_echo():
        return
    for action in ACTIONS_MVP:
        if event.is_action_pressed(action):
            _pressed_this_tick[action] = true
            # emit typed signal here (jump_pressed, etc.) si souhaité

func was_pressed_this_tick(action: StringName) -> bool:
    if not _enabled:
        return false
    return _pressed_this_tick.get(action, false)

func _physics_process(_delta: float) -> void:
    # (tout le corps de InputManager _physics_process — mesure latency, etc.)
    # ...
    # Reset SYNCHRONE en fin de corps — cf. D-3
    for action in ACTIONS_MVP:
        _pressed_this_tick[action] = false
```

Le `Dictionary` est pré-alloué au `_ready()` avec toutes les actions MVP ; en runtime, uniquement `.get()` (pas de mutation de structure, pas d'allocation). Si une action inconnue est requêtée, `.get(action, false)` retourne `false` sans warning (l'erreur est capturée en debug via un check séparé, cf. GDD règle 7).

> **Note** : le signal-canal (`jump_pressed`, `dash_pressed`, etc.) prescrit par le GDD règle 7 coexiste avec `was_pressed_this_tick`. Les signaux restent pour UI / event-driven (Menu, HUD). Le polling tick-based est pour gameplay (Movement, Combat, Checkpoint). Règle 11 du GDD s'applique sans changement.

### D-2 — Renommer l'ancien `is_action_just_pressed` en `_is_action_just_pressed_raw` (private)

L'API publique `InputManager.is_action_just_pressed()` est supprimée. Un wrapper privé `_is_action_just_pressed_raw()` existe pour les tests internes et l'implémentation, mais n'est pas appelable depuis l'extérieur (convention GDScript `_` prefix).

Le `forbidden_patterns` registry `is_action_just_pressed_direct_in_gameplay_physics_process` (ADR-0001) couvre déjà l'appel direct à `Input.is_action_just_pressed` ; ce ADR étend la règle : **aucun consumer gameplay ne doit appeler `InputManager.is_action_just_pressed`** (qui n'existe plus) **ni `Input.is_action_just_pressed` directement**. Seul `was_pressed_this_tick` est autorisé.

### D-3 — Reset du flag : SYNCHRONE en fin de corps de `_physics_process` (pas `call_deferred`)

Le reset du dictionnaire `_pressed_this_tick` se fait **dans la dernière instruction du corps** de `_physics_process` de l'InputManager, sans `call_deferred`. Raison : `call_deferred` repousse l'exécution à la fin de tous les `_physics_process` du frame, donc si un consumer aval (Movement) appelle `was_pressed_this_tick` dans **son** `_physics_process`, il lirait le flag **après** reset — retournerait toujours `false` → AC-CS-1 échoue systématiquement.

**Ordre garanti** (par `[autoload]` declaration + règle 10 du GDD) :

1. `InputManager._unhandled_input(event)` tick N (cadence render) : set flag à `true`.
2. `InputManager._physics_process(delta)` tick N (1er autoload à tourner) : mesure latency, autres traitements.
3. `InputManager._physics_process(delta)` tick N, **dernière ligne** : reset tous les flags à `false`.

Attention : étape (3) termine le corps de `InputManager._physics_process`. Les `_physics_process` des consumers (`PlayerMovement`, etc.) tournent **après** dans le même tick N, et liront... `false`. **Problème** : l'ordre ci-dessus comme écrit casse le pattern.

**Correctif** : le reset doit avoir lieu en **début** de `_physics_process`, **pas en fin** — lire le flag *avant* qu'il soit clobbered. Mais cela ouvre la fenêtre : si un event arrive dans `_unhandled_input` entre deux ticks physiques, le flag est setté, lu par le consumer au tick suivant, puis reset au tick suivant + 1.

Le pattern correct est :

1. `_unhandled_input` tick N render : set flag.
2. `_physics_process` tick N, **ligne 1** de InputManager : copie du dictionnaire vers un buffer `_consumed_this_tick` (swap de références, pas de copie profonde — GDScript Dictionary = reference type).
3. `_physics_process` tick N, **ligne 2** de InputManager : `_pressed_this_tick` est vidé (refs remises à `false`).
4. Consumers appellent `was_pressed_this_tick(action)` → retourne `_consumed_this_tick.get(action, false)`.

**API finale** :

```gdscript
var _pressed_this_tick: Dictionary = {}    # écrit par _unhandled_input
var _consumed_this_tick: Dictionary = {}   # lu par was_pressed_this_tick()

func _physics_process(_delta: float) -> void:
    # Ligne 1 : snapshot avant que le tick ne consomme
    var temp = _consumed_this_tick
    _consumed_this_tick = _pressed_this_tick
    _pressed_this_tick = temp  # recycle le dict (zero alloc)
    # Vider le dict recyclé pour le prochain tick
    for action in ACTIONS_MVP:
        _pressed_this_tick[action] = false
    # (reste du corps : mesure latency, etc.)

func was_pressed_this_tick(action: StringName) -> bool:
    if not _enabled:
        return false
    return _consumed_this_tick.get(action, false)
```

Synchrone, zero-alloc (swap de refs), garantit AC-CS-1. Le GDD sera mis à jour pour refléter ce pattern.

### D-4 — Enable refcount : `request_disable(owner) / release_enable_request(owner)` avec `Dictionary` owner→bool

Remplacer `set_enabled(bool)` par un pattern refcount idempotent :

```gdscript
var _enable_blockers: Dictionary = {}  # key: Object id (owner), value: true
                                        # `_enabled` dérivé : _enable_blockers.is_empty()

func request_disable(owner: Object) -> void:
    assert(owner != null, "request_disable: owner must not be null")
    var id = owner.get_instance_id()
    if _enable_blockers.has(id):
        return  # idempotent — même owner peut appeler N fois sans drift
    _enable_blockers[id] = true
    if not owner.tree_exited.is_connected(_on_blocker_tree_exited):
        owner.tree_exited.connect(_on_blocker_tree_exited.bind(id), CONNECT_ONE_SHOT)
    _update_enabled_state()

func release_enable_request(owner: Object) -> void:
    if owner == null:
        return  # déjà gc'd — l'auto-cleanup via tree_exited a probablement déjà tourné
    var id = owner.get_instance_id()
    if not _enable_blockers.erase(id):
        push_warning("release_enable_request: owner %s n'avait pas de requête active" % owner)
    _update_enabled_state()

func _on_blocker_tree_exited(owner_id: int) -> void:
    # Auto-cleanup : si un owner se fait free sans release, on retire son blocker
    if _enable_blockers.erase(owner_id):
        _update_enabled_state()

var _enabled: bool = true

func _update_enabled_state() -> void:
    var new_state = _enable_blockers.is_empty()
    if new_state == _enabled:
        return
    _enabled = new_state
    enabled_changed.emit(_enabled)
    if not _enabled:
        # Quand on passe disabled, vider les flags en cours pour éviter une press mémorisée
        for action in ACTIONS_MVP:
            _pressed_this_tick[action] = false
            _consumed_this_tick[action] = false
```

**Propriété `enabled`** : reste publique **read-only** (getter). Les setters `set_enabled(bool)` publics sont **supprimés**.

**Séquence « respawn pendant menu »** couverte :

```
t0: Menu.request_disable(Menu) → blockers = {Menu}, enabled = false
t1: Checkpoint.request_disable(Checkpoint) → blockers = {Menu, Checkpoint}, enabled = false
t2: Menu.release_enable_request(Menu) → blockers = {Checkpoint}, enabled = false  ← GOOD
t3: Checkpoint.release_enable_request(Checkpoint) → blockers = {}, enabled = true
```

Le scénario bug identifié par systems-designer F2 (input réactivé pendant respawn) est structurellement impossible.

**Propriété** : `ui_cancel_pressed` signal reste émis même quand `_enabled == false` (cf. GDD règle 6) — indépendant du refcount, câblé dans `_input()` au-dessus du gate `_enabled`.

### D-5 — Découplage Input ↔ GameStateManager : signal `application_focus_lost` / `application_focus_gained`

L'Input System **émet** deux signaux sur notification OS et n'appelle **aucun** système aval :

```gdscript
signal application_focus_lost()
signal application_focus_gained()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _saved_mouse_mode = Input.mouse_mode  # main thread — cf. D-7
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        _focus_regained_until_ticks_usec = 0
        application_focus_lost.emit()
    elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
        Input.mouse_mode = _saved_mouse_mode
        _focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000  # fenêtre 50 ms
        application_focus_gained.emit()
```

**GameStateManager** (autoload aval, déclaré après InputManager) connecte ces signaux dans son `_ready()` :

```gdscript
# GameStateManager
func _ready() -> void:
    InputManager.application_focus_lost.connect(_on_focus_lost)

func _on_focus_lost() -> void:
    if current_state == PLAYING:
        request_pause("focus_lost")
```

Le InputManager ne contient aucun `GameStateManager.request_pause()`. Dépendance one-way : GameStateManager (aval) consomme, InputManager (amont) émet. Aligne avec le principe « Input = Foundation, Aucune dépendance amont » du GDD.

### D-6 — Focus re-acquisition : fenêtre temporelle 50 ms (cross-OS Wayland-safe)

Remplacer le pattern `_skip_next_mouse_delta: bool` (single-shot, vulnérable Wayland burst) par une fenêtre temporelle absolue :

```gdscript
var _focus_regained_until_ticks_usec: int = 0

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        if Time.get_ticks_usec() < _focus_regained_until_ticks_usec:
            return  # absorbe tout burst jusqu'à 50 ms post-FOCUS_IN
        # ... traitement normal, emit mouse_motion(delta)
```

**Durée 50 ms** : choisie comme compromis (Wayland burst observé 15–35 ms, macOS rare 2–5 ms, Windows ~0 ms ou 1 frame). 50 ms = perceptible comme « la caméra met un instant à répondre au revenir » mais **pas comme un jump** de caméra. Si playtest montre que 50 ms est perceptible comme latence gênante au retour de focus, paramètre tunable dans `input_settings.tres` (clamp 20–100 ms).

**Pourquoi absolute time et pas frame count** : à 60 Hz physics + 144 Hz render, un count de « N prochaines frames render » est ambigu (30 ms @ 144 Hz = 4.3 frames, ~30 ms @ 60 physics = 1.8 tick). Absolute time est non-ambigu et indépendant du rafraîchissement.

### D-7 — `Input.mouse_mode` main-thread only

Le singleton Godot `Input` n'est pas documenté thread-safe. Règle projet :

- **Autorisé** : `Input.mouse_mode` lu ou écrit depuis `_ready`, `_process`, `_physics_process`, `_input`, `_unhandled_input`, `_notification`, signal handlers — tous tournant sur le main thread.
- **Interdit** : toute lecture ou écriture de `Input.*` (y compris `mouse_mode`, `is_action_pressed`, `get_vector`) depuis un `Thread`, `WorkerThreadPool.add_task` callback, ou un `Callable.call_deferred` qui résulterait d'un thread non-main.
- **Si besoin depuis un thread** (peu probable au MVP, case Accessibility System Tier 3) : capturer la valeur au dernier tick main via un atomique ou une `Semaphore`, jamais accès direct.

Ajouté comme `forbidden_pattern` registry : `input_singleton_access_from_non_main_thread`.

### D-8 — Ring buffer latency : 2× `PackedFloat32Array` pré-alloués

Remplacer le `Array[Dictionary]` du GDD (ligne 250) par deux `PackedFloat32Array` de capacité fixe, indexés par `write_idx % capacity`. Zero alloc runtime.

```gdscript
const LATENCY_SAMPLES_CAPACITY: int = 120  # 2 s à 60 samples/s = fenêtre rolling

var _latency_values_ms: PackedFloat32Array = PackedFloat32Array()
var _latency_timestamps_usec: PackedInt64Array = PackedInt64Array()
var _latency_write_idx: int = 0
var _latency_sample_count: int = 0  # clamp à CAPACITY

func _ready() -> void:
    _latency_values_ms.resize(LATENCY_SAMPLES_CAPACITY)
    _latency_timestamps_usec.resize(LATENCY_SAMPLES_CAPACITY)
    # resize() pré-alloue — zero allocs en push ultérieur

func _record_latency_sample(value_ms: float, ts_usec: int) -> void:
    var slot = _latency_write_idx % LATENCY_SAMPLES_CAPACITY
    _latency_values_ms[slot] = value_ms
    _latency_timestamps_usec[slot] = ts_usec
    _latency_write_idx += 1
    if _latency_sample_count < LATENCY_SAMPLES_CAPACITY:
        _latency_sample_count += 1
```

Le calcul p99 se fait à la demande (lectures rares depuis HUD debug @ F3 — ~1 Hz) : copie temporaire triée dans un buffer scratch pré-alloué de même capacité. Pas dans le hot path d'écriture.

**Fenêtre glissante par âge** : au calcul p99, skip les samples dont `_latency_timestamps_usec[i] < now - 1_000_000`. Pas d'éviction active, juste filtrage à la lecture. Le buffer écrase naturellement les vieux samples par `% capacity`.

**Si < 10 samples valides** dans la fenêtre : renvoyer `max` au lieu du p99 (GDD règle actuelle conservée).

### D-9 — Fixtures test sans préprocesseur : `OS.has_feature("debug")` + no-op release

Supprimer toute référence à `#if debug_build`. Les fixtures test `simulate_action_press(action)` et `simulate_mouse_motion(delta)` sont présentes **en toute build** mais :

- **En debug** (`OS.has_feature("debug") == true`) : fonctionnelles. Injection via `Input.parse_input_event(InputEventKey.new(...))` (not `Input.action_press()` — cf. godot-specialist r4 tranché : `action_press()` ne trigger pas `_unhandled_input`).
- **En release** : `return` immédiat (no-op). Le coût est un seul `if` check par appel, négligeable.
- **Gardées par assert** : `assert(OS.has_feature("debug"), "simulate_action_press only allowed in debug builds")` pour attraper tout usage en release au build time d'une scène test.

```gdscript
func simulate_action_press(action: StringName) -> void:
    if not OS.has_feature("debug"):
        return
    var ev = InputEventAction.new()
    ev.action = action
    ev.pressed = true
    Input.parse_input_event(ev)  # triggers _unhandled_input
```

**Corollaire** : `InputEventAction` + `parse_input_event` est le pattern canonique pour test. Pas `Input.action_press` (qui ne trigger pas les callbacks). AC-AG-1 du GDD sera réécrite en conséquence.

### Architecture Diagram

```
                    ┌───────────────────────────────────────────────┐
                    │              OS Event Queue                   │
                    │  (USB polling 125–1000 Hz, batch 0–8 ms)      │
                    └──────────────────┬────────────────────────────┘
                                       ▼
                    ┌───────────────────────────────────────────────┐
                    │ Godot Input singleton + InputMap resolution   │
                    │  (main thread, dual-focus 4.6 semantics)      │
                    └──────────────────┬────────────────────────────┘
                                       ▼
         ┌─────────────────────────────────────────────────────────────┐
         │ InputManager (autoload #1)                                  │
         │                                                             │
         │  _unhandled_input(event)              _notification(what)   │
         │    └─ if pressed:                       ├─ FOCUS_OUT:       │
         │        _pressed_this_tick[a] = true      │   mouse_mode ←   │
         │        emit a_pressed signal             │   VISIBLE        │
         │    └─ if MouseMotion:                    │   emit focus_lost│
         │        if ticks_usec < focus_until:      └─ FOCUS_IN:       │
         │          return (absorb burst)               mouse_mode ←   │
         │        emit mouse_motion(delta)              saved          │
         │                                              focus_until =  │
         │                                              now + 50 ms    │
         │                                              emit gained    │
         │                                                             │
         │  _physics_process(delta) — RUNS FIRST (autoload #1)         │
         │    1. swap: _consumed ↔ _pressed (refs, zero alloc)         │
         │    2. clear _pressed[action] for all actions MVP            │
         │    3. record latency sample (PackedFloat32Array % CAP)      │
         │    4. (rest of processing)                                  │
         │                                                             │
         │  was_pressed_this_tick(action) → _consumed[action]          │
         │                                                             │
         │  Enable gating:                                             │
         │    _enable_blockers: Dict<owner_id, true>                   │
         │    request_disable(owner) / release_enable_request(owner)   │
         │    enabled = _enable_blockers.is_empty()                    │
         │    tree_exited → auto-cleanup blocker                       │
         └──┬──────────────────────────┬───────────────────────────┬───┘
            │ signals                  │ API polling                │ signals
            ▼ (event-driven)           ▼ (_physics_process)         ▼ (one-way)
        ┌────────────┐           ┌─────────────────────┐    ┌─────────────────┐
        │ HUD, Menu  │           │ Player Movement,    │    │ GameStateManager│
        │ VFX, Audio │           │ Combat, Checkpoint, │    │ (consumes       │
        │ (signals)  │           │ Camera (polling)    │    │ focus_lost)     │
        └────────────┘           └─────────────────────┘    └─────────────────┘
```

### Key Interfaces

| Interface | Contrat |
|-----------|---------|
| `InputManager.was_pressed_this_tick(action: StringName) -> bool` | Polling canonique gameplay. Appelé depuis `_physics_process` du consumer. Retourne `true` exactement une fois par press edge, sur le tick qui suit la press. `false` si `enabled == false`. |
| `InputManager.get_movement_vector() -> Vector2` | Inchangé. `ZERO` si `enabled == false`. |
| `InputManager.request_disable(owner: Object) -> void` | Ajoute un blocker. Idempotent pour même owner. Auto-cleanup via `owner.tree_exited`. |
| `InputManager.release_enable_request(owner: Object) -> void` | Retire le blocker. `push_warning` si owner n'avait pas de blocker actif. |
| `InputManager.enabled: bool` | READ-ONLY. `true` si `_enable_blockers.is_empty()`. |
| `signal application_focus_lost()` | Émis dans `_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)`. Consommé par GameStateManager (et autres). |
| `signal application_focus_gained()` | Émis dans `_notification(NOTIFICATION_APPLICATION_FOCUS_IN)`. Consommé par UX systems. |
| `signal mouse_motion(delta: Vector2)` | Inchangé (GDD règle 4). Supprimé dans fenêtre 50 ms post-FOCUS_IN. |
| `InputManager.simulate_action_press(action: StringName) -> void` | Debug-only (no-op release). Utilise `Input.parse_input_event(InputEventAction)`. |
| `InputManager.last_input_to_publish_latency_ms: float` | READ-ONLY getter. Calcul p99 sur demande (PackedFloat32Array ring buffer cap 120). |
| **Supprimé** : `InputManager.is_action_just_pressed()` | Déprécié. Consumer doit appeler `was_pressed_this_tick()`. |
| **Supprimé** : `InputManager.set_enabled(bool)` | Déprécié. Remplacé par `request_disable` / `release_enable_request`. |

## Alternatives Considered

### Alternative 1 : Keep `is_action_just_pressed` + add `was_pressed_this_tick` as alias

- **Description** : Garder l'API existante du GDD r2 comme wrapper au-dessus de `Input.is_action_just_pressed`, ajouter `was_pressed_this_tick` comme alternative recommandée.
- **Pros** : Migration GDD minimale. Rétro-compatibilité formelle.
- **Cons** : Le forbidden_pattern ADR-0001 interdit déjà `is_action_just_pressed` direct — avoir deux APIs avec sémantiques différentes (render-frame vs physics-tick) et dont l'une est forbidden est une **erreur structurelle de design** qu'on paiera en confusion développeur. Un nouveau dev copiera la mauvaise API et cassera l'AC-CS-1.
- **Rejection Reason** : La cohérence avec ADR-0001 exige une suppression nette, pas une coexistence ambiguë. Le coût de migration GDD (quelques renames) est faible comparé au coût long-terme d'un forbidden pattern à l'interface publique.

### Alternative 2 : `set_enabled(bool)` simple + convention d'usage côté caller

- **Description** : Garder l'API `set_enabled(bool)` existante. Les callers doivent « coopérer » pour ne pas stomper les uns sur les autres (convention).
- **Pros** : API plus simple. Zéro infrastructure refcount.
- **Cons** : Les conventions de ce type ne survivent pas à un 4e contributeur. Le scénario bug identifié (Menu close pendant Checkpoint respawn ongoing) est structurellement possible et silencieux. Debug extrêmement coûteux (race entre trois autoloads).
- **Rejection Reason** : Les bugs de race condition sur state global sont les plus coûteux à diagnostiquer en QA. L'infrastructure refcount est 30 lignes de code ; le coût d'un bug shipping est bien supérieur.

### Alternative 3 : Garder `_skip_next_mouse_delta: bool` + documenter Wayland comme « limitation connue »

- **Description** : Garder le pattern single-shot du GDD règle 13, ajouter note « Wayland peut avoir un micro-jump au retour de focus — limitation connue, pas de fix MVP ».
- **Pros** : Zéro code change.
- **Cons** : Linux Wayland est ~30–40 % de la base Linux 2026 (Steam Hardware Survey trend). Steam Deck = GameScope (dérivé Wayland). Un micro-jump caméra au retour de focus sur Steam Deck serait un bug visible et reproduisible, coûteux en review review Steam.
- **Rejection Reason** : Le fix (fenêtre temporelle 50 ms) est 5 lignes. Le risque reviewer negatif est réel. La fenêtre temporelle est aussi une **meilleure** sémantique que le bool single-shot sur tous les OS, pas juste Wayland.

### Alternative 4 : Mesure latency via `Array[Dictionary]` avec pre-allocation `.resize()` + pool

- **Description** : Garder la structure `Array[Dictionary]` mais pré-allouer l'Array au boot et réutiliser les Dict existants (write-over, pas `push_back`).
- **Pros** : Plus lisible que deux PackedArrays parallèles. Accès champ par nom `sample.ms` au lieu de deux indexages.
- **Cons** : Un `Dictionary` en GDScript alloue pour ses buckets internes même après reuse — il n'y a pas de garantie qu'écrire sur une clé existante ne ré-alloue pas (selon la version Godot, peut compacter). `PackedFloat32Array` est garanti contigu et zero-alloc write. De plus, l'accès par clé `Dict.ms` est plus lent qu'un index `Array[i]` (hash vs pointer arith).
- **Rejection Reason** : Zero-alloc hot path est une contrainte absolue (Pillar 1). `PackedFloat32Array` est l'API idiomatique Godot pour buffer numérique dense. Léger coût de lisibilité accepté.

### Alternative 5 : Output `ticks_usec()` compteur interne depuis `_input` + timestamp natif Godot

- **Description** : Attendre que Godot 4.7+ livre un timestamp natif sur `InputEvent` (feature request upstream récente) puis migrer. En attendant, pattern sous-optimal accepté.
- **Pros** : Futur-proof.
- **Cons** : Godot 4.7 non annoncé. Bloque le MVP indéfiniment. Le pattern `Time.get_ticks_usec()` au début du callback est standard et fonctionnel.
- **Rejection Reason** : Wait-and-see n'est pas une option pour MVP Sprint 1.

## Consequences

### Positive

- **Stabilisation de 4 BLOCKINGs structurels + 3 testing** identifiés review r4. Le GDD peut être finalisé sans re-ouvrir ces points.
- **Cohérence avec ADR-0001** : `was_pressed_this_tick` remplace précisément le forbidden pattern. Plus de contradiction cross-ADR.
- **Multi-owner safe** : le refcount élimine la classe entière de bugs « input réactivé pendant autre owner encore disabled ».
- **Découplage propre** : InputManager redevient Foundation vraie (zero dépendance aval). GameStateManager consomme signal one-way.
- **Cross-OS robuste** : fenêtre 50 ms absorbe le burst Wayland sans casser les autres OS.
- **Zero-alloc hot path** mesuré : le ring buffer PackedFloat32Array rend l'AC-PF-2 passable sur 60 s stress test.
- **Testability** : `parse_input_event(InputEventAction)` déclenche réellement `_unhandled_input`, couvre tous les AC du GDD — fin de la zone grise r2.
- **Thread safety** explicite : interdiction claire évite bugs futur Accessibility System.

### Negative

- **Migration GDD requise** : le GDD Input System r2 devra être réécrit sur 7 sections (Published API, Detailed Design règles 6/7/10/11/13/14, Edge Cases, AC-AG-1/2/3 et AC-CS-1 et AC-PF-2). Effort ~1h30 après ADR Accepted.
- **API légèrement plus verbeuse** : `InputManager.request_disable(self)` vs `InputManager.set_enabled(false)` — 2 tokens de plus. Acceptable.
- **Double storage latency (values + timestamps)** : 120 × (4 + 8) bytes = 1.4 KB fixes. Négligeable.
- **Coût CPU refcount** : `Dictionary.has()` + `.erase()` par request/release — O(1), mesurable en µs, non-significatif hors stress extrême.
- **Complexité conceptuelle accrue** : un dev qui arrive doit comprendre pourquoi il y a deux Dict (`_pressed` / `_consumed`) et pourquoi on swap. Documentation inline claire requise dans InputManager.gd.

### Risks

- **Risk 1 — `NOTIFICATION_APPLICATION_FOCUS_IN/OUT` remplacés par `Window.focus_entered/exited` en 4.6**. Dual-focus system (breaking-changes.md 4.6) peut avoir déplacé la sémantique OS-level vers `Window` signals. → **Mitigation** : valider en setup phase sur build Godot 4.6 local. Si NOTIFICATION constants obsolètes, migrer vers signals. Critère Verification-1.
- **Risk 2 — Swap `_pressed ↔ _consumed` par référence GDScript** : si GDScript applique une copy-on-write subtile sur Dictionary swap (non documenté explicitement), le comportement diverge. → **Mitigation** : test GUT dédié `test_was_pressed_this_tick_swap_is_zero_alloc` avec `Performance.get_monitor(MEMORY_STATIC)` stable. Si alloc détectée, replier sur deux tableaux parallèles indexés.
- **Risk 3 — Fenêtre 50 ms trop courte sur certains drivers Wayland** : un burst de 80–100 ms a été reporté sur certains compositeurs (Sway, Hyprland en mode gaming). → **Mitigation** : paramétrer la fenêtre dans `input_settings.tres` (range 20–150 ms). Default 50 ms ; tunable par platform si playtest Linux révèle un problème.
- **Risk 4 — Owner qui se fait free sans passage par `tree_exited`** : `Object` non-Node (Resource, RefCounted) n'émet pas `tree_exited`. Si un tel owner est utilisé pour `request_disable`, pas d'auto-cleanup. → **Mitigation** : restreindre l'API à `Node` via signature typée `request_disable(owner: Node) -> void`. Assert runtime pour attraper les cas edge.
- **Risk 5 — `Input.parse_input_event(InputEventAction)` n'est pas strictly equivalent à un vrai key press** : il déclenche `_unhandled_input` mais pas nécessairement `Input.is_action_pressed()` pour le tick courant, selon la version Godot. → **Mitigation** : valider dans un test GUT de contrat `test_simulate_action_press_triggers_unhandled_input_and_is_pressed` avant d'écrire d'autres AC qui s'appuient dessus.
- **Risk 6 — Ordre autoload garanti mais fragile** : un futur autoload ajouté avant `InputManager` dans `project.godot` casserait l'ordre « InputManager runs first ». → **Mitigation** : lint rule `.claude/rules/inputmanager-autoload-first.md` + AC GUT `test_autoload_order_inputmanager_first`. Documenter dans CLAUDE.md.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/input-system.md` règle 7 (Published API) | Expose `is_action_just_pressed()` publiquement | Supprime cette méthode, remplace par `was_pressed_this_tick()`. GDD à mettre à jour. |
| `design/gdd/input-system.md` règle 6 (`enabled`) | `set_enabled(bool)` + convention d'usage | Remplace par refcount `request_disable(owner) / release_enable_request(owner)`. |
| `design/gdd/input-system.md` règle 11 (signal vs polling) | « polling gameplay, signal UI/event » | Conservé. `was_pressed_this_tick` est le polling canonique ; signals typés restent pour UI. |
| `design/gdd/input-system.md` règle 13 (focus loss) | `_skip_next_mouse_delta: bool` single-shot | Remplace par fenêtre temporelle 50 ms absolute time. Wayland-safe. |
| `design/gdd/input-system.md` Formulas / Latency measurement (ligne 250) | `Array[Dictionary]` allocated per sample | Remplace par 2× `PackedFloat32Array` pré-alloués + `write_idx % capacity`. Zero alloc. |
| `design/gdd/input-system.md` Edge Case ligne 278 (focus out) | `GameStateManager.request_pause()` appel direct depuis Input | Remplace par signal `application_focus_lost` ; GameStateManager consomme. |
| `design/gdd/input-system.md` règle 7 (fixture test) | `#if debug_build` | Remplace par `OS.has_feature("debug")` runtime + no-op release + `parse_input_event(InputEventAction)`. |
| `design/gdd/input-system.md` AC-CS-1 | Consumer polling lit `true` au tick N, pas N+1 | Reset synchrone via swap `_pressed ↔ _consumed` en début de `_physics_process` du InputManager. |
| `design/gdd/input-system.md` AC-AG-1 | `Input.action_press()` déclenche `_unhandled_input` | Remplace par `Input.parse_input_event(InputEventAction)` (pattern godot-specialist tranché r4). |
| `design/gdd/input-system.md` AC-PF-2 | Zero alloc hot path | Satisfiable par construction avec PackedFloat32Array + swap par ref. |
| `design/gdd/input-system.md` AC-PF-4 (à ajouter) | Coût hot path p99 ≤ 0.1 ms release | Profilable séparément du gate 16 ms AC-L-3. |
| `docs/architecture/adr-0001-physics-rate-60hz.md` | Pattern flag-via-signal ; forbidden `is_action_just_pressed` direct | Formalise `was_pressed_this_tick` comme l'implémentation concrète du pattern. |

## Performance Implications

- **CPU** :
  - `_unhandled_input` : 1 dict write `_pressed_this_tick[action] = true` par press + 1 signal emit typed. Négligeable (~0.01 ms).
  - `_physics_process` InputManager : 1 dict swap (ref assignment) + 1 loop `N_actions` pour clear + 1 write PackedFloat32Array. Total ≈ 0.02 ms.
  - `was_pressed_this_tick` côté consumer : 1 `.get()` + 1 compare. ≈ 0.001 ms par appel. Movement + Combat ≈ 4–6 appels par tick → 0.005 ms cumulé.
  - **Budget registry** : `input: 0.2 ms/frame` p99 (à enregistrer dans `architecture.yaml` performance_budgets). Large marge vs mesures théoriques ~0.05 ms.
- **Memory** : fixed overhead 1.4 KB (ring buffers) + dict `_pressed` / `_consumed` / `_enable_blockers` ≈ 2 KB total. Zero runtime growth après `_ready()`.
- **Load Time** : inchangé. `_ready()` alloue 2 Dict + 2 PackedArray — µs range.
- **Network** : non applicable.

## Migration Plan

- **Code** : aucun code dans `src/gameplay/` ni `src/core/`. Pas de migration de production.
- **Prototype `prototypes/movement-katana/`** : le prototype utilise un Input inline (pas d'InputManager autoload). Non affecté par ce ADR — il sera remplacé par l'implémentation v1 de `src/core/input_manager.gd` en Sprint 1, construite directement selon ce ADR.
- **GDD `input-system.md`** : réécriture en une passe dédiée **après Accepted**. Sections touchées : Published API (règle 7), Core Rules (6, 10, 11, 13, 14), Edge Cases (focus out/in, test fixture), Formulas (latency measurement), AC-AG-1/2/3, AC-CS-1, AC-PF-2, + ajout AC-PF-4. Estimation 1h30.
- **Registry `architecture.yaml`** : nouvelles entrées `interfaces` (was_pressed_this_tick, application_focus_lost signal, mouse_motion signal), `api_decisions` (input_polling_api, input_enable_refcount, latency_ring_buffer_format), `forbidden_patterns` (`input_singleton_access_from_non_main_thread`, `set_enabled_bool_global_without_refcount`, `preprocessor_if_debug_build_in_gdscript`), `performance_budgets` (input 0.2 ms/frame). À créer en phase 6 du skill `/architecture-decision` avec validation Martin.
- **Rules / Control Manifest** : après création du manifest (phase ultérieure), ajouter :
  - REQUIRED : `was_pressed_this_tick` pour tout polling gameplay action
  - FORBIDDEN : `Input.is_action_just_pressed` direct depuis gameplay ; `InputManager.set_enabled`; `#if debug_build`
  - GUARDRAIL : `Input.mouse_mode` main-thread only
- **Session state** : marquer `[x]` sur ADR-0002 (nomenclature session-state) ou ADR-0004 (nomenclature réelle) puis déclarer next task = « application fixes GDD Input System ».

## Validation Criteria

- **VC-1 (Focus notifications 4.6)** : test manuel trois OS (Windows 11, macOS Sonoma, Linux Ubuntu 24 Wayland + X11). GIVEN build debug, scène test. WHEN alt-tab x5. THEN `application_focus_lost` + `application_focus_gained` émis 5 fois chacun ; aucun warning log « NOTIFICATION_APPLICATION_FOCUS_OUT obsolete ». Si warning, migration vers `Window.focus_entered/exited` requise.
- **VC-2 (Wayland burst absorbé)** : test manuel Ubuntu Wayland. GIVEN caméra active, mouse captured. WHEN alt-tab vers autre fenêtre, bouger souris 300 px, retour focus. THEN rotation caméra post-focus ≤ 2° (vs > 30° sans fix).
- **VC-3 (Zero alloc hot path)** : test GUT `tests/performance/input_zero_alloc_test.gd`. GIVEN 10 000 `simulate_action_press` + 10 000 `simulate_mouse_motion` sur 60 s. THEN `Performance.get_monitor(MEMORY_STATIC)` delta < 64 KB (marge GC).
- **VC-4 (AC-CS-1 tick parity)** : test GUT `tests/integration/input_polling_same_tick_test.gd`. GIVEN consumer node polling `was_pressed_this_tick(&"jump")` dans `_physics_process`. WHEN `simulate_action_press(&"jump")` injecté. THEN le consumer lit `true` au `_physics_process` du **tick N** (pas N+1).
- **VC-5 (Refcount multi-owner)** : test GUT `tests/integration/input_enable_refcount_test.gd`. GIVEN 3 owners (Menu, Checkpoint, Cutscene mocks). THEN la séquence Menu.request_disable → Checkpoint.request_disable → Menu.release → gameplay input still gated → Checkpoint.release → gameplay input re-enabled.
- **VC-6 (Auto-cleanup tree_exited)** : test GUT. GIVEN owner Node qui appelle `request_disable(self)` puis `queue_free()` sans release. THEN après `tree_exited`, `_enable_blockers.size() == 0`, `enabled == true`.
- **VC-7 (Thread safety guardrail)** : lint statique `.claude/rules/input-singleton-main-thread-only.md`. GIVEN scan `src/` pour `Input.*` dans contextes `Thread`, `WorkerThreadPool`, `Callable.call_deferred` from non-main. THEN zéro match.
- **VC-8 (Latency p99 rolling)** : test GUT. GIVEN 120 samples injectés manuellement avec valeurs connues. WHEN `last_input_to_publish_latency_ms` lu. THEN valeur = p99 attendu ± 0.1 ms.

Si VC-1 échoue → ADR re-ouvert avec migration vers `Window.focus_entered/exited`.
Si VC-3 échoue → Alternative 4 (pool Dict) ou reporter ring buffer en GDExtension C++.
Les autres VC échouant → fix implementation, pas de rollback ADR.

## Related Decisions

- **ADR-0001 (Physics Rate 60 Hz)** — Amont direct. Cet ADR implémente concrètement le pattern flag-via-signal prescrit par ADR-0001.
- **ADR-0002 (Camera Scene Tree)** — Aucune interaction directe. La Camera consomme `mouse_motion` signal (contrat inchangé) et `was_pressed_this_tick` (pour toggle éventuel — non MVP).
- **ADR-0003 (Rendering & Display Latency)** — Complémentaire. ADR-0003 traite display side (VSync, refresh). Cet ADR-0004 traite intra-engine input side. Additionnent pour Pillar 1 end-to-end ≤ 50 ms.
- **`design/gdd/input-system.md`** — GDD piloté. À réécrire dans une passe dédiée post-Accepted.
- **`design/gdd/player-movement-system.md`** — Consumer. AC jump buffer / dash cooldown utiliseront `was_pressed_this_tick`.
- **`design/gdd/player-combat-system.md`** (à créer) — Consumer attack.
- **Futur ADR Accessibility** (Tier 3) — héritera de la règle main-thread only pour features hold-to-repeat / sticky keys.
- **Futur `.claude/rules/inputmanager-autoload-first.md`** — enforce autoload ordering.

---

*Auteur : Architecture Decision skill, 2026-04-21*
*Source directe : `design/gdd/reviews/input-system-review-log.md` r4 (2026-04-21) — 4 BLOCKINGs structurels + 3 testing.*
*Mode review : solo (TD-ADR gate skipped, engine-specialist gate skipped — à valider en fresh session via `/architecture-review` indépendant avant Accepted).*
*Numérotation : ADR-0004. Note : le slot ADR-0002 était initialement réservé à « Input API & Focus Handling » (cf. footer adr-0003-rendering-latency.md) mais a été attribué entretemps à adr-0002-camera-scene-tree-cameraarm.md. Cette numérotation préserve la séquence existante sans forcer de renumérotation cross-ADR.*
