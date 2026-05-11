# Player Movement System

> **Status**: Revised (post design-review r3 2026-04-21) — pending r4 fresh re-review
> **Author**: Martin + design-system skill (auto mode), revised after `/design-review` r1 (8 specialists) → r2 (5 specialists) → r3 (4 specialists + creative-director)
> **Last Updated**: 2026-04-21 (r3 revision — Clusters 1-5 : propagation décisions Martin A/B/C/D, formule wall-jump finale, invariants numériques, ADRs, mock spec)
> **Last Verified**: 2026-04-21
> **Review log**: `design/gdd/reviews/player-movement-system-review-log.md`
> **Implements Pillar**: Pillar 1 (FLOW AVANT TOUT) — primaire ; Pillar 2 (LA PROGRESSION SE VOIT ET SE SENT) — via upgrades activant de nouvelles capacités ; Pillar 3 (UNE SECONDE CHANCE N'EST JAMAIS LOIN) — via respawn instant. Pillar 4 indirect (les routes vers secrets dépendent du moveset).

## Summary

Le Player Movement System est le cœur mécanique et existentiel de CHROME://ASCENT. Il définit comment le corps cybernétique du joueur se déplace dans l'espace 3D FPS : marche, course, saut, double saut, dash horizontal, wall-run, respawn. Chaque capacité au-delà du déplacement de base et du saut simple est *désactivée au démarrage* et débloquée par le shop — le moveset grandit littéralement au fil du jeu. L'input latency cible < 1 frame et le feel snap/responsif sont non-négociables : ce système est le risque #1 du projet.

> **Quick reference** — Layer: `Core` · Priority: `MVP` · Key deps: `Input System (amont), Upgrade System (amont, capability flags), Camera System (aval), Checkpoint & Respawn (amont+aval), Player Combat (aval, consomme velocity)`

## Overview

Le Player Movement System gère toutes les transformations de position et de vélocité du joueur en réponse aux inputs clavier/souris. Il orchestre cinq états de mouvement (Grounded, Airborne, Dashing, WallRunning, Dead) et trois capacités optionnelles gated par l'Upgrade System (double-jump, dash, wall-run). Il fournit en aval une signature de vélocité consommée par le système de combat (pour la hitbox katana swept), par le système de caméra (pour le head-bob et le wall-run tilt), et par le VFX System (pour les trails de dash). Il consomme en amont les actions abstraites d'Input et les flags de capabilities publiés par Upgrade. Le respawn est délégué à Checkpoint & Respawn — le Movement System expose seulement `respawn(position: Vector3)` et l'appelle via `died` signal. Le système tourne à **60 Hz physique** (ADR-0001 Accepted 2026-04-21 — default Godot 4.6 + Jolt) et cible une latence input→action ≤ 16 ms côté engine (budget `1 / 60 ≈ 16.6 ms` worst-case, respecté par le pattern `was_pressed_this_tick` d'ADR-0004).

## Player Fantasy

Tu es une lame fluide. Pas une lame tenue par un humain lourd : *tu es la lame*, et ton corps cybernétique t'obéit avant que tu aies formé l'intention. Quand tu appuies sur Shift pour dasher, tu *es* déjà 4 mètres plus loin. Quand tu longes un mur à 10 m/s, tu le *sens* coller à toi sans avoir à réfléchir à la physique. Quand tu sautes, tu montes vite et tu retombes sèchement — aucune phase de flottement qui te demanderait de corriger.

Le sentiment-cible, en une phrase : **« ma main bouge et le jeu est déjà là. »**

Référence précise : **Ghostrunner (2020)**. Plus précisément : le dash de Ghostrunner, qui t'extrait *instantanément* du danger et te rend le contrôle à la fraction de seconde. Anti-référence : les FPS qui "glissent" après un arrêt d'input (Halo moderne, COD), les FPS où le saut a une anim de windup (Destiny), les platformers où le perso "monte en vitesse" (simulation arcade). Rien de tout ça ici. *Chaque input est une note staccato.*

Ce que le joueur doit *jamais* ressentir : "j'ai appuyé trop tôt", "le perso flotte", "le saut est mou", "le dash n'est pas parti". Si un playtester prononce un de ces mots, le système a échoué, pas le joueur.

## Detailed Design

### Core Rules

1. **Déplacement horizontal au sol** : lorsque Grounded, la vélocité horizontale (`velocity.x`, `velocity.z`) est settée chaque tick à `wish_dir * MOVE_SPEED`, où `wish_dir` est la direction d'input normalisée, projetée sur le plan XZ via la rotation Y du joueur. Si `wish_dir` est nul, la vélocité horizontale est remise à **zéro au tick suivant** (stop instantané, arcade pur). Aucune accélération ni décélération analogique — feel staccato. *Revision 2026-04-21 : la décélération linéaire précédente (500 ms) contredisait la Player Fantasy "snap crisp binaire" et l'anti-référence COD — Cluster A fix.*

2. **Saut simple (toujours disponible)** : au pressage de `jump` quand Grounded, `velocity.y = JUMP_VELOCITY`. Le pressage est *edge-triggered* (just_pressed), pas *held*.

3. **Double saut (gated par capability `can_air_jump`)** : quand Airborne et `air_jumps_used < MAX_AIR_JUMPS` (=1) et `can_air_jump == true`, un pressage de `jump` met `velocity.y = AIR_JUMP_VELOCITY` et incrémente `air_jumps_used`. Le compteur remet à 0 **uniquement au contact sol** (`is_on_floor() == true` transition). *Revision r3 2026-04-21 : le wall-jump ne reset PLUS `air_jumps_used` — au contraire il le set à `MAX_AIR_JUMPS` (cf. Rule 8). Corrige la formulation antérieure "reset à 0 dès le contact sol ou un wall-jump".*

4. **Coyote time (MVP)** : après avoir quitté le sol sans saut délibéré, le joueur a une fenêtre `COYOTE_TIME` (100 ms) pendant laquelle `jump` est traité comme un saut-sol (ne consomme pas l'air-jump). *Décision 2026-04-21 : feature MVP — à ajouter au prototype avant le début du level design. Budget estimé : 0.5 jour.*

5. **Jump buffer [POST-MVP]** : si `jump` est pressé jusqu'à `JUMP_BUFFER` (100 ms) avant le landing, le saut est exécuté automatiquement à l'impact sol. *Décision Martin r2 (2026-04-21, r3-propagée) : feature **POST-MVP**, split du coyote time. Rationale : réduire scope Sprint 1 ; coyote seul adresse les inputs tardifs, suffisant pour MVP. Jump buffer à réévaluer en playtest MVP — si les inputs anticipés à l'atterrissage sont identifiés comme source de frustration, prioriser en Tier 2.*

6. **Dash horizontal (gated par capability `can_dash`)** : au pressage de `dash` si `dash_cooldown_timer <= 0` et `can_dash == true`, le système entre en état Dashing. Direction = `wish_dir` projeté au plan XZ ; si vide, direction = **forward horizontal du joueur** (basé sur la rotation Y du CharacterBody3D, PAS sur le pitch camera — un joueur qui regarde vers le haut ne dashe pas en diagonale ascendante). À l'entrée en Dashing, `velocity.y = 0.0` (reset explicite pour éviter qu'un dash en plein saut conserve une composante verticale imprévue). Pendant Dashing, la vélocité horizontale est fixée à `dash_dir * DASH_SPEED` chaque tick, gravité désactivée, durée = `DASH_DURATION` (100 ms, *revision : court pour éviter le glissé perceptible*). À la fin du dash, la vélocité horizontale est settée à `dash_dir * DASH_EXIT_SPEED` (15 m/s nominal, soit 1.5× MOVE_SPEED) et la gravité reprend ; pendant les `DASH_MOMENTUM_WINDOW` suivantes (200 ms) le joueur peut infléchir mais la décélération vers MOVE_SPEED est linéaire (momentum conservation). Après cette fenêtre, contrôle ground/air standard reprend. Cooldown `DASH_COOLDOWN` (800 ms) démarre au début du dash. *Revision 2026-04-21 : Cluster A fix — court dash + exit momentum au lieu de cap immédiat à MOVE_SPEED.*

7. **Wall-run (gated par capability `can_wall_run`)** : quand Airborne, `horizontal_speed > WALL_RUN_MIN_SPEED` (5 m/s), et **au moins un** de deux RayCast3D latéraux (gauche `%WallRayLeft` ET droite `%WallRayRight`, pattern Godot 4.5+ unique-name via `@onready var wall_ray_left: RayCast3D = %WallRayLeft` — plus robuste que `$WallRayLeft` aux renommages de scène, godot-specialist F11 ; longueur = `capsule_radius + WALL_DETECT_MARGIN` ≈ 0.8 m avec capsule 0.35 m) touche une surface verticale, le système entre en état WallRunning. **Priorité si les deux touchent simultanément** (couloir étroit) : gauche gagne par défaut (reproductible, testable — cf. AC-MV-34). Pendant WallRunning, la gravité devient `WALL_RUN_GRAVITY` (4 m/s² au lieu de 28) et la chute verticale est clampée à -3 m/s. Le wall-run se termine dès que la condition échoue (sol touché, vitesse perdue, aucun raycast ne touche plus) OU après `WALL_RUN_MAX_DURATION` (1.5 s) pour éviter le camping infini. *Optimisation (performance-analyst F7) : les deux raycasts sont désactivés quand le joueur est en état Grounded (wall-run impossible), réactivés à l'entrée en Airborne.*

8. **Wall-jump** : quand WallRunning, un pressage de `jump` met `velocity = wall_normal * WALL_JUMP_SIDE + Vector3.UP * WALL_JUMP_UP`, **set `air_jumps_used = MAX_AIR_JUMPS`** (bloque tout double-jump post-wall-jump — *décision Martin r3 A, 2026-04-21*), et sort de WallRunning. Le wall-jump prend priorité sur le double-jump si les deux sont éligibles simultanément. Rationale : le wall-jump est la ressource de mouvement aérien principale après le double-jump ; enchaîner les deux trivialiserait la difficulté de platforming vertical (Pillar 4). Conséquence Level Grid : un couloir parallèle de largeur > `WALL_JUMP_NOMINAL_DISTANCE = 3.25 m` n'est PAS franchissable en un seul wall-jump — le Level Grid Spec fige les couloirs MVP à ≤ 3.25 m (voir `design/levels/level-grid-spec.md`).

9. **Mort & respawn** : quand une source externe (Hazard, Enemy laser, Combat) appelle `die()`, le système émet le signal `died`, fige les inputs pendant `RESPAWN_DELAY` (**50 ms** — *décision Martin r3, 2026-04-21 : respawn quasi-instantané pour maximiser Pillar 3 "UNE SECONDE CHANCE N'EST JAMAIS LOIN"*), puis appelle `respawn(position)` via le Checkpoint system. `respawn` remet la position au checkpoint courant, zéro la vélocité, reset tous les timers (dash, wall-run, air-jumps). **Contrainte matérielle** : `RESPAWN_DELAY ≥ 1 frame` (16.6 ms à 60 Hz) pour garantir que les consommateurs `CONNECT_DEFERRED` du signal `died` (VFX, Audio, HUD) reçoivent leur callback avant `respawn()`. En dessous, le feedback visuel/audio n'est pas garanti. **Feedback de mort à 50 ms** : `death.wav` doit être ≤ 40 ms pour ne pas être tronqué ; fondu rouge raccourci à 40 ms (la version 100 ms historique est conservée uniquement en toggle `reduce_flash` OFF avec délai prolongé). **Garde-fou testabilité** : un AC playtest d'attribution causale (Feel AC ci-dessous) vérifie que 5 joueurs débutants sur 5 identifient correctement la cause de leur mort ; si < 4/5, revisiter `RESPAWN_DELAY` en playtest MVP.

10. **Capabilities par défaut au départ d'une save neuve** : `can_air_jump=false`, `can_dash=false`, `can_wall_run=false`. Seuls sont autorisés : course + saut simple. L'Upgrade System flip ces flags à `true` quand le joueur achète l'upgrade correspondante dans le shop. *Décision 2026-04-21 : `can_slow_mo_air` retiré du MVP movement — il sera un système séparé `aerial-slowmo-system.md` en Tier 2+ qui scale `Engine.time_scale`, hors scope de ce GDD.*

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Grounded** | `is_on_floor() == true` et non Dashing | `is_on_floor() == false` → Airborne ; `jump` pressed → Airborne ; `dash` pressed si `can_dash` → Dashing ; `die()` → Dead | Move horizontal = wish_dir * MOVE_SPEED ; gravité appliquée mais absorbée par le sol ; `air_jumps_used = 0` ; `coyote_timer = 0` |
| **Airborne** | Quitter le sol sans wall-run éligible | `is_on_floor() == true` → Grounded ; wall-run éligible → WallRunning ; `dash` pressed si `can_dash` → Dashing ; `die()` → Dead | Move horizontal avec air control `AIR_CONTROL_FACTOR` (~65%, cf. Formulas) ; gravité normale ; jump consomme air-jump si dispo |
| **Dashing** | `dash` pressed + `can_dash` + cooldown OK | `dash_timer <= 0` → Grounded (si sol) ou Airborne ; `die()` → Dead | Vélocité horizontale = `dash_dir * DASH_SPEED` ; `velocity.y = 0` (reset à l'entrée) ; gravité 0 ; input horizontal ignoré ; hitbox katana reste active ; invulnérabilité = **non** (décision post-revision : non-MVP, réévalué en playtest). **Transition Dashing → WallRunning explicitement interdite** : les raycasts wall-run sont désactivés pendant Dashing pour garantir un dash rectiligne prévisible ; le wall-run peut démarrer seulement au tick suivant `dash_timer <= 0` si le joueur est Airborne et les conditions sont remplies. |
| **WallRunning** | Airborne + horiz_speed > WALL_RUN_MIN_SPEED + raycast latéral hit + `can_wall_run` | Raycast perd contact ; sol touché → Grounded ; `jump` pressed → wall-jump (sets `air_jumps_used = MAX_AIR_JUMPS`, cf. Rule 8) puis Airborne ; duration > WALL_RUN_MAX_DURATION → Airborne ; `die()` → Dead | Gravité réduite (WALL_RUN_GRAVITY) ; chute clampée à -3 m/s ; `air_jumps_used` *non reset* à l'**entrée** en WallRunning (le wall-run ne donne pas de double-jump gratuit) — à distinguer du wall-jump lui-même qui **set** `air_jumps_used = MAX` à la sortie |
| **Dead** | `die()` appelé | `respawn()` exécuté après RESPAWN_DELAY → Grounded | Tous les inputs ignorés ; vélocité figée ; `died` signal émis pour que HUD/VFX/Audio réagissent |

### Interactions with Other Systems

| Système | Rôle | Interface |
|---------|------|-----------|
| **Input System** (amont) | Fournit les actions abstraites | Consomme `move_left`, `move_right`, `move_forward`, `move_back`, `jump`, `dash`, `attack`, `restart`, `ui_cancel`. Input System publie aussi `mouse_motion` pour le look. |
| **Upgrade System** (amont) | Publie les capability flags | Movement lit `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run`. *Retiré : `can_slow_mo_air` (hors MVP — futur système séparé `aerial-slowmo-system.md`).* Interface unidirectionnelle : Movement ne sait pas *comment* les flags ont été settés. |
| **Camera System** (aval) | Suit la tête du joueur, applique tilt wall-run | Lit `velocity: Vector3`, `state: State` (enum), `is_dashing: bool` (pour FOV pulse), `wall_normal: Vector3` (Camera dérive `wall_side` depuis cette normale, cf. Camera GDD Rule 4). Hiérarchie **3-tier canonique (ADR-0002)** : `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D`. Le tilt wall-run s'applique sur **`CameraEffects.rotation.z`** (owned par Camera GDD Rule 4 — **pas** CameraArm, pour éviter conflit Tween avec pitch/head-bob). |
| **Checkpoint & Respawn** (bidirectionnel) | Stocke le dernier checkpoint, exécute respawn | Checkpoint appelle `Player.set_checkpoint(position)` à chaque trigger. Movement appelle `Checkpoint.get_current_position()` depuis `respawn()`. |
| **Player Combat** (aval) | Hitbox katana sweepée à la vélocité du perso | Combat lit `velocity` et `global_position` pour positionner le ShapeCast3D du katana. **Orientation : `CameraSystem.aim_forward` (roll-corrigé ADR-0002), jamais `transform.basis.z`** (cf. Combat GDD Rule 5 r1 — `transform.basis.z` explicitement interdit car il inclut le tilt wall-run et dévierait la trajectoire horizontalement). Aucune influence inverse — Movement ignore que le katana existe. |
| **Hazard System / Enemy System** (aval) | Déclenche `die()` | Enemy et Hazard appellent `Player.die()` quand leur hitbox touche le joueur (laser, projectile, collision). |
| **VFX & Feedback System** (aval) | Trails de dash, impact wall-run, fade respawn | Écoute les signals `dash_started`, `dash_ended`, `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned`, `attacked`. **Connexions recommandées : `CONNECT_DEFERRED`** pour éviter les burst CPU synchrones sur mort/respawn (perf F4). VFX ne modifie jamais la vélocité ou l'état. |
| **Audio System** (aval) | Foot-steps, swoosh dash, wall-run whoosh, impact respawn | Écoute les mêmes signals que VFX, également en `CONNECT_DEFERRED`. |
| **HUD System** (aval) | Affiche l'état du dash cooldown, éventuels mediums de feedback | Lit `dash_cooldown_timer: float`, `dash_cooldown_ratio: float` (0–1), `can_dash: bool` (pour afficher/cacher l'indicateur). |

### Published API (signals + properties)

*Contrat provisoire — à confirmer à l'implémentation des GDDs aval (Camera, Combat, VFX, Audio, HUD).*

**Signals — Liste canonique par ADR-0005 D-2** (tous émis depuis le `MovementController` = le `CharacterBody3D` lui-même, avec payload typé). **Ajouter/retirer/renommer un signal = amendement ADR-0005 requis.**

```gdscript
signal dash_started(dash_dir: Vector3, dash_speed: float)
signal dash_ended()
signal wall_run_entered(wall_normal: Vector3)
signal wall_run_exited()
signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)
signal died()
signal respawned(spawn_position: Vector3)
signal attacked()  # forwarded from Input "attack" action, for Player Combat convenience
```

**Note implémentation (godot-specialist F5)** : les typed signals Godot 4.x vérifient les types de payload à la connexion **en debug build** — les mismatches passent silencieusement en release. Toutes les connexions (Camera System, VFX, Audio, HUD) DOIVENT être testées en debug build au moins une fois avant merge pour attraper les mismatches.

**Note connexions CONNECT_DEFERRED (ADR-0005 D-5 — règle codée)** : `CONNECT_DEFERRED` est OBLIGATOIRE pour les consommateurs **lourds** (VFX GPUParticles, Audio AudioStreamPlayer instanciation) — évite les burst CPU synchrones pendant `_physics_process`. Pour les consommateurs **light** (HUD toggle booléen, logger save state), connexion normale. Règle opérationnelle : `CONNECT_DEFERRED` si le callback peut instancier un nœud ou déclencher un sampler ; connexion normale sinon. Détail complet (critères, exceptions, tests) : voir ADR-0005 D-5.

**Exposed properties (read-only pour consommateurs externes) :**

*Pattern GDScript prescrit (godot-specialist F7)* : pour chaque propriété "read-only pour consommateurs externes", implémentation via backing var privée et `get:` sans setter. GDScript n'a pas de modificateur `readonly` natif — ce pattern est le seul moyen d'empêcher l'écriture externe (erreur GDScript en debug).

```gdscript
# Pattern prescrit pour toutes les propriétés read-only (sauf velocity, héritée) :
var _state: State = State.GROUNDED
var state: State:
    get: return _state

var _wall_normal: Vector3 = Vector3.ZERO
var wall_normal: Vector3:
    get: return _wall_normal

# Propriétés exposées :
var velocity: Vector3            # hérité de CharacterBody3D (setter interne Godot)
var state: State                 # enum { GROUNDED, AIRBORNE, DASHING, WALL_RUNNING, DEAD } — read-only
var is_dashing: bool             # raccourci == (state == DASHING) — read-only
var wall_normal: Vector3         # valide pendant WallRunning, Vector3.ZERO sinon — read-only
var dash_cooldown_timer: float   # seconds remaining, 0.0 si dispo — read-only
var dash_cooldown_ratio: float   # 0.0 (cooldown finissant) à 1.0 (cooldown démarré) — read-only
var can_dash: bool               # mirror du flag Upgrade, exposé pour HUD — read-only
var can_air_jump: bool           # read-only
var can_wall_run: bool           # read-only
```

**Methods appelables externes :**
```gdscript
func die() -> void:
    # CONTRAT IDEMPOTENCE : early return OBLIGATOIRE en première ligne
    # (godot-specialist F6 — sans early return, l'idempotence n'est pas
    # garantie thread-safe sous deferred signal emission Godot)
    if _state == State.DEAD:
        return
    _state = State.DEAD
    died.emit()
    # ... respawn timer, freeze inputs, etc.

func set_checkpoint(pos: Vector3) -> void:
    # appelé par Checkpoint System
    pass

# respawn() est privé — déclenché internement via timer après died
```

## Formulas

### Déplacement horizontal (Grounded)

```
velocity.xz = wish_dir.xz * MOVE_SPEED                      # si |wish_dir| > 0.01
velocity.xz = Vector2.ZERO                                  # si idle input (stop instantané)
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `wish_dir` | — | Vector3 | unit vector (xz) | Direction désirée issue de l'input, projetée sur le plan horizontal |
| `MOVE_SPEED` | `v_m` | float | 8.0 – 12.0 m/s | Vitesse au sol cible |
| `delta` | `Δt` | float | `1 / 60 ≈ 0.01667` s | Tick physique fixe 60 Hz (ADR-0001 Accepted 2026-04-21 — default Godot 4.6 + Jolt). |

**Output range** : `|velocity.xz|` ∈ {0, MOVE_SPEED} — valeur binaire au sol (pas d'analogique). Par défaut : 0 ou 10 m/s.
**Exemple** : wish_dir = (1, 0, 0), MOVE_SPEED=10 → velocity.xz = (10, 0, 0). Relâchement input au tick T → velocity.xz = (0, 0) au tick T+1.

*Revision 2026-04-21 (Cluster A fix) : retiré la décélération linéaire 500 ms qui contredisait "snap crisp binaire" / anti-ref COD. Stop instantané garantit le feel staccato.*

### Déplacement horizontal (Airborne — air control)

```
air_wish = wish_dir.xz * MOVE_SPEED
velocity.xz = move_toward(velocity.xz, air_wish, AIR_CONTROL_FACTOR * delta)
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `AIR_CONTROL_FACTOR` | `k_air` | float | 30 – 80 m/s² | Accélération aérienne effective. Défaut 65 m/s² (~65% de contrôle à échelle Ghostrunner). **Note dimensionnelle** : `AIR_CONTROL_FACTOR` est passé comme 3ème argument de `move_toward(from, to, step)` où `step = k_air × delta` est exprimé en m/s (step maximal par tick). L'unité nominale m/s² se lit comme "step m/s divisé par delta s". **Attention implémentation** : ne PAS additionner `AIR_CONTROL_FACTOR × delta` à `velocity.xz` — utiliser exclusivement `move_toward` qui plafonne le step à la distance vers `air_wish`. |

**Output range** : en une seconde d'input Airborne constant, le joueur peut passer de `-MOVE_SPEED` à `+MOVE_SPEED` (delta de 20 m/s) en `20 / 65 ≈ 0.308 s` avec `k_air = 65` → contrôle responsif mais non-instantané. La trajectoire est *significativement* conservée : un saut lancé vers la gauche ne peut pas être intégralement réorienté vers la droite en plein vol.

*Revision 2026-04-21 (Cluster A + C fix) : remplacé "air control 100% identique au sol" qui (a) contredisait anti-référence Destiny 2, (b) annulait la difficulté de plateformes de timing (Pillar 4 gating), (c) contredisait le prototype qui implémente déjà `move_toward(air_accel=40)`. Nouvelle valeur 65 m/s² = recalibration Ghostrunner-like. Prototype doit être aligné à cette valeur.*

### Gravité (Normale vs Wall-run)

```
# Normale
velocity.y -= GRAVITY * delta

# Pendant WallRunning
velocity.y -= WALL_RUN_GRAVITY * delta
velocity.y = max(velocity.y, -WALL_RUN_FALL_CAP)
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `GRAVITY` | `g` | float | 22.0 – 32.0 m/s² | Gravité au sol et en air normal |
| `WALL_RUN_GRAVITY` | `g_w` | float | 3.0 – 6.0 m/s² | Gravité pendant wall-run |
| `WALL_RUN_FALL_CAP` | — | float | 2.0 – 4.0 m/s | Vitesse de chute max pendant wall-run |

**Output range** : `velocity.y` ∈ [-∞, +JUMP_VELOCITY] en normale ; ∈ [-WALL_RUN_FALL_CAP, +∞] en wall-run.
**Exemple** : après 0.5s de chute normale depuis velocity.y=0, GRAVITY=28 → velocity.y = -14 m/s. En wall-run pendant 0.5s avec g_w=4, cap=3 : velocity.y reste à max(-2, -3) = -2 m/s.

### Dash (déplacement instantané)

```
# Phase 1 — burst
dash_displacement = DASH_SPEED * DASH_DURATION
dash_distance_nominal = 28 * 0.10 = 2.80 m

# Phase 2 — exit momentum (décélération linéaire de DASH_EXIT_SPEED vers MOVE_SPEED
#            sur DASH_MOMENTUM_WINDOW) :
velocity.xz_exit = dash_dir * DASH_EXIT_SPEED             # initialisation à t=DASH_DURATION
speed(t) = DASH_EXIT_SPEED - (DASH_EXIT_SPEED - MOVE_SPEED) * (t / DASH_MOMENTUM_WINDOW)
                                                          # pour t ∈ [0, DASH_MOMENTUM_WINDOW]
d_momentum = (DASH_EXIT_SPEED + MOVE_SPEED) / 2 * DASH_MOMENTUM_WINDOW
d_momentum_nominal = (15 + 10) / 2 * 0.20 = 2.50 m

# Total chaîne dash → momentum
d_total = dash_distance + d_momentum
d_total_nominal = 2.80 + 2.50 = 5.30 m sur 0.30 s
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `DASH_SPEED` | `v_d` | float | **30.0 – 40.0 m/s** | Vitesse pendant le dash. Valeur nominale 28 m/s (à rebaser à ≥ 30 si MOVE_SPEED tuné à 12 — voir contrainte invariante ci-dessous). *Revision r3 : range min 24 → 30 pour couvrir tout le range MOVE_SPEED sans violation silencieuse de l'invariant × 2.5.* |
| `DASH_DURATION` | `t_d` | float | 0.08 – 0.14 s | Durée du burst. Valeur nominale 0.10 s (court pour masquer le mouvement visuellement). |
| `DASH_EXIT_SPEED` | `v_de` | float | 1.3× – 1.8× MOVE_SPEED | Vitesse horizontale à la fin du dash (conservation momentum). Défaut : `1.5 × MOVE_SPEED = 15 m/s` avec MOVE_SPEED=10. |
| `DASH_MOMENTUM_WINDOW` | `t_dm` | float | 0.15 – 0.30 s | Fenêtre de décélération linéaire de `DASH_EXIT_SPEED` vers `MOVE_SPEED`. Défaut 0.20 s. |
| `DASH_COOLDOWN` | `c_d` | float | 0.6 – 1.2 s | Cadence entre dashes. |

**Contrainte invariante (F1 systems-designer r3)** : `DASH_SPEED ≥ MOVE_SPEED × 2.5`. Au range courant (MOVE_SPEED ∈ [8, 12] ∧ DASH_SPEED ∈ [30, 40]), l'invariant est satisfait **partout** (30 ≥ 12 × 2.5 = 30, borne exacte). **Assertion à ajouter au `_ready()` du player** : `assert(DASH_SPEED >= MOVE_SPEED * 2.5, "DASH_SPEED viole l'invariant × 2.5")`.

**Contrainte invariante** : `DASH_COOLDOWN ≥ 4 × DASH_DURATION` (évite que le joueur soit en Dashing >25% du temps, ce qui casserait la tension tactique). Vérifié sur les coins : min_cooldown=0.6, max_duration=0.14 → 4×0.14=0.56 ≤ 0.6 ✓.

**Output range (recalculé)** :
- Burst (Phase 1) nominal : `28 × 0.10 = 2.80 m`, range [30×0.08, 40×0.14] = **[2.40 m, 5.60 m]**
- Momentum (Phase 2) nominal : `(15 + 10) / 2 × 0.20 = 2.50 m`, range min/max selon DASH_EXIT_SPEED et DASH_MOMENTUM_WINDOW.
- **Total chaîne nominal : 5.30 m sur 0.30 s** (pas 5.8 m comme précédemment annoncé — erreur arithmétique r2 corrigée).

*Revision r3 2026-04-21 (Cluster 3 fix) : (a) DASH_SPEED range min 24 → 30 pour supprimer la zone de violation silencieuse de l'invariant × 2.5 quand MOVE_SPEED > 9.6 ; (b) formule de décélération linéaire explicitée (était seulement qualitative en r2) ; (c) distance momentum corrigée 3 m → 2.50 m (intégrale correcte), total chaîne 5.8 m → 5.30 m.*

*Revision r1/r2 conservées : DASH_DURATION raccourci (0.15 → 0.10) pour feel "teleport" ; ajout `DASH_EXIT_SPEED` + `DASH_MOMENTUM_WINDOW` pour conservation momentum (retiré le cap abrupt à MOVE_SPEED).*

### Jump heights

```
max_jump_height = JUMP_VELOCITY² / (2 * GRAVITY)
max_single_jump (nominal r4) = 7.2² / (2 * 28) = 51.84 / 56 = 0.926 m

max_double_jump_height = JUMP_VELOCITY²/(2*GRAVITY) + AIR_JUMP_VELOCITY²/(2*GRAVITY)
max_double_jump (nominal r4) = 0.926 + 6.5²/56 = 0.926 + 0.754 = 1.680 m
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `JUMP_VELOCITY` | `v_j` | float | **7.2 – 8.5 m/s** | Vélocité verticale initiale du saut sol. *Revision r3 : min relevé de 7.0 à **7.2** pour respecter l'invariant `h ≥ 0.8 m` à GRAVITY=32 (ancien min 7.0 donnait h=0.766 m, marge RÉELLE -0.034 m malgré la déclaration r2 "+0.2 m" — erreur arithmétique corrigée).* |
| `AIR_JUMP_VELOCITY` | `v_aj` | float | 5.5 – 7.5 m/s | Vélocité verticale du double saut. |

**Contrainte invariante** : `JUMP_VELOCITY² / (2 × GRAVITY_MAX) ≥ 0.8 m` — le saut simple doit franchir un obstacle bas standard (0.8 m) à la gravité maximale. À GRAVITY=32, cela impose `JUMP_VELOCITY ≥ √(2 × 32 × 0.8) ≈ 7.155 m/s`. Le range min **7.2 m/s** donne `h = 7.2² / 64 = 0.810 m`, marge **+0.010 m** (vs -0.034 m avec l'ancien min 7.0). Arrondi au 0.1 supérieur pour tuning UX.

**Output range (recalculé r4)** :
- Single jump : min = 7.2²/(2×32) = **0.810 m** · nominal = 7.2²/(2×28) = **0.926 m** · max = 8.5²/(2×22) = **1.642 m**
- Combo jump (sol + double) : min = 0.810 + 5.5²/(2×32) = 0.810 + 0.473 = **1.283 m** · nominal = 0.926 + 6.5²/(2×28) = **1.680 m** · max = 1.642 + 7.5²/(2×22) = 1.642 + 1.279 = **2.921 m**

*Revision r3 2026-04-21 (Cluster 3 fix) : JUMP_VELOCITY range min 7.0 → 7.2 pour éliminer la violation silencieuse de l'invariant à GRAVITY max. Marge r2 annoncée "+0.2 m" corrigée : la valeur réelle était -0.034 m (violation), maintenant +0.010 m (respect strict). Output range min recalculé 0.766 m → 0.810 m ; combo jump min 1.239 m → 1.283 m.*

*Revision r4 2026-04-23 (P1 #2 post-review) : valeur nominale JUMP_VELOCITY rebasée 7.0 → 7.2 m/s (alignement sur le range min publié). Nominal single jump 0.875 → 0.926 m ; nominal combo 1.629 → 1.680 m. L'ancienne valeur 7.0 était un vestige de prototype sous le range r3 — l'exemple prototype ligne 264 reste historique (doit être re-validé au prototype movement-katana avant Sprint 1, cf. ADR-0001 Migration Plan action #2).*

*Revision r2 conservée : Level Grid Spec (design/levels/level-grid-spec.md) fige les hauteurs d'obstacle sur cette plage de saut.*

**Exemple historique (prototype r1, à re-valider Sprint 1)** : avec valeurs prototype (JUMP_VELOCITY=7.0 / AIR_JUMP_VELOCITY=6.5 / GRAVITY=28), combo max ≈ 1.63 m. Un obstacle de hauteur 1.7 m (body height) n'est PAS franchissable en combo — oblige à wall-run/dash. Volontaire : force l'usage du moveset gated (cf. Level Grid Spec, obstacle tiers). **r4** : le prototype doit être rebasé à JUMP_VELOCITY=7.2 avant Sprint 1 (cohérence avec le range r3 publié + valeur nominale r4). Nouveau combo nominal = 1.680 m — l'obstacle 1.7 m reste non franchissable en combo (marge 20 mm), comportement inchangé.

### Wall-jump (trajectoire)

```
velocity = wall_normal * WALL_JUMP_SIDE
velocity.y = WALL_JUMP_UP
# trajectoire parabolique standard ensuite sous GRAVITY
```

**Output range** : distance horizontale d'un wall-jump, calculée sur tout le safe range = `WALL_JUMP_SIDE * (2 * WALL_JUMP_UP / GRAVITY)`
- Min : 5 × (2 × 5 / 32) = **1.56 m**
- Nominal : 7 × (2 × 6.5 / 28) = **3.25 m**
- Max : 9 × (2 × 8 / 22) = **6.55 m**

**Contrainte level design (revised r3)** : le wall-jump **bloque le double-jump** (cf. Rule 8, décision Martin r3 A) — impossible de chaîner wall-jump → double-jump. Par conséquent, **tous les couloirs parallèles MVP doivent être ≤ 3.25 m** (wall-jump nominal seul). Level Grid Spec (`design/levels/level-grid-spec.md`) est mis à jour en conséquence : couloir 4 m du prototype r1 retiré du MVP, remplacé par couloir 3.0 m (marge 0.25 m pour le tuning). **Contrainte invariante wall-jump height** (F12 systems-designer) : `WALL_JUMP_UP² / (2 × GRAVITY_MAX) ≥ JUMP_VELOCITY² / (2 × GRAVITY_MAX) × 0.7` — le wall-jump doit gagner au moins 70 % de la hauteur d'un single jump à gravité max, sinon le wall-jump devient purement horizontal et inutile verticalement. À GRAVITY=32, impose `WALL_JUMP_UP ≥ 0.837 × JUMP_VELOCITY` ; avec `JUMP_VELOCITY_min=7.2`, `WALL_JUMP_UP_min ≥ 6.03 m/s` — range actuel min 5.0 viole l'invariant ; **range min à relever de 5.0 à 6.0 m/s** (voir Tuning Knobs).

*Revision r3 2026-04-21 (Clusters 2+3 fix) : couloir 4 m → 3.25 m suite décision Martin A (wall-jump bloque double-jump) ; contrainte invariante wall-jump height ajoutée ; range min `WALL_JUMP_UP` relevé de 5.0 à 6.0 m/s.*

## Edge Cases

- **Dash pressé pendant wall-run** : le dash gagne. `is_wall_running = false`, entrée en Dashing, `wall_normal` reset. Raison : le dash est la ressource avec cooldown (choix conscient), le wall-run est passif (contexte environnemental) — la décision gagne le contexte.
- **Jump pressé simultanément au tick où wall-run s'active** : wall-jump gagne sur double-jump, car `is_wall_running` est vérifié avant `air_jumps_used`. Raison : exploiter la paroi donne plus de distance horizontale — c'est ce que le joueur voulait s'il longe une paroi.
- **Dash dans un mur** : CharacterBody3D + `move_and_slide()` absorbe la collision, le perso glisse le long du mur au lieu de traverser. Le `dash_timer` continue normalement. À la fin du dash, la vélocité horizontale passe à `dash_dir * DASH_EXIT_SPEED` — si le mur bloque toujours, `move_and_slide` la consomme et le joueur retrouve le contrôle immédiatement après.
- **Dash en cours pendant respawn delay** : si `die()` est appelé pendant Dashing, le système transite directement Dashing → Dead (pas via Grounded/Airborne intermédiaire) pour éviter tout état transitoire.
- **`velocity.y` à l'entrée en Dashing** : explicitement réinitialisé à 0.0 (voir Rule 6) pour que le dash soit strictement horizontal quel que soit l'état antérieur (saut en cours, chute, etc.).
- **Dash direction par défaut quand wish_dir vide** : `forward` = direction horizontale basée sur `transform.basis.z` du CharacterBody3D (body rotation Y uniquement, PAS `camera.basis.z` qui inclurait le pitch). Un joueur qui regarde vers le haut et dash sans input directionnel avance horizontalement, il ne s'envole pas.
- **Respawn pendant un dash** : `respawn()` doit reset `is_dashing=false`, `dash_timer=0`, `dash_cooldown_timer=DASH_COOLDOWN/2` (partial cooldown — pas full reset, pour ne pas punir la mort). `air_jumps_used=0`.
- **Respawn après mort standard (hors Dashing)** : `respawn()` remet `dash_cooldown_timer = 0` (dash immédiatement disponible au retry — favorise la rétention de flow, cohérent avec Pillar 3). `air_jumps_used = 0`. Distinguer ce cas de "Respawn pendant un dash" ci-dessus qui applique un cooldown partiel pour ne pas offrir de dash gratuit au retry. *AC edge case ajouté r3 (game-designer F9).*
- **Respawn en wall-run** : reset tous les états (`is_wall_running=false`, `wall_normal=Vector3.ZERO`). Le nouveau spawn remet le joueur à `checkpoint.position`, au sol.
- **Input `jump` tenu (hold) vs tapé (tap)** : le système utilise **just_pressed** (edge-triggered). Un hold ne saute pas en continu ; il faut relâcher + retap pour sauter à nouveau. Raison : feel staccato, pas platformer arcade à saut continu.
- **Input `move` opposé simultané (gauche + droite)** : `Input.get_vector` renvoie Vector2.ZERO, donc le perso s'arrête. Pas de tie-breaker nécessaire.
- **Plateforme mobile / en rotation sous le joueur** : hors scope MVP (niveaux hand-crafted statiques). Si introduit post-MVP, la vélocité de la plateforme doit être ajoutée à `velocity` au moment du `is_on_floor()` — à réévaluer en design doc dédié.
- **Jump buffer pendant dash [POST-MVP]** : si `jump` est pressé pendant Dashing, le buffer démarre à la fin du dash → si `is_on_floor()` à ce moment, saut exécuté automatiquement. Sinon, le buffer expire sans effet. *Hors MVP : jump buffer lui-même est post-MVP (décision Martin r2, cf. Rule 5). Conservé en Edge Cases pour référence lors de l'introduction post-MVP.*
- **Coyote time pendant wall-run** : inapplicable — quitter wall-run ne déclenche pas le coyote timer, car le wall-jump est l'affordance prévue. Le coyote ne s'active qu'en quittant Grounded sans jump délibéré.
- **Deux `dash` pressés en < 0.8 s** : le second est ignoré (cooldown). Un feedback audio court et discret est joué (`dash_reject.wav`, 30 ms, -12 dB — cf. Visual/Audio Requirements) pour affordance accessibilité.
- **`RESPAWN_DELAY` configuré sous 1 frame d'affichage (< 16.6 ms à 60 Hz)** : les consommateurs `CONNECT_DEFERRED` du signal `died` (VFX, Audio, HUD) risquent de ne pas recevoir leur callback avant `respawn()`. Le feedback de mort n'est pas garanti. **Minimum strict requis** : `RESPAWN_DELAY ≥ 1 / DISPLAY_TICK_RATE`. La valeur courante 50 ms respecte largement ce minimum (3 frames à 60 Hz). *AC edge case ajouté r3 (game-designer F7).*
- **Joueur spawn dans le vide (au-dessus d'un pit)** : si le checkpoint a été placé au mauvais endroit, le joueur tombe et meurt → re-respawn au même checkpoint → boucle infinie. *C'est un bug de level design, pas de movement.* Level System doit valider que chaque checkpoint pointe sur une surface solide.
- **Vélocité NaN ou Infinity** (bug edge) : à chaque tick, **après** toute modification de vélocité (movement, gravité, dash) mais **avant** `move_and_slide()`, tester `if not velocity.is_finite(): push_error("velocity NaN/Inf detected — reset to zero"); velocity = Vector3.ZERO`. *Revision r3 (godot-specialist F8) : remplacé l'ancien `clamp(velocity, -50, 50)` qui (a) ne détectait pas NaN de façon fiable (`clamp(NaN, -50, 50)` retourne NaN en IEEE 754), (b) limitait artificiellement la vitesse de chute légitime dans des pits profonds (à GRAVITY=28, -50 m/s atteint en 1.79 s de chute libre) et interférait avec le Jolt resolver sur surfaces inclinées à grande vitesse. `is_finite()` cible uniquement les bugs réels.*
- **Camera rotation.x atteint ±PI/2** : clampée à ±(PI/2 - 0.05) pour éviter le gimbal lock dans la camera FPS. Présent dans le prototype.
- **Mouse motion pendant la pause ou respawn delay** : les inputs d'action sont ignorés, mais la rotation de la tête (mouse look) reste appliquée *en pause* pour éviter le "saut de vue" au unpause. *Respawn delay* = inputs **et** rotation figés. **Cascade cross-doc Input GDD** : le Input System DOIT exposer un flag `emit_mouse_during_disable: bool` (ou équivalent sémantique — nom à confirmer au GDD Input) pour que cette distinction soit implémentable. Sans cette API, pause et respawn ne sont pas distinguables côté Input. Référencé comme blocker r2 #2 (cross-doc) — à lever à la révision du Input System GDD.
- **`die()` appelé pendant `Dead`** : ignoré (idempotent). Raison : plusieurs hazards peuvent overlapper pendant le même tick ; on ne veut qu'une seule mort.

## Dependencies

| Système | Direction | Nature de la dépendance |
|---|---|---|
| **Input System** | Amont (ce système consomme) | Actions abstraites : `move_*`, `jump`, `dash`, `restart`, `ui_cancel` + `mouse_motion`. Si Input change le nom d'une action, Movement casse. |
| **Upgrade System** | Amont (ce système consomme) | Flags `can_air_jump`, `can_dash`, `can_wall_run`. Interface unidirectionnelle via capability API. Movement n'appelle jamais Upgrade. |
| **Checkpoint & Respawn System** | Bidirectionnel | Movement appelle `Checkpoint.get_current_position()` pour respawn ; Checkpoint appelle `Player.set_checkpoint(pos)` aux triggers. Ownership du checkpoint current = Checkpoint. |
| **Camera System** | Aval (ce système est consommé) | Lit `velocity`, `state`, `is_dashing` pour appliquer head-bob / wall-run tilt / dash FOV pulse. |
| **Player Combat System** | Aval | Lit `velocity` et `transform.basis` pour swept hitbox katana. Consomme aussi le signal `attacked` (que le Movement forward depuis input). |
| **Hazard System** | Aval (appelle `die()`) | Les lasers et pits appellent `Player.die()` au contact. |
| **Enemy System** | Aval (appelle `die()`) | Les lasers d'ennemis appellent `Player.die()` au contact. |
| **VFX & Feedback System** | Aval (écoute signals) | Écoute `dash_started`, `dash_ended`, `wall_run_entered`, `wall_run_exited`, `died`, `respawned` pour déclencher les effets. |
| **Audio System** | Aval (écoute signals) | Mêmes signals que VFX pour SFX. |
| **HUD System** | Aval | Lit `dash_cooldown_ratio` et `state` pour affichage. |
| **AccessibilityService** (ADR-0015 D-1) | Amont (consommé par Camera via signal `settings_changed`) | Movement délègue les effets visuels `reduce_motion` / `reduce_flash` à Camera System (Rule 14), qui pull les valeurs depuis `AccessibilityService.get_camera_tilt_mult()` / `get_camera_fov_kick_mult()` / `get_camera_shake_mult()`. Movement ne lit pas directement le service (voir tableau D-4 ADR-0015 : `MovementController` — aucun appel direct). |

**Note de cohérence bidirectionnelle** : chaque dépendance listée ci-dessus DOIT apparaître dans le GDD de l'autre système (à rédiger). Au moment de ce GDD, aucun des autres GDDs n'existe encore — toutes ces interfaces sont *provisoires* et doivent être confirmées ou révisées quand les GDDs amont/aval sont écrits.

## Tuning Knobs

| Paramètre | Valeur courante | Safe Range | Effet si augmenté | Effet si diminué |
|---|---|---|---|---|
| `MOVE_SPEED` | 10.0 m/s | 8.0 – 12.0 | Plus rapide au sol, gaps plus faciles à franchir sans dash, niveau paraît petit | Plus lent, gaps trop grands, FLOW compromis |
| `JUMP_VELOCITY` | 7.2 m/s | **7.2 – 8.5** | Sauts plus hauts, level design doit scaler verticalement | Sauts bas, obligation de combo double-jump plus tôt. *r3 : range min 6.0 → 7.2 pour respecter `h ≥ 0.8 m` à GRAVITY=32 — voir Formulas.* *r4 (P1 #2) : valeur nominale rebasée 7.0 → 7.2 pour s'aligner sur le range min — l'ancien 7.0 était un vestige de prototype sous le range publié. Nominal recalculé single=0.926 m, combo=1.680 m.* |
| `AIR_JUMP_VELOCITY` | 6.5 m/s | 5.5 – 7.5 | Double-jump plus puissant, réduit l'utilité du wall-run | Double-jump anémique, wall-run devient vital |
| `GRAVITY` | 28.0 m/s² | 22.0 – 32.0 | Chute sèche, "poids", sentiment d'urgence | Flottement, viole Pillar 1 |
| `WALL_RUN_GRAVITY` | 4.0 m/s² | 3.0 – 6.0 | Wall-run glisse plus longtemps, sticky | Wall-run trop court, dur à déclencher |
| `WALL_RUN_FALL_CAP` | 3.0 m/s | 2.0 – 4.0 | Cap laxiste, chute en wall-run visible | Cap strict, effet "sticky vertical" appuyé |
| `WALL_RUN_MIN_SPEED` | 5.0 m/s | 4.0 – 7.0 | Wall-run déclenché plus facilement, même après dash mou | Wall-run exigeant, force la course avant le mur |
| `WALL_RUN_MAX_DURATION` | 1.5 s | 1.0 – 2.5 | Évite le camping infini contre les boss | Trop court → wall-run qui coupe au milieu d'une chaîne |
| `WALL_JUMP_SIDE` | 7.0 m/s | 5.0 – 9.0 | Ejection horizontale forte, saute d'un mur à l'autre | Wall-jump mou, descend plus vite |
| `WALL_JUMP_UP` | 6.5 m/s | **6.0 – 8.0** | Wall-jump gagne de la hauteur | Wall-jump reste horizontal. *r3 : range min 5.0 → 6.0 pour respecter l'invariant `h_walljump ≥ 0.7 × h_single_jump` à GRAVITY max — voir Formulas.* |
| `DASH_SPEED` | 28.0 m/s† | **30.0 – 40.0** | Dash couvre plus de distance, trop tolérant aux erreurs | Dash court, exige précision de wish_dir. *r3 : range min 24 → 30 pour respecter `DASH_SPEED ≥ MOVE_SPEED × 2.5` sur tout le range MOVE_SPEED. **†** Valeur courante 28 < range min 30 — à rebaser à 30 m/s minimum OU documenter comme exception prototype avec MOVE_SPEED=10 (28 ≥ 25 OK à MOVE_SPEED=10 mais viole si MOVE_SPEED tuné à 12).* |
| `DASH_DURATION` | **0.10 s** | **0.08 – 0.14** | Dash long, "glissé", moins snap (viole Pillar 1) | Dash ultra-court, peut paraître raté visuellement |
| `DASH_EXIT_SPEED` | 15.0 m/s | 1.3× – 1.8× MOVE_SPEED | Momentum fort post-dash, chaînes fluides | Chaînes cassées, frein perçu |
| `DASH_MOMENTUM_WINDOW` | 0.20 s | 0.15 – 0.30 | Momentum conservé longtemps, dash→wall-run facile | Reprise immédiate de MOVE_SPEED, chaînes plus dures |
| `DASH_COOLDOWN` | 0.8 s | 0.6 – 1.2 | Dash moins spammable, plus de planification | Dash quasi-infini, casse la tension |
| `AIR_CONTROL_FACTOR` | **65.0 m/s²** | 30.0 – 80.0 | Air control fort, trajectoire très modifiable | Air control réduit, commit directionnel au saut |
| `COYOTE_TIME` | 0.10 s | 0.06 – 0.15 | Tolérance aux inputs tardifs, "forgiveness" | Jeu plus punitif, frustration |
| `JUMP_BUFFER` **[POST-MVP]** | 0.10 s | 0.06 – 0.15 | Inputs pré-anticipés honorés, feel "magique" | Inputs perdus, sensation d'input rate. *r3 : feature POST-MVP (décision Martin r2). Tuning knob conservé pour référence post-MVP.* |
| `RESPAWN_DELAY` | **0.05 s** | **0.03 – 0.2** | Plus de temps pour digérer la mort, feedback visible (mais viole Pillar 3 si > 0.3 s) | Pas le temps de *sentir* qu'on est mort ; attribution causale à valider par AC playtest. *r3 : décision Martin r3 A — 0.2 → 0.05 s, safe range ajusté. `RESPAWN_DELAY ≥ 1/DISPLAY_TICK_RATE` impératif (cf. Edge Cases).* |
| `MAX_AIR_JUMPS` | 1 | 1 – 2 | Triple-jump post-shop unlock possible | Pas d'air-jump = gated Upgrade ne change rien |

**Interactions notables & contraintes invariantes (r3 consolidé)** :
- **Invariant** `DASH_SPEED ≥ MOVE_SPEED × 2.5` — le dash doit rester significativement plus rapide que la course. Range r3 min DASH_SPEED = 30, range max MOVE_SPEED = 12 → 30 ≥ 30 à la borne exacte. Assertion runtime à ajouter : `assert(DASH_SPEED >= MOVE_SPEED * 2.5)`.
- **Invariant** `DASH_COOLDOWN ≥ 4 × DASH_DURATION` — évite que le joueur soit en Dashing >25% du temps. Vérifié aux coins : 0.6 ≥ 4 × 0.14 = 0.56 ✓.
- **Invariant** `JUMP_VELOCITY² / (2 × GRAVITY_MAX) ≥ 0.8 m` — garantit que le saut simple franchit un obstacle bas standard (cf. Level Grid Spec). Range r3 min JUMP_VELOCITY=7.2 ; `7.2²/(2×32) = 0.810 m` ≥ 0.8 m ✓ (marge +0.010 m).
- **Invariant (nouveau r3)** `WALL_JUMP_UP² / (2 × GRAVITY_MAX) ≥ 0.7 × JUMP_VELOCITY² / (2 × GRAVITY_MAX)` — le wall-jump doit gagner au moins 70% de la hauteur d'un single jump à gravité max. Range r3 min WALL_JUMP_UP=6.0 ; `6.0²/(2×32) = 0.5625 m ≥ 0.7 × 0.810 = 0.567 m` — **très borderline** (marge -0.004 m), range min effectif ≈ 6.03 m/s. À surveiller au tuning.
- **Invariant** `GRAVITY > WALL_RUN_GRAVITY` — triviallement respecté (max WALL_RUN_GRAVITY = 6.0 vs min GRAVITY = 22.0).
- **Invariant (nouveau r3)** `RESPAWN_DELAY ≥ 1 / DISPLAY_TICK_RATE` — garantit que les consommateurs CONNECT_DEFERRED reçoivent le signal `died` avant `respawn()`. À 60 Hz affichage, min = 16.6 ms. Valeur courante 50 ms ≫ min ✓.
- Augmenter `GRAVITY` sans toucher `JUMP_VELOCITY` réduit la hauteur max et le temps en l'air → oblige à re-tuner les gaps du level.

Tous ces knobs doivent vivre dans une `Resource` (`movement_tuning.tres`). **Pattern hot-reload Godot 4.6** : exposer la ressource via `@export var tuning: MovementTuning : set = _on_tuning_changed` sur le player script. Modification dans l'Inspector éditeur pendant play déclenche le setter et propage les valeurs. **Hot-reload via modification directe du `.tres` sur disque** : fonctionne **uniquement en editor mode** (Godot 4.6 `ResourceFilesystem` détecte et reimporte). Ne fonctionne **pas en play mode** — nécessite le setter Inspector ou un reload explicite de scène. *Revision r3 (godot-specialist F9) : précision du scope editor vs play.*

> **Settings owned by Input System** : `mouse_sensitivity` (anciennement listé ici sous `MOUSE_SENS`) est désormais **owned par l'Input System** (`design/gdd/input-system.md` — section Tuning Knobs). Movement le *consomme* pour calculer le yaw horizontal du joueur (`yaw_delta = mouse_motion.x * mouse_sensitivity`) mais ne le possède plus. Valeur cross-system : **0.0022 rad/px** (safe range **0.0005 – 0.012** — élargi r2 Input GDD 2026-04-21 pour couvrir high-sens FPS et low-sens sniper ; ancien range 0.0010–0.0050 obsolète). Source de vérité : `design/registry/entities.yaml` → constants.

## Visual/Audio Requirements

| Événement | Feedback visuel | Feedback audio | Priorité |
|---|---|---|---|
| Pas (Grounded, moving) | Aucun visuel (FPS) | `footstep_*.wav` rotatif, 2 Hz à MOVE_SPEED normal | Low — peut être omis MVP |
| Saut sol | Aucun | `jump.wav` court | Medium |
| Double-jump | Légère trail verticale (50 ms) | `air_jump.wav` synthé, plus aigu que saut sol | High — distingue les deux sauts |
| Dash démarre | Trail linéaire 0.3 s dans `dash_dir`, vignette latérale FOV pulse 90 → 100 → 90 (owned par Camera System : `BASE_FOV=90°`, `DASH_FOV_KICK=10°`) | `dash_whoosh.wav` 200 ms | Critical — feel signature |
| Dash finit | Trail se dissout | `dash_out.wav` bref (optionnel) | Low |
| Wall-run entre | Camera tilt vers le mur (angle + timings owned par Camera GDD `WALL_RUN_TILT_ANGLE`, `TILT_LERP_SPEED`), particules étincelles au point de contact | `wall_run_enter.wav` — whoosh grave | High |
| Wall-run sort | Camera tilt revient à 0 (timing owned par Camera GDD) | Fade du whoosh | Medium |
| Wall-jump | Camera kick latéral + trail (magnitude owned par Camera GDD `WALL_JUMP_KICK_MAGNITUDE`) | `wall_jump.wav` — punchy, plus fort que wall-run enter | High |
| Mort | Fondu rouge plein écran en **≤ 40 ms** (aligné sur `RESPAWN_DELAY`=50 ms), freeze input | `death.wav` **≤ 40 ms** (court pour ne pas être tronqué par le respawn quasi-instantané) | Critical |
| Respawn | Flash blanc inversé ≤ 30 ms au spawn (laisse marge pour le delta visuel) | `respawn_pop.wav` ≤ 40 ms | Critical |

> Détail VFX/animation à élaborer dans un art-bible section dédiée (non priorité MVP tant que art-bible n'est pas à jour).

### Accessibility Options (MVP-required)

*Revision 2026-04-21 (Cluster G fix) : tous les effets visuels ci-dessus doivent respecter deux toggles accessibilité non-optionnels pour un release Steam — conformité WCAG 2.3.1 + 2.3.3.*

| Toggle | Par défaut | Effet quand activé |
|---|---|---|
| **`reduce_flash`** (conformité photosensible) | OFF | Remplace le fondu rouge mort (≤40 ms, haute saturation) par un assombrissement progressif gris neutre non-saturé (80-120 ms, contraste ≤ 3:1). Remplace le flash blanc respawn (≤30 ms) par un fade-in neutre (100 ms). Aucun flash plein écran > 3 Hz autorisé. *r3 : durées alignées sur `RESPAWN_DELAY=50 ms` courant ; le reduce_flash prolonge légèrement le feedback (80-120 ms) au prix d'un léger retard perceptuel acceptable pour les joueurs photosensibles.* |
| **`reduce_motion`** (confort vestibulaire) | OFF | Multiplicateurs appliqués par Camera GDD Rule 14 : tilt wall-run `× 0.25`, FOV pulse dash `× 0.5` (peak ≤ 95°), shake wall-jump `× 0`. Valeurs numériques owned par Camera GDD (voir Camera Rule 14 + Tuning Knobs). |

Les valeurs alternatives sont des `tuning_knobs` dans `movement_tuning.tres` (ou dans un `accessibility_settings.tres` séparé) et doivent être exposées dans le menu principal (pas seulement pendant gameplay). Le toggle **MUST** être accessible dès le premier lancement, avant tout gameplay.

**Tier coverage (ADR-0015 D-1 — `AccessibilityService` autoload single-source-of-truth)** :

| Feature accessibility | Tier | Source-of-truth | Notes |
|---|---|---|---|
| `reduce_motion` (tilt wall-run × 0.25, FOV dash × 0.5, shake × 0) | Tier 1 — Baseline (MVP-required) | `AccessibilityService.get_camera_tilt_mult()` / `get_camera_fov_kick_mult()` / `get_camera_shake_mult()` — délégation à Camera System Rule 14 | Movement ne lit pas le service directement (ADR-0015 D-4) |
| `reduce_flash` (fondu rouge → assombrissement gris 80-120 ms ; flash respawn → fade neutre 100 ms) | Tier 1 — Baseline (MVP-required) | `AccessibilityService.is_reduce_flash_enabled()` — consommé par VFX System lors des événements `died` / `respawned` | WCAG 2.3.1 + 2.3.3 |
| `dash_reject.wav` feedback cooldown (AC-MV gap accessibilité malvoyants) | Tier 1 — Baseline (MVP-required) | Audio System (signal `dash_rejected` Movement → Audio) | Pas de dépendance `AccessibilityService` — toujours actif |
| Input remapping (`move_*`, `jump`, `dash`) | Tier 2 — Expanded (post-MVP) | Input System GDD — ADR-0004 OQ-INP-X | ADR-0015 OQ-ACC-6 : sticky keys / hold-to-toggle Tier 2+ Input remap epic |
| `slow_mo_air` aerial slow-motion | Tier 2 — Expanded (post-MVP) | `aerial-slowmo-system.md` (à écrire) + `AccessibilityService.get_slow_mo_scale_mult()` | Hors scope MVP Movement GDD |
| Sticky keys / hold-to-toggle inputs | Tier 2 — Expanded (post-MVP) | ADR-0004 (Input remap epic) | ADR-0015 OQ-ACC-6 |
| Screen reader / AccessKit integration | Tier 3 — Advanced | Godot 4.5+ AccessKit natif Control nodes + `AccessibilityService.is_screen_reader_active()` (futur) | Tier 3 — ADR-0015 OQ-ACC-5 |

📌 **Asset Spec** — Visual/Audio requirements sont définis. Après que l'art bible soit approuvée, lancer `/asset-spec system:player-movement-system` pour produire les specs per-asset.

📌 **Cooldown feedback input raté** : reversal de la décision précédente ("aucun feedback audio pour input raté") — la review UX a identifié cela comme gap d'accessibilité bloquant pour joueurs malvoyants. Un son sec court de très faible volume (`dash_reject.wav`, 30 ms, -12 dB) sera joué quand `dash` est pressé pendant cooldown. Garde le feedback universel sans saturer le sound design.

## Game Feel

### Feel Reference

Ghostrunner (2020) — spécifiquement le dash horizontal et le wall-run court. Le dash doit te *téléporter* 4 m plus loin sans te donner l'impression de "glisser". Le wall-run doit *coller* la vue au mur pendant qu'il dure, pas proposer une simulation de friction.

Anti-référence : Destiny 2 saut flotté (trop de temps en l'air, trop de correction en l'air). Halo melee (le perso se déplace légèrement pendant le coup — non, on ne veut pas ça). COD glisse après arrêt — jamais.

### Input Responsiveness

| Action | Max Input-to-Response Latency | Frame Budget (@60Hz physique / 60fps affichage, ref: ADR-0001) | Notes |
|---|---|---|---|
| Mouse look | ≤ 16 ms | 1 frame affichage | Direct dans `_unhandled_input`, pas dans `_physics_process` |
| Move start (WASD edge) | ≤ 16 ms | ≤ 1 frame | Polling dans `_physics_process` à 60 Hz = 16.6 ms worst-case (ref: ADR-0001) |
| Jump | ≤ 16 ms | ≤ 1 frame | just_pressed consomé au tick suivant |
| Dash | ≤ 16 ms | ≤ 1 frame | Critical : signature FLOW |
| Katana attack | ≤ 16 ms | ≤ 1 frame | Cf. Player Combat GDD |

Si playtest mesure > 1 frame (via HUD live mesure présente au prototype), **escalader** — c'est un bloqueur Pillar 1.

### Animation Feel Targets

Le Player Movement System n'a **pas d'animations de personnage FPS visibles** (vue FPS, pas de ragdoll, pas de viewmodel mouvement hors camera). Seules animations : transitions camera (tilt, FOV pulse) et viewmodel katana.

| Animation | Startup | Active | Recovery | Feel Goal | Notes |
|---|---|---|---|---|---|
| Camera wall-run tilt | *(timings owned par Camera GDD `TILT_LERP_SPEED`)* | (maintenu) | *(timings owned par Camera GDD)* | Sticky, confortable | Interp ease-out, pas linear. **Appliqué sur `CameraEffects: Node3D.rotation.z`** (nœud intermédiaire dédié aux effets, distinct de `CameraArm` qui porte pitch et head-bob — évite les conflits Tween sur la même propriété, voir Camera GDD). |
| Camera dash FOV pulse | *(snap — owned par Camera GDD)* | *(timings owned par Camera GDD `DASH_FOV_LERP_SPEED`)* | *(owned par Camera GDD)* | Snap-in, ease-out | Pulse `BASE_FOV` → `BASE_FOV + DASH_FOV_KICK` → `BASE_FOV`, owned par Camera System. |
| Camera death fade | 0 s (snap) | ≤ 40 ms | (jusqu'à respawn) | Immédiat, punitif | Rouge sombre plein écran. *r3 : durée ≤ 40 ms alignée sur RESPAWN_DELAY=50 ms.* |

**Hiérarchie camera recommandée (revised r3 godot-specialist F3)** :
```
CharacterBody3D (rotation.y = yaw body)
└── CameraArm: Node3D (rotation.x = pitch, position.y = head-bob)
    └── CameraEffects: Node3D (rotation.z = wall-run tilt)
        └── Camera3D
```
Séparer `CameraEffects` du `CameraArm` évite le conflit : head-bob et wall-run tilt n'opèrent plus sur la même propriété du même nœud. Permet de composer plusieurs effets simultanément sans Tween écrasé.

### Impact Moments

| Type | Durée | Description | Configurable ? |
|---|---|---|---|
| Hit-stop (dash vs wall) | 0 ms | **Aucun** — dash dans un mur n'a pas de feedback spécial. Juste glisse. | N/A |
| Screen shake (wall-jump) | 100 ms | Mini-kick vertical 0.5°, atténuation exp | Oui (intensité) |
| Camera impact (death) | 0 ms (instant fade) | Pas de ragdoll, fondu direct | Non |
| Controller rumble | Non scopé MVP (clavier primary) | — | — |
| Time-scale slowdown | 0 ms pour le mouvement (la slow-mo aérienne = upgrade future distincte, pas ce GDD) | — | — |

### Weight and Responsiveness Profile

- **Weight** : **Léger**. Pas de simulation de masse. Au sol, zéro inertie — stop instantané quand input relâché. En l'air : légère conservation trajectoire (AIR_CONTROL_FACTOR=65 m/s² ~ 65% de contrôle Ghostrunner-like). Post-dash : momentum conservé via DASH_EXIT_SPEED (15 m/s) pendant DASH_MOMENTUM_WINDOW (200 ms).
- **Contrôle joueur** : **Élevé en Ground / Mesuré en Airborne**. Au sol : stop/start binaire immédiat. En l'air : le joueur peut modifier la trajectoire mais pas l'inverser instantanément (commit directionnel partiel au saut). Seul l'état Dashing retire le contrôle intégral, et seulement pour 100 ms.
- **Snap quality** : **Crisp et binaire au sol, légèrement analog en l'air**. Ground = start/stop immédiats. Dash = burst instantané + momentum exit. Air = contrôle ~65% (Ghostrunner-like), pas d'inversion brutale de trajectoire.
- **Modèle d'accélération** : **Arcade au sol, recentré en l'air**. Ground velocity = wish_dir * MOVE_SPEED (binaire, pas d'analogique). Air velocity = move_toward(velocity, wish_dir * MOVE_SPEED, AIR_CONTROL_FACTOR * delta). *Revision 2026-04-21 : ancien "100% air control" corrigé — préserve la difficulté de plateformes de timing (Pillar 4) et aligne formule avec prototype.*
- **Texture d'échec** : **Lecteur de la faute immédiat**. Si le joueur meurt, le laser/ennemi qui l'a tué reste visible à l'écran pendant le respawn delay → "j'ai raté le dash, j'étais trop lent". Jamais "le jeu ne m'a pas obéi".

### Feel Acceptance Criteria

*Revision 2026-04-21 (Cluster E fix) : ACs feel réécrits avec méthodologie concrète — n'étaient pas testables dans leur version initiale.*

- [ ] **Feel playtest** (type : Visual/Feel — ADVISORY) : GIVEN un groupe d'au moins 5 playtesters complète 10 minutes de jeu en session libre (sans instruction de mouvement), WHEN leurs retours verbaux sont collectés via grille d'observation structurée, THEN **moins de 20%** des playtesters prononcent l'un des mots-clés négatifs : "floaty", "slippery", "unresponsive", "raté", "stuck". Evidence : grille + signature QA Lead dans `production/qa/evidence/`.
- [ ] **Latence input→vélocité** (Logic — BLOCKING) : GIVEN debug build headless, WHEN un script GUT exécute 200 inputs `dash` instrumentés (`Time.get_ticks_usec()` entre `_unhandled_input` event et tick `_physics_process` où `velocity == dash_dir * DASH_SPEED`), THEN moyenne ≤ 12 ms et P99 ≤ 16 ms sur les 200 échantillons.
- [ ] **Respawn total** (Integration — BLOCKING) : GIVEN n'importe quel état vivant, WHEN `die()` est appelé, THEN le timestamp entre `die()` et le premier `_physics_process` tick où `state == GROUNDED AND inputs_accepted == true` est **< 100 ms** (budget : `RESPAWN_DELAY=50 ms` + 1 physics tick à 60 Hz = 16.6 ms + checkpoint lookup < 1 ms + state reset < 1 ms ≈ 70 ms théorique, marge 30 ms). Mesure GUT. *r3 : seuil 2000 ms → 100 ms — serre le budget pour que l'AC protège réellement l'ambition Pillar 3, ancien seuil laxiste 40× la valeur attendue.*
- [ ] **Attribution causale mort (garde-fou 50 ms)** (Visual/Feel — ADVISORY) : GIVEN 5 joueurs débutants (jamais joué CHROME://ASCENT) complètent 10 morts chacun dans une session contrôlée, WHEN le facilitateur leur demande après chaque mort "qu'est-ce qui t'a tué ?" (laser rouge / pic / ennemi X / chute), THEN ≥ 4 joueurs sur 5 identifient correctement la cause sur ≥ 8 morts / 10. Si < 4/5 ou < 8/10, flagger `RESPAWN_DELAY` comme suspect et revisiter en playtest MVP (relever à 80-120 ms ?). Evidence : grille + signature QA Lead. *r3 : AC garde-fou ajouté suite désaccord game-designer F2 ↔ décision Martin A — permet de valider empiriquement que 50 ms reste compatible avec attribution causale.*
- [ ] **Chaîne combo complète** (Integration — BLOCKING) : cf. AC Intégration cross-system ci-dessous (rewrite avec assertions concrètes par étape).
- [ ] **Physics tick rate** (Performance — BLOCKING) : GIVEN debug build avec `physics_ticks_per_second = 60` (ADR-0001 Accepted), WHEN scène test tourne 30 s, THEN `Engine.get_physics_frames()` delta ∈ `[1782, 1818]` (60 × 30 ± 1 %). Mesure via GUT.
- [ ] **Fallback 60 Hz** (Performance — ADVISORY) : GIVEN release build sur hardware minimum spec, WHEN séquence dash→wall-run→wall-jump exécutée 60 s, THEN `Performance.TIME_PROCESS` P90 ≤ 16.6 ms (60 fps min soutenu). Mesure manuelle avec Godot profiler.

## UI Requirements

| Information | Emplacement HUD | Fréquence update | Condition |
|---|---|---|---|
| Dash cooldown ratio | **Arc proche réticule** (8-12° du centre, pas centre-bas) | Tick physique (60 Hz, ref: ADR-0001) | Visible en permanence si `can_dash == true`, caché sinon. *Revision 2026-04-21 (ux-designer F1) : centre-bas créait un conflit attentionnel avec le réticule — arc proche évite la saccade oculaire.* |
| État current (debug) | Overlay debug toggle F3 | Tick physique | Pendant dev uniquement, pas en build release |
| Input→action latency | Overlay debug toggle F3 | Frame | Dev & QA only |
| Dead fade | Full screen (pas HUD system) | Immédiat | Pendant RESPAWN_DELAY — respecte `reduce_flash` toggle (cf. Accessibility Options) |
| First-dash-unlock prompt | Centre-haut, one-shot, ≤ 3 s | Déclenché au premier tick où `can_dash=true` | Montre le keybind courant pour `dash`. Non répété. *Affordance onboarding (ux-designer F2).* |

**Encodage visuel non-couleur-seule** : le cooldown indicator doit utiliser **remplissage progressif** (arc/barre qui se remplit), PAS uniquement une couleur on/off. Compatibilité daltonienne WCAG 1.4.1.

**Remapping inputs** : toutes les actions du Movement System (`move_*`, `jump`, `dash`) DOIVENT être remappables via le Input System GDD. Contrainte à propager à `design/gdd/input-system.md` (à écrire).

**Mouse sensitivity (`mouse_sensitivity`)** : exposée dans les settings menu (slider). La sensibilité *effective* peut être normalisée DPI si le Input System GDD le décide. Défaut : 0.0022 rad/px (safe range **0.0005 – 0.012** — élargi r2 Input GDD 2026-04-21). Source de vérité : `design/registry/entities.yaml` → constants.

> **📌 UX Flag — Player Movement System** : Le dash cooldown indicator doit être spec'd en UX. En Phase 4 (Pre-Production), lancer `/ux-design dash-cooldown-indicator` — le spec DOIT couvrir : position (arc proche réticule), encodage non-couleur-seule, first-unlock prompt, toggle reduce-flash/reduce-motion, affordance daltonienne. Note-le dans le systems-index.

## Cross-References

| Ce document référence | GDD cible | Élément référencé | Nature |
|---|---|---|---|
| `Input.get_vector(move_*)` et actions abstraites | `design/gdd/input-system.md` *(à écrire)* | Input action names and semantics | Data dependency |
| `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run` | `design/gdd/upgrade-system.md` *(à écrire)* | Capability flag API | Data dependency |
| `Player.die()` appelé par enemy/hazard | `design/gdd/enemy-system.md`, `design/gdd/hazard-system.md` *(à écrire)* | Trigger d'état Dead | State trigger |
| `Checkpoint.get_current_position()` | `design/gdd/checkpoint-respawn-system.md` *(à écrire)* | Ownership du spawn point | Ownership handoff |
| `velocity`, `transform.basis` consommés par katana | `design/gdd/player-combat-system.md` *(à écrire)* | Données de direction et vitesse du swept hitbox | Data dependency |
| Grille de couloirs 2 m, hauteurs d'obstacles, wall-jump corridors | `design/levels/level-grid-spec.md` *(créé 2026-04-21)* | Constantes de grille modulaire + tiers d'obstacles | Spatial constraint |

> Toutes les cibles sont encore *non rédigées* (hormis `level-grid-spec.md`, créé lors de cette revision). Ce GDD publie des interfaces *provisoires* qui seront confirmées ou révisées à la rédaction des GDDs cibles.

## Acceptance Criteria

> **Format r3** : chaque AC a un ID stable `AC-MV-NN`, une classification entre `[Logic | Integration | Visual/Feel | UI | Config/Data — BLOCKING | ADVISORY]`, et un ownership (Owner: qa-tester / lead-programmer / QA Lead). Classification alignée sur coding-standards `.claude/docs/coding-standards.md`.

### Core movement

- **AC-MV-01** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur est Grounded, **WHEN** il presse `W` pendant 1 s, **THEN** sa position a avancé d'exactement `MOVE_SPEED * 1 = 10 m` ± tolerance physique ±0.3 m.
- **AC-MV-02** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur est Grounded et moving, **WHEN** il relâche tous les inputs move, **THEN** sa vélocité horizontale devient `Vector2.ZERO` au tick suivant (stop instantané, max 1 physics tick de latence ≈ 16.6 ms @ 60 Hz, ref: ADR-0001).
- **AC-MV-03** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur est Grounded, **WHEN** il presse `A`+`D` simultanément, **THEN** sa vélocité horizontale reste 0.

### Saut

- **AC-MV-10** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Grounded, **WHEN** le joueur presse `jump`, **THEN** `velocity.y` devient `JUMP_VELOCITY` au tick suivant, et le peak de saut atteint `JUMP_VELOCITY² / (2 * GRAVITY)` ± 0.05 m.
- **AC-MV-11** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Airborne avec `air_jumps_used=0` et `can_air_jump=true`, **WHEN** le joueur presse `jump`, **THEN** `velocity.y` devient `AIR_JUMP_VELOCITY` et `air_jumps_used` passe à 1.
- **AC-MV-12** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Airborne avec `air_jumps_used=1` et `can_air_jump=true`, **WHEN** le joueur presse `jump`, **THEN** rien ne se passe (pas de triple-jump à MAX_AIR_JUMPS=1).
- **AC-MV-13** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Airborne avec `can_air_jump=false`, **WHEN** le joueur presse `jump`, **THEN** rien ne se passe.
- **AC-MV-14** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur vient de quitter le sol sans jump (fall), **WHEN** `jump` est pressé dans la fenêtre `COYOTE_TIME` (≤ 100 ms après `is_on_floor()` transition true→false), **THEN** le saut sol est exécuté (pas de décompte d'air-jump).
- **AC-MV-15** `[Logic — BLOCKING] [POST-MVP] [Owner: qa-tester]` — **GIVEN** le joueur est Airborne et descendant, **WHEN** `jump` est pressé jusqu'à `JUMP_BUFFER` (100 ms) avant le premier tick où `is_on_floor() == true`, **THEN** le saut sol est exécuté automatiquement à l'impact. *r3 : AC conservé mais taggé POST-MVP (décision Martin r2 : jump buffer hors scope MVP).*

### Dash

- **AC-MV-20** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_dash=true` et cooldown expiré, **WHEN** `dash` est pressé avec wish_dir non-nul, **THEN** la position avance de `DASH_SPEED * DASH_DURATION = 2.80 m` (valeurs nominales) ± 0.15 m dans la direction du wish_dir, en `DASH_DURATION` seconds. **ET** à `t = DASH_DURATION`, `velocity.xz == dash_dir * DASH_EXIT_SPEED ± 0.5`. **ET** à `t = DASH_DURATION + DASH_MOMENTUM_WINDOW`, `velocity.xz.length() == MOVE_SPEED ± 0.3` (décélération momentum terminée).
- **AC-MV-21** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_dash=false`, **WHEN** `dash` est pressé, **THEN** rien ne se passe (pas de déplacement, pas de cooldown déclenché).
- **AC-MV-22** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** un dash vient de se terminer, **WHEN** `dash` est repressé avant `DASH_COOLDOWN` écoulé, **THEN** l'input est ignoré et le son `dash_reject.wav` est déclenché.
- **AC-MV-23** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** un dash est en cours, **WHEN** le joueur presse `move_left` ou `move_right`, **THEN** la direction du dash ne change pas (input horizontal ignoré pendant dash).
- **AC-MV-24** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `is_dashing=true` à `t=0.05s` de Dashing, **WHEN** `die()` est appelé, **THEN** après respawn : `is_dashing=false`, `dash_timer=0`, `dash_cooldown_timer ∈ [DASH_COOLDOWN*0.4, DASH_COOLDOWN*0.6]` (partial cooldown), `velocity=Vector3.ZERO`.
- **AC-MV-25** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_dash=true`, cooldown expiré, joueur Airborne avec `velocity.y = 8.0` (saut en cours), **WHEN** `dash` est pressé, **THEN** au premier tick de l'état Dashing : `velocity.y == 0.0 ± 0.001` (reset explicite Rule 6). *AC coverage gap ajouté r3 (qa-lead F10).*
- **AC-MV-26** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** n'importe quel état `* → Dashing` (Grounded→Dashing, Airborne→Dashing, WallRunning→Dashing), **WHEN** la transition s'exécute dans un seul physics tick, **THEN** signal `dash_started` émis **exactement 1 fois** par transition. Idempotence sur signal = pas seulement sur état. *AC symétrique ajouté r4 (ADR-0005 VC-4) — miroir d'AC-MV-41 (died 1×).*

### Wall-run et Wall-jump

- **AC-MV-30** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_wall_run=true`, Airborne, horiz_speed > WALL_RUN_MIN_SPEED, **WHEN** au moins un raycast latéral touche un mur vertical, **THEN** l'état passe à WallRunning ≤ 3 physics ticks plus tard et la gravité descend à `WALL_RUN_GRAVITY`.
- **AC-MV-31** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** WallRunning, **WHEN** plus aucun raycast latéral ne touche, **THEN** l'état revient à Airborne et la gravité normale reprend au tick suivant.
- **AC-MV-32** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** WallRunning avec `air_jumps_used == 0` avant le wall-jump, **WHEN** `jump` est pressé, **THEN** velocity est settée à `wall_normal * WALL_JUMP_SIDE + UP * WALL_JUMP_UP ± 0.1`, **`air_jumps_used == MAX_AIR_JUMPS`** (wall-jump bloque double-jump post-wall-jump — décision Martin r3 A), et l'état sort de WallRunning.
- **AC-MV-33** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** WallRunning avec raycast maintenu en contact, **WHEN** `WALL_RUN_MAX_DURATION` (1.5 s) s'écoule sans input `jump` ni perte de contact, **THEN** à `t ≥ 1.5 s` : `state == Airborne` et la gravité normale reprend.
- **AC-MV-34** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_wall_run=true`, Airborne, horiz_speed > WALL_RUN_MIN_SPEED, **WHEN** `$WallRayLeft` ET `$WallRayRight` touchent simultanément deux surfaces verticales (couloir étroit ≤ 1.6 m), **THEN** `wall_normal == $WallRayLeft.get_collision_normal()` ET `state == WallRunning` (priorité gauche déterministe, Rule 7). *AC coverage gap ajouté r3 (qa-lead F9).*
- **AC-MV-35** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** état Airborne juste après un wall-jump (donc `air_jumps_used == MAX_AIR_JUMPS`), `can_air_jump=true`, **WHEN** `jump` est pressé, **THEN** rien ne se passe (double-jump bloqué — décision Martin r3 A vérifiée). *AC coverage gap ajouté r3 : garantit l'effet réel de la décision B.*
- **AC-MV-36** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** n'importe quel état `* → WallRunning` (Airborne→WallRunning, Dashing→WallRunning pendant dash terminé), **WHEN** la transition s'exécute dans un seul physics tick, **THEN** signal `wall_run_entered` émis **exactement 1 fois** par transition avec `wall_normal` payload cohérent avec `wall_normal` exposé en propriété read-only. *AC symétrique ajouté r4 (ADR-0005 VC-4).*

### Mort & respawn

- **AC-MV-40** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** n'importe quel état vivant, **WHEN** `die()` est appelé, **THEN** au tick T : `state == Dead`, signal `died` émis **exactement 1 fois**. **ET** pendant `t ∈ [T, T + RESPAWN_DELAY]` : toutes les actions d'input (`jump`, `dash`, `move_*`) sont ignorées (velocity inchangée par inputs). **ET** à `t = T + RESPAWN_DELAY + 1 tick` : `position == checkpoint.position ± 0.01`, `velocity == Vector3.ZERO`, `state == Grounded`, `inputs_accepted == true`. *r3 rewrite (qa-lead F8) : THEN éclaté en assertions atomiques timestampées, suppression terme ambigu "figés".*
- **AC-MV-41** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Dead, **WHEN** `die()` est rappelé 3 fois dans le même physics tick, **THEN** signal `died` émis **exactement 1 fois** au total (idempotence sur les signaux, pas seulement sur l'état). Implémentation prescrite : early return `if state == Dead: return` en première ligne de `die()` (godot-specialist F6). *AC coverage gap ajouté r3 (qa-lead F12).*
- **AC-MV-42** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** mort standard (hors Dashing), **WHEN** `respawn()` s'exécute, **THEN** `dash_cooldown_timer == 0.0` (dash immédiatement disponible — favorise rétention de flow Pillar 3). *AC coverage gap ajouté r3 (game-designer F9) : distingue la mort standard de la mort-pendant-dash (AC-MV-24).*
- **AC-MV-43** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `is_dashing == true`, **WHEN** `die()` est appelé pendant Dashing, **THEN** dans l'ordre d'émission : signal `dash_ended` précède strictement signal `died` (même tick physique, `dash_ended` émis en premier). Raison : les consommateurs Audio/VFX attendent que `dash_ended` ferme proprement les boucles samplers/particules avant que `died` déclenche les SFX de mort. *AC symétrique ajouté r4 (ADR-0005 VC-4, point 4 Context : « si `die()` est appelé pendant Dashing, est-ce que `dash_ended` est émis avant `died` ? »).*

### Performance

- **AC-MV-50** `[Integration — BLOCKING] [Owner: QA Lead]` — **GIVEN** scène test `tests/scenes/perf_test_movement.tscn` (10 ennemis NavMeshAgent en patrouille, capabilities toutes actives), **WHEN** un script GUT fait exécuter au joueur la séquence course→saut→double-saut→dash→wall-run→wall-jump en boucle pendant 30 s, **THEN** sur les 1800 frames mesurées (60 Hz × 30 s) : P99 de `Performance.TIME_PROCESS * 1000` ≤ 16.6 ms, et `Engine.get_physics_frames()` delta ∈ `[1782, 1818]` (60 × 30 ± 1 %, ref: ADR-0001 Accepted).
- **AC-MV-51** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** debug build avec instrumentation, **WHEN** 200 inputs `dash` exécutés via GUT, **THEN** P99 de (timestamp velocity-set − timestamp input event) ≤ 16 ms.

### Capability gating

- **AC-MV-60** `[Config/Data — BLOCKING] [Owner: qa-tester]` — **GIVEN** une save neuve (fresh start), **THEN** `can_air_jump=false`, `can_dash=false`, `can_wall_run=false`.
- **AC-MV-61** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `player.can_dash = true` injecté directement (simulant Upgrade System), **WHEN** un input `dash` est exécuté au tick suivant, **THEN** `velocity.xz.length() == DASH_SPEED ± 0.1` pendant `DASH_DURATION`.

### Vélocité état dégénéré

- **AC-MV-70** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** un tick où le script injecte `velocity = Vector3(INF, INF, INF)` après le calcul de mouvement, **WHEN** le tick se termine avant `move_and_slide()`, **THEN** `velocity.is_finite() == true` (la vérification a remplacé le `velocity` par `Vector3.ZERO`) et un `push_error` est émis au stdout/debugger. *r3 : AC réécrit — `is_finite()` au lieu de clamp [-50,50] (godot-specialist F8).*

### Intégration cross-system

- **AC-MV-80** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_dash=true`, un mock inline `MockCombatSystem extends Node` qui dans `_physics_process(delta)` : (a) récupère le player via `get_node("../Player")`, (b) si `player.is_dashing == true`, écrit `last_sweep_velocity: Vector3 = player.velocity` ; `last_sweep_velocity` initialisé à `Vector3.ZERO`. **WHEN** le joueur dashe avec `DASH_SPEED=30` (valeur r3 du range min) dans la direction forward, **THEN** `MockCombatSystem.last_sweep_velocity.length() ≈ 30 ± 0.1` au tick pendant lequel `is_dashing == true`. *r3 rewrite (qa-lead F6) : interface minimale du mock spécifiée inline pour que l'AC soit implémentable aujourd'hui. Sera remplacé par test d'intégration réel une fois `player-combat-system.md` rédigé.*
- **AC-MV-81** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** un checkpoint trigger est crossed, **WHEN** `set_checkpoint(new_pos)` est appelé, **THEN** un `die()` suivant respawne le joueur à `new_pos ± 0.01`.

### Chaîne combo (Integration — BLOCKING)

- **AC-MV-90** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `can_dash=true`, `can_wall_run=true`, `can_air_jump=true`, `air_jumps_used=0`, joueur Grounded face à un mur vertical à 4 m, **WHEN** le script GUT exécute dans l'ordre : presse `dash` → attend `DASH_DURATION + DASH_MOMENTUM_WINDOW` → presse `move_right` (vers le mur) → attend wall-run activation (`state == WallRunning`) → presse `jump` → attend `state == Airborne`, **THEN** toutes les assertions passent :
  - Après dash : `state ∈ {Airborne, Grounded}`, `velocity.length() > 0`
  - Après wall-run entry : `state == WallRunning` dans ≤ 3 physics ticks
  - Après wall-jump : `velocity.y ≈ WALL_JUMP_UP ± 0.1`, `air_jumps_used == MAX_AIR_JUMPS` (**décision Martin r3 A : wall-jump bloque double-jump**), `state == Airborne`
  - Au premier `jump` suivant l'état Airborne : rien ne se passe (double-jump bloqué, cf. AC-MV-35)
  - `r3 rewrite` : la chaîne d'origine (double-jump post wall-jump) devient invalide avec décision A. La nouvelle chaîne **teste explicitement que le blocage fonctionne** — c'est l'invariant le plus important de la décision A.

### Visual/Feel AC

- **AC-MV-100** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` — **GIVEN** joueur déclenche un dash, **WHEN** `dash_started` signal émis, **THEN** screenshot capturé à `t = DASH_DURATION/2` montre trail linéaire visible + FOV = 100° ±1° (peak `BASE_FOV + DASH_FOV_KICK` = 90° + 10°, owned par Camera System) (sauf si `reduce_motion` activé → ≤ 94°, soit kick ≤ 4°). Evidence : `production/qa/evidence/dash-vfx-[date].png` + signature QA Lead.
- **AC-MV-101** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` — **GIVEN** `die()` appelé, **WHEN** `died` signal émis, **THEN** screenshot à `t = RESPAWN_DELAY/2` (= 25 ms avec `RESPAWN_DELAY=50 ms`) montre fondu rouge plein écran ≤ 40 ms (sauf si `reduce_flash` activé → assombrissement gris neutre 80-120 ms). Evidence : `production/qa/evidence/death-fade-[date].png` + signature QA Lead.

## Decisions Taken (post-review 2026-04-21)

*Questions antérieurement ouvertes et closes lors de la révision du 2026-04-21 :*

| Question | Décision | Source |
|---|---|---|
| Air control : 100% ou Ghostrunner-like ? | **~65% (AIR_CONTROL_FACTOR=65 m/s²)**. Aligne formule ET prototype. | Martin (widget 2026-04-21) + game-designer F4, level-designer F8, gameplay-programmer F9 convergent |
| Slow-mo aérien MVP ou séparé ? | **Système séparé hors-MVP** (`aerial-slowmo-system.md` futur). Retiré de `game-concept.md §MVP`. | Martin r1 (widget 2026-04-21) |
| Coyote time (100 ms) MVP ? | **OUI MVP** — à intégrer au prototype avant level design. Budget 0.5 j. | Martin r1 + game-designer F10 + level-designer F7 |
| Jump buffer (100 ms) MVP ? | **NON → POST-MVP** (décision r2 2026-04-21). Coyote seul en MVP. Jump buffer à réévaluer en playtest MVP. | Martin r2 (**corrigé r3** — r1 disait par erreur MVP) |
| Feel Cluster A (décel, dash duration, post-dash cap) | **Full fix** : stop instantané, dash 100 ms, momentum exit 15 m/s sur 200 ms. | Martin + creative-director synthesis |
| `air_jumps_used` reset par wall-run ENTRY ? | **NON**. Wall-run entry ne modifie pas `air_jumps_used` (le wall-run ne donne pas de double-jump gratuit). | systems-designer F8 (auto-contradiction résolue r1) |
| Wall-jump consomme les air-jumps ? | **OUI → wall-jump bloque double-jump** (formule `air_jumps_used = MAX_AIR_JUMPS`). Cascade : couloirs MVP ≤ 3.25 m dans Level Grid Spec. | Martin r3 A (widget 2026-04-21) + creative-director synthesis r3 |
| `RESPAWN_DELAY` valeur ? | **0.05 s** (ancien 0.2 s). AC garde-fou d'attribution causale ajouté (AC-MV garde-fou). `death.wav` et fondu rouge raccourcis à ≤ 40 ms. | Martin r3 (widget 2026-04-21) + game-designer F2 désaccord documenté |
| Tick rate physique ? | **60 Hz** (ADR-0001 Accepted 2026-04-21 — default Godot 4.6 + Jolt, verdict `/architecture-review` fresh-session). | Martin r3 (widget 2026-04-21) + godot-specialist F1/F2 + ADR-0001 Acceptance |

## Open Questions (remaining)

| Question | Owner | Deadline | Résolution attendue |
|---|---|---|---|
| Le dash doit-il accorder des i-frames (100 ms d'invincibilité) ? | game-designer | Playtest MVP | **Default post-revision : non-MVP**. Si frustration "je viens de dasher et je meurs" en playtest, ajouter 100 ms d'i-frames. Décision de playtest, pas de design a priori. |
| Triple-jump (MAX_AIR_JUMPS=2) comme upgrade post-MVP ? | game-designer | Tier 2 (Vertical Slice) | À ajouter au moveset upgrade pool seulement si le level design Tier 2 en tire parti (gaps plus hauts). |
| Plateformes mobiles / rotatives : dans ce GDD ou séparé ? | level-designer | Tier 2 | Hors MVP. Si ajouté Tier 2, GDD séparé "dynamic-platforms" recommandé (ne pas étendre ce GDD qui est déjà volumineux). |

## Project Settings requis

*Revision 2026-04-21 (godot-specialist F12) : bugs classiques Godot à éviter.*

```
# ProjectSettings (project.godot) — valeurs requises pour ce système
physics/common/physics_ticks_per_second = 60                  # ADR-0001 Accepted 2026-04-21 (default Godot 4.6 + Jolt)
physics/3d/physics_engine = "JoltPhysics3D"                   # défaut Godot 4.6, explicite pour traçabilité
physics/3d/default_gravity = 0.0                              # le script applique manuellement `GRAVITY`
physics/3d/default_gravity_vector = Vector3(0, -1, 0)         # irrelevant avec default_gravity=0 mais explicite
physics/common/max_physics_steps_per_frame = 4                # override du défaut 8 — entry-level laptop safety
                                                              # (godot-specialist F12), évite spiral-of-death
```

*Revision r4 2026-04-23 : `physics_ticks_per_second = 60` figé suite ADR-0001 Accepted 2026-04-21 (verdict `/architecture-review` fresh-session, CONCERNS résolues). Les latences WASD (~16 ms worst-case) sont compatibles avec le pattern `was_pressed_this_tick` d'ADR-0004. `max_physics_steps_per_frame = 4` maintenu (entry-level laptop safety, évite spiral-of-death).*

*Si `default_gravity ≠ 0` et le script applique aussi manuellement `velocity.y -= GRAVITY * delta`, la gravité sera doublée — bug classique CharacterBody3D. Gravité full-manual volontaire ici.*

## Escalations

Les décisions techniques suivantes dépassent le scope de ce GDD et sont traitées (ou à traiter) par des ADRs avant l'implémentation :

1. **ADR-0002 — Camera scene tree** : hiérarchie `CharacterBody3D → CameraArm → CameraEffects → Camera3D` (pattern r3 godot-specialist F3 — évite conflit Tween sur `rotation.z` entre head-bob et wall-run tilt). Statut : voir `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md`.
2. **ADR-0001 — Physics tick rate** (`docs/architecture/adr-0001-physics-rate-60hz.md`) : **Accepted 2026-04-21** — tick rate **60 Hz** (default Godot 4.6 + Jolt). `max_physics_steps_per_frame = 4` (override du défaut 8, entry-level laptop safety). Verification Required par l'ADR : (1) `Engine.get_physics_frames()` delta ∈ [1782, 1818] sur 30 s, (2) bench p99 input→velocity mutation ≤ 16 ms release, (3) no Jolt runtime warnings sur joints katana/wall-run. Le prototype movement-katana doit être re-validé en 60 Hz avant Sprint 1 (ADR-0001 Migration Plan action #2).
3. **ADR-0005 — Movement Signals Architecture** (`docs/architecture/adr-0005-movement-signals-architecture.md`) : **Accepted 2026-04-21** (fresh-session `/architecture-review` r2 — verdict PASS, gap G-1 HIGH résolu, dépendance ADR-0001 satisfaite). Décision : direct typed signals émis depuis `MovementController` (le `CharacterBody3D` lui-même), pas d'EventBus autoload. Les 8 signaux canoniques (D-2), la règle `CONNECT_DEFERRED` codée (D-5), et les ACs de symétrie d'idempotence (VC-4) sont propagés dans ce GDD r4 (Published API l. 82, note CONNECT_DEFERRED l. 96, AC-MV-26/36/43).
4. **ADR — ShapeCast3D + Jolt CCD** (godot-specialist F3) : ordre `force_shapecast_update()` / `move_and_slide()`. Sera couvert par `design/gdd/player-combat-system.md` (à écrire).

*Revision r3 2026-04-21 (Cluster 4 fix godot-specialist F2/F12) : les 3 ADRs listés comme "à faire" mais utilisés comme faits établis dans le doc étaient un statut contradictoire. ADR-0001 a été créé (Proposed) ; le GDD paramétrait `PHYSICS_TICK_RATE` pour refléter l'attente Acceptance ; ADR signaux était à écrire.*

*Revision r4 2026-04-23 (P1 #1 & P1 #3 post-review) : ADR-0001 est passé Accepted 2026-04-21 (fresh-session `/architecture-review`) — toutes les références `PENDING` / `Proposed` / `hypothèse 120 Hz` / `PHYSICS_TICK_RATE` paramétrique ont été remplacées par `60` littéral + mention ADR-0001 Accepted. ADR-0005 Accepted 2026-04-21 (fresh-session `/architecture-review` r2) — la liste canonique des 8 signaux, la note `CONNECT_DEFERRED`, et les ACs symétriques d'idempotence (VC-4) ont été propagés depuis ADR-0005 D-2 / D-5.*
