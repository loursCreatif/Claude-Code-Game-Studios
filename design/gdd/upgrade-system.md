# Upgrade System

> **Status**: Designed r1 — pending fresh `/design-review` (solo auto-approve `/design-system upgrade-system` 2026-04-27)
> **Author**: Martin + game-designer + systems-designer + qa-lead
> **Last Updated**: 2026-04-27
> **Implements Pillar**: Pillar 2 (LA PROGRESSION SE VOIT ET SE SENT) — primaire (l'upgrade est le moment où le crédit devient capacité physique permanente, vu directement dans le moveset). Pillar 1 (FLOW AVANT TOUT) — par soustraction (zéro UI propre, zéro friction runtime, capabilities lues comme champ booléen O(1)).
> **Quick reference** — Layer: `Progression / Infrastructure` · Priority: `MVP` · Key deps: `Shop System (Designed r1, calls apply_upgrade), Player Movement (Designed r3, reads capability flags), Save/Load System (Designed r1, locked load_string_array at boot — OQ-UPG-1 RESOLVED), Game State Manager (APPROVED r1, autoload order)`

---

## Overview

Upgrade System est l'**autorité canonique** sur l'état des capacités permanentes du joueur. C'est un autoload data-pure quasi-stateless qui expose trois booléens (`can_air_jump`, `can_dash`, `can_wall_run`) et une seule méthode mutante (`apply_upgrade(id: StringName) -> void`). Il vit entre **Shop System** (qui appelle `apply_upgrade(id)` à chaque achat réussi — R-SHP-6 étape 5c locked) et **Player Movement System** (qui lit les capability flags chaque tick depuis `_physics_process` — Movement Rules 3, 6, 7 locked). Upgrade ne calcule rien (les coûts sont owned par Credit Economy F-CRD-3), ne persiste rien activement (Shop écrit la clé `owned_upgrades` via Save/Load R-SHP-8), et ne notifie personne (Movement pull les flags, pas de signal). Au boot, Upgrade lit `SaveLoad.load_string_array("owned_upgrades", [])` et applique tous les upgrades chargés en une passe (boot hydration = série de `apply_upgrade` idempotents). Le mapping `id: StringName → capability flag` est owned par Upgrade et constitue son seul "catalogue" : MVP = `{&"double_jump" → can_air_jump, &"dash_horizontal" → can_dash}` ; Tier 2+ = `{&"wall_run_long" → can_wall_run}` (provisoire). `apply_upgrade(id)` est **SYNC idempotent** — un même id appelé deux fois produit le même état (no-op silencieux la deuxième fois). Le scope MVP couvre 2 upgrades binaires permanentes, zéro signal outbound, zéro UI, et zéro side-effect autre que la mutation des trois booléens.

---

## Player Fantasy

### B.1 — Le moment où l'achat devient capacité

L'Upgrade System est invisible. Le joueur n'interagit jamais avec lui — il ne sait même pas qu'il existe. Ce que le joueur vit, c'est : il quitte le shop avec son crédit dépensé, il rentre dans l'étage suivant, il saute, il appuie sur `jump` une seconde fois en l'air, et soudain **il monte au lieu de tomber**. L'upgrade n'est pas un buff de stat dans une fenêtre — c'est un changement physique du moveset, ressenti à la milliseconde où le doigt presse la touche. Le crédit n'est plus un nombre, c'est une nouvelle façon de toucher l'air.

C'est exactement la promesse du Pillar 2 : *LA PROGRESSION SE VOIT ET SE SENT*. Le système d'upgrade est l'organe qui matérialise cette promesse. Sans lui, le shop reste une vitrine ; avec lui, chaque achat rejaillit dans le contrôleur de mouvement à la frame suivante. La fantasy est la **continuité non-rompue** entre clic d'achat et nouvelle capacité — pas de cinématique, pas d'écran de chargement explicatif, pas de "votre nouvelle compétence" pop-up. Tu cliques, tu sors du shop, tu sautes, tu re-sautes, et tu sais.

### B.2 — Pacte avec le Movement System

Upgrade est un fournisseur silencieux pour Movement. Movement vit son cycle `_physics_process` à 60 Hz et, quand il évalue la branche "double-jump possible ?", il lit `Upgrade.can_air_jump`. La lecture est `O(1)`, sans signal, sans event, sans handshake. Cette discipline sert Pillar 1 : aucune latence ajoutée par la couche progression. Si Upgrade émettait un signal `capability_unlocked`, Movement devrait s'y connecter et y réagir — un point de friction qui devient un bug à 60 Hz × 8 capabilities. Ici, Movement se contente de poller — invariant simple, testable, sans race condition possible.

Le pacte tient une seule règle : **Upgrade n'appelle jamais Movement**. Movement ignore que Upgrade existe au niveau classe (il lit une propriété autoload comme il lirait `Engine.time_scale`). Cette unidirectionnalité préserve la possibilité de remplacer Upgrade par n'importe quel mock en test (`tests/helpers/mock_upgrade.gd` peut juste exposer `var can_air_jump: bool = true` sans implémenter quoi que ce soit d'autre).

### B.3 — Anti-fantasy : ce que l'Upgrade System ne doit PAS être

- **NOT un skill tree** : pas d'arbre de talents, pas de prérequis croisés, pas de respec, pas de point de spécialisation. Chaque upgrade est binaire (owned/not_owned), permanent, et indépendant des autres. Les anti-piliers du game-concept l'imposent.
- **NOT un système de classes** : pas de "build" guerrier vs assassin. Le moveset est un seul, l'upgrade ajoute des capacités sans en retirer. Pas de trade-off, pas de mutualité exclusive.
- **NOT un système de stats numériques** : `can_dash` est `bool`, pas un float multiplier. La portée d'un dash, sa cooldown, sa vitesse — tout cela est figé par Movement (Tuning Knobs Movement). Upgrade ne tune jamais une valeur — il flip un booléen.
- **NOT un fournisseur d'UI** : zéro icône, zéro menu de capacités, zéro "Compétences débloquées". Le HUD ne matérialise pas les capabilities possédées (le joueur les sent dans ses doigts). Le Shop renders ses cartes OWNED indépendamment via `_owned_upgrades` (Shop GDD R-SHP-9). Upgrade n'a pas de surface visuelle.

Anti-référence : tous les jeux RPG-lite avec arbres de skills, branches, prérequis (Path of Exile, Diablo skill trees, Cyberpunk perks). Référence directe : *Hollow Knight* charm system (binaire owned/not_owned, permanent, effet immédiat, zéro friction). *Ghostrunner* upgrade unlocks (le crédit devient mouvement, sans mise en scène).

---

## Detailed Rules

### C.1 — Architecture

#### ⚠️ DESIGN DECISION — Autoload vs Node-local

**Décision : AUTOLOAD** (`UpgradeSystem`, attaché à `src/gameplay/upgrade/upgrade_system.gd`).

Rationale : Movement lit les capability flags en pull à 60 Hz depuis `_physics_process` — il faut un point d'accès stable, scene-agnostic, présent dès le boot avant tout Player. Shop appelle `apply_upgrade(id)` pendant la scène shop transitoire qui est déchargée à chaque transition shop→level : Upgrade doit survivre à cette transition. Boot hydration via `SaveLoad.load_string_array` impose `_ready()` autoload (exécuté une seule fois, avant toute scène gameplay). Un Node-local serait désinstancié à chaque changement de scène — incompatible avec tous ces contrats.

**Fichier source :** `src/gameplay/upgrade/upgrade_system.gd`

#### ⚠️ DESIGN DECISION — Représentation des capability flags

**Décision : trois `var` booléens publics typés statiquement.**

Rationale : Movement lit `Upgrade.can_air_jump` comme une propriété directe — typage statique GDScript, lecture compile-time vérifiée, O(1) sans lookup de clé. Un `Dictionary[StringName, bool]` forcerait chaque consumer à connaître les StringName exacts des clés (couplage fragile). MVP = 3 capabilities ; Tier 2+ = +5 `var` supplémentaires (toujours O(1), toujours type-safe). Migration vers Dictionary envisageable uniquement si N > 12 capabilities (OQ Tier 3+).

#### Variables membres

```gdscript
# --- Capability flags publics (lus en pull par Movement à 60 Hz) ---
var can_air_jump: bool = false
var can_dash: bool = false
var can_wall_run: bool = false

# --- État interne ---
var _owned: Dictionary = {}   # {StringName: bool} — set-like, clé=id, valeur=true

# --- Catalogue immuable MVP ---
const _CATALOG: Dictionary = {
    &"double_jump":       &"can_air_jump",
    &"dash_horizontal":   &"can_dash",
    # Tier 2+: &"wall_run_long": &"can_wall_run"
}

# --- Flag debug/test ---
var _boot_complete: bool = false
```

---

### C.2 — API publique

Toutes les méthodes ci-dessous sont les seules méthodes publiques exposées. Aucune autre méthode mutante n'est permise au MVP.

```gdscript
## Applique un upgrade identifié par [param id].
## SYNC — aucun await ni yield.
## Idempotent — appeler deux fois avec le même [param id] produit le même état.
## Si [param id] est inconnu dans _CATALOG, émet push_warning et retourne immédiatement.
## Si [param id] est déjà possédé (_owned), retourne immédiatement (no-op silencieux).
func apply_upgrade(id: StringName) -> void

## Retourne true si [param id] est possédé, false sinon.
## Lecture pure — aucun side-effect. Usage : tests et debug.
func is_owned(id: StringName) -> bool

## Retourne le nombre total d'upgrades possédés.
## Usage : tests et debug uniquement (pas d'usage runtime gameplay).
func get_owned_count() -> int
```

**Méthodes absentes par décision :** `revoke_upgrade` (pas de respec MVP — R-UPG-12), `get_capabilities` (Movement lit directement les `var` publiques), tout getter UI (Shop et HUD sont autonomes).

---

### C.3 — Core Rules

**R-UPG-1** — `UpgradeSystem` est un autoload GDScript (`src/gameplay/upgrade/upgrade_system.gd`). Il est instancié au boot avant toute scène et survit à toutes les transitions de scène. Il n'est jamais détaché ni réinstancié pendant une session de jeu.

**R-UPG-2** — L'état des capabilities est représenté par trois booléens publics typés statiquement : `can_air_jump: bool`, `can_dash: bool`, `can_wall_run: bool`. Tous démarrent à `false`. Ce sont les seules propriétés publiques liées aux capabilities — aucun getter intermédiaire, aucun Dictionary exposé.

**R-UPG-3** — Le catalogue `id → capability flag` est owned exclusivement par `UpgradeSystem`, défini comme constante interne `_CATALOG: Dictionary`. MVP : `{&"double_jump" → &"can_air_jump", &"dash_horizontal" → &"can_dash"}`. Shop maintient son propre catalogue de prix et labels côté UI. Le seul contrat partagé entre Shop et Upgrade est le `id: StringName` — les deux tables référencent le même identifiant sans se connaître mutuellement. Toute modification du mapping nécessite un ADR (changement structurel inter-système).

**R-UPG-4** — `apply_upgrade(id: StringName) -> void` est SYNC et idempotent. Séquence d'exécution dans le même call stack, sans `await` ni `yield` :
1. Valider que `id` existe dans `_CATALOG` → sinon `push_warning("UpgradeSystem: id inconnu '%s'" % id)` + `return`.
2. Vérifier `_owned.has(id)` → si vrai, `return` (no-op silencieux).
3. `_owned[id] = true`.
4. Obtenir le nom du flag via `_CATALOG[id]` → `set(flag_name, true)`.

Cette séquence garantit l'idempotence et l'atomicité : le call stack de Shop (Shop r1 R-SHP-6, étape 5c) reste synchrone du `try_spend()` jusqu'au retour de `apply_upgrade`.

**R-UPG-5** — Boot hydration dans `_ready()` autoload :
1. `var owned: Array = SaveLoad.load_string_array("owned_upgrades", [])`.
2. Pour chaque `id` dans `owned` : `apply_upgrade(id)` (idempotent — un id inconnu produit un warning silencieux, jamais un crash).
3. `_boot_complete = true`.

Cette hydration s'exécute avant que GSM `start_etage()` soit jamais appelé et avant qu'aucun Player soit instancié. Les capability flags sont prêts dès le premier `_physics_process` de Movement.

**R-UPG-6** — Zéro signal outbound. `UpgradeSystem` n'émet aucun signal (`capability_unlocked`, `upgrade_applied` ou autre). Movement poll les capability flags directement dans `_physics_process` — la mutation d'un booléen est instantanée et visible au prochain tick sans aucune notification. Un signal créerait un risque de race condition sur l'ordre de connexion et une dépendance inutile.

**R-UPG-7** — Le defer-apply décrit par EC-SHP-17 (Shop r1) est résolu trivialement par le pull pattern. Si Shop appelle `apply_upgrade(id)` alors qu'aucun Player n'est instancié (ex. : shop chargé depuis MENU Tier 2+), Upgrade flippe le flag booléen immédiatement. Au prochain `Player._ready()` (post-`request_scene_transition` GSM ADR-0007 D-5), Movement lit la valeur déjà flippée depuis son premier `_physics_process`. Aucune queue, aucun retry, aucune logique de defer explicite dans Upgrade.

**R-UPG-8** — Movement est un consumer pull-only. Il lit `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run` directement dans `_physics_process` à chaque tick (Movement Rules 3, 6, 7). Movement n'appelle jamais `apply_upgrade` ni aucune autre méthode mutante d'Upgrade. Upgrade n'a aucune référence à Movement. Ergonomie test : un mock `UpgradeSystem` n'a besoin que d'exposer les trois `var` booléens publics — `apply_upgrade` peut être un stub vide.

**R-UPG-9** — Un `id` inconnu dans `_CATALOG` produit un `push_warning` et un `return` immédiat, sans crash, sans état corrompu. Ce comportement assure la forward-compatibility (EC-SHP-8 Shop r1) : un save file contenant des ids Tier 2+ chargé dans une build MVP produira des warnings en console mais ne cassera pas la session.

**R-UPG-10** — `UpgradeSystem` ne persiste jamais. Il ne contient aucun appel à `SaveLoad.save_*`. Shop écrit la clé `"owned_upgrades"` (Array[StringName]) via `SaveLoad.save_string_array` (Shop r1 R-SHP-8). Upgrade lit cette clé une seule fois au boot. Si Upgrade écrivait la save, deux writers sur la même clé créeraient des conflits d'ordre non déterministe.

**R-UPG-11** — Ordre des autoloads dans `project.godot` : `InputManager → GameStateManager → SaveLoadSystem → AudioSystem → UpgradeSystem` (extension de l'ordre canonique ADR-0007 D-1, figé par Save/Load r1 R-SAV-1). Upgrade est positionné **après** `SaveLoadSystem` (consumer de `load_string_array` dans `_ready()` — contrainte stricte) et **après** `AudioSystem` (alignement Foundation, pas de dépendance MVP). L'ordre relatif Upgrade ↔ GSM n'a pas d'impact runtime : tous les autoloads `_ready()` s'exécutent séquentiellement avant le démarrage de toute scène (Movement, Shop, etc.), donc les capability flags sont prêts dès le premier `_physics_process` de Movement, indépendamment de l'ordre Upgrade ↔ GSM. La seule contrainte stricte est : `SaveLoadSystem._ready()` < `UpgradeSystem._ready()`.

**R-UPG-12** — Pas de `revoke_upgrade` au MVP. L'état possédé est binaire et permanent : une fois `_owned[id] = true` et le flag flippé, ils ne reviennent pas à `false` pendant une session. Pas de respec, pas de trade, pas d'expiration. Cette règle applique l'anti-pilier « pas de skill tree » et simplifie le contrat avec Save/Load (Array append-only).

**R-UPG-13** — Les capability flags sont indépendants. Aucune règle de dépendance croisée entre `can_air_jump`, `can_dash`, et `can_wall_run`. Posséder `dash_horizontal` n'est pas un prérequis pour `wall_run_long`. Shop peut imposer des gates de prix séquentiels (catalogue Shop), mais Upgrade ignore ces règles — `apply_upgrade(&"wall_run_long")` est valide indépendamment de l'état des autres flags.

**R-UPG-14** — Upgrade ignore le coût (Credit System owns la formule F-CRD-3), ignore la persistance write (Shop + SaveLoad owns), et ignore l'UI (Shop affiche les cartes OWNED via `_owned_upgrades`, HUD System affiche les capacités actives indépendamment). Upgrade reçoit une commande (`apply_upgrade`) et expose un état (`can_*`). C'est son scope complet.

---

### C.4 — States and Transitions

`UpgradeSystem` a un cycle de vie minimal à deux états. Il n'y a pas de cycle par upgrade — chaque upgrade est un flip binaire sans état intermédiaire.

| État | Condition d'entrée | Propriétés | Transitions sortantes |
|---|---|---|---|
| `BOOTING` | Instanciation autoload (`_ready()` appelé) | `_boot_complete = false`, tous les flags à `false` | → `READY` après fin de la boucle de hydration SaveLoad |
| `READY` | `_boot_complete = true` (fin de `_ready()`) | Flags hydratés selon save ; `apply_upgrade` opérationnel | Stable pour la durée de la session ; aucune transition sortante |

Note : `_boot_complete` est exposé en tant que propriété publique uniquement pour les tests d'intégration (vérification que l'hydration est terminée avant les assertions). Il n'a aucun usage gameplay.

---

### C.5 — Interactions with Other Systems

| Système | Direction | Interface | Contrat verrouillé ? | Tier | Notes |
|---|---|---|---|---|---|
| **Shop System** | In | `apply_upgrade(id: StringName) -> void` — appelé SYNC à l'étape 5c du cycle d'achat | Verrouillé (Shop r1 R-SHP-6) | MVP | Shop appelle dans le même call stack que `try_spend()`. Aucun `await` entre les deux. Shop écrit `"owned_upgrades"` via SaveLoad — Upgrade ne l'écrit jamais. |
| **Player Movement System** | Out | `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run` — lus en pull à 60 Hz dans `_physics_process` | Verrouillé (Movement r3 Rules 3, 6, 7) | MVP | Movement ne connaît pas `apply_upgrade`. Upgrade ne connaît pas Movement. Pull pur, zéro signal, zéro handshake. |
| **Save/Load System** | In (boot only) | `SaveLoad.load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` — appelé une seule fois dans `_ready()` avec `key="owned_upgrades"`, `default=[]` | ✅ Verrouillé par Save/Load r1 R-SAV-4 (OQ-UPG-1 RESOLVED) | MVP | Upgrade ne persiste jamais. Default `[]` = première session, tous les flags restent `false`. Format de la valeur stockée : `Array[StringName]`. |
| **Game State Manager** | Indirect (ordre autoload) | Aucun appel direct ; dépendance d'ordre dans `project.godot` | APPROVED r1 | MVP | Upgrade doit être listé avant GSM dans `project.godot` pour garantir que `_boot_complete = true` avant `GSM.start_etage()`. Pas de coordination runtime. |
| **HUD System** | None (MVP) | Pas d'interface directe | N/A | Tier 2+ | HUD peut lire les flags directement (`Upgrade.can_dash`) pour afficher des indicateurs de capacité. Aucun signal à consommer. |
| **Credit Economy System** | None | Upgrade ignore complètement les coûts | N/A | — | Le coût en crédits est owned par Credit System (F-CRD-3) et validé par Shop. Upgrade reçoit uniquement la commande d'application post-validation. |
| **Audio / VFX Systems** | None (MVP) | Pas d'interface directe | N/A | Tier 2+ | Si un feedback sonore ou visuel est ajouté à l'unlock, le consumer (Audio/VFX) se connecte en lisant les flags depuis `_physics_process`, sans signal depuis Upgrade. |

## Formulas

`UpgradeSystem` est un système data-pure. Il ne calcule rien activement — il maintient un état booléen et délègue toutes les formules à d'autres GDDs. Les "formules" listées ici sont en majorité des **délégations explicites** (cross-refs vers les owners) et un seul invariant interne (sanity sur le catalogue).

---

### F-UPG-1 — Cost lookup (DÉLÉGATION owned par Credit Economy F-CRD-3)

`UpgradeSystem` ne calcule jamais le coût d'un upgrade. Le coût est calculé exclusivement par Credit Economy via la courbe linéaire F-CRD-3 :

`cost_n = BASE_UPGRADE_COST + n × TIER_COST_STEP`

**Variables** (référence — pas redéfinies ici) :

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `BASE_UPGRADE_COST` | B | `int` | 20 (registry, owned Credit) | Coût de l'upgrade à `n=0`. Lu depuis registry. |
| `TIER_COST_STEP` | S | `int` | 20 (registry, owned Credit) | Incrément linéaire par rang. Lu depuis registry. |
| `n` | n | `int` | `[0, MAX_UPGRADE_INDEX]` | Index zero-based dans le catalogue Shop trié par prix croissant. |

**Output** : `int` ∈ `[20, 40]` cr MVP ; `[20, 160]` cr Tier 2+ (8 upgrades).

**Consumer side (Shop)** : Shop F-SHP-1 délègue à F-CRD-3 pour render les BuyButtons. **Consumer side (Upgrade)** : ZÉRO. Upgrade reçoit `apply_upgrade(id)` post-validation économique — il ne connaît même pas le coût payé.

**Exemple** : à l'achat de `&"dash_horizontal"` (n=1) au shop, Shop calcule `cost = 20 + 1 × 20 = 40 cr`, valide via `try_spend(40)`, persiste, puis appelle `Upgrade.apply_upgrade(&"dash_horizontal")`. Upgrade voit uniquement le `id` — le `40` n'est jamais transmis.

---

### F-UPG-2 — Boot hydration sequence (INVARIANT D'ORDRE)

Le boot d'Upgrade applique tous les upgrades possédés en une seule passe. La séquence est strictement ordonnée :

```
hydrate_at_boot():
    owned_array = SaveLoad.load_string_array("owned_upgrades", [])
    for id in owned_array:
        apply_upgrade(id)        # idempotent — tolère les ids inconnus
    _boot_complete = true
```

**Invariants** :

1. `apply_upgrade` est appelé **N fois** où N = `owned_array.size()` ; chaque appel est `O(1)` (lookup `_CATALOG` + set `var`).
2. Coût total : `O(N)` — borné par le nombre d'upgrades MVP (max 2) ou Tier 2+ (max 8). Aucune contrainte de performance même au pire cas.
3. **Ordre indifférent** : R-UPG-13 garantit l'indépendance des capabilities — ré-ordonner `owned_array` produit le même état final.
4. **Idempotence préservée** : un même `id` présent deux fois dans `owned_array` (pathologique, ne devrait jamais arriver via Shop) produit un seul flag flip. Le second `apply_upgrade(id)` early-return via `_owned.has(id)` (R-UPG-4 step 2).

**Exemple** : save contenant `[&"double_jump", &"dash_horizontal"]` au boot → `can_air_jump = true` puis `can_dash = true`. `_boot_complete = true`. Movement spawné ensuite lit les deux flags à `true` au premier `_physics_process`.

---

### F-UPG-3 — Catalog sanity invariant (DESIGN GUIDELINE — non-runtime)

Validation statique du catalogue à l'authoring-time, pas une formule runtime. Garantit que le catalogue Upgrade et le catalogue Shop sont alignés sur les mêmes `id`.

```
∀ id ∈ Shop._CATALOG : id ∈ Upgrade._CATALOG
∀ id ∈ Upgrade._CATALOG : ∃ flag_name ∈ {"can_air_jump", "can_dash", "can_wall_run", ...}
                          tel que UpgradeSystem.has_property(flag_name) == true
```

**Variables** :

| Variable | Type | Description |
|----------|------|-------------|
| `Shop._CATALOG` | `Array[Dictionary]` | Catalogue Shop (id, label, price). Owned Shop. |
| `Upgrade._CATALOG` | `const Dictionary` | Mapping id → flag_name. Owned Upgrade. |
| `flag_name` | `StringName` | Nom du `var` capability publique sur `UpgradeSystem`. |

**Vérification** : test GUT au build-time (`tests/integration/upgrade/catalog_sanity_test.gd`) qui itère les deux catalogues et `assert` la cohérence. Toute désynchronisation = test failure → CI block. Si Shop ajoute `&"new_upgrade"` sans qu'Upgrade ajoute le mapping, le test échoue avant merge.

**MVP état attendu** :
- `Shop._CATALOG.size() == 2` (`double_jump`, `dash_horizontal`)
- `Upgrade._CATALOG.size() == 2`, mêmes ids
- `Upgrade._CATALOG[&"double_jump"] == &"can_air_jump"` et propriété `can_air_jump` existe.
- `Upgrade._CATALOG[&"dash_horizontal"] == &"can_dash"` et propriété `can_dash` existe.

---

### F-UPG-4 — Tier 2+ catalog growth (DEFERRED)

Au Tier 2+ (Vertical Slice / Full Vision), le catalogue passe de 2 à 8 upgrades. Le mapping `_CATALOG` s'étend :

```gdscript
const _CATALOG_TIER_2: Dictionary = {
    &"double_jump":       &"can_air_jump",
    &"dash_horizontal":   &"can_dash",
    &"wall_run_long":     &"can_wall_run",       # +1 capability flag
    &"triple_jump":       &"can_triple_jump",    # +1 var membre
    &"dash_vertical":     &"can_dash_vertical",  # +1
    &"slow_mo_aerial":    &"can_slow_mo_aerial", # +1 (système séparé Movement r3 Rule 10)
    &"katana_extended":   &"can_katana_extended",# +1 (Combat dependency)
    &"secret_radar":      &"can_secret_radar",   # +1 (Secret dependency Tier 2+)
}
```

Conditions de promotion :
- Chaque nouveau `id` Tier 2+ doit être validé par F-UPG-3 (catalog sanity test).
- Chaque nouveau flag doit être déclaré comme `var public: bool = false` sur `UpgradeSystem`.
- Movement / Combat / Secret doivent être amendés pour lire le nouveau flag (downstream contracts).
- Aucun changement à l'API publique `apply_upgrade` — toujours `(id: StringName) -> void`.

Migration recommandée si N > 12 capabilities : remplacer les `var` publics par `Dictionary[StringName, bool]` + getter `is_capability_enabled(id)`. Documenté en OQ-UPG (Section K).

## Edge Cases

### Catégorie A — Autoload order et boot

**EC-UPG-1 — SaveLoad absent au boot** : SI `project.godot` charge `UpgradeSystem` avant `SaveLoadSystem` ALORS `_ready()` appelle un autoload inexistant et crash. Résolution : l'ordre canonique ADR-0007 D-1 étendu par R-UPG-11 (`InputManager → GSM → SaveLoadSystem → AudioSystem → UpgradeSystem`) est enforced par `project.godot` ; un test GUT boot-order valide la séquence au build.

**EC-UPG-2 — GSM appelle `start_etage()` avant hydration complète** : SI `GameStateManager._ready()` s'exécute et déclenche immédiatement une transition de scène ALORS `UpgradeSystem._ready()` peut ne pas encore avoir itéré le save. Résolution : autoload order garantit que `UpgradeSystem._ready()` est terminé avant que GSM s'exécute (Godot 4.6 initialise les autoloads séquentiellement dans l'ordre déclaré). Aucune guard `_boot_complete` requise au MVP.

**EC-UPG-3 — `load_string_array` retourne un type inattendu** : SI la save est corrompue et que `SaveLoad.load_string_array("owned_upgrades", [])` retourne autre chose qu'un `Array` (ex. `null`, `int`) ALORS `_ready()` doit détecter le type via `is Array` et tomber en fallback `[]` silencieusement avec `push_warning`. Rationale : évite un crash GDScript sur `.size()` ou l'itération d'un non-Array.

**EC-UPG-4 — Première session, save absente** : SI aucune save n'existe ALORS `load_string_array("owned_upgrades", [])` retourne le default `[]`. Upgrade itère zéro fois, les trois booléens restent `false`. Comportement attendu et propre ; aucun traitement spécial requis.

**EC-UPG-5 — Hot-reload Godot editor pendant runtime** : SI l'éditeur Godot reload les scripts pendant le play-in-editor ALORS l'autoload est réinstancié et `_ready()` relance la boot hydration depuis la save. Les booléens sont remis à `false` puis re-hydratés. Comportement attendu ; le pull-pattern Movement (R-UPG-7, R-UPG-8) absorbe le bref flash `false` au tick du reload.

---

### Catégorie B — `apply_upgrade` — Validation d'id

**EC-UPG-6 — Id inconnu (Tier 2+ ou migration)** : SI `apply_upgrade(id)` reçoit un `id` absent de `_CATALOG` ALORS R-UPG-9 s'applique : `push_warning("UpgradeSystem: unknown upgrade id '%s'" % id)` + early return. Aucun état muté. Cohérent avec EC-SHP-8 (Shop r1).

**EC-UPG-7 — Id `null` ou `StringName` vide** : SI `id == &""` ou que GDScript passe `null` casté en `StringName` ALORS `_CATALOG.has(id)` retourne `false`, R-UPG-9 déclenche le warning et early return. Aucune guard supplémentaire nécessaire car `_CATALOG.has` est null-safe pour StringName.

**EC-UPG-8 — Id avec caractères non-ASCII** : SI un id contient des accents ou caractères Unicode (ex. `&"montée"`) ALORS Godot 4.6 `StringName` accepte UTF-8 arbitraire ; le catalog lookup est exact-match case-sensitive. L'id ne correspondra à rien dans `_CATALOG` MVP → R-UPG-9 warning + skip. Pas de traitement spécial requis.

**EC-UPG-9 — `_CATALOG[id]` mappé sur un `flag_name` inexistant comme propriété** : SI une erreur de saisie dans `_CATALOG` produit `flag_name = &"can_fli"` (typo) ALORS `set(flag_name, true)` en GDScript sur un autoload sans cette propriété retourne `false` silencieusement (no-op). Résolution : F-UPG-3 catalog sanity invariant (test GUT au build) vérifie que chaque `flag_name` dans `_CATALOG` existe bien comme `var` publique déclarée. Bloque le build si le catalog est malformé.

**EC-UPG-10 — Flag name est une méthode ou une constante, pas une var** : SI `flag_name` pointe sur une constante (`const CAN_DASH = false`) ou une méthode ALORS `set(flag_name, true)` est no-op en GDScript 4. Résolution : F-UPG-3 GUT invariant vérifie que chaque entrée catalog pointe sur une propriété mutable (`get_property_list()` inclut les vars).

---

### Catégorie C — Idempotence et état

**EC-UPG-11 — Double-appel rapide par Shop (double-click)** : SI Shop appelle `apply_upgrade(&"double_jump")` deux fois dans le même frame (bug double-click malgré R-SHP-7) ALORS le premier appel set `_owned[&"double_jump"] = true` + `can_air_jump = true`. Le second appel vérifie `_owned.has(id)` → true → early return sans remutation. Idempotence garantie (R-UPG-4).

**EC-UPG-12 — Id déjà owned via boot hydration, réapplication par Shop** : SI la save contient déjà `&"dash_horizontal"` et que le Shop (post-bug ou test) réappelle `apply_upgrade(&"dash_horizontal")` ALORS `_owned.has(id)` → true → early return. Aucun effet de bord. Comportement attendu.

**EC-UPG-13 — Mutation externe directe d'un booléen public** : SI du code de test ou un mod fait `UpgradeSystem.can_dash = false` directement ALORS `_owned[&"dash_horizontal"]` reste `true` mais le flag est `false` : état interne désynchronisé. Résolution : GDScript 4 ne permet pas de setter privé sur les `var` simples au MVP. L'état sera re-synchronisé au prochain `apply_upgrade` ou au prochain boot. Admis Tier 1 solo ; un setter avec guard peut être ajouté en Tier 2 si nécessaire.

**EC-UPG-14 — `_owned[id] = true` mais flag = false (désynchronisation résiduelle)** : SI un crash ou mutation externe laisse `_owned` et le booléen désynchronisés ALORS `apply_upgrade(id)` vérifie `_owned.has(id)` → early return → le flag reste `false`. Résolution : l'idempotence guard doit vérifier `not _owned.has(id) OR not get(flag_name)` pour forcer la re-synchronisation. Rationale : priorité à la cohérence flag = vérité de gameplay.

---

### Catégorie D — Boot hydration et save corrompue

**EC-UPG-15 — Éléments non-StringName dans la save** : SI la save contient `[&"double_jump", 42, null, "dash_horizontal"]` ALORS `apply_upgrade(42)` reçoit un int casté en StringName → `_CATALOG.has(…)` → false → R-UPG-9 warning + skip. Chaque élément est traité indépendamment ; les ids valides sont appliqués normalement. Cohérent avec EC-SHP-7 (Shop r1).

**EC-UPG-16 — Ids dupliqués dans la save** : SI la save contient `[&"double_jump", &"double_jump"]` ALORS le premier appel applique l'upgrade, le second passe par `_owned.has(id)` → early return. Les deux itérations terminent sans erreur. Idempotence (R-UPG-4) absorbe nativement.

**EC-UPG-17 — Ids Tier 2+ inconnus en build MVP** : SI une save d'une session Tier 2+ est chargée dans un build MVP ALORS tous les ids inconnus déclenchent R-UPG-9 (warning + skip). Les ids MVP connus sont appliqués normalement. La save n'est pas réécrite par Upgrade (R-UPG-10) ; les ids Tier 2+ sont préservés en save pour la prochaine session Tier 2+.

**EC-UPG-18 — Save vide, première session** : Cas nominal — voir EC-UPG-4. Les trois booléens restent `false` ; aucun warning.

**EC-UPG-19 — Catalog renommé entre versions (`&"double_jump"` → `&"air_jump"`)** : SI une migration de nommage change les ids catalog ALORS les saves anciennes contiennent `&"double_jump"` que le nouveau build ne reconnaît plus → R-UPG-9 warning + skip → upgrade perdu à runtime. Résolution : la migration est hors scope MVP. Un outil de migration save dédié sera requis en Tier 2 avant tout renommage de `_CATALOG`. Le warning sert de signal d'alerte.

---

### Catégorie E — Defer pattern et intégration Movement

**EC-UPG-20 — `apply_upgrade` appelé depuis Shop, Movement non instancié (shop chargé depuis MENU)** : SI le Player n'existe pas dans la scène au moment de l'achat ALORS `apply_upgrade` flipe le booléen public de l'autoload. Au spawn du Player, Movement lit les flags en pull au premier `_physics_process` (R-UPG-7, R-UPG-8). Aucun defer actif requis. EC-SHP-17 est résolu trivialement par le pull pattern.

**EC-UPG-21 — `apply_upgrade` appelé pendant despawn du Player (transition)** : SI le Player est en cours de `queue_free()` au moment de l'appel ALORS le flip du booléen autoload est sans effet sur le Player en despawn. Le prochain Player instancié lira la valeur correcte à son premier tick. Comportement sain.

**EC-UPG-22 — Movement spawné avec flag déjà `true` post-save** : SI un Player est instancié après boot hydration réussie ALORS `can_air_jump`, `can_dash` sont déjà `true` dans l'autoload. Movement les lit dès le premier `_physics_process` : la capability est active immédiatement. Comportement attendu et nominal.

**EC-UPG-23 — Lecture de flag pendant mutation intra-tick** : SI Movement lit `Upgrade.can_dash` au début du `_physics_process` et que Shop appelle `apply_upgrade` dans le même frame ALORS Godot 4.6 est single-threaded sur le main thread : `apply_upgrade` s'exécute soit avant soit après le `_physics_process` de Movement, jamais pendant. Aucun torn-read possible. Le flip est visible au plus tôt au tick suivant ; délai d'un tick admis.

---

### Catégorie F — Multi-call et fenêtres d'atomicité

**EC-UPG-24 — Crash entre `try_spend` réussi et `apply_upgrade`** : SI le process crash après que Shop a débité les crédits mais avant d'appeler `apply_upgrade` ALORS la save `"owned_upgrades"` ne contient pas le nouvel id. Au boot suivant, hydration ne l'applique pas : upgrade perdu, crédits débités. Admis Tier 1 — cohérent avec EC-SHP-9 (Shop r1) qui documente ce risque résiduel. Résolution complète requiert transaction atomique hors scope MVP.

**EC-UPG-25 — Crash entre `apply_upgrade` et `save_string_array`** : SI le process crash après que Shop a appelé `apply_upgrade` (flag flippé en RAM, `_owned` muté) mais avant que Shop écrive la save ALORS au boot suivant, `load_string_array` retourne l'ancienne save sans le nouvel id. Hydration ne réapplique pas l'upgrade → upgrade perdu malgré le flag en RAM. Admis Tier 1 solo offline, cohérent EC-SHP-9. Le contrat R-SHP-6 (séquence SYNC sans `await`) minimise la fenêtre.

**EC-UPG-26 — Appels multiples depuis plusieurs call stacks simultanés** : Godot 4.6 main thread single-threaded : deux appels `apply_upgrade` ne peuvent pas s'entremêler. L'idempotence (R-UPG-4) et la séquentialité garantie absorbent tout cas d'appels multiples intra-frame.

---

### Catégorie G — Tier 2+ et forward-compat

**EC-UPG-27 — Save future avec ids inconnus (forward-compat)** : SI une save créée par un build Tier 2+ contient `&"wall_run_boost"`, `&"triple_jump"` etc. et est chargée par un build MVP ALORS R-UPG-9 s'applique pour chaque id inconnu (warning + skip). Les ids MVP dans la même save sont appliqués normalement. La save n'est pas réécrite (R-UPG-10) ; les ids Tier 2+ survivent intacts pour un futur build Tier 2+.

**EC-UPG-28 — `_CATALOG` Tier 2+ avec propriété absente (`can_wall_run` pas déclarée en MVP)** : SI une save Tier 2+ contient `&"wall_run"` qui mappe sur `&"can_wall_run"` ALORS même si `can_wall_run` n'est pas une `var` déclarée dans le build MVP, `_CATALOG` MVP ne contient pas cet id → R-UPG-9 warning + skip avant même d'atteindre `set()`. Aucun crash.

**EC-UPG-29 — Capabilities Tier 2+ chargées, flag absent comme propriété (build MVP)** : SI par erreur un build MVP déclare un `_CATALOG` incomplet qui mappe un id Tier 2+ sur un `flag_name` inexistant ALORS F-UPG-3 GUT catalog invariant le détecte au build. Bloquant avant release.

---

### Catégorie H — Sécurité et anti-cheat

**EC-UPG-30 — Edition manuelle de save pour ajouter un id invalide** : SI le joueur édite la save et ajoute `&"premium_upgrade"` absent du `_CATALOG` ALORS R-UPG-9 warning + skip au boot. Aucun effet gameplay. Cohérent avec EC-SHP-32 (Shop r1, Tier 3). Upgrade respecte le catalog comme source de vérité (R-UPG-3).

**EC-UPG-31 — Edition manuelle pour ajouter un id valide sans paiement** : SI le joueur ajoute `&"double_jump"` dans la save ALORS boot hydration appelle `apply_upgrade(&"double_jump")` → flag `can_air_jump = true`. Upgrade n'est pas responsable de la validation économique (R-UPG-14) ; Shop owns la transaction. Admis Tier 1 solo offline sans anti-cheat. Résolution Tier 3 : validation server-side ou checksum save hors scope.

---

### Catégorie I — Test et mock

**EC-UPG-32 — Mock UpgradeSystem pour tests Movement** : SI un test GUT doit isoler Movement de l'autoload réel ALORS le mock expose uniquement les trois `var bool` (`can_air_jump`, `can_dash`, `can_wall_run`) et un stub `apply_upgrade(id)` no-op. Remplacement via `Engine.set_singleton("UpgradeSystem", mock)` en `before_each` / restauré en `after_each`. Le pull-pattern Movement (R-UPG-8) rend le mock trivial.

**EC-UPG-33 — `_boot_complete` flag pour synchronisation d'assert en test** : SI un test de boot hydration doit asserter l'état post-`_ready()` ALORS l'autoload expose `var _boot_complete: bool = false` setté à la fin de `_ready()`. Les tests vérifient `assert_true(Upgrade._boot_complete)` avant d'asserter les flags. Optionnel MVP ; recommandé pour fiabilité des tests de boot.

---

### Catégorie J — `process_mode` et pause moteur

**EC-UPG-34 — `apply_upgrade` appelé pendant GSM PAUSED** : SI une logique de Shop hors-MVP appelait `apply_upgrade` pendant un état pausé ALORS Shop ne peut pas être ouvert en état PAUSED (contrat GSM). EC défensif : `apply_upgrade` est une méthode synchrone pure sans dépendance à `_process` ; elle s'exécute indépendamment du `process_mode`. Aucune guard requise.

**EC-UPG-35 — Engine pausé (`get_tree().paused = true`)** : SI le moteur est mis en pause (menu pause) ALORS `apply_upgrade` reste appelable car l'autoload doit avoir `process_mode = PROCESS_MODE_ALWAYS`. Les `_process` / `_physics_process` de Movement sont suspendus (ils lisent les flags) mais les booléens peuvent être mutés ; Movement lira les nouvelles valeurs à la reprise. Recommandation : déclarer explicitement `process_mode = PROCESS_MODE_ALWAYS` dans `_ready()` de l'autoload pour éviter toute régression si le parent tree change.

## Dependencies

`UpgradeSystem` est un autoload data-pure quasi-stateless. Il a une surface de dépendance volontairement minimale : trois Hard, deux Soft, deux Cousins, quatre Anti-deps explicites. Aucune dépendance circulaire, aucune dépendance bidirectionnelle non documentée.

---

### Hard dependencies (Upgrade ne peut pas fonctionner sans)

| Système | Direction | Status | Contrat | Bidirectional check |
|---------|-----------|--------|---------|---------------------|
| **Shop System** | In (Shop appelle Upgrade) | ✅ Designed r1 | `apply_upgrade(id: StringName) -> void` SYNC idempotent | ✅ Shop r1 §Interactions ligne 229 + R-SHP-6 step 5c. **OQ-SHP-2 RESOLVED** : Upgrade r1 confirme l'API à l'identique. Recommandation amendement Shop r2 cosmetic (passer "PROVISOIRE" à "VERROUILLÉ"). |
| **Player Movement System** | Out (Movement lit Upgrade) | ✅ Designed r3 (In Review) | Movement lit `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run` en pull à 60 Hz dans `_physics_process` (Movement Rules 3, 6, 7, 10) | ✅ Movement r3 §Dependencies ligne 69 + ligne 315 + ligne 489 confirme "interface unidirectionnelle via capability API. Movement n'appelle jamais Upgrade." Upgrade r1 confirme symétriquement : ignore l'existence de Movement. |
| **Save/Load System** | In (Upgrade lit au boot) | ✅ Designed r1 (parallel session 2026-04-27) | `SaveLoad.load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` appelé une seule fois dans `_ready()` autoload avec clé `"owned_upgrades"`, default `[]`. | ✅ Save/Load r1 R-SAV-4 + §Interactions consumer table confirme l'API à l'identique. OQ-UPG-1 RESOLVED. |

---

### Soft dependencies (Upgrade fonctionne dégradé sans, ou peer Tier 2+)

| Système | Direction | Status | Lien | Tier |
|---------|-----------|--------|------|------|
| **Game State Manager** | Indirect (ordre autoload) | ✅ APPROVED r1 | Aucun appel direct. Ordre `project.godot` ADR-0007 D-1 étendu : `InputManager → GSM → SaveLoadSystem → AudioSystem → UpgradeSystem` (R-UPG-11). GSM précède Upgrade dans l'ordre Foundation, mais ce n'est pas une contrainte runtime — les autoloads `_ready()` s'exécutent tous avant le démarrage de toute scène. | MVP |
| **Audio System** | Out (peer, Tier 2+) | ✅ APPROVED r2.1 | Aucun appel direct au MVP. Tier 2+ : un consumer Audio pourra lire `Upgrade.can_*` pour déclencher un SFX d'unlock — sans signal depuis Upgrade. Voir OQ-UPG-3. | Tier 2+ |

---

### Cousins (Upgrade ignore, mais partage des contrats partagés via tiers)

| Système | Lien | Notes |
|---------|------|-------|
| **HUD System** | Lecture indirecte des capability flags Tier 2+ | HUD r1 ne consomme PAS Upgrade au MVP (anti-pattern explicit HUD GDD AC-HUD-32 : zero ammo/objective indicator). Tier 2+ : HUD pourra afficher des indicateurs de capabilities possédées en lisant `Upgrade.can_*` directement (sans signal). Pas de couplage runtime au MVP. |
| **Credit Economy System** | Coût des upgrades owned par Credit | Upgrade ignore complètement les coûts (R-UPG-14). Credit F-CRD-3 est la source de vérité pour `cost_at_index(n)` ; Shop F-SHP-1 délègue ce lookup. Upgrade reçoit `apply_upgrade(id)` post-validation économique sans paramètre coût. Aucune dépendance runtime. |

---

### Anti-dependencies (systèmes qui NE doivent PAS dépendre de Upgrade ni l'inverse)

| Système | Anti-relation | Justification |
|---------|---------------|---------------|
| **Player Combat System** | Combat ne lit pas Upgrade au MVP | Pas d'upgrade Combat MVP (`katana_extended` est Tier 2+). Combat est complet sans connaître Upgrade. Migration Tier 2+ : Combat lira un nouveau flag `Upgrade.can_katana_extended` en pull (même pattern que Movement). |
| **Level System** | Level ne lit pas Upgrade | Level est purement géométrique. Les capability gates (porte ne s'ouvre que si dash) sont implicites via géométrie (Level GDD R-2/Combat Rule 16) — pas de check runtime sur capability. |
| **VFX & Feedback System** | VFX ne lit pas Upgrade au MVP | Aucun feedback VFX d'unlock MVP (Pillar 1 anti-friction). Tier 2+ : VFX pourra lire `Upgrade.can_*` directement si besoin, sans signal Upgrade. |
| **Secret System** | Secret ne lit pas Upgrade | Secret r1 ne consomme PAS de capability flag. Le gating est implicite via géométrie (Secret GDD §C — capability gate IMPLICITE par positionnement Lure/Volume Level). Tier 2+ : un secret de type "secret_radar" pourra exposer un flag `Upgrade.can_secret_radar` en pull. |

---

### Bidirectional check summary (mandatory rules `.claude/rules/design-docs.md`)

| Système ↔ Upgrade | Direction documentée Upgrade r1 | Direction documentée chez l'autre | Status |
|-------------------|--------------------------------|-----------------------------------|--------|
| Shop ↔ Upgrade | Upgrade reçoit `apply_upgrade(id)` SYNC idempotent (R-UPG-4 + §C.5 Interactions) | Shop r1 §Interactions ligne 229 (PROVISOIRE → demande RESOLVED via Upgrade r1) | ✅ Cohérent — confirmation Upgrade r1 résout OQ-SHP-2 |
| Movement ↔ Upgrade | Upgrade expose `can_air_jump/can_dash/can_wall_run` (R-UPG-2 + §C.5) | Movement r3 §Dependencies "Movement n'appelle jamais Upgrade" + ligne 489 capability flag API | ✅ Cohérent |
| Save/Load ↔ Upgrade | Upgrade lit `load_string_array("owned_upgrades", [])` au boot (R-UPG-5 + §C.5) | Save/Load r1 (parallel session 2026-04-27) §Interactions table confirme contrat | ✅ Cohérent — OQ-UPG-1 RESOLVED |
| GSM ↔ Upgrade | Upgrade documente l'ordre autoload R-UPG-11 (§C.5) | GSM r1 ne mentionne pas Upgrade (autoload order indépendant des contrats GSM) | ✅ Cohérent (pas d'API directe) |
| Credit ↔ Upgrade | Upgrade ignore Credit (R-UPG-14 + §F Cousins) | Credit r1 §Cousins HUD/Shop downstream — ne mentionne pas Upgrade explicitement | ✅ Cohérent (zéro couplage) |
| HUD ↔ Upgrade | Upgrade ne consomme pas HUD (Tier 2+ pull en option) | HUD r1 ne consomme pas Upgrade (anti-pattern explicit AC-HUD-32) | ✅ Cohérent |

---

### Provisional contracts table (à figer post-design dépendances)

| Contrat | Owned by | Consumer | Status | Open Question |
|---------|----------|----------|--------|---------------|
| `SaveLoad.load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` | Save/Load r1 ✅ Designed | Upgrade boot hydration | ✅ VERROUILLÉ par Save/Load r1 R-SAV-4 | OQ-UPG-1 RESOLVED — Save/Load r1 confirme à l'identique |
| `Audio.play_sfx(id, bus="UI")` Tier 2+ unlock SFX | Audio (peer) | Upgrade Tier 2+ feedback | PROVISOIRE Tier 2+ | OQ-UPG-3 — décider si SFX d'unlock existe et son bus |
| `Upgrade.can_<capability>: bool` extension Tier 2+ | Upgrade | Movement / Combat / Secret Tier 2+ | À FORMALISER | OQ-UPG-2 — ajout de flags Tier 2+ avec migration Dictionary si N > 12 |

## Tuning Knobs

`UpgradeSystem` est volontairement pauvre en tuning knobs runtime. C'est un système de plomberie : son comportement est régi par sa structure de données (`_CATALOG`), pas par des paramètres ajustables. La majorité des "knobs" listés ci-dessous sont **structurels** (modification = ADR) ; seuls 2 knobs MVP sont design-active (modifiables sans ADR).

---

### Knobs structurels (modification = ADR)

| Knob | Type | Default MVP | Safe range | Effet | Owner |
|------|------|-------------|------------|-------|-------|
| `_CATALOG` (mapping `id → flag_name`) | `const Dictionary` | `{&"double_jump" → &"can_air_jump", &"dash_horizontal" → &"can_dash"}` | MVP : 2 entrées exactement ; Tier 2+ : 8 entrées max recommandé | Définit l'univers complet des upgrades possibles. Toute modification (ajout, retrait, renommage) impacte Shop catalog + tests F-UPG-3 + Movement contract + Save/Load forward-compat | Upgrade GDD (ce document) — ADR requis pour modification |
| `OWNED_UPGRADES_SAVE_KEY` | `StringName` | `&"owned_upgrades"` | unique, non-collision avec autres save keys | Clé partagée Shop+Upgrade pour la save Array. Renommage = breaking change de save = migration outil | Shop r1 R-SHP-8 + Upgrade R-UPG-5 ; modification = ADR Save/Load |
| Autoload order `project.godot` | `Array[String]` | `[InputManager, GameStateManager, SaveLoadSystem, AudioSystem, UpgradeSystem, …]` | Contrainte stricte : `SaveLoadSystem` < `UpgradeSystem`. Ordre canonique ADR-0007 D-1 + extension R-UPG-11 | Ordre d'init des autoloads. Inversion SaveLoad/Upgrade = crash boot ; ordre relatif Upgrade ↔ GSM indifférent runtime | R-UPG-11 + ADR-0007 D-1 ; modification = amendement ADR-0007 |
| `process_mode` autoload | `ProcessMode` | `PROCESS_MODE_ALWAYS` | tjrs ALWAYS pour pause-resilience | Garantit que `apply_upgrade` reste appelable pendant `get_tree().paused` (EC-UPG-35) | R-UPG-1 + EC-UPG-35 ; modification = ADR |

---

### Knobs design-active MVP (modifiables sans ADR)

| Knob | Type | Default | Safe range | Effet | Notes |
|------|------|---------|------------|-------|-------|
| `_boot_complete` exposed for tests | `bool` | `false` puis `true` | binaire | Synchronisation des assertions GUT post-`_ready()` (EC-UPG-33) | Public read, jamais muté hors `_ready()`. Pas un vrai knob — purement debug. |
| Default des `var` capability publiques | `bool` | `false` (pour les 3) | toujours `false` au démarrage à froid | Capabilities verrouillées au boot, débloquées par hydration ou apply | R-UPG-2 + Movement Rule 10 ligne 52 ; aligné sur game-concept (joueur démarre sans upgrades). |

---

### Tier 2+ hooks réservés (latents, pas de tuning au MVP)

| Hook | Description | Trigger d'activation |
|------|-------------|----------------------|
| Capability flag `can_wall_run` | Déjà déclaré comme `var public: bool = false` MVP. Catalog `_CATALOG` ne contient pas encore l'id pour le débloquer. | Tier 2+ : ajouter `&"wall_run_long"` au `_CATALOG` |
| Capability flags Tier 2+ supplémentaires (`can_triple_jump`, `can_dash_vertical`, `can_slow_mo_aerial`, `can_katana_extended`, `can_secret_radar`) | À déclarer comme `var public: bool = false` au moment de l'ajout au `_CATALOG` (F-UPG-4) | Tier 2+ par upgrade individuelle ; chaque ajout = 1 ligne `var` + 1 entrée `_CATALOG` |
| Migration `var` → `Dictionary[StringName, bool]` + `is_capability_enabled(id)` | Refactor si N > 12 capabilities | Tier 3 — déclencheur de revue performance + ergonomie |
| `revoke_upgrade(id)` API | Anti-pattern MVP (R-UPG-12). Latent pour Tier 2+ si un système de respec est introduit | Tier 2+ — nécessite ADR + amendement Shop (refund flow) |
| Audio SFX d'unlock | Latent pour feedback Tier 2+ (OQ-UPG-3) | Tier 2+ amendement Audio r2.2 — bus `UI` ou `UPGRADE_FEEDBACK` |
| `apply_upgrade_emit_signal: bool` toggle | Si un consumer Tier 2+ a besoin d'un signal `capability_unlocked(id)` plutôt que pull | Tier 2+ — nécessite OQ-UPG-4 décision pull vs push |

## Visual/Audio Requirements

### ZÉRO Visual/Audio owned par Upgrade — par décision Pillar 1

`UpgradeSystem` est un système data-pure invisible. Il n'a **aucune** surface visuelle, **aucun** SFX propre, **aucune** VFX propre. Cette absence est intentionnelle et alignée sur trois piliers :

- **Pillar 1 FLOW AVANT TOUT** — par soustraction. Le joueur ne perçoit pas l'unlock comme un événement ("compétence débloquée !") — il le perçoit dans le moveset au prochain saut. Pas de cinématique, pas de pop-up, pas de particles burst.
- **Pillar 2 LA PROGRESSION SE VOIT** — mais elle se voit dans le shop (la carte qui passe AFFORDABLE → OWNED, le compteur qui tombe en 300 ms — owned Shop UI Section J) et dans le moveset (le joueur saute plus haut, dash plus loin — owned Movement). Upgrade ne s'auto-célèbre pas.
- **Anti-pattern F2P** — éviter la fanfare d'unlock typique des jeux à monétisation aggressive (loot box reveal, particles dorées, son de jackpot). Référence Hollow Knight charm system : un charm équipé est juste équipé — pas de mise en scène.

### Délégation de feedback aux systèmes consumers

Tout feedback visuel ou sonore lié à une upgrade est owned par d'autres systèmes :

| Feedback | Owner | Notes |
|----------|-------|-------|
| Carte upgrade OWNED dans le shop (cyan désaturé, pulse 1.0→1.03→1.0 sur 150 ms) | Shop System (Shop r1 §J UI Requirements) | Shop GDD R-SHP-9 + R-SHP-10. Upgrade ne contribue rien. |
| Compteur crédit qui tombe lors de l'achat (tween 300 ms) | Shop System (Shop r1) | Distinct du HUD CreditCounterLabel (HUD r1 R-6 hard-set silencieux pendant SPEND_SHOP). |
| Capability nouvellement débloquée se manifeste à la prochaine action gameplay (double-saut effectif, dash effectif) | Movement System + VFX System (Tier 2+) | Movement Rule 3 + 6. Pas d'animation d'unlock — l'unlock EST le mouvement. |
| SFX d'achat shop | Aucun (zéro SFX shop MVP, audio-system r2.1 cohérent) | Différé Tier 2+ (Shop OQ-SHP-4 — bus `SHOP_UI` ou `UI`). Upgrade resterait silencieux ; le SFX serait owned Shop. |
| SFX d'unlock capability | Aucun MVP | Latent Tier 2+ (OQ-UPG-3) — owned Audio si introduit, déclenché par consumer (Movement, HUD) en lisant `Upgrade.can_*`. |

### Anti-patterns visuels/audio testables

Les comportements suivants sont explicitement **interdits** au MVP — chacun produit un AC blocking en Section H :

- **Pop-up "Capacité débloquée"** (full-screen ou notification HUD) — anti-Pillar 1, anti-référence Hollow Knight charm system.
- **Particles burst à `apply_upgrade(id)`** (fontaine dorée, cercle de lumière) — anti-pattern F2P.
- **SFX jingle d'unlock** (son de fanfare, choeur, notification système) — anti-Pillar 1.
- **Camera kick / shake** au moment de l'achat — anti-Pillar 1, casse l'invariance camera lors du shop.
- **Couleur de UI globale modifiée** (palette qui vire au doré pendant 200 ms) — anti-Chrome Zen.
- **Vibration / haptic feedback** — pas implémenté MVP de toute façon (pas de gamepad), mais latent pour Tier 2+ et explicitement OFF par défaut.

### Asset spec

Aucun asset visuel ni audio à produire pour Upgrade System au MVP. Pas de Asset Spec à générer (`/asset-spec` non applicable). Tier 2+ seulement si OQ-UPG-3 décide d'ajouter un SFX d'unlock — alors owned Audio System.

---

## UI Requirements

### ZÉRO UI propre Upgrade — par décision architecturale

`UpgradeSystem` est un autoload data-pure sans surface visuelle. Il n'a aucune Control, aucun CanvasLayer, aucun Label. Toute UI liée aux upgrades est owned par les systèmes consumers :

| Élément UI | Owner | Référence |
|------------|-------|-----------|
| Carte d'achat avec prix, label, état AFFORDABLE/DISABLED/OWNED | Shop System | Shop r1 §J.2 catalogue VBoxContainer |
| Bouton "Continuer" du shop | Shop System | Shop r1 §J.4 |
| Compteur de crédits (HUD top-right) | HUD System | HUD r1 R-1 CreditCounterLabel |
| Indicateurs de capabilities possédées (si jamais ajoutés Tier 2+) | HUD System | HUD r1 OQ + Tier 2+ extensions |
| Menu de configuration upgrades (skill tree, respec) | **N'EXISTE PAS** | Anti-pattern explicite (R-UPG-12 + game-concept anti-piliers) |

### Anti-patterns UI testables (AC blocking)

- **Pas de menu "Mes capacités"** dans aucun écran (pause, options, HUD). Game-concept impose : "L'UI est invisible" (ligne 96).
- **Pas de tooltip / hover info** sur les capabilities. Le joueur les apprend en jouant.
- **Pas de logbook / progression tracker** d'upgrades possédées. Le joueur les sent.
- **Pas de UI runtime debug** (`F3` overlay) listant les flags Upgrade — sauf en build debug, jamais en release.

### Pas de UX flag

Upgrade System n'a pas de surface UX — le UX flag est porté par Shop System (`/ux-design shop-screen.md` requis avant `/create-epics shop-system`). Upgrade ne nécessite **aucun** `/ux-design` propre. La spec est complète sans intervention UX-designer.


## Acceptance Criteria

### Catégorie A — Architecture & autoload

- **AC-UPG-1** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** un projet Godot booté avec la liste d'autoloads canonique définie dans `project.godot`, **WHEN** n'importe quel script accède à l'identifiant global `Upgrade` depuis un contexte de scène ou autoload, **THEN** la référence est non-null et `Upgrade is UpgradeSystem` retourne `true`. (R-UPG-1, R-UPG-11)

- **AC-UPG-2** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` instancié, **WHEN** on lit `Upgrade.can_air_jump`, `Upgrade.can_dash`, `Upgrade.can_wall_run` avant tout appel à `apply_upgrade`, **THEN** les trois variables retournent `false` et leurs types sont `bool` (vérification `typeof(x) == TYPE_BOOL`). (R-UPG-2)

- **AC-UPG-3** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le fichier `project.godot` avec la liste autoload complète, **WHEN** on inspecte l'ordre de déclaration des autoloads, **THEN** `SaveLoadSystem` précède `UpgradeSystem` (contrainte stricte) ; ordre canonique attendu `InputManager → GSM → SaveLoadSystem → AudioSystem → UpgradeSystem` (ADR-0007 D-1 + R-UPG-11). (R-UPG-11, ADR-0007 D-1)

- **AC-UPG-4** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` après `_ready()`, **WHEN** on lit `Upgrade.process_mode`, **THEN** la valeur est `Node.PROCESS_MODE_ALWAYS`. (R-UPG-1)

- **AC-UPG-5** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` avant et après `_ready()`, **WHEN** on instrumente un flag `_boot_complete : bool` avant et après l'appel `_ready()`, **THEN** il est `false` avant et `true` à la dernière ligne de `_ready()`. (F-UPG-2)

- **AC-UPG-6** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` instancié, **WHEN** un test tente de réassigner `UpgradeSystem._CATALOG` via une mutation directe (`_CATALOG = {}`), **THEN** GDScript lève une erreur de compilation ou d'exécution confirmant l'immutabilité du `const` ; F-UPG-3 passe sans dépendance d'état runtime. (R-UPG-3, F-UPG-3)

---

### Catégorie B — apply_upgrade idempotence et validation

- **AC-UPG-7** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `Upgrade.can_air_jump` à `false` et `_owned` vide, **WHEN** on appelle `Upgrade.apply_upgrade(&"double_jump")`, **THEN** `Upgrade.can_air_jump` est `true` et `Upgrade.is_owned(&"double_jump")` est `true`. (R-UPG-4, R-UPG-2)

- **AC-UPG-8** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `Upgrade.can_dash` à `false` et `_owned` vide, **WHEN** on appelle `Upgrade.apply_upgrade(&"dash_horizontal")`, **THEN** `Upgrade.can_dash` est `true` et `Upgrade.is_owned(&"dash_horizontal")` est `true`. (R-UPG-4, R-UPG-2)

- **AC-UPG-9** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `apply_upgrade(&"double_jump")` déjà appelé une première fois (`can_air_jump == true`), **WHEN** on appelle `apply_upgrade(&"double_jump")` une seconde fois, **THEN** `can_air_jump` reste `true`, `get_owned_count()` reste à `1`, et aucune erreur ou warning n'est émis. (R-UPG-4, EC-UPG-11)

- **AC-UPG-10** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** un `UpgradeSystem` initialisé avec `_owned` vide, **WHEN** on appelle `apply_upgrade(&"nonexistent_id")`, **THEN** un `push_warning` est émis (testé via mock/capture de `push_warning`), aucun flag booléen ne change, et `get_owned_count()` reste à `0`. (R-UPG-9, EC-UPG-6)

- **AC-UPG-11** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** un `UpgradeSystem` initialisé, **WHEN** on appelle `apply_upgrade(StringName(""))` (StringName vide), **THEN** aucun crash n'est levé, un `push_warning` est capturé, et aucun flag booléen ne mute. (R-UPG-9, EC-UPG-7)

- **AC-UPG-12** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `apply_upgrade` instrumenté par un wrapper de test qui mesure le nombre de frames entre appel et retour, **WHEN** on appelle `apply_upgrade(&"double_jump")`, **THEN** la fonction retourne dans la même frame (compteur frame identique avant/après) sans aucun `await` ni `yield` observable. (R-UPG-4)

- **AC-UPG-13** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `_owned` vide avant appel, **WHEN** on appelle `apply_upgrade(&"double_jump")`, **THEN** `Upgrade.is_owned(&"double_jump")` retourne `true` et `get_owned_count()` retourne `1`. (R-UPG-4)

- **AC-UPG-14** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `can_dash` à `false` et `can_wall_run` à `false`, **WHEN** on appelle uniquement `apply_upgrade(&"double_jump")`, **THEN** `can_dash` reste `false` et `can_wall_run` reste `false` ; les capabilities sont mutuellement indépendantes. (R-UPG-13)

- **AC-UPG-15** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le test GUT F-UPG-3 catalog sanity qui vérifie que chaque valeur de `_CATALOG` correspond à un nom de propriété `bool` existant sur `UpgradeSystem`, **WHEN** on introduit intentionnellement une entrée `{&"test_id": &"typo_flag"}` dans une instance de test, **THEN** F-UPG-3 détecte la violation et le test échoue. (F-UPG-3, R-UPG-3)

---

### Catégorie C — Boot hydration

- **AC-UPG-16** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array("owned_upgrades", [])` retourne `[]` (mock), **WHEN** `UpgradeSystem._ready()` s'exécute, **THEN** `can_air_jump`, `can_dash`, `can_wall_run` sont tous `false` et `get_owned_count()` retourne `0`. (F-UPG-2, EC-UPG-4)

- **AC-UPG-17** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` mockée retournant `[&"double_jump"]`, **WHEN** `UpgradeSystem._ready()` s'exécute, **THEN** `can_air_jump` est `true` et `can_dash` reste `false`. (F-UPG-2)

- **AC-UPG-18** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` mockée retournant `[&"double_jump", &"dash_horizontal"]`, **WHEN** `_ready()` s'exécute, **THEN** `can_air_jump` est `true` et `can_dash` est `true`. (F-UPG-2)

- **AC-UPG-19** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` retournant `[&"double_jump", &"unknown_id_xyz"]`, **WHEN** `_ready()` s'exécute, **THEN** `can_air_jump` est `true`, `can_dash` reste `false`, un `push_warning` est capturé pour `&"unknown_id_xyz"`, et aucun crash n'est levé. (R-UPG-9, EC-UPG-17)

- **AC-UPG-20** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` retournant une valeur non-Array (ex. `null` ou `"corrupted"`), **WHEN** `_ready()` s'exécute, **THEN** `UpgradeSystem` utilise le fallback `[]`, aucun crash n'est levé, un `push_warning` de corruption est capturé, et tous les flags restent `false`. (EC-UPG-3, R-UPG-9)

- **AC-UPG-21** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` retournant `[&"double_jump", &"double_jump"]`, **WHEN** `_ready()` s'exécute, **THEN** `can_air_jump` est `true`, `get_owned_count()` retourne `1` (idempotence absorbe le doublon), aucun warning d'idempotence n'est émis. (R-UPG-4, EC-UPG-16)

- **AC-UPG-22** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` retournant `[&"double_jump", 42, null, "string_plain"]`, **WHEN** `_ready()` s'exécute, **THEN** les éléments non-StringName sont filtrés avec warning, `&"double_jump"` est appliqué, et `get_owned_count()` retourne `1`. (EC-UPG-15, R-UPG-9)

- **AC-UPG-23** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `UpgradeSystem._ready()` instrumenté avec un point de mesure, **WHEN** on vérifie l'état de `_boot_complete` au milieu de `_ready()` (avant la dernière ligne), **THEN** `_boot_complete` est `false` pendant la boucle d'hydratation et passe à `true` uniquement après le dernier `apply_upgrade` de la liste. (F-UPG-2, AC-UPG-5)

---

### Catégorie D — Pull pattern Movement integration

- **AC-UPG-24** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `apply_upgrade(&"double_jump")` appelé avant l'instanciation du Player, **WHEN** un `MovementController` est ajouté à la scène et son premier `_physics_process` s'exécute, **THEN** un appel à `Upgrade.can_air_jump` depuis `MovementController` retourne `true` sans nécessiter de signal ou callback. (R-UPG-8, R-UPG-7, EC-UPG-20)

- **AC-UPG-25** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `apply_upgrade(&"double_jump")` appelé pendant que le Player est despawné (absent du scene tree), **WHEN** un nouveau `MovementController` est instancié et lit `Upgrade.can_air_jump` à son premier tick, **THEN** la valeur est `true` ; l'autoload a conservé l'état pendant l'absence du Player. (R-UPG-8, EC-UPG-21)

- **AC-UPG-26** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `apply_upgrade(&"double_jump")` appelé sur le main thread, **WHEN** un autre nœud lit `Upgrade.can_air_jump` dans le même `_physics_process` tick ou le tick suivant, **THEN** la lecture retourne `true` sans état intermédiaire indéfini (no torn read — vérifiable par lecture répétée 100x en boucle GUT). (R-UPG-8, EC-UPG-23)

- **AC-UPG-27** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` instancié, **WHEN** on appelle `Upgrade.get_signal_list()` et qu'on filtre les signaux hérités de `Object`/`Node`, **THEN** la liste de signaux définis par `UpgradeSystem` est vide. (R-UPG-6)

---

### Catégorie E — Pas de persistance write

- **AC-UPG-28** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le fichier source `src/gameplay/upgrade/upgrade_system.gd` (ou chemin équivalent), **WHEN** on exécute un grep statique pour tout appel `SaveLoad.save_` ou `SaveLoad.write_`, **THEN** zéro match est trouvé. (R-UPG-10)

- **AC-UPG-29** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** un test d'intégration cross-GDD simulant un achat shop complet, **WHEN** la clé `"owned_upgrades"` est écrite dans le save, **THEN** l'écriture provient du système Shop et non d'`UpgradeSystem` (vérifiable par mock de `SaveLoad.save_string_array` comptant l'appelant). (R-UPG-10, R-UPG-14)

- **AC-UPG-30** `[Integration — ADVISORY] [Owner: qa-tester] [PROVISIONAL]` — **GIVEN** une session avec upgrades achetés, sauvegardée puis rechargée via `SaveLoad` stable, **WHEN** `UpgradeSystem._ready()` lit le save au boot, **THEN** les flags sont restaurés identiquement à l'état pré-reload (chain-blocked sur Save/Load #3 Not Started). (F-UPG-2, EC-UPG-4)

---

### Catégorie F — Process_mode et pause

- **AC-UPG-31** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `get_tree().paused = true` actif, **WHEN** on appelle `Upgrade.apply_upgrade(&"double_jump")` depuis un script non-pausé, **THEN** `can_air_jump` est `true` immédiatement, confirmant que `PROCESS_MODE_ALWAYS` permet l'exécution pendant la pause. (R-UPG-1, EC-UPG-35)

- **AC-UPG-32** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `get_tree().paused = true` actif et un upgrade précédemment appliqué, **WHEN** un script à `PROCESS_MODE_ALWAYS` lit `Upgrade.can_air_jump`, **THEN** la lecture retourne `true` sans exception ni valeur stale. (EC-UPG-35)

---

### Catégorie G — Anti-patterns testables

- **AC-UPG-33** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** l'autoload `UpgradeSystem` (même vérification que AC-UPG-27), **WHEN** on appelle `Upgrade.get_signal_list()` et qu'on filtre les signaux `Object`/`Node` de base, **THEN** la liste retournée est vide, confirmant zéro signal outbound déclaré. (R-UPG-6)

- **AC-UPG-34** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le fichier source `upgrade_system.gd`, **WHEN** on exécute un grep statique pour les classes `Control`, `Label`, `CanvasLayer`, `Button`, `Panel`, tout nœud UI Godot, **THEN** zéro match est trouvé dans le fichier. (R-UPG-14)

- **AC-UPG-35** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le fichier source `upgrade_system.gd`, **WHEN** on exécute un grep statique pour `AudioStreamPlayer`, `AudioServer`, `play(`, toute API audio Godot, **THEN** zéro match est trouvé. (R-UPG-14)

- **AC-UPG-36** `[Logic — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** le fichier source `upgrade_system.gd`, **WHEN** on exécute un grep statique pour `revoke_upgrade` ou toute méthode de retrait d'upgrade, **THEN** zéro match est trouvé ; R-UPG-12 interdit le revoke au MVP. (R-UPG-12)

- **AC-UPG-37** `[Visual — ADVISORY] [Owner: qa-tester] [PLAYTEST]` — **GIVEN** une session de jeu complète avec achat d'upgrade via Shop, **WHEN** le joueur effectue un achat, **THEN** aucun popup skill tree, aucun arbre de talents, aucun écran d'upgrade propre à `UpgradeSystem` n'apparaît ; toute présentation est déléguée au Shop UI ou HUD. (R-UPG-14, Pillar 1 FLOW AVANT TOUT)

---

### Catégorie H — Forward-compat et Tier 2+

- **AC-UPG-38** `[Integration — BLOCKING] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad.load_string_array` retournant un array contenant des ids Tier 2+ inconnus du MVP (ex. `[&"double_jump", &"wall_run_extended", &"tier2_special"]`), **WHEN** `_ready()` s'exécute sur un build MVP, **THEN** les ids inconnus sont skippés avec warning, `&"double_jump"` est appliqué, et aucun crash n'est levé. (R-UPG-9, EC-UPG-27, F-UPG-4)

- **AC-UPG-39** `[Logic — ADVISORY] [Owner: qa-tester] [PROVISIONAL]` — **GIVEN** un `_CATALOG` Tier 2+ de 8 entrées valides ajouté dans une branch de test, **WHEN** le test GUT F-UPG-3 catalog sanity s'exécute sur ce catalog étendu, **THEN** tous les mappings `id → flag_name` pointent vers des propriétés `bool` existantes et F-UPG-3 passe (PROVISIONAL — deferred à Tier 2+ implementation). (F-UPG-3, F-UPG-4)

---

### Catégorie I — Performance

- **AC-UPG-40** `[Logic — ADVISORY] [Owner: qa-tester] [AUTO]` — **GIVEN** `SaveLoad` mockée retournant `[&"double_jump", &"dash_horizontal"]` (catalog MVP complet à 2 entrées), **WHEN** on mesure le wall-clock de `_ready()` via `Time.get_ticks_usec()` avant et après, **THEN** la durée est inférieure à 1 000 µs (1 ms). (R-UPG-4 O(1))

- **AC-UPG-41** `[Logic — ADVISORY] [Owner: qa-tester] [AUTO]` — **GIVEN** `UpgradeSystem` initialisé, **WHEN** on mesure le wall-clock d'un appel `apply_upgrade(&"double_jump")` via `Time.get_ticks_usec()` sur 1 000 appels répétés (idempotence) et qu'on prend la médiane, **THEN** la médiane est inférieure à 100 µs (0,1 ms), confirmant la complexité O(1) du Dictionary lookup. (R-UPG-4)

---

### Catégorie J — PROVISIONAL chain-blocked (Save/Load Not Started)

- **AC-UPG-42** `[Integration — BLOCKING] [Owner: qa-tester] [PROVISIONAL]` — **GIVEN** l'implémentation de `SaveLoad` livrée (Save/Load #3 Started), **WHEN** on vérifie la signature publique de `SaveLoad.load_string_array`, **THEN** elle accepte un paramètre `key: String` et un paramètre `default: Array` et retourne un `Array` (chaîne bloquée jusqu'à Save/Load #3 Designed). (F-UPG-2, R-UPG-5)

- **AC-UPG-43** `[Integration — BLOCKING] [Owner: qa-tester] [PROVISIONAL]` — **GIVEN** `SaveLoad.load_string_array("owned_upgrades", [])` appelé avec une clé absente du save, **WHEN** l'implémentation Save/Load est livrée, **THEN** la valeur retournée est `[]` (le default passé en paramètre), sans exception ni log d'erreur (chain-blocked sur Save/Load #3 Not Started). (F-UPG-2, EC-UPG-4)

## Open Questions

10 OQ-UPG identifiées : 3 critiques bloquantes pour Sprint 1 (chaîne Save/Load + Movement re-review) + 4 Tier 2+ latents + 3 cosmétiques/cross-GDD.

---

### OQ critiques (bloquantes Sprint 1)

**OQ-UPG-1 — RESOLVED 2026-04-27** : Save/Load r1 (parallel session, GDD écrit même date) confirme la signature canonique `func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` (R-SAV-4). Différences vs contrat provisoire Upgrade r1 : (a) `key` typé `String` (pas `StringName`) — alignement avec API ConfigFile native Godot ; (b) `default` typé `Array[StringName]` — strict typing ✅ ; (c) corruption type retourne `default` + `push_warning` (R-SAV-12 + EC-SAV-8) ✅. **Action requise** : amendement éditorial Upgrade r1 §C.5 et §F dependencies pour passer le param key de `StringName` à `String` (cosmetic — Upgrade utilisera `String("owned_upgrades")` comme literal). **Status final : RESOLVED par Save/Load r1**.

**OQ-UPG-2 — Movement re-review r4 confirme contrat `Upgrade.can_*` en pull** : Movement r3 est In Review (pending fresh r4). La re-review doit confirmer que le pattern pull dans `_physics_process` reste verrouillé après les corrections r4 (cluster Martin A/B/C/D 2026-04-21). Si Movement r4 introduit un pattern push (signal `capability_changed`), Upgrade r1 doit être amendé. **Owner : Movement designer + qa-lead pour fresh re-review**. **Target : avant `/create-epics upgrade-system`**.

**OQ-UPG-3 — SFX d'unlock capability Tier 2+** : décider si Audio System ajoute un SFX au moment où le joueur **utilise** une capability nouvellement débloquée pour la première fois (pas au moment de `apply_upgrade`). Owner natural : Movement (déclenche le SFX au premier saut post-unlock) ou HUD (compteur d'usage). Si oui, amendement Audio r2.2 pour ajouter bus `UI_UPGRADE` ou réutilisation `UI`. Si non, latent permanent. **Owner : audio-director + creative-director (Pillar 1 vs Pillar 2 trade-off)**. **Target : Tier 2+ playtest 2 — pas bloquant Sprint 1**.

---

### OQ Tier 2+ latents

**OQ-UPG-4 — Migration `var` → `Dictionary[StringName, bool]` quand N > 12** : F-UPG-4 documente l'extension Tier 2+ à 8 capabilities. Au-delà (12+), maintenir 12 `var` publiques devient un anti-pattern (lookup symbolique manuel via auto-complétion fragile). À ce moment, refactor vers `_capabilities: Dictionary[StringName, bool]` + getter `is_capability_enabled(id: StringName) -> bool`. **Trigger** : ajout d'une 13e capability. **Migration** : remplacer chaque `Upgrade.can_dash` par `Upgrade.is_capability_enabled(&"can_dash")` dans tous les consumers (Movement, HUD, etc.) — breaking change, nécessite ADR. **Owner : technical-director + lead-programmer**. **Target : Tier 3 si jamais atteint**.

**OQ-UPG-5 — Push pattern via signal `capability_unlocked(id, flag)`** : alternative au pull pattern Movement (R-UPG-6, R-UPG-8). Décision MVP = pull pour simplicité ; un signal pourrait être ajouté Tier 2+ si un consumer a besoin de réagir AU MOMENT précis de l'unlock (ex. : VFX burst, achievement system). Caveat : un signal expose Upgrade aux risques de connexion désordonnée. Si introduit, le pattern doit rester additif (le pull continue de fonctionner). **Owner : technical-director**. **Target : à évaluer Tier 2+ avec premier consumer demandeur**.

**OQ-UPG-6 — `revoke_upgrade(id)` API pour respec Tier 2+** : R-UPG-12 interdit le revoke MVP. Tier 2+ pourrait introduire un système de respec (refund crédits, re-allouer ailleurs). Implications : `apply_upgrade(id)` ↔ `revoke_upgrade(id)` doivent être symétriques côté state (`_owned`), capability flags, et persistance Shop. Refund cost : Credit System F-CRD-3 doit définir ratio refund (100% ? 50% ?). UI : Shop must add "Revoke" button per-card. **Owner : economy-designer + game-designer**. **Target : Tier 2+ Vertical Slice ou Alpha si playtest demande respec**.

**OQ-UPG-7 — Multi-profil saves Tier 2+** : EC-SHP-31 (Shop r1) flagge le besoin de profils multiples (slot 1/2/3). Pour Upgrade : la clé save passerait de `"owned_upgrades"` à `"profile_<N>.owned_upgrades"`. Upgrade doit alors être informé du profile actif au boot (dépendance GSM ou Save/Load wrapper). MVP : un seul profil. **Owner : Save/Load designer (lors de l'extension Tier 2+)**. **Target : Tier 2+ — coordonné avec Shop OQ-SHP-3**.

---

### OQ cosmétiques et cross-GDD

**OQ-UPG-8 — Amendement Shop r1 → Shop r2 pour passer "PROVISOIRE" à "VERROUILLÉ"** : Shop r1 §Interactions ligne 229 et §Provisional contracts table ligne 526 marquent le contrat `apply_upgrade(id)` comme PROVISOIRE OQ-SHP-2. Upgrade r1 confirme l'API à l'identique. Recommandation : amendement Shop r2 cosmetic pour mettre à jour le statut PROVISOIRE → VERROUILLÉ et résoudre OQ-SHP-2. **Owner : économe-designer ou orchestrateur de session**. **Target : prochaine session de design Shop ou batch /consistency-check**.

**OQ-UPG-9 — Cohérence avec Movement r3 anti-circular dependency note** : systems-index.md ligne 154 affirme "Player Movement ignore l'existence d'Upgrade System". Cette assertion est partiellement correcte (Movement n'appelle jamais Upgrade en mutation) mais nécessite raffinement : Movement LIT bien `Upgrade.can_*` en pull (Movement r3 ligne 69, 315, 489). Le bon phrasing serait : "Movement consume Upgrade as data source via pull (no signal, no callback) — Upgrade ignores Movement entirely." Recommandation : amendement systems-index.md cosmetic post-Upgrade r1. **Owner : technical-director ou orchestrateur**. **Target : prochain `/review-all-gdds` ou batch /consistency-check**.

**OQ-UPG-10 — F-UPG-3 catalog sanity test : path et nom du fichier** : F-UPG-3 mentionne `tests/integration/upgrade/catalog_sanity_test.gd` comme path attendu. À confirmer lors de `/create-epics upgrade-system` que ce path s'aligne avec les conventions de `tests/` du projet (ex. : `tests/static/` vs `tests/integration/`). Le test est statique (build-time, pas runtime) — donc `tests/static/` pourrait être plus approprié. **Owner : qa-lead + lead-programmer (lors de l'epic)**. **Target : avant first commit `apply_upgrade.gd` Sprint 1**.
