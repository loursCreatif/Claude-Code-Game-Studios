# ADR-0001: Physics Tick Rate 60 Hz (Godot Default) + Jolt

## Status
Accepted

## Date
2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session `/architecture-review` — verdict CONCERNS résolues par actions #1 stale refs ADR-0003 + #2 camera scene tree arbitration)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Physics |
| **Knowledge Risk** | MEDIUM |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/modules/physics.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | Jolt Physics 3D (défaut Godot 4.6) ; `physics_interpolation_mode` (4.5+ rearchitecturé, API publique inchangée) |
| **Verification Required** | (1) Mesurer `Engine.get_physics_frames()` delta ∈ [1782, 1818] sur 30 s (60 × 30 ± 1 %). (2) Bench p99 input→velocity mutation ≤ 16 ms release. (3) Vérifier que Jolt n'émet pas de runtime warnings pour les joints utilisés (katana, wall-run) lors de leur implémentation. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | Player Movement System implementation ; Player Combat System hitbox detection ; Checkpoint/Respawn deterministic replay ; un futur ADR rendering-latency (VSync/refresh rate, ≤ 50 ms end-to-end) peut s'appuyer sur la cible intra-engine ≤ 16 ms fixée ici |
| **Blocks** | Epic Player Movement (ne peut pas démarrer sans tick rate formel) ; Epic Player Combat (hitbox timing dépend du tick) ; création des premières stories gameplay |
| **Ordering Note** | Cet ADR doit être Accepted avant toute story gameplay qui mesure la latence ou le timing tick-based (jump buffer, coyote time, combo window, iframes). |

## Context

### Problem Statement

Le projet doit fixer formellement le physics tick rate de Godot avant la première story gameplay. Deux GDDs déjà rédigés (Input System, Player Movement System) portent des valeurs **contradictoires** : Input System r2 acte **60 Hz** (post-design-review 2026-04-21), Player Movement System mentionne **120 Hz** à 5 endroits (hérité du prototype `movement-katana`). Tant que l'ADR n'est pas Accepted, toute story créée à partir du Movement GDD embarquera un chiffre faux ; toute mesure de latence (AC-LAT-01 Input, AC-PERF tick rate Movement) référencera le mauvais budget.

La cible produit (game-concept.md, Pillar 1 « FLOW AVANT TOUT ») est latence input → réponse ≤ 1 frame. Il faut arbitrer : (a) aligner physique sur le frame rate d'affichage (60 Hz = 1 tick par frame vsync), (b) doubler la physique à 120 Hz pour gagner 8.3 ms théoriques intra-engine, ou (c) découpler physics et render via interpolation. Le choix contraint tout le moteur de jeu en aval (Combat, Camera, Checkpoint, Boss), le budget CPU physique, et les ACs de test GUT.

### Constraints

- **Engine** : Godot 4.6 avec Jolt Physics 3D (défaut 4.6, déterminisme requis pour wall-run et hitbox katana).
- **Platform target** (per `technical-preferences.md`) : PC entry-level laptop, 60 fps locked avec vsync, 120+ fps désirable sur hardware moderne, budget frame 16.6 ms, 2 Go RAM / 1 Go VRAM.
- **Pillar 1** : latence input → réponse ≤ 1 frame (game-concept.md).
- **Pipeline de tests** : framework GUT, tests déterministes (pas de dépendance au temps réel).
- **Pre-production** : aucun code dans `src/` — seul le prototype `prototypes/movement-katana/` existe, et est lui-même appelé à être aligné.
- **Input system (GDD Accepted pending re-review)** : cible p99 ≤ 16 ms intra-engine, déjà acté.

### Requirements

- **REQ-1** : Le tick rate doit permettre latence p99 ≤ 16 ms intra-engine du callback d'input à la mutation gameplay correspondante (alignement Pillar 1).
- **REQ-2** : Le budget CPU physique doit laisser de la marge aux autres systèmes (Combat, Camera, IA, Audio) dans les 16.6 ms frame sur entry-level laptop.
- **REQ-3** : Le timing tick-based (jump buffer, coyote time, dash cooldown, combo window) doit être déterministe, reproductible en GUT, et indépendant du frame rate d'affichage.
- **REQ-4** : L'autorité de mutation de l'état gameplay doit être unique (pas de race condition `_process` vs `_physics_process`).
- **REQ-5** : Le pattern d'input sampling doit tolérer un render fps > physics rate (ex : moniteur 144 Hz G-Sync, render 144 / physics 60) sans drop discret d'action one-shot.
- **REQ-6** : Jolt doit être le moteur physique (déterminisme supérieur à GodotPhysics3D per `physics.md`).

## Decision

Adopter **60 Hz comme physics tick rate** (défaut Godot), avec **Jolt Physics 3D** comme moteur, et verrouiller les patterns d'autorité gameplay et d'input sampling ci-dessous.

### Project Settings (project.godot)

```ini
[physics]
common/physics_ticks_per_second = 60
common/max_physics_steps_per_frame = 4
3d/physics_engine = "JoltPhysics3D"
3d/default_gravity = 0.0
```

> `physics_ticks_per_second = 60` est déjà la valeur par défaut de Godot. La ligne est écrite explicitement dans `project.godot` pour rendre le choix traçable en code review et dans le repo.
> `max_physics_steps_per_frame = 4` est un **override** du défaut Godot (8) → décision godot-specialist F12 (review player-movement-system.md) pour cible hardware entry-level laptop : limite la fenêtre de catch-up à 66.6 ms, préfère un stutter court et honnête à un freeze de 133 ms sur CPU spike. À 60 Hz physics / 60 fps render nominal le paramètre joue quasiment jamais.
> `default_gravity = 0.0` est un **override** du défaut Godot (9.8) — la GDD Movement applique une gravité custom `GRAVITY = 24.0` explicitement dans `_physics_process` (hors wall-run) et doit **court-circuiter** la gravité globale Jolt pour éviter un double-cumul. Applique uniquement à Jolt 3D ; la 2D reste à son défaut. Ne modifie pas le comportement des RigidBody3D de scène (ils utiliseront leur propre `gravity_scale` si gravité requise — à préciser par système au cas par cas).

### Règle d'autorité gameplay

`_physics_process(delta)` est l'**UNIQUE** autorité de mutation de l'état gameplay :

- `velocity`, `position`, `rotation` du Player (et de toute entité gameplay)
- Évaluation hitbox (katana swing, damage delivery)
- Transitions de state machine (grounded → airborne, idle → dashing, etc.)
- Application de dégâts, consommation de ressources (stamina future, etc.)
- Timing tick-based : jump buffer, coyote time, dash cooldown, combo window, iframes
- Comptage de ticks via `Engine.get_physics_frames()` (API Godot inchangée en 4.6, vérifié contre `deprecated-apis.md`)

`_process(delta)` est **cosmétique ONLY** :

- Caméra yaw/pitch (décision GDD Camera System : la caméra est child du Player, appliquée en `_process`)
- VFX (particles, shake decay, FOV interp)
- HUD, tween UI, debug overlay F3
- Son (AudioStreamPlayer trigger — la logique qui *déclenche* le son reste en `_physics_process`)

> **Ban explicite** : toute mutation de `velocity`, `position`, ou d'une variable d'état gameplay dans `_process()` est un forbidden pattern (voir Consequences → Risks et registry `architecture.yaml`).

### Pattern d'input sampling (anti-drop render > physics)

Le `InputManager` (cf. GDD Input System) applique la règle suivante :

1. Les events bruts sont reçus dans `_unhandled_input(event)` (cadence render, appelé 0-N fois par frame render selon les events buffered OS).
2. Pour **chaque action gameplay** (`jump`, `dash`, `attack`, `restart`, etc.), un **flag booléen** `_pressed_this_tick[action]` est set à `true` dans `_unhandled_input` dès qu'un edge `pressed` est détecté.
3. Les consumers (Player Movement, Player Combat, Checkpoint) polling `InputManager.was_pressed_this_tick(action)` dans leur propre `_physics_process`.
4. Le flag est **consommé via swap `_pressed ↔ _consumed` en début de `_physics_process`** de l'InputManager (ordre autoload garantit qu'il tourne en premier). Pattern canonique figé par **ADR-0004 D-3** — lire `was_pressed_this_tick(action)` retourne le buffer `_consumed` swappé en ligne 1 du `_physics_process` de l'InputManager (zero-alloc, ref-swap). Le « reset en fin » initialement envisagé casse l'AC-CS-1 (les consumers aval liraient `false` au tick N) — rejeté.

> **Raison** : `is_action_just_pressed()` retourne `true` uniquement pour *un seul frame render*. À 144 Hz render / 60 Hz physics (monitor 144 Hz G-Sync + render non cappé), entre deux ticks physiques il y a ~2.4 frames render. Si le tick physique rate la fenêtre render où `just_pressed` était `true`, l'input est silencieusement perdu. Le flag-via-signal setté dans `_unhandled_input` et consommé dans `_physics_process` garantit qu'aucune action one-shot n'est droppée.

### Interpolation

`physics_interpolation_mode` est réglé à **OFF** sur le root Player (et non projet-wide). Deux raisons :

1. Avec 60 Hz physics + 60 fps vsync render, le ratio 1:1 rend l'interpolation inutile et ajouterait 1 frame de latence visuelle.
2. Laisser `INHERIT` (défaut) sur les nodes enfants du Player permet au reste du projet (UI, menus, systèmes 2D futurs) d'utiliser l'interpolation si pertinent, sans que le gameplay en pâtisse.

Si, en phase Polish, un support 120/144 Hz render + 60 Hz physics est souhaité (G-Sync), un ADR ultérieur pourra acter l'activation de l'interpolation Player avec rebudgétisation.

### Architecture Diagram

```
                        ┌─────────────────────────────────────────┐
                        │ Cadence render (60+ fps, vsync locked)  │
                        │   _process(delta) — COSMÉTIQUE ONLY     │
                        │   - Camera yaw/pitch                    │
                        │   - VFX, shake, FOV interp              │
                        │   - HUD, tween UI, debug F3             │
                        └─────────────┬───────────────────────────┘
                                      │ READ (read-only getters)
                                      ▼
┌────────────────────────────────────────────────────────────────┐
│  Cadence physique (60 Hz, UNIQUE AUTORITÉ gameplay)            │
│    _physics_process(delta) — MUTATION STATE                    │
│                                                                │
│   InputManager  ─►  Player Movement  ─►  Player Combat ─►  ... │
│   (autoload #1)     (velocity/pos)       (hitbox/damage)       │
│                                                                │
│   Timing référence : Engine.get_physics_frames()               │
│   Δt ≈ 16.667 ms                                               │
└─────────────▲──────────────────────────────────────────────────┘
              │ Flag was_pressed_this_tick[action]
              │ (set dans _unhandled_input, reset fin _physics_process)
┌─────────────┴──────────────────────────────────────────────────┐
│  Events bruts OS — _unhandled_input(event)                     │
│  (cadence render, 0-N fois par frame)                          │
└────────────────────────────────────────────────────────────────┘
```

### Key Interfaces

| Interface | Contrat |
|-----------|---------|
| `_physics_process(delta: float)` | Unique callback autorisé à muter l'état gameplay. `delta` constant ≈ 1/60 s. |
| `Engine.get_physics_frames() -> int` | Compteur de ticks physiques écoulés. Utilisé pour timing tick-based déterministe (jump buffer, coyote time, cooldowns, iframes). |
| `InputManager.was_pressed_this_tick(action: StringName) -> bool` | Accesseur polling pour events one-shot edge-triggered. Appelé depuis `_physics_process` du consumer. Flag setté dans `_unhandled_input`, reset fin `_physics_process` de l'InputManager. |
| Project setting `physics/common/physics_ticks_per_second = 60` | Source de vérité ; ne doit pas être modifié sans ADR superseding. |
| Project setting `physics/3d/physics_engine = "JoltPhysics3D"` | Explicite (défaut 4.6). |
| `Node.physics_interpolation_mode = OFF` (root Player uniquement) | Gameplay 1:1 tick:frame. UI et autres sous-arbres peuvent garder `INHERIT`. |

## Alternatives Considered

### Alternative 1: 120 Hz Jolt (prototype choice)

- **Description** : `physics_ticks_per_second = 120`. `_physics_process` tourne à 8.33 ms par tick. Gain théorique : latence intra-engine p99 ≤ 8 ms au lieu de 16 ms.
- **Pros** :
  - Meilleure latence théorique intra-engine (8 ms vs 16 ms).
  - Meilleure résolution temporelle pour hitbox fast-moving (katana swing, dash trajectory).
  - Jump buffer et coyote time à résolution 8 ms — marge plus fine.
- **Cons** :
  - **Coût CPU physique doublé** (Jolt tourne 2× par frame render à 60 fps). Sur entry-level laptop cible (budget frame 16.6 ms), doubler le coût physique comprime le budget Combat/IA/Audio.
  - Le gain de 8 ms intra-engine est **sous le seuil de perception humaine** pour actions click-one-shot (seuil ~20 ms). Seules les actions continues (aim) en bénéficient — mais `mouse_motion` est déjà traité en `_unhandled_input` et ne dépend pas du physics rate.
  - Risque de drop render-rate > physics-rate plus discret (car 120 Hz physics dépasse déjà 60 Hz render, introduit un autre pattern d'aliasing).
  - Désaligne les GDDs existants (Input GDD r2 = 60 Hz) — impose un rework là où 60 Hz est déjà validé.
- **Rejection Reason** : Le coût CPU n'est pas justifié par un gain perceptuel mesurable. L'acteur clé (Input GDD r2) a déjà acté 60 Hz après review indépendant par 7 specialists. 120 Hz reste une option de futur Polish ADR.

### Alternative 2: 60 Hz physics + physics_interpolation_mode ON + render 144 Hz G-Sync

- **Description** : Physique à 60 Hz mais render à 144 Hz uncapped, activation de `physics_interpolation_mode = INTERPOLATED` sur le Player root pour lisser le mouvement visible entre ticks.
- **Pros** :
  - Movement visuel lisse à 144 Hz sans doubler le coût CPU physique.
  - Bénéfice pour joueurs sur hardware premium.
- **Cons** :
  - Ajoute **1 frame de latence visuelle** (interpolation lit entre tick N-1 et N).
  - Complexifie le pipeline de test (GUT en headless ne valide pas le visuel interpolé).
  - Désaligne Pillar 1 (latence ≤ 1 frame).
  - Risque subtil : `global_position` lue en `_process` est interpolée ≠ `global_position` en `_physics_process` — peut introduire des bugs camera/aim si mal scopé.
- **Rejection Reason** : Pillar 1 prime sur fluidité visuelle. Option à rouvrir en Polish si Valve/Steam Deck / 144 Hz feedback le justifie.

### Alternative 3: 240 Hz Jolt (over-budget)

- **Description** : `physics_ticks_per_second = 240`.
- **Pros** : Latence intra-engine ≤ 4 ms théorique.
- **Cons** : Coût CPU physique 4× le baseline 60 Hz. Sur entry-level laptop (budget 16.6 ms frame), 240 Hz Jolt consomme potentiellement >50 % du budget, incompatible avec Combat + IA.
- **Rejection Reason** : Over-budget, gain imperceptible au joueur.

## Consequences

### Positive

- **Alignement Pillar 1** : latence p99 ≤ 16 ms intra-engine garantie (1 tick = 1 frame vsync 60).
- **Budget CPU physique compact** : ~2-4 ms/frame attendus sur Jolt 60 Hz avec scène MVP → marge abondante pour Combat, IA, Audio.
- **Déterminisme GUT** : `Engine.get_physics_frames()` = 60 × seconds, reproductible tick-par-tick.
- **Règle d'autorité claire** : une seule fonction (`_physics_process`) mute l'état — élimine les races `_process` vs `_physics_process`, facilite le debug, clarifie le contrat pour nouveaux devs.
- **Pattern anti-drop input** : le flag-via-signal tolère n'importe quel ratio render:physics sans drop d'action one-shot (futur-proof pour G-Sync, 144 Hz, VRR).
- **Alignement Input GDD r2** : plus aucun conflit cross-document.

### Negative

- **Latence intra-engine 16 ms au lieu de 8 ms** (trade-off assumé vs 120 Hz). Pour actions continues type aim, non impactant car traité hors physics rate.
- **Resolution temporelle jump buffer / coyote time = 16.6 ms** — moins fine que 8.3 ms. Les valeurs de tuning (buffer = 6 ticks = 100 ms) restent exprimables en ticks entiers.
- **Prototype `movement-katana/` à re-valider** avec 60 Hz physics avant réutilisation éventuelle (validé techniquement à 120 Hz — il faut confirmer que le feel reste identique à 60 Hz).

### Risks

- **Risk 1 — Pattern forbidden ignoré en code review** : un dev mute `velocity` dans `_process` par inadvertance (e.g. pour « simplifier » la camera sway). → Mitigation : registry `forbidden_patterns` entry + futur lint rule `.claude/rules/no-gameplay-state-mutation-in-process.md` + godot-gdscript-specialist review obligatoire sur chaque PR Player.
- **Risk 2 — Pattern flag-via-signal remplacé par `is_action_just_pressed` direct** : un dev retire le flag pour « simplifier », introduit un drop d'input subtil reproductible uniquement sur hardware 144 Hz. → Mitigation : doc explicite dans cet ADR + rationale dans InputManager source + AC InputManager spécifique (AC-CS-1 GDD Input déjà prévue).
- **Risk 3 — Joints Jolt incompatibles** : un futur système (wall-run constraint, katana tether, etc.) utilise `HingeJoint3D.damp` ou autre propriété non-Jolt, silent behavior mismatch. → Mitigation : au moment du design de chaque joint-based mechanic, relire `physics.md` (section "Jolt vs GodotPhysics3D") et vérifier les propriétés utilisées ; ajouter un AC de warning Jolt zéro dans le test suite Movement.
- **Risk 4 — Frame drops sur entry-level laptop qui trigger `max_physics_steps_per_frame` clamp** : si le rendering spike (chargement asset, shader compile), le physics peut skipper des ticks, désaligner les timings. → Mitigation : `max_physics_steps_per_frame = 4` (override du défaut 8, validé godot-specialist F12 Movement GDD) permet 66.6 ms de catch-up — préfère un court stutter honnête à un freeze long. Soak test en Polish phase pour détecter. Si observé en continu, réduire la charge rendering, pas le tick rate.
- **Risk 5 — VSync 60 Hz + physics 60 Hz = jitter si désalignés** : si le render timing ne matche pas parfaitement les ticks physics, le mouvement peut paraître saccadé. → Mitigation : Godot aligne déjà physics et render par défaut. Si jitter perçu en playtest, considérer l'Alternative 2 (interpolation) via ADR ultérieur.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/input-system.md` | « Cible ≤ 16 ms p99 **intra-engine** (= 1 tick physique à 60 Hz, défaut Godot) » (ligne 266) | Fixe `physics_ticks_per_second = 60` — rend la cible atteignable par construction (1 tick = 16.6 ms). |
| `design/gdd/input-system.md` | « publish latency p99 ≤ 16 ms intra-engine » (ligne 383, cible publique) | Même décision de tick rate garantit la borne. |
| `design/gdd/input-system.md` | AC-L-3 : « scène `tests/performance/input_benchmark.tscn` injectant 1000 events sur 1000 frames à 60 Hz physique » (ligne 482) | Le projet doit tourner à 60 Hz pour que ce test ait du sens — cet ADR le verrouille. |
| `design/gdd/input-system.md` | AC-CS-1 : « consumer polling `was_pressed_this_tick(&"jump")` depuis `_physics_process`, consumer lit `true` au `_physics_process` du frame N (pas N+1) » (ligne 493 — GDD à mettre à jour post-ADR-0004 Accepted, remplace `is_action_just_pressed` supprimé par ADR-0004 D-2) | Le pattern flag-via-signal prescrit dans cet ADR — implémenté concrètement par ADR-0004 D-3 (swap `_pressed ↔ _consumed` début `_physics_process`) — est exactement ce qui fait passer cette AC sur hardware render > physics. |
| `design/gdd/player-movement-system.md` | Jump buffer, coyote time tick-based déterministes | `Engine.get_physics_frames()` tick = 16.6 ms fixé ; les durées MVP (coyote = 6 ticks = 100 ms, buffer = 6 ticks = 100 ms) restent des entiers propres. |
| `design/gdd/player-movement-system.md` | AC (ligne 395) « Latence input→vélocité P99 ≤ 16 ms » | Tick rate 60 Hz + pattern `_physics_process` autorité garantissent la borne. |
| `design/gdd/player-movement-system.md` | AC (ligne 398) Physics tick rate test GUT | L'ADR met à jour la cible de `[3564, 3636]` (120 Hz) à `[1782, 1818]` (60 Hz). |
| `design/gdd/camera-system.md` | « Aucune logique caméra en `_physics_process` — pitch/yaw sont des inputs visuels, pas de la physique » (ligne 63) | Règle d'autorité de l'ADR confirme que `_process` est le bon callback pour la caméra (cosmétique). |
| `design/gdd/game-concept.md` | Pillar 1 « FLOW AVANT TOUT » : latence input → réponse ≤ 1 frame | L'ADR rend la cible atteignable par construction (1 tick = 1 frame vsync). |

## Performance Implications

- **CPU** : Jolt 60 Hz sur scène MVP Player (CharacterBody3D + 1-2 ShapeCast3D + environnement simple) est estimé ~1-2 ms/frame baseline ; marge pour ~10 ennemis physics-simulés avant saturation. À 120 Hz : ~2-4 ms baseline, marge réduite de moitié. **Budget registry** : allouer 4 ms sur 16.6 ms pour physics (25 %), à raffiner après premières mesures Sprint 1.
- **Memory** : négligeable. Jolt n'alloue pas plus à 60 Hz qu'à 120 Hz (mêmes collision shapes).
- **Load Time** : inchangé. Le choix de tick rate n'affecte pas le cold start.
- **Network** : non applicable (jeu solo, pas de multi au MVP).

## Migration Plan

- **Aucun code dans `src/`** : pas de migration de production.
- **Prototype `prototypes/movement-katana/`** : actuellement à 120 Hz. À convertir à 60 Hz **avant** toute réutilisation comme référence de feel pour les stories Movement. Tâche : modifier `project.godot` du prototype, re-playtester (Martin), confirmer que le feel survie.
- **GDD player-movement-system.md** : 5 occurrences « 120 Hz » à corriger (lignes 352, 355, 398, 405, 528) + ligne 541 (référence ADR obsolète). Mis à jour dans la même passe que cet ADR (approbation Martin 2026-04-21).
- **GDD camera-system.md** : 1 occurrence ligne 380. Mis à jour dans la même passe.
- **Registry `architecture.yaml`** : entrées `api_decisions` (physics_tick_rate, gameplay_authority), `forbidden_patterns` (mutate_gameplay_state_in_process), `performance_budgets` (target 60 fps, frame 16.6 ms, physics ~4 ms stub) à ajouter après approbation.
- **Project setting `physics/3d/default_gravity = 0.0`** : override obligatoire du défaut Godot (9.8). MovementController applique `GRAVITY = 24.0` custom manuellement dans `_physics_process` (hors wall-run — état `WallRunning` annule gravité par design), donc la gravité globale Jolt doit être désactivée pour éviter un double-cumul qui casserait la calibration du saut et du dash. Couvre **TR-mov-007** (G-3 HIGH `/architecture-review` 2026-04-21). Les RigidBody3D ponctuels nécessitant gravité (props, ennemis ragdoll futurs) activeront leur propre `gravity_scale`.

## Validation Criteria

L'ADR sera considéré correct si, mesurés en fin de Sprint 1 (première story Movement implémentée) :

- **VC-1 (Physics tick rate stable)** : test GUT `tests/performance/physics_tick_rate_test.gd`. GIVEN build debug. WHEN la scène test tourne 30 s. THEN `Engine.get_physics_frames()` delta ∈ [1782, 1818] (60 × 30 ± 1 %).
- **VC-2 (Input→velocity latency p99)** : test GUT `tests/performance/input_to_velocity_latency_test.gd`. GIVEN 200 dash inputs instrumentés. THEN p99 ≤ 16.6 ms release, ≤ 50 ms debug interpreter.
- **VC-3 (Jolt zero warnings)** : test GUT `tests/smoke/jolt_compatibility_test.gd`. GIVEN chargement scène MVP (Player + niveau grid). THEN zéro runtime warning Jolt (captage via `push_warning` redirect).
- **VC-4 (Frame budget physics)** : test perf `tests/performance/physics_frame_budget_test.gd` sur hardware référence (entry-level laptop). GIVEN scène MVP + 10 ennemis placeholder physics-simulés. THEN `Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)` ≤ 4 ms/frame p99.
- **VC-5 (Règle d'autorité respectée)** : lint rule ou code review. GIVEN l'ensemble du code gameplay dans `src/gameplay/`. THEN grep static détecte zéro mutation de `velocity`, `position`, `health`, ou état state-machine depuis `_process`.

Si une de ces VCs échoue, l'ADR est re-ouvert (pas automatiquement superseded — possibilité d'ajustement paramètres, ou escalade `max_physics_steps_per_frame`, ou envisager Alternative 2).

## Escalation Criteria (60 → 120 Hz Re-evaluation)

Cet ADR fixe 60 Hz pour MVP. Alternative 1 (120 Hz) reste une option de Polish si le playtest révèle un déficit perceptuel de latence. Pour éviter que la décision soit portée par du confirmation bias en interne, les triggers de re-évaluation sont **mesurables**, **externes** (playtesters tiers, pas Martin ni agents), et **spécifiés avant playtest**.

### EC-1 — Déclencheur quantitatif (score questionnaire)

- **Quand** : à chaque session playtest externe dès le premier Vertical Slice jouable (fin Sprint 3 ou plus tôt si prototype gameplay disponible). Répété à chaque build playtesté jusqu'à la fin de Polish.
- **Qui** : playtesters tiers, N ≥ 3 par session, **jamais informés du tick rate** ni de ce qu'on cherche à détecter (blind).
- **Outil** : questionnaire post-session intégré au protocole `/playtest-report`, question dédiée latence :
  > « Sur une échelle de 1 à 5, à quel point le jeu répondait-il instantanément à tes actions ? (1 = je sens un délai gênant, 5 = réponse immédiate, indissociable de ma commande) »
- **Seuil de déclenchement** : **≥ 2 playtesters sur 3 (ou ≥ 66 % si N > 3) notent ≤ 3/5** sur deux sessions consécutives avec des builds différents (évite le one-off bad-session).

### EC-2 — Déclencheur qualitatif (feedback libre)

- **Quand** : debrief post-session + transcripts playtest.
- **Outil** : coding lexical structuré sur les verbatims ouverts. Tags déclencheurs :
  - « j'anticipe mes inputs », « je dois prévoir », « j'appuie avant »
  - « ça répond pas tout de suite », « il y a un décalage », « c'est mou »
  - « je sens un délai », « c'est pas direct », « c'est flottant »
- **Seuil de déclenchement** : **≥ 1 playtester mentionne spontanément un tag de cette liste** sur une session, avec citation verbatim archivée au report. Un tag unique suffit (le feedback qualitatif spontané est coûteux à produire et rare — traité comme signal fort).

### EC-3 — Protocole de vérification post-trigger

Si EC-1 **ou** EC-2 se déclenche :

1. **Spike technique 1 sprint** : branche `spike/physics-120hz`. Modifier `physics/common/physics_ticks_per_second = 120` + rebudgéter `max_physics_steps_per_frame`. Tourner VC-1 à VC-4 sur hardware référence (entry-level laptop).
2. **A/B playtest blind** (même protocole que EC-1) : 2 builds side-by-side (60 Hz vs 120 Hz), testeurs différents des sessions ayant déclenché EC-1/EC-2, non informés du build qu'ils essayent. Même questionnaire.
3. **Critère d'adoption 120 Hz** : la cohorte 120 Hz doit score **≥ 1 point de moyenne au-dessus** de la cohorte 60 Hz sur la question latence (cohen's d > 0.4 proxy), **ET** le budget physics p99 mesuré sur laptop entry-level doit rester **≤ 6 ms** (2× le baseline 4 ms stubbé, limite supérieure absolue sinon Combat/IA n'ont plus de place).
4. **Décision** :
   - Si les deux critères passent → superseder cet ADR par ADR-00XX (Physics Rate 120 Hz), migration plan inclus.
   - Si score gagne mais budget dépasse → tenter Alternative 2 (60 Hz + interpolation INTERPOLATED sur Player) via nouvel ADR.
   - Si ni score ni budget ne passent → 60 Hz confirmé, archive du trigger dans cet ADR comme note « re-evaluated on [date], retained 60 Hz ».

### Non-triggers (à ne PAS interpréter comme escalade)

- Martin ou un agent interne rapporte un délai ressenti (biais auteur + absence de cécité).
- Un seul playtester note bas sur une seule session sans tag verbatim (bruit d'échantillon).
- Sentiment général « le jeu pourrait être plus nerveux » sans référence explicite au délai d'input (peut venir de FOV, camera shake, mouvement, audio — causes non-latency à investiguer séparément).
- Mesures de latence end-to-end dégradées au-delà du budget display **sans** dégradation p99 intra-engine : relève d'ADR-0002 rendering-latency (à créer), pas de cet ADR.

### Liens

- Protocole d'exécution : `/playtest-report` skill + template dédié à créer Sprint 3 (`design/playtest/latency-playtest-protocol.md`).
- Trigger source : `design/gdd/reviews/input-system-review-log.md` r4, R1 (game-designer F1, 2026-04-21).

## Related Decisions

- `design/gdd/input-system.md` — Cross-system dependency : la cible p99 ≤ 16 ms intra-engine dépend directement du tick rate fixé ici. Déjà aligné (r2).
- `design/gdd/player-movement-system.md` — Cross-system dependency : tuning jump buffer / coyote time / dash cooldown exprimé en ticks. GDD à mettre à jour (5 occurrences + ref ADR ligne 541).
- `design/gdd/camera-system.md` — Cross-system dependency : la caméra tourne en `_process` (décision GDD confirmée par cet ADR). GDD à mettre à jour (1 occurrence ligne 380).
- **Futur ADR rendering-latency** (à créer par technical-director avant Sprint 1, voir Input GDD Open Questions ligne 517) : VSync + refresh rate pour atteindre l'end-to-end ≤ 50 ms p99 cible playtest. Cet ADR-0001 fixe uniquement l'intra-engine ; le budget display est indépendant.
- **Futur ADR focus-handling** (à créer par godot-specialist, voir Input GDD Open Questions) : `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` IDs Godot 4.6 — indépendant mais même Sprint prep.

---

*Auteur : Architecture Decision skill, 2026-04-21*
*Validation engine : `godot-specialist` — verdict MINOR NOTES (3 enrichissements intégrés : pattern flag-via-signal, audit Jolt joints, scope `physics_interpolation_mode`)*
*Mode review : solo (TD-ADR gate skipped)*

*Révision 2026-04-21 (reopen) : ajout section `## Escalation Criteria (60 → 120 Hz Re-evaluation)` — triggers mesurables EC-1 (questionnaire playtest ≤ 3/5 sur ≥ 2/3 testeurs), EC-2 (feedback libre verbatim « j'anticipe », « délai », « mou »), EC-3 (protocole A/B blind spike + budget 6 ms p99 laptop). Issu de review log r4 Input System, R1 game-designer. Status reste **Proposed** (enrichissement pre-Accepted, aucune stance architecturale modifiée). Aucun impact registry.*

*Révision 2026-04-21 (amendement post-Accepted, G-3 résolu) : ajout `physics/3d/default_gravity = 0.0` en Project Settings et ligne correspondante en Migration Plan. Couvre TR-mov-007 (G-3 HIGH `/architecture-review` 2026-04-21) — nécessité de désactiver la gravité globale Jolt pour que le custom `GRAVITY = 24.0` appliqué par MovementController ne soit pas cumulé. Amendement paramétrique mineur (pas de changement de stance) : Status reste **Accepted**. Aucun impact registry (pas de nouvelle stance). Stories Movement référençant TR-mov-007 peuvent désormais passer `/story-readiness`.*

---

## Empirical Verification — EC-8 Jolt CCD (story-023, 2026-04-27)

> **EC-8 Claim** (origine : `design/gdd/level-system.md` Edge Case 8) :
> *« No collision clip-through at high velocity ; velocity > 20 m/s (dash + wall-run + wall-jump combo) must not clip walls of thickness ≥ 0.3 m ».*

**Statut antérieur** : `CLAIM-UNVERIFIED` (review level-system r2-fresh 2026-04-23, MINOR-r2-fresh-2 — flagué tech-risk Sprint 1, exigeait benchmark prototype).

**Statut courant** : **VERIFIED via story-023 (sub-gate auto, baseline locked 2026-04-27)**.

### Evidence

- **Sub-gate microbench** (story-014, livré 2026-04-27) :
  - Runner : `tests/performance/level_ccd_sweep_runner.gd` (3 thicknesses × 100 passes, CharacterBody3D + capsule r=0.3m h=1.8m, velocity 27 m/s sur Z négatif, motion_mode FLOATING, safe_margin 0.001).
  - Résultat local (Godot 4.6.2.stable, Darwin 25.4.0) : 0.3 m → 0 clips, 0.5 m → 0 clips.
  - CI job : `perf-level-ccd` (`.github/workflows/tests.yml`).
- **Sub-gate gameplay scenario** (story-023, livré 2026-04-27) :
  - Runner : `tests/performance/level_ccd_gameplay_runner.gd` (4 scenarios × 50 passes — dash_into_wall_03m, dash_into_wall_05m, wallrun_into_corner_03m, dash_wallrun_combo_03m — Player.tscn instancié avec CollisionShape3D programmatique + Area3D plane detector behind wall).
  - Détection clip : double critère (Area3D body_entered signal + fallback `global_position.z < wall_back_z - 0.05` ET 0 collisions).
  - CI job : `perf-level-ccd-gameplay` (`.github/workflows/tests.yml`).
- **Baseline lock + regression gate** :
  - Baseline : `tests/baselines/level-ccd-baseline.json` (sweep 0.3m/0.5m + gameplay 4 scenarios, tolérance 1 %).
  - Comparator : `tools/perf/compare_ccd_baseline.gd` (CLI + fonction pure `compare_results` réutilisable en GdUnit4).
  - Tests régression : `tests/integration/level/ccd_baseline_compare_test.gd` (4 tests : regression fail, within tolerance, below baseline, missing file → exit 2).
  - Gate CI : `compare_ccd_baseline.gd` est appelé en step terminal des deux jobs perf — fail si `current.clips_rate_pct > baseline + 1 %`.

### Déviations documentées (story-023)

- **DEV-1** : Le state machine PlayerController réel (dash/wall-run/wall-jump) n'est pas implémenté au MVP. Le runner gameplay instancie `Player.tscn` (real Jolt CharacterBody3D root + production scene tree) MAIS ajoute `CollisionShape3D` programmatiquement et drive `velocity` directement (pas via state machine). C'est l'approximation la plus proche de "réel" disponible — la gate teste la robustesse Jolt CCD à la magnitude de vélocité, pas la fidélité du state machine.
- **DEV-2** : `WALL_JUMP_HORIZONTAL = 12.0 m/s` est une approximation issue de la lecture Movement GDD constants — pas de calibration finale. À reconfirmer Sprint 1 lors de l'implémentation MovementController.
- **DEV-3** : Combo "wall_run + wall_jump" simulé comme vélocité linéaire cumulative (-18 m/s sur Z), pas comme transition state-machine.

### Impact aval

- **TR-lvl-039** : status `active → verified` dans `docs/architecture/tr-registry.yaml`, champ `verified_by: [story-023]`.
- **AC-LVL-41 PLAYTEST** : reste à valider en build jouable (déféré post-MVP — Movement state machine requis).
- **Si régression observée en CI** : 3 options de remediation pré-documentées (story-023 Phase 4 fallback) :
  1. `CharacterBody3D.safe_margin = 0.04` (Jolt-compatible 4 cm collision shell extension)
  2. Élever wall_thickness floor 0.3 m → 0.5 m (impact level design — coordination level-designer requise)
  3. ShapeCast3D manuel anti-tunneling sur murs critiques meta-tagged (pattern combat story-009)

### Status restant **Accepted**

Cette section est un **addendum d'evidence** (verification d'une claim downstream couverte par cet ADR), pas un changement de stance. Aucun impact registry. Aucune story Movement re-bloquée — au contraire débloque `AC-LVL-41 PLAYTEST` pour Sprint 2+.
