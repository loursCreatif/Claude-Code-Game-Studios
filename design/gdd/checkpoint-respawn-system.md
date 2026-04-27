# Checkpoint & Respawn System

> **Status** : In Design (skeleton 2026-04-27 — Sprint A VS Backbone, solo auto-approve)
> **Author** : Martin + game-designer (via /design-system checkpoint-respawn-system, solo auto-approve)
> **Last Updated** : 2026-04-27
> **Implements Pillar** : Pillar 3 (UNE SECONDE CHANCE N'EST JAMAIS LOIN — primaire) + Pillar 1 (FLOW AVANT TOUT — la mort est une note staccato, pas un break)

## Summary

Le **Checkpoint & Respawn System** orchestre la promesse Pillar 3 : *« UNE SECONDE CHANCE N'EST JAMAIS LOIN »*. Quand le joueur meurt, ce système coordonne — en moins d'une seconde — la transition `Movement.died → GSM.RESPAWNING → snapshot Enemy/Level state restore → Movement.respawn(active_anchor_position) → GSM.PLAYING`. Les **CheckpointVolume Area3D** (placés dans la scène d'étage par Level System) latchent l'« anchor de respawn courant » au passage du joueur ; à la mort, le système remet le Player à cet anchor, restaure l'état des grunts au snapshot pris au passage du checkpoint, et rend l'input < 50 ms après la mort. Au MVP, 3-5 checkpoints par étage de 8-10 salles (Level Formula 3 — `CHECKPOINT_SPACING ∈ [2, 3]` rooms). Pas de save game, pas de cloud sync, pas de menu reload — la mort est une **continuation latérale**, pas une rupture.

## Overview

Le Checkpoint & Respawn System est l'**infrastructure invisible** du Pillar 3. Du point de vue *technique*, il est un coordinateur léger autoload (ou Service-Locator pattern, OQ-CHK-1) qui :

1. **Écoute** le signal `LevelSystem.level_active(etage_id, player_start)` au boot d'étage et lit `LevelSystem.get_checkpoint_slots() -> Array[CheckpointSlot]` pour câbler ses Area3D.
2. **Latche** le `CheckpointAnchor` actif via `body_entered` Area3D : chaque CheckpointVolume traversé devient le nouveau respawn point (latch monotone — ne régresse jamais en arrière).
3. **Capture un snapshot** de l'état des `Grunt.is_dead()` à chaque latch (Enemy GDD Rule 13 + AC-ENM-16/17).
4. **Pull** au signal `Player.died` : déclenche le pipeline RESPAWNING orchestré avec GSM (ADR-0007 D-7 + GSM Rule 5), attend `RESPAWN_DELAY = 0.05 s` wall-clock, puis appelle `Movement.respawn(active_anchor_position)` + restaure les snapshots Enemy.
5. **Reset** au signal `LevelSystem.level_active` (nouveau étage) ou `GSM.request_new_run()` : tous les checkpoints sont déactivés, les snapshots vidés, le PlayerStart Marker devient l'anchor effectif initial.

Du point de vue *player-facing*, le système n'a **aucune surface UI directe** — pas de message « checkpoint reached », pas de loading screen, pas de pause forcée. Le joueur **comprend** par la spatialité : il traverse une zone, voit subtilement (chime audio + brief glow VFX selon §Visual/Audio), et apprend qu'il y a là « un point de retour ». À la mort, l'écran fade rouge 40 ms (Movement-owned), un sound effect mortel 60-80 ms (Audio bus combat_kill ducking), puis fade-back blanc 40 ms et le joueur reprend contrôle au dernier checkpoint visité — *en moins de 200 ms wall-clock total*. Le système **ne sauvegarde pas la session** entre deux runs (les checkpoints sont volatils ; quitter l'étage = repartir du PlayerStart au prochain run). Le persistant entre runs est géré par le futur **Save/Load System** (Persistence layer, MVP — non couvert ici).

Le boss final reste **non-checkpointable** au sens classique : sa salle MVP-post (Tier 3) aura un seul checkpoint d'entrée — toute mort en boss fight te ramène avant le boss, pas au milieu. Cette règle vit dans le futur Boss System GDD, pas ici.

> **Quick reference** — Layer: `Gameplay` · Priority: `MVP` · Key deps: `Player Movement (bidirectional, die/respawn), Game State Manager (state RESPAWNING + refcount), Level System (CheckpointVolume/Anchor markers), Enemy System (snapshot dead/alive)` · Consumed by: `Audio (respawn cue), VFX (fade overlay), HUD (checkpoint reached toast post-MVP)`

## Player Fantasy

> *« Mourir n'est pas perdre. C'est juste un battement de plus dans ma phrase de mouvement. Je relance avant même d'avoir eu le temps de soupirer. »*

**Émotion cible** : *invisibilité bienveillante du système*. Le meilleur compliment qu'un joueur peut faire au Checkpoint System est de **ne jamais penser à lui**. Aucune phrase « checkpoint atteint » glisse à l'écran ; aucun message « respawn... » ne ralentit le retour ; aucun bouton à appuyer pour redémarrer. La mort déclenche, l'écran fade rouge, le joueur sent un demi-souffle — et il est de nouveau debout, à 5 mètres de son point de mort, prêt à retenter. La phrase de mouvement avortée se rejoue **avant que la frustration ne s'installe**.

**Trois sensations ancrées par le système** :

1. **Sub-second recovery** (Pillar 3 + Pillar 1) : le délai total de mort à reprise contrôle est sous la seconde wall-clock — concrètement `RESPAWN_DELAY = 50 ms` + transition GSM ~16 ms + restoration snapshots ~16 ms = **~80 ms total inter-control**. Cette vitesse n'est pas un détail technique, c'est *la* signature du game feel. Référence : Hotline Miami (~150 ms), Super Meat Boy (~200 ms), Ghostrunner (~600 ms — déjà perçu comme « lent » par les pros). CHROME://ASCENT vise **plus vite que Hotline**.

2. **Préservation du progrès** (Pillar 3 forgiveness) : si le joueur a tué 3 grunts dans la salle, traversé un checkpoint, puis meurt 5 secondes plus tard — au respawn, **les 3 grunts restent morts** (Enemy snapshot Rule 13). Le respawn n'efface pas le travail accompli. Cette mécanique est **fondamentale** : elle dit au joueur *« ton skill compte ; je ne te punis pas pour mourir, je te remets sur les rails »*. La seule chose perdue est le *temps* écoulé entre le checkpoint et la mort — quelques secondes au pire.

3. **Spatialité du retour** (Pillar 1 lecture instantanée) : le joueur sait *où* il va respawn parce qu'il a *traversé* le checkpoint en marchant. Pas de menu, pas de map, pas de teleporteur abstrait — l'anchor de respawn est un point géographique de la salle qu'il vient de parcourir. À la mort, son cerveau prédit déjà l'angle de caméra du respawn, et la prédiction est correcte. C'est le contraire d'un **dark souls-like** où la mort fait pop un message « you died » + un cut au feu de camp lointain — ici, la continuité spatiale est **maximale**.

**Sensation par-dessus tout : « la mort m'enseigne, elle ne me punit pas »** (Pillar 3 mort pédagogique, partagé avec Enemy System AC-ENM-28)

Quand le joueur meurt par laser grunt, **le grunt qui l'a tué est encore là au respawn** (Enemy persistance Rule 13). Le checkpoint l'a remis à 5 mètres en arrière — il voit le même grunt, le même cône, et **comprend instantanément** ce qu'il avait raté. Pas de message « try again », pas de « You died. Press R to retry. » — juste la réalité spatiale du grunt qui était là tout du long. La boucle apprentissage-mort-respawn-apprentissage est **incarnée par le système Checkpoint**, qui orchestre cette continuité géographique.

**Référence jouable absolue** : **Hotline Miami** (Dennaton Games, 2012). Loop *die-retry < 1 s*, screen flash, rejoue de l'arène pré-mort (pas du jeu entier), aucun menu, aucun message. La sensation visée par CHROME://ASCENT est *exactement* celle-là, sans le 2D top-down : *la mort comme fast-forward au point d'évolution suivant*.

**Anti-fantasy explicit** :

- ❌ *Save & Quit fantasy* : pas de save manuel, pas de save slot, pas de cloud. Quitter l'étage = recommencer du début au next run. Le checkpoint est volatile entre runs.
- ❌ *Souls-like fantasy* : pas de « bloodstain » à récupérer, pas de monnaie perdue à la mort (le Credit Economy MVP ne perd rien à la mort — voir Credit GDD futur), pas de mort coûteuse en ressources. La mort est *gratuite* en termes de progrès.
- ❌ *Tutorial fantasy* : aucun « checkpoint reached » UI explicite au MVP. Le joueur découvre par les playtests que oui, traverser ce volume signifie quelque chose. Si le playtest montre que c'est trop subtil, on ajoute un VFX/audio léger, mais **jamais** un message texte.
- ❌ *Permadeath fantasy* : zéro lien avec roguelike. Mourir n'a aucun effet sur la prochaine session ; le seul état persistant entre sessions est dans Save/Load (upgrades achetés au shop).

## Detailed Rules

### Core Rules

1. **Architecture** — un autoload Godot unique `CheckpointSystem` (ou Service-Locator pattern via `LevelSystem.get_checkpoint_service()` — OQ-CHK-1, décision Sprint 1 ADR). Au MVP, autoload est privilégié pour symétrie avec GSM/AudioSystem/InputManager (foundation systems pattern). Pas de scene tree visible — pure data + signal coordinator.

2. **Scope MVP** : 1 étage = 3-5 CheckpointVolume + CheckpointAnchor pairs (Level Formula 3 — `checkpoint_count = ceil(N_rooms / CHECKPOINT_SPACING)` avec `N_rooms ∈ [8, 10]` et `CHECKPOINT_SPACING = 3` nominal → 4 checkpoints typiques). Pair indexée : `CheckpointVolume_NN` ↔ `CheckpointAnchor_NN` même `NN` (Level System R-5.2 naming convention).

3. **Boot d'étage** — au signal `LevelSystem.level_active(etage_id, player_start)`, le `CheckpointSystem._on_level_active` exécute :
   ```gdscript
   func _on_level_active(etage_id: int, player_start: Vector3) -> void:
       _active_anchor = player_start                       # PlayerStart Marker3D = anchor initial
       _active_checkpoint_id = -1                          # -1 = aucun checkpoint visité
       _enemy_snapshot.clear()                             # Empty dict (no kills yet)
       var slots: Array[CheckpointSlot] = LevelSystem.get_checkpoint_slots()
       for slot in slots:
           slot.volume.body_entered.connect(_on_checkpoint_entered.bind(slot))
       _state = State.IDLE
   ```
   - Le `PlayerStart` Marker3D (Level Rule R-2.4) est traité comme un **« checkpoint -1 »** : c'est l'anchor initial avant que le joueur n'ait visité aucun CheckpointVolume.
   - La `connect(_on_checkpoint_entered.bind(slot))` réplique le pattern Level System pour les Area3D triggers.

4. **Checkpoint activation (latch monotone)** — quand un `CheckpointVolume` Area3D fire `body_entered(body: Node3D)` ET `body.is_in_group("player")` :
   ```gdscript
   func _on_checkpoint_entered(body: Node3D, slot: CheckpointSlot) -> void:
       if slot.id <= _active_checkpoint_id:
           return                                          # Déjà visité ou checkpoint antérieur — no-op
       _active_checkpoint_id = slot.id
       _active_anchor = slot.anchor                        # Vector3 absolute
       _capture_enemy_snapshot()                           # foreach Enemy in scene → meta dead/alive
       checkpoint_activated.emit(slot.id, slot.anchor)     # Pour Audio/VFX/HUD consumers
   ```
   - **Latch monotone** : seul un checkpoint d'`id` strictement supérieur à `_active_checkpoint_id` peut prendre le relais. Cela rend le système robuste aux passages multiples (player traverse Volume_03 → Volume_02 → Volume_03 = reste à 03).
   - Ordre d'`id` figé level-time par numérotation `CheckpointVolume_01 < _02 < _03 < ...` (Level R-5.2 zero-padded).
   - **Aucun déclenchement multiple** sur le même checkpoint : la disconnect Area3D n'est pas requise (le guard `<= _active_checkpoint_id` suffit), ce qui garde la logique simple.

5. **Player.died handler** (souscrit au signal Movement-emitted `died(reason: String)` ADR-0005 D-2) :
   ```gdscript
   func _on_player_died(reason: String) -> void:
       if _state != State.IDLE:
           return                                          # Idempotent : double-died absorbé
       _state = State.RESPAWNING
       GameStateManager._on_player_died(reason)            # Notify GSM → state RESPAWNING
       InputManager.request_disable(&"GSMRespawning")      # Refcount disable (ADR-0004 D-4)
       _respawn_timer = 0.0                                # Reset wall-clock timer
   ```
   - **Idempotent** (Pattern aligné Movement F6, Enemy Rule 6) : un second `died` reçu pendant `RESPAWNING` est absorbé silencieusement.
   - GSM est **notifié** par le Checkpoint (pas inversé) — Checkpoint owns the respawn pipeline orchestration ; GSM owns the state transition (ADR-0007 D-7).
   - L'`Input.request_disable(&"GSMRespawning")` est nommé pour clarté (l'owner string est *tracé* dans les debug logs Input). Le matching `request_enable` est appelé en step 7 ci-dessous.

6. **Respawn delay countdown** — pendant `RESPAWNING`, le système compte le temps wall-clock écoulé via `_physics_process` :
   ```gdscript
   func _physics_process(delta: float) -> void:
       if _state != State.RESPAWNING:
           return
       _respawn_timer += delta                             # delta @ 60 Hz, time_scale-affected !
       if _respawn_timer >= RESPAWN_DELAY:
           _execute_respawn()
   ```
   - **Notice** : `delta` est **time_scale affected** (`Engine.time_scale = 0.3` pendant Combat slow-mo retire cinétiquement la durée perçue). Décision MVP : utiliser `delta` (= time_scale-affected) pour que la mort durant le slow-mo respecte la lenteur (50 ms wall-clock × 0.3 = 167 ms perçus). Cela simplifie l'intégration avec Combat Rule 13 slow-mo. **Si problème playtest** (e.g. respawn « semble se traîner » durant un kill final), pivoter vers `Time.get_ticks_msec()` wall-clock absolu — ajustement minor codebase.
   - **Pendant `tree.paused = true`** (PAUSED state GSM), `_physics_process` ne tourne pas → respawn timer fige. Au resume, continue depuis l'instant de pause. Conforme EC-CHK-9.

7. **Respawn execution** — quand le timer atteint `RESPAWN_DELAY` :
   ```gdscript
   func _execute_respawn() -> void:
       _restore_enemy_snapshot()                           # foreach Enemy → _restore_from_snapshot(was_dead)
       Player.respawn(_active_anchor)                      # Movement-owned, sets position + reset velocity + reset state to GROUNDED
       InputManager.request_enable(&"GSMRespawning")       # Refcount enable
       GameStateManager._on_player_respawned()             # Notify GSM → state PLAYING
       respawn_executed.emit(_active_anchor)               # Pour Audio/VFX consumers
       _state = State.IDLE
   ```
   - **Order critique** :
     1. **Restore Enemy snapshot AVANT Player.respawn** : si un grunt redevient ALIVE et son LaserCone est près de l'anchor, le Player respawn doit déjà voir le grunt vivant pour que la lecture spatiale soit cohérente. (Sinon : 1 frame le grunt apparaît mort, frame d'après il est vif — flicker).
     2. **Player.respawn AVANT Input enable** : le Player doit être à la position correcte avant que les inputs ne déplacent quoi que ce soit.
     3. **GSM notify APRÈS Input enable** : GSM transitionne RESPAWNING → PLAYING en dernier, garantissant que les autres systèmes (HUD, Camera) voient le respawn déjà résolu.

8. **Enemy snapshot capture** — au passage d'un checkpoint :
   ```gdscript
   func _capture_enemy_snapshot() -> void:
       _enemy_snapshot.clear()
       for enemy in get_tree().get_nodes_in_group("enemies"):
           if not is_instance_valid(enemy):
               continue
           _enemy_snapshot[enemy.get_instance_id()] = enemy.is_dead()
   ```
   - **Group `"enemies"`** : tous les `Grunt.tscn` instanciés par EnemySpawner ajoutent eux-mêmes au group `"enemies"` au `_ready`. Pas de couplage Checkpoint → Enemy.
   - **`get_instance_id()` clé** : robuste à l'ajout/retrait dynamique de grunts entre checkpoints (Tier 2+ pourrait spawner des grunts dynamiquement). Au MVP, scope figé level-time, mais le pattern absorbé pour future-proofing.
   - **`is_dead()` value** : Enemy GDD AC-ENM-3 garantit que `is_dead()` retourne `true` pendant DYING ET DEAD. Choix MVP : capturer `is_dead()` qui inclut DYING — un grunt en cours de mort au moment du checkpoint est restauré DEAD au respawn (le tween de mort ne survit pas — EC-CHK-7 + Enemy EC-ENM-13).

9. **Enemy snapshot restore** — au respawn :
   ```gdscript
   func _restore_enemy_snapshot() -> void:
       for enemy in get_tree().get_nodes_in_group("enemies"):
           if not is_instance_valid(enemy):
               continue
           var was_dead: bool = _enemy_snapshot.get(enemy.get_instance_id(), false)
           enemy._restore_from_snapshot(was_dead)
   ```
   - Si un grunt est dans le scene tree mais **pas** dans `_enemy_snapshot` (cas Tier 2+ : grunt spawné après le passage du checkpoint), default = `false` → restore ALIVE. Au MVP, n'arrive pas (tous les grunts sont level-time).

10. **WorldBounds → respawn** — Level System publie le signal `player_out_of_world(last_valid_position: Vector3)` quand le `WorldBoundsVolume` Area3D fire `body_entered(player)` (Level GDD EC-1, AC-LVL-25). Comportement Checkpoint :
    ```gdscript
    func _on_player_out_of_world(last_valid_position: Vector3) -> void:
        # Ne PAS modifier _active_anchor — on respawn au checkpoint courant, pas à last_valid_position.
        # last_valid_position est ignoré au MVP (réservé pour un futur fallback si _active_anchor est lui-même out-of-world)
        Player.die("out_of_world")  # Trigger normal pipeline via died signal
    ```
    - **Décision MVP** : la sortie de monde est traitée comme une mort normale (cohérent Pillar 3, le joueur revient au checkpoint). `last_valid_position` est ignoré. Si playtest montre des cas pathologiques (e.g. checkpoint placé hors-monde par bug authoring), ajouter fallback Sprint 2.

11. **Run reset** — sur `GameStateManager.request_new_run()` (par Menu post-mort, ou sortie boss, ou retour MENU) :
    ```gdscript
    func _on_request_new_run() -> void:
        _active_anchor = Vector3.ZERO                      # Sera ré-initialisé au prochain level_active
        _active_checkpoint_id = -1
        _enemy_snapshot.clear()
        _state = State.IDLE
    ```
    Au prochain `level_active`, le PlayerStart Marker reprend son rôle d'anchor initial (Rule 3).

12. **Pas de save/load au MVP** — la persistance des checkpoints **entre sessions** est explicitement hors scope. À la fermeture du jeu, l'état Checkpoint est perdu. Le **Save/Load System futur** (Persistence layer, Tier 2+) pourra ajouter une couche de persistance (last checkpoint reached, run summary stats), mais pas avant.

13. **PlayerStart NE devient PAS un checkpoint visité** — le PlayerStart Marker3D est l'anchor *initial implicite*, mais `_active_checkpoint_id = -1` jusqu'au premier CheckpointVolume traversé. Cela évite que le joueur perde la possibilité de retourner au PlayerStart si premier checkpoint est dans une room arrière (impossible MVP avec layout linéaire, mais robuste à des layouts non-linéaires Tier 2+).

### States and Transitions

| State | Entry condition | Exit condition | Behavior |
|---|---|---|---|
| `IDLE` | Boot autoload OU `_execute_respawn()` finished OU `_on_request_new_run()` | `Player.died` reçu (Rule 5) | Listening Area3D body_entered (latch checkpoints), listening Player.died, no respawn pipeline active. `tree.paused` peut être true ou false (orthogonal) |
| `RESPAWNING` | `Player.died` reçu pendant `IDLE` (Rule 5) | `_respawn_timer >= RESPAWN_DELAY` (Rule 6 → 7) | Input.request_disable(&"GSMRespawning") active, GSM en RESPAWNING state. Wall-clock countdown via `_physics_process`. Player position figée par Movement (state DEAD), Camera fade rouge active. Pause via tree.paused fige le timer ; resume continue |

**Transitions valides** :
- `IDLE → RESPAWNING` : sur `Player.died` reçu (idempotent — guard `_state != IDLE`).
- `RESPAWNING → IDLE` : sur completion de `_execute_respawn()` (Rule 7).
- `IDLE → IDLE` : `_on_request_new_run()` (Rule 11) ne change pas l'état mais réinitialise les variables.
- `RESPAWNING → RESPAWNING` : `Player.died` reçu pendant respawn = **absorbed** (idempotence).
- ❌ `RESPAWNING → IDLE via request_new_run` : le request_new_run pendant respawn est traité par GSM (qui peut soit absorber, soit forcer la transition). Décision : Checkpoint suit GSM — si GSM autorise la transition, Checkpoint reset (`_state = IDLE`, snapshots clear). Si GSM refuse, Checkpoint reste RESPAWNING. Pattern aligné GSM Rule 5 idempotence.

### Interactions with Other Systems

| Système | Direction | Interface | Contrat |
|---|---|---|---|
| **Player Movement System** (In Review r3) | Receive signal + Send call | Receive : `Player.died(reason: String)` signal SYNC ; Send : `Player.respawn(position: Vector3)` | Movement émet `died` à toute mort (Enemy laser, Hazard, manuel debug). Checkpoint reçoit, attend RESPAWN_DELAY, appelle `Player.respawn(active_anchor)`. Movement-owned API. **Bidirectional** — Movement GDD ligne 71 cite Checkpoint comme bidirectionnel |
| **Game State Manager** (APPROVED r1) | Notify | `GameStateManager._on_player_died(reason)` + `_on_player_respawned()` | Checkpoint **notifie** GSM des transitions de state, GSM **transitionne** PLAYING → RESPAWNING → PLAYING. Nommage method privées cohérent avec ADR-0007 D-7 (GSM consomme via signaux Player.died/respawned ; mais Checkpoint a déjà fait le bind, alors on appelle directement les handlers) |
| **Level System** (APPROVED r3) | Read | `LevelSystem.level_active` signal + `LevelSystem.get_checkpoint_slots() -> Array[CheckpointSlot]` | Au boot d'étage, Checkpoint reçoit la liste des `{volume: Area3D, anchor: Vector3, id: int}` slots et câble les body_entered. Level R-5.2 garantit pairing `CheckpointVolume_NN` ↔ `CheckpointAnchor_NN` même NN |
| **Enemy System** (Designed) | Read getter + Send call | `enemy.is_dead() -> bool` + `enemy._restore_from_snapshot(was_dead: bool)` | Snapshot capture à chaque checkpoint passé, restore au respawn. Enemy GDD Rule 13 + AC-ENM-16/17/18 figè le contract |
| **InputManager** (In Review r4) | Refcount | `request_disable(&"GSMRespawning") + request_enable(&"GSMRespawning")` | Refcount owner string « GSMRespawning » documenté ADR-0004 D-4. Disable au début RESPAWNING (Rule 5), enable post-respawn (Rule 7). Pas de conflit avec autres owners (Menu, Combat slow-mo, etc.) — refcount cumulatif |
| **Audio System** (APPROVED r2.1) | Send signal | `respawn_executed(position: Vector3)` + `checkpoint_activated(id: int, anchor: Vector3)` | Audio peut connecter ces signaux pour jouer (a) un cue checkpoint léger (chime ?) sur passage, (b) un sound de respawn (whoosh d'air ? hum cybernétique ?) au retour. Optionnel MVP — Audio GDD r2.1 ne mentionne pas explicitement, à amender Tier 2+ |
| **VFX & Feedback System** (Not Started) | Send signal | `respawn_executed(position: Vector3)` + `checkpoint_activated(id: int, anchor: Vector3)` | VFX peut afficher (a) un brief glow CheckpointVolume au passage, (b) un fade-back blanc 40 ms au respawn (overlap avec fade-rouge mort owned by Camera) |
| **HUD / UI System** (Not Started) | Send signal | `checkpoint_activated(id: int, anchor: Vector3)` + `respawn_executed(position: Vector3)` | HUD peut afficher (a) un toast brief « Checkpoint X/4 » 1 s post-MVP, (b) un counter deaths/run. Optional Tier 2+. **Anti-pattern explicit** : pas de toast checkpoint au MVP (player fantasy invisibilité) |
| **Save/Load System** (Not Started, Persistence layer) | Read snapshot | `get_run_summary() -> Dictionary` | Tier 2+ : Save/Load lit l'état Checkpoint pour persister dernière run completed (stats, deaths count, time-to-completion). MVP : aucun save persistant |
| **ADR-0007 (Game State Manager)** | Constraint | `GSM.RESPAWNING` state, refcount via owner strings | Checkpoint suit ADR-0007 D-7 contract : pas de mutation directe de `GSM._current_state`, uniquement notify |
| **ADR-0008 (Collision Layer Taxonomy)** | Constraint | `LAYER_INTERACTIVE = 5` pour CheckpointVolume Area3D | Level System garantit que les CheckpointVolume sont layer 5 mask 1. Checkpoint System ne touche pas aux layers — les Area3D sont déjà figés par Level authoring |
| **ADR-0011 (Level Scene Architecture)** | Constraint | Hiérarchie scène + naming `CheckpointVolume_NN`/`CheckpointAnchor_NN` paired | Checkpoint dépend de cette architecture pour parser correctement les slots via `get_checkpoint_slots()` |

## Formulas

Checkpoint System a **peu de math interne** — c'est un coordinator de state machine. Les formules ci-dessous documentent (1) le délai canonique, (2) la sélection d'anchor active, (3) le décompte de checkpoints par étage (cross-ref Level F3), et (4) la performance budget.

### F-CHK-1 : Respawn delay window

Le délai de respawn = window pendant lequel le Player est en state DEAD/RESPAWNING avant que le contrôle soit rendu au checkpoint :

`respawn_window_wall_clock_ms = RESPAWN_DELAY × 1000`

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `RESPAWN_DELAY` | T_resp | float | constant `0.05 s` | Owned by Movement GDD §Tuning Knobs (registry registered, value figeé r3 Martin 2026-04-21). Consommé par Checkpoint System via `_physics_process` countdown. **Invariant matériel** : `≥ 1/60 s = 0.0166 s` pour garantir CONNECT_DEFERRED consumers ont reçu leur callback (Movement Rule 9) |

**Output** : 50 ms wall-clock entre `Player.died` emit et `Player.respawn` call.

**Example timeline pour une mort grunt** :
```
t=0 ms     : LaserCone body_entered Player → Player.die("enemy_laser") → died.emit() → Movement state=DEAD, freeze input
t=0 ms     : Checkpoint._on_player_died handler → state=RESPAWNING, GSM RESPAWNING, Input.disable("GSMRespawning")
t=0-50 ms  : Audio death.wav 60-80ms perceptual onset (Audio r2.1 D3) ; Camera fade rouge 40 ms (Camera GDD Rule 9)
t=50 ms    : Checkpoint._execute_respawn → restore Enemy snapshot → Player.respawn(anchor) → Input.enable
t=50 ms    : Camera fade-back blanc 40 ms (commence)
t=90 ms    : Camera fade complete, joueur a contrôle plein
```

**Edge case** : si `RESPAWN_DELAY` est augmenté en playtest (e.g. à 0.1 s pour permettre une death animation), Audio death.wav max duration doit aussi être ajustée (Audio Rule cohérent ≤ RESPAWN_DELAY - 1 frame margin = 84 ms à 0.1 s).

---

### F-CHK-2 : Active anchor selection (latch monotone)

L'anchor de respawn courant est sélectionné par latch monotone sur l'`id` des checkpoints visités :

`active_anchor_position = max{anchor_NN ∣ visited(NN) == true} ∪ {PlayerStart}`

Plus précisément, l'algorithme :

```
si _active_checkpoint_id == -1 → return PlayerStart_position
sinon → return CheckpointAnchor_NN.global_position où NN == _active_checkpoint_id
```

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `_active_checkpoint_id` | id_cur | int | `[-1, K-1]` où K = checkpoint_count | Index du dernier checkpoint **strictement supérieur** atteint. `-1` = aucun visité (PlayerStart actif) |
| `K` | K | int | `[3, 5]` MVP via Level F3 | Nombre total de CheckpointVolume dans l'étage |

**Output** : `Vector3` absolu monde, position où le Player respawn.

**Example** : Player traverse `CheckpointVolume_01` (id=1) → `_active_checkpoint_id = 1`, `_active_anchor = CheckpointAnchor_01.global_position`. Plus tard, traverse `CheckpointVolume_03` (id=3) → `_active_checkpoint_id = 3`. Ne traverse jamais Volume_02 → reste à 03 (pas de régression).

**Edge case** : double-traverse Volume_02 après Volume_03 (par retour arrière) — le guard `slot.id <= _active_checkpoint_id` (Rule 4) bloque la régression. ✅ Cohérent Pillar 3 « UNE SECONDE CHANCE N'EST JAMAIS LOIN » (jamais en arrière).

---

### F-CHK-3 : Checkpoint count per étage (cross-ref Level F3)

Cette formule est **owned by Level System GDD Formula 3**, citée ici pour référence :

`checkpoint_count = ceil(N_rooms / CHECKPOINT_SPACING)`

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `N_rooms` | N | int | `[8, 10]` MVP | Nombre de salles dans l'étage. Owned by Level GDD R-2.6 |
| `CHECKPOINT_SPACING` | S | int | `[2, 3]` rooms | Espacement min en salles entre deux checkpoints. Owned by Level GDD F3. Nominal MVP : `S = 3` → 3-4 checkpoints par étage |

**Output** : `[3, 5]` checkpoints par étage MVP.

**Example MVP** : `N_rooms = 9`, `S = 3` → `ceil(9/3) = 3` checkpoints actifs + le PlayerStart implicite. Total 4 anchors de respawn possibles.

**Cross-ref note** : Cette formule est validée au level-time par `tools/lint/level_lint.gd::validate_level_formulas()` (Level story-020 — F3 lint). Checkpoint System n'a **rien à valider** au runtime ; il accepte la liste reçue de Level.

---

### F-CHK-4 : Total inter-control time (perf budget)

Le temps total entre la mort du Player et le retour au contrôle plein :

`total_inter_control_ms = RESPAWN_DELAY_ms + camera_fade_back_ms + frame_margins`

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `RESPAWN_DELAY_ms` | T_r | int | `50 ms` | Owned by Movement (F-CHK-1) |
| `camera_fade_back_ms` | T_cf | int | `40 ms` | Owned by Camera GDD Rule 9 — fade blanc → transparent au respawn |
| `frame_margins` | F_m | int | `[16, 33] ms` | Marge ~1-2 frames pour `_physics_process` overhead Checkpoint + GSM transitions + Movement.respawn |

**Output** : `≈ 90 ms minimum, 130 ms maximum` total wall-clock entre input figé (mort) et input ré-actif perçu joueur.

**Target Pillar 3** : sous la seconde wall-clock (`< 1000 ms`) — atteint avec marge confortable (~10×).

**Example** : Player meurt → 50 ms RESPAWN_DELAY → 16 ms frame physics tick → respawn exécuté → 40 ms camera fade-back → contrôle plein. Total : **106 ms wall-clock typique**.

**Edge case** : si `RESPAWN_DELAY` est tuné à 100 ms (e.g. pour permettre une death animation), le total grimpe à ~156 ms — toujours sous le seuil sub-second Pillar 3.

---

### Cross-system formula references

| Formula owner | Formula | Consumes Checkpoint constant | Constraint imposed |
|---|---|---|---|
| **Movement GDD Rule 9** | Death pipeline `died → freeze RESPAWN_DELAY → respawn(position)` | `RESPAWN_DELAY = 0.05 s` (registry) | Owned by Movement, consumed by Checkpoint. Bidirectional contract — Movement ne peut changer la valeur sans amender Checkpoint timing |
| **GSM Formula 2** | `respawn_window_ms = RESPAWN_DELAY × 1000 = 50 ms MVP` | `RESPAWN_DELAY` | Owned by GSM, consumed for AC-GSM-14 verification. Aligné Movement + Checkpoint |
| **Camera GDD Rule 9** | Fade rouge `40 ms` + Fade blanc `40 ms` | `RESPAWN_DELAY ≥ fade_red_ms + 10ms margin` | Camera fade rouge **doit** s'achever avant ou au moment du respawn. Avec RESPAWN_DELAY=50 ms et fade=40 ms, marge 10 ms ✅ |
| **Audio GDD r2.1 D3** | `death.wav` 60-80 ms perceptual onset | `RESPAWN_DELAY ≥ death.wav_duration + 1 frame margin` | Audio death sound doit pouvoir jouer dans la fenêtre RESPAWN_DELAY. À 50 ms vs 60-80 ms perceptual onset, **conflict potentiel** — Audio r2.1 D3 explicite que `death.wav` chevauche le respawn de 1 frame (CONNECT_DEFERRED garantit le start du sample), pas un blocker |
| **Level GDD F3** | `checkpoint_count = ceil(N_rooms / CHECKPOINT_SPACING)` | `N_rooms`, `CHECKPOINT_SPACING` | Owned by Level, consumed transitively par Checkpoint (qui itère les slots reçus de Level) |

## Edge Cases

- **EC-CHK-1 — Player meurt avant d'avoir traversé un checkpoint** : `_active_checkpoint_id == -1`, `_active_anchor` est resté à `PlayerStart` (Rule 3). Respawn execute normalement, Player retourne au PlayerStart. ✅ Aucun crash. Si playtest montre que c'est trop punitif au boot d'étage, ajouter règle « PlayerStart = checkpoint_00 implicite » + add une marker à PlayerStart Position.

- **EC-CHK-2 — Player traverse un checkpoint déjà visité (régression spatiale)** : Rule 4 guard `slot.id <= _active_checkpoint_id` retourne sans no-op. ✅ Pas de re-snapshot Enemy state, pas de signal `checkpoint_activated` re-emit.

- **EC-CHK-3 — Player traverse 2 checkpoints exactement au même tick physics** : peu probable géométriquement (CheckpointVolume non-overlap garanti par Level lint), mais si arrive — les 2 `body_entered` fire dans le même tick. Le 1er handler exécute (e.g. checkpoint id=2 → snapshot capture), le 2nd exécute (checkpoint id=3 → guard 3 > 2 → snapshot capture refait). ✅ Order-independent : seul le checkpoint d'`id` final maximum survit, snapshot reflète l'état au moment du dernier passage. Pas de bug.

- **EC-CHK-4 — Player.died emit pendant Player déjà DEAD (double-died)** : Rule 5 guard `_state != IDLE` absorbe le 2nd died. ✅ Idempotent.

- **EC-CHK-5 — Player.died emit pendant level transition (état GSM = TRANSITION)** : décision MVP — Checkpoint **ignore** died pendant transition. GSM est en `start_etage` ou `unload_current` flow (ADR-0007 D-5), Player est entre deux scènes. Garde Rule 5 `_state != IDLE` absorbe (le state est en RESPAWNING residual ou IDLE selon ordre, mais GSM aura déjà reset). Si bug subsiste, ajouter `if GSM.get_current_state() != GSM.State.PLAYING: return` au début du handler.

- **EC-CHK-6 — Snapshot capture pendant qu'un Grunt est mid-DYING (tween 75 ms écoulé sur 150)** : Rule 8 capture `enemy.is_dead()` qui retourne `true` durant DYING (Enemy AC-ENM-3). Au respawn, `_restore_from_snapshot(true)` force le grunt en DEAD instantanément — le tween est `kill()` et le mesh est invisible (Enemy EC-ENM-13). Cohérent UX : *« j'avais commencé à tuer ce grunt avant de mourir, il reste mort à mon respawn »* — récompense du progrès partiel.

- **EC-CHK-7 — Snapshot restore alors qu'un Grunt a été detruit entre temps** (queue_free externe par bug) : `is_instance_valid(enemy) == false`, le `for` skip ce grunt (Rule 9 ligne `if not is_instance_valid(enemy): continue`). ✅ Robust à la perte d'instances. Au MVP avec `queue_free` interdite (Enemy Rule 12), n'arrive pas — mais robust pour Tier 2+.

- **EC-CHK-8 — Player.respawn() raise une exception (e.g. anchor position inside wall)** : Movement GDD `respawn(position)` n'est pas spec'd pour throw — devrait silently teleport et fixer collision via Jolt push-out. Si exception inattendue, état Checkpoint reste `RESPAWNING` indefiniment (timer fini mais respawn pas exécuté). **Recovery** : ajouter timeout safeguard 500 ms post-RESPAWN_DELAY ; si encore RESPAWNING, force IDLE + push_error. **Décision MVP** : pas de safeguard implémenté ; trust Movement contract. À reconsidérer si crash playtest.

- **EC-CHK-9 — Pause GSM (`tree.paused = true`) pendant `RESPAWNING`** : `_physics_process` ne tourne plus → respawn timer fige. Au resume, continue normalement. ✅ Confirmé Rule 6. Player reste DEAD visuellement, Camera fade rouge actif, état RESPAWNING actif. Si Player Quit pendant cet état, Save/Load (Tier 2+) doit réinitialiser proprement. MVP : pas de save → quit force clean exit.

- **EC-CHK-10 — `request_new_run` appelé pendant `RESPAWNING`** : conflit potentiel. Décision MVP : Checkpoint **suit GSM**. Si GSM accepte la transition (e.g. PLAYING → MENU via timeout post-mort), Checkpoint exécute Rule 11 `_on_request_new_run` qui clear tout + state = IDLE. Si GSM refuse, Checkpoint reste RESPAWNING et terminera son respawn. Pattern aligné GSM idempotence Rule 5.

- **EC-CHK-11 — `level_active` reçu pendant `RESPAWNING`** : un nouveau level qui démarre alors qu'un respawn est en cours. **Décision** : Checkpoint reset complet (`_state = IDLE` forcé + `_active_anchor = player_start` + snapshot clear) dans `_on_level_active` (Rule 3). Le respawn pending est abandonné — c'est cohérent avec le fait que Player est dans un nouveau scene tree, l'anchor ancien n'a plus de sens. Logged via `push_warning("Checkpoint state reset mid-respawn on level transition")`.

- **EC-CHK-12 — Tous les CheckpointVolume sont chevauchants (level authoring bug)** : Player traverse l'overlap → tous les body_entered fire dans un tick. Rule 4 latch monotone garantit que seul le `max(id)` survit. ✅ Robust — pas de bug runtime, juste une UX dégradée (le joueur active 4 checkpoints en 1 frame). Lint Level System à ajouter : `validate_checkpoint_volume_no_overlap()`.

- **EC-CHK-13 — `CheckpointVolume` sans `CheckpointAnchor` paired** (level authoring bug — Volume_03 existe sans Anchor_03) : Level System lint catch (Level story-021 AC-LVL-EC7 « validate_checkpoint_anchors »). Au runtime, si un slot CheckpointSlot a `anchor == Vector3.ZERO` ou null, Checkpoint System log error et fallback PlayerStart. Au MVP, lint Level garantit pas d'orphelin.

- **EC-CHK-14 — `_active_anchor` pointe à une position devenue inaccessible après level event dynamique** : au MVP, scène statique → impossible. Tier 2+ avec géométrie dynamique nécessitera vérification `is_position_walkable(anchor)` + fallback PlayerStart si invalide.

- **EC-CHK-15 — Player meurt out-of-world (chute) ET un grunt laser hit le même tick** : 2 sources de `Player.die()` dans le même tick. Movement absorbe (Player GDD die() idempotent). Checkpoint reçoit died une seule fois (le 2ème died emit est filtré par Movement ou par Rule 5 idempotence). ✅ Robust.

- **EC-CHK-16 — Frame budget dépassé pendant `_physics_process` à 60 Hz (e.g. `delta = 0.025` au lieu de 0.0166)** : `_respawn_timer += delta` accumule plus vite, respawn déclenche plus tôt en termes de frames. **Wall-clock total reste conforme** (50 ms réels). C'est un bug de frame drop, pas Checkpoint-related — pas d'edge case spécifique.

- **EC-CHK-17 — Plusieurs Player nodes (cas dev/test, plusieurs spawn manuels)** : MVP scope solo, 1 Player garanti par GSM `start_etage`. Si bug provoque 2 Player, le `body.is_in_group("player")` (Rule 4) catche les deux → 2 latch handlers → 2 snapshot captures ; potentiellement des appels multiples `Player.respawn` à la mort. **Décision** : pas de safeguard MVP, trust GSM single-player invariant.

## Dependencies

### Hard dependencies (Checkpoint ne peut pas fonctionner sans ces systèmes)

| Système | Status | Direction | Interface critique |
|---|---|---|---|
| **Player Movement System** (In Review r3) | ⚠️ GDD pending re-review | Bidirectional | Receive : `Player.died(reason)` signal SYNC. Send : `Player.respawn(position)` call. Sans Movement, le pipeline mort-respawn n'a pas d'autorité de mort/transition |
| **Game State Manager** (APPROVED r1) | ✅ Designed | Notify (1-way Checkpoint → GSM) | `GameStateManager._on_player_died(reason) + _on_player_respawned()`. Sans GSM, le state RESPAWNING n'est pas tracké, pas de pause discipline |
| **Level System** (APPROVED r3) | ✅ Designed | Read | `LevelSystem.level_active(etage_id, player_start) + LevelSystem.get_checkpoint_slots() -> Array[CheckpointSlot]`. Sans Level, pas de slot Checkpoint = system dormant |
| **InputManager** (In Review r4) | ⚠️ GDD pending re-review | Refcount call | `request_disable(&"GSMRespawning") + request_enable(&"GSMRespawning")`. Sans Input refcount, le joueur peut bouger pendant le respawn (cassure UX Pillar 3) |
| **Enemy System** (Designed) | ✅ Designed (this session) | Read getter + Send call | `enemy.is_dead() -> bool` + `enemy._restore_from_snapshot(was_dead: bool)`. Sans Enemy snapshot API, les grunts seraient reset au respawn (Pillar 3 forgiveness cassée) |
| **ADR-0007 (Game State Manager)** | ✅ Accepted | Constraint | RESPAWNING state, refcount ownership, idempotence rules |
| **ADR-0008 (Collision Layers)** | ✅ Accepted | Constraint | LAYER_INTERACTIVE = 5 pour CheckpointVolume Area3D |

### Soft dependencies (système enrichi par mais fonctionne sans)

| Système | Status | Direction | Interface |
|---|---|---|---|
| **Audio System** (APPROVED r2.1) | ✅ Designed | Send signal | `respawn_executed + checkpoint_activated` consumés par Audio pour cues. Sans Audio, le respawn est silencieux (UX dégradé mais fonctionnel). À mettre dans Audio Tier 2+ amendment |
| **VFX & Feedback System** (Not Started) | ❌ Pas designed | Send signal | Idem — fade-back blanc 40 ms post-respawn, glow CheckpointVolume au passage. Sans VFX, le respawn est moins polished |
| **HUD / UI System** (Not Started) | ❌ Pas designed | Send signal | Toast checkpoint reached (post-MVP). Sans HUD, aucun feedback explicite — voulu MVP (player fantasy invisibilité) |
| **Camera System** (In Review r2) | ⚠️ GDD pending re-review | Indirect — Movement.died/respawned chain | Camera consomme `Player.died/respawned` (pas Checkpoint signaux directement). Camera GDD Rule 9 figè le fade rouge/blanc |

### Cousins (latents — Tier 2+, hors MVP)

- **Save/Load System** (Not Started, Persistence layer Tier 2+) — Tier 2+ pourrait persister entre sessions le run summary (deaths, time, last checkpoint). MVP : pas de save persistant.
- **Boss System** (Not Started, Full Vision) — Tier 3 boss aura un seul checkpoint d'entrée à sa salle, comportement hors scope ici.
- **Hazard System** (Not Started) — Tier 2+ pourrait appeler `Player.die()` (ce qui déclenche le pipeline normal Checkpoint). Au MVP, pas de Hazard.
- **Tutorial System** (Not Started) — Si Tutorial existe Tier 2+ et veut signaler « tu as activé un checkpoint », il consommera le signal `checkpoint_activated`.

### Bidirectional consistency check

| Cited dependency | Réciprocité dans GDD cible | Status |
|---|---|---|
| Movement cite Checkpoint comme « bidirectionnel » dans header (line 14) + Rule 9 + Interactions | ✅ Mention présente | ✅ Bidirectionnel |
| GSM cite Checkpoint comme « consumed by » + ADR-0007 D-7 figè le contract | ✅ Présent (GSM Rule 5 + Depended on by header) | ✅ Bidirectionnel |
| Level cite Checkpoint comme « Depended on by » + R-2.6 + Formula 3 + R-5.2 naming | ✅ Présent (Level header line 9 + multiple rules) | ✅ Bidirectionnel |
| Enemy cite Checkpoint comme « Aval, post-MVP — Read/Write meta + `_restore_from_snapshot` » | ✅ Présent (Enemy GDD Rule 13 + Section F Soft dependency) | ✅ Bidirectionnel |
| Audio cite Checkpoint ? | ⚠️ Pas explicite dans Audio GDD r2.1 — à amender Tier 2+ ou OQ | ⚠️ One-directional — amendment suggested |
| Camera cite Checkpoint ? | ⚠️ Camera consumed `Player.died/respawned`, pas Checkpoint directement — pas vraiment de dependency | ✅ Indirect (via Movement) |

## Tuning Knobs

Checkpoint System a **peu de knobs internes** — il est principalement consumer de constantes owned by d'autres systèmes (Movement RESPAWN_DELAY, Level CHECKPOINT_SPACING). Les seuls knobs propres sont des paramètres de bordure (timeout safeguard, snapshot strategy).

### Constantes consumées (owned ailleurs)

| Knob | Owner | Valeur MVP | Range | Affecte |
|---|---|---|---|---|
| `RESPAWN_DELAY` | Movement GDD §Tuning Knobs | `0.05 s` | `[0.0166, 0.5]` | Délai entre Player.died et Movement.respawn(position). Lower bound = 1 frame physics ; upper bound = subjectif (au-delà casse Pillar 3) |
| `CHECKPOINT_SPACING` | Level GDD F3 | `3` rooms | `[2, 4]` | Espacement min entre 2 checkpoints. Affecte F-CHK-3 checkpoint count. Bas = retours fréquents (Pillar 3 max) ; haut = rare = punitif |
| `LAYER_INTERACTIVE` | ADR-0008 + registry | `5` | constant | Layer pour CheckpointVolume Area3D. Non-tunable |

### Constantes Checkpoint-internes

| Knob | Valeur MVP | Safe range | Affecte | Risque hors-range |
|---|---|---|---|---|
| `RESPAWN_TIMEOUT_SAFEGUARD_MS` (proposé, non implémenté MVP) | `500 ms` | `[200, 2000]` | EC-CHK-8 fallback : si respawn_timer dépasse RESPAWN_DELAY + safeguard sans `_execute_respawn`, force IDLE + push_error | < 200 → false alarms ; > 2000 → bugs cachés trop longtemps |
| `SNAPSHOT_STRATEGY` | `EAGER` (capture à chaque checkpoint) | `{EAGER, LAZY}` | Stratégie de capture du snapshot Enemy. EAGER = capture au passage (Rule 8) ; LAZY = capture au died moment (juste les enemies courants) | LAZY produirait des snapshots éphémères, casse Pillar 3 forgiveness — éviter |

### Per-checkpoint metadata (level-time authoring)

Tunable individuellement via `Marker3D.set_meta(...)` sur les CheckpointAnchor par le level designer :

| Meta key | Type | Default | Range | Description |
|---|---|---|---|---|
| `checkpoint_silent` | bool | `false` | `{true, false}` | Si true, le `checkpoint_activated` signal n'est PAS émis pour ce checkpoint — Audio/VFX silent. **Use case** : checkpoint passage automatique invisible (e.g. transition entre zones de la même salle) |
| `checkpoint_label` | String | `"Checkpoint NN"` | string libre | Future Tier 2+ : label affichable HUD (« Mid-arena », « Pre-boss », etc.). Au MVP non-utilisé |
| `respawn_facing_basis` | Basis | `IDENTITY` | rotation valide | Future Tier 2+ : rotation du Player au respawn (par défaut, garde rotation pré-mort). MVP : Movement décide |

### Knobs latents (Tier 2+, hors MVP)

| Knob | Description futur |
|---|---|
| `INTER_RUN_PERSISTENCE` | Save/Load Tier 2+ : persister `_active_checkpoint_id` entre sessions (continue from last checkpoint at game start) |
| `MULTI_ANCHOR_PER_CHECKPOINT` | Tier 2+ : checkpoint avec multi-anchor (per-direction d'arrivée) — Tier 2+ niveaux non-linéaires |
| `CHECKPOINT_PROGRESS_PERCENT` | Tier 2+ HUD : afficher `_active_checkpoint_id / K` comme progress bar |

## Visual/Audio Requirements

> **Note de scope** : Checkpoint System est **Foundation/Infrastructure** — le player fantasy ciblé est *l'invisibilité bienveillante*. Visual/Audio MVP est donc volontairement **minimal**. Toute amplification (toast checkpoint, shimmer permanent du Volume, cue audio fort) est anti-pattern Pillar 1 invisibility.

### Visual

**CheckpointVolume — passage activation** (signal `checkpoint_activated`)

- **MVP** : aucun visuel direct sur le CheckpointVolume Area3D (rappel : layer 5 INTERACTIVE = pass-through, le volume n'a pas de mesh visible). **Le passage du checkpoint est silencieux visuellement au MVP**. Justification : Pillar 1 « lecture instantanée » impose que le décor ne soit pas pollué de marqueurs invisibles à manipuler. Le checkpoint *fait* son travail sans attirer l'œil.
- **Tier 2+ optionnel** : un brief glow blanc/cyan 200 ms à l'emplacement du `CheckpointAnchor` Marker (un MeshInstance3D Quad émissif activé puis fade-out). Couleur cyan choisie pour aligner art-bible État 2 (Secret/Interactif), pas rouge (réservé Hostile) ni blanc (réservé Path principal). À spec dans VFX & Feedback System GDD futur.
- **Anti-pattern** : pas de pillier vertical permanent, pas de shimmer continue, pas de pulse, pas de holographic icon. Ces UX (Souls-like bonfire, Ghostrunner respawn beacon) sont incompatibles avec Pillar 1.

**Death overlay** (signal `Player.died` consumé Camera GDD Rule 9, hors scope Checkpoint)

- **Owned by Camera** — Camera GDD figè le fade rouge `~40 ms` à la mort. Checkpoint n'a aucun rôle visuel ici.

**Respawn overlay** (signal `respawn_executed`)

- **MVP** : fade-back blanc → transparent `~40 ms` à la transition RESPAWNING → PLAYING. Owned by **Camera GDD Rule 9** (déjà figé). Checkpoint System émet le signal `respawn_executed`, Camera l'écoute via Movement.respawned chain.
- **VFX additionnel** : aucun MVP. Tier 2+ pourrait ajouter un brief « digital glitch » cybernétique cohérent cyber-ronin theme — à spec VFX GDD futur.

**HUD checkpoint indicator**

- **MVP** : aucun. Le joueur ne voit pas combien de checkpoints il a activés, ni où il respawnera (il le sait spatialement). 
- **Tier 2+ optionnel** : une icône discrète bottom-left HUD montrant `_active_checkpoint_id / K` (e.g. « ◆◆◇◇ » 4 diamonds for 4 checkpoints, filled = visited). À spec HUD GDD futur, mais **anti-pattern par défaut** sauf si playtest montre un besoin clair.

> 📌 **Asset Spec** — Visual requirements MVP sont minimaux (silent checkpoint). Si Tier 2+ ajoute glow/icon, exécuter `/asset-spec system:checkpoint-respawn-system` post-art-bible Tier 2+.

### Audio

**Source de vérité** : Audio System GDD r2.1 + ADR-0009 D-1 figè les bus names et la pool architecture. Checkpoint System est **consumer aval** d'Audio via signal `checkpoint_activated` + `respawn_executed`.

**Sonic events Checkpoint → Audio** :

| Event | Trigger | Audio bus | Sample type | MVP |
|---|---|---|---|---|
| **Checkpoint activated chime** | `checkpoint_activated` signal | `UI` ou `Ambience` (Audio GDD r2.1 §Mix hierarchy) | Sub-second tick mineur (40-80 ms perceptual onset, doux, low-frequency) | **HORS MVP** — Pillar 1 invisibility. Anti-pattern d'attirer l'attention sur l'event mécanique. À implémenter **uniquement si playtest demande**. Si oui, sample Audio Tier 2+ recommandé : pulse cybernétique discret -18 dB, durée < 300 ms total |
| **Respawn whoosh** | `respawn_executed` signal | `combat_kill` (Audio r2.1 §Mix hierarchy) ou `UI` | Sub-second swoosh d'air, 100-200 ms | **HORS MVP** au sens Audio specifique — mais le `death.wav` 60-80 ms (Audio r2.1 D3, owned by Movement death pipeline) couvre déjà l'événement audio de mort + transition. Pas besoin de second cue de respawn. Tier 2+ peut ajouter |
| **Death sound** | `Player.died` signal | `combat_kill` (Audio r2.1) | 60-80 ms perceptual onset (Audio r2.1 D3 + RESPAWN_DELAY contract) | **MVP — owned by Audio + Movement chain**, pas Checkpoint. Checkpoint juste orchestre le timing |

**Mix priority pendant RESPAWNING** : Audio System owns its mix hierarchy. Checkpoint n'impose rien — le sidechain ducking `MUSIC ← combat_kill` (ADR-0009 D-1 r2 amend) gère le ducking automatique.

### Conclusion Visual/Audio MVP

**MVP voulu** : invisibilité totale. Le joueur passe un volume → state Checkpoint mute mais aucun feedback ne pop. Le seul feedback audio/visuel à la mort est :
1. Camera fade rouge 40 ms (Camera GDD Rule 9)
2. Audio death.wav 60-80 ms sur bus `combat_kill` (Audio GDD r2.1 D3)
3. Camera fade-back blanc 40 ms (Camera GDD Rule 9)

**Tout le reste est SILENT MVP** — par design Pillar 1 + Pillar 3 forgiveness invisible. Si playtest échoue (joueurs perdus, ne savent pas ce qui se passe), envisager d'ajouter le chime + glow de Tier 2+ comme « fallback UX ».

## UI Requirements

Checkpoint System **n'a pas d'UI Checkpoint-owned au MVP**. Cohérent avec Player Fantasy invisibilité (cf §Visual/Audio).

### Consumers UI possibles (post-MVP)

| Consumer | Signal écouté | Présentation UI possible | Décision MVP | GDD owner |
|---|---|---|---|---|
| **HUD** (Not Started) | `checkpoint_activated` | Toast brief « Checkpoint X/4 » 1 s top-right OU progress bar discrète | ❌ HORS MVP — Player Fantasy invisibilité. Si playtest demande, Tier 2+ | HUD GDD futur |
| **HUD** (Not Started) | `respawn_executed` | Death counter incremented (« Deaths: 7 ») | ❌ HORS MVP — anti-Pillar 3 punition | HUD GDD futur Tier 2+ |
| **Run Summary screen** (Tier 2+) | (cumulative end-of-etage) | Stats : « 4/4 checkpoints activated, 7 deaths total, time-to-completion 8m32s » | ❌ HORS MVP | Run Summary GDD Tier 2+ |
| **Pause Menu** (Not Started) | (read state) | « Resume from last checkpoint » button vs « Restart etage » button | ⚠️ Pause Menu MVP a besoin d'au moins un Resume button — design dans Pause Menu UX spec futur | Pause Menu UX spec futur |

### UX Flag (per skill convention)

> **📌 UX Flag — Checkpoint & Respawn System** : Aucune UX spec dédiée requise au MVP. Le système est invisible UI-wise. Ses consumers (HUD, Run Summary, Pause Menu) auront leurs propres UX specs respectives à designer Tier 2+ ou via `/ux-design hud` Sprint A (cf gate-check r2 roadmap).

**Pas d'asset UI à produire MVP.**

## Acceptance Criteria

Format : `**AC-CHK-NN [type]** : GIVEN [état initial], WHEN [action ou trigger], THEN [résultat mesurable]`

Types : **Logic** = unit BLOCKING ; **Integration** = integration BLOCKING ; **Visual** = playtest evidence ADVISORY ; **Perf** = benchmark BLOCKING.

### Boot et initialisation

- **AC-CHK-01 [Integration]** : GIVEN un projet Godot avec autoload `CheckpointSystem`, WHEN le signal `LevelSystem.level_active(etage_id=1, player_start=Vector3(0,0,0))` est émis, THEN `_active_anchor == Vector3(0,0,0)` ET `_active_checkpoint_id == -1` ET `_enemy_snapshot.is_empty() == true` ET `_state == State.IDLE`.

- **AC-CHK-02 [Integration]** : GIVEN un étage chargé avec 3 `CheckpointVolume_01..03` et 3 `CheckpointAnchor_01..03`, WHEN `level_active` émis, THEN `LevelSystem.get_checkpoint_slots()` retourne 3 entrées correctement parées, ET `CheckpointSystem` connecte 3 handlers `body_entered` (vérifiable via `signal.get_connections().size() == 3` sur chaque CheckpointVolume).

### Latch monotone des checkpoints

- **AC-CHK-03 [Logic]** : GIVEN `_active_checkpoint_id == -1`, WHEN Player traverse `CheckpointVolume_01`, THEN `_active_checkpoint_id == 1` ET `_active_anchor == CheckpointAnchor_01.global_position` ET signal `checkpoint_activated(1, anchor_pos)` émis 1 fois.

- **AC-CHK-04 [Logic]** : GIVEN `_active_checkpoint_id == 3`, WHEN Player traverse `CheckpointVolume_02` (régression spatiale), THEN `_active_checkpoint_id` reste à `3` ET `_active_anchor` inchangé ET aucun signal `checkpoint_activated` émis (Rule 4 latch monotone, EC-CHK-2).

- **AC-CHK-05 [Logic]** : GIVEN `_active_checkpoint_id == 1`, WHEN Player traverse `CheckpointVolume_01` (re-passage du même), THEN aucun changement, aucun signal (guard `slot.id <= _active_checkpoint_id`).

- **AC-CHK-06 [Integration]** : GIVEN 2 `CheckpointVolume_02` et `_03` chevauchants (level authoring bug), WHEN Player traverse l'overlap, THEN `_active_checkpoint_id` final == max des deux ids fired (EC-CHK-12), aucun crash.

### Pipeline died → respawn

- **AC-CHK-07 [Integration]** : GIVEN `_state == IDLE`, WHEN signal `Player.died("enemy_laser")` émis, THEN `_state == State.RESPAWNING` ET `GameStateManager.get_current_state() == GSM.State.RESPAWNING` ET `InputManager.is_disabled_by(&"GSMRespawning") == true` (refcount > 0).

- **AC-CHK-08 [Logic]** : GIVEN `_state == RESPAWNING` ET `_respawn_timer == 0`, WHEN `_physics_process(delta=0.0166)` est appelé 4 fois (4 frames @ 60 Hz = ~66 ms wall-clock), THEN `_respawn_timer >= RESPAWN_DELAY (=0.05 s)` ET `_execute_respawn()` est appelé exactement 1 fois.

- **AC-CHK-09 [Integration]** : GIVEN `_state == RESPAWNING` après 50 ms wall-clock, WHEN `_execute_respawn()` exécute, THEN dans l'ordre : (a) `_restore_enemy_snapshot()` appelée, (b) `Player.respawn(_active_anchor)` appelée 1 fois avec position correcte, (c) `InputManager.request_enable(&"GSMRespawning")` appelée 1 fois, (d) `GameStateManager._on_player_respawned()` appelée, (e) signal `respawn_executed(_active_anchor)` émis 1 fois, (f) `_state == State.IDLE`.

- **AC-CHK-10 [Logic]** : GIVEN `_state == RESPAWNING`, WHEN signal `Player.died("debug")` émis une 2ème fois, THEN aucun changement, no-op silent (Rule 5 idempotent).

### Enemy snapshot

- **AC-CHK-11 [Integration]** : GIVEN un étage avec 3 grunts dont 1 est `is_dead() == true` (tué pré-checkpoint) et 2 sont `is_dead() == false`, WHEN Player traverse un CheckpointVolume, THEN `_enemy_snapshot` contient 3 entrées `{instance_id: bool}` reflétant exactement les `is_dead()` au moment du passage (Rule 8).

- **AC-CHK-12 [Integration]** : GIVEN `_enemy_snapshot` capture un grunt `is_dead() == false`, WHEN respawn execute, THEN ce grunt reçoit `_restore_from_snapshot(false)` et son `_state == ALIVE` post-restore (Enemy AC-ENM-17).

- **AC-CHK-13 [Integration]** : GIVEN `_enemy_snapshot` capture un grunt `is_dead() == true`, WHEN respawn execute, THEN ce grunt reçoit `_restore_from_snapshot(true)` et son `_state == DEAD` post-restore (Enemy AC-ENM-16).

- **AC-CHK-14 [Integration]** : GIVEN un grunt `is_dead() == true` au snapshot capture, mais le node a été `queue_free()`'d entre-temps (cas Tier 2+ — au MVP impossible), WHEN respawn execute, THEN le `for` loop skip ce node via `is_instance_valid()` guard, aucun crash (Rule 9 + EC-CHK-7).

### Pause / state interactions

- **AC-CHK-15 [Integration]** : GIVEN `_state == RESPAWNING` ET `_respawn_timer == 0.025`, WHEN `tree.paused = true` est positionné (e.g. via `GSM.request_pause()`), puis 5 secondes wall-clock écoulées, puis `tree.paused = false`, THEN `_respawn_timer == 0.025` au resume (pas d'avancement durant pause), respawn complete au cumul wall-clock 50 ms hors pause (EC-CHK-9).

- **AC-CHK-16 [Integration]** : GIVEN `_state == RESPAWNING`, WHEN `GameStateManager.request_new_run()` est appelé, THEN selon GSM acceptance : si GSM transition (e.g. PLAYING → MENU), Checkpoint reset (`_state = IDLE`, snapshots clear). Si GSM refuse, Checkpoint reste RESPAWNING et termine (EC-CHK-10).

- **AC-CHK-17 [Integration]** : GIVEN `_state == RESPAWNING`, WHEN signal `LevelSystem.level_active` émis (nouveau étage chargé), THEN `_state` forcé à IDLE, `_active_anchor = new_player_start`, `_enemy_snapshot.clear()`, `push_warning("Checkpoint state reset mid-respawn on level transition")` log (EC-CHK-11).

### WorldBounds + run reset

- **AC-CHK-18 [Integration]** : GIVEN un étage avec `WorldBoundsVolume`, WHEN Player traverse WorldBoundsVolume body_entered, THEN signal `LevelSystem.player_out_of_world(last_valid_pos)` émis, et Checkpoint appelle `Player.die("out_of_world")` (Rule 10), pipeline normal RESPAWN.

- **AC-CHK-19 [Logic]** : GIVEN `_active_checkpoint_id == 2` ET `_enemy_snapshot` non-empty, WHEN `_on_request_new_run()` exécuté, THEN `_active_checkpoint_id == -1`, `_active_anchor == Vector3.ZERO`, `_enemy_snapshot.is_empty() == true`, `_state == IDLE` (Rule 11).

### Performance

- **AC-CHK-20 [Perf]** : GIVEN un étage avec 30 grunts (max MVP) et 5 checkpoints, WHEN Player traverse un checkpoint (snapshot capture des 30 grunts), THEN snapshot capture overhead < 1 ms wall-clock (mesuré via `Time.get_ticks_usec()` autour de `_capture_enemy_snapshot()`).

- **AC-CHK-21 [Perf]** : GIVEN un étage avec 30 grunts, WHEN respawn execute (snapshot restore + Player.respawn + Input enable + GSM notify), THEN total respawn execution overhead < 2 ms wall-clock (frame budget contract — ne doit pas faire skipper la frame physics @ 60 Hz).

- **AC-CHK-22 [Perf]** : GIVEN `_state == IDLE`, WHEN `_physics_process(delta)` exécuté 1000 ticks (16.6 s @ 60 Hz), THEN aucune allocation heap dans Checkpoint System (delta `MEMORY_STATIC` < 1 KB sur la fenêtre).

### Cross-system integration

- **AC-CHK-23 [Integration]** : GIVEN un test e2e Movement + GSM + Checkpoint + Enemy mockés, WHEN `Player.die("enemy_laser")` émis, THEN après 50 ms wall-clock simulé, le pipeline complet exécute dans l'ordre canonique (Movement DEAD → Checkpoint RESPAWNING → GSM RESPAWNING → Input disable → 50ms wait → Enemy snapshot restore → Movement.respawn → Input enable → GSM PLAYING).

- **AC-CHK-24 [Integration]** : GIVEN Camera GDD Rule 9 fade rouge actif au died, WHEN respawn execute @ t=50ms, THEN Camera reçoit le signal `respawned` (via Movement chain) et démarre fade blanc → transparent 40 ms. Total wall-clock visual recovery ≤ 90 ms (F-CHK-4).

### Visual / Feel (ADVISORY playtest)

- **AC-CHK-25 [Visual]** : Playtest evidence — Pillar 3 sub-second recovery : 5 playtesters indépendants ne perçoivent **pas** un délai « long » entre mort et reprise contrôle. Questionnaire post-session : aucun mot négatif (« lent », « frustrant », « j'ai dû attendre »). Si > 1/5 négatif, retune RESPAWN_DELAY ou camera fade.

- **AC-CHK-26 [Visual]** : Playtest evidence — Pillar 3 forgiveness : un playtester qui tue 2 grunts puis traverse un checkpoint puis meurt, **comprend sans tutoriel** que ces 2 grunts restent morts au respawn. Confirmé par observation (le playtester ne re-tente pas de tuer les grunts au respawn) ou par interview post-session.

- **AC-CHK-27 [Visual]** : Playtest evidence — Pillar 1 invisibility : 5 playtesters indépendants n'identifient **pas** spontanément le « système checkpoint » lors d'un debrief libre. Aucun mot « checkpoint », « save », « respawn point » dans les 30 premières secondes de feedback. Si invisibilité ratée (joueur cherche activement les checkpoints), retune Visual/Audio (peut-être ajouter chime Tier 2+).

### Authoring lints (à add Level System)

- **AC-CHK-28 [Logic]** : GIVEN un étage avec `CheckpointVolume_03` mais sans `CheckpointAnchor_03`, WHEN `tools/lint/level_lint.gd::validate_checkpoint_anchors()` exécute, THEN un FAIL est rapporté avec message contenant « CheckpointVolume_03 missing paired CheckpointAnchor_03 » (Level story-021 AC-LVL-EC7 — already shipped).

- **AC-CHK-29 [Logic]** : GIVEN un étage avec 2 `CheckpointVolume_*` chevauchants spatialement, WHEN `validate_checkpoint_volume_no_overlap()` exécute (à ajouter), THEN un WARNING est rapporté (EC-CHK-12) — overlap accepté en runtime (latch monotone gère) mais flagué pour review designer.

## Open Questions

| OQ | Question | Owner | Target resolution |
|---|---|---|---|
| **OQ-CHK-1** | Pattern d'instantiation : autoload `CheckpointSystem` global vs Service-Locator (`LevelSystem.get_checkpoint_service()`) ? **Recommandation MVP** : autoload (cohérent avec GSM, AudioSystem, InputManager) — Foundation systems pattern. Service-Locator amène un overhead de lookup sans bénéfice MVP | technical-director / godot-specialist | Sprint A — décider avant `/dev-story checkpoint-system-001` ; ADR-0012 « Foundation Systems Autoload Pattern » potentiel |
| **OQ-CHK-2** | `_physics_process delta` time_scale-affected (Combat slow-mo Engine.time_scale=0.3) vs `Time.get_ticks_msec()` wall-clock absolu pour le respawn timer ? **Recommandation MVP** : `delta` (time_scale-affected) — une mort durant slow-mo respecte la lenteur perçue (50 ms × 0.3 = 167 ms perçus, cohérent UX). Pivoter Tier 2+ si playtest demande | game-designer | Sprint A — playtest peut valider |
| **OQ-CHK-3** | `RESPAWN_TIMEOUT_SAFEGUARD` (EC-CHK-8) implémenté MVP ? **Recommandation** : non — trust Movement contract `respawn(position)` n'a pas de failure mode. Ajouter Sprint 2 si crash playtest | game-designer + qa-lead | Sprint 2 |
| **OQ-CHK-4** | Visual feedback minimal au passage d'un checkpoint (chime audio ou glow VFX) ? **Recommandation MVP** : aucun (Pillar 1 invisibility). Si playtest catastrophe, Tier 2+ ajoute chime cyan discret | art-director + audio-director | Sprint C playtest evidence — décide post-test |
| **OQ-CHK-5** | Audio cite Checkpoint comme consumer ? **Recommandation** : ajouter au Audio GDD r2.2 amendment (Tier 2+) le `respawn_executed` signal en consumer pour respawn whoosh optionnel + `checkpoint_activated` en consumer Tier 2+ chime. Pas blocker MVP | audio-director | Tier 2+ |
| **OQ-CHK-6** | Inter-run persistence (Save/Load) : persister `_active_checkpoint_id` entre sessions ? **Recommandation MVP** : non — un nouveau run = repart du PlayerStart. Tier 2+ via Save/Load GDD futur peut ajouter | game-designer + Save/Load GDD owner | Tier 2+ |
| **OQ-CHK-7** | Multi-anchor per-checkpoint (Tier 2+ niveaux non-linéaires) : un checkpoint avec plusieurs anchors selon direction d'arrivée ? Hors scope MVP (layout linéaire), mais à anticiper API design | level-designer | Tier 2+ |
| **OQ-CHK-8** | Pause Menu UX MVP : doit-il afficher « Resume from last checkpoint » comme bouton, ou juste « Resume » (continue gameplay) + « Restart etage » + « Quit to menu » ? Affecte la lisibilité du Checkpoint System | ux-designer | Sprint A — Pause Menu UX spec à designer |
| **OQ-CHK-9** | Bidirectional cross-GDD : Audio GDD r2.1 ne mentionne pas explicitement Checkpoint comme consumer. Faut-il amender Audio r2.2 ? **Recommandation** : oui, à fold dans une amendment globale post-/design-review enemy + checkpoint qui validera tous les signal contracts cross-system | game-designer + audio-director | Sprint A — `/design-review checkpoint-respawn-system` fresh window vérifiera |
| **OQ-CHK-10** | `checkpoint_silent` per-meta knob (Tuning Knobs) : utile MVP ou Tier 2+ ? **Recommandation MVP** : déclarer dans le contract (parsable par Level System), mais aucun checkpoint silent dans le 1er etage MVP. Validation par `/dev-story` Level | level-designer | Sprint A |
