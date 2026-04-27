# Shop System

> **Status**: In Design (r1 solo auto-approve)
> **Author**: Martin + main session (Opus 4.7) + subagents
> **Last Updated**: 2026-04-27
> **Implements Pillar**: 2 (LA PROGRESSION SE VOIT) primaire ; 1 (FLOW) garde-fou transition ; anti-Pillar 4 (le shop est l'unique lieu de dépense — protège la sémantique "secrets = mouvement, pas marchandage")
> **Quick reference** — Layer: `Feature/UI` · Priority: `MVP` · Key deps: `Credit Economy (Designed r1, locked try_spend), Game State Manager (APPROVED r1, request_scene_transition), Upgrade System (Not Started — provisional apply_upgrade), Save/Load System (Not Started — provisional save_string_array), Menu System (Not Started — sibling UI scene)`

## Overview

Shop System est la **scène transitoire d'achat** entre étages : un Control fullscreen `res://scenes/shop/shop.tscn` chargé par GameStateManager (`request_scene_transition` ADR-0007 D-5) au signal `etage_completed` du Level System. Le shop expose un catalogue MVP de **2 upgrades binaires permanentes** (`double_jump` à 20 cr, `dash_horizontal` à 40 cr — coûts dérivés de la courbe linéaire F-CRD-3 `cost_n = 20 + 20×n` owned par Credit Economy). Chaque achat est une transaction atomique : `CreditEconomy.try_spend(amount: int) -> bool` (R-CRD-4 locked) — si succès, l'état owned est immédiatement persisté via `SaveLoad.save_string_array("owned_upgrades", _owned_upgrades)` (provisional Save/Load) puis `UpgradeSystem.apply_upgrade(id: StringName)` (provisional Upgrade) active la capacité dans la couche gameplay. Le shop est **idempotent** (chaque upgrade = achat unique, double-click bloqué par guard `_owned_upgrades.has(id)`), **sans grinding** (pas de re-stock, pas de stack, pas de re-roll), et **sans état SHOPPING dédié dans GSM** (le shop est une scène container PLAYING-state agnostic — voir R-SHP-5). Sa surface API est minimale : un nœud-local `ShopControllerScript` dans la scène (pas d'autoload), un signal interne `_on_continue_pressed()` qui déclenche `request_scene_transition` vers MENU au MVP (Tier 2+ : `start_etage(next_etage_id)` chaîné). Le shop ferme le segment économique du core loop : sans lui, les crédits accumulés par Credit Economy n'ont pas de sortie, Pillar 2 (LA PROGRESSION SE VOIT) reste promesse. Le scope MVP couvre 2 upgrades, 1 visite par étage (1 shop pour 1 étage MVP), persistance binaire owned/not_owned via Save/Load, et zéro SFX (Audio bus shop différé Tier 2+).

---

## Player Fantasy

> **Cadrage** : système **direct-actif** — le joueur engage volontairement avec le Shop (clic, lecture, décision) à un moment précis du loop (entre étages). C'est l'unique pause respirée du jeu. Sa fantasy n'est pas spectaculaire — elle est **délibérative**.

### Le moment Shop

Tu viens de finir l'étage. La caméra est encore essoufflée, l'écran fade au noir 200 ms, puis le shop apparaît. Le 3D world a disparu. Le silence est total — pas de musique d'ambiance qui te précipite, pas de timer qui te presse. Devant toi, **deux cartes**. À droite, ton compteur de crédits — le même chiffre que tu surveilles depuis le début, mais ici il a un poids différent : il est **convertible**. La carte du haut dit `Saut Double — 20 ₵`. Tu en as 47. Tu peux. La carte du bas dit `Dash Horizontal — 40 ₵`. Tu peux aussi. Mais pas les deux. Tu vas devoir choisir.

Et c'est exactement le point : **le shop est le seul moment du jeu où tu réfléchis pour avancer**. Partout ailleurs, tu réagis à 60 fps — un laser, un mur, un grunt. Ici, tu *décides*. Cette décision est légère (deux options MVP, pas un skill tree) et lourde à la fois (chaque upgrade change physiquement ce que tu peux faire dans le prochain étage). Il n'y a pas de modal "Are you sure?", pas de fanfare, pas de cinématique. Tu cliques, le compteur tombe de 47 à 27 en 300 ms, la carte vire au cyan désaturé qui dit `POSSÉDÉ`, et le bouton `CONTINUER` est toujours là, toujours prêt. Tu reprends ton souffle, tu cliques, et la tour t'attend de nouveau.

### Le pacte avec le crédit

Pillar 2 (LA PROGRESSION SE VOIT) est tenu par un pacte simple : **le crédit que tu vois n'est pas un score, c'est un engagement signé**. Quand tu enchaînes 12 grunts pour 12 crédits, tu n'es pas en train de monter un compteur abstrait — tu es en train de constituer la mise d'un futur achat. Le shop est le moment où ce pacte se tient. Il transforme le crédit gagné dans la sueur du gameplay en capacité physique permanente, sans intermédiaire psychologique : pas de "you've earned a point, choose your reward" décoratif, pas de level-up scripted. Juste : *47 crédits → clic → -20 → tu as le double jump pour toujours*. La progression ne se promet pas, elle s'achète, et l'achat se voit dans le compteur qui descend.

### Le pacte avec Pillar 4 (SECRETS = MOUVEMENT)

Le shop est aussi le seul endroit où l'asymétrie 5:1 entre crédit-secret et crédit-kill (F-CRD-2 vs F-CRD-1) prend son vrai sens. Quand tu vois la carte `Dash Horizontal — 40 ₵` et que tu te dis "je l'aurai au prochain étage si je trouve le secret tier 2 que j'ai vu briller derrière le wall-run impossible" — c'est **là** que Pillar 4 se matérialise. Le shop est l'écran où le secret devient une *promesse cible* : "atteins ce crédit-secret et la prochaine carte est à toi". Le dash horizontal ne s'achète pas avec 40 kills (40 secondes de combat banal) — il s'achète avec **2 secrets de mouvement** (deux moments de prise de risque verticale). Le shop ne dit pas ça en mots. Il le dit dans l'arithmétique du compteur.

### Anti-fantasy (ce que le shop n'est pas)

Le shop n'est **pas** :

- **Un moment d'optimisation** : pas de skill tree à comparer, pas de build à planifier, pas de tier-list à mémoriser. Deux cartes MVP. Tu prends ce que tu peux, tu continues. Pillar 1 anti-friction.
- **Un moment marchand** : pas de PNJ qui parle, pas de dialog tree, pas de bourse qui fluctue. Le shop est une *interface* (au sens électrique), pas un *personnage*. Anti-pillar narration interruptive.
- **Un moment de récompense** : pas de fanfare, pas de confetti, pas de "Congratulations!". L'achat est silencieux car le crédit a déjà été gagné dans la course — le shop ne célèbre pas, il **livre**. Cohérent avec l'aesthetic Chrome Zen "le vide rend la lame visible".
- **Un moment de grinding** : pas de re-stock, pas de re-roll de boutique, pas d'upgrade consommable à racheter. Une upgrade = un achat unique = une capacité permanente. Le shop ferme la porte au comportement d'accumulation stratégique.

### Référence sentimentale

Inspirations directes : *Hollow Knight* shop Iselda/Sly (sobre, fonctionnel, la décision est dans le choix de l'item, pas dans la mise en scène) ; *Ghostrunner* upgrade screen (minimaliste, monospace, zéro friction). Anti-référence : tous les shops F2P (loot box reveal, particules, son de jackpot) — le shop de Chrome://Ascent est leur opposé exact.

## Detailed Rules

### Core Rules (R-SHP-1 … R-SHP-16)

**R-SHP-1 — Architecture : scène transitoire, pas d'autoload**

Le Shop System n'est **pas** un autoload. Il vit entièrement dans `res://scenes/shop/shop.tscn` — une scène Control fullscreen instanciée et détruite à chaque visite de shop. La logique de shop est portée par un nœud script `ShopController` (class_name `ShopControllerScript`) attaché à la racine de la scène. Justification : le Shop n'a pas d'état inter-session à maintenir (les upgrades owned sont dans Save/Load, le solde dans Credit Economy) ; en faire un autoload créerait un singleton qui tourne pendant tout le jeu pour une surface d'un seul écran de transition. Le pattern correct pour ce type de scène-modale courte est un nœud local coordonné par GSM. `ShopControllerScript` expose une API publique minimale destinée à GSM et au bouton "Continuer" : `func _on_continue_pressed() -> void`. Le reste est événementiel interne.

**R-SHP-2 — Hiérarchie de nœuds de `shop.tscn`**

```
shop.tscn
└── ShopRoot : Control (CanvasLayer.layer = 60, fullscreen, ProcessMode = ALWAYS)
    ├── Background : ColorRect (fullscreen #0A0A14 — Chrome Zen fond nuit)
    ├── CreditDisplay : HBoxContainer
    │   ├── CreditLabel : Label ("CRÉDITS : ")
    │   └── CreditValueLabel : Label (valeur live du solde)
    ├── UpgradeList : VBoxContainer
    │   ├── UpgradeCard_0 : Panel (double_jump)
    │   │   ├── NameLabel : Label
    │   │   ├── CostLabel : Label
    │   │   └── BuyButton : Button
    │   └── UpgradeCard_1 : Panel (dash_horizontal)
    │       ├── NameLabel : Label
    │       ├── CostLabel : Label
    │       └── BuyButton : Button
    └── ContinueButton : Button ("Continuer →")
```

`ProcessMode = ALWAYS` sur `ShopRoot` : la scène shop peut tourner même si le GSM est en état PLAYING avec l'arbre pausé. En pratique, la scène shop est instanciée via `request_scene_transition` (pas d'arbre pausé hérité), mais la règle `ALWAYS` protège contre tout résiduel et reste cohérente avec le pattern projet (Audio, GSM, Save/Load tous PROCESS_MODE_ALWAYS). `CanvasLayer.layer = 60` : au-dessus du HUD (layer 50), en-dessous d'une hypothétique overlay GSM (layer 100).

**R-SHP-3 — Catalogue d'upgrades : hardcodé avec constantes externes, pas de Resource fichier**

Le catalogue MVP est une `Array[Dictionary]` statique déclarée dans `ShopControllerScript._CATALOG` :

```gdscript
const _CATALOG: Array[Dictionary] = [
    { "id": &"double_jump",      "display_name": "Saut Double",       "n_index": 0 },
    { "id": &"dash_horizontal",  "display_name": "Dash Horizontal",   "n_index": 1 },
]
```

Le coût de chaque upgrade est **calculé dynamiquement** via la courbe F-CRD-3 du Credit Economy GDD : `cost_n = BASE_UPGRADE_COST(20) + n_index × TIER_COST_STEP(20)` → 20 cr (n=0), 40 cr (n=1).

Les valeurs `BASE_UPGRADE_COST` et `TIER_COST_STEP` ne sont pas hardcodées dans le script Shop : elles sont lues depuis `assets/data/shop_config.tres` (tuning knob G-1) ou exposées comme constantes Credit Economy si l'API y prévoit un getter. **Justification du choix hardcodé Array vs Resource externe** : avec 2 upgrades MVP, un fichier `.tres` séparé ajoute de la friction de tooling pour zéro gain de flexibilité. Tier 2+ (4+ upgrades) : migration vers `shop_catalog.tres` (Resource custom `ShopCatalogResource`) pour permettre l'édition en inspector Godot sans toucher le code.

**R-SHP-4 — État interne des upgrades : `_owned_upgrades: Array[StringName]`**

À l'initialisation (`_ready()`), `ShopControllerScript` charge l'état owned depuis Save/Load :

```gdscript
_owned_upgrades = SaveLoad.load_string_array("owned_upgrades", [])
```

Cette array contient les `id: StringName` de chaque upgrade achetée (ex. `[&"double_jump"]`). Elle est l'unique source de vérité locale pour le rendu des boutons. Elle est écrite dans Save/Load après chaque achat réussi (R-SHP-8), pas en batch à la fermeture du shop — écriture immédiate post-apply pour résistance aux crash.

**R-SHP-5 — État GSM pendant le shop : PLAYING + scène shop active (pas d'état SHOPPING)**

⚠️ **Décision tranchée — pas de nouvel état dans GSM enum.** Le Shop n'a pas de gameplay 3D — `Engine.time_scale` n'a pas d'effet, pas de physique active. Introduire `SHOPPING` dans l'enum `State` (ADR-0007 D-2 — immutable, requiert amendement ADR) pour une scène sans gameplay 3D serait une violation du principe de minimisation de surface API (ADR-0007 D-10). Le flow MVP est : GSM appelle `request_scene_transition("res://scenes/shop/shop.tscn")` → `get_tree().change_scene_to_file()` — l'état GSM reste PLAYING mais le gameplay 3D est absent (aucun Level actif, Player non instancié dans shop.tscn). Le shop étant une scène "container" au sens ADR-0007 D-5 two-path §6(a), la transition existante couvre ce cas sans nouvel état.

**Flag amendement** : si Tier 2+ apporte un shop sur-écran (HUD overlay pendant le gameplay 3D, sans changer de scène), alors un état SHOPPING deviendrait justifié — voir OQ-SHP-1.

**R-SHP-6 — Cycle d'achat complet (6 étapes déterministes)**

Pour une upgrade `id` de coût `cost`, le cycle suit cette séquence stricte dans le même frame :

1. **Render initial** — Au `_ready()`, chaque `BuyButton` est rendu selon `_owned_upgrades.has(id)` et `CreditEconomy.get_total() >= cost`.
2. **Hover** — Sur `mouse_entered` du `BuyButton`, le `CostLabel` passe en couleur accentuée (cyan `#3EE4FF` si affordable, rouge `#FF4455` si insuffisant). Pas de tooltip MVP (sauf cas DISABLED/OWNED — voir J.5).
3. **Click** — Le joueur clique `BuyButton`. Le handler vérifie immédiatement le guard d'idempotence : `if _owned_upgrades.has(id): return` (double-click = no-op silencieux). Si not owned, continue vers étape 4.
4. **`try_spend(cost)`** — Appel atomique `CreditEconomy.try_spend(cost) -> bool`.
   - Si `false` (solde insuffisant) : feedback rejet visuel (BuyButton shake tween 4 px horizontal sur 200 ms TRANS_SINE — voir J.5). Aucun feedback audio MVP. Fin du cycle.
   - Si `true` : continue vers étape 5.
5. **Mark + Persist + Apply** — En séquence stricte dans le même frame, ordre impératif :
   - `_owned_upgrades.append(id)` — mise à jour état local.
   - `SaveLoad.save_string_array("owned_upgrades", _owned_upgrades)` — persistance immédiate.
   - `UpgradeSystem.apply_upgrade(id)` — activation de la capacité (appel SYNC idempotent).
   - Désactivation du `BuyButton` (`disabled = true`, label change en `"POSSÉDÉ"`).
   - Mise à jour de `CreditValueLabel` (déjà géré côté shop via signal `credits_changed` connecté en R-SHP-9 — pas besoin de pull explicite).
6. **Feedback succès** — Tween pulse sur `UpgradeCard` (scale 1.0 → 1.03 → 1.0, 150 ms wall-clock, TRANS_SINE) + counter tween 300 ms (J.3) déclenché côté `credits_changed` handler. Aucun son MVP.

**Ordre 5a → 5b → 5c impératif** : la persistance précède `apply_upgrade` afin que, même si `apply_upgrade` lance une exception non fatale, l'état owned soit enregistré (évite la double-facturation au rechargement). Si `save_string_array` échoue, `push_error` est émis mais le cycle continue (apply se fait quand même — le crédit est déjà débité, le moins pire est d'activer l'upgrade).

**R-SHP-7 — Idempotence : double-click et re-entry**

L'idempotence est garantie à trois niveaux :

- **Niveau UI (guard local)** : avant tout appel `try_spend`, le handler vérifie `_owned_upgrades.has(id)`. Si `true`, retour immédiat sans appel, sans son, sans animation. BuyButton est `disabled = true` dès l'achat — le click physique est bloqué à la source par Godot (event consommé avant handler).
- **Niveau Save/Load (re-entry)** : si le joueur quitte le shop, revient (Tier 2+ multi-étages), et `_ready()` re-charge `_owned_upgrades`, les upgrades déjà owned sont marquées OWNED dès le rendu initial. Aucun crédit ne peut être re-débité.
- **Niveau UpgradeSystem (contrat provisional)** : `UpgradeSystem.apply_upgrade(id)` est contractuellement idempotent (re-apply même id = no-op). Si Shop appelle deux fois par bug, aucun effet cumulatif.

**R-SHP-8 — Persistance : écriture immédiate, pas de batch**

Chaque achat réussi déclenche une écriture immédiate `SaveLoad.save_string_array("owned_upgrades", _owned_upgrades)` dans le frame de l'achat, avant tout autre effet. Le shop ne reporte jamais la persistance à la fermeture (`ContinueButton` press ou unload de scène). Justification : si l'application crash entre l'achat et la fermeture du shop, le joueur retrouve son upgrade au redémarrage. La perte de crédit (`try_spend` débite avant la persistance de `_owned_upgrades`) sans persistence de l'owned state serait le pire scénario — ce pattern l'élimine.

Clé Save/Load : `"owned_upgrades"` (cohérent typage avec Credit Economy `"total_credits"`). Type : `Array[StringName]`. Default si absent : `[]` (première session).

**R-SHP-9 — Affordability display : rendu temps-réel via signal**

Le shop se connecte au signal `CreditEconomy.credits_changed(total, delta, source)` dans `_ready()` avec `CONNECT_DEFERRED`. À chaque emit :

- `CreditValueLabel` est mis à jour avec le nouveau `total` (animation tween 300 ms côté shop, voir J.3 — distinct du hard-set silencieux du HUD r1 R-6).
- Pour chaque upgrade non-owned dans `_CATALOG` : si `total >= cost` → BuyButton enabled + label couleur affordable ; sinon → BuyButton disabled + label couleur insufficient.

Cas initial (entre `_ready()` et premier emit) : le rendu initial appelle `CreditEconomy.get_total()` directement (pattern pull, cohérent ADR-0007 D-9 + Credit r1 R-CRD-7 boot hydration). Le signal met ensuite à jour en live à chaque event.

**Note sur CONNECT_DEFERRED** : `credits_changed` peut être émis depuis `_physics_process` du Credit Economy (SYNC dans le call stack `try_spend`). Le shop étant une scène Control (pas de gameplay 3D), `CONNECT_DEFERRED` laisse le signal arriver à l'idle frame suivante — acceptable pour l'UI (pas de contrainte frame-precise ici, contrairement au gameplay 3D qui exige SYNC).

**R-SHP-10 — Bouton "Continuer" : transition GSM**

Le bouton "Continuer" est l'unique mécanisme de sortie du shop au MVP.

```gdscript
func _on_continue_pressed() -> void:
    GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")
```

Au MVP (1 seul étage) : transition vers `main_menu.tscn`. Tier 2+ (multi-étages) : `request_scene_transition` est remplacé par `start_etage(next_etage_id)` où `next_etage_id` est passé par le Level System au moment de l'ouverture du shop (payload de `etage_completed`).

Le bouton "Continuer" est **toujours actif**, même si aucun achat n'a été fait. Il n'est jamais désactivé par état d'upgrade. Le joueur peut entrer dans le shop, ne rien acheter, et continuer sans friction. Conformément à Pillar 1 FLOW anti-clic obligatoire.

**R-SHP-11 — ESC : déclenche "Continuer" (pas de fermeture silencieuse)**

⚠️ **Décision tranchée** : ESC = comportement identique au clic "Continuer".

Justification Pillar 1 FLOW : forcer le joueur à trouver et cliquer "Continuer" alors qu'il vient de finir l'étage et veut avancer crée une friction inutile. ESC est la touche d'avancement naturelle pour un joueur en état de flow post-étage. Un ESC silencieux (fermeture sans transition) créerait un état UI ambigu (shop fermé sans progression).

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"ui_cancel"):
        _on_continue_pressed()
```

`ui_cancel` est l'action Godot par défaut pour ESC et le bouton B/Circle de gamepad.

**R-SHP-12 — État OWNED : rendu visuel différencié**

Un upgrade owned est rendu avec :
- `BuyButton.disabled = true`
- `BuyButton.text = "POSSÉDÉ"` (pas "Acheter")
- `CostLabel` text remplacé par `"—"` ou vidé
- `UpgradeCard.modulate.a = 0.6` (grayed-out — upgrade consommée, pas supprimée)

L'upgrade owned reste visible dans la liste — le joueur voit ce qu'il a acquis. Cela sert Pillar 2 (LA PROGRESSION SE VOIT) : la carte grayed-out dit "tu as déjà ça", renforçant la lecture de la progression accumulée.

**R-SHP-13 — No grinding : absence de re-stock et d'achat multiple**

Chaque upgrade ne peut être achetée qu'une seule fois (`_owned_upgrades.has(id)` guard permanent). Le shop ne propose pas de quantités, pas de stack, pas d'upgrades consommables, pas de re-roll de catalogue. Conformément à l'anti-pillar "NOT un jeu d'inventaire". Si tous les upgrades MVP sont achetés (2/2), toutes les cartes sont grayées — le shop affiche uniquement le bouton "Continuer". Aucun message "shop vide" n'est nécessaire : l'état visuel est auto-explicatif.

**R-SHP-14 — N_UPGRADES_MVP : constante Shop-interne**

`N_UPGRADES_MVP = 2` est une constante Shop-interne définie dans `ShopControllerScript` (pas dans Credit Economy, pas dans le registry global — sa portée est uniquement le Shop). Elle est utilisée pour valider que `_CATALOG.size() == N_UPGRADES_MVP` en `_ready()` (`assert` debug). Si un développeur ajoute une upgrade au catalogue sans mettre à jour `N_UPGRADES_MVP`, l'assert crache immédiatement en debug.

**R-SHP-15 — Déclenchement du shop : signal `etage_completed`**

Le shop s'ouvre sur réception d'un signal `etage_completed` émis par Level System (Level GDD §Dependencies). Au MVP, ce signal est consommé par GSM qui appelle `request_scene_transition("res://scenes/shop/shop.tscn")`. Shop n'écoute pas directement `etage_completed` — il est instancié par GSM, et son `_ready()` constitue son point d'entrée. Shop est agnostique à l'étage d'où il vient (au MVP). Tier 2+ : le payload de `etage_completed` (etage_id) sera passé via mécanisme à définir (param de scène, autoload state-bag, etc.) pour que le shop puisse calculer `next_etage_id` lors du clic "Continuer".

**R-SHP-16 — ProcessMode et tween pause-mode**

`ShopRoot.process_mode = PROCESS_MODE_ALWAYS`. Cohérent avec le pattern projet (Audio, GSM, Save/Load tous ALWAYS). Les tweens d'UI utilisent `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` pour ignorer `Engine.time_scale` (animations en wall-clock, pas en game time). En pratique, le shop est invoqué avec `Engine.time_scale = 1.0` (sortie de slow-mo gérée par Combat à la fin de l'étage), mais la règle reste défensive.

---

### States and Transitions

| État | Description | Condition d'entrée | Condition de sortie | Trigger |
|------|-------------|-------------------|---------------------|---------|
| **INACTIVE** | Shop non instancié. `ShopControllerScript` n'existe pas en mémoire. | État initial (avant toute visite de shop) | GSM appelle `request_scene_transition("res://scenes/shop/shop.tscn")` | Signal `etage_completed` reçu par GSM |
| **LOADING** | `get_tree().change_scene_to_file()` en cours. Aucun nœud Shop actif encore. | GSM a émis `request_scene_transition` | Godot a instancié shop.tscn et `_ready()` de ShopControllerScript s'exécute | Completion du `change_scene_to_file()` par le moteur |
| **ACTIVE** | Shop pleinement opérationnel. `_ready()` terminé. Catalogue rendu. Signaux Credit connectés. Boutons en état correct (affordable/owned/disabled). Joueur peut acheter ou cliquer "Continuer". | `_ready()` du ShopControllerScript s'est exécuté sans erreur, SaveLoad hydration réussie | Joueur clique "Continuer" (ou ESC) → `_on_continue_pressed()` | Action joueur |
| **PURCHASE_PENDING** | Sub-état transitoire de ACTIVE. Le joueur vient de cliquer BuyButton. `try_spend` est en cours d'évaluation (appel SYNC — dure < 1 tick). | Joueur clique un BuyButton non-owned et affordable | `try_spend` retourne `bool` (succès ou échec) — sortie vers ACTIVE dans le même frame | Retour de `CreditEconomy.try_spend(cost)` |
| **CLOSING** | `_on_continue_pressed()` appelé. `request_scene_transition` transmis à GSM. Aucune interaction joueur possible. | `_on_continue_pressed()` ou ESC déclenché en état ACTIVE | Godot décharge shop.tscn et charge la scène cible (menu ou next étage) | GSM reçoit `request_scene_transition` |
| **UNLOADED** | Shop.tscn déchargé par Godot. `ShopControllerScript` libéré. Tous les signaux connectés sont déconnectés (Godot cleanup). `_owned_upgrades` persisté en Save/Load (déjà fait à chaque achat R-SHP-8). | `change_scene_to_file()` complete — nouvelle scène active | État final pour cette visite. Prochain shop = retour à INACTIVE | Fin du `change_scene_to_file()` |

---

### Interactions with Other Systems

| Système | Direction | Mécanisme | Données échangées | Owner du contrat | Status |
|---------|-----------|-----------|-------------------|-----------------|--------|
| **Credit Economy** | In + Out | Signal `credits_changed(total, delta, source)` reçu via `connect(CONNECT_DEFERRED)` dans `_ready()`. Appel SYNC `CreditEconomy.try_spend(amount) -> bool` pour chaque achat. Pull `CreditEconomy.get_total()` pour rendu initial. | Solde courant `int`, delta `int`, source `SourceKind`. Réponse booléenne atomique. | Credit Economy GDD r1 (R-CRD-4, R-CRD-8) | LOCKED (Credit r1) |
| **Game State Manager** | Out | `GameStateManager.request_scene_transition(scene_path: String)` appelé par ContinueButton ou ESC. L'un des 5 verbes publics figés ADR-0007 D-10. | `scene_path` String : `main_menu.tscn` MVP, `start_etage(next_id)` en Tier 2+. | GSM GDD APPROVED r1 (Rule 3, ADR-0007 D-10) | LOCKED (GSM r1) |
| **Game State Manager** | In (indirect) | Shop est instancié par GSM via `change_scene_to_file()` — pas de signal direct. Déclenchement par `etage_completed → GSM → request_scene_transition`. Shop n'écoute jamais `state_changed`. | Aucune donnée directe. Déclenchement implicite par instanciation de scène. | GSM GDD r1 (Rule 6, ADR-0007 D-5 two-path §a) | LOCKED (GSM r1) |
| **HUD System** | Peer (architecture) | HUD vit dans la scène 3D Level. Quand shop.tscn devient la scène active, HUD est déchargé avec le Level. Aucun couplage direct Shop ↔ HUD. Le compteur du shop est **distinct** du compteur HUD (même contrat Credit, deux Labels indépendants — voir HUD r1 R-6 hard-set vs Shop J.3 tween 300 ms). | Aucune donnée directe. Coordination implicite par architecture scène. | HUD GDD Designed r1 (Rule visibility) | LOCKED par architecture |
| **Upgrade System** | Out | `UpgradeSystem.apply_upgrade(id: StringName) -> void` SYNC idempotent après `try_spend` réussi. Shop ne connaît pas l'implémentation — il délègue entièrement. | `id: StringName` (ex. `&"double_jump"`). | Shop GDD r1 (ce document) — contrat à confirmer Upgrade GDD #13 | PROVISOIRE (OQ-SHP-2) |
| **Save/Load System** | In + Out | `SaveLoad.load_string_array("owned_upgrades", [])` dans `_ready()`. `SaveLoad.save_string_array("owned_upgrades", _owned_upgrades)` après chaque achat (immédiat, pas batch). | Clé `"owned_upgrades"`, valeur `Array[StringName]`. | Shop GDD r1 (ce document) — contrat à confirmer Save/Load GDD #3 | PROVISOIRE (OQ-SHP-3) |
| **Menu System** | Sibling | Menu System et Shop System sont des scènes séparées dans la même couche container GSM. Aucun appel direct Menu ↔ Shop. Séquence orchestrée par GSM. | Aucune donnée directe. | GSM GDD r1 — coordination implicite | LOCKED par architecture |
| **Audio System** | Peer (consumer Tier 2+) | Audio est autoload `PROCESS_MODE_ALWAYS`. Au MVP : **aucun SFX Shop défini** — pas de bus dédié dans Audio r2.1. Tier 2+ : amendement Audio r2.2 ajoutera un bus `SHOP_UI` ou réutilisera `UI` existant. | SFX id (StringName) Tier 2+. | Audio GDD APPROVED r2.1 — pas de contrat shop MVP | PROVISOIRE Tier 2+ (OQ-SHP-4) |
| **Input System** | Peer (events UI) | Shop reçoit input via `_unhandled_input` Godot standard (Control nodes consomment leurs events en priorité via `gui_input`). Action `ui_cancel` (ESC / B gamepad) interceptée. Shop ne consulte JAMAIS `Input.*` direct (cohérence Input GDD Core Rule 1). | `InputEvent` standard. Action `ui_cancel` via InputMap. | Input GDD r4 (Core Rule 1) | LOCKED par règle projet |
| **Level System** | Peer (déclencheur indirect) | Level émet `etage_completed(etage_id, boss_defeated: bool)` consommé par GSM (cf. Level GDD §Dependencies). Shop n'écoute pas directement. Tier 2+ : Shop pourra recevoir `next_etage_id` via mécanisme à définir. | Aucune donnée directe MVP. | Level GDD APPROVED r3 — émetteur, pas consommateur direct | LOCKED par GSM relay |

## Formulas

> **Scope** : les formules Shop sont des **consommateurs** de Credit Economy (F-CRD-3, F-CRD-4). Le Shop System ne redéfinit aucune constante appartenant à Credit — il délègue par lookup et expose uniquement les décisions de présentation et de validation qui lui sont propres.

---

**F-SHP-1 — Cost Lookup (délégation à F-CRD-3)**

Le Shop ne calcule pas le coût d'une upgrade — il délègue à la courbe linéaire définie par F-CRD-3 dans Credit Economy. Aucune constante `BASE_UPGRADE_COST` ni `TIER_COST_STEP` n'est redéfinie ici.

```
cost_at_index(n) := F-CRD-3 = BASE_UPGRADE_COST + TIER_COST_STEP × n
                            = 20 + 20 × n
```

**Variables :**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `n` | n | `int` | `[0, MAX_UPGRADE_INDEX]` | Index zero-based de l'upgrade dans la liste triée par prix croissant. `n = 0` est l'upgrade la moins chère. |
| `BASE_UPGRADE_COST` | B | `int` | 20 (fixé Credit GDD) | Coût de l'upgrade à n=0. **Non redéfini ici — lire Credit F-CRD-3.** |
| `TIER_COST_STEP` | S | `int` | 20 (fixé Credit GDD) | Incrément linéaire par rang. **Non redéfini ici — lire Credit F-CRD-3.** |
| `MAX_UPGRADE_INDEX` | M | `int` | 1 (MVP) ; 7 (Full Vision 8 upgrades) | Index maximum légal. Toute valeur `n > M` doit déclencher une erreur. |
| `cost_at_index(n)` | c | `int` | `[20, 40]` MVP ; `[20, 160]` Full Vision | Coût en crédits retourné pour l'index n. |

**Output Range :** `[20, 40]` sous jeu normal MVP ; courbe non-bornée supérieurement en théorie mais plafonnée par `MAX_UPGRADE_INDEX`.

**Table MVP :**

| n | Upgrade | `cost_at_index(n)` |
|---|---------|-------------------|
| 0 | `double_jump` | 20 cr |
| 1 | `dash_horizontal` | 40 cr |

**Exemple worked :** Shop affiche le coût de `dash_horizontal` → `cost_at_index(1) = 20 + 20 × 1 = 40`. Passe le résultat à F-SHP-2 et à l'UI.

**Edge cases :**

- `n < 0` → `push_warning("ShopSystem: cost_at_index appelé avec n négatif (" + str(n) + ")")` ; retourne `0` ; précondition explicite : Shop n'appelle jamais `try_spend` si `n < 0`.
- `n > MAX_UPGRADE_INDEX` → `push_error` ; retourne `0` ; achat annulé. Bug de configuration.
- Upgrade déjà owned → filtré en amont par `_owned_upgrades.has(id)` (R-SHP-7) ; F-SHP-1 ne connaît pas l'état owned.

---

**F-SHP-2 — Affordability Check (rendu UI temps-réel)**

Vérification passive de la capacité d'achat pour l'upgrade d'index n. **Non-mutante** : ne touche ni `total_credits`, ni l'état du Shop. Appelée à chaque rendu pour décider du highlight visuel des boutons. **Ne jamais utiliser `try_spend` à des fins de vérification** — `try_spend` est atomique et **modifie** `total_credits` si la condition est vraie.

```
affordable_n = CreditEconomy.get_total() >= cost_at_index(n)
```

**Variables :**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `CreditEconomy.get_total()` | T | `int` | `[0, +∞)` | Lecture passive du solde. Non-mutant. |
| `cost_at_index(n)` | c | `int` | `[20, 40]` MVP | Coût de l'upgrade n via F-SHP-1. |
| `affordable_n` | a | `bool` | `{false, true}` | `true` si le joueur peut acheter sans déficit. |

**Output Range :** `{false, true}` déterministe pour un solde donné.

**Exemples worked :**

| `T = get_total()` | `c = cost_at_index(n)` | `affordable_n` | État UI |
|-------------------|----------------------|----------------|---------|
| 15 cr | 20 cr (n=0) | `false` | Bouton DISABLED, cost rouge |
| 20 cr | 20 cr (n=0) | `true` | Bouton NORMAL, glow cyan affordable |
| 50 cr | 40 cr (n=1) | `true` | Bouton NORMAL |
| 35 cr | 40 cr (n=1) | `false` | Bouton DISABLED |
| 60 cr | 40 cr (n=1) | `true` | Bouton NORMAL, surplus 20 cr visible |

**Edge cases :**

- `T == c` (solde exactement égal au coût) → `true`. Condition `>=`, jamais `>` — solde exact permet l'achat, laissant 0 cr résiduel. Cas économique valide et intentionnel.
- `T == 0` → `affordable_n` toujours `false` pour tout `c >= 20` MVP.
- `n` invalide → `cost_at_index(n)` retourne `0` après warning, `T >= 0` toujours `true` → résultat incorrect. Shop doit valider `n` avant d'appeler F-SHP-2 (précondition partagée avec F-SHP-1).

---

**F-SHP-3 — Total Spend Budget Validation (Pillar 2 sanity check)**

Validation économique statique (design-time + test-time, non runtime). Vérifie que la somme des coûts de toutes les upgrades MVP est atteignable sans grind. Garantit Pillar 2 : un joueur qui joue bien doit pouvoir acheter toutes les upgrades MVP.

```
total_cost_MVP = Σ cost_at_index(n)  pour n ∈ [0, N_UPGRADES_MVP - 1]
              = cost_at_index(0) + cost_at_index(1)
              = 20 + 40
              = 60 cr

session_yield_max_MVP = 85 cr   (F-CRD-4 — run complète 2 étages, tous secrets trouvés)

margin = session_yield_max_MVP - total_cost_MVP
       = 85 - 60
       = 25 cr
```

**Variables :**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `N_UPGRADES_MVP` | N | `int` | 2 | Nombre d'upgrades MVP. Figé game-concept ligne 271. |
| `total_cost_MVP` | C | `int` | 60 | Somme des coûts. Dérivé F-SHP-1 × N. |
| `session_yield_max_MVP` | Y | `int` | 85 | Rendement maximal session 2 étages (F-CRD-4). Source de vérité Credit GDD. |
| `margin` | m | `int` | 25 | Crédits résiduels après achat de toutes upgrades MVP en scénario optimal. |

**Output Range :** `margin >= 0` est la condition de validité économique. `margin < 0` → violation Pillar 2 + anti-pillar grinding.

**Interprétation de la marge 25 cr** :

1. **Confort de jeu** : un joueur qui rate quelques secrets (rendement < 85 cr) peut quand même financer les 2 upgrades s'il atteint ≈ 60 cr — la marge absorbe l'imperfection sans forcer le grind.
2. **Anticipation Tier 2+** : les crédits résiduels s'accumulent sur le compteur permanent. Quand l'upgrade n=2 (Tier 2+ `wall_run_long` à 60 cr) sera disponible, le joueur sera déjà partiellement financé — la progression se voit avant même que l'upgrade n'existe.
3. **Non-trivialité** : 25 cr ne suffisent pas pour une 3e upgrade fictive (n=2 = 60 cr > 25 cr) — pas de "tout acheter sans effort" même en session parfaite. Tension économique réelle préservée.

**Invariant de santé économique** : à chaque extension Tier 2+ qui ajoute une upgrade, vérifier que `session_yield_max(nouveau_tier) - total_cost(nouveau_N) >= 0`. Si négatif, retuner `BASE_UPGRADE_COST`/`TIER_COST_STEP` (Credit) ou augmenter rendement (nouveaux ennemis, secrets).

**Sanity checks de non-boucle économique :**

- Pas de gain → dépense → regain : `try_spend` est sink pur, sources non régénérables, étage déjà complété ne peut pas être regrindé (anti-pillar).
- Pas d'inflation : courbe F-CRD-3 linéaire, croissance bornée à 20 cr par rang, pas de "wall final" exponentiel.

---

**F-SHP-4 — Upgrade Ordering Rationale (DESIGN GUIDELINE — non-runtime)**

Règle de tri des upgrades dans la liste Shop, appliquée au design (authoring-time) et figée dans `shop_config.tres`. Guide de décision, pas formule calculée en jeu.

```
ordre_upgrade = f(prix_croissant, impact_gameplay_croissant, pillar_2_visibilité)
```

**Règles d'ordering par priorité décroissante :**

1. **Prix croissant** — La moins chère en premier. Introduction à l'économie : le joueur comprend le modèle coût/bénéfice dès sa première interaction. Casser ce tri = friction cognitive.
2. **Impact gameplay croissant** — À prix égaux ou pour départager des prix proches, l'upgrade au changement le plus visible passe en premier. Pillar 2 : "la progression se voit" impose que l'achat le plus accessible produise le changement le plus perceptible.
3. **Visibilité Pillar 2** — En cas d'égalité, prioriser l'upgrade qui change le plus rapidement le comportement observable.

**Application MVP :**

| n | Upgrade | Prix | Impact perceptuel immédiat | Tactique étendue | Position |
|---|---------|------|---------------------------|------------------|----------|
| 0 | `double_jump` | 20 cr | Très élevé — franchit gaps impossibles, visible au premier saut post-achat | Moyen — ouvre verticalité | **Premier** |
| 1 | `dash_horizontal` | 40 cr | Élevé — accélère traversée, impact moins immédiat sans level design dédié | Élevé — couvre distances latérales, esquive lasers | **Second** |

**Justification double_jump en n=0** : le double_jump à 20 cr est délibérément le moins cher car il est la première preuve que "acheter change ce qu'on peut faire". Le moment où le joueur prend un élan, saute, et franchit un bord raté 5 fois avant l'achat est la démonstration de Pillar 2 la plus directe possible. Récompense immédiate, sans équipement supplémentaire, sans tutoriel. Le dash_horizontal (40 cr) demande compréhension du level design pour révéler son potentiel — correctement placé en second, une fois le modèle économique compris.

**Roadmap Tier 2+ (indicative — non figée) :**

| n | Upgrade (non finale) | Coût indicatif | Impact |
|---|---------------------|----------------|--------|
| 2 | `wall_run_long` | 60 cr | Extension durée wall-run — traversées de façades longues |
| 3 | `aerial_slow_mo` | 80 cr | Slow-mo en l'air — lecture tactique mid-air |
| 4–7 | TBD Tier 2+ | 100–160 cr | À définir VS/Alpha selon playtest |

---

**F-SHP-5 — Bulk Discount / Loyalty Multiplier**

> **DEFERRED — Tier 3 design space. Aucune formule MVP.**

Slot réservé pour documenter un éventuel système de remise groupée (multi-buy), de fidélité (bonus après N achats), ou de prix dégressifs par profil. Ces mécaniques sont **explicitement incompatibles** avec le MVP :

1. **Anti-pillar grinding** : tout mécanisme d'optimisation d'achat (ex. acheter 3 upgrades d'un coup moins cher) crée une incitation à accumuler avant d'acheter — exactement le comportement de grind à éviter.
2. **Simplicité cognitive Pillar 1** : le Shop MVP est un écran d'une dizaine de secondes entre deux étages. Un mécanisme de remise complexifie la lecture et rompt le FLOW.

Si Tier 3 introduit une progression méta (runs multiples, profil persistant étendu), un mécanisme de loyauté pourrait être envisagé — mais devra d'abord passer par un amendement de l'anti-pillar grinding pour justifier qu'il ne crée pas d'accumulation. Il n'est pas exclu que cette case reste vide définitivement.

## Edge Cases

**EC-SHP-1 — try_spend false entre hover et clic** : SI `CreditEconomy.total_credits` chute entre l'instant où la carte upgrade s'affiche AFFORDABLE (rendu UI précédent) et le clic confirmé ALORS `try_spend(cost)` retourne `false`, le Shop affiche l'animation DISABLED shake (J.5), ne déduit rien, ne marque pas l'upgrade OWNED, et l'UI recalcule l'affordability de toutes les cartes immédiatement. Le bouton Continue reste actif sans interruption. Cas structurellement improbable au MVP (un seul sink = `try_spend` via Shop), mais la garde est obligatoire : `try_spend` est l'unique source de vérité, l'UI est un miroir en retard d'au moins 1 frame.

**EC-SHP-2 — try_spend(0) accidentel** : SI le Shop construit un `cost == 0` (bug de catalogue ou index invalide) ALORS Credit Economy retourne `true` sans émettre `credits_changed` (Credit Rule 4). Le Shop ne doit jamais interpréter ce `true` comme un achat valide : un guard `assert(cost > 0)` sur R-SHP-6 étape 4 bloque cette branche avant l'appel. Si le guard passe en prod, l'upgrade serait marquée OWNED sans débit. Garde coût-positif côté Shop, pas côté Credit.

**EC-SHP-3 — try_spend(total_credits exact)** : SI `total_credits == cost` au moment du clic ALORS `try_spend(cost)` retourne `true`, `total_credits` passe à 0. Dans le même frame, signal `credits_changed(0, -cost, SPEND_SHOP)` émis SYNC. Toutes les cartes restantes recalculent leur affordability dans le handler et passent DISABLED immédiatement. Aucune fenêtre où une autre carte serait encore cliquable. Bouton Continue reste actif.

**EC-SHP-4 — BOOT_HYDRATE signal reçu pendant LOADING** : SI Credit émet `credits_changed(total, 0, BOOT_HYDRATE)` alors que Shop est en LOADING (avant `_ready()` ait connecté son handler) ALORS le signal est perdu. Résolution : au passage en ACTIVE, Shop appelle `CreditEconomy.get_total()` pour initialiser son affichage — il ne dépend pas du signal BOOT_HYDRATE pour son état initial. Garantie par R-SHP-9 (pull actif au `_ready()`), indépendamment de l'ordre d'exécution des autoloads.

**EC-SHP-5 — credits_changed CONNECT_DEFERRED loss** : SI Shop souscrit `credits_changed` via CONNECT_DEFERRED ET qu'un `try_spend` réussi émet le signal dans le même frame que la connexion ALORS le signal peut être livré avec 1 frame de retard (idle frame). Mitigation : Shop ne dépend pas de la première frame du signal — son rendu initial est un pull actif (R-SHP-9 cas initial). Le délai 1-frame post-achat est acceptable côté UI shop (pas de contrainte frame-precise contrairement au gameplay 3D).

**EC-SHP-6 — SaveLoad.load_string_array corruption type** : SI `load_string_array("owned_upgrades", [])` retourne une valeur non-Array (corruption, null, int) ALORS Shop capture la valeur dans un bloc de validation : si type != Array, `_owned_upgrades = []`, `push_warning("ShopSystem: owned_upgrades save corrupted — resetting to empty")` émis, session continue. Catalogue rendu depuis `[]` : tout peut être racheté. Crédits intacts (Credit indépendant), perte limitée à la progression d'upgrades de la session courante.

**EC-SHP-7 — SaveLoad.load_string_array éléments non-StringName** : SI `load_string_array` retourne un Array contenant des éléments non-castables en StringName (entiers, nulls, objets) ALORS Shop filtre chaque élément via `if element is StringName or element is String` au chargement, ne retient que les valides, log un warning par élément rejeté. Array partiellement corrompu donne `_owned_upgrades` partiellement peuplé — préférable au crash.

**EC-SHP-8 — owned_upgrades contient un ID inconnu** : SI `_owned_upgrades` chargé depuis Save contient un StringName ne correspondant à aucune entrée du catalogue (upgrade retirée entre versions) ALORS l'ID est conservé silencieusement dans `_owned_upgrades` (idempotence de persistance — on ne purge pas ce qu'on ne reconnaît pas), mais aucune carte UI n'est générée pour lui. Il ne bloque pas l'achat d'autres upgrades valides. Au prochain `save_string_array`, l'ID inconnu est réécrit tel quel — forward-safe pour Tier 2+ restauration. Log `push_warning` si catalog lookup échoue.

**EC-SHP-9 — SaveLoad.save_string_array échoue post-débit** : SI `try_spend(cost)` retourne `true` (crédits débités irréversiblement), upgrade ajoutée à `_owned_upgrades` en RAM, ET `save_string_array` échoue (disque plein, permissions) ALORS la session continue avec `_owned_upgrades` à jour en RAM — l'upgrade est active jusqu'à fin de session. Au redémarrage, `_owned_upgrades` rechargée depuis save non mis à jour : upgrade perdue, mais `total_credits` aura été débité (Credit persiste indépendamment au prochain quit-to-menu R-CRD-12). Résolution MVP : `push_error`, appliquer `apply_upgrade` normalement (session correcte), signal déjà émis. Tier 2+ : retry ou alerte UX. Risque de cohérence Tier 1 admis.

**EC-SHP-10 — double-clic rapide avant disabled** : SI joueur double-clique sur un bouton affordable avant que Godot ait traité le premier clic et désactivé `BuyButton.disabled` ALORS deux events `pressed` passent dans la queue. Résolution : guard `_purchase_in_progress: bool` posé à `true` au premier clic, remis à `false` à la fin du tween post-achat. Le second event teste ce flag et est ignoré. Guard prioritaire sur `BuyButton.disabled` car Godot peut livrer les deux events avant le prochain `_process`.

**EC-SHP-11 — click sur upgrade déjà OWNED** : SI `BuyButton.disabled = true` est posé mais qu'un clic passe malgré tout (spam input, accessibilité externe, test manuel) ALORS le guard local `_owned_upgrades.has(id)` intercepte avant tout appel à `try_spend`. Aucun crédit débité, aucun signal, log silencieux (comportement attendu). `apply_upgrade(id)` n'est pas rappelé (idempotence garantie côté guard local).

**EC-SHP-12 — ESC pendant animation DISABLED shake** : SI joueur presse ESC pendant l'animation shake (durée ≤ 400 ms cooldown) ALORS shop déclenche fermeture via `request_scene_transition` normalement. Shake abandonné immédiatement (`tween.kill()`). Retour propre. ESC n'attend jamais la fin d'une animation.

**EC-SHP-13 — ESC ou Continue pendant counter tween post-achat** : SI joueur presse ESC ou Continue pendant le tween 300 ms post-achat (compteur animé, carte OWNED) ALORS `request_scene_transition` émis immédiatement. Tween interrompu (kill). État `_owned_upgrades` déjà persisté (R-SHP-8 écrit synchrone au clic, AVANT le tween). `apply_upgrade` déjà appelé. Transition safe à n'importe quel point du tween — aucun état critique n'est porté par l'animation.

**EC-SHP-14 — solde 0 après achat, autres cartes DISABLED dans le même frame** : SI joueur avec 20 cr achète `double_jump` (cost=20, n=0) ALORS `total_credits` passe à 0, `credits_changed(0, -20, SPEND_SHOP)` émis SYNC. Dans le handler `_on_credits_changed`, Shop recalcule `affordable_n` (F-SHP-2) pour toutes les cartes restantes (`dash_horizontal`, cost=40). `0 >= 40` faux → `dash_horizontal.BuyButton.disabled = true` dans le même `_physics_process`. Aucune fenêtre où dash reste cliquable.

**EC-SHP-15 — joueur avec 19 cr (sous le seuil minimum)** : SI `total_credits < BASE_UPGRADE_COST` (19 < 20) à l'ouverture du shop ALORS `affordable_n(19)` retourne `false` pour toutes les upgrades. Toutes les BuyButtons disabled. Seul Continue actif et focalisé. État visuel des cartes DISABLED. Joueur peut sortir via Continue ou ESC. Aucun message d'erreur — état lisible par prix vs solde.

**EC-SHP-16 — UpgradeSystem.apply_upgrade exception post try_spend** : SI `try_spend(cost)` retourne `true` ET `apply_upgrade(id)` lève une exception ou panic ALORS crédits perdus sans upgrade appliquée. Résolution MVP : Shop enveloppe l'appel dans bloc défensif. Si échec : `_owned_upgrades` ne marque pas l'ID owned, `push_error` émis, upgrade reste achetable visuellement. Incohérence crédit/upgrade admise comme risque Tier 1 (contrat UpgradeSystem PROVISOIRE — voir OQ-SHP-2). Tier 2+ : retry ou compensation crédit.

**EC-SHP-17 — UpgradeSystem.apply_upgrade sans Player instancié** : SI Shop appelle `apply_upgrade(id)` alors qu'aucune scène 3D Level n'est active (shop chargé directement depuis MENU) ALORS UpgradeSystem doit différer l'application au prochain `level_active` (contrat PROVISOIRE OQ-SHP-2). Shop ne porte pas de logique de retry — délègue intégralement à UpgradeSystem. Si UpgradeSystem applique au spawn suivant du Player, comportement correct. Si UpgradeSystem plante, EC-SHP-16 s'applique.

**EC-SHP-18 — request_scene_transition avec transition déjà en cours** : SI `GSM.request_scene_transition` est appelé alors qu'une transition GSM est déjà en cours (double-clic Continue, double-press ESC) ALORS GSM rejette le second appel silencieusement (ADR-0007 D-10 — état GSM déjà en transition). Shop ajoute un flag `_closing: bool` posé au premier appel et testé avant tout second appel à `request_scene_transition` (double-safeguard).

**EC-SHP-19 — get_tree().paused = true résiduel** : SI `paused = true` appliqué par Menu System (pause overlay) et non remis à `false` avant chargement shop.tscn ALORS les nœuds Shop dont `process_mode != ALWAYS` seraient gelés. Résolution : tous nœuds interactifs Shop utilisent `PROCESS_MODE_ALWAYS` (R-SHP-16). Le shop est une scène de transition fullscreen — il ne doit pas hériter du pause state du level précédent. GSM doit garantir `paused = false` avant `change_scene_to_file` (à confirmer ADR-0007).

**EC-SHP-20 — Player.died émis depuis scène fantôme pendant shop** : SI un grunt dont le level n'a pas encore été déchargé émet `enemy_killed` ou si `Player.died` est émis pendant que le Shop est actif (scène Level non unloadée) ALORS Credit crédite normalement (indépendant de Shop), mais Shop n'écoute pas `died` directement. GSM reste PLAYING pendant shop. Si joueur "meurt" pendant shop par bug lifecycle, GSM reçoit signal et déclenche RESPAWNING → shop fermé prématurément. Cas pathologique indiquant un bug lifecycle Level — Level doit être entièrement déchargé avant shop.

**EC-SHP-21 — change_scene_to_file échoue (fichier manquant)** : SI `request_scene_transition("res://scenes/shop/shop.tscn")` provoque un `change_scene_to_file` qui échoue (fichier absent, parse error) ALORS Godot émet erreur console et le changement n'a pas lieu — joueur reste dans le level. Shop n'a pas de mécanisme retry. Résolution : test AC vérifie que `shop.tscn` est présent et parseable en CI. En runtime, joueur continue level sans shop — comportement dégradé acceptable vs crash.

**EC-SHP-22 — autoload order : SaveLoad ou CreditEconomy non prêt au _ready()** : SI `Shop._ready()` s'exécute avant que SaveLoad ou CreditEconomy soit initialisé (ordre autoload incorrect) ALORS appels `load_string_array` ou `get_total()` échoueraient. Résolution : Godot 4.6 initialise autoloads dans l'ordre déclaré dans `project.godot`. Contrat de dépendance impose SaveLoad et CreditEconomy listés avant ShopSystem. Comme `shop.tscn` est scène transitoire (non-autoload), son `_ready()` s'exécute après tous les autoloads — ce cas n'existe que si Shop instancié prématurément hors flow GSM (bug d'intégration).

**EC-SHP-23 — shop unloaded mid-purchase (fenêtre 1 frame)** : SI une unload de la scène shop survient dans la fenêtre entre `try_spend(cost) == true` et `apply_upgrade(id)` (un seul `await` ou yield entre les deux) ALORS upgrade non appliquée mais crédits débités. Résolution : aucun `await` ni `yield` autorisé entre `try_spend` et `apply_upgrade` — les deux appels dans le même call stack synchrone du handler `pressed`. Séquence atomique du point de vue GDScript (pas de suspension coroutine). Écriture Save immédiatement après dans le même handler (R-SHP-8).

**EC-SHP-24 — force-quit application pendant shop** : SI joueur force-quit (Alt+F4, SIGKILL) pendant shop ouvert ALORS `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` peut ne pas être reçu. Si achat eu lieu, `save_string_array` déjà écrit synchrone post-achat (R-SHP-8) — upgrade persistée. Si Credit a écrit `save_int` au même moment (R-CRD-12), cohérence garantie. Si force-quit exactement entre débit crédit et écriture save UpgradeSystem, EC-SHP-9 s'applique. Risque Tier 1 admis (force-kill OS ne garantit pas point de sauvegarde).

**EC-SHP-25 — tous owned (catalogue exhaustif 2/2 MVP)** : SI `_owned_upgrades` contient tous les IDs catalogue MVP (`double_jump`, `dash_horizontal`) ALORS toutes cartes affichées OWNED, tous BuyButtons disabled label "POSSÉDÉ". Continue est seul élément actif et focalisé. Aucun achat possible. Shop n'est pas caché ni by-passé automatiquement (joueur peut consulter et sortir). Affichage visuel distinct OWNED vs DISABLED-non-affordable requis (carte OWNED grayed cyan désaturé, pas juste rouge).

**EC-SHP-26 — catalogue vide (N_UPGRADES = 0)** : SI catalogue vide au MVP (anomalie build) ALORS shop affiche zéro cartes, seul Continue visible et actif. Aucun crash, aucune erreur UI. Log `push_warning("ShopSystem: upgrade catalog is empty")`. Cas non production — couvert par AC smoke test catalogue non-vide.

**EC-SHP-27 — resize fenêtre pendant shop ACTIVE** : SI joueur redimensionne fenêtre (mode fenêtré, ultrawide 21:9, portrait 9:16) pendant shop actif ALORS Shop étant Control fullscreen avec ancrage `FULL_RECT`, Godot reflow automatiquement. Cards restent lisibles si marges et `min_size` correctement configurées via `Container`. Aucune logique GDScript requise. AC associé valide cards dans bounds à 1280×720, 1920×1080, 2560×1440.

**EC-SHP-28 — ESC pressé pendant LOADING (avant _ready terminé)** : SI joueur presse ESC avant que `shop._ready()` ait fini (race entre input et scene init) ALORS input ESC mis en queue par Godot et traité au premier `_unhandled_input` après `_ready()`. Shop traite ESC normalement dès qu'il est prêt — effet : fermeture immédiate visuellement transparente. Queue Godot garantit qu'aucun input n'est perdu pendant `_ready()`.

**EC-SHP-29 — reduce motion : tween de counter supprimé** : SI `AccessibilityManager.reduce_motion == true` (Tier 3) ALORS counter tween 300 ms supprimé : valeur hard-set immédiat sans animation. Transition carte vers OWNED instantanée. Functions `_purchase_in_progress` et séquence try_spend/apply/save inchangées — seul l'affichage impacté. EC-SHP-13 reste valide (ESC pendant tween = ESC immédiat car tween = no-op en reduce motion).

**EC-SHP-30 — BuyButton shake cooldown anti-spam** : SI joueur clique 10 fois rapidement sur un BuyButton non-affordable ALORS première tentative déclenche shake (≤ 400 ms). Tentatives suivantes pendant cooldown 400 ms ignorées — shake ne se re-déclenche pas, ne se cumule pas, ne bloque pas l'input Continue. Cooldown porté par timer côté carte (`_shake_cooldown_remaining: float`), pas état global Shop. Continue reste actif et répondant pendant tout le spam.

**EC-SHP-31 — multi-profil saves Tier 2+** : SI Tier 2+ introduit profils multiples (slot 1, slot 2, slot 3) ALORS clé `"owned_upgrades"` doit être préfixée par profile_id (`"profile_1.owned_upgrades"`). MVP : un seul profil, clé non préfixée. Migration vers profile-aware nécessitera amendement Shop r2 + Save/Load API étendu. Hors scope MVP — flag pour OQ-SHP-3.

**EC-SHP-32 — anti-pattern attempt : édition save file (sécurité Tier 3)** : SI joueur édite manuellement save file pour ajouter `"premium_upgrade"` non-acheté ALORS au prochain `_ready()`, l'ID est chargé dans `_owned_upgrades`, mais EC-SHP-8 s'applique : ID inconnu ignoré silencieusement (pas de carte rendue). Pas de validation HMAC/signature MVP — sécurité reportée Tier 3 (anti-cheat). Acceptable car solo offline pas de leaderboard MVP.

**EC-SHP-33 — Audio bus SHOP_UI inexistant si call avant amendement Audio r2.2** : SI Tier 2+ ajoute SFX shop avant amendement Audio r2.2 (bus `SHOP_UI` dans hierarchy) ALORS appel `AudioSystem.play_sfx(..., bus="SHOP_UI")` retourne fallback bus `UI` ou `Master` (Audio GDD comportement défensif). MVP : zéro SFX shop, contrainte non applicable. Flag pour OQ-SHP-4.

**EC-SHP-34 — alt+tab / window minimize pendant shop ACTIVE** : SI joueur Alt+Tab ou minimise fenêtre pendant shop actif ALORS Godot focus loss event reçu. Shop n'a pas de gameplay 3D — pas besoin d'auto-pause GSM (PAUSED état). PROCESS_MODE_ALWAYS garantit que les tweens continuent (pas de gel). Au retour focus, shop resume immédiatement — aucun state à restaurer. Cohérent avec pattern Audio/GSM (ALWAYS).

**EC-SHP-35 — localization MVP : texte FR hardcoded** : SI texte UI Shop ("POSSÉDÉ", "Continuer", "CRÉDITS :") hardcoded en français MVP ALORS aucune localization runtime au MVP. Tier 2+ : extraction strings vers fichier i18n (Godot tr() pattern), flag pour Tier 2+ Localization team. Police monospace fallback : si TTF target absent, Godot fallback sur police système monospace.

## Dependencies

### Hard dependencies (Shop ne peut pas fonctionner sans)

| Système | Status | Direction | Interface | Risque si absent |
|---------|--------|-----------|-----------|------------------|
| **Credit Economy** | ✅ Designed r1 | Bidir (Shop appelle + écoute) | `try_spend(amount: int) -> bool` SYNC atomique (R-CRD-4) ; signal `credits_changed(total, delta, source: SourceKind)` SYNC ; getter `get_total() -> int` ; constantes `BASE_UPGRADE_COST=20`, `TIER_COST_STEP=20` (F-CRD-3). | Shop non fonctionnel — pas de débit possible, catalogue n'a aucun coût utilisable. |
| **Game State Manager** | ✅ APPROVED r1 | Out (Shop appelle) + indirect In (instanciation par GSM) | `request_scene_transition(scene_path: String)` (ADR-0007 D-10, l'un des 5 verbes publics figés) ; instanciation Shop déclenchée par `etage_completed` → GSM → `change_scene_to_file`. | Shop ne peut être lancé ni fermé proprement — pas de transition de scène orchestrée. |
| **Save/Load System** | ⚠️ Not Started (PROVISIONAL) | Bidir (Shop lit + écrit) | `save_string_array(key: StringName, array: Array[StringName]) -> void` ; `load_string_array(key: StringName, default: Array[StringName]) -> Array[StringName]`. Clé `"owned_upgrades"`. | Pas de persistance owned_upgrades — Shop perd l'état entre sessions, joueur peut re-acheter (perte de crédits). Voir OQ-SHP-3. |

### Soft dependencies (Shop est réduit / dégradé sans)

| Système | Status | Direction | Interface | Comportement dégradé |
|---------|--------|-----------|-----------|---------------------|
| **Upgrade System** | ⚠️ Not Started (PROVISIONAL) | Out (Shop appelle) | `apply_upgrade(id: StringName) -> void` SYNC idempotent | Achat marqué owned + persisté, mais capacité gameplay non activée. EC-SHP-16 + EC-SHP-17 décrivent le comportement défensif. Voir OQ-SHP-2. |
| **Audio System** | ✅ APPROVED r2.1 (peer Tier 2+ pour SFX shop) | Out (Shop appelle Tier 2+) | Tier 2+ : `AudioSystem.play_sfx(id, bus="SHOP_UI" \| "UI")` après amendement Audio r2.2 | MVP : zéro SFX, shop silencieux côté audio. Cohérent Audio r2.1 scope. Voir OQ-SHP-4. |
| **Input System** | ✅ Designed r4 (peer events UI) | In (events) | `_unhandled_input` Godot standard ; action `ui_cancel` via InputMap ; jamais d'accès direct `Input.*` (Input Core Rule 1 conformity) | Shop conforme par défaut Godot UI routing. Pas de risque. |
| **Menu System** | ⚠️ Not Started (sibling) | Sibling (séquence GSM) | Aucun appel direct. Coordination par GSM `request_scene_transition` (Shop → Menu MVP, Menu → Shop Tier 2+ via boutons menu). | MVP : transition vers `main_menu.tscn` (en cours d'écriture côté Menu). Au pire fallback : retour direct `main_scene.tscn`. |

### Cousin systems (proximité fonctionnelle, pas de couplage)

| Système | Status | Relation | Notes |
|---------|--------|----------|-------|
| **HUD System** | ✅ Designed r1 | Cousin UI — partage typo monospace + couleurs Chrome Zen + autorité Credit r1 sur compteur | HUD vit dans scène 3D Level. Quand shop.tscn devient active, HUD déchargé avec Level. Aucun couplage direct. Compteur shop = Label distinct du compteur HUD (même contrat Credit, deux Labels indépendants — HUD r1 R-6 hard-set silencieux vs Shop J.3 tween 300 ms). |
| **Level System** | ✅ APPROVED r3 | Cousin trigger — émet `etage_completed` consommé par GSM | Shop n'écoute pas directement `etage_completed`. Level ignore l'existence de Shop. Tier 2+ : payload `next_etage_id` à passer via mécanisme défini OQ-SHP-1. |
| **Player Combat / Movement** | APPROVED r6/r3 | Cousins — fournissent les events qui alimentent Credit (kills, mort) | Aucun couplage Shop. Movement consomme les upgrades activées par UpgradeSystem (transitivement). |
| **Secret System** | Designed r1 | Cousin source crédits | Aucun couplage direct. Secret alimente Credit, Credit alimente Shop. Asymétrie 5:1 secret/kill (F-CRD-2 vs F-CRD-1) cible explicite Pillar 4 dans la fantasy Shop. |

### Anti-dependencies (Shop ne doit JAMAIS coupler avec)

| Système | Raison du non-couplage | Lint testable |
|---------|----------------------|---------------|
| **VFX & Feedback System** (Not Started) | Shop = écran statique sans gameplay 3D, aucun particle effect requis. Anti-distraction Pillar 1. | AC-SHP-43 : zéro AudioStreamPlayer ; zéro GPUParticles3D dans shop.tscn |
| **Enemy System** | Shop = scène hors gameplay, aucun ennemi présent. | Architecture par construction (scène container indépendante) |
| **Checkpoint & Respawn System** | Shop n'a pas de mort possible — RESPAWN_DELAY hors scope. | EC-SHP-20 : signal `Player.died` pendant shop = bug lifecycle Level, pas comportement attendu |
| **Tutorial / Onboarding System** (Vertical Slice) | Shop doit s'auto-expliquer (game-concept anti-tutoriel intrusif). Pas de texte d'aide MVP. | J.4 : aucun tooltip sur "Continuer" |

### Bidirectional check

- Credit Economy r1 §Interactions table cite Shop comme aval consommateur de `try_spend` ✅
- Credit Economy r1 §Open Questions OQ-CRD-2 : "contrat try_spend Shop" — **resolved by this GDD** : Shop confirme l'API `try_spend(amount: int) -> bool` SYNC atomique à l'identique (recommandation Phase 5 : Credit GDD peut promote OQ-CRD-2 RESOLVED en amendement r2 ou laisser le statut, le contrat est verrouillé)
- GSM r1 §Dependencies cite Shop dans "ShopSystem (inferred, Not Started) → Hard (Tier 2+) — Shop scene chargée via `request_scene_transition`" ✅
- HUD r1 §Interactions soft Tier 2+ : pas de couplage direct mais comportement HUD R-6 SPEND_SHOP hard-set est cohérent avec philosophie Shop (HUD silencieux pendant transactions shop)
- Save/Load (Not Started) : Shop fournira contrat `save_string_array` à confirmer lors design Save/Load #3
- Upgrade System (Not Started) : Shop fournira contrat `apply_upgrade` à confirmer lors design Upgrade #13
- Menu System (Not Started) : sibling — aucun contrat à confirmer côté Shop, GSM orchestre

### Provisional contracts résumé

| Contrat | Owner provider | Owner consumer | Status |
|---------|----------------|----------------|--------|
| `UpgradeSystem.apply_upgrade(id: StringName) -> void` SYNC idempotent | Upgrade System (Not Started) | Shop | PROVISOIRE — OQ-SHP-2 |
| `SaveLoad.save_string_array(key, array)` + `load_string_array(key, default)` | Save/Load (Not Started) | Shop | PROVISOIRE — OQ-SHP-3 |
| `AudioSystem.play_sfx(id, bus="SHOP_UI" \| "UI")` Tier 2+ | Audio (APPROVED r2.1) | Shop | PROVISOIRE Tier 2+ — OQ-SHP-4 |
| Shop `etage_completed → GSM → request_scene_transition(shop.tscn)` | Level r3 + GSM r1 | Shop (consumer indirect) | LOCKED — pas de contrat Shop direct |

## Tuning Knobs

### MVP — Design-active

| Knob | Default | Safe range | Impact | Owner |
|------|---------|------------|--------|-------|
| `N_UPGRADES_MVP` | 2 | [2, 4] | Nombre d'upgrades dans le catalogue MVP. Augmenter > 2 nécessite F-SHP-3 re-validation (`total_cost <= session_yield_max`). À > 4 : migration vers `shop_catalog.tres` Resource (R-SHP-3 Tier 2+ trigger). | Shop GDD |
| `SHOP_FADE_IN_DURATION_MS` | 200 | [100, 400] | Durée fade-in à l'entrée du shop (post-`etage_completed`). En-dessous 100 ms = cut brutal ; au-dessus 400 ms = friction perceptible. Cohérent GSM Formula 2 budget total 285 ms. | Shop GDD |
| `SHOP_FADE_OUT_DURATION_MS` | 200 | [100, 400] | Durée fade-out à la sortie. Symétrique fade-in. | Shop GDD |
| `SHOP_CREDIT_TWEEN_DURATION_MS` | 300 | [100, 500] | Durée animation décrément compteur post-achat. Distinct du HUD r1 R-6 hard-set silencieux. Sentiment "prix qui tombe". | Shop GDD |
| `SHOP_PURCHASE_PULSE_DURATION_MS` | 150 | [100, 250] | Durée pulse scale 1.0→1.03→1.0 sur UpgradeCard post-achat. | Shop GDD |
| `SHOP_DISABLED_SHAKE_AMPLITUDE_PX` | 4 | [2, 8] | Amplitude horizontale shake sur clic non-affordable. > 8 = trop violent. < 2 = imperceptible. | Shop GDD |
| `SHOP_DISABLED_SHAKE_DURATION_MS` | 200 | [150, 300] | Durée shake. | Shop GDD |
| `SHOP_DISABLED_SHAKE_COOLDOWN_MS` | 400 | [300, 600] | Cooldown anti-spam shake (EC-SHP-30). Garantit < 3 Hz fréquence (J.8 accessibility). | Shop GDD |
| `SHOP_HOVER_TOOLTIP_DELAY_MS` | 400 | [300, 800] | Délai avant affichage tooltip "X crédits manquants" sur hover DISABLED. Standard tooltip Godot. | Shop GDD |

### MVP — Structurel (modification = ADR ou cross-GDD)

| Knob | Default | Justification figée |
|------|---------|--------------------|
| `SHOP_CANVAS_LAYER` | 60 | Above HUD=50, below GSM overlay=100. Modification = revoir hiérarchie CanvasLayer projet. |
| `SHOP_PROCESS_MODE` | `PROCESS_MODE_ALWAYS` | Pattern projet (Audio/GSM/Save-Load tous ALWAYS). Modification = amendement architecture. |
| `SHOP_TWEEN_PAUSE_MODE` | `TWEEN_PAUSE_PROCESS` | Wall-clock indépendant `Engine.time_scale`. Modification = amendement projet. |
| `SAVE_LOAD_KEY_OWNED_UPGRADES` | `"owned_upgrades"` | Clé Save/Load. Modification = migration save (Tier 2+) + amendement Save/Load contract. |

### Tuning visuels (Chrome Zen palette — voir J.7)

| Token | Default | Range / Note |
|-------|---------|--------------|
| `SHOP_BG` | `#0A0A12` | Background fullscreen. Range : tons sombres < `#202030`. |
| `SHOP_SURFACE` | `#111120` | Panel upgrade NORMAL. |
| `SHOP_SURFACE_HOVER` | `#161628` | Panel HOVER (souris affordable). |
| `SHOP_SURFACE_INACTIVE` | `#0D0D18` | Panel DISABLED / OWNED. |
| `SHOP_SEPARATOR` | `#2A2A3A` | HSeparator, bordures NORMAL. |
| `SHOP_TEXT_PRIMARY` | `#E8E8F0` | Labels principaux (cohérence HUD). |
| `SHOP_TEXT_SECONDARY` | `#6E6E8A` | Descriptions, tooltips. |
| `SHOP_ACCENT` | `#3EE4FF` | Bordure HOVER, glow affordable, flash spend. Cohérence Pillar 4 sémantique cyan = interactif. |
| `SHOP_ACCENT_OWNED` | `#2A8A8A` | Cyan désaturé — OWNED cost label. |
| `SHOP_COST_BLOCKED` | `#FF4455` | Cost label DISABLED (rouge sémantique hostile). |

### Tier 2+ — Hooks réservés (déclarés ici pour archive)

| Knob réservé | Default cible | Activation |
|--------------|---------------|------------|
| `SHOP_REDUCE_MOTION` | `false` | Tier 3 Accessibility — supprime tween counter, fade transitions instant, shake DISABLED supprimé |
| `SHOP_FONT_SCALE_FACTOR` | `1.0` | Tier 3 Accessibility — multiplicateur taille texte (relatif `theme_override_font_sizes`) |
| `SHOP_SFX_BUS` | `"UI"` | Tier 2+ — bus audio cible si SFX shop activés (amendement Audio r2.2 requis) |
| `SHOP_PROFILE_PREFIX` | `""` | Tier 2+ multi-profile saves — préfixe clé (`"profile_1.owned_upgrades"`) |
| `SHOP_NEXT_ETAGE_PARAM` | `null` | Tier 2+ — payload `next_etage_id` reçu de Level via mécanisme à définir (OQ-SHP-1) |

## Visual/Audio Requirements

### Visuel — palette Chrome Zen Shop

> Voir Section J pour le détail layout/wireframe complet. Cette section fixe les **requirements** transverses Visual + Audio à un niveau GDD, pas la pixel-perfect spec (UX flag délégué à `design/ux/shop-screen.md`).

| Élément | Asset / Spec MVP | Tier 2+ |
|---------|------------------|---------|
| **Background fullscreen** | `ColorRect` solid `#0A0A12` (noir profond bleuté). Aucune texture, aucun shader, aucune animation. | Optional shader subtle vignette `vignette_intensity = 0.05` (Chrome Zen "le vide rend la lame visible") |
| **Typo** | Police monospace TTF libre (JetBrains Mono ou IBM Plex Mono) — partagée avec HUD r1. Sizes : 16 px display_name, 20 px cost label + counter, 24 px bouton "CONTINUER". | Custom font Tier 2+ corporate (Asset Spec) |
| **Couleur d'accent** | Une seule par écran — cyan `#3EE4FF` (sémantique Pillar 4 = interactif). Rouge `#FF4455` informatif (cost DISABLED), pas décoratif. | Inchangé. |
| **Icon upgrade** | Placeholder MVP : `ColorRect` 32×32 cyan opacity 40 %. | Asset Spec : SVG/TTF icône par upgrade (target 32×32 ou 48×48) |
| **Bordures cards** | StyleBoxFlat `1 px` solid, color variable par état (NORMAL `#2A2A3A`, HOVER `#3EE4FF`, DISABLED `#1A1A28`, OWNED `#1E3A3A`). | Inchangé. |
| **Glow affordable subtle** | `StyleBoxFlat.shadow_color = #3EE4FF` opacity 20 %, `shadow_size = 4 px` sur cartes NORMAL. | Désactivable knob `SHOP_AFFORDABLE_GLOW_ENABLED` Tier 3 Accessibility. |
| **Counter compteur crédits** | Label monospace 20 px `#E8E8F0`, préfixe `₵` opacity 60 %. Tween décrément 300 ms `EASE_OUT TRANS_QUAD` (sentiment "prix qui tombe"). | Inchangé. |
| **Pulse achat réussi** | Tween scale UpgradeCard 1.0→1.03→1.0 sur 150 ms `TRANS_SINE`. | Inchangé. |
| **Shake refus** | Tween offset_x 0→4→-4→2→0 sur 200 ms `TRANS_SINE`, cooldown 400 ms anti-spam. | Inchangé. |
| **Fade IN/OUT** | 200 ms linéaire via GSM transition. | Inchangé. |

### Audio — MVP zéro SFX shop

| Élément | Status MVP | Justification |
|---------|------------|---------------|
| **SFX clic affordable** | ❌ Aucun MVP | Audio GDD r2.1 : pas de bus shop défini. Cohérent ligne 169 audio-system.md "zéro SFX UI MVP". HUD reste silencieux côté audio (HUD r1 R-6). Tier 2+ amendement Audio r2.2 ajoutera bus `SHOP_UI` ou réutilisera `UI`. |
| **SFX clic refusé** | ❌ Aucun MVP | Idem. Feedback visuel (shake) suffit Pillar 1. |
| **SFX hover** | ❌ Jamais | Anti-pattern (bruit constant avec mouse mouvement). |
| **SFX achat réussi** | ❌ Aucun MVP | Pas de fanfare — anti-fantasy "moment de récompense". |
| **SFX fermeture / "Continuer"** | ❌ Aucun MVP | Idem. Transition GSM gère son propre fade audio (Audio r2.1 ducking strategy). |
| **Musique ambiance shop** | ❌ Aucune MVP | Audio r2.1 ne définit pas de stem `shop_ambience`. Cohérent Pillar 1 "silence rythmique". |
| **Bus SHOP_UI** | ❌ Inexistant MVP | Voir OQ-SHP-4 — amendement Audio r2.2 requis Tier 2+ pour activation. |

### Tier 2+ Audio (post amendement Audio r2.2)

| SFX | Bus | Asset spec |
|-----|-----|-----------|
| `shop_purchase_success` | `SHOP_UI` ou `UI` | clac sec court 80-120 ms, monaural, cohérent palette Audio "clac" |
| `shop_purchase_denied` | `SHOP_UI` ou `UI` | thud grave court 60-100 ms, opposé sémantique du clac |
| `shop_continue` | `SHOP_UI` ou `UI` | swoosh court 150 ms (transition prep) |

### Anti-pattern Visual/Audio (testables)

| Anti-pattern | Test |
|--------------|------|
| Particles GPU sur achat (confetti, sparkles) | AC lint static : zéro `GPUParticles2D/3D` dans shop.tscn |
| Animation arrière-plan ambiance | AC lint static : zéro `AnimationPlayer` connecté au background ColorRect |
| Texture corporate animée | AC lint static : zéro `AnimatedTexture` dans shop.tscn |
| SFX hover persistant | AC lint static : zéro `mouse_entered.connect(_play_sfx)` |
| Fanfare achat | AC lint static MVP : zéro `AudioStreamPlayer` instancié |
| Musique stinger | AC lint static MVP : aucun appel `AudioSystem.play_music_stinger` (méthode Audio absente MVP) |

## UI Requirements

> **Contrat de section** : cette section fixe les requirements UX/UI du Shop Screen MVP. Définit structure de nœud, états visuels, comportements interactifs, contraintes accessibilité. L'implémentation Godot cite ces specs ; toute déviation requiert révision GDD.

### J.1 — Layout global (fullscreen Control)

**Philosophie** : le shop est la seule interruption volontaire du flow. Le joueur *sort* du 3D world — la scène fullscreen signale sans ambiguïté ce changement de registre. Pas d'overlay semi-transparent sur le gameplay : ambiguïté "suis-je encore en danger ?" qui viole Pillar 1.

#### Hiérarchie de nœuds proposée

```
Control [shop_root]          ← FULL_RECT, CanvasLayer = 60 (above HUD=50, sous Menu=100)
  └── ColorRect [bg]         ← fond pleine fenêtre, couleur unie #0A0A12
  └── MarginContainer        ← marges uniformes 64 px (1080p), 80 px (1440p)
        └── VBoxContainer [layout_main]
              ├── Label [shop_title]      ← "SHOP" monospace
              ├── HSeparator              ← ligne fine 1 px #2A2A3A
              ├── Control [credit_bar]    ← compteur crédits (J.3)
              ├── VBoxContainer [catalogue_container]   ← items upgrades (J.2)
              └── HBoxContainer [footer]  ← spacer + bouton Continuer (J.4)
```

**Stratégie d'ancrage** : `Control.LayoutPreset.FULL_RECT` sur `shop_root`. Resize fenêtre géré nativement Godot 4.6.

**Background** : `#0A0A12` solid uni. Pas de texture, shader, image. Pillar 1 — toute texture corporate animée crée un plan concurrent. Le vide rend le catalogue visible.

**Position compteur crédits** : top-right via `credit_bar` aligné à droite dans le `VBoxContainer`. Cohérence stricte avec HUD gameplay (top-right `#E8E8F0`) — joueur ne cherche pas, il sait où il est.

### J.2 — Catalogue d'upgrades

#### Widget par upgrade : `PanelContainer` + `Button` interne

```
PanelContainer [upgrade_row]          ← état visuel via StyleBoxFlat swap
  └── HBoxContainer
        ├── Control [icon_slot]       ← 32×32 px, placeholder MVP
        ├── VBoxContainer [info]
        │     ├── Label [display_name]   ← "Saut Double" / "Dash Horizontal" — monospace 16 px #E8E8F0
        │     └── Label [description]    ← courte description — monospace 12 px #6E6E8A
        └── HBoxContainer [cost_block]
              ├── Label [symbol]        ← "₵" monospace, opacity 60 %
              └── Label [cost]          ← "20" / "40" — monospace 20 px, couleur variable
```

#### États visuels

| État | Condition | Background | Bordure | Couleur cost | Curseur |
|------|-----------|-----------|---------|--------------|---------|
| **NORMAL** | Affordable, non possédé | `#111120` | `1 px #2A2A3A` | `#E8E8F0` | `CURSOR_POINTING_HAND` |
| **HOVER** | Souris sur row affordable | `#161628` | `1 px #3EE4FF` | `#E8E8F0` | `CURSOR_POINTING_HAND` |
| **DISABLED** | `credits < cost`, non possédé | `#0D0D18` | `1 px #1A1A28` | `#FF4455` (rouge hostile) | `CURSOR_ARROW` |
| **OWNED** | `_owned_upgrades.has(id)` | `#0D0D18` | `1 px #1E3A3A` | `#2A8A8A` (cyan désaturé) | `CURSOR_ARROW` |

**Notes** :
- HOVER existe uniquement sur NORMAL.
- `#FF4455` cost DISABLED : rouge sémantique sans label texte — game-concept ligne 138 rouge=hostile.
- OWNED : `display_name` opacity 50 % — recule visuellement, laisse les affordables dominer la hiérarchie.
- Aucun badge "NEW" / "SALE" / "RECOMMENDED" — anti-patterns F2P.

**Layout catalogue** : `VBoxContainer` vertical, `separation = 12 px`. Deux upgrades MVP — liste verticale suffit. Grid 2D prématurée (parité fausse).

**Affordable feedback (glow subtil)** : `StyleBoxFlat.shadow_color = #3EE4FF` opacity 20 %, `shadow_size = 4 px` sur rows NORMAL. Visible en attention diffuse, invisible en regard direct. Désactivable knob `SHOP_AFFORDABLE_GLOW_ENABLED` Tier 3 Reduce Motion.

### J.3 — Compteur crédits live

**Position** : `credit_bar` aligné à droite, `custom_minimum_size.y = 40 px`, sous `HSeparator`.

**Typographie** : monospace `20 px` (vs HUD 18 px — shop écran statique, lisibilité prime), couleur `#E8E8F0`. Préfixe `₵` opacity 60 %.

**Connexion signal** :
- **Boot** : pull synchrone `CreditEconomy.get_total()` au `_ready()` (R-SHP-9, ADR-0007 D-9).
- **Live** : `credits_changed.connect(..., CONNECT_DEFERRED)` — update à chaque transaction.

**Animation post-spend** :
- Tween durée `300 ms` (milieu plage 200-400 ms Credit GDD ligne 384).
- Interpolation linéaire `from old_value to new_value` via `Tween.interpolate_value`.
- Easing `Tween.EASE_OUT TRANS_QUAD` — chiffre baisse vite début, ralentit arrivée. Effet "prix qui tombe".
- Couleur flash `#E8E8F0 → #3EE4FF → #E8E8F0` overlay sur 150 ms (opacity 0→0.6→0) simultané au tween numérique. Cyan = confirmation interactive.
- **Distinct du HUD r1 R-6 hard-set silencieux**. Le shop a son propre feedback.

### J.4 — Bouton "Continuer"

**Position** : `HBoxContainer [footer]` en bas, spacer flexible le pousse en bas. Centré horizontalement (`alignment = CENTER`).

**Taille** : `custom_minimum_size = Vector2(200, 48)` — Fitts's Law, atteignable sans précision.

**Label** : `"CONTINUER"` capitales monospace. Cohérence FR (game-concept FR). Alternative `"→"` rejetée (accessibilité screen reader).

**Comportement** :
- Click souris gauche → `request_scene_transition(...)`.
- Touche `Enter` ou `Space` quand focus clavier → identique.
- Pas de confirmation dialog.
- ESC = identique (R-SHP-11).

**État visuel** :
- NORMAL : bordure `1 px #2A2A3A`, background `#111120`, label `#E8E8F0`.
- HOVER : bordure `1 px #E8E8F0`, background `#161628`, label `#FFFFFF`. **Pas de cyan** — cyan réservé aux éléments d'achat. Continue = navigation, pas achat.
- PRESSED : `scale 0.97` instantané, release → `1.0` sur 80 ms.

### J.5 — Affordance feedback (détail)

#### AFFORDABLE — hover

- Background panel `#111120 → #161628` immédiat (pas de tween — Pillar 1 latence hover).
- Bordure `#2A2A3A → #3EE4FF` immédiat.
- Curseur `CURSOR_POINTING_HAND`.
- Pas d'arrow indicator, pas de tooltip — état visuel suffit pour 2 items MVP.

#### DISABLED — hover

- Curseur `CURSOR_ARROW`.
- Tooltip `RichTextLabel` Godot natif `"[X] crédits manquants"` (ex. `"20 crédits manquants"`). Délai `400 ms` (knob `SHOP_HOVER_TOOLTIP_DELAY_MS`).
- Tooltip background `#0A0A12`, texte `#6E6E8A`, sans bordure colorée.
- Cost label `#FF4455` = signal primaire ; tooltip = secondaire.

#### OWNED — hover

- Curseur `CURSOR_ARROW`.
- Tooltip `"Déjà acquis"` — délai 400 ms.
- Pas de glow, pas d'animation.

#### Click AFFORDABLE (achat — voir R-SHP-6 cycle complet)

1. Cycle achat (try_spend → save → apply → disable button) — voir Section C.
2. Counter tween 300 ms (J.3).
3. Row transition immédiate vers OWNED (StyleBox swap).
4. **Pas de modal**. Pas de confetti, pas de particules, pas de fanfare.
5. Cartes restantes recalculent affordability via `credits_changed` handler — passages NORMAL→DISABLED dans le frame.

#### Click DISABLED

- No-op fonctionnel (event consommé, pas de transaction).
- Shake horizontal `offset_x : 0 → 4 → -4 → 2 → 0` sur 200 ms `TRANS_SINE`. Cooldown 400 ms anti-spam (J.8 / EC-SHP-30).
- Pas de son MVP. Cost label `#FF4455` = signal principal.

### J.6 — Transitions IN/OUT

**Entrée** : GSM transition vers `shop.tscn` → fade-in 200 ms `black → transparent` (CanvasLayer GSM layer 100 above shop layer 60). `EASE_OUT TRANS_LINEAR`. Budget perceptuel 285 ms total (GSM Formula 2). Scène shop légère (zéro mesh 3D, zéro shader complexe).

**Sortie** : Click "Continuer" → `request_scene_transition` → GSM fade-out 200 ms `transparent → black` → load scène suivante derrière le fondu.

### J.7 — Cohérence Chrome Zen

#### Palette MVP (cf. Tuning Knobs visuels)

Voir tableau Section "Tuning Knobs - Tuning visuels".

**Choix background `#0A0A12` (noir profond)** : rejet du blanc cassé pour 3 raisons :
1. Chrome Zen dans le jeu = environnement majoritairement sombre — shop blanc serait rupture tonale non préparée.
2. `#3EE4FF` cyan ressort mieux sur fond sombre (contraste WCAG AA garanti).
3. Fond sombre minimise fatigue oculaire pendant pause décision (cohérent moment de calme).

**Typo** : monospace TTF libre (JetBrains Mono / IBM Plex Mono) partagé HUD. Asset placeholder MVP, finalisation Tier 2+.

**Règles strictes Chrome Zen** :
- Zéro gradient (`StyleBoxFlat` uniquement).
- Zéro blur.
- Zéro animation arrière-plan (ColorRect statique).
- Zéro décoration superflue (pas de NinePatchRect texture complexe, pas d'ornements coins).
- Lignes droites, marges généreuses (64 px min 1080p).
- Une seule couleur d'accent par écran : `#3EE4FF`. Rouge `#FF4455` informatif (cost DISABLED), pas décoratif.

### J.8 — Accessibility (flags Tier 2+ et Tier 3)

#### Tier 1 — MVP obligatoire

- **Clavier** : `Tab` navigue rows + Continue. `Enter`/`Space` active. `Escape` = Continue.
- **Focus visible** : élément focalisé clavier → bordure `2 px #E8E8F0` (distinct HOVER souris cyan). Godot 4.6 dual-focus : `mouse_filter = MOUSE_FILTER_STOP`, `focus_mode = FOCUS_ALL`.
- **Couleur non exclusive** : DISABLED signalé par cost rouge **+** absence `CURSOR_POINTING_HAND` **+** comportement no-op clic.
- **Pas de contenu flashant** : aucune animation > 3 Hz. Shake DISABLED 200 ms (5 Hz potentiel sur spam) → cooldown 400 ms (EC-SHP-30) garantit < 3 Hz.

#### Tier 2+ — Gamepad

- `focus_neighbor_bottom`/`focus_neighbor_top` : topologie verticale rows + Continue.
- Bouton Sud (A/Cross) = confirm. Bouton Est (B/Circle) = Continue (cancel-to-continue pattern).
- Deadzone stick `|stick_y| > 0.5`, délai répétition 300 ms.
- UX spec `design/ux/shop-screen.md` définira topologie complète.

#### Tier 3 — Accessibilité avancée

- **Reduce Motion** (`SHOP_REDUCE_MOTION = true`) : fade IN/OUT instant (0 ms), tween counter supprimé (hard-set immédiat), shake DISABLED supprimé.
- **Screen reader** (Godot 4.5+ AccessKit) : `accessible_name` sur chaque row : `"[display_name], coût [X] crédits, [état]"`. Ex : `"Saut Double, coût 20 crédits, disponible"`.
- **Font scale** : `SHOP_FONT_SCALE_FACTOR` via `theme_override_font_sizes` relatifs — aucun `px` hardcoded.

### J.9 — Anti-patterns Shop UI MVP (testables QA)

| Anti-pattern | Raison | Test QA |
|---|---|---|
| Modal confirmation popup avant achat | Friction Pillar 1 | Inspecter shop.tscn : aucun `AcceptDialog` / `ConfirmationDialog` |
| News feed / promo banner | Anti-pillar grinding / F2P | Aucun `ScrollContainer` en background |
| Monnaie premium séparée | Pas de F2P | Un seul Label compteur `₵` |
| Onglet cosmétiques | Pas de cosmetics | Aucun `TabContainer` |
| Skill tree visualization | Tier 2+ Upgrade, pas Shop | Aucun nœud graphe arbre |
| Animated background loop | Pillar 1 distraction | `bg ColorRect` statique, `AnimationPlayer` interdit sur bg |
| Damage numbers / "+XP" pop-ups | Anti-pattern HUD global | Aucun `Label` instancié dynamiquement post-achat |
| Sound de fanfare | Audio MVP scope | Aucun `AudioStreamPlayer` (cohérence Audio r2.1) |
| Tooltip sur "Continuer" | Action évidente, condescendant | Aucun tooltip assigné au footer button |

### J.10 — UX Flag

> **📌 UX Flag — Shop System** : ce GDD §J fixe les *requirements* UX (structure, états, comportements, contraintes). Avant `/create-epics shop-system`, produire `design/ux/shop-screen.md` via `/ux-design shop-screen.md`. Le UX spec contiendra :
> - Mockups textuels / wireframes annotés par état
> - Motion curves exactes (Tween type, duration, easing) pour chaque animation
> - Topologie `focus_neighbor` complète gamepad Tier 2+
> - `accessible_name` complète screen reader Tier 3
> - Vérification WCAG AA contrastes (`#3EE4FF` sur `#0A0A12`, `#E8E8F0` sur `#111120`, `#FF4455` sur `#0D0D18`)
>
> Stories d'implémentation UI citeront `design/ux/shop-screen.md`, pas le présent GDD directement.

## Acceptance Criteria

> **52 ACs total** — 32 BLOCKING + 20 ADVISORY. Distribution : 41 AUTO (Logic+Integration+Lint+Performance), 8 MANUAL (Visual+Manual-Playtest), 3 PROVISIONAL (chain-blocked OQ-SHP-2/3/4). Couvre 11 sous-thèmes A-K.

### Groupe A — Boot et hydration

**AC-SHP-1 [Logic] [BLOCKING]** : GIVEN shop.tscn instancié, WHEN `Shop._ready()` s'exécute, THEN `_owned_upgrades` contient exactement les ids retournés par `SaveLoad.load_string_array("owned_upgrades", [])`. *Mécanisme* : unit GUT — mock SaveLoad retournant `["double_jump"]`, instancier ShopControllerScript, assert `_owned_upgrades == ["double_jump"]` via getter `get_owned_upgrades()`.

**AC-SHP-2 [Logic] [BLOCKING]** : GIVEN `load_string_array` retourne `[]` (key absente), WHEN `_ready()` s'exécute, THEN `_owned_upgrades == []` et aucune upgrade marquée OWNED. *Mécanisme* : unit GUT — mock retournant `[]`, assert liste vide, assert deux BuyButtons non disabled.

**AC-SHP-3 [Logic] [BLOCKING]** : GIVEN `CreditEconomy.get_total()` retourne 35, WHEN `_ready()` s'exécute, THEN `CreditValueLabel.text` affiche `"35"` avant tout signal reçu. *Mécanisme* : unit GUT — mock get_total retournant 35, instancier, assert label text.

**AC-SHP-4 [Lint] [BLOCKING]** : GIVEN `_ready()`, WHEN connexion à `credits_changed`, THEN flag `CONNECT_DEFERRED` présent. *Mécanisme* : lint static — grep `credits_changed.connect` dans ShopControllerScript, vérifier `CONNECT_DEFERRED` ; ou unit GUT via `signal.get_connections()` assert flag bitmask.

**AC-SHP-5 [Integration] [BLOCKING]** : GIVEN `_owned_upgrades == ["double_jump"]` et solde 15, WHEN catalogue rendu après `_ready()`, THEN `double_jump` BuyButton.disabled=true OWNED visible, `dash_horizontal` BuyButton.disabled=true DISABLED (15<40). *Mécanisme* : integration scene — instancier shop.tscn avec mocks, assert états boutons.

### Groupe B — Cycle d'achat (R-SHP-6)

**AC-SHP-6 [Logic] [BLOCKING]** : GIVEN `dash_horizontal` affordable et non owned, WHEN click BuyButton, THEN `try_spend(40)` appelé exactement 1 fois. *Mécanisme* : unit GUT — mock CreditEconomy avec compteur, simuler `_on_buy_pressed("dash_horizontal")`, assert count==1.

**AC-SHP-7 [Logic] [BLOCKING]** : GIVEN `try_spend(20)` retourne `true`, WHEN cycle s'exécute, THEN `_owned_upgrades.has("double_jump") == true` immédiatement. *Mécanisme* : unit GUT — assert `get_owned_upgrades().has("double_jump")` avant tout yield.

**AC-SHP-8 [Logic] [BLOCKING]** : GIVEN `try_spend` retourne true, WHEN cycle s'exécute, THEN `save_string_array` appelé AVANT `apply_upgrade`. *Mécanisme* : unit GUT — mocks avec séquence d'appels journalisée `_call_order: Array[String]`, assert `find("save") < find("apply")`.

**AC-SHP-9 [Logic] [BLOCKING]** : GIVEN `try_spend(40)` retourne true, WHEN cycle dash_horizontal s'exécute, THEN `apply_upgrade("dash_horizontal")` appelé exactement 1 fois. *Mécanisme* : unit GUT — mock UpgradeSystem avec compteur, assert count==1.

**AC-SHP-10 [Logic] [BLOCKING]** : GIVEN `try_spend(20)` retourne true et cycle complété, WHEN rendu post-achat, THEN `BuyButton_double_jump.disabled == true`. *Mécanisme* : unit GUT — assert état bouton après cycle.

**AC-SHP-11 [Logic] [BLOCKING]** : GIVEN solde 15 et double_jump non owned (cost 20), WHEN tentative achat, THEN `try_spend` NON appelé, `_owned_upgrades` inchangé, `save_string_array` NON appelé, `apply_upgrade` NON appelé. *Mécanisme* : unit GUT — mocks avec compteurs, forcer solde<cost, assert tous compteurs == 0.

**AC-SHP-12 [Integration] [BLOCKING]** : GIVEN shop ACTIVE et émission `credits_changed(15, -5, SPEND_SHOP)`, WHEN handler invoqué, THEN `CreditValueLabel.text == "15"` ET `BuyButton_double_jump.disabled == true` (15<20) ET `BuyButton_dash_horizontal.disabled == true` (15<40). *Mécanisme* : integration scene — émettre signal manuellement, assert labels et boutons même frame.

### Groupe C — Idempotence

**AC-SHP-13 [Logic] [BLOCKING]** : GIVEN double_jump affordable et non owned, WHEN `_on_buy_pressed("double_jump")` appelé 2 fois en succession immédiate, THEN `try_spend` appelé exactement 1 fois total. *Mécanisme* : unit GUT — guard `_purchase_in_progress` bloque le 2e ; mock try_spend compteur, assert == 1.

**AC-SHP-14 [Logic] [BLOCKING]** : GIVEN `_owned_upgrades == ["double_jump"]`, WHEN `_on_buy_pressed("double_jump")` appelé, THEN `try_spend` NON appelé (early return guard `has(id)`). *Mécanisme* : unit GUT — mock compteur, init owned, assert == 0.

**AC-SHP-15 [Integration] [BLOCKING]** : GIVEN save existante avec `["double_jump", "dash_horizontal"]`, WHEN shop.tscn instancié et `_ready()` exécuté, THEN deux BuyButtons disabled OWNED dès premier frame rendu. *Mécanisme* : integration scene — mock SaveLoad, assert états dans `_ready()` ou signal initialisé.

### Groupe D — Affordability dynamique (F-SHP-2)

**AC-SHP-16 [Logic] [BLOCKING]** : GIVEN solde 19 et `_owned_upgrades == []`, WHEN catalogue évalué, THEN `BuyButton_double_jump.disabled == true` (19<20) ET `BuyButton_dash_horizontal.disabled == true` (19<40). *Mécanisme* : unit GUT — mock get_total 19, appeler update affordability, assert deux disabled.

**AC-SHP-17 [Logic] [BLOCKING]** : GIVEN solde 20, WHEN double_jump acheté (try_spend(20)→true, Credit net=0), THEN solde effectif=0 et `BuyButton_dash_horizontal.disabled == true` (0<40). *Mécanisme* : unit GUT — séquence achat + signal credits_changed(0, -20, SPEND_SHOP), assert dash disabled.

**AC-SHP-18 [Logic] [BLOCKING]** : GIVEN solde 60 et `_owned_upgrades == []`, WHEN double_jump acheté (try_spend(20)→true, credits_changed(40, -20, SPEND_SHOP)), THEN `BuyButton_dash_horizontal.disabled == false` état NORMAL (40>=40). *Mécanisme* : unit GUT — mock séquence, assert dash non disabled.

**AC-SHP-19 [Integration] [BLOCKING]** : GIVEN solde 60, WHEN deux upgrades achetées séquentiellement, THEN solde final=0, `_owned_upgrades == ["double_jump", "dash_horizontal"]`, deux boutons disabled OWNED. *Mécanisme* : integration scene — exécution séquentielle deux cycles, assert état final.

### Groupe E — Persistance

**AC-SHP-20 [Logic] [BLOCKING]** : GIVEN try_spend retourne true, WHEN `save_string_array` appelé, THEN appel SYNCHRONE (pas await, pas call_deferred) — donnée persistée même frame que l'achat, AVANT `apply_upgrade`. *Mécanisme* : lint static — grep `await.*save_string_array` zéro match ; unit GUT mock save flag `_was_called_sync` posé dans corps mock (pas deferred).

**AC-SHP-21 [Integration] [BLOCKING]** : GIVEN upgrade achetée et shop fermé, WHEN shop.tscn rechargé (simulation re-enter), THEN upgrade apparaît OWNED dès boot nouvelle instance. *Mécanisme* : integration test — séquence : instance 1 achète → mock SaveLoad capture array → instance 2 créée avec mock retournant array capturé → assert owned.

**AC-SHP-22 [Logic] [BLOCKING]** : GIVEN `save_string_array` lance erreur (mock disk full), WHEN cycle tente persistance, THEN `push_error` appelé (vérifiable spy ou GUT `assert_error`) ET cycle continue jusqu'à `apply_upgrade`. *Mécanisme* : unit GUT — mock save lançant erreur, assert push_error appelé ET apply_upgrade appelé quand même.

**AC-SHP-23 [Logic] [BLOCKING]** : GIVEN `load_string_array` retourne valeur non-Array (null ou "corrupt"), WHEN `_ready()` traite résultat, THEN `_owned_upgrades = []` ET `push_error` ou `push_warning` appelé. *Mécanisme* : unit GUT — mock load null, assert liste vide ET error/warning déclenché.

**AC-SHP-24 [Logic] [BLOCKING]** : GIVEN `load_string_array` retourne `["triple_jump"]` (id inconnu), WHEN `_ready()` filtre catalogue, THEN id inconnu ignoré silencieusement, deux upgrades MVP affichées NORMAL. *Mécanisme* : unit GUT — mock load `["triple_jump"]`, assert zéro erreur, assert BuyButtons non disabled (id pas dans owned-known).

### Groupe F — GSM transition (R-SHP-10)

**AC-SHP-25 [Logic] [BLOCKING]** : GIVEN shop ACTIVE, WHEN bouton "Continuer" cliqué, THEN `GSM.request_scene_transition(scene_path)` appelé exactement 1 fois avec scene_path non vide. *Mécanisme* : unit GUT — mock GSM avec compteur et capture path, simuler click, assert count==1 et path non vide.

**AC-SHP-26 [Logic] [BLOCKING]** : GIVEN shop ACTIVE, WHEN `_unhandled_input` reçoit `InputEventKey` ESC ou action `ui_cancel`, THEN `request_scene_transition` appelé 1 fois — identique au click. *Mécanisme* : unit GUT — mock GSM, envoyer InputEventKey via `_unhandled_input`, assert mock 1 fois même path.

**AC-SHP-27 [Logic] [BLOCKING]** : GIVEN shop LOADING (avant `_ready()` complété), WHEN `_unhandled_input` reçoit ESC, THEN `request_scene_transition` PAS appelé. *Mécanisme* : unit GUT — forcer état LOADING, envoyer ESC, assert count == 0.

**AC-SHP-28 [Logic] [BLOCKING]** : GIVEN shop ACTIVE avec 0 achats, WHEN inspection bouton Continuer, THEN `ContinueButton.disabled == false`. *Mécanisme* : unit GUT — instancier shop avec 0 upgrades 0 achats, assert disabled false.

### Groupe G — Visibility / Layout

**AC-SHP-29 [Lint] [BLOCKING]** : GIVEN shop.tscn, WHEN inspecté, THEN `CanvasLayer.layer == 60`. *Mécanisme* : lint static — grep `layer = ` shop.tscn assert == 60 ; ou test GUT instancier scène et `$CanvasLayer.layer`.

**AC-SHP-30 [Lint] [BLOCKING]** : GIVEN shop.tscn, WHEN inspecté, THEN `ShopRoot.process_mode == PROCESS_MODE_ALWAYS`. *Mécanisme* : lint static — grep "process_mode" assert valeur 4 ; ou integration test.

**AC-SHP-31 [Logic] [BLOCKING]** : GIVEN Tween créé dans ShopControllerScript, WHEN inspecté, THEN `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` appelé. *Mécanisme* : lint static — grep `create_tween()`, vérifier `.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` dans 5 lignes suivantes.

**AC-SHP-32 [Visual] [ADVISORY]** : GIVEN shop.tscn ouvert éditeur, WHEN background ColorRect inspecté, THEN aucun AnimationPlayer connecté, ColorRect statique sans keyframe. *Mécanisme* : voir AC-SHP-39.

**AC-SHP-33 [Visual] [ADVISORY]** : GIVEN fenêtre redimensionnée 1280×720, 1920×1080, 2560×1440, WHEN shop affiché, THEN layout ne déborde pas, BuyButtons restent visibles et cliquables sans scroll. *Mécanisme* : manual — screenshots dans `production/qa/evidence/shop-layout-resize.png`, sign-off lead.

### Groupe H — Performance

**AC-SHP-34 [Performance] [BLOCKING]** : GIVEN `load("res://scenes/shop/shop.tscn")` + instanciation + `_ready()` complet, WHEN mesuré wall-clock, THEN durée < 100 ms sur machine référence (laptop entrée gamme). *Mécanisme* : integration test headless GUT — `Time.get_ticks_msec()` avant/après, assert delta < 100.

**AC-SHP-35 [Performance] [BLOCKING]** : GIVEN shop ACTIVE, WHEN achat déclenché (`_on_buy_pressed → try_spend → save → apply → render`), THEN durée totale wall-clock < 16.6 ms (1 frame 60 fps). *Mécanisme* : integration test — tick avant/après cycle complet, assert delta < 16.6 ms ; mocks synchrones imposés.

**AC-SHP-36 [Performance] [BLOCKING]** : GIVEN shop ACTIVE, WHEN handler `credits_changed` invoqué, THEN update complète (label + affordability recalcul + bouton states) < 5 ms wall-clock. *Mécanisme* : unit GUT — tick avant/après `_on_credits_changed`, assert delta < 5.

**AC-SHP-37 [Lint] [ADVISORY]** : GIVEN ShopControllerScript, WHEN inspecté hot-paths (handlers tween, hover, click), THEN aucune allocation heap (`push_back` dans `_process`, Dictionary literal créé à chaque tick). *Mécanisme* : lint static — grep `push_back\|Dictionary\.new\|String\(` dans corps `_process`/`_physics_process` (cohérent rule no-alloc-hot-paths).

**AC-SHP-38 [Performance] [ADVISORY]** : GIVEN shop ACTIVE sans tween (statique), WHEN frame time mesuré, THEN contribution ShopControllerScript < 0.5 ms. *Mécanisme* : manual — profiler Godot, capture 100 frames shop statique, moyenne < 0.5 ms.

### Groupe I — Anti-patterns testables (lint static)

**AC-SHP-39 [Lint] [ADVISORY]** : GIVEN shop.tscn, WHEN fichier inspecté, THEN zéro AnimationPlayer dans arbre scène. *Mécanisme* : lint static — `grep -c "AnimationPlayer" src/ui/shop/shop.tscn` assert == 0.

**AC-SHP-40 [Lint] [ADVISORY]** : GIVEN shop.tscn, WHEN inspecté, THEN zéro `TabContainer`. *Mécanisme* : lint static — grep assert == 0.

**AC-SHP-41 [Lint] [ADVISORY]** : GIVEN ShopControllerScript, WHEN inspecté, THEN un seul Label expose solde crédits — zéro second Label avec symbole monétaire alternatif ("premium", "gem", "coin"). *Mécanisme* : lint static — grep counter ; review manuelle .tscn.

**AC-SHP-42 [Lint] [ADVISORY]** : GIVEN shop.tscn, WHEN inspecté, THEN zéro `ScrollContainer` dans arbre background. *Mécanisme* : lint static — grep assert == 0.

**AC-SHP-43 [Lint] [ADVISORY]** : GIVEN shop.tscn et ShopControllerScript, WHEN inspectés, THEN zéro `AudioStreamPlayer` dans scène et zéro instanciation script. *Mécanisme* : lint static — grep `AudioStreamPlayer` deux fichiers assert == 0.

**AC-SHP-44 [Lint] [BLOCKING]** : GIVEN ShopControllerScript, WHEN inspecté pour accès singleton `Input`, THEN zéro `Input.*` hors `_unhandled_input` (Input GDD Core Rule 1, conforme rule `input-singleton-main-thread-only`). *Mécanisme* : lint static — extraire bodies fonctions hors `_unhandled_input`, grep `\bInput\.` assert zéro.

**AC-SHP-45 [Lint] [ADVISORY]** : GIVEN ShopControllerScript, WHEN inspecté, THEN zéro appel `UpgradeSystem.*` hors bloc `if try_spend(...):` (couplage minimal). *Mécanisme* : lint static — grep `UpgradeSystem\.apply_upgrade`, vérifier contexte branche true uniquement.

### Groupe J — Bidirectional contracts validation

**AC-SHP-46 [Integration] [BLOCKING]** : GIVEN Credit r1 verrouillé, WHEN `try_spend` appelé depuis ShopControllerScript, THEN contrat SYNC respecté (retour même frame, sans await, sans signal intermédiaire). *Mécanisme* : integration test + lint static — `grep -n "await.*try_spend"` zéro match ; assert signal `credits_changed` reçu même frame.

**AC-SHP-47 [Integration] [BLOCKING]** : GIVEN GSM r1 verrouillé, WHEN `request_scene_transition` appelé, THEN transition commence (état GSM change) même frame (ADR-0007 D-10 SYNC). *Mécanisme* : integration test — mock GSM, assert shop passe état CLOSING même frame.

**AC-SHP-48 [Logic] [PROVISIONAL — chain-blocked OQ-SHP-2]** : GIVEN UpgradeSystem (Not Started), WHEN contrat `apply_upgrade(id) -> void` SYNC idempotent confirmé par UpgradeSystem r1, THEN shop peut appeler sans await ni vérification retour. *Mécanisme* : CHAIN-BLOCKED jusqu'à UpgradeSystem Designed r1. Placeholder mock SYNC idempotent ; à re-tester avec impl réelle. Flag OQ-SHP-2.

**AC-SHP-49 [Logic] [PROVISIONAL — chain-blocked OQ-SHP-3]** : GIVEN SaveLoad (Not Started), WHEN contrats `save_string_array` et `load_string_array` confirmés par SaveLoad r1, THEN comportement erreur shop (AC-22, AC-23) validé contre API réelle. *Mécanisme* : CHAIN-BLOCKED — tests AC-22/23 utilisent mocks ; re-valider avec SaveLoad r1. Flag OQ-SHP-3.

### Groupe K — Manual Playtest (ADVISORY)

**AC-SHP-50 [Manual-Playtest] [ADVISORY]** : GIVEN 5 sessions playtest joueurs n'ayant pas vu le shop, WHEN observées, THEN au moins 1/5 sessions présente joueur restant 5+ secondes avant clic (sentiment "décision réelle" Pillar 2). *Mécanisme* : manual — observateur chronomètre, `production/qa/evidence/shop-playtest-decision-time.md`, sign-off game designer.

**AC-SHP-51 [Manual-Playtest] [ADVISORY]** : GIVEN 5 sessions playtest, WHEN joueurs doivent quitter shop, THEN zéro joueur demande "comment je sors ?" ou cherche visuellement > 3 secondes ESC/Continue. *Mécanisme* : manual — observation + verbatim, `production/qa/evidence/shop-playtest-esc-intuitif.md`.

**AC-SHP-52 [Manual-Playtest] [ADVISORY]** : GIVEN tween counter 300 ms, WHEN achat effectué, THEN retour qualitatif neutre/positif (zéro "trop lent" ni "trop rapide" mentionné par > 2/5 joueurs). *Mécanisme* : manual — questionnaire post-session, `production/qa/evidence/shop-playtest-tween-feel.md`.

---

**Total : 52 ACs**
- BLOCKING : 32 (groupes A-B-C-D-E-F-G-H-I partiel + J)
- ADVISORY : 20 (groupes G visuels, H perf, I anti-patterns, K playtest)
- PROVISIONAL chain-blocked : 2 (AC-SHP-48 OQ-SHP-2 UpgradeSystem r1, AC-SHP-49 OQ-SHP-3 SaveLoad r1)
- AUTO : 41 (Logic + Integration + Lint + Performance auto)
- MANUAL : 8 (Visual + Manual-Playtest)
- PROVISIONAL : 3

## Open Questions

| OQ | Question | Status | Recommandation | Owner | Urgence |
|----|----------|--------|----------------|-------|---------|
| **OQ-SHP-1** | Faut-il un état dédié `SHOPPING` dans GSM enum (ADR-0007 D-2) si Tier 2+ apporte un shop overlay sur gameplay 3D (au lieu de scène container) ? | OPEN — Tier 2+ uniquement | MVP : pas de nouvel état (R-SHP-5 décidé, scène container suffit). Tier 2+ : si shop overlay envisagé, amendement ADR-0007 D-2 + GSM r2 requis (ajouter SHOPPING state). | Game-designer + technical-director | Tier 2+ |
| **OQ-SHP-2** | Contrat exact `UpgradeSystem.apply_upgrade(id: StringName) -> void` : signature, timing, comportement si Player non instancié (shop.tscn n'a pas de Player) ? | OPEN — bloquant impl | À résoudre lors de `/design-system upgrade-system` (Systems Index #13). Recommandation guard provisoire : si UpgradeSystem.apply_upgrade appelé hors PLAYING 3D, flag upgrade comme "pending apply au prochain `level_active`". Idempotence confirmée par contrat. | Game-designer + Upgrade GDD author | Bloquant impl Sprint 1 |
| **OQ-SHP-3** | API exacte `SaveLoad.save_string_array(key, array)` + `load_string_array(key, default)` : type retour, gestion corruption (valeur non-Array), atomicité écriture, multi-profile prefix Tier 2+ ? | OPEN — bloquant impl | À résoudre lors de `/design-system save-load-system` (Systems Index #3). Comportement défensif Shop déjà spécifié (EC-SHP-6/7/8/9). | Game-designer + Save/Load GDD author | Bloquant impl Sprint 1 |
| **OQ-SHP-4** | Audio bus `SHOP_UI` Tier 2+ : créer dédié OU réutiliser `UI` existant (Audio r2.1 hierarchy figée) ? Quels SFX MVP→Tier 2+ (purchase/denied/continue) ? | OPEN — Tier 2+ | Recommandation : zéro SFX MVP (cohérent Audio r2.1 + Pillar 1 anti-bruit). Tier 2+ : amendement Audio r2.2 ajoutera bus `SHOP_UI` dédié OU réutilisation `UI` (décision audio-director Tier 2+). | Audio-director + Shop GDD r2 | Tier 2+ |
| **OQ-SHP-5** | Mécanisme de passage `next_etage_id` du Level (ou GSM) vers Shop pour Tier 2+ multi-étages ? Param scène, autoload state-bag, signal payload, instance `Shop.set_next_etage(id)` post-init ? | OPEN — Tier 2+ | MVP : non-applicable (1 étage). Tier 2+ recommandation : autoload `RunContext` simple (`current_etage_id: int`, `next_etage_id: int`), Shop lit au `_ready()`. Évite couplage scène-à-scène. | Game-designer + GSM r2 author | Tier 2+ |
| **OQ-SHP-6** | Faut-il introduire un système d'upgrades consommables (potions, boost runs) Tier 3 ? | DEFERRED — Tier 3 design space | Recommandation : NON. Anti-pillar grinding strict (game-concept anti-pillar inventory). Si Tier 3 introduit méta-progression cross-run, ré-évaluer. | Creative-director Tier 3 | Tier 3 (probablement jamais) |
| **OQ-SHP-7** | Faut-il un mode "preview" upgrade sur hover (animation Player démontrant l'effet en miniature) ? | DEFERRED — Tier 2+ | Recommandation : NON MVP (Pillar 1 anti-distraction). Tier 2+ envisageable comme video clip 2-3s sur hover prolongé > 1s. | UX-designer Tier 2+ | Tier 2+ |
| **OQ-SHP-8** | Sécurité save tampering Tier 3 : HMAC/signature sur `owned_upgrades` pour prévenir édition manuelle ? | DEFERRED — Tier 3 | Recommandation : NON MVP (solo offline, pas de leaderboard). Tier 3 si speedrun leaderboard introduit, signature requise (Save/Load extension). | Security-engineer Tier 3 | Tier 3 |
| **OQ-SHP-9** | Localization MVP : strings hardcoded FR ("POSSÉDÉ", "Continuer", "CRÉDITS :") — pattern `tr()` Godot ou skip i18n MVP ? | OPEN — extraction Tier 2+ | Recommandation : skip MVP (FR-only game-concept). Extraction `tr()` Tier 2+ via `/localize` skill quand Localization team établie. | Localization-lead Tier 2+ | Tier 2+ |
| **OQ-SHP-10** | Multi-profile saves (slot 1/2/3) : préfixage clé `"profile_{N}.owned_upgrades"` côté Shop ou côté SaveLoad ? | OPEN — Tier 2+ | Recommandation : côté SaveLoad (préfixage transparent via `set_active_profile(id)`). Shop reste agnostique. | Save/Load GDD author Tier 2+ | Tier 2+ |

---

### Résolutions induites par ce GDD

- **OQ-CRD-2 (Credit r1)** : "contrat `try_spend` Shop" — ✅ **RESOLVED** par ce GDD. Shop confirme l'API `CreditEconomy.try_spend(amount: int) -> bool` SYNC atomique à l'identique du contrat provisoire Credit r1. Recommandation Phase 5 : Credit GDD peut promote OQ-CRD-2 RESOLVED en amendement r2 ou laisser le statut tel quel (le contrat est verrouillé).

### Bidirectional updates requises (Phase 5 / Sprint A continuation)

- **Credit r1 §Open Questions** : marquer OQ-CRD-2 RESOLVED (Shop confirme contrat).
- **GSM r1 §Dependencies** : `ShopSystem (inferred, Not Started)` → `ShopSystem (Designed r1)` quand ce GDD landed.
- **HUD r1** : aucun amendement requis — zéro couplage direct (architecture séparée scène).
- **Audio r2.1** : amendement r2.2 Tier 2+ pour bus `SHOP_UI` (OQ-SHP-4).
- **Upgrade GDD #13** : devra citer Shop comme caller `apply_upgrade` (OQ-SHP-2).
- **Save/Load GDD #3** : devra citer Shop comme consumer `save/load_string_array` (OQ-SHP-3).
- **Level GDD r3** : aucun amendement MVP requis (Level émet `etage_completed` consommé par GSM, pas Shop direct). Tier 2+ : payload `next_etage_id` à passer (OQ-SHP-5).
