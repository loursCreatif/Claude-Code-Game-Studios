# Player Combat System

> **Status**: **APPROVED r6** (2026-04-23 — propagation Addendum r5.2 achevée inline : CONV-1 Basis fix via helper centralisé `_build_capsule_basis()`, 3 décisions Martin D-r4-1/2/3, 5 RECOMMENDED, Addendum purgé remplacé par note historique. **Fresh `/design-review` r6 session indépendante 2026-04-23 confirmée — verdict APPROVED via 7 specialists + creative-director, 9 BLOCKING retenus puis résolus inline (CONV-1 propagation vérifiée 4 occurrences, Invariant #9 scope `_validate_invariants()` inclus dans AC-CMB-17 description, AC-CMB-51 fade-out swoosh wall-clock, AC-CMB-52 Gap 4 formalisé, AC-CMB-audio-01/02 contrats multi-kill + ducking ordering, Gap 8 ShapeCast3D.margin Jolt test empirique owner lead-programmer, AC-CMB-41 clause 8 grep structural SYNC, AC-CMB-19 branche C accessibility disable + teardown, AC-CMB-35b split worst case + soak global). Aucun BLOCKING résiduel.**)
> **Author**: Martin + design-system skill (auto mode, solo) — 6 revisions r1→r6, toutes tranchées et propagées inline. Historique détaillé (blocking counts par review, décisions Martin D1-D5 / M1-M2 / D-r3-1 / D-r3-2 / DEC-r5-1 / DEC-r5-2 / D-r4-1 / D-r4-2 / D-r4-3, faux positifs rejetés, spot-checks CLEAN) dans `design/gdd/reviews/player-combat-system-review-log.md`.
> **Last Updated**: 2026-04-23 (r5.1→r6 propagation Addendum r5.2 inline via revise-now flow solo mode)
> **Implements Pillar**: Pillar 1 (FLOW AVANT TOUT) — primaire, critique. Katana = extension de l'input, zéro latence tolérée. Pillar 3 (UNE SECONDE CHANCE) — via one-shot mutuel symétrique. Pillar 2 (LA PROGRESSION SE VOIT) — indirect via moveset qui change les approches de combat (dash-slash, wall-run-slash, double-jump-slash).
> **Governing ADRs**: ADR-0001 (Physics Rate 60 Hz + Jolt) · ADR-0002 (Camera Scene Tree 3-tier) · ADR-0004 (Input API & Focus Handling) · ADR-0005 (Movement Signals Architecture)
> **Pending ADR** (r1 action): `adr-combat-tick-model.md` — ordre `_physics_process` parent/enfant, proprietaire cache `_prev_position`, interface MockMovement/MockEnemy, CONNECT_DEFERRED vs sync policy pour `enemy_killed` consumers. A rediger par lead-programmer avant Sprint 1 Combat.

## Overview

Le Player Combat System traduit l'action `attack` du joueur en un geste létal unique : un sweep de katana qui tue instantanément tout ennemi standard dont la hitbox est touchée. Il ne contient aucune progression numérique (pas de dégâts, pas de combo), aucun autre type d'arme, aucune gestion de munitions — *un clic, un coup, un kill*. Le système orchestre quatre responsabilités : (1) détecter l'input `attack` et déclencher un swing à `ATTACK_COOLDOWN` près ; (2) effectuer un sweep de hitbox via `ShapeCast3D` en `_physics_process` @ 60 Hz (ADR-0001) — la forme balayée trace le volume couvert par la lame entre le tick précédent et le tick courant, ce qui prévient le tunneling quand le joueur dash à 30 m/s ou flicke la caméra ; (3) consommer `CameraSystem.aim_forward` (roll-corrigé, forme close trigonométrique per ADR-0002) pour orienter le sweep — jamais la rotation caméra brute, afin que le tilt wall-run ne dévie pas horizontalement la trajectoire du katana ; (4) émettre les signals de hit/kill pour que VFX, Audio, Credit Economy, et HUD puissent réagir sans que Combat connaisse leur existence. Le feedback de kill est calibré au niveau concept (game-concept.md), ajuste r1 : **slow-mo mécanique 50 ms wall-clock à `Engine.time_scale = 0.3` (167 ms percus, micro-pause rythmique — pas climax), flash blanc 50 ms en connexion SYNC (pas DEFERRED, frame-precise avec kill tick), splash de sang brut** — les seules taches chaudes de l'image (art-bible État 2). Le joueur, lui, reste one-shot : toute hitbox ennemie qui le touche appelle `Player.die()` — symétrie stricte. L'unique exception est le boss final (système séparé Full Vision), qui consommera plusieurs hits tandis que le joueur reste one-shot.

> **Quick reference** — Layer: `Gameplay` · Priority: `MVP` · Key deps: `Player Movement (amont, velocity + transform + signal attacked), Camera System (amont, aim_forward), Input System (amont, attack action)` · Consumed by: `Enemy System (die() au hit), Checkpoint & Respawn (player die), Credit Economy (kill → credits), VFX & Feedback (impact flash + blood), Audio (swoosh + impact + kill cue), HUD (feedback visuel)`

## Player Fantasy

**Cible émotionnelle : le kill est le silence entre deux notes de mouvement.**

Le joueur ne "combat" pas au sens classique : il *enchaîne*. Il court, saute, wall-run, dash, tranche, rebondit — et le kill n'est pas la destination de la séquence, c'est une syllabe en son milieu. La lame claque comme un hi-hat dans un break : nette, instantanée, puis la course reprend. L'ennemi n'existe plus en tant qu'obstacle individuel — il existe en tant que *beat* dans la partition que le joueur joue avec son corps.

Le sentiment-cible, en une phrase : **« le kill est le silence entre deux notes de mouvement. »**

Les 0.1 seconde de slow-mo au kill ne sont pas une récompense cathartique séparée — ce sont la micro-pause entre deux mesures, juste assez pour que le joueur sente le tempo avant de repartir. Le plaisir vient de la *chaîne* (dash → saut → slash → wall-run → slash), jamais d'un kill isolé. Un kill qui arrive hors flux de mouvement (joueur arrêté, ennemi immobile devant lui) doit se sentir comme une syllabe bâillée — techniquement correct mais mécaniquement vide. Un kill en plein dash avec un pivot de caméra doit se sentir comme une note parfaitement placée.

Référence précise : **Hotline Miami en vue FPS à la Ghostrunner**. Le kill est la conséquence inévitable du bon placement + bon timing, pas une action discrète qu'on "déclenche". Anti-références : les FPS où le kill est un événement célébré séparément (Shadow Warrior 3 gore finisher, DOOM Eternal glory kill à l'écran fixe), les jeux où le combat a son propre rythme distinct du mouvement (Sekiro combat parry qui fige le mouvement). Ici, le katana est *dans* le mouvement, jamais *à la place de*.

Ce que le joueur doit *jamais* ressentir : "j'ai eu du bol sur ce hit", "ce kill était satisfaisant, je me pose", "le combat est un mode séparé du platforming", "j'ai fait un combo". Si un playtester prononce les mots *combo*, *finisher*, *engagement*, *affrontement*, ou parle d'un kill isolé comme d'un événement mémorable — le système a échoué. Les seuls mots admis dans les verbatims sont ceux du rythme et du passage : *beat*, *tempo*, *staccato*, *traverser*, *enchaîner*, *cadence*.

> *Note de cohérence cross-fantasy* : cette framing est la sœur rythmique de la Movement Fantasy ("ma main bouge et le jeu est déjà là"). Movement = la course. Combat = les notes. Camera = la scène qui rend les notes audibles. Les trois sont un seul instrument joué par le joueur.

## Detailed Design

### Core Rules

1. **Trigger du swing** — Combat écoute le signal `Player.attacked()` émis par Movement (ADR-0005 D-2 : Movement forward `InputManager.was_pressed_this_tick(&"attack")` chaque tick où l'action est pressée). Combat **ne poll jamais directement `InputManager.*`** — ce couplage via signal préserve la règle Input System Core Rule 1 ("aucun système ne lit `Input.*` directement") et garantit que Movement reste l'unique propriétaire du edge-detection `attack`. À réception du signal, Combat évalue la garde `_cooldown_timer <= 0.0 and _state != State.DEAD` ; si passant, le système entre en état `Swinging` au tick courant.

2. **Three states seulement** : `Idle`, `Swinging`, `Dead`. Idle = prêt à swing (cooldown éventuellement en décrémentation passive). Swinging = active window pendant `ACTIVE_TICKS = 8` ticks physiques (120 ms @ 60 Hz). Dead = mirror du `Player.state == DEAD` via connection au signal `Player.died()`. Le Combat System **n'a pas de machine d'état propre pour les states Movement** — il lit `Player.state` en read-only quand nécessaire (pour l'orientation du sweep, cf. Rule 5).

3. **Timing du swing + buffering input** (fige le rythme staccato — cohérent Pillar 1 + Fantasy "beat rythmique") :
   - `SWING_DURATION_MS = 120` (8 ticks @ 60 Hz) — fenêtre pendant laquelle la hitbox est active
   - `ATTACK_COOLDOWN_MS = 400` — délai minimum entre fin de swing N et début de swing N+1 (~2.5 swings/s max)
   - `ACTIVE_TICKS = ceil(SWING_DURATION_MS / (delta × 1000))` ; exemple calibre @60 Hz → 8 ticks (non-hardcode : recalcule si delta change, ADR future 120 Hz).
   - Le cooldown démarre au **début** du swing (pas à la fin). Pattern habituel qui evite le spam fin-de-window **et** qui reduit le temps effectif inter-swings de `SWING + COOLDOWN = 520 ms` (~1.9 swings/s) a `max(SWING, COOLDOWN) = 400 ms` (~2.5 swings/s) — calibrage staccato choisi.
   - **Buffering input `ATTACK_BUFFER_MS = 80 ms`** (decision Martin r1 D1 — confirme r4 D-r3-1 **buffer unconditionnel**) — si `Player.attacked()` est recu alors que `_cooldown_timer > ATTACK_BUFFER_MS / 1000.0` (clic trop precoce), le signal est **ignore silencieusement** (comme avant). Si `_cooldown_timer <= ATTACK_BUFFER_MS / 1000.0` (dans la fenetre de 80 ms avant expiration), le signal est **bufferise** dans `_buffered_attack: bool = true`. Au tick ou `_cooldown_timer` atteint `0.0`, si `_buffered_attack == true` ET `_state == Idle`, le swing demarre immediatement et le flag est remis `false`. Le buffer est **single-slot** (pas une queue) — un seul clic bufferise, les suivants dans la fenetre sont ignores. Le buffer est **efface** lors de `died()` / `respawned()` (voir Edge Case mort/respawn pour propagation explicite). Rationale : Pillar 1 FLOW exige que le joueur ressente "le jeu attrape mon intention" et non "le jeu refuse mes clics". Refs Hades / Hotline Miami / Ghostrunner ont tous un buffer comparable (50-150 ms). **Garde-fou speedrun** : le buffer ne peut etre superieur a `ATTACK_COOLDOWN_MS / 5 = 80 ms` (marge 5x) pour preserver la precision frame-perfect au haut niveau.

   **r4 D-r3-1 — Buffer unconditionnel assume (decision Martin 2026-04-23)** : le buffer s'applique dans **tous les states Movement** (Grounded, Airborne, Dashing, WallRunning), y compris stationnaire. Un joueur immobile qui clique 80 ms avant expiration cooldown obtiendra un swing au tick exact, identique a un joueur en dash. Tension Fantasy reconnue : la Fantasy B "silence entre deux notes de mouvement" suggere que le kill hors-flux doit sembler mecaniquement vide, mais la decision Martin priorise Pillar 1 FLOW (precedents Hades/Hollow Knight/DMC — buffer unconditionnel est invisible au joueur quand il est bien cale). Consequence QA : AC-CMB-33 (kill hors-mouvement perceived as plat) reste ADVISORY playtest — si le playtest revele que le buffer dilue trop la Fantasy, reevaluer en Tier 2 via ajustement economique (Level System garantit que stationnaire est rare) plutot que par conditionnement du buffer lui-meme. Le buffer reste unconditionnel.

4. **Géométrie de la hitbox** :
   - Forme : `CapsuleShape3D`, `radius = KATANA_RADIUS = 0.45 m`, `height = KATANA_REACH = 1.8 m`
   - Alignement : l'axe long de la capsule est colinéaire à `CameraSystem.aim_forward`. Origine de la capsule = `player.global_position + aim_forward × (KATANA_REACH / 2)` (centre de la capsule = centre de la reach).
   - Rationale : `1.8 m` oblige la proximité (vs `~2.0 m` Ghostrunner) — colle à la Fantasy "traverser", pas "viser à distance". `0.45 m` radius couvre la lame + 0.10 m de marge pour le feel "netteté".

5. **Orientation du sweep = aim_forward, JAMAIS `camera.basis.z` NI `player.transform.basis.z`** (r1 reinforce) — Combat lit `CameraSystem.aim_forward` (forme close trigonométrique roll-corrigée, cf. ADR-0002 + Camera GDD Rule 13). Le tilt wall-run (`camera_effects.rotation.z`) ne doit pas dévier la direction du katana horizontalement — sans cette règle, un swing pendant wall-run traverserait le sol ou le plafond de façon imprévisible. En état `Dashing`, l'orientation reste `aim_forward` (pas `player.velocity.normalized()`) : le joueur choisit où il regarde, pas où il dash — c'est la lecture naturelle et ça produit les moments "dash latéral + slash face".

   **Interdit explicite (forbidden_pattern candidat) r1 resolut BLOCKING #5** : le draft initial listait `player.transform` dans les read-only properties Dependencies (Section F), ce qui contredisait Rule 5 (`transform.basis.z` interdit). La Section F est corrigee r1 : `player.transform` est retire de la liste exposee, seul `player.global_position` suffit comme position source. Tout acces a `player.transform.basis.z` par Combat est un bug de code review a rejeter.

6. **Sweep strategy** — un `ShapeCast3D` node persistant (child de Player, configuré `enabled = false` hors window active). 

   **Ownership cache `_prev_position` (r1 specification, resolut BLOCKING #4)** : Combat est child de Player dans le scene tree. Godot `_physics_process` execute parent AVANT enfants en depth-first preorder → `Player._physics_process()` (Movement incluant `move_and_slide()`) s'execute AVANT `CombatSystem._physics_process()`. Au moment ou CombatSystem s'execute, `player.global_position` reflete deja tick N (post-move_and_slide). Combat est donc **proprietaire exclusif** de `_prev_position: Vector3` — cache en **fin de son propre `_physics_process`** (apres tout calcul de sweep du tick courant), valeur = `player.global_position` (qui est la position tick N). Au tick suivant N+1, `_prev_position` contient donc la position tick N — correcte pour le sweep N+1. Initialisation : `_prev_position = player.global_position` a `_ready()` (premier tick N=0 → sweep_delta=Vector3.ZERO, pas de sweep possible au tick 0 car Idle).

   Chaque tick de l'active window :
   - `shape_cast.global_transform.origin = _prev_position + aim_forward × (KATANA_REACH / 2)` (centre de la capsule positionne au tick N-1 + offset reach)
   - `shape_cast.target_position = shape_cast.global_transform.basis.inverse() * (player.global_position - _prev_position)` (delta de déplacement inter-tick **converti en coordonnées locales via `basis.inverse()`**, cf. Formula 2 r4 S-F-04 + r5 BLOCK-r5-A fix — la formulation "exprime en local si basis identité" du draft initial était un cas particulier qui produisait un bug de direction sweep jusqu'à 90° quand `aim_forward != Vector3(0, 0, -1)`)
   - `shape_cast.global_transform.basis` orienté sur `aim_forward` courant (recalcule chaque tick — Rule 5)
   - **Addendum Gap 2 (r1 resolut BLOCKING #2 triple convergence + r2 code pattern complet)** : au **premier tick de la window active** (`_active_tick == 0`), Combat precede le `force_shapecast_update()` par un `space_state.intersect_shape()` statique de **meme forme** a `origin = _prev_position + aim_forward × (KATANA_REACH / 2)` pour capturer les colliders deja en overlap a l'origine. Justification : Godot 4.6 ShapeCast3D avec `target_position` non-nul ne detecte **pas** systematiquement les colliders deja en overlap a `origin` (comportement non modifié selon les migration guides officiels 4.4/4.5/4.6 **mais non vérifié empiriquement sur cette codebase Godot 4.6 + Jolt — r5 BLOCK-r5-D fix auto-contradiction : Gap 2 Open Question 1 test empirique deadline fin Sprint 1 Combat impl, owner lead-programmer, résultat consigné dans `docs/engine-reference/godot/modules/physics.md`**). La mitigation `_tick0_intersect_shape_overlap()` reste en place quel que soit le résultat empirique (defensive-correct). Les colliders retournes par `intersect_shape` sont **unionises** (via Dictionary `_tick0_ids: Dictionary[int, Node]` pour dédup O(1) sur `get_instance_id`) avec ceux de `force_shapecast_update`, puis filtre/tri multi-hit Rule 9 applique. Aux ticks N>=1 de la window, seul `force_shapecast_update` suffit (l'overlap tick-1 est deja capture, les overlaps futurs sont traverses par le sweep).

     **Code pattern Godot 4.6 complet (r2 resolut BLOCKING-D gameplay-programmer + godot-specialist REC-R2-04)** :

     ```gdscript
     # Appele UNIQUEMENT quand _active_tick == 0 (premier tick window)
     # r6 CONV-1 FIX : basis construite via helper _build_capsule_basis (cross product direct,
     # axe Y = aim_forward par construction — voir helper partagé plus bas Rule 6 code pattern).
     # Le pattern r4 Basis.looking_at * from_euler(+PI/2) produisait un axe Y ANTIPARALLELE
     # a aim_forward (masque par symetrie CapsuleShape3D mais visible via target_position
     # = basis.inverse() * sweep_delta → tunneling direction inversee 180°).
     func _tick0_intersect_shape_overlap() -> Array[Node]:
         assert(shape_cast != null, "CombatSystem requires ShapeCast3D child (r4 defensive assert)")
         var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
         var query := PhysicsShapeQueryParameters3D.new()
         query.shape = shape_cast.shape  # meme CapsuleShape3D que le ShapeCast3D persistant
         # r6 : _build_capsule_basis encapsule le safe_up fallback pitch +/- PITCH_LIMIT (r4 B-R3-01)
         # + garde runtime determinant quasi-singuliere (r5 systems B-1).
         query.transform = Transform3D(
             _build_capsule_basis(aim_forward),
             _prev_position + aim_forward * (KATANA_REACH / 2.0)
         )
         query.collision_mask = 0b00010  # Enemy layer uniquement (Rule 12)
         query.exclude = [player.get_rid()]  # defensif — collision_mask filtre deja Player (layer 0b00001)
         query.collide_with_bodies = true
         query.collide_with_areas = false  # Combat ne cible pas les Area3D (pickups, triggers)
         # intersect_shape retourne Array[Dictionary] : chaque dict contient {collider: Node, shape: int, rid: RID, collider_id: int}
         var hits: Array[Dictionary] = space_state.intersect_shape(query, 32)
         var result: Array[Node] = []
         for hit: Dictionary in hits:
             var node := hit.collider as Node
             if is_instance_valid(node):
                 result.append(node)
         return result
     ```

     **r4 B-R3-02 RESOLU — Union intersect_shape + force_shapecast_update (call site complet)** : le GDD r2/r3 documentait l'union en prose mais ne fournissait pas de code pattern pour la dedup. r4 code pattern explicite (dedup O(1) par `get_instance_id()` via Dictionary) :

     ```gdscript
     # Call site dans _physics_process Combat (pendant _state == SWINGING)
     # Union des deux sources de colliders au tick 0 de la window active
     func _collect_swing_hits() -> Array[Node]:
         var seen_ids: Dictionary[int, bool] = {}
         var merged: Array[Node] = []

         # 1) Source A (tick 0 uniquement) : intersect_shape capture overlaps a l'origine
         if _active_tick == 0:
             for node: Node in _tick0_intersect_shape_overlap():
                 var id: int = node.get_instance_id()
                 if not seen_ids.has(id):
                     seen_ids[id] = true
                     merged.append(node)

         # 2) Source B (tous ticks) : ShapeCast3D capture colliders entres pendant le sweep
         shape_cast.force_shapecast_update()
         for i in range(shape_cast.get_collision_count()):
             var collider: Node = shape_cast.get_collider(i) as Node
             if not is_instance_valid(collider):
                 continue
             var id: int = collider.get_instance_id()
             if not seen_ids.has(id):
                 seen_ids[id] = true
                 merged.append(collider)

         return merged  # transmis a Rule 9 filter + Rule 10 idempotence + Formula 6 tri multi-hit
     ```

     **Note Gap 7 (CapsuleShape3D axis basis — r6 CONV-1 FIX)** : Godot `CapsuleShape3D` a son axe long sur Y par convention. Pour aligner Y sur `aim_forward`, on construit la basis **directement via cross product** (pas `Basis.looking_at * from_euler`) :

     ```gdscript
     # r6 CONV-1 FIX — helper partage par _tick0_intersect_shape_overlap + setup ShapeCast3D tick courant.
     # Verifiable math : _build_capsule_basis(v) * Vector3.UP == v pour tout v unit vector non-colineaire a safe_up.
     # r4 B-R3-01 guard : fallback safe_up = FORWARD si aim_forward colineaire a UP (pitch +/- PITCH_LIMIT).
     # r5 systems B-1 guard : fallback IDENTITY si determinant quasi-singulier (amplification conversion local).
     func _build_capsule_basis(forward: Vector3) -> Basis:
         assert(forward.is_normalized(), "aim_forward doit etre unit vector (Camera Rule 13)")
         var safe_up: Vector3 = Vector3.UP
         if absf(forward.dot(Vector3.UP)) > 0.999:
             safe_up = Vector3.FORWARD
         var right: Vector3 = safe_up.cross(forward).normalized()
         var local_z: Vector3 = right.cross(forward)
         var b := Basis(right, forward, local_z)  # axe Y = forward par construction
         if absf(b.determinant()) < 0.01:
             push_error("_build_capsule_basis: basis quasi-singuliere, fallback IDENTITY — forward=%v" % forward)
             return Basis.IDENTITY
         return b
     ```

     **Pourquoi pas `Basis.looking_at * from_euler(+PI/2)` (pattern r4 retiré r6)** : `Basis.looking_at(target, up)` oriente l'axe **-Z local** sur `target` (convention caméra Godot 4.x). La rotation `from_euler(+PI/2, 0, 0)` autour de X permute Y et Z de telle manière que l'axe **+Y local** pointe **antiparallèle** à `aim_forward`. La symétrie de `CapsuleShape3D` sur son axe long masquait l'erreur à la détection standard, mais `ShapeCast3D.target_position = basis.inverse() * sweep_delta` (Formula 2) propageait l'inversion 180° dans la direction du sweep → tunneling garanti dès que `aim_forward ≠ Vector3(0,0,-1)`. Convergence multi-specialist r5.2 (gameplay-programmer + godot-specialist fresh session). AC-CMB-08 r6 teste l'alignement via `(_build_capsule_basis(aim) * Vector3.UP).angle_to(aim) < 0.001 rad` sur 100 échantillons sphère unitaire (détecte l'inversion 180° = `π rad`). Documente dans `docs/engine-reference/godot/modules/physics.md` (a ajouter par lead-programmer en pre-Sprint 1).

   La forme sweepée couvre donc le volume balayé ENTRE les deux ticks — prévient le tunneling quand le joueur dash à haute vélocité pendant le swing. L'union `_collect_swing_hits()` au tick 0 couvre les overlaps initiaux (Gap 2 addendum).

   **Addendum r5 — Exemption ADR-0005 D-9 (zero-alloc) explicite** : `_collect_swing_hits()` et `_tick0_intersect_shape_overlap()` allouent localement `var seen_ids: Dictionary[int, bool] = {}`, `var merged: Array[Node] = []`, et (tick 0 uniquement) `var query := PhysicsShapeQueryParameters3D.new()` + `var hits: Array[Dictionary]` + `var result: Array[Node]` — soit **~16 allocations max par swing** (8 ticks actifs × 2 locaux + 5 allocations au tick 0). Convergence r5 godot-specialist B3 + performance-analyst P-R5-07 a identifié une tension avec ADR-0005 D-9 zero-alloc hot path. **Décision explicite (déléguée lead-programmer, DEC-r5-3) : exemption documentée** — pas de refactor pool pré-alloué au MVP. Rationale : (1) taille bornée ≤ 3 entrées (MAX_KILLS_PER_SWING), (2) allocation locale à scope court avec cleanup GDScript déterministe à fin de fonction, (3) AC-CMB-37 soak 1000 cycles avec seuil `Performance.OBJECT_COUNT` delta ≤ +5 et `MEMORY_STATIC` delta ≤ +500 KB valide empiriquement l'absence de fuite, (4) refactor pool anti-YAGNI avant mesure. **Si AC-CMB-37 échoue au bench empirique** : refactor pool `_PooledQueryParams` + `_seen_ids`/`_merged` promus membres privés pré-alloués + `.clear()` en entrée `_collect_swing_hits()`. L'exemption doit être documentée dans le Pending ADR Combat Tick Model (lead-programmer, pre-Sprint 1) avec ces 4 clauses + clause de rollback conditionnel AC-37.

7. **Anti-tunneling — subdivision CONSTANTE `N_SUBSTEPS = 3`** (r1 CD tranche BLOCKING desaccord #4 — choix vs N dynamique 1|3 du draft initial) : le sweep est **toujours** subdivise en 3 casts sequentiels de `delta/3` chacun, avec positions interpolees lineairement entre `_prev_position` et `player.global_position`. Justification Pillar 1 : un N dynamique (1 si V<=25, 3 sinon) genere un **frame time spike silencieux** a la frontiere 25 m/s (passage 1→3 casts double-triple le cout CPU du tick). Ces spikes peuvent produire un skip de collision lors d'un dash-slash synchrone — exactement le pire cas que Pillar 1 interdit. Cout CPU constant a 3 casts par tick actif est tolerable (a valider via AC-CMB-35a microbench, voir Section H). Formule : `gap_max = V × delta / N_SUBSTEPS = V × 0.01666 / 3`. A V=30 m/s, `gap_max ≈ 0.167 m` — inferieur au rayon ennemi (0.35 m), tunneling impossible. Seuil theorique de rupture : V > 126 m/s (bien au-dela du max projete V_max=30 m/s, marge 4x). `TUNNELING_THRESHOLD` est **deprecie** (valeur conservee en config pour compat future si un mode low-V sans subdivision est reintroduit, mais jamais consume dans Rule 7).

8. **Comportement par state Movement** : le swing est autorisé dans tous les states Movement sauf `Dead` :

   | Movement state | Swing autorisé | Orientation sweep | Notes |
   |---|---|---|---|
   | Grounded | ✅ | `aim_forward` | Cas standard |
   | Airborne | ✅ | `aim_forward` | Fantasy "traverser" — le plus fréquent en Pillar 4 |
   | Dashing | ✅ | `aim_forward` (**pas** `dash_dir`) | Décrit Rule 5 — le joueur choisit la direction de slash via le regard |
   | WallRunning | ✅ | `aim_forward` | Hitbox **non étendue** latéralement (éviter avantage invisible) |
   | Dead | ❌ | — | Le signal `attacked()` est ignoré pendant Dead |

9. **Pénétration multi-ennemi (multi-hit)** : un sweep peut toucher plusieurs ennemis simultanément. Résolution :
   - Tous les colliders retournés par `force_shapecast_update()` sont collectés.
   - Filtrés par `collider not in _hit_this_swing and collider.has_method("die") and not collider.is_dead()`.
   - **Triés par distance croissante** à `player.global_position` (déterministe, requis pour speedruns + ordering VFX spawn).
   - Les `MAX_KILLS_PER_SWING = 3` premiers reçoivent `collider.die()`. Au-delà, les ennemis supplémentaires sont ignorés silencieusement ce tick (ils pourront être touchés aux ticks suivants de la même window active s'ils restent dans le sweep — garde-fou contre "un coup vide une salle").
   - Chaque kill traité émet `enemy_killed(enemy: Node, position: Vector3)`.
   - Si ≥ 2 kills dans le même tick : émet en plus `multi_kill(count: int)` (hook pour feedback audio/VFX dédié, pas MVP mais infrastructure prête).

10. **Idempotence du sweep (active window 8 ticks) + guard freed nodes** (r1 resolut BLOCKING #3 double convergence) : `_hit_this_swing: Array[int] = []` — **stockage d'instance_ids** (int stables, pas de reference Node), reinitialise a `[]` a l'entree en etat `Swinging`. 

    Pattern : quand un collider est tue, `_hit_this_swing.append(collider.get_instance_id())`. Au tick suivant, filtrage :
    ```gdscript
    for collider in shape_cast_results:
        if not is_instance_valid(collider):
            continue  # Enemy queue_free'd entre ticks — skip silencieux (cohérent is_dead() filter)
        if collider.get_instance_id() in _hit_this_swing:
            continue  # deja tue ce swing
        if not collider.has_method(&"die") or collider.is_dead():
            continue
        # resolve kill...
    ```
    
    Justification migration `Array[Node]` → `Array[int]` : un `Node` devenu invalide (`queue_free()`'d par Enemy System ou autre source externe comme laser concurrent) garde sa reference en memoire mais toute operation dessus peut paniquer en debug build. En stockant l'`instance_id` (int qui ne change pas après `queue_free()`), l'idempotence survit meme si l'ennemi est libere. **r5 BLOCK-r5-godot-B4 précision critique** : `is_instance_valid()` n'est **pas** une garde "complémentaire" mais **OBLIGATOIRE avant tout accès via `instance_from_id(id)`** — un Node en cours de suppression (`queue_free()` appelé mais cleanup frame pas encore exécuté) a toujours un `instance_id` valide dans `ObjectDB` mais n'est plus manipulable (toute opération panique en debug build). **Ne pas extrapoler "instance_id stable = accès safe" à d'autres contextes dans le codebase** : le seul gardien correct d'un accès post-queue_free est `is_instance_valid()`. Le pattern `debug_hits_last_swing` (Published API) suit strictement ce contrat : `instance_from_id(id)` toujours précédé de `is_instance_valid()`.
    
    Un ennemi touché au tick N de la window ne peut plus être re-touché aux ticks N+1 à N+7. À la sortie de `Swinging` (tick `ACTIVE_TICKS + 1`), `_hit_this_swing.clear()`. **Contrat `die()` idempotent sur l'ennemi** : l'Enemy System DOIT garantir que `enemy.die()` appelé deux fois n'émet qu'une seule fois son signal `enemy_killed` (early return si déjà Dead, pattern Movement `die()` godot-specialist F6). Combat ne dépend pas aveuglément de cette garantie — la liste `_hit_this_swing` est la double-sécurité.
    
    **Interdit explicite (forbidden_pattern candidat pour `docs/architecture/architecture.md`)** : ne jamais lire `_hit_this_swing` depuis un Thread GDScript. Si Enemy System introduit du pathfinding threade plus tard, l'acces concurrent a cette liste est un forbidden_pattern a registered.

11. **Reach fixe (pas de velocity lookahead)** : `KATANA_REACH = 1.8 m` constant. **Aucun allongement dynamique** avec la vélocité joueur. Rationale : un reach variable crée une aide implicite à la visée qui masque les miss légitimes — exactement les anti-références Fantasy (Shadow Warrior 3, DOOM glory kills). La latence input-display (~33 ms à 60 Hz) est absorbée par les 8 ticks de `ACTIVE_TICKS` (133 ms de window active).

12. **Collision layers/mask** (taxonomie projet — première GDD qui les fige, à enregistrer en registry) :

    | Layer | Bit | Nom | Usage |
    |---|---|---|---|
    | 1 | `0b00001` | Player | Body + ShapeCast katana |
    | 2 | `0b00010` | Enemy | Enemy body/hitbox |
    | 3 | `0b00100` | EnemyHitbox | Hitboxes **létales** vers joueur (laser, projectile) |
    | 4 | `0b01000` | Environment | Sols, murs, plafonds |
    | 5 | `0b10000` | Interactive | Triggers shop/checkpoints/secrets |

    | Volume | Layer | Mask | Rôle |
    |---|---|---|---|
    | Katana `ShapeCast3D` | 1 (Player) | 2 (Enemy) | Ne détecte que Enemy — jamais EnemyHitbox, jamais mur |
    | Enemy laser / projectile | 3 (EnemyHitbox) | 1 (Player) | Touche exclusivement Player body |
    | Player `CharacterBody3D` | 1 (Player) | 3+4+5 | Détecte hitboxes létales + environment + interactive |
    | Enemy `CharacterBody3D` (nav) | 2 (Enemy) | 4 (Environment) | Les ennemis se déplacent contre murs uniquement |

13. **Slow-mo au kill via `Engine.time_scale`** (r1 revise — decision Martin D3 + CD tranche BLOCKING #8 `_process` → `_physics_process`) : à la réception du premier `enemy_killed` d'un swing, Combat set `Engine.time_scale = SLOW_MO_SCALE = 0.3` (valeur r1) pendant `SLOW_MO_DURATION_MS = 50` (r1) wall-clock absolu via `Time.get_ticks_msec()`, puis restore `Engine.time_scale = 1.0`. 
    
    **Perception a l'ecran** : 50 ms wall-clock a time_scale 0.3 → simulation avance de 15 ms physique pendant la fenetre → **167 ms percus** a 60 Hz rendering (10 frames). Volontairement plus court que le draft initial (667 ms percus a 0.15×) — le slow-mo est une micro-pause rythmique ("silence entre deux notes"), pas un climax cinematique (anti-Fantasy). Peut etre retune en playtest dans les ranges safe de la Section G.
    
    **Check de restore en `_physics_process` (pas `_process`)** : le draft initial proposait le check dans `_process` avec justification "non scale par time_scale", mais cette justification est **erronee** (`_process` EST aussi scale par time_scale en Godot 4.x). Le check en `_physics_process` fonctionne de maniere identique avec `Time.get_ticks_msec()` (wall-clock independant du callback). Place en `_physics_process` pour respecter ADR-0001 "_process cosmetic only" — aucune logique qui mute l'etat moteur global ne doit vivre dans `_process`. Tolerance de restore : jusqu'a 1 physics frame (16.6 ms wall-clock) apres expiration theorique — acceptable.
    
    Impact connu :
    - **Physics Jolt** ralentit avec `time_scale` (delta réduit) — cohérent avec le feel "pause suspendue".
    - **Input polling cadencé 60 Hz wall-clock** (non affecté par time_scale) — inputs captés et quiesced pendant la pause.
    - **Timers Godot en mode IDLE/PHYSICS respectent time_scale** — acceptable (les cooldowns Combat reprendront leur cours à la restauration, pas de glitch).
    - **Audio `AudioStreamPlayer`** : pitch **non** affecté par `Engine.time_scale` en Godot 4.6 (comportement confirme audio-director + godot-specialist r1). Le "whoosh" katana reste à vitesse normale (souhaité : la slow-mo est visuelle, pas sonore ; decision Martin D3 = no pitch audio). Correction r1 : la section Visual/Audio Row 5 "Slow-mo audio response" est reformulee pour refleter ce comportement correct (voir Section).
    - **Tick courant et time_scale** (r1 resolut BLOCKING #7) : l'assignation `Engine.time_scale = 0.3` au milieu d'un `_physics_process` tick **n'affecte PAS le tick en cours** — Godot recalcule `delta` pour le tick SUIVANT uniquement. Consequence : sur un multi-kill tick, les 3 `enemy_killed` sortent dans le meme tick a delta non-scale, `multi_kill(3)` emis au meme tick, puis tick N+1 demarre avec delta scale. AC-CMB-25 couvre ce sequencement.
    - **Multi-kill** : si un deuxième `enemy_killed` tombe pendant la slow-mo active (ou dans le meme tick), la fenêtre n'est **pas** re-entrée ni étendue — une seule slow-mo par swing (évite compound qui ralentirait l'écran a 0.027× sur 3 kills successifs).
    - Idempotence : Combat garde `_slow_mo_active: bool` pendant la fenêtre, toute tentative de re-entrée est no-op.

14. **One-shot symétrie joueur** : Combat ne détecte PAS les hitboxes ennemies frappant le joueur — c'est le `Player.CharacterBody3D` (layer 1, mask 3+4+5) qui collisionne avec `EnemyHitbox`, via un signal `body_entered` de l'Area3D ennemi ou un check de collision dans l'Enemy System. Quand déclenché, l'Enemy System appelle `Player.die()` (Movement-owned). Combat n'a **aucun rôle dans la mort du joueur** — il respecte simplement l'état `Dead` (Rule 8). Cette séparation garantit qu'un bug Combat ne peut pas tuer le joueur par accident.

15. **Pas d'invulnérabilité pendant le swing ni pendant le dash** (aligné Movement GDD décision post-review : "invulnérabilité = non MVP, réévalué en playtest"). Le joueur qui clique `attack` en plein laser meurt — le slash ne le sauve pas. C'est la conséquence directe de "one-shot mutuel strict" (concept doc anti-pillar).

16. **Pas de viewmodel (katana visible 1st-person) au MVP** : c'est un asset art qui viendra en Visual/Audio. La logique Combat fonctionne sans viewmodel — seul le trail VFX + sons + feedback kill suffisent à rendre le swing lisible au MVP. Le viewmodel sera ajouté en Tier 2. **Onboarding caveat (r1 note game-designer)** : sans viewmodel et sans UI, le Level System DOIT garantir qu'un ennemi est visible dans les 10 premieres secondes de la salle de tutoriel et qu'une zone safe permet au joueur d'experimenter `attack` sans mourir. Ce contrat est a tracer dans le Level System GDD a venir.

17. **Mutual kill tick-meme — les deux meurent (r2 M1 Option C Hybrid, Martin 2026-04-23)** : si `Player.died()` est emis par Enemy System au **meme tick physique** ou Combat traite un `enemy_killed`, **les deux morts sont resolues**.

    **Mecanisme M1 Option C Hybrid (r2 resolut BLOCKING-CONV-4)** : le signal `died` de Movement est connecte a Combat en **SYNC** (coherent ADR-0005 D-5 amendment r2 — exemption pour signaux frame-precis). Le handler sync `_on_player_died()` de Combat **ne mute PAS directement `_state`** — il set un flag interne `_death_pending: bool = true`. Ce flag est verifie et consomme **en fin de `_physics_process`** de Combat, APRES la resolution complete des colliders du tick courant. Cette architecture coexiste avec AC-CMB-28 (race condition `_state == IDLE` et `player.state == Dead` sans signal — force Dead immediat) et AC-CMB-41 (mutual kill pendant Swinging — resolve colliders avant Dead) sans contradiction : les deux cas sont distingues par la phase du swing au moment de la reception du signal.

    **Sequence garantie** : 
    - Tick N `_physics_process` — Movement `_physics_process` (parent, DFS preorder) execute, recoit le signal du laser ennemi, appelle `Player.die()` → emet `died` signal SYNC.
    - Handler SYNC `_on_player_died()` de Combat execute inline (dans la stack de Movement `_physics_process`) : set `_death_pending = true`. **Ne mute pas `_state`**. Retourne immediatement.
    - Combat `_physics_process` (child, execute apres Movement) demarre. Si `_state == Swinging`, Combat execute son sweep normalement : resolution colliders du ShapeCast (Rule 9, multi-hit avec `MAX_KILLS_PER_SWING` et `_hit_this_swing`). Les `enemy_killed` sont emis normalement.
    - **En fin de `_physics_process`** (apres toute resolution collider, avant retour de la frame), Combat verifie `_death_pending` : si `true`, transite vers `Dead` : `_state = State.DEAD`, `ShapeCast3D.enabled = false`, `_death_pending = false`. Le `swing_ended` n'est **pas** emit (swing interrompu par Dead, coherent Edge Case mort/respawn).
    - Si `_slow_mo_active == true` au moment de la transition Dead : `Engine.time_scale = 1.0` restaure **avant** la transition (coherent Edge Case mort pendant slow-mo + AC-CMB-21 — eviter respawn ralenti).
    - Rationale : la Fantasy dit "le kill est la consequence inevitable du bon placement" — si le joueur a place son swing dans la hitbox ennemie au tick ou l'ennemi a place le sien dans la hitbox joueur, les deux ont reussi, les deux meurent. Symetrie one-shot stricte preservee. La ludonarrative est coherente : le joueur perd la vie mais gagne le kill au tableau (Credit Economy comptabilise), respawn 50 ms (Pillar 3) lance la prochaine tentative avec le compte credite.
    - **Difference avec draft initial** : le draft disait "ennemi gagne" (priorite Movement.die() resolu avant Combat). Cette asymetrie etait une violation Fantasy documentee — r1 la corrige via Martin D2 + r2 la sécurise via M1 Option C Hybrid (mécanisme `_death_pending` explicite).

    **Consequence pour AC-CMB-28 (race condition Idle)** : la garde "`player.state == Dead and _state != Dead` → force Dead immediat" s'applique **uniquement quand `_state == IDLE` en debut de `_physics_process`** (pas pendant Swinging). Pendant Swinging, le mécanisme `_death_pending` gouverne (voir plus haut). Distinction tracée dans AC-CMB-28 r2.

18. **Decal cap et pool LRU** (r1 resolut BLOCKING #10 performance) : les decals sang au sol sont bornes a `MAX_DECALS_PER_ROOM = 12` (tuning knob) par salle (scene ou niveau separes geographiquement). Quand un 13e `enemy_killed` spawne un decal et que le cap est atteint, le **plus ancien decal de la salle courante** est recycle (pool LRU). Implementation : VFX System maintient `Array[Decal]` borne, `append` en fin de liste, `pop_front()` + reassignation transform si cap atteint. Justification : Godot 4.6 Forward+ pipeline voit degradation de perf non-lineaire au-dela de ~32 decals simultanes sur hardware entry-level — le cap 12 garde un headroom 2-3x pour autres sources (future Hazard System, Credit pickup flashes, etc.). AC performance dedie (voir Section H).

| State | Entry Condition | Exit Condition | Behavior |
|---|---|---|---|
| **Idle** | Tick 0 OU `_active_tick >= ACTIVE_TICKS` (fin de swing) | `Player.attacked()` reçu ET `_cooldown_timer <= 0.0` ET `_state != Dead` → Swinging ; `Player.died()` → Dead | `_cooldown_timer` décrémente chaque `_physics_process`. `ShapeCast3D.enabled = false`. Aucun travail par ailleurs. |
| **Swinging** | Transition depuis Idle validée | `_active_tick >= ACTIVE_TICKS` → Idle ; `Player.died()` → Dead (sweep interrompu) | `_active_tick++` chaque tick. `ShapeCast3D.enabled = true`, configuration du sweep (Rule 6), parcours colliders (Rule 9), émission signals. `_cooldown_timer = ATTACK_COOLDOWN_MS / 1000` est mis à l'entrée. `_hit_this_swing` accumulé puis vidé à la sortie. **Slow-mo (Rule 13) peut être déclenchée pendant ce state depuis le premier kill.** |
| **Dead** | `Player.died()` reçu | `Player.respawned(position)` reçu → Idle (reset : `_active_tick = 0`, `_hit_this_swing.clear()`, `_cooldown_timer = 0`, `ShapeCast3D.enabled = false`) | Aucun signal `attacked()` traité. Tous les timers figés. `ShapeCast3D.enabled = false` inconditionnellement. |

### Interactions with Other Systems

| Système | Rôle | Interface |
|---|---|---|
| **Input System** (amont, transitif) | Source originelle de l'action `attack` | Combat ne consomme **jamais** `InputManager.*` directement. `attack` est médiatisé par Movement qui forward `attacked()` signal. |
| **Player Movement System** (amont) | Source du signal d'attaque + position/vélocité/state | Combat connecte `player.attacked` (signal ADR-0005 D-2). Combat lit en read-only : `player.global_position`, `player.velocity`, `player.state` (pour Rule 8). **r1+r4 correction** : `player.transform` n'est PAS expose a Combat (contredit Rule 5 qui interdit `transform.basis.z`). Combat connecte `player.died` (SYNC Hybrid r2 + ADR-0005 D-5 amendment) et `player.respawned` (state transitions). **Combat ne mute jamais l'état Movement** (ADR-0005 D-7 consumer contract). |
| **Camera System** (amont) | Source de l'orientation du sweep | Combat lit `CameraSystem.aim_forward` chaque tick de la window active. Forme close roll-corrigée (ADR-0002) — jamais `camera3d.basis.z`. |
| **Enemy System** (aval) | Receveur de `die()` au hit | Combat appelle `enemy.die()` sur les colliders Enemy retournés par le sweep (Rule 9). Enemy System est responsable de l'idempotence de son propre `die()`. Combat émet `enemy_killed(enemy: Node, position: Vector3)` signal que l'Enemy System peut connecter pour cleanup si besoin. |
| **Checkpoint & Respawn System** (bidirectionnel indirect) | Via Movement | Combat n'a aucun contact direct avec Checkpoint. Le `Player.die()` déclenché par Enemy → Movement → Checkpoint chain est hors-Combat. |
| **Credit Economy** (aval) | Convertit kills en crédits | Connecte `enemy_killed` (Combat signal). Économie traite le crédit au kill, pas au swing — donc un swing miss n'affecte rien. |
| **VFX & Feedback System** (aval) | Trail katana, impact flash, blood splash, slow-mo screen effects | Connecte les signals Combat (`swing_started`, `swing_ended`, `enemy_killed`, `multi_kill`). Connexions recommandées : `CONNECT_DEFERRED` pour consommateurs lourds (GPUParticles spawn, blood decal) — cohérent Movement CONNECT_DEFERRED pattern. VFX spawne le trail + blood splash, Combat ne crée aucun asset visuel lui-même. |
| **Audio System** (aval) | Swoosh swing, impact kill, slow-mo audio mix | Connecte les mêmes signals que VFX (`swing_started` → whoosh, `enemy_killed` → impact sec 50 ms, `multi_kill` → layer audio optionnel). `CONNECT_DEFERRED` recommandé. Le pitch audio n'est **pas** affecté par la slow-mo (cf. Rule 13). |
| **HUD System** (aval) | Indicateur cooldown (optionnel MVP) | Lit `CombatSystem.cooldown_ratio: float` (0.0 prêt → 1.0 cooldown fraîchement démarré). MVP : pas d'indicateur visible (feel "no UI" art-bible) — propriété exposée pour Vertical Slice+. |
| **Upgrade System** (aval future, post-MVP) | Capabilities Combat extensibles | **Non MVP** — Combat est statique au MVP (pas d'upgrade Combat). Infrastructure préparée : si futur `can_slash_through_environment` (Tier 2+), ce serait un flag lu par Combat à l'entrée du sweep. |
| **Game State Manager** (contrôleur) | Pause global | Quand GameStateManager bascule en Paused, `Input.enabled = false` (Input System refcount, cf. ADR-0004 D-4) → Movement n'émet plus `attacked()` → Combat reçoit 0 trigger. Aucun contrôle direct Combat ↔ GameState requis. |

### Published API

**Signals (émis depuis le `CombatSystem` node, tous en `_physics_process`)** :

```gdscript
signal swing_started(direction: Vector3)                      # direction == aim_forward at swing start
signal swing_ended()                                          # after ACTIVE_TICKS ticks
signal enemy_killed(enemy: Node, position: Vector3)           # position == enemy.global_position at hit tick
signal multi_kill(count: int)                                 # count >= 2, émis en sus de enemy_killed individuels
```

**Note pattern (cohérent ADR-0005)** : signals directs depuis `CombatSystem` (child de Player), pas via EventBus. Emit depuis `_physics_process` uniquement. Typed payloads value-types (Vector3, int, Node). Consumer contract : handlers interdits de muter `CombatSystem._state` ou d'appeler `CombatSystem.attempt_swing()` de façon ré-entrante. Ordre intra-tick : `swing_started` précède `enemy_killed` du même tick ; `multi_kill` suit les `enemy_killed` individuels du même tick ; `swing_ended` émis au tick ACTIVE_TICKS+1.

**Exposed properties (read-only pour consommateurs externes — pattern `get:` sans setter, cf. Movement godot-specialist F7)** :

```gdscript
# Backing vars privées + getters sans setter (empêche écriture externe)
var _state: State = State.IDLE
var state: State:
    get: return _state

var _cooldown_timer: float = 0.0
var cooldown_timer: float:              # seconds remaining, 0.0 si prêt
    get: return _cooldown_timer

var cooldown_ratio: float:              # 0.0 (ready) → 1.0 (just fired)
    get: return clamp(_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0), 0.0, 1.0)

var is_swinging: bool:
    get: return _state == State.SWINGING

var _active_tick: int = 0
var active_tick: int:                   # 0 to ACTIVE_TICKS-1 pendant Swinging, -1 sinon — exposé debug HUD
    get: return _active_tick if _state == State.SWINGING else -1

# r2 M1 Option C Hybrid — flag interne mute par handler SYNC _on_player_died().
# Consomme en fin de _physics_process apres resolution colliders (Rule 17).
# Privee : jamais expose externe. Aucun getter public.
var _death_pending: bool = false

# r1 D1 — buffer single-slot input attaque dans fenetre [COOLDOWN - BUFFER, COOLDOWN].
# Privee : jamais expose externe. Reset au died() et respawned() (voir Edge Case mort/respawn).
var _buffered_attack: bool = false

# r4 S-02 — timestamp wall-clock du debut slow-mo (Time.get_ticks_msec()).
# Valeur significative uniquement quand _slow_mo_active == true.
# Privee : jamais expose externe.
var _slow_mo_start_msec: int = 0
var _slow_mo_active: bool = false
```

**r4 Precondition structurelle (invariants archi — B-R3-03 + godot-specialist Reco-A/B)** :

1. **CombatSystem DOIT etre direct child de Player** dans le scene tree. Le mecanisme Rule 17 `_death_pending` repose sur l'ordre DFS preorder Godot (`Player._physics_process` execute AVANT `CombatSystem._physics_process`). Tout refactor qui rend Combat sibling ou descendant indirect casse l'ordre SYNC → `_death_pending` pourrait etre set APRES le tick Combat → transition Dead decalee de 1 tick → mutual kill semantique non garantie.
2. **CombatSystem.physics_process_priority DOIT rester = 0 (defaut)**. Une valeur negative forcerait Combat a s'executer avant Player dans le meme sous-arbre → rompt la garantie d'ordre. `assert(physics_process_priority == 0, "Combat priority doit rester defaut — preserve DFS order")` en `_ready()` debug build recommande.
3. Ces 2 invariants structurels sont verifies par AC-CMB-49 (lecture de code PR) et documentes dans le Pending ADR Combat Tick Model.

**Methods appelables externes** : **aucune**. Combat est 100% réactif aux signals Movement — l'API externe est lecture-only (properties) + signals (event-driven). Pas de `force_swing()`, pas de `cancel_swing()` — la seule entrée est `Player.attacked()`.

**Note debug** : en build debug (`OS.has_feature("debug")`), propriété additionnelle exposée :

```gdscript
# r2 fix BLOCKING gameplay-programmer B : _hit_this_swing est Array[int] (instance_ids,
# cf. Rule 10 r1 migration). Le getter convertit les ids vers Array[Node] via
# instance_from_id() + filtrage is_instance_valid() pour eviter erreur de type GDScript.
var debug_hits_last_swing: Array[Node]:
    get:
        if not OS.has_feature("debug"):
            return []
        var result: Array[Node] = []
        for id: int in _hit_this_swing:
            var node := instance_from_id(id) as Node
            if is_instance_valid(node):
                result.append(node)
        return result
```

Permet au HUD F3 d'afficher "last swing hit: 2 enemies" pour debug de feel. Les ennemis déjà libérés (`queue_free` entre kill et lecture) sont silencieusement filtrés — le debug reflète les ennemis encore vivants en scene.

## Formulas

### 1. Orientation du sweep (consommation d'`aim_forward`)

**r1 correction** : la formule trigonometrique est **owned par Camera GDD Rule 13** (ADR-0002 Formula close). Combat est un **consommateur read-only** — il ne recalcule jamais cette forme close et ne duplique plus l'expression ici pour eviter le drift documentaire si Camera GDD est amende.

`sweep_forward = CameraSystem.aim_forward  # read-only consumer, owned Camera GDD`

Pour la definition mathematique (`aim_forward = Vector3(-sin(yaw)*cos(pitch), -sin(pitch), -cos(yaw)*cos(pitch))`), referer : `design/gdd/camera-system.md` Section D "Aim forward exposé" (Rule 13) + Formula 5, et ADR-0002 "Camera Scene Tree 3-tier".

**Variables consommées** :

| Variable | Type | Range | Source | Garde cote Combat |
|---|---|---|---|---|
| `sweep_forward` | Vector3 | unit vector (magnitude 1.0 strict) | `CameraSystem.aim_forward` | `is_finite()` + `not is_zero_approx()` (Edge Case cross-system) |

**Garde-fous Combat** (r1 explicit per systems-designer F1 recommandation) : Combat verifie en debut de `_physics_process` swing :
- `sweep_forward.is_finite()` (filtre NaN, inf) → sinon skip tick + `push_error` debug build
- `not sweep_forward.is_zero_approx()` (filtre vecteur nul) → sinon skip tick + `push_error` debug build

AC-CMB-27 couvre le cas ZERO. AC-CMB-27b ajoute r1 pour NaN/inf explicitement (voir Section H).

**Output range** : `|sweep_forward| = 1.0` strictement (par construction trigonometrique Camera). Aucun impact du tilt wall-run `camera_effects.rotation.z` (verifie par AC-CAM-50 cote Camera GDD).
**Example** : yaw=0, pitch=0 → `sweep_forward = Vector3(0, 0, -1)`. Yaw=π/2 → `sweep_forward = Vector3(-1, 0, 0)`.

### 2. Position de la hitbox swept (per tick de l'active window)

À chaque tick `N` de l'active window (`_active_tick ∈ [0, ACTIVE_TICKS)`) :

```
hitbox_origin   = player.global_position_tick_N_minus_1
hitbox_target   = player.global_position_tick_N
hitbox_center   = hitbox_origin + sweep_forward × (KATANA_REACH / 2)
sweep_delta     = hitbox_target - hitbox_origin
```

Le `ShapeCast3D` est configuré :
- `global_transform.origin = hitbox_origin + sweep_forward × (KATANA_REACH / 2)` (centre capsule = centre reach, devant le joueur)
- `global_transform.basis` orienté tel que l'axe long de la capsule (Y local) est parallèle à `sweep_forward` via `_build_capsule_basis(aim_forward)` (helper Rule 6 r6 CONV-1 FIX — cross product direct avec guards safe_up colineaire + determinant quasi-singulier)
- `target_position` (en coordonnees LOCALES du node, `ShapeCast3D.target_position` est toujours local en Godot 4.x) : **r4 S-F-04 correction** — quand `aim_forward ≠ Vector3(0, 0, -1)` (cas general en FPS), `sweep_delta` est en coordonnees world et DOIT etre converti en local avant assignation. Pattern correct : `shape_cast.target_position = shape_cast.global_transform.basis.inverse() * sweep_delta`. Le draft initial affirmait "local si basis identite, ou converti en local" sans preciser la conversion — bug direction sweep jusqu'a 90° si le joueur ne regarde pas exactement vers Z-

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `KATANA_REACH` | `L_k` | float | 1.4 – 2.2 m (tuning), défaut **1.8 m** | Longueur utile de la hitbox |
| `sweep_forward` | — | Vector3 unit | — | Cf. Formula 1 |
| `sweep_delta` | `Δp` | Vector3 | `\|Δp\| ∈ [0, V_max × delta]` avec V_max ≈ 30 m/s | Déplacement joueur entre tick N-1 et tick N |

**Output range** : `|sweep_delta| ≤ 30 × 0.01666 ≈ 0.5 m` par tick à V max (sans subdivision). La capsule balaie donc jusqu'à `KATANA_REACH + 0.5 = 2.3 m` de volume effectif par tick en dash full speed.
**Example** : Joueur dash vers l'avant à 30 m/s, tick N-1 = (0, 1.8, 0), tick N = (0, 1.8, -0.5). `sweep_delta = (0, 0, -0.5)`. ShapeCast balaie de (0, 1.8, -0.9) (centre = position + 0.9 m forward) avec offset -0.5 Z.

### 3. Anti-tunneling — gap maximum par tick (r2 aligne Rule 7 N constant)

**r2 correction (BLOCKING-CONV-3 résolu)** : Rule 7 r1 (CD verdict) a tranché `N_SUBSTEPS = 3` **constant** (plus de logique dynamique). `TUNNELING_THRESHOLD` est **DEPRECATED** (conservé en knob pour compat future éventuelle, jamais consommé par Rule 7 / Formula 3). Formula 3 r2 reflète le comportement constant.

`gap_max = V × delta / N_SUBSTEPS` avec `N_SUBSTEPS = 3` (constant)

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `V` | — | float | `[0, 30]` m/s | `player.velocity.length()` au tick courant (V_max ≈ 30 m/s dash) |
| `delta` | `Δt` | float | `1/60 = 0.01666` s (fixe 60 Hz, ADR-0001) | Durée tick physique |
| `N_SUBSTEPS` | `N` | int | **3** (constant, Rule 7 r1 CD verdict) | Subdivision toujours active — pas de condition dynamique |
| `TUNNELING_THRESHOLD` | `V_t` | float | **DEPRECATED** | Conservé en knob pour compat future (mode low-V sans subdivision éventuel) mais **non consommé** par Formula 3 r2 |
| `gap_max` | — | float | `[0, V × delta / 3]` m | Distance non-couverte max par tick |

**Condition anti-tunneling** : `gap_max < 2 × r_enemy_min`, avec `r_enemy_min = 0.35 m` (capsule Enemy minimum imposée par Enemy System GDD — cross-system contract).

**Output range** : `gap_max ∈ [0, 0.167]` m à V_max=30 m/s.
**Example worked (r2 N=3 constant à toute vélocité)** :
- V = 0 m/s → N=3 → gap_max = 0 m (pas de déplacement, pas de tunneling possible) ; coût CPU = 3 casts (constant, acceptable Rule 7 rationale Pillar 1)
- V = 10 m/s → N=3 → gap_max = 10 × 0.01666 / 3 ≈ 0.056 m (< 0.7 m, OK) — r2 élimine la transition 1→3 casts qui créait un frame spike silencieux à V=25 (cf. Rule 7 r1 justification)
- V = 30 m/s → N=3 → gap_max = 30 × 0.01666 / 3 ≈ 0.167 m (< 0.7 m, OK)
- V = 126 m/s (théorique seuil rupture) → N=3 → gap_max ≈ 0.7 m (= 2 × r_enemy_min, limite tunneling) — marge 4x sur V_max=30 m/s Movement.

### 4. Dérivation `ACTIVE_TICKS` + gardes r2 (BLOCKING systems-designer #5)

`ACTIVE_TICKS = ceil(SWING_DURATION_MS / (delta × 1000))`

**r2 gardes anti div/0 + invariant #2.5 (BLOCKING systems-designer #5 resolu)** :
- `assert(SWING_DURATION_MS > 0.0)` au `_ready()` de CombatSystem — sinon `ACTIVE_TICKS = 0` ou negatif → window silencieusement cassee, aucun sweep.
- `assert(delta > 0.0)` runtime en `_physics_process` : si `delta == 0.0` (debug pause exotique ou hitch extreme), `ceil(SWING_DURATION_MS / 0.0) = ceili(INT_MAX)` → boucle pathologique. Godot garantit normalement `delta > 0` via `Engine.physics_ticks_per_second > 0` — la garde est defensive.
- Invariant Section D.8 **#2.5 nouveau r2** : `SWING_DURATION_MS > 0.0` documenté.

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `SWING_DURATION_MS` | — | float | 80 – 200 ms (tuning), défaut **120 ms** | Durée nominale du swing actif |
| `delta` | `Δt` | float | `1/60` s (fixe) | Durée tick physique |
| `ACTIVE_TICKS` | — | int | `[5, 12]` | Nombre de ticks pendant lesquels `_state == Swinging` |

**Output range** : `ACTIVE_TICKS ∈ [5, 12]` sous le range de tuning (80–200 ms @ 60 Hz).
**Example** : `SWING_DURATION_MS = 120` → `ACTIVE_TICKS = ceil(120 / 16.666) = ceil(7.2) = 8`. La window effective dure `8 × 16.666 ≈ 133.3 ms` (légèrement plus longue que 120 ms nominal — arrondi sup pour ne jamais sous-couper).

### 5. Cooldown ratio (pour HUD) + garde division par zéro (r1)

```gdscript
var cooldown_ratio: float:
    get:
        if ATTACK_COOLDOWN_MS <= 0.0:  # r1 garde BLOCKING #9 systems-designer
            return 0.0
        return clamp(_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0), 0.0, 1.0)
```

**r1 resolut BLOCKING #9 (systems-designer)** : le draft initial avait `_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0)` sans garde. Si un bug de config pose `ATTACK_COOLDOWN_MS = 0` (hors safe range [300, 600] mais possible edit asset), le calcul produit :
- `0.0 / 0.0 = NaN` en IEEE 754 — `clamp(NaN, 0.0, 1.0)` est un comportement indefini GDScript (peut propager NaN).
- `x / 0.0 = +inf` — `clamp(inf, 0.0, 1.0)` = 1.0 mais chemin invalide.

Dans les deux cas, le HUD (si affichage futur) tween sur alpha NaN = rendering glitch. La garde `if ATTACK_COOLDOWN_MS <= 0.0: return 0.0` retourne un ratio de 0 (ready) sans NaN — fail gracieux. AC-CMB-36 smoke check la valeur de config en complement. Un `assert(ATTACK_COOLDOWN_MS > 0.0)` au `_ready()` de CombatSystem ferme completement le trou.

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `_cooldown_timer` | `t_c` | float | `[0.0, ATTACK_COOLDOWN_MS/1000]` s | Temps restant, décrémenté par `delta` chaque `_physics_process` |
| `ATTACK_COOLDOWN_MS` | `C_ms` | float | 300 – 600 ms (tuning), défaut **400 ms** | Cooldown nominal entre swings. **Doit etre > 0.0** (invariant r1, garde Formula 5). |
| `cooldown_ratio` | — | float | `[0.0, 1.0]` | 0=ready, 1=just fired ; retourne 0.0 si `ATTACK_COOLDOWN_MS <= 0` (fail gracieux) |

**Output range** : `cooldown_ratio ∈ [0.0, 1.0]`. À l'entrée en Swinging, `_cooldown_timer = 0.4` et `cooldown_ratio = 1.0` **exactement** (r1 note qa-lead AC-CMB-13 : denominateur identique, pas de tolerance `± 0.001` necessaire pour ce cas). Après ~400 ms décrémentation, retour à 0.0.
**Example** : `ATTACK_COOLDOWN_MS = 400`, `_cooldown_timer = 0.25 s` → `cooldown_ratio = 0.25 / 0.4 = 0.625` (± 0.001 tolerance appropriee ici car division FP intermediaire). HUD affiche une barre à 62.5% (si affichage MVP, sinon propriété inutilisée).

### 6. Tri multi-hit par distance

Pour un tick avec `k` colliders retournés par `force_shapecast_update()` :

```
candidates  = [(collider_i, distance_i) for i in [0, k)
               where not filtered_out]
distance_i  = (collider_i.global_position - player.global_position).length()
sorted      = sort_ascending(candidates, by=distance)
resolved    = sorted[0 : min(MAX_KILLS_PER_SWING - len(_hit_this_swing), len(sorted))]
```

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `k` | — | int | `[0, max_results]` avec `max_results = 32` (Godot `ShapeCast3D.max_results` défaut) | Nombre brut colliders retournés |
| `distance_i` | `d_i` | float | `[0, KATANA_REACH + 0.5]` m approx | Distance player → collider |
| `MAX_KILLS_PER_SWING` | `K_max` | int | **3** (fixe MVP) | Limite multi-kill par swing |
| `_hit_this_swing` | — | **Array[int]** (r1 migration — instance_ids) | taille ≤ `K_max` | Instance_ids des Ennemis déjà tués pendant cette window (pas références Node — survit à `queue_free`, guard `is_instance_valid()` au filtre Rule 10). |

**Output range** : `|resolved| ∈ [0, K_max - |_hit_this_swing|]`. La liste `resolved` reçoit `die()` dans cet ordre.
**Example** : 5 ennemis intersectés au tick 3 de la window, distances `[1.2, 0.8, 2.1, 1.5, 0.3]`. Aucun dans `_hit_this_swing` encore. Tri ascendant → `[0.3, 0.8, 1.2, 1.5, 2.1]`. Les 3 premiers reçoivent `die()` (ceux à 0.3, 0.8, 1.2 m). Les 2 derniers ignorés ce tick (pourraient être touchés tick 4+ s'ils restent dans le sweep — garde `_hit_this_swing` appliquée en condition de filtrage).

### 7. Timing slow-mo wall-clock (check en `_physics_process`, r1 corrige ADR-0001)

Le timer de slow-mo est mesure en **wall-clock absolu** via `Time.get_ticks_msec()` — independant de `delta` et de `Engine.time_scale`. Le draft initial proposait le check dans `_process` avec justification "non scale" — cette justification etait erronee (`_process` EST scale par time_scale en Godot 4.x, tout autant que `_physics_process`). La valeur de retour de `Time.get_ticks_msec()` est wall-clock quel que soit le callback qui l'appelle.

**r1 decision (CD tranche BLOCKING #8 desaccord godot-specialist vs gameplay-programmer)** : le check est place en `_physics_process` pour respecter ADR-0001 "_process cosmetic only". Aucune mutation `Engine.time_scale` dans `_process`.

```gdscript
# Au premier enemy_killed du swing (dans _physics_process) :
_slow_mo_start_msec = Time.get_ticks_msec()
Engine.time_scale = SLOW_MO_SCALE  # 0.3 r1
_slow_mo_active = true

# Dans _physics_process chaque tick suivant (r1 correction — pas _process) :
if _slow_mo_active:
    var elapsed_msec: int = Time.get_ticks_msec() - _slow_mo_start_msec
    if elapsed_msec >= SLOW_MO_DURATION_MS:  # 50 ms r1
        Engine.time_scale = 1.0
        _slow_mo_active = false
```

**Variables** (r1 valeurs Martin D3) :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `SLOW_MO_SCALE` | `s_m` | float | **0.3** r1 (fixe MVP), range [0.1, 0.5] | `Engine.time_scale` pendant la fenetre. r1 change de 0.15 → 0.3 pour reduire la duree percue (anti-Fantasy initialement). |
| `SLOW_MO_DURATION_MS` | `D_ms` | int | **50** r1 (fixe MVP), range [30, 150] | Duree wall-clock. r1 change de 100 → 50 ms. |
| `elapsed_msec` | — | int | `[0, D_ms + 1 physics frame]` | Mesure wall-clock par `Time.get_ticks_msec()` |
| `_slow_mo_active` | — | bool | — | Flag idempotence (une slow-mo par swing) |

**Output range** : `elapsed_msec` atteint `SLOW_MO_DURATION_MS = 50 ms` en ~3 physics frames wall-clock @ 60 Hz. Tolerance de restore : jusqu'a 1 physics frame (16.6 ms) apres expiration theorique → AC-CMB-19 documente la fenetre `[50, 67] ms` de restauration.

**Perception ecran** : 50 ms wall-clock a time_scale 0.3 → **167 ms percus** par le joueur (10 frames rendering). Coherent avec la Fantasy "micro-pause rythmique, pas climax". Comparaison : draft initial = 667 ms percus (anti-Fantasy), r1 = 167 ms (serves Fantasy).

**Example** : Kill au t=0 wall-clock. `Engine.time_scale = 0.3`. Pendant 50 ms wall-clock (3 physics ticks), simulation Jolt avance de `50 × 0.3 = 15 ms` (~1 physics tick simule). A t=50 ms wall-clock, `elapsed_msec >= 50` → restore `Engine.time_scale = 1.0`. Perception joueur : 10 frames rendering @ 60 fps = 167 ms de "beat suspendu".

### 8. Invariants numériques du système (récap non-computationnel) — r1 revise

Sanity checks à valider en test unitaire (cf. Acceptance Criteria) :

| Invariant | Formule | Statut | Justification |
|---|---|---|---|
| **1. Reach physique** | `KATANA_REACH > player.capsule_radius + 1.0 m` | ✅ | 1.8 > 0.35 + 1.0 = 1.35 (marge 0.45 m). Borne basse tuning 1.4 → marge 0.05 m (fragile — documenter). |
| **2. Reach > 0** (r1 nouveau, systems-designer F2) | `KATANA_REACH > 0.0` | ✅ | Assert `_ready()`. Sinon hitbox centree sur joueur → self-overlap non sense. |
| **2.5. Swing duration > 0** (r2 nouveau, systems-designer #5 resolu) | `SWING_DURATION_MS > 0.0` | ✅ | Assert `_ready()`. Sinon `ACTIVE_TICKS = 0` (Formula 4) → window silencieusement cassee, aucun sweep, aucun kill possible. Parite avec Formula 5 `ATTACK_COOLDOWN_MS > 0`. |
| **3. Cooldown > Swing** | `ATTACK_COOLDOWN_MS >= SWING_DURATION_MS + 1 frame (16.6 ms)` | ✅ | 400 >= 120 + 16.6 = 136.6 (marge 263.4 ms) |
| **4. Combine Cooldown > Swing + SlowMo** (r1 nouveau, r4 S-F-09 assert runtime sur somme) | `ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS` | ✅ | 400 > 120 + 50 = 170 (marge 230 ms, coherent r1 slow-mo raccourci). Empeche qu'un nouveau swing demarre pendant slow-mo active. **r4 S-F-09 RESOLU** : les safe ranges individuelles (SWING ∈ [80,200], SLOW_MO ∈ [30,150], COOLDOWN ∈ [300,600]) permettent la combinaison `SWING=200 + SLOW_MO=150 + COOLDOWN=300 = 350 > 300` qui **viole silencieusement** l'invariant. Fix : `assert(ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS, "Invariant #4 violated: COOLDOWN must exceed SWING + SLOW_MO sum")` au `_ready()`. AC-CMB-36 etendu pour verifier la somme en plus des ranges individuelles. Contrat de tuning : modifier un de ces 3 knobs exige re-verification de la somme. |
| **5. Subdivision efficace** (r1 corrigee vers V_max) | `V_max × delta / N_SUBSTEPS < 2 × r_enemy_min` | ✅ | 30 × 0.01666 / 3 = 0.167 < 0.7 (r1 utilise V_max=30 m/s au lieu de TUNNELING_THRESHOLD=25 car N_SUBSTEPS est constant a 3 — voir Rule 7 r1). |
| **6. Slow-mo < cooldown / 2** (r4 tighten) | `SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2` | ✅ | 50 < 200 (le joueur recupere controle normal bien avant de re-swing). r1 valeurs actualisees. **r4 tighten** : combinaison `SLOW_MO=150 + COOLDOWN=300` donne `150 < 150` FAUX (egalite). Invariant #6 necessite inegalite stricte. Assert runtime ajoute : `assert(SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2.0, "Invariant #6 violated")` au `_ready()`. AC-CMB-36 etendu. |
| **7. Buffer < Cooldown / 5** (r1 D1 + r2 M2 invariant **assert fort** au `_ready()`) | `ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5` | ✅ | 80 <= 400/5 = 80 (limite exacte défaut — preserve precision speedrun). **r2 M2 safe range BUFFER = `[0, COOLDOWN/5]` dynamique** (cf. Section G). `assert(ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5.0)` au `_ready()` de CombatSystem rejete toute config violante. AC-CMB-36 vérifie dynamiquement. |
| **8. Dash asymetrique swing** (r1 re-etiquete, pas un bug) | `DASH_DURATION` et `SWING_DURATION_MS` relations libres | 📝 documente | DASH_DURATION=100 ms et SWING_DURATION_MS=120 ms sont independamment tunables. Un swing demarre pendant un dash peut finir Airborne — **comportement attendu couvert par Rule 8** (swing autorise tous states sauf Dead, orientation = aim_forward chaque tick). r1 clarification : ce n'est **pas** un invariant a violer/respecter, c'est une **relation documentee** entre deux systemes. AC-CMB-18 reclasse Integration. |
| **9. Duty cycle staccato** (r6 D-r4-2 — Martin tranché) | `SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4` | ✅ | 120 / (120 + 400) = 120 / 520 = **0.23 < 0.4** (marge confortable 0.17). Protège la Fantasy staccato contre tuning dérive : au-delà de 40% de duty cycle, le swing occupe trop la ligne temporelle et le "silence entre deux notes" disparaît (kill devient continu, pas staccato). Safe ranges individuelles permettent `SWING=200 + COOLDOWN=300` → 200/500 = 0.4 (limite exacte). **Assert runtime debug** : `assert(SWING_DURATION_MS / float(SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4, "Invariant #9 violated: duty cycle ≥ 0.4 — staccato Fantasy dégradée")` ajouté dans `_validate_invariants()` (DEC-r5-2). AC-CMB-17 r6 étendu pour vérifier invariant #9 en plus de #1-7. |

## Edge Cases

### Cas de transition d'état Movement pendant swing

- **Si un swing démarre en Grounded et que le joueur devient Airborne pendant la window active** (ex : swing + saut au tick 2 de la window) : le sweep continue normalement jusqu'au tick `ACTIVE_TICKS`. L'orientation reste `aim_forward`, la capsule se repositionne chaque tick en fonction de `player.global_position`. Rationale : Rule 8 autorise swing dans tous les states sauf Dead.

- **Si un swing démarre en Airborne et que le joueur atterrit pendant la window active** : identique — sweep continue, capsule repositionnée au tick courant. Aucune interruption.

- **Si un swing démarre en Grounded et que le joueur entre en Dashing au tick 2 de la window** : sweep continue, vélocité inter-tick augmente → subdivision anti-tunneling toujours active (N_SUBSTEPS = 3 constante r2, pas de condition dynamique — TUNNELING_THRESHOLD DEPRECATED cf. Rule 7). L'orientation reste `aim_forward` (pas `dash_dir` — Rule 5). AC-CMB-50 r4 couvre cette transition mid-swing.

- **Si un swing démarre en Dashing et que le dash finit pendant la window** : `DASH_DURATION = 100 ms` (Movement) vs `SWING_DURATION = 120 ms` → **le swing survit au dash** (flag invariant Section D.8). Tick 6-7 de la window, le joueur est Airborne avec `exit_momentum`. Rule 8 couvre — swing normal.

- **Si un swing démarre en Airborne et qu'un wall-run commence au tick 3** : sweep continue, orientation `aim_forward` inchangée (Rule 5). Le tilt camera (`camera_effects.rotation.z`) n'affecte **pas** la direction du katana puisque `aim_forward` est roll-corrigé.

### Cas mort/respawn

- **Si `Player.died()` est émis pendant `Swinging`** (r4 G-02 split sous-cas pour coherence Rule 17 Hybrid) : **deux sous-cas distincts** :
  - **Sous-cas (a) — aucun collider Enemy dans le sweep du tick courant** (`_collect_swing_hits().is_empty()`) : Handler SYNC set `_death_pending = true`. Combat `_physics_process` execute son sweep normalement (resultat vide), puis en fin de tick consomme `_death_pending` → transition `Dead`. Aucun `enemy_killed` emis (pas de collider a resoudre), `swing_ended` **non** emis (swing interrompu), `_active_tick` gele, `_hit_this_swing` conserve mais inutile. Couvert par AC-CMB-20.
  - **Sous-cas (b) — colliders Enemy dans le sweep du tick courant** (mutual kill tick-meme) : Rule 17 Hybrid s'applique — Combat **resolut les colliders et emet `enemy_killed` normalement selon Rule 9 multi-hit** avant de consommer `_death_pending` en fin de tick. Les deux meurent (Fantasy one-shot mutuel preservee). `swing_ended` **non** emis (swing interrompu par Dead). Couvert par AC-CMB-41.

  La distinction est faite par Rule 17 `_death_pending` mechanism — l'Edge Case n'est plus ambigu. Rationale : la mort annule la continuation du swing mais pas la resolution du tick en cours si des kills y sont legitimes.

- **Si `Player.respawned(position)` est reçu** (r4 P-05 + P-06 reset complet) : reset atomique de **tout** l'etat Combat : `_state = Idle`, `_active_tick = 0`, `_hit_this_swing.clear()`, `_cooldown_timer = 0.0` (réinitialisation), `_slow_mo_active = false`, `_slow_mo_start_msec = 0`, `Engine.time_scale = 1.0` (force restore au cas où la mort était intervenue pendant slow-mo active), **`_death_pending = false`** (r4 P-05 — sinon joueur bloque Dead au premier tick post-respawn via consommation orpheline), **`_buffered_attack = false`** (r4 P-06 — sinon clic anterieur a la mort declenche un swing involontaire au respawn), `ShapeCast3D.enabled = false`. AC-CMB-11 r4 etendu verifie les 8 assertions (state, active_tick, hits, cooldown, slow_mo_active, slow_mo_start_msec, death_pending, buffered_attack).

- **Si `Player.died()` est émis pendant la fenêtre slow-mo active (`_slow_mo_active == true`)** : `Engine.time_scale = 1.0` est restauré immédiatement (avant toute autre action), puis transition Dead. Rationale (r2 valeurs D3) : éviter que le respawn 50 ms (Movement `RESPAWN_DELAY`) soit lui-même ralenti à `SLOW_MO_SCALE = 0.3` → le joueur attendrait `50 / 0.3 ≈ 167 ms` réels avant de revenir — violation Pillar 3 "seconde chance < 2s" (ratio reste problématique même à 0.3).

- **Si `Player.died()` est émis exactement au tick où un `enemy_killed` serait traité (mutual kill tick-meme)** : **r1 decision Martin D2 — les deux meurent** (Rule 17). Movement execute d'abord (parent avant enfant `_physics_process`), emet `died` signal. Combat `_physics_process` (execute ensuite) **termine le tick swing en cours** (resolve les colliders retournes par le ShapeCast, emet `enemy_killed` signals normalement selon Rule 9 multi-hit) AVANT de transiter vers Dead. Sequencement garanti par Rule 17. Credit Economy recoit les kills du tick. Respawn 50 ms (Pillar 3). Le swing_ended **n'est pas** emis (swing interrompu par transition Dead). Rationale : symetrie stricte one-shot + Fantasy "kill = consequence du bon placement" preserves. **Difference avec draft initial** : le draft disait "ennemi gagne" (non-resolu), r1 corrige cette asymetrie anti-Fantasy.

### Cas d'input

- **Si deux signals `Player.attacked()` arrivent au même tick** (improbable mais possible si ADR-0005 D-2 future amendment autorise multi-emit) : Combat traite le **premier**, ignore les suivants du tick (la garde `_cooldown_timer > 0` après entrée en Swinging absorbe automatiquement les émissions suivantes). Rationale : défensif sans coût.

- **Si `Player.attacked()` est reçu exactement au tick où `_cooldown_timer` atteint 0.0** : la garde `_cooldown_timer <= 0.0` (comparaison inclusive) accepte le swing au tick courant. Pas de délai d'un tick supplémentaire. Rationale : feel responsif (Pillar 1) — chaque tick de latence ajouté est perceptible.

- **Si `Player.attacked()` est reçu à tick N-1 juste avant un `died()` à tick N** : tick N-1 → Combat entre en Swinging, tick N → `died()` → transition Dead avec interruption du swing (cas "mort pendant Swinging" ci-dessus). Le swing naissant est annulé.

### Cas de hitbox / collision

- **Si un ennemi est spawné CHEVAUCHANT déjà le sweep au tick d'entrée** (ex : swing démarre avec ennemi à 0.5 m dans le volume capsule) : `ShapeCast3D` avec `target_position = delta` peut **ne pas détecter** un collider déjà en overlap à `origin` (comportement Godot : ShapeCast détecte les colliders ENTRÉS pendant le sweep). **Mitigation MVP** : au premier tick de la window, précéder le cast d'un `space_state.intersect_shape()` statique à `origin` pour capturer les colliders déjà à l'intérieur. À vérifier en implémentation — si Godot 4.6 ShapeCast3D détecte bien les overlaps d'origine, cette mitigation est redondante (cf. engine-reference/godot/modules/physics.md).

- **Si deux ennemis sont à exactement la même distance du joueur** (à la précision float près) : le tri `sort_ascending` de GDScript est stable — leur ordre relatif préserve l'ordre de `get_collider(idx)` du ShapeCast. Déterminisme run-to-run dépendant de Jolt (ADR-0001). Pour un speedrun leaderboard strict, imposer un tri secondaire par `instance_id` (garanti monotonique Godot).

- **Si un collider intersecté est un `CharacterBody3D` mais n'a pas la méthode `die()`** (ex : body générique layer=Enemy mal configuré) : skip silencieux avec `push_warning` en debug build (`collider "%s" layer Enemy mais pas has_method('die')"`), aucun crash, pas de re-tentative. Rationale : le bug est en config asset, pas en logic Combat.

- **Si un collider est à jour "dead" (`collider.is_dead() == true`)** : skip silencieux (sans warning). Rationale : normal pendant multi-hit — un ennemi tué tick N de la window est still dans la scène tick N+1 le temps du cleanup Enemy System.

- **Si le swing orientation `aim_forward` pointe exactement vers le sol** (joueur looking down, pitch = -PITCH_LIMIT) : la capsule balaie verticalement. `collision_mask = Enemy only` (Rule 12) garantit que Environment n'est pas touché. Aucun kill déclenché si aucun ennemi n'est sous les pieds. Comportement attendu et cohérent.

### Cas slow-mo / time_scale

- **Si `Engine.time_scale != 1.0` au moment du premier `enemy_killed`** (ex : debug pause manuel `time_scale = 0.5`) : Combat écrase avec `SLOW_MO_SCALE = 0.3` (r1 valeur Martin D3), puis restore à `1.0` après `SLOW_MO_DURATION_MS = 50 ms` wall-clock — **pas** à `0.5`. Rationale : Combat ne sait pas pourquoi time_scale était à 0.5 ; restaurer à 1.0 est le comportement prévisible (le debug pause doit relancer son propre override si besoin).

- **Si deux `enemy_killed` du même swing arrivent au même tick** : `multi_kill(2)` est émis après les 2 `enemy_killed`. **Une seule slow-mo** déclenchée (au premier `enemy_killed`). `_slow_mo_active = true` empêche re-entrée. Rationale : éviter compound `time_scale` ou reset window.

- **Si un deuxième swing démarre pendant une slow-mo active** : géré par `ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS` (invariant Section D.8 : 400 > 120 + 50 = 170 ✅, r1 valeurs Martin D3). Le cooldown couvre la slow-mo — impossible de re-swing pendant la fenêtre.

### Cas cross-system non-nominaux

- **Si `CameraSystem.aim_forward` retourne un vecteur invalide** (NaN, Vector3.ZERO — par ex. si Camera n'est pas prête `_ready`) : garde `if not aim_forward.is_finite() or aim_forward.is_zero_approx(): return` au début de `_physics_process` swing. Skip tick, émet `push_error` en debug. Rationale : défensif — un bug Camera ne doit pas crasher Combat ni swinger dans une direction non définie.

- **Si Movement émet `attacked()` en mode `_process` au lieu de `_physics_process`** (violation ADR-0005 D-4) : Combat reçoit le signal hors-physics, ne peut pas sweeper car `ShapeCast3D.force_shapecast_update()` DOIT être en `_physics_process`. Garde d'assertion en debug : `assert(Engine.is_in_physics_frame(), "attacked() received outside _physics_process — ADR-0005 D-4 violation")`. En release, skip silencieux. Rationale : détecter régressions ADR-0005 tôt.

- **Si `Player.state` retourne `Dead` mais Combat n'a pas reçu `died()` signal** (race condition théorique) : la garde `_state != Dead` dans la condition de transition vers Swinging lit `Combat._state`, pas `Player.state`. Elles peuvent diverger temporairement (1 tick) pendant la propagation du signal `died`. Conséquence : un swing peut démarrer sur un tick où Movement est déjà Dead mais Combat encore Idle. **Mitigation** : en début de `_physics_process`, si `player.state == Dead and _state != Dead`, forcer transition vers Dead immédiate avant toute autre logique. Rationale : cohérence rapide entre state Movement et Combat sans attendre le signal deferred.

- **Si le joueur spam-click alors que `InputManager.enabled == false`** (pause ouverte) : Movement n'émet pas `attacked()` (per ADR-0004 D-4 — signals gameplay coupés quand disabled). Combat reçoit 0 trigger. À la ré-activation, le premier click **post-pause** déclenche un swing normal (pas de buffered input depuis avant la pause).

## Dependencies

### Upstream (Combat dépend de) — systèmes DESIGNED

| Système | Type | Nature (hard/soft) | Interface consommée | Vérification bidirectionnelle |
|---|---|---|---|---|
| **Player Movement System** | Hard | **Hard** — Combat ne peut fonctionner sans. | Signal `Player.attacked()` (ADR-0005 D-2, signal de déclenchement). Signal `Player.died()` (transition Dead). Signal `Player.respawned(position)` (reset à Idle). Read-only properties : `player.global_position`, `player.velocity`, `player.state`. **r1 correction BLOCKING #5** : `player.transform` retire de la liste (contredisait Rule 5 qui interdit `transform.basis.z`). Combat cache `_prev_position` lui-meme (Rule 6 ownership). | ✅ Movement GDD Interactions table liste "Player Combat (aval, consomme velocity)". Cohérent. |
| **Camera System** | Hard | **Hard** — Combat ne peut orienter le sweep sans. | Read-only : `CameraSystem.aim_forward: Vector3` (forme close roll-corrigée, ADR-0002 + Camera GDD Rule 13). | ✅ Camera GDD Interactions table liste "Player Combat (aval, forward vector pour katana)". Cohérent. |
| **Input System** (transitif, via Movement) | Soft | **Soft** — pas de contact direct. | Combat ne consomme **jamais** `InputManager.*`. L'action `attack` est médiatisée entièrement par Movement. Pas d'import, pas de dépendance directe. | ✅ Input GDD Interactions table **ne liste pas Combat** comme consommateur direct — cohérent avec le couplage transitif. |

### Upstream (Combat dépend de) — systèmes NOT STARTED (contrats définis par Combat ici)

| Système | Type | Nature | Interface attendue | Action requise quand ce système sera designé |
|---|---|---|---|---|
| **Checkpoint & Respawn System** | Soft | Indirect | Combat ne contacte pas Checkpoint directement. Checkpoint est consommé par Movement, qui notifie Combat via `died()` / `respawned()`. | Le futur GDD Checkpoint doit référencer Movement pour le lifecycle, pas Combat. **Combat absent des Dependencies Checkpoint**. |

### Downstream (systèmes qui dépendent de Combat) — à figer ici en contract one-way

| Système | Type | Interface qu'ils consommeront | Contrat côté consommateur |
|---|---|---|---|
| **Enemy System** (Not Started, MVP) | Hard (critique) | Combat appellera `enemy.die()` sur chaque collider Enemy retourné par le sweep. Combat émettra `enemy_killed(enemy: Node, position: Vector3)` pour cleanup. | **Enemy GDD DOIT** : (1) implémenter `die()` idempotent (early return si already Dead, pattern Movement godot-specialist F6) ; (2) exposer une méthode `is_dead() -> bool` ; (3) avoir au moins un `CollisionShape3D` layer=2 (Enemy) ; (4) respecter `r_enemy_min = 0.35 m` (rayon capsule minimum — invariant Section D.3 anti-tunneling). |
| **Credit Economy** (Not Started, MVP) | Soft | Connectera `enemy_killed(enemy, position)` pour incrémenter les crédits. | **Credit Economy GDD DOIT** : (1) déterminer la valeur crédit par type d'ennemi (contract Credit ↔ Enemy, pas Combat) ; (2) consommer `enemy_killed` sans muter `enemy` (read-only). |
| **VFX & Feedback System** (Not Started, MVP) | Soft | Connectera `swing_started(direction)`, `swing_ended()`, `enemy_killed(enemy, position)`, `multi_kill(count)`. | **VFX GDD DOIT** : (1) connecter en `CONNECT_DEFERRED` pour consommateurs lourds (GPUParticles, décalques sang, post-process flash) ; (2) ne jamais muter `enemy` ou `player` via les handlers ; (3) spawner le trail katana pendant `swing_started` → `swing_ended` window ; (4) gérer le flash blanc 50 ms + splash sang au `enemy_killed` (art-bible État 2). |
| **Audio System** (Not Started, MVP) | Soft | Connectera les mêmes signals que VFX + `multi_kill`. | **Audio GDD DOIT** : (1) connecter en `CONNECT_DEFERRED` ; (2) ne pas pitcher le son sous `Engine.time_scale` (AudioStreamPlayer default OK) ; (3) prévoir layer audio optionnel pour `multi_kill` (chord cyberpunk) — MVP sans, Tier 2+. |
| **HUD System** (Not Started, MVP) | Soft (optionnel MVP) | Lecture de `CombatSystem.cooldown_ratio: float` (0.0 prêt → 1.0 just fired). Potentiel usage `is_swinging` et `debug_hits_last_swing` en F3 debug. | **HUD GDD DOIT** : (1) lire via getter read-only (jamais tenter d'écrire `_cooldown_timer`) ; (2) accepter que MVP n'affiche pas le cooldown visuellement (feel "no UI" art-bible). |
| **Upgrade System** (Not Started, MVP) | Future | Pas d'interface Combat ↔ Upgrade au MVP. | **Upgrade GDD N'A PAS BESOIN** de référencer Combat au MVP (Combat est statique). Tier 2+ : hooks capability pour slash-through-environment, finisher, etc. — ADR à créer si introduit. |
| **Boss System** (Full Vision, Tier 3) | Hard future | Boss sera un collider Enemy avec `die()` qui ne tue pas au premier hit — **exception unique à one-shot**. | **Boss GDD DOIT** : (1) implémenter un `die()` multi-hit (HP interne) qui ne propage pas `enemy_killed` tant que HP > 0 ; (2) ne pas rompre le contrat `has_method("die")` du Combat. Combat traite Boss comme n'importe quel ennemi — la logique HP est interne Boss. |

### Dépendances ADR (contraintes d'implémentation)

| ADR | Statut | Contrainte sur Combat |
|---|---|---|
| **ADR-0001 Physics Rate 60 Hz + Jolt** | Accepted | Sweep obligatoirement en `_physics_process`. Respect `default_gravity = 0` Jolt (pas de calcul gravité Combat). Jolt ShapeCast3D via `margin` — valider en impl (collision margin Jolt ≠ GodotPhysics3D). |
| **ADR-0002 Camera Scene Tree 3-tier** | Accepted | Combat lit `CameraSystem.aim_forward` (forme close trigonométrique owned Camera Rule 13) — **interdit** `camera3d.basis.z` brut. |
| **ADR-0004 Input API & Focus Handling** | Accepted | Combat ne poll JAMAIS `InputManager.*`. Médié via signal Movement `attacked()`. Cohérent `was_pressed_this_tick` API canonique. |
| **ADR-0005 Movement Signals Architecture** | Accepted | Respect consumer contract D-7 (handlers ne mutent pas Movement state) + D-4 (emit from `_physics_process` only, garde en edge case). |
| **ADR à créer : Combat Hitbox Sweep** | N/A | **Possible gap** — si Combat introduit des décisions cross-system sur collision layers taxonomie (Layer 1-5), un ADR dédié pourrait être utile. À décider par `/architecture-review` post-GDD. Actuellement, les layers sont GDD-owned (Rule 12) — pas encore registry-enregistrés. |
| **ADR à créer : Slow-mo Time Dilation** | N/A | **Possible gap** — `Engine.time_scale` impacte tous les systèmes. Un ADR dédié clarifiera l'ownership (Combat possesseur exclusif du MVP, Boss possesseur potentiel Tier 3, futurs systèmes de cinématique post-MVP pourraient le contester). |

### Exclusions explicites (pas de dépendance)

- **Combat ne dépend pas du Save/Load System** — aucun état Combat n'est persisté (les swings sont transients, pas de progression Combat MVP).
- **Combat ne dépend pas du Level System** — les hitboxes sont pur-logic, aucune géométrie niveau consommée.
- **Combat ne dépend pas du Menu System** — pas de menu Combat (pas de rebinding Combat, pas de difficulté Combat).
- **Combat ne dépend pas de l'Audio System** en tant que dépendance — Audio est un consommateur downstream.

### Dépendances circulaires

Aucune détectée. Combat est un nœud terminal aval de Movement/Camera/Input et source pour Enemy/Credit/VFX/Audio/HUD/Boss/Upgrade.

## Tuning Knobs

Tous les knobs Combat vivent dans un `Resource` `combat_config.tres` (à créer en implémentation). Data-driven — aucune valeur hardcodée dans le code Combat. Les knobs sont chargés à `_ready()` de `CombatSystem` depuis `preload("res://assets/data/combat_config.tres")`.

### Knobs de géométrie hitbox

| Knob | Default | Safe range | Unité | Effet gameplay | Interactions / garde-fous |
|---|---|---|---|---|---|
| `KATANA_REACH` | **1.8** | 1.4 – 2.2 | m | Longueur utile de la capsule hitbox. Valeur haute = plus de lecture à distance (casse Fantasy "traverser"). Valeur basse = proximité extrême requise (frustration). | < 1.4 : sub-capsule player, impossible à connecter. > 2.2 : "aim assist" implicite (viole Pillar 1). Interaction : doit rester > `capsule_radius + 1.0 m` (invariant Section D.8). |
| `KATANA_RADIUS` | **0.45** | 0.30 – 0.60 | m | Rayon de la capsule hitbox. Valeur haute = wider sweep (faux-positifs latéraux, casse skill ceiling). Valeur basse = forme plus linéaire (misses légitimes). | < 0.30 : sweep en ligne quasi-raycast, tunneling partiel sur ennemis étroits. > 0.60 : Box-like coverage, viole Fantasy "la lame a un axe". |

### Knobs de timing

| Knob | Default | Safe range | Unité | Effet gameplay | Interactions / garde-fous |
|---|---|---|---|---|---|
| `SWING_DURATION_MS` | **120** | 80 – 200 | ms | Fenêtre active hitbox. Valeur haute = plus indulgent sur timing joueur. Valeur basse = staccato pur, exige précision. | < 80 : window < 5 ticks → misses reliés à la latence input-display (~33 ms = 2 frames). > 200 : encourage "hold-swing then move", casse rythme staccato. **Interaction critique** : `SWING_DURATION_MS + SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS` (invariant 4 Section D.8). |
| `ATTACK_COOLDOWN_MS` | **400** | 300 – 600 | ms | Délai entre fin de swing N et début swing N+1. Valeur haute = cooldown visible, frustrant. Valeur basse = spam possible. | < 300 : > 3.3 swings/s → animation indiscernable, impression "mitraillette". > 600 : casse feel staccato ("trop lent"). **Doit etre > 0** (invariant 2 r1, garde Formula 5). |
| `ATTACK_BUFFER_MS` (r1 D1 + r2 M2 safe range dynamique) | **80** | **0 – `ATTACK_COOLDOWN_MS / 5` (dynamique)** | ms | Fenetre de buffering des clics `attack` dans les dernieres ms du cooldown. 0 = pas de buffer (anti-Fantasy). 80 = buffer sweet-spot (Hades/Ghostrunner reference). | **Safe range borne haute = `ATTACK_COOLDOWN_MS / 5` dynamique (r2 M2 resserre)** — à COOLDOWN=300 ms, borne = 60 ms ; à COOLDOWN=400 ms, borne = 80 ms (défaut, limite exacte) ; à COOLDOWN=600 ms, borne = 120 ms. < 30 : buffer imperceptible. **Garde-fou speedrun** : invariant 7 `<= ATTACK_COOLDOWN_MS / 5` (Section D.8) — rejete par `_ready()` assert si viole. Contrat tuning r2 : modifier COOLDOWN exige re-verification BUFFER. |
| `MAX_KILLS_PER_SWING` | **3** | 1 – 10 | kills | Plafond multi-hit par swing. Valeur haute = fantaisie "un coup vide la salle". Valeur basse = prudence tactique. | 1 : reduit multi-kill a single target (feel pauvre en densite d'ennemis). > 5 : degenerate "swing pendant groupe = free kill". **Rationale r1 (correction game-designer)** : 3 est une **hypothese pre-playtest** (pas un "sweet spot playtest" comme disait le draft initial — aucun playtest n'a eu lieu). Hypothese : densite MVP cible 2-3 ennemis par zone → 3 max permet clear de zone en un swing **possible** mais **pas systematique**. A valider playtest + reajuster si degenerate. |

### Knobs d'anti-tunneling (techniques, peu exposés gameplay)

| Knob | Default | Safe range | Unité | Effet | Interactions |
|---|---|---|---|---|---|
| `TUNNELING_THRESHOLD` (r2 **DEPRECATED**) | **25.0** | 20.0 – 35.0 | m/s | **DEPRECATED par Rule 7 r1 CD verdict** — N_SUBSTEPS est désormais constant à 3, ce knob n'est plus consommé par Formula 3 / Rule 7. Conservé en config `combat_config.tres` uniquement pour compatibilité future si un mode low-V sans subdivision est réintroduit. **Toute lecture de ce knob depuis le code Combat r2 est un bug de code review à rejeter.** | — |
| `N_SUBSTEPS` (r2 **constant**) | **3** | 2 – 5 | count | Nombre de sous-casts **constants** par tick actif (r2, plus de condition dynamique). Valeur haute = anti-tunneling renforcé mais N× CPU par tick rapide. | Doit garantir `gap_max = V × delta / N < 2 × r_enemy_min = 0.7 m` (invariant Section D.3). À 5, couvre V jusqu'à 70 m/s théorique. À 3 couvre V jusqu'à 126 m/s (marge 4x sur V_max=30 m/s). |

### Knobs de slow-mo kill

| Knob | Default | Safe range | Unité | Effet gameplay | Interactions |
|---|---|---|---|---|---|
| `SLOW_MO_SCALE` (r1 retune D3) | **0.3** | 0.10 – 0.50 | ratio | `Engine.time_scale` pendant la fenêtre. r1 change de 0.15 → 0.3 (micro-pause, pas climax). Valeur basse = pause quasi-totale (climax Shadow Warrior 3 style — anti-Fantasy). Valeur haute = ralenti subtil (mesure fluide). | < 0.10 : perçu comme "pause dramatique" (breaks Pillar 1 FLOW + Fantasy "silence entre deux notes"). > 0.50 : effet imperceptible. r1 range elargi a 0.50 pour permettre retune fluide en playtest. |
| `SLOW_MO_DURATION_MS` (r1 retune D3) | **50** | 30 – 150 | ms | Durée wall-clock de la fenêtre slow-mo. r1 change de 100 → 50 ms. A time_scale=0.3, 50 ms wall-clock = **167 ms percus** a l'ecran = micro-pause rythmique. | **Invariants critiques** : `< ATTACK_COOLDOWN_MS / 2` (invariant 6 Section D.8) + `SWING + SLOW_MO < ATTACK_COOLDOWN` (invariant 4 r1). < 30 : imperceptible. > 150 : percu 500 ms = redevient climax → casse staccato. Safe range r1 reduit pour garder la Fantasy. |
| `MAX_DECALS_PER_ROOM` (r1 nouveau Rule 18) | **12** | 4 – 32 | count | Plafond de decals sang actifs simultanement dans la salle courante. Pool LRU recycle le plus ancien au-dela. | < 4 : recyclage trop frequent visible (le sang des premiers kills disparait avant fin de salle). > 32 : degradation Forward+ sur hardware entry-level (Godot 4.6 pipeline non-lineaire au-dela ~32 decals). |

### Knobs de feel "feedback intensity" (Vertical Slice+, pas MVP)

| Knob | Default | Safe range | Unité | Effet | Notes |
|---|---|---|---|---|---|
| `TRAIL_INTENSITY` | 1.0 (MVP off) | 0.5 – 2.0 | multiplier | Intensité du trail VFX katana (opacity, largeur). | Owned par VFX System via signal `swing_started` — paramètre ici listé pour compatibilité contract futur. |
| `MULTI_KILL_AUDIO_LAYER` | false | bool | — | Active layer audio supplémentaire sur `multi_kill(count)`. | MVP off (Audio GDD Tier 2+ feature). |

### Knobs accessibility (cf. Section "Visual/Audio" + Camera System Rule 14 `reduce_motion`)

| Knob | Default | Range | Description |
|---|---|---|---|
| `reduce_motion_slow_mo_scale_mult` (r1 corrige logique inverse) | 1.0 | 1.0 – 3.33 | Si `reduce_motion` actif (Input System setting), **multiplie** `SLOW_MO_SCALE` vers une valeur plus proche de 1.0 (moins agressive). Ex : defaut `SLOW_MO_SCALE = 0.3`, `mult = 2.0` → `effective = 0.6` (ralenti moins prononce). Borne sup 3.33 = 0.3 × 3.33 = 1.0 (aucune slow-mo). `mult = 1.0` (defaut) = aucun impact. **r1 correction game-designer POLISH-3** : le draft initial proposait `mult = 0.5` ce qui produisait `0.3 × 0.5 = 0.15` (slow-mo PLUS agressive = contresens accessibility). La semantique correcte pour "reduce motion" est attenuer l'effet — `mult >= 1.0`. |
| `reduce_motion_disable_slow_mo` (r1 nouveau, option nette) | false | bool | Si true ET `reduce_motion = true` : desactive completement la slow-mo au kill. Plus lisible semantiquement que scale_mult pour l'accessibilite severe (photosensibilite, vertige). Recommande over `scale_mult` pour le toggle public Settings. |
| `reduce_motion_flash_mult` | 1.0 | 0.0 – 1.0 | Multiplier alpha du flash blanc kill (50 ms default). Owned par VFX System, Combat ne fait qu'émettre le signal — listé ici pour traçabilité accessibility cross-system. |

### Contrat de tuning (règles pour le designer)

1. **Ne jamais modifier un knob sans vérifier les invariants Section D.8**. Un changement `ATTACK_COOLDOWN_MS` nécessite de re-vérifier la relation avec `SWING_DURATION_MS + SLOW_MO_DURATION_MS`.
2. **Les ranges safe sont validées par simulation mathématique** (Section D formules). Une valeur hors-range peut fonctionner en runtime mais viole un invariant → bug attendu.
3. **Les valeurs par défaut sont calibrées pré-playtest**. Elles seront revisitées après le premier playtest MVP du système Combat — un review log playtest sera à maintenir dans `design/gdd/reviews/player-combat-system-playtest-log.md`.
4. **Les knobs techniques (`TUNNELING_THRESHOLD`, `N_SUBSTEPS`) ne sont pas exposés dans le menu Settings**. Ils restent dans `combat_config.tres` éditable par designer uniquement.
5. **`MAX_KILLS_PER_SWING` est un knob de design, pas d'accessibility**. Ne PAS le faire varier selon difficulté — ce serait un changement de règle de base, pas de tuning.

## Visual/Audio Requirements

### VFX 1 — Trail de lame (swing actif)

**Déclencheur** : début de l'état `Swinging` → fin de l'état `Swinging` (120 ms, 8 ticks).

**Technique** : `Line3D` avec `GradientTexture1D` appliqué sur l'alpha. Pas de `GPUParticles3D` (overhead inutile pour un trait géométrique de durée fixe). Pas de `MeshInstance3D` custom — la géométrie est triviale et Line3D est natif Godot.

**Ancrage spatial** : l'origine du trail est fixe à `player.global_position + Vector3(0, 1.0, 0) + aim_forward × (KATANA_REACH / 2)` — point médian de la lame virtuelle, à hauteur caméra. Le trail ne suit pas la caméra frame-by-frame (évite le smear motion nauséeux) : il est positionné une fois à l'entrée du swing et reste world-space pendant les 8 ticks.

**Couleur et opacity curve** :
- Couleur : `#FFFFFF` (blanc pur — blanc = trajectoire principale, art-bible Section 1 Principe 1). Zéro saturation, zéro glow, zéro teinte. Si le shader ajoute du bloom sur ce blanc, le technical-artist DOIT limiter l'energy à ≤ 1.0 pour rester dans la gamut Chrome Zen.
- Curve d'opacity sur 120 ms :

| Phase | Range | Alpha | Courbe |
|---|---|---|---|
| Appear | 0–20 ms (ticks 1-2) | 0.0 → 1.0 | Linear in |
| Sustain | 20–100 ms (ticks 2-7) | 1.0 | Flat |
| Fade | 100–120 ms (ticks 7-8) | 1.0 → 0.0 | Linear out |

**Cohérence Chrome Zen** : pas de particules secondaires, pas de distorsion UV, pas de pulsation. Si le trail est visible dans un plan contenant déjà un ennemi rouge ou un élément cyan — la présence du blanc pur peut coexister temporairement (le blanc est la trajectoire *du joueur* et est par définition en mouvement) mais ne doit jamais persister statiquement. Le fade-out sur 20 ms assure l'absence d'artefact après le swing.

**Fallback contre fond blanc Chrome Zen (r1 game-designer RECOMMENDED-3)** : si le trail blanc `#FFFFFF` risque l'invisibilite sur les murs Chrome Zen blancs/chromes, le shader ajoute un **outline gris fonce `#1A1A2E` de 1 px** autour du trail pour preserver la lisibilite. Outline actif **uniquement** si le pixel behind est > luminance 0.7 (detection locale via DepthTexture ou simplement toujours-on pour le MVP si detection complexe). Ce fallback est dans le GDD (pas juste Open Question) — le trail reste lisible par design, pas par chance.

**Asset requis** : `vfx_katana_trail_loop_small.tres` (material Line3D + gradient alpha + outline shader fin).

---

### VFX 2 — Kill feedback (3 éléments simultanés sur `enemy_killed`)

Les trois éléments ci-dessous sont déclenchés **au premier `enemy_killed` du swing**, synchronisés sur le même frame.

#### 2a. Flash blanc (50 ms) — connexion SYNC (r1 Martin D4)

**Technique** : `ColorRect` fullscreen en `CanvasLayer` (layer 127, au-dessus de tout UI). Couleur fixe `#F0F4FF` (blanc cassé légèrement froid — pas blanc pur `#FFFFFF` pour éviter que le flash se confonde avec une surexposition moteur). Alpha curve :

| Phase | Range | Alpha |
|---|---|---|
| Instant on | frame 0 | 0.0 → 0.85 |
| Decay | 0–50 ms | 0.85 → 0.0 (linear) |

Le `ColorRect` est désactivé (`visible = false`) par défaut. À chaque `enemy_killed`, un `Tween` one-shot pilote l'alpha et rappelle `visible = false` à la fin. Pas de post-process, pas de shader screen-space — le ColorRect est suffisant et ne dépend pas du pipeline de rendu Forward+.

**r1 decision Martin D4 — connexion SYNC (pas DEFERRED)** : la connexion VFX ↔ Combat pour le signal `enemy_killed` est en mode **direct/SYNC** uniquement pour ce consumer VFX flash. Rationale : le draft initial recommandait CONNECT_DEFERRED pour tous consumers (pattern general "deferred pour eviter re-entrance"), ce qui introduisait 16 ms de decalage visuel vs tick kill — viole Pillar 1 "FLOW AVANT TOUT" + "frame-precis avec flash blanc" (contract inter-systeme). Le ColorRect flash est une operation triviale (`visible = true` + `Tween.tween_property(alpha)`) — aucun risque de re-entrance, aucune allocation lourde, conforme a l'exemption ADR-0005 D-5. **Amendment ADR-0005 D-5 r1 pending** : documenter l'exemption sync pour signals frame-synchro (flash blanc etant le seul cas MVP). Les **autres** consumers du meme signal (GPUParticles sang, Decal, Audio) restent CONNECT_DEFERRED (operations lourdes).

**Note `reduce_motion`** : quand `reduce_motion = true`, l'alpha peak est multiplié par `reduce_motion_flash_mult = 0.5` → peak à **0.425**. À 0.425 alpha sur fond noir/gris, le flash reste détectable visuellement — AC-CMB-05 est préservé.

**Asset requis** : aucun asset externe. Le ColorRect est instancié par code dans `VFXLayer.gd`.

#### 2b. Splash de sang brut

**Cible artistique** : "seule tache warm de l'image, non esthétisée, brute" (art-bible Section 1 Principe 3 + État 2). Pas de sprite blood stylisé, pas de particule avec motion blur artistique — des gouttes balistiques réalistes sur surface.

**Technique (deux couches)** :
1. **Airborne particles** : `GPUParticles3D` émis depuis `enemy.global_position`, 12–16 particules (budget Chrome Zen : minimalisme), direction conique (60°) opposée à `aim_forward` (les gouttes partent vers l'arrière de l'impact). Lifetime : 0.4 s. Pas de rotation de particule, pas de softbody.
2. **Surface decal** : 1 `Decal` node posé sur le sol ou la wall la plus proche via raycast vertical depuis `enemy.global_position`. Texture : `vfx_blood_splash_decal_medium.png` (1 seul variant MVP — avec 1 seul ennemi en MVP, la répétition n'est pas encore perceptible). Durée : permanente dans la salle courante (cleared au respawn player + au changement de niveau). Pas de fade — le sang reste. C'est intentionnel : la trace physique confirme le passage du joueur.

**Couleur exacte** : `#C01A1A` (rouge 2 200 K-visuel — saturé, chaud, pas brillant). Aucun metallic, aucun emissive sur le material sang. Fond Chrome Zen froid = contraste thermique maximal garanti (art-bible État 2 : "contraste thermique maximal dans l'espace visuel le plus bref possible").

**Assets requis** :
- `vfx_blood_splash_particles_small.tres` (GPUParticles3D resource, material couleur #C01A1A, unlit)
- `vfx_blood_splash_decal_medium.png` (512×512, rouge sur alpha, 1 variant)

#### 2c. Slow-mo visuel (50 ms wall-clock)

**Mécanique (r2 aligne Rule 13 + Formula 7)** : `Engine.time_scale = SLOW_MO_SCALE = 0.3` pendant `SLOW_MO_DURATION_MS = 50 ms` wall-clock (spec Core Rules Rule 13, valeurs Martin D3). Le moteur ralentit — animations, vélocités, sons (hors audio Godot qui reste wall-clock, cf. Rule 13) — sans traitement visuel additionnel. **Perception écran** : 50 ms wall-clock × (1/0.3) ≈ 167 ms perçus par le joueur = 10 frames rendering @ 60 fps = micro-pause rythmique servant la Fantasy "silence entre deux notes".

**Décision Chrome Zen — aucun effet visuel ajouté** : pas de chromatic aberration, pas de micro-vignette, pas de désaturation. Le ralentissement perçu provient uniquement du time_scale. Justification : (1) Chrome Zen = aucun élément visuel "pour être beau" — un effet screen-space pendant 167 ms perçus n'est pas actionnable ; (2) le flash blanc et le splash sang déjà présents suffisent à marquer le beat ; (3) tout ajout risque de concurrencer le blanc/rouge en introduisant une troisième lecture (anti-pillar "une couleur par plan").

**Note `reduce_motion` (r2 aligne Section G logique corrigée)** : Section G ligne `reduce_motion_slow_mo_scale_mult` est un multiplicateur `>= 1.0` qui attenue l'effet (mult=1.0 par défaut → aucun impact, mult=2.0 → `0.3 × 2.0 = 0.6` = ralenti moins prononcé, mult=3.33 → `0.3 × 3.33 ≈ 1.0` = aucune slow-mo). L'option nette `reduce_motion_disable_slow_mo = true` desactive completement. La durée wall-clock 50 ms reste inchangée. Le visuel est identique — aucun ajustement nécessaire côté art.

---

### VFX 3 — Multi-kill (≥ 2 kills au même tick)

**Signal émis** : `multi_kill(count: int)` (Core Rule 9).

**Visual MVP** : somme additive des splashes de chaque kill — chaque `enemy_killed` déclenche indépendamment son splash 2b. Le flash 2a est joué **une seule fois** (sur le premier `enemy_killed`) pour ne pas saturer l'écran. Résultat naturel : plusieurs décals de sang au sol, plusieurs jets de particules, un seul flash blanc.

**Pas de visual marker additionnel MVP** : aucune augmentation de durée flash, aucun tint supplémentaire, aucun indicateur "DOUBLE KILL". Raison : ChromeZen "une couleur par plan" — ajouter un effet dédié introduirait une troisième lecture simultanée (blanc flash + rouge sang + X signal multi-kill). La quantité de sang au sol *est* le signal multi-kill.

**Infrastructure Tier 2** : le signal `multi_kill(count)` est émis et prêt. Un feedback audio ou visuel dédié peut être branché en Tier 2 sans modifier Combat System.

---

### Accessibility — `reduce_motion` récapitulatif

| Effet | Normal | `reduce_motion = true` (exemple) | Knob |
|---|---|---|---|
| Flash alpha peak | 0.85 | 0.425 | `reduce_motion_flash_mult = 0.5` |
| Slow-mo time_scale (r2 valeurs) | **0.3** | **0.6** (mult 2.0) ou **1.0** (disable) | `reduce_motion_slow_mo_scale_mult >= 1.0` OU `reduce_motion_disable_slow_mo = true` |
| Slow-mo durée wall-clock | 50 ms | 50 ms (inchangé) ou 0 ms si disable | — |
| Trail opacity | pleine curve | pleine curve (non affecté) | — |
| Splash sang | normal | normal (non affecté) | — |

Le flash à 0.425 alpha reste suffisant pour confirmer un kill (AC-CMB-05 ADVISORY). Si des playtests d'accessibilité indiquent que 0.425 est encore trop intense pour photosensibilité sévère, abaisser `reduce_motion_flash_mult` à 0.25 (peak 0.21) — le kill reste confirmé par le splash sang et le slow-mo perçu. Pour la photosensibilité sévère ou le vertige, `reduce_motion_disable_slow_mo = true` est recommandé over le tuning par mult (plus lisible sémantiquement).

---

### Assets visuels MVP — liste de livraison

| Asset | Technique | Priorité | Complexité |
|---|---|---|---|
| `vfx_katana_trail_loop_small.tres` | Line3D + GradientTexture1D | P1 | Low |
| `vfx_blood_splash_particles_small.tres` | GPUParticles3D resource | P1 | Low |
| `vfx_blood_splash_decal_medium.png` | Texture decal 512×512 | P1 | Low |
| Flash overlay | ColorRect instancié par code | P1 | Trivial (no asset) |

Aucun viewmodel katana au MVP (Core Rule 16). Aucun asset Tier 2 à produire avant playtest.

**Flag `/asset-spec`** : cette section contient des specs concrètes (technique, couleur hex, dimensions, durée, alpha curve) suffisantes pour que `/asset-spec system:player-combat-system` génère les prompts asset. Les ~4 assets visuels ci-dessus sont les cibles de Phase Asset Spec pour le combat system.

---

### Audio Requirements (high-level)

*Le design audio détaillé (waveform, mixing, spatialisation) est délégué au sound-designer via `/team-audio`. Cette sous-section liste les événements et contraintes que l'Audio System DOIT couvrir.*

| Événement | Signal source | Description fonctionnelle | Contrainte temporelle |
|---|---|---|---|
| Swing swoosh | `swing_started` | Son de lame en mouvement, dur, sec — pas de réverb longue. **Spatialisation** : head-locked (ego-positionned, `AudioStreamPlayer` 2D player-anchored) — sans viewmodel MVP, le swoosh est le seul feedback proprioceptif de la lame. **Interruption** r2 : si `Player.died()` pendant le swing actif, **fade-out 30 ms wall-clock**. **r4 A-01 / A-08 FIX** : le fade-out DOIT etre pilote par un mecanisme wall-clock **independant de `Engine.time_scale`** — utiliser `AudioStreamPlayer.volume_db` interpole dans `_physics_process` via `Time.get_ticks_msec()` (wall-clock). **Ne pas utiliser Tween dans `_process`** car `_process` est scale par `time_scale` (Rule 13 note) : pendant slow-mo @ 0.3×, un Tween 30 ms deviendrait 100 ms wall-clock perçus, overlap avec clac + blood ambiance → casse Fantasy staccato. **Cas "kill pendant swing actif" (r5 BLOCK-r5-B fix — architecture DEFERRED clarifiée)** : si `enemy_killed` est emis alors que le swoosh joue encore, le fade-out est **dispatché DEFERRED au frame N+1 post-kill** (cohérent avec ADR-0005 D-5 amendment r2 qui limite l'exemption SYNC au seul flash blanc VFX — tous les autres consumers audio restent CONNECT_DEFERRED). La formulation r4 "déclenché immédiatement au tick du kill" était **factuellement incorrecte** dans cette architecture — au time_scale 0.3, un frame N+1 DEFERRED = ~55 ms perçus. La perception d'immédiateté est assurée par le **ducking -6 dB du bus `swing_active` sur événement `enemy_killed` avec release 30 ms** (cf. Mix hierarchy § ci-dessous, règle de ducking 3). Le ducking absorbe l'overlap swoosh+clac perçu sans requérir un fade-out SYNC — c'est la solution architecturale correcte, pas le timing du dispatch. Sound designer : **ne pas tenter un SYNC override** pour l'Audio Handler swoosh (casserait D-5). | Déclenché au tick 1 du swing, dure ≤ 120 ms wall-clock (**pas scale par time_scale**). Connexion CONNECT_DEFERRED. |
| Impact hit (non-kill) | `enemy_hit` (si système partiel futur) | N/A MVP — ennemi meurt toujours au premier hit | — |
| Kill impact | `enemy_killed(enemy: Node, position: Vector3)` | Son sec bref — **"clac"** (r1 tranche audio-director : transitoire pur 800Hz-4kHz, attaque < 5 ms, decay rapide sans queue) — PAS "thud" (qui evoquait une basse frequence organique incompatible avec "katana acier"). Pas de metal resonnant. **Spatialisation** : 3D positional `AudioStreamPlayer3D` place au **champ `position` du payload signal `enemy_killed`** (Vector3 stable, capture au tick du kill) — **r4 A-03 FIX** : NE PAS utiliser `enemy.global_position` au moment de la reception (l'ennemi peut etre `queue_freed` entre emission DEFERRED et reception au frame N+1 → crash). **Ownership node** : le `AudioStreamPlayer3D` vit dans le scene root de la room ou dans un pool dedie Audio System — **jamais attache a l'ennemi** (qui peut etre freed avant fin du sample). **Ear placement r4 A-05** : `Camera3D` active est l'`AudioListener3D` par defaut Godot 4.6 — aucun `AudioListener3D` dedie ne doit etre ajoute sans coordination Audio System (casserait la spatialisation). Attenuation sur distance normale (0-3 m). | **r2 reformulation** : Dispatché au frame N+1 post-kill via CONNECT_DEFERRED (soit 16.6 ms wall-clock après le flash blanc SYNC au frame N). **~ 55 ms perçus à `SLOW_MO_SCALE = 0.3`** (16.6 × 1/0.3). Tolérance audio-lagging-visual : ≤ 125 ms (Vatakis & Spence 2006) — respecte meme en perçu. Connexion CONNECT_DEFERRED. |
| Blood ambiance | `enemy_killed(enemy: Node, position: Vector3)` | Micro son de liquide organique sur le splash (tranche r1 audio-director : **IN au MVP**, pas "facultatif"). <= 500 ms, delay 40-60 ms post-impact (tombe dans le silence rythmique apres le clac). Atteunation douce, pas de reverb. **Spatialisation r2 + r4 A-03 fix** : 3D positional `AudioStreamPlayer3D` place au **champ `position` du payload** (pas `enemy.global_position` — meme reason que Kill impact). **Ownership node** : scene root de la room ou pool Audio System — jamais child de l'ennemi. Sur multi-kill N, N instances `AudioStreamPlayer3D` indépendantes — budget CPU négligeable (≤ 3 instances simultanées par swing MVP). | Declenche apres impact avec delay 50 ms wall-clock. Connexion CONNECT_DEFERRED. |
| Slow-mo audio response | `enemy_killed` (pendant time_scale = 0.3) | **r1 CORRECTION BLOCKING #5** : `AudioStreamPlayer` **NE pitche PAS** automatiquement avec `Engine.time_scale` en Godot 4.6 (comportement stable 4.0+, verifie audio-director + godot-specialist r1). Le draft initial affirmait le contraire — correction factuelle critique. **Decision Martin D3 : aucun pitch audio** pendant slow-mo (slow-mo est visuelle, pas sonore). Aucun bypass necessaire : le comportement default est deja coherent avec l'intention. | Aucune action code. Documentation explicite ici pour eviter futur sound designer d'implementer un bypass inutile. |
| Multi-kill audio | `multi_kill(count)` | **r1 tranche audio-director** : sur multi-kill meme tick, le "clac" kill impact est joue **une seule fois** (premier `enemy_killed`), pas N fois. Evite saturation/phasing de 3 clacs simultanes (parallele VFX Rule 3 "flash une seule fois"). Blood ambiance joue pour **chaque** kill individuellement (les sang qui gicle est perceptible N fois). Layer stinger additionnel = Tier 2. | MVP : 1 clac + N blood ambiances. Infrastructure `_kill_sound_played_this_swing: bool` flag. |
| Cooldown ready | (aucun signal) | **r1 tranche audio-director** : aucun son de cooldown "pret" au MVP. Silence intentionnel (Pillar 1 : le timing se ressent, pas s'ecoute — coherent UI "no HUD" art-bible). Reevaluation en Tier 2 si playtest revele des misses lies a desynchronisation tactile. | N/A MVP. |
| Swing miss | `swing_started` sans `enemy_killed` | **r1 tranche audio-director** : aucun son de miss differencie au MVP. Le swoosh + silence = le signal. Reevaluation Tier 2 si playtest revele "j'ai l'impression de rater au hasard". | N/A MVP. |

### Mix hierarchy — Intention kill sequence (r4 A-06 resolu)

**Fenetre kill totale** : ~200 ms wall-clock (50 ms slow-mo + 150 ms post-restore) ou ~350 ms percus à 0.3×. 4 sources audio peuvent se superposer pendant cette fenetre (swoosh + clac + blood ambiance + ambient salle). Sans directive mix, le sound-designer livrera une accumulation additive qui contredit la Fantasy staccato ("silence entre deux notes"). **Directive explicite pour `/team-audio`** :

**Priorite percue (du plus audible au moins audible)** :
1. **Kill impact "clac"** — jamais attenue, frequence principale (800Hz-4kHz transitoire) domine la fenetre.
2. **Blood ambiance** — seul element apres le clac dans la micro-pause percue, delay 50 ms wall-clock = ~170 ms percus place parfaitement apres le clac pour remplir le "silence" sans le couvrir.
3. **Swoosh swing** — doit etre termine ou en fade-out 30 ms wall-clock avant l'impact (cf. row Swing swoosh r4 fix). Si encore actif au clac, ducked -6 dB jusqu'a fin fade.
4. **Ambient salle** (future Level System / Audio ambient) — ducked -3 dB pendant toute la fenetre kill `[swoosh_start, kill_impact + 500 ms]` pour preserver la lisibilite rythmique.

**Regles de ducking** (bus routing — a detailler par sound-designer dans Audio GDD futur) :
- Bus `sfx_combat` (swoosh + clac + blood ambiance) : 0 dB.
- Bus `ambient` (future) : duck -3 dB via sidechain sur `enemy_killed` event, release 300 ms.
- Bus `swing_active` (swoosh) : duck -6 dB sur `enemy_killed` event, release 30 ms (aligne fade-out wall-clock swoosh). **r6 audio-director paramétrage précisé** : (a) **courbe de release** = **exponentielle** (conforme comportement Godot AudioBusLayout compressor par défaut, cohérent avec la perception psychoacoustique exponentielle du volume) ; (b) **volume nominal swoosh avant ducking** = **≤ -6 dB** sur le bus (nominal), de sorte que `ducked = ≤ -12 dB` pendant la release 30 ms — en dessous du seuil de masquage psychoacoustique pendant le decay du clac (≈ 50 dB SPL relatif typique). Si le sound-designer cible un swoosh plus présent (nominal > -6 dB), le seuil release doit être réexaminé ou le ducking renforcé à -9 dB. Ce paramètre est un contrat testable via AC-CMB-audio-02 (MockAudioBus log ducking event avec timestamp wall-clock). **Bus naming proposition** : `sfx_combat`, `ambient`, `swing_active` sont proposés ici et serviront de baseline — **autorité canonique finale = Audio System GDD** (à créer) qui peut renommer ou restructurer si justifié. En attendant, lead-programmer ne doit pas hardcoder ces noms dans le code Combat — les exposer comme constantes d'un `audio_bus_config.tres` data-driven.
- **Cas kill précoce (swing < 20 ms)** (r6 Martin D-r4-3) : si `enemy_killed` arrive dans les 20 premières ms du swing (tick 0 ou tick 1 de la window active), le fade-out swoosh n'a pas encore démarré et chevauche le clac avec atténuation -6 dB potentiellement insuffisante (l'attack du clac 800Hz-4kHz peut être masquée par la queue du swoosh). **Décision Martin D-r4-3 tranchée MVP** : **conserver -6 dB standard + pas de hard-cut MVP** (risque cut audible trop net sur kill standard, anti-Fantasy staccato). **Réévaluer en Tier 2 via playtest** si Fantasy staccato est dégradée sur cette edge case — alternatives examinées si besoin : (a) augmenter ducking à -9 dB conditionnel sur `_active_tick < 2`, (b) hard-cut swoosh si swing < 20 ms, (c) layer transient filter sur le clac pour percer le masquage. Actuellement aucune action code ; AC playtest ADVISORY couvre le monitoring.

**Concept "silence percu post-clac"** : la Fantasy "silence entre deux notes de mouvement" exige un instant de clarte rythmique apres l'impact. La blood ambiance (delayed 50 ms wall-clock = 170 ms percus à 0.3×) est **l'unique son** qui doit etre audible dans cette fenetre — swoosh termine, clac decay termine (< 5 ms attack + 50 ms decay). Cette intention doit etre preservee par le mix level, pas par l'absence de sons.

**AC-CMB-coverage** : le flag `_kill_sound_played_this_swing: bool` (documentation Audio row Multi-kill) est owned par Audio System — pas d'AC Combat-side. AC-CMB-integration future (post Audio GDD) verifiera que le mix hierarchy ci-dessus est respecte playtest.

### Accessibility audio timing (r4 A-10 resolu)

Le parametre `reduce_motion_slow_mo_scale_mult` et l'option `reduce_motion_disable_slow_mo` modifient la fenetre percue, ce qui impacte le timing audio percu. **Comportements audio documentes** :

| Mode accessibility | `Engine.time_scale` pendant kill | Fenetre percue | Consequence audio |
|---|---|---|---|
| **Defaut** (`mult = 1.0`, `disable = false`) | 0.3 | 50 ms wall-clock = 167 ms percus | Clac arrive a 16.6 ms wall-clock (~55 ms percus). Blood ambiance a 50 ms wall-clock (~170 ms percus). Micro-pause staccato. |
| **Mild** (`mult = 2.0`, `disable = false`) | 0.6 | 50 ms wall-clock = 83 ms percus | Blood ambiance arrive en fin de fenetre percue (~170 ms % 83 ms). Mix legerement compresse — Fantasy attenuee mais lisible. |
| **Strong** (`mult = 3.33`, `disable = false`) | ~1.0 | 50 ms wall-clock = ~50 ms percus | Micro-pause quasi-absente. Clac + blood ambiance en flux normal. |
| **Disabled** (`disable = true`) | 1.0 constant | Aucune fenetre | Pas de micro-pause — clac + blood ambiance en flux normal comme `Strong`. |

**Garantie implementation** : le fade-out swoosh 30 ms reste wall-clock **independant du mode** (cf. row Swing swoosh r4 A-01 fix). La blood ambiance delay 50 ms est aussi wall-clock (pas scale). Le mix hierarchy (ducking, priorites) reste identique — seule la compression temporelle percue change. **Compromis accessibility assume** : les modes `Strong` et `Disabled` degradent la Fantasy staccato au benefice des joueurs photosensibles/vertige — documente ici pour que le playtest accessibility sache quoi evaluer.

## UI Requirements

Le Player Combat System contribue **aucun élément UI visible au MVP**. C'est une conséquence directe de l'art-bible Chrome Zen ("une couleur par plan", "le vide rend la lame visible") et du game-concept MDA analysis "Onboarding : L'UI est invisible".

### MVP — aucun affichage HUD Combat

Pas de crosshair (la visée est corporelle, pas centrée écran). Pas d'indicateur de cooldown (le timing de swing se ressent dans la main, pas à la lecture d'une barre). Pas d'icône "kill confirmed" (le flash blanc + splash sang + slow-mo sont le feedback). Pas de compteur multi-kill (la somme des splashes est le signal).

### Debug HUD F3 (dev-only, pas player-facing)

Consommateur : le HUD System debug overlay (owned par HUD GDD à venir, F3 toggle géré par InputManager per Input GDD règle 3). Affichage en overlay `CanvasLayer` debug, non activé en release :

- `state: [Idle | Swinging | Dead]`
- `active_tick: [0..7 | -1 si !Swinging]`
- `cooldown_ratio: [0.00 — 1.00]`
- `hits_last_swing: [list of enemy names | empty si pas de swing]` — utilise la propriété debug `debug_hits_last_swing` (Published API Section C)
- `sweep_fwd: [Vector3]` — direction du sweep courant (cross-ref avec aim_forward Camera)
- `substeps_active: [1 | 3]` — visualise si anti-tunneling est engagé
- `slow_mo: [true | false]` + `time_scale: [float]`

Cette liste est informative — le HUD GDD fixera la présentation exacte (position écran, couleur, taille).

### Vertical Slice (Tier 2) — optionnel

Si un playtest MVP remonte que les joueurs ratent leurs swings parce qu'ils ne savent pas quand le cooldown est prêt (très peu probable avec `ATTACK_COOLDOWN_MS = 400`), une barre de cooldown minimaliste peut être introduite — invisible à `cooldown_ratio == 0`, fade-in opacity progressive uniquement quand `cooldown_ratio > 0.2` et fade-out à `cooldown_ratio == 0`. Forme recommandée : arc circulaire fin (1 px) autour d'un point central invisible, 2 cm au-dessus du centre écran. Couleur : blanc pur (trajectoire = path principal). Absent du MVP.

### Full Vision (Tier 3)

- Multi-kill "streak counter" style numérique minimaliste (chiffre seul, pas de fanfare, pas de texte).
- Option accessibilité "afficher reach katana" sous forme de point subtil aux coordonnées d'aim_forward × KATANA_REACH (pour daltoniens sévères ou joueurs non-proprioceptifs).

### Contrainte cross-GDD HUD System

Le HUD System GDD futur DOIT :
1. Ne **jamais** écrire `CombatSystem._cooldown_timer` directement — seulement lire `cooldown_ratio` via getter.
2. Ne **jamais** appeler de méthode Combat pour déclencher un swing — Combat est 100% réactif aux signals Movement.
3. Respecter le flag `OS.has_feature("debug")` pour l'affichage F3 — pas en release.

## Acceptance Criteria

> **Format** : chaque AC a un ID stable `AC-CMB-NN`, une classification `[Logic | Integration | Visual/Feel | Config/Data — BLOCKING | ADVISORY]`, et un ownership (`Owner: qa-tester / lead-programmer / QA Lead`). Classification alignée sur `coding-standards.md`. Chaque AC est independamment verifiable par un qa-tester sans lire le GDD.

### Core Rules coverage

- **AC-CMB-01** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en état `Idle` avec `_cooldown_timer = 0.0`, **WHEN** le signal `Player.attacked()` est émis depuis un mock `PlayerMovement` dans un test GUT, **THEN** au tick suivant : `_state == State.SWINGING`, `_active_tick == 0`, `_cooldown_timer == ATTACK_COOLDOWN_MS / 1000.0 ± 0.001`, `ShapeCast3D.enabled == true`. *Covers Rule 1, Rule 2, Rule 3.*

- **AC-CMB-02** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en état `Idle` avec `_cooldown_timer = 0.1` (cooldown non expiré), **WHEN** le signal `Player.attacked()` est émis, **THEN** `_state` reste `Idle` et `_cooldown_timer` reste `> 0.0`. *Covers Rule 1, Rule 3 — garde cooldown.*

- **AC-CMB-03** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en état `Dead`, **WHEN** le signal `Player.attacked()` est émis, **THEN** `_state` reste `Dead`, aucun sweep n'est effectué, `ShapeCast3D.enabled == false`. *Covers Rule 2, Rule 8 — Dead bloque tout swing.*

- **AC-CMB-04** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en état `Swinging` à `_active_tick == ACTIVE_TICKS - 1` (tick 7, dernier tick de la window), **WHEN** `_physics_process` est invoqué une fois supplémentaire, **THEN** `_state == State.Idle`, `_active_tick == 0`, `_hit_this_swing.is_empty() == true`, `ShapeCast3D.enabled == false`, signal `swing_ended` émis exactement 1 fois. *Covers Rule 2, Rule 3, Rule 10.*

- **AC-CMB-05** `[Logic — BLOCKING] [Owner: qa-tester]` `[BLOCKED: Gap 1 — tests/unit/combat/mock_enemy.gd non créé]` — **GIVEN** `CombatSystem` en état `Swinging` avec un MockEnemy positionné dans le volume de la capsule à distance `0.9 m` (< `KATANA_REACH`), **WHEN** `force_shapecast_update()` retourne ce collider, **THEN** `MockEnemy.die()` est appelé exactement 1 fois, signal `enemy_killed(enemy, position)` émis avec `position == MockEnemy.global_position`, ennemi ajouté à `_hit_this_swing`. Prérequis : `MockEnemy` implémente `die()` (idempotent) et `is_dead() -> bool`. *Covers Rule 6, Rule 9 — contract Enemy System Section F.*

- **AC-CMB-06** `[Logic — BLOCKING] [Owner: qa-tester]` `[BLOCKED: Gap 1 — MockEnemy non créé]` — **GIVEN** `CombatSystem` en état `Swinging`, le même `MockEnemy` déjà présent dans `_hit_this_swing` (stocké via `get_instance_id()`), **WHEN** `force_shapecast_update()` retourne ce même collider à nouveau (tick suivant de la window active), **THEN** `MockEnemy.die()` n'est PAS appelé une deuxième fois (guard `collider.get_instance_id() in _hit_this_swing`). *Covers Rule 10 — idempotence sweep intra-swing.*

- **AC-CMB-07** `[Logic — BLOCKING] [Owner: qa-tester]` `[BLOCKED: Gap 1 — MockEnemy non créé]` (r2 precision constantes) — **GIVEN** `KATANA_REACH == 1.8 m` (valeur nominale combat_config.tres), `MAX_KILLS_PER_SWING == 3`, `CombatSystem` en état `Swinging` avec `_hit_this_swing` vide, 4 MockEnemies aux distances `[0.3 m, 0.8 m, 1.2 m, 1.7 m]` tous intersectés au même tick, **WHEN** `force_shapecast_update()` les retourne, **THEN** `die()` est appelé sur les 3 premiers (distances 0.3, 0.8, 1.2 m) dans cet ordre exact, PAS sur le 4ème (1.7 m — au-delà du cap `MAX_KILLS_PER_SWING=3`), et `multi_kill(3)` est émis immédiatement après les 3 `enemy_killed`. *Covers Rule 9, Formula 6.*

- **AC-CMB-08** `[Logic — BLOCKING] [Owner: qa-tester]` `[Prereq: Gap 7 — pattern CapsuleShape3D basis documenté dans docs/engine-reference/godot/modules/physics.md]` (r1 FIX FAIL qa-lead + r4 note prereq Gap 7 + r6 CONV-1 FIX helper `_build_capsule_basis` + échantillonnage sphère unitaire) — **GIVEN** `CombatSystem` en état `Swinging`, helper `_build_capsule_basis(aim_forward)` implémenté (cf. Rule 6 code pattern r6 CONV-1 FIX — cross product direct, PAS `Basis.looking_at * from_euler(+PI/2)` qui produisait axe Y antiparallèle à aim_forward), **WHEN** le test GUT échantillonne **100 valeurs d'`aim_forward` sur la sphère unitaire** avec pitch ∈ `[-PITCH_LIMIT + 0.01, PITCH_LIMIT - 0.01]` (évite colinéaire UP/DOWN qui déclenche fallback safe_up), **THEN** : (a) **orientation** — pour chaque échantillon, `(_build_capsule_basis(aim) * Vector3.UP).angle_to(aim) < 0.001 rad` (axe Y local de la capsule aligné avec `aim_forward`, PAS antiparallèle — détection de l'inversion 180° qui vaudrait `π rad`). Test spécifique `aim_forward = Vector3(1, 0, 0)` : `capsule_axis_y_world.angle_to(Vector3(1, 0, 0)) < 0.001` rad ; (b) **position** — `ShapeCast3D.global_transform.origin.distance_to(player.global_position + Vector3(0.9, 0, 0)) < 0.001` m (distance en mètres). **r6 note** : la précision "100 échantillons sphère unitaire" est load-bearing — un test sur un seul échantillon `Vector3(0, 0, -1)` ne détecte PAS le bug CONV-1 (masqué par symétrie de la basis cardinale). Tant que Gap 7 n'est pas résolu (pattern CapsuleShape3D basis documenté dans engine-reference), AC-CMB-08 reste non-exécutable — owner lead-programmer pré-Sprint 1. *Covers Rule 4, Rule 5, Formula 1, Formula 2, r6 CONV-1 FIX.*

- **AC-CMB-09** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` `Idle`, `ShapeCast3D.collision_mask` configuré, **WHEN** inspecté statiquement sans swing, **THEN** `ShapeCast3D.collision_mask == 0b00010` (bit 2 uniquement — Enemy layer) et `ShapeCast3D.collision_layer == 0b00001` (bit 1 — Player). *Covers Rule 12.*

- **AC-CMB-10** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en état `Idle`, `Player.state == Movement.State.DASHING` (vélocité élevée `30 m/s`), **WHEN** `Player.attacked()` est émis et que le swing commence, **THEN** `_state == Swinging`, `aim_forward` utilisé pour le sweep correspond à `CameraSystem.aim_forward` (pas à `player.velocity.normalized()`). *Covers Rule 5, Rule 8 — Dashing autorisé, orientation = aim.*

- **AC-CMB-11** `[Logic — BLOCKING] [Owner: qa-tester]` (r4 P-05 + P-06 — reset complet `_death_pending` + `_buffered_attack`) — **GIVEN** `CombatSystem` `Idle`, **WHEN** `Player.died()` est reçu, **THEN** `_state == State.DEAD`, `ShapeCast3D.enabled == false`. **GIVEN** Combat `Dead` avec etat arbitraire pre-mort (`_active_tick = 3`, `_hit_this_swing = [ids...]`, `_cooldown_timer = 0.15`, `_slow_mo_active = true`, `_slow_mo_start_msec = 1234`, `_death_pending = true`, `_buffered_attack = true`), **WHEN** `Player.respawned(Vector3.ZERO)` est reçu, **THEN** les 8 assertions suivantes sont verifiees : (1) `_state == State.IDLE` ; (2) `_active_tick == 0` ; (3) `_hit_this_swing.is_empty() == true` ; (4) `_cooldown_timer == 0.0` ; (5) `_slow_mo_active == false` ; (6) `_slow_mo_start_msec == 0` ; (7) `_death_pending == false` (r4 P-05 — sinon joueur bloque Dead au premier tick post-respawn) ; (8) `_buffered_attack == false` (r4 P-06 — sinon clic anterieur a la mort declenche swing involontaire). **AND** `Engine.time_scale == 1.0 ± 0.0001`, `ShapeCast3D.enabled == false`. *Covers Rule 2, Edge Case mort/respawn r4.*

### Formulas / invariants numériques

- **AC-CMB-12** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `SWING_DURATION_MS = 120.0`, `delta = 1.0/60.0`, **WHEN** `ACTIVE_TICKS` est calculé via `ceili(SWING_DURATION_MS / (delta * 1000.0))`, **THEN** `ACTIVE_TICKS == 8`. **ET** un swing GUT qui avance 8 ticks confirm `_state == Idle` au tick 9. *Covers Formula 4.*

- **AC-CMB-13** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `_cooldown_timer = 0.25` s, `ATTACK_COOLDOWN_MS = 400`, **WHEN** `cooldown_ratio` est lu, **THEN** `cooldown_ratio == clamp(0.25 / 0.4, 0.0, 1.0) == 0.625 ± 0.001`. **ET** à `_cooldown_timer = 0.0`, `cooldown_ratio == 0.0`. **ET** au moment d'entrée en `Swinging`, `cooldown_ratio == 1.0 ± 0.001`. *Covers Formula 5.*

- **AC-CMB-14** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 aligne Rule 7 N constant = 3) — **GIVEN** `delta = 1/60`, **WHEN** `CombatSystem` configure le sweep pour l'une des vélocités suivantes : (a) `player.velocity.length() == 0.0 m/s`, (b) `== 10.0 m/s`, (c) `== 30.0 m/s`, **THEN** pour **chaque** cas : `N_SUBSTEPS == 3 ± 0` (constant, pas de branching dynamique), `gap_max = V * (1.0/60.0) / 3` calculé correctement, `gap_max < 0.7 m` (2 × r_enemy_min) vérifié pour chaque V. **AND** statiquement : aucun chemin de code ne lit `TUNNELING_THRESHOLD` pour déterminer N_SUBSTEPS (vérifiable par grep sur le source Combat — AC fail si `TUNNELING_THRESHOLD` apparait dans une condition de branching N). *Covers Rule 7 r2, Formula 3 r2 — N constant, TUNNELING_THRESHOLD déprécié.*

- **AC-CMB-15** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** l'orientation `sweep_forward = CameraSystem.aim_forward` mockée à `(yaw=0, pitch=0)`, **WHEN** la forme close trigonométrique est évaluée : `aim_forward = Vector3(-sin(0)*cos(0), -sin(0), -cos(0)*cos(0))`, **THEN** `sweep_forward == Vector3(0, 0, -1) ± 0.001`. **ET** `sweep_forward.length() == 1.0 ± 0.0001` (vecteur unitaire strict). *Covers Formula 1.*

- **AC-CMB-16** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur à `global_position = Vector3(0, 1.8, 0)`, `aim_forward = Vector3(0, 0, -1)`, **WHEN** la hitbox est positionnée selon Formula 2, **THEN** `ShapeCast3D.global_transform.origin == Vector3(0, 1.8, -0.9)` (centre = position + `aim_forward × (KATANA_REACH/2)` = `0 + 0 - 0.9`). *Covers Formula 2.*

- **AC-CMB-17** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 valeurs Martin D3 + r4 S-F-09 assert runtime invariants #4 + #6 + #7 sur somme + r6 Martin D-r4-2 invariant #9 duty cycle) — **GIVEN** les constantes du système, **WHEN** les invariants numériques Section D.8 sont vérifiés en test unitaire statique, **THEN** les 8 conditions suivantes sont toutes vraies : (1) `KATANA_REACH > player_capsule_radius + 1.0` → `1.8 > 1.35` ✅ ; (2) `KATANA_REACH > 0.0` → `1.8 > 0.0` ✅ ; (3) `ATTACK_COOLDOWN_MS >= SWING_DURATION_MS + (1000.0/60.0)` → `400 >= 136.6` ✅ ; (4) `ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS` → `400 > 120 + 50 = 170` ✅ ; (5) `V_max * delta / N_SUBSTEPS < 2 * r_enemy_min` → `30 * 0.01666 / 3 ≈ 0.167 < 0.7` ✅ (r2 utilise V_max=30 m/s car N_SUBSTEPS constant à 3, cf. Rule 7) ; (6) `SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2` → `50 < 200` ✅ (r2 valeurs D3) ; (7) `ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5` → `80 <= 80` ✅ (limite exacte défaut) ; **(8) r6 D-r4-2 — duty cycle staccato** : `SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4` → `120 / 520 = 0.23 < 0.4` ✅ (marge confortable 0.17, protège Fantasy staccato contre tuning dérive). **r4 rejet config — mecanisme observable** : pour toute config chargée depuis `combat_config.tres`, les invariants #4, #6, #7 sont re-calcules a `_ready()` et la config est rejetee via `assert()` GDScript en **debug build** — l'assert panique et est capture par GUT `assert_fail()` (test procedure : `var combat_system := CombatSystem.new() ; combat_system.ATTACK_BUFFER_MS = 100 ; combat_system.ATTACK_COOLDOWN_MS = 300 ; assert_fail(combat_system._ready(), "Invariant #7 violated")`). En **release build** (asserts desactives), les invariants sont non-enforces runtime — AC-CMB-36 smoke check statique compense en rejetant les configs violantes pre-release. **Décision Martin DEC-r5-2 tranchée (2026-04-23) : Option A `_validate_invariants()` runtime MVP** — pour couvrir le **live-tuning via Godot Inspector** (scénario Sprint 1 garanti qui bypass l'assert `_ready()` car les valeurs sont mutées sans re-ready), Combat DOIT implémenter `_validate_invariants() -> void` **appelé en début de chaque `_physics_process`** sous garde `if OS.is_debug_build():` (1 branchement + 3 asserts par tick en debug, cost négligeable ; asserts compilés out en release, cost zéro). La méthode re-calcule les invariants **#4, #6, #7 et #9** (r6 D-r4-2 duty cycle staccato ajouté dans le scope — protège la Fantasy contre dérive live-tuning `SWING/COOLDOWN` via Inspector) sur les valeurs courantes des constantes et `assert()` panique si violation. **Test procedure étendue** : après `combat_system._ready()` réussi avec valeurs valides, muter `combat_system.ATTACK_BUFFER_MS = 100` (puis `ATTACK_COOLDOWN_MS = 300` → BUFFER/COOLDOWN=5 viole #7) et vérifier que le prochain `_physics_process` tick panique en debug via `assert_fail(combat_system._physics_process(1.0/60.0), "Invariant #7 violated runtime")`. **Test #9 dédié** : muter `SWING_DURATION_MS = 200` + `ATTACK_COOLDOWN_MS = 300` → duty = 200/500 = 0.4 (limite exacte violée en strict `< 0.4`) et vérifier `assert_fail(combat_system._physics_process(1.0/60.0), "Invariant #9 violated: duty cycle ≥ 0.4")`. Les Options B (hot-reload hook sur `resource_reloaded`) et C (statu quo `_ready()` seulement) examinées en r5 sont rejetées : B a un coût d'impl disproportionné et rate les cas tuning sans hot-reload ; C cède la validation à la discipline du tester. *Covers Formula 8 — sanity check invariants + live-tuning safety r5.*

- **AC-CMB-18** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le flag `DASH_DURATION` du Movement System (`100 ms`) et `SWING_DURATION_MS` Combat (`120 ms`), **WHEN** l'invariant croisé est vérifié statiquement dans un test GUT inter-système, **THEN** `DASH_DURATION < SWING_DURATION_MS` est confirmé (`100 < 120`) et un commentaire de test documente explicitement : "un swing démarré à mi-dash finit en état Airborne — comportement attendu couvert par Rule 8". *Covers Formula 8 — cross-system flag documenté.*

- **AC-CMB-19** `[Integration — BLOCKING] [Owner: qa-tester + lead-programmer]` (r4 QA-AC-19 — reclassement Integration via injection Callable, correction non-determinisme GUT headless) — **GIVEN** un swing actif avec `_slow_mo_active = false`, 1 MockEnemy tué au tick 2 de la window, **pattern d'injection** : `CombatSystem` expose un `_get_time_msec: Callable` substituable (defaut `Time.get_ticks_msec`) — lead-programmer implemente cette injection pre-Sprint 1 pour permettre le mocking deterministe wall-clock en test. **WHEN** `enemy_killed` est traité (avec `_get_time_msec()` mocke retournant `1000`), **THEN** immediatement `Engine.time_scale == SLOW_MO_SCALE == 0.3 ± 0.0001`, `_slow_mo_active == true`, `_slow_mo_start_msec == 1000`. **WHEN** `_physics_process` est invoque successivement avec `_get_time_msec()` mocke retournant `1030`, `1050`, `1067`, **THEN** : (a) à `1030` (< 50 ms elapsed) : `Engine.time_scale == 0.3`, `_slow_mo_active == true` ; (b) à `1050` (= 50 ms elapsed exact) ou `1067` (= 67 ms elapsed = 50 + 1 physics frame tolerance) : `Engine.time_scale == 1.0 ± 0.0001` ET `_slow_mo_active == false`. **Décision Martin DEC-r5-1 tranchée (2026-04-23) : Option A Injection Callable — BLOCKING pre-Sprint 1** — lead-programmer DOIT implémenter `CombatSystem._get_time_msec: Callable = Time.get_ticks_msec` substituable avant le démarrage Sprint 1 Combat. AC-CMB-19 reste `[Integration — BLOCKING]` déterministe automatisé CI — **pas de fallback ADVISORY**. Rationale : Pillar 1 no-regression silencieuse — un AC BLOCKING dont le verdict dépend d'une décision technique non tranchée serait un trou dans le filet CI documenté par le GDD lui-même. L'Option B (fallback profiler manuel) examinée en r5 est rejetée : elle perd la CI automatisée et laisse le timing wall-clock slow-mo dériver sans garde-fou continu. Coût estimé : ~15 lignes GDScript + 1 test d'injection. **r6 branche C accessibility disable ajoutée (qa-lead BLOCKING #3)** : quand `reduce_motion_disable_slow_mo == true` (Section G accessibility knob), le premier `enemy_killed` d'un swing ne DOIT PAS muter `Engine.time_scale`. Test procedure : `combat_system._reduce_motion_disable_slow_mo = true`, déclencher 5 kills consécutifs avec `_get_time_msec()` mocké, **THEN** pour chacun des 5 kills : `Engine.time_scale == 1.0 ± 0.0001` avant/pendant/après le kill, `_slow_mo_active == false` tout au long (jamais set à true). Si un kill mute `Engine.time_scale`, AC FAIL : "slow-mo déclenchée malgré reduce_motion_disable_slow_mo=true — viole accessibility contract". Ferme le gap qa-lead r6 : un implémenteur qui inverse la condition (`if not reduce_motion_disable_slow_mo` au lieu de l'inverse) est détecté par CI automatisé. **r6 teardown obligatoire** : test doit terminer par `Engine.time_scale = 1.0` pour éviter contamination inter-tests (global state process-wide). *Covers Rule 13, Formula 7, Section G `reduce_motion_disable_slow_mo` accessibility contract.*

### Edge Cases

- **AC-CMB-20** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 aligne M1 Option C Hybrid — mort pendant Swinging **sans** collider intersecte ce tick) — **GIVEN** `CombatSystem` en `Swinging` à `_active_tick = 3`, **aucun collider Enemy dans le sweep du tick courant** (`shape_cast_results == []`), **WHEN** `Player.died()` est reçu au même tick (handler SYNC set `_death_pending = true`), **THEN** apres execution complete du `_physics_process` Combat : `_state == State.DEAD`, signal `swing_ended` **non** émis, `ShapeCast3D.enabled == false`, aucun `enemy_killed` émis (aucun collider a resoudre), `Engine.time_scale == 1.0 ± 0.0001` (pas de slow-mo sur tick sans kill), `_death_pending == false` (consommé). *Covers Edge Case — mort pendant Swinging sans hit + Rule 17 Hybrid.*

- **AC-CMB-21** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 valeurs Martin D3) — **GIVEN** `CombatSystem` en `Swinging` avec `_slow_mo_active = true` et `Engine.time_scale = 0.3` (r2 valeur D3, pas 0.15 draft), **WHEN** `Player.died()` est reçu, **THEN** `Engine.time_scale == 1.0 ± 0.0001` est restauré **avant** tout autre traitement de la transition Dead, puis `_state == State.DEAD`, `_slow_mo_active == false`. *Covers Edge Case — mort pendant slow-mo, Pillar 3.*

- **AC-CMB-22** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` `Idle`, `_cooldown_timer = 0.0`, **WHEN** deux signaux `Player.attacked()` arrivent au même tick (injection GUT double-emit), **THEN** `_state == State.SWINGING` avec `_active_tick == 0` et `_cooldown_timer == ATTACK_COOLDOWN_MS / 1000.0` — un seul swing déclenché. *Covers Edge Case — double attacked() même tick.*

- **AC-CMB-23** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` `Idle`, `_cooldown_timer` à exactement `0.0` au tick courant (transition depuis > 0.0 au tick précédent), **WHEN** `Player.attacked()` est émis à ce même tick, **THEN** le swing est accepté immédiatement (`_state == Swinging`). La garde `_cooldown_timer <= 0.0` est **inclusive** — pas d'un tick de délai supplémentaire. *Covers Edge Case — timing exact cooldown=0, Pillar 1.*

- **AC-CMB-24** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 valeurs Martin D3) — **GIVEN** `Engine.time_scale = 0.5` (debug externe) au moment du premier `enemy_killed` d'un swing, **WHEN** la slow-mo est déclenchée, **THEN** `Engine.time_scale` passe à `0.3 ± 0.0001` (écrase la valeur externe, r2 valeur D3), et après `SLOW_MO_DURATION_MS = 50 ms` wall-clock, `Engine.time_scale` est restauré à `1.0 ± 0.0001` (pas à `0.5`). *Covers Edge Case slow-mo — time_scale déjà != 1.*

- **AC-CMB-25** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** un tick où 2 MockEnemies sont tous les deux tués (`multi_kill`), **WHEN** `enemy_killed` est traité pour le premier, **THEN** `_slow_mo_active` passe à `true` et la slow-mo est déclenchée. **WHEN** `enemy_killed` est traité pour le second (même tick), **THEN** `_slow_mo_active` est déjà `true` → aucune re-entrée, `Engine.time_scale` non ré-assigné. Signal `multi_kill(2)` émis après les deux `enemy_killed`. *Covers Edge Case — multi-kill même tick, Rule 13 idempotence.*

- **AC-CMB-26** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` avec un vrai `CameraSystem` intégré (test d'intégration), `Player.state == Movement.State.WALL_RUNNING`, tilt wall-run actif (`camera_effects.rotation.z = 0.3 rad`), **WHEN** un swing est effectué, **THEN** `CombatSystem` lit `CameraSystem.aim_forward` (forme close roll-corrigée), et `aim_forward.y` n'est PAS dévié par le tilt `z` (`|aim_forward - expected_forward_no_roll| < 0.001`). *Covers Rule 5, ADR-0002 — aim_forward roll-corrigé.*

- **AC-CMB-27** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` `Idle`, `CameraSystem.aim_forward` retourne `Vector3.ZERO` (mock bug Camera), **WHEN** `Player.attacked()` est émis, **THEN** le swing est **ignoré silencieusement** (garde `aim_forward.is_zero_approx()`), `_state` reste `Idle`, un `push_error` est émis en debug build. *Covers Edge Case cross-system — aim_forward invalide.*

- **AC-CMB-28** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 restreint à `_state == IDLE` — r4 ajout phrase isolation Swinging) — **GIVEN** `CombatSystem` en `Idle` (pas Swinging), `Player.state` retourne `Movement.State.DEAD` sans que `Player.died()` ait encore été émis (race condition 1 tick — scenario theorique connexion deferred ou drop de signal), **WHEN** `_physics_process` est exécuté avec `_state == IDLE`, **THEN** la mitigation détecte la divergence (`player.state == Dead and _state != Dead and _state == IDLE`), force immédiatement `_state = Dead` avant le reste de la logique, et `ShapeCast3D.enabled == false`. **Restriction r2** : cette garde ne s'applique **PAS** quand `_state == SWINGING` — dans ce cas, le mécanisme `_death_pending` (Rule 17) gouverne et la resolution des colliders du tick courant precede la transition Dead. **r4 isolation** : ce test est **limite a `_state == IDLE`** — verifier le comportement en `Swinging` est hors-scope de cet AC (couvert par AC-CMB-41 mutual kill Hybrid). Si la garde Idle-mitigation est erroneement appliquee pendant Swinging par un implementeur, AC-CMB-41 la capturera (resolution colliders manquante). *Covers Edge Case cross-system — race state Dead en Idle uniquement (complement Rule 17 Hybrid).*

- **AC-CMB-29** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** un test d'intégration avec `InputManager.enabled = false` (pause simulée, ADR-0004), **WHEN** 10 clics `attack` sont injectés via GUT en mode pause, **THEN** `Player.attacked()` n'est émis aucune fois (Movement n'émet pas le signal en pause), `CombatSystem._state` reste `Idle` tout au long. *Covers Edge Case cross-system — spam click en pause.*

- **AC-CMB-30** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CombatSystem` en `Swinging` à `_active_tick = 4`, **WHEN** `Player.attacked()` est reçu (signal de re-attack pendant window active), **THEN** le signal est ignoré silencieusement (garde `_cooldown_timer > 0` absorbe) — pas de reset de window, pas de re-démarrage de swing, `_active_tick` continue sa progression normale. *Covers Rule 3 — pas de buffering.*

### Playtest / Feel (manual, playtest signoff requis)

- **AC-CMB-31** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` `[BLOCKED: Gap 5 — production/qa/protocols/combat-feel-interview.md non créé]` (r4 clarification critere + r6 REC-01 liste mots bannis unifiée 7 items) — **GIVEN** un playtester joue 5 minutes de session MVP incluant au moins 10 kills, **WHEN** il est interviewé immédiatement après sur le ressenti du katana, **THEN** **au moins 4 descripteurs distincts** appartenant au vocabulaire rythmique (`beat`, `tempo`, `staccato`, `traverser`, `enchaîner`, `cadence`) apparaissent dans les verbatims du playtester **sur un panel de ≥ 5 testeurs** (taux cible ≥ 80% des testeurs utilisent spontanement au moins 2 descripteurs rythmiques distincts) ET **aucun verbatim ne contient les 7 mots bannis** : `combo`, `finisher`, `engagement`, `affrontement` (vocabulaire combat classique anti-Fantasy) ET `satisfaisant`, `récompense`, `impressionnant` (vocabulaire Fantasy B récompense isolée — r6 REC-01 étend la liste unifiée ici pour que l'intervieweur ait toute la référence en un seul endroit ; AC-CMB-33 pointe vers cette liste). Evidence : notes d'entretien horodatées + codage intervieweur dans `production/qa/evidence/combat-feel-playtest-[date].md`. **r4 note** : la formulation r3 melangeait "4/5 descripteurs" (ambigu distinct vs testeurs) — r4 fige "4 distincts par tester + 80% panel". *Covers Player Fantasy — vocabulaire rythmique + liste mots bannis unifiée r6.*

- **AC-CMB-32** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` `[BLOCKED: Gap 5]` — **GIVEN** un playtester réalise un kill pendant un dash (`dash + attacked() + enemy_killed` dans la même window active), **WHEN** il est questionné sur le kill isolément, **THEN** il décrit l'événement dans le contexte du mouvement en cours (ex : "j'ai traversé en même temps") et NON comme un événement mémorable isolé. Evidence : 3 sessions minimum, 5 testeurs minimum, taux cible ≥ 80%. *Covers Fantasy — kill = syllabe dans le mouvement.*

- **AC-CMB-33** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` `[BLOCKED: Gap 5 — production/qa/protocols/combat-feel-interview.md non créé]` (r4 ajout [BLOCKED] + liste mots de codage + r6 REC-01 pointe vers AC-CMB-31 liste mots bannis unifiée) — **GIVEN** un kill hors-mouvement (joueur stationnaire, ennemi face à lui), **WHEN** le playtester décrit le kill, **THEN** il utilise spontanément **au moins un mot appartenant a la liste de codage "vide-ou-manque"** : `plat`, `vide`, `sans intérêt`, `basique`, `ça passe`, `mécanique`, `bof`, `ok quoi` — confirmant que le kill hors-flux est perçu comme mécaniquement vide. **r6 note** : la liste des 7 mots bannis (combat-classique + Fantasy B récompense) est centralisée dans AC-CMB-31 pour référence unique de l'intervieweur. Si les mots `satisfaisant` / `récompense` / `impressionnant` apparaissent dans ce contexte hors-mouvement, cela signale une Fantasy B perçue (récompense isolée) plutôt que staccato — l'intervieweur doit demander un contexte pour distinguer. Evidence : comparaison verbatim in-flow vs out-of-flow dans `production/qa/evidence/combat-feel-playtest-[date].md`, codage par l'intervieweur via le protocole Gap 5. *Covers Fantasy — kill isolé = syllabe bâillée.*

- **AC-CMB-34** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` (r4 N minimum + mediane + r6 REC-02 Likert item reformulé pour tester Fantasy A perception rythmique au lieu de Fantasy B récompense) — **GIVEN** un slow-mo déclenché au premier kill d'un swing, **WHEN** le playtester observe la séquence, **THEN** il perçoit la slow-mo comme "une micro-pause naturelle" et non comme "une récompense séparée" ou un "effet de caméra gênant" — attesté par **réponse Likert ≥ 4/5 obtenu par ≥ 70% des testeurs sur un panel de ≥ 5 personnes, médiane ≥ 4** sur l'item Likert r6 **"Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée"** (teste perception rythmique Fantasy A — anciennement "La pause au kill m'a aidé à reprendre le rythme" qui testait la fonctionnalité Fantasy B récompense, rejetée r6 REC-02 car ne distinguait pas les deux Fantasies). **r4 note** : la formulation r3 ne spécifiait pas le N minimum ni l'agrégation (1 tester Likert 4 aurait suffi) — r4 fige pourcentage + N minimum + médiane. Evidence : questionnaire playtest `production/qa/evidence/combat-slomo-feel-[date].md` + signature QA Lead. *Covers Rule 13 — feel slow-mo Fantasy A perception rythmique.*

### Performance / Regression

- **AC-CMB-35a** `[Integration — BLOCKING] [Owner: performance-analyst + lead-programmer]` (r1 SPLIT + r2 1000 samples + r4 correction evidence path + justification seuil + Tier 1 explicite + r6 P-1 mesure `_collect_swing_hits()` COMPLET incluant union tick-0 worst case) — **GIVEN** un microbenchmark isolé dans `tests/perf/combat-shapecast-microbench.gd` : scène minimale avec `ShapeCast3D` (CapsuleShape3D radius=0.45, height=1.8), 10 MockEnemies placés aléatoirement dans un volume 5×5×5 m, Jolt physics actif. **WHEN** la fonction `_collect_swing_hits()` COMPLETE est exécutée (r6 P-1 fix — **pas juste les 3 substeps isolés**, mais l'**union complète** incluant `_tick0_intersect_shape_overlap()` au tick 0 avec `PhysicsShapeQueryParameters3D.new()` + `intersect_shape()` + dedup Dictionary, PLUS `force_shapecast_update()` + itération `get_collision_count()` à tous les ticks), mesurée via `Time.get_ticks_usec()` autour du bloc complet. Le warmup 60 samples inclut **60 swings complets** (pas 60 casts isolés) — ainsi le p99 capture le worst case tick-0 (union + allocation) pas juste les ticks 1-7 en régime stationnaire. **THEN** résultat loggé dans `tests/perf/combat-shapecast-microbench-log.md` (**r4 fix evidence path** — r3 pointait à tort vers `docs/engine-reference/` qui est la doc engine, pas un log de bench) avec valeurs `p50`, `p99` sur **1000 samples** (r2 bump depuis 240 — couvre ≥1 cycle GC Godot, position p99 = rang 990, granularité ~0.1%, 60 samples warmup ignorés). **Seuil de refus** : `p99 > 5 ms` sur **hardware testbed Tier 1 Minimum Supporté** (r4 explicite — `docs/architecture/hardware-spec-testbeds.md`). **Justification seuil 5 ms r4** : 5 ms = ~30% du frame budget 16.6 ms (60 fps locked), réserve pour le bloc ShapeCast (3 casts séquentiels avec tick-0 intersect_shape union) seul. Les 11.6 ms restants du frame budget couvrent Movement, Camera, VFX, Audio, rendering. Si p99 > 5 ms sur Tier 1, le ShapeCast mange plus que sa part équitable — revue Rule 7 / N_SUBSTEPS / engine choice obligatoire. **Si testé sur Tier 2 Confort (hardware plus puissant)** : seuils identiques — un benchmark Tier 2 qui passe ne garantit rien sur Tier 1 (pente GPU/CPU différente). Le gate CI est Tier 1. *Covers Rule 7 + r6 P-1 — bench empirique `_collect_swing_hits()` COMPLET obligatoire avant sprint Combat.*

- **AC-CMB-35b** `[Integration — BLOCKING] [Owner: performance-analyst]` (r1 SPLIT + r2 Time.get_ticks_usec + 1000 frames + r5 setup worst case Dashing V=30 + r6 perf fix setup physiquement tenable) — **GIVEN** scene integre (Player + Movement + Camera + Combat + 10 enemies + physics Jolt + rendering Forward+). **r6 perf BLOCKING #1 correction** : le setup r5 "velocity 30 m/s pendant 1000 frames" = 500 m parcourus → collision environnement → velocity tombe à 0 → p99 **sous-estime le vrai worst case ShapeCast**. Setup r6 séparé en deux mesures distinctes : **(1) Worst case ShapeCast p99** mesuré **sur les 8 ticks actifs d'un swing** (133 ms wall-clock @ 60 Hz) avec `player.velocity = Vector3(0, 0, -30.0)` forcée par le test (no environment collision — scene ring-buffer ou CharacterBody3D déplacé sans `move_and_slide()`) ; répéter sur **N=100 swings consécutifs** déclenchés depuis Dashing V=30 ; calculer p99 sur les 100 × 8 = 800 samples de tick actif. **(2) Soak frame time global** mesuré sur 1000 frames consécutifs (16.7 sec @ 60 Hz) en conditions normales (idle + swings réguliers N=10 swings pendant 1000 frames), capte cycles GC périodiques — distinct du worst case ShapeCast (1) ci-dessus. Resultats loggés dans `tests/perf/combat-integration-frametime-log.md` (colonnes p50, p99, draw_calls_max, hardware testbed, **setup type [ShapeCast worst / Soak global]**). **WHEN** les 2 mesures sont exécutées via `Time.get_ticks_usec()` en debut/fin de `_physics_process` (pas Godot Profiler intégré — résolution ~10 ms + overhead 1-3 ms, cf. r2 performance-analyst recommendation). Log dans `Array[int]`, calcul p50/p99 en fin de run. **THEN** pour **(1) Worst case ShapeCast** : `frame_time p99 <= 16.6 ms` (60 fps locked) ; pour **(2) Soak global** : (a) `frame_time p99 <= 16.6 ms` ; (b) `frame_time p50 <= 12.0 ms` (marge ≥28%) ; (c) `draw_calls <= 500` (budget Chrome Zen). Mesure sur hardware testbed reference `docs/architecture/hardware-spec-testbeds.md` Tier 1 Minimum Supporté. *Covers budget frame global post-integration + worst case ShapeCast séparé.*

- **AC-CMB-36** `[Logic — BLOCKING] [Owner: qa-tester]` (r2 ranges alignes sur Knob table Section G + r4 assert somme invariants #4 + #6) — **GIVEN** un test de régression GUT qui vérifie les constantes Combat statiques depuis `combat_config.tres`, **WHEN** la suite est exécutée après tout changement de configuration data, **THEN** (a) toutes les valeurs nominales sont dans leur safe range individuelle (source of truth = Section G) : `KATANA_REACH ∈ [1.4, 2.2]`, `KATANA_RADIUS ∈ [0.30, 0.60]`, `SWING_DURATION_MS ∈ [80, 200]`, `ATTACK_COOLDOWN_MS ∈ [300, 600]`, `ATTACK_BUFFER_MS ∈ [0, ATTACK_COOLDOWN_MS / 5]` (r2 M2 range dynamique), `SLOW_MO_SCALE ∈ [0.10, 0.50]`, `SLOW_MO_DURATION_MS ∈ [30, 150]`, `N_SUBSTEPS ∈ [2, 5]`, `MAX_KILLS_PER_SWING ∈ [1, 10]`, `MAX_DECALS_PER_ROOM ∈ [4, 32]` ; **(b) r4 assertions sur somme des invariants #4 et #6** (les safe ranges individuelles permettent des combinaisons violantes) : `ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS` (invariant #4) ET `SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2` (invariant #6 inegalite stricte) — les deux verifies sur les valeurs effectives chargees, pas sur les bornes theoriques. **Fail mode** : une config `SWING=200 + SLOW_MO=150 + COOLDOWN=300` passe (a) individuellement mais echoue (b) `350 > 300` — AC-CMB-36 rejette cette config. *Covers Tuning Knobs Section G — smoke check data + invariants 4/6/7 dynamiques.*

- **AC-CMB-37** `[Integration — BLOCKING] [Owner: qa-tester]` (r1 FIX qa-lead + r2 API + r4 P-08 ajout OBJECT_COUNT) — **GIVEN** un test de régression cross-system GUT (Movement + Camera + Combat), **WHEN** le cycle complet `Idle → Swinging (8 ticks) → Idle` est exécuté **1000 fois** en boucle (r1 change 100 → 1000 pour detecter fuites <1 KB/iter) avec un MockEnemy tué à chaque swing, **THEN** : (a) `_hit_this_swing.is_empty() == true` après chaque retour à `Idle` (pas de fuite idempotence) ; (b) `Engine.time_scale == 1.0` après chaque slow-mo (pas de dérive) ; (c) `_cooldown_timer == 0.0` après chaque expiration ; (d) **memory metric** : `Performance.get_monitor(Performance.MEMORY_STATIC)` apres 1000 cycles <= avant + 500 KB (tolerance GDScript GC) ; (e) **r4 P-08 NOUVEAU — object count metric** : `Performance.get_monitor(Performance.OBJECT_COUNT)` apres 1000 cycles <= avant + 5 objets (detection fuite Nodes/AudioStreamPlayer3D/Arrays que `MEMORY_STATIC` ne capture pas — `MEMORY_STATIC` mesure la heap allouee par Godot C++, pas les Objects GDScript qui comptent contre l'object pool). Un soak qui fuit des `AudioStreamPlayer3D` sur chaque `enemy_killed` passerait (d) mais echouera (e) ; (f) aucun `push_error` ou `push_warning` emis pendant les 1000 cycles. Message d'echec inclut l'iteration index et la metric deviant. *Covers règles d'idempotence + régression système combiné + soak memoire + soak objets.*

### ACs ajoutes r1 (decisions Martin + RECOMMENDED specialists)

- **AC-CMB-38** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 Martin D1 — buffering 80 ms) — **GIVEN** `CombatSystem` en etat `Swinging` avec `_cooldown_timer = 0.05 s` (dans la fenetre de buffering `ATTACK_BUFFER_MS / 1000 = 0.08 s`), `_buffered_attack = false`. **WHEN** `Player.attacked()` est emis. **THEN** `_buffered_attack == true`, `_state` reste `Swinging` (buffer ne reset pas l'etat). **AND** quand `_cooldown_timer` atteint `0.0` (apres environ 50 ms wall-clock), **THEN** au tick suivant : `_state == State.SWINGING` (nouveau swing), `_buffered_attack == false` (consomme), `_active_tick == 0`. *Covers Rule 3 buffering r1.*

- **AC-CMB-39** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 Martin D1 — single-slot buffer + clic precoce) — **GIVEN** `CombatSystem` `Idle` → transite Swinging, `_cooldown_timer = 0.4 s` (juste fire, hors fenetre buffer). **WHEN** `Player.attacked()` est emis (3× successivement dans le meme tick). **THEN** `_buffered_attack` reste `false` (3 signals tous hors fenetre). **GIVEN** puis simulation jusqu'a `_cooldown_timer = 0.075 s` (dans fenetre buffer). **WHEN** 2× `Player.attacked()` emis successivement. **THEN** `_buffered_attack == true` (1er signal), le 2e signal est ignore (single-slot, pas de queue). *Covers Rule 3 buffer conditions + single-slot.*

- **AC-CMB-40** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 Martin D1 — buffer vide apres died) — **GIVEN** `_buffered_attack = true` dans n'importe quel etat. **WHEN** `Player.died()` recu. **THEN** `_buffered_attack == false` (buffer vide a la transition Dead, confirme aussi au respawned). *Covers Rule 3 + Edge Case mort.*

- **AC-CMB-41** `[Integration — BLOCKING] [Owner: qa-tester]` (r1 Martin D2 + r2 M1 Hybrid + r4 documentation verification indirecte) — **GIVEN** scene integree Player + MockEnemy + Combat. `CombatSystem` en `Swinging` avec hitbox intersectant `MockEnemy1` (0.8 m), et un `MockEnemyLaser` intersectant simultanement le joueur au meme tick physique. Signal `died` de Movement connecte a Combat en SYNC (cf. ADR-0005 D-5 amendment r2). **WHEN** `_physics_process` tick s'execute. **THEN** dans l'ordre d'execution : (a) Movement `_physics_process` parent execute, `Player.die()` appele, `died` signal emis SYNC ; (b) Handler `_on_player_died()` de Combat execute inline : set `_death_pending = true`, `_state` reste `Swinging`, aucune mutation d'etat ; (c) Combat `_physics_process` child execute, resolvant les colliders du ShapeCast → `MockEnemy1.die()` appele 1 fois, `enemy_killed(MockEnemy1, position)` emis ; (d) En fin de `_physics_process` Combat, verification `_death_pending == true` → transition : `_state = Dead`, `ShapeCast3D.enabled = false`, `_death_pending = false`, `swing_ended` **non** emis. Les deux meurent : Player dead + Enemy1 killed. **r4 procedure de verification indirecte** : la verification de l'ordre intra-tick (a)→(d) n'est pas directement observable par GUT (pas de hooks intra-_physics_process). Le test verifie **uniquement le resultat final post-tick** via les 7 assertions : (1) `_state == Dead`, (2) `_death_pending == false`, (3) `MockEnemy1.die()` appele exactement 1 fois, (4) `enemy_killed(MockEnemy1, ...)` emis exactement 1 fois, (5) `swing_ended` **non** emis, (6) `ShapeCast3D.enabled == false`, (7) `Player.state == Dead`. La verification de l'ordre d'execution SYNC est assuree par **code review du handler `_on_player_died()`** (evidence complementaire : capture diff PR dans `production/qa/evidence/combat-mutual-kill-code-review-[date].md`). **r5 clarification statut Done** : les 7 assertions GUT post-tick constituent le **critère BLOCKING Done** autonome — un qa-tester indépendant peut marquer cet AC Done si les 7 passent. La capture diff PR est **ADVISORY** (bonne pratique de revue défensive, non bloquante pour le sprint review). Si les 7 assertions passent mais que l'ordre SYNC est implémenté incorrectement par un mécanisme exotique, AC-CMB-20 (sous-cas sans collider) + AC-CMB-28 (race Idle) + AC-CMB-50 (transitions mid-swing) captureront la divergence via leurs permutations. Le test GUT ne peut pas observer l'ordre intra-tick, mais le **résultat post-tick** des 7 assertions suffit pour Done. **r6 qa-lead clause (8) structurelle ajoutée** : en complément des 7 assertions runtime, le test GUT effectue une **inspection statique** via grep — `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd` DOIT retourner **zéro match** (la connexion `player.died` à `_on_player_died` DOIT être en mode SYNC, pas DEFERRED — sinon le mécanisme Rule 17 Hybrid est rompu, voir ADR-0005 amendment r2 exemption SYNC pour `died`). Si grep retourne 1+ match, AC-CMB-41 FAIL avec message "player.died connecté en CONNECT_DEFERRED — viole Rule 17 Hybrid + ADR-0005 D-5 amendment r2, mécanisme `_death_pending` cassé". Cette clause (8) ferme le gap qa-lead r6 : un implémenteur exotique qui cascade un set manuel `_death_pending = true` dans `_collect_swing_hits()` passerait les 7 assertions runtime mais échouerait sur la clause (8) statique. *Covers Rule 17 mutual kill r2 Hybrid + r6 inspection SYNC structural.*

- **AC-CMB-42** `[Integration — ADVISORY] [Owner: performance-analyst]` `[BLOCKED: VFX System non implémenté — reclassé ADVISORY r6 Martin D-r4-1, sera **promue BLOCKING dès VFX System GDD disponible** ; conservé ici pour traçabilité contract Combat→VFX]` (r1 Rule 18 decal cap + r4 P-12 bump frames + annotation BLOCKED + r6 Martin D-r4-1 reclassement ADVISORY) — **GIVEN** une salle avec 15 kills successifs emettant 15 `enemy_killed` signals. **WHEN** VFX System traite les signals. **THEN** apres les 15 kills : nombre de Decal nodes actifs dans la scene = `MAX_DECALS_PER_ROOM = 12` (pas 15). Les 3 premiers decals (plus anciens) ont ete recycles via pool LRU. **r4 P-12 fix** : Frame time p99 sur **les 500 frames suivantes** (8.3 sec @ 60 Hz, coherent avec `hardware-spec-testbeds.md` qui exige ≥500 frames pour capter cycles GC Forward+) <= 16.6 ms sur hardware testbed Tier 1 Minimum Supporté. La valeur 60 frames r3 etait insuffisante pour detection GC spikes. **r4 scope note** : cet AC teste la logique VFX System (pool LRU) — quand le VFX System GDD sera cree, AC-CMB-42 sera migre la-bas ou duplique avec l'ownership clarifie. Conserve ici comme **contract Combat→VFX** (si le cap Combat `MAX_DECALS_PER_ROOM = 12` change, VFX GDD doit re-verifier). **r5 P-R5-06 clarification exécutabilité CI** : cet AC **requiert un runner GPU Tier 1 (non headless)** — `draw_calls` et frame time Forward+ post-Decal sont non mesurables en CI Godot headless (aucun GPU contexte). Le gate CI headless actuel ne peut pas exécuter cet AC. **Option future** : scinder en (a) AC-CMB-42a logique pool LRU headless-safe (compte Decal nodes via `Performance.OBJECT_COUNT` delta après 15 kills, cap à 12 exact — testable headless) + (b) AC-CMB-42b frame time Forward+ GPU runner Tier 1 dédié. Pour le MVP Sprint 1, AC-CMB-42 reste `[BLOCKED: VFX System + runner GPU]`. *Covers Rule 18 decal cap + pool LRU (contract seulement, test VFX-side).*

- **AC-CMB-43** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 Rule 11 reach constant sous velocity — gap qa-lead) — **GIVEN** `CombatSystem` en `Swinging`, `player.velocity = Vector3(0, 0, -30)` (dash max). **WHEN** ShapeCast configure au tick 0. **THEN** `ShapeCast3D.shape.height == KATANA_REACH == 1.8 m ± 0.001` — **constant**, pas augmente par velocity. *Covers Rule 11 — pas de velocity lookahead.*

- **AC-CMB-44** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 Rule 6 ShapeCast tick-par-tick update — gap qa-lead) — **GIVEN** swing actif, joueur se deplace de `Vector3(0, 0, -0.5)` entre tick 2 et tick 3 de la window. **WHEN** `_physics_process` tick 3 s'execute. **THEN** `ShapeCast3D.global_transform.origin` est mis a jour au tick 3 (cf. nouvelle position cacheee `_prev_position` tick 2 + offset reach), pas fige au tick 0. `aim_forward` est lu a jour chaque tick. *Covers Rule 6 sweep update per tick.*

- **AC-CMB-45** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 collider sans `die()` — gap qa-lead + Edge Case existant non-couvert) — **GIVEN** un collider layer=2 (Enemy) sans methode `die()` (mock configuration erroneee). **WHEN** intersecte pendant Swinging. **THEN** aucun crash, skip silencieux, `push_warning` emis en debug build (`OS.is_debug_build()`), `enemy_killed` non emis, `_hit_this_swing` non mute. *Covers Edge Case hitbox 3.*

- **AC-CMB-46** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 aim_forward vers le sol — gap qa-lead + Edge Case existant non-couvert) — **GIVEN** `CameraSystem.aim_forward = Vector3(0, -1, 0)` (pitch max -PITCH_LIMIT, regard vertical sol). **WHEN** swing actif, aucun ennemi dans la capsule verticale sous le joueur. **THEN** aucun `enemy_killed`, `ShapeCast3D.collision_mask == 0b00010` (Enemy uniquement, pas Environment), aucun crash, sweep execute normalement sans kill. *Covers Edge Case aim au sol.*

- **AC-CMB-47-Prelim** `[Logic — BLOCKING] [Owner: lead-programmer]` (r6 CONV-2 — ownerise le test empirique Gap 2 lui-même, deadline AVANT Sprint 1 Combat start, pas "fin Sprint 1") — **GIVEN** scène minimale Godot 4.6 + Jolt (aucun Combat code), un `ShapeCast3D` node avec `CapsuleShape3D` (radius=0.45, height=1.8) à `global_transform.origin = Vector3.ZERO`, un MockEnemy (CharacterBody3D layer=2, CollisionShape3D sphère radius=0.35) placé exactement à `Vector3(0, 0, -0.3)` (déjà en overlap à l'origine du ShapeCast), `shape_cast.target_position = Vector3(0, 0, -0.5)` (sweep 0.5 m vers -Z), `shape_cast.collision_mask = 0b00010`. **WHEN** `shape_cast.force_shapecast_update()` est appelé puis `shape_cast.get_collision_count()` est lu. **THEN** le résultat détermine la **variante applicable à AC-CMB-47** (ci-dessous) : (a) **Variante A confirmée — `intersect_shape` requis** : si `get_collision_count() == 0` (le collider en overlap à l'origine n'est PAS détecté par ShapeCast seul), la mitigation `_tick0_intersect_shape_overlap()` est load-bearing et AC-CMB-47 utilise Variante A ; (b) **Variante B confirmée — `force_shapecast_update` suffit** : si `get_collision_count() == 1` et `get_collider(0) == MockEnemy`, la mitigation est une sécurité redondante et AC-CMB-47 utilise Variante B. **Evidence** : résultat empirique + version Godot + version Jolt + commit SHA consignés dans `docs/engine-reference/godot/modules/physics.md` section "ShapeCast3D overlap at origin — Godot 4.6 + Jolt empirical test". **Rationale r6 CONV-2** : si Variante A confirmée, le code pattern Combat est déjà en place (rien à changer). Si Variante B confirmée, le code peut être simplifié (retirer `_tick0_intersect_shape_overlap()` et le call site) sans régression — mais il faut savoir laquelle AVANT de coder, sinon le Sprint 1 livre soit du code mort (B) soit un bug non-mitigé (A). Deadline : clôture fin-des-épics pré-Sprint 1. *Covers Gap 2 ownership + deadline r6 CONV-2.*

- **AC-CMB-47** `[Logic — BLOCKING] [Owner: qa-tester]` `[BLOCKED: Gap 2 — test empirique ShapeCast3D overlap origine Godot 4.6 non execute par lead-programmer (voir AC-CMB-47-Prelim)]` (r1 Gap 2 + r4 annotation BLOCKED + 2 variantes + r6 CONV-2 lien AC-CMB-47-Prelim) — **GIVEN** swing tick 0 (`_active_tick == 0`), un MockEnemy place exactement a `_prev_position + aim_forward × 0.5` (deja en overlap a l'origine du ShapeCast). **WHEN** Combat execute le tick 0 du swing : `_collect_swing_hits()` invoque qui fait l'union `_tick0_intersect_shape_overlap()` + `force_shapecast_update()`. **THEN** le collider est detecte, `die()` appele, `enemy_killed` emis. **r4 2 variantes selon resultat Gap 2** — lead-programmer determine laquelle post test empirique pre-Sprint 1 : (**Variante A — `intersect_shape` requis**) : si Godot 4.6 ShapeCast3D ne detecte pas les overlaps initiaux, le test verifie que **desactiver temporairement `_tick0_intersect_shape_overlap()` dans l'implem cause l'echec** (le collider est rate sans la mitigation) — prouve que la mitigation Gap 2 est load-bearing ; (**Variante B — `force_shapecast_update` suffit**) : si Godot 4.6 detecte bien les overlaps initiaux, `_tick0_intersect_shape_overlap()` est une securite redondante et ce test verifie simplement que les 2 sources produisent le meme kill (union dedup O(1) par `get_instance_id()`). Owner lead-programmer : trancher post test empirique. *Covers Rule 6 addendum Gap 2.*

- **AC-CMB-48** `[Logic — BLOCKING] [Owner: qa-tester]` (r1 guard NaN/inf aim_forward — systems-designer F1) — **GIVEN** `CombatSystem` `Idle`, `CameraSystem.aim_forward` mocke a `Vector3(NaN, 0, NaN)` ou `Vector3(inf, 0, 0)`. **WHEN** `Player.attacked()` emis. **THEN** swing ignore silencieusement (garde `is_finite()`), `_state` reste Idle, `push_error` emis en debug build. *Covers garde Formula 1 r1 — extension AC-CMB-27 aux cas NaN/inf explicitement.*

### ACs ajoutes r4 (couverture Rules + Edge Cases gap)

- **AC-CMB-49** `[Logic — BLOCKING] [Owner: qa-tester + lead-programmer]` (r4 qa-lead — Rule 15 no invulnerabilite + invariants structurels) — **Partie A (Rule 15)** : **GIVEN** le source code de CombatSystem inspecte statiquement via grep, **WHEN** on cherche les connexions signals et les flags d'invulnerabilite, **THEN** : (a) **aucun `connect(` sur layer `EnemyHitbox` (0b00100)** dans CombatSystem — Combat ne gere pas la detection de la mort joueur (Rule 14 one-shot symetrie) ; (b) **aucune propriete exposant `is_invulnerable: bool`, `invuln_timer: float`, ou equivalent** dans CombatSystem code ou Published API ; (c) **aucune logique de type "pendant Swinging, Player ne peut pas mourir"** — la garde `_state != Dead` verifie seulement l'etat Combat pour transition, pas un flag d'invulnerabilite joueur. **Partie B (invariants structurels r4 B-R3-03)** : **GIVEN** CombatSystem instancie a `_ready()`, **WHEN** le scene tree est inspecte, **THEN** : (d) `get_parent() == player_node` (CombatSystem est direct child de Player — precondition Rule 17 `_death_pending`) ; (e) `physics_process_priority == 0` (valeur defaut preservee — precondition godot-specialist Reco-A). Assertion debug build : `assert(get_parent() == player_node and physics_process_priority == 0, "Combat structural invariants violated")`. *Covers Rule 15 + r4 B-R3-03 invariants structurels.*

- **AC-CMB-50** `[Integration — BLOCKING] [Owner: qa-tester]` (r4 qa-lead — transition state Movement mid-swing) — **GIVEN** `CombatSystem` en `Swinging` à `_active_tick = 3` (mi-window), scene integree Player + Movement + Camera + Combat. **WHEN** le state Movement transite pendant la window active selon les 4 sous-cas : (a) Grounded → Airborne (saut mid-swing), (b) Airborne → Grounded (atterrissage mid-swing), (c) Grounded → Dashing (dash mid-swing), (d) Airborne → WallRunning (accrochage mur mid-swing). **THEN** pour **chaque** sous-cas : (1) `_state` reste `Swinging`, (2) `_active_tick` continue sa progression normale (3 → 4 → ... → ACTIVE_TICKS-1), (3) `ShapeCast3D.global_transform.origin` est mis a jour au tick courant avec `_prev_position + aim_forward × (KATANA_REACH / 2)` (aim_forward lu a jour chaque tick, pas fige tick 0), (4) `aim_forward` reste roll-correct (le tilt wall-run n'affecte pas horizontalement, AC-CMB-26 coverage), (5) N_SUBSTEPS=3 constant (pas de branching dynamique par state), (6) a l'expiration `_active_tick >= ACTIVE_TICKS` : transition normale vers Idle, `swing_ended` emis, `_hit_this_swing.clear()`. *Covers Edge Cases Rule 8 — transitions state mid-swing (Grounded→Airborne, Airborne→Grounded, Grounded→Dashing, Airborne→WallRunning).*

- **AC-CMB-51** `[Integration — BLOCKING] [Owner: qa-tester + lead-programmer]` (r6 REC-03 — fade-out swoosh wall-clock vérification déterministe sous slow-mo, pattern identique AC-CMB-19 injection Callable DEC-r5-1) — **GIVEN** un swing actif en état `Swinging`, `Engine.time_scale = SLOW_MO_SCALE = 0.3` (pendant fenêtre slow-mo active), le swoosh `AudioStreamPlayer` en cours de lecture avec `volume_db = 0.0`. **Pattern d'injection** : le système Audio handler (ou CombatSystem si ownership Audio côté Combat au MVP) expose un `_get_time_msec: Callable` substituable (défaut `Time.get_ticks_msec`, même injection que AC-CMB-19 DEC-r5-1). **WHEN** `enemy_killed` est dispatché DEFERRED au frame N+1 post-kill (cohérent Rule 17 + ADR-0005 D-5) et le handler audio déclenche le fade-out swoosh avec `_get_time_msec()` mocké retournant successivement `1000` (t=0 fade start), `1015`, `1025`, `1030`, `1050`. **THEN** : (a) le fade-out `volume_db` est interpolé wall-clock via `_get_time_msec()` dans `_physics_process` (**pas Tween dans `_process`** — Tween scaled par `time_scale` produirait 100 ms wall-clock perçus au lieu de 30 ms, violation Fantasy staccato r4 A-01) ; (b) à `_get_time_msec() = 1025` (25 ms elapsed wall-clock, 83% du fade 30 ms), `volume_db ≈ -20 dB ± 2 dB` (interpolation linéaire sur échelle dB) ; (c) à `_get_time_msec() = 1030` (30 ms elapsed wall-clock exact, 100% du fade), `volume_db <= -60 dB` (silence pratique) ; (d) **résolution complète dans `[25, 50] ms wall-clock`** (50 ms = 30 ms fade + 1 physics frame tolerance à 16.6 ms wall-clock). Si le test observe résolution à 75-100 ms wall-clock, c'est le signal qu'un Tween `_process`-based a été utilisé → AC FAIL avec message explicite "swoosh fade-out scaled by time_scale — violates r4 A-01 fix, Fantasy staccato dégradée". Evidence : log `volume_db` par tick dans `tests/integration/combat/swoosh-fade-wall-clock-test.gd`. *Covers Rule 13 + row Swing swoosh r4 A-01 fix + r6 REC-03 vérification CI automatisée.*

- **AC-CMB-52** `[Logic — ADVISORY] [Owner: lead-programmer]` (r6 qa-lead — Gap 4 `attacked()` hors `_physics_process` formalisé) — **GIVEN** le source code de CombatSystem inspecté statiquement via grep + revue de diff PR, **WHEN** on cherche la garde d'assertion `attacked()` dans le handler connecté à `player.attacked`, **THEN** : (a) le handler (ex : `_on_player_attacked()` ou inline dans la connexion) contient explicitement `assert(Engine.is_in_physics_frame(), "attacked() received outside _physics_process — ADR-0005 D-4 violation")` en tête de méthode, en debug build uniquement ; (b) aucun chemin de code Combat ne lit `InputManager.*` directement (Core Rule 1 + AC-CMB-49 Partie A coverage). Evidence : capture diff PR dans `production/qa/evidence/combat-attacked-physics-frame-check-[date].md` + snapshot grep output `grep -nE 'assert\(Engine\.is_in_physics_frame' src/gameplay/combat/combat_system.gd` retournant au moins 1 match. Classification ADVISORY (pas BLOCKING Done) : l'assertion sert de détection de régression ADR-0005, pas de critère gameplay — un MOCK GUT ne peut pas émuler une émission hors `_physics_process` de façon fiable (GUT s'exécute hors frame loop). Code review + static grep est le seul mécanisme de vérification. *Covers Edge Case cross-system — `attacked()` mode emit (Gap 4 r1 formalisé r6).*

- **AC-CMB-audio-01** `[Integration — ADVISORY pre-playtest] [Owner: qa-tester]` `[BLOCKED: Audio System GDD non implémenté — ADVISORY jusqu'à création Audio System GDD, sera promue BLOCKING Integration dès Audio System GDD disponible]` (r6 audio-director BLOCKING #2 — contrat multi-kill côté Combat) — **GIVEN** un swing actif en `Swinging` avec 2 MockEnemies intersectés au même tick de la window active (cas multi-kill AC-CMB-25 coverage). **WHEN** `enemy_killed(MockEnemy1, pos1)` et `enemy_killed(MockEnemy2, pos2)` sont émis au même tick, suivis de `multi_kill(2)`. **THEN** côté Audio (mocké via `MockAudioHandler` implémentant le contrat `_kill_sound_played_this_swing: bool`) : (a) au premier `enemy_killed` reçu (MockEnemy1), le flag `_kill_sound_played_this_swing` passe de `false` à `true` et le clac est joué 1 fois ; (b) au second `enemy_killed` reçu (MockEnemy2) au même tick, le flag est déjà `true` → le clac **n'est PAS rejoué** (évite saturation phasing 3 clacs simultanés, r1 tranche audio-director) ; (c) blood ambiance joue 2 fois (une par `enemy_killed` individuel — le sang qui gicle est perceptible N fois, cf. Section Audio row Multi-kill audio) ; (d) à `swing_ended` (tick ACTIVE_TICKS+1), le flag est reset à `false` pour le prochain swing. *Covers Section Audio row Multi-kill audio + contrat Combat→Audio multi-kill (infrastructure `_kill_sound_played_this_swing` owned by Audio System mais contract vérifiable côté Combat via MockAudioHandler).*

- **AC-CMB-audio-02** `[Integration — ADVISORY pre-playtest] [Owner: qa-tester]` `[BLOCKED: Audio System GDD + AudioBus CI access]` (r6 audio-director BLOCKING #2 — contrat ducking event ordering côté Combat) — **GIVEN** un swing actif, swoosh en lecture sur bus `swing_active` (nominal volume ≤ -6 dB selon Mix hierarchy). **WHEN** `enemy_killed` est émis au tick N du swing. **THEN** dans l'ordre temporel sur les frames suivantes : (a) au frame N+1 (CONNECT_DEFERRED dispatch, cohérent ADR-0005 D-5), le bus `swing_active` reçoit l'événement ducking -6 dB avec release 30 ms wall-clock ; (b) aucun nouveau `swing_started` n'est émis pendant la fenêtre `[N, N + ATTACK_COOLDOWN_MS / (1000 / 60) = 24 ticks]` — le cooldown cover la période de ducking active ; (c) si un `multi_kill(count)` est émis suite à plusieurs `enemy_killed`, il suit les événements `enemy_killed` individuels (ordre intra-tick Section C Note pattern coherent). Test via MockAudioBus qui log chaque événement ducking avec timestamp wall-clock. *Covers Section Audio Mix hierarchy règles de ducking 1-4 + contrat ordonnancement Combat→Audio.*

### Gaps identifiés / Dépendances de test non résolues

**Gap 1 — MockEnemy interface requise (bloquant les ACs 05, 06, 07, 25).**
ACs -CMB-05 à -CMB-07 et -CMB-25 requirent un `MockEnemy` GDScript implementant le contrat Enemy System : `die()` idempotent + `is_dead() -> bool` + `CollisionShape3D` layer=2. Ce mock n'existe pas encore — il doit être créé en `tests/unit/combat/mock_enemy.gd` avant que ces ACs puissent être automatisés. Conséquence : ces ACs sont en attente d'implémentation du MockEnemy, pas du CombatSystem. À délivrer au sprint de test de combat.

**Gap 2 — Comportement ShapeCast3D sur overlap à l'origine (Edge Case hitbox / collision 1).**
L'Edge Case "ennemi spawné en chevauchement au tick d'entrée" documente une incertitude : ShapeCast3D Godot 4.6 détecte-t-il les colliders déjà en overlap à `origin` ? Aucun AC automatisé n'est possible sans vérification d'API sur le moteur réel. **Action requise** : le lead-programmer doit écrire un test ad-hoc en implémentation (hors GUT standard) qui instancie un collider Enemy à 0.0 m du sweep origin et vérifie si `get_collision_count() > 0`. Résultat à documenter dans `docs/engine-reference/godot/` et à intégrer en AC si le comportement est déterministe.

**Gap 3 — Déterminisme Jolt pour égalité de distance (Edge Case hitbox 2).**
Le tri secondaire par `instance_id` (requis pour speedrun leaderboard strict) n'est actuellement pas spécifié dans le code — il est documenté en edge case comme "optionnel". Si un AC de déterminisme strict est requis pour la discipline speedrun, il faudra un addendum Rule 9 avec le tri secondaire explicite. Aujourd'hui aucun AC de ce type n'est inclus (non-MVP). **Flag** : à réévaluer si le projet déploie des leaderboards online avant la Full Vision.

**Gap 4 — `attacked()` hors `_physics_process` (Edge Case cross-system).**
L'assertion `assert(Engine.is_in_physics_frame(), ...)` est en debug build uniquement. Aucun AC GUT automatisé ne peut émuler une émission hors `_physics_process` de façon fiable via les mocks GUT (les tests GUT s'exécutent hors frame loop). Vérification manuelle : lead-programmer valide l'existence de l'assertion via lecture de code lors de la code review, pas en test automatisé. Evidence acceptée : capture diff PR dans `production/qa/evidence/`.

**Gap 5 r1 — Protocole d'entretien playtest standardise (ACs -CMB-31 a -CMB-34).**
Les 4 ACs Visual/Feel ADVISORY referencent un questionnaire playtest standardise qui n'existe pas. Sans ce document, les ACs sont non-reproductibles d'un playtest a l'autre. **Action requise** : creer `production/qa/protocols/combat-feel-interview.md` AVANT le premier playtest MVP Combat. Contenu attendu : script d'interview 10-15 questions, codage des verbatims (in-flow vs out-of-flow), echelle Likert 3-item pour slow-mo, criteres pass/fail quantifies. Owner : `qa-lead`. Blocker pour AC-31, -32, -33, -34 execution.

**Gap 6 r1 → ✅ RÉSOLU r3 (créé) + r6 P-2 clarification source of truth.**
Les ACs performance requirent un "hardware minimum spec" reproductible. **Statut** : `docs/architecture/hardware-spec-testbeds.md` **existe** (créé r3 par technical-director, Tier 1 Minimum Supporté + Tier 2 Confort + Tier 3 Haut de gamme). **r6 P-2 fix** : aucune recommandation hardware inline ici — tout hardware spec (CPU model, GPU model, RAM, OS, Godot version pin) vit **exclusivement** dans `docs/architecture/hardware-spec-testbeds.md` (source of truth unique). Les ACs 35a/35b/42 pointent vers ce doc, pas vers des spécifications inline qui dérivent. Owner : `technical-director` (maintenance du doc). Gate CI AC-35a/35b = Tier 1 Minimum Supporté (cf. doc pour specs exactes).

**Gap 7 r1 — Axe long `CapsuleShape3D` dans `ShapeCast3D` basis (Godot 4.6).**
Orienter l'axe long (Y par defaut en Godot) d'une `CapsuleShape3D` pour qu'il suive `aim_forward` necessite de construire une `basis` specifique. AC-CMB-08 est corrige r1 pour utiliser `angle_to()` + r6 CONV-1 FIX via helper centralisé `_build_capsule_basis()` (cross product direct, cf. Rule 6 code pattern). **Action résiduelle** : lead-programmer documente le code pattern `_build_capsule_basis()` complet (avec safe_up fallback + determinant guard) dans `docs/engine-reference/godot/modules/physics.md` + test unitaire simple verifiant l'alignement (100 échantillons sphère unitaire cf. AC-CMB-08 r6) avant integration Combat. Owner : `lead-programmer`. Blocker pour AC-CMB-08 implementation.

**Gap 8 r6 — Comportement `ShapeCast3D.margin` avec Jolt physics (Godot 4.6).**
L'engine-reference `docs/engine-reference/godot/modules/physics.md` ligne 35 note que le collision margin "may behave differently" entre Jolt (default Godot 4.6) et GodotPhysics3D. Le GDD Combat ligne 636 (Dependencies ADR-0001) mentionne "Jolt ShapeCast3D via `margin` — valider en impl" comme commentaire isolé sans owner ni échéance. Cette `margin` property affecte la distance de détection de contact TOUS les ticks de la window active (distinct de Gap 2 qui concerne l'overlap à l'origine tick 0 uniquement). Si Jolt introduit un margin ghost-hit ou une différence de résultat non documentée, l'implémenteur Sprint 1 n'a aucune spec. **Action requise** : lead-programmer effectue un test empirique minimal — scène avec CapsuleShape3D + target_position non-nul + Enemy à distance contrôlée, mesurer le seuil de détection réel vs. théorique — et documenter la valeur de `margin` par défaut + toute anomalie comportementale dans `docs/engine-reference/godot/modules/physics.md`. Owner : `lead-programmer`. Échéance : pré-Sprint 1 Combat implementation (regrouper avec Gap 2 test empirique dans la même session d'instrumentation Jolt). Source : review r6 godot-specialist BLOCKING #2.

## Open Questions

Questions identifiées pendant l'authoring de ce GDD qui appellent une décision future (playtest, ADR, nouvelle ressource) — chacune avec owner et échéance cible.

1. **ShapeCast3D overlap à l'origine — comportement Godot 4.6** (*AC-CMB-05 lié, Gap 2 Section H*)
   - Question : le node `ShapeCast3D` avec `target_position = delta` détecte-t-il les colliders déjà en overlap à `origin` (cas ennemi spawné CHEVAUCHANT le volume au tick 1) ?
   - Impact : si non, Combat doit précéder chaque `force_shapecast_update()` d'un `space_state.intersect_shape()` statique — overhead CPU mineur mais ajoute du code.
   - Owner : `lead-programmer` (test empirique en impl Sprint Combat)
   - Échéance : avant fin Sprint 1 Combat implementation
   - Documentation attendue : résultat noté dans `docs/engine-reference/godot/modules/physics.md`

2. **Déterminisme Jolt — tri secondaire pour speedruns** (*Gap 3 Section H*)
   - Question : si deux ennemis sont à distance strictement égale du joueur au sort multi-hit, l'ordre `get_collider(idx)` de Jolt est-il stable run-to-run ?
   - Impact : si non-déterministe, les speedrun leaderboards nécessiteront un tri secondaire par `instance_id`.
   - Owner : `ai-programmer` + `lead-programmer`
   - Échéance : Tier 3 (Full Vision) — irrelevant au MVP
   - Décision pendante : ajouter Rule 9 addendum si leaderboards online sont poussés.

3. **~~Slow-mo audio — pitch de `Engine.time_scale`~~** (*FERMEE r1 Martin D3*)
   - **Decision** : aucun pitch audio pendant slow-mo. `AudioStreamPlayer` Godot 4.6 default = pas de pitch automatique (confirmee r1). Le swoosh et le kill impact restent a vitesse normale pendant la fenetre slow-mo. Coherent Fantasy "slow-mo visuelle, pas sonore".
   - Si un playtest MVP revele un besoin de pitch-down leger pour accentuer le beat, reevaluer en Tier 2 — mais l'infrastructure actuelle (no pitch) est le defaut valide.

4. **Viewmodel katana — Tier 2** (*cf. Section C Rule 16*)
   - Question : la version Tier 2 ajoute-t-elle un viewmodel 1st-person (lame visible dans le coin bas écran) ? Si oui, qui possède l'animation (Combat ou Animation System) ?
   - Impact : modèle 3D + animation rigging + weapon sway — travail art non-MVP.
   - Owner : `art-director` + `animation specialist` (non encore assigné)
   - Échéance : début Tier 2 Vertical Slice
   - Note : le système Combat actuel **fonctionne sans viewmodel** — un ajout doit être strictement additif, jamais modifier la logique.

5. **Trail katana — visibilité avec surfaces blanches (Chrome Zen)**
   - Question : le trail blanc `#FFFFFF` sera-t-il lisible sur les murs Chrome Zen blancs/chromés de la Tour Arasaka ?
   - Impact : si non, il faudra probablement bordure sombre (contour) ou switcher couleur selon contexte — risque Chrome Zen.
   - Owner : `technical-artist` + `art-director`
   - Échéance : premier prototype visuel post-MVP implementation (week 2-3)
   - Résolution anticipée : jouer avec outline shader fin + énergie > 1 en HDR si bloom contrôlé.

6. **ADR Hitbox Sweep + Slow-mo Time Dilation** (*cf. Section F ADR gaps*)
   - Question : faut-il créer un ADR Combat Hitbox Sweep (architecture ShapeCast3D + subdivision) ET un ADR Slow-mo Time Dilation (ownership `Engine.time_scale`) ?
   - Impact : formalisation cross-system. Les 5 collision layers sont GDD-owned actuellement — un ADR figerait la taxonomie pour tous les systèmes futurs.
   - Owner : `technical-director` (via `/architecture-decision` après `/architecture-review`)
   - Échéance : avant sprint Enemy System (qui consommera le layer 2+3)
   - Recommandation : lancer `/architecture-review` sur ce GDD en fresh session avant d'écrire les ADRs — la review surfacera si nécessaire.

7. **Playtest feel post-MVP — validation `vocabulaire rythmique`** (*AC-CMB-31*)
   - Question : si le playtest MVP révèle que < 4/5 playtesters utilisent le vocabulaire rythmique (beat, staccato, traverser), faut-il ajuster la Fantasy ou le feedback visuel/audio ?
   - Impact : validation de la Player Fantasy — potentiellement review de tous les choix Chrome Zen hit feedback.
   - Owner : `creative-director` + `qa-lead` + `Martin`
   - Échéance : après le premier playtest MVP Combat (Sprint 2-3)

---

## Addendum r5.2 — CONV-1 faux positif r4 (non capturé par r5.1)

**Date** : 2026-04-23
**Source** : `/design-review` r5 fresh session — convergence multi-specialist `[gameplay-programmer]` + `[godot-specialist]` + arbitrage `[creative-director]`. 3 décisions Martin D-r4-1 / D-r4-2 / D-r4-3 confirmées.

### CONV-1 — Basis signe incorrect (Rule 6 + Formula 2 + AC-CMB-08 + Note Gap 7)

**Issue** : le pattern r4 `Basis.looking_at(aim_forward, safe_up) * Basis.from_euler(Vector3(PI/2, 0, 0))` est **mathématiquement incorrect**. `Basis.looking_at(target, up)` oriente l'axe **-Z local** sur `target` (convention caméra Godot 4.x). La rotation `from_euler(+PI/2, 0, 0)` autour de X permute Y et Z de telle manière que l'axe **+Y local** pointe **antiparallèle** à `aim_forward`. Sans symétrie de `CapsuleShape3D` sur son axe long, cette erreur est masquée à la détection standard mais devient visible dès qu'un test asymétrique vérifie la direction du balayage.

**r5 confirme par 2 specialists indépendants fresh session** (faux positif r4 non rejeté par r5.1 non plus).

**Fix requis — remplacer les 4 occurrences** :
- Rule 6 code pattern ligne ~87 (dans `_tick0_intersect_shape_overlap`)
- Rule 6 Note Gap 7 ligne ~135 (doc mathématique)
- Formula 2 ligne ~377 (description technique)
- AC-CMB-08 ligne ~931 (référence pattern)

**Construction correcte — via cross product directement** :

```gdscript
# r5.2 CONV-1 FIX — remplace Basis.looking_at * from_euler(+PI/2). Axe Y local = aim_forward par construction.
# Verifiable math : _build_capsule_basis(v) * Vector3.UP == v pour tout v unit vector non-colineaire a safe_up.
func _build_capsule_basis(forward: Vector3) -> Basis:
    assert(forward.is_normalized(), "aim_forward doit etre unit vector (Camera Rule 13)")
    var safe_up: Vector3 = Vector3.UP
    if absf(forward.dot(Vector3.UP)) > 0.999:
        safe_up = Vector3.FORWARD  # fallback pitch +/- PITCH_LIMIT (regard ciel/sol)
    var right: Vector3 = safe_up.cross(forward).normalized()
    var local_z: Vector3 = right.cross(forward)
    var b := Basis(right, forward, local_z)  # axe Y = forward par construction
    # r5 systems B-1 — garde runtime contre basis quasi-singuliere (amplification conversion local)
    if absf(b.determinant()) < 0.01:
        push_error("_build_capsule_basis: basis quasi-singuliere, fallback IDENTITY — forward=%v" % forward)
        return Basis.IDENTITY
    return b
```

**AC-CMB-08 r5.2 précision** : test GUT doit vérifier sur 100 valeurs `aim_forward` sampleees sur la sphère unitaire (pitch ∈ [-PITCH_LIMIT + 0.01, PITCH_LIMIT - 0.01]) que `(_build_capsule_basis(aim) * Vector3.UP).angle_to(aim) < 0.001 rad`.

### CONV-2 — Gap 2 test empirique owner + deadline (convergence gameplay + qa)

Gap 2 (ShapeCast3D overlap à l'origine Godot 4.6 + Jolt) est noté dans le GDD avec mitigation `_tick0_intersect_shape_overlap()` en place. r5.1 a ajouté la deadline "fin Sprint 1 Combat impl". **r5.2 ajoute** : créer AC-CMB-47-Prelim `[Logic — BLOCKING] [Owner: lead-programmer]` qui ownerise le test empirique lui-même (scène minimale + assertion `get_collision_count()`), AVANT Sprint 1 Combat start (pas "fin de Sprint 1"). Rationale : si Variante A (intersect_shape requis) confirmée, le code pattern est déjà en place. Si Variante B (redondant), le code peut être simplifié sans regression — mais il faut savoir laquelle avant de coder.

### Décisions Martin confirmées r5.2

- **D-r4-1 (AC-CMB-42 decal cap)** : reclasser `[Integration — ADVISORY]` avec note "promue BLOCKING dès VFX GDD disponible". Évite gate zombie sur système non implémenté. Recommandation creative-director appliquée.
- **D-r4-2 (Invariant #8 duty cycle)** : ajouter dans Section D.8 invariant `SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4` avec assert runtime debug. Default 120/520 = 0.23 << 0.4 (marge confortable). Protège staccato silencieux contre tuning dérive. AC-CMB-17 étendu pour vérifier invariant #8.
- **D-r4-3 (Audio ducking -6dB)** : conserver -6dB standard + ajouter dans Section Audio "Mix hierarchy" note **"Cas kill précoce (swing < 20 ms)"** : le fade-out swoosh peut chevaucher le clac avec atténuation -6dB insuffisante — réévaluer en Tier 2 via playtest si Fantasy staccato dégradée sur cette edge case. Pas de hard-cut au MVP (risque cut audible trop net sur kill standard).

### RECOMMENDED r5.2 retenues (à intégrer post-CONV-1 fix)

- **`[game-designer]` REC-01** : AC-CMB-31 doit référencer explicitement la liste étendue de mots bannis (inclure `satisfaisant`, `récompense`, `impressionnant` cf. AC-CMB-33) pour qu'un intervieweur ait toute la liste en un seul endroit.
- **`[game-designer]` REC-02** : AC-CMB-34 Likert item reformulé — remplacer "La pause au kill m'a aidé à reprendre le rythme" (teste fonctionnalité) par **"Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée"** (teste perception rythmique Fantasy A, pas Fantasy B récompense).
- **`[game-designer]` REC-03** : nouveau AC-CMB-51 `[Integration — BLOCKING] [Owner: qa-tester + lead-programmer]` — vérifier que pendant slow-mo (`Engine.time_scale = 0.3`), le fade-out volume_db du swoosh est résolu dans `[25, 50] ms wall-clock` (pas 75-100 ms qui indiquerait Tween non wall-clock). Pattern identique à AC-CMB-19 (injection `_get_time_msec: Callable`).
- **`[performance-analyst]` P-1** : AC-CMB-35a doit mesurer `_collect_swing_hits()` COMPLET (union `intersect_shape` + `force_shapecast_update` incluse), pas juste les 3 substeps. Warmup 60 samples inclut 60 swings complets pour que p99 capture tick-0 worst case.
- **`[performance-analyst]` P-2** : Gap 6 ligne ~1047 retirer "GTX 1650 Ti + Core i5 12gen" inline — le doc `docs/architecture/hardware-spec-testbeds.md` fixé Tier 1 = GTX 1050 3 GB (plus contraignant). Pointer vers le doc sans citer hardware inline.

### Status post-r5.2

~~Status GDD : **Designed r5.1 → pending revise r5.2 (CONV-1 + 3 décisions Martin confirmées + 5 RECOMMENDED)** avant fresh re-review r6 cible APPROVED.~~

**Status historique — voir header ligne 3** : propagation Addendum r5.2 achevée (CONV-1 `_build_capsule_basis()` aux 4 emplacements corps, Invariant #9 duty cycle Section D.8, AC-CMB-17 clause 8 + scope `_validate_invariants()` étendu, D-r4-1 AC-CMB-42 reclass ADVISORY, D-r4-3 Audio Mix hierarchy note "Cas kill précoce", REC-03 AC-CMB-51 Section H). Review r6 fresh session 2026-04-23 confirme verdict **APPROVED CONDITIONAL** (quelques RECOMMENDED résiduels non-bloquants : AC-CMB-52 Gap 4 inspection, AC-CMB-audio-01/02, Gap 8 ShapeCast3D.margin Jolt empirique — tous tracés via review log r6). Cet Addendum reste en fin de document pour **traçabilité historique** des corrections r5.2 — ne pas le traiter comme vivant.
