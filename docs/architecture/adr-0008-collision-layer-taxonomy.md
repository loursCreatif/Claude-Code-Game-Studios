# ADR-0008: Collision Layer Taxonomy & Mask Canonicalization

## Status
Accepted 2026-04-23 r4 (promoted via `/architecture-review full` r4 — verdict PASS pour promotion : 0 cross-ADR conflict vs ADR-0001/0003/0005/0006/0007/0011, upstream dep ADR-0001 Accepted, Engine LOW risk (API 1-idx `set_collision_layer_value`/`set_collision_mask_value` stable Godot 4.0+, 0 post-cutoff, 0 deprecated, Jolt 4.6 = 0 divergence), godot-specialist APPROVE r3 (réciprocité unilatérale Player→Enemy valide Jolt, NavigationAgent3D.navigation_layers séparé donc layers 6-32 free). Ferme **Gap G-5** (TR-cmb-012 + TR-lvl-008 Covered) et ajoute second coverage à TR-lvl-007. Architecture globale **passe CONCERNS → PASS** (0 Foundation/Core gap, 6 Feature gaps tous non-blockers MVP documentés). Migration Plan à Sprint 0 Technical Setup : update `project.godot [layer_names]`, créer `src/core/collision_layers.gd`, ajouter CI lint `lint-collision-layers`, créer smoke test `tests/unit/collision/layer_mask_contract_test.gd`, créer `.claude/rules/collision-layer-api-1-indexed.md`. GDD sync Sprint 1 Combat : Combat GDD l.88 snippet illustratif `query.collision_mask = 0b00010` → `CollisionLayers.build_mask([CollisionLayers.LAYER_ENEMY])` ; ADR-0006 D-4a MockEnemy l.177 `collision_layer = 0b00010` à migrer vers `set_collision_layer_value(CollisionLayers.LAYER_ENEMY, true)` lors de l'implémentation réelle (hors scope lint D-6 qui cible `src/**` uniquement).)

## Date
2026-04-23

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Physics |
| **Knowledge Risk** | LOW — La 1-indexation de Project Settings → Layer Names → 3D Physics et les méthodes `set_collision_layer_value(N)` / `get_collision_mask_value(N)` existent depuis Godot 4.0 stable et sont documentées sans ambiguïté. Aucun changement 4.4/4.5/4.6 sur cette API (validé `docs/engine-reference/godot/modules/physics.md`). Jolt (4.6 default) consomme les mêmes layer/mask bits — pas de divergence Jolt vs GodotPhysics3D sur cette surface. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/modules/physics.md`, `docs/engine-reference/godot/breaking-changes.md` (aucune breaking change physics layer API), `docs/registry/architecture.yaml` §state_ownership (LAYER_PLAYER/ENEMY/ENEMY_HITBOX/ENVIRONMENT/INTERACTIVE déjà enregistrées owned par Combat GDD r6). |
| **Post-Cutoff APIs Used** | Aucune. L'API `set_collision_layer_value` / `get_collision_layer_value` / `set_collision_mask_value` / `get_collision_mask_value` est pré-cutoff (Godot 4.0). |
| **Verification Required** | (1) Lint pre-build CI vérifie que chaque `CollisionObject3D` du projet déclare un `collision_layer` et `collision_mask` conformes à la Decision Matrix ci-dessous. (2) Test GUT smoke : spawn minimal scene avec un de chaque archetype, assert `get_collision_layer_value(N) == true` pour N attendu + `get_collision_mask_value(M) == true` pour chaque bit M attendu. (3) Project Settings → Layer Names → 3D Physics doit contenir les 5 noms canoniques (vérifié via diff `project.godot`). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 Accepted (physics engine Jolt + tick rate 60 Hz — un ADR layer taxonomy ne peut être posé qu'après le choix du moteur physique, car le comportement des layers dépend du backend). |
| **Enables** | Epic Enemy System (définit collision_layer=2 pour corps + 3 pour lethal hitbox) ; Epic Hazard System (layer=3 pour lethal triggers environnementaux — lasers, spikes) ; Epic Boss System (réutilise layers 2+3, variantes en +XL) ; Epic Secret System (SecretCollectVolume layer=5 déjà prévu Level GDD §InteractiveVolumes) ; Combat TR-cmb-012 devient Covered (levée Gap G-5). |
| **Blocks** | Story-first-enemy (Enemy System) tant que ADR-0008 reste Proposed — sans layers Accepted, le lint pre-build ne peut pas gater les archetypes. Combat Sprint 1 **n'est pas bloqué** (Combat GDD Rule 12 a figé les valeurs inline — AC-CMB-09 teste `ShapeCast3D.collision_mask == 0b00010` statiquement ; l'ADR ne change pas ces valeurs, il les canonise). |
| **Ordering Note** | ADR-0008 est cohérent avec ADR-0011 Level Scene (Proposed) — si ADR-0011 est promu sans ADR-0008 Accepted, les lint pre-build Level (TR-lvl-007/008) afficheront un warning "layer reference unresolved" jusqu'à promotion ADR-0008. Recommandation : promouvoir ADR-0008 dans la même passe que ADR-0011. |

## Context

### Problem Statement

Cinq layers de collision sont déjà utilisées de facto par le projet sans ADR canonique :

- **Combat GDD r6 Rule 12** (2026-04-22) a gelé `0b00001` Player / `0b00010` Enemy / `0b00100` EnemyHitbox / `0b01000` Environment / `0b10000` Interactive directement dans le GDD et dans le registry (`docs/registry/architecture.yaml` §state_ownership l.337-402, owned-by Combat GDD).
- **Level System GDD r2** (2026-04-23) a aligné `LAYER_ENVIRONMENT = 4` (TR-lvl-007) et `LAYER_INTERACTIVE = 5` (TR-lvl-008) pour StaticBody3D et Area3D triggers respectivement, avec gate `collision_mask ⊃ LAYER_PLAYER` pour les Area3D.
- **Movement GDD** consomme implicitement `LAYER_ENVIRONMENT = 4` pour `$WallRayLeft` / `$WallRayRight` et `CharacterBody3D.move_and_slide()` wall detection.

Cette taxonomie est **cohérente sémantiquement** entre les trois GDDs mais **n'est dans aucun ADR**. G-5 (architecture-review 2026-04-23 §3.4) identifie ce gap comme bloqueur avant les epics Enemy / Hazard / Boss / Secret — ces GDDs ne peuvent pas être rédigés tant qu'un ADR n'a pas tranché **(a)** la liste canonique des layers, **(b)** le contrat mask par archetype, **(c)** la politique d'extension (ajout d'une 6e layer pour un système non encore conçu).

Sans ADR :

1. Le premier Enemy GDD choisira sa propre convention (bitmask hex vs. décimal, layer 6 ou layer 3-reuse) et contredira peut-être Combat / Level.
2. Le lint pre-build du Level System (TR-lvl-008) ne peut pas valider `monitoring=true` + `collision_mask ⊃ LAYER_PLAYER` sans référentiel stable.
3. Les masks de CharacterBody3D Player ne sont formalisés nulle part — le mask retenu (`0b11110` = 30, soit Enemy+EnemyHitbox+Environment+Interactive) vit dans une note inline Combat Section C.3 l.234.
4. La convention API (1-indexée `set_collision_layer_value(N)` vs. manipulation bitmask directe) reste ambiguë — Combat GDD utilise des commentaires bitmask (`0b00010`) alors que Level GDD r2 a explicitement corrigé pour utiliser `set_collision_layer_value(4)` 1-indexé (§AC-LVL-12 r2 fix).

### Constraints

- **Contraintes techniques** : Godot alloue 32 bits de layer / 32 bits de mask par `CollisionObject3D` (Project Settings → Layer Names → 3D Physics). Impossible de changer ces limites. Jolt (4.6 default) respecte la même API.
- **Contrainte de cohérence** : Combat GDD est Accepted (ADR-0006) et Level GDD est Draft Complete r2. Tout renumérotage des layers casse les AC-CMB-09 / AC-LVL-12 / AC-LVL-13 déjà écrits → l'ADR doit **ratifier** les 5 layers existantes, pas les réorganiser.
- **Contrainte d'authoring** : les stages Pre-Production (Level hand-crafted, Chrome Zen primitives) ont besoin d'un référentiel que les level designers et programmeurs peuvent lire sans plonger dans Combat GDD.
- **Contrainte de lint pre-build** : tout `CollisionObject3D` d'une `.tscn` devra pouvoir être validé sans ambiguïté contre la taxonomie (outil CI déjà envisagé Level GDD §R-5.5).

### Requirements

- Fige les 5 layers 1-indexées (Player, Enemy, EnemyHitbox, Environment, Interactive) par nom + bit + rôle + semantics solid/pass-through.
- Publie le contrat `(collision_layer, collision_mask)` pour chaque archetype gameplay (Player body, Katana ShapeCast, Enemy body, Enemy lethal hitbox, Environment static, Interactive trigger, Movement wall-ray).
- Canonise l'API d'accès : `set_collision_layer_value(N)` / `get_collision_mask_value(N)` 1-indexée mandatoire ; manipulation bitmask directe (`collision_layer = 0b...` ou `collision_layer = 8`) interdite sauf dans la configuration éditeur `.tscn`.
- Réserve un pool layer pour extensions post-MVP (systèmes non encore conçus : projectiles non-lethaux, pickups, particles-as-physics, AI nav volumes). Définit le protocole d'amendement ADR pour attribuer une nouvelle layer.
- Définit le gate de lint pre-build CI qui échoue la build si un `CollisionObject3D` du projet ne respecte pas la Decision Matrix.

## Decision

### D-1 — Taxonomie 5 layers gelée (ratification)

Les 5 layers 1-indexées suivantes sont canoniques au MVP et **ne peuvent pas être renumérotées**. Les bits parenthèses sont donnés à titre de référence — le code doit utiliser l'API 1-indexée (voir D-3).

| Layer (1-idx) | Nom canonique | Bit (0-idx) | Bitmask | Semantics | Archetypes concernés | Owner GDD |
|---|---|---|---|---|---|---|
| **1** | `LAYER_PLAYER` | 0 | `0b00001` = 1 | solid | Player `CharacterBody3D`, Katana `ShapeCast3D` (même layer que le corps du joueur) | Combat GDD Rule 12 |
| **2** | `LAYER_ENEMY` | 1 | `0b00010` = 2 | solid | Enemy `CharacterBody3D` body (walk, AI nav) — **non-lethal au contact** (la mort joueur passe par LAYER_ENEMY_HITBOX) | Combat GDD + futur Enemy GDD |
| **3** | `LAYER_ENEMY_HITBOX` | 2 | `0b00100` = 4 | pass-through (Area3D) | Hitboxes **létales** vers le joueur : laser beam, projectile, spike trigger, boss AoE, hazard environnemental (futur) | Combat GDD + futurs Enemy / Hazard / Boss GDDs |
| **4** | `LAYER_ENVIRONMENT` | 3 | `0b01000` = 8 | solid | Toute géométrie statique : sols, murs, rampes, plafonds, primitives Chrome Zen (StaticBody3D + ConcavePolygonShape3D) | Level GDD §R-5.5 |
| **5** | `LAYER_INTERACTIVE` | 4 | `0b10000` = 16 | pass-through (Area3D) | Triggers non-solides : `RoomTrigger`, `CheckpointVolume`, `SecretCollectVolume`, `EtageExit`, `WorldBoundsVolume` | Level GDD §InteractiveVolumes |

**Names doivent être présents dans `project.godot`** sous `[layer_names]/3d_physics/layer_N` exactement comme ci-dessus (section `[layer_names]` — Godot 4.x). Un diff de `project.godot` absent de ces 5 noms = build CI fail.

### D-2 — Decision Matrix des masks par archetype

Tout `CollisionObject3D` du projet doit tomber dans exactement un des archetypes ci-dessous. Les tuples `(collision_layer, collision_mask)` sont normatifs — toute déviation requiert amendement ADR.

| Archetype | Node type | `collision_layer` | `collision_mask` | Rationale |
|---|---|---|---|---|
| **Player body** | `CharacterBody3D` root | Layer 1 (Player) | Layers 2+3+4+5 = `0b11110` = 30 | Doit collisionner avec ennemis (navigation contact mais pas de dégât), subir les hitboxes létales (Rule 14 mort joueur), walker sur l'environnement, et déclencher les triggers Interactive. |
| **Katana swept hitbox** | `ShapeCast3D` child du Player | Layer 1 (même que le corps) | Layer 2 uniquement = `0b00010` = 2 | Combat Rule 12 : la hitbox ne touche que les corps ennemis. **Ne touche pas** Environment (un swing traverse un mur silencieusement sans kill — EC swing vers le sol) ni EnemyHitbox (pas de double-résolution katana ↔ laser). |
| **Movement wall-ray** | `ShapeCast3D` / `RayCast3D` child du Player | Aucune (non-monitorable) | Layer 4 uniquement = `0b01000` = 8 | Wall-run detection Movement — ne s'intéresse qu'aux walls Environment. |
| **Enemy body** | `CharacterBody3D` | Layer 2 (Enemy) | Layer 4 uniquement = `0b01000` = 8 | Navigation sur l'environnement. **Pas de mask LAYER_PLAYER** — la collision joueur↔ennemi est résolue par le mask joueur (Player a bit 2 dans son mask). **Pas de mask LAYER_ENEMY** — les ennemis ne collisionnent pas entre eux (évite train-wrecks MVP). |
| **Enemy lethal hitbox** | `Area3D` child de l'Enemy (laser emitter, projectile, AoE) | Layer 3 (EnemyHitbox) | Layer 1 uniquement = `0b00001` = 1 | Ne détecte que le joueur (Rule 14 signal `body_entered` → `Player.die()`). Jamais Environment (le laser ne "touche" pas un mur, il le traverse visuellement par design — le rendering est géré par VFX indépendamment). |
| **Static environment** | `StaticBody3D` | Layer 4 (Environment) | `0` = `0b00000` | Statique — ne détecte rien ; tout le monde le détecte via son propre mask (Player, Enemy, Movement ray). |
| **Interactive trigger** | `Area3D` (RoomTrigger, Checkpoint, Secret, EtageExit, WorldBounds) | Layer 5 (Interactive) | **Doit inclure Layer 1** (Player) `⊃ 0b00001` ; additionnels autorisés si le trigger doit détecter aussi les ennemis (ex : zone qui reset un ennemi tombé sous la map — Layer 2). Minimal MVP = `0b00001` = 1 | Level GDD §AC-LVL-13 r2 : sans bit 1, `body_entered` ne se déclenche jamais silencieusement. `monitoring=true`, `monitorable=false`. |

### D-3 — API 1-indexée obligatoire

**Required** :

```gdscript
# ✅ CORRECT
body.set_collision_layer_value(4, true)   # Layer 4 = Environment
area.set_collision_mask_value(1, true)    # Mask bit pour Layer 1 = Player
var hits_player: bool = area.get_collision_mask_value(1)
```

**Forbidden** dans tout code `.gd` :

```gdscript
# ❌ INTERDIT
body.collision_layer = 8              # bitmask direct (ambigu, fragile)
body.collision_layer = 0b01000        # bitmask littéral
body.collision_layer |= (1 << 3)      # bit manipulation
area.collision_mask = 30              # décimal direct
```

**Exception unique autorisée** : dans les fichiers `.tscn` / `.tres` (sérialisation scene), Godot stocke la valeur entière décimale. Ce n'est pas du code — c'est de la configuration éditeur. Aucune intervention manuelle n'est nécessaire : l'éditeur Godot écrit ces valeurs quand les cases sont cochées dans l'Inspector. Si un développeur édite un `.tscn` à la main, il doit vérifier contre D-1 que le décimal correspond au bon layer set.

**Cas spécial : `PhysicsRayQueryParameters3D` / `PhysicsShapeQueryParameters3D`**. Ces objets de query sont construits ad-hoc (pas des `CollisionObject3D`) et n'exposent que la propriété `collision_mask: int` — pas d'API per-bit. Pour rester cohérent avec D-3 sans autoriser le bitmask littéral, utiliser le helper canonique `CollisionLayers.build_mask([...])` (implémentation triviale) :

```gdscript
# src/core/collision_layers.gd — classe utilitaire (non-autoload, static-only)
class_name CollisionLayers
extends Object

const LAYER_PLAYER: int = 1
const LAYER_ENEMY: int = 2
const LAYER_ENEMY_HITBOX: int = 3
const LAYER_ENVIRONMENT: int = 4
const LAYER_INTERACTIVE: int = 5

static func build_mask(layers_1idx: Array[int]) -> int:
    var m: int = 0
    for layer: int in layers_1idx:
        assert(layer >= 1 and layer <= 32,
            "Layer doit être 1-indexée et ≤ 32")
        m |= 1 << (layer - 1)
    return m

# ✅ CORRECT — query params
var query := PhysicsShapeQueryParameters3D.new()
query.collision_mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENEMY])

# ❌ INTERDIT — bitmask littéral (failera lint D-6)
# query.collision_mask = 0b00010
# query.collision_mask = 2
```

Le lint D-6 passe car la RHS est un appel statique, pas un littéral `0b/0x/[0-9]`. Les `const LAYER_*` de `CollisionLayers` sont les **noms symboliques** recommandés en code GDScript ; ils sont synchronisés avec `project.godot [layer_names]` (D-4) et le registry (owned Combat GDD).

**Rationale** : la manipulation bitmask directe a déjà causé un bug dans Level GDD r1 (commentaire `bit 4 = layer 4` faux — Project Settings 1-indexe et bit 0-indexe, donc "Layer 4" = bit 3 = `1 << 3 = 8`). Corrigé r2 en forçant l'API idiomatique. Ce bug ne peut pas se reproduire avec `set_collision_layer_value(4, true)` ni avec `CollisionLayers.build_mask([LAYER_ENVIRONMENT])`.

### D-4 — `project.godot` layer names mandatory

Ajouter/ratifier dans `project.godot` (section `[layer_names]`) — si la section n'existe pas, la créer :

```
[layer_names]

3d_physics/layer_1="LAYER_PLAYER"
3d_physics/layer_2="LAYER_ENEMY"
3d_physics/layer_3="LAYER_ENEMY_HITBOX"
3d_physics/layer_4="LAYER_ENVIRONMENT"
3d_physics/layer_5="LAYER_INTERACTIVE"
```

Raisons :

1. L'Inspector Godot affiche le nom au lieu de "Layer 1/2/3..." (ergonomique pour level designer non-programmeur).
2. Le lint pre-build (D-6) peut parser `project.godot` pour vérifier présence + ordre canonique.
3. Constitue une source unique de vérité éditeur ↔ code.

### D-5 — Layers 6-32 réservées + protocole d'extension

Les layers 6 à 32 **ne sont pas utilisées au MVP** et **ne peuvent pas être utilisées sans amendement ADR**. Slot alloué par ordre FIFO :

- Layer 6 : **Reserved — Hazard environmental projectiles** (si futur Hazard GDD distingue projectiles des lethal-triggers statiques) — à valider par ADR futur quand Hazard GDD sera rédigé. Décision par défaut : réutiliser Layer 3 (EnemyHitbox) pour unifier "tout ce qui tue le joueur" → pas de Layer 6 sauf si le GDD Hazard identifie un besoin spécifique.
- Layer 7 : **Reserved — Pickups / credits** (si le Shop System introduit des pickup-globes au sol) — à valider par ADR Shop/Economy.
- Layer 8 : **Reserved — AI nav volumes** (si Enemy System utilise des `Area3D` pour path planning gates).
- Layer 9-32 : **Free** — aucune allocation prévue au MVP.

**Protocole d'amendement** pour attribuer une layer 6+ :

1. Le GDD demandeur ouvre un `/architecture-decision` dédié (amendement ADR-0008) ou un nouvel ADR héritier.
2. L'amendement doit :
   - Nommer la nouvelle layer (convention `LAYER_*` UPPER_SNAKE_CASE).
   - Définir son semantics (solid vs. pass-through).
   - Définir le mask contract pour tous les archetypes existants qui doivent la voir (update du Decision Matrix D-2 ci-dessus).
   - Mettre à jour `project.godot` `[layer_names]/3d_physics/layer_N`.
3. Si l'amendement réutilise une layer existante (1-5) plutôt qu'en ajouter une nouvelle, il doit justifier pourquoi l'archetype est sémantiquement identique (ex : un spike pit **est** un EnemyHitbox du point de vue de la résolution de collision — pas besoin d'une layer dédiée).

### D-6 — Lint pre-build CI (gating)

Un job CI `lint-collision-layers` doit être ajouté à `.github/workflows/tests.yml` (cf. `.claude/rules/no-alloc-hot-paths.md` et `.claude/rules/input-singleton-main-thread-only.md` pour le pattern). Le job échoue la build si :

1. Un fichier `.gd` sous `src/**` contient une affectation bitmask directe : regex `\bcollision_(layer|mask)\s*=\s*(0b[01]+|0x[0-9a-fA-F]+|[0-9]+)` → FAIL (D-3 violation).
2. Un fichier `.tscn` sous `scenes/**` contient un `CollisionObject3D` dont `collision_layer` ou `collision_mask` ne correspond pas à un des archetypes D-2 → WARN + manual review. (MVP : WARN seulement, car le parsing `.tscn` est non-trivial ; upgrade FAIL post-MVP.)
3. `project.godot` section `[layer_names]/3d_physics/layer_N` ne contient pas les 5 noms canoniques D-4 → FAIL.

Le lint s'exécute en < 2 s (grep + parser YAML de `project.godot`). Exception documentée : un commentaire `# lint-collision-layers-ok: <raison>` sur la ligne d'une affectation autorise l'exception avec justification tracée.

### Architecture Diagram

```
               ┌─────────────────────────┐
               │  Project Settings       │
               │  [layer_names]/3d_physics│
               │  layer_1..5 canoniques  │ ← D-4 source of truth éditeur
               └───────────┬─────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │   .tscn      │  │   .gd code   │  │   CI lint    │
  │ Inspector    │  │ API 1-idx    │  │ pre-build    │
  │ (éditeur)    │  │ set_..value  │  │ (D-6)        │
  └──────────────┘  └──────────────┘  └──────────────┘

  Archetypes (D-2) — contrat collision :

   Layer 1 Player ◄────── body_entered ── Layer 3 EnemyHitbox
   (CharacterBody3D)        (sole lethal)  (Area3D, mask=1)
       │ mask=2+3+4+5
       │
       ├─ mask bit 2 ─► Layer 2 Enemy body (solid, navigation)
       ├─ mask bit 3 ─► Layer 3 EnemyHitbox (lethal trigger)
       ├─ mask bit 4 ─► Layer 4 Environment (walk, wall-run)
       └─ mask bit 5 ─► Layer 5 Interactive (body_entered)

   Layer 1 Katana ShapeCast3D (mask=2) ──► Layer 2 Enemy (kill)

   Layer 2 Enemy body (mask=4) ──► Layer 4 Environment (AI nav only)

   Layer 4 Environment StaticBody3D (mask=0) — détecte rien, détecté par tout le monde
```

### Key Interfaces

```gdscript
# Pattern d'initialisation CollisionObject3D — archetype Player body
func _ready() -> void:
    set_collision_layer_value(1, true)  # LAYER_PLAYER
    # Reset autres bits pour être safe (idempotent)
    for i: int in range(2, 33):
        set_collision_layer_value(i, false)

    # Mask : Enemy + EnemyHitbox + Environment + Interactive
    set_collision_mask_value(2, true)   # LAYER_ENEMY
    set_collision_mask_value(3, true)   # LAYER_ENEMY_HITBOX
    set_collision_mask_value(4, true)   # LAYER_ENVIRONMENT
    set_collision_mask_value(5, true)   # LAYER_INTERACTIVE
    # Layers 1 et 6-32 : mask=false par défaut après les reset, pas besoin de toucher.
```

```gdscript
# Pattern d'assertion invariant — archetype Interactive trigger (Area3D)
func _ready() -> void:
    assert(get_collision_layer_value(5),
        "Interactive trigger doit déclarer Layer 5")
    assert(get_collision_mask_value(1),
        "Interactive trigger doit inclure LAYER_PLAYER dans son mask sinon body_entered silencieux")
    assert(monitoring == true and monitorable == false,
        "Area3D trigger : monitoring ON (détecte le player), monitorable OFF (n'est pas détecté)")
```

## Alternatives Considered

### Alternative 1 : Constants GDScript `const LAYER_PLAYER := 1` dans un singleton (autoload `Layers.gd`)

- **Description** : Un autoload `Layers.gd` expose `const LAYER_PLAYER := 1`, `const LAYER_ENEMY := 2`, etc. Le code fait `set_collision_layer_value(Layers.LAYER_PLAYER, true)`.
- **Pros** : Refactor-friendly (renommer un const propage partout) ; centralisation par fichier.
- **Cons** : Ajoute un autoload supplémentaire (coût boot + pollution namespace) pour 5 constantes entières triviales ; double la source de vérité avec `project.godot` → `[layer_names]` (risque de désynchro entre autoload et éditeur) ; l'éditeur Inspector n'affichera pas le nom canonique pour les CollisionObject3D créés via `.tscn` (seule solution : `project.godot [layer_names]`).
- **Rejection Reason** : `project.godot [layer_names]` est la source de vérité éditeur **non-contournable** — si on y ajoute les noms, l'autoload devient redondant. La duplication augmente le risque de drift sans bénéfice opérationnel (les level designers n'écrivent pas de GDScript). Préférons une unique source de vérité `.godot` + convention de code API 1-indexée (D-3).

### Alternative 2 : Encodage bitmask hex canonique (`const MASK_PLAYER_BODY := 0x1E`)

- **Description** : Définir les masks pré-calculés comme constants hexadécimales (`MASK_PLAYER_BODY = 0x1E` = Enemy+EnemyHitbox+Env+Interactive). Affectation directe `collision_mask = MASK_PLAYER_BODY`.
- **Pros** : Un seul write au boot (perf négligeable mais conceptuellement plus rapide que 4 `set_collision_mask_value` calls) ; mask entier lisible d'un coup.
- **Cons** : Ré-introduit la manipulation bitmask que D-3 interdit ; obscure pour quelqu'un qui lit `0x1E` sans table de correspondance ; la table de correspondance devient dépendance de lecture pour **tout** le code qui touche un mask ; les bugs historiques Level GDD r1 ("bit 4 = layer 4" faux) étaient exactement ce genre d'erreur d'off-by-one.
- **Rejection Reason** : Le gain perf est illusoire (init `_ready()` se fait une fois, pas en hot path). Le coût de lecture et de maintenance est réel et a déjà causé un bug documenté. `set_collision_mask_value(N, true)` est auto-explicatif et résistant aux erreurs d'indexation.

### Alternative 3 : Fusionner dans ADR-0011 Level Scene (décision unique)

- **Description** : Au lieu d'un ADR-0008 dédié, inclure la taxonomie layers comme §7 de ADR-0011 Level Scene Architecture (recommandation optionnelle §10.2 architecture-review 2026-04-23).
- **Pros** : Un ADR de moins ; cohérence spatiale (scene + layers lus ensemble).
- **Cons** : La taxonomie layers concerne **tous les systèmes** (Player, Combat, Enemy, Hazard, Boss), pas seulement Level. Cacher cette décision dans un ADR "Level Scene Architecture" rend la découverte par futurs GDDs non-évidente ("pourquoi chercherais-je le mask EnemyHitbox dans un ADR sur la hiérarchie des scènes Level ?"). L'ADR Dependencies deviendrait confus (Combat dépend de Level par l'intermédiaire d'une section transverse).
- **Rejection Reason** : Séparation des concerns. ADR-0008 est consommé par Combat (Rule 12), Level (TR-007/008), Movement (wall-ray mask), et tous futurs GDDs Enemy/Hazard/Boss. ADR-0011 est consommé principalement par Level-authored content. Les deux ADRs peuvent co-exister sans couplage circulaire.

## Consequences

### Positive

- G-5 (architecture-review 2026-04-23 §3.4) résolu : tous les GDDs futurs Enemy / Hazard / Boss / Secret ont un référentiel canonique pour déclarer leurs layer/mask.
- TR-cmb-012 passe de `covered_by: []` (Blocked Gap G-5) à `covered_by: [ADR-0008]` (Covered).
- TR-lvl-007 passe de "sous réserve ADR layers G-5" à Covered par ADR-0008 (en plus d'ADR-0001 déjà Covered).
- TR-lvl-008 passe de `covered_by: []` (Gap G-5) à `covered_by: [ADR-0008]` (Covered).
- Le bug Level GDD r1 "bit N = layer N" off-by-one (corrigé r2) ne peut plus se reproduire via D-3 (API 1-indexée obligatoire).
- L'Inspector Godot affiche les 5 noms canoniques (D-4) → level designers non-programmeurs peuvent cocher la bonne case sans lire le code.
- Le lint pre-build (D-6) devient un gate CI objectif : toute nouvelle scène est auto-validée.

### Negative

- Contrainte supplémentaire sur les futurs GDDs : chaque nouveau système physique doit déclarer son archetype **avant** ses stories (pas possible de prototyper un Hazard sans consulter D-2 ou déclencher un amendement ADR). → coût d'authoring low (5 min de lecture), haut bénéfice.
- Le lint pre-build (D-6) est du travail CI à écrire — estimé 1-2 h (grep + YAML parser trivial).
- Limite à 5 archetypes au MVP — tout 6e cas (ex : pickup gravity field) déclenche un amendement ADR (overhead procédural léger).

### Risks

- **Risk 1 — `project.godot` mal mis à jour** : un dev ajoute un `CollisionObject3D` en cochant une case par erreur dans l'Inspector (layer 6 par exemple) → lint D-6 flag (FAIL si `src/**` `.gd`, WARN si `.tscn` au MVP). **Mitigation** : upgrade du WARN .tscn en FAIL avant Sprint 1 Combat (story dédiée dans Sprint 1 DevOps).
- **Risk 2 — Reciprocity Enemy body ↔ Player body contre-intuitive** : le mask Enemy body exclut Layer 1 (Player), donc l'Enemy "ne voit pas" le Player en collision — la collision est résolue unilatéralement côté Player (Player.mask ⊃ Enemy). Un dev Enemy AI pourrait s'attendre à recevoir un `body_entered` Player côté Enemy et être surpris. **Mitigation** : commentaire explicite dans D-2 table + story Enemy AI doit référencer ADR-0008.
- **Risk 3 — Hazard GDD futur veut une Layer 6 dédiée au lieu de réutiliser Layer 3** : pas un risque mais une incertitude de design. **Mitigation** : D-5 permet l'amendement via ADR ; la décision par défaut "réutilise Layer 3 EnemyHitbox" est documentée comme point de départ.
- **Risk 4 — Jolt comportement divergent sur layers** : aucun connu (confirmé physics.md) mais Gap 2/8 ont révélé que Jolt peut surprendre sur détails physics (ShapeCast.margin ignoré). **Mitigation** : test GUT smoke `tests/unit/collision/layer_mask_contract_test.gd` qui spawn 1 Player + 1 Enemy + 1 EnemyHitbox + 1 Env + 1 Interactive et vérifie que chaque trigger/collision attendu se produit **réellement** sous Jolt 4.6 — gate avant Sprint 1 Combat.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/player-combat-system.md` | TR-cmb-012 (Rule 12) — Collision layer taxonomy 5 layers, katana ShapeCast layer=1/mask=2, Player body mask=3+4+5 | D-1 ratifie les 5 layers existantes ; D-2 ligne "Player body" et "Katana swept hitbox" publient les contracts exacts consommés par AC-CMB-09 et Combat C.3 l.234 |
| `design/gdd/level-system.md` | TR-lvl-007 (R-5.5) — Static geometry exclusivement Layer 4 LAYER_ENVIRONMENT, Movement lit via collision_mask | D-1 ligne Layer 4 + D-2 ligne "Static environment" (mask=0, layer=4) ; gate AC-LVL-12 r2 `set_collision_layer_value(4, true)` devient enforcement D-3 |
| `design/gdd/level-system.md` | TR-lvl-008 — Interactive triggers Area3D exclusivement Layer 5 LAYER_INTERACTIVE, signal-only, n'interfèrent pas avec physics player | D-1 ligne Layer 5 + D-2 ligne "Interactive trigger" incluant obligatoirement `get_collision_mask_value(1) == true` (gate AC-LVL-13 r2) ; `monitoring=true monitorable=false` formalisé en assertion |
| `design/gdd/player-movement-system.md` | Wall-run detection via `$WallRayLeft` / `$WallRayRight` sur surface verticale Environment (AC-MV-34) | D-2 ligne "Movement wall-ray" : mask=Layer 4 uniquement, layer=none (non-monitorable) — cohérent avec l'implémentation Movement implicite |

## Performance Implications

- **CPU** : Impact négligeable. `set_collision_layer_value(N, true)` est un bit-set inline Godot (< 1 μs). Appelé 5-10 fois au `_ready()` d'un `CollisionObject3D` (init one-shot) — aucun impact runtime. Jolt et GodotPhysics3D utilisent tous deux des bitmasks 32-bit sous le capot : le coût de test `(layer_A & mask_B) != 0` est identique.
- **Memory** : Aucun impact. Les layer/mask sont 2× `uint32` par `CollisionObject3D` (8 bytes) — coût fixe pré-existant, pas augmenté par l'ADR.
- **Load Time** : Aucun impact mesurable.
- **Network** : Non applicable (pas de multiplayer).
- **Build/CI** : Lint pre-build D-6 ajoute ~1-2 s au job `tests.yml` (grep sur `src/**/*.gd` + YAML parse sur `project.godot`). Acceptable.

## Migration Plan

Le projet est en Pre-Production sans code gameplay mergé (0 fichier `.gd` dans `src/` touchant des `CollisionObject3D`). **Aucune migration requise** — l'ADR prend effet dès Accepted pour toutes les futures stories.

Actions one-shot au moment de Sprint 0 (Technical Setup) :

1. **Mettre à jour `project.godot`** avec la section `[layer_names]/3d_physics/layer_1..5` canonique D-4.
2. **Créer le helper `src/core/collision_layers.gd`** (classe `CollisionLayers` avec les 5 constantes `LAYER_*` + `static func build_mask(Array[int]) -> int`) — cf. code D-3.
3. **Ajouter le job CI `lint-collision-layers`** à `.github/workflows/tests.yml`.
4. **Ajouter le smoke test GUT** `tests/unit/collision/layer_mask_contract_test.gd` (spawn 1 archetype de chaque, assert layer/mask).
5. **Ajouter la règle `.claude/rules/collision-layer-api-1-indexed.md`** (équivalent à `.claude/rules/no-alloc-hot-paths.md` pattern) décrivant D-3 forbidden patterns pour code review.

**GDD sync à faire lors de Sprint 1 Combat** : Combat GDD l.88 contient une illustration snippet `query.collision_mask = 0b00010 # Enemy layer uniquement (Rule 12)`. Lors de l'implémentation dans `src/gameplay/combat_system.gd`, le code réel doit utiliser le pattern canonique `query.collision_mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENEMY])`. La GDD peut rester avec le littéral (illustratif) OU être mise à jour en même temps que la story Combat en pointant vers ADR-0008. Recommandation : update GDD lors de la revue r7 pour prévenir copy-paste naïf.

Aucun fichier existant à éditer hors `project.godot` + CI workflow + `src/core/collision_layers.gd` (new).

## Validation Criteria

1. **VC-1 (D-1 ratification cohérente registry)** : `docs/registry/architecture.yaml` §state_ownership mentionne LAYER_PLAYER/ENEMY/ENEMY_HITBOX/ENVIRONMENT/INTERACTIVE (déjà présent l.337-402) ; après ADR-0008 Accepted, les `source:` de ces 5 entrées référencent `docs/architecture/adr-0008-collision-layer-taxonomy.md` en plus du GDD d'origine.
2. **VC-2 (D-3 API 1-indexée enforced)** : `grep -rE '\bcollision_(layer|mask)\s*=\s*(0b|0x|[0-9])' src/**/*.gd` retourne 0 résultat (hors commentaires). Lint CI green.
3. **VC-3 (D-4 project.godot canonical)** : `grep -E '^3d_physics/layer_[1-5]=' project.godot` retourne exactement 5 lignes avec les 5 noms canoniques D-4.
4. **VC-4 (D-2 Decision Matrix test GUT)** : `tests/unit/collision/layer_mask_contract_test.gd` passe — un test par archetype (7 archetypes = 7 tests), chaque test spawn le node, assert les bits attendus set/unset.
5. **VC-5 (D-6 lint pre-build actif)** : `.github/workflows/tests.yml` contient un job `lint-collision-layers` exécuté sur chaque PR.
6. **VC-6 (gate CombatSystem AC-CMB-09)** : au Sprint 1 Combat, le test AC-CMB-09 (assertion `ShapeCast3D.collision_mask == 0b00010`) passe — l'ADR ne change pas les valeurs attendues, VC-6 valide la cohérence.
7. **VC-7 (gate Level AC-LVL-12 + AC-LVL-13)** : aux stories Level correspondantes, les assertions `get_collision_layer_value(4) == true` (statique) et `get_collision_layer_value(5) == true` + `get_collision_mask_value(LAYER_PLAYER) == true` (triggers) passent sur toutes les scènes du MVP.

## Related Decisions

- **ADR-0001 Physics Rate 60 Hz + Jolt** (Accepted 2026-04-21) — prérequis upstream (engine physique choisi).
- **ADR-0005 Movement Signals Architecture** (Accepted 2026-04-22) — cohérent avec D-5 (amendement ADR pour nouvelles layers ~ amendement ADR pour nouveaux signals).
- **ADR-0006 Combat Tick Model** (Accepted 2026-04-23) — consommateur majeur via Rule 12 (TR-cmb-012). ADR-0008 ratifie sans changer les valeurs.
- **ADR-0007 Game State Manager** (Accepted 2026-04-23 r2) — indépendant, pas de couplage direct.
- **ADR-0011 Level System Scene Architecture** (Proposed) — consommateur Level ; ADR-0008 débloque les lint pre-build Level. Recommandation : promouvoir ADR-0008 et ADR-0011 en passe jointe (voir Ordering Note).
- `design/gdd/player-combat-system.md` Rule 12 + Section C.3 — source factuelle de la taxonomie.
- `design/gdd/level-system.md` §Collision Layers + R-5.5 + AC-LVL-12/13 — source factuelle côté Level.
- `docs/registry/architecture.yaml` §state_ownership l.337-402 — registry 5 layers déjà enregistrées owned-by Combat GDD.
- `.claude/rules/no-alloc-hot-paths.md` — pattern lint CI à dupliquer pour `collision-layer-api-1-indexed.md`.
