# Shop System

> **Status**: Designed r2 (revisions 2026-04-27 post design-review fresh — voir `reviews/shop-system-review-r1-2026-04-27.md`)
> **Author**: Martin + main session (Opus 4.7) + subagents (game-designer, economy-designer, systems-designer, qa-lead, ux-designer)
> **Last Updated**: 2026-04-27 (r2)
> **Implements Pillar**: 2 (LA PROGRESSION SE VOIT) primaire ; 1 (FLOW) garde-fou transition ; anti-Pillar 4 (le shop est l'unique lieu de dépense — protège la sémantique "secrets = mouvement, pas marchandage")
> **Quick reference** — Layer: `Feature/UI` · Priority: `MVP` · Key deps: `Credit Economy ✅ Designed r1 (locked try_spend, F-CRD-3 amendée r2 0-based, OQ-CRD-2 RESOLVED), Game State Manager ✅ APPROVED r1 (request_scene_transition), Save/Load System ✅ Designed r1 (save/load_string_array LOCKED, OQ-SHP-3 RESOLVED), Upgrade System ⚠️ Not Started (provisional apply_upgrade + _pending_upgrades pattern, OQ-SHP-2 chain-blocked Sprint 1), Menu System ⚠️ Not Started (sibling UI scene)`

## Overview

Shop System est la **scène transitoire d'achat** entre étages : un Control fullscreen `res://scenes/shop/shop.tscn` chargé par GameStateManager (`request_scene_transition` ADR-0007 D-5) au signal `etage_completed` du Level System. Le shop expose un catalogue MVP de **2 upgrades binaires permanentes** (`double_jump` à 20 cr index n=0, `dash_horizontal` à 40 cr index n=1 — coûts dérivés de la courbe linéaire F-CRD-3 amendée r2 `cost_n = 20 + 20×n` 0-based owned par Credit Economy). Chaque achat est une transaction atomique : `CreditEconomy.try_spend(amount: int) -> bool` (R-CRD-4 locked) — si succès, l'état owned est immédiatement persisté via `SaveLoad.save_string_array("owned_upgrades", _owned_upgrades)` (provisional Save/Load, atomicité requise — voir Dependencies) puis `UpgradeSystem.apply_upgrade(id: StringName)` (provisional Upgrade — pattern `_pending_upgrades` si Player non instancié, voir EC-SHP-17) active la capacité dans la couche gameplay. Le shop est **idempotent** (chaque upgrade = achat unique, double-click bloqué par guard `_owned_upgrades.has(id)`), **sans grinding au MVP** (pas de re-stock, pas de stack, pas de re-roll ; cf. note Tier 2+ courbe F-SHP-1 sur l'accumulation cross-session), et **sans état SHOPPING dédié dans GSM** (le shop est une scène container PLAYING-state agnostic — voir R-SHP-5). Sa surface API est minimale : un nœud-local `ShopControllerScript` dans la scène (pas d'autoload), un signal interne `_on_continue_pressed()` qui déclenche `request_scene_transition` vers MENU au MVP (Tier 2+ : `start_etage(next_etage_id)` chaîné via autoload `RunContext`, OQ-SHP-5 RESOLVED). Le shop ferme le segment économique du core loop : sans lui, les crédits accumulés par Credit Economy n'ont pas de sortie, Pillar 2 (LA PROGRESSION SE VOIT) reste promesse. Le scope MVP couvre 2 upgrades, **2 étages playable MVP** (1 shop par étage = 2 visites possibles, F-CRD-4 yield_max 85 cr cumul cohérent F-SHP-3), persistance binaire owned/not_owned via Save/Load, et zéro SFX (Audio bus shop différé Tier 2+, OQ-SHP-4 RESOLVED).

---

## Player Fantasy

> **Cadrage** : système **direct-actif** — le joueur engage volontairement avec le Shop (clic, lecture, décision) à un moment précis du loop (entre étages). C'est l'unique pause respirée du jeu. Sa fantasy n'est pas spectaculaire — elle est **délibérative**.

### Le moment Shop

Tu viens de finir l'étage. La caméra est encore essoufflée, l'écran fade au noir 200 ms, puis le shop apparaît. Le 3D world a disparu. Le silence est total — pas de musique d'ambiance qui te précipite, pas de timer qui te presse. Devant toi, **deux cartes**. À droite, ton compteur de crédits — le même chiffre que tu surveilles depuis le début, mais ici il a un poids différent : il est **convertible**. La carte du haut dit `Saut Double — 20 ₵`. Tu en as 33 (étage 1, trois secrets trouvés). Tu peux. La carte du bas dit `Dash Horizontal — 40 ₵`. Tu ne peux pas. Pas encore. À ta première visite, tu peux. Mais pas les deux — pas encore.

Et c'est exactement le point : **le shop est le seul moment du jeu où tu réfléchis pour avancer**. Partout ailleurs, tu réagis à 60 fps — un laser, un mur, un grunt. Ici, tu *décides*. Cette décision est légère (deux options MVP, pas un skill tree) et lourde à la fois (chaque upgrade change physiquement ce que tu peux faire dans le prochain étage). Il n'y a pas de modal "Are you sure?", pas de fanfare, pas de cinématique. Tu cliques, le compteur tombe de 33 à 13 en 300 ms, la carte vire au cyan désaturé qui dit `POSSÉDÉ`, et le bouton `CONTINUER` est toujours là, toujours prêt. La carte du dash reste ouverte — tu sais qu'au prochain étage, si tu trouves les bons secrets, elle deviendra à toi. Tu reprends ton souffle, tu cliques, et la tour t'attend de nouveau.

> **Honnêteté économique** (note design) : la tension décisionnelle "tu peux mais pas les deux" est la promesse de la **première visite** d'un joueur explorateur normal (yield étage 1 ≈ 21–38 cr selon profil, voir F-SHP-3). Pour le joueur expert qui finit les 2 étages MVP avec tous les secrets (yield_max 85 cr), la tension se résout en "tu peux les deux avec marge". Pour le joueur faible (yield ≤ 19 cr), aucun achat possible étage 1 — la fenêtre arrive étage 2. La fantasy est temporelle, pas invariante : le moment de tension existe à un instant précis dans la progression, pas à chaque visite.

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

Inspirations directes (révisées r2 design-review) :

- **Sobriété d'interface** : *Hotline Miami* écran de stats fin de niveau (texte monospace, fond noir, zéro FX décoratif — le score parle, l'écran se tait).
- **Absence de friction** : *Hades* inventory screens (lecture immédiate, transitions courtes, le joueur n'a pas l'impression de "rentrer dans un menu").
- **Livraison sans célébration** : *Dead Cells* unlocks passifs entre runs (l'upgrade s'applique sans cinématique, sans fanfare — le seul changement est que la barre de capacité s'agrandit).

Anti-référence : tous les shops F2P (loot box reveal, particules, son de jackpot), tous les skill trees graphiques connectés (Path of Exile, Ghostrunner upgrade tree) — le shop de Chrome://Ascent est leur opposé exact.

> **Note** : versions précédentes du GDD citaient *Hollow Knight* Iselda/Sly et *Ghostrunner* upgrade screen comme références. Ces analogies étaient imprécises (Iselda est un PNJ avec dialogues, Ghostrunner upgrade screen est un skill tree connecté). Remplacées r2 pour éviter d'orienter mal l'art direction.

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
6. **Feedback succès** — Tween pulse sur `UpgradeCard` (scale 1.0 → 1.03 → 1.0, 150 ms wall-clock, TRANS_SINE) + counter tween 300 ms (J.3) déclenché côté `credits_changed` handler. **Pas de flash cyan** sur counter (retiré r2 design-review — l'animation numérique 300 ms est suffisante comme livraison ; cohérent anti-fantasy "sobre" pas "silencieux"). Aucun son MVP.

**Ordre 5a → 5b → 5c impératif** : la persistance précède `apply_upgrade` afin que, même si `apply_upgrade` lance une exception non fatale, l'état owned soit enregistré (évite la double-facturation au rechargement). Si `save_string_array` échoue, voir EC-SHP-9 (pattern Option C buffer retry — pas de "Risque Tier 1 admis").

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

> ⚠️ **CONNECT_DEFERRED est OBLIGATOIRE et VERROUILLÉ** (r2 design-review) : ce flag empêche le handler `_on_credits_changed` de s'exécuter dans le call stack du handler `pressed` du BuyButton. Si la connexion passait à `CONNECT_SYNC`, un autre handler de `credits_changed` (par exemple un Tier 2+ qui déclencherait une transition GSM) pourrait s'exécuter *entre* `try_spend` et `apply_upgrade`, cassant l'atomicité du cycle d'achat (cf. EC-SHP-23). **Tout passage à CONNECT_SYNC sur ce signal côté Shop = audit chaîne d'appel obligatoire + amendement Shop r3.** AC-SHP-4 verrouille le flag.

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

**F-SHP-1 — Cost Lookup (délégation à F-CRD-3, convention unifiée r2 0-based)**

Le Shop ne calcule pas le coût d'une upgrade — il délègue à la courbe linéaire définie par F-CRD-3 dans Credit Economy. Aucune constante `BASE_UPGRADE_COST` ni `TIER_COST_STEP` n'est redéfinie ici.

> **Convention `n` r2 unifiée 0-based** (correction design-review) : F-CRD-3 a été amendée r2 (Credit GDD) pour passer de 1-based (rang) à 0-based (index) — alignement avec F-SHP-1. Les deux GDDs utilisent désormais `n ∈ [0, N_UPGRADES - 1]`. Avant amendement, Credit utilisait `cost_n = B + S × (n - 1)` ; après : `cost_n = B + S × n`. Arithmétiquement équivalent (rang 1 = index 0), évite le bug d'impl cross-GDD.

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

**F-SHP-3 — Total Spend Budget Validation (Pillar 2 sanity check, MVP 2 étages)**

Validation économique statique (design-time + test-time, non runtime). Vérifie que la somme des coûts de toutes les upgrades MVP est atteignable **sur le cumul des 2 étages MVP** sans grind cross-session. Garantit Pillar 2 : un joueur explorateur qui joue bien doit pouvoir acheter toutes les upgrades MVP en complétant les 2 étages playable MVP.

> **Scope MVP confirmé r2** : MVP = **2 étages playable** (cohérent F-CRD-4 yield range `[8, 100] cr cumul étage 1+2`). Une visite shop par étage (2 visites possibles total). L'étage 1 finance typiquement la 1ère upgrade ; l'étage 2 finance la 2e. Le yield 85 cr est le scenario optimal cumul, pas un seul étage.

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
| `N_UPGRADES_MVP` | N | `int` | 2 | Nombre d'upgrades MVP. Figé game-concept. |
| `total_cost_MVP` | C | `int` | 60 | Somme des coûts. Dérivé F-SHP-1 × N. |
| `session_yield_max_MVP` | Y | `int` | 85 | Rendement maximal **cumul 2 étages MVP** (F-CRD-4). Source de vérité Credit GDD. |
| `margin` | m | `int` | 25 | Crédits résiduels après achat de toutes upgrades MVP en scénario optimal cumul 2 étages. |

**Output Range :** `margin >= 0` est la condition de validité économique. `margin < 0` → violation Pillar 2 + anti-pillar grinding.

**Profils de joueur — affordability réelle MVP (analyse r2 economy-designer)** :

| Profil | Étage 1 yield approx | Cumul 2 étages | n=0 affordable étage 1 ? | n=1 affordable cumul ? |
|--------|---------------------|----------------|--------------------------|------------------------|
| Q25 (combat-only, 0 secrets) | ~8 cr | ~16 cr | NON (16 < 20) | NON (16 < 40) |
| Q50 (médian, ~50% secrets) | ~21 cr | ~42 cr | OUI (étage 1) | OUI (cumul) |
| Q75 (explorateur normal, 3 secrets mix) | ~33 cr | ~66 cr | OUI confortable | OUI confortable |
| Q95 (expert, tous secrets) | ~55 cr | ~85 cr | OUI + restes | OUI + marge 25 cr |

**Interprétation r2** :

1. **Q25 friction Pillar 2** : un joueur strictement combat-only (0 secret trouvé) ne peut acheter aucune upgrade MVP en 2 étages (16 cr < 20 cr). C'est une **conséquence designée** de l'asymétrie 5:1 secret/kill — le joueur est incité à explorer. Documenté comme tension intentionnelle, pas bug Pillar 2.
2. **Q50–Q75 cible Pillar 2** : le profil médian achète n=0 étage 1 ou cumul, n=1 cumul 2 étages — la promesse "1 session = 1-2 upgrades" tient.
3. **Q95 confort + Tier 2+ anticipation** : les 25 cr résiduels s'accumulent sur le compteur permanent (Credit R-CRD-12 persistance). Quand Tier 2+ ajoutera n=2 à 60 cr, le joueur Q95 sera déjà partiellement financé.
4. **Non-trivialité** : 25 cr ne suffisent pas pour une 3e upgrade fictive (n=2 = 60 cr > 25 cr) — pas de "tout acheter sans effort" même en session parfaite. Tension économique réelle préservée.

**Invariant de santé économique** : à chaque extension Tier 2+ qui ajoute une upgrade, vérifier que `session_yield_max(nouveau_tier) - total_cost(nouveau_N) >= 0`. Si négatif, retuner `BASE_UPGRADE_COST`/`TIER_COST_STEP` (Credit) ou augmenter rendement (nouveaux ennemis, secrets).

**Sanity checks de non-boucle économique :**

- Pas de gain → dépense → regain : `try_spend` est sink pur, sources non régénérables **dans une même run d'étage** (kills une seule fois, secrets une seule fois). 
- Pas d'inflation : courbe F-CRD-3 linéaire, croissance bornée à 20 cr par rang, pas de "wall final" exponentiel.

> **⚠️ Re-run d'étage = grinding mou (r2 design-review honnêteté)** : si le joueur quitte au menu et relance étage 1, les ennemis et secrets sont **reset au prochain `level_active`** (Enemy GDD `_credited_this_run` vidé). Donc en théorie, le joueur peut farmer crédits via re-runs. **Cette possibilité n'est pas verrouillée par lock système au MVP** (pas de "level seal"). C'est un compromis assumé : plutôt que d'introduire une mécanique de verrou anti-replay (qui casserait Pillar 4 — "rejouer pour explorer"), on accepte que le joueur motivé puisse ré-accumuler. La vraie protection anti-grinding au MVP est la quantité limitée d'upgrades (2) — pas un verrou de re-run. Tier 2+ : si playtest révèle un comportement de re-run mécanique cumulatif, considérer une OQ "level completion seal" ou "diminishing returns sur re-credit".

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

**Justification double_jump en n=0** : le double_jump à 20 cr est délibérément le moins cher car (a) il est la première upgrade accessible économiquement (Q50+ peut l'acheter étage 1) et (b) son impact gameplay est *binaire et lisible* — le joueur acquiert une nouvelle capacité de mouvement vertical, observable au premier saut où il chooses de double-tapper. Le dash_horizontal (40 cr) demande compréhension du level design pour révéler son potentiel — correctement placé en second, une fois le modèle économique compris.

> **Note dépendance level design (r2 design-review)** : l'attente "le joueur découvre l'upgrade par le premier déclenchement post-achat" suppose que le level design étage 2 (post-shop étage 1) contient un contexte où chaque upgrade est *utile* — pas nécessairement obligatoire, mais clairement applicable. Cette contrainte est **soft** côté Level GDD (pas un AC bloquant Level) mais devient un critère de playtest AC-SHP-50 (temps avant premier déclenchement post-achat < 60 sec sur 3/5 sessions playtest internes). Si playtest révèle que le joueur n'utilise jamais l'upgrade post-achat, F-SHP-4 ordering est à reconsidérer (priorité 4 nouvelle).

**Roadmap Tier 2+ (indicative — non figée) :**

| n | Upgrade (non finale) | Coût indicatif | Impact |
|---|---------------------|----------------|--------|
| 2 | `wall_run_long` | 60 cr | Extension durée wall-run — traversées de façades longues |
| 3 | `aerial_slow_mo` | 80 cr | Slow-mo en l'air — lecture tactique mid-air |
| 4–7 | TBD Tier 2+ | 100–160 cr | À définir VS/Alpha selon playtest |

> **⚠️ Note Tier 2+ anti-grinding (r2 design-review)** : avec 8 upgrades (n=0 à n=7) et Credit `total_credits` persistant cross-session (Credit R-CRD-12), le coût total Full Vision = 720 cr. Si yield_max/run reste à 85 cr (pas de nouveaux ennemis ni secrets Tier 2+), atteindre n=7 demande **8-9 runs**. Cette accumulation cross-session **n'est pas considérée comme grinding** au sens anti-pillar (game-concept) : l'anti-pillar interdit les **mécaniques de re-stock** (re-roll catalogue, upgrades consommables, multi-buy), pas la progression lente. Néanmoins, Tier 2+ doit valider, avant ajout de chaque upgrade au catalogue, que (a) le yield/run a augmenté en proportion (nouveaux secrets / nouveaux ennemis), OU (b) la fréquence des sessions assumée est compatible avec la durée de découverte attendue. Si ni (a) ni (b), retuner `BASE_UPGRADE_COST` / `TIER_COST_STEP` (Credit r2+) avant d'ajouter l'upgrade. **MVP r2 conserve l'anti-grinding strict** (2 upgrades, atteignables en 1-2 runs explorateur), Tier 2+ assume l'accumulation lente comme mécanique designée.

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

**EC-SHP-9 — SaveLoad.save_string_array échoue post-débit (Option C buffer retry, r2)** : SI `try_spend(cost)` retourne `true` (crédits débités irréversiblement), upgrade ajoutée à `_owned_upgrades` en RAM, ET `save_string_array` échoue (disque plein, permissions, file lock) ALORS Shop applique le pattern **Option C buffer retry non-bloquant** :

1. `push_error("ShopSystem: save_string_array failed for owned_upgrades — entering retry buffer")` (logguer mais pas bloquer).
2. Append l'array `_owned_upgrades` courant dans une queue interne `_pending_save_retries: Array[Array[StringName]]`.
3. Continuer le cycle d'achat normalement (`apply_upgrade` appelé, animations jouées) — le débit a eu lieu, l'upgrade est active en RAM.
4. À chaque `_process` idle frame, si `_pending_save_retries` non vide, retenter `save_string_array` avec le dernier état. Maximum **3 tentatives** sur 5 secondes wall-clock (intervalle 1s exponentiel : 0.5s, 1.5s, 3s).
5. Si une tentative réussit : `_pending_save_retries.clear()`, log `push_warning("ShopSystem: save retry succeeded after N attempts")`.
6. Si les 3 tentatives échouent : log `push_error("ShopSystem: save retry exhausted — owned_upgrades will be re-attempted at quit-to-menu")`. L'upgrade reste active en RAM. L'écriture définitive est déléguée au save quit-to-menu (Credit R-CRD-12) qui re-écrira `total_credits` ET déclenchera un dernier `save_string_array` pour `owned_upgrades` (Shop hook `_on_pre_quit` connecté à GSM `state_changed(MENU)`).
7. Si force-quit avant écriture quit-to-menu : upgrade perdue au redémarrage, mais débit crédit persisté indépendamment (Credit R-CRD-12 idempotent). Cas restant documenté en EC-SHP-24 (force-quit) — risque résiduel admis (~0.5% des cas selon ratio "save fail × force-quit imprédictible").

**Couverture Option C** : ~95% des failures disque transitoires absorbées par retry + fallback quit-to-menu. Le pire cas (retry exhausted + force-quit avant menu) reste documenté et acceptable. Aucune notification UX joueur au MVP (l'upgrade fonctionne en RAM, le silence est cohérent Pillar 1) — Tier 2+ : alerte UX discrète si retry exhausted ("Sauvegarde retardée").

**EC-SHP-10 — double-clic rapide avant disabled** : SI joueur double-clique sur un bouton affordable avant que Godot ait traité le premier clic et désactivé `BuyButton.disabled` ALORS deux events `pressed` passent dans la queue. Résolution : guard `_purchase_in_progress: bool` posé à `true` au premier clic, remis à `false` à la fin du tween post-achat. Le second event teste ce flag et est ignoré. Guard prioritaire sur `BuyButton.disabled` car Godot peut livrer les deux events avant le prochain `_process`.

**EC-SHP-11 — click sur upgrade déjà OWNED** : SI `BuyButton.disabled = true` est posé mais qu'un clic passe malgré tout (spam input, accessibilité externe, test manuel) ALORS le guard local `_owned_upgrades.has(id)` intercepte avant tout appel à `try_spend`. Aucun crédit débité, aucun signal, log silencieux (comportement attendu). `apply_upgrade(id)` n'est pas rappelé (idempotence garantie côté guard local).

**EC-SHP-12 — ESC pendant animation DISABLED shake** : SI joueur presse ESC pendant l'animation shake (durée ≤ 400 ms cooldown) ALORS shop déclenche fermeture via `request_scene_transition` normalement. Shake abandonné immédiatement (`tween.kill()`). Retour propre. ESC n'attend jamais la fin d'une animation.

**EC-SHP-13 — ESC ou Continue pendant counter tween post-achat** : SI joueur presse ESC ou Continue pendant le tween 300 ms post-achat (compteur animé, carte OWNED) ALORS `request_scene_transition` émis immédiatement. Tween interrompu (kill). État `_owned_upgrades` déjà persisté (R-SHP-8 écrit synchrone au clic, AVANT le tween). `apply_upgrade` déjà appelé. Transition safe à n'importe quel point du tween — aucun état critique n'est porté par l'animation.

**EC-SHP-14 — solde 0 après achat, autres cartes DISABLED dans le même frame** : SI joueur avec 20 cr achète `double_jump` (cost=20, n=0) ALORS `total_credits` passe à 0, `credits_changed(0, -20, SPEND_SHOP)` émis SYNC. Dans le handler `_on_credits_changed`, Shop recalcule `affordable_n` (F-SHP-2) pour toutes les cartes restantes (`dash_horizontal`, cost=40). `0 >= 40` faux → `dash_horizontal.BuyButton.disabled = true` dans le même `_physics_process`. Aucune fenêtre où dash reste cliquable.

**EC-SHP-15 — joueur avec 19 cr (sous le seuil minimum)** : SI `total_credits < BASE_UPGRADE_COST` (19 < 20) à l'ouverture du shop ALORS `affordable_n(19)` retourne `false` pour toutes les upgrades. Toutes les BuyButtons disabled. Seul Continue actif et focalisé. État visuel des cartes DISABLED. Joueur peut sortir via Continue ou ESC. Aucun message d'erreur — état lisible par prix vs solde.

**EC-SHP-16 — UpgradeSystem.apply_upgrade exception post try_spend** : SI `try_spend(cost)` retourne `true` ET `apply_upgrade(id)` lève une exception ou panic ALORS crédits perdus sans upgrade appliquée. Résolution MVP : Shop enveloppe l'appel dans bloc défensif. Si échec : `_owned_upgrades` ne marque pas l'ID owned, `push_error` émis, upgrade reste achetable visuellement. Incohérence crédit/upgrade admise comme risque Tier 1 (contrat UpgradeSystem PROVISOIRE — voir OQ-SHP-2). Tier 2+ : retry ou compensation crédit.

**EC-SHP-17 — UpgradeSystem.apply_upgrade sans Player instancié** : SI Shop appelle `apply_upgrade(id)` alors qu'aucune scène 3D Level n'est active (shop chargé directement depuis MENU) ALORS UpgradeSystem doit différer l'application au prochain `level_active` (contrat PROVISOIRE OQ-SHP-2). Shop ne porte pas de logique de retry — délègue intégralement à UpgradeSystem. Si UpgradeSystem applique au spawn suivant du Player, comportement correct. Si UpgradeSystem plante, EC-SHP-16 s'applique.

**EC-SHP-18 — request_scene_transition avec transition déjà en cours** : SI `GSM.request_scene_transition` est appelé alors qu'une transition GSM est déjà en cours (double-clic Continue, double-press ESC) ALORS GSM rejette le second appel silencieusement (ADR-0007 D-10 — état GSM déjà en transition). Shop ajoute un flag `_closing: bool` posé au premier appel et testé avant tout second appel à `request_scene_transition` (double-safeguard).

**EC-SHP-19 — get_tree().paused = true résiduel** : SI `paused = true` appliqué par Menu System (pause overlay) et non remis à `false` avant chargement shop.tscn ALORS les nœuds Shop dont `process_mode != ALWAYS` seraient gelés. Résolution **double-couche r2** :

1. **Niveau Shop (defensive)** : tous nœuds interactifs Shop utilisent `PROCESS_MODE_ALWAYS` (R-SHP-16). Le shop est une scène de transition fullscreen — il ne doit pas hériter du pause state du level précédent.
2. **Niveau GSM (contrat)** : GSM doit garantir `paused = false` avant `change_scene_to_file`. **Ce contrat n'est pas encore confirmé dans ADR-0007** — voir nouvelle OQ-SHP-11 (audit GSM ADR-0007 D-? `paused` lifecycle pendant transitions). En attendant résolution OQ-SHP-11, la défense Shop niveau 1 (`PROCESS_MODE_ALWAYS` partout) est suffisante pour MVP.

**EC-SHP-20 — Player.died émis depuis scène fantôme pendant shop** : SI un grunt dont le level n'a pas encore été déchargé émet `enemy_killed` ou si `Player.died` est émis pendant que le Shop est actif (scène Level non unloadée) ALORS Credit crédite normalement (indépendant de Shop), mais Shop n'écoute pas `died` directement. GSM reste PLAYING pendant shop. Si joueur "meurt" pendant shop par bug lifecycle, GSM reçoit signal et déclenche RESPAWNING → shop fermé prématurément. Cas pathologique indiquant un bug lifecycle Level — Level doit être entièrement déchargé avant shop.

**EC-SHP-21 — change_scene_to_file échoue (fichier manquant)** : SI `request_scene_transition("res://scenes/shop/shop.tscn")` provoque un `change_scene_to_file` qui échoue (fichier absent, parse error) ALORS Godot émet erreur console et le changement n'a pas lieu — joueur reste dans le level. Shop n'a pas de mécanisme retry. Résolution : test AC vérifie que `shop.tscn` est présent et parseable en CI. En runtime, joueur continue level sans shop — comportement dégradé acceptable vs crash.

**EC-SHP-22 — autoload order : SaveLoad ou CreditEconomy non prêt au _ready()** : SI `Shop._ready()` s'exécute avant que SaveLoad ou CreditEconomy soit initialisé (ordre autoload incorrect) ALORS appels `load_string_array` ou `get_total()` échoueraient. Résolution : Godot 4.6 initialise autoloads dans l'ordre déclaré dans `project.godot`. Contrat de dépendance impose SaveLoad et CreditEconomy listés avant ShopSystem. Comme `shop.tscn` est scène transitoire (non-autoload), son `_ready()` s'exécute après tous les autoloads — ce cas n'existe que si Shop instancié prématurément hors flow GSM (bug d'intégration).

**EC-SHP-23 — shop unloaded mid-purchase (fenêtre 1 frame)** : SI une unload de la scène shop survient dans la fenêtre entre `try_spend(cost) == true` et `apply_upgrade(id)` (un seul `await` ou yield entre les deux) ALORS upgrade non appliquée mais crédits débités. Résolution : aucun `await` ni `yield` autorisé entre `try_spend` et `apply_upgrade` — les deux appels dans le même call stack synchrone du handler `pressed`. Séquence atomique du point de vue GDScript (pas de suspension coroutine). Écriture Save immédiatement après dans le même handler (R-SHP-8).

> **Renforcement r2** : l'atomicité repose sur le fait qu'**aucun handler tiers** ne peut s'exécuter dans le call stack du `pressed` handler. Cette garantie est tenue uniquement si `credits_changed` est connecté en `CONNECT_DEFERRED` (R-SHP-9 verrouillage). Si un futur contributeur passait à `CONNECT_SYNC`, le handler `_on_credits_changed` s'exécuterait *entre* `try_spend` (qui émet le signal) et `apply_upgrade`, ouvrant une fenêtre de réentrance potentiellement catastrophique (transition GSM, reload Save, etc.). **AC-SHP-4 verrouille CONNECT_DEFERRED comme invariant testable.** Tout passage à SYNC = audit chaîne d'appel obligatoire + amendement Shop r3.

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

---

### Edge Cases ajoutés r2 (design-review systems-designer)

**EC-SHP-36 — double `etage_completed` (bug Level)** : SI Level System émet `etage_completed` deux fois consécutives par bug (ex. handler dupliqué) ALORS GSM reçoit le second signal alors que la transition shop est déjà en cours (état LOADING ou ACTIVE). Résolution attendue côté GSM : `request_scene_transition` rejette silencieusement si une transition est déjà en cours (idempotence GSM ADR-0007 D-10, à confirmer audit). Côté Shop : aucune action requise — Shop n'écoute pas `etage_completed` directement (R-SHP-15). Si GSM ne rejette pas le second appel, cas pathologique = double instanciation shop.tscn → bug architecture GSM, hors scope Shop. Flag pour bidirectional check GSM r2.

**EC-SHP-37 — `Player.died` pendant LOADING shop (race lifecycle Level)** : SI Level System a émis `etage_completed` et GSM a lancé `change_scene_to_file("shop.tscn")` MAIS le Level n'est pas entièrement déchargé encore et un ennemi fantôme tue le joueur ALORS `Player.died` est émis, GSM peut tenter une transition RESPAWNING en parallèle de la transition shop. Résolution attendue : GSM doit **prioriser la transition en cours** (transition shop reste prioritaire sur respawn pendant LOADING). Si RESPAWNING prime, le joueur arrive au respawn point sans avoir vu le shop — état cohérent mais surprenant. **Contrat à clarifier dans GSM r2** (audit ADR-0007 lifecycle priority). Côté Shop : aucune action MVP — Shop ne gère pas le respawn flow.

**EC-SHP-38 — BuyButton + ContinueButton dans le même frame (ordre déterministe)** : SI joueur clique BuyButton (upgrade affordable) ET ContinueButton dans la même frame (input spam, accessibilité externe, double-tap) ALORS Godot délivre les deux `pressed` dans l'ordre de la scene tree. Comme `BuyButton` est déclaré avant `ContinueButton` dans `shop.tscn` (R-SHP-2 hiérarchie), son handler s'exécute en premier — achat complété atomiquement. Puis ContinueButton handler s'exécute, déclenche `request_scene_transition`. Le flag `_closing: bool` (EC-SHP-18) absorbe tout second appel `request_scene_transition` éventuel. Résultat : achat valide + transition propre. Documenter explicitement que **l'ordre de déclaration dans shop.tscn est l'ordre de traitement des `pressed`** (non-obvious pour futurs contributeurs Godot).

**EC-SHP-39 — String vs StringName dans `_owned_upgrades` (cast safety)** : SI `SaveLoad.load_string_array` retourne un Array contenant des Strings au lieu de StringNames (sérialisation JSON typique : pas de StringName natif en JSON) ALORS le cast `String("double_jump") → StringName(&"double_jump")` est **équivalent** pour `has()` en Godot 4.6 — les StringNames sont internés, l'égalité fonctionne. EC-SHP-7 doit donc **convertir** les Strings valides plutôt que les rejeter : `for elem in raw_array: if elem is String: _owned_upgrades.append(StringName(elem)) ; elif elem is StringName: _owned_upgrades.append(elem) ; else: push_warning("invalid type")`. Comportement défensif et forward-compatible avec sérialisations JSON futures.

**EC-SHP-40 — réentrance CONNECT_DEFERRED (modèle threading GDScript)** : SI deux handlers DEFERRED de `credits_changed` sont connectés (ex. Shop UI + futur Tier 2+ telemetry) ET émis dans la même frame ALORS GDScript exécute les handlers DEFERRED **séquentiellement à la prochaine idle frame**, pas en parallèle (modèle single-thread garanti). Aucune réentrance possible : le second handler ne peut pas modifier `_owned_upgrades` pendant que le premier itère `_CATALOG`. **Non-risque prouvé par modèle threading GDScript single-thread + DEFERRED séquentiel.** Documenté ici pour lever toute ambiguïté future.

**EC-SHP-41 — ESC réflexe sans achat (joueur 19 cr ou hover annulé)** : SI joueur ouvre shop avec solde insuffisant pour toute upgrade (ex. 19 cr, EC-SHP-15) OU joueur a hover-cliqué une carte DISABLED puis presse ESC par réflexe d'annulation ALORS R-SHP-11 spec ESC = Continuer direct (sortie immédiate, pas de re-entry MVP). **Comportement assumé — pas de garde-fou MVP.** Justification (r2 design-review) : Pillar 1 anti-friction prime sur protection contre sortie accidentelle. Le joueur sans crédit ne peut rien acheter de toute façon — la sortie immédiate est rationnelle. Le joueur qui veut "annuler le hover" voit que la carte cliquée n'a rien fait (DISABLED no-op) et peut continuer à hover. Si playtest AC-SHP-51 révèle ≥ 1/5 sortie accidentelle non désirée, considérer pattern alternatif (1er ESC focus Continue + pulse, 2nd ESC trigger) en r3. **Risque MVP assumé.**

## Dependencies

### Hard dependencies (Shop ne peut pas fonctionner sans)

| Système | Status | Direction | Interface | Risque si absent |
|---------|--------|-----------|-----------|------------------|
| **Credit Economy** | ✅ Designed r1 (F-CRD-3 amendée r2 0-based, OQ-CRD-2 RESOLVED) | Bidir (Shop appelle + écoute) | `try_spend(amount: int) -> bool` SYNC atomique (R-CRD-4) ; signal `credits_changed(total, delta, source: SourceKind)` SYNC ; getter `get_total() -> int` ; constantes `BASE_UPGRADE_COST=20`, `TIER_COST_STEP=20` (F-CRD-3 r2 0-based). | Shop non fonctionnel — pas de débit possible, catalogue n'a aucun coût utilisable. |
| **Game State Manager** | ✅ APPROVED r1 | Out (Shop appelle) + indirect In (instanciation par GSM) | `request_scene_transition(scene_path: String)` (ADR-0007 D-10, l'un des 5 verbes publics figés) ; instanciation Shop déclenchée par `etage_completed` → GSM → `change_scene_to_file`. **Audit pending OQ-SHP-11** : `paused = false` garanti avant change_scene_to_file. | Shop ne peut être lancé ni fermé proprement — pas de transition de scène orchestrée. |
| **Save/Load System** | ✅ Designed r1 (OQ-SHP-3 RESOLVED 2026-04-27) | Bidir (Shop lit + écrit) | `save_string_array(key: StringName, value: Array[StringName]) -> void` ; `load_string_array(key: StringName, default: Array[StringName]) -> Array[StringName]`. Clé `"owned_upgrades"`. **Atomicité** : Save/Load r1 ConfigFile write-through synchrone ; atomic write temp+rename différé Tier 2+ (OQ-SAV-4). Shop EC-SHP-9 Option C buffer retry couvre la majorité des failures transitoires. | LOCKED — contrat verrouillé par Save/Load r1, atomicité MVP best-effort. |

### Soft dependencies (Shop est réduit / dégradé sans)

| Système | Status | Direction | Interface | Comportement dégradé |
|---------|--------|-----------|-----------|---------------------|
| **Upgrade System** | ⚠️ Not Started (PROVISIONAL — pattern `_pending_upgrades` requis) | Out (Shop appelle) | `apply_upgrade(id: StringName) -> void` SYNC idempotent. **Contrainte normative r2** : si `apply_upgrade` est appelé alors qu'aucun Player n'est instancié (shop chargé directement depuis MENU sans Level actif), UpgradeSystem doit (a) maintenir une queue `_pending_upgrades: Array[StringName]` et (b) flush la queue automatiquement au prochain signal de cycle de vie Player approprié (à définir lors de `/design-system upgrade-system` Sprint A continuation). | Achat marqué owned + persisté, mais capacité gameplay non activée. EC-SHP-16 + EC-SHP-17 décrivent le comportement défensif Shop côté caller. Voir OQ-SHP-2. |
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

- Credit Economy r1 (F-CRD-3 amendée r2 0-based) §Interactions table cite Shop comme aval consommateur de `try_spend` ✅
- Credit Economy r1 §Open Questions OQ-CRD-2 : "contrat try_spend Shop" — ✅ **RESOLVED 2026-04-27** par ce GDD r2 + design-review : Credit GDD a marqué OQ-CRD-2 RESOLVED, le contrat `try_spend(amount: int) -> bool` SYNC atomique est verrouillé à l'identique
- GSM r1 §Dependencies cite Shop dans "ShopSystem (inferred, Not Started) → Hard (Tier 2+) — Shop scene chargée via `request_scene_transition`" ✅. **Bidirectional update r2** : GSM r1 doit promote `Not Started` → `Designed r2` lors du commit landed.
- HUD r1 §Interactions soft Tier 2+ : pas de couplage direct mais comportement HUD R-6 SPEND_SHOP hard-set est cohérent avec philosophie Shop (HUD silencieux pendant transactions shop)
- Save/Load (Not Started) : Shop fournit contrats normatifs `save_string_array` (atomicité requise) + `load_string_array` à confirmer lors design Save/Load #3. **Bidirectional pending** : Save/Load GDD futur doit citer Shop comme consumer + valider atomicité contract.
- Upgrade System (Not Started) : Shop fournit contrat normatif `apply_upgrade(id) -> void` SYNC idempotent + pattern `_pending_upgrades` queue à confirmer lors design Upgrade #13. **Bidirectional pending** : Upgrade GDD futur doit citer Shop comme caller + implémenter la queue pending.
- Menu System (Not Started) : sibling — aucun contrat à confirmer côté Shop, GSM orchestre
- Audio r2.1 (APPROVED) : aucun amendement requis MVP (zéro SFX shop). **Tier 2+ amendement r2.2** pour bus `SHOP_UI` ou réutilisation `UI` (OQ-SHP-4 `RESOLVED MVP zéro SFX`, mais dependency Tier 2+ resté ouvert).

### Provisional contracts résumé

| Contrat | Owner provider | Owner consumer | Status |
|---------|----------------|----------------|--------|
| `UpgradeSystem.apply_upgrade(id: StringName) -> void` SYNC idempotent + queue `_pending_upgrades` | Upgrade System (Not Started) | Shop | PROVISOIRE — OQ-SHP-2 (chain-blocked Sprint 1, exigence Sprint 2 designed) |
| `SaveLoad.save_string_array(key, value) -> void` + `load_string_array(key, default)` | Save/Load ✅ Designed r1 | Shop | LOCKED — OQ-SHP-3 RESOLVED par Save/Load r1, atomicité MVP best-effort + EC-SHP-9 Option C buffer retry |
| `AudioSystem.play_sfx(id, bus="SHOP_UI" \| "UI")` Tier 2+ | Audio (APPROVED r2.1) | Shop | PROVISOIRE Tier 2+ — OQ-SHP-4 (RESOLVED MVP zéro SFX, dependency Tier 2+ resté open) |
| Shop `etage_completed → GSM → request_scene_transition(shop.tscn)` | Level r3 + GSM r1 | Shop (consumer indirect) | LOCKED — pas de contrat Shop direct |
| `RunContext` autoload (current_etage_id, next_etage_id) Tier 2+ | RunContext (Not Started Tier 2+) | Shop | PROVISOIRE Tier 2+ — OQ-SHP-5 (RESOLVED design pattern) |

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

**AC-SHP-12 [Integration] [BLOCKING]** (révisé r2) : GIVEN shop ACTIVE et émission `credits_changed(15, -5, SPEND_SHOP)`, WHEN handler invoqué (idle frame suivante via CONNECT_DEFERRED — voir R-SHP-9), THEN `CreditValueLabel.text == "15"` ET `BuyButton_double_jump.disabled == true` (15<20) ET `BuyButton_dash_horizontal.disabled == true` (15<40). *Mécanisme* : integration scene GUT — émettre `credits_changed` manuellement, `await get_tree().process_frame` (laisse passer l'idle frame DEFERRED), assert labels et boutons. **Note r2** : la version r1 disait "même frame" — incompatible avec CONNECT_DEFERRED qui reporte à l'idle frame suivante. Corrigé.

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

**AC-SHP-31 [Logic] [BLOCKING]** (révisé r2) : GIVEN Tween créé dans ShopControllerScript, WHEN inspecté, THEN `set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` appelé sur chaque tween créé. *Mécanisme* : (a) **Unit GUT** (préféré) — spy sur `create_tween()` retournant un mock Tween, assert `set_pause_mode` appelé avec `Tween.TWEEN_PAUSE_PROCESS` avant toute `tween_property` ou `tween_callback` sur ce tween. (b) **Lint static** (fallback robuste) — count `grep -c "create_tween()"` sur ShopControllerScript ; count `grep -c "set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)"` ; assert counts égaux. **Note r2** : la version r1 utilisait "5 lignes suivantes" — fragile si variable intermédiaire ou chaining sur 6+ lignes. Corrigé.

**AC-SHP-32 [Visual] [ADVISORY]** : GIVEN shop.tscn ouvert éditeur, WHEN background ColorRect inspecté, THEN aucun AnimationPlayer connecté, ColorRect statique sans keyframe. *Mécanisme* : voir AC-SHP-39.

**AC-SHP-33 [Visual] [ADVISORY]** : GIVEN fenêtre redimensionnée 1280×720, 1920×1080, 2560×1440, WHEN shop affiché, THEN layout ne déborde pas, BuyButtons restent visibles et cliquables sans scroll. *Mécanisme* : manual — screenshots dans `production/qa/evidence/shop-layout-resize.png`, sign-off lead.

### Groupe H — Performance

**AC-SHP-34 [Performance] [BLOCKING]** (révisé r2) : GIVEN `load("res://scenes/shop/shop.tscn")` + instanciation + `_ready()` complet, WHEN mesuré wall-clock en CI headless Ubuntu 22.04 4-core (runner GitHub Actions standard), THEN durée < 200 ms (tolérance CI absorbant jitter runner) ; baseline locale dev machine target < 100 ms. *Mécanisme* : integration test headless GUT — `Time.get_ticks_msec()` avant/après, assert delta < 200 ms (CI gate) ; baseline développeur enregistrée dans `tests/performance/baselines/shop_load_baseline.json` avec target < 100 ms et tolerance ±50% pour absorber variance hardware. **Note r2** : "machine référence (laptop entrée gamme)" était non reproductible cross-runner. Corrigé en CI runner spécifique + baseline file.

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

**AC-SHP-44 [Lint] [BLOCKING]** (révisé r2) : GIVEN ShopControllerScript, WHEN inspecté pour accès singleton `Input`, THEN zéro `Input.*` hors `_unhandled_input` (Input GDD Core Rule 1, conforme rule `input-singleton-main-thread-only`). *Mécanisme* : lint static — extraire bodies fonctions hors `_unhandled_input`, `grep -nE '\bInput\.'` filtré `grep -v '^\s*#'` (exclure commentaires GDScript) et `grep -v '^\s*"'` (exclure strings littérales avec "Input."), assert zéro match. Conforme enforcement rule `.claude/rules/input-singleton-main-thread-only.md`.

**AC-SHP-45 [Lint] [ADVISORY]** : GIVEN ShopControllerScript, WHEN inspecté, THEN zéro appel `UpgradeSystem.*` hors bloc `if try_spend(...):` (couplage minimal). *Mécanisme* : lint static — grep `UpgradeSystem\.apply_upgrade`, vérifier contexte branche true uniquement.

### Groupe J — Bidirectional contracts validation

**AC-SHP-46 [Integration] [BLOCKING]** (révisé r2) : GIVEN Credit r1 verrouillé, WHEN `try_spend` appelé depuis ShopControllerScript, THEN contrat SYNC respecté du côté Credit (retour `bool` même frame, sans await, sans signal intermédiaire dans le call stack `try_spend`) ET le signal `credits_changed` est émis SYNC par CreditEconomy ; côté Shop, le handler `_on_credits_changed` est invoqué à l'idle frame suivante via CONNECT_DEFERRED (R-SHP-9 verrou). *Mécanisme* : integration test + lint static — `grep -n "await.*try_spend"` zéro match ; assert `try_spend` retourne `bool` immédiatement ; `await get_tree().process_frame` puis assert handler invoqué exactement 1 fois. **Note r2** : la version r1 disait "credits_changed reçu même frame" — incompatible avec CONNECT_DEFERRED côté Shop. Corrigé pour distinguer émission SYNC (Credit) vs réception DEFERRED (Shop).

**AC-SHP-47 [Integration] [BLOCKING]** : GIVEN GSM r1 verrouillé, WHEN `request_scene_transition` appelé, THEN transition commence (état GSM change) même frame (ADR-0007 D-10 SYNC). *Mécanisme* : integration test — mock GSM, assert shop passe état CLOSING même frame.

**AC-SHP-48 [Logic] [PROVISIONAL — chain-blocked OQ-SHP-2]** (workflow r2) : GIVEN UpgradeSystem (Not Started), WHEN contrat `apply_upgrade(id) -> void` SYNC idempotent + queue `_pending_upgrades` confirmé par UpgradeSystem r1, THEN shop peut appeler sans await ni vérification retour. *Mécanisme* : CHAIN-BLOCKED jusqu'à UpgradeSystem Designed r1. **Workflow Sprint 1** : Shop implémenté avec **mock SYNC idempotent** UpgradeSystem (test double dans `tests/unit/shop/mocks/mock_upgrade_system.gd`). AC-SHP-48 marqué `PENDING-ACTIVATION` dans rapport sprint. À l'activation (UpgradeSystem r1 mergé), re-run integration tests Shop contre impl réelle. Story Shop marquée `Done-Provisional` jusqu'alors. Flag OQ-SHP-2. **Sprint 2 exigence** : UpgradeSystem GDD Designed avant Sprint 2 (pas après).

**AC-SHP-49 [Logic] [BLOCKING]** (révisé r2 — OQ-SHP-3 RESOLVED) : GIVEN SaveLoad ✅ Designed r1, WHEN contrats `save_string_array` + `load_string_array` confirmés par SaveLoad r1, THEN comportement erreur shop (AC-22, AC-23, EC-SHP-9 buffer retry Option C) validé contre API réelle. *Mécanisme* : integration test GUT — instancier autoload SaveLoad réel (pas mock) en headless, vérifier roundtrip + behavior corruption (EC-SHP-6/7/8) + behavior write fail (mock disk full sur ConfigFile en pré-injectant exception). **Note r2** : ce AC était PROVISIONAL chain-blocked en r1 ; promu BLOCKING suite à Save/Load r1 résolution.

### Groupe K — Manual Playtest (ADVISORY)

**AC-SHP-50 [Manual-Playtest] [ADVISORY]** (révisé r2) : GIVEN **2 sessions playtest internes MVP** (game-designer + 1 testeur interne) joueurs n'ayant pas vu le shop, WHEN observées, THEN au moins 1/2 sessions présente joueur restant 5+ secondes avant clic (sentiment "décision réelle" Pillar 2) ET temps avant premier déclenchement de l'upgrade post-achat < 60 sec sur 2/2 sessions (vérif F-SHP-4 ordering). *Mécanisme* : manual — observateur chronomètre, `production/qa/evidence/shop-playtest-decision-time.md`, sign-off game designer. **Note r2** : seuil 5 sessions externes recommandé pre-Alpha — abaissé à 2 internes pour MVP advisory.

**AC-SHP-51 [Manual-Playtest] [ADVISORY]** (révisé r2) : GIVEN 2 sessions playtest internes MVP, WHEN joueurs doivent quitter shop, THEN zéro joueur demande "comment je sors ?" ou cherche visuellement > 3 secondes ESC/Continue ET zéro joueur ressort accidentellement sans avoir consulté les cartes (vérif EC-SHP-41 ESC réflexe). *Mécanisme* : manual — observation + verbatim, `production/qa/evidence/shop-playtest-esc-intuitif.md`. **Note r2** : si ≥ 1/2 sortie accidentelle, considérer pattern alt ESC (focus Continue + 2nd ESC) en r3.

**AC-SHP-52 [Manual-Playtest] [ADVISORY]** (révisé r2) : GIVEN tween counter 300 ms, WHEN achat effectué, THEN retour qualitatif neutre/positif (zéro "trop lent" ni "trop rapide" mentionné par > 1/2 joueurs en MVP internes). *Mécanisme* : manual — questionnaire post-session, `production/qa/evidence/shop-playtest-tween-feel.md`.

### Groupe L — ACs ajoutés r2 (design-review qa-lead)

**AC-SHP-53 [Logic] [ADVISORY]** : GIVEN shop.tscn instancié et `_ready()` complété, WHEN aucune action utilisateur effectuée, THEN le focus UI initial est positionné sur ContinueButton (cohérent avec accessibilité clavier J.8 — l'élément le plus universellement accessible est focalisé par défaut). *Mécanisme* : unit GUT — assert `get_viewport().gui_get_focus_owner() == ContinueButton` après `_ready()` + `await get_tree().process_frame`. **Justification** : l'AC manquait dans r1 — la spec J.8 mentionne `Tab` navigue rows + Continue mais ne précise pas l'élément initialement focalisé.

**AC-SHP-54 [Integration] [ADVISORY]** : GIVEN shop.tscn instancié une première fois et achat effectué, scene libérée (free), WHEN shop.tscn instancié une deuxième fois dans la même session de jeu (Tier 2+ multi-étages, ou test re-entry), THEN `_owned_upgrades` de la nouvelle instance contient uniquement ce que `SaveLoad.load_string_array("owned_upgrades", [])` retourne — aucune donnée leak de l'instance précédente. *Mécanisme* : integration test GUT — instance 1 achète (mock SaveLoad capture array), instance 1 free, instance 2 créée avec mock SaveLoad retournant `[]`, assert `_owned_upgrades == []` côté instance 2. **Justification** : risque réel si `_owned_upgrades` est déclaré `static` par erreur ou si autoload conserve l'état.

**AC-SHP-55 [Integration] [ADVISORY]** (méta-AC propagation) : GIVEN CreditEconomy r2+ amende le contrat `try_spend` (signature, valeur de retour, comportement erreur), WHEN shop-system est re-testé contre Credit r2+, THEN tous ACs groupe B (AC-SHP-6 à 14) et groupe J (AC-SHP-46) re-passent sans modification du code shop. *Mécanisme* : note de propagation — à l'entrée de chaque sprint modifiant CreditEconomy, re-runner l'intégralité du groupe B + J automatiquement (CI suffit si tests indépendants bien mockés). Si fail, amendement Shop r3 requis. **Justification** : méta-AC de régression inter-système, absente du r1.

---

**Total : 55 ACs (r2)**
- BLOCKING : 33 (groupes A-B-C-D-E-F-G-H-I partiel + J — incluant AC-SHP-49 promu BLOCKING suite à Save/Load r1 RESOLVED)
- ADVISORY : 22 (groupes G visuels, H perf, I anti-patterns, K playtest, L ajouts r2 + AC-55 méta)
- PROVISIONAL chain-blocked : 1 (AC-SHP-48 OQ-SHP-2 UpgradeSystem r1 — seul restant)
- AUTO : 43 (Logic + Integration + Lint + Performance auto)
- MANUAL : 8 (Visual + Manual-Playtest)
- PROVISIONAL : 1 (réduit de 3 à 1 par r2 — Save/Load r1 + OQ-SHP-4 RESOLVED MVP)
- META-PROPAGATION : 1 (AC-SHP-55, surveille amendements Credit r2+)

## Open Questions

| OQ | Question | Status | Recommandation | Owner | Urgence |
|----|----------|--------|----------------|-------|---------|
| **OQ-SHP-1** | Faut-il un état dédié `SHOPPING` dans GSM enum (ADR-0007 D-2) si Tier 2+ apporte un shop overlay sur gameplay 3D (au lieu de scène container) ? | OPEN — Tier 2+ uniquement | MVP : pas de nouvel état (R-SHP-5 décidé, scène container suffit). Tier 2+ : si shop overlay envisagé, amendement ADR-0007 D-2 + GSM r2 requis (ajouter SHOPPING state). | Game-designer + technical-director | Tier 2+ |
| **OQ-SHP-2** | Contrat exact `UpgradeSystem.apply_upgrade(id: StringName) -> void` : signature, timing, comportement si Player non instancié (shop.tscn n'a pas de Player) ? | OPEN — bloquant impl | À résoudre lors de `/design-system upgrade-system` (Systems Index #13). Recommandation guard provisoire : si UpgradeSystem.apply_upgrade appelé hors PLAYING 3D, flag upgrade comme "pending apply au prochain `level_active`". Idempotence confirmée par contrat. | Game-designer + Upgrade GDD author | Bloquant impl Sprint 1 |
| **OQ-SHP-3** | API exacte `SaveLoad.save_string_array(key, array)` + `load_string_array(key, default)` : type retour, gestion corruption (valeur non-Array), atomicité écriture, multi-profile prefix Tier 2+ ? | ✅ **RESOLVED 2026-04-27** par Save/Load System Designed r1 (Systems Index #3, batch commit Sprint A). Save/Load r1 confirme l'API `save_string_array(key, value) -> void` + `load_string_array(key, default) -> Array[StringName]` à l'identique du contrat provisoire Shop r1. **Atomicité** : Save/Load r1 écrit via `ConfigFile` write-through synchrone, atomic write temp+rename **différé Tier 2+** (OQ-SAV-4) — MVP accepte le risque crash-mid-write, mitigé par Shop EC-SHP-9 Option C buffer retry. Multi-profile prefix Tier 2+ délégué à Save/Load `set_active_profile(id)` transparent (OQ-SAV-6). AC-SHP-49 peut être validé contre Save/Load r1 réel (plus PROVISIONAL chain-blocked). | RESOLVED via Save/Load r1 |
| **OQ-SHP-4** | Audio bus `SHOP_UI` Tier 2+ : créer dédié OU réutiliser `UI` existant (Audio r2.1 hierarchy figée) ? Quels SFX MVP→Tier 2+ (purchase/denied/continue) ? | ✅ **RESOLVED 2026-04-27 (MVP partiel)** | **MVP : zéro SFX shop confirmé** (cohérent Audio r2.1 + Pillar 1 anti-bruit + anti-fantasy "achat sobre"). **Tier 2+ : OPEN** — amendement Audio r2.2 décidera bus dédié `SHOP_UI` vs réutilisation `UI` quand audio-director designera l'extension. Aucun blocage MVP, aucun blocage /create-epics. | Audio-director Tier 2+ | RESOLVED MVP / OPEN Tier 2+ |
| **OQ-SHP-5** | Mécanisme de passage `next_etage_id` du Level (ou GSM) vers Shop pour Tier 2+ multi-étages ? Param scène, autoload state-bag, signal payload, instance `Shop.set_next_etage(id)` post-init ? | ✅ **RESOLVED 2026-04-27** | Décision tranchée : **autoload `RunContext`** (singleton léger, state-bag) exposant `current_etage_id: int`, `next_etage_id: int`. Shop lit `RunContext.next_etage_id` au `_ready()` Tier 2+ et l'utilise dans `_on_continue_pressed()` pour `request_scene_transition` chaîné. Justification : évite le couplage scène-à-scène (Shop→Level direct), évite param scène fragile, cohérent avec pattern projet (autoloads pour state cross-scene). MVP : non-applicable (2 étages MVP gérés par séquence Level1→Shop→Level2→Shop→Menu sans `RunContext`). Tier 2+ : RunContext à créer lors de l'ajout du 3e étage. Aucun blocage /create-epics MVP. | Game-designer + GSM r2 author | RESOLVED |
| **OQ-SHP-6** | Faut-il introduire un système d'upgrades consommables (potions, boost runs) Tier 3 ? | DEFERRED — Tier 3 design space | Recommandation : NON. Anti-pillar grinding strict (game-concept anti-pillar inventory). Si Tier 3 introduit méta-progression cross-run, ré-évaluer. | Creative-director Tier 3 | Tier 3 (probablement jamais) |
| **OQ-SHP-7** | Faut-il un mode "preview" upgrade sur hover (animation Player démontrant l'effet en miniature) ? | DEFERRED — Tier 2+ | Recommandation : NON MVP (Pillar 1 anti-distraction). Tier 2+ envisageable comme video clip 2-3s sur hover prolongé > 1s. | UX-designer Tier 2+ | Tier 2+ |
| **OQ-SHP-8** | Sécurité save tampering Tier 3 : HMAC/signature sur `owned_upgrades` pour prévenir édition manuelle ? | DEFERRED — Tier 3 | Recommandation : NON MVP (solo offline, pas de leaderboard). Tier 3 si speedrun leaderboard introduit, signature requise (Save/Load extension). | Security-engineer Tier 3 | Tier 3 |
| **OQ-SHP-9** | Localization MVP : strings hardcoded FR ("POSSÉDÉ", "Continuer", "CRÉDITS :") — pattern `tr()` Godot ou skip i18n MVP ? | OPEN — extraction Tier 2+ | Recommandation : skip MVP (FR-only game-concept). Extraction `tr()` Tier 2+ via `/localize` skill quand Localization team établie. | Localization-lead Tier 2+ | Tier 2+ |
| **OQ-SHP-10** | Multi-profile saves (slot 1/2/3) : préfixage clé `"profile_{N}.owned_upgrades"` côté Shop ou côté SaveLoad ? | OPEN — Tier 2+ | Recommandation : côté SaveLoad (préfixage transparent via `set_active_profile(id)`). Shop reste agnostique. | Save/Load GDD author Tier 2+ | Tier 2+ |
| **OQ-SHP-11** (nouveau r2) | Audit GSM ADR-0007 D-? : `paused = false` est-il garanti avant `change_scene_to_file` lors d'une transition vers une scène container (shop, menu) ? EC-SHP-19 dépend de cette garantie. Aujourd'hui non confirmé dans ADR-0007. | OPEN — bloquant impl Sprint 1 (low severity) | Audit GSM r2 ADR-0007 D-? lors du `/design-system upgrade-system` ou `/design-system save-load-system` Sprint A continuation. Si non garanti, GSM doit ajouter une décision explicite (D-N) imposant `get_tree().paused = false` avant tout `change_scene_to_file`. Couverture Shop niveau 1 (PROCESS_MODE_ALWAYS partout) suffit MVP. | GSM author + technical-director | Sprint A continuation |
| **OQ-SHP-12** (nouveau r2) | Tier 2+ : si playtest révèle un comportement de re-run mécanique cumulatif (joueur farm crédits via re-runs étage 1), considérer "level completion seal" (étage marqué COMPLETED dans Save, pas regrindable) OU "diminishing returns" sur re-credit. Aujourd'hui aucun verrou. | OPEN — Tier 2+ playtest dependent | MVP : aucune action — accepté comme compromis Pillar 4 (rejouer pour explorer reste possible). Tier 2+ : décision basée sur playtest data. | Game-designer + creative-director | Tier 2+ |

---

### Résolutions induites par ce GDD r2

- **OQ-CRD-2 (Credit r1)** : "contrat `try_spend` Shop" — ✅ **RESOLVED 2026-04-27** par ce GDD r2. Shop confirme l'API `CreditEconomy.try_spend(amount: int) -> bool` SYNC atomique à l'identique du contrat provisoire Credit r1. Credit GDD a marqué OQ-CRD-2 RESOLVED dans son §Open Questions.
- **F-CRD-3 convention `n` (Credit r1)** : amendée r2 (1-based → 0-based) pour aligner avec F-SHP-1. Bug d'impl cross-GDD éliminé.

### Bidirectional updates appliquées r2

- ✅ **Credit r1 §Open Questions** : OQ-CRD-2 RESOLVED ; F-CRD-3 amendée r2 0-based.
- ⚠️ **GSM r1 §Dependencies** : `ShopSystem (inferred, Not Started)` → `ShopSystem (Designed r2)` à propager lors du commit landed (action Phase 5).
- **HUD r1** : aucun amendement requis — zéro couplage direct (architecture séparée scène).
- **Audio r2.1** : aucun amendement requis MVP. Tier 2+ : amendement r2.2 pour bus `SHOP_UI` (OQ-SHP-4 Tier 2+ resté open).
- **Upgrade GDD (Not Started, Systems Index #13)** : devra citer Shop comme caller `apply_upgrade` + implémenter pattern `_pending_upgrades` queue (OQ-SHP-2).
- **Save/Load GDD (Not Started, Systems Index #3)** : devra citer Shop comme consumer `save/load_string_array` + garantir atomicité écriture (OQ-SHP-3 contrainte normative).
- **Level r3** : aucun amendement requis MVP. Tier 2+ : si seal de niveau introduit (OQ-SHP-12), Level r4 amendement.
- **Level GDD r3** : aucun amendement MVP requis (Level émet `etage_completed` consommé par GSM, pas Shop direct). Tier 2+ : payload `next_etage_id` à passer (OQ-SHP-5).
