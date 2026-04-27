# Design Review — Level System r1
**Date** : 2026-04-23
**Reviewer** : game-designer (fresh session solo)
**GDD** : `design/gdd/level-system.md` (923 lignes)
**Session** : review r1 indépendante, session fraîche, auto-approve mode

---

## Executive Summary

Le GDD Level System est structurellement solide, substantiel sur les 8 sections requises, et implémentable tel quel pour le MVP. La séparation des responsabilités (Level = données spatiales, pairs = comportement) est un choix d'architecture sain et cohérent avec l'ensemble de la base GDD. La Player Fantasy est la meilleure du projet à ce stade — viscérale, précise, pillar-aligned.

Trois findings BLOCKING ont été initialement identifiés. **BLOCKING-1 a été INVALIDÉ** après vérification inline du registry (voir annotation ci-dessous) — `design/gdd/level-system.md` est déjà présent dans le `referenced_by` des 4 constantes citées (KATANA_REACH l.230, LAYER_ENVIRONMENT l.374, LAYER_INTERACTIVE l.386, RESPAWN_DELAY l.215). Le reviewer a manqué l'état à jour du registry (mis à jour en Phase 5b du `/design-system` source). **Il reste donc 2 BLOCKINGs réels** : une ambiguïté sur le signal `room_entered` qui bloquera l'implémentation HUD (BLOCKING-2), et une AC manquante sur la validation de `checkpoint_spacing` (BLOCKING-3).

**Verdict : APPROVED WITH REVISIONS — r1 → r2 ciblé.**

Les 2 BLOCKINGs réels doivent être résolus avant merge. Aucun ne nécessite de rethinking architectural.

---

## Findings par sévérité

### BLOCKING (3)

---

**BLOCKING-1 — [INVALIDATED 2026-04-23 post-verification]** `KATANA_REACH` absent du `referenced_by` registry

> **CORRECTION** : Vérification directe du registry (`design/registry/entities.yaml`) effectuée après publication du rapport : `design/gdd/level-system.md` est **déjà présent** dans le `referenced_by` des 4 constantes concernées :
> - `KATANA_REACH` : l.228–230 inclut bien `design/gdd/level-system.md`
> - `LAYER_ENVIRONMENT` : l.372–374 inclut bien `design/gdd/level-system.md`
> - `LAYER_INTERACTIVE` : l.384–386 inclut bien `design/gdd/level-system.md`
> - `RESPAWN_DELAY` : l.211–215 inclut bien `design/gdd/level-system.md`
>
> Le registry a été mis à jour en Phase 5b du `/design-system` source (voir `last_updated` commentaire l.40 et changelog `production/session-state/active.md`). Le reviewer n'a pas vu l'état à jour. **Aucune action requise.**
>
> Texte original du finding conservé ci-dessous pour traçabilité :

---

**BLOCKING-1 (original, INVALIDATED) — `KATANA_REACH` absent du `referenced_by` registry**

`design/registry/entities.yaml`, constante `KATANA_REACH` (lignes 224-234) :

```yaml
referenced_by:
  - design/gdd/player-combat-system.md
```

Le Level System utilise `KATANA_REACH` comme input critique de F1 (`min_opening_width = 2 × KATANA_REACH = 3.6 m`, line 152-153) et de F8 (`min_wall_height = jump_apex + reach_margin`, line 259-268). Le registry liste uniquement `player-combat-system.md` en `referenced_by`. Si `KATANA_REACH` change (sa `safe_range` est `[1.4, 2.2]` — plage large), F1 et F8 changent silencieusement et toute la géométrie de l'étage peut devenir invalide.

De plus, le GDD note (line 152) que `KATANA_REACH` vient du registry, mais le registry note (lignes 228-232) : *"Sera consommé par Enemy System et par Level System"* — futur, pas encore acté. La réciprocité est déclarée en commentaire prose mais pas dans le champ `referenced_by`.

**Fix requis** : ajouter `design/gdd/level-system.md` au `referenced_by` de `KATANA_REACH` dans `design/registry/entities.yaml`. Vérifier aussi que `LAYER_ENVIRONMENT = 4` et `LAYER_INTERACTIVE = 5` (référencés dans R-3, line 73-80) ont des entrées registry — ils apparaissent dans le `last_updated` du registry mais aucune entrée structurée n'est présente (les collision layers sont mentionnés dans le changelog de `entities.yaml` mais la section `constants` ne les contient pas).

---

**BLOCKING-2 — Signal `room_entered` — signature incohérente entre Detailed Rules et ACs**

Le tableau `§Interactions` (line 136) déclare :

```
Signal : room_entered(room_index: int, total_rooms: int)
```

Mais l'AC-LVL-21 (line 701-703) dit :

```
THEN signal room_entered(3, total_rooms) émis...
```

Et AC-LVL-22 (line 705-708) dit :

```
THEN chaque entrée émet un room_entered(3, ...) séparé
```

Alors que l'interface provisoire GDD (line 366-373) ne liste **pas** `room_entered` parmi les signaux déclarés de l'interface Game State Manager. Le signal existe dans le tableau Interactions (line 136) mais est absent du bloc GDScript provisoire (lines 360-372).

Problème concret : un programmeur qui implémente depuis la section §Dependencies (qui liste l'interface GDScript) ne verra pas `room_entered` dans la signature. L'HUD System et l'Audio System dépendent de ce signal (lines 136-139) — s'il est manqué à l'implémentation, deux systèmes sont silencieusement cassés.

**Fix requis** : ajouter `signal room_entered(room_index: int, total_rooms: int)` au bloc GDScript de l'interface provisoire (section Dependencies). Confirmer que la signature à deux paramètres (`room_index`, `total_rooms`) est définitive — l'AC-LVL-21 l'utilise implicitement mais l'AC-LVL-22 utilise `(3, ...)` avec le second paramètre indéfini.

---

**BLOCKING-3 — AC manquante : violation de F3 (checkpoint_spacing hors range)**

F3 (lines 179-195) définit `CHECKPOINT_SPACING ∈ [2, 3]` et documente les conséquences hors-range dans Tuning Knobs (lines 414). Mais aucun AC ne teste qu'un étage dont le `checkpoint_spacing` viole la contrainte [2,3] est détecté et rejeté. Actuellement, le lint pré-build (mentionné dans plusieurs ACs comme gate) ne couvre pas ce cas.

L'AC-LVL-20 (line 693-696) teste que `count ∈ [8, 10]` pour `RoomTrigger_NN` — mais le test du spacing checkpoint dépend du ratio `checkpoint_count / room_count`, pas d'une valeur isolée. Un étage de 10 salles avec 1 seul checkpoint passe AC-LVL-20 mais viole F3.

**Fix requis** : ajouter un AC (AUTO, groupe B ou D) qui valide que `floor(N_rooms / checkpoint_count) ∈ [2, 3]` — avec gate lint pré-build. Exemple de formulation :

```
AC-LVL-46 AUTO — Checkpoint spacing dans range F3
GIVEN scène chargée, N checkpoints et N_rooms salles
WHEN floor(N_rooms / checkpoint_count) calculé
THEN résultat ∈ [2, 3] ; sinon lint pré-build échoue avec message explicit
```

---

### MAJOR (4)

---

**MAJOR-1 — F2 draw_calls : marge non-testable en worst-case**

F2 (lines 162-176) projette `draw_calls_total ≤ 350` avec une marge de 150 pour enemies/VFX/projectiles. L'AC-LVL-31 (lines 752-755) teste le budget global (≤ 500 total, contribution Level ≤ 350), mais ne spécifie pas les conditions worst-case.

Problème : "salle worst-case" n'est pas définie. Une salle avec 3 SecretVolume_*, 2 CheckpointVolume_*, 8 EnemySlot et 3 HazardSlot peut avoir une géométrie dense qui dépasse 30 draw calls à elle seule. Mais aucun AC ne spécifie le scénario de test (quelle combinaison de slots, quel niveau d'activation des peers).

Le budget de 150 draw calls pour tout le reste (enemies + VFX + projectiles + HUD + menus) est généreux sur un étage vide mais devient tendu si 4-6 ennemis avec trail VFX sont actifs simultanément (les specs VFX et Enemy System n'existent pas encore, donc impossible de valider).

**Recommandation** : ajouter dans AC-LVL-31 une clause "worst-case" : mesure avec mocks simulant la présence de N ennemis (N = ROOM_COUNT_MAX / 2 = 5), VFX actifs, HUD actif. La note actuelle "contribution Level isolable ≤ 350" est bonne mais non-testable sans une définition de "isolable".

---

**MAJOR-2 — EC-7 et AC-LVL-40 : responsabilité de validation mal attribuée**

EC-7 (lines 313-317) dit que Level System expose `validate_checkpoint_anchors()` mais que "c'est la responsabilité du Checkpoint System de valider via raycast up avant spawn". AC-LVL-40 (lines 799-803) teste `validate_checkpoint_anchors()` en debug.

Problème de design : Level System n'a pas à connaître la physique du raycast pour valider ses propres anchors. Mais la règle dit que Checkpoint System "valide" — alors qui fail le build si un anchor est dans un mur ? Le GDD dit "lint runtime" pour Level, mais c'est une validation authoring, pas runtime. En CI, si Level expose `validate_checkpoint_anchors()` avec un raycast `up`, c'est Level qui fait de la physique — ce qui viole l'encapsulation établie ailleurs (Level publie de la donnée spatiale, il ne calcule pas de physique).

Le AC-LVL-40 est taggé SMOKE (manuel) alors qu'un authoring bug d'anchor peut silencieusement casser la boucle de respawn — c'est un BLOCKING gameplay.

**Recommandation** : clarifier l'ownership. Option A : `validate_checkpoint_anchors()` reste dans Level mais est upgradé en gate CI automatique (AUTO, pas SMOKE). Option B : la validation est déportée dans le Checkpoint System GDD futur avec un AC dédié. Trancher avant l'implémentation du Checkpoint System.

---

**MAJOR-3 — `LevelState` enum non défini dans le GDD**

Le GDD utilise `LevelState.UNLOADED`, `LevelState.ACTIVE`, etc. dans les ACs (ex: AC-LVL-1 line 598-600, AC-LVL-2 lines 602-605) et dans l'interface provisoire (`get_state() -> LevelState`). Mais `LevelState` n'est défini nulle part dans ce GDD.

Les états sont décrits dans le tableau §States (lines 108-115) et dans la machine d'état (lines 100-106) — mais la correspondance entre les labels textuels (`Unloaded`, `Loading`, `Active`, `Unloading`) et les valeurs GDScript de l'enum est implicite. En implémentation Godot 4.6, `LevelState` doit être un `enum` déclaré dans le script — avec exactement ces 4 valeurs : `UNLOADED`, `LOADING`, `ACTIVE`, `UNLOADING`.

Un programmeur doit déduire les noms exacts des valeurs depuis les ACs. Si les noms diffèrent (ex: `LEVEL_ACTIVE` au lieu de `ACTIVE`), les ACs deviennent fausses.

**Recommandation** : ajouter dans §Detailed Design un bloc GDScript déclarant l'enum `LevelState` avec ses 4 valeurs et une description d'une ligne par valeur. Coût : 10 lignes.

---

**MAJOR-4 — `player_out_of_world` payload : `last_valid_position` non défini**

EC-1 (lines 274-279) documente que Level émet `signal player_out_of_world(last_valid_position: Vector3)`. Mais "last_valid_position" n'est pas défini : c'est quoi ? La dernière position connue du joueur avant qu'il sorte du WorldBoundsVolume ? La position au tick précédent ? La position du dernier checkpoint ?

Dans EC-1 la phrase est : `Level System émet signal player_out_of_world(last_valid_position: Vector3)`. Dans AC-LVL-25 (lines 721-723) : `last_valid_position ≠ position void`. C'est tout.

Checkpoint System consomme ce signal pour déclencher le respawn. Si `last_valid_position` est la position du joueur un tick avant la chute (qui peut être en plein vide), Checkpoint System risque de respawn le joueur dans le vide. Si c'est le dernier checkpoint franchi, c'est le bon comportement — mais alors Level System doit tracker le dernier checkpoint, ce qui couple Level avec Checkpoint.

**Recommandation** : définir précisément `last_valid_position` dans EC-1. Clarifier si Level System trackera la dernière position "in-world" (position à chaque tick dans WorldBoundsVolume) ou déléguera complètement à Checkpoint System (qui ignore le signal `player_out_of_world` et utilise son propre état de dernier checkpoint). L'un ou l'autre est valide — l'ambiguïté actuelle ne l'est pas.

---

### MINOR (5)

---

**MINOR-1 — `ceil` vs `floor` dans F3 pour checkpoint_count**

F3 (line 181) utilise `ceil(N_rooms / CHECKPOINT_SPACING)` pour calculer `checkpoint_count`. Mais l'exemple (lines 186-194) donne : spacing=3, N_rooms=10 → 4 checkpoints. `ceil(10/3) = ceil(3.33) = 4` — correct. Pour N_rooms=8, spacing=3 : `ceil(8/3) = ceil(2.67) = 3` — correct.

Mais le texte dit "nominal MVP : spacing = 3 → 4 checkpoints (start, après salle 3, après salle 6, après salle 9)". Le checkpoint "start" est-il compté dans les 4 ? Si oui, c'est `PlayerStart` qui est un Marker3D, pas un `CheckpointVolume_NN`. Si non, `checkpoint_count` dans la formule ne compte pas `PlayerStart`.

C'est un edge case authoring : si `PlayerStart` est compté comme checkpoint 0, et que le Checkpoint System commence à numéroter à 1, l'indexing `CheckpointVolume_NN ↔ CheckpointAnchor_NN` peut commencer à 01 ou 00, ce qui affecte R-5.2.

**Recommandation** : préciser si `PlayerStart` est un `CheckpointVolume_00` (et donc compté dans F3) ou un nœud distinct non-compté. La règle R-5.2 et les ACs-LVL-18/19 traitent `PlayerStart` séparément — mais F3 est ambigu.

---

**MINOR-2 — `ceiling_height` dans F6 vs R-2.3 vs Tuning Knobs**

F6 (lines 229-239) utilise `ceiling_height = 5 m` pour calculer le volume de l'étage. R-2.3 (line 69) dit que les murs wall-runnable ont `hauteur ≥ 4 m`. F8 (line 257) calcule `min_wall_height = 4.0 m`. Tuning Knobs (line 417) liste `CEILING_HEIGHT` avec default `5.0` et safe range `[4.0, 6.0]`.

Incohérence : si `CEILING_HEIGHT` est abaissé à son minimum de `4.0 m` (safe range), la formule F6 change (`etage_bounding_volume = 100 * 10 * 4 = 4000 m³` au lieu de 5000), et surtout le plafond à 4.0 m = exactement le minimum wall-run. Un joueur en wall-run dans une salle avec `CEILING_HEIGHT = 4.0 m` touche le plafond en fin de run.

La note Tuning Knobs dit "< 4 = wall-run cassé (viole R-2.3)" — mais ne dit pas que `CEILING_HEIGHT = 4.0 m` (la limite basse du safe range) est elle-même problématique.

**Recommandation** : ajuster le safe range de `CEILING_HEIGHT` à `[4.5, 6.0]` et documenter le raisonnement : `ceiling_height > min_wall_height + 0.5 m` de marge tête = minimum `4.5 m`.

---

**MINOR-3 — Collision layer ownership : `LAYER_ENVIRONMENT` dans registry vs GDD**

R-3 (lines 73-80) définit `LAYER_ENVIRONMENT = 4` et `LAYER_INTERACTIVE = 5`. Le `last_updated` du registry (line 40) mentionne : *"+5 constants collision layers (LAYER_PLAYER, LAYER_ENEMY, LAYER_ENEMY_HITBOX, LAYER_ENVIRONMENT, LAYER_INTERACTIVE)"* — mais aucune entrée `constants` structurée pour ces layers n'est visible dans le registry.

Si ces constantes existent dans un bloc registry non accessible (hors les 250 premières lignes lues), il n'y a pas de problème. Mais si elles sont uniquement dans le changelog du `last_updated` et pas en entrée structurée, le registry est incomplet.

**Recommandation** : vérifier que `LAYER_ENVIRONMENT`, `LAYER_INTERACTIVE`, `LAYER_PLAYER`, `LAYER_ENEMY`, `LAYER_ENEMY_HITBOX` ont des entrées `constants` structurées dans `design/registry/entities.yaml`. Si non, les ajouter avec `source: design/gdd/player-combat-system.md` (owner initial selon le changelog) et `referenced_by: [design/gdd/level-system.md]`.

---

**MINOR-4 — `ResourceLoader.load_threaded_request` : API Godot 4.6 non vérifiée**

F4 (lines 197-210) et EC-2 (line 283) et EC-3 (line 292) utilisent `ResourceLoader.load_threaded_request()` et `load_threaded_get_status()`. Ces APIs existent depuis Godot 4.0, mais Godot 4.6 a introduit des changements dans `FileAccess` et les APIs de resource loading (voir `docs/engine-reference/godot/VERSION.md` : "4.4 MEDIUM — FileAccess return types").

Le GDD référence ADR-0001 et ADR-0003 mais pas d'ADR spécifique sur le threading de resource loading. La note de bas du GDD dit "Pas d'ADR spécifique Level au MVP" — acceptable, mais le comportement exact de `load_threaded_get_status()` sur Godot 4.6 + Jolt + le nouveau D3D12 Windows default (ADR-0003) doit être vérifié empiriquement.

**Recommandation** : ajouter une note dans AC-LVL-3 et EC-3 : "Vérifier la compatibilité `ResourceLoader.load_threaded_*` avec Godot 4.6 avant Sprint 1 Level — consulter `docs/engine-reference/godot/` et valider sur la codebase existante."

---

**MINOR-5 — Open Questions OQ-7 et OQ-8 ont des deadlines "Pré-Vertical Slice" alors qu'elles impactent le MVP**

OQ-7 (lines 899-909) concerne la validation runtime des anchors en CI — deadline "Pré-Vertical Slice". Mais le MVP lui-même a un seul étage avec des anchors. Si un mauvais anchor passe en MVP et casse le respawn, le problème surgit avant le Vertical Slice.

OQ-8 (lines 911-920) concerne un overlay debug — deadline "Pré-Vertical Slice". Acceptable, un overlay debug n'est pas bloquant MVP.

**Recommandation** : avancer la deadline OQ-7 à "Fin Sprint 1 Level" (premier étage authorizé complet). La valider en CI sur le premier étage prévient les régressions authoring dès le MVP.

---

### POLISH (3)

---

**POLISH-1 — `FogColumnAnchor` non documenté dans la hiérarchie canonique R-1**

V-4 (line 483) mentionne `Marker3D FogColumnAnchor` pour la colonne de volumetric fog en fin d'étage. R-1 (lines 40-63) définit la hiérarchie canonique de scène avec `SpawnMarkers` — mais `FogColumnAnchor` n'y est pas listé.

C'est un Marker3D non-standard, géré par VFX System. Il mérite d'être dans la hiérarchie canonique R-1 ou dans une sous-section "SpawnMarkers optionnels (VS+)".

---

**POLISH-2 — Tuning Knobs : `AUDIO_ROOM_AMBIENT_SWAP` listé dans §Visual/Audio (A-3) mais absent de §Tuning Knobs**

Line 501 (§Visual/Audio A-3) mentionne `AUDIO_ROOM_AMBIENT_SWAP = false` comme un knob MVP. La section §Tuning Knobs ne le liste pas. Incohérence mineure — un programmeur qui implémente depuis §Tuning Knobs uniquement ne verra pas ce flag.

---

**POLISH-3 — AC-LVL-45 est un placeholder, pas un AC**

AC-LVL-45 (lines 826-829) dit : "GIVEN création d'un GDD cité §Dependencies Downstream... THEN §Dependencies du nouveau GDD contient une entrée explicite citant Level System". Ce n'est pas un AC du Level System — c'est un reminder de process. Il ne teste pas le Level System lui-même.

Un AC vrai serait : "GIVEN implementation Level System — WHEN introspection des signaux exposés — THEN chaque signal dans §Interactions est présent dans le script compilé" (ce qui ressemble à AC-LVL-43). AC-LVL-45 devrait être déplacé dans les Open Questions ou dans une note §Dependencies, pas dans §Acceptance Criteria.

---

## Section-by-Section Assessment

### 1. Overview

**Verdict : PASS — substantiel**

923 mots, couvre scope MVP, dépendances clés, couches de responsabilités, pillar alignment. Un nouveau contributeur peut comprendre le périmètre du système en 2 minutes. Aucune section faible.

Note : la mention "aucun ADR dédié Level au MVP" est correctement documentée — les contraintes temps-réel sont absorbées par ADR-0001/0003.

### 2. Player Fantasy

**Verdict : PASS — la meilleure Player Fantasy du projet à ce stade**

Le texte "La tour Arasaka te refuse" est concret, ancré dans le ressenti player, et connecté directement aux 4 pillars avec des tests ("Ce que le joueur ne doit jamais ressentir"). La vignette "tu arrives en bas d'un puits vertical de quarante mètres... Trois runs plus tard" est exactement le type d'exemple-cible qui guide le level design authoring.

Alignement MDA : la section délivre sur Challenge (P1 FLOW, skill ceiling) et Discovery (P4 SECRETS). Relatedness (SDT) est intentionnellement absent — cohérent avec le solo design et l'anti-narratif.

### 3. Detailed Rules

**Verdict : PASS avec note**

R-1 à R-5 sont précis et implémentables. La machine d'état est correcte (4 états, transitions atomiques, règles T-1 à T-4). Le tableau §Interactions est complet et couvre tous les peers.

Note mineure : le tableau §Interactions a une ligne "Camera System — Aucune interaction (Camera suit le player, ignore l'étage)" qui est correcte mais créé une attente : si post-MVP le Camera System doit réagir à une salle particulière (effet de salle, parallax), l'interface n'existe pas. Acceptable pour MVP, à noter en OQ future.

**BLOCKING-2 impacte cette section** (signal `room_entered` absent du bloc GDScript provisoire).

### 4. Formulas

**Verdict : PASS avec réserves**

F1-F8 sont substantielles, les variables sont définies, les exemples calculés. Les justifications ("Pourquoi × 2 et pas × 1") sont utiles et non-triviales.

**Réserve** : F8 (min_wall_height) dépend de `jump_apex = 1.680 m` sourced depuis `player-movement-system.md Formulas r4`. Le Movement GDD est en statut "In Review (r3 appliqué, pending r4)" — si la formule de jump_apex change en r4, F8 du Level System se retrouve désynchronisée silencieusement. Ce n'est pas un BLOCKING (la valeur actuelle est correcte) mais un risque de maintenance.

F2 draw calls budget : voir MAJOR-1.

### 5. Edge Cases

**Verdict : PASS**

12 edge cases en format GIVEN/WHEN/THEN — tous précis, sans "handle gracefully". EC-8 (tunneling) est particulièrement bien documenté avec la mitigation authoring (épaisseur ≥ 0.3 m) liée à la règle physique. EC-11 (race condition peer binding) est le seul edge case qui révèle un gap architectural (le `call_deferred` de `level_active` n'est pas mentionné dans §Detailed Rules §States Transitions — il est dans EC-11 uniquement, puis AC-LVL-26 le couvre). La règle devrait être dans T-2 des transitions atomiques.

**MAJOR-4** impacte EC-1 (payload `last_valid_position` non défini).

### 6. Dependencies

**Verdict : PASS avec note sur BLOCKING-1**

Le tableau upstream/downstream est complet. L'interface provisoire GDScript est utile. La section "Notes de réciprocité forward-looking" est une pratique saine et unique dans le projet — mérite d'être normalisée dans les prochains GDDs.

**BLOCKING-1** : `KATANA_REACH` absent du `referenced_by` registry.
**BLOCKING-2** : `room_entered` absent du bloc GDScript provisoire.

Dépendances indirectes (Player Movement, Combat, Camera) sont clairement délimitées — sain.

### 7. Tuning Knobs

**Verdict : PASS — exhaustif**

Trois catégories de knobs (authoring, runtime, debug) avec ranges safe, impacts documentés, formulas sources. Les "immutable sans amendement registry" (`MIN_OPENING_WIDTH`) sont correctement identifiés. Les règles d'ajustement (re-run smoke Level, playtest 10 min) sont concrètes.

**POLISH-2** : `AUDIO_ROOM_AMBIENT_SWAP` listé dans §Visual/Audio mais absent ici.
**MINOR-2** : `CEILING_HEIGHT` safe range légèrement incorrect (voir finding).

### 8. Acceptance Criteria

**Verdict : PASS — 45 ACs bien distribuées**

Répartition : 10 Lifecycle, 10 Structure, 10 Signals, 7 Performance, 5 Edge Cases, 3 Meta.

Qualité globale : les ACs AUTO sont testables en GUT, les SMOKE ont des scénarios précis, les PLAYTEST ont des critères observables (pas "ça doit feel bien"). Le mélange AUTO/SMOKE/PLAYTEST est approprié à la nature du système spatial.

**Redondances détectées** :
- AC-LVL-27 (SMOKE, signaux typés) et AC-LVL-43 (SMOKE, signals list match) couvrent des aspects similaires. AC-LVL-27 vérifie les types GDScript, AC-LVL-43 vérifie la correspondance contractuelle — complémentaires mais pourraient être fusionnés.
- AC-LVL-32 (VRAM budget) et AC-LVL-37 (baseline mémoire < 50 MB) se chevauchent. AC-LVL-32 mesure le delta post-load, AC-LVL-37 le combined RAM+VRAM. Gardez les deux mais clarifier que AC-LVL-32 = VRAM seule, AC-LVL-37 = RAM + VRAM combined.

**ACs manquantes** :
- **BLOCKING-3** : aucune AC valide `checkpoint_spacing ∈ [2, 3]`.
- Manque un AC pour `EtageExitTrigger` fires-once même si le joueur recule post-trigger (EC-6 est documenté mais AC-LVL-24 ne couvre que le fires-once sur re-entrée, pas le back-out impossible).
- Manque un AC pour F2 en worst-case (voir MAJOR-1).

**POLISH-3** : AC-LVL-45 n'est pas un vrai AC.

---

## Cross-GDD Issues

### Cohérence avec `player-combat-system.md`

**KATANA_REACH** : F1 (`min_opening_width = 2 × 1.8 = 3.6 m`) et F8 (`jump_apex + reach_margin = 3.98 m → 4.0 m`) utilisent `KATANA_REACH = 1.8 m` — valeur correcte, cohérente avec le registry (ligne 229) et le Combat GDD (Rule 4, ligne 51 du combat GDD : `height = KATANA_REACH = 1.8 m`). Pas de conflit.

**LAYER_ENVIRONMENT = 4** : cohérent entre Level System R-3 (line 73) et le registry changelog (line 40 du registry). L'absence d'entrée structurée est MINOR-3.

### Cohérence avec `player-movement-system.md`

**jump_apex = 1.680 m** : F8 du Level System source cette valeur depuis "player-movement-system.md Formulas r4 — h_combo = h_single + 6.5² / (2 * 28) = 0.926 + 0.754". Vérification : le Movement GDD (lignes 179-197) donne `GRAVITY = 28 m/s²` (dans la plage [22, 32]), et la formule double-jump utilise `v_y² / (2g)`. La valeur 1.680 m est plausible avec `GRAVITY = 28` et la formule jump combo. Mais le Movement GDD est en statut "In Review r3, pending r4" — risque de désynchro mentionné dans §Formulas.

**RESPAWN_DELAY = 0.05 s** : Level System cite (line 10) `RESPAWN_DELAY = 0.05 s pull déclenché depuis Checkpoint System`. Le registry (ligne 215) confirme 0.05 s. Cohérent.

**Wall-run conditions** : R-2.3 (line 69) dit `hauteur ≥ 4 m, longueur ≥ 3 m` pour les murs wall-runnable. Movement GDD Rule 7 dit `horizontal_speed > WALL_RUN_MIN_SPEED (5 m/s)` pour activer le wall-run. F8 dérive 4.0 m de `jump_apex + 2.3 m reach_margin`. Cohérence correcte — mais la "longueur ≥ 3 m" de R-2.3 n'est pas dérivée d'une formule Movement, c'est une approximation authoring. Acceptable mais non-vérifiable formellement.

### Cohérence avec `camera-system.md`

Le Level System déclare "Camera System — Aucune interaction". Le Camera GDD confirme que la caméra suit le joueur et ignore l'étage. Cohérent.

**BASE_FOV = 90°** et `WALL_RUN_TILT_ANGLE = 0.35 rad` du registry ne sont pas consommés par Level — correct.

### Cohérence avec `input-system.md`

Level System déclare "Input System — Aucune dépendance de Level envers Input" — avec la nuance correcte que `EtageExitTrigger` est détecté par physique Area3D, pas par input. Cohérent.

### Cohérence avec `systems-index.md`

Le systems-index (ligne 30) liste Level System comme "In Design r1 — Draft Complete". Le statut header du GDD (ligne 3) dit la même chose. Cohérent.

La dépendance Level System → Game State Manager est documentée dans systems-index (ligne 11 : "Depends On: Game State Manager") et dans le GDD §Dependencies. Cohérent.

---

## Registry Issues

### `entities.yaml`

1. **BLOCKING-1** : `KATANA_REACH.referenced_by` manque `design/gdd/level-system.md`.
2. **MINOR-3** : `LAYER_ENVIRONMENT` et `LAYER_INTERACTIVE` mentionnés dans le changelog `last_updated` mais absents des entrées `constants` structurées. À vérifier en lisant la suite du fichier registry (au-delà des 250 premières lignes).
3. Les formules F1-F8 du Level System ne sont pas enregistrées dans la section `formulas` du registry. F1 et F8 consomment `KATANA_REACH` cross-system — elles devraient avoir une entrée registry pour garantir la traçabilité si `KATANA_REACH` change.

### `tr-registry.yaml`

Aucun TR-ID n'existe pour le Level System. C'est attendu : le registry `tr-registry.yaml` est écrit par `/architecture-review` (voir header line 17), pas par `/design-system`. Le Level System n'a pas encore été passé en architecture-review. Pas un problème pour r1 — c'est le workflow normal.

---

## Open Questions — Évaluation

| OQ | Reportable ? | Deadline actuelle | Évaluation |
|----|-------------|-------------------|------------|
| OQ-1 (scene unique vs room-split) | Oui | Fin Tier 1 | Correctement positionné. La position actuelle (scene unique) est implémentable MVP. |
| OQ-2 (streaming inter-étage) | Oui | Début Tier 2 | Hors MVP, bien positionné. |
| OQ-3 (LevelKit vs hand-built) | Oui | Début Tier 3 | Hors MVP, bien positionné. 250 bodies manuels pour 1 étage sont tenables. |
| OQ-4 (SDFGI / GI baked) | Oui | Tier 2 | Hors MVP, aucun impact r1. |
| OQ-5 (audio ambient swap) | Oui | Tier 2+ | Hors MVP, signal déjà émis = 0 coût Level. |
| OQ-6 (accessibility) | Oui | Tier 3 | Hors MVP, architecture knobs existante est compatible. |
| OQ-7 (validation anchors CI) | **Non — avancer à Sprint 1 Level** | Pré-VS | Impacte le MVP (un seul étage, un mauvais anchor casse le respawn). Voir MINOR-5. |
| OQ-8 (debug overlay) | Oui | Pré-VS | Debug quality-of-life, pas MVP-blocking. |

**Verdict OQ** : 7/8 correctement reportables. OQ-7 devrait être avancée.

---

## Dominant Strategy Analysis

Le Level System étant un conteneur spatial, les "dominant strategies" sont des patterns de level design dégenerate plutôt que des exploits mécaniques.

**Pattern potentiel 1 — Clustering de secrets**

F7 dit `secret_count ≤ 3 par salle` (R-4, ≤ 3 Area3D secret par salle). Si un designer place 3 secrets dans la salle 1 et 0 dans les 7 suivantes, un joueur qui connait le pattern "fouille la première salle exhaustivement" maximise ses crédits sans aucun risque. Le GDD ne contraint pas la *distribution* des secrets par salle, seulement le total et le max par salle.

Le Design dit que les secrets sont "hors chemin nominal" et derrière des défis de mouvement (Pillar 4) — si ces contraintes de placement sont respectées à l'authoring, le clustering est atténué. Mais aucune règle formelle ne l'interdit.

**Recommandation** : ajouter dans R-5 ou §Tuning Knobs : "Pas plus de 1 secret dans les 2 premières salles" comme règle d'authoring pour distribuer la récompense d'exploration sur l'ensemble de l'étage.

**Pattern potentiel 2 — Farming de room_entered**

EC-5 et AC-LVL-22 documentent que `room_entered` est émis à chaque re-entrée. Si l'Audio System ou le Tutorial System ont un comportement déclenché par `room_entered` qui peut être farmed (ex: un popup tutoriel qui reset un cooldown), un joueur qui fait des allers-retours entre deux salles peut exploiter ça. Le Level System lui-même n'est pas exploitable, mais ses consommateurs pourraient l'être.

Le GDD en est conscient : "les consommateurs HUD/Tutorial/Audio doivent supporter le cas 2 room_entered au même tick" (EC-5). C'est documenté mais c'est une exigence contractuelle sur des systèmes qui n'existent pas encore. À formaliser dans les GDDs downstream.

---

## Recommendations

### Actions r2 obligatoires (pour lever les BLOCKINGs)

1. ~~**BLOCKING-1** : Ajouter `design/gdd/level-system.md` au `referenced_by` de `KATANA_REACH`~~ **INVALIDATED** — déjà présent dans le registry. Aucune action.

2. **BLOCKING-2** : Ajouter `signal room_entered(room_index: int, total_rooms: int)` au bloc GDScript de l'interface provisoire dans §Dependencies. Confirmer la signature à 2 paramètres dans tous les ACs (AC-LVL-21, AC-LVL-22 utilisent des ellipses).

3. **BLOCKING-3** : Ajouter AC-LVL-46 (AUTO) qui valide que `floor(N_rooms / checkpoint_count) ∈ [2, 3]` avec gate lint pré-build.

### Actions recommandées pour r2 (MAJOR — résolution avant implementation)

4. **MAJOR-1** : Ajouter une clause worst-case à AC-LVL-31 définissant le scénario de test (N ennemis mocks actifs, VFX actifs).

5. **MAJOR-2** : Trancher l'ownership de `validate_checkpoint_anchors()` et upgrader AC-LVL-40 de SMOKE à AUTO (ou déléguer au Checkpoint System GDD futur avec AC dédiée).

6. **MAJOR-3** : Ajouter un bloc GDScript déclarant `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }` dans §Detailed Rules.

7. **MAJOR-4** : Définir précisément `last_valid_position` dans EC-1 — est-ce la dernière position intra-WorldBoundsVolume (Level trackera) ou déléguée au Checkpoint System ?

### Actions optionnelles (MINOR/POLISH — peuvent attendre Tier 2)

8. Préciser dans F3 si `PlayerStart` est compté dans `checkpoint_count`.
9. Ajuster `CEILING_HEIGHT` safe range à `[4.5, 6.0]`.
10. Ajouter `FogColumnAnchor` dans la hiérarchie canonique R-1 comme "Marker optionnel".
11. Ajouter `AUDIO_ROOM_AMBIENT_SWAP` dans §Tuning Knobs.
12. Transformer AC-LVL-45 en OQ ou note §Dependencies.
13. Avancer deadline OQ-7 à Sprint 1 Level.
14. Ajouter une règle d'authoring dans R-5 sur la distribution minimum des secrets.
15. Documenter que `call_deferred` sur `level_active` est une règle d'implémentation (actuellement dans EC-11 uniquement — devrait être dans T-2).

---

## Addendum — Revue Godot 4.6 Implementability

**Reviewer** : godot-specialist (session parallèle, lecture seule)
**Verdict technique** : **IMPLEMENTABLE WITH RISK**

Le GDD démontre une bonne connaissance des patterns Godot. La hiérarchie de scène canonique (R-1) est correcte et idiomatique pour 4.6. Les trois risques techniques identifiés sont gérables avec mitigations.

### Risques techniques (3)

**Tech-Risk-1 — NavMesh bake dans budget F4** *(medium)*
Le contrat Level ↔ Enemy System est muet sur la nav mesh. Si Enemy System tente un bake runtime au `level_active`, 200–800 ms viennent directement sur le budget F4 (1000 ms). **Mitigation** : exiger que `NavigationRegion3D` soit baked en éditeur et exportée avec la scène, jamais rebaked runtime. Ajouter cette contrainte dans §Dependencies côté Enemy System.

**Tech-Risk-2 — F4 : budget 600 ms `base_scene_load` optimiste sans Shader Baker** *(medium)*
Forward+ sur D3D12 (défaut Windows 4.6) ajoute une compilation de pipeline sur first-use. Sans Shader Baker (disponible 4.5+), la première frame après `level_active` peut freezer 50–150 ms non comptabilisés. **Mitigation** : activer Shader Baker dans Project Settings et pré-chauffer le shader au boot global (scène dummy invisible, 1 frame). Le GDD mentionne "shader compile... pré-compilé à boot global" — il faut formaliser que c'est via Shader Baker 4.5+, pas un workaround manuel.

**Tech-Risk-3 — Area3D `WorldBoundsVolume` 5800 m³ avec Jolt** *(low-medium)*
Jolt broad-phase gère bien `BoxShape3D` convex pour grosses Area3D, mais un réflexe `ConcavePolygonShape3D` ferait exploser le coût. **Mitigation** : documenter explicitement dans R-1 / EC-1 que `WorldBoundsVolume` utilise obligatoirement `BoxShape3D`.

### Open Questions — réponses immédiates

**OQ-1 (scène unique vs split) — FERMÉE en faveur du single-scene.**
Trois faits Godot 4.6 : (1) `ResourceLoader.load_threaded_request()` charge une scène entière en un appel async sans overhead pour les sub-scenes inline ; (2) 8-10 salles × 25 StaticBody3D = 250 nœuds max, bien sous le seuil de traversal visible (> 5000) ; (3) les room-triggers intra-étage n'unloadent rien (R-5.1), donc split n'apporte aucun gain mémoire MVP. Split justifié seulement à Tier 2+ si étages simultanés augmentent.

**OQ-5 (audio layer swap) — FERMÉE, trivialement implémentable.**
`AudioServer.set_bus_volume_db()` par bus nommé depuis handler `room_entered`. 1 ligne GDScript côté Audio System. Aucun risque, aucun prototype. Décision "optionnel MVP / désactivé Tier 1" est la bonne.

**Dual-focus UI 4.6 breaking — N/A pour Level.**
Godot 4.6 introduit dual-focus (mouse/touch vs keyboard/gamepad). Level System n'expose aucun `Control` node (purement 3D). Breaking change transparent pour ce GDD, affectera HUD/Menu uniquement.

### Flags — Assumptions à préciser

**Flag-1 — AC-LVL-31 et draw calls Forward+**
`RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME` inclut passes shadow et depth pre-pass de Forward+. Forward+ Clustered sur Chrome Zen (flat shader, pas de transparence, pas de GI) = 1 draw call / surface matériau / passe. Avec shader unique + atlas unique, estimation 30 draw calls/salle réaliste **seulement si MeshInstance3D mergés par salle**. Sans merging, chaque `BoxMesh` séparé = 1 draw call min. **Action r2** : préciser dans R-4 que les MeshInstance3D d'une salle doivent être mergés via `MeshInstance3D.merge_meshes()` ou "bake mesh" éditeur.

**Flag-2 — `call_deferred` pour `level_active`**
GDScript `call_deferred` reporte d'exactement 1 frame dans idle step. Correct pour autoloads préexistants. Garantie tient pour peers autoload qui chargent dans `_ready()`. Si peer instancié dynamiquement *après* `level_active`, doit appeler `Level.get_level_state()` en pull — le GDD prévoit ça (EC-11 fallback). **Aucun changement requis, confirmation d'implémentabilité.**

**Flag-3 — Glow désactivé mais volumetric fog V-4**
Godot 4.6 change l'ordre glow/tonemapping (glow *avant* tonemapping maintenant). Le `FogColumnAnchor` exposé par Level devra être consommé par VFX System avec recalibration vs 4.3 reference. **Action** : note à transmettre à technical-artist, pas d'action GDD Level.

### Note F2 — 350 draw calls conservateur

Forward+ Clustered ne pénalise pas les draw calls sur géométrie statique opaque. Avec 1 shader, 1 atlas, meshes fusionnés, une salle Chrome Zen peut tenir 5–10 draw calls plutôt que 30. Le budget F2 est conservateur dans le bon sens — marge réelle plus grande que les 150 nominaux. **Indication qu'on aura du room for VFX / shadow passes additionnels sans casser le budget projet 500.**

### Intégration aux findings principaux

| Godot finding | Sévérité équivalente | Recommandation merge |
|---|---|---|
| Tech-Risk-1 (NavMesh) | MAJOR-5 | Ajouter au §Dependencies, contrat Enemy |
| Tech-Risk-2 (Shader Baker) | MAJOR-6 | Formaliser dans §Tuning Knobs ou T-2 |
| Tech-Risk-3 (BoxShape3D) | MINOR-6 | Note dans R-1 |
| Flag-1 (mesh merging) | MINOR-7 | Préciser dans R-4 |
| OQ-1 fermée | Win | Résoudre OQ-1 dans r2 directement |
| OQ-5 fermée | Win | Résoudre OQ-5 dans r2 directement |

**Deux OQ fermables immédiatement en r2** réduit la liste OQ à 6 entrées.

---

## Verdict Final

**APPROVED WITH REVISIONS — r1 → r2 ciblé**

Le GDD est implementable pour le MVP avec les 3 BLOCKINGs résolus. La qualité de rédaction est élevée : la Player Fantasy est viscérale, les Detailed Rules sont non-ambiguës, les Edge Cases couvrent les cas réels. Le GDD se compare favorablement aux autres GDDs du projet en termes de complétude.

**Pré-conditions pour r2 APPROVED — toutes résolues 2026-04-23** :
- [x] ~~`KATANA_REACH` ajouté au registry `referenced_by`~~ INVALIDATED — déjà présent
- [x] `room_entered(room_index: int, total_rooms: int)` ajouté à l'interface GDScript provisoire §Dependencies + 5 autres lookups spatiaux (BLOCKING-2) — signature verrouillée documentée
- [x] AC-LVL-51 ajoutée — invariant spacing checkpoints `floor(N_rooms / K) ∈ [2, 3]` avec cas limites (K=0, K=1, K=N) + lint `tools/lint/level_lint.gd` (BLOCKING-3)
- [x] `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }` défini en tête de §States and Transitions avec contrat d'introspection verrouillé (MAJOR-3)
- [x] `last_valid_position` défini précisément dans EC-1 — sampling `_physics_process` intra-WorldBoundsVolume, fallback `PlayerStart`, usage télémetrie-only (pas position de respawn) (MAJOR-4)

**Addendum Godot 4.6 — toutes résolues 2026-04-23** :
- [x] `NavigationRegion3D` bake editor-only documenté dans §Dependencies Downstream (contrat Enemy System) + §Notes de réciprocité (Tech-Risk-1)
- [x] `SHADER_BAKER_ENABLED` ajouté §Tuning Knobs runtime avec instructions Project Settings + précompilation boot global (Tech-Risk-2)
- [x] `BoxShape3D` imposé dans R-1 hierarchy + R-5.6 nouveau avec rationale Jolt broad-phase (Tech-Risk-3)
- [x] OQ-1 fermée inline "CLOSED 2026-04-23" avec 3 faits Godot 4.6 documentés + condition de réouverture Tier 2+
- [x] OQ-5 fermée inline "CLOSED 2026-04-23" avec route d'activation `AudioServer.set_bus_volume_db()` documentée

**GDD passé de 923 → 1155 lignes (+232 lignes de revisions r2 ciblées).**

**Statut post-revision** : tous BLOCKINGs résolus. MAJOR-1 et MAJOR-2 restent ouverts (non-bloquants pour démarrage code Sprint 1 — précisions de test / ownership négociable côté Checkpoint System GDD futur). MINORs et POLISH pas touchés dans ce passage ciblé.

**Revision r2 status : DONE. GDD APPROVED pour démarrage implementation.**

Les items MAJOR-1 et MAJOR-2 peuvent être résolus en parallèle de l'implémentation Sprint 1 — ils n'ont pas besoin de bloquer le démarrage du code si le lead-programmer a conscience des ambiguïtés.

Le système peut démarrer son implémentation après résolution des 3 BLOCKINGs + MAJOR-3 + MAJOR-4. Les MAJOR-1 et MAJOR-2 sont des précisions de test qui n'affectent pas le code de production lui-même.
