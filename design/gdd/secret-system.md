# Secret System

> **Status**: In Design (r2 — full revision 2026-04-27 : 3 BLOCKING résolus B-1..B-3 ; 4 RECOMMENDED + 5 NICE-TO-HAVE déférés batch séparé)
> **Author**: Martin + agents (game-designer, level-designer, systems-designer, qa-lead, creative-director)
> **Last Updated**: 2026-04-27 (r2 full revision after fresh /design-review)
> **Implements Pillar**: **Pillar 4 (LES SECRETS RÉCOMPENSENT LE MOUVEMENT)** primaire ; Pillar 2 (LA PROGRESSION SE VOIT) secondaire ; Pillar 1 (FLOW AVANT TOUT) garde-fou
> **Review history** : `design/gdd/reviews/secret-system-review-r1-2026-04-27.md` — NEEDS REVISION → r2 résout les 3 BLOCKING (B-1 contrat Checkpoint renommé `inject_collected_secrets` + gate flag amendement Checkpoint r2 ; B-2 invariant instance_id stabilité via nouvelle Rule R-SEC-16 ; B-3 Tuning Knobs data-driven via `src/gameplay/secret/secret_constants.gd`). 4 RECOMMENDED + 5 NICE-TO-HAVE reportés séparément.

## Summary

Secret System est l'autoload qui détecte la collection des secrets placés par Level System dans la géométrie d'un étage, gère leur état binaire UNCOLLECTED/COLLECTED, et émet le signal `secret_collected(secret_node: Node, tier: int)` SYNC consommé par Credit Economy. Le système est volontairement minimaliste : pas de logique de placement (Level est l'autorité spatiale), pas de logique économique (Credit est l'autorité monétaire), pas de logique visuelle (VFX écoute le signal). Secret System est le **détecteur de franchissement** + le **garde-fou idempotent** + l'**autorité de l'état "collected"** entre deux events Level (`level_active`) et Credit (`secret_collected`). Il sert **Pillar 4 (LES SECRETS RÉCOMPENSENT LE MOUVEMENT)** comme contrat primaire — chaque body_entered sur un `SecretCollectVolume_NN` est par construction la conclusion d'un défi de mouvement, jamais d'une énigme.

> **Quick reference** — Layer: `Feature` · Priority: `MVP` · Key deps: `Level System (APPROVED r3 r4), Credit Economy (Designed r1), Game State Manager (APPROVED r1), VFX System (Not Started — visual feedback), Audio System (APPROVED r2.1 — collect cue), Save/Load System (Not Started — persist collected_secret_ids)`

## Overview

CHROME://ASCENT incarne la promesse Pillar 4 « LES SECRETS RÉCOMPENSENT LE MOUVEMENT, PAS LE CERVEAU » — chaque cachette est un défi d'exécution (timing, route, skill), jamais une énigme logique. Secret System est le système qui rend cette promesse opérationnelle : il transforme un body_entered sur un volume Area3D placé en bout de défi de parkour en **un crédit + un feedback audio/visuel** qui dit au joueur « tu viens de comprendre quelque chose que personne ne t'a dit ». Le système est **purement réactif** — il ne crée aucune entité, ne place aucun lure, ne calcule aucune route — il **observe** les `SecretSlot` que Level System publie au boot (`level_active`), connecte chaque `SecretCollectVolume_NN.body_entered` à son handler interne, vérifie l'idempotence (un secret ne se collecte qu'une fois par run), et émet `secret_collected(self, tier)` SYNC dans le même `_physics_process` tick que le franchissement. Au MVP, Secret System gère 3-5 secrets par étage (Level F7 — divisor=3 nominal, plancher 3, plafond 5), 3 tiers de difficulté (1/2/3 = 5/10/15 cr via Credit F-CRD-2), et un état binaire UNCOLLECTED/COLLECTED persistant à travers les morts (preserved par Checkpoint snapshot post-MVP, jamais reset à la mort). Le système n'a **aucune** logique de récompense secondaire au MVP : pas de drop d'item, pas de teleport, pas de cinematic, pas de message UI — seulement un signal SYNC vers Credit + VFX + Audio. Cette austérité est volontaire : ajouter une couche de logique secondaire transformerait Secret System en énigme à résoudre, contradiction directe avec Pillar 4. Le système existe parce que sans lui, la promesse Pillar 4 n'a pas de support mesurable : c'est lui qui transforme « le joueur a réussi à atteindre la plateforme » en « le joueur a gagné quelque chose » dans le même tick que le contact, sans pause, sans pickup volume, sans course supplémentaire.

## Player Fantasy

**Le secret est l'engagement signé entre la tour et toi.** La tour n'a jamais demandé que tu cherches. Elle te montre simplement qu'il y a quelque chose là-haut — une lueur cyan accrochée à une corniche que ton dash actuel ne peut pas atteindre, un volume suspendu derrière trois wall-runs en série au-dessus d'un puits noir. Tu sais que tu peux y aller. Tu sais aussi que tu vas peut-être mourir trois fois en essayant. Et c'est exactement pour ça que tu y vas.

Quand ton corps cybernétique finit par franchir le bord du volume après cinq tentatives, **rien ne s'arrête**. Il n'y a pas de cinematic, pas de pop-up "Secret found 1/5", pas de slow-mo, pas de pause qui te demande de respirer. La tour a juste cédé : un son court et plus grave qu'un kill (un clac riche, une signature distincte du clac de combat — voir Audio System Rule), une lueur cyan qui s'éteint d'un coup à l'endroit où elle te narguait depuis trois minutes, ton compteur en haut à gauche qui saute de 47 à 57 d'un bloc avec une intensité visuelle légèrement plus forte que celle d'un kill, et tu es déjà reparti dans la salle suivante. **Tu n'as rien à lire. Tu n'as rien à valider.** Tu es juste plus riche, plus haut dans la tour, et tu sais — sans que personne ne te le dise — que ce crédit-là, tu ne l'aurais pas eu en tuant des grunts.

C'est cette **asymétrie viscérale** qui fait Pillar 4 : un kill, c'est un battement régulier (clac sec, +1 cr) ; un secret, c'est un riff isolé (clac plus profond, +5 ou +10 ou +15 cr selon le défi). L'écart de valeur n'est jamais une feuille de calcul — c'est une **reconnaissance ludique** que le jeu te donne au moment où ta main vient d'exécuter quelque chose que personne dans le tutoriel ne t'a appris à faire. Le tier 3, c'est le plus cher pour une raison physique : il a demandé le wall-run long enchaîné qu'il n'y a que 8% des joueurs qui maîtriseront jamais. Tu as appartenu à ces 8% pendant 3 secondes. La tour s'en souvient avec toi via le compteur.

Ce que le système ne fait **jamais** : pas de message "Secret unlocked: The Hidden Path of the Cyber-Ronin". Pas d'ajout de lore environnemental qui interrompt le flow. Pas de mini-cinematic de la caméra qui zoom sur le volume. Pas de carte mini-map qui se met à clignoter pour te montrer le secret suivant. Pas de mode "secret found, replay this room?" overlay. Pas de recompte à la fin de l'étage. **Le secret est noir sur blanc dans le compteur, point.** Toute friction visuelle ou narrative ajoutée transformerait l'expérience en chasse aux collectibles — l'anti-pattern explicite du Pillar 4 design test (`/Si pour trouver un secret il faut réfléchir, on refait le secret en exigeant de bouger.`).

**Le secret est aussi la promesse du retour.** Tu vas voir un lure cyan en l'air à 12 m du sol, et ton dash actuel te plafonne à 6 m. Tu sais que dans deux étages tu auras le double-jump. Tu vas revenir. **Cette promesse-là est silencieuse**, mais elle est imprimée dans la géométrie de la tour : chaque secret inaccessible est une reconnaissance que ton skill futur compte autant que ton skill présent. Le système ne te le dit pas avec un message ; il te le dit avec un volume placé exactement là où il faut, et un `required_ability: wall_run_long` que tu ne peux pas encore satisfaire mais que tu vas pouvoir satisfaire bientôt.

## Detailed Rules

### Core Rules

**R-SEC-01 — Authority boundaries**
Secret System est l'unique autorité de l'état COLLECTED/UNCOLLECTED d'un secret pendant
un run. Level System est l'autorité du placement spatial et de la composition d'un SecretSlot
(lure, volume, anchor, required_ability). Credit Economy est l'unique autorité du montant
crédité — elle consomme le signal `secret_collected(secret_node: Node, tier: int)` et applique
sa formule F-CRD-2. VFX System est l'autorité du visuel post-collect (éteindre le glow cyan).
Secret System n'a aucune connaissance de ces systèmes downstream — il émet et oublie.

**R-SEC-02 — Lifecycle 2-phases**
Secret System est un autoload. Il opère en deux phases exclusives :
- `INACTIVE` : de `_ready()` jusqu'à la réception du premier signal `level_active`. Aucun
  volume n'est connecté, aucun signal n'est émis. Les signaux `body_entered` éventuellement
  reçus avant `level_active` sont ignorés (guard `_is_active == false`).
- `ACTIVE` : de la réception de `level_active(etage_id, player_start)` jusqu'à la réception
  du prochain `level_active` ou du signal `state_changed(MENU)` (cleanup). En phase ACTIVE,
  les `SecretCollectVolume_NN.body_entered` sont connectés et le traitement est opérationnel.

**R-SEC-03 — Souscription au signal Level `level_active`**
Secret System souscrit au signal `level_active(etage_id: int, player_start: Vector3)` du Level
System dans son `_ready()` via `LevelSystem.level_active.connect(_on_level_active)`. La connexion
est SYNC (pas `CONNECT_DEFERRED`) pour garantir que les SecretSlots sont traités avant le premier
tick de physique où le joueur peut se déplacer. Un double `level_active` (re-enter même étage ou
étage suivant) déclenche un cleanup complet de l'étage précédent avant la re-souscription
(R-SEC-11).

**R-SEC-04 — Itération des SecretSlots et connexion body_entered**
À la réception de `level_active`, Secret System appelle
`LevelSystem.get_secret_slots() -> Array[SecretSlot]` et itère sur le tableau retourné. Pour
chaque `SecretSlot` valide (R-SEC-13), Secret System :
1. Lit `slot.lure` (SecretLureMarker_NN) pour extraire `lure.tier` (`@export var tier: int`).
2. Vérifie que `slot.collect_volume` (SecretCollectVolume_NN) est un Area3D valide sur le
   layer 5 (`LAYER_INTERACTIVE`).
3. Si le secret est déjà dans `_collected_secret_ids[volume.get_instance_id()] == true`, le
   connecte en lecture seule (aucun signal body_entered — volume reste dans la scène pour la
   persistance visuelle ; VFX a déjà éteint le glow lors de la collecte initiale).
4. Sinon, connecte `slot.collect_volume.body_entered` au Callable
   `_on_body_entered.bind(slot)` avec `flags = 0` (SYNC, pas CONNECT_DEFERRED).

**R-SEC-05 — Détermination du tier**
Le tier d'un secret est défini par `SecretLureMarker_NN.tier : int` (`@export`, valeur par
défaut 1). C'est une propriété éditoriale : le Level Designer encode la difficulté d'exécution
au moment de la pose dans l'éditeur Godot. Le tier n'est **pas** dérivé de `slot.required_ability`
— un même `required_ability: wall_run` peut correspondre à un tier 1 (wall-run unique court) ou
un tier 3 (enchaînement wall-run long + dash mid-air). L'algorithme ne peut pas distinguer ces
cas sans connaissance du parcours complet ; seul le designer le peut. Valeurs légales : `{1, 2,
3}`. Tier hors plage → `push_warning("SecretSystem: tier invalide %d sur %s, slot ignoré" %
[slot.lure.tier, slot.lure.name])` + skip du slot (aucun crédit, aucune connexion). Ce
comportement est conforme au garde AC-CRD-15 de Credit Economy côté consommateur.

**R-SEC-06 — Idempotence : un secret, un signal par run**
L'état de collection est maintenu dans `_collected_secret_ids : Dictionary[int, bool]` keyed
par `volume.get_instance_id()`. La clé `int` est l'instance_id GDScript de l'objet
`SecretCollectVolume_NN` — stable pendant toute la durée de vie du nœud dans la scène (les
volumes ne sont pas supprimés entre les morts au MVP, R-SEC-12). À chaque `body_entered`,
Secret System vérifie `_collected_secret_ids.get(volume.get_instance_id(), false)` avant tout
traitement. Si `true`, le signal est ignoré sans log (multi-trigger attendu, pas une erreur). Si
`false`, le secret est marqué collecté immédiatement AVANT l'émission du signal — mutation
d'état avant emit, pattern ADR-0005 D-8 — pour immuniser contre les re-entrants synchrones.

**R-SEC-07 — Émission `secret_collected` SYNC depuis callback physique**
Le signal `secret_collected(secret_node: Node, tier: int)` est émis SYNC (flags=0) depuis le
handler `_on_body_entered`, qui est un callback de `body_entered` (physics step, main thread
garanti par Godot). Si l'état du GSM n'est pas PLAYING au moment du callback (R-SEC-08),
l'émission est supprimée et `_collected_secret_ids` n'est pas modifié. Secret System ne
bufferise pas les pending collections — si le joueur entre dans un volume pendant RESPAWNING,
le tick est perdu. En pratique, le MovementController ne peut pas atteindre un volume en
RESPAWNING (GSM freeze movement) ; le guard existe par défense.

**R-SEC-08 — Garde GSM : no-op si state ≠ PLAYING**
Secret System observe le signal `state_changed(new_state: State)` du Game State Manager
(ADR-0007 D-10). L'autoload maintient `_current_gsm_state : State` synchrone. Dans le handler
`_on_body_entered`, la première instruction est :
```gdscript
if _current_gsm_state != GameStateManager.State.PLAYING:
    return
```
États bloquants : PAUSED, MENU, RESPAWNING, BOSS_DEFEATED. Aucun crédit ne peut être accordé
pendant ces états. Cette garde s'applique avant la vérification d'idempotence — `_collected_
secret_ids` n'est jamais modifié hors de l'état PLAYING.

**R-SEC-09 — Capability gate : géométrie implicite (Level + Movement)**
Secret System ne vérifie **pas** `slot.required_ability` contre les capacités actuelles du
joueur. La logique : si le joueur a physiquement déclenché `body_entered` sur le
`SecretCollectVolume_NN`, c'est qu'il a atteint le volume — par la capability requise ou par
un glitch. Dans les deux cas, le crédit est accordé. Vérifier la capability côté Secret System
imposerait une dépendance à Movement System (violation du pattern outbound-only ADR-0005 D-10
par analogie). Level System garantit physiquement que le volume est inatteignable sans
`required_ability` via la géométrie de l'étage. Les cas de glitch sont acceptés — Pillar 3
SECONDE CHANCE étend sa tolérance au skill gap, et punir un glitch réussi serait anti-Pillar 4.

**R-SEC-10 — Persistance Pillar 3 : collecté reste collecté au respawn (r2 B-1 — interface Checkpoint clarifiée)**
`_collected_secret_ids` survit aux morts. À `level_active`, Secret System peuple le dictionnaire
depuis le snapshot Checkpoint actif (liste d'instance_ids déjà collectés dans cet étage + les
étages précédents du run). Les secrets collectés avant une mort ne sont pas re-collectables après
respawn. Ce comportement est intentionnel — Pillar 3 SECONDE CHANCE garantit que le joueur ne
perd pas ce qu'il a acquis par compétence. **MVP** : Checkpoint System maintient la liste
`collected_secret_ids` en mémoire (session-scoped, pas de disque). À `level_active` :

- **Lecture (Secret hydrate depuis Checkpoint)** : Secret appelle `checkpoint.get_collected_secrets() -> Array[int]` pour peupler `_collected_secret_ids`.
- **Écriture (Secret injecte son état dans Checkpoint au moment du checkpoint latch)** : Secret expose `Secret.get_collected_ids() -> Array[int]` que Checkpoint lit. Le verbe d'**appel de Checkpoint vers Secret** s'appelle **`inject_collected_secrets(ids: Array[int])`** (renommé r2 B-1 — ex `restore_collected_secrets`) — Secret reçoit cette injection comme alternative à la lecture pull. Le nom `inject_*` clarifie que c'est Secret qui *reçoit* l'injection, pas Checkpoint qui *restore* (ambiguïté nominale r1).

**Post-MVP** : Checkpoint snapshot persiste via `SaveLoad.save_int_array("collected_secret_ids", ...)` — voir aussi R-SEC-16 pour l'invariant `instance_id` stabilité MVP. Reset **uniquement** à `request_new_run()` (signal GSM) — dictionnaire vidé et Checkpoint snapshot purgé.

> **[GATE r2 B-1] amendement Checkpoint r2 requis avant `/create-epics secret-system`** : le Checkpoint GDD r1 (In Design) ne liste pas Secret dans §Interactions ni les verbes `get_collected_secrets()` / `inject_collected_secrets(ids)`. Amendement Checkpoint r2 doit ajouter une ligne §Interactions Secret System bidirectionnel + Published API ces deux verbes. Sans cet amendement, AC-SEC-12 + AC-SEC-33 sont non-testables et R-SEC-10 est non-implémentable.

**R-SEC-11 — Cleanup à la transition de scène**
À la réception d'un nouveau signal `level_active` (nouvel étage ou re-enter), Secret System
exécute le cleanup suivant AVANT d'itérer les nouveaux SecretSlots :
1. Déconnecte tous les Callables `_on_body_entered.bind(slot)` connectés lors de l'itération
   précédente (R-SEC-04), pour chaque `slot` dans `_slots_this_level`.
2. Vide `_slots_this_level : Array[SecretSlot]`.
3. Ne vide PAS `_collected_secret_ids` — la persistance inter-étage est intentionnelle (R-SEC-10).
4. Passe immédiatement en phase ACTIVE pour le nouvel étage.
Double `level_active` dans le même tick (bug Level System) : la déconnexion d'un signal non
connecté est un no-op Godot — le cleanup est idempotent.

**R-SEC-12 — Pas de queue_free, pas de drop, pas de cinematic au MVP**
Secret System ne supprime jamais un `SecretCollectVolume_NN` ni un `SecretLureMarker_NN` de
la scène. Il ne spawne aucun item, ne téléporte pas le joueur, ne déclenche aucune cinematic,
n'envoie aucun message UI. Ces responsabilités appartiennent aux systèmes aval (VFX éteint le
glow, Audio joue le clac, HUD pulse le compteur) via le signal `secret_collected`. Toute
extension Tier 2+ (cinematic, drop) passe par un nouveau signal ou un payload étendu — jamais
par injection de logique dans Secret System.

**R-SEC-13 — Comportement défensif sur slot mal formé**
Lors de l'itération R-SEC-04, chaque SecretSlot est validé :
- `slot.lure == null` ou `slot.collect_volume == null` → `push_error("SecretSystem: slot
  incomplet lure=%s volume=%s — ignoré" % [str(slot.lure), str(slot.collect_volume)])` + skip.
  Pas de crash.
- `slot.collect_volume` n'est pas un `Area3D` → `push_error` + skip.
- `slot.lure.tier` hors `{1, 2, 3}` → `push_warning` + skip (R-SEC-05).
- Tableau `get_secret_slots()` vide → comportement normal (ACTIVE sans slots connectés). Level
  F7 impose ≥ 3 secrets par étage : si le tableau retourne 0 éléments, c'est un bug Level System,
  pas un cas d'erreur Secret System.

**R-SEC-14 — Protection contre double souscription `level_active`**
La connexion du signal `level_active` est établie une seule fois dans `_ready()` avec
`CONNECT_ONE_SHOT = false` et sans `CONNECT_PERSIST`. Aucun `connect()` supplémentaire n'est
effectué dans `_on_level_active`. Si un double `level_active` arrive dans le même tick, R-SEC-11
cleanup est idempotent et la re-itération produit un état cohérent.

**R-SEC-15 — Réservation Tier 2+ : signal `room_cleared` séparé**
Credit Economy définit `SourceKind.ROOM_CLEAR_BONUS = 5` (réservé, non implémenté MVP). Si une
feature "room clear bonus" est designée en Tier 2+, elle sera émise via un signal séparé
`room_cleared(room_node: Node, bonus: int)` — elle ne sera pas encodée dans `secret_collected`
via un `tier = 4`. Ce cloisonnement garantit que la sémantique de `tier` reste `{1, 2, 3}` sur
toute la durée de vie du MVP, et que Credit Economy n'a pas à gérer un tier hors plage silencieux.

**R-SEC-16 — Invariant instance_id stability (r2 B-2 — pré-contrat Level/VFX MVP)**
La clé d'idempotence MVP `volume.get_instance_id()` (R-SEC-06) est **session-scoped et stable
uniquement tant que le nœud `SecretCollectVolume_NN` existe sans interruption dans le scene
tree** (Godot réassigne les `instance_id` à chaque instanciation de nœud). Pour que la persistance
inter-respawn intra-étage fonctionne, **Level System, VFX System, et tout autre consommateur de
`SecretCollectVolume_NN` s'interdisent de `queue_free()` ou de réinstancier ces nœuds pendant
un run actif (`_is_active == true`)**. C'est un **pré-contrat externe** — Secret System n'est
pas responsable de cette stabilité ; il l'assume comme garantie fournie par Level/VFX. Conséquence
attendue d'une violation : secret potentiellement non-collecté (instance_id changé après respawn,
ne match plus l'entrée dans `_collected_secret_ids`) ou double-collecté silencieusement (nouveau
instance_id traité comme nouveau secret). Cas légitimes où les volumes sont supprimés :
(a) `state_changed(MENU)` — fin de run, OK car `_collected_secret_ids` purgé au prochain
`request_new_run()` ; (b) `request_scene_transition` (transition étage N→N+1) — OK car les
volumes de l'étage N+1 sont nouveaux par construction (R-SEC-11 cleanup). **Cas interdit** : Level
ou VFX ne doit jamais `queue_free()` un volume **pendant le run actif d'un même étage** (entre
deux `level_active` du même `etage_id`). Cet invariant est documenté ici pour propagation Level
GDD r5 §Anti-dependencies + VFX GDD futur §Anti-dependencies. Tier 2+ migration : voir OQ-SEC-2
(`uuid_export` stable cross-version) — la migration `IDEMPOTENCE_KEY_STRATEGY` rend cet invariant
caduc en Tier 2+ post-MVP.

---

### States and Transitions

| Phase | État | Déclencheur d'entrée | Déclencheur de sortie | Comportement |
|-------|------|---------------------|----------------------|--------------|
| Pré-niveau | `INACTIVE` | `_ready()` autoload init | `level_active` reçu du Level System | Aucun slot connecté. `body_entered` rejetés (guard `_is_active == false`). `_collected_secret_ids` vide (nouveau run) ou peuplé depuis Checkpoint snapshot (run repris après mort). |
| En-jeu | `ACTIVE` | `level_active(etage_id, player_start)` | `level_active` suivant (cleanup R-SEC-11) ou `state_changed(MENU)` | Slots connectés. `body_entered` traités sous garde GSM R-SEC-08. Signal `secret_collected` émis SYNC sur franchissement valide. `_collected_secret_ids` mis à jour avant emit. |
| Sous-état de ACTIVE | `ACTIVE / PAUSED` | `state_changed(PAUSED)` | `state_changed(PLAYING)` | Slots restent connectés. `body_entered` callbacks reçus mais rejetés par garde R-SEC-08. `_collected_secret_ids` non modifié. |
| Sous-état de ACTIVE | `ACTIVE / RESPAWNING` | `state_changed(RESPAWNING)` | `state_changed(PLAYING)` | Idem PAUSED — garde R-SEC-08 active. En pratique MovementController freeze interdit l'atteinte d'un volume. Guard par défense. |
| Sous-état de ACTIVE | `ACTIVE / BOSS_DEFEATED` | `state_changed(BOSS_DEFEATED)` | (terminal au MVP) | Garde R-SEC-08 active. Aucune collection possible après boss final. |
| Fin de run | `INACTIVE` (reset) | `request_new_run()` (signal GSM) | `level_active` du nouvel run | `_collected_secret_ids` vidé. `_slots_this_level` vidé. Tous signaux `body_entered` déconnectés. Checkpoint snapshot purgé. `_is_active = false`. |

**Invariants d'état :**
- `_collected_secret_ids` n'est jamais modifié pendant PAUSED, RESPAWNING, MENU, BOSS_DEFEATED.
- La mutation `_collected_secret_ids[id] = true` se produit AVANT l'émission de `secret_collected`
  dans le même call stack (ADR-0005 D-8).
- `slot.lure.tier` est immuable pendant un étage — un `@export` Godot ne peut pas changer à runtime.

---

### Interactions with Other Systems

| Système | Direction | Interface | Détails |
|---------|-----------|-----------|---------|
| **Level System** (APPROVED r3) | Amont — Secret reçoit | Signal `level_active(etage_id: int, player_start: Vector3)` + getter `get_secret_slots() -> Array[SecretSlot]` | Secret System souscrit à `level_active` dans `_ready()`. À chaque réception, appelle `get_secret_slots()` et itère les SecretSlots. Contrat : Level F7 garantit 3-5 slots par étage, au moins 1 `required_ability: wall_run` (AC-LVL-46). Secret System consomme `slot.lure` (tier @export) + `slot.collect_volume` (Area3D layer 5). Tuple NN strict garanti par Level : LureMarker_NN ↔ CollectVolume_NN ↔ Anchor_NN indices identiques. |
| **Credit Economy** (Designed r1) | Aval — Credit écoute | Signal `secret_collected(secret_node: Node, tier: int)` SYNC, flags=0 | Secret System émet ; Credit Economy consomme et crédite `BASE_SECRET_CREDIT × tier` (F-CRD-2). Contrat confirmé — clôture OQ-CRD-1 Credit Economy : `tier ∈ {1, 2, 3}`, signal émis depuis callback physique main thread. Tier invalide filtré en amont par R-SEC-05 — Credit ne devrait jamais recevoir un tier hors plage depuis Secret System. |
| **Game State Manager** (APPROVED r1) | Amont — Secret observe | Signal `state_changed(new_state: State)` (ADR-0007 D-10) + verb `request_new_run()` | Secret System maintient `_current_gsm_state` synchrone pour la garde R-SEC-08. `request_new_run()` → reset complet `_collected_secret_ids` (R-SEC-10). Secret System ne modifie jamais l'état GSM. |
| **VFX System** (Not Started) | Aval — VFX s'auto-connecte | Signal `secret_collected(secret_node: Node, tier: int)` | VFX System se connecte au signal depuis son propre `_ready()` (outbound-only — Secret ne connaît pas VFX). Sur réception : éteint le glow cyan du `SecretLureMarker_NN` référencé via `secret_node`. Secret System n'a aucune responsabilité visuelle. |
| **Audio System** (APPROVED r2.1) | Aval — Audio s'auto-connecte | Signal `secret_collected(secret_node: Node, tier: int)` | Audio System joue le clac secret (signature distincte du clac combat — Audio GDD Rule). Connexion self-managed depuis Audio `_ready()`. Secret System ne connaît pas Audio. |
| **Save/Load System** (Not Started) | Aval — persist post-MVP | `SaveLoad.save_int_array("collected_secret_ids", ids)` | MVP : état session-only via Checkpoint snapshot in-memory. Post-MVP : Secret System appelle Save/Load dans le handler `state_changed(MENU)` pour persister `collected_secret_ids` entre sessions. Format : `Array[int]` d'instance_ids. |
| **Checkpoint System** (Not Started — **r2 B-1 [GATE] amendement Checkpoint r2 requis**) | Bidirectionnel — snapshot | Getter `checkpoint.get_collected_secrets() -> Array[int]` (Secret lit au `level_active`) + setter `Secret.inject_collected_secrets(ids: Array[int])` (Checkpoint pousse la liste vers Secret au moment du restore — verbe **renommé r2 B-1** depuis `restore_collected_secrets` pour clarifier la direction d'appel) + getter `Secret.get_collected_ids() -> Array[int]` (Checkpoint lit l'état courant au moment du checkpoint latch) | MVP path : Checkpoint fournit la liste `collected_secret_ids` à Secret à `level_active` (R-SEC-10). **Interface PROVISOIRE [GATE]** : Checkpoint GDD r1 (In Design) ne liste actuellement pas Secret dans §Interactions ni ces verbes — amendement Checkpoint r2 requis avant `/create-epics secret-system`. AC-SEC-12 + AC-SEC-33 sont conditionnés à cet amendement. |
| **Movement System** (APPROVED r3) | Cousin — aucune interface directe | (aucune) | Movement gère implicitement la capability gate : le joueur ne peut pas physiquement atteindre un `SecretCollectVolume_NN` sans la `required_ability` encodée dans la géométrie de l'étage (R-SEC-09). Secret System ne dépend pas de Movement et ne l'interroge jamais. Absence de couplage intentionnelle. |

## Formulas

Secret System est un détecteur d'événement, pas un système calculatoire — il contient une seule formule canonique (référence vers Credit Economy F-CRD-2) et une formule descriptive de yield attendu pour valider la calibration MVP. Toute la math monétaire vit dans Credit Economy.

### F-SEC-1 : Crédit délégué par tier (référence vers Credit Economy F-CRD-2)

Formule de référence — Secret System ne calcule **pas** le crédit, il transmet `tier` au signal `secret_collected(secret_node, tier)` et Credit Economy applique sa propre formule.

```
credits = BASE_SECRET_CREDIT × secret.tier  (Credit GDD F-CRD-2)
```

**Variables (rappel) :**

| Variable | Symbol | Type | Range | Description | Source de vérité |
|----------|--------|------|-------|-------------|------------------|
| `BASE_SECRET_CREDIT` | B | int | constant `5` | Tuning Knob Credit Economy | `design/gdd/credit-economy-system.md` F-CRD-2 |
| `secret.tier` | t | int ∈ {1, 2, 3} | — | Tier de difficulté MVP | `SecretLureMarker_NN.tier` (`@export`) — autorité Secret System |
| `credits` | c | int | 5 / 10 / 15 | Crédits attribués par Credit Economy | `design/gdd/credit-economy-system.md` F-CRD-2 |

**Output Range :** `5 ≤ credits ≤ 15` strictement (3 valeurs discrètes). Toute valeur hors plage indique un bug : tier invalide non filtré par R-SEC-05 (Secret System doit filtrer en amont) ou modification illégale de `BASE_SECRET_CREDIT`. Comportement attendu : Credit ignore + push_warning (AC-CRD-15). Secret System filtre en amont (R-SEC-05) — ce path défensif Credit ne devrait jamais s'activer en pratique.

**Example :** Secret tier=2, Credit reçoit `secret_collected(volume_node, 2)` → applique `5 × 2 = 10 cr`, `total_credits` passe de 47 à 57, `credits_changed.emit(57, +10, SourceKind.SECRET)` SYNC.

---

### F-SEC-2 : Yield attendu de secrets par session (validation MVP)

Formule descriptive — pas un calcul à l'exécution, un budget de calibration pour valider que la promesse Pillar 4 et la promesse Credit F-CRD-4 (1-2 upgrades par session) restent cohérentes.

```
secret_yield_session = Σ (BASE_SECRET_CREDIT × tier_i)  pour i ∈ secrets_collectés_session
```

**Variables :**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `secrets_collectés_session` | S | Array[int] | size ∈ [0, 5] par étage, 1-2 étages par session typique | Tier de chaque secret collecté pendant la session |
| `tier_i` | tᵢ | int ∈ {1, 2, 3} | — | Tier du i-ème secret collecté |
| `secret_yield_session` | Y_s | int | 0 à 75 (cap théorique : 5 secrets × tier 3 × 5 cr = 75 par étage × 2 = 150 max session) | Total crédits secrets gagnés dans la session |

**Output Range pratique :**

| Profil joueur | Secrets/étage | Tier mix | Yield/étage | Yield session 2 étages |
|---------------|---------------|----------|-------------|------------------------|
| Combat-only (skip secrets) | 0 | — | 0 cr | 0 cr |
| Casual (3 secrets faciles) | 3 | 1+1+2 | 5+5+10 = 20 cr | 40 cr |
| Normal (3 secrets mix) | 3 | 1+2+2 | 5+10+10 = 25 cr | 50 cr |
| Expert (4 secrets dont T3) | 4 | 1+2+2+3 | 5+10+10+15 = 40 cr | 80 cr |
| Completionist (5 secrets, 1+ T3) | 5 | 2+2+2+3+3 | 10+10+10+15+15 = 60 cr | 120 cr |

**Worked example — étage 2 normal session :**
- 12 grunts × 1 cr = 12 cr (Credit F-CRD-4)
- 4 secrets : T1 + T2 + T2 + T3 = 5 + 10 + 10 + 15 = **40 cr**
- `session_yield_etage_2 = 12 + 40 = 52 cr`
- Cohérent avec Credit F-CRD-4 worked example étage 2 (52 cr → upgrade n=2 à 40 cr atteignable).

**Validation Pillar 4 — ratio secret/kill par session normale :**
- Session 2 étages normal : kills = 8+12 = 20 cr ; secrets normal mix = 25+40 = 65 cr
- Ratio secret/kill = 65/20 = **3.25:1** sur la session
- Conforme à la justification Credit F-CRD-2 : « ratio 5:1 minimum **par secret individuel** » et « secret >> combat sur session ». La promesse Pillar 4 reste mathématiquement valide.

## Edge Cases

### Comportements défensifs runtime

- **EC-SEC-01 — body_entered avant `level_active`** : Secret System reçoit un `body_entered` alors que `_is_active == false` (autoload prêt mais Level pas encore booté). **Outcome** : ignore silencieusement, aucun signal émis, aucune mutation. Cas théorique uniquement (Level boote avant Player spawn par contrat ADR-0011).

- **EC-SEC-02 — body_entered pendant `state_changed(PAUSED)`** : Joueur entre dans un volume puis le menu pause s'ouvre, le callback Godot arrive après le state_changed. **Outcome** : R-SEC-08 garde refuse, `_collected_secret_ids` non modifié. Le signal `secret_collected` n'est pas émis. Si le joueur sort puis re-entre après resume, le secret peut être collecté à ce moment-là (état UNCOLLECTED préservé).

- **EC-SEC-03 — body_entered multiple sur le même volume dans la même frame** : Joueur traverse un volume large à haute vitesse (dash + double_jump combiné), Godot peut émettre 2 `body_entered` consécutifs sur le même volume si le `CollisionShape3D` du joueur entre par deux faces simultanées. **Outcome** : R-SEC-06 garantit qu'un seul `secret_collected` est émis (mutation `_collected_secret_ids` AVANT emit, pattern ADR-0005 D-8). Le second body_entered hit la garde idempotence et est silencieusement ignoré.

- **EC-SEC-04 — body_entered sur volume déjà collecté (multi-trigger inter-passage)** : Joueur revient sur un volume déjà collecté lors d'un autre passage. **Outcome** : R-SEC-06 ignore sans log (multi-trigger attendu). Aucun crédit, aucun feedback (le glow est déjà éteint, le clac ne rejoue pas).

- **EC-SEC-05 — Secret tier hors plage `{1, 2, 3}`** : Level Designer met `tier = 0`, `tier = 4`, ou `tier = -1` sur un `SecretLureMarker_NN` par erreur d'authoring. **Outcome** : R-SEC-05 + R-SEC-13 → `push_warning("SecretSystem: tier invalide %d sur %s, slot ignoré")` + skip lors de l'itération à `level_active`. Le slot n'est jamais connecté, le volume reste inerte (`body_entered` rejeté car non connecté). Aucun crédit accordé. Ce cas doit être détecté par le lint pré-build de Level (recommandation : élever R-SEC-13 en CI gate via lint).

- **EC-SEC-06 — SecretSlot mal formé (lure null OU collect_volume null)** : Level retourne un slot incomplet (bug authoring : Marker3D supprimé sans cleanup du tuple). **Outcome** : R-SEC-13 `push_error` + skip. Slot ignoré. Pas de crash, pas de connexion. Le lint Level (AC-LVL-53) doit attraper ce cas avant runtime.

- **EC-SEC-07 — `get_secret_slots()` retourne tableau vide** : Étage MVP avec aucun secret placé (bug Level F7 — minimum 3 attendu). **Outcome** : Phase ACTIVE sans slots connectés, comportement nominal (aucune collection possible). Secret System n'émet pas d'erreur — c'est un bug Level System à attraper en amont (lint étage). Si ce cas atteint runtime, l'étage est jouable mais sans secrets.

- **EC-SEC-08 — Double `level_active` même tick** : Bug Level émet deux fois `level_active` dans le même `_physics_process`. **Outcome** : R-SEC-11 cleanup idempotent (déconnexion d'un signal non-connecté = no-op Godot). Re-itération produit un état cohérent. Performance : temps cumulé de 2× cleanup + 2× iteration ; acceptable car cas théorique (bug Level).

- **EC-SEC-09 — `level_active` reçu pendant que joueur est dans un volume** : Très rare — implique une transition de scène alors que le PlayerCollider chevauche un Area3D. **Outcome** : Le cleanup R-SEC-11 déconnecte les anciens body_entered avant la nouvelle itération. Aucun signal pour l'étage précédent n'est émis. Le nouveau volume doit attendre un body_exited puis body_entered pour déclencher (Godot ne re-émet pas body_entered si le body est déjà à l'intérieur au moment de la connexion). Acceptable au MVP — `request_scene_transition` GSM repositionne le joueur à `player_start`, sortant de tout volume.

- **EC-SEC-10 — `request_new_run` pendant ACTIVE** : Joueur quitte au menu via GSM `request_new_run()`. **Outcome** : R-SEC-10 reset complet — `_collected_secret_ids` vidé, Checkpoint snapshot purgé. Tous les secrets redeviennent collectables au prochain run. Comportement intentionnel.

### Incohérences cross-system

- **EC-SEC-11 — `secret_collected` émis avec `secret_node = null`** : Cas théorique où un slot est libéré entre la connexion et le callback (bug Level retire un volume runtime). **Outcome** : Le signal embarque un payload null ; les consumers (Credit, VFX, Audio) doivent tolérer `secret_node == null` côté handler (Credit applique le crédit basé sur tier, VFX skip glow off, Audio joue le clac sans positional). Recommandation : Credit GDD à amender Sprint A pour expliciter ce cas. Au MVP, considéré théorique — Level ne supprime jamais de volume runtime.

- **EC-SEC-12 — Joueur skipe un secret par glitch (capability gate physique contournée)** : Joueur trouve un sweet spot dash + jump pour atteindre un volume `required_ability: wall_run_long` sans avoir le wall_run. **Outcome** : R-SEC-09 — Secret System ne vérifie pas la capability, le crédit est accordé. Comportement intentionnel (anti-Pillar 3 de punir un skill réussi). Si playtest révèle des glitchs systématiques sur un volume, Level Designer ré-architecture la géométrie — pas un cas Secret System.

- **EC-SEC-13 — Save corrompue avec `collected_secret_ids` invalides** (post-MVP) : Save/Load injecte une liste d'instance_ids qui ne correspondent à aucun volume du nouvel étage. **Outcome** : Les ids fantômes sont conservés dans `_collected_secret_ids` (ne causent aucun bug — keys orphelines), les volumes réels de l'étage ne matchent pas les ids fantômes et restent collectables. Comportement nominal (saves cross-version : les ids fantômes meurent silencieusement). Au MVP, le snapshot est session-only, ce cas n'apparaît pas.

- **EC-SEC-14 — Ordre body_entered vs body_exited rapide (joueur en ricochet)** : Joueur entre, sort, re-entre dans un volume en moins d'un tick physique. **Outcome** : Godot émet body_entered puis body_exited puis body_entered. Le premier body_entered déclenche la collection (R-SEC-06 marque `_collected_secret_ids[id] = true`), le second body_entered hit la garde idempotence. Comportement nominal.

### Anti-patterns d'authoring (level-designer)

Ces cas ne sont pas des edge cases runtime mais des erreurs d'authoring Level System. Listés ici parce que Secret System se comporte défensivement mais ne peut pas les *détecter* programatiquement — ils nécessitent un lint Level ou un playtest.

- **EC-SEC-AP-1 — CollectVolume au sol ou en couloir de passage** : Volume positionné à hauteur de marche (< 1.5 m) sur le chemin critique. Conséquence runtime : collection involontaire, casse Pillar 1 FLOW. **Recommandation** : Tuning Knob `MIN_VOLUME_HEIGHT_ABOVE_FLOOR = 2.0 m` (G-3) à valider via lint Level pré-build.

- **EC-SEC-AP-2 — Lure derrière une porte ou trigger d'interaction** : Lure caché tant qu'un mécanisme d'activation n'est pas franchi. Conséquence : transforme le secret en énigme (violation Pillar 4). **Recommandation** : lint Level interdit toute géométrie occlusive entre le lure et les points de passage du chemin critique.

- **EC-SEC-AP-3 — required_ability=none avec volume sur chemin critique** : Volume facile sans déviation visible du path nominal. Devient un pickup dissimulé, pas un secret. **Recommandation** : lint Level vérifie angle de bifurcation ≥ 30° ou delta hauteur ≥ 2 m du chemin critique.

- **EC-SEC-AP-4 — Deux SecretCollectVolume colocalisés (séparation < 3 m horizontal et < 4 m vertical)** : Risque de double body_entered race condition lors d'un passage rapide. Bien que R-SEC-06 garantit l'idempotence par volume individuel, deux secrets distincts collectés simultanément peuvent brouiller le feedback audio (deux clacs superposés) — viole la signature audio Pillar 4. **Recommandation** : lint Level impose séparation horizontale ≥ 3 m OU verticale ≥ 4 m entre deux volumes même salle.

- **EC-SEC-AP-5 — Lure non-visible depuis le chemin nominal** : Lure derrière un mur ou en dehors du frustum naturel du joueur. Lure invisible = bruit authoring. **Recommandation** : test playtest manuel obligatoire pour chaque secret.

- **EC-SEC-AP-6 — required_ability incohérent avec géométrie** : `required_ability: wall_run` déclaré mais path nécessite wall_run_long, OU `required_ability: dash` mais path requiert un double_jump. Joueur sans la vraie capability croit pouvoir tenter et meurt en vain. **Recommandation** : test playtest obligatoire avec chaque ability subset, en particulier le set MVP "no abilities" (étage 1 vanilla).

- **EC-SEC-AP-7 — `wall_run_long` dans archetype Traversal** : Traversal R-2.A ceiling [3.5, 4.5] m + 0..1 mur wall-run incompatible avec un path wall_run_long structurel. **Recommandation** : lint Level interdit `required_ability: wall_run_long` sauf dans `Shaft` ou `SecretHub`.

## Dependencies

### Hard dependencies (Secret System ne peut pas fonctionner sans)

| Système | Status | Interface canonique | Direction |
|---------|--------|---------------------|-----------|
| **Level System** | APPROVED r3 r4 ✅ | `level_active(etage_id, player_start)` signal + `get_secret_slots() -> Array[SecretSlot]` getter | Amont — Secret consomme |
| **Game State Manager** | APPROVED r1 ✅ | `state_changed(new_state: State)` signal (ADR-0007 D-10) + `request_new_run()` verb | Amont — Secret observe |
| **Credit Economy** | Designed r1 ✅ | `secret_collected(secret_node: Node, tier: int)` SYNC signal | Aval — Secret produit |

### Soft dependencies (Secret System fonctionne sans, mais expérience dégradée)

| Système | Status | Interface canonique | Direction |
|---------|--------|---------------------|-----------|
| **VFX System** | Not Started | Self-connect au signal `secret_collected` | Aval — passive listener |
| **Audio System** | APPROVED r2.1 ✅ | Self-connect au signal `secret_collected` | Aval — passive listener |
| **HUD System** | Not Started | Indirect via Credit `credits_changed(total, delta, SECRET)` | Aval — passive listener (chaîne) |
| **Checkpoint System** | Not Started — **r2 B-1 [GATE] amendement Checkpoint r2 requis** | Bidirectionnel : `Secret.get_collected_ids() -> Array[int]` (Checkpoint lit) + `Secret.inject_collected_secrets(ids: Array[int])` (Checkpoint écrit, renommé r2 depuis `restore_*`) + `checkpoint.get_collected_secrets() -> Array[int]` (Secret lit au `level_active`) | Bidirectionnel — **PROVISOIRE pending Checkpoint r2** |
| **Save/Load System** | Not Started | `save_int_array("collected_secret_ids", ...)` + `load_int_array(...)` post-MVP | Aval — passive write/read |

### Cousins (pas d'interface directe, contraintes implicites partagées)

| Système | Status | Contrainte partagée |
|---------|--------|---------------------|
| **Player Movement System** | In Review r3 | La capability gate (R-SEC-09) repose sur la géométrie Level, pas sur un check Movement. Secret System ne dépend pas de Movement. Movement ignore Secret. |
| **Player Combat System** | APPROVED r6 | Aucun couplage direct. Secret n'interfère pas avec swing katana ; Combat n'interfère pas avec body_entered Area3D layer 5. |
| **Enemy System** | APPROVED r2 | Aucun couplage direct. Un grunt placé près d'un volume ne change pas la sémantique Secret. La pression combat sur un secret est un choix d'authoring Level (R-2.6 SecretHub). |

### Bidirectional check (consistency cross-GDD)

- **Level System GDD §Interactions Table** liste Secret comme aval avec `get_secret_slots()` + `level_active` ✅ (déjà documenté dans Level GDD)
- **Credit Economy GDD §Detailed Rules R-9** liste `secret_collected` comme contrat d'entrée provisoire OQ-CRD-1 ✅ (Secret System ferme cette OQ — voir §Open Questions)
- **GSM GDD §Interactions** liste les consumers de `state_changed` : Secret doit être ajouté via amendement GSM r2 (recommandation Phase 5 propagation)
- **Audio System GDD r2.1** : Audio écoute `secret_collected` mais le clac secret n'est pas explicitement listé dans Audio Rule 11. **Recommandation amendement Audio r2.2** : ajouter Rule entrée pour le clac secret (signature distincte de `combat_kill`, bus `combat_kill` ou nouveau bus `secret_collect` à trancher avec audio-director).
- **VFX System GDD** : Not Started — le contrat "VFX éteint le glow cyan sur réception `secret_collected`" doit être codé dans VFX GDD futur.

### Provisional contracts (à confirmer lors du design des systèmes Not Started)

- **Checkpoint System** (#8) : interface `checkpoint.get_collected_secrets()` (Secret lit) + `Secret.inject_collected_secrets(ids: Array[int])` (Checkpoint écrit, **renommé r2 B-1** depuis `restore_collected_secrets` pour clarté direction) + `Secret.get_collected_ids()` (Checkpoint lit) PROVISOIRE. Si Checkpoint choisit une autre forme (ex : snapshot opaque + struct typée), un amendement Secret r3 sera requis. Marqueur : `OQ-SEC-1`. **[GATE r2 B-1]** — amendement Checkpoint r2 requis avant `/create-epics secret-system` pour ajouter Secret System dans Checkpoint §Interactions et Published API.
- **Save/Load System** (#3) : signature `save_int_array(key, Array[int])` + `load_int_array(key, default: Array[int])` PROVISOIRE. Marqueur : `OQ-SEC-2`. Voir aussi R-SEC-16 invariant instance_id MVP — migration `uuid_export` Tier 2+ rend l'invariant caduc.
- **VFX System** (#19) : self-connect au signal — pattern outbound-only confirmé. **Anti-dependency invariant R-SEC-16** : VFX ne doit jamais `queue_free()` un `SecretCollectVolume_NN` pendant `_is_active == true`.
- **HUD System** (#17) : aval indirect via `credits_changed`. Aucune dépendance directe Secret↔HUD.

### Gates pré-`/create-epics` (propagation cross-GDD requise)

| Gate | GDD cible | Action requise | Bloque |
|------|-----------|---------------|--------|
| **B-1** | Checkpoint GDD r2 | Ajouter Secret dans §Interactions (3 verbes : `checkpoint.get_collected_secrets() / Secret.inject_collected_secrets(ids) / Secret.get_collected_ids()`) + §Published API. ~5 lignes. | `/create-epics secret-system` |
| **R-SEC-16** | Level GDD r5 §Anti-dependencies | Documenter "Level interdit `queue_free()` sur `SecretCollectVolume_NN` pendant run actif". 2 lignes. | Implémentation Level r5 |
| **R-SEC-16** | VFX GDD futur §Anti-dependencies | Documenter même invariant côté VFX. À spec lors de `/design-system vfx-system`. | `/create-epics vfx-system` |

### Anti-dependencies (interdites)

- Secret System ne dépend **jamais** de :
  - **Player Movement System** (capability gate géré par géométrie Level, pas par check de capability runtime).
  - **VFX System** (autorité visuelle déléguée, pas inversée).
  - **HUD System** (HUD est aval indirect via Credit).
- Secret System ne **lit jamais** d'état d'autres systèmes pour décider de la collection — la décision est entièrement locale (body_entered + idempotence + GSM state).

## Tuning Knobs

Secret System a peu de variables tunables — la plupart de la balance vit dans Credit Economy (BASE_SECRET_CREDIT) et Level System (SECRET_DENSITY_DIVISOR, cap par archetype). Les knobs ci-dessous sont **internes Secret** ou **authoring guidelines** pour Level Designers.

### Knobs runtime (Secret System) — data-driven external (r2 B-3)

> **r2 B-3 fix** — Conformément à CLAUDE.md « Gameplay values must be data-driven (external config), never hardcoded », les 2 knobs runtime ci-dessous sont définis dans **`src/gameplay/secret/secret_constants.gd`** (script GDScript autoload constants, pattern aligné avec `input_constants.gd`/`level_constants.gd` du studio). Le fichier expose des `const` typés strict avec safe range commenté. Tier 2+, ces constantes peuvent migrer vers `assets/data/secret_config.tres` (Resource Godot) si tuning playtest-driven sans recompilation devient nécessaire — la migration est transparente puisque les call sites lisent via API publique du module constants.

**Fichier source de vérité** : `src/gameplay/secret/secret_constants.gd`

```gdscript
class_name SecretConstants extends RefCounted

# r2 B-3 — Tuning Knobs runtime data-driven (CLAUDE.md compliance)
# Safe ranges documentés ; modification > range = ADR amendment requis.

## R-SEC-06 — clé d'idempotence Dictionary[int|StringName, bool] _collected_secret_ids.
## MVP : "instance_id" (session-scoped, requires R-SEC-16 invariant Level/VFX).
## Tier 2+ migration : "uuid_export" (stable cross-version, débloque Save/Load disque OQ-SEC-2).
## Safe range : {"instance_id", "scene_path", "uuid_export"}.
const IDEMPOTENCE_KEY_STRATEGY: StringName = &"instance_id"

## R-SEC-02 — guard de phase. Si false, body_entered traités en INACTIVE (DEBUG ONLY).
## Safe range : {true, false} mais false interdit en prod.
const IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE: bool = true
```

| Knob | Valeur MVP | Type | Range sûr | Ce qu'il contrôle | Ce qui casse hors range | Source de vérité |
|------|------------|------|-----------|-------------------|--------------------------|------------------|
| `IDEMPOTENCE_KEY_STRATEGY` | `&"instance_id"` | StringName | `{&"instance_id", &"scene_path", &"uuid_export"}` | Clé du `Dictionary[int|StringName, bool] _collected_secret_ids`. MVP : `instance_id` (R-SEC-06 + R-SEC-16 invariant). Tier 2+ alternatives : `scene_path` (resilient à recompose Level), `uuid_export` (export sur LureMarker, le plus robuste cross-version). | Changer la stratégie en cours de version casse les saves Tier 2+. Plan : promote vers `uuid_export` au moment de Save/Load post-MVP (OQ-SEC-2). | `src/gameplay/secret/secret_constants.gd` |
| `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE` | `true` | bool | `{true, false}` | R-SEC-02 garde de phase. Si `false`, signaux body_entered traités même en INACTIVE (utilisé pour debug uniquement). | `false` en prod = collection prématurée pendant transitions de scène, état incohérent. | `src/gameplay/secret/secret_constants.gd` |

> **AC-SEC-NEW (r2 B-3)** : grep statique `tests/static/secret_constants_lint_test.gd` vérifie qu'aucune valeur magique `"instance_id"` / `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE` n'apparaît hardcodée dans `src/gameplay/secret/*.gd` hors du fichier `secret_constants.gd` lui-même. Tout call site doit lire `SecretConstants.IDEMPOTENCE_KEY_STRATEGY`. Voir Acceptance Criteria — nouveau AC dans groupe E (Static).

### Knobs d'authoring (guidelines Level Designer — appliqués via lint Level pré-build)

Ces valeurs ne sont pas tunées à runtime mais sont les contraintes que Level Designers respectent en posant les tuples Secret dans l'éditeur. Elles sont documentées ici pour Phase 5 propagation vers Level GDD r5 ou un nouveau lint Level dédié.

| Knob | Valeur MVP | Unité | Range sûr | Ce qu'il garantit | Ce qui casse hors range |
|------|------------|-------|-----------|-------------------|--------------------------|
| `MIN_VOLUME_HEIGHT_ABOVE_FLOOR` | `2.0` | m | `[1.5, 4.0]` | EC-SEC-AP-1 — défi de mouvement minimal (jump nécessaire) | < 1.5 m : volume devient pickup au sol (anti-Pillar 4). > 4.0 m sans dégagement : volume inatteignable même avec wall_run_long. |
| `MIN_LURE_TO_VOLUME_DISTANCE` | `5.0` | m | `[3.0, 10.0]` | Séparation minimale physique entre provocation visuelle et collection (rend la traversée un défi) | < 3.0 m : lure et volume confondus, pas de défi. > 10.0 m sans skill : volume hors portée même cross-room. |
| `MAX_LURE_TO_VOLUME_DISTANCE` | `30.0` | m | `[15.0, 40.0]` | Lisibilité visuelle — portée glow cyan nominale 20 m + marge | > 30 m : lure invisible depuis sa salle d'appel naturelle (devient bruit authoring EC-SEC-AP-5). |
| `COLLECT_VOLUME_RADIUS` | `1.5` | m | `[0.8, 2.5]` | Taille de la SphereShape3D du Area3D — capture passage rapide sans déclencher au sol | < 0.8 m : joueur peut traverser sans déclencher (frame skip à haute vitesse). > 2.5 m : déclenche depuis le sol ou couloir adjacent (EC-SEC-AP-1). |
| `MIN_RADIAL_CLEARANCE_AROUND_VOLUME` | `0.5` | m | `[0.3, 1.0]` | Zone dégagée autour du volume — évite body_entered parasite sur StaticBody3D layer 4 | < 0.3 m : risque collision parasite. > 1.0 m : volume isolé, perd la sensation "au bord du bord". |
| `MIN_LURE_HEIGHT_ABOVE_EYE_LEVEL` | `1.5` | m | `[1.0, 3.0]` | Lure tire le regard vers le haut (eye level joueur ≈ 1.7 m → lure ≥ 3.2 m hauteur monde) | < 1.0 m : lure à hauteur d'œil, pas de provocation verticale. > 3.0 m sans contexte de salle : peut sortir du frustum naturel. |
| `MAX_VOLUMES_PER_ROOM` | `3` | count | `[1, 4]` | Cap budget Area3D archetype (cohérent Level R-4 r2 SecretHub ≤ 12 Area3D) + lisibilité authoring | > 4 : densité crée confusion authoring + risque race condition collection multi-volume EC-SEC-AP-4. |
| `MIN_VOLUME_TO_VOLUME_HORIZONTAL_SEP` | `3.0` | m | `[2.0, 5.0]` | Séparation entre 2 volumes même salle (évite double-collect race) | < 2.0 m : risque body_entered simultané, brouille feedback audio. |
| `MIN_VOLUME_TO_VOLUME_VERTICAL_SEP` | `4.0` | m | `[3.0, 8.0]` | Alternative à séparation horizontale (volumes empilables verticalement avec gap) | < 3.0 m : ascension rapide déclenche les deux volumes en moins d'une frame. |
| `MIN_WALL_RUN_LONG_PATH_LENGTH` | `6.0` | m cumulé | `[4.0, 10.0]` | Définit structurellement quand `required_ability: wall_run_long` est applicable (vs wall_run simple) | < 4.0 m : path tier 3 trivialisé, devient tier 2 effectif. > 10.0 m : path inatteignable même avec wall_run_long. |

### Mapping default `required_ability` ↔ `tier` (authoring convention)

Mapping recommandé pour les Level Designers — applicable comme default lors de l'authoring d'un nouveau `SecretLureMarker_NN`. Override possible via `@export var tier: int` (R-SEC-05) avec justification commentée.

| `required_ability` | `tier` default | Justification |
|--------------------|----------------|---------------|
| `none` | 1 | Secret accessible sans capability (vanilla) — défi minimal de lecture spatiale |
| `dash` | 1 | Capability disponible dès achat upgrade #1 — défi modéré |
| `double_jump` | 2 | Capability rare au MVP (upgrade #2) — défi moyen, exige timing |
| `wall_run` | 2 | Wall-run unique court — défi moyen, exige précision |
| `wall_run_long` | 3 | Enchaînement wall-run + dash mid-air — défi maximal, réservé Shaft/SecretHub |

**Override autorisé** : un `SecretLureMarker_NN` avec `required_ability: wall_run` mais `tier: 3` (override) signale que le path nécessite un wall-run *exceptionnellement difficile* (timing + angle critique) malgré l'utilisation d'une capability simple. Convention authoring : ajouter un commentaire `# tier-override-reason: <description>` sur le nœud dans la scène pour traçabilité.

**Lint recommandé** : si `tier ≠ default(required_ability)` sans commentaire override, fail le lint pré-build avec un warning éducationnel (pas un blocking — Tier 2+).

### Hooks Tier 2+ (réservation contrat futur, non implémenté MVP)

| Hook | Description | Quand activer |
|------|-------------|---------------|
| `SECRET_DROP_BONUS_ENABLED` | Permet à un secret de spawn un item bonus en plus du crédit | Tier 2+ — nécessite Item System |
| `SECRET_TELEPORT_ENABLED` | Permet à un secret de téléporter le joueur (raccourci niveau) | Tier 2+ — nécessite design éthique vs Pillar 4 |
| `SECRET_LORE_REVEAL_ENABLED` | Affiche un lore snippet à la collection | Tier 3 — viole Pillar 4 strict, à évaluer vs anti-pillar narration |

Aucune de ces extensions ne sera implémentée au MVP — toutes nécessitent un nouvel ADR + un amendement Secret r2.

## Visual/Audio Requirements

Secret System est data-pure : il n'instancie aucun visuel et ne joue aucun son. Toutes les exigences visuelles et audio passent par le signal `secret_collected(secret_node: Node, tier: int)` consommé par VFX System (visuel) et Audio System (son). Cette section documente **ce que les systèmes aval doivent rendre** sur réception du signal.

### Visuel — VFX System (Not Started, contrat à verrouiller dans VFX GDD)

| Trigger | Réaction visuelle attendue | Délai max | Source autorité |
|---------|---------------------------|-----------|-----------------|
| `secret_collected.emit(volume, tier)` | Glow cyan #3EE4FF du `SecretLureMarker_NN` (référencé via tuple NN matching ou méta sur volume) s'éteint d'un coup (instant fade-out ≤ 50 ms) | 1 frame (16 ms @ 60 fps) | VFX GDD futur — Rule "secret collect glow off" |
| `level_active(etage_id, ...)` | Glow cyan allumé sur tous les `SecretLureMarker_NN` non collectés (`_collected_secret_ids[volume.id] == false`) | < 200 ms post-level_active | VFX GDD futur — Rule "secret lure glow on level_active" |
| `request_new_run` | Glow cyan ré-allumé sur tous les lures (state reset) | < 200 ms | VFX GDD futur |

**Spec critique Pillar 4** :
- Le glow cyan doit être **portée ≥ 20 m** (Level R-2 r2 fix #4 — provocation visuelle cross-room).
- Le glow doit être **distinct de toute autre couleur de signalisation mécanique** : rouge = ennemi, cyan = secret/interactif, blanc = path. Aucun autre cyan dans la palette du jeu.
- L'extinction post-collect doit être **brutale** (pas de fade lent qui prolonge l'événement) — Pillar 1 FLOW : le secret est consommé en 1 frame, pas en cinematic.
- **Aucun particle burst additionnel** au moment de la collection (pas de gerbe d'étoiles, pas de flash blanc) — le clac audio + l'extinction du glow + la pulse HUD du compteur suffisent. Ajouter du particle viole l'austérité Pillar 4.

### Audio — Audio System (APPROVED r2.1, amendement Audio r2.2 recommandé)

| Trigger | Réaction audio attendue | Délai max | Source autorité |
|---------|------------------------|-----------|-----------------|
| `secret_collected.emit(volume, tier)` | Clac secret joué sur bus dédié (recommandation : nouveau bus `SECRET_COLLECT` séparé du `COMBAT_KILL`) | 1 frame (16 ms @ 60 fps) | Audio GDD r2.2 amendement requis — Rule "secret collect cue" |
| (idem, position spatiale) | Son joué via `AudioStreamPlayer3D` avec `position = secret_node.global_position` (positional 3D) | — | Audio GDD r2.2 |

**Spec critique Pillar 4** :
- Le clac secret doit être **distinct timbralement du clac combat** (`COMBAT_KILL` bus). Recommandation audio-director : son **plus grave** (downshift 100-200 cents) et **plus long** (durée 200-300 ms vs 60-80 ms pour kill) — il marque un moment de récompense, pas un kill staccato.
- **Pas de musique stinger**, pas de jingle, pas de "ding" de progression — le clac doit s'intégrer dans le mix existant comme une percussion isolée (cf. Player Fantasy §22 « un riff isolé »).
- **Pas de variation par tier au MVP** : tier 1, 2, 3 jouent le même clac (différenciation suffisante via le saut visible du compteur HUD). Tier 2+ pourrait introduire pitch-shift +0/+2/+4 semitones par tier (réservé OQ-SEC-3, dépend playtest).
- **Bus dédié** : Audio GDD actuel liste `MASTER / MUSIC / SFX / SWING_ACTIVE / COMBAT_KILL / AMBIENCE / UI`. Recommandation Phase 5 : amendement Audio r2.2 ajoute `SECRET_COLLECT` bus parented à SFX, avec ducking spec à définir avec audio-director.

### Asset spec flag

📌 **Asset Spec** — Visual/Audio requirements ci-dessus définissent les contrats. Après l'art bible approuvée, `/asset-spec system:secret-system` produira :
- Asset visuel : aucun (le glow cyan est rendu par VFX, le LureMarker est un Marker3D pur — pas d'asset à produire pour Secret System spécifiquement)
- Asset audio : `secret_collect.wav` (durée 200-300 ms, peak frequency 200-400 Hz pour timbre grave, sample rate 48 kHz mono)

## UI Requirements

Secret System ne possède **aucun UI propre**. Tout affichage UI passe par le signal `secret_collected` consommé en chaîne : Credit Economy applique sa formule F-CRD-2 et émet `credits_changed(total, +5/+10/+15, SourceKind.SECRET)`, le HUD écoute `credits_changed` et pulse le compteur de crédits. Le compteur de secrets/étage (UI optionnel "3/5 secrets") est **explicitement hors MVP** — il viole l'austérité Pillar 4 (transforme l'expérience en chasse aux collectibles).

### Compteur HUD secrets — DÉSACTIVÉ MVP

| Élément UI | Status MVP | Justification |
|------------|------------|---------------|
| Compteur "X/Y secrets collectés" sur HUD | **HORS SCOPE** | Anti-Pillar 4 strict (Player Fantasy §26 : "pas de recompte à la fin de l'étage", "le secret est noir sur blanc dans le compteur, point"). Le saut visible du compteur de crédits HUD (delta +5/+10/+15) est l'unique feedback UI MVP. |
| Pop-up "Secret found!" | **HORS SCOPE** | Viole anti-pillar narration interruptive + Pillar 1 FLOW. |
| Mini-map avec lures | **HORS SCOPE** | Viole Pillar 4 ("récompense le mouvement, pas le cerveau" — chercher sur une mini-map = énigme cognitive). |
| End-of-stage récap "X secrets trouvés" | **HORS SCOPE** | Viole anti-pillar "narration interruptive" et le ton Player Fantasy §26. |
| Counter "X/Y" Tier 2+ post-MVP | RÉSERVÉ | Décision playtest — si le playtest MVP montre que les joueurs perdent la trace de leur progression, ré-évaluer en Tier 2+ avec un compteur discret intégré au HUD existant (pas un overlay). |

### UX flag — propagation aux autres systèmes

📌 **UX Flag — Secret System** : Aucun UI propre Secret System au MVP. Le HUD Credit Economy (§UI Requirements Credit GDD) couvre l'unique feedback UI nécessaire (pulse compteur sur `credits_changed(SECRET)`). Quand le HUD GDD sera designé (Systems Index #17), il devra inclure :
- Pulse différenciée par `SourceKind` : `KILL` (pulse subtile +1 cr) vs `SECRET` (pulse plus forte +5/+10/+15 cr) — différenciation visuelle qui matérialise l'asymétrie viscérale Pillar 4 (Player Fantasy §24).
- Pas de notification distincte secret — uniquement la pulse compteur Credit.

Aucun screen UI dédié Secret System à designer via `/ux-design` au MVP. Si Tier 2+ ré-introduit un compteur discret, un screen UX devra être spécifié (`design/ux/hud-secret-counter.md`).

## Acceptance Criteria

### Tableau récapitulatif (r2)

| Dimension | Compte |
|-----------|--------|
| **Total ACs (r2)** | 53 (52 r1 + 1 nouveau AC-SEC-NEW r2 B-3 lint constants) |
| **BLOCKING** | 30 (29 r1 + 1 nouveau B-3) |
| **ADVISORY** | 23 (count r1 corrigé — voir review N-1 et recompte r2) |
| **AUTO** (testable headless GUT) | 27 |
| **MANUAL** (playtest requis) | 9 |
| **STATIC** (lint pré-build / lint constants) | 8 (7 r1 + 1 r2 B-3) |

> **r2 note** : le tableau récap r1 annonçait 43 ACs ; le contenu effectif r1 = 52 ACs (review N-1). r2 ajoute 1 AC Static (`AC-SEC-NEW` ci-dessous) pour le lint constants → 53 total. Décomptes BLOCKING/ADVISORY ajustés en conséquence.

> **Nouveau AC r2 B-3** :
>
> **AC-SEC-NEW (r2 B-3 — Lints/Static lint constants externalization)** — GIVEN tous les fichiers `src/gameplay/secret/*.gd` sauf `secret_constants.gd` lui-même, WHEN un grep statique cherche les littéraux `"instance_id"` (StringName MVP de `IDEMPOTENCE_KEY_STRATEGY`) ou `"scene_path"` ou `"uuid_export"` ou la valeur booléenne hardcodée pour `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE`, THEN aucun match ne doit être trouvé hors du fichier `secret_constants.gd` et hors des commentaires. Tout call site doit lire `SecretConstants.IDEMPOTENCE_KEY_STRATEGY` ou `SecretConstants.IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE`.
> `[BLOCKING | STATIC]` — `tests/static/secret_constants_lint_test.gd` GdUnit4 runner CI. Conformité CLAUDE.md « Gameplay values must be data-driven (external config), never hardcoded ».

---

### Groupe A — Lifecycle 2-phases (R-SEC-02, R-SEC-03, R-SEC-04, R-SEC-11, R-SEC-14)

**AC-SEC-01** — GIVEN Secret System vient d'être initialisé (`_ready()` appelé, aucun signal `level_active` reçu), WHEN un `body_entered` est reçu sur un `SecretCollectVolume_NN` quelconque, THEN le signal `secret_collected` n'est pas émis et `_collected_secret_ids` reste vide.
`[BLOCKING | AUTO]` — `assert(not secret_system.secret_collected.is_connected(...))` + vérifier taille dictionnaire = 0 après simulation body_entered.

**AC-SEC-02** — GIVEN Secret System est en phase INACTIVE, WHEN `level_active(etage_id=1, player_start=Vector3.ZERO)` est reçu, THEN Secret System passe en phase ACTIVE : `_is_active == true`, `get_secret_slots()` est appelé exactement une fois, et tous les volumes retournés valides ont leur signal `body_entered` connecté dans le même tick (SYNC, pas CONNECT_DEFERRED).
`[BLOCKING | AUTO]` — spy sur `LevelSystem.get_secret_slots()` + assert `connect` appelé flags=0 pour chaque slot valide.

**AC-SEC-03** — GIVEN Secret System est en phase ACTIVE sur l'étage 1 avec 3 slots connectés, WHEN un second `level_active(etage_id=2, ...)` est reçu, THEN le cleanup de l'étage 1 est exécuté avant la connexion des slots de l'étage 2 : les 3 anciens body_entered sont déconnectés, `_slots_this_level` est réinitialisé, `_collected_secret_ids` conserve ses entrées (non vidé).
`[BLOCKING | AUTO]` — assert déconnexion des anciens callables + assert `_collected_secret_ids.size()` inchangé après transition.

**AC-SEC-04** — GIVEN Secret System est en phase ACTIVE, WHEN `state_changed(MENU)` est reçu du GSM, THEN tous les body_entered connectés sont déconnectés et `_is_active` passe à `false`.
`[BLOCKING | AUTO]` — assert `_is_active == false` + assert zéro callable connecté sur les volumes après state_changed(MENU).

**AC-SEC-05** — GIVEN Level System retourne 5 SecretSlots valides à `level_active`, WHEN Secret System itère les slots, THEN exactement 5 signaux `body_entered` distincts sont connectés (1 par volume), chacun bindé à son propre slot via `_on_body_entered.bind(slot)`.
`[BLOCKING | AUTO]` — assert count connections = 5, assert chaque connection référence le bon slot via `.get_bound_arguments()`.

**AC-SEC-06** — GIVEN Secret System reçoit deux signaux `level_active` dans le même tick physique (bug Level System simulé), WHEN le second `level_active` arrive, THEN le cleanup est idempotent : déconnecter un signal non connecté est un no-op, aucun crash, l'état final est cohérent (slots du dernier `level_active` connectés, anciens déconnectés).
`[BLOCKING | AUTO]` — double émission simulée, assert aucune exception GDScript, assert état final correct.

**AC-SEC-07** — GIVEN la connexion du signal `level_active` est établie dans `_ready()`, WHEN `_on_level_active` est appelé à nouveau (nouveau level), THEN aucun `connect()` supplémentaire sur `level_active` n'est effectué (protection double souscription R-SEC-14).
`[BLOCKING | AUTO]` — assert `LevelSystem.level_active.get_connections().size() == 1` après deux `level_active` successifs.

---

### Groupe B — Idempotence et état (R-SEC-06, R-SEC-10, EC-SEC-03, EC-SEC-04, EC-SEC-14)

**AC-SEC-08** — GIVEN un secret tier=2 est UNCOLLECTED, WHEN `body_entered` est reçu une première fois, THEN `_collected_secret_ids[volume.get_instance_id()]` est mis à `true` AVANT que `secret_collected` soit émis (mutation d'état avant emit, ADR-0005 D-8).
`[BLOCKING | AUTO]` — spy signal : dans le handler connecté, assert `secret_system._collected_secret_ids[id] == true` avant que le handler ne retourne.

**AC-SEC-09** — GIVEN un secret est déjà collecté (`_collected_secret_ids[id] == true`), WHEN un second `body_entered` arrive sur le même volume (joueur repasse sur le volume), THEN le signal `secret_collected` n'est pas émis, `_collected_secret_ids` n'est pas modifié, aucun log n'est généré.
`[BLOCKING | AUTO]` — spy signal count = 0 sur second body_entered, assert dictionnaire inchangé.

**AC-SEC-10** — GIVEN deux `body_entered` sur le même volume arrivent dans la même frame physique (EC-SEC-03 multi-trigger), WHEN les deux callbacks sont traités, THEN exactement 1 signal `secret_collected` est émis et `_collected_secret_ids[id]` est `true` après le premier callback.
`[BLOCKING | AUTO]` — simulation double body_entered synchrone, assert emit_count == 1.

**AC-SEC-11** — GIVEN un joueur a collecté 2 secrets dans l'étage 1, WHEN le joueur meurt et un respawn est déclenché (simulation `state_changed(RESPAWNING)` puis `state_changed(PLAYING)`), THEN `_collected_secret_ids` contient toujours les 2 entrées à `true` après le respawn.
`[BLOCKING | AUTO]` — assert dictionnaire size == 2 après cycle respawn simulé.

**AC-SEC-12 (r2 B-1 — conditioned to Checkpoint r2 amendment)** — GIVEN Checkpoint GDD r2 amendement B-1 est appliqué (Checkpoint expose `get_collected_secrets() -> Array[int]` dans sa Published API + §Interactions liste Secret System), GIVEN un joueur a collecté 1 secret avant sa mort, et Checkpoint mock retourne `[instance_id_secret_1]` via `get_collected_secrets()` à `level_active`, WHEN Secret System itère les slots au nouvel étage, THEN `_collected_secret_ids` est pré-peuplé avec cet id avant que le joueur n'ait fait quoi que ce soit.
`[BLOCKING | AUTO — pending Checkpoint r2 amendment]` — mock `checkpoint.get_collected_secrets()` retournant `[42]`, assert `_collected_secret_ids[42] == true` immédiatement après `level_active`. **Pre-condition AC** : si Checkpoint r2 amendement non appliqué, AC reste PENDING (non-FAIL — bloqué sur dépendance externe documentée [GATE B-1]).

**AC-SEC-13** — GIVEN Secret System est en phase ACTIVE avec 3 secrets collectés, WHEN `request_new_run()` est reçu du GSM, THEN `_collected_secret_ids` est vidé, `_slots_this_level` est vidé, `_is_active == false`, et le Checkpoint snapshot est purgé.
`[BLOCKING | AUTO]` — assert dictionnaire size == 0 + assert `_is_active == false` après request_new_run.

---

### Groupe C — Garde GSM (R-SEC-08, EC-SEC-02, EC-SEC-09, EC-SEC-10)

**AC-SEC-14** — GIVEN Secret System est en phase ACTIVE et `_current_gsm_state == PAUSED`, WHEN `body_entered` est reçu sur un volume UNCOLLECTED, THEN aucun signal `secret_collected` n'est émis et `_collected_secret_ids` n'est pas modifié (garde R-SEC-08 appliquée avant la vérification d'idempotence).
`[BLOCKING | AUTO]` — set state PAUSED via mock GSM, simulate body_entered, assert emit_count == 0.

**AC-SEC-15** — GIVEN `_current_gsm_state == RESPAWNING`, WHEN `body_entered` est reçu, THEN la garde R-SEC-08 refuse et le secret reste UNCOLLECTED (même si le MovementController freeze rend le cas théorique en prod).
`[BLOCKING | AUTO]` — même pattern que AC-SEC-14 avec état RESPAWNING.

**AC-SEC-16** — GIVEN `_current_gsm_state == BOSS_DEFEATED`, WHEN `body_entered` est reçu, THEN la garde R-SEC-08 refuse, `secret_collected` n'est pas émis. État terminal MVP : aucune collection possible après boss final.
`[BLOCKING | AUTO]` — assert emit_count == 0 avec état BOSS_DEFEATED.

**AC-SEC-17** — GIVEN `state_changed(PAUSED)` puis `state_changed(PLAYING)` sont reçus dans cet ordre, WHEN `body_entered` arrive après le retour en PLAYING sur un volume UNCOLLECTED, THEN le secret est collecté normalement (signal émis, `_collected_secret_ids` mis à jour).
`[BLOCKING | AUTO]` — cycle complet simulé, assert emit_count == 1 après résumption PLAYING.

**AC-SEC-18** — GIVEN `level_active` arrive alors que le joueur chevauche déjà un volume (EC-SEC-09), WHEN le cleanup R-SEC-11 déconnecte les anciens body_entered et reconnecte les nouveaux, THEN aucun signal parasite n'est émis pour l'étage précédent et le nouveau volume n'émet qu'au prochain body_entered distinct.
`[BLOCKING | AUTO]` — simulation overlap pendant transition, assert zéro émission parasite.

---

### Groupe D — Tier validation et comportement défensif (R-SEC-05, R-SEC-13, EC-SEC-05, EC-SEC-06, EC-SEC-07)

**AC-SEC-19** — GIVEN un SecretSlot contient un `SecretLureMarker_NN` avec `tier = 0` (hors plage), WHEN Secret System itère ce slot à `level_active`, THEN `push_warning(...)` est émis, le slot est ignoré (aucun body_entered connecté), et le slot suivant est traité normalement (pas de crash, pas d'arrêt de l'itération).
`[BLOCKING | AUTO]` — assert warning contient "tier invalide 0" + assert volume non connecté + assert slots suivants connectés.

**AC-SEC-20** — GIVEN un SecretSlot contient `tier = 4` (hors plage {1, 2, 3}), WHEN Secret System traite ce slot, THEN comportement identique AC-SEC-19 : `push_warning` + skip. Cas symétrique côté hautes valeurs.
`[BLOCKING | AUTO]` — assert warning + assert non-connexion pour tier=4.

**AC-SEC-21** — GIVEN un SecretSlot a `slot.lure == null`, WHEN Secret System traite ce slot, THEN `push_error(...)` est émis avec le message format défini (R-SEC-13), le slot est ignoré, aucun crash.
`[BLOCKING | AUTO]` — assert error contient "slot incomplet" + assert absence de connexion.

**AC-SEC-22** — GIVEN un SecretSlot a `slot.collect_volume` qui n'est pas un `Area3D` (ex : `MeshInstance3D`), WHEN Secret System valide ce slot, THEN `push_error` + skip. Le volume inerte n'est jamais connecté.
`[BLOCKING | AUTO]` — mock slot avec volume MeshInstance3D, assert error + assert non-connexion.

**AC-SEC-23** — GIVEN `get_secret_slots()` retourne un tableau vide (EC-SEC-07 — bug Level), WHEN Secret System traite ce retour, THEN Phase ACTIVE est établie sans connexions, aucun signal d'erreur, l'étage est jouable sans secrets.
`[BLOCKING | AUTO]` — mock retour tableau vide, assert `_is_active == true` + assert `_slots_this_level.size() == 0` + assert zéro push_error.

**AC-SEC-24** — GIVEN un tableau mixte de 3 slots (1 valide tier=2, 1 lure null, 1 tier=5), WHEN Secret System itère, THEN exactement 1 body_entered est connecté (le slot valide), 2 logs d'erreur/warning sont générés (1 push_error pour lure null, 1 push_warning pour tier=5), et le slot valide est opérationnel.
`[BLOCKING | AUTO]` — assert connections == 1 + assert error_count == 1 + assert warning_count == 1.

---

### Groupe E — Émission signal SYNC (R-SEC-07, R-SEC-09, R-SEC-12)

**AC-SEC-25** — GIVEN un secret tier=1 est UNCOLLECTED et GSM est en PLAYING, WHEN `body_entered` est déclenché sur son volume, THEN `secret_collected(secret_node, 1)` est émis exactement une fois avec `secret_node == volume_node` et `tier == 1`, depuis le callback physique main thread (flags=0, pas CONNECT_DEFERRED).
`[BLOCKING | AUTO]` — assert signal émis avec payload correct, assert appelé depuis physics callback (is_physics_processing == true dans l'émetteur).

**AC-SEC-26** — GIVEN un secret tier=3, WHEN `body_entered` déclenche la collection, THEN `secret_collected(secret_node, 3)` est émis SYNC dans le même call stack que le body_entered (pas de deferred, pas de `call_deferred`). Le consumer Credit Economy reçoit le signal avant que le callback physique ne retourne.
`[BLOCKING | AUTO]` — spy Credit handler : assert `total_credits` est incrémenté avant retour du callback body_entered.

**AC-SEC-27** — GIVEN le joueur déclenche un `body_entered` via un glitch de géométrie sur un volume `required_ability: wall_run_long` sans avoir la capability (EC-SEC-12), WHEN Secret System traite ce body_entered, THEN le signal `secret_collected` est émis normalement (crédit accordé). Aucune vérification de capability par Secret System.
`[BLOCKING | AUTO]` — simulation body_entered sans mock Movement capability check, assert emit_count == 1.

**AC-SEC-28** — GIVEN Secret System n'a aucune référence directe à `CameraSystem`, `CombatSystem`, `VFXManager`, `AudioManager`, `HUDController` dans son code source, WHEN le fichier `src/gameplay/secret/secret_system.gd` est inspecté statiquement, THEN zéro match sur les patterns ADR-0005 D-10 outbound-only.
`[BLOCKING | STATIC]` — lint grep patterns interdits (analogie movement-no-consumer-refs.md).

---

### Groupe F — Contrats cross-system (Level, Credit, GSM, Checkpoint, VFX, Audio)

**AC-SEC-29** — GIVEN Level System émet `level_active(etage_id=3, player_start=Vector3(10, 0, 5))`, WHEN Secret System reçoit ce signal, THEN `get_secret_slots()` est appelé avec exactement le contexte de l'étage 3 (pas de mélange avec les slots d'un étage précédent en mémoire).
`[BLOCKING | AUTO]` — mock LevelSystem.get_secret_slots() retournant des slots étage-spécifiques, assert slots étage 3 connectés + zéro slot étage précédent.

**AC-SEC-30** — GIVEN Credit Economy est connecté à `secret_collected` et a `total_credits = 47`, WHEN secret tier=2 est collecté, THEN Credit Economy reçoit `secret_collected(node, 2)` et `total_credits == 57` dans le même tick (47 + 5×2 = 57). Le signal `credits_changed(57, +10, SourceKind.SECRET)` est émis par Credit.
`[BLOCKING | AUTO]` — integration test avec Credit mock ou stub, assert total_credits == 57 post-signal.

**AC-SEC-31** — GIVEN `secret_collected` est émis avec tier hors plage {1,2,3} (ne devrait jamais arriver en prod car R-SEC-05 filtre en amont), WHEN Credit Economy reçoit ce signal théoriquement, THEN Credit applique AC-CRD-15 (push_warning + no-op) sans crash. Ce test valide le contrat d'interface bidirectionnel.
`[BLOCKING | AUTO]` — force-émission du signal avec tier=0, assert Credit push_warning + total_credits inchangé.

**AC-SEC-32** — GIVEN Secret System expose `get_collected_ids() -> Array[int]`, WHEN Checkpoint System appelle ce getter après que 2 secrets ont été collectés dans l'étage courant, THEN le retour est un `Array[int]` contenant exactement les 2 instance_ids des volumes collectés.
`[BLOCKING | AUTO]` — assert return value = `[id1, id2]` avec les ids connus du mock.

**AC-SEC-33 (r2 B-1 — verbe renommé `inject_collected_secrets` + conditioned to Checkpoint r2)** — GIVEN Checkpoint GDD r2 amendement B-1 est appliqué (Checkpoint Published API expose `Secret.inject_collected_secrets(ids: Array[int])` callable), GIVEN Checkpoint System appelle `Secret.inject_collected_secrets([id_vol_1, id_vol_2])` avant `level_active`, WHEN `level_active` est reçu avec des slots incluant les volumes `id_vol_1` et `id_vol_2`, THEN ces deux volumes sont itérés en "lecture seule" (non connectés à body_entered), les volumes non pré-collectés du même étage restent connectés normalement.
`[BLOCKING | AUTO]` — mock checkpoint restauration, assert connections == (slots_total - 2).

**AC-SEC-34** — GIVEN VFX System et Audio System sont connectés à `secret_collected` via self-connect dans leur `_ready()`, WHEN un secret est collecté, THEN `secret_collected` est bien émis une seule fois et les deux listeners reçoivent le même payload `(secret_node, tier)`. Secret System n'initie aucune connexion vers ces systèmes.
`[ADVISORY | AUTO]` — mock VFX + Audio listeners, assert chacun reçoit le signal exactement une fois, assert aucun `connect(...)` VFX/Audio dans le code Secret System.

**AC-SEC-35** — GIVEN Secret System reçoit `state_changed(MENU)`, WHEN le cleanup s'exécute, THEN tous les body_entered sont déconnectés et `get_collected_ids()` reste accessible en lecture (état non purgé — purge uniquement sur `request_new_run()`).
`[BLOCKING | AUTO]` — assert connections == 0 + assert `get_collected_ids().size()` conserve les entrées existantes.

---

### Groupe G — Formules (F-SEC-1, F-SEC-2)

**AC-SEC-36** — GIVEN Credit Economy a `BASE_SECRET_CREDIT = 5`, WHEN Secret System émet `secret_collected(node, tier=1)`, `secret_collected(node, tier=2)`, `secret_collected(node, tier=3)` séquentiellement sur 3 volumes distincts, THEN les crédits ajoutés sont respectivement 5, 10, 15 (F-SEC-1 / F-CRD-2 : `credits = 5 × tier`). L'output range est strictement {5, 10, 15}.
`[BLOCKING | AUTO]` — integration test Credit stub, assert delta crédits par émission.

**AC-SEC-37** — GIVEN une session 2 étages avec le profil "Normal (3 secrets mix : T1+T2+T2)" et 20 kills total (8+12), WHEN la session se termine, THEN `secret_yield_session ≥ 25+40 = 65 cr` et `ratio_secret_kill = secret_yield / kill_yield ≥ 3.0` (F-SEC-2 — validation Pillar 4 ratio 3.25:1 attendu).
`[BLOCKING | AUTO]` — integration test Credit + Secret stub, assert ratio ≥ 3.0 sur session simulée.

**AC-SEC-38** — GIVEN un completionist collecte 5 secrets T3 dans un seul étage (cas limite F-SEC-2 cap théorique), WHEN tous les signaux `secret_collected` sont émis, THEN `secret_yield = 5 × 5 × 3 = 75 cr` exactement et aucun débordement ou troncature n'est observé dans `total_credits`.
`[BLOCKING | AUTO]` — assert total_credits == valeur_initiale + 75 après 5 émissions tier=3.

---

### Groupe H — Performance

**AC-SEC-39** — GIVEN Secret System est en phase ACTIVE avec 5 secrets connectés et GDUnit4 est en mode headless, WHEN 1000 `body_entered` events sont simulés sur des volumes déjà collectés (cas idempotence hot path), THEN le temps CPU total pour les 1000 callbacks est < 1 ms (16.6 ms frame budget 60 Hz — < 1/16 frame pour 1000 ops).
`[BLOCKING | AUTO]` — benchmark GUT, assert time_usec < 1000 pour 1000 iterations.

**AC-SEC-40** — GIVEN le handler `_on_body_entered` est exécuté, WHEN profiling GUT trace les allocations mémoire, THEN zéro allocation heap dans le hot path (pas de `Dictionary.new()`, Array literal `= [...]`, `String(` cast, concat `"" +`), conforme au pattern no-alloc-hot-paths.md appliqué par analogie à Secret System.
`[BLOCKING | STATIC]` — lint grep patterns interdits dans `_on_body_entered` du fichier implémentation.

---

### Groupe I — Authoring lints STATIC (EC-SEC-AP-1 à EC-SEC-AP-7)

**AC-SEC-41** — GIVEN un `SecretCollectVolume_NN` est posé à une hauteur `< 2.0 m` au-dessus du sol de la salle (EC-SEC-AP-1), WHEN le lint Level pré-build analyse la scène, THEN le lint retourne un FAIL avec le message `"SecretCollectVolume trop bas: [nom] height=[h]m < 2.0m MIN_VOLUME_HEIGHT_ABOVE_FLOOR"`.
`[ADVISORY | STATIC]` — lint Level (scope Level System, déclenché sur fichiers `.tscn` Level).

**AC-SEC-42** — GIVEN deux `SecretCollectVolume_NN` dans la même salle sont séparés de moins de 3.0 m horizontalement ET moins de 4.0 m verticalement (EC-SEC-AP-4), WHEN le lint Level pré-build analyse la scène, THEN le lint retourne un WARNING avec `"Volumes trop proches: [nom1] ↔ [nom2] sep_h=[X]m sep_v=[Y]m"`.
`[ADVISORY | STATIC]` — lint Level, assert présence du warning dans stdout.

**AC-SEC-43** — GIVEN un `SecretLureMarker_NN` a `tier` différent du default attendu pour sa `required_ability` (ex : `required_ability: dash`, `tier: 3`) sans commentaire `# tier-override-reason:` sur le nœud, WHEN le lint pré-build s'exécute, THEN un warning éducationnel est généré : `"Tier override sans justification: [nom] ability=[a] tier=[t] default=[d]"`.
`[ADVISORY | STATIC]` — lint Level Tier 2+, assert warning présent.

**AC-SEC-44** — GIVEN un `SecretLureMarker_NN` a `required_ability: wall_run_long` dans un archetype de salle Traversal (R-2.A ceiling [3.5, 4.5] m), WHEN le lint Level pré-build s'exécute (EC-SEC-AP-7), THEN le lint retourne un FAIL : `"wall_run_long interdit en archetype Traversal: [nom salle]"`.
`[ADVISORY | STATIC]` — lint Level, assert FAIL pour cette combinaison.

**AC-SEC-45** — GIVEN un `SecretLureMarker_NN` et son `SecretCollectVolume_NN` associé sont séparés de moins de 3.0 m (MIN_LURE_TO_VOLUME_DISTANCE trop petit), WHEN le lint Level s'exécute, THEN un WARNING est émis : `"Lure-Volume trop proches: [nom] distance=[d]m < 3.0m"`.
`[ADVISORY | STATIC]` — lint Level, assert warning.

---

### Groupe J — Expérience perçue et Pillar 4 (MANUAL playtest)

**AC-SEC-46** — GIVEN un joueur naïf (première session, pas de tutoriel secret), WHEN il collecte son premier secret en atteignant un `SecretCollectVolume_NN` tier=1, THEN il perçoit un feedback immédiat sans pause ni interruption du flow : le son est distinct du clac kill, le compteur saute, aucun overlay ni pop-up n'apparaît.
`[ADVISORY | MANUAL]` — playtest 5/5 joueurs naïfs, validation par QA Lead et Audio Director.

**AC-SEC-47** — GIVEN un joueur complète un secret tier=3 (wall_run_long enchaîné), WHEN la collection se déclenche, THEN le clac audio est perçu comme « plus grave et plus riche » que le clac de kill par au moins 4/5 testeurs lors d'un blind A/B test audio.
`[ADVISORY | MANUAL]` — blind A/B test auditif, résultats dans `production/qa/evidence/`.

**AC-SEC-48** — GIVEN un lure cyan est visible depuis le chemin nominal de l'étage, WHEN un joueur voit le lure pour la première fois, THEN au moins 4/5 testeurs comprennent spontanément « il y a quelque chose à atteindre là-haut » sans indication textuelle.
`[ADVISORY | MANUAL]` — observation playtest protocole think-aloud, résultats dans `production/qa/evidence/`.

**AC-SEC-49** — GIVEN un étage complet avec 3 secrets (mix T1+T2+T3) et 10 grunts, WHEN un joueur joue l'étage sans guide, THEN la session perçue valide Pillar 4 : le joueur mentionne spontanément « les secrets valent plus que les kills » ou équivalent dans le questionnaire post-session.
`[ADVISORY | MANUAL]` — questionnaire playtest item Pillar 4, seuil 4/5 joueurs, résultats dans `production/qa/evidence/`.

**AC-SEC-50** — GIVEN un joueur a collecté 2 secrets et meurt, WHEN il respawne et revient aux emplacements des secrets collectés, THEN les lures sont éteints (VFX éteint, aucun glow cyan), confirmant visuellement la persistance Pillar 3.
`[ADVISORY | MANUAL]` — observation visuelle playtest, les lures des secrets collectés ne clignotent pas après respawn.

**AC-SEC-51** — GIVEN un joueur collecte un secret tier=2 pendant un run actif, WHEN le compteur de crédits HUD est observé, THEN le delta affiché est `+10` avec une intensité visuelle perceptivement plus forte qu'un `+1` kill, et ce sans aucune pause de flow.
`[ADVISORY | MANUAL]` — observation playtest + validation HUD designer, 5/5 joueurs perçoivent la différence.

**AC-SEC-52** — GIVEN un secret tier=3 inaccessible est visible (lure à 12 m, joueur sans wall_run), WHEN le joueur le voit et continue sa progression, THEN au moins 3/5 testeurs mentionnent spontanément « je reviendrai quand j'aurai une meilleure capacité » dans le questionnaire.
`[ADVISORY | MANUAL]` — questionnaire playtest item "promesse de retour", résultats dans `production/qa/evidence/`.

## Open Questions

Toutes les Open Questions sont catégorisées par owner et target resolution date. Les OQs PROVISOIRE sont des contrats inter-système que Secret System a définis sans amont coordination avec un système Not Started — elles seront soit confirmées par le GDD du système concerné (avec amendement Secret r2 si divergence), soit RESOLVED quand le contrat sera figé.

### Contrats provisoires (PROVISOIRE — résolution lors du design des systèmes Not Started)

**OQ-SEC-1 — Interface Checkpoint System** *(PROVISOIRE — r2 B-1 verbes clarifiés, [GATE] amendement Checkpoint r2 requis)*
Secret System suppose que Checkpoint System exposera 3 verbes (renommés r2 B-1 pour clarté direction d'appel) :
- `checkpoint.get_collected_secrets() -> Array[int]` — Secret lit au `level_active` pour hydratation initiale
- `Secret.inject_collected_secrets(ids: Array[int])` — Checkpoint pousse la liste vers Secret au moment du restore (renommé r2 depuis `restore_collected_secrets` ; le préfixe `inject_*` clarifie que Secret *reçoit*, pas Checkpoint qui *restore*)
- `Secret.get_collected_ids() -> Array[int]` — Checkpoint lit l'état courant Secret au moment du checkpoint latch

Ce contrat est PROVISOIRE jusqu'au design du Checkpoint GDD (Systems Index #8) **et reste BLOCKING [GATE r2 B-1]** : Checkpoint GDD r1 (In Design) ne liste actuellement pas Secret dans §Interactions. **Amendement Checkpoint r2 requis** : ajouter ligne §Interactions Secret System bidirectionnel + 3 verbes ci-dessus dans Published API. Sans cet amendement, AC-SEC-12 + AC-SEC-33 restent PENDING (non-FAIL — bloqués sur dépendance externe documentée). Résolution : `/design-system checkpoint-respawn-system` puis amendement Checkpoint r2 cosmetic ajout Secret §Interactions. Si Checkpoint choisit une interface différente (ex : snapshot opaque + struct typée, pattern Memento), un amendement Secret r3 sera requis pour adapter la sérialisation.
- **Owner** : game-designer + Martin (Sprint A backbone)
- **Target** : avant `/create-epics secret-system` (séquencé après Checkpoint Designed + amendement r2)

**OQ-SEC-2 — Save/Load API + clé de persistance Tier 2+** *(PROVISOIRE)*
Au MVP, l'état `_collected_secret_ids` est session-only (perdu au quit). Tier 2+ nécessite persistance disque via Save/Load. Spécifications provisoires :
- Signature : `SaveLoad.save_int_array("collected_secret_ids", Array[int])` + `SaveLoad.load_int_array("collected_secret_ids", default: Array[int])`.
- Clé d'idempotence : `instance_id` est session-scoped (Godot regénère les ids au boot) → INCOMPATIBLE avec persistance cross-session. Migration recommandée Tier 2+ : `IDEMPOTENCE_KEY_STRATEGY = "uuid_export"` — chaque `SecretLureMarker_NN` porte un `@export var secret_uuid: StringName` stable cross-version. Voir Tuning Knob G-1.
- Décision en suspens : Save/Load API exacte + format struct Save (Array[int] vs Array[StringName] vs Array[Resource]).
- **Owner** : game-designer + gameplay-programmer
- **Target** : avant Save/Load GDD design (Systems Index #3)

**OQ-SEC-3 — Pitch-shift par tier post-MVP** *(PROVISOIRE)*
Au MVP, tier 1/2/3 jouent le même clac audio (différenciation suffisante via le delta visible HUD). Si playtest MVP révèle que les joueurs ne distinguent pas perceptivement le tier d'un secret collecté (« j'ai eu 5 ou 15 cr ? »), introduire pitch-shift +0/+2/+4 semitones par tier en Tier 2+ (réutilise le pattern Audio Rule 11 multi-kill). Décision : attendre playtest data — pas de spéc préemptive. Si pitch-shift introduit, vérifier ducking compatibility avec sidechain Music ADR-0009 D-1.
- **Owner** : audio-director + qa-lead (playtest data)
- **Target** : Tier 2+ post-MVP playtest

**OQ-SEC-4 — Bus audio dédié `SECRET_COLLECT`** *(PROVISOIRE — amendement Audio r2.2)*
Audio System r2.1 liste 7 bus (`MASTER / MUSIC / SFX / SWING_ACTIVE / COMBAT_KILL / AMBIENCE / UI`). Le clac secret pourrait :
- (a) Réutiliser `COMBAT_KILL` (refroidi par sidechain Music + cohérence kill-ish)
- (b) Réutiliser `SFX` générique (simple, mais perd l'identité)
- (c) Créer nouveau bus `SECRET_COLLECT` parented à SFX (clean, identifie le bus dans Audio profiler)
- **Recommandation** : option (c). Amendement Audio r2.2 requis avant epic Secret System.
- **Owner** : audio-director
- **Target** : Phase 5 propagation (Audio r2.2)

### Décisions design en attente (non-PROVISOIRE)

**OQ-SEC-5 — VFX du glow lure post-collect : éteint vs grayed-out** *(à trancher Sprint A)*
Au MVP : glow cyan s'éteint complètement (R-SEC-12 + Visual/Audio Requirements). Alternative considérée : grayed-out (cyan désaturé, encore visible mais signalant "déjà collecté") pour aider les joueurs revisitant un étage à voir où ils ont déjà été. **Argument PRO grayed-out** : Pillar 2 LA PROGRESSION SE VOIT — le joueur voit son progrès dans la géométrie. **Argument CONTRA grayed-out** : viole austérité Pillar 4 (UI ajoute du bruit cognitif), ajoute une complexité visuelle pour un cas d'usage rare (re-visit d'étage). **Recommandation** : MVP éteint complet, ré-évaluer post-playtest. Si retour utilisateurs sur "je ne me souviens plus quels secrets j'ai eus", introduire grayed-out en Tier 2+.
- **Owner** : creative-director + art-director
- **Target** : Sprint A `/design-review secret-system` ou playtest MVP

**OQ-SEC-6 — Comportement glow lure si `required_ability` non possédée** *(reservation Tier 2+)*
Au MVP : glow cyan toujours allumé tant que UNCOLLECTED, indépendamment de la capability joueur. Alternative considérée Tier 2+ : glow plus pâle si `required_ability` non possédée + plus saturé si possédée — signal visuel de "tu peux maintenant aller le chercher". **Argument PRO** : matérialise visuellement la promesse Pillar 2 (la progression débloque des secrets). **Argument CONTRA** : viole anti-pillar narration interruptive (le jeu te dit quoi faire), augmente surface d'erreur authoring. **Statut MVP** : aucune logique de capability-aware glow. À revisiter post-MVP si playtest révèle que les joueurs n'identifient pas spontanément les "promesses de retour" mentionnées dans Player Fantasy §28.
- **Owner** : creative-director + ux-designer
- **Target** : Tier 2+ post-playtest MVP

**OQ-SEC-7 — Lint Level pré-build pour validation tuples Secret** *(à scoper Sprint A)*
Les anti-patterns EC-SEC-AP-1 à EC-SEC-AP-7 et les contraintes Tuning Knobs G-3 à G-11 sont des règles d'authoring. Idéalement, un lint Level pré-build (script GDScript invoqué par CI) valide automatiquement chaque étage `.tscn` avant merge :
- Hauteur volumes ≥ 2.0 m
- Distance lure↔volume ∈ [5, 30] m
- Séparation volumes même salle ≥ 3 m horiz / 4 m vert
- Cap volumes/salle ≤ 3
- Présence ≥ 1 `wall_run` par étage
- Cohérence `tier` ↔ `required_ability` (warning si override sans commentaire)

**Statut MVP** : lint pas encore implémenté. **Recommandation** : ouvrir epic `level-system-lint-secret-tuples` Sprint 1, après Secret System Designed r1 et Level r5 amendement (intégrer les règles dans Level Tuning Knobs).
- **Owner** : level-designer + tools-programmer
- **Target** : Sprint 1 implémentation

**OQ-SEC-8 — Différenciation HUD pulse SourceKind KILL vs SECRET** *(coordination HUD GDD)*
Le HUD GDD (Systems Index #17, Not Started) doit consommer `credits_changed(total, delta, source: SourceKind)` et différencier visuellement les sources. Recommandation Visual/Audio Requirements + UI Requirements ci-dessus :
- `SourceKind.KILL` : pulse subtile +1 cr
- `SourceKind.SECRET` : pulse plus forte (+5/+10/+15 cr) avec intensité accrue
- `SourceKind.SPEND_SHOP` : pulse silencieuse (delta négatif)
- `SourceKind.BOOT_HYDRATE` : pas de pulse (delta=0 init)

**Statut MVP** : HUD GDD doit valider et coder cette différenciation comme contrat. Coordination requise.
- **Owner** : ux-designer + game-designer (HUD GDD lead)
- **Target** : avant `/design-system hud-system`

**OQ-SEC-9 — Boss room : secret possible derrière le boss ?** *(Tier 3 Full Vision)*
Le Boss System (Systems Index #16, Not Started, Tier Full Vision) introduit l'asymétrie one-shot/multi-hits unique du jeu. Question : un secret peut-il être placé dans la salle du boss (collectable post-victoire ou pendant le combat) ? **Argument PRO** : Pillar 4 cohérence (le boss est l'étage final, mériter un secret fort). **Argument CONTRA** : viole le ton du combat de boss (statique, pas exploratoire), force le joueur à diviser attention pendant le combat le plus dangereux du jeu. **Statut MVP** : aucun secret en salle de boss MVP (boss Tier 3 hors scope). À revisiter si Boss System designé.
- **Owner** : game-designer + creative-director
- **Target** : Tier 3 Boss System design

**OQ-SEC-10 — Speedrun mode : secrets collectés affectent leaderboard split ?** *(Tier 3 Full Vision)*
Speedrun & Leaderboards System (Systems Index #22, Not Started, Tier Full Vision) introduit chronométrage. Question : doit-il y avoir des leaderboards séparés "any%" (pas de secrets requis) vs "100%" (tous secrets collectés) ? **Argument PRO** : pratique standard speedrun community. **Argument CONTRA** : ajoute complexité UI, fork le replay value. **Statut MVP** : hors scope, pas de leaderboards. À déterminer en design Speedrun System.
- **Owner** : game-designer + community-manager
- **Target** : Tier 3 Speedrun System design
