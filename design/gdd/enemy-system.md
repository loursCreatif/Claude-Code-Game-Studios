# Enemy System

> **Status** : **APPROVED r2** (2026-04-27 fresh re-review APPROVED — voir [enemy-system-review-log.md](reviews/enemy-system-review-log.md))
> **Author** : Martin + agents (game-designer, ai-programmer, art-director, systems-designer, qa-lead, creative-director, audio-director)
> **Last Updated** : 2026-04-27 (r2 = r1 + 6 corrections éditoriales review-r1 + fresh re-review APPROVED)
> **Gate condition résiduelle pour `/create-epics`** : (A) amendement Combat GDD r7 (retirer `enemy_killed` de Published API CombatSystem) + (B) Movement GDD re-review r4 confirme contrat `Player.die()` bidirectionnel (cf §Dependencies bidirectional check)
> **Implements Pillar** : Pillar 1 FLOW AVANT TOUT (one-shot mutuel = staccato), Pillar 3 SECONDE CHANCE (mort pédagogique — l'ennemi qui t'a tué reste visible), Pillar 4 (positionnement spatial pour secrets — indirect)

## Overview

**Enemy System** est l'ensemble des entités hostiles — humanoïdes statiques au MVP, archétypes mobiles aux tiers supérieurs — que le joueur affronte au katana dans chaque salle de la tour Arasaka. Au cœur du système : la règle d'asymétrie inviolable du jeu — **un coup, mort, des deux côtés**. Tous les ennemis standards sont des cibles à 1 PV strict ; ils tuent le joueur en 1 hit, et meurent en 1 hit du katana. Le boss final est l'unique exception architecturée séparément (système Boss dédié, post-MVP).

Du point de vue *infrastructure*, chaque ennemi est un nœud `CharacterBody3D` (collision layer 2 — `LAYER_ENEMY`) doté d'une `Area3D` lethal hitbox (layer 3 — `LAYER_ENEMY_HITBOX`) qui blesse mortellement le joueur quand actif. Le système expose une API minimale lue par Combat (`die()` idempotent, `is_dead() -> bool`) et émet ses propres signaux consommés par Credit Economy, VFX, Audio, et HUD. Combat reste l'autorité unique du kill — Enemy ne se tue jamais lui-même hors de l'ordre `enemy.die()` reçu du sweep katana.

Du point de vue *player-facing*, les ennemis sont les **panneaux indicateurs du flow** : leur position dans la salle dicte l'angle d'approche, la chaîne de mouvements optimale, et la pression temporelle. Au MVP, un seul archétype existe — le **Grunt** — sentinelle immobile braquant un laser frontal en cône télégraphié. Le joueur doit sortir du cône avant la fenêtre lethal et toucher le grunt par le côté ou par derrière. Cette mécanique simple suffit à enseigner les trois leçons fondamentales du jeu : (1) lire la salle avant d'agir, (2) le mouvement est la seule défense, (3) le katana exige proximité. Les Tiers 2+ ajouteront 4 archétypes supplémentaires (sentinelle pivotante, brute proximité, drone aérien, sniper longue portée) qui élargissent le vocabulaire de menace sans rompre l'invariant one-shot.

## Player Fantasy

> *« L'ennemi n'est pas un adversaire — c'est un panneau indicateur de ma chorégraphie. Sa géométrie me dicte ma trajectoire. Sa mort est la coda de ma phrase de mouvement. »*

**Émotion cible** : *lecture spatiale instantanée → résolution chorégraphique → catharsis du clac.* Le grunt MVP est une **fixture lethale dans le décor**, pas un combattant. Le joueur ne veut pas « battre » le grunt — il veut **traverser** la salle élégamment, et le grunt est l'obstacle géométrique qui rend cette traversée intéressante. Son cône laser est une zone interdite au sol, exactement comme un précipice ou un mur ; sa hitbox est un point de passage obligé, exactement comme un secret à toucher. Lire la salle = lire ses grunts. Sortir du cône + atteindre le côté/dos en wall-run/dash = la phrase de mouvement. Le clac qui suit n'est pas une récompense d'efficacité tactique — c'est la **note finale d'un solo de batterie**.

**Trois sensations ancrées par archétype** (MVP = Grunt seul, Tiers 2+ ajoutent les autres sans casser l'invariant) :

1. **Lecture instantanée** (Pillar 1 FLOW) : en entrant dans une salle, le joueur identifie en < 0.5 s la position de chaque grunt et l'orientation de chaque cône lethal. La silhouette du grunt + la couleur rouge du cône (art-bible État 1 — la seule couleur d'accent rouge réservée à l'hostile) doivent être lisibles comme des panneaux de signalisation. Pas de surprise : si tu meurs, c'est parce que tu n'as pas lu — pas parce que le grunt « t'a eu ».

2. **Tension du cône** (Pillar 1 — la friction qui rend le flow nécessaire) : tant que le joueur est dans la projection du laser, chaque tick est mortel. Cette pression continue est ce qui transforme un déplacement banal en chorégraphie. Le mouvement n'est pas optionnel — c'est la seule forme de défense (anti-pillar : pas de garde, pas de heal, pas de cover-shooter). Le cône n'est jamais un piège injuste : il est toujours visible, toujours statique au MVP, toujours sortable par dash ou wall-run pour qui a regardé la salle.

3. **Coda du clac** (Pillar 1 + spillover Combat) : le grunt mort = la fin propre d'une phrase. Pas de cri de douleur, pas de chute en ragdoll étendue, pas de loot — juste un *clac* sec, un flash blanc 50 ms, un splash de sang brut, une disparition tween 150 ms. La satisfaction est **kinesthésique**, pas narrative. Le joueur n'a pas « vaincu un ennemi » — il a **complété un mouvement**.

**Sensation par-dessus tout : la mort pédagogique** (Pillar 3 SECONDE CHANCE)

Quand le joueur meurt par laser grunt, **le grunt reste à sa place exacte**, dans la même posture, avec le même cône actif. Il n'est ni rejoué, ni recyclé — il était là quand tu es entré dans la salle, il est encore là quand tu respawn. Cette persistance est volontaire et porteuse : *« voici précisément ce que tu n'avais pas lu — relit-le maintenant »*. Aucun message à l'écran, aucun « Try again » — juste l'évidence spatiale de l'erreur. Le joueur respawn, voit le même grunt, et **comprend** sans qu'on le lui dise. Cette boucle apprentissage-mort-respawn-apprentissage est la promesse de Pillar 3 incarnée par le système Enemy.

**Références jouables qui ancrent le feel** :

- **Ghostrunner** (One More Level, 2020) : grunt-rifleman statique = même pattern, même portée laser visible, même one-shot mutuel. À copier littéralement pour la lisibilité du cône et la pédagogie de la mort.
- **Hotline Miami** (Dennaton Games, 2012) : la « danse » entre cibles statiques sur arène dense — *le rythme staccato vient de la rapidité du retry*, pas de la complexité IA. Le grunt MVP doit donner cette même sensation de *try-die-retry < 3 s* boucle.
- **DOOM Eternal** (id Software, 2020) : *enemy as puzzle* — chaque ennemi a une faiblesse géométrique (entrer dans la portée close, frapper au point faible). Au MVP, le « point faible » du grunt est trivial (n'importe quel hit = mort), mais la **géométrie d'approche** est le puzzle.

**Anti-fantasy explicit (ce qu'on ne sert PAS)** :

- ❌ *Power fantasy de domination* : le joueur n'est pas plus fort que le grunt — la symétrie one-shot interdit cette lecture. Le pouvoir du joueur est la **mobilité**, pas la **létalité supérieure**.
- ❌ *Tactical fantasy* : pas de couverture, pas de prise de flanc IA-aware, pas de gestion de ressources. Le grunt MVP ne « pense » pas — il oriente son cône et tire. C'est une fixture, pas un adversaire.
- ❌ *Loot fantasy* : pas de chute d'objets, pas de butin (les crédits viennent du kill mais sont gérés par Credit Economy, pas par Enemy — le grunt est ascétique).
- ❌ *Empathie / narration* : pas de voix, pas de réaction émotionnelle à la mort, pas d'animation de souffrance. Le grunt est un robot du décor — son humanoïdité visuelle est purement géométrique (silhouette lisible).

## Detailed Rules

### Core Rules

1. **One-shot strict, mutuel** (invariant Pillar 1, anti-pillar #5 game-concept) — tout `Enemy` standard MVP est à 1 PV strict. Aucun damage system, aucun PV variable, aucun shield. Recevoir un `enemy.die()` de Combat ⇒ transition immédiate `Alive → Dying`. La symétrie inverse est garantie côté Player (laser → `Player.die()` immédiat). Le boss final est le **seul** système autorisé à dévier de cette règle, via un système Boss séparé post-MVP.

2. **MVP scope = un seul archétype : Grunt** (game-concept §269 #4 — *« 1 type d'ennemi (grunt statique avec laser frontal) »*). Le système est conçu pour absorber 4 archétypes Tier 2+ supplémentaires (sentinelle pivotante, brute proximité, drone aérien, sniper longue portée) sans rompre l'invariant `one_shot = true`, mais **aucun de ces archétypes n'est livré au MVP**. La factory Enemy doit accepter un `archetype: StringName` paramètre dès le MVP pour ne pas faire de churn d'API au Tier 2.

3. **Architecture du nœud Grunt MVP** (canonical scene `res://src/gameplay/enemy/grunt.tscn`) :

   ```
   Grunt: CharacterBody3D                 (layer 2 LAYER_ENEMY, mask 8 LAYER_ENVIRONMENT)
   ├── CollisionShape3D                   (CapsuleShape3D, radius=0.35 m, height=1.8 m)
   ├── MeshInstance3D                     (silhouette humanoid primitive, ChromeZenFlat)
   ├── %FacingPivot: Node3D               (rotation horizontale du corps, oriente le cône laser)
   │   └── %LaserCone: Area3D             (layer 3 LAYER_ENEMY_HITBOX, mask 1 LAYER_PLAYER, monitoring=true)
   │       ├── CollisionShape3D           (BoxShape3D — cône approximé par rectangle horizontal, 6 m × 0.5 m × 0.3 m)
   │       └── MeshInstance3D             (Quad émissif rouge — visualise le cône lethal)
   └── %DeathTween: Node                  (pas de Tween node — script-side `create_tween()`)
   ```

   - Le `%FacingPivot` permet à un futur archétype « sentinelle pivotante » Tier 2 de réutiliser la même hiérarchie en pilotant la rotation du pivot ; au MVP, `FacingPivot.rotation` est figée à l'orientation de spawn lue depuis `EnemySlot.global_basis` (cf Rule 9).
   - Pas de `Skeleton3D`, pas d'animation `AnimationPlayer` au MVP. Le grunt est rigide, son seul mouvement visuel est le tween de mort (Rule 11).

4. **Collision contract figé** (ADR-0008 + entries registry `LAYER_ENEMY = 2`, `LAYER_ENEMY_HITBOX = 3`, `LAYER_ENVIRONMENT = 4`, `LAYER_PLAYER = 1`) :

   | Nœud | Layer | Mask | Justification |
   |---|---|---|---|
   | `Grunt: CharacterBody3D` (body) | `2` (LAYER_ENEMY) | `8` (LAYER_ENVIRONMENT) | Détecté par Player.mask⊃2 et par Katana ShapeCast.mask=2 ; détecte uniquement environnement (collision navigation, mais pas d'auto-nav MVP donc dormant) |
   | `LaserCone: Area3D` (hitbox lethal) | `3` (LAYER_ENEMY_HITBOX, 1-indexed Godot convention = bit `0b00000100`) | `1` (LAYER_PLAYER) | Touche le Player exclusivement — pas d'enemies auto-touchables, pas de murs, pas de katana qui « parerait » le laser |

   ⚠️ **Convention 1-indexée Godot** : tous les `set_collision_layer_value(N, true)` utilisent N = 1-based (LAYER_ENEMY = 2 → bit 1 = `set_collision_layer_value(2, true)`). Source de vérité : ADR-0008.

5. **`r_enemy_min = 0.35 m`** est le **rayon de capsule canonique d'un Enemy standard MVP** (registry candidate — voir §Tuning Knobs). Combat (Section D.3) consomme cette valeur comme borne basse pour le sizing du sweep ShapeCast (gap_max = V × delta / N_SUBSTEPS < 2 × r_enemy_min = 0.7 m). Tout futur archétype DOIT respecter `r ≥ 0.35 m` ou amender le contrat via PR cross-Combat.

6. **`die()` idempotent** (Combat r5 BLOCK-r5-godot-B4 contract) — l'API publique `enemy.die() -> void` peut être appelée N fois ; seule la première transition `Alive → Dying` émet le signal `enemy_killed`, les appels suivants sont des no-ops silencieux. Pattern d'implémentation aligné Movement F6 :

   ```gdscript
   func die() -> void:
       if _state != State.ALIVE:
           return  # idempotent — déjà en Dying ou Dead
       _state = State.DYING
       enemy_killed.emit(self, global_position)
       _start_death_tween()
   ```

   Combat tient une double-sécurité avec sa liste `_hit_this_swing` (Combat Rule 9 + Rule 11), donc Enemy n'a pas besoin de tracker quel sweep l'a tué — juste de garantir l'idempotence côté Enemy.

7. **Authority of kill exclusivement via `die()` externe** — un Enemy ne décide jamais seul de mourir. Les seules sources légitimes d'appel `die()` au MVP :
   - **Combat sweep katana** (autorité primaire — Combat Rule 9) : appel direct `enemy.die()` quand le ShapeCast hit le `CharacterBody3D` Enemy.
   - **Hazard System** (Tier 2+ — POST MVP) : un piège environnemental pourrait appeler `enemy.die()`. Au MVP, aucun Hazard ne touche les ennemis.
   - **Boss System** (post-MVP) : un boss pourrait pousser un ennemi dans le vide. Hors scope MVP.
   - ❌ **JAMAIS** : timer, AI auto-suicide, fall damage, out-of-bounds. Le grunt MVP est statique — il ne tombe pas, ne sort pas du monde.

8. **Détection lethal → `Player.die()`** (Combat Rule 14 contract) — le LaserCone Area3D Enemy connecte son signal `body_entered(body: Node3D)` à un handler interne qui :
   ```gdscript
   func _on_laser_cone_body_entered(body: Node3D) -> void:
       if _state != State.ALIVE:
           return  # un grunt mort ne tue plus
       if body.is_in_group("player") and body.has_method("die"):
           body.die()  # Movement-owned, voir Movement GDD Rule die()
   ```
   - Le `_state != State.ALIVE` guard interdit qu'un grunt en `Dying` (tween 150 ms en cours) tue encore via son cône — le cône doit être **désactivé immédiatement à la transition `Alive → Dying`** (Rule 11.b).
   - L'usage du group `"player"` plutôt qu'un cast `as MovementController` évite de coupler Enemy à `MovementController` (Player Movement-owned). Combat Rule 14 stipule que c'est l'Enemy System qui appelle `Player.die()`, pas Combat — Enemy assume cette responsabilité.

9. **Spawn depuis `EnemySlot` Marker3D** (Level System R-2.6 contract) — au boot d'un étage (`LevelSystem._on_level_active`), un `EnemySpawner` (autoload ou Service Locator pattern, ADR à figer Sprint 1 si nécessaire) parcourt tous les nœuds nommés `EnemySlot_*` dans la scène d'étage chargée, lit leur `global_transform`, et instancie un `Grunt.tscn` à chaque slot :
   - `Grunt.global_position = EnemySlot.global_position`
   - `Grunt.%FacingPivot.global_basis = EnemySlot.global_basis` (l'orientation du Marker3D dicte la direction du cône laser — l'auteur du niveau peint son intention de cône en orientant le Marker dans l'éditeur Godot).
   - Optional metadata `EnemySlot.set_meta("archetype", "grunt")` pour le Tier 2+ ; au MVP toujours `"grunt"`.

10. **Pas d'AI auto-pathfinding MVP** — un Grunt MVP est strictement statique. `_physics_process` est désactivé (`set_physics_process(false)` au `_ready`), `velocity` reste `Vector3.ZERO` à perpetuité. Le seul comportement runtime est :
    - Detection lethal hit (signal-driven, Rule 8 — handler Area3D body_entered)
    - Reception de `die()` (API publique, Rule 6)
    - Death tween (script-side, Rule 11)

    ➡️ **Aucun NavigationAgent3D, aucun raycast, aucun timer de tick au MVP.** Cela garantit que 30 grunts simultanés dans un étage ont un coût `_process` total proche de zéro.

11. **Death sequence** (transition `Alive → Dying → Dead → free`) en 4 étapes ordonnées dans `die()` :

    a. `_state = State.DYING` (atomic guard pour idempotence Rule 6 + désactivation lethal Rule 8).
    b. `LaserCone.monitoring = false` (immédiat — un grunt en Dying ne tue plus, même pendant les 150 ms de tween).
    c. `enemy_killed.emit(self, global_position)` — payload SYNC (pas de CONNECT_DEFERRED côté émetteur, conforme Combat Rule 11 contract). Consommé par Credit Economy, VFX, Audio, HUD.
    d. **Tween wall-clock obligatoire** :
       ```gdscript
       var t: Tween = create_tween()
       t.set_ignore_time_scale(true)  # ⚠️ OBLIGATOIRE — sans ça, Engine.time_scale=0.3 (slow-mo Combat) ralentit le tween
       # set_pause_mode() est laissé à son default TWEEN_PAUSE_BOUND : le tween reste pausé quand tree.paused = true (EC-ENM-9)
       t.tween_property(%MeshInstance3D, "scale", Vector3(EPSILON, EPSILON, EPSILON), DEATH_TWEEN_DURATION_MS / 1000.0)
       t.tween_callback(_on_death_tween_finished)
       ```
       À la fin du tween (`_on_death_tween_finished`), `_state = State.DEAD` puis **pas de `queue_free()`** — voir Rule 12.

       ⚠️ **Note Godot 4.6 — séparation pause vs time_scale** :
       - `Tween.set_ignore_time_scale(true)` : tween indépendant de `Engine.time_scale` (ignore le slow-mo Combat). C'est cette ligne qui matérialise la propriété « wall-clock absolu » de F-ENM-3.
       - `Tween.set_pause_mode()` (default `TWEEN_PAUSE_BOUND`) : tween pausé quand `tree.paused = true`. C'est le comportement attendu par EC-ENM-9 (Pause GSM gèle le tween, resume reprend).
       - Si `set_ignore_time_scale(true)` est omis, F-ENM-3 est violé (tween dure 500 ms wall-clock pendant slow-mo 0.3× au lieu de 150 ms).
       - Si `set_pause_mode(TWEEN_PAUSE_PROCESS)` était utilisé, EC-ENM-9 serait violé (tween continue pendant pause GSM).
       Cf review-r1 BLOCKING-3 — la résolution canonique sépare les deux APIs.

12. **Pas de `queue_free()` au MVP** (déviation explicite vs prototype `prototypes/movement-katana/enemy.gd`) — le grunt mort reste dans la scène en état `Dead`, son `MeshInstance3D` à scale 0.01 (invisible mais présent), son `LaserCone` désactivé. Justification :
    - **Pillar 3 mort pédagogique** : si Player meurt après avoir tué grunt, au respawn checkpoint le grunt doit rester mort (sa kill survit la mort joueur — récompense du progrès). Garder le nœud permet au Checkpoint System de capturer son état (`is_dead()`) dans son snapshot et de le restaurer au respawn.
    - **Idempotence Combat** : Combat utilise `instance_from_id(id)` + `is_instance_valid()` (Combat r5 BLOCK-r5-godot-B4) pour ses hits historiques. Si Enemy fait `queue_free()`, `is_instance_valid()` devient false → safe mais sous-optimal pour debug `debug_hits_last_swing`. Garder le nœud rend le debug plus simple.
    - **Coût mémoire négligeable** : ~30 grunts par étage × ~2 KB par instance = 60 KB. Aucun risque budget MVP.
    - **Cleanup au level unload** : le grunt mort est libéré par `LevelSystem.unload_etage` qui `queue_free()` la scène d'étage racine (transitive cleanup).

13. **Persistance d'état entre respawns Player** (cross-system contract avec Checkpoint System — à confirmer dans le Checkpoint GDD futur) :
    - Tant que le checkpoint actif n'a pas changé, **les grunts morts restent morts** au respawn Player.
    - Quand le Player passe un nouveau checkpoint, le **snapshot Enemy** est mis à jour (le Checkpoint System capture la liste des `is_dead()` des grunts présents à ce moment) — au futur respawn depuis ce checkpoint, seuls les grunts vivants au moment du snapshot sont restaurés vivants.
    - **Impl MVP minimale** : Checkpoint System fait `enemy_node.set_meta("snapshot_dead", enemy.is_dead())` au passage de checkpoint, puis au respawn lit ces metas et appelle `enemy._restore_from_snapshot(was_dead)`. Method `_restore_from_snapshot(was_dead: bool)` est une API publique d'Enemy.
    - Au level reload (`reload_etage`), tous les grunts respawn vivants — c'est la « complete reset » du Level System (Level GDD Rule 6).

### States and Transitions

| State | Entry condition | Exit condition | Behavior |
|---|---|---|---|
| `ALIVE` | `_ready()` ou `_restore_from_snapshot(false)` | `die()` reçu (autorité externe Rule 7) | LaserCone monitoring=true ; détecte Player et appelle `Player.die()` ; rendu visible scale 1 |
| `DYING` | `die()` 1ère fois (idempotent Rule 6) | tween scale 0.01 fini après 150 ms | LaserCone monitoring=false ; `enemy_killed` signal émis SYNC à l'entrée ; tween scale en cours |
| `DEAD` | tween scale fini (`_on_death_tween_finished`) | `_restore_from_snapshot(false)` ou unload étage | Nœud présent mais invisible (scale 0.01) ; pas d'émission, pas de détection ; `is_dead()` renvoie `true` |

**Transitions valides** :
- `ALIVE → DYING` : seule transition de mort, déclenchée par `die()` externe (Rule 7).
- `DYING → DEAD` : automatique post-tween 150 ms.
- `DEAD → ALIVE` : seulement via `_restore_from_snapshot(false)` au respawn Checkpoint (Rule 13).
- `ALIVE → DEAD` : interdit (toujours passer par DYING pour préserver le tween + signal).
- `DEAD → DYING` : interdit (un mort ne re-meurt pas).
- `DYING → ALIVE` : interdit (un tween de mort ne s'annule pas — sauf au unload étage qui détruit tout).

### Interactions with Other Systems

| Système | Direction | Interface | Contrat |
|---|---|---|---|
| **Level System** (amont) | Direct spawn | LevelSystem itère ses propres `EnemySlot_*` Marker3D au signal `level_active` et instancie `Grunt.tscn` à chaque slot avec `EnemySlot.global_basis` orientation. **Pas d'API publique `get_etage_enemy_slots()`** — Level est la factory directe au MVP (OQ-ENM-2 résolu review-r1, voir §Open Questions). Contract **Level GDD R-2.6** : ARENA ≥3 EnemySlot, COMBAT room ≥3 EnemySlot, FirstEnemySightline garanti | Authoring time : EnemySlot Marker3D placés dans `.tscn` étage. Boot time : Level itère + spawn |
| **Player Combat System** (aval) | Receive call + listen signal | `enemy.die() -> void` (call) + écoute `enemy_killed` (signal) | Combat appelle `enemy.die()` à chaque collider hit du sweep ShapeCast (idempotent Rule 6). **Enemy émet `enemy_killed(node, position)` SYNC** depuis `die()` (Rule 11.c) ; Combat se connecte à ce signal pour déclencher slow-mo `Engine.time_scale = 0.3` 50 ms wall-clock (Combat Rule 13). **Enemy est l'autorité d'émission** — Combat n'émet pas son propre `enemy_killed` (OQ-ENM-1 résolu review-r1 → amendement Combat r7 requis, voir §Cross-system note ci-dessous) |
| **Player Movement** (aval, indirect) | Send call | `Player.die() -> void` | LaserCone Area3D body_entered → `body.die()` si `body.is_in_group("player")`. Movement-owned die() (Movement GDD Rule die()) gère le tween fade rouge + Pillar 3 respawn |
| **Checkpoint & Respawn System** (aval, post-MVP) | Read/Write meta | `enemy.is_dead() -> bool`, `enemy._restore_from_snapshot(was_dead: bool)` | Checkpoint capture `is_dead()` au passage ; au respawn restaure via `_restore_from_snapshot`. Rule 13 contract |
| **Credit Economy** (aval, post-MVP) | Receive signal | `Enemy.enemy_killed(node, position)` | Credit System se connecte à **`Enemy.enemy_killed`** (pas `CombatSystem.enemy_killed` — Enemy est l'autorité, OQ-ENM-1 résolu) ; chaque kill = +X crédits selon archetype (MVP grunt = 1 credit ?) |
| **VFX & Feedback System** (aval, post-MVP) | Receive signal | `Enemy.enemy_killed(node, position)` | VFX se connecte à **`Enemy.enemy_killed`** ; flash blanc 50 ms + splash sang à `position` ; flash en connexion SYNC (frame-precise avec kill tick — Combat Rule 13). Le tween de scale 150 ms est géré par Enemy lui-même au MVP (pas externalisable au VFX System) |
| **Audio System** (aval, APPROVED r2.1) | Receive signal | `Enemy.enemy_killed(node, position)` | Audio se connecte à **`Enemy.enemy_killed`** ; joue le clac sur bus `combat_kill` à `position` 3D (positional). Source de vérité bus name : Audio GDD Rule 11 + ADR-0009 D-1. Audio GDD r2.1 est neutre sur la source du signal (pas de mention `CombatSystem.enemy_killed`) — la résolution OQ-ENM-1 est transparente |
| **HUD / UI System** (aval, post-MVP) | Receive signal | `Enemy.enemy_killed(node, position)` | HUD se connecte à **`Enemy.enemy_killed`** ; peut afficher kill count, combo timer, etc. Optional consumer — le kill count fait partie du compteur global, pas Enemy-owned |
| **Hazard System** (cousin, Tier 2+) | Receive call | `enemy.die()` | Au Tier 2+, un piège environnemental pourrait appeler `enemy.die()` (Rule 7). Au MVP, contract latent — aucun Hazard MVP |
| **Game State Manager** (amont, APPROVED r1) | Read state | `GameStateManager.get_current_state() -> State` | Enemy n'agit que si `state == PLAYING`. Si state passe à `PAUSED` ou `MENU`, Enemy gèle (LaserCone monitoring=false ; tween paused via `tree.paused = true` propagation natif Godot) |

## Formulas

Enemy System MVP a **peu de math interne** — le grunt est statique et 1-PV strict, donc pas de damage curve, pas de scaling, pas d'IA scoring. Les formules ci-dessous documentent (1) les dimensions géométriques du LaserCone et de la capsule, (2) la courbe du death tween, et (3) les **cross-references obligatoires** vers les formules d'autres systèmes qui consomment des constantes Enemy.

### F-ENM-1 : Capsule grunt (collision body)

La capsule de collision du `Grunt: CharacterBody3D` est définie par :

`capsule_radius = r_enemy_min`
`capsule_height = HEIGHT_GRUNT_M`

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `r_enemy_min` | r | float | constant `0.35 m` | Rayon canonique d'un Enemy standard MVP. **Source de vérité Enemy GDD §Tuning Knobs** — registry candidate. |
| `HEIGHT_GRUNT_M` | h | float | constant `1.8 m` | Hauteur capsule grunt humanoid. Aligné silhouette concept art Tier 1, et place le centre de cône laser à 0.9 m sol = hauteur torse joueur. |

**Output** : `CapsuleShape3D` avec `radius = 0.35`, `height = 1.8`. Total volume occupé sol-au-plafond = `π × 0.35² × 1.8 = 0.69 m³`.

**Example** : un grunt placé à `EnemySlot.global_position = (5.0, 0.0, 10.0)` occupera la zone X∈[4.65, 5.35], Y∈[0.0, 1.8], Z∈[9.65, 10.35].

**Edge case** : si un futur archetype Tier 2+ (e.g. drone aérien) pose un `r < 0.35 m`, **violation contract Combat F.gap_max** (cf cross-ref ci-dessous). Tout amendement doit passer par PR cross-Combat + amendement registry.

---

### F-ENM-2 : LaserCone hitbox geometry

Le LaserCone Area3D est approximé par un `BoxShape3D` (pas un vrai cône — économie de polygones et collision check, lisibilité visuelle suffisante au MVP avec plan émissif rouge sur la face frontale du box) :

`box_size = Vector3(LASER_WIDTH_M, LASER_HEIGHT_M, LASER_RANGE_M)`

Le box est positionné devant le grunt avec son origine au point `Grunt.%FacingPivot.global_position + FacingPivot.basis.z * (LASER_RANGE_M / 2)` (centre du box à mi-portée, faces avant/arrière perpendiculaires au regard).

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `LASER_WIDTH_M` | w | float | constant `0.50 m` | Largeur horizontale du cône — étroit pour permettre side-step (player capsule radius 0.4 m, donc dodge 0.1 m de marge nominal). |
| `LASER_HEIGHT_M` | hl | float | constant `0.30 m` | Hauteur verticale du cône — étroit aussi pour permettre saut/wall-run par-dessus. Centré au milieu du grunt (Y = 0.9 m du sol). |
| `LASER_RANGE_M` | r | float | constant `6.0 m` (default) ; tunable per-slot via `EnemySlot.set_meta("laser_range", X)` | Portée de mort. À 6 m, couvre la largeur typique d'une salle linéaire MVP (Level GDD §Salles 5-10 m de large). |

**Output** : `BoxShape3D.size = Vector3(0.5, 0.3, 6.0)`, volume effectif `0.9 m³`.

**Example** : grunt placé en `(5, 0, 10)` orienté `+Z` → LaserCone box couvre approximativement X∈[4.75, 5.25], Y∈[0.75, 1.05], Z∈[10, 16]. Player en `(5, 0, 13)` est mort à l'instant où il rentre dans la box.

**Edge case** : si le LaserCone se chevauche avec un wall (LAYER_ENVIRONMENT) au level-time, c'est une **erreur d'authoring** que Level System doit catch via lint. Au runtime, l'overlap mur n'a aucun effet (LaserCone ne mask que LAYER_PLAYER) mais visuellement le rendu émissif rouge traversera le mur — anomalie. Lint Level futur : `validate_enemy_slot_laser_clearance()` warn si la box LaserCone projetée intersecte un static body.

---

### F-ENM-3 : Death tween scale curve

Le tween de disparition du `MeshInstance3D` au `Alive → Dying → Dead` :

`mesh.scale(t) = lerp(Vector3.ONE, Vector3(EPSILON, EPSILON, EPSILON), clamp(t / DEATH_TWEEN_DURATION_MS, 0.0, 1.0))`

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `t` | t | float | `[0, 150]` ms wall-clock depuis `die()` 1ère appel | Temps écoulé depuis transition `Alive → Dying`. Wall-clock ABSOLU (pas Engine.time_scale-affected) — la propriété est garantie par `Tween.set_ignore_time_scale(true)` au create_tween (Rule 11.d). Le tween reste 150 ms même pendant le slow-mo Combat 50 ms × 0.3. **Note** : pause GSM (`tree.paused = true`) gèle quand-même le tween — c'est le comportement attendu (EC-ENM-9), géré par le default `TWEEN_PAUSE_BOUND`. |
| `DEATH_TWEEN_DURATION_MS` | T | int | constant `150 ms` | Durée du tween. Aligné prototype `enemy.gd:tween_property(..., 0.15)`. Suffisamment long pour que le clac/flash blanc de Combat (50 ms slow-mo) soit clairement séparé du fade visuel. |
| `EPSILON` | ε | float | constant `0.01` | Scale final non-zéro pour éviter `Vector3.ZERO` qui pose des artefacts numériques sur certains shaders Godot 4.6. À 0.01 le mesh est invisible à l'œil nu (1% de sa taille originale, sub-pixel à distance > 2 m). |

**Output** : à `t = 0` mesh à scale 1 ; à `t = 75 ms` mesh à scale ~0.5 (mi-fondu) ; à `t = 150 ms` mesh à scale 0.01 (invisible).

**Example timeline pour un kill** :
```
t=0 ms     : Combat sweep hit grunt → die() → state=DYING + LaserCone off + enemy_killed.emit() + Engine.time_scale=0.3 (Combat Rule 13)
t=0-50 ms  : slow-mo perçue (clac, flash blanc Combat, splash sang VFX) — wall-clock 50 ms = perçu 167 ms
t=50 ms    : Engine.time_scale=1.0 restored ; tween Enemy continue à wall-clock pace
t=150 ms   : tween fini → state=DEAD ; nœud invisible, persisté pour Checkpoint
```

**Edge case** : si Enemy reçoit `die()` pendant `state=DYING` (idempotent Rule 6), le tween en cours **n'est PAS reset** — la 2ème call est no-op silencieux.

---

### Cross-system formula references

Les formules ci-dessous appartiennent à d'autres GDDs mais **consomment des constantes Enemy** ou **dictent des contraintes sur Enemy**. Elles sont citées ici pour bidirectionnalité — toute modification d'Enemy doit vérifier la non-rupture côté consommateur.

| Formula owner | Formula | Consumes Enemy constant | Constraint imposed |
|---|---|---|---|
| **Combat GDD §D.3** | `gap_max = V_player × delta / N_SUBSTEPS` doit rester `< 2 × r_enemy_min` | `r_enemy_min = 0.35 m` | Si Enemy diminue `r_enemy_min`, Combat doit augmenter `N_SUBSTEPS` proportionnellement OU réduire `V_max_player`. Cap actuel : `V_max = 30 m/s` × `delta = 1/60 s` / `N_SUBSTEPS = 4` = `0.125 m < 2 × 0.35 = 0.7 m` ✅ marge |
| **Level GDD F1** | `min_opening_width = 2 × KATANA_REACH = 3.6 m` | `KATANA_REACH = 1.8 m` (Combat-owned) | Couloirs ≥ 3.6 m garantissent le sweep katana atteint un grunt centré. Enemy n'impose rien à Level via cette formule |
| **Audio GDD F3** | `pool_3d_size = 12` (combat_kill bus) | Max enemies simultanés tuables au tick T | Estimation max kills/swing = `MAX_KILLS_PER_SWING = 3` (Combat) × ~1 swing/seconde × pool décroche post-150 ms → 12 voices suffisent |
| **Level GDD F7** | `secret_count = clamp(floor(room_count / SECRET_DENSITY_DIVISOR), 3, 5)` | Aucune dépendance Enemy directe | Référence informative — secrets et grunts coexistent dans la même salle ARENA mais sont placés indépendamment |
| **Credit Economy GDD** (futur, Not Started) | `credit_amount_per_kill = CREDIT_VALUE[archetype]` | `archetype: StringName` | Au MVP avec 1 archetype, `CREDIT_VALUE["grunt"] = 1` (à confirmer dans Credit Economy GDD) |

## Edge Cases

- **EC-ENM-1 — `die()` appelé sur grunt déjà `DYING`** : no-op silencieux. Le 2ème `die()` retourne immédiatement (Rule 6 idempotent guard `_state != ALIVE`). Aucun signal `enemy_killed` 2ème emit, aucun reset du tween en cours, aucun warning console. Justification : Combat `_hit_this_swing` (Combat Rule 11) doit déjà filtrer, mais Enemy assume la double-sécurité.

- **EC-ENM-2 — `die()` appelé sur grunt déjà `DEAD`** : no-op silencieux (même guard Rule 6). Cas typique : Combat appelle `die()` dans un sweep dont la liste de hits inclut un instance_id de grunt déjà tué dans un sweep précédent (situation possible si `is_instance_valid()` true mais state == DEAD). Robust no-op.

- **EC-ENM-3 — Player traverse LaserCone exactement au tick où grunt entre `DYING`** : si le `body_entered` Area3D signal et le `die()` externe arrivent dans le même `_physics_process` tick, **l'ordre dépend de l'ordre DFS preorder du scene tree** (parent avant enfant — ADR-0006 Combat tick model). Cas analysés :
  - **Cas A** : Combat (parent ou peer DFS antérieur) sweep tue grunt en premier → grunt._state = DYING + LaserCone.monitoring = false **avant** le body_entered. Player survit. ✅ comportement souhaité (le grunt « stop tirer » à l'instant où il meurt).
  - **Cas B** : Le body_entered fire avant le sweep Combat (rare — physics body_entered est evt physics step, Combat sweep est `_physics_process` script tick). Player.die() est appelé. Tick suivant Combat resolve sweep, grunt.die(). Mutual kill résolu (Combat Rule 17 r2 Option C). ✅ comportement Combat-canonical.

- **EC-ENM-4 — Player traverse LaserCone d'un grunt `DEAD`** : `body_entered` fire mais le handler `_on_laser_cone_body_entered` retourne immédiatement (Rule 8 guard `_state != ALIVE`). De plus, `LaserCone.monitoring = false` au passage `Alive → Dying` (Rule 11.b) **désactive le signal** dès l'instant de mort. Donc le `body_entered` ne devrait même pas fire pour un grunt mort, sauf si Player est rentré dans la box pendant les ~0 ms entre l'eval du `monitoring = false` et le polling collision. Double-sécurité avec le state guard.

- **EC-ENM-5 — Deux LaserCone se chevauchent (deux grunts proches)** : Player rentre dans l'overlap → `body_entered` fire **2 fois** (un par Area3D). Chacun appelle `Player.die()`. **Player.die() doit être idempotent côté Movement** (Movement GDD Rule die()). Movement absorbe le 2ème call sans crash, sans double respawn. ✅ contrat Movement existant suffit. Pas de tracking croisé entre grunts requis.

- **EC-ENM-6 — Grunt instancié avec `EnemySlot.global_basis` non-orthonormale** : si l'auteur de niveau a un Marker3D scaled différemment, l'orientation copiée à `%FacingPivot.global_basis` peut produire un cône déformé visuellement. **Lint Level System obligatoire** (à ajouter au futur `validate_enemy_slot_marker3d`) : warn si `EnemySlot.basis.is_normalized() == false` ou si `EnemySlot.scale != Vector3.ONE`. Au runtime, normalisation forcée : `FacingPivot.global_basis = EnemySlot.global_basis.orthonormalized()`.

- **EC-ENM-7 — `EnemySlot` placé dans un secteur sans walkable space (e.g. dans un mur, au plafond)** : grunt instancié et bloqué dans la géométrie. La capsule rouge (mesh émissif) sera invisible derrière le mur. Pas de crash, juste un grunt « inutile » non-tuable. **Lint Level System obligatoire** (à ajouter à `validate_enemy_slot_clearance`) : raycast vertical ± 1 m depuis `EnemySlot.global_position` pour vérifier qu'il y a un sol et headroom.

- **EC-ENM-8 — Plusieurs grunts EnemySlot collisionnent** : capsules grunt occupent la même zone → Jolt physics push automatiquement. Comportement non-blocking mais visuel laid (grunts qui « glissent »). **Lint Level System obligatoire** : `validate_enemy_slot_min_distance` warn si distance entre 2 EnemySlot < `2 × r_enemy_min + buffer = 1.0 m`.

- **EC-ENM-9 — Grunt en `DYING` reçoit Pause (`GameStateManager.state = PAUSED`)** : `tree.paused = true` (autorité GameStateManager — GSM GDD AC-PAUSE-1) propage à l'arbre scene → le tween Enemy est pausé natif Godot via `Tween.set_pause_mode` default = `TWEEN_PAUSE_BOUND` (cf Rule 11.d). Au resume, tween continue depuis l'instant de pause. Wall-clock total = 150 ms hors temps de pause. ✅ Comportement assuré par la séparation API : `set_ignore_time_scale(true)` ignore slow-mo MAIS pas la pause tree (default `TWEEN_PAUSE_BOUND` actif).

- **EC-ENM-10 — Grunt en `ALIVE` reçoit Pause** : `tree.paused = true` propage → `_physics_process` désactivé (déjà désactivé par Rule 10 d'ailleurs) ; LaserCone Area3D `monitoring` reste à true mais Godot suspend les body_entered events tant que paused. Au resume, si Player s'est téléporté pendant la pause (impossible UX MVP mais hypothétique), le body_entered correspondant à la nouvelle position fire au tick de resume.

- **EC-ENM-11 — `_restore_from_snapshot(true)` appelé sur grunt actuellement `ALIVE`** : transition vers DEAD direct sans tween (snapshot dit qu'il était mort à ce checkpoint, donc forcer DEAD). Implémentation : `_state = State.DEAD; LaserCone.monitoring = false; mesh.scale = Vector3(EPSILON, EPSILON, EPSILON)`. Pas de signal `enemy_killed` (le kill a déjà été crédité au moment de la mort originale, le restore ne doit pas re-créditer).

- **EC-ENM-12 — `_restore_from_snapshot(false)` appelé sur grunt actuellement `DEAD`** : transition DEAD → ALIVE direct. `_state = ALIVE; LaserCone.monitoring = true; mesh.scale = Vector3.ONE`. Pas de signal `enemy_respawned` au MVP (consumers comme HUD/Audio n'en ont pas besoin — cette transition n'arrive qu'au respawn Checkpoint, qui a déjà ses propres signaux). 

- **EC-ENM-13 — `_restore_from_snapshot(X)` appelé pendant `DYING` (tween en cours)** : **abort le tween**, transition immédiate au state cible (ALIVE ou DEAD selon `X`). Justification : le respawn Player force un état canonique — pas de mid-tween survivant. Implémentation : `_death_tween.kill()` puis assignation directe state + mesh.scale.

- **EC-ENM-14 — Combat sweep tue grunt + Player meurt dans le même tick (mutual kill)** : Combat Rule 17 r2 Option C Hybrid résout — Movement DFS preorder execute en premier (Player.die() emit), puis Combat (enfant DFS) execute son sweep (grunt.die() emit). Les deux morts sont résolues, slow-mo Engine.time_scale=0.3 démarre normalement (non-affected par Player dead). VFX flash blanc + splash sang fire pour le kill grunt. Audio combat_kill bus joue le clac. Player respawn 50 ms plus tard via Movement-owned die() pipeline. ✅ Comportement testé Combat AC-CMB-25.

- **EC-ENM-15 — Tous les grunts d'un étage `EnemySlot_count = 0`** : étage légal mais sans menace. EnemySpawner n'instancie rien. ✅ Comportement non-bug — utile pour onboarding salle 1 du level (game-concept §96 « 1ère salle = ennemi immobile ») où la salle 1 PEUT être sans grunt si l'auteur veut un palier de calme. Lint Level System NE doit PAS bloquer count=0 (c'est explicitement permis par Level GDD §archetypes).

- **EC-ENM-16 — Spawn d'un archetype inconnu (`EnemySlot.get_meta("archetype") == "drone")` au MVP** : `EnemySpawner` lit le meta, ne trouve pas de `Drone.tscn` (Tier 2+ pas livré), **fallback** : instancie un Grunt à la place + log `push_warning("Enemy archetype 'drone' unknown — fallback to 'grunt'")`. Justification : ne jamais crasher au level load à cause d'un meta erroné — robustesse > strictness au runtime. Lint Level System catch en authoring time si archetype unrecognized.

## Dependencies

### Hard dependencies (Enemy ne peut pas fonctionner sans ces systèmes)

| Système | Status | Direction | Interface critique |
|---|---|---|---|
| **Level System** (APPROVED r3) | ✅ Designed, ⚠️ partiellement Implemented | Amont | LevelSystem est la **factory directe** des grunts au MVP (OQ-ENM-2 résolu) : itère ses propres `EnemySlot_*` Marker3D au signal `level_active` et instancie `Grunt.tscn` à chaque slot. **Pas d'API publique exposée Enemy → Level** (pas d'`EnemySpawner` autoload séparé). Level R-2.6 garantit ARENA ≥3, COMBAT ≥3, FirstEnemySightline anchoring. Si Tier 2+ exige un EnemyManager dédié, l'API sera extraite alors |
| **Player Combat System** (APPROVED r6) | ✅ Designed | Aval | Combat appelle `enemy.die()` + écoute `enemy_killed`. Sans Combat, les grunts sont invincibles ; le système Enemy reste fonctionnel pour le côté letal (laser → Player.die()) mais le gameplay loop est cassé |
| **Player Movement System** (In Review r3) | ⚠️ GDD pending re-review | Aval | LaserCone Area3D appelle `Player.die()`. Sans Movement-owned `die()`, le grunt ne peut pas tuer le Player. Movement GDD figè le contract `die()` idempotent + tween fade rouge |
| **Game State Manager** (APPROVED r1) | ✅ Designed | Amont | Enemy gèle quand `state != PLAYING` (via `tree.paused = true` propagation). Sans GSM, pas de pause/unpause clean |
| **ADR-0008 Collision Layer Taxonomy** | ✅ Accepted | Constraint | LAYER_ENEMY=2, LAYER_ENEMY_HITBOX=3 figés. Toute violation = crash logique (Combat ne détecte plus les grunts, ou laser ne touche plus Player) |

### Soft dependencies (système enrichi par mais fonctionne sans)

| Système | Status | Direction | Interface |
|---|---|---|---|
| **Audio System** (APPROVED r2.1) | ✅ Designed | Aval | Audio écoute `enemy_killed` pour jouer clac sur bus `combat_kill`. Sans Audio, le kill reste fonctionnel mais silencieux (UX dégradé mais pas blocker MVP) |
| **VFX & Feedback System** (Not Started) | ❌ Pas designed | Aval | VFX écoute `enemy_killed` pour flash blanc + splash sang. Sans VFX, le kill est moins satisfaisant mais le tween scale 150 ms d'Enemy reste visible (pas total black-out feedback) |
| **Credit Economy** (Not Started) | ❌ Pas designed | Aval | Credit écoute `enemy_killed` pour incrémenter compteur joueur. Sans Credit, les kills ne donnent pas de monnaie mais le combat reste jouable |
| **HUD / UI System** (Not Started) | ❌ Pas designed | Aval | HUD peut afficher kill count, combo timer. Optional consumer |
| **Checkpoint & Respawn System** (Not Started) | ❌ Pas designed | Aval | Checkpoint capture `is_dead()` + appelle `_restore_from_snapshot`. Sans Checkpoint, les grunts respawn vivants à chaque mort Player (acceptable temporairement, Pillar 3 partiellement honoré) |

### Cousins (latents — Tier 2+, pas MVP)

- **Hazard System** (Not Started) — Tier 2+ pourrait appeler `enemy.die()` (Rule 7). Au MVP, contract latent, aucun Hazard ne touche les ennemis.
- **Boss System** (Not Started, Full Vision) — système séparé avec PV multiples. **N'utilise pas** Enemy System (asymétrie boss vs grunt).

### Bidirectional consistency check

| Cited dependency | Réciprocité dans GDD cible | Status |
|---|---|---|
| Level System cite Enemy comme « Depended on by: Enemy » dans Level GDD §header | ✅ Présent (« Depended on by: Checkpoint, Hazard, **Enemy**, Secret, HUD, Tutorial, Audio, VFX » ligne 9 Level GDD) | ✅ Bidirectionnel |
| Combat System cite Enemy comme « Consumed by: Enemy System (die() au hit) » dans Combat GDD §Quick reference | ✅ Présent (Combat GDD ligne 14) | ✅ Bidirectionnel |
| Movement cite Enemy via « die() called by Enemy laser » | ⚠️ À vérifier dans Movement GDD r3 — pending re-review fresh | ⚠️ **Gate condition** : ENEMY APPROVED conditionnel à confirmation Movement r4 documente `Player.die()` comme appelé par Enemy LaserCone (cf review-r1 BLOCKING-4). Tracé header GDD ligne 6. Non-bloquant pour design r2 mais bloquant pour `/create-epics enemy-system` |
| Audio cite Enemy comme consumer de bus combat_kill via `enemy_killed` signal | ✅ Audio GDD r2.1 est neutre sur la source du signal (parle de "écoute `enemy_killed`" sans nommer l'émetteur) — la résolution OQ-ENM-1 (Enemy émet) est transparente pour Audio | ✅ Bidirectionnel post-résolution OQ-ENM-1 (review-r1) |

> **Cross-system note 🚨 — RÉSOLU review-r1** : OQ-ENM-1 a été résolu lors de la `/design-review enemy-system` r1 (2026-04-27) — **Enemy est l'autorité d'émission de `enemy_killed`**. Justifications : (1) un Hazard Tier 2+ peut appeler `enemy.die()` sans passer par Combat — si Combat était l'émetteur, les kills Hazard seraient silencieux pour Credit/VFX/Audio (bug architectural garanti) ; (2) cohérence sémantique — l'ennemi sait quand il meurt, c'est son signal ; (3) idempotence déjà résolue côté Enemy (Rule 6) garantit un seul emit ; (4) slow-mo Combat Rule 13 reste cohérent — Combat **réagit** à `Enemy.enemy_killed` pour déclencher `Engine.time_scale = 0.3` (cause causale grunt meurt → Combat réagit, vs self-loop Combat émet → Combat réagit) ; (5) Audio GDD r2.1 est neutre sur la source — aucun changement requis Audio.
>
> **Amendement Combat r7 requis** (à exécuter dans une session Combat dédiée — **NE PAS modifier Combat GDD depuis Enemy**) :
> - Combat GDD Rule 9 (multi-hit) : retirer "émet `enemy_killed`" → "Combat appelle `enemy.die()` — Enemy émet son propre signal `enemy_killed`"
> - Combat GDD Interactions table Enemy row : "Combat appelle `enemy.die()` au hit. Enemy émet `enemy_killed` que Combat connecte pour déclencher slow-mo Rule 13."
> - Combat GDD Published API : retirer signal `enemy_killed` de la liste des signaux émis par CombatSystem (Combat consume, n'émet pas)
> - Combat GDD Interactions Credit Economy / VFX rows : "Credit Economy / VFX se connecte à `Enemy.enemy_killed` (pas `CombatSystem.enemy_killed`)"
>
> Ce statut "amendement Combat r7 pending" est un **prerequisite gate** avant `/create-epics enemy-system` Sprint A (cohérence cross-GDD requise pour implémentation).

## Tuning Knobs

Tous les knobs ci-dessous sont des **constantes GDScript** au MVP (`const X: float = …` dans `enemy_constants.gd` autoload ou directement dans `Grunt.gd`). Pas de fichier `.tres` config externe au MVP — la simplicité de scope (1 archetype, 5 constantes) ne le justifie pas. Si Tier 2+ ajoute 4 archétypes, migration vers `enemy_config.tres` recommandée.

### Configuration globale Enemy

| Knob | Valeur MVP | Safe range | Affecte | Risque hors-range |
|---|---|---|---|---|
| `r_enemy_min` | `0.35 m` | `[0.30, 0.50]` | Rayon capsule grunt — input de Combat F.gap_max | < 0.30 → Combat tunneling possible à V_max=30 m/s ; > 0.50 → grunt obstrue trop le path |
| `HEIGHT_GRUNT_M` | `1.8 m` | `[1.5, 2.2]` | Hauteur capsule humanoid | < 1.5 → silhouette enfantine perd lisibilité hostile ; > 2.2 → bloque jump par-dessus dans corridor 2.5 m |
| `LASER_WIDTH_M` | `0.50 m` | `[0.30, 1.00]` | Largeur cône laser hitbox | < 0.30 → side-step trivial, perd menace ; > 1.00 → couloir étroit devient impossible à dodge sans wall-run |
| `LASER_HEIGHT_M` | `0.30 m` | `[0.20, 0.80]` | Hauteur cône laser | < 0.20 → flicker visuel, mauvaise lisibilité ; > 0.80 → impossible à passer dessous en sliding (Movement n'a pas slide MVP donc moot) ou par-dessus en jump |
| `LASER_RANGE_M` | `6.0 m` | `[3.0, 12.0]` | Portée letal du laser | < 3.0 → grunt trop facile à éviter en arc large ; > 12.0 → couvre toute la salle, force wall-run obligatoire |
| `DEATH_TWEEN_DURATION_MS` | `150 ms` (default) ; `400 ms` si `reduce_motion = true` (Accessibility System Tier 3 — latent) | `[100, 300]` MVP ; `[300, 600]` reduce_motion | Durée disparition mesh post-`die()` | < 100 → pop-out brutal, perd Pillar 1 staccato satisfaction ; > 300 → fade traîne, casse rythme. **Variant reduce_motion=true** : 400 ms réduit la vitesse de scale-down pour photosensibilité / motion sensitivity. Tracé dans `entities.yaml:69` mais **dépendance conditionnelle à Accessibility System (Not Started, Tier 3)** — la valeur 400 ms est figée ici comme contrat futur, pas activable au MVP (pas d'API `reduce_motion`) |
| `EPSILON` | `0.01` | `(0, 0.05]` | Scale final mesh « invisible » | `0` → artefacts numériques shaders Godot 4.6 ; > 0.05 → mesh visible à distance < 1 m |

### Per-EnemySlot metadata (level-time authoring)

Tunable individuellement via `Marker3D.set_meta(...)` dans l'éditeur Godot par le level designer :

| Meta key | Type | Default | Range | Description |
|---|---|---|---|---|
| `archetype` | StringName | `&"grunt"` | `[&"grunt"]` MVP ; `[&"grunt", &"sentinel", &"brute", &"drone", &"sniper"]` Tier 2+ | Type d'ennemi à spawner sur ce slot. Fallback grunt si unknown (EC-ENM-16) |
| `laser_range` | float | `LASER_RANGE_M = 6.0` | `[3.0, 12.0]` | Override per-slot de la portée laser. Permet à un level designer de placer un sniper dans un corridor long (range 12) et un grunt courte portée dans une petite salle (range 4) |
| `laser_active` | bool | `true` | `{true, false}` | Si false, le grunt est instancié sans LaserCone (silhouette inerte). **Anti-pattern attention** : un grunt sans menace casse Pillar 1. À utiliser **uniquement** pour onboarding (1ère salle level — voir game-concept §96) |

### Knobs latents (Tier 2+, hors MVP)

| Knob | Description futur |
|---|---|
| `PIVOT_SPEED_DEG_PER_SEC` | Vitesse rotation horizontale d'un archetype « sentinelle pivotante » (Tier 2) |
| `BRUTE_LUNGE_RANGE_M` | Distance d'attaque mêlée d'un archetype « brute » (Tier 2) |
| `DRONE_HOVER_HEIGHT_M` | Hauteur de patrouille d'un drone aérien (Tier 2) |
| `SNIPER_CHARGE_TIME_MS` | Telegraph time avant tir sniper (Tier 2) |
| `CREDIT_VALUE` | dict mapping `archetype → credits awarded on kill`. Owned by Credit Economy GDD futur, pas Enemy |

## Visual/Audio Requirements

### Visual

**Silhouette (Pillar 1 — lecture instantanée)**

- **Shape primitive Chrome Zen** : capsule (corps) + box (tête) + 2 boxes (bras croisés tenant l'arme laser frontale). Pas de mesh humanoid détaillé MVP — silhouette lisible à 20 m de distance suffit.
- **Material** : `chrome_zen_flat.gdshader` (asset existant `assets/shaders/chrome_zen_flat.gdshader`) — surfaces matte, pas de specular, pas d'ombre auto-cast (Forward+ + light baked au level-time, ADR-0003 rendering latency budget).
- **Couleur de base** : gris foncé (`Color(0.3, 0.3, 0.35)`) — neutre dans la palette art-bible, ne consume pas le « budget rouge » réservé aux éléments hostiles actifs.
- **Accent rouge** : seulement sur le LaserCone émissif (cf laser ci-dessous) et un détail mineur (yeux ? petit point sur la tête ?). Le grunt corps lui-même n'est PAS rouge — c'est son **arme** qui l'est.

**LaserCone (Pillar 1 — télégraphe lethal)**

- **Visualisation** : `Quad` plan plat émissif (`MeshInstance3D` avec `QuadMesh`) sur la face frontale du `BoxShape3D` LaserCone. Couleur émissive `Color(1.0, 0.1, 0.1)` à `emission_energy_multiplier = 3.0` — **le rouge est saturé et fluo, signal de mort universel**.
- **Animation** : aucune au MVP. Le laser est statique (toujours-on, aligné Q1 reco). Tier 2+ pourrait ajouter un cycle on/off de telegraph (200 ms warning + 800 ms lethal, e.g.) — prévu mais hors scope MVP.
- **Particle/VFX** : aucun MVP. Pas de smoke, pas de crackle, pas d'aura. Économie polygone et garantit lecture instantanée à 60 FPS.

**Death VFX (Pillar 1 — coda du clac)**

- **Owned by Enemy System** (au MVP) : tween scale du `MeshInstance3D` Vector3.ONE → Vector3(0.01) sur 150 ms wall-clock. Pas de rotation, pas de particle, pas de blink.
- **Externalisé au VFX & Feedback System** (Not Started, Tier 2+) :
  - Flash blanc 50 ms à `position` : owned by VFX, pas Enemy.
  - Splash de sang brut (rouge fluo, art-bible État 2) : owned by VFX, pas Enemy.
  - Spark électrique cybernétique (cohérent cyber-ronin theme) : owned by VFX, optional.

**Lighting / shadow**

- Le grunt projette une ombre statique baked au level-time (Forward+ avec ProjectSettings.rendering.global_illumination — VR-1 Shader Baker, hors scope ADR direct au MVP). Pas d'ombre dynamique.
- LaserCone émissif **n'éclaire pas** la scène (pas de Light3D enfant — coût Forward+ trop élevé pour 30 sources). Le rendu émissif via shader suffit pour la lisibilité.

**Animation**

- **Aucune au MVP**. Le grunt est rigide. Tier 2+ pourrait ajouter :
  - Idle breathing loop (subtle, non-broadcast)
  - Aim adjustment subtle (head/torso tilt vers Player)
  - Death stagger (avant le tween scale) — actuellement remplacé par scale-down direct

> 📌 **Asset Spec** — Visual/Audio requirements sont définis. Après art bible approuvé (`/art-bible`), exécuter `/asset-spec system:enemy-system` pour produire les specs visuels par-asset (silhouette grunt, mesh tête, mesh arme laser, shader émissif rouge, death VFX flash) avec dimensions et generation prompts pour pipeline AI assets.

### Audio

**Source de vérité** : Audio System GDD r2.1 + ADR-0009 D-1 figè les bus names et la pool architecture. Enemy System est **consumer aval** d'Audio via signal `enemy_killed` — Enemy n'instancie aucun `AudioStreamPlayer3D` lui-même.

**Sonic events Enemy → Audio** :

| Event | Trigger | Audio bus | Sample type | Notes |
|---|---|---|---|---|
| **Kill clac** | `enemy_killed` signal SYNC | `combat_kill` (UPPER_SNAKE_CASE bus) | One-shot 60-100 ms perceptual onset, ducks `MUSIC` via sidechain compressor (ADR-0009 D-1 r2 amend) | Audio System pool 3D (`pool_3d_size = 12`, F3 Audio GDD) joue à `position` 3D. Multi-kill MVP = pitch-shift +2 semitones sur 2ème kill, +4 sur 3ème (Audio Rule 13 r2.1) |
| **Laser hum (ambient)** | LaserCone monitoring=true | `AMBIENCE` bus (Tier 2+ ?) | Loop infini 30-50 Hz sub-bass | **HORS MVP** — Audio GDD r2.1 OQ#7 résolu pour room tone Chrome Zen `-12 dB` 40-80 Hz, mais grunt-specific laser hum non spécifié au MVP. Au MVP, le LaserCone est **silencieux** — le joueur lit la menace visuellement uniquement. Tier 2+ peut ajouter via amendement Audio GDD |
| **Death stagger sound** | `Alive → Dying` transition | `combat_kill` ou nouveau bus | Optional Tier 2+ | Pas au MVP. Le clac suffit |
| **Laser fire SFX** | LaserCone hit Player (body_entered → Player.die()) | Owned by Movement death pipeline | One-shot | Pas Enemy-owned — c'est le bruit de mort joueur, géré par Movement GDD (death.wav 60-80 ms — Audio r2.1 D3) |

**Mix priority au tick d'un kill** : ducking via sidechain `MUSIC ← combat_kill` (ADR-0009 D-1 r2 amend) garantit que le clac perce sans qu'on coupe la musique. Audio GDD r2.1 §Mix hierarchy figé.

## UI Requirements

Enemy System **n'a pas d'UI Enemy-owned au MVP**. Aucun health bar (one-shot), aucun nameplate, aucun marker compass, aucun threat indicator. Le grunt est lisible visuellement par sa silhouette + son LaserCone rouge (cf §Visual Requirements).

Les consommateurs UI suivants reçoivent les signaux Enemy mais possèdent leur propre GDD/UX spec :

| Consumer | Signal écouté | Présentation UI possible | GDD owner |
|---|---|---|---|
| **HUD** (Not Started) | `enemy_killed` | Kill counter (en haut à droite ?), combo timer, multi-kill flash text | HUD GDD futur (à designer Sprint A — voir gate r2 roadmap) |
| **Score / Run statistics** (Tier 2+) | `enemy_killed` | Run summary screen end-of-etage : « 12 kills, 3 multi-kills, 0 deaths » | Run Summary GDD futur (Tier 2+) |

**UX flag absent** : Enemy System ne contribue à aucun screen ou widget directement. Le futur travail UX sera fait dans le HUD GDD + ses screens, pas dans une UX spec « enemy-overlay » ou similaire. Pas de `/ux-design enemy-*` à prévoir.

## Acceptance Criteria

Format : `**AC-ENM-NN [type]** : GIVEN [état initial], WHEN [action ou trigger], THEN [résultat mesurable]`

Types (per CLAUDE.md test evidence) : **Logic** = unit test BLOCKING ; **Integration** = integration test BLOCKING ; **Visual** = playtest evidence ADVISORY ; **UI** = manual walkthrough ADVISORY ; **Perf** = benchmark BLOCKING.

### Core invariants

- **AC-ENM-01 [Logic]** : GIVEN un Grunt en `state == ALIVE`, WHEN `enemy.die()` est appelé, THEN `_state == DYING`, `LaserCone.monitoring == false`, signal `enemy_killed(self, global_position)` émis exactement 1 fois, et un Tween de scale est démarré sur le `MeshInstance3D`.

- **AC-ENM-02 [Logic]** : GIVEN un Grunt en `state == DYING`, WHEN `enemy.die()` est appelé une seconde fois, THEN `_state` reste `DYING`, **aucun signal `enemy_killed` additionnel** n'est émis, **aucun warning console**, le tween en cours n'est pas reset (Rule 6 idempotent).

- **AC-ENM-03 [Logic]** : GIVEN un Grunt en `state == DEAD`, WHEN `enemy.die()` est appelé, THEN `_state` reste `DEAD`, aucun signal, aucun warning (EC-ENM-2).

- **AC-ENM-04 [Logic]** : GIVEN un Grunt en `state == ALIVE`, WHEN un body entre dans le `LaserCone.body_entered` Area3D ET `body.is_in_group("player")`, THEN `body.die()` est appelé exactement 1 fois.

- **AC-ENM-05 [Logic]** : GIVEN un Grunt en `state == DYING`, WHEN un body entre dans le `LaserCone.body_entered` Area3D, THEN `body.die()` n'est **pas** appelé (handler retourne via guard `_state != ALIVE`).

- **AC-ENM-06 [Logic]** : GIVEN un Grunt instancié, WHEN inspect des collision layers, THEN `Grunt.collision_layer == 0b00000010` (LAYER_ENEMY=2 1-indexé bit 1) ET `Grunt.collision_mask == 0b00001000` (LAYER_ENVIRONMENT=4 1-indexé bit 3) ET `LaserCone.collision_layer == 0b00000100` (LAYER_ENEMY_HITBOX=3 bit 2) ET `LaserCone.collision_mask == 0b00000001` (LAYER_PLAYER=1 bit 0) ET `LaserCone.monitoring == true`.

- **AC-ENM-07 [Logic]** : GIVEN un Grunt MVP, WHEN inspect le node tree, THEN `_physics_process` est désactivé (`is_physics_processing() == false`) ET `velocity == Vector3.ZERO` (Rule 10).

- **AC-ENM-07b [Logic]** : `is_dead()` getter contract (review-r1 missing AC). GIVEN `enemy.is_dead()` appelé sur 3 grunts dans 3 states distincts, WHEN inspect retours, THEN `enemy_alive.is_dead() == false`, `enemy_dying.is_dead() == true`, `enemy_dead.is_dead() == true`. Justification : Checkpoint System consume `is_dead()` pour son snapshot — comportement DYING+DEAD = "dead" garantit qu'un kill mid-tween est bien capturé au snapshot.

- **AC-ENM-07c [Logic]** : Spawn orientation orthonormalization (review-r1 missing AC, EC-ENM-6). GIVEN un `EnemySlot_01` créé avec `basis = Basis.IDENTITY.scaled(Vector3(2, 1, 1))` (non-uniform scale), WHEN spawn, THEN `Grunt.%FacingPivot.global_basis.is_equal_approx(EnemySlot.global_basis.orthonormalized())` ET `FacingPivot.global_basis.is_normalized() == true` (cône non-déformé visuellement).

### Spawn et orientation

- **AC-ENM-08 [Integration]** : GIVEN un étage chargé avec `EnemySlot_01..03` (3 Marker3D) à des positions distinctes, WHEN signal `LevelSystem.level_active` est émis, THEN exactement 3 instances de `Grunt.tscn` sont ajoutées au scene tree, leurs `global_position` matchent les `EnemySlot.global_position` (epsilon 0.001 m).

- **AC-ENM-09 [Integration]** : GIVEN un `EnemySlot_01` orienté `Basis.IDENTITY.rotated(Vector3.UP, PI / 4)` (45° autour Y), WHEN spawn, THEN `Grunt.%FacingPivot.global_basis.is_equal_approx(EnemySlot.global_basis.orthonormalized())` (epsilon 0.001).

- **AC-ENM-10 [Integration]** : GIVEN un `EnemySlot.set_meta("archetype", "drone")` au MVP, WHEN spawn, THEN un Grunt est instancié à la place ET `push_warning("Enemy archetype 'drone' unknown — fallback to 'grunt'")` apparaît dans le log (EC-ENM-16).

### Death sequence

- **AC-ENM-11 [Logic]** : GIVEN un Grunt qui vient de recevoir `die()`, WHEN 150 ms wall-clock se sont écoulées, THEN `_state == DEAD` ET `MeshInstance3D.scale.is_equal_approx(Vector3(0.01, 0.01, 0.01))` (epsilon 0.001) ET le nœud existe encore (pas de queue_free, Rule 12).

- **AC-ENM-12 [Logic]** : GIVEN un Grunt qui meurt pendant `Engine.time_scale = 0.3` (slow-mo Combat), WHEN 150 ms wall-clock absolu se sont écoulées (Time.get_ticks_msec(), pas delta-affected), THEN `_state == DEAD` indépendamment du time_scale.

### Cross-system integration

- **AC-ENM-13 [Integration]** : GIVEN un Combat sweep qui hit un Grunt, WHEN le sweep résolve, THEN Combat appelle `grunt.die()` exactement 1 fois, signal `enemy_killed` est émis SYNC dans le même `_physics_process` tick que le sweep, et Audio reçoit `enemy_killed` via signal connection au tick T.

- **AC-ENM-14 [Integration]** : GIVEN un Player en collision avec un LaserCone Grunt, WHEN body_entered fire, THEN `Player.died` signal est émis dans le tick courant (Movement-owned), et le Grunt n'a pas de side-effect (LaserCone reste actif si Player respawn dans la cone, donc 2ème kill possible).

- **AC-ENM-15 [Integration]** : Mutual kill tick-même (Combat Rule 17). GIVEN un Player en swing actif Combat ET un Grunt avec laser actif, WHEN le tick physique N voit (Player.body in LaserCone) ET (Grunt.body in Combat sweep), THEN dans le même tick : `Player.died` émis ET `enemy_killed(grunt)` émis (les deux morts résolues, Combat AC-CMB-25 cross-link).

### Persistance respawn

- **AC-ENM-16 [Integration]** : GIVEN un Grunt en `state == DEAD` et un Player qui respawn depuis checkpoint dont snapshot inclut `enemy_id → was_dead = true`, WHEN respawn, THEN `_restore_from_snapshot(true)` est appelé, `_state == DEAD` post-restore (le grunt mort reste mort, Pillar 3 forgiveness, Rule 13 + EC-ENM-11).

- **AC-ENM-17 [Integration]** : GIVEN un Grunt en `state == ALIVE` et un Player qui respawn depuis checkpoint dont snapshot inclut `enemy_id → was_dead = false`, WHEN respawn, THEN `_restore_from_snapshot(false)` est appelé, `_state == ALIVE` post-restore.

- **AC-ENM-18 [Integration]** : GIVEN un Grunt en `state == DYING` (tween en cours), WHEN `_restore_from_snapshot(false)` est appelé, THEN le tween est `kill()` ET `_state == ALIVE`, `MeshInstance3D.scale == Vector3.ONE`, `LaserCone.monitoring == true` (EC-ENM-13).

- **AC-ENM-18b [Integration]** : `_restore_from_snapshot(true)` sur DYING (review-r1 missing AC, EC-ENM-13 second variant). GIVEN un Grunt en `state == DYING` (tween 50 ms écoulés), WHEN `_restore_from_snapshot(true)` est appelé, THEN le tween est `kill()` ET `_state == DEAD` direct (skip DYING→DEAD natural transition), `MeshInstance3D.scale.is_equal_approx(Vector3(EPSILON, EPSILON, EPSILON))` (epsilon 0.001), `LaserCone.monitoring == false`, **aucun signal `enemy_killed`** ré-émis (le kill original a déjà été crédité au moment de la mort, le restore ne re-crédite pas).

### Pause / state transitions

- **AC-ENM-19 [Integration]** : GIVEN un Grunt en `DYING` (tween 75 ms écoulés), WHEN `GameStateManager.request_pause()` puis 10 secondes wall-clock, puis `request_resume()`, THEN le tween reprend son cours, completion à wall-clock 150 ms hors temps de pause (EC-ENM-9).

- **AC-ENM-20 [Logic]** : GIVEN un Grunt en `ALIVE` ET `tree.paused == true`, WHEN inspect, THEN `LaserCone.monitoring` reste `true` mais aucun `body_entered` ne fire pendant la pause (Godot natif).

### Performance

- **AC-ENM-21 [Perf]** : GIVEN un étage avec **30 grunts** instanciés (max realistic MVP : 8-10 salles × 3 EnemySlot), WHEN gameplay loop tourne 10 secondes à 60 FPS, THEN frame time p99 reste sous 16.6 ms (frame budget Combat ADR-0001) ET `_physics_process` time budget Enemy ≤ 0.5 ms total (cumulé, 30 grunts × idle).

- **AC-ENM-22 [Perf]** : GIVEN 30 grunts sur un étage, WHEN `_physics_process` cumulé sur 1000 ticks (16.6 s @ 60 Hz), THEN aucune allocation heap permanent (delta `MEMORY_STATIC` < 64 KB, aligné no-alloc-hot-paths rule extended scope si Enemy ajoute hot path).

### Authoring lints (Level System cross-add)

- **AC-ENM-23 [Logic]** : GIVEN un fichier `.tscn` étage avec `EnemySlot_01.scale = Vector3(2, 1, 1)` (non-uniform), WHEN `tools/lint/level_lint.gd::validate_enemy_slot_marker3d()` exécute, THEN un FAIL est rapporté avec message contenant « EnemySlot scale not uniform » (EC-ENM-6).

- **AC-ENM-24 [Logic]** : GIVEN deux `EnemySlot_*` séparés de moins de `1.0 m`, WHEN `validate_enemy_slot_min_distance()` exécute, THEN un FAIL est rapporté (EC-ENM-8).

- **AC-ENM-25 [Logic]** : GIVEN un `EnemySlot_*` placé dans un wall (raycast vertical hit StaticBody3D au lieu de sol walkable), WHEN `validate_enemy_slot_clearance()` exécute, THEN un FAIL est rapporté (EC-ENM-7).

### Visual / Feel (ADVISORY playtest)

- **AC-ENM-26 [Visual]** : Playtest evidence — un playtester non-initié identifie le LaserCone d'un Grunt comme « zone de mort » dans les 5 premières secondes d'exposition à la salle, sans tutoriel ni dialogue. Evidence template : screenshot + 3 quotes spectator + survival rate sur 5 attempts (target ≥ 60% survival après 1ère mort = mort pédagogique fonctionne).

- **AC-ENM-27 [Visual]** : Playtest evidence — feel du clac kill : 5 playtesters indépendants décrivent la mort grunt avec un mot positif (« satisfaisant », « solide », « clean ») dans questionnaire post-session. Pas de mot négatif (« plat », « anti-climatique », « confus »).

- **AC-ENM-28 [Visual]** : Playtest evidence — Pillar 3 mort pédagogique : un playtester qui meurt à un Grunt re-tente la salle dans les 10 s post-respawn ET réussit à passer dans les ≤ 3 tentatives totales (incluant la 1ère mort). Evidence : timestamp log session.

## Open Questions

| OQ | Question | Owner | Target resolution |
|---|---|---|---|
| **OQ-ENM-1** ✅ RESOLVED review-r1 | Combat GDD Rule 11 stipule « Combat émet `enemy_killed` » mais Enemy GDD Rule 11 (ici) dit Enemy émet. **Cross-GDD conflict** sur l'autorité du signal. **Résolution** : **Enemy est l'autorité d'émission** (5 justifications, voir §Dependencies cross-system note). Amendement Combat GDD r7 requis (à exécuter dans une session Combat dédiée) — **prerequisite gate avant `/create-epics enemy-system`** | game-designer + Combat GDD owner | RÉSOLU 2026-04-27 review-r1. Amendement Combat r7 pending |
| **OQ-ENM-2** ✅ RESOLVED review-r1 | Pattern d'instantiation des grunts : autoload `EnemySpawner` global vs Service Locator vs Service ad-hoc per-LevelSystem ? **Résolution** : **LevelSystem est la factory directe** — itère ses propres `EnemySlot_*` au signal `level_active` et instancie `Grunt.tscn`. Pas d'autoload `EnemySpawner` séparé au MVP. API publique `LevelSystem.get_etage_enemy_slots()` retirée de la Interactions table (obsolète). Si Tier 2+ exige un EnemyManager dédié, l'API sera extraite alors | technical-director / godot-specialist | RÉSOLU 2026-04-27 review-r1 |
| **OQ-ENM-3** | LaserCone : `BoxShape3D` (MVP simple, lecture rectangle) vs `CylinderShape3D` (cône évasé plus correct géométriquement) ? **Recommandation MVP** : `BoxShape3D` — la précision géométrique du cône importe moins que la lisibilité visuelle, et le rectangle 0.5 × 0.3 × 6 m est plus prévisible côté side-step joueur | art-director + game-designer | Sprint A — playtest peut valider que le rectangle « se lit » comme un cône |
| **OQ-ENM-4** | Credit value per kill au MVP : `CREDIT_VALUE["grunt"] = 1` ? Ou plus ? **Recommandation** : 1 crédit MVP — Credit Economy GDD futur tranchera (3 upgrades ≈ 3-9 crédits totaux par etage = 1 crédit par kill = 9 kills à faire = 1 etage de 8-10 salles, économie cohérente) | economy-designer | Sprint A — bloque finalisation Credit Economy GDD |
| **OQ-ENM-5** | Death sound MVP : un seul `clac` partagé tous archetype, ou un sample dédié grunt ? **Recommandation** : un sample « combat_kill_clac.wav » universel partagé tous archétypes Tier 2+ (cohérence rythme staccato Pillar 1) — Audio GDD r2.1 confirme qu'un seul bus `combat_kill` est utilisé. Pitch-shift (Audio Rule 13 r2.1 +2/+4 semitones multi-kill) suffit pour différenciation | audio-director + sound-designer | Sprint A — vérifier dans Audio GDD si déjà figé |
| **OQ-ENM-6** | Onboarding salle 1 : le grunt 1ère salle a-t-il `laser_active = false` (silhouette inerte pour apprendre approche katana) OU `laser_active = true` mais cône orienté hors path principal (lecture sans risque) ? **Recommandation** : `laser_active = true` cône hors path — préserve la « grammaire visuelle » constante (tous grunts ont laser rouge), enseigne plutôt qu'éviter la grammaire | level-designer + game-designer | Sprint B — décision authoring level 1 quand designer commence à layout salle 1 |
| **OQ-ENM-7** | Enemy ADR dédié nécessaire ? Au MVP non (statique, simple, absorbé par ADR-0006/0008). Mais Tier 2+ (pathfinding, AI states, behavior trees) demandera probablement un ADR-0012 ou similaire | technical-director | Tier 2 — ADR-0012 « Enemy AI Architecture » à créer quand archétypes mobiles arrivent |
| **OQ-ENM-8** | Animation idle subtile (breathing, micro-tilt) au MVP ? Trade-off : visuel plus vivant vs scope creep + risque distract Pillar 1 lecture instantanée. **Recommandation** : aucune animation MVP — fixture pure. Tier 2+ peut ajouter | art-director | Tier 2 |
| **OQ-ENM-9** | `_restore_from_snapshot` : les params à passer plus larges que juste `was_dead: bool` (e.g. `state: State`, `position: Vector3` si Tier 2+ ennemi mobile) ? **Recommandation MVP** : signature simple `was_dead: bool` suffit, refactoring API en Tier 2+ sera trivial (1 archetype concerné) | game-designer + Checkpoint GDD futur | Sprint B — quand Checkpoint GDD est designed |
| **OQ-ENM-10** | Performance worst-case 30 grunts → ce nombre est-il pessimiste ? Estimation game-concept §269 + Level GDD R-2.6 : 8-10 salles × 3 EnemySlot moyen = 24-30 grunts par étage. AC-ENM-21 budget basé là-dessus. **Recommandation** : valider en playtest Sprint C que 30 grunts simultanés tient le budget 16.6 ms (budget partagé avec Movement+Combat+Level+Audio) | performance-analyst | Sprint C — benchmark perf sur build VS intégré |
