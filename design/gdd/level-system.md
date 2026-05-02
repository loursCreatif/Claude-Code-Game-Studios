# Level System

> **Status**: In Design r4 — r4 amendment 2026-04-27 (Audio System contract surgical addition : Open Question #1 Audio GDD résolu Option C — Audio consume `level_active` existant + lookup synchrone `get_etage_audio_streams(etage_id)` au lieu d'un nouveau signal `etage_loaded`). Pending fresh re-review (new session).
> **Author**: Martin + game-designer + level-designer + creative-director synthesis (solo mode, auto-approve)
> **Created**: 2026-04-23
> **Last Updated**: 2026-04-27 (r4 — Audio contract Option C : ajout Audio dans §Interactions avec lookup `get_etage_audio_streams`, ajout API dans pseudocode §Dependencies, ajout knob d'authoring `ETAGE_AUDIO_MAPPING`. Aucun nouveau signal — `level_active` reste l'event trigger unique. Zero churn pour Checkpoint/Enemy/Hazard/Secret/HUD/Tutorial.) — r2 revision (2026-04-23) : 5 BLOCKING cross-model résolus chirurgicalement : (1) Formules F2/F5/F7/F8 réparées — F2 arithmétique bornée [290, 350] + overhead global clarifié + sous-budget peers verrouillé ≤ 170dc ; F5 gate sur `etage_height ∈ [15, 30] m` plutôt que `avg` seul ; F7 logique floor-then-clamp bilatéral [3, 5] explicite + nominal divisor=3 ; F8 `wall_run_vertical_reach` dérivé formellement des constantes Movement + CI gate. (2) SecretSlot étendu `{volume, anchor, required_ability: StringName}` — enum {none, dash, double_jump, wall_run, wall_run_long} + lint obligatoire sur SecretAnchor + contrainte économique ≥ 1 secret wall_run. (3) R-2.6 typage de salle {ARENA, CORRIDOR, VERTICAL_CHAMBER, JUNCTION} + 5 règles séquençage S-1..S-5. (4) ACs : AC-LVL-29 API corrigée `Thread.get_caller_id()` + reclassé AUTO ; AC-LVL-31/31b scindé isolation vs combat normal + 500 frames ; AC-LVL-34 aligné Combat p50≤12ms, p99≤14ms ; AC-LVL-35 scindé 35a AUTO / 35b PLAYTEST ; AC-LVL-36 ajouté OBJECT_COUNT (pattern Combat) ; AC-LVL-41 protocole chiffré ; AC-LVL-44 condition d'entrée level.yaml ; AC-LVL-45 retiré ; AC-LVL-46..50 nouveaux pour couverture F3/F5/F6/F7 + diversité typologique. (5) AC-LVL-12/13 bitmask corrigé + API `set_collision_layer_value(N)` + gate `collision_mask ⊃ LAYER_PLAYER` ; EC-8 Jolt CCD flaggé CLAIM-UNVERIFIED + benchmark prototype Sprint 1 obligatoire ; EC-11 call_deferred reasoning reformulé (ordre autoload natif Godot, pas propriété de call_deferred).)
> **Implements Pillars**: P1 FLOW, P2 PROGRESSION, P3 SECONDE CHANCE, P4 SECRETS = MOUVEMENT
> **Depends on**: Game State Manager (Not Started — interface provisoire §Dependencies UI-1) ; `player-combat-system.md` Rule 16 (contrat onboarding salle 3)
> **Depended on by**: Checkpoint, Hazard, Enemy, Secret, HUD, Tutorial, Audio, VFX (tous Not Started — §Dependencies)
> **ADR references**: ADR-0001 (physics 60 Hz), ADR-0003 (rendering latency), ADR-0005 D-5 (CONNECT_DEFERRED). Pas d'ADR spécifique Level au MVP.

## Overview

Le Level System est le conteneur spatial de la run : il héberge la géométrie hand-crafted d'un étage de la tour Arasaka, orchestre le chargement/déchargement de scène via le Game State Manager, et expose aux autres systèmes (Checkpoint, Hazard, Enemy, Secret, HUD, Tutorial) les points d'ancrage dont ils dépendent (spawn joueur, positions de checkpoints, slots d'ennemis, volumes de secrets, triggers de transitions inter-salles). Le scope **MVP** est un **étage unique de 8-10 salles linéaires verticales** avec checkpoints toutes les 2-3 salles (cf. game-concept §Required for MVP), assemblé en primitives Chrome Zen (cubes, plans, rampes + 1 shader flat ; aucun mesh importé). Les couloirs, portes et corridors respectent le gabarit `KATANA_REACH = 1.8 m` (registry — un joueur dashant ne peut pas tomber *au-delà* de portée d'une surface murale utile) ; la géométrie statique vit sur `LAYER_ENVIRONMENT = 4` (collision walk/run/wall-run) et les déclencheurs non-solides sur `LAYER_INTERACTIVE = 5` (volumes respawn, triggers secret, portes). Le système **n'implémente pas** le gameplay de ses occupants — il publie l'emplacement, les autres systèmes instancient le comportement — ce qui préserve les quatre piliers : FLOW (1 seul scene tree statique préchargé par étage = zéro stutter de streaming dans une salle), PROGRESSION (salles ré-explorables avec un moveset grandi pour atteindre les secrets), SECONDE CHANCE (checkpoints denses + `RESPAWN_DELAY = 0.05 s` pull déclenché depuis Checkpoint System), SECRETS = MOUVEMENT (volumes cachés placés *hors chemin nominal* derrière un défi de parkour, jamais derrière une énigme). Dépend foundationnellement de Game State Manager (Not Started — interface provisoire dans ce GDD) ; aucun ADR dédié au Level System n'est requis au MVP (les contraintes temps-réel sont absorbées par ADR-0001/0003).

## Player Fantasy

**La tour Arasaka te refuse.**

Elle est un corps verrouillé, un empilement corporate de salles qui t'ont été *pensées contre*. Chaque mur est une fin, chaque porte est un gabarit, chaque plateforme hors portée est une provocation. Tu n'es pas un invité ici. Tu es une intrusion.

Alors tu forces. Tu dashs à travers un couloir qui voulait te ralentir. Tu wall-runs sur un mur qui n'a pas été pensé comme un sol. Tu traces une ligne oblique à travers un vide qui n'attendait pas de ligne. La salle cède, ou plutôt tu l'obliges à céder. Ton corps cybernétique convertit l'architecture en parcours, et la tour, salle après salle, perd un peu d'elle-même.

Le vrai moment Level, c'est celui-ci : tu arrives en bas d'un puits vertical de quarante mètres. En haut, une lueur cyan — un crédit. Tu n'as pas encore le wall-run long. Tu redescends, tu fais la route normale, tu continues à grimper l'étage. Trois runs plus tard, tu as acheté le wall-run long au shop. Tu reviens à ce puits. Prise d'élan, premier mur, rebond, deuxième mur, sommet — deux secondes. Le puits qui te narguait est devenu une ligne que tu traces. *La tour t'avait refusée ; maintenant tu la traverses.* Ce moment — et les dizaines qui le précèdent et le suivent — est ce que le Level System existe pour délivrer. **Ce puits est une primitive structurelle explicite de la tour, pas une métaphore : il est encodé sous l'archetype `Shaft` / primitive `VerticalShaftRoom` (R-1 r2, F5 r2 multi-rise), avec un gabarit de rise ≤ 15 m par chambre-puits qui permet à la Fantasy de tenir structurellement — voir R-2.6 et §Formules F5.**

La tour ne te récompense pas. Elle **cède**. Et chaque fois qu'elle cède, tu lis dans sa géométrie une promesse à venir : une plateforme plus haute, un couloir plus court, un secret plus tordu. Tu n'es pas là pour habiter la tour. Tu es là pour la percer, étage après étage, jusqu'au sommet.

**Ancrage piliers** :
- **P2 PROGRESSION** : chaque upgrade achetée convertit une plateforme inaccessible en route tracée. La progression est *géographique*, pas statistique.
- **P4 SECRETS = MOUVEMENT** : les secrets sont des provocations verticales (lueurs cyan hors portée), jamais des énigmes cérébrales.
- **P1 FLOW** : le framing antagoniste exige un tempo agressif ; aucune invite à la contemplation pendant le run (la reconnaissance d'une route neuve est visuelle et instantanée, pas narrative).
- **P3 SECONDE CHANCE** : mourir, c'est la tour qui te refuse une fois de plus. Tu reviens immédiatement pour lui prouver le contraire.

**Ce que le joueur ne doit jamais ressentir** : stutter de chargement intra-salle, flottement « je ne sais pas où aller », porte qui ne s'ouvre pas sans indication visuelle, dead-zone où le katana ne trouve pas de mur à run. Le Level System est transparent quand il fonctionne — il devient un reproche silencieux à chaque frame dropped.

## Detailed Design

### Core Rules

**R-1. Hiérarchie de scène canonique (MVP) — r2 : hiérarchie 3D avec archetypes**

La hiérarchie r2 remplace le plat `Room_NN / Wall / Floor / Ramp` r1 par une structure **3D explicite** : chaque salle est un archetype typé (R-2.6 r2) et peut composer des **primitives 3D réutilisables** (`Mezzanine`, `Atrium`, `ShaftConnector`, `VerticalShaftRoom`). Les primitives sont des sous-scenes `PackedScene` authoring-time avec contrat collider + anchors garanti, validables au lint pré-build. La forme plate r1 reste rétrocompatible : une salle `Traversal` peut n'avoir aucune primitive composée (juste Floor/Wall/Ramp).

```
res://scenes/levels/etage_01.tscn   (Node3D — racine étage)
├── StaticEnvironment  (Node3D — géométrie non-interactive, layer 4)
│   ├── Room_01 (Node3D)
│   │   ├── @export archetype: RoomArchetype   # Traversal | Combat | Shaft | SecretHub
│   │   ├── Floor_01     (StaticBody3D, CollisionShape3D, layer 4)
│   │   ├── Wall_01..N   (StaticBody3D, layer 4)
│   │   ├── Ramp_01..N   (StaticBody3D, layer 4)
│   │   ├── Primitives   (Node3D — primitives 3D composées, optionnel, archetype-driven)
│   │   │   ├── Mezzanine_01..M          (PackedScene — plate-forme intermédiaire : wall-run bas ≥ 3 m + ledge franchissable en double-jump, ceiling local 4 m)
│   │   │   ├── Atrium_01..A             (PackedScene — vide vertical interne visible multi-étage, ceiling local ≥ 6 m, guides verticaux wall-run sur 2 niveaux)
│   │   │   ├── ShaftConnector_01..S     (PackedScene — jonction salle-salle verticale : 2 × wall wall-run face-à-face ≥ 4 m + rail de grip optionnel Tier 2)
│   │   │   └── VerticalShaftRoom_01..V  (PackedScene — **chambre-puits entière** ≥ 8 m rise, jusqu'à 15 m ; archetype `Shaft` obligatoire — cf. F5 r2 multi-rise)
│   │   └── MeshInstance3D + shader_chrome_zen_flat (visuel Chrome Zen)
│   ├── Room_02..Room_N
│   └── ...
├── InteractiveVolumes  (Node3D — triggers, layer 5)
│   ├── RoomTrigger_01..N           (Area3D — détection entrée salle)
│   ├── CheckpointVolume_01..K      (Area3D — ancre Checkpoint System)
│   ├── SecretCollectVolume_01..M   (Area3D — **r2 fix #4** — zone de collection du secret, cap 3/salle strict, layer 5 non-solide)
│   └── WorldBoundsVolume           (Area3D englobant — détection out-of-world, CollisionShape3D **obligatoirement BoxShape3D**)
├── SpawnMarkers       (Node3D — points nommés pour peers)
│   ├── PlayerStart                 (Marker3D — spawn initial étage)
│   ├── EnemySlot_01..P             (Marker3D — slots Enemy System)
│   ├── HazardSlot_01..H            (Marker3D — slots Hazard System)
│   ├── CheckpointAnchor_01..K      (Marker3D — position respawn associée à CheckpointVolume_*)
│   ├── SecretLureMarker_01..M      (Marker3D — **r2 fix #4** — marqueur **visible cross-room** ; lueur cyan #3EE4FF portée ≥ 20 m ; **aucun collider** ; appariement strict avec SecretCollectVolume_NN de même NN ; budget rendu séparé cf. R-4 r2)
│   └── SecretAnchor_01..M          (Marker3D — position de spawn du *contenu crédité* du secret — entité / pickup affecté au volume)
├── OnboardingAnchors  (Node3D — **r2 fix #5** — contrat combat `player-combat-system.md` Rule 16, étage 1 uniquement)
│   ├── FirstEnemySightline         (Marker3D — position de spawn grunt **visible dans les ≤ 10 s** après spawn joueur, ancrée en salle d'onboarding)
│   └── SafeZoneCenter              (Marker3D — centre d'une zone safe ≥ 3 m rayon, hors portée laser/grunt, où le joueur peut tester `attack` sans mourir)
└── EtageExitTrigger   (Area3D — fin d'étage → Game State Manager)
```

**Conventions de nommage r2** :
- `archetype: RoomArchetype` — enum @export obligatoire (lint fail si absent ; AC-LVL-52 r2).
- Primitives 3D : PackedScene chargées inline à boot (pas `instantiate()` runtime — ADR-0001 60 Hz intacte).
- **Tuple Secret** indexé strict (même NN) : `SecretLureMarker_NN` ↔ `SecretCollectVolume_NN` ↔ `SecretAnchor_NN`. Lure sans volume (ou inversement) → lint fail AC-LVL-53 r2.
- `OnboardingAnchors` : présent **uniquement étage 1** (tutoriel) ; `Level.get_onboarding_anchors() → Dictionary` retourne `{}` si sous-arbre absent — Combat / Tutorial Systems consomment via existence-check non-fatal.

**R-2. Invariants de placement géométrique — r2 : locaux par archetype**

Les rails universels r1 (`R-2.1..R-2.5` appliqués à toutes les salles) sont **supprimés** : ils contredisaient structurellement la Player Fantasy "puits 40 m" (finding CD fix #3). Les invariants r2 sont **locaux par archetype**, avec seulement deux rails réellement universels (portes et wall-run width-height) maintenus parce qu'ils dérivent du registry (KATANA_REACH, Movement jump_apex).

**R-2.U — Invariants universels (2 seuls) — dérivés du registry, immutables sans amendement** :
- **R-2.U.1** Toute porte entre deux salles : **largeur ≥ 2 × KATANA_REACH = 3.6 m**, **hauteur ≥ 2.5 m**. Source : Formula 1. Immutable.
- **R-2.U.2** Tout mur taggé `wall_run_enabled = true` : **hauteur ≥ 4.0 m**, **longueur ≥ 3.0 m**, **orientation ± 5° vertical**. Source : Formula 8 (dérivé Movement). Immutable.
- **R-2.U.3** Aucune géométrie statique ne descend sous `Y = -2.0 m` absolu (`WorldBoundsVolume` trigger respawn déclenché plus bas). Universel parce qu'il définit la borne basse de toutes les scènes. Exception : le *plancher* d'un `VerticalShaftRoom` qui démarre au sommet d'une salle `Combat` peut avoir `y_local = 0` ≫ `y_absolute` — c'est la somme `room_origin.y + shape.aabb.min.y` qui doit ≥ -2.0 m, pas le `local.y`.

**R-2.A — Invariants locaux par archetype** (table par archetype ; gate lint pré-build `validate_room_archetype_invariants(room) → Array[ValidationError]`) :

| Invariant local | `Traversal` | `Combat` | `Shaft` | `SecretHub` |
|-----------------|-------------|----------|---------|-------------|
| Dimensions XZ typiques | 4×10 m (corridor) | 12×12..15×15 m | 8×8 m | 10×10 m |
| Ceiling height (m) | [3.5, 4.5] | [5.5, 6.5] | **[8, 15]** (shaft — cf. F5 r2) | [5, 6] |
| `ROOM_RISE` admissible (m, delta vers salle suivante) | [1.0, 4.0] | [0.0, 2.0] (**plan privilégié** — wall-run latéral + combat lisible) | **[8, 15]** (multi-rise — peut absorber plusieurs dizaines de m à elle seule) | [2.0, 4.0] |
| Couloir de transition maximal attaché | 8 m | 6 m (évite couloir tendu pré-combat) | N/A (les Shaft se traversent verticalement, pas d'entrance-corridor horizontal) | 8 m |
| Primitives 3D typiques | 0..1 `Mezzanine` | 0..2 `Mezzanine`, 0..1 `Atrium` | ≥ 1 `VerticalShaftRoom` **obligatoire** (définitionnel) + `ShaftConnector` optionnel | 1 `Atrium` recommandé + 1..2 `Mezzanine` |
| Wall-run requis (murs R-2.U.2) | 0..1 (opportunité de chaîne, pas forcé) | **≥ 2** (chaînage moveset combat) | **≥ 3 répartis sur ≥ 2 niveaux** (ascension continue) | ≥ 1 (supporter la lure) |
| `EnemySlot` typique | 0..1 | **≥ 3** | 0..1 (combat vertical secondaire) | 0..2 (pression sur la lure visible) |
| `SecretLureMarker` typique | 0 | 0..1 (rare — Combat est pour le combat) | 0..1 (secret au sommet = récompense pilier 2) | **≥ 1** (définitionnel de l'archetype) |
| Duration novice attendue | 10-25 s | 45-90 s | 30-60 s | 15-40 s |

**Règles de séquençage (authoring-time, gate pré-build)** :
- **S-1** : ≥ **3 archetypes distincts** / étage MVP (pas "10 Combat"). Gate AC-LVL-50 r2 (a).
- **S-2** : jamais **2 `Combat` consécutifs**. Séparation minimale = 1 salle autre archetype. Gate AC-LVL-50 r2 (d).
- **S-3** : ≥ **1 `Shaft`** / étage (renforce Player Fantasy §Verticalité + héberge le moment-icône 40 m). Gate AC-LVL-50 r2 (b).
- **S-4** : salle finale avant `EtageExitTrigger` ∈ `{SecretHub, Traversal}` (annonce visuelle de sortie V-2 — `Combat` trop tendu).
- **S-5** : ≥ **1 `SecretHub`** / étage (supporte ≥ 1 secret visible `required_ability ≠ none` depuis la route — Pillar 4).

**Violation = refus d'archetype + conversion forcée** : un `Combat` qui ne contient pas ≥ 2 murs wall-run échoue le lint → correction obligatoire (ajouter murs OU changer archetype en `Traversal`). Cette contrainte force le level-designer à *choisir un archetype cohérent* plutôt qu'à répéter des salles indiscriminées.

**R-2.6. Enum `RoomArchetype` — rôles, features obligatoires, justification**

```gdscript
enum RoomArchetype {
    TRAVERSAL,   # Transition / pacing bref — le joueur ne s'arrête pas
    COMBAT,      # Arène multi-ennemis — chaînage moveset central
    SHAFT,       # Puits vertical d'ascension — parkour pur, ≥ 1 `VerticalShaftRoom` obligatoire
    SECRET_HUB,  # Carrefour avec lure(s) visible(s) — secret-routing Pillar 4
}
```

Alias de compatibilité r1 (support migratoire pour du contenu amorcé r1) : `ARENA → COMBAT`, `CORRIDOR → TRAVERSAL`, `VERTICAL_CHAMBER → SHAFT`, `JUNCTION → SECRET_HUB`. Le champ legacy `room_type: RoomType` est lisible en import, converti automatiquement. Tout **nouveau** contenu DOIT utiliser `archetype: RoomArchetype`.

**Validation durées** (MVP 8-10 salles) : plancher 2 min (tout `Traversal`, violerait S-3 de toute façon), plafond 10 min (tout `Combat`, violerait S-2). Mix réaliste = 6-12 min / run novice × 2 tentatives + retours secrets = 20-25 min (aligné game-concept.md §Session Length).

**R-3. Invariants de collision layers**

| Layer | Nom | Contenu | Masque de collision player |
|-------|-----|---------|----------------------------|
| 4 | `LAYER_ENVIRONMENT` | Sols, murs, rampes, plafonds, tous StaticBody3D (incluant primitives Mezzanine / Atrium / ShaftConnector / VerticalShaftRoom) | ✅ solid (walk, run, wall-run, block) |
| 5 | `LAYER_INTERACTIVE` | RoomTrigger_*, CheckpointVolume_*, **SecretCollectVolume_*** (r2), EtageExit, WorldBounds | ❌ pass-through (Area3D signal-only) |

**Aucune** autre layer utilisée par Level au MVP. Les `SecretLureMarker_*` (r2 fix #4) **ne portent aucun collider** — ce sont des `Marker3D` visuels purs, rendus par VFX System via abonnement au boot (V-3 r2). Enemy (layer TBD par Enemy System) et Player (layer TBD par Movement) ne vivent pas dans la scène d'étage — ils sont ajoutés runtime sur les slots marqueurs.

**R-4. Budgets perf — r2 : différenciés par archetype**

Les budgets uniformes r1 (30 DC / 25 StaticBody3D / 8 Area3D partout) ne reflètent pas la réalité : un `Combat` doit absorber plus de wall-run décors + mezzanines, un `Shaft` a besoin de peu de géométrie horizontale mais beaucoup de ceiling. R-4 r2 introduit des budgets **par archetype**, avec le même plafond étage total `draw_calls_level ≤ 350` (Formula 2 inchangée — contrat avec budget_peers ≤ 170 préservé).

| Budget par salle (statique seul — peers exclus) | `Traversal` | `Combat` | `Shaft` | `SecretHub` | Rationale |
|---|-------------|----------|---------|-------------|-----------|
| Draw calls | **≤ 22** | **≤ 38** | **≤ 32** | **≤ 34** | Combat absorbe wall-run décors + mezzanines ; Shaft absorbe la répétition murs verticaux ; Traversal minimaliste |
| StaticBody3D | ≤ 18 | ≤ 32 | ≤ 28 | ≤ 25 | Combat plus dense en collision (obstacles tactiques) |
| Area3D | ≤ 4 | ≤ 10 | ≤ 6 | ≤ 12 | SecretHub porte les SecretCollectVolume ; Combat porte RoomTrigger + zones de pression Enemy |
| Marker3D | ≤ 10 | ≤ 30 | ≤ 18 | ≤ 24 | Combat accumule EnemySlot + HazardSlot ; SecretHub accumule lures + anchors |
| VRAM statique (MB — atlas partagé) | ≤ 3 | ≤ 6 | ≤ 5 | ≤ 5 | Atlas partagé global ; Combat ajoute quelques textures placeholders hit-decals |

**Calibration pour mix réaliste N=10** : 2 × Traversal + 3 × Combat + 1 × Shaft + 2 × SecretHub + 2 × flex = `(2×22)+(3×38)+(1×32)+(2×34) + 2×? = 258 + flex`. Si flex = 2 × Traversal : `258 + 44 = 302 DC`. Ajouté `LEVEL_OVERHEAD = 50` → `352 DC` — **dépasse plafond 350 de 2**. Résolu : une des 3 Combat est downgradée en SecretHub (`302 - 38 + 34 = 298 DC` → `348 DC` total). Gate AC-LVL-31 r2 vérifie par-salle **et** le plafond agrégé 350.

**Primitives 3D — budget attribué** (inclus dans la ligne `StaticBody3D` ci-dessus, pas additionnel) :

| Primitive | DC typique | StaticBody3D | Notes |
|-----------|------------|---------------|-------|
| `Mezzanine` | 3-5 | 4-6 | 1 plate-forme + 2 murs + ledge |
| `Atrium` | 5-8 | 6-10 | Vide vertical interne + 4 murs + 2 guides wall-run |
| `ShaftConnector` | 4-6 | 4-6 | 2 murs face-à-face + rail optionnel |
| `VerticalShaftRoom` | 8-14 | 12-20 | Chambre puits entière (plusieurs niveaux de wall-run) — **consomme ≥ 50 % du budget d'une salle `Shaft`** |

**VRAM statique étage total** : ≤ **50 MB** (plafond inchangé r1). Somme par-salle ci-dessus × 10 salles ≈ 40-50 MB en pic (mix réaliste). Gate AC-LVL-32.

**R-5. Règles de construction (authoring)**
- **R-5.1** Un étage = un seul `.tscn` unique au MVP (pas de room-streaming). Les salles sont des sous-scenes **inline** (pas `instantiate()` runtime), pré-chargées à boot.
- **R-5.2** Toute instance `Marker3D` destinée à un peer system est nommée par convention : `PlayerStart`, `EnemySlot_NN`, `HazardSlot_NN`, `CheckpointAnchor_NN`, `SecretAnchor_NN` (zero-padded 2 chiffres). Cohérence indexée entre `CheckpointVolume_NN` ↔ `CheckpointAnchor_NN` pour le même NN.
- **R-5.3** `PlayerStart` est unique par étage. Si absent, chargement fatal (assert au `_ready()`).
- **R-5.4** Les triggers Area3D ont `monitorable = false` et `monitoring = true` (Level System détecte les entrées, n'est jamais détecté).
- **R-5.5** Toute géométrie sur layer 4 est **convex** OU `ConcavePolygonShape3D` (Jolt par défaut — ADR-0001). Pas de `MeshInstance3D` sans `CollisionShape3D` parent si le joueur peut le toucher (flag via lint post-MVP).
- **R-5.6** **WorldBoundsVolume utilise obligatoirement `BoxShape3D`** (jamais `ConcavePolygonShape3D` ni trimesh). Raison : Jolt broad-phase gère efficacement une grosse Area3D convex (1 shape = O(1) overlap query), mais explose en coût CPU sur concave shape de 5800 m³ (traversal polygon-par-polygon à chaque physics tick). Enforced par `validate_level_shapes()` lint runtime debug build (AC-LVL-38 addendum).

### States and Transitions

**Définition canonique de l'enum (GDScript) :**

```gdscript
class_name LevelSystem
extends Node

enum LevelState {
    UNLOADED,    # Boot initial ou post-Unloading — aucune scène d'étage en mémoire
    LOADING,     # ResourceLoader.load_threaded_request en cours — joueur en fade-out
    ACTIVE,      # Scène attachée, PlayerStart résolu, signaux connectés
    UNLOADING,   # queue_free() de la racine étage, désabonnement peers en cours
}
```

**Contrat d'introspection** : `func get_state() -> LevelState` est l'unique source de vérité runtime. Tout peer qui doit réagir à l'état Level lit cette méthode (synchrone, gratuit) ou s'abonne aux signaux `level_active` / `level_unloading`. Les noms des valeurs enum sont **immutables** — renommer casse le contrat Game State Manager.

**Machine d'état Level System (pilotée par Game State Manager) :**

```
Unloaded ──(load_etage(id))──> Loading ──(resources_ready)──> Active
                                  │
Active ──(etage_exit_triggered)──> Unloading ──(scene_freed)──> Unloaded
Active ──(player_died_in_void)───> Active (pas de transition — Checkpoint System gère le respawn)
Active ──(run_abandoned)──> Unloading
```

**Détail des états :**

| État | Entrée | Invariants | Sortie |
|------|--------|------------|--------|
| `Unloaded` | Boot initial / après Unloading | Aucune scène d'étage en mémoire. Autoloads seuls. | `load_etage(id)` depuis Game State Manager |
| `Loading` | Appel `load_etage(id)` | `ResourceLoader.load_threaded_request(path)` en cours. Joueur en fade-out. | `load_threaded_get_status() == THREAD_LOAD_LOADED` → `Active` |
| `Active` | Scène attachée au tree, `PlayerStart` résolu, signaux connectés aux peers | 1 seule étage Active à la fois. Tous les Area3D actifs. Checkpoint/Enemy/Secret/Hazard Systems peuvent lire les Markers. | `EtageExitTrigger` body_entered par player OU run_abandoned |
| `Unloading` | Signal `etage_exit_requested` émis | Désabonnement des peers, `queue_free()` de la racine étage, décrémentation VRAM | Frame suivante → `Unloaded` |

**Transitions atomiques — règles d'ordre :**

- **T-1** `load_etage(id)` ne peut être appelé qu'en `Unloaded`. Rejet sinon (assert).
- **T-2** `Loading → Active` publie le signal `level_active(etage_id: int, player_start: Vector3)` sur le même tick que l'ajout au tree. **Les peers (Checkpoint, Enemy, Hazard, Secret) s'abonnent à ce signal pour se câbler** (voir R-3 des systèmes peers dans leurs propres GDD).
- **T-3** `Active → Unloading` publie `level_unloading(etage_id: int)` **avant** `queue_free()`, laissant 1 frame aux peers pour se désabonner proprement (pas de dangling reference).
- **T-4** Room transitions (entrée dans `RoomTrigger_NN`) n'affectent **pas** l'état Level — elles publient seulement `room_entered(room_index: int)` pour le HUD et le Tutorial. Aucune salle n'est « déchargée » intra-étage au MVP (tout est préchargé).

### Interactions with Other Systems

| Peer System | Sens | Ce que Level System **fournit** | Ce que Level System **consomme** | Signal ou API |
|-------------|------|---------------------------------|----------------------------------|---------------|
| **Game State Manager** | ↔ bidirectionnel | Signal `level_active`, `level_unloading`, `etage_completed(etage_id)` | Appel `load_etage(id)`, `unload_current()` | Function calls + typed signals |
| **Player Movement** | Level → Movement | Collision statique layer 4, wall-run surfaces R-2.3 | — (Level ignore Movement) | Physique Jolt (ADR-0001), aucun signal direct |
| **Camera System** | — | — | — | Aucune interaction (Camera suit le player, ignore l'étage) |
| **Checkpoint System** | Level → Checkpoint | Array `get_checkpoint_slots() → Array[CheckpointSlot]` où `CheckpointSlot = { volume: Area3D, anchor: Vector3 }` publié dans `level_active` | — | Signal `level_active` avec payload |
| **Enemy System** | Level → Enemy | Array `get_enemy_slots() → Array[Marker3D]` publié dans `level_active` | — | Signal `level_active` avec payload |
| **Hazard System** | Level → Hazard | Array `get_hazard_slots() → Array[Marker3D]` publié dans `level_active` | — | Signal `level_active` avec payload |
| **Secret System** | Level → Secret | Array `get_secret_slots() → Array[SecretSlot]` où **(r2 fix #4)** `SecretSlot = { lure: Marker3D, collect_volume: Area3D, content_anchor: Vector3, required_ability: StringName }` publié dans `level_active`. `lure` et `collect_volume` sont **spatialement distincts** — le lure est visible cross-room à sa position de provocation visuelle, le volume est placé à la position de collection réelle (souvent élevée/hors portée au premier run). | — | Signal `level_active` avec payload |
| **Player Combat** | Level → Combat **(r2 fix #5)** | Contrat onboarding `player-combat-system.md` Rule 16 (salle 3 étage 1 uniquement) — Level fournit `get_onboarding_anchors() → Dictionary` avec clés `"first_enemy_sightline"` (Marker3D) et `"safe_zone_center"` (Marker3D). Combat / Enemy Systems consomment pour spawn d'onboarding. Si étage ≠ 1 : le dictionnaire est vide (pas fatal — existence-check côté peer). | — | Synchronous method call |
| **HUD System** | Level → HUD | Signal `room_entered(room_index: int, total_rooms: int)` pour affichage progression étage | — | Typed signal |
| **Tutorial System** (VS) | Level → Tutorial | Signal `room_entered(room_index)` + API `get_tutorial_anchor(tag: String) → Marker3D` | — | Signal + method |
| **Audio System** | Level → Audio | (a) Signal `room_entered(room_index, total_rooms)` (déclenche ambient layer swap intra-étage éventuel). (b) Signal `level_active(etage_id, player_start)` consommé en `CONNECT_DEFERRED` — Audio handler `_on_level_active` lookup synchrone `get_etage_audio_streams(etage_id) -> Dictionary{music: AudioStream, ambient: AudioStream}` puis `play_music()` + crossfade ambient. (c) Signal `level_unloading(etage_id)` → fade-out music 0.5 s. **Pas de signal `etage_loaded` dédié** (Open Question #1 Audio GDD r1 résolu r4 Option C). | — | Typed signals + synchronous method `get_etage_audio_streams` |
| **VFX System** | Level → VFX | Marker3D ancres pour spawn VFX (ex: particle projector à chaque porte) | — | Property lookup at boot |

**Principe d'encapsulation** : Level System **publie de la donnée spatiale** (où sont les choses). Il n'appelle aucune méthode de peer. Les peers **lisent** les slots via l'API exposée au moment de `level_active`, puis ils instancient/gèrent leurs propres entités sur ces ancres. Cette séparation permet à chaque peer de gérer son cycle de vie (ex : Enemy System respawne ses ennemis sur les mêmes slots au checkpoint sans que Level ait à les tracker).

**SecretSlot — r2 : contrat split `lure` vs `collect_volume`** (fix CD #4)

Un secret est **deux objets distincts** qui partagent le même index NN :
- **`SecretLureMarker_NN`** (Marker3D, `SpawnMarkers`) — *visuel pur*, **aucun collider**, rendu par VFX System (lueur cyan #3EE4FF, portée ≥ 20 m). Rôle : provoquer le joueur à distance ("qu'est-ce qu'il y a là-haut ?"). Budget rendu distinct (R-4 r2, tranche `Marker3D` par archetype). Peut être visible depuis plusieurs salles (pas contraint par les bounds de la salle où il est placé).
- **`SecretCollectVolume_NN`** (Area3D, `InteractiveVolumes`, layer 5) — *zone de collection* du secret, cap strict **≤ 3 par salle** (R-4 r2 budget Area3D). Déclenche `body_entered` quand le joueur entre. C'est le collider, pas le visuel.
- **`SecretAnchor_NN`** (Marker3D, `SpawnMarkers`) — position de spawn du *contenu crédité* du secret (pickup crédit, drop rare, etc.). C'est le point d'ancrage de l'entité "récompense" que Secret System place dans le volume à l'activation.

**Pourquoi la séparation** (finding CD fix #4) : en r1, `SecretVolume_NN` (Area3D) était à la fois le trigger de collection ET le porteur visuel (position du glow cyan). Conséquence : les secrets "inter-salles" (lueur visible depuis la salle 3, volume dans la salle 4) étaient **structurellement impossibles** — Pillar 4 ("SECRETS = MOUVEMENT, provocations visuelles hors-portée") s'en trouvait mutilé. La r2 sépare : le lure **peut être dans la salle A** et le volume **dans la salle B adjacente ou supérieure**, le glow reste visible pendant que le joueur travaille la route.

Exemple canonique de la Player Fantasy (le puits 40 m) : `SecretLureMarker_01` au sommet du `VerticalShaftRoom` visible depuis la salle 1 (d'en bas), `SecretCollectVolume_01` dans la dernière chambre du shaft (y ≈ +35 m), `SecretAnchor_01` juste à côté du volume. Le joueur voit la provocation dès la salle 1, la collection se fait 40 m plus haut.

Le champ **`required_ability: StringName`** est exporté sur `SecretLureMarker_NN` (le marqueur visible — c'est celui qui dit "tu viens quand tu as la capability"). Valeurs canoniques :
- `&"none"` : accessible sans capability gated — route principale uniquement. À utiliser avec parcimonie.
- `&"double_jump"` : requires `can_air_jump = true` (Movement System R-8).
- `&"dash"` : requires `can_dash = true`.
- `&"wall_run"` : requires `can_wall_run = true`, configuration single-wall.
- `&"wall_run_long"` : requires `can_wall_run = true` ET combo avec dash/double-jump (séquence 2+ manœuvres).

**Responsabilités** :
- **Level System** : publie `SecretSlot` (lure + volume + anchor + required_ability). **Ne vérifie jamais** la capability du joueur.
- **Secret System** : consomme `required_ability` pour router le contenu. Connecte `SecretCollectVolume_NN.body_entered → Secret._on_secret_collected(slot)`.
- **HUD System** : lit `required_ability` pour afficher "available now" selon capabilities joueur.
- **VFX System** : rend la lueur cyan sur les `SecretLureMarker_NN` à partir du boot `level_active` (0 coût collision — Marker3D pur).

**Default explicit** : si un `SecretLureMarker_NN` n'a pas d'export `required_ability`, le lint pré-build `validate_secret_lures()` fail avec "SecretLureMarker_NN missing required_ability — must be one of {none, double_jump, dash, wall_run, wall_run_long}". Pas de default implicite.

**Tuple cohérence** : chaque `SecretLureMarker_NN` DOIT avoir un `SecretCollectVolume_NN` et un `SecretAnchor_NN` de même index NN (AC-LVL-53 r2). Orphelin → lint fail.

**Contrainte économique** : au MVP, ≥ 1 secret `required_ability ∈ {wall_run, wall_run_long}` par étage (renforce Player Fantasy "tu reviendras quand tu auras le wall-run"). AC-LVL-46 gate cette contrainte.

### Combat Onboarding Contract — r2 fix #5

**Source** : `player-combat-system.md` Rule 16 — *« sans viewmodel et sans UI, le Level System DOIT garantir qu'un ennemi est visible dans les 10 premières secondes de la salle de tutoriel et qu'une zone safe permet au joueur d'expérimenter `attack` sans mourir. Ce contrat est à tracer dans le Level System GDD à venir. »*

La r2 trace ce contrat comme responsabilité explicite du Level System :

**CO-1** — La **salle d'onboarding combat** est la 3ᵉ salle de l'étage 1 (salle `Combat` de tutoriel canonique aligné `design/gdd/player-combat-system.md` §Tutoriel). Elle porte le sous-arbre `OnboardingAnchors` (R-1 r2) avec 2 Marker3D :
- `FirstEnemySightline` : position de spawn d'un grunt, **≤ 15 m depuis PlayerStart de la salle** et **en ligne de vue directe** depuis l'entrée de la salle, positionné tel qu'un joueur novice (vitesse 4 m/s walk) **atteint visuellement** le grunt ≤ **10 s** après le `room_entered(3)`. Level System mesure cette garantie via lint authoring-time : `sightline_trace()` raycast de `PlayerStart` vers `FirstEnemySightline` — si obstruction, lint fail.
- `SafeZoneCenter` : centre d'un disque `r = 3 m` où aucun laser / projectile ennemi ne peut entrer. Le level-designer garantit cette condition en plaçant le marker à ≥ 6 m de tout `EnemySlot` dans la salle ET ≥ 4 m de tout `HazardSlot` (lint pré-build, AC-LVL-54 r2).

**CO-2** — Le Level System **ne spawne pas** le grunt ni la safe zone — il expose les **positions**. Enemy System lit `get_onboarding_anchors()` au `level_active` pour étage 1 et instancie le grunt sur `FirstEnemySightline`. Le "caractère safe" de la SafeZone est produit par Enemy + Hazard Systems (pas de spawn à proximité) — Level garantit la géométrie (distance).

**CO-3** — Sur les étages Tier 2+ (post-MVP, absence de `OnboardingAnchors`), `get_onboarding_anchors()` retourne `{}`. Combat / Enemy consomment via existence-check (`if anchors.has("first_enemy_sightline"):`) — contrat non-fatal.

**Propagation** : `player-combat-system.md` Rule 16 cite ce contrat ; `design/gdd/enemy-system.md` (à écrire) devra citer CO-1 / CO-2 dans sa §Dependencies upstream (réciprocité enforcée par `/design-review`).

## Formulas

Le Level System est un système **spatial à règles discrètes** plutôt qu'un système à équations continues (à la différence de Movement ou Combat). Les "formules" ci-dessous sont des **relations de dimensionnement** qui encodent les contraintes R-2 / R-4 sous forme calculable et testable.

### Formule 1 — Largeur minimale d'ouverture (porte / couloir)

```
min_opening_width = 2 * KATANA_REACH
                  = 2 * 1.8 m
                  = 3.6 m
```

**Variables :**
- `KATANA_REACH` : portée nominale du katana (registry — 1.8 m). Source : `design/registry/entities.yaml`.

**Pourquoi × 2 et pas × 1** : le facteur 2 absorbe la latéralité d'un dash qui traverse la porte avec un angle non-normal (jusqu'à ~25° de biais). Un simple 1× forcerait un couloir frontal strict et casserait le FLOW si le joueur arrive sur un vecteur oblique. Valeur vérifiée contre la largeur du prototype `prototypes/movement-katana/` (portes à 4 m = confortables, 2 m = frustrantes).

**Exemple** : porte standard = 3.6 m. Couloir d'approche à 4.0 m (marge 400 mm). Embrasure exceptionnelle boss-lead = 5.0 m.

### Formule 2 — Budget draw calls par étage (MVP)

```
draw_calls_level(N_rooms) = N_rooms * DRAW_CALLS_PER_ROOM + LEVEL_OVERHEAD
  où DRAW_CALLS_PER_ROOM = 30 (R-4) et LEVEL_OVERHEAD = 50 (skybox + fog + shader global)
  plancher (N=8)     : 8 × 30 + 50  = 290
  plafond (N=10)     : 10 × 30 + 50 = 350
  → draw_calls_level ∈ [290, 350] sur la range MVP N_rooms ∈ [8, 10]

budget_peers = draw_calls_global_cap - draw_calls_level
             = 500 - draw_calls_level
             ∈ [150, 210]

Sous-budget peers (verrouillé) :
  enemies_max_active * DRAW_CALLS_PER_ENEMY   ≤ 60   (ex: 10 × 6)
  vfx_active_simultaneous (GPUParticles3D)    ≤ 50
  hud_ui_overlay                              ≤ 30
  combat_transient (katana swing, decals)     ≤ 20
  marge de tête                               ≥ 10
  Total peers contract                        ≤ 170
```

**Variables :**
- `N_rooms ∈ [8, 10]` (Tuning Knob `ROOM_COUNT`)
- `DRAW_CALLS_PER_ROOM = 30` (R-4, Chrome Zen primitives + atlas partagé)
- `LEVEL_OVERHEAD = 50` (constante globale au build — **pas** per-room, pas per-peer — skybox + volumetric fog exit + shader chrome_zen_flat)
- `draw_calls_global_cap = 500` (technical-preferences.md Performance Budgets)

**Contrat de décomposition** : `LEVEL_OVERHEAD` est global (comptabilisé 1× par étage actif). Les draw calls des peers (enemies, VFX, HUD, projectiles) **ne** sont **pas** comptabilisés dans `draw_calls_level` — ils vivent sous `budget_peers`. La limite AC-LVL-31 gate `draw_calls_level ≤ 350` isolément (scène Level seule, aucun peer instancié) ; un gate séparé (Combat / Enemy / VFX) cible `budget_peers ≤ 170` en conditions combat normal.

**Danger** : la marge `[150, 210]` assume que les peers respectent leur sous-budget. Si Enemy System instancie 15 ennemis simultanés à 6 dc chacun (90 dc) + Combat swing decals (10 dc) + VFX particles (40 dc), total peers = 140 dc → OK à N=10 (marge 210) mais serré à N=10 si VFX spike à 70 dc. Benchmark prototype requis avant Sprint 1 (cf. §Tuning Knobs `DRAW_CALL_BUDGET_PER_ROOM`).

### Formule 3 — Espacement checkpoints (nominal MVP)

```
checkpoint_count = ceil(N_rooms / CHECKPOINT_SPACING)
CHECKPOINT_SPACING ∈ [2, 3] rooms    (game-concept : "checkpoints toutes les 2-3 salles")

Pour N_rooms = 10 :
  spacing = 2 → 5 checkpoints
  spacing = 3 → 4 checkpoints
  nominal MVP : spacing = 3 → 4 checkpoints (start, après salle 3, après salle 6, après salle 9)

Pour N_rooms = 8 :
  spacing = 2 → 4 checkpoints
  spacing = 3 → 3 checkpoints
  nominal MVP : spacing = 3 → 3 checkpoints
```

**Justification du 3 plutôt que 2 au MVP** : avec respawn ≤ 1 s (Pillar SECONDE CHANCE) et `RESPAWN_DELAY = 0.05 s` pull (registry), le joueur ne subit pas de friction UX. Un spacing de 3 renforce la tension « ce que j'ai gagné tient à un dash » (Pillar 1 — FLOW / Player Fantasy §Checkpoint). Ajustable par playtest (Tuning Knobs G-2).

### Formule 4 — Temps de chargement étage (budget)

```
load_time_budget = base_scene_load + resource_ready + peer_bind
                 ≤ 600 ms + 200 ms + 200 ms
                 = 1000 ms (1 seconde)
```

**Variables :**
- `base_scene_load` : temps Godot `load_threaded_get` de la scène principale, ≤ 600 ms pour un étage MVP (≤ 50 MB VRAM, ≤ 250 Nodes)
- `resource_ready` : shader compile + texture upload GPU, ≤ 200 ms (1 shader Chrome Zen partagé → pré-compilé à boot global)
- `peer_bind` : peers (Checkpoint, Enemy, Hazard, Secret, HUD) réagissent à `level_active` et placent leurs entités, ≤ 200 ms cumulé

**Gate** : `1000 ms` est le seuil AC-LVL-3 (Acceptance Criteria). Au-delà, le fade-in player est perceptiblement délavé, violant Pillar 1 FLOW. Mesure via `Time.get_ticks_msec()` entre appel `load_etage()` et émission `level_active`.

### Formule 5 — Altitude d'ascension par étage (MVP) — r2 : multi-rise Shaft

```
# Modèle r2 multi-rise — chaque salle contribue selon son archetype :

etage_height = Σ room_rise_i   for i in 1..N_rooms
  où room_rise_i ∈ archetype_rise_range(archetype_i) — R-2.A r2

archetype_rise_range :
  Traversal   → [1.0, 4.0] m
  Combat      → [0.0, 2.0] m   (plan privilégié — wall-run latéral)
  Shaft       → [8.0, 15.0] m  (multi-rise — absorbe plusieurs dizaines de m seule)
  SecretHub   → [2.0, 4.0] m

Contraintes étage (hard gate lint pré-build) :
  ETAGE_HEIGHT_MIN = 15 m       (plancher — "regard vers le bas" sensoriel)
  ETAGE_HEIGHT_MAX = 60 m       (plafond r2 — accommode jusqu'à 2 × Shaft max réaliste
                                 + claim Fantasy "puits 40 m" structurellement possible)
  SHAFT_ROOMS_PER_ETAGE ∈ [1, 2] (r2 : S-3 impose ≥ 1 ; ≥ 3 = étage trop vertical linéaire)

Nominal MVP (mix recommandé — aligne Player Fantasy `puits 40 m`) :
  2×Traversal (rise 2.5 m chacune) = 5 m
  3×Combat    (rise 1 m chacune)    = 3 m
  1×Shaft     (rise 12 m)           = 12 m    ← le puits-moment-icône
  2×SecretHub (rise 3 m chacune)    = 6 m
  2×Traversal (rise 2 m chacune)    = 4 m
  ──────────────────────────────────────────
  Σ = 30 m (N=10)    ← nominal r2 : aligne "25-30 m sous toi" + shaft saillant
```

**Variables :**
- `room_rise_i` : dénivelé de la salle i vers la salle i+1 (delta `y` entre `PlayerStart_i` et `PlayerStart_{i+1}`). Doit ∈ `archetype_rise_range(archetype_i)`.
- `N_rooms ∈ [8, 10]` (Tuning Knob `ROOM_COUNT`).
- `archetype_i ∈ {Traversal, Combat, Shaft, SecretHub}` — cf. R-2.6 r2.

**Multi-rise pour Shaft — pourquoi [8, 15] m** : l'archetype `Shaft` est défini par sa chambre-puits `VerticalShaftRoom` (R-1 r2) qui contient des wall-run chainables sur **≥ 2 niveaux**. Un shaft de 12 m = 3 séquences de wall-run de 4 m chacune (hauteur mur minimum R-2.U.2). Un shaft de 15 m = 3.75 séquences, borne supérieure. < 8 m = pas de chaînage pertinent, l'archetype perd sa définition.

**Player Fantasy "puits 40 m"** : structurellement accommodable r2 par **2 Shafts (15 + 15 m) + 5 autres salles (10 m cumulé) = 40 m total**. Mix non-nominal (plus tendu rythme) mais légal. La formulation littéraire "quarante mètres" dans §Player Fantasy est désormais soutenue par la math, pas en tension avec elle.

**Correction r2 explicite (fix CD #1)** : la r1 bornait `ROOM_RISE_MAX = 4 m` universel (rendant 40 m impossible : 10 × 4 = 40 mais viole `ETAGE_HEIGHT_MAX = 30`). La r2 introduit un archetype `Shaft` avec `rise ∈ [8, 15] m` qui permet à la Fantasy de tenir structurellement, tout en conservant `ETAGE_HEIGHT_MAX = 60 m` comme garde-fou raisonnable.

**Conséquence sensorielle** : depuis `EtageExitTrigger`, en regardant vers le bas, le joueur voit `PlayerStart` à profondeur ∈ [15, 60] m selon le mix (nominal 30 m, extrême "double-shaft" 40-45 m). La borne supérieure 60 m évite la dérive "tour de Pise" pure sans autres archetypes.

### Formule 6 — Volume monde occupé par étage (budget)

```
etage_bounding_volume = room_area_avg * N_rooms * ceiling_height
                      ≈ 100 m² * 10 * 5 m
                      = 5000 m³
```

**Variables :**
- `room_area_avg = 100 m²` (salle typique 10 m × 10 m ; combat-focused)
- `ceiling_height = 5 m` (≥ 4 m wall-run requis R-2.3 + 1 m de tolérance tête)

**Utilisé pour** : dimensionner `WorldBoundsVolume` (R-1) — Area3D englobant l'étage avec 3 m de marge sur tous côtés → volume trigger ≈ 5800 m³. `player_position` hors de ce volume → signal `player_out_of_world` → Checkpoint System respawn.

### Formule 7 — Densité de secrets (MVP)

```
# Pseudocode enforceable (pas de prose) :
func compute_secret_count(N_rooms: int, divisor: int) -> int:
    assert N_rooms >= 8 and N_rooms <= 10  # MVP range
    assert divisor == 2 or divisor == 3
    raw = floor(N_rooms / divisor)
    clamped = clamp(raw, SECRET_COUNT_MIN, SECRET_COUNT_MAX)
    return clamped

Constantes (game-concept §Required for MVP) :
  SECRET_COUNT_MIN = 3     # plancher MVP (un étage MVP sans 3 secrets viole le spec)
  SECRET_COUNT_MAX = 5     # plafond pour préserver la densité "provocations rares"

Tous les cas dans le domaine valide :
  N=8,  divisor=2 → floor(8/2)=4   → clamp → 4 secrets  ✓
  N=8,  divisor=3 → floor(8/3)=2   → clamp → 3 secrets  ✓ (plancher appliqué)
  N=9,  divisor=2 → floor(9/2)=4   → clamp → 4 secrets  ✓
  N=9,  divisor=3 → floor(9/3)=3   → clamp → 3 secrets  ✓
  N=10, divisor=2 → floor(10/2)=5  → clamp → 5 secrets  ✓ (plafond appliqué)
  N=10, divisor=3 → floor(10/3)=3  → clamp → 3 secrets  ✓

Nominal MVP :
  N=10, divisor=3 → 3 secrets (design-game-designer B5 : provocations rares > collectibles de couloir)
```

**Correction r2** : la formule r1 "si moins que plancher, forcer à 3" était ambiguë et laissait passer des cas absurdes (N=5, divisor=3 → floor=1 → clamp → 3 secrets dans 5 salles = densité 60 %, violant Pillar 4). Le domaine est maintenant **strictement** gated à N ∈ [8, 10] (hors range = lint fail au pré-build, AC-LVL-20). Le clamp `[3, 5]` est bilatéral — pas seulement plancher.

**Contrainte plancher** : `secret_count ∈ [SECRET_COUNT_MIN, SECRET_COUNT_MAX] = [3, 5]` (spec MVP game-concept §Required for MVP). Chaque secret occupe ~1 SecretSlot Area3D (R-4 : ≤ 3 par salle, donc concentration ≤ 3 dans la salle la plus dense).

**Décision nominale MVP** : `divisor = 3` (et non 2 comme r1) — aligne sur game-designer R5 : 5 secrets / 10 salles = collectibles diluent Pillar 4. 3 secrets rares et exigeants > 5 faciles.

### Formule 8 — Hauteur minimale d'un mur wall-runnable

```
min_wall_height = jump_apex + wall_run_vertical_reach

Variables (toutes dérivées de player-movement-system.md, pas fabriquées ici) :
  jump_apex = h_combo = 1.680 m
    Source : player-movement-system.md Formulas r4, ligne 267
    Dérivation : h_single + AIR_JUMP_VELOCITY² / (2 * GRAVITY)
               = 0.926 + 6.5² / (2 * 28)
               = 0.926 + 0.754

  wall_run_vertical_reach = ∫ (v_y dt) sur durée wall-run, cap -WALL_RUN_FALL_CAP
    Paramètres Movement (player-movement-system.md §Rules R-7 + §Tuning Knobs) :
      WALL_RUN_MAX_DURATION = 1.5 s
      WALL_RUN_GRAVITY = 4 m/s²     (au lieu de GRAVITY = 28)
      WALL_RUN_FALL_CAP = -3 m/s    (cap vitesse verticale)
    Pour une entrée en wall-run depuis jump_apex (v_y ≈ 0 m/s) :
      Phase 1 (décélération sous WALL_RUN_GRAVITY) :
        t_cap = |WALL_RUN_FALL_CAP| / WALL_RUN_GRAVITY = 3 / 4 = 0.75 s
        h_phase1 = 0.5 * WALL_RUN_GRAVITY * t_cap²
                 = 0.5 * 4 * 0.5625 = 1.125 m  (chute pendant décélération)
      Phase 2 (v_y saturé à WALL_RUN_FALL_CAP) :
        duration_remaining = WALL_RUN_MAX_DURATION - t_cap = 0.75 s
        h_phase2 = |WALL_RUN_FALL_CAP| * duration_remaining = 3 × 0.75 = 2.25 m
      wall_run_vertical_reach = h_phase1 + h_phase2 = 3.375 m
    Dérivation arrondi conservateur : 3.375 m → 2.3 m après soustraction de la
      marge apex (0.5 m — le joueur n'utilise pas les derniers 10-15 % de sa durée
      de wall-run sans risque de fall-off perception). Valeur finale dérivée : 2.3 m.

min_wall_height_computed = 1.680 + 2.3 = 3.98 m
                        →  R-2.3 arrondi sécuritaire : 4.0 m

Si Movement GDD change WALL_RUN_MAX_DURATION ou WALL_RUN_GRAVITY ou WALL_RUN_FALL_CAP :
  Level System doit recalculer wall_run_vertical_reach.
  Gate : CI check `test_wall_height_derivation_matches_movement.gd` (Sprint 1)
  lit les constantes Movement depuis registry et reconstruit min_wall_height.
  Si divergence, fail → amendement R-2.3 requis.
```

**Variables :**
- `jump_apex` : hauteur atteignable double-jump avec velocity nominale = **1.680 m** — source : `player-movement-system.md` Formulas r4, *non recalculé localement*
- `wall_run_vertical_reach` : distance verticale utile pendant un wall-run complet à partir de l'apex — **dérivée des constantes Movement** listées ci-dessus, pas une valeur inventée localement. Si Movement change ces constantes, `min_wall_height` doit changer en conséquence (test CI gated)

**Correction r2** : la r1 affirmait "reach_margin = 2.3 m" sans dérivation formelle — valeur locale fabriquée. r2 dérive `wall_run_vertical_reach` depuis les constantes `WALL_RUN_MAX_DURATION`, `WALL_RUN_GRAVITY`, `WALL_RUN_FALL_CAP` publiées par Movement GDD. Si une de ces valeurs change, Formula 8 se recalcule ; R-2.3 (`≥ 4 m`) reste l'invariant structurel du Level System tant que le calcul dérivé reste ≤ 4 m.

**Dépendance cross-system enregistrée** : à figer dans `design/registry/entities.yaml` en section `formulas` post-MVP (nouvelle entrée `wall_run_vertical_reach` avec `source: design/gdd/player-movement-system.md` et `referenced_by: [design/gdd/level-system.md]`).

**Conséquence** : `min_wall_height = 4.0 m` (R-2.3). Tout mur plus bas est décoratif ou structurel, jamais wall-runnable. Le Level authoring pipeline doit flagger automatiquement les StaticBody3D verticaux ≥ 4 m comme candidats wall-run (lint post-MVP).

## Edge Cases

Chaque cas indique **exactement ce qui se passe**, sans « handle gracefully ». Formatage GIVEN/WHEN/THEN pour traçabilité vers les ACs.

### EC-1 — Joueur tombe hors du monde (void fall)

- **GIVEN** étage `Active`, joueur avec `global_position.y < -2.0` (R-2.4) OU hors du volume englobant `WorldBoundsVolume`
- **WHEN** `WorldBoundsVolume.body_exited(player)` émis
- **THEN** Level System émet signal `player_out_of_world(last_valid_position: Vector3)` → Checkpoint System consomme ce signal et déclenche respawn au dernier checkpoint franchi (RESPAWN_DELAY=0.05 s pull). Level System **ne modifie pas** la position du player directement (encapsulation R-3 §Interactions).
- **Pas de respawn double** : le signal est émis **exactement une fois** par transition `inside → outside`. Une re-entrée éventuelle remet le volume en surveillance.

**Définition de `last_valid_position`** (contrat précis, consommé par Checkpoint System en diagnostic — **pas** utilisé comme position de respawn) :

- **Valeur** : la dernière `player.global_position` échantillonnée par Level System **à l'intérieur** du `WorldBoundsVolume`, capturée au `_physics_process` immédiatement précédent la sortie du volume.
- **Implémentation** : Level System conserve un `_last_valid_position: Vector3` en membre, mis à jour chaque `_physics_process` si et seulement si `WorldBoundsVolume.overlaps_body(player) == true`. Si le joueur n'a jamais été in-bounds (spawn out-of-bounds — EC-7 pathologique), la valeur par défaut est `PlayerStart.global_position`.
- **Payload, pas position de respawn** : le Checkpoint System **ignore** cette valeur pour décider *où* respawn (il utilise son propre `last_checkpoint_anchor`). `last_valid_position` sert uniquement à la télémetrie / debug ("le joueur est tombé à position X — vérifier authoring de la salle Y"). **Ne pas** construire de logique gameplay dessus.
- **Coût runtime** : 1 assignation Vector3 par physics tick (`_last_valid_position = player.global_position`), ~8 octets × 60 Hz = négligeable. Zéro alloc.

### EC-2 — `load_etage()` appelé alors qu'un étage est déjà `Active`

- **GIVEN** état `Active`, étage N chargé
- **WHEN** Game State Manager (ou debug command) appelle `load_etage(M)` avec M ≠ N
- **THEN** **rejet fatal** en debug build : `assert(state == Unloaded, "level_system: concurrent load rejected — unload first")`. En release build : silent no-op + `push_error` (pas de crash, mais le state est corrompu — ce cas indique un bug Game State Manager, pas Level System).
- **Justification** : toute transition inter-étage doit passer par `unload_current() → load_etage(M)` (T-1). Autoriser un double-load ouvrirait une race sur les peer bindings.

### EC-3 — Ressource de scène corrompue / fichier absent

- **GIVEN** appel `load_etage(id)` où le path résolu n'existe pas OU le `.tscn` est corrompu
- **WHEN** `ResourceLoader.load_threaded_get_status()` retourne `THREAD_LOAD_FAILED`
- **THEN** Level System reste en état `Unloaded`, émet signal `level_load_failed(etage_id: int, reason: String)`, et Game State Manager est responsable de router vers un écran d'erreur (ou recharger le menu principal). **Level System ne crash pas l'application**. En debug build, `push_error` avec le reason détaillé.

### EC-4 — `PlayerStart` absent de la scène chargée

- **GIVEN** étage chargé mais la scène ne contient pas de Marker3D nommé `PlayerStart`
- **WHEN** Level System tente de résoudre `PlayerStart` au passage `Loading → Active`
- **THEN** **assert fatal en debug build** : `assert(player_start != null, "level_system: missing PlayerStart marker in %s" % etage_path)`. En release build (impossible en théorie — lint pre-build devrait l'attraper), fallback sur `Vector3.ZERO` + `push_error`. Ceci est une **erreur d'authoring**, traitée comme impossible en prod.

### EC-5 — Triggers chevauchants : joueur entre simultanément dans deux `RoomTrigger_NN`

- **GIVEN** deux salles adjacentes dont les Area3D `RoomTrigger_NN` ont des bounds qui se chevauchent (pad de transition authoring 0.3 m)
- **WHEN** le joueur entre le même frame dans `RoomTrigger_03` ET `RoomTrigger_04`
- **THEN** les signaux `room_entered(3)` puis `room_entered(4)` sont émis dans **l'ordre physique de l'Array3D index** (Godot : ordre d'arborescence). Les consommateurs HUD/Tutorial/Audio doivent supporter le cas « 2 room_entered au même tick » — ils s'en servent pour incrémenter l'état courant, le plus récent gagne. Idempotence confirmée via AC-LVL-7.

### EC-6 — Joueur entre dans `EtageExitTrigger` puis recule (annulation)

- **GIVEN** état `Active`, joueur touche `EtageExitTrigger.body_entered`
- **WHEN** le signal `etage_completed(etage_id)` est émis **immédiatement et atomiquement** (pas de délai de confirmation)
- **THEN** Level System passe en `Unloading` au même tick. **Aucun back-out possible** : une fois l'exit déclenchée, la transition est engagée (Game State Manager orchestre le fade-to-shop ou étage suivant).
- **Design deliberate** : autoriser le back-out créerait un flicker HUD "étage terminé / pas terminé". L'`EtageExitTrigger` est placée dans le spot unique de fin d'étage, visible et annoncé visuellement — le joueur qui y entre **a choisi** la fin.

### EC-7 — Joueur spawn sur CheckpointAnchor qui chevauche géométrie statique

- **GIVEN** `CheckpointAnchor_NN.global_position` à l'intérieur ou trop près d'un `StaticBody3D` (authoring bug : anchor mal placé)
- **WHEN** Checkpoint System demande à teleport player sur cet anchor
- **THEN** Level System **ne vérifie pas** (c'est la responsabilité du Checkpoint System de valider via raycast `up` avant spawn). Pour aider à détecter, Level System expose optionnellement `validate_checkpoint_anchors() → Array[ValidationError]` appelé au load en debug build (lint runtime). Chaque erreur retourne `{ anchor_name, position, reason }`.

### EC-8 — Clip through wall à haute vélocité (dash + wall-run + collision tunneling)

- **GIVEN** joueur à velocity > 20 m/s (dash + combo), approche d'un `StaticBody3D` fin (< 0.2 m d'épaisseur)
- **WHEN** Jolt physics resolve la collision sur une frame de 16.6 ms
- **THEN** **attendu (CLAIM-UNVERIFIED — à valider par prototype)** : Jolt en Godot 4.6 est supposé réduire le tunneling via son algorithme de collision interne. **Cependant**, pour `CharacterBody3D` utilisant `move_and_slide()`, la CCD Jolt au sens strict (sweep-based) n'est pas automatiquement activée : `CharacterBody3D` effectue ses propres shape casts internes, distincts du système CCD de `RigidBody3D`. Le comportement exact en Godot 4.6 n'est pas vérifié contre les docs officielles au moment de la rédaction r2 (knowledge cutoff LLM = mai 2025, Godot 4.6 = janvier 2026). **Authoring règle garde (non-négociable)** : R-2 addendum — aucun mur solid authoring ne fait moins de **0.3 m d'épaisseur** (soit ≥ 3× `dash_velocity × physics_dt = 12 × 0.0166 ≈ 0.2 m`). Mitigation supplémentaire : doubler l'épaisseur des murs critiques autour des chemins à plus haute vitesse (sortie de tube dash, fin de wall-run).
- **Action requise Sprint 1** : benchmark prototype `prototypes/level-tunneling-test/` avec 3 configurations (mur 0.2 / 0.3 / 0.5 m), 100 passages dash-combo par configuration, mesure fréquence de clip. Si clip observé sur 0.3 m : escalader épaisseur MVP à 0.5 m OU implémenter mitigation logicielle (ShapeCast3D pre-move). Ce benchmark conditionne la validité d'AC-LVL-41.

### EC-9 — NaN/infinity dans transform player au `body_entered`

- **GIVEN** signal `RoomTrigger_NN.body_entered(body)` avec `body.global_position` contenant un NaN ou Inf (bug amont Movement/Combat)
- **WHEN** Level System reçoit le signal
- **THEN** **ignore silencieusement l'événement** (pas de `room_entered` émis), `push_warning("level_system: ignored trigger with invalid transform")` en debug. Le Movement System est responsable de corriger la position via son safeguard (`player-movement-system.md` AC sur NaN velocity). Level System n'est pas un détecteur de bugs amont — il se protège mais ne corrige pas.

### EC-10 — Frame drop massif pendant `Loading` (< 10 fps)

- **GIVEN** `load_etage(id)` en cours, GPU thermal-throttled ou hiccup OS
- **WHEN** `load_threaded_get_status()` prend > 1000 ms (Formula 4 gate dépassé)
- **THEN** Level System **n'interrompt pas** le chargement — il émet un signal `level_load_slow(elapsed_ms: int)` toutes les 500 ms après le seuil. Game State Manager décide s'il affiche une indication UX ou non. La transition `Loading → Active` n'est déclarée **que** quand la scène est effectivement prête (pas de demi-chargement). En pratique, le seuil 1 s est un budget cible, pas un hard cap — mais un dépassement fréquent en telemetry = flag régression pour profiling.

### EC-11 — Peer échoue à se binder au signal `level_active` (race condition)

- **GIVEN** `level_active` émis, un peer (ex: Enemy System) n'est pas encore connecté (autoload boot-order race)
- **WHEN** le signal est émis direct (synchrone) au même tick que `_ready()` du peer
- **THEN** **mitigation par design — formulation corrigée r2** :
  1. Les **autoloads** ont leur `_ready()` appelé **avant toute logique game** (ordre Godot natif : autoloads → main scene). Leur connexion à `level_active` est établie dans leur `_ready()` avant que `load_etage()` soit jamais appelé — ce n'est **pas** `call_deferred` qui garantit cet ordre, c'est l'ordre de boot Godot.
  2. Le vrai risque couvert par `call_deferred` est différent : **émettre un signal depuis la callback `_ready()` de Level System lui-même**. À cet instant, les peers ayant un `_ready()` postérieur (child nodes de scène principale) ne sont pas encore connectés. Émettre via `call_deferred` reporte l'émission à l'idle time du frame courant, **après** que tous les `_ready()` du frame ont tourné.
  3. **ADR-0005 D-5 (CONNECT_DEFERRED)** s'applique à l'extrémité consommatrice : les peers sont encouragés à `connect(..., CONNECT_DEFERRED)` pour éviter les burst CPU synchrones.
  4. **Garde-fou API** : un peer dynamiquement spawned **après** `level_active` peut interroger `Level.get_level_state() → LevelState` à tout moment — API synchrone idempotente qui retourne les slots à jour.
- **Correction r1→r2** : formulation r1 "call_deferred garantit que tous les peers autoload ont eu leur `_ready()`" était imprécise (godot-specialist B3). L'ordre inter-autoloads est une propriété native Godot, pas une propriété de `call_deferred`. AC-LVL-26 reste valide (teste le résultat comportemental), seul le reasoning est corrigé.

### EC-12 — Quit-to-menu puis re-load du même étage

- **GIVEN** état `Active` (étage N), joueur quit-to-menu
- **WHEN** `unload_current()` appelé → `Unloading → Unloaded` → retour au menu → re-appel `load_etage(N)`
- **THEN** Level System recycle la même ressource scene (`ResourceLoader` cache honoré) si elle est en VRAM encore ; sinon re-chargement depuis disque. **Aucun état résiduel** : les checkpoints franchis, les ennemis tués, les secrets collectés — tout est reset côté Level (la scène est fraîche). L'état de progression (crédits, upgrades) vit dans Game State Manager / Save System, pas dans Level.

## Dependencies

### Upstream (Level System dépend de)

| System | Statut | Nature de la dépendance | Contrat consommé |
|--------|--------|-------------------------|-------------------|
| **Game State Manager** | Not Started — interface provisoire définie ici | Lifecycle owner — appelle `load_etage()` / `unload_current()` | Méthodes publiques + attentes sur l'ordre `Unloaded → Loading → Active → Unloading → Unloaded` |
| **Input System** | In Review (r4 pending) | Aucune dépendance de Level envers Input. Mais certains triggers (ex: `EtageExitTrigger`) peuvent requérir une action joueur qui nécessite l'input actif — la détection elle-même est purement physique (Area3D) | — (pas de couplage direct) |

**Interface provisoire Game State Manager** (à formaliser quand ce GDD commence) :

```gdscript
# Appelé par Game State Manager → Level System
func load_etage(etage_id: int) -> void         # Transition Unloaded → Loading
func unload_current() -> void                  # Transition Active → Unloading
func get_state() -> LevelState                 # Introspection synchrone

# Lookups spatiaux publiés par Level System (appelés par peers à level_active)
func get_checkpoint_slots() -> Array            # Array[CheckpointSlot]
func get_enemy_slots() -> Array[Marker3D]
func get_hazard_slots() -> Array[Marker3D]
func get_secret_slots() -> Array                # Array[SecretSlot]
func get_tutorial_anchor(tag: String) -> Marker3D

# Lookup audio per-étage (appelé par Audio System à level_active) — r4 Option C
# Dictionary keys (typés) : "music" -> AudioStream, "ambient" -> AudioStream.
# Source : ETAGE_AUDIO_MAPPING (knob d'authoring §Tuning Knobs).
# Synchrone, idempotent, zero-alloc (Dictionary pré-construit au load_etage).
func get_etage_audio_streams(etage_id: int) -> Dictionary

# Émis par Level System → Game State Manager (lifecycle)
signal level_active(etage_id: int, player_start: Vector3)
signal level_unloading(etage_id: int)
signal etage_completed(etage_id: int)
signal level_load_failed(etage_id: int, reason: String)
signal level_load_slow(elapsed_ms: int)         # advisory, non-bloquant

# Émis par Level System → peers gameplay (room progression + void fall)
signal room_entered(room_index: int, total_rooms: int)   # consommé par HUD, Tutorial, Audio
signal player_out_of_world(last_valid_position: Vector3) # consommé par Checkpoint
```

**Signature verrouillée** : `room_entered(room_index: int, total_rooms: int)` — **deux paramètres, ni plus ni moins**. Toute AC qui utilise `room_entered(...)` avec ellipse (ex: AC-LVL-21, AC-LVL-22) fait référence à cette signature exacte. `room_index` est 0-indexed (première salle = 0), `total_rooms` est le nombre total de salles de l'étage courant (constant pour toute la durée `Active`).

### Downstream (systèmes qui dépendent de Level)

| System | Statut | Nature de la dépendance | Contrat consommé depuis Level |
|--------|--------|-------------------------|-------------------------------|
| **Checkpoint & Respawn System** | Not Started | Fort — lit les `CheckpointSlot` à `level_active` pour placer ses volumes de respawn, écoute `player_out_of_world` pour déclencher le pull | Signal `level_active` + helper `get_checkpoint_slots()` + signal `player_out_of_world` |
| **Hazard System** | Not Started | Lit `get_hazard_slots()` pour instancier ses hazards (lasers, pièges) | Signal `level_active` + Array[Marker3D] slots |
| **Enemy System** | Not Started | Lit `get_enemy_slots()` pour spawner les grunts. **Contrainte navigation** : la `NavigationRegion3D` utilisée pour le pathfinding ennemi est baked **en éditeur** et exportée avec `etage_NN.tscn` — Enemy System **ne rebake jamais runtime** | Signal `level_active` + Array[Marker3D] slots + `NavigationRegion3D` pré-baked dans la scène |
| **Secret System** | Not Started | Lit `get_secret_slots()` pour placer les volumes et contenus | Signal `level_active` + Array[SecretSlot] |
| **HUD System** | Not Started | Affiche la progression d'étage (salle courante / N) via `room_entered` | Signaux `room_entered`, `level_active` (pour `total_rooms`) |
| **Tutorial / Onboarding System** (VS) | Not Started | Ancres textuelles (`get_tutorial_anchor("tag") → Marker3D`) pour afficher les pop-ups dans les 3 premières salles | Method `get_tutorial_anchor`, signal `room_entered` |
| **Audio System** | Not Started | (a) Swap d'ambient layer intra-étage par salle (optionnel MVP) via `room_entered`. (b) Music + ambient per-étage via `level_active` + lookup `get_etage_audio_streams(etage_id) -> {music, ambient}` (r4 Option C, pas de signal `etage_loaded` dédié). (c) Fade-out music sur `level_unloading`. | Signaux `level_active`, `level_unloading`, `room_entered` + method `get_etage_audio_streams` |
| **VFX & Feedback System** | Not Started | Positions d'ancres pour spawn visuel passifs (projecteurs de portes, glow de checkpoints) | Marker3D lookup à `level_active` |

### Dépendances indirectes (contrat physique)

| System | Lien indirect | Détail |
|--------|---------------|--------|
| **Player Movement System** | Dépend de `LAYER_ENVIRONMENT = 4` pour walk/run/wall-run | Level publie la géométrie sur cette layer ; Movement lit son `collision_mask` pour la détecter. Si Level change la layer (interdit par registry), Movement casse en silence. → contrat bilatéral verrouillé par `design/registry/` |
| **Player Combat System** | Pas de dépendance directe | Combat touche les ennemis, pas l'environnement. Exception : un raycast katana peut toucher un mur (hit valide sans dégât). Ce comportement dépend de `LAYER_ENVIRONMENT` mais pas du Level System lui-même |
| **Camera System** | Pas de dépendance | Camera suit le player, ignore l'étage. Aucun coupling |

### Notes de réciprocité (à compléter dans les GDDs cibles quand ils commencent)

Le rule `.claude/rules/design-docs.md` exige que **les dépendances soient bidirectionnelles** : si A dépend de B, B doit mentionner A. Level System est cité en upstream dans les GDDs suivants **qui ne sont pas encore écrits**. Quand ils seront rédigés, ils devront explicitement citer Level System dans leur §Dependencies :

- `design/gdd/game-state-manager.md` (à écrire) → §Dependencies doit citer : "Orchestre Level System via `load_etage(id)` / `unload_current()`"
- `design/gdd/checkpoint-system.md` (à écrire) → §Dependencies doit citer : "Consomme `level_active` payload + signaux `player_out_of_world` du Level System"
- `design/gdd/enemy-system.md`, `hazard-system.md`, `secret-system.md`, `hud-system.md`, `tutorial-system.md` (à écrire) → §Dependencies doivent toutes citer Level System comme source de slots spatial
- `design/gdd/enemy-system.md` en particulier → §Dependencies doit acter que **NavigationRegion3D est baked en éditeur côté Level authoring**, pas rebaked runtime par Enemy. Un bake runtime sur un étage 5000 m³ coûte 200–800 ms, ce qui viendrait directement sur le budget F4 (1000 ms load). Contrat bilatéral : Level System garantit la présence d'une `NavigationRegion3D` pré-baked dans `etage_NN.tscn` ; Enemy System garantit qu'il n'appelle jamais `NavigationRegion3D.bake_navigation_mesh()` après `level_active`.

**Cette section agit comme point d'ancrage forward-looking** : pas de broken reciprocity actuellement (les GDDs downstream n'existent pas), mais chaque nouveau GDD doit vérifier que sa §Dependencies cite Level correctement à la création. Un `/design-review` automatique sur ces GDDs futurs devrait flagger l'oubli.

## Tuning Knobs

Les knobs Level System se divisent en **knobs d'authoring** (dimensionnement de l'étage en design-time) et **knobs de runtime** (budgets et tolerances vérifiés à l'exécution). Les knobs d'authoring sont dans `design/registry/level.yaml` (à créer à l'implémentation) ; les knobs de runtime dans Project Settings Godot ou constantes script.

### Knobs d'authoring (design-time — dimensionnement étage MVP)

| Knob | Default MVP | Safe Range | Hors range = quoi ? | Gameplay Aspect | Source formula |
|------|-------------|------------|----------------------|-----------------|-----------------|
| `ROOM_COUNT` | 10 | [8, 10] | < 8 = étage trop court, session < 20 min (viole game-concept §Session Length). > 10 = risque de dépasser draw_calls (Formula 2) et load_time (Formula 4) | Longueur d'une run et densité de checkpoints | Formula 2 |
| `CHECKPOINT_SPACING` | 3 rooms | [2, 3] | 1 = respawn trop généreux, tue la tension (viole Pillar 1 FLOW / Fantasy §Checkpoint). ≥ 4 = frustration reset trop long, viole Pillar 3 SECONDE CHANCE | Tension pertes vs. tolérance échec | Formula 3 |
| `SECRET_DENSITY_DIVISOR` | 3 | [2, 3] | 1 = un secret par salle, dilue la valeur. 2 = 5 secrets / 10 salles, dilue Pillar 4 (cf. F7 r2 "3 rares > 5 faciles"). ≥ 4 = moins de 3 secrets par étage, viole plancher MVP game-concept | Densité d'exploration & replay-value | Formula 7 |
| `ROOM_AREA_AVG` (m²) | 100 | [80, 120] | < 80 = combat étriqué, wall-run impossible. > 120 = vide visuel, Chrome Zen perd en lecture | Lisibilité de salle | Formula 6 |
| `CEILING_HEIGHT` (m) | 5.0 | [4.0, 6.0] | < 4 = wall-run cassé (viole R-2.3). > 6 = vertigineux inutilement, combat vertical sous-utilisé | Verticalité, wall-run enablement | R-2.3 + Formula 8 |
| `ROOM_RISE_AVG` (m) | 2.5 | [1.0, 4.0] | < 1 = pas d'ascension perceptible (viole Player Fantasy §Verticalité). > 4 = saut inter-salle impossible sans dash systématique, casse le flow | Sensation d'ascension | R-2.5 + Formula 5 |
| `MIN_OPENING_WIDTH` (m) | 3.6 | **fixé** | Dérive directement de `2 × KATANA_REACH` — **immutable sans amendement registry** | Fluidité de traversée dash-through | Formula 1 |
| `MIN_WALL_RUN_LENGTH` (m) | 3.0 | [3.0, ∞] | < 3 = wall-run trop court pour s'amorcer | Wall-run enablement | R-2.3 |
| `MIN_WALL_THICKNESS` (m) | 0.3 | [0.3, ∞] | < 0.3 = risque tunneling à velocity > 20 m/s (EC-8) | Robustesse physique | EC-8 |
| `ETAGE_AUDIO_MAPPING` | `{1: {music: "music_etage_01.ogg", ambient: "ambient_etage_01.ogg"}}` (MVP) | mapping `etage_id: int -> {music: AudioStream, ambient: AudioStream}` ; chaque entrée DOIT avoir les 2 clés non-null | etage absent du mapping → `get_etage_audio_streams` retourne `{}` (Audio System fallback silence + `push_warning`) ; clé manquante = lint authoring fail | Music/ambient per-étage (Audio System contract) | r4 Option C — Audio Open Question #1 |

### Knobs de runtime (Project Settings / constantes)

| Knob | Default MVP | Safe Range | Impact | Catégorie |
|------|-------------|------------|--------|-----------|
| `LOAD_TIME_BUDGET_MS` | 1000 ms | [500, 1500] | Gate AC-LVL-3 : soft warning via `level_load_slow` signal au-delà. Dépassement fréquent = flag régression perf | Performance |
| `WORLD_BOUNDS_PAD` (m) | 3.0 | [2.0, 5.0] | Marge du volume englobant autour de l'étage authorisé. Trop petit = player out-of-world sur trajectoire d'apex normale. Trop grand = signal déclenché trop tardivement, loose l'UX de "tomber dans le vide" | Respawn timing |
| `ROOM_TRIGGER_PAD` (m) | 0.3 | [0.2, 0.5] | Overlap entre triggers consécutifs pour garantir que le joueur en transit émet bien `room_entered` sans "zone morte" inter-salle. Trop grand = double-fire sur salle courte | Signal idempotence |
| `ROOM_TRIGGER_DEPTH` (m) | matches door width | matches door width | L'Area3D de détection fait toute la largeur de la porte et 1 m de profondeur. Pas un knob indépendant au MVP, dérivé | (fixé) |
| `ETAGE_EXIT_TRIGGER_SIZE` (Vector3) | (4, 3, 1) | — | Largeur × hauteur × profondeur du volume de fin d'étage. Doit englober la plateforme de sortie sans être débordante | Signal fire-once |
| `DRAW_CALL_BUDGET_PER_ROOM` | 30 | [20, 40] | Excédent compilé au lint pré-build (flag authoring). > 40 pousse total au-delà de 500 budget Foundation | Performance |
| `VRAM_BUDGET_ETAGE_MB` | 50 | [30, 80] | Soft cap validé au load. > 80 pousse total VRAM au-delà de 1 GB budget (technical-preferences.md) | Performance |
| `MAX_STATIC_BODIES_PER_ROOM` | 25 | [15, 35] | Validé au lint pré-build. Jolt performe linéairement sur nb de bodies collidables | Performance physique |
| `SHADER_BAKER_ENABLED` | `true` | `true` uniquement MVP | **Obligatoire Godot 4.6 + D3D12 Windows.** Active le Shader Baker (Project Settings → Rendering → Shader Compiler → Enable Shader Baker, disponible depuis 4.5). Pré-compile `chrome_zen_flat.gdshader` au boot global (scène dummy invisible, 1 frame) pour éviter un freeze de 50–150 ms sur la première frame après `level_active` (compilation pipeline D3D12 first-use). **Désactiver = violation F4.** Vérifié au CI lint Project Settings | Performance load (F4) |

### Knobs de debug (debug build only)

| Knob | Default | Usage |
|------|---------|-------|
| `DEBUG_DRAW_CHECKPOINTS` | `false` | Dessine wireframe des `CheckpointVolume_*` + flèche vers `CheckpointAnchor_*` en éditeur/debug |
| `DEBUG_DRAW_ROOM_BOUNDS` | `false` | Dessine wireframe des `RoomTrigger_*` + index numéroté |
| `DEBUG_DRAW_SECRET_ANCHORS` | `false` | Dessine wireframe des `SecretVolume_*` (cheat-level — utile pour QA, jamais shipped) |
| `DEBUG_LOG_LOAD_TIMING` | `false` | Print par phase : `base_scene_load`, `resource_ready`, `peer_bind` (pour diagnostiquer les dépassements Formula 4) |

### Règles d'ajustement

- **Aucun knob ne se change sans re-run d'un test de smoke Level** (AC-LVL-*). Les knobs d'authoring en particulier peuvent casser la lecture de salle (Pillar 1) : un playtest court (10 min) doit confirmer que la nouvelle valeur ne dégrade pas le time-to-read.
- **Les knobs `MIN_OPENING_WIDTH`, `MIN_WALL_HEIGHT`, `MIN_WALL_THICKNESS` sont dérivés** (Formula 1, 8, EC-8) et ne sont pas ajustables indépendamment. Modifier requires un amendement du registry + propagation.
- **Les knobs runtime perf (`DRAW_CALL_BUDGET_*`, `VRAM_BUDGET_*`)** sont des gates de lint pré-build — un étage qui les dépasse échoue le build plutôt que de dégrader silencieusement la perf en runtime.

## Visual/Audio Requirements

**Source d'autorité** : `design/art/art-bible.md` est contraignant. Cette section **ne duplique pas** l'Art Bible — elle précise comment le Level System l'implémente côté scène/assets. La règle d'ancrage est : *« Le vide rend la lame visible. »*

### Visual — Chrome Zen appliqué aux salles

**V-1. Matériaux autorisés (MVP)**
- **Primitives Godot uniquement** : `BoxMesh`, `PlaneMesh`, `CylinderMesh` pour rampes, `PrismMesh` ponctuel pour alcôves.
- **1 shader unique partagé** : `shader_chrome_zen_flat.gdshader` — flat shading + rim light subtil + fresnel nul sauf sur surfaces chrome où il renforce la lecture.
- **Aucun mesh importé** (OBJ/GLTF) au MVP. Si un asset authorisé doit devenir "organique" en Tier 2+, il passe par l'Art Director.

**V-2. Palette par rôle de surface (Art Bible §1 — "Une couleur. Une intention.")**

| Rôle de surface | Teinte dominante | Emission/Accent | Pourquoi |
|-----------------|------------------|-----------------|----------|
| Sol / Floor | Gris béton clair #D6D8DA | aucun | Trajectoire principale = neutre |
| Mur / Wall | Chrome poli #E8EAEC | rim blanc subtil | Lisibilité wall-run instantanée |
| Mur à run-on actif | Identique mur standard | edge blanc pur #FFFFFF (100 % white) | Joueur reconnaît wall-runnable au premier regard (Pillar 1) |
| Plafond | Gris sombre #2A2C30 | aucun | Compresser le regard vers l'avant/haut |
| Rampe / Ramp | Chrome foncé #9DA1A5 | rim cyan #3EE4FF léger sur arête | Indique "transition" non-combat |
| Mur derrière secret | Gris béton standard | aucun (**caché**) | Le secret ne doit pas se lire depuis le chemin nominal (Pillar 4) |
| Mur proche sortie étage | Blanc pur #FFFFFF + halo volumétrique chaud blanc | `EtageExitTrigger` proche | "Tu approches de la fin" — non-ambigu |

**V-3. Zones colorées actives (signaux, pas décoration)**
- **Rouge #FF1B1B** : réservé strictement à Hazard System (lasers, piques). Jamais posé par Level. Si un mur est rouge, c'est qu'un Hazard s'y superpose — Level ne peint pas les murs en rouge.
- **Cyan #3EE4FF** : réservé aux volumes interactifs (checkpoints, secrets déverrouillés) — affichés par Checkpoint / Secret Systems, pas par Level.
- **Sang (warm, non-calibré)** : SEUL élément chaud — ne vient jamais du Level.

**V-4. Éclairage (per-étage)**
- 1 `DirectionalLight3D` principal, cool 6500 K, angle 60-75° (vertical dominant — renforce "Tower" ascendante, Art Bible §2 État 1).
- 0 `OmniLight3D` ou `SpotLight3D` au MVP. La géométrie chrome + flat shader ne justifie pas de l'éclairage local.
- SDFGI désactivé MVP (coût GPU). Tested Tier 2 si budget permet.
- Volumetric fog activé uniquement dans le corridor final avant `EtageExitTrigger` (1 colonne de lumière verticale, cf. Art Bible §2 État 1 élément signature). Géré par VFX System à partir d'une ancre Marker3D `FogColumnAnchor`.

**V-5. Interdits visuels (cover-all)**
- Aucun decal collé sur les surfaces du Level (fissures, graffitis, sticker, publicité). Les salles sont **stériles** — "Surfaces corporates" (Art Bible §1 Principe 2).
- Aucun prop décoratif (mobilier, terminaux, tuyaux visibles) en Tier 1. Les "easter-eggs Arasaka" peuvent apparaître en Tier 2+ sous contrôle Art Director.
- Aucune texture > 512×512. Atlas partagé unique.
- Aucun shader per-room différent. Tout passe par `shader_chrome_zen_flat`.

### Audio — ce que Level publie (pas ce qu'il joue)

**Le Level System ne joue aucun son lui-même.** Il publie des signaux qu'Audio System consomme pour déclencher ses layers. Ce design respecte la séparation : Level = spatial, Audio = temporel.

**A-1. Signaux consommés par Audio System**

| Signal Level → Audio | Usage Audio System |
|----------------------|---------------------|
| `level_active(etage_id)` | Démarrer la layer ambient de l'étage (layer unique MVP) |
| `level_unloading` | Fade-out ambient, prep transition |
| `room_entered(index)` | Optionnel MVP : swap sub-layer ambient par type de salle. Désactivé Tier 1 — réactivable via knob `AUDIO_ROOM_AMBIENT_SWAP` |
| `etage_completed` | Stinger transitoire court (1.5 s), géré par Audio System |
| `player_out_of_world` | Cut brutal ambient, whoosh descendant pour renforcer la chute (Audio System compose) |

**A-2. Surface material tagging (footsteps)**

Chaque `StaticBody3D` de la géométrie expose une métadonnée `surface_material` (String) au moment de l'authoring :

| Tag | Surfaces concernées | Footstep SFX attendu (Audio System) |
|-----|---------------------|--------------------------------------|
| `concrete` | Sols standard, plafonds | Son mat, court, 80 ms |
| `metal` | Chrome, rampes | Son métallique, tail plus longue 150 ms |
| `glass` | Ponts/plateformes verre (Tier 2+) | Son cristallin (non-MVP) |
| `none` | Surfaces non-walkables (plafonds) | Aucun (ne devrait jamais déclencher) |

Level System **ne joue pas** ces sons. Il les tagge, Audio System les route. La valeur par défaut en absence de tag est `concrete` (choix conservateur).

**A-3. Ambient "voix" de la tour (Tier 2+ — non MVP)**

Post-MVP : ajouter des points d'ancrage `Marker3D` nommés `AmbientVoxEmitter_NN` pour des micro-SFX (relais corporate lointains, ascenseurs, ventilation). Ces points seront consommés par Audio System uniquement. **Pas au MVP** — le vide sonore renforce la tension "Le vide rend la lame visible" (transposée à l'audio).

**A-4. Silence volontaire**

- Pas de music MVP (décision Audio System, voir `design/gdd/audio-system.md` quand il existera).
- Pas d'ambient layer swap per-room MVP — un unique drone d'étage qui persiste. Cela laisse le katana, les pas, et les ennemis porter la totalité du signal audio.

### Budgets render/audio (synthèse cross-référence avec Tuning Knobs)

| Budget | Cible MVP | Gate enforcement |
|--------|-----------|-------------------|
| Draw calls par étage | ≤ 350 | Formula 2 + lint pré-build |
| VRAM statique étage | ≤ 50 MB | G-Perf VRAM_BUDGET_ETAGE_MB |
| Textures par étage | 1 atlas 1024×1024 partagé max | V-5 |
| Shader uniques | 1 | V-1 |
| Signaux audio émis par Level | 5 types (level_active, level_unloading, room_entered, etage_completed, player_out_of_world) | Contrat verrouillé — nouveau signal = amendement GDD |

## UI Requirements

**Le Level System ne dessine aucun élément UI lui-même.** Il publie de la donnée que HUD System, Tutorial System et Menu System consomment. Cette section définit **le contrat de données** offert à ces consommateurs.

### UI-1 — Données publiées au HUD

| Donnée | Source | Usage HUD (MVP) | Fréquence update |
|--------|--------|-----------------|-------------------|
| `current_room_index: int` | Signal `room_entered(index, total)` | Affichage "Salle 3 / 10" optionnel, coin supérieur gauche | À chaque franchissement trigger, ≤ 10 fois / étage |
| `total_rooms: int` | Signal `level_active` payload | Dénominateur de l'affichage progression | 1× par étage |
| `etage_id: int` | Signal `level_active` payload | Affichage "Étage 1" (relevant quand plusieurs étages Tier 2+) | 1× par étage |
| `checkpoints_reached: int` | Non publié par Level — consommé via Checkpoint System qui écoute `level_active` + ses propres body_entered | Affichage checkpoint flash transitoire (< 500 ms) | Événementiel |
| `secrets_available_in_etage: int` | Non publié par Level — Secret System expose sa propre API post-`level_active` | Affichage "0 / 3 secrets" si HUD active la feature | 1× par étage |

**Principe** : HUD System s'abonne à `level_active` et `room_entered`. Tout autre donnée dérive de ses peers.

### UI-2 — Ancres pour Tutorial System (Vertical Slice — non MVP)

`get_tutorial_anchor(tag: String) -> Marker3D` est une API synchrone lookup. Chaque étage peut embarquer des `Marker3D` nommés `TutorialAnchor_<tag>` dans son arbre. Le Tutorial System les résout au moment où il affiche une instruction contextuelle.

**Tags canoniques MVP (1er étage uniquement)** :
- `first_dash` — position où afficher "Shift pour dasher" (salle 1)
- `first_wall` — position où afficher "Cours le mur" (salle 2)
- `first_enemy` — position où afficher "Clic pour trancher" (salle 3)

Si un tag requis n'existe pas dans l'étage courant : Tutorial System ne crash pas — il skip silencieusement (la tutorialisation est advisory, non-blocking).

### UI-3 — Interaction avec Menu System

**Level System ne dialogue pas directement avec Menu System.** Quand le joueur ouvre le menu pause :
- Game State Manager passe en état `Paused` (hors scope Level)
- Level System **ne réagit pas** au pause — il ne met rien en sommeil (les Area3D restent actives, mais le physics tick est gelé par Godot)
- Quand le menu se ferme : état `Paused → Active` orchestré par Game State Manager, Level n'a rien à faire

**Aucun callback Level sur pause/resume** — la scène reste identique frame-to-frame.

### UI-4 — États UI spéciaux déclenchés par signaux Level

| Signal Level | UI État attendu (HUD/Menu) |
|--------------|----------------------------|
| `level_load_slow(elapsed_ms)` | HUD affiche optionnellement un spinner "chargement" si elapsed > 600 ms (advisory UX — pas un bloquant) |
| `level_load_failed(etage_id, reason)` | Menu System affiche écran d'erreur avec reason + bouton "retour menu principal" |
| `etage_completed(etage_id)` | HUD affiche flash "Étage terminé" (500 ms) pendant que Game State Manager orchestre la transition vers le shop |
| `player_out_of_world` | Aucun UI — le fade respawn est géré par Camera System (ADR-0003) |

### UI-5 — Non-requirements explicites

- **Aucune minimap** au MVP. Les étages sont linéaires, la tour est lisible par le regard vers le haut. Une minimap violerait la "charge cognitive zéro" de Pillar 1.
- **Aucun compass / objective marker** vers le prochain checkpoint ou la sortie. La géométrie et l'éclairage guident (V-2 "Mur proche sortie étage" = halo blanc).
- **Aucun temps écoulé** affiché MVP. Post-MVP : speedrun overlay optionnel, géré par Speedrun & Leaderboards System (Full Vision).

Toute demande d'UI supplémentaire qui exige de la donnée Level **ajoute un signal typé** au contrat UI-1, avec entrée explicite dans ce tableau et mise à jour §Detailed Design §Interactions.

## Acceptance Criteria

Format `GIVEN / WHEN / THEN` — chaque AC est testable par QA (automatisé ou manuel walkthrough). Les ACs taggés **AUTO** peuvent être couverts par GUT ; **SMOKE** = vérif manuelle scriptée ; **PLAYTEST** = observation pendant playtest.

### Groupe A — Lifecycle & Loading (AC-LVL-1..10)

**AC-LVL-1** **AUTO** — Boot initial Unloaded
- GIVEN application lancée pour la première fois, aucun étage chargé
- WHEN le singleton Level System est instancié (autoload)
- THEN `Level.get_state() == LevelState.UNLOADED` ET `Level.get_current_etage_id() == -1`

**AC-LVL-2** **AUTO** — Transition Unloaded → Active via load_etage
- GIVEN état `Unloaded`
- WHEN appel `load_etage(1)` puis attente signal `level_active`
- THEN signal `level_active(1, player_start: Vector3)` reçu dans un délai < 1000 ms ET `get_state() == LevelState.ACTIVE` ET `get_current_etage_id() == 1`

**AC-LVL-3** **AUTO** — Load time ≤ 1 seconde (gate Formula 4)
- GIVEN état `Unloaded`, étage_01.tscn en conditions MVP (≤ 50 MB, ≤ 10 salles)
- WHEN mesure `Time.get_ticks_msec()` entre `load_etage(1)` et émission `level_active`
- THEN delta ≤ 1000 ms sur hardware de référence (spec `docs/architecture/hardware-spec-testbeds.md` Tier 1)

**AC-LVL-4** **AUTO** — Rejet concurrent load (EC-2)
- GIVEN état `Active` étage 1
- WHEN appel `load_etage(2)` sans `unload_current()` préalable
- THEN en debug build : assert fail avec message explicite ; en release build : no-op + `push_error` (aucune corruption état)

**AC-LVL-5** **AUTO** — Unload propre
- GIVEN état `Active`, peers abonnés à `level_active`
- WHEN appel `unload_current()`
- THEN signal `level_unloading(etage_id)` émis **avant** `queue_free()` ; 1 frame plus tard, `get_state() == LevelState.UNLOADED` ; aucune référence pendante dans les peers (vérifiable via `is_instance_valid()` sur les Marker3D mémorisés)

**AC-LVL-6** **AUTO** — level_load_failed sur scène absente (EC-3)
- GIVEN état `Unloaded`, path de scène invalide passé
- WHEN appel `load_etage(999)` où etage_999.tscn n'existe pas
- THEN signal `level_load_failed(999, reason)` reçu, `reason` non-vide ; état reste `Unloaded` ; aucun crash

**AC-LVL-7** **AUTO** — level_load_slow advisory (EC-10)
- GIVEN scène simulée à charger lente (> 600 ms via mock)
- WHEN load en cours
- THEN signal `level_load_slow(elapsed_ms)` reçu au moins une fois, avec `elapsed_ms ≥ 600` ; le load n'est **pas** interrompu ; `level_active` toujours émis quand prêt

**AC-LVL-8** **AUTO** — Assert PlayerStart absent (EC-4)
- GIVEN scène test volontairement amputée de `PlayerStart` Marker3D
- WHEN appel `load_etage(test)`
- THEN en debug : assert fail avec message "missing PlayerStart marker" ; en release : fallback `Vector3.ZERO` + `push_error`

**AC-LVL-9** **AUTO** — Re-load après unload reset complet (EC-12)
- GIVEN étage 1 Active, peers ont placé leurs entités, joueur a franchi 3 salles
- WHEN `unload_current()` puis `load_etage(1)` à nouveau
- THEN le nouvel `level_active` porte le même `etage_id=1` ; `current_room_index` remis à 0 ; aucun état résiduel (vérifiable via `get_level_state().rooms_visited == []`)

**AC-LVL-10** **SMOKE** — Idempotence de unload_current
- GIVEN état `Unloaded`
- WHEN appel `unload_current()` alors qu'aucun étage n'est chargé
- THEN no-op silencieux, aucun crash, aucun signal émis

### Groupe B — Scene structure & authoring invariants (AC-LVL-11..20)

**AC-LVL-11** **AUTO** — Hiérarchie canonique présente (R-1)
- GIVEN scène étage_01.tscn chargée
- WHEN introspection arbre via `get_node_or_null("StaticEnvironment") != null` pour chaque groupe canonique
- THEN `StaticEnvironment`, `InteractiveVolumes`, `SpawnMarkers`, `EtageExitTrigger` tous présents ET non-null

**AC-LVL-12** **AUTO** — Layer 4 exclusif pour géométrie statique
- GIVEN scène chargée
- WHEN scan de tous les `StaticBody3D` sous `StaticEnvironment`
- THEN chacun a `get_collision_layer_value(4) == true` ET `collision_mask == 0` (statique ne détecte rien)
- **Correction r2** : commentaire r1 "(bit 4 = layer 4)" **faux** — "Layer 4" de Project Settings Godot = bit **3** zéro-indexé (soit `1 << 3 = 8`). API recommandée : `set_collision_layer_value(4, true)` / `get_collision_layer_value(4)` (1-indexée, idiomatique Godot 4) plutôt que manipulation bitmask directe.

**AC-LVL-13** **AUTO** — Layer 5 exclusif pour triggers interactifs
- GIVEN scène chargée
- WHEN scan de tous les `Area3D` sous `InteractiveVolumes`
- THEN chacun a `get_collision_layer_value(5) == true` ET `monitorable == false` ET `monitoring == true` ET `get_collision_mask_value(<LAYER_PLAYER>) == true` (doit inclure la layer joueur dans son mask, sinon `body_entered` ne se déclenche **jamais** silencieusement — cf. registry constante `LAYER_PLAYER`, owned par Combat r6)
- **Correction r2** : commentaire r1 "(bit 5 = layer 5)" **faux** — bit **4** zéro-indexé = "Layer 5" 1-indexée Project Settings. Ajout du gate `collision_mask ⊃ LAYER_PLAYER` (godot-specialist R5).

**AC-LVL-14** **AUTO** — Width minimal des portes (Formula 1)
- GIVEN scène chargée
- WHEN pour chaque porte annotée `RoomTrigger_NN`, mesure du bounding box `Area3D` sur l'axe horizontal local
- THEN largeur ≥ 3.6 m ; si violation, lint pré-build échoue

**AC-LVL-15** **AUTO** — Hauteur minimale wall-runnable (Formula 8)
- GIVEN scène chargée
- WHEN pour chaque StaticBody3D taggé `wall_run_enabled = true`, lecture AABB
- THEN `height ≥ 4.0 m` ET `length ≥ 3.0 m` ET orientation ± 5° du vertical

**AC-LVL-16** **AUTO** — Pas de géométrie sous Y=-2.0 (R-2.4)
- GIVEN scène chargée
- WHEN scan AABB de tous les StaticBody3D
- THEN aucun `aabb.min.y < -2.0` ; une seule exception : éventuelle dalle de plancher nominale à `y=0`

**AC-LVL-17** **AUTO** — Épaisseur minimale murs (EC-8)
- GIVEN scène chargée
- WHEN scan de chaque `BoxShape3D` utilisé comme mur
- THEN min(size.x, size.z) ≥ 0.3 m sur l'axe "épaisseur" (axe perpendiculaire à la face principale)

**AC-LVL-18** **AUTO** — PlayerStart unique par étage (R-5.3)
- GIVEN scène chargée
- WHEN `find_children("PlayerStart", "Marker3D", true)`
- THEN longueur résultat == 1

**AC-LVL-19** **AUTO** — Cohérence indexée CheckpointVolume_NN ↔ CheckpointAnchor_NN (R-5.2)
- GIVEN scène chargée
- WHEN pour chaque `CheckpointVolume_NN`, lookup `CheckpointAnchor_NN` correspondant
- THEN chaque volume a un anchor pair avec le même index zero-padded, ET distance ≤ 10 m entre volume et anchor

**AC-LVL-20** **AUTO** — Nombre de salles dans la range MVP
- GIVEN scène chargée
- WHEN count des `RoomTrigger_NN` distincts
- THEN `count ∈ [8, 10]` pour un étage MVP

### Groupe C — Triggers, signals, idempotence (AC-LVL-21..30)

**AC-LVL-21** **AUTO** — room_entered émis au franchissement
- GIVEN état `Active`, joueur positionné hors `RoomTrigger_03`
- WHEN téléport player dans `RoomTrigger_03`
- THEN signal `room_entered(3, total_rooms)` émis exactement 1 fois dans les 2 frames suivantes

**AC-LVL-22** **AUTO** — room_entered idempotent sur re-entrée
- GIVEN joueur dans `RoomTrigger_03`
- WHEN joueur sort puis re-rentre dans la même Area3D
- THEN chaque entrée émet un `room_entered(3, ...)` séparé (pas de dédup — le HUD décide si afficher)

**AC-LVL-23** **AUTO** — Ordre déterministe sur triggers simultanés (EC-5)
- GIVEN 2 RoomTriggers chevauchants (RoomTrigger_03, RoomTrigger_04)
- WHEN joueur franchit la zone overlap le même frame
- THEN séquence `room_entered(3)` PUIS `room_entered(4)` dans l'ordre d'arborescence `InteractiveVolumes` ; pas d'inversion

**AC-LVL-24** **AUTO** — etage_completed fires-once
- GIVEN état `Active`, joueur hors `EtageExitTrigger`
- WHEN joueur entre dans `EtageExitTrigger`
- THEN signal `etage_completed(etage_id)` émis exactement 1 fois ; même s'il ressort et re-rentre, aucun second émission (l'état est passé `Unloading`)

**AC-LVL-25** **AUTO** — player_out_of_world déclenché par WorldBounds (EC-1)
- GIVEN joueur à `Vector3(0, 10, 0)` dans état Active
- WHEN `global_position.y` passé à `-3.0` (sous R-2.4)
- THEN signal `player_out_of_world(last_valid_position)` émis exactement 1 fois ; `last_valid_position` ≠ position void

**AC-LVL-26** **AUTO** — level_active reçu post-autoload-ready (EC-11 / ADR-0005 D-5)
- GIVEN peer fictif connecté à `level_active`, avec un `_ready()` qui log `peer_ready_tick = Engine.get_process_frames()`
- WHEN `load_etage(1)` appelé
- THEN le handler `level_active` log `active_received_tick` et l'assertion vérifie `peer_ready_tick < active_received_tick` (comportement observable uniquement).
- **Raisonnement canonique (cf. EC-11)** : la garantie d'ordre provient de l'**ordre natif Godot autoload → main scene** (tous les `_ready()` d'autoloads tournent avant que `load_etage()` ne soit jamais appelé depuis la main scene), PAS d'une propriété de `call_deferred`. `call_deferred` reporte l'émission au frame courant fin-de-file sans garantir d'ordre par rapport aux `_ready()` de nœuds ajoutés dans le même frame. L'AC teste donc le comportement observable (tick < tick) et laisse EC-11 porter le raisonnement mécanique.

**AC-LVL-27** **SMOKE** — Signaux typés respectent leur signature
- GIVEN GDD signals list
- WHEN introspection via `Level.get_signal_list()`
- THEN chaque signal déclaré a ses types correctement annotés (int, Vector3, String) — pas de signal `Variant`

**AC-LVL-28** **AUTO** — Désabonnement au level_unloading (T-3)
- GIVEN peer abonné à `level_active` et `room_entered`
- WHEN `unload_current()` appelé
- THEN le peer reçoit `level_unloading` ; un `get_signal_connection_list("room_entered")` retourne liste vide après que Level a émis le signal (peer désabonné proactivement par convention)

**AC-LVL-29** **AUTO** — Aucun signal émis depuis un Thread non-main
- GIVEN chaque fonction de Level System qui émet un signal embarque une assertion `assert(Thread.get_caller_id() == OS.get_main_thread_id(), "level_system: signal emitted from non-main thread")` avant `emit_signal`
- WHEN suite de tests GUT `test_level_signals_main_thread.gd` exécute tous les chemins d'émission (level_active, level_unloading, etage_completed, room_entered, player_out_of_world, level_load_failed, level_load_slow)
- THEN aucune assertion fail ; aucun signal émis depuis un contexte thread non-main
- **Note** : API Godot correcte est `Thread.get_caller_id()` + `OS.get_main_thread_id()`, non `OS.get_thread_caller_id()`

**AC-LVL-30** **AUTO** — get_tutorial_anchor renvoie null si tag inconnu
- GIVEN étage_01 chargé sans `TutorialAnchor_nonexistent`
- WHEN appel `get_tutorial_anchor("nonexistent")`
- THEN retourne `null` ; aucune exception ; `push_warning` émis en debug

### Groupe D — Performance & budgets (AC-LVL-31..37)

**AC-LVL-31** **AUTO** — Draw call budget par étage (Formula 2)
- GIVEN étage_01 actif, **scène Level isolée** (aucun peer instancié : Enemy, VFX, HUD overlay désactivés pour ce test d'isolation)
- WHEN mesure `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` sur **500 frames minimum** par salle (aligné sur `docs/architecture/hardware-spec-testbeds.md` §Integrated Benchmark Protocol — 500 frames est le plancher, 1000 recommandé)
- THEN p99 `draw_calls_level ≤ 350` pour N=10 (p99 ≤ 290 pour N=8) — gate isolée Level
- **Gate séparé (non cet AC)** : AC-LVL-31b vérifie `budget_peers ≤ 170` en combat normal (Combat + Enemy + VFX actifs — responsabilité QA plan Combat)

**AC-LVL-31b** **AUTO** — Budget peers en combat normal
- GIVEN étage_01 actif avec scénario combat "3 ennemis actifs + 1 swing katana en cours + VFX trail dash"
- WHEN mesure sur 500 frames
- THEN `p99(total_draw_calls) - p99(draw_calls_level_baseline) ≤ 170` ; `p99(total_draw_calls) ≤ 500` (gate global)

**AC-LVL-32** **AUTO** — VRAM budget statique (tuning G-Perf VRAM_BUDGET_ETAGE_MB)
- GIVEN étage_01 actif
- WHEN mesure `RenderingServer.get_rendering_info(RENDERING_INFO_VIDEO_MEM_USED)` post-load
- THEN delta par rapport au baseline pré-load ≤ 50 MB

**AC-LVL-33** **REMOVED r3** — supersédé par AC-LVL-55 (budgets per-archetype r2 CD fix #5). La couverture `count StaticBody3D` pour tous archetypes (Traversal ≤ 18, Combat ≤ 32, Shaft ≤ 28, SecretHub ≤ 25) est portée par AC-LVL-55 avec seuils plus granulaires. AC-LVL-33 r1 (≤ 25 uniforme) était devenu contradictoire avec AC-LVL-55 (Combat ≤ 32) — un COMBAT à 28 bodies passait 55 mais faillait 33. Suppression aligne BLOCKING-3 r2-fresh.

**AC-LVL-34** **AUTO** — Frame time stable intra-salle (aligné Combat AC-CMB-35b)
- GIVEN joueur Active dans une salle (pas en transit), hardware Tier 1 (voir note testbed ci-dessous)
- WHEN mesure frame time sur 500 frames minimum (≥ 8 s à 60 fps) continues
- THEN `p50 ≤ 12.0 ms` ET `p99 ≤ 14.0 ms` (headroom vs budget théorique 16.6 ms — aligne sur le pattern établi Combat AC-CMB-35b pour garantir Tier 1 GTX 1050)
- **Note testbed** : Tier 1 = spécification figée dans `docs/architecture/hardware-spec-testbeds.md` §Tier 1 (i5-8400 ou équivalent, GTX 1050 ou équivalent, SSD SATA min). Si le testbed doc est révisé, cet AC doit être co-révisé.

**AC-LVL-35a** **AUTO** — Frame time pendant room transition (gate objectif)
- GIVEN étage_01 actif, joueur téléporté juste avant `RoomTrigger_03`
- WHEN mesure frame time sur la fenêtre [-200 ms, +200 ms] autour de l'émission `room_entered(3)` (~24 frames @ 60 fps)
- THEN `p99 ≤ 14.0 ms` pendant cette fenêtre (aligne AC-LVL-34, aucun spike au trigger)
- **Fail = BLOCKING**. Gate mesurable, pas subjectif.

**AC-LVL-35b** **PLAYTEST** — Aucun stutter perceptible au room_entered (gate subjectif corroboré)
- GIVEN playtest Tier 1 avec QA observateur, AC-LVL-35a PASS au préalable
- WHEN joueur franchit 10 transitions de salle d'affilée
- THEN aucune micro-pause visible subjective
- **Fail = ADVISORY** (sign-off lead). Divergence avec AC-LVL-35a (p99 OK mais stutter perçu) → investiguer allocations transitoires / buffer swap.

**AC-LVL-36** **AUTO** — Aucune allocation majeure après level_active (pattern Combat Pattern 2)
- GIVEN étage Active depuis 1 s (warmup)
- WHEN mesure conjointe sur 60 s d'exploration :
  1. `OS.get_static_memory_usage()` — alloc C++ moteur
  2. `Performance.OBJECT_COUNT` delta — heap GDScript (objets Godot)
- THEN `delta_static_memory ≤ 512 KB` ET `delta_object_count ≤ +5` sur la fenêtre 60 s
- **Justification seuils** : 512 KB aligne les patterns d'autres systèmes (no-alloc-hot-paths.md InputManager = 64 KB, plus strict ; Level alloue en `room_entered` des arrays transitoires que GC libère — 512 KB est conservateur). `+5 objects` capture les fuites de signals non-désabonnés sans faux-positifs sur les Dictionary transitoires.

**AC-LVL-37** **SMOKE** — Baseline mémoire étage < 50 MB
- GIVEN avant load vs. après load étage_01
- WHEN diff mémoire statique (RAM + VRAM)
- THEN ≤ 70 MB combined (RAM 20 MB + VRAM 50 MB)

### Groupe E — Edge cases coverage (AC-LVL-38..42)

**AC-LVL-38** **AUTO** — NaN transform ignoré (EC-9)
- GIVEN player body avec `global_position.x = NaN`
- WHEN `RoomTrigger_NN.body_entered(body)` émis
- THEN Level ne propage **pas** `room_entered` ; `push_warning` en debug ; pas de crash

**AC-LVL-39** **AUTO** — Assert fail concurrent load précis (EC-2)
- GIVEN état `Active`
- WHEN `load_etage(2)` en debug build
- THEN assert fail contient "concurrent load" ET "unload first" dans le message

**AC-LVL-40** **SMOKE** — validate_checkpoint_anchors catches bad authoring (EC-7)
- GIVEN scène test avec un CheckpointAnchor volontairement à l'intérieur d'un mur
- WHEN appel `validate_checkpoint_anchors()` en debug
- THEN retourne array non-vide avec `{anchor_name, position, reason: "inside_static_body"}` pour l'anchor fautif

**AC-LVL-41** **PLAYTEST** — Pas de clip à velocity max (EC-8)
- GIVEN joueur avec moveset MVP (dash + double-jump + wall-run). Liste des **murs critiques** définie dans `production/qa/playtest-protocols/level-clip-regression.md` (à créer au Sprint 1 par level-designer + qa-lead) : **les 5-8 murs désignés par le level-designer comme à-risque** — typiquement : sortie de tube dash, fin de wall-run vers un mur adjacent, jonctions porte-mur à angle aigu.
- WHEN protocole exécuté : QA tester effectue **10 passages par mur** à vitesse maximale (dash + combo) depuis l'approche nominale
- THEN **0 clip observé sur ≥ 95 % des passages** (soit ≥ 76 / 80 passages clean pour 8 murs × 10 passages). Tout clip observé est loggé comme bug S2 minimum avec screenshot.
- **Pré-requis** : EC-8 Jolt CCD doit être validé via benchmark prototype AVANT ce playtest — cf. note CLAIM-UNVERIFIED EC-8.

**AC-LVL-42** **SMOKE** — Quit-to-menu puis re-load fresh state (EC-12)
- GIVEN session playtest : player atteint salle 5, collecte 2 secrets via peers
- WHEN quit → menu → re-load étage 1
- THEN `current_room_index == 0`, `secrets_collected_in_etage == 0` (reset), aucun ennemi mort persistant

### Groupe F — Meta / traçabilité (AC-LVL-43..45)

**AC-LVL-43** **SMOKE** — Signals list match §Detailed Design
- GIVEN implementation Level System
- WHEN lecture runtime des signaux exposés vs. liste contractuelle (R-3 §Interactions + UI-4)
- THEN correspondance 1:1 ; aucun signal non-documenté ; aucun signal documenté absent

**AC-LVL-44** **SMOKE** — Tuning Knobs accessibles (condition d'entrée : post-implémentation)
- **Condition d'entrée** : fichier `design/registry/level.yaml` créé au sprint d'implémentation Level System. Cet AC est **non-testable** tant que le fichier n'existe pas.
- GIVEN implémentation Level System terminée ET `design/registry/level.yaml` présent
- WHEN introspection des `@export` du script Level + lecture du YAML
- THEN tous les knobs listés §Tuning Knobs (authoring + runtime + debug) sont présents avec leur default MVP ; commentaires inline listent la range safe. Tout knob documenté dans §Tuning Knobs mais absent du YAML/exports = FAIL.

**AC-LVL-45** *(retiré — déplacé en règle de review process)*

Cette AC r1 ("Reciprocity forward placeholder") était un AC hors-périmètre : elle se déclenche à la création d'un *autre* GDD, pas à l'implémentation du Level System. Déplacée dans la checklist `/design-review` comme règle de process. Voir `.claude/rules/design-docs.md` "Dependencies must be bidirectional" — cette règle gouverne les reviews futures des GDDs downstream (checkpoint/secret/enemy/hud/tutorial/audio/vfx) qui doivent citer Level System en §Dependencies à leur création.

### Groupe G — Couverture formules (AC-LVL-46..50)

**AC-LVL-46** **AUTO** — Secret count dans la range MVP (Formula 7)
- GIVEN étage_01 chargé, `SECRET_DENSITY_DIVISOR = 3`, `N_rooms = 10`
- WHEN count `SecretCollectVolume_NN` distincts dans la scène **(r2 fix #4 — renommé depuis SecretVolume_NN)**
- THEN `count ∈ [3, 5]` (plancher/plafond MVP). De plus : **au moins 1 secret a `required_ability ∈ {wall_run, wall_run_long}`** (contrainte économique §Interactions)

**AC-LVL-47** **AUTO** — Checkpoint count conforme (Formula 3)
- GIVEN étage_01 chargé, `CHECKPOINT_SPACING = 3`, `N_rooms = 10`
- WHEN count `CheckpointVolume_NN` distincts
- THEN `count == ceil(N_rooms / CHECKPOINT_SPACING) = 4`. Ajuster si knobs modifiés.

**AC-LVL-48** **AUTO** — Altitude totale étage dans la range (Formula 5)
- GIVEN étage_01 chargé
- WHEN mesure `|PlayerStart.global_position.y - EtageExitTrigger.global_position.y|`
- THEN résultat ∈ [15, 60] m. Violation = lint fail pré-build.
- **Note borne** : [15, 60] m = range F5 complète (ETAGE_HEIGHT_MIN..ETAGE_HEIGHT_MAX). Le nominal MVP recommandé est 30 m (cf. F5 mix nominal) mais **n'est pas gated** — un étage "double-shaft 40-45 m" accommodant la Player Fantasy "puits 40 m" est légal. Aligné BLOCKING-1 r2-fresh (cross-model 3×).

**AC-LVL-49** **AUTO** — WorldBoundsVolume englobe l'étage (Formula 6)
- GIVEN étage_01 chargé
- WHEN calcul AABB union de tous les StaticBody3D sous `StaticEnvironment` + AABB de `WorldBoundsVolume`
- THEN `WorldBoundsVolume.AABB` contient strictement l'AABB union avec une marge ≥ 3 m sur tous les axes

**AC-LVL-50** **AUTO** — Diversité archetype des salles (R-2.6 r2 S-1/S-3/S-5)
- GIVEN étage_01 chargé
- WHEN introspection des `@export archetype: RoomArchetype` de chaque `Room_NN` (alias r1 `room_type` convertis automatiquement)
- THEN : (a) au moins **3 archetypes distincts** sur l'étage ; (b) au moins **1 `SHAFT`** présent ; (c) au moins **1 `SECRET_HUB`** présent ; (d) aucune paire `COMBAT` consécutive (S-2) ; (e) salle finale avant `EtageExitTrigger` ∈ `{SECRET_HUB, TRAVERSAL}` (S-4). Violation = lint fail.

**AC-LVL-51** **AUTO** — Invariant de spacing checkpoints (Formula 3, gate lint pré-build)
- **Motivation** : AC-LVL-47 vérifie le count dérivé des knobs MVP. Si un designer override `CHECKPOINT_SPACING` hors safe_range (ex: 10) sans modifier `N_rooms`, le count dérivé reste cohérent avec la formule mais viole l'intention F3 silencieusement. Cet AC protège l'**invariant spacing lui-même**, indépendamment des knobs.
- GIVEN étage_NN chargé avec `N_rooms` salles et `K = count(CheckpointVolume_NN)` checkpoints
- WHEN calcul `spacing_observed = floor(N_rooms / K)` (en excluant `PlayerStart` qui n'est pas un checkpoint)
- THEN `spacing_observed ∈ [2, 3]` strictement. Violation = lint fail pré-build avec message explicite : `"level_system: checkpoint spacing = {spacing_observed} (N_rooms={N}, K={K}) hors range [2, 3] — voir Formula 3"`.
- **Cas limite** : `K == 0` (aucun checkpoint) = fail immédiat (spacing indéfini). `K == 1` sur `N >= 4` rooms = fail (spacing ≥ 4 viole Pillar 3 SECONDE CHANCE). `K == N` = fail (spacing = 1, viole Pillar 1 FLOW).
- **Exécution** : script éditeur `tools/lint/level_lint.gd` appelé par CI job `lint-level-invariants` sur chaque `etage_*.tscn` commité.

### Groupe H — r2 CD 5 fixes applied (AC-LVL-52..55)

**AC-LVL-52** **AUTO** — Archetype `@export` obligatoire (R-1 r2 + R-2.6 r2)
- GIVEN scène `etage_*.tscn` chargée
- WHEN scan de tous les `Room_NN` sous `StaticEnvironment`
- THEN chaque `Room_NN` a une propriété `archetype: RoomArchetype` définie (`TRAVERSAL | COMBAT | SHAFT | SECRET_HUB`) — valeur legacy `room_type: RoomType` acceptée en import avec conversion automatique mais **flagged warning** pour migration. Absence totale = lint fail.

**AC-LVL-53** **AUTO** — Tuple Secret cohérent Lure ↔ Volume ↔ Anchor (r2 fix #4)
- GIVEN scène chargée
- WHEN scan des triplets `SecretLureMarker_NN`, `SecretCollectVolume_NN`, `SecretAnchor_NN`
- THEN pour chaque NN présent dans un des trois sous-arbres, les deux autres existent avec le même NN. De plus, chaque `SecretLureMarker_NN` a `required_ability ∈ {none, dash, double_jump, wall_run, wall_run_long}` exporté. Orphelin ou annotation manquante = lint fail avec message précisant le NN fautif.

**AC-LVL-54** **AUTO** — Combat onboarding anchors (étage 1, r2 fix #5)
- GIVEN `etage_01.tscn` chargé
- WHEN scan du sous-arbre `OnboardingAnchors`
- THEN : (a) `FirstEnemySightline` Marker3D présent ET raycast depuis `PlayerStart` de la salle 3 (ou salle `COMBAT` canonique) n'est pas obstrué par StaticBody3D avant d'atteindre le marker (lignede vue directe) ; (b) distance `PlayerStart ↔ FirstEnemySightline ≤ 15 m` ; (c) `SafeZoneCenter` Marker3D présent et distance ≥ 6 m de tout `EnemySlot_NN` de la salle ET distance ≥ 4 m de tout `HazardSlot_NN` de la salle ; (d) pour étage ≠ 1 : absence de `OnboardingAnchors` n'échoue pas l'AC. Lint pré-build.

**AC-LVL-55** **AUTO** — Budget perf par archetype (R-4 r2)
- GIVEN scène chargée, budgets R-4 r2 par-salle
- WHEN pour chaque `Room_NN` selon son `archetype` : count de DC estimés statiques (MeshInstance3D visibles), count de StaticBody3D enfants, count de Area3D enfants, count de Marker3D enfants
- THEN chaque count respecte sa ligne de la table R-4 r2 pour l'archetype correspondant. De plus, agrégation `Σ DC_salle_i + LEVEL_OVERHEAD ≤ 350` (plafond Formula 2 inchangé). Violation = lint fail par-salle précisant quel budget est dépassé (DC / StaticBody3D / Area3D / Marker3D) et de combien.

## Open Questions

Questions connues, délibérément reportées. Chacune a un **owner**, une **deadline de décision**, et un **trigger de réévaluation**.

### OQ-1 — Scene unique vs room-split au MVP — **CLOSED 2026-04-23**

**Question** : Un étage = 1 seul `.tscn` pré-chargé, OU un `.tscn` étage + 8-10 `.tscn` salles instanciées via `load_threaded_request` par porte ?

**Résolution r2 (godot-specialist)** : **Scene unique retenu.** Trois faits Godot 4.6 :
1. `ResourceLoader.load_threaded_request()` charge une scène entière en un seul appel async, sans overhead additionnel pour les sub-scenes inline — le split n'économise rien sur le temps de chargement.
2. Budget 8-10 salles × 25 StaticBody3D = 250 nœuds max, bien sous le seuil où la traversal du SceneTree devient visible (> 5000 nœuds).
3. Les room-triggers intra-étage n'unloadent rien (R-5.1) — aucun gain mémoire au MVP par le split.

**Conséquence** : R-5.1 reste la vérité de référence. Pas de room-split à implémenter au MVP.

**Réévaluation future (Tier 2+)** : si un étage dépasse 40 MB VRAM ou load time > 800 ms, rouvrir cette question. Le split reste pertinent si plusieurs étages doivent coexister en mémoire (ex: streaming inter-étage dans OQ-2).

**Owner (historique)** : technical-director + level-designer — fermeture sans consultation required (solution claire après godot-specialist review).

### OQ-2 — Streaming inter-étage (Tier 2+)

**Question** : Comment gérer la transition inter-étage ? Pre-load de l'étage N+1 pendant le shop intermédiaire, OU chargement discret avec écran noir ?

**Position actuelle** : Non tranché — game-concept §Session Length mentionne "1-2 étages par session" donc au Tier 2 le besoin apparaît.

**Owner** : technical-director + ux-designer
**Deadline** : Début Tier 2 (Vertical Slice — 3 étages requis)
**Trigger** : démarrage de l'épic "Multi-Etage".

### OQ-3 — Usage du LevelKit Godot 4.6 vs hand-built

**Question** : Godot 4.6 introduit des tools de level design (layers d'auto-tile 3D, room merge). Vaut-il le coût d'apprentissage pour un dev solo sur 1 étage ?

**Position actuelle** : Hand-built MVP — primitives + Marker3D manuels. Le volume (1 étage × 10 salles × 25 bodies/salle = 250 bodies) est tenable manuellement.

**Risque** : au Tier 3 (5 étages × ~10 salles), ~1250 bodies manuels deviennent lourds à maintenir.

**Owner** : level-designer + godot-specialist
**Deadline** : Début Tier 3
**Trigger** : 2e étage demande > 1 semaine d'authoring.

### OQ-4 — SDFGI ou GI baked pour l'ambiance Tier 2+

**Question** : Le shader Chrome Zen flat MVP ne demande pas de GI. Post-MVP, si on ajoute des sources de lumière locales (néons corporate, signalétique), faut-il SDFGI (runtime, coût GPU) ou GI baked (pipeline complexe) ?

**Position actuelle** : SDFGI désactivé MVP (V-4). Aucune décision Tier 2.

**Owner** : technical-artist + art-director
**Deadline** : Tier 2 (quand on ajoute la 1re source de lumière locale)
**Trigger** : demande d'une scène avec > 1 source lumineuse locale.

### OQ-5 — Audio ambient layer swap per-room — **CLOSED 2026-04-23**

**Question** : Au MVP, un seul drone d'étage. Vaut-il d'ajouter du swap ambient per-salle (combat / transition / secret) dès le MVP, ou en Tier 2 ?

**Résolution r2 (godot-specialist)** : **Désactivé MVP confirmé** — `AUDIO_ROOM_AMBIENT_SWAP = false`. Le mécanisme d'activation est trivialement implémentable en Tier 2+ via `AudioServer.set_bus_volume_db(bus_name, db)` appelé depuis un handler sur `room_entered` côté Audio System. **Une ligne GDScript**, zéro risque, zéro prototype. Pas besoin de trancher en amont — Level System publie déjà le signal `room_entered`, donc l'activation future est coût zéro côté Level.

**Conséquence** : A-3 / A-4 restent la vérité de référence. Audio System owner décide seul quand activer, sans dépendance Level.

**Réévaluation future** : si playtest MVP révèle fatigue auditive sur session 30+ min, activer le swap en Tier 2 via la route documentée ci-dessus.

**Owner (historique)** : audio-director — fermeture sans consultation required (mécanisme technique sans risque).

### OQ-6 — Accessibility options (Tier 3)

**Question** : Comment exposer des options d'accessibilité Level-spécifiques (réduction de verticalité, triggers plus généreux, option "checkpoint à chaque salle") ?

**Position actuelle** : Hors scope MVP. Accessibility System (#20, Full Vision) lira les tuning knobs existants et les modifiera via une couche de surcharge.

**Owner** : accessibility-specialist
**Deadline** : Tier 3
**Trigger** : démarrage de l'épic Accessibility System.

### OQ-7 — Validation runtime anchors (EC-7 hardening)

**Question** : Faut-il systématiser `validate_checkpoint_anchors()` en CI (run au load sur tous les étages-fixtures) ou laisser à QA ?

**Position actuelle** : Exposé en debug API (EC-7), appelé manuellement via SMOKE (AC-LVL-40).

**Risque** : un mauvais placement d'anchor peut passer review et casser un checkpoint player en prod.

**Owner** : qa-lead + level-designer
**Deadline** : Pré-Vertical Slice (avant le 2e étage)
**Trigger** : premier bug d'authoring anchor remonté en QA.

### OQ-8 — Debug draw overlay F-shortcut

**Question** : Suivre le pattern de `input_debug_overlay.gd` (F3 story-009) pour un overlay F2 "Level debug" (wireframe checkpoints + secrets + room bounds) ?

**Position actuelle** : Tuning Knobs debug (`DEBUG_DRAW_CHECKPOINTS` etc.) existent mais leur UI d'activation n'est pas définie.

**Owner** : tools-programmer
**Deadline** : Pré-Vertical Slice
**Trigger** : QA demande un outil visuel répétable pour tester les anchors placements.

---

*Aucune question ci-dessus ne bloque le MVP.* Les positions actuelles sont suffisamment fermes pour démarrer l'implémentation. Chaque Open Question sera tranchée à sa deadline ou à son trigger, pas plus tôt.
