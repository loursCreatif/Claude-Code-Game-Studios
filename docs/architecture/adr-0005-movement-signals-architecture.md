# ADR-0005: Movement Signals Architecture — Direct Typed Signals from MovementController

## Status
Accepted

## Date
2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session `/architecture-review` r2 — verdict PASS, gap G-1 HIGH résolu, cohérence cross-ADR confirmée avec ADR-0001/0002/0004, dépendance ADR-0001 satisfaite)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Events / Architecture / Core |
| **Knowledge Risk** | LOW |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/current-best-practices.md` (aucun changement signal 4.4–4.6), `docs/engine-reference/godot/breaking-changes.md` (aucun item signal-related), `docs/engine-reference/godot/deprecated-apis.md` (aucun signal deprecated), `.claude/docs/technical-preferences.md` (naming conventions snake_case past tense), `docs/architecture/adr-0001-physics-rate-60hz.md`, `docs/architecture/adr-0004-input-api-focus-handling.md` (pattern de référence pour signal contracts) |
| **Post-Cutoff APIs Used** | Aucune. Signals typés, `CONNECT_DEFERRED`, `emit_signal()`, `@warning_ignore` existaient avant 4.4. Typed signal strictness check (debug build) existait en 4.0+. |
| **Verification Required** | (1) Valider en debug build que les payloads typés `Vector3` / `float` / `StringName` déclenchent bien l'erreur de connexion sur mismatch (godot-specialist F5 : mismatch silencieux en release). (2) Benchmark coût signal dispatch pour 8 signals × 3–6 consumers sur 60 fps → doit rester ≤ 0.05 ms/frame cumulé. (3) Vérifier qu'un `emit_signal` depuis `_physics_process` avec `CONNECT_DEFERRED` exécute le callback avant la fin du process_frame suivant (pas reporté de plusieurs frames). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Physics Rate 60 Hz + Jolt) — les émissions signal Movement sont contraintes à `_physics_process` par l'autorité gameplay posée par ADR-0001. ADR-0001 doit être `Accepted` avant qu'ADR-0005 puisse l'être. |
| **Enables** | Implémentation Camera System (consomme `wall_run_entered/exited` pour tilt, `dash_started/dash_ended` pour FOV kick, `died/respawned` pour overlay rouge + reset) ; implémentation Combat System (consomme `attacked` pour trigger swept hitbox) ; implémentation Audio System (consomme tous signals pour SFX) ; implémentation VFX System (trails dash, impact wall-run, fondu respawn) ; implémentation HUD System (dash cooldown, death overlay). Déverrouille la 1ère story Sprint 1 Movement. |
| **Blocks** | Epic `player-movement` (contrat API non stable sans cet ADR) ; Epic `camera-system` (tilt wall-run dépend de `wall_run_entered.connect`) ; Epic `player-combat` (hitbox timing sur `attacked`) ; Epic `audio-system` (SFX binding) ; Epic `vfx-feedback` ; Epic `hud-system`. |
| **Ordering Note** | ADR-0005 peut être Accepted en parallèle avec ADR-0002/0003/0004 (tous Core-tier, tous dépendent uniquement d'ADR-0001 Foundation). Aucun cycle. Transition recommandée : ADR-0001 `Accepted` en premier, puis les 4 Core ADRs ensemble dans la foulée. |

## Context

### Problem Statement

La review indépendante `/architecture-review` du 2026-04-21 (verdict CONCERNS) a identifié G-1 comme gap **HIGH** bloquant : le GDD `design/gdd/player-movement-system.md` r3 liste 8 signaux (l. 82–91) publiés par le Player node — `dash_started`, `dash_ended`, `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned`, `attacked` — **sans pattern architectural canonique** pour leur ownership, leur typage strict, leur ordre d'émission, ni leur discipline de consommation cross-system.

godot-specialist F5 avait déjà surfacé cette zone en review r3 du GDD Movement (cf. Movement review log) : *« 9 consommateurs des signaux Movement → direct signals (simple, mais couplage N:1) ou EventBus autoload (découplage, overhead signal dispatch) ? Technical-director arbitrage. À lever avant Sprint 1 story implementation. »* Cette question a été laissée en pending dans le GDD avec un PENDING ADR marker (cf. progress list l. 619).

Cinq points concrets exigent une décision figée avant toute story :

1. **Ownership** : qui émet, depuis quel node ? Le GDD dit « depuis le Player node » sans préciser si c'est le `CharacterBody3D` lui-même (MovementController) ou un sub-node dédié (`MovementEventEmitter`). Différence : couplage direct au body vs surface additionnelle de scene tree.

2. **Pattern** : direct typed signals attachés au MovementController (consumers `player.dash_started.connect(...)`) OU EventBus autoload `MovementEvents` (consumers `MovementEvents.dash_started.connect(...)`) ? Chaque alternative a des coûts. Sans décision, deux developers feront deux choix et les consumers casseront.

3. **Typage strict** : Godot 4.x permet des signals typés (`signal dash_started(dash_dir: Vector3, dash_speed: float)`). Godot vérifie les types **à la connexion en debug build seulement** (godot-specialist F5) — mismatches passent silencieusement en release. Sans contrainte formelle, un consumer peut connecter un Callable avec mauvaise signature et shipper un bug.

4. **Ordre d'émission et contrat d'idempotence** : si `die()` est appelé pendant `Dashing`, est-ce que `dash_ended` est émis avant `died`, ou `died` seul, ou les deux dans l'ordre inverse ? Les consumers Audio/VFX attendent une séquence prévisible. AC-MV-41 couvre déjà l'idempotence de `died` (early return ligne 130), mais pas les autres signaux de transition d'état.

5. **Discipline de performance et coupling** : les consommateurs (VFX, Audio, HUD) peuvent être « lourds » (instancier GPUParticles, démarrer AudioStreamPlayer) ou « light » (toggle booléen HUD). Le GDD r3 (godot-specialist F4 nuancé) recommande `CONNECT_DEFERRED` pour les lourds, synchrone pour les légers — mais sans règle codée, un dev appliquera `CONNECT_DEFERRED` partout (ajoute 1 frame de latence HUD) ou nulle part (burst CPU sur mort/respawn).

Sans ces 5 points figés dans un ADR, chaque itération GDD et chaque nouveau consumer re-ouvre la discussion. Coût cumulé estimé : 2–3× re-review cross-GDD pour chaque nouveau système consommateur (Camera, Combat, VFX, Audio, HUD — 5 × 2h = 10h).

### Constraints

- **Engine** : Godot 4.6 + GDScript. Signals = API stable pré-4.0 ; typed signals = 4.0+ ; typed strictness check = debug build only (runtime silencieux en release).
- **ADR-0001 acquis** : autorité gameplay `_physics_process`. Toute mutation d'état (incluant signal emit sur state transition) doit se produire dans ce callback. Interdiction d'émettre signal Movement depuis `_process` (cosmétique only).
- **Pillar 1 — Zero-alloc hot path** : les payloads signal ne doivent pas allouer (pas de `Dictionary` littéral, pas de `Array` littérale). Vector3 / float / StringName / int = value types ou references pré-allouées.
- **Pillar 3 — Respect de la Rétention / Feedback immédiat** : les signaux `died` et `respawned` sont sur chemin critique respawn (RESPAWN_DELAY = 50 ms, invariant `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE`). Tout retard cross-frame est perceptible.
- **Naming convention** : `snake_case` past tense pour signals (technical-preferences.md). Valeurs actuelles GDD conformes (`dash_started`, `wall_jumped`, `died`).
- **Solo mode** : TD-ADR gate + engine-specialist gate skipped (cohérent avec `production/review-mode.txt` = `solo`). Validation indépendante par `/architecture-review` en fresh session obligatoire avant Accepted.
- **Foundation discipline** : MovementController est un système Core (dépend d'Input Foundation). Il ne doit référencer aucun consumer par nom (pas de `CameraSystem.dash_started.emit()`, pas de `VFXManager.play_dash_trail()`). Communication sortante exclusivement par signal émis depuis lui-même.

### Requirements

- **REQ-1** — Un consumer qui connecte `player.dash_started.connect(_on_dash_started)` avec signature mismatch (e.g. `func _on_dash_started(dir: Vector3)` au lieu de `(dir: Vector3, speed: float)`) doit être **détecté en debug build** avant merge. Contrat test explicite.
- **REQ-2** — L'émission d'un signal Movement doit être **zero-alloc** dans le hot path `_physics_process`. Pas de `{...}` literal, pas de `Array[Vector3]` construit à la volée pour payload.
- **REQ-3** — L'ordre d'émission doit être **déterministe** pour toute combinaison de transitions d'état dans le même tick (e.g. dash→die, wall-jump→dash, respawn-during-dash). Séquence prévisible = testable.
- **REQ-4** — Les consommateurs lourds (instanciation de Node / AudioStream / GPUParticles) doivent utiliser `CONNECT_DEFERRED` par convention explicite ; les consommateurs légers (toggle bool, lecture read-only) peuvent utiliser connection synchrone.
- **REQ-5** — MovementController ne doit contenir **aucune référence directe** vers Camera, Combat, VFX, Audio, HUD (ni par `$NodePath`, ni par `get_node()`, ni par `ClassName.method()` static). Vérifié par lint.
- **REQ-6** — Les consommateurs ne doivent **jamais muter l'état Movement** depuis un signal handler (pas de `player.velocity = ...`, pas de `player.die()`). Write access exclusif au MovementController lui-même (forbidden_pattern `direct_cross_system_state_write` généralisé aux signal handlers).
- **REQ-7** — Un signal d'entrée d'état (`wall_run_entered`, `dash_started`) doit être émis **une seule fois** par transition d'état. Les signaux `died` est déjà idempotent (AC-MV-41 + early return). Symétrie requise pour les autres.
- **REQ-8** — La propriété `state: State` (enum read-only, GDD l. 114) reste la **source de vérité canonique** pour l'état courant. Les signaux sont des **notifications de transition**, pas le state lui-même. Un consumer arrivant tard (connect après la transition) lit `player.state`, ne reçoit pas la notification passée. Contrat documenté.

## Decision

Adopter les décisions D-1..D-10 ci-dessous comme pattern canonique pour toute communication événementielle depuis MovementController. Elles formeront la base implémentable du GDD Movement (confirme et précise les sections actuelles) et servent de **référence pour les ADRs ultérieurs** Combat / Camera / VFX / Audio qui publieront leurs propres signaux.

### D-1 — Pattern : direct typed signals depuis MovementController (Player node)

Tous les événements Movement sont émis comme **signals Godot natifs typés** déclarés **sur le MovementController lui-même** (classe attachée au CharacterBody3D Player). Consumers se connectent via `player_ref.signal_name.connect(callable)`.

- **Pas d'EventBus autoload** pour les événements intra-gameplay Movement. Rejected — cf. Alternative 1.
- **Pas de sub-node dédié `MovementEventEmitter`**. Le MovementController émet directement. Rejected — cf. Alternative 2.
- **Pattern de référence** : identique au contract `mouse_motion` posé par ADR-0004 (signal sur InputManager, consumer Camera se connecte).

### D-2 — Signal list canonique figée (8 signals MVP)

Liste exhaustive des signals publiés par MovementController au MVP. **Ajout d'un signal = amendement de cet ADR** (pas de drift silencieux GDD→implémentation).

```gdscript
# In movement_controller.gd (attached to Player CharacterBody3D):

signal dash_started(dash_dir: Vector3, dash_speed: float)
signal dash_ended()
signal wall_run_entered(wall_normal: Vector3)
signal wall_run_exited()
signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)
signal died()
signal respawned(spawn_position: Vector3)
signal attacked()  # forwarded from Input "attack" action pour Combat convenience
```

**Reserved for post-MVP** (non émis au MVP, renommage interdit si introduit plus tard) :
- `falling(fall_speed: float)` — candidat pour Audio wind loop + Accessibility narration. Hors scope MVP, nom réservé pour ne pas collider.

### D-3 — Typage strict des payloads

Tous les payloads utilisent des types Godot primitifs / value-type stricts :
- `Vector3` (normal de mur, direction de dash, position de spawn, vélocité de launch) — value type, zero-alloc à l'emit.
- `float` (dash_speed, fall_speed) — value type.
- `StringName` interdit comme payload de ces 8 signaux (aucun n'a besoin de stringId).
- `Dictionary`, `Array`, `String` **interdits** comme payload (allocation hot path).
- `Node` / `Resource` interdits comme payload (coupling indirect, risque dangling ref sur free).

**Test de contrat obligatoire** : un test GUT `tests/integration/movement/test_movement_signals_typed_contract.gd` vérifie en debug build que chaque signal connecté avec mauvaise signature déclenche `push_error` (typed signal strictness Godot 4.x). Sans ce test, les mismatches passent silencieux en release build (godot-specialist F5 review r3 Movement).

### D-4 — Lieu d'émission : `_physics_process` exclusivement

Tous les signals Movement sont `emit()` **uniquement depuis** `_physics_process` du MovementController (ou une fonction appelée depuis `_physics_process` : `die()`, `respawn()`, transition state machine interne).

- **Forbidden** : emit depuis `_process`, `_input`, `_unhandled_input`, `_ready`, timer callbacks directs (`Timer.timeout.connect`). Les timers de dash / respawn sont lus depuis `_physics_process` (compteurs `dash_timer -= delta`), pas via Timer node signals.
- **Justification** : respecte l'autorité gameplay ADR-0001. Les consumers lisent `player.state` depuis leur propre `_process` (caméra) ou `_physics_process` (combat) avec la garantie que les signals sont cohérents avec l'état.

### D-5 — Connection mode : `CONNECT_DEFERRED` pour consumers lourds, synchrone pour légers

**Règle codée** : un consumer doit utiliser `CONNECT_DEFERRED` **si et seulement si** le callback peut :
- (a) instancier un `Node` (GPUParticles3D, AudioStreamPlayer, MeshInstance3D, scene `.instantiate()`),
- (b) démarrer un sampler / stream (`AudioStreamPlayer.play()` avec stream non pré-chargé),
- (c) effectuer une allocation GDScript de taille > 256 bytes (e.g. Array d'objets, Dictionary construit à la volée),
- (d) exécuter une logique > 0.5 ms CPU.

**Sinon** (toggle bool, lecture read-only, lerp cible de variable existante), connection synchrone (flag `CONNECT_0` / default).

**Exemples MVP** :
- VFX dash trail → `CONNECT_DEFERRED` (instancie GPUParticles3D). 
- Audio dash whoosh → `CONNECT_DEFERRED` (AudioStreamPlayer.play).
- Camera FOV kick → synchrone (lerp target var).
- HUD dash cooldown UI toggle → synchrone (bool assignment).

**Table de référence consignée dans le GDD Movement r3 l. 96** — cet ADR la formalise comme règle architecturale, pas juste recommandation.

**Caveat** : `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE` (invariant GDD l. 355) est obligatoire pour garantir que les consumers `CONNECT_DEFERRED` de `died` reçoivent leur callback avant `respawn()`. Valeur courante 50 ms ≫ 16.6 ms min ✓.

#### Amendment r2 (2026-04-23) — Exemptions SYNC pour signaux frame-précis Combat

Le GDD Player Combat System r2 (`design/gdd/player-combat-system.md`) impose deux exceptions SYNC documentées en application des critères (a)(b)(c)(d) :

1. **VFX flash blanc `enemy_killed` → `ColorRect.visible = true` + `Tween.tween_property(alpha)`** (GDD Combat Section VFX 2a, r2 Martin D4).
   - Opération triviale : toggle bool + tween sur propriété existante. Aucune allocation > 256 bytes, aucune instanciation de Node (ColorRect pré-existant dans VFXLayer), pas de stream start.
   - **Critères (a)(b)(c)(d) non remplis** → connexion synchrone autorisée.
   - **Pourquoi SYNC est nécessaire** : Pillar 1 FLOW exige que le flash blanc soit rendu dans le même rendering frame que le kill tick. `CONNECT_DEFERRED` décalerait de 16.6 ms (frame +1) → viole "frame-précis" contract GDD + Fantasy "silence entre deux notes". Les autres consumers du même signal `enemy_killed` (GPUParticles sang, Decal, AudioStreamPlayer3D impact) **restent `CONNECT_DEFERRED`** (critères (a)(b) remplis).

2. **Combat consumer SYNC du signal `died` de Movement** (GDD Combat Rule 17 r2 M1 Option C Hybrid).
   - Handler SYNC `_on_player_died()` dans CombatSystem : set `_death_pending: bool = true`, retour immédiat. Aucune mutation d'état Movement (respect D-7). Aucune allocation. Aucune logique > 0.5 ms.
   - **Critères (a)(b)(c)(d) non remplis** → connexion synchrone autorisée.
   - **Pourquoi SYNC est nécessaire** : le mécanisme Rule 17 Hybrid exige que Combat sache `_death_pending` AVANT d'exécuter son propre `_physics_process` (le signal arrive dans la stack de Movement `_physics_process` parent, AVANT le callback `_physics_process` Combat child). Avec `CONNECT_DEFERRED`, le flag serait set au tick+1 → la Rule 17 séquence est rompue, et la résolution des colliders avant transition Dead n'est plus garantie.
   - **Invariant contrat D-7 respecté** : le handler SYNC mute un flag **local** à CombatSystem (`_death_pending`), jamais un attribut de Movement. Consumer contract D-7 reste valide.

**Exceptions documentées — toute autre exception SYNC doit passer un amendment explicite à cet ADR** (code review strict : tout `connect(callable)` sans `CONNECT_DEFERRED` hors ces 2 cas + les exemples light MVP existants (Camera FOV kick, HUD toggle) est un defect.)

#### r4 scope note — Cross-Domain Signal References (non-normative)

(Ajout 2026-04-23 suite à `/design-review` r4 Combat GDD — décision Martin D-r3-2 Option B)

ADR-0005 régit **exclusivement** les signaux MovementController (D-2 : `dash_started`, `dash_ended`, `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `attacked`, `died`, `respawned`). La table de référence ci-dessous inclut des lignes qui référencent le signal **Combat** `enemy_killed` (source `CombatSystem`, pas `MovementController`). Ces entrées sont listées ici **pour tracabilité historique** (décision Martin M1/D4 propagée depuis `design/gdd/player-combat-system.md` r2 via `/design-review`) mais elles sont **non-normatives au sens ADR-0005** — l'autorité canonique pour les connexions aux signaux Combat est le **Pending ADR Combat Tick Model** (owner lead-programmer pré-Sprint 1), qui héritera cette exemption SYNC sans modification sémantique.

**Normatif ADR-0005** : ligne `Combat _on_player_died (flag _death_pending) | died | SYNC` régit la connexion d'un consumer Combat au signal **Movement** `died` → autorité ADR-0005.

**Non-normatif ADR-0005** : ligne `VFX flash blanc ColorRect | enemy_killed | SYNC` régit la connexion d'un consumer VFX au signal **Combat** `enemy_killed` → autorité déléguée au Pending ADR Combat Tick Model. Conservée ici pour contexte historique.

Décision Martin 2026-04-23 D-r3-2 : préservation du contexte historique dans ADR-0005 plutôt que création d'un ADR-0006-combat-signals-architecture séparé — rationale : moins de churn, traçabilité M1 intacte, pas de pollution ADR-0006 avec une seule ligne d'exemption. technical-director peut réviser ce choix via gate TD-ADR-SCOPE si future friction apparaît.

**Table de référence mise à jour r2** :

| Consumer | Signal | Mode | Justification |
|---|---|---|---|
| VFX dash trail | `dash_started` | DEFERRED | instancie GPUParticles3D (critère a) |
| Audio dash whoosh | `dash_started` | DEFERRED | AudioStreamPlayer.play (critère b) |
| Camera FOV kick | `dash_started` | SYNC | lerp target var (light) |
| HUD dash UI toggle | `dash_ended` | SYNC | bool assignment (light) |
| VFX GPUParticles sang | `enemy_killed` | DEFERRED | instancie GPUParticles3D (critère a) |
| VFX Decal sang | `enemy_killed` | DEFERRED | instancie Decal (critère a) |
| Audio kill impact | `enemy_killed` | DEFERRED | AudioStreamPlayer3D.play (critère b) |
| **VFX flash blanc ColorRect** | **`enemy_killed`** | **SYNC (exemption r2)** | **Toggle bool + Tween existant — Pillar 1 frame-précis** |
| **Combat `_on_player_died` (flag `_death_pending`)** | **`died`** | **SYNC (exemption r2)** | **Mecanisme Rule 17 Hybrid — flag avant resolution colliders, Pillar 3 mutual kill** |

### D-6 — Ordre d'émission intra-tick : transition-sortie avant transition-entrée, `died` terminal

Quand plusieurs transitions d'état se produisent dans le même `_physics_process` tick, l'ordre d'émission est **déterministe** et documenté :

**Règle 1 — Sortie de l'état courant avant entrée du nouvel état.**
- Dashing → Grounded : `dash_ended` émis puis rien (pas de `grounded_entered` au MVP).
- Dashing → Dead : `dash_ended` émis puis `died` émis. `dash_timer` reset avant emit `died`.
- WallRunning → Airborne (via wall-jump) : `wall_run_exited` puis `wall_jumped`.
- WallRunning → Dead : `wall_run_exited` puis `died`.

**Règle 2 — `died` est terminal.** Aucun signal Movement (hors `respawned`) n'est émis après `died` dans le même tick ni dans les ticks suivants jusqu'à `respawn()`. `die()` early return idempotent garantit l'unicité (AC-MV-41).

**Règle 3 — `respawned` fait le reset implicite.** Aucun signal `grounded_entered` n'est émis au respawn (entrée implicite dans l'état Grounded post-respawn). Les consumers qui veulent savoir « je suis vivant et au sol » lisent `player.state == State.GROUNDED` après avoir reçu `respawned`.

**Règle 4 — `attacked` est forward sans interférer avec l'état Movement.** `attacked` est juste un forward du `was_pressed_this_tick(&"attack")` ; il peut être émis dans n'importe quel état Movement (Grounded, Airborne, Dashing, WallRunning — pas Dead). Ordre vis-à-vis des autres signals du tick : émis **après** toute transition d'état (en fin de `_physics_process`).

### D-7 — Consumer contract : interdiction de muter l'état Movement depuis un signal handler

Un callback signal Movement **ne doit JAMAIS** :
- Écrire sur `player.velocity`, `player.position`, `player.rotation`.
- Appeler `player.die()`, `player.respawn()`, `player.set_checkpoint()` (sauf Checkpoint System qui a cette responsabilité explicite via appel direct, pas signal).
- Appeler `player._state = ...` (`_state` est private, pas accessible hors classe — enforce par godot-specialist F7 pattern `get:` read-only).
- Muter `movement_tuning.tres` runtime.

**Autorisé** : lire `player.state`, `player.velocity`, `player.wall_normal`, `player.dash_cooldown_ratio`, etc. (read-only properties exposées par GDD l. 112–122).

**Enforcement** : forbidden_pattern `mutate_movement_state_from_signal_handler` enregistré au registry. Lint grep pour `player.velocity =`, `player.die()`, `player._state` dans les handlers des consumers. Contrôlé en code review.

### D-8 — Idempotence par transition d'état

Symétrie généralisée de l'AC-MV-41 (`died` émis exactement 1× par transition) :

- `dash_started` émis **une seule fois** par transition `* → Dashing`. Re-emit pendant Dashing = bug.
- `wall_run_entered` émis **une seule fois** par transition `Airborne → WallRunning`. Wall contact changes (différent mur, raycast perd contact puis retrouve) DANS le même état WallRunning = pas de re-emit.
- `wall_jumped` émis **une seule fois** par jump (ne se re-emit pas si le joueur garde `jump` pressed).
- `attacked` peut être émis plusieurs fois par tick ? **Non** — `was_pressed_this_tick` ADR-0004 D-1 garantit true une seule fois par edge press. Max 1 `attacked` par tick.

**Implémentation prescrite** : chaque transition met à jour `_state` **avant** l'`emit`. La state machine n'émet le signal d'entrée d'un état que si `_state != new_state` avant assignment. Les guards `if _state == NEW: return` sont déjà dans le code pattern (cf. `die()` early return).

### D-9 — Zero-alloc signal dispatch

Corollaire de D-3 (payloads typés value) et Pillar 1. Pas de construction d'objet au moment de l'`emit` :

- **Interdit** : `emit_signal("dash_started", {dir = dash_dir, speed = DASH_SPEED})` — Dict literal alloc.
- **Interdit** : `dash_started.emit(Vector3(x, y, z), DASH_SPEED)` si les composantes sont calculées par une méthode qui elle-même construit une sortie. Par contre, `Vector3(x, y, z)` inline avec primitives = value type = zero-alloc.
- **Autorisé** : `dash_started.emit(dash_dir, dash_speed)` où `dash_dir: Vector3` est une variable membre ou locale Vector3 (value type contigu stack-allocated en GDScript).

**Test GUT obligatoire** : `tests/performance/movement_signals_zero_alloc_test.gd` — GIVEN scène test MovementController + 3 consumers attachés. WHEN 1000 `dash_started.emit()` + 1000 `wall_jumped.emit()` sur 60 s. THEN `Performance.get_monitor(MEMORY_STATIC)` delta < 64 KB (marge GC identique à ADR-0004 VC-3).

### D-10 — Dependency direction : MovementController = outbound-only events, zero knowledge of consumers

Le fichier `src/core/movement_controller.gd` (ou équivalent à l'implémentation) **NE DOIT référencer** :
- Aucun class name consommateur (`CameraSystem`, `CombatSystem`, `VFXManager`, `AudioManager`, `HUD`).
- Aucun `$NodePath` vers un système consommateur (`$Camera/CameraArm`).
- Aucun `get_node("/root/...")` vers un autoload consommateur.
- Aucun `preload("res://src/gameplay/camera.gd")`.

Les consumers font la connexion **depuis leur propre `_ready()`** :
```gdscript
# In camera_system.gd (child of Player):
func _ready() -> void:
    var player := get_parent() as CharacterBody3D
    player.wall_run_entered.connect(_on_wall_run_entered, CONNECT_DEFERRED)
    player.dash_started.connect(_on_dash_started)  # sync — just FOV lerp target
```

**Enforcement** : lint grep sur `src/core/movement_controller.gd` (ou futur path) pour bannir les patterns ci-dessus. AC CI-runnable.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  INPUT LAYER (Foundation — ADR-0004)                         │
│  InputManager                                                │
│   ├─ was_pressed_this_tick(&"jump") ─────┐                   │
│   ├─ was_pressed_this_tick(&"dash") ─────┤                   │
│   ├─ was_pressed_this_tick(&"attack") ───┤                   │
│   └─ mouse_motion(delta)                 │                   │
└───────────────────────────────────────────┼──────────────────┘
                                            │ (polling depuis _physics_process)
                                            ▼
┌─────────────────────────────────────────────────────────────┐
│  MOVEMENT LAYER (Core — ADR-0005)                            │
│  MovementController (CharacterBody3D) [_physics_process]     │
│                                                              │
│  Internal state machine: Grounded|Airborne|Dashing|          │
│                          WallRunning|Dead                    │
│                                                              │
│  Outbound signals (ZERO references to consumers):            │
│   ├─ dash_started(dir, speed)     ┐                          │
│   ├─ dash_ended()                 │                          │
│   ├─ wall_run_entered(normal)     │                          │
│   ├─ wall_run_exited()            │  ← emit depuis           │
│   ├─ wall_jumped(normal, vel)     │    _physics_process only │
│   ├─ died()                       │    (ADR-0001 authority)  │
│   ├─ respawned(spawn_pos)         │                          │
│   └─ attacked()                   ┘                          │
└─────┬──────────┬─────────┬─────────┬─────────┬──────────────┘
      │          │         │         │         │
      │ connect  │ connect │ connect │ connect │ connect
      ▼          ▼         ▼         ▼         ▼
┌──────────┐ ┌────────┐ ┌─────┐  ┌──────┐  ┌─────────┐
│ Camera   │ │Combat  │ │ VFX │  │Audio │  │ HUD     │
│(Core)    │ │(Core)  │ │(Core)│ │(Core)│  │(Feature)│
│ sync     │ │ sync   │ │ DEF  │ │ DEF  │  │ sync    │
└──────────┘ └────────┘ └─────┘  └──────┘  └─────────┘
 FOV kick    Hitbox     Trails   SFX       Dash cd UI
 overlay     swept      Fondus   Whoosh    Death overlay
 Tilt        on         Sparks   Foot-     toggle
 wall-run    attacked            steps
```

Direction des flèches = flux d'événements. **Aucune flèche retour** vers MovementController depuis les consumers (contrat REQ-5/D-10).

### Key Interfaces

| Interface | Owner | Consumers | Pattern | Semantics |
|-----------|-------|-----------|---------|-----------|
| `signal dash_started(dash_dir: Vector3, dash_speed: float)` | MovementController | Camera (sync FOV), VFX (deferred trail), Audio (deferred whoosh) | signal | Émis 1× à la transition `* → Dashing`. `dash_dir` normalisé, horizontal. `dash_speed` = DASH_SPEED courant. |
| `signal dash_ended()` | MovementController | VFX (deferred stop trail), Audio (deferred tail) | signal | Émis 1× à la transition `Dashing → *`. Aucun payload (consumers lisent `player.state` pour savoir où on va). |
| `signal wall_run_entered(wall_normal: Vector3)` | MovementController | Camera (sync tilt cible), VFX (deferred sparks), Audio (deferred loop start) | signal | Émis 1× à la transition `Airborne → WallRunning`. `wall_normal` = normale du mur (direction opposée à la surface). |
| `signal wall_run_exited()` | MovementController | Camera (sync tilt retour zéro), VFX (deferred stop sparks), Audio (deferred loop stop) | signal | Émis 1× à la transition `WallRunning → *`. |
| `signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)` | MovementController | Camera (sync shake kick 0.05 rad), VFX (deferred burst), Audio (deferred whoosh) | signal | Émis 1× lors du wall-jump. `launch_velocity` = vélocité résultante post-jump. |
| `signal died()` | MovementController | Camera (sync overlay rouge), VFX (deferred fondu), Audio (deferred death stinger), HUD (sync death UI toggle) | signal | Émis 1× par mort (idempotent AC-MV-41). `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE` obligatoire pour que deferred consumers reçoivent avant `respawn()`. |
| `signal respawned(spawn_position: Vector3)` | MovementController | Camera (sync reset pitch/roll/fov, yaw préservé cf. Camera GDD), VFX (deferred flash blanc), HUD (sync reset) | signal | Émis 1× par respawn. `spawn_position` = `checkpoint.position`. |
| `signal attacked()` | MovementController | Combat (sync trigger swept hitbox) | signal | Forward de `was_pressed_this_tick(&"attack")`. Émis depuis `_physics_process` du Movement **après** la state machine (fin de tick). Peut être émis dans tous les états sauf Dead. |

## Alternatives Considered

### Alternative 1 : EventBus autoload `MovementEvents`

- **Description** : Créer un autoload `MovementEvents` (singleton global) qui porte les 8 signals. MovementController appelle `MovementEvents.dash_started.emit(...)` au lieu de `self.dash_started.emit(...)`. Consumers se connectent à `MovementEvents.dash_started.connect(...)`.
- **Pros** :
  - Découple formellement l'émetteur du receiver (consumer n'a pas besoin de référence au Player node).
  - Robust à la destruction/recréation du Player (respawn recrée pas le Player, mais si on le faisait un jour, les connexions survivent).
  - Pattern familier aux devs venant d'Unity (C# events) / C++ signal frameworks.
- **Cons** :
  - **Ajoute un autoload** au projet — multiplie le nombre de dépendances au bootstrap. Ordre autoload à maintenir (InputManager avant MovementEvents avant autres).
  - **Double dispatch** : l'emit va à MovementEvents qui re-dispatch aux consumers. Coût CPU ~1.5× signal normal. Mesurable au MVP à 8 signals × 60 Hz × 3–6 consumers = 1440–2880 dispatches/s.
  - **Aggregation prématurée** : si plus tard on a 2 Players (coop local), les signaux des 2 joueurs se mélangent dans MovementEvents. Il faudrait ajouter `player_id` en payload — changement d'API rétroactif. Single-player MVP ne voit pas le problème mais le design se bloque.
  - **Coupling caché** : les consumers paraissent découplés mais dépendent d'un autoload global — c'est juste un coupling déplacé vers un shared singleton. Plus dur à tester unitairement (le test doit bootstrap l'autoload).
  - **Violation du principe** « un système ne référence que ses dépendances amont déclarées » : MovementEvents n'est ni amont ni aval, c'est un intermediary parasite.
- **Rejection Reason** : les pros (découplage) ne matérialisent pas un bénéfice réel pour un MVP single-player avec un Player node unique à la fois. Les cons (autoload overhead, aggregation prématurée, test friction) sont tous concrets. Le pattern direct typed signals sur MovementController est idiomatique Godot, déjà utilisé par ADR-0004 pour InputManager (c'est un autoload mais avec discipline one-way Foundation pur — pas un EventBus intermédiaire). Cohérence cross-ADR préférée.

### Alternative 2 : Sub-node dédié `MovementEventEmitter` child du Player

- **Description** : Créer un Node3D child du CharacterBody3D qui porte les 8 signals. MovementController appelle `$MovementEventEmitter.dash_started.emit(...)`. Consumers se connectent à `player.get_node("MovementEventEmitter").dash_started.connect(...)` ou via `@onready var emitter := $MovementEventEmitter`.
- **Pros** :
  - Clarification visuelle dans le scene tree : le dev voit un node dédié events.
  - Si MovementController devient un GDScript lourd (> 500 lignes), sépare l'API signals du code state machine.
- **Cons** :
  - **Indirection inutile** pour 8 signals. Un script bien organisé avec section `# ─── Signals ─── ` atteint la même clarté sans ajouter de node.
  - **Overhead get_node()** côté consumer à chaque connect (1× au `_ready`, négligeable mais ajouté sans raison).
  - **Pattern non-idiomatique Godot** : les signals sont attendus sur le node qui **porte** le state (CharacterBody3D, Control, etc.), pas sur un intermediary sibling. Un dev nouveau cherchera `player.dash_started` en premier et sera surpris de ne pas la trouver.
  - **Symétrie rompue** avec ADR-0004 : InputManager émet ses signals directement (pas de `$InputEventEmitter`), donc Movement devrait faire pareil.
- **Rejection Reason** : ajoute de la surface sans bénéfice. Le MovementController restera probablement sous 400 lignes au MVP (state machine simple 5 états + 8 signals). Si la taille explose post-MVP (combat avancé, grapple, etc.), on pourra extract en refactor ciblé — YAGNI maintenant.

### Alternative 3 : Messenger pattern typé via classe helper `MovementEventDispatcher`

- **Description** : Créer une classe GDScript `MovementEventDispatcher` avec méthodes typées `emit_dash_started(dir: Vector3, speed: float)` etc. MovementController possède une instance, les consumers s'abonnent via une API custom `dispatcher.subscribe_dash_started(callable: Callable)`.
- **Pros** :
  - Validation statique des signatures plus stricte que les signals Godot (compile-time en GDScript typé).
  - Pattern testable sans scene tree (la classe peut être instanciée en unit test isolé).
- **Cons** :
  - **Non-idiomatique GDScript** : réinvente le système de signals Godot. Perd les outils natifs (`CONNECT_DEFERRED`, `disconnect`, inspection dans l'éditeur, async `await signal`).
  - **Typed signals Godot 4.x** atteignent déjà la validation en debug build (REQ-1). Un test de contrat (D-3) couvre le reste.
  - **Boilerplate** : 8 méthodes `subscribe_*` + 8 méthodes `unsubscribe_*` + 8 arrays de Callables + gestion manuelle `tree_exited` cleanup. 150+ lignes pour reimplémenter ce que Godot livre nativement en 8 lignes.
- **Rejection Reason** : réinvente la roue Godot. Le bénéfice (validation statique) est atteint par typed signals + test de contrat.

### Alternative 4 : Signals typés + EventBus hybride (signals directs pour gameplay-critical, EventBus pour observer)

- **Description** : Signals directs pour les 4 signaux temps-critique (`dash_started`, `wall_run_entered`, `wall_jumped`, `died`) ; EventBus autoload pour les 4 signaux non-critique (`dash_ended`, `wall_run_exited`, `respawned`, `attacked`) afin qu'un futur telemetry / analytics système puisse les écouter sans toucher au Player.
- **Pros** : hybride théoriquement adapté au besoin de chaque signal.
- **Cons** :
  - **Split cognitif** : les devs doivent mémoriser quels signals sont où. Source de bug classique.
  - **Analytics-first design** : on n'a pas de système analytics MVP. Optimisation prématurée.
  - **Cohérence de l'API** : un pattern unique pour un même système est plus simple à apprendre qu'un mix.
- **Rejection Reason** : complexité conceptuelle sans bénéfice MVP. Si un analytics tier 3 émerge, il connecte directement aux signals Player comme les autres consumers (ou passe par un observer wrapper dédié).

## Consequences

### Positive

- **G-1 résolu** : les 9 consommateurs cross-system (Camera, Combat, VFX, Audio, HUD, 4 futurs) ont un contrat architectural stable. Plus de re-review GDD pour ce point.
- **Cohérence cross-ADR** : même pattern que ADR-0004 (InputManager émet ses propres signals directement, consumers connectent). Pattern réplicable pour ADRs futurs Combat / Camera / Enemy.
- **Zero-alloc mesurable** : D-9 + test GUT rendent le respect de Pillar 1 prouvable. AC `zero_alloc_test` à ajouter au GDD Movement passera post-implementation.
- **Ordre déterministe** : D-6 rend les AC cross-state predictables. `test_die_during_dash_emits_both_in_order` est un test écrivable.
- **Pas d'autoload ajouté** : bootstrap projet inchangé. Pas de dépendance supplémentaire MovementEvents singleton.
- **Testability** : MovementController peut être instancié dans un test GUT sans autoload MovementEvents (les signals sont internes).
- **Scale linéaire** : ajouter un consumer ne coûte pas un 2e fichier — il connecte directement au Player node qu'il reçoit déjà par scene tree ou injection.

### Negative

- **Couplage N:1** inhérent au pattern direct : si un jour on ajoute un 2e Player (coop), chaque consumer devra connecter aux deux Player nodes séparément. Scope hors MVP — si coop introduit en Tier 2+, refactor possible vers EventBus à ce moment-là (Alternative 1 peut être reconsidérée).
- **Scene tree dependence** : les consumers doivent avoir une référence au Player pour se connecter (via `$Player`, `get_parent()`, ou injection). Pas un problème architectural (scene tree est le pattern de composition Godot), mais nécessite discipline dans les scenes (.tscn).
- **Debug build strictness only** : typed signal mismatches silencieux en release (REQ-1). Mitigé par test de contrat obligatoire (D-3) qui tourne en CI debug build.
- **Documentation inline requise** : le MovementController.gd doit avoir un header commentaire listant les 8 signals + leur contrat exact. Sans ça, un dev ajoutera un 9e signal « discrètement » et déclenchera un drift GDD. Enforce via template + review.
- **Ajout d'un signal = amendement ADR** (D-2 reserved list) — coût process par signal (~15 min amendement). Jugé acceptable vs coût d'un drift silencieux.

### Risks

- **Risk 1 — Typed signal strictness absente en release** : un consumer shippé avec mauvaise signature passe silencieusement. → **Mitigation** : test de contrat (D-3) obligatoire en CI debug, `push_error` sur mismatch déclenche fail. Pas de release sans CI debug passing.
- **Risk 2 — Ordre d'émission non déterministe si state machine refactorée** : un dev qui refactor la state machine peut inverser l'ordre `dash_ended` / `died` sans s'en rendre compte. → **Mitigation** : AC GUT dédié `test_movement_signal_emit_order_die_during_dash` avec assertion sur l'ordre (capture timestamps de callbacks). Sans cet AC, D-6 est une règle morte.
- **Risk 3 — `CONNECT_DEFERRED` drift** : un dev applique `CONNECT_DEFERRED` sur tous les consumers « par précaution » et introduit 1 frame de latence cascadée sur tout le feedback visuel, ce qui viole Pillar 1. → **Mitigation** : D-5 table de référence dans le Control Manifest (quand créé). Lint sur patterns `CONNECT_DEFERRED` dans handlers qui ne matchent pas les critères (a)(b)(c)(d). Explicit check en code review.
- **Risk 4 — Consumer mute l'état Movement (REQ-6 violation)** : un VFX handler appelle `player.die()` pour tester « feedback de mort » en debug et oublie de retirer le code. → **Mitigation** : `die()` idempotent (AC-MV-41) limite les dégâts. Forbidden pattern registry + grep lint attrape les violations structurelles.
- **Risk 5 — Multi-tick transition edge case** : un `die()` pendant la même frame qu'un `respawn()` non encore exécuté (edge case extreme). → **Mitigation** : l'invariant `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE` (50 ms ≫ 16.6 ms min) garantit que `respawn` ne peut pas être dans le même tick que `die`. GDD Edge Case l. 305 documente déjà idempotence.
- **Risk 6 — Signal emit depuis `_process` par accident** : un dev ajoute un feedback visuel qui émet un signal Movement depuis `_process` « pour plus de fluidité ». Viole D-4. → **Mitigation** : forbidden_pattern `emit_movement_signal_from_process` au registry + lint grep.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/player-movement-system.md` l. 82–91 (Published API — signals) | Liste des 8 signals avec payloads typés | Formalise la liste canonique (D-2), gèle les signatures (D-3), impose le contrat typed strictness test (REQ-1). |
| `design/gdd/player-movement-system.md` l. 74 (VFX listener sur signals) | « Connexions recommandées CONNECT_DEFERRED pour éviter burst CPU synchrones » | Transforme recommandation en règle codée (D-5) avec critères (a)(b)(c)(d). |
| `design/gdd/player-movement-system.md` l. 94 (typed signals Godot 4.x debug-only check) | godot-specialist F5 : mismatches silencieux release | Oblige test de contrat GUT (D-3) pour attraper en CI debug. |
| `design/gdd/player-movement-system.md` l. 96 (CONNECT_DEFERRED nuancé r3 : lourd vs light) | Règle verbale « lourd = deferred, light = sync » | Formalise critères objectifs (D-5). |
| `design/gdd/player-movement-system.md` l. 300 (RESPAWN_DELAY vs consumers CONNECT_DEFERRED) | Invariant `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE` | Reconfirmé comme contrainte liée à D-5 (deferred consumers de `died`). |
| `design/gdd/player-movement-system.md` AC-MV-41 (idempotence `died` signal) | Early return en `die()` | Généralise le pattern d'idempotence à tous les signals d'entrée d'état (D-8). Nouveaux ACs symétriques à ajouter au GDD post-Accepted : `AC-MV-XX dash_started émis exactement 1× par transition * → Dashing`. |
| `design/gdd/player-movement-system.md` l. 619 (PENDING ADR architecture signaux Movement) | « Technical-director arbitrage. À lever avant Sprint 1 » | Lève le PENDING — ADR-0005 = réponse directe. GDD l. 619 à marquer RÉSOLU par ADR-0005 post-Accepted. |
| `design/gdd/camera-system.md` (consumer) | Tilt wall-run cible ≤ 200 ms via `camera_effects.rotation.z` | Confirme que Camera consomme `wall_run_entered(wall_normal)` en **connexion synchrone** (lerp target var = light). D-5 compatible. |
| `design/gdd/camera-system.md` (consumer) | FOV kick dash | Confirme consommation `dash_started(dir, speed)` synchrone (lerp FOV target). |
| `design/gdd/camera-system.md` (consumer) | Overlay rouge respawn | Confirme consommation `died()` synchrone (overlay toggle) + `respawned(pos)` synchrone (reset state). |
| `design/gdd/input-system.md` (amont) | `was_pressed_this_tick(&"attack")` polling | Movement forward en `attacked` signal (D-2). Pattern cohérent ADR-0004. |
| `design/gdd/game-concept.md` Pillar 1 (FLOW AVANT TOUT) | Latence input→réponse ≤ 1 frame perçue | D-9 zero-alloc + D-5 sync pour consumers critiques garantit pas de cascade de latence frame. |
| `docs/architecture/adr-0001-physics-rate-60hz.md` | Autorité gameplay `_physics_process` unique | D-4 aligné : emissions signal uniquement depuis `_physics_process`. |
| `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` | Scene tree Camera consomme Movement | D-10 direction unidirectionnelle Movement → Camera confirme. |
| `docs/architecture/adr-0004-input-api-focus-handling.md` | Pattern signals directs sur InputManager | D-1 réplique le même pattern pour MovementController — cohérence cross-ADR. |

## Performance Implications

- **CPU** :
  - Signal emit depuis `_physics_process` : 1 emit + N callback invocations (sync) ou N deferred queue entries. Coût mesuré Godot ~0.005 ms par emit avec 3 consumers sync typés. Pour 8 signals × fréquence max observée (1 dash/s + 1 wall-run/s + 1 mort/10s + 1 attaque/0.3s = ~5 emits/s peak gameplay), coût négligeable.
  - `attacked` forward à chaque tick si input pressed : max 60 Hz × 1 consumer Combat = 60 dispatches/s × 0.005 ms = 0.3 ms/s cumulé, soit 0.005 ms/frame amorti.
  - **Budget registry** : aucune allocation dédiée au movement-events seul — inclus dans le budget Movement global (Sprint 1 stub, à raffiner post-impl). Pas de nouvelle entrée `performance_budgets` nécessaire pour les events eux-mêmes.
- **Memory** : zero runtime growth (D-9). Chaque signal = overhead fixe Godot ~80 bytes pour l'array de Callables. 8 signals × 80 bytes = 640 bytes overhead fixe MovementController. Négligeable.
- **Load Time** : `_ready()` des consumers fait les `connect()` — chaque connect = 1 lookup + 1 push_back interne Godot array de Callables. 5 consumers × 4 signals moyens = 20 connects × ~5 µs = 100 µs au boot. Négligeable.
- **Network** : non applicable (MVP single-player).

## Migration Plan

- **Code** : aucun code dans `src/core/` ni `src/gameplay/` n'existe encore. Pas de migration. L'implémentation v1 de `src/core/movement_controller.gd` (ou `src/gameplay/player_movement_controller.gd` — path à fixer au Sprint 1) sera construite directement selon ce ADR.
- **Prototype `prototypes/movement-katana/`** : le prototype implémente déjà les signals de manière inline mais non exhaustive (cf. REPORT.md Lessons Learned). Non affecté — remplacé par l'implémentation MVP propre au Sprint 1.
- **GDD `player-movement-system.md`** : 3 petits ajouts post-Accepted :
  1. Dans « Published API » (l. 82–91) : ajouter commentaire header `# Canonical list per ADR-0005 (D-2). Ajout d'un signal = amendement ADR-0005.`.
  2. Dans « Interactions with Other Systems » (l. 74) : transformer « Connexions recommandées : CONNECT_DEFERRED » en « Connection mode per ADR-0005 D-5 — see table ».
  3. Dans « Progress list » (l. 619) : marquer « 3. **ADR — Architecture signaux Movement** » comme **RÉSOLU par ADR-0005**.
  4. ACs post-Accepted à ajouter au GDD : `AC-MV-XX dash_started émis exactement 1× par transition * → Dashing` (symétrie AC-MV-41), `AC-MV-YY wall_run_entered idem`, `AC-MV-ZZ dash_ended précède died si die() pendant Dashing` (D-6 ordre). Effort ~30 min.
- **GDD `camera-system.md`** : confirmer dans « Dependencies » que la connection mode aux signals Movement suit ADR-0005 D-5 (tilt = sync, overlay rouge = sync, etc.). 1 ligne de référence croisée. ~5 min.
- **Registry `docs/registry/architecture.yaml`** : nouvelles entrées (détail Step 6 du skill) — 1 state_ownership, 8 interfaces (1 contrat par signal ou 1 contrat groupé `movement_events` selon granularité), 1 api_decision `movement_intra_gameplay_event_pattern`, 3 forbidden_patterns.
- **Control Manifest** (phase ultérieure, pas encore créé) : ajouter :
  - REQUIRED : signals Movement émis uniquement depuis `_physics_process` ; test contrat typed signatures en CI debug ; CONNECT_DEFERRED pour consumers lourds.
  - FORBIDDEN : EventBus autoload pour intra-gameplay Movement events ; mutation d'état Movement depuis signal handler ; Dictionary literal en signal payload ; référence à class/path consumer depuis MovementController.
  - GUARDRAIL : ajout d'un signal = amendement ADR-0005 (pas de drift silencieux).
- **Session state** : marquer `[x]` sur ADR-0005 + déclarer next task = « Edit ADR-0001 migration plan pour append `default_gravity=0` (G-3) + transition Proposed→Accepted des 5 ADRs ».

## Validation Criteria

- **VC-1 (Typed signal contract test — debug CI blocking)** : `tests/integration/movement/test_movement_signals_typed_contract.gd` — GIVEN debug build + MovementController instanciée. WHEN consumer connecte un Callable avec signature incorrecte (e.g. `func(dir: Vector3)` au lieu de `func(dir: Vector3, speed: float)`). THEN `push_error` déclenché, test `expect_error` passe. Si connexion accepte silencieusement, test fail et release block.
- **VC-2 (Zero-alloc signal dispatch)** : `tests/performance/movement_signals_zero_alloc_test.gd` — GIVEN MovementController + 3 consumers attachés. WHEN 1000 emissions `dash_started` + 1000 `wall_jumped` + 1000 `attacked` sur 60 s. THEN `Performance.get_monitor(MEMORY_STATIC)` delta < 64 KB (marge GC).
- **VC-3 (Ordre d'émission intra-tick — die during dash)** : `tests/integration/movement/test_signal_order_die_during_dash.gd` — GIVEN MovementController en état Dashing, un consumer stub qui capture timestamps de callbacks. WHEN `player.die()` appelé au tick N pendant Dashing. THEN consumer reçoit `dash_ended` puis `died` dans cet ordre, timestamps croissants (ou égaux au µs près), AVANT fin de `_physics_process` tick N.
- **VC-4 (Idempotence entry signals)** : `tests/integration/movement/test_state_entry_signals_idempotent.gd` — GIVEN Player en Airborne approche d'un mur. WHEN la state machine entre en WallRunning, reste 0.5 s, sort, re-entre (raycast perd contact puis retrouve). THEN `wall_run_entered` émis exactement 2× (1 par entrée réelle), pas 3 ou plus.
- **VC-5 (Lint Movement outbound-only)** : `tests/static/movement_no_consumer_references_test.gd` ou script lint `.claude/rules/movement-no-consumer-refs.md` — GIVEN parse de `src/core/movement_controller.gd`. WHEN grep pour class names consumers (`CameraSystem`, `CombatSystem`, `VFXManager`, `AudioManager`, `HUD`, `HUDController`), `get_node("/root/` paths vers systèmes aval, `preload("res://src/gameplay/camera.gd")`, etc. THEN zéro match.
- **VC-6 (Lint no-emit-from-_process)** : `.claude/rules/movement-emit-physics-only.md` — scan pour `<signal_name>.emit(` à l'intérieur de `func _process(` dans `movement_controller.gd`. THEN zéro match.
- **VC-7 (RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE invariant assertion)** : runtime `assert(RESPAWN_DELAY_MS >= 1000.0 / DISPLAY_TICK_RATE)` au `_ready()` de MovementController. Déjà invariant GDD l. 355 — ici rendu runtime-enforceable pour éviter configuration silencieuse invalide.
- **VC-8 (Benchmark signal dispatch cumulé)** : `tests/performance/movement_signals_dispatch_bench.gd` — GIVEN scène stress (simule 60 dashs + 60 wall-runs + 60 attacks sur 60 s). THEN coût CPU cumulé des signal emits + callbacks sync + deferred queue ≤ 0.1 ms/frame amorti (marge 4× par rapport aux 0.025 ms/frame mesurés théoriquement).

Si VC-1 échoue → problème de typed signal strictness Godot 4.6 à investiguer (possible régression post-4.3). ADR re-ouvert avec fallback test runtime type introspection explicite.
Si VC-2 échoue → investiguer quel signal/payload alloue. Les 4 alternatives sont : (a) corriger le call site, (b) pré-allouer un pool de Vector3 (non idiomatique), (c) replier le signal incriminé sur un getter property (`player.last_dash_dir`) au lieu de payload (régression API), (d) accepter l'alloc si < 64 KB delta.
Si VC-3 échoue → refactor state machine pour centraliser les emissions en fin de `_physics_process`, pas au moment exact de la transition d'état. Plus de code mais plus prévisible.
Les autres VC échouant → fix implémentation, pas de rollback ADR.

## Related Decisions

- **ADR-0001 (Physics Rate 60 Hz + Jolt)** — Amont direct. D-4 (emit depuis `_physics_process`) applique l'autorité gameplay posée par ADR-0001.
- **ADR-0002 (Camera Scene Tree CameraArm)** — Complémentaire. Camera est le 1er consumer critique des signals Movement (wall_run_entered, dash_started, died, respawned). D-5 + ownership CameraArm/CameraEffects par étage sont compatibles par construction.
- **ADR-0003 (Rendering & Display Latency)** — Indirect. Le chemin des signals côté intra-engine est zero-alloc par D-9, n'affecte pas le rendering budget.
- **ADR-0004 (Input API & Focus Handling)** — Pattern de référence (InputManager émet `mouse_motion`, `application_focus_lost/gained` via signals directs). D-1 Movement = réplique du pattern. `attacked` signal est un forward direct de `was_pressed_this_tick(&"attack")` d'ADR-0004.
- **Futur ADR Combat** — Consumer principal de `attacked`. Devra documenter que la swept hitbox est déclenchée sync (D-5 light pattern).
- **Futur ADR Audio** — Consumer de tous les 8 signals. Devra documenter que `AudioStreamPlayer.play()` dans handler déclenche `CONNECT_DEFERRED` (D-5 critère (b)).
- **Futur ADR VFX** — Consumer GPUParticles. `CONNECT_DEFERRED` (D-5 critère (a)).
- **Futur ADR Save/Load Settings** (G-2) — non directement lié. Le lifecycle `movement_tuning.tres` est orthogonal aux signals runtime.
- **Futur `.claude/rules/movement-no-consumer-refs.md`** — lint qui enforce D-10 (VC-5).
- **Futur `.claude/rules/movement-emit-physics-only.md`** — lint qui enforce D-4 (VC-6).

---

*Auteur : Architecture Decision skill, 2026-04-21*
*Source directe : `/architecture-review` 2026-04-21 Gap G-1 HIGH (ADR-0005 Movement Signals Architecture à créer). GDD Movement r3 l. 619 PENDING ADR marker. godot-specialist F5 review r3 Movement (dilemme direct signals vs EventBus).*
*Mode review : solo (TD-ADR gate skipped, engine-specialist gate skipped — à valider en fresh session via `/architecture-review` indépendant avant Accepted, identique protocole ADR-0001..0004).*
