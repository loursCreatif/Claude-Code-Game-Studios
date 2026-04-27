# Credit Economy System

> **Status**: In Design (r2 — cosmetic amendment 2026-04-27 : OQ-CRD-1/OQ-CRD-2 RESOLVED, B-3 tween ownership delegation, dependency status refresh post Shop/HUD/Secret r1)
> **Author**: economy-designer + creative-director + game-designer + qa-lead + Martin
> **Last Updated**: 2026-04-27 (r2 cosmetic amendment after fresh /design-review)
> **Last Verified**: 2026-04-27
> **Implements Pillar**: Pillar 2 (LA PROGRESSION SE VOIT) primaire ; Pillar 4 (LES SECRETS RÉCOMPENSENT LE MOUVEMENT) secondaire ; Pillar 1 (FLOW AVANT TOUT) garde-fou (le crédit ne doit jamais interrompre)
> **Review history** : `design/gdd/reviews/credit-economy-system-review-r1-2026-04-27.md` — NEEDS REVISION (7 ship-blocking + 10 pre-impl + 9 polish pending separate r2 design session ; this r2 amendment addresses B-3 + OQ promotions only)

## Summary

Credit Economy est l'autoload qui maintient `total_credits` — l'unique compteur de monnaie permanente du joueur. Il crédite à chaque kill (+1 par grunt MVP) et chaque secret collecté (+5 / +10 / +15 selon tier 1/2/3), expose `try_spend(amount: int) -> bool` au Shop System, et émet `credits_changed(total, delta, source)` SYNC pour que le HUD voie le compteur monter dans le même `_physics_process` que le kill. Le système est stateless mécaniquement, persiste via Save/Load, et n'est jamais reset à la mort. Il sert **Pillar 2 (LA PROGRESSION SE VOIT)** comme contrat primaire — le `total_credits` est l'odomètre permanent qui matérialise la trajectoire personnelle du joueur — et **Pillar 4 (LES SECRETS RÉCOMPENSENT LE MOUVEMENT)** via l'asymétrie 5:1 minimum entre crédit-secret et crédit-kill.

> **Quick reference** — Layer: `Feature` · Priority: `MVP` · Key deps: `Enemy System (Designed r1), Secret System (Designed r1 — locked secret_collected SYNC), Shop System (Designed r1 — locked try_spend SYNC atomique), Save/Load System (Not Started — persist), Game State Manager (APPROVED r1), HUD System (Designed r1 — listens credits_changed SYNC, owns visual presentation)`

## Overview

CHROME://ASCENT est un action-platformer FPS solo construit sur quatre piliers, dont le second est **« la progression se voit »** : chaque upgrade achetée doit changer mesurablement ce que le joueur peut faire dans la tour. Credit Economy est le système qui rend cette promesse mathématiquement vraie. Il transforme deux types d'événements de jeu — **un kill ennemi** ou **un secret atteint via défi de mouvement** — en une unité unique de compte (`int total_credits`), qui sert ensuite à acheter des upgrades permanents au shop entre étages (double jump, dash horizontal MVP ; jusqu'à 5-8 upgrades en Full Vision). Le crédit n'est **jamais** un objet 3D à ramasser au sol : il est crédité au compteur instantanément à l'événement source, sans pause, sans pickup volume, sans course supplémentaire. Le système est volontairement minimaliste — un seul `int`, une seule monnaie, deux sources, un seul sink — pour garantir Pillar 1 FLOW (zéro overhead) et l'anti-pillar « pas de grinding ». Il existe parce que sans lui, la promesse Pillar 2 n'a pas de support mesurable : l'odomètre qui passe de 198 à 247 entre deux sessions est la trace tangible que le joueur a progressé, sans cinématique, sans level-up, sans HUD bavard.

## Player Fantasy

L'émotion centrale du Credit Economy, c'est le **compteur permanent qui grimpe**. Pas la collection, pas le grind, pas la dopamine du loot rare — juste un nombre, sobre, qui monte en haut à droite chaque fois que le joueur fait quelque chose qui méritait de monter. La référence directe, c'est les **gems de Ghostrunner** : un ticker discret qui s'incrémente quand tu enchaînes proprement, et qui vit en dehors de la boucle de combat parce que la boucle de combat se suffit à elle-même. On évite explicitement la **geo de Hollow Knight** — pas de petites pièces qui pop, pas d'aimant magnétique qui te fait courir derrière, pas de "shade" qui garde ton butin à la mort. La geo récompense le déplacement *vers* l'argent ; le crédit de CHROME://ASCENT récompense le déplacement *en lui-même*. Et on évite la **darkness de Hades** — le crédit n'est pas une devise méta-narrative qu'on dépense entre runs dans un hub social ; c'est une métrique d'ascension, lue par l'étage où on s'arrête, pas par le nombre de morts.

Chaque crédit doit se sentir **gagné par le mouvement**. Le grunt qu'on coupe en passant pendant un wallrun ne donne pas un crédit parce qu'on a "tué un ennemi" — il en donne un parce que le katana a touché au bon moment d'une trajectoire qu'on a choisie. Le crédit est la trace que la trajectoire a réussi. C'est pour cela qu'il n'y a aucun pickup au sol : ramasser, c'est s'arrêter, et s'arrêter, c'est rompre Pillar 1. Le crédit est crédité au moment exact de l'impact, le compteur fait un petit pulse de 150 ms, et le joueur est déjà en l'air. Le geste de gagner et le geste de jouer sont le même geste.

La tension avec Pillar 2 (« la progression se voit ») se résout dans la lecture du compteur lui-même. Le `total_credits` n'est pas un wallet de run qu'on remet à zéro ; c'est un odomètre permanent. Le joueur qui revient demain voit 247 au lieu de 198, et cette différence dit littéralement *« j'ai été plus fort hier qu'avant-hier »*. La progression visible ne passe pas par un level-up, ne passe pas par une cinématique, ne passe pas par un « vous avez débloqué » : elle passe par un chiffre qui ne diminue jamais, qui ne se reset jamais, et qui finit par acheter au shop un double-jump qui change *physiquement* ce que le joueur peut faire dans le niveau d'après. Le crédit est l'unité de compte de la trajectoire personnelle.

L'asymétrie 1 crédit / 5–10 crédits avec Pillar 4 doit être **viscérale, pas tabulaire**. Un kill, c'est un battement. Un secret, c'est un riff. Quand le joueur résout une cachette qui demandait trois wall-runs enchaînés et un dash mid-air, le compteur ne fait pas +1 cinq fois de suite — il saute d'un bloc, avec un son légèrement plus profond, plus long, qui dit « ça, c'était toi qui as compris quelque chose que personne ne t'a dit ». L'écart de valeur n'est pas un multiplicateur de balance, c'est une **reconnaissance ludique** : les secrets paient plus parce qu'ils demandent plus de skill, et le joueur doit *l'entendre* dans le feedback, pas le déduire d'une feuille de calcul.

Ce que le système ne fait **jamais** : pas de drop chance, pas de rareté, pas de RNG sur la valeur d'un crédit, pas de multiplicateur "kill streak ×1.5", pas de bonus zone, pas de perte de crédits à la mort, pas de timer de combo qui menace de s'éteindre, pas de currency secondaire à crafter. Le crédit ne se négocie pas, ne se perd pas, ne se vole pas, ne se boost pas. Sa valeur est lisible à l'œil nu et constante sur toute la durée de vie du save. Tout système qui rendrait le compteur *non-prédictible* le transformerait en machine à sous — et une machine à sous récompense le temps passé, pas le mouvement réussi.

> **North Star** : le crédit n'est jamais un objet à ramasser, c'est un ticker silencieux qui grimpe quand tu danses bien.

## Detailed Rules

### Core Rules

1. **Compteur unique, entier non-signé** — `total_credits : int` est l'unique variable d'état de Credit Economy. Elle est toujours `>= 0`, jamais flottante, jamais segmentée par run ou par étage. Il n'existe pas de « crédits de session » séparés des crédits persistants — un seul entier, une seule vérité.

2. **Irréversibilité à la mort** — La mort du joueur ne déduit aucun crédit. `total_credits` est inchangé entre `Player.die()` et la fin du cycle respawn. Le signal `state_changed(RESPAWNING)` du Game State Manager (APPROVED r1, ADR-0007 D-10) est observé mais ne déclenche aucune écriture sur `total_credits`. Contrat explicite : Credit Economy n'écoute ni `died`, ni `respawned`.

3. **Sources MVP exhaustives** — Deux sources de crédits existent au MVP, et uniquement deux : les kills ennemis (signal `enemy_killed`) et les secrets collectés (signal `secret_collected` — voir contrat provisoire Rule 9). Aucune autre source n'est autorisée au MVP : pas de bonus room clear, pas de time bonus, pas de streak multiplier. L'ajout de sources se fait par amendement GDD en Tier 2+ avec un nouvel enum `SourceKind` value.

4. **Sink unique** — Les crédits ne peuvent être dépensés que via `CreditEconomy.try_spend(amount: int) -> bool`. Il n'existe pas d'autre mécanisme de perte (pas de taxe, pas de decay, pas de coût caché au respawn). L'API `try_spend` est atomique : si `total_credits >= amount`, déduit et retourne `true` ; sinon, ne modifie rien et retourne `false`. Aucune exception, aucune transaction intermédiaire, aucun « panier ». Choix de l'API `try_spend` plutôt que `spend + can_afford` séparés : un appel atomique élimine la fenêtre de race condition entre le check et la dépense — le Shop System ne peut pas vérifier, puis être interrompu, puis dépenser un montant désormais invalide. **Edge cases atomiques** : `try_spend(0)` retourne `true` et n'émet pas de signal (no-op explicite, voir AC-CRD-05) ; `try_spend(amount < 0)` retourne `false` et `push_warning` (paramètre invalide, AC-CRD-06).

5. **Connexion event-driven aux ennemis** — Credit Economy est un autoload. Au chargement d'un étage, Credit Economy souscrit au signal `enemy_killed` de chaque grunt via `get_tree().get_nodes_in_group("enemies")`. Ce pattern de connexion (`autoload` + groupe Godot) est préféré à un signal bus centralisé car il conserve la traçabilité directe par instance et évite d'introduire un intermédiaire avant que le bus ne soit designé. Le Level System émet `level_active` (Level GDD R-2) au moment où les ennemis sont prêts — Credit Economy se connecte dans le handler de `level_active`, pas dans `_ready()`.

6. **Idempotence de kill** — Si le signal `enemy_killed` était réémis par bug pour le même ennemi (exemple : double-appel de `die()` contourné), Credit Economy filtre via un `Dictionary[int, bool] _credited_this_run` indexé par `enemy.get_instance_id()`. Si l'ID est déjà présent, le signal est ignoré. Ce dictionnaire est vidé au `request_new_run()` (GSM ADR-0007) ou au `level_active` suivant. Rappel : Enemy GDD Rule 6 garantit l'idempotence côté `die()` — ce filtre est une garde défensive côté Credit, pas une dépendance au comportement Enemy.

7. **Multi-kill simultané : 3 emits séquentiels** — `MAX_KILLS_PER_SWING = 3` (registry constant, source Combat GDD) peut générer jusqu'à 3 signaux `enemy_killed` dans le même `_physics_process` tick. Credit Economy traite chaque signal séquentiellement dans l'ordre de réception et émet 3 signaux `credits_changed` séquentiels dans le même tick. Décision retenue contre le batching en un seul emit : le batching complexifie le HUD (qui devrait séparer l'affichage de 1 vs 3 kills) et masque la granularité au analytics futur. Le HUD peut animer 3 incréments distincts (+1, +1, +1) ou les regrouper visuellement en aval — c'est une décision de présentation HUD, pas de Credit Economy.

8. **Émission synchrone du signal `credits_changed`** — Le signal `credits_changed(total: int, delta: int, source: SourceKind)` est émis SYNC (non CONNECT_DEFERRED) immédiatement après la mise à jour de `total_credits`. Justification : le HUD doit voir le compteur monter dans le même `_physics_process` que le kill pour respecter Pillar 1 (zéro overhead perçu — le nombre change au moment où l'ennemi meurt, pas une frame plus tard). L'émission SYNC depuis un autoload connecté à un signal Enemy est safe — aucun risque de mutation de scène pendant le callback car Credit Economy ne modifie que son propre état interne. **Cas particulier `try_spend` réussi** : émission `credits_changed(new_total, -amount, SPEND_SHOP)` SYNC dans le même call stack que l'appel `try_spend`. **Cas particulier BOOT_HYDRATE** : `delta == 0`, `source == BOOT_HYDRATE`, émis 1 fois après lecture Save/Load.

9. **[RESOLVED r2] Contrat Signal Secret System** — Credit Economy reçoit le signal `secret_collected(secret_node: Node, tier: int)` SYNC émis par Secret System (Designed r1 — R-SEC-08) quand un secret est collecté par le joueur. Ce signal est l'interface d'entrée canonique pour les crédits de type SECRET. `tier ∈ {1, 2, 3}` détermine le montant (voir F-CRD-2). Credit Economy n'impose aucune logique de détection — Secret System est l'autorité d'émission, Credit Economy est consumer pur. **Ce contrat est CONFIRMÉ par Secret r1 (2026-04-27)** : signature exacte `secret_collected(secret_node: Node, tier: int)` SYNC validée. OQ-CRD-1 promu RESOLVED dans la section Open Questions. Comportement défensif sur tier invalide (`tier ∉ {1, 2, 3}`) : ignore le signal, `push_warning`, aucun crédit accordé (AC-CRD-15).

10. **Comportement en pause** — Pendant `state_changed(PAUSED)` (GSM ADR-0007), Credit Economy ignore tout signal `enemy_killed` reçu. En pratique, Enemy System gèle son LaserCone et Combat System ne swing pas pendant la pause (Enemy GDD Rule : GSM state == PLAYING requis) — ce cas ne devrait pas se produire. Le contrat est documenté ici par défense : si un signal parvenait pendant PAUSED, le handler vérifie `GameStateManager.get_current_state() == State.PLAYING` avant de créditer.

11. **Boot hydration** — À la réception de `state_changed(PLAYING)` au démarrage, Credit Economy charge `total_credits` depuis Save/Load System (`SaveLoad.load_int("total_credits", 0)`). Immédiatement après, elle émet un signal `credits_changed(total_credits, 0, SourceKind.BOOT_HYDRATE)` pour que le HUD initialise son affichage sans attendre un premier gain. Si Save/Load retourne une valeur absente (première session) ou corrompue, `total_credits` est initialisé à `0` sans crash (AC-CRD-25).

12. **Persistance en quit-to-menu** — À `state_changed(MENU)`, Credit Economy écrit `total_credits` dans Save/Load (`SaveLoad.save_int("total_credits", total_credits)`). Les crédits survivent au quit-to-menu et à tout retour en MENU. Il n'y a pas de « reset de run » en Credit Economy : la persistance est la règle, la perte est l'exception réservée à `try_spend`.

13. **`SourceKind` enum** — Credit Economy définit l'enum `SourceKind { KILL = 0, SECRET = 1, SPEND_SHOP = 2, BOOT_HYDRATE = 3 }`. Ces 4 valeurs sont l'ensemble exhaustif MVP. Le champ `BOOT_HYDRATE` est réservé au signal d'hydratation initiale (`delta = 0`, pas un vrai gain). Le champ `SPEND_SHOP` est utilisé exclusivement par `try_spend` réussi (`delta < 0`). Les valeurs Tier 2+ (`BOSS_BONUS = 4`, `ROOM_CLEAR_BONUS = 5`) sont **réservées comme contrat futur** mais non implémentées au MVP. Cet enum est défini dans Credit Economy et consommé par HUD System — il est la source de vérité pour le typage des gains et dépenses.

### States and Transitions

Credit Economy est mécaniquement stateless : il n'existe pas d'enum d'état interne. L'autoload fonctionne en continu depuis son `_ready()` jusqu'au quit. Le lifecycle s'articule en deux phases fonctionnelles :

| Phase | Déclencheur | Comportement |
|-------|-------------|--------------|
| `INACTIVE` | De `_ready()` jusqu'au premier `state_changed(PLAYING)` | Aucun crédit ne peut être gagné ou dépensé. Les signaux `enemy_killed` reçus avant hydration sont ignorés (guard : `_is_hydrated == false`). |
| `ACTIVE` | Depuis `state_changed(PLAYING)` + hydration Save/Load réussie | Credit Economy opère normalement : crédite les kills/secrets, répond à `try_spend`, émet `credits_changed`. |

La phase ACTIVE est permanente jusqu'à quit du processus. Il n'existe pas de transition retour vers INACTIVE : le signal `state_changed(MENU)` persiste les crédits mais ne désactive pas l'autoload. Une nouvelle session (nouveau processus) recommence par INACTIVE.

### Interactions with Other Systems

| Système | Direction | Interface | Détails |
|---------|-----------|-----------|---------|
| **Enemy System** (Designed r1) | Amont — Credit reçoit | Signal `enemy_killed(enemy: Node, position: Vector3)` | Credit Economy se connecte au signal de chaque grunt au `level_active`. 1 signal = 1 crédit MVP grunt. Multi-kill (`MAX_KILLS_PER_SWING = 3`) = 3 signaux séquentiels le même tick → 3 crédits + 3 emits `credits_changed` séquentiels. Filtre idempotence via `get_instance_id()`. Contrat : Enemy GDD Rule 11 + registry entry `grunt.signals_emitted`. |
| **Secret System** (Designed r1) | Amont — Credit reçoit | Signal `secret_collected(secret_node: Node, tier: int)` SYNC *(LOCKED par Secret r1 R-SEC-08, OQ-CRD-1 RESOLVED)* | Credit crédite `BASE_SECRET_CREDIT × tier` crédits et émet `credits_changed(total, delta, SECRET)`. Le tier est fourni par Secret System dans le payload du signal. Contrat confirmé identique à la signature provisoire r1. |
| **Shop System** (Designed r1) | Aval — Shop appelle | `CreditEconomy.try_spend(amount: int) -> bool` SYNC atomique *(LOCKED par Shop r1 R-SHP-6, OQ-CRD-2 RESOLVED)* | API publique atomique. Shop vérifie la réponse booléenne pour confirmer ou annuler l'achat. Pas d'appel `can_afford` séparé — l'atomicité de `try_spend` est la garantie contre les races. Émission `credits_changed(new_total, -amount, SPEND_SHOP)` SYNC à `try_spend()` réussi. Confirmé identique à la signature provisoire r1. |
| **HUD System** (Designed r1) | Aval — HUD écoute | Signal `credits_changed(total: int, delta: int, source: SourceKind)` SYNC | HUD est **owner exclusif de la présentation visuelle** (HUD r1 R-6) — Credit Economy spec uniquement les **événements**, pas la durée des animations. HUD met à jour le compteur via tween SECRET / pulse KILL, ou hard-set silencieux pour SPEND_SHOP (Shop UI owns son propre tween de transaction). Émission SYNC depuis `_physics_process` (Rule 8). |
| **Save/Load System** (Not Started) | Aval — Credit écrit/lit | `SaveLoad.load_int(key, default)` + `SaveLoad.save_int(key, value)` | Au boot PLAYING : lecture `"total_credits"`. Au state_changed MENU : écriture `"total_credits"`. Format : `int` simple, pas de struct. |
| **Game State Manager** (APPROVED r1) | Amont — Credit observe | Signal `state_changed(new_state: State)` (ADR-0007 D-10) | PLAYING → hydration boot + activation. PAUSED → guard sur créditage (Rule 10). MENU → persistance save. RESPAWNING → aucune action (les crédits survivent). |

## Formulas

### F-CRD-1 : Crédits par kill (credits_per_kill)

Formule d'attribution de crédits au signal `enemy_killed` selon l'archétype de l'ennemi.

```
credits = kill_credit[archetype]
```

| Archétype | `kill_credit` | Tier | Source |
|-----------|--------------|------|--------|
| `grunt` | 1 | MVP | Enemy GDD entry `grunt` (registry) |
| `sentinelle` | 2 | Tier 2+ | Prévu — à confirmer Enemy GDD Tier 2 |
| `drone` | 1 | Tier 2+ | Prévu — faible (mobilité = difficulté compensée par secrets) |
| `brute` | 3 | Tier 2+ | Prévu — tanky relatif (multi-hits Phase B) |
| `sniper` | 2 | Tier 2+ | Prévu — dangereux mais statique |
| `mini-boss` | 5 | Tier 2+ | Prévu — pic de difficulté local |
| `boss_final` | 10 | Full Vision | Prévu — récompense de fin de run |

**Variables** :

| Variable | Symbol | Type | Valeur MVP | Description |
|----------|--------|------|-----------|-------------|
| `archetype` | — | StringName | `"grunt"` | Archétype de l'ennemi mort. Récupéré via `enemy.get_meta("archetype")` ou `enemy.archetype` si propriété publique Enemy GDD. |
| `kill_credit[archetype]` | k | int | 1 | Table de correspondance archétype → crédits. Définie dans `credit_config.tres` (Tuning Knob). |

**Output range** : MVP = `[1, 1]` (grunt unique). Tier 2+ = `[1, 10]`.

**Exemple worked (MVP)** : 3 grunts tués en un swing (`MAX_KILLS_PER_SWING = 3`) → 3 signaux `enemy_killed` → 3 × 1 cr = **+3 crédits**, `credits_changed` émis 3 fois séquentiellement le même tick.

**Cross-ref** : `MAX_KILLS_PER_SWING = 3` est une constante registry (source Combat GDD, referenced_by Enemy GDD, Audio GDD). Credit Economy la consomme implicitement : un swing peut générer au maximum 3 × `kill_credit["grunt"]` = 3 crédits par tick. Quand Tier 2+ intégrera de nouveaux archétypes, `kill_credit` sera étendu dans `credit_config.tres` sans modifier la formule.

---

### F-CRD-2 : Crédits par secret (credits_per_secret)

Formule d'attribution de crédits au signal `secret_collected` selon le tier de difficulté du secret.

```
credits = BASE_SECRET_CREDIT × secret.tier
```

| Variable | Symbol | Type | Valeur | Description |
|----------|--------|------|--------|-------------|
| `BASE_SECRET_CREDIT` | B | int | 5 | Crédit de base pour un secret Tier 1 (facile). Tuning Knob. |
| `secret.tier` | t | int ∈ {1, 2, 3} | — | Tier de difficulté du secret, fourni dans le payload `secret_collected`. |
| `credits` | c | int | 5 / 10 / 15 | Crédits attribués selon tier. |

**Output range** : `[5, 15]` (MVP). Tier ∉ {1,2,3} → ignore + push_warning (AC-CRD-15).

**Table de résultats** :

| Tier | Difficulté | Crédits | Équivalent kills |
|------|-----------|---------|-----------------|
| T1 | Facile (visible, chemin droit) | 5 cr | 5 kills grunt |
| T2 | Moyen (saut précis ou zone cachée) | 10 cr | 10 kills grunt |
| T3 | Difficile (séquence de mouvement, timing) | 15 cr | 15 kills grunt |

**Justification du ratio 5:1 (Pillar 4)** : un secret doit valoir au moins autant qu'une salle entière de grunts pour que l'exploration soit une alternative économiquement rationnelle au combat direct. Une salle COMBAT type MVP contient 3-5 grunts (Level GDD R-2.6 : `ARENA ≥ 3 EnemySlot`). Un secret T1 = 5 kills = toute une salle. Un secret T3 = 15 kills = 3-4 salles de combat. Ce ratio rend visible et tangible la promesse Pillar 4 « LES SECRETS RÉCOMPENSENT LE MOUVEMENT » sans exiger de narration ou d'UI dédiée.

**Exemple worked** : étage 1, joueur collecte 3 secrets (T1 + T2 + T2) → 5 + 10 + 10 = **25 crédits secrets**, contre 8 grunts × 1 = 8 crédits combat. Total secret >> combat confirmé.

---

### F-CRD-3 : Courbe de coût des upgrades (upgrade_cost_n)

Formule définissant le coût de l'upgrade d'index n dans le shop.

> **Amendement r2 (2026-04-27, design-review shop-system)** : convention `n` unifiée 0-based pour aligner avec F-SHP-1 (Shop). Avant amendement : `n ∈ [1, N_UPGRADES]` (1-based, rang). Après : `n ∈ [0, N_UPGRADES - 1]` (0-based, index). Arithmétiquement équivalent (rang 1 = index 0), mais évite le bug d'implémentation cross-GDD identifié en review.

```
cost_n = BASE_UPGRADE_COST + TIER_COST_STEP × n
```

| Variable | Symbol | Type | Valeur | Description |
|----------|--------|------|--------|-------------|
| `BASE_UPGRADE_COST` | B | int | 20 | Coût de l'upgrade à n=0 (la moins chère). Tuning Knob. |
| `TIER_COST_STEP` | S | int | 20 | Incrément linéaire entre deux upgrades consécutives. Tuning Knob. |
| `n` | n | int ∈ [0, N_UPGRADES - 1] | — | Index 0-based de l'upgrade par ordre croissant de prix. |
| `cost_n` | c | int | — | Coût en crédits de l'upgrade d'index n. |

**Output range** : MVP = `[20, 40]` (2 upgrades). Full Vision = `[20, 160]` (8 upgrades).

**Table MVP (2 upgrades, 0-based)** :

| n | Upgrade | Coût | Justification |
|---|---------|------|---------------|
| 0 | Double jump | 20 cr | Atteignable en 1 session sans secrets (8 grunts × 1 + mix minimal). Pillar 2 : la progression se voit dès la première session. |
| 1 | Dash horizontal | 40 cr | Nécessite secrets ou cumul cross-session — incite à explorer avant d'acheter. |

**Table Full Vision indicative (5-8 upgrades, 0-based)** :

| n | Coût indicatif |
|---|---------------|
| 0 | 20 cr |
| 1 | 40 cr |
| 2 | 60 cr |
| 3 | 80 cr |
| 4 | 100 cr |
| 5 | 120 cr |
| 6 | 140 cr |
| 7 | 160 cr |

**Justification courbe linéaire vs exponentielle** : une courbe exponentielle (coût × 2 par rang) produirait un « wall final » (upgrade n=8 à 2 560 cr si base=20 × 2^7) qui transforme les dernières upgrades en grind de dizaines de sessions — contradiction directe avec Pillar 1 FLOW et l'anti-pillar « pas de grinding ». La courbe linéaire garantit que l'upgrade la plus chère (n=8 à 160 cr) reste atteignable en 3-4 sessions riches en secrets, et que chaque session offre un progrès perceptible. La progression « se voit » (Pillar 2) à chaque session, pas seulement en fin de game.

---

### F-CRD-4 : Budget de session (session_yield_budget)

Modèle de validation économique global : vérifie que la promesse « 1 session = 1-2 upgrades » est mathématiquement tenue.

```
session_yield = kill_yield + secret_yield
kill_yield    = N_KILLS_SESSION × kill_credit["grunt"]
secret_yield  = Σ (BASE_SECRET_CREDIT × secret_i.tier)  pour i ∈ secrets_collectés
```

**Variables** :

| Variable | Symbol | Description |
|----------|--------|-------------|
| `N_KILLS_SESSION` | K | Nombre de grunts tués dans la session (tous étages) |
| `kill_credit["grunt"]` | k | 1 cr (F-CRD-1 MVP) |
| `secrets_collectés` | S | Ensemble des secrets trouvés dans la session |
| `session_yield` | Y | Total crédits gagnés dans la session |

**Output range visé** : `[8, 100]` cr par session MVP (étage 1+2 cumul).

**Worked example — Étage 1 (session minimale, combat-only)** :

- 8 grunts × 1 cr = 8 cr kills
- 0 secret collecté = 0 cr secrets
- `session_yield = 8 cr`
- Upgrade n=1 (20 cr) : non atteignable en 1 seul étage combat-only → **incitation à trouver des secrets ou rejouer**

**Worked example — Étage 1 (session normale, 3 secrets mix)** :

- 8 grunts × 1 cr = 8 cr kills
- 3 secrets : T1 (5 cr) + T2 (10 cr) + T2 (10 cr) = 25 cr secrets
- `session_yield = 33 cr`
- Upgrade n=1 (20 cr) : **atteignable** avec 13 cr en réserve

**Worked example — Étage 2 (session normale, 4 secrets mix)** :

- 12 grunts × 1 cr = 12 cr kills
- 4 secrets : T1 (5 cr) + T2 (10 cr) + T2 (10 cr) + T3 (15 cr) = 40 cr secrets
- `session_yield = 52 cr`
- Upgrade n=2 (40 cr) : **atteignable** avec 12 cr en réserve

**Worked example — Run complète MVP (étage 1 + étage 2, crédits accumulés)** :

- Étage 1 : 33 cr → achat upgrade n=1 (20 cr) → solde 13 cr
- Étage 2 : 52 cr gagnés → solde 13 + 52 = 65 cr → achat upgrade n=2 (40 cr) → solde 25 cr
- **2 upgrades achetées en 1 run de 2 étages** : promesse « 1-2 upgrades par session » tenue.

**Validation de la promesse économique** :

| Profil joueur | Session typique | Crédits gagnés | Upgrades achetées |
|---------------|----------------|---------------|------------------|
| Combat-only (ignore secrets) | Étage 1 : 8 kills | 8 cr | 0 — doit revenir ou explorer |
| Explorateur (3 secrets T1+T2+T2) | Étage 1 | 33 cr | 1 (n=1 à 20 cr) |
| Explorateur avancé (tous secrets) | Étage 1+2 | 85 cr | 2 (n=1 + n=2 = 60 cr) |

**Sanity check anti-inflation** : un run complet MVP (2 étages, tous secrets trouvés) génère au maximum ≈ 85-100 cr. Avec 2 upgrades MVP coûtant 20 + 40 = 60 cr, le solde résiduel maximum est ≈ 40 cr. Ce surplus n'est pas récupérable au MVP (pas d'upgrade n=3 disponible) et s'accumule pour Tier 2+ — ce comportement est intentionnel : les crédits épargnés créent une récompense psychologique anticipatoire (« je serai prêt pour la prochaine upgrade dès qu'elle sera disponible »). Aucun risque d'inflation dégénérative au MVP car le seul sink (Shop) est borné par `N_UPGRADES = 2`.

---

### Cross-system formula references

- **F-CRD-1 ↔ Enemy GDD entry `grunt`** : `archetype = "grunt"` ⟺ `kill_credit["grunt"] = 1`. Tier 2+ : F-CRD-1 sera étendu en parallèle des nouveaux archétypes Enemy.
- **F-CRD-1 ↔ Combat constant `MAX_KILLS_PER_SWING = 3`** : impose le plafond physique du yield kill par tick = 3 cr.
- **F-CRD-3 ↔ Upgrade System (Not Started)** : `N_UPGRADES = 2` MVP est figé par Upgrade System GDD futur. Credit Economy expose la courbe ; Upgrade System référence les coûts.
- **F-CRD-4 ↔ Level System (APPROVED r3)** : `N_KILLS_SESSION` borne par Level GDD R-2.6 (≥ 3 EnemySlot par ARENA × N_ARENA par étage MVP).

**Note registre cross-system** : les formules F-CRD-1 à F-CRD-4 introduisent les constantes `BASE_SECRET_CREDIT`, `BASE_UPGRADE_COST`, `TIER_COST_STEP`, et la table `kill_credit[]`. Ces constantes sont internes au Credit Economy au MVP (un seul GDD les consomme directement). Quand Shop System (consume `cost_n`) et HUD System seront designés, vérifier si l'une d'elles traverse la frontière de système — si oui, enregistrement registry requis à ce moment.

## Edge Cases

- **EC-CRD-1 — `try_spend(0)`** : retourne `true` immédiatement, `total_credits` inchangé, **aucun signal `credits_changed` émis** (pas de changement à signaler — UI ne doit pas pulse pour un no-op). Justification : un Shop System mal codé pourrait passer 0 par accident — Credit doit être tolérant et silencieux.

- **EC-CRD-2 — `try_spend(amount < 0)`** : retourne `false`, `total_credits` inchangé, `push_warning("Credit Economy: try_spend with negative amount: %d" % amount)` loggé. Aucun signal émis. Justification : un montant négatif serait un cadeau dérivé d'un bug Shop ; on refuse plutôt que d'ajouter accidentellement.

- **EC-CRD-3 — `try_spend(amount > total_credits)`** : retourne `false`, `total_credits` inchangé, aucun signal. Comportement attendu et fréquent (tentative d'achat avec solde insuffisant) — pas de log warning, juste un retour booléen.

- **EC-CRD-4 — `try_spend(amount == total_credits)`** : retourne `true`, `total_credits = 0`, signal `credits_changed(0, -amount, SPEND_SHOP)` émis. Le compteur peut atteindre 0 sans crash (pas de borne `> 0` imposée).

- **EC-CRD-5 — Multi-kill 3 séquentiels** : 3 emits `enemy_killed` reçus dans le même `_physics_process` tick → 3 incréments `total_credits` séquentiels + 3 emits `credits_changed` séquentiels (`total = N+1`, `N+2`, `N+3`). Voir Rule 7 pour rationale (granularité préservée pour HUD/analytics).

- **EC-CRD-6 — `enemy_killed` ré-émis pour le même `instance_id`** : Credit Economy détecte la collision dans `_credited_this_run`, ignore le 2ème emit, aucun crédit ajouté, aucun warning console (silent guard). Rappel : Enemy GDD Rule 6 garantit l'idempotence côté `die()` — ce filtre est défensif. AC-CRD-09 le verrouille.

- **EC-CRD-7 — `_restore_from_snapshot(was_dead=true)` côté Enemy** : Enemy ne re-émet PAS `enemy_killed` pendant le restore (Enemy EC-ENM-11). Credit ne reçoit donc rien et ne re-crédite pas. Le crédit a été comptabilisé au kill original ; le restore ne peut pas créer de double-crédit. AC-CRD-22 verrouille.

- **EC-CRD-8 — Save absent / corrompu au boot** : `SaveLoad.load_int("total_credits", 0)` retourne `0` (default) si la clé est absente ou si la valeur n'est pas castable en `int`. Credit hydrate `total_credits = 0`, émet `credits_changed(0, 0, BOOT_HYDRATE)`. Pas de crash, pas de prompt utilisateur — comportement silencieux pour première session ou save corrompu. AC-CRD-25.

- **EC-CRD-9 — Secret tier invalide (`tier ∉ {1, 2, 3}`)** : Credit Economy logue `push_warning("Credit Economy: invalid secret tier: %d" % tier)`, ignore le signal, aucun crédit attribué. Garde-fou contre Secret System mal codé en V1.

- **EC-CRD-10 — Signal `enemy_killed` reçu pendant `state_changed(PAUSED)`** : guard sur `GameStateManager.get_current_state() == State.PLAYING` rejette le signal. En pratique impossible (Enemy gèle son LaserCone, Combat ne swing pas pendant pause), mais documenté défensivement (Rule 10).

- **EC-CRD-11 — Signal `enemy_killed` reçu avant `state_changed(PLAYING)` (boot pré-hydration)** : guard sur `_is_hydrated == false` rejette le signal silencieusement. Aucun crédit attribué avant que Save/Load ait été lu. Cas attendu : le Level System charge avant que GSM passe à PLAYING (race au boot).

- **EC-CRD-12 — `total_credits` atteint `int.MAX` (cap théorique GDScript int 64-bit)** : non capé au MVP. Godot int est 64-bit signé (`9_223_372_036_854_775_807`) — un joueur devrait tuer 9 quintillions de grunts pour déborder, donc impossible. Tier 2+ pourra introduire un `MAX_CREDITS` knob si analytics révèle des saves anormalement gros (cap symbolique 9 999 ou 99 999 pour UX HUD à 4 chiffres).

- **EC-CRD-13 — Quit-to-menu sans avoir complété un étage** : à `state_changed(MENU)`, Save/Load écrit `total_credits` actuel. Les crédits gagnés au milieu d'un étage avant un quit volontaire **sont conservés** — il n'existe pas de notion « run complétée » pour la persistence. Les crédits sont permanents par essence (Pillar 2).

- **EC-CRD-14 — Crash / kill-process pendant le jeu** : si le processus est tué brutalement avant `state_changed(MENU)`, les crédits gagnés depuis le dernier save écrit sont perdus. **Décision MVP** : pas de auto-save sur `enemy_killed` — coût I/O à chaque kill incompatible Pillar 1. Risque acceptable au MVP solo. Tier 2+ pourra introduire auto-save par étage (à `level_active` next).

- **EC-CRD-15 — Connexion à un grunt manqué (signal pas connecté au spawn)** : si `_on_level_active()` rate la connexion d'un grunt (race timing avec Level System), ce grunt mort ne créditera pas. Garde-fou : assertion en debug que tous les nodes du groupe `"enemies"` ont leur signal `enemy_killed` connecté à Credit Economy. Production : silently failing — un kill perdu est invisible côté joueur.

- **EC-CRD-16 — Plusieurs runs back-to-back sans quit** : `request_new_run()` (GSM ADR-0007) est appelé. Credit Economy purge `_credited_this_run` (set d'IDs) mais **conserve `total_credits`** — c'est un nouveau run, pas une nouvelle vie économique. Comportement aligné Pillar 2 (la progression survit aux runs).

## Dependencies

### Hard dependencies (Credit Economy ne peut pas fonctionner sans ces systèmes)

| Système | Status | Direction | Nature |
|---------|--------|-----------|--------|
| **Enemy System** (Designed r1) | ✅ Designed | Amont | Émet `enemy_killed(enemy: Node, position: Vector3)` SYNC depuis `die()`. Sans Enemy, aucune source KILL — Credit n'a aucun crédit à attribuer. Contrat : Enemy GDD Rule 11 + registry entry `grunt`. |
| **Game State Manager** (APPROVED r1) | ✅ APPROVED | Amont | Émet `state_changed(new_state)` (ADR-0007 D-10). Credit observe pour : (1) hydratation au boot PLAYING ; (2) persistance à MENU ; (3) guard PAUSED. Sans GSM, Credit ne sait pas quand activer ni quand sauver. |
| **Save/Load System** (Not Started) | ❌ Pas designed | Aval | API `SaveLoad.load_int(key, default)` + `SaveLoad.save_int(key, value)`. Sans Save/Load, `total_credits` revient à 0 à chaque session — Pillar 2 cassé. **Bloqueur MVP** : Save/Load doit être designé avant l'implémentation Credit. |
| **Shop System** (Designed r1) | ✅ Designed r1 | Aval | Appelle `CreditEconomy.try_spend(amount: int) -> bool` SYNC atomique (R-SHP-6). Contrat `try_spend` **LOCKED** par Shop r1 — OQ-CRD-2 RESOLVED. Sans Shop, Credit accumule mais ne dépense jamais — la moitié du loop est cassée (gain → dépense). |

### Soft dependencies (système enrichi par mais fonctionne sans)

| Système | Status | Direction | Nature |
|---------|--------|-----------|--------|
| **Secret System** (Designed r1) | ✅ Designed r1 | Amont | Émet `secret_collected(secret_node: Node, tier: int)` SYNC (R-SEC-08). Contrat **LOCKED** par Secret r1 — OQ-CRD-1 RESOLVED. Sans Secret System, seuls les kills crédite — économie déséquilibrée vers le combat (anti-Pillar 4). |
| **HUD System** (Designed r1) | ✅ Designed r1 | Aval | Écoute `credits_changed(total, delta, source)` SYNC + pull `get_total()` au boot. HUD r1 R-6 owns la présentation visuelle (durées tween, hard-set silencieux SPEND_SHOP). Sans HUD, le compteur reste correct côté logique mais le joueur ne voit rien — Pillar 2 cassé visuellement. Pas un bloqueur fonctionnel mais critique UX. |
| **Audio System** (APPROVED r2.1) | ✅ APPROVED | Aval (latent) | Au MVP, Credit n'a pas de son propre — le clac kill est joué par Audio sur `enemy_killed` (Audio Rule 11). Tier 2+ pourra introduire un son distinct pour `credits_changed(source=SECRET)` (« riff secret » plus profond, voir Player Fantasy section 4). Aucun contrat Audio↔Credit MVP. |

### Cousins (latents — Tier 2+, pas MVP)

- **Upgrade System** (Not Started) — consommera la courbe `cost_n` (F-CRD-3) pour afficher les coûts dans le shop. Couplage indirect via Shop System.
- **VFX & Feedback System** (Not Started) — pourra écouter `credits_changed` pour pulse cyan HUD au gain. Owner du VFX = HUD System pas Credit.
- **Run Summary / Speedrun System** (Tier 3) — consommera `total_credits` pour afficher le diff session (« +52 cr cette run »). Lecture pure, aucun signal back-Credit.

### Bidirectional consistency check

- **Enemy GDD Rule 11 + registry `grunt.signals_emitted`** : « Émet `enemy_killed(self, global_position)` SYNC depuis `die()`. Consommé par Credit Economy, VFX, Audio, HUD » ✅ Credit GDD est référencé comme aval consumer.
- **Enemy GDD Section Interactions L167** : « Credit System écoute le signal Enemy (pas Combat — séparation des concerns) ; chaque kill = +X crédits selon archetype (MVP grunt = 1 credit ?) » ✅ Confirmé, ce GDD verrouille « 1 credit ».
- **Enemy GDD Section Dependencies L312** : « Credit Economy (Not Started) — Credit écoute `enemy_killed` pour incrémenter compteur joueur » ✅ Cohérent.
- **GSM GDD ADR-0007 D-10** : enum `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }` + signal `state_changed(new_state)` ✅ Credit utilise le bon contrat.
- **Combat GDD Rule 11 (APPROVED r6) référence `enemy_killed`** : Combat consomme le signal pour slow-mo. Credit consomme aussi indépendamment (pas de chaîne — séparation des concerns confirmée). Pas de conflit avec Credit.
- **Audio GDD r2.1 Rule 11** : Audio consomme `enemy_killed` pour bus `combat_kill`. Aucun couplage Audio↔Credit MVP. ✅
- **Level GDD R-2.6** : `ARENA ≥ 3 EnemySlot` borne `N_KILLS_SESSION` dans F-CRD-4. ✅ référence cohérente.

> **Bidirectional update status (r2 amendment 2026-04-27)** :
> - ✅ Secret System r1 — liste Credit Economy en aval consumer pour `secret_collected` (Secret §Dependencies + R-SEC-08).
> - ✅ Shop System r1 — liste Credit en amont sink (`try_spend`) (Shop §Quick reference + R-SHP-6).
> - ✅ HUD System r1 — liste Credit en amont source (`credits_changed` + `get_total()`) (HUD §Interactions + R-6).
> - ❌ Save/Load System (Not Started) — quand designé, doit lister Credit Economy comme consumer des helpers `load_int` / `save_int`.

## Tuning Knobs

### Configuration globale Credit Economy (`credit_config.tres`)

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------------|------------|-------------------|-------------------|
| `BASE_SECRET_CREDIT` | 5 | [3, 10] | Secrets paient plus → plus d'incitation à explorer (Pillar 4) → upgrades atteignables plus vite, risque de progression trop rapide | Secrets paient moins → ratio secret:kill se rapproche de 1:1 → Pillar 4 affaibli, économie penche vers combat |
| `kill_credit["grunt"]` | 1 | [1, 3] | Kills paient plus → économie penche vers combat, ratio secret:kill diminue → Pillar 4 affaibli | Kills paient 0 — interdit (économie devient secrets-only, sessions combat-only impossibles à monétiser) |
| `BASE_UPGRADE_COST` | 20 | [15, 40] | Upgrades plus chères → première upgrade nécessite plus de sessions → progression plus lente, frustration potentielle | Upgrades trop bon marché → joueur achète tout en 1 session → Pillar 2 dilué (la progression doit être étalée) |
| `TIER_COST_STEP` | 20 | [10, 40] | Courbe coût plus pentue → upgrades tardives deviennent difficiles → flirt avec « wall final » (anti-Pillar 1) | Courbe trop plate → toutes les upgrades coûtent ~pareil → pas de hiérarchie économique perceptible |
| `_credited_this_run` size | unbounded (Dictionary) | n/a | n/a | n/a |

> Les valeurs sont définies dans `data/balance/credit_config.tres` (Resource Godot) pour itération playtest sans recompilation.

### Tier-specific reward table (Tier 2+ extensible)

| Knob | MVP Value | Target Tier 2+ | Notes |
|------|-----------|----------------|-------|
| `kill_credit["grunt"]` | 1 | 1 | Stable — l'archetype baseline ne change pas |
| `kill_credit["sentinelle"]` | n/a | 2 | Tier 2+ |
| `kill_credit["drone"]` | n/a | 1 | Tier 2+ |
| `kill_credit["brute"]` | n/a | 3 | Tier 2+ |
| `kill_credit["sniper"]` | n/a | 2 | Tier 2+ |
| `kill_credit["mini-boss"]` | n/a | 5 | Tier 2+ |
| `kill_credit["boss_final"]` | n/a | 10 | Full Vision |

### Knobs latents (Tier 2+, hors MVP)

| Knob | Default Tier 2+ | Description |
|------|----------------|-------------|
| `MAX_CREDITS` | n/a (uncapped MVP) | Plafond optionnel pour contraindre l'UX HUD à 4 chiffres (9 999 ou 99 999). À introduire si analytics révèlent saves anormalement gros. |
| `BOSS_BONUS_AMOUNT` | 25 cr | Bonus crédité à `boss_defeated` (BOSS_BONUS = 4 dans `SourceKind` réservé). |
| `ROOM_CLEAR_BONUS_AMOUNT` | 0 cr (anti-Pillar 4) | Réservé désactivé par défaut — un bonus « room clear » récompenserait le combat sans skill, anti-Pillar 4. À débattre si playtest révèle des salles ennuyantes. |
| `AUTO_SAVE_ON_LEVEL_ACTIVE` | `false` | Trigger auto-save à chaque `level_active` du Level System (Tier 2+ pour réduire risque crash EC-CRD-14). |
| `BATCH_MULTI_KILL_EMIT` | `false` | Si `true`, batche les 3 emits multi-kill en 1 seul `credits_changed(N+3, +3, KILL_BATCH)`. À évaluer playtest si HUD sature visuellement. |

### Cross-tuning interactions

- **`BASE_SECRET_CREDIT × N_secrets_par_etage` doit ≥ `BASE_UPGRADE_COST`** : pour qu'un explorateur achète son upgrade en 1 étage, le yield secrets doit dépasser le coût upgrade. Knob réglable côté Level (densité secrets) ou côté Credit (`BASE_SECRET_CREDIT`).
- **`BASE_UPGRADE_COST + TIER_COST_STEP × (N_UPGRADES - 1) ≤ session_yield × 5`** : la dernière upgrade doit être atteignable en ~5 sessions max (Pillar 2 — la progression visible doit aboutir avant fatigue). Avec MVP : 40 + 20 × (2-1) = 40 cr ≤ session_yield (33-52 cr) × 5 = 165-260 cr ✅.
- **Si `BATCH_MULTI_KILL_EMIT == true`, alors HUD doit afficher `+N`** : sinon le joueur ne voit qu'1 incrément pour 3 kills (perception cassée). Couplage Credit↔HUD à confirmer si knob activé.

## Visual/Audio Requirements

> **Note d'architecture** : Credit Economy est un **système purement data** — il ne possède aucun `Node3D`, aucun `MeshInstance3D`, aucun `AudioStreamPlayer`, aucun shader propre. Tout le rendu visible et audible des événements crédits est délégué à **HUD System** (compteur + pulse VFX) et à **Audio System** (clac kill + son secret futur). Cette section documente les **événements** que Credit émet et **les requirements imposés aux consumers** — pas de l'implémentation visuelle/audio dans Credit lui-même.

### Visual

> **r2 amendment B-3** : Credit Economy spec uniquement les **événements** émis ; HUD r1 (Designed r1) est **owner exclusif** de la durée des animations, des courbes d'easing, et du choix hard-set vs tween. Les valeurs ci-dessous sont des **requirements pillar-driven** ; les durées exactes appartiennent à `design/gdd/hud-system.md` §J Visual Requirements.

| Event Credit | Source signal | Owner du rendu | VFX requirement (pillar-driven) | Pillar contrat |
|--------------|---------------|----------------|----------------------------------|----------------|
| Gain crédit kill | `credits_changed(_, +1, KILL)` | HUD System | Compteur `total` mis à jour avec pulse visible mais court. AUCUNE pause, AUCUNE animation full-screen. Durée exacte → HUD GDD §J. | Pillar 1 FLOW — animation < 200 ms, ne bloque pas le combat |
| Gain crédit secret | `credits_changed(_, +5/+10/+15, SECRET)` | HUD System | Compteur mis à jour avec feedback **différencié et plus marqué** que le kill (durée et/ou pulse plus long, flash icône secret optionnel). Reconnaissance ludique distincte du kill (Pillar 4 viscéral pas tabulaire). Durée exacte → HUD GDD §J. | Pillar 4 — l'asymétrie 5:1 doit être *vue* dans le feedback, pas seulement lue dans le chiffre |
| Boot hydrate | `credits_changed(N, 0, BOOT_HYDRATE)` | HUD System | Compteur initialisé silencieusement (NO pulse, NO VFX) — c'est juste l'affichage initial. | Pillar 1 — pas de spam visuel à chaque load |
| Dépense shop | `credits_changed(N, -amount, SPEND_SHOP)` | HUD System + Shop UI | HUD hard-set silencieux du compteur (HUD r1 R-6) ; Shop UI owns son propre tween de transaction (Shop r1 R-SHP J-tween 300 ms). Le compteur HUD doit être à jour avant que Shop UI commence son tween. | UX — la dépense est visible via Shop UI animation, pas via animation HUD double |

**Couleur d'accent** : cyan (cohérent avec game-concept Visual Identity Anchor — « cyan = secret/interactif » — et le crédit est un objet d'interaction permanente). Le rouge (réservé au sang/hostile) n'est **jamais** utilisé pour un compteur positif.

**Anti-spec — ce que Credit ne doit JAMAIS demander aux consumers** :

- Pas d'animation full-screen au gain (anti-Pillar 1).
- Pas de pickup volume 3D ni de magnet pickup au sol (Player Fantasy : « le crédit n'est jamais un objet à ramasser »).
- Pas de combo counter affiché en plus du `total_credits` (multiplicateur = anti-pattern game-concept).
- Pas de splash screen « +X CREDITS » qui couvre l'action (anti-Pillar 1).

### Audio

> **Source de vérité** : Audio System GDD r2.1 + ADR-0009 D-1 figent les bus names et la pool architecture. Credit Economy est **consumer aval** d'Audio uniquement via les sons déjà associés aux signaux upstream (`enemy_killed`, `secret_collected`) — Credit n'instancie aucun `AudioStreamPlayer` lui-même.

| Event Credit | Audio actuel | Bus | Notes |
|--------------|--------------|-----|-------|
| Gain crédit kill | **Clac kill déjà joué par Audio sur `enemy_killed`** (Audio Rule 11, bus `COMBAT_KILL`) | `COMBAT_KILL` | Aucun son additionnel Credit MVP. Le clac est la signature audio du kill — il sert simultanément Combat, Enemy mort, et Credit gagné. |
| Gain crédit secret | **Son joué par Secret System (futur) sur `secret_collected`** | bus à définir Secret GDD | Credit ne demande aucun son spécifique au MVP. Tier 2+ pourra introduire un « riff secret » distinct du clac kill (bus dédié `SECRET_REWARD` ?) selon Player Fantasy section 4. |
| Boot hydrate | **Aucun son** | n/a | Initialisation silencieuse — pas de cue audio au load. |
| Dépense shop | **Son shop joué par Shop System (futur) sur transaction** | bus à définir Shop GDD | Credit ne demande aucun son. Le « caching » sonore est délégué à Shop UI. |

**Aucun son propre Credit Economy au MVP** — le système est silencieux par design. Cette absence est volontaire et alignée avec l'anti-spec « pas de splash + pas de timer + pas de jingle ».

> **📌 Asset Spec** — Credit Economy n'a aucun asset visuel ou audio à produire. Si un asset est requis (ex. icône cyan « ¢ » du HUD), il appartient à HUD System et sera spécifié dans `design/gdd/hud-system.md` (à designer Sprint A). Pas d'asset-spec Credit-only à générer.

## UI Requirements

> **Note d'architecture** : la **présentation HUD** du compteur de crédits appartient à **HUD System GDD** (à designer Sprint A — voir Systems Index #17). Credit Economy spécifie ici les **données et événements** que le HUD doit consommer. La spec UX précise (typographie, dimensions, position pixel-perfect, animation curves) sera produite via `/ux-design` après le HUD GDD.

| Information | Source | Display Location | Update Frequency | Condition |
|-------------|--------|-----------------|-----------------|-----------|
| `total_credits` (chiffre courant) | Lecture `CreditEconomy.get_total()` ou cache après `credits_changed` | Haut-droite HUD (cohérent game-concept layout) | À chaque `credits_changed` | Toujours visible pendant `state_changed(PLAYING)` ; caché pendant `MENU` et écran shop (le shop affiche son propre solde) |
| Pulse VFX gain | Signal `credits_changed(total, delta>0, source)` | Compteur HUD | À chaque `delta > 0` | KILL = pulse 150 ms cyan ; SECRET = pulse 200-300 ms cyan + flash icône |
| Animation soustraction | Signal `credits_changed(total, delta<0, SPEND_SHOP)` | Compteur HUD + écran shop | À chaque `delta < 0` | Counter tween 200-400 ms ; pulse rouge bref optionnel |
| Indicateur affordance shop | Lecture `CreditEconomy.get_total()` vs cost upgrade | Écran shop (pas HUD principal) | Static display lors de l'ouverture shop | Highlight les upgrades affordables vs lockées |

> **📌 UX Flag — Credit Economy** : ce système expose des données HUD. En Phase 4 (Pre-Production), avant d'écrire les epics HUD, exécuter `/ux-design` pour créer les UX specs `design/ux/hud.md` et `design/ux/shop-screen.md`. Ces specs référenceront ce GDD pour les contrats data, mais détailleront la présentation visuelle (positioning, typography, motion curves) — ce GDD ne fixe que les **événements et requirements de feedback**, pas la pixel-art.

> **À noter dans systems-index** : Credit Economy a une UI requirement → flag UX requis pour HUD + Shop avant epics.

### Contrat HUD ↔ Credit (interface signal)

```gdscript
# HUD se connecte au boot, dans son _ready() :
CreditEconomy.credits_changed.connect(_on_credits_changed)

func _on_credits_changed(total: int, delta: int, source: SourceKind) -> void:
    _credit_label.text = str(total)
    if source == SourceKind.BOOT_HYDRATE:
        return  # pas de VFX pour init
    if delta > 0:
        _trigger_gain_pulse(source)  # KILL ou SECRET
    elif delta < 0:
        _trigger_spend_animation()
```

Cette connexion est **outbound-only** côté HUD — Credit Economy ne référence jamais HUD directement (séparation des concerns, comme Movement→Camera ADR-0005 D-10).

## Cross-References

| This Document References | Target GDD | Specific Element Referenced | Nature |
|--------------------------|-----------|----------------------------|--------|
| `enemy_killed(enemy: Node, position: Vector3)` SYNC payload depuis `die()` | `design/gdd/enemy-system.md` | Enemy GDD Rule 11 + entry `grunt.signals_emitted` (registry) | State trigger |
| Idempotence `die()` | `design/gdd/enemy-system.md` | Enemy GDD Rule 6 | Rule dependency |
| `_restore_from_snapshot(was_dead=true)` ne re-émet pas | `design/gdd/enemy-system.md` | Enemy GDD EC-ENM-11 | Rule dependency |
| `MAX_KILLS_PER_SWING = 3` plafond multi-kill par tick | `design/gdd/player-combat-system.md` | Combat GDD constant + registry | Data dependency |
| `state_changed(new_state)` enum `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }` | `design/gdd/game-state-manager.md` | GSM GDD enum + signal API | State trigger |
| `request_new_run()` purge `_credited_this_run` | `design/gdd/game-state-manager.md` | GSM GDD verbe public + ADR-0007 D-10 | State trigger |
| `level_active` connexion event-driven aux ennemis | `design/gdd/level-system.md` | Level GDD R-2 signal `level_active` | State trigger |
| `N_ARENA × N_EnemySlot` borne yield kill | `design/gdd/level-system.md` | Level GDD R-2.6 (`ARENA ≥ 3 EnemySlot`) | Data dependency |
| `BASE_FOV` indirect (HUD ne dépend pas) | n/a | n/a | (no dependency) |
| Visual Identity « cyan = secret/interactif » | `design/gdd/game-concept.md` | game-concept.md Visual Identity Anchor | Rule dependency |
| Pillar 1 FLOW (zéro overhead) | `design/gdd/game-concept.md` | Pillar 1 design test | Rule dependency |
| Pillar 2 LA PROGRESSION SE VOIT | `design/gdd/game-concept.md` | Pillar 2 design test | Rule dependency |
| Pillar 4 LES SECRETS RÉCOMPENSENT MOUVEMENT | `design/gdd/game-concept.md` | Pillar 4 design test | Rule dependency |
| Audio bus `COMBAT_KILL` joue clac kill | `design/gdd/audio-system.md` | Audio GDD r2.1 Rule 11 + ADR-0009 D-1 | Data dependency |
| `secret_collected(secret_node: Node, tier: int)` PROVISOIRE | `design/gdd/secret-system.md` *(Not Started)* | À designer — contrat provisoire défini par ce GDD (OQ-CRD-1) | Ownership handoff |
| `SaveLoad.load_int(key, default)` + `save_int(key, value)` | `design/gdd/save-load-system.md` *(Not Started)* | À designer — Credit assume API simple int-keyed | Ownership handoff |
| `try_spend(amount: int) -> bool` invoqué par Shop | `design/gdd/shop-system.md` *(Not Started)* | À designer — Credit expose l'API Shop appellera | Ownership handoff |
| `credits_changed(total, delta, source)` consommé par HUD | `design/gdd/hud-system.md` *(Not Started)* | À designer — Credit expose le signal HUD écoutera | Ownership handoff |

## Acceptance Criteria

> **49 ACs total** — 48 BLOCKING (Logic + Integration + Performance + Lint), 1 ADVISORY (Visual/Feel). ACs provisoires marqués sur dépendances Secret/Shop/Save-Load (à raffermir lors du design de ces systèmes).

### Core invariants

- **AC-CRD-01 [Logic]** : GIVEN le système Credit Economy est initialisé, WHEN `total_credits` est interrogé à n'importe quel point du cycle de vie, THEN `total_credits >= 0` est toujours vrai — le compteur ne peut jamais être négatif. *Mécanisme* : unit test qui appelle `try_spend(9999)` sur un compte à 0 et vérifie que `total_credits == 0` après.
- **AC-CRD-02 [Logic]** : GIVEN `total_credits == N`, WHEN `try_spend(amount)` est appelé avec `amount > N`, THEN la fonction retourne `false`, `total_credits` reste `== N`, et aucun signal `credits_changed` n'est émis. *Mécanisme* : unit test avec spy sur `credits_changed` — vérifier 0 appels.
- **AC-CRD-03 [Logic]** : GIVEN `total_credits == N`, WHEN `try_spend(amount)` est appelé avec `amount == N`, THEN la fonction retourne `true`, `total_credits == 0`, et `credits_changed(0, -N, SPEND_SHOP)` est émis.
- **AC-CRD-04 [Logic]** : GIVEN n'importe quelle séquence d'opérations source/sink, WHEN `total_credits` est consulté, THEN sa valeur est toujours égale à `credits_at_boot + sum(gains) - sum(spends)` — invariant comptable. *Mécanisme* : unit test avec journal d'opérations et vérification de l'invariant en fin de séquence.
- **AC-CRD-05 [Logic]** : GIVEN `try_spend(0)` est appelé, WHEN le montant est zéro, THEN la fonction retourne `true`, `total_credits` reste inchangé, et aucun signal `credits_changed` n'est émis. *Mécanisme* : unit test — vérifier retour true, compteur stable, 0 émission de signal.
- **AC-CRD-06 [Logic]** : GIVEN `try_spend(-5)` est appelé avec un montant négatif, WHEN le paramètre est invalide, THEN la fonction retourne `false` sans modifier `total_credits`, et un message d'erreur est poussé dans les logs Godot (`push_warning` ou `push_error`). *Mécanisme* : unit test interceptant `ERR_HANDLER` ou vérifiant le retour false + compteur stable.

### Source KILL

- **AC-CRD-07 [Logic]** : GIVEN `total_credits == N` et un grunt ennemi est tué, WHEN `enemy_killed(enemy_node, position)` est émis par Enemy System, THEN `total_credits == N + 1` et `credits_changed(N+1, +1, KILL)` est émis dans le même physics frame. *Mécanisme* : unit test avec mock Enemy émettant le signal, vérification compteur + payload signal.
- **AC-CRD-08 [Logic]** : GIVEN 3 ennemis distincts meurent dans le même tick physics (multi-kill swing katana), WHEN 3 émissions `enemy_killed` arrivent séquentiellement dans `_physics_process`, THEN `total_credits` augmente de 3, et exactement 3 signaux `credits_changed` sont émis dans cet ordre : `(N+1, +1, KILL)`, `(N+2, +1, KILL)`, `(N+3, +1, KILL)`. *Mécanisme* : unit test avec spy sur `credits_changed` enregistrant l'ordre et le payload de chaque appel.
- **AC-CRD-09 [Logic]** : GIVEN un grunt a déjà été comptabilisé (`instance_id` enregistré), WHEN `enemy_killed` est ré-émis pour le **même** `enemy.get_instance_id()`, THEN `total_credits` n'est PAS incrémenté et aucun signal `credits_changed` n'est émis. *Mécanisme* : unit test — émettre deux fois le même signal avec le même node mock, vérifier compteur stable après le 2ème et spy à 0 appel.
- **AC-CRD-10 [Logic]** : GIVEN le set d'IDs vus contient des entrées de l'étage précédent, WHEN `_on_level_unloaded()` est appelé (fin d'étage), THEN le set d'IDs vus est vidé (`seen_ids.size() == 0`) ET `total_credits` est inchangé. *Mécanisme* : unit test — peupler le set, déclencher unload, vérifier les deux conditions indépendamment.
- **AC-CRD-11 [Integration]** : GIVEN `MAX_KILLS_PER_SWING == 3` (Combat-side enforcement), WHEN exactement 3 ennemis distincts meurent sur le même swing, THEN `total_credits` augmente de exactement 3 — pas plus. *Note* : si un 4ème `enemy_killed` arrive sur le même tick (bug Combat), il est ignoré seulement si déjà dans `_credited_this_run`. Cet AC dépend du contrat Combat MAX_KILLS_PER_SWING.

### Source SECRET (provisoire)

> Note : provisional — Secret System GDD pending. Ces ACs utilisent un mock de signal en attendant le contrat définitif.

- **AC-CRD-12 [Logic]** : GIVEN un secret de tier 1 est collecté (mock `secret_collected(secret_node, tier=1)`), WHEN `credits_changed` est capturé, THEN `delta == +5` et `source == SECRET`. *Mécanisme* : unit test avec mock signal, spy sur `credits_changed`.
- **AC-CRD-13 [Logic]** : GIVEN un secret de tier 2 est collecté (mock `secret_collected(secret_node, tier=2)`), WHEN `credits_changed` est capturé, THEN `delta == +10` et `source == SECRET`.
- **AC-CRD-14 [Logic]** : GIVEN un secret de tier 3 est collecté (mock `secret_collected(secret_node, tier=3)`), WHEN `credits_changed` est capturé, THEN `delta == +15` et `source == SECRET`.
- **AC-CRD-15 [Logic]** : GIVEN un tier inconnu ou invalide (`tier=0`, `tier=99`) est reçu, WHEN Credit Economy traite `secret_collected(node, tier=invalid)`, THEN aucun crédit n'est accordé, `total_credits` reste inchangé, et un `push_warning` est loggé. *Mécanisme* : unit test vérifiant compteur stable + log intercepté.
- **AC-CRD-16 [Logic]** : GIVEN Pillar 4 — LES SECRETS RÉCOMPENSENT LE MOUVEMENT, WHEN on compare le gain d'un secret tier 1 vs un kill grunt, THEN `secret_tier1_reward (5) >= 5 × kill_reward (1)` — ratio plancher respecté. *Mécanisme* : unit test asserting `BASE_SECRET_CREDIT × 1 >= 5 × kill_credit["grunt"]`.

### Sink Shop — `try_spend` (provisoire)

> Note : provisional — Shop GDD pending. Ces ACs utilisent un appel direct à l'API `CreditEconomy.try_spend()` sans dépendance au ShopSystem réel.

- **AC-CRD-17 [Logic]** : GIVEN `total_credits == 10`, WHEN `try_spend(10)` est appelé, THEN retourne `true`, `total_credits == 0`, `credits_changed(0, -10, SPEND_SHOP)` émis.
- **AC-CRD-18 [Logic]** : GIVEN `total_credits == 10`, WHEN `try_spend(11)` est appelé, THEN retourne `false`, `total_credits == 10`, aucun signal émis. *Mécanisme* : spy sur `credits_changed` — 0 appels.
- **AC-CRD-19 [Logic]** : GIVEN `total_credits == 5`, WHEN deux appels `try_spend(3)` se produisent séquentiellement dans le même frame, THEN le premier retourne `true` (`total_credits == 2`), le second retourne `false` (`total_credits == 2` inchangé). *Mécanisme* : unit test séquentiel — vérifier état intermédiaire après chaque appel.
- **AC-CRD-20 [Logic]** : GIVEN `try_spend(amount)` est appelé, WHEN l'opération est exécutée, THEN elle est atomique : aucun état intermédiaire n'est observable entre la vérification du solde et la déduction. *Mécanisme* : impossible en single-thread GDScript de rompre l'atomicité — documenter comme assertion architecturale dans le test (pas de `await`, pas de signal intermédiaire entre check et deduct).
- **AC-CRD-21 [Logic]** : GIVEN Pillar 1 — FLOW AVANT TOUT, WHEN `try_spend` est appelé, THEN aucun `await`, aucun signal asynchrone, aucun deferred call n'est effectué dans le chemin d'exécution de `try_spend` lui-même. *Mécanisme* : revue de code statique — chercher `await` dans la fonction `try_spend`.

### Persistence

- **AC-CRD-22 [Logic]** : GIVEN `total_credits == 42` au moment d'un respawn, WHEN `_restore_from_snapshot(was_dead=true)` est appelé côté Enemy System (et Enemy NE re-émet PAS `enemy_killed`), THEN `total_credits` reste `== 42` après le respawn — aucun crédit perdu, aucun crédit ajouté. *Mécanisme* : unit test — simuler le respawn sans émettre `enemy_killed`, vérifier compteur stable.
- **AC-CRD-23 [Integration]** : GIVEN `total_credits == 42` et le joueur quitte via "Quit to Menu", WHEN le jeu sauvegarde et la session est terminée, THEN à la prochaine session, après hydratation depuis savegame, `total_credits == 42`. *Mécanisme* : test d'intégration avec Save/Load mock — sauvegarder state, reset système, hydrater depuis save, vérifier compteur.
- **AC-CRD-24 [Integration]** : GIVEN le joueur démarre une nouvelle session, WHEN `state_changed(PLAYING)` est reçu du GSM au boot, THEN Credit Economy hydrate `total_credits` depuis le savegame ET émet `credits_changed(loaded_value, 0, BOOT_HYDRATE)`. *Mécanisme* : test d'intégration avec GSM mock et Save/Load mock — spy sur signal `credits_changed` capturant `source == BOOT_HYDRATE`.
- **AC-CRD-25 [Logic]** : GIVEN un savegame absent ou corrompu, WHEN Credit Economy tente d'hydrater, THEN `total_credits` est initialisé à `0` sans crash, et `credits_changed(0, 0, BOOT_HYDRATE)` est émis. *Mécanisme* : unit test avec Save/Load mock retournant null ou données invalides.
- **AC-CRD-26 [Integration]** : GIVEN `total_credits == 30`, le joueur joue, gagne 5 crédits (`total_credits == 35`), puis meurt et respawn, WHEN le respawn est complété, THEN `total_credits == 35` (la progression est préservée — « tu ne perds jamais ce que tu as gagné »). *Mécanisme* : test d'intégration Enemy → Credit → respawn — vérifier compteur avant/après.
- **AC-CRD-27 [Logic]** : GIVEN un round-trip save/load complet, WHEN `total_credits` est sauvegardé puis rechargé, THEN la valeur rechargée est identique bit-pour-bit à la valeur sauvegardée (pas de truncation float, stocké en int). *Mécanisme* : unit test — sauvegarder valeur entière max plausible (ex. 9 999), recharger, assertEqual.

### Signal `credits_changed`

- **AC-CRD-28 [Logic]** : GIVEN un crédit est gagné ou dépensé, WHEN `credits_changed(total, delta, source)` est émis, THEN `total` reflète le nouveau total APRÈS la modification, `delta` est la variation nette signée (`+N` pour gain, `-N` pour spend). *Mécanisme* : unit test — capturer payload et vérifier `total == expected_new_total` et `delta == expected_delta`.
- **AC-CRD-29 [Logic]** : GIVEN Pillar 2 — LA PROGRESSION SE VOIT, WHEN un kill est enregistré dans `_physics_process` au tick T, THEN `credits_changed` est émis SYNC dans ce même tick T — pas de `call_deferred`, pas d'`await`, pas de frame delay. *Mécanisme* : unit test — vérifier que le signal est émis dans le même appel à `_physics_process` en inspectant l'ordre d'exécution (signal connecté avec flag 0, pas CONNECT_DEFERRED).
- **AC-CRD-30 [Logic]** : GIVEN un boot hydrate, WHEN `credits_changed` est émis avec `source == BOOT_HYDRATE`, THEN `delta == 0` (pas de variation, juste une notification de valeur courante).
- **AC-CRD-31 [Logic]** : GIVEN un multi-kill de 3 ennemis dans le même tick, WHEN les 3 signaux `credits_changed` sont émis, THEN ils sont émis dans l'ordre séquentiel des kills : le 1er signal a `total == N+1`, le 2ème `total == N+2`, le 3ème `total == N+3`. *Mécanisme* : unit test avec liste d'appels capturés en ordre — `received_signals[0].total < received_signals[1].total < received_signals[2].total`.
- **AC-CRD-32 [Logic]** : GIVEN le signal `credits_changed` est déclaré dans CreditEconomy, WHEN le contrat de signal est inspecté statiquement, THEN la signature est `signal credits_changed(total: int, delta: int, source: SourceKind)` avec types statiques stricts — pas de `Variant`. *Mécanisme* : grep sur le fichier source ou GdUnit4 assertant les types des paramètres du signal.

### Cross-system integration

- **AC-CRD-33 [Integration]** : GIVEN Enemy System est actif et un grunt meurt en jeu réel (pas de mock), WHEN le signal `enemy_killed` est émis par EnemySystem, THEN CreditEconomy reçoit le signal, incrémente `total_credits` de 1, et `credits_changed` est émis avant la fin du même `_physics_process`. *Mécanisme* : test d'intégration avec EnemySystem réel (ou stub minimal) — vérifier le flux de bout en bout.
- **AC-CRD-34 [Integration]** : GIVEN Secret System mock émet `secret_collected(mock_node, tier=2)`, WHEN CreditEconomy reçoit le signal, THEN `total_credits` augmente de 10 et `credits_changed(N+10, +10, SECRET)` est émis. *Mécanisme* : test d'intégration avec Secret System stub. *Note* : provisional — Secret System GDD pending.
- **AC-CRD-35 [Integration]** : GIVEN ShopSystem appelle `CreditEconomy.try_spend(cost)` lors d'un achat, WHEN le joueur a suffisamment de crédits, THEN `try_spend` retourne `true`, `total_credits` est décrémenté, et ShopSystem peut procéder à la transaction sans second appel de vérification. *Mécanisme* : test d'intégration avec Shop stub. *Note* : provisional — Shop GDD pending.

### GSM observation

- **AC-CRD-36 [Integration]** : GIVEN le jeu est en état `PAUSED`, WHEN `enemy_killed` est émis (théoriquement impossible en pause, mais testé défensivement), THEN CreditEconomy ne traite pas le signal — `total_credits` reste inchangé. *Mécanisme* : test d'intégration avec GSM mock en PAUSED — émettre signal manuellement, vérifier compteur stable.
- **AC-CRD-37 [Logic]** : GIVEN le jeu est en état `MENU` (pas encore PLAYING), WHEN CreditEconomy est interrogé sur `total_credits`, THEN la valeur retournée est `0` ou la valeur chargée depuis save — pas de reset intempestif, pas de modification. *Mécanisme* : unit test — initialiser en état MENU, vérifier que le compteur n'est pas réinitialisé à la transition MENU → PLAYING (seul BOOT_HYDRATE la fixe).
- **AC-CRD-38 [Logic]** : GIVEN le GSM passe de PLAYING à PAUSED puis revient à PLAYING, WHEN les transitions d'état sont complètes, THEN `total_credits` est identique avant et après la pause — la pause ne modifie pas le compteur. *Mécanisme* : unit test — capturer valeur avant pause, simuler transitions, vérifier égalité.

### Performance

- **AC-CRD-39 [Performance]** : GIVEN un tick `_physics_process` avec 3 kills simultanés (multi-kill max, `MAX_KILLS_PER_SWING == 3`), WHEN le traitement complet (3 incréments + 3 émissions `credits_changed`) est mesuré, THEN le temps d'exécution total du bloc Credit Economy dans ce tick est `< 0.1 ms`. *Mécanisme* : benchmark GdUnit4 avec timer entourant le bloc de traitement — seuil basé sur budget frame 16.6 ms Pillar 1 (Credit ne doit pas dépasser 0.6% du budget).
- **AC-CRD-40 [Performance]** : GIVEN le boot hydrate depuis savegame au démarrage, WHEN `_on_state_changed(PLAYING)` est reçu et l'hydratation est complète, THEN le temps d'exécution de l'hydratation (lecture save + assign + emit signal) est `< 2 ms`. *Mécanisme* : benchmark avec chrono Godot `Time.get_ticks_usec()` avant/après — seuil basé sur budget boot acceptable sans freeze frame visible.

### Lints / Static

- **AC-CRD-41 [Logic]** : GIVEN CreditEconomy est un autoload Godot, WHEN le projet est chargé et `Engine.get_singleton("CreditEconomy")` est appelé, THEN exactement une instance de CreditEconomy existe dans la scène — pas de duplication possible. *Mécanisme* : unit test assertant `Engine.has_singleton("CreditEconomy") == true` et que le node retourné est le même à deux appels successifs (même `get_instance_id()`).
- **AC-CRD-42 [Logic]** : GIVEN le signal `credits_changed` est déclaré, WHEN une analyse statique du fichier source est effectuée, THEN tous les paramètres du signal sont typés statiquement (`total: int`, `delta: int`, `source: SourceKind`) — aucun `Variant` implicite. *Mécanisme* : grep `signal credits_changed` dans le fichier `.gd` et assertion sur la présence des types — ou GdUnit4 + gdtoolkit lint.
- **AC-CRD-43 [Logic]** : GIVEN `SourceKind` est un enum déclaré dans CreditEconomy, WHEN les valeurs MVP sont inspectées, THEN l'enum contient exactement : `KILL`, `SECRET`, `SPEND_SHOP`, `BOOT_HYDRATE` — pas plus, pas moins pour le MVP. *Mécanisme* : unit test listant les valeurs de l'enum et assertant le count == 4 et les noms exacts.
- **AC-CRD-44 [Logic]** : GIVEN le fichier `credit_economy.gd` est analysé statiquement, WHEN gdtoolkit ou lint maison est exécuté, THEN aucun `Variant` implicite n'apparaît dans les signatures de méthodes publiques (`try_spend`, `get_total`, handler callbacks) — typage strict GDScript appliqué. *Mécanisme* : CI lint job sur le fichier source.
- **AC-CRD-45 [Logic]** : GIVEN CreditEconomy est un autoload, WHEN il est inspecté pour le pattern `emit_signal()` / `.emit()`, THEN tous les appels `.emit()` sur `credits_changed` se trouvent dans des fonctions appelées depuis `_physics_process` (callbacks signal `enemy_killed`, `secret_collected`) ou dans le scope direct d'un appel publié (`try_spend`, `_on_state_changed`) — aucun emit depuis `_ready`, `_process` ou callback async. *Mécanisme* : revue de code statique + grep sur fichier source, aligné avec la règle `level-signals-main-thread-only`.

### Visual / Feel (ADVISORY playtest)

- **AC-CRD-46 [Visual/Feel] ADVISORY** : GIVEN un kill grunt est enregistré, WHEN le HUD affiche le compteur de crédits, THEN le chiffre affiché dans le HUD monte visiblement dans le **même frame** que le kill — l'effet de « récompense immédiate » est perceptible sans latence d'affichage. *Mécanisme* : playtest evidence — screencap ou vidéo frame-by-frame + sign-off lead designer. Déposé dans `production/qa/evidence/`.

### Edge cases supplémentaires

- **AC-CRD-47 [Logic]** : GIVEN `total_credits` est à sa valeur maximale plausible (knob `MAX_CREDITS` non capé MVP), WHEN un nouveau gain est tenté (`enemy_killed` reçu), THEN soit le compteur est plafonné à `MAX_CREDITS` sans overflow, soit le plafond n'est pas défini MVP et le compteur dépasse sans crash (`int` GDScript 64-bit ne déborde pas). *Mécanisme* : unit test avec `total_credits` à valeur très haute — vérifier absence de crash. *Note* : la politique de plafond peut être précisée plus tard via knob `MAX_CREDITS` (Tier 2+).
- **AC-CRD-48 [Logic]** : GIVEN deux ennemis avec des `instance_id` distincts meurent dans le même tick, WHEN leurs deux `enemy_killed` arrivent dans le même `_physics_process`, THEN les deux sont comptabilisés (IDs distincts, pas de collision dans le memoization set). *Mécanisme* : unit test — deux nodes mock distincts, vérifier `total_credits += 2`.
- **AC-CRD-49 [Integration]** : GIVEN l'étage se charge pour la première fois (aucun enemy encore tué), WHEN `_on_level_loaded()` est appelé, THEN le set d'IDs vus est vide et `total_credits` est intact depuis le boot hydrate — pas de reset imprévu. *Mécanisme* : test d'intégration avec GSM mock émettant level_loaded, vérifier les deux conditions.

---

### Test Coverage Matrix

| Sous-thème | ACs | Type | Gate |
|------------|-----|------|------|
| Core invariants | AC-CRD-01..06 | Logic | BLOCKING |
| Source KILL | AC-CRD-07..11 | Logic + Integration | BLOCKING |
| Source SECRET (provisoire) | AC-CRD-12..16 | Logic | BLOCKING |
| Sink Shop (provisoire) | AC-CRD-17..21 | Logic | BLOCKING |
| Persistence | AC-CRD-22..27 | Logic + Integration | BLOCKING |
| Signal `credits_changed` | AC-CRD-28..32 | Logic | BLOCKING |
| Cross-system integration | AC-CRD-33..35 | Integration | BLOCKING |
| GSM observation | AC-CRD-36..38 | Logic + Integration | BLOCKING |
| Performance | AC-CRD-39..40 | Performance | BLOCKING |
| Lints / Static | AC-CRD-41..45 | Logic | BLOCKING |
| Visual / Feel | AC-CRD-46 | Visual/Feel | ADVISORY |
| Edge cases | AC-CRD-47..49 | Logic + Integration | BLOCKING |

**Total** : 49 ACs — 48 BLOCKING, 1 ADVISORY.

**ACs provisoires** (à raffermir post Secret/Shop/Save-Load GDDs) : AC-CRD-12..16 (Secret), AC-CRD-17..21 (Shop logic OK mais intégration AC-CRD-35 dépend de Shop stub), AC-CRD-23..25 (Save/Load).

## Open Questions

| ID | Question | Owner | Deadline / Resolution |
|----|----------|-------|----------------------|
| **OQ-CRD-1** | ✅ **RESOLVED 2026-04-27** par Secret System GDD r1 (`design/gdd/secret-system.md` R-SEC-08) confirmé par /design-review r1 (`design/gdd/reviews/credit-economy-system-review-r1-2026-04-27.md`). Secret r1 émet `secret_collected(secret_node: Node, tier: int)` SYNC à l'identique du contrat provisoire Credit r1 — aucun amendement de payload requis, `tier ∈ {1, 2, 3}` confirmé. Aucun amendement Credit r2 requis sur ce contrat — verrouillé. | game-designer + economy-designer | RESOLVED |
| **OQ-CRD-2** | ✅ **RESOLVED 2026-04-27** par Shop System GDD r1 + design-review r2 (`design/gdd/reviews/shop-system-review-r1-2026-04-27.md`). Shop confirme l'API `try_spend(amount: int) -> bool` SYNC atomique à l'identique du contrat provisoire Credit r1 (R-SHP-6 cycle d'achat étape 4). Aucun amendement Credit r2 requis sur ce contrat — verrouillé. | economy-designer + Shop System owner | RESOLVED |
| **OQ-CRD-3** | **Plafond `MAX_CREDITS`** : non capé MVP (Godot int 64-bit, débordement physiquement impossible). Faut-il introduire un cap symbolique 9 999 ou 99 999 pour contraindre l'UX HUD à 4-5 chiffres ? Décision dépend de l'analytics post-launch. | game-designer | Tier 2+ — basé sur playtest data |
| **OQ-CRD-4** | **Réservation enum `SourceKind` Tier 2+** : `BOSS_BONUS = 4`, `ROOM_CLEAR_BONUS = 5` réservés mais inactifs MVP. À confirmer la liste exhaustive (faut-il `STREAK_MULTIPLIER` ? `TIME_BONUS` ?) — potentiellement anti-Pillar 4 si non maîtrisé. | creative-director + economy-designer | Tier 2+ — sera tranché lors du Boss System ou Speedrun System design |
| **OQ-CRD-5** | **Multi-kill 3 emits séquentiels vs batch unique** : ce GDD tranche pour 3 emits séquentiels (Rule 7). Si playtest HUD révèle saturation visuelle (3 pulses en 1 frame imperceptibles), knob `BATCH_MULTI_KILL_EMIT = true` activable. À valider playtest. | game-designer + ux-designer | Sprint A playtest evidence |
| **OQ-CRD-6** | **Auto-save trigger** : MVP ne save qu'à `state_changed(MENU)`. Risque : crash mid-run perd ~30 cr. Faut-il auto-save à chaque `level_active` (Tier 2+) ? Trade-off : I/O overhead vs sécurité. | gameplay-programmer + producer | Tier 2+ — dépend telemetry crash |
| **OQ-CRD-7** | **Connexion event-driven aux ennemis** : Rule 5 propose `get_tree().get_nodes_in_group("enemies")` au `level_active`. Alternative : signal bus centralisé (autoload `EventBus`) émettrait `enemy_killed` global. Choix groupe-Godot retenu MVP par simplicité. À reconsidérer si EventBus est introduit Tier 2+. | godot-specialist + lead-programmer | Tier 2+ — décision architecture |
| **OQ-CRD-8** | **VFX gain crédit secret distinct du kill** : Player Fantasy section 4 propose un « son plus profond » au crédit secret. Implémentation : nouvelle bus Audio `SECRET_REWARD` ? Variation sur `COMBAT_KILL` ? À designer lors du HUD GDD + Audio GDD r3 si Secret System impose un son dédié. | audio-director + ux-designer | Sprint A `/design-system hud-system` |
| **OQ-CRD-9** | **Plafond `kill_credit` Tier 2+ pour boss_final** : 10 cr proposé. Si boss final dure 3-5 fenêtres d'attaque (cf. game-concept design risk), 10 cr est-il proportionné au temps investi ? Comparaison : 10 grunts kills = 10 cr en 30 sec ; boss = 10 cr en 2-3 min. Risque : boss sous-payé. | game-designer + creative-director | Full Vision — `/design-system boss-system` Tier 3 |
| **OQ-CRD-10** | **Persistence par profil de save** : MVP suppose 1 savegame par installation. Faut-il supporter plusieurs profils (slot saves) ? Multi-profil exigerait `SaveLoad.load_int(key, default, profile_id)` au lieu de `load_int(key, default)`. À designer lors du Save/Load GDD. | gameplay-programmer + Save/Load owner | Sprint A — `/design-system save-load-system` |
