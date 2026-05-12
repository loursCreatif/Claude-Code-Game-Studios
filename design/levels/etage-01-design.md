# Etage 01 — Design Spec (Chrome Ascent)

> **Status** : Draft v1 — prêt à implémenter  
> **Fichier cible** : `res://scenes/levels/etage_01.tscn`  
> **Référence ADR** : ADR-0011 (hiérarchie canonique, 11 invariants), ADR-0008 (collision layers)  
> **Référence GDD** : `design/gdd/level-system.md` r4  
> **Created** : 2026-05-11  

---

## 1. Concept

### Intent onboarding

L'étage 1 est le seul étage à posséder un contrat d'onboarding explicite (ADR-0011 D-7 invariant 9, Level GDD CO-1/CO-2/CO-3). Son rôle est d'enseigner sans texte : le mouvement de base (course, saut), puis le dash, puis le premier contact ennemi, puis l'escalade verticale — dans cet ordre. Chaque salle fait une chose.

Le joueur n'a aucune upgrade active au départ. Il découvre la Chrome Spire vide, désertée mais hostile dans sa géométrie. Le premier ennemi est optionnel à voir depuis une zone safe — le joueur peut choisir de passer ou d'expérimenter le katana.

### Narrative beat (environnemental uniquement — aucun texte ni dialogue)

La Chrome Spire est un couloir corporate abandonné : surfaces chromées, lumières de secours, aucune trace d'occupation. Impression : tu n'es pas attendu ici. La Spire ne s'ouvre pas pour toi — elle te contraint, tu forces. Le Secret Hub (Room_07) laisse entrevoir un espace plus large, partiellement condamné, avec une lueur cyan visible depuis le bas du shaft — la promesse d'un crédit inaccessible sans upgrade.

### Temps de jeu estimé

| Profil joueur | Temps nominal |
|---|---|
| Novice (découverte, morts incluses) | 12-20 min |
| Joueur expérimenté (premier run) | 6-10 min |
| Speedrun (post-maîtrise) | 2-4 min |

---

## 2. Room Map (9 rooms)

N_rooms = 9. Espacement checkpoint floor(9/3) = 3. Checkpoints après rooms 03, 06, 09.

| Room ID | Archetype | Primitive(s) | Position approx. (X, Y, Z) m | Rôle gameplay | Notes onboarding étage 1 |
|---|---|---|---|---|---|
| Room_01 | TRAVERSAL (0) | Aucune (géométrie custom : corridor 4×4×10 m) | (0, 0, 0) | Spawn initial — course et saut de base | PlayerStart ici. Couloir droit, hauteur 4 m. Aucun ennemi. Porte de sortie visible dès l'entrée (guidage sightline). |
| Room_02 | TRAVERSAL (0) | 1× mezzanine | (0, 1.5, 12) | Introduction saut + ledge — mezzanine à franchir | Mezzanine_01 en milieu de salle, hauteur plate-forme 1.5 m. Donne accès à la porte suivante. Aucun ennemi. Prouve au joueur qu'il peut sauter sur les plates-formes. |
| Room_03 | COMBAT (1) | 1× mezzanine | (0, 2, 24) | First enemy — contrat onboarding CO-1 | FirstEnemySightline ici. SafeZoneCenter ici. EnemySlot_01. Mezzanine_02 comme couverture latérale (valide la safe zone). Checkpoint_01 juste avant cette salle (AnchorCP_01 en Room_02 exit). |
| Room_04 | TRAVERSAL (0) | 1× shaft_connector | (0, 4, 36) | Intro wall-run — deux murs face-à-face, 4 m hauteur | ShaftConnector_01 : 2 murs verticaux face-à-face ≥ 4 m. Le joueur doit bouncer entre les deux pour franchir un gap horizontal. Aucun ennemi. |
| Room_05 | COMBAT (1) | 1× mezzanine | (0, 5, 48) | Combat 2 ennemis — mezzanine comme terrain tactique | EnemySlot_02, EnemySlot_03. Mezzanine_03 centrale. Le joueur apprend à positionner le dash avant l'attaque. |
| Room_06 | SHAFT (2) | 1× vertical_shaft_room | (0, 6, 58) | Ascension verticale — puits 10 m, 2 wall-run levels | VerticalShaftRoom_01 : rise 10 m (murs 10 m hauteur, floor y=6, sommet y=16). SecretLureMarker_01 visible depuis le bas (secret au sommet, required_ability=wall_run). Checkpoint_02 au pied du shaft. |
| Room_07 | SECRET_HUB (3) | 1× atrium + 1× mezzanine | (0, 16, 64) | Carrefour — secret visible cross-room, route principale et déviation | Atrium_01 (espace vertical 6 m, 2 wall-run guides). Mezzanine_04 à mi-hauteur comme chemin nominal. SecretCollectVolume_01 au sommet de l'atrium. SecretAnchor_01 adjacent. EnemySlot_04 sur plateforme basse. SecretLureMarker_02 visible depuis Room_06 (required_ability=dash). |
| Room_08 | TRAVERSAL (0) | 1× shaft_connector | (0, 17, 76) | Transition courte — dernier mur à wall-run avant sortie | ShaftConnector_02. 0 ennemi. Couloir étroit 4 m large. |
| Room_09 | TRAVERSAL (0) | Aucune (géométrie custom : salle terminale 6×6×4 m) | (0, 17, 86) | Salle finale — EtageExitTrigger | Aucun ennemi. Checkpoint_03 à l'entrée. EtageExitTrigger au fond (Z ≈ +92 depuis origin étage). Plafond 4 m. Sightline directe vers la sortie depuis l'entrée. |

**Note primitive manquante** : aucune primitive n'existe pour un corridor Traversal nu (Room_01, Room_09) ni pour une arène Combat sans primitive composée (Room_03 nécessite des murs wall-run customs). Ces rooms devront être construites manuellement avec StaticBody3D + CollisionShape3D Floor/Wall/Ramp inline dans le fichier `.tscn`. Le programmer devra créer la géométrie custom pour Room_01, Room_03 (murs wall-run ≥ 4 m × ≥ 3 m, Rule R-2.U.2), et Room_09.

**Contrainte ADR-0008** : toute la géométrie statique utilise `set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)` (layer 4). Aucun bitmask littéral en GDScript.

---

## 3. Checkpoints

Espacement = floor(9/3) = 3. Valeur K=3 ∈ [2, 3] — conforme AC-LVL-51.

| ID | Type | Position Volume (Area3D) | Position Anchor (Marker3D) | Distance vol-anchor | Salle associée |
|---|---|---|---|---|---|
| Checkpoint_01 | CheckpointVolume_01 | (0, 1.8, 23) — corridor avant Room_03 | (0, 2.2, 22) — CheckpointAnchor_01 | ≈ 1.4 m | Avant Room_03 (combat onboarding) |
| Checkpoint_02 | CheckpointVolume_02 | (0, 6.2, 58) — entrée Room_06 (pied du shaft) | (0, 6.5, 57) — CheckpointAnchor_02 | ≈ 1.4 m | Avant Room_06 (shaft) |
| Checkpoint_03 | CheckpointVolume_03 | (0, 17.2, 86) — entrée Room_09 | (0, 17.5, 85) — CheckpointAnchor_03 | ≈ 1.4 m | Avant Room_09 (salle finale) |

Distances volume-anchor toutes ≤ 10 m. Conforme invariant #5 (AC-LVL-19).

Nommage zero-padded `_01/_02/_03` : conforme R-5.2.

---

## 4. Onboarding Anchors (étage 1 uniquement)

Sous-arbre `OnboardingAnchors` requis uniquement pour `etage_01.tscn` (ADR-0011 D-2, Level GDD R-1 r2, CO-1).

### FirstEnemySightline

- **Position** : (0, 2, 30) — centre de Room_03, 6 m en avant de la porte d'entrée
- **Distance depuis PlayerStart** : PlayerStart à (0, 0.1, 1). Distance ≈ 29 m.

> **Risque** : 29 m dépasse la contrainte de 15 m (AC-LVL-54, invariant #9). Correction : placer PlayerStart dans Room_02 à (0, 1.5, 13) et FirstEnemySightline à (0, 2, 28), distance ≈ 15 m. Ou placer le grunt visible depuis l'ouverture de Room_02 à (0, 2, 24), distance depuis spawn ≈ 23 m via couloir — toujours trop long.

**Décision recommandée** : réduire Room_01 à 6 m de profondeur et Room_02 à 6 m, placement PlayerStart à (0, 0.1, 1), FirstEnemySightline à (0, 2, 14) dans Room_03 (distance ≈ 13 m — conforme). Cela compresse le couloir d'approche mais maintient la lisibilité. Le programmer doit ajuster les positions Z des rooms 01 et 02 en conséquence (room_02 origin Z ≈ 8 au lieu de 12, room_03 origin Z ≈ 14 au lieu de 24). Voir Note Position Corrigée ci-dessous.

### Positions Z corrigées (variante contrainte ≤ 15 m)

| Room ID | Origin (X, Y, Z) corrigé | Delta Z cumulatif |
|---|---|---|
| Room_01 | (0, 0, 0) — 6 m profondeur | 0-6 |
| Room_02 | (0, 1.5, 8) — 6 m profondeur | 8-14 |
| Room_03 | (0, 2, 14) | début à Z=14 |
| Room_04 | (0, 4, 26) | |
| Room_05 | (0, 5, 38) | |
| Room_06 | (0, 6, 48) | |
| Room_07 | (0, 16, 58) | |
| Room_08 | (0, 17, 68) | |
| Room_09 | (0, 17, 78) | |
| EtageExitTrigger | (0, 17, 84) | |

**FirstEnemySightline** (corrigé) : (0, 2, 18) dans Room_03. Distance depuis PlayerStart (0, 0.1, 1) ≈ 17 m — encore légèrement au-dessus de 15 m. Ajustement final : PlayerStart à (0, 0.1, 2), FirstEnemySightline à (0, 2, 16) → distance = 14 m. Conforme.

**Sightline libre** : aucun obstacle entre PlayerStart et FirstEnemySightline — couloir droit Room_01 + porte ouverte Room_02 = ligne de vue dégagée. Conforme invariant #9 (`sightline_trace()` raycast doit passer). Le lint `validate_onboarding_anchors()` vérifiera ce raycast.

### SafeZoneCenter

- **Position** : (0, 2, 18) dans Room_03, coin gauche de la salle (opposé à EnemySlot_01)
- **Distance vers EnemySlot_01** : EnemySlot_01 à (2, 2, 22) → distance ≈ 4.5 m

> **Risque** : 4.5 m < 6 m requis (AC-LVL-54). Correction : placer SafeZoneCenter à (-3, 2, 15) et EnemySlot_01 à (2, 2, 22) → distance ≈ 7.1 m. Conforme.

**SafeZoneCenter final** : (-3, 2, 15). Distance vers EnemySlot_01 (2, 2, 22) = 8.6 m. Conforme ≥ 6 m.
**HazardSlot_01** absent de Room_03 (onboarding sans hazard) → contrainte ≥ 4 m de HazardSlot non applicable ici.

---

## 5. WorldBoundsVolume

Nœud : `Area3D` nommé `WorldBoundsVolume`, sous `InteractiveVolumes`. Shape : **`BoxShape3D`** obligatoire (ADR-0011 REQ-9, R-5.6 — jamais ConcavePolygonShape3D).

L'étage monte de Y=0 (sol Room_01) à Y≈17 m (sol Room_09) + 10 m de shaft (Room_06 peak Y=16), avec marge de 5 m de chaque côté.

| Paramètre | Valeur |
|---|---|
| Centre (local) | (0, 8, 42) |
| Taille BoxShape3D (x, y, z) | (30, 40, 100) |
| Borne X | -15 à +15 m (corridor 4-15 m large, marge 5 m) |
| Borne Y | -2 à +38 m (plancher Y=-2 conforme R-2.U.3 → bound bas, sommet shaft +16 + marge 5 m) |
| Borne Z | -5 à +95 m (de l'entrée à la sortie + 5 m de marge) |

`monitorable = false`, `monitoring = true`. Déclenche `player_out_of_world` sur `body_exited`.

---

## 6. EtageExitTrigger

- **Type** : Area3D, nommé `EtageExitTrigger`
- **Position** : (0, 17, 84) — fond de Room_09, 6 m au-delà de l'entrée de la salle finale
- **Shape** : BoxShape3D, taille (6, 3, 1) — largeur = largeur salle (6 m), hauteur 3 m, profondeur 1 m
- **Flag fires-once** : `_exit_fired: bool` côté LevelSystem (ADR-0011 D-5, AC-LVL-24)
- **Placement authoring** : nœud top-level direct de `etage_01.tscn`, hors `InteractiveVolumes` (conforme D-2 — EtageExitTrigger est un 5e groupe top-level)

---

## 7. Diversité Archetype — Conformité S-1..S-5

| Règle | Vérification | Résultat |
|---|---|---|
| S-1 : ≥ 3 archetypes distincts | TRAVERSAL (0), COMBAT (1), SHAFT (2), SECRET_HUB (3) = 4 archetypes | PASS |
| S-2 : jamais 2 COMBAT consécutifs | Room_03=COMBAT, Room_04=TRAVERSAL, Room_05=COMBAT — séparation par Room_04 | PASS |
| S-3 : ≥ 1 SHAFT | Room_06=SHAFT | PASS |
| S-4 : salle finale ∈ {SECRET_HUB, TRAVERSAL} | Room_09=TRAVERSAL | PASS |
| S-5 : ≥ 1 SECRET_HUB | Room_07=SECRET_HUB | PASS |

Séquence archétypes : TRAVERSAL → TRAVERSAL → COMBAT → TRAVERSAL → COMBAT → SHAFT → SECRET_HUB → TRAVERSAL → TRAVERSAL. Aucune paire COMBAT-COMBAT adjacente.

---

## 8. Budget Draw Calls Total

| Room | Archetype | DC room (max par archetype) |
|---|---|---|
| Room_01 | TRAVERSAL | 22 |
| Room_02 | TRAVERSAL | 22 |
| Room_03 | COMBAT | 38 |
| Room_04 | TRAVERSAL | 22 |
| Room_05 | COMBAT | 38 |
| Room_06 | SHAFT | 32 |
| Room_07 | SECRET_HUB | 34 |
| Room_08 | TRAVERSAL | 22 |
| Room_09 | TRAVERSAL | 22 |
| **Sous-total salles** | | **252** |
| LEVEL_OVERHEAD (skybox + fog + global shaders) | | **20** |
| **Total** | | **272** |

**272 DC ≤ 350** — conforme F2 et AC-LVL-31. Marge de 78 DC disponible si le programmer ajoute de la géométrie custom dans les rooms Traversal ou Combat.

Note : la formule F2 du GDD utilise LEVEL_OVERHEAD = 50 dans son exemple de calibration, mais ce chiffre intègre skybox + volumetric fog + shader global dans une scène full-polish. Pour le MVP placeholder Chrome Zen sans fog, l'overhead réel est estimé à 20. Si le programmer active le fog volumétrique, le LEVEL_OVERHEAD monte à 50, portant le total à 302 DC — toujours conforme ≤ 350.

---

## 9. Hiérarchie Canonique (ADR-0011 D-2)

Structure attendue de `etage_01.tscn` :

```
etage_01.tscn (Node3D — racine)
├── StaticEnvironment  (Node3D — layer LAYER_ENVIRONMENT=4)
│   ├── Room_01  (Node3D, @export archetype = TRAVERSAL)
│   │   ├── Floor_01   (StaticBody3D + CollisionShape3D)
│   │   ├── Wall_01..4 (StaticBody3D + CollisionShape3D)
│   │   └── [aucune primitive]
│   ├── Room_02  (Node3D, @export archetype = TRAVERSAL)
│   │   ├── Floor_02, Wall_02..N  (StaticBody3D custom)
│   │   └── Primitives/
│   │       └── Mezzanine_01  (inline PackedScene — primitive mezzanine)
│   ├── Room_03  (Node3D, @export archetype = COMBAT)
│   │   ├── Floor_03, Wall_03..N, WallRunWall_01, WallRunWall_02  (custom, hauteur ≥ 4 m, longueur ≥ 3 m)
│   │   └── Primitives/
│   │       └── Mezzanine_02  (inline PackedScene)
│   ├── Room_04  (Node3D, @export archetype = TRAVERSAL)
│   │   └── Primitives/
│   │       └── ShaftConnector_01  (inline PackedScene)
│   ├── Room_05  (Node3D, @export archetype = COMBAT)
│   │   ├── Floor_05, Wall_05..N, WallRunWall_03, WallRunWall_04  (custom, ≥ 2 murs wall-run)
│   │   └── Primitives/
│   │       └── Mezzanine_03  (inline PackedScene)
│   ├── Room_06  (Node3D, @export archetype = SHAFT)
│   │   └── Primitives/
│   │       └── VerticalShaftRoom_01  (inline PackedScene — nommage "VerticalShaftRoom_01" obligatoire pour lint AC-LVL-55)
│   ├── Room_07  (Node3D, @export archetype = SECRET_HUB)
│   │   └── Primitives/
│   │       ├── Atrium_01    (inline PackedScene)
│   │       └── Mezzanine_04 (inline PackedScene)
│   ├── Room_08  (Node3D, @export archetype = TRAVERSAL)
│   │   └── Primitives/
│   │       └── ShaftConnector_02  (inline PackedScene)
│   ├── Room_09  (Node3D, @export archetype = TRAVERSAL)
│   │   └── Floor_09, Wall_09..N  (custom)
│   └── NavigationRegion3D  (baked authoring-time — ne pas rebake runtime)
│
├── InteractiveVolumes  (Node3D — layer LAYER_INTERACTIVE=5, monitorable=false, monitoring=true)
│   ├── RoomTrigger_01..09          (Area3D × 9 — un par salle)
│   ├── CheckpointVolume_01         (Area3D — entrée Room_03)
│   ├── CheckpointVolume_02         (Area3D — entrée Room_06)
│   ├── CheckpointVolume_03         (Area3D — entrée Room_09)
│   ├── SecretCollectVolume_01      (Area3D — sommet Room_06 shaft, y≈16)
│   ├── SecretCollectVolume_02      (Area3D — sommet Atrium Room_07, y≈22)
│   └── WorldBoundsVolume           (Area3D + BoxShape3D — centre (0,8,42), size (30,40,100))
│
├── SpawnMarkers  (Node3D)
│   ├── PlayerStart                 (Marker3D — position (0, 0.1, 2) — unique)
│   ├── EnemySlot_01                (Marker3D — (2, 2, 22) — Room_03 grunt onboarding)
│   ├── EnemySlot_02                (Marker3D — (-2, 5, 42) — Room_05)
│   ├── EnemySlot_03                (Marker3D — (2, 5, 44) — Room_05)
│   ├── EnemySlot_04                (Marker3D — (0, 16.5, 62) — Room_07 plateforme basse)
│   ├── CheckpointAnchor_01         (Marker3D — (0, 2.2, 13))
│   ├── CheckpointAnchor_02         (Marker3D — (0, 6.5, 47))
│   ├── CheckpointAnchor_03         (Marker3D — (0, 17.5, 77))
│   ├── SecretLureMarker_01         (Marker3D — (0, 16, 52) — sommet shaft, @export required_ability = "wall_run")
│   ├── SecretLureMarker_02         (Marker3D — (3, 21, 60) — haut atrium, @export required_ability = "dash")
│   ├── SecretAnchor_01             (Marker3D — (0, 16.2, 53) — adjacent SecretCollectVolume_01)
│   └── SecretAnchor_02             (Marker3D — (3, 21.2, 61) — adjacent SecretCollectVolume_02)
│
├── OnboardingAnchors  (Node3D — étage 1 uniquement, ADR-0011 D-2)
│   ├── FirstEnemySightline         (Marker3D — (0, 2, 16) — sightline libre depuis PlayerStart, distance ≈ 14 m)
│   └── SafeZoneCenter              (Marker3D — (-3, 2, 15) — ≥ 6 m de EnemySlot_01, aucun HazardSlot dans Room_03)
│
└── EtageExitTrigger  (Area3D — (0, 17, 84), BoxShape3D size (6,3,1))
```

---

## 10. Secrets — Tuples Complets

Deux secrets. Conforme contrainte économique : ≥ 1 `required_ability ∈ {wall_run, wall_run_long}` (Level GDD AC-LVL-46).

| Index NN | LureMarker position | CollectVolume position | ContentAnchor position | required_ability | Archetype salle |
|---|---|---|---|---|---|
| 01 | (0, 16, 52) — visible depuis bas Room_06 | (0, 16, 53) — sommet shaft VerticalShaftRoom_01 | (0, 16.2, 53) | `wall_run` | SHAFT |
| 02 | (3, 21, 60) — visible depuis Room_07 + Room_06 | (3, 21, 61) — sommet Atrium_01 Room_07 | (3, 21.2, 61) | `dash` | SECRET_HUB |

Secret_01 : accessible après achat upgrade `wall_run` (shop inter-étage). Le joueur voit la lueur cyan depuis le bas du shaft au premier run — prototypique de la Player Fantasy "puits qui nargue".

Secret_02 : accessible après achat upgrade `dash`. Visible depuis Room_07 en arrivant depuis Room_06.

---

## 11. Risques et Open Questions

### Risque 1 — Géométrie custom manquante (BLOCKING)

Les primitives existantes (`atrium`, `mezzanine`, `shaft_connector`, `vertical_shaft_room`) ne couvrent pas tous les besoins :

- **Room_01** (TRAVERSAL pur) : pas de primitive corridor. Géométrie custom obligatoire : Floor + 2 murs latéraux + plafond, dimensions 4×4×6 m. StaticBody3D custom.
- **Room_03** (COMBAT onboarding) : les murs wall-run requis par R-2.U.2 (≥ 4 m hauteur, ≥ 3 m longueur) ne sont pas fournis par la primitive mezzanine. Le programmer doit ajouter 2 StaticBody3D custom `WallRunWall_01/02` dans Room_03, positionnés ≥ 6 m de EnemySlot_01 pour ne pas violer les contraintes SafeZone.
- **Room_05** (COMBAT) : même besoin que Room_03. ≥ 2 murs wall-run custom obligatoires (invariant #2 AC-LVL-15).
- **Room_09** (TRAVERSAL terminale) : corridor d'arrivée custom, aucune primitive utile ici.

### Risque 2 — Positions Z non vérifiées par lint

Le lint `level_lint.gd` vérifie les invariants structurels (archetype, budgets, tuples secrets) mais pas la cohérence spatiale globale (rooms qui se chevauchent ou laissent des gaps). Le programmer doit s'assurer manuellement que les extents des rooms adjacentes sont contigus et non-superposés. Recommandation : utiliser des `BoxShape3D` de dimensions exactes pour chaque Floor et vérifier visuellement dans l'éditeur Godot.

### Risque 3 — Bug collision layer dans les primitives (BLOCKING — à corriger avant implémentation)

**Bug authoring confirmé** : les 4 primitives existantes ont `collision_layer = 2` dans leurs fichiers `.tscn`. Or, selon ADR-0008 D-1, `LAYER_ENVIRONMENT = layer 4 (1-indexé) = bitmask 0b01000 = 8` en décimal. La valeur `2` décimal correspond à `LAYER_ENEMY` (layer 2). La géométrie statique de l'étage sera sur la mauvaise layer : le joueur ne pourra pas marcher dessus (son mask inclut layer 4, pas layer 2).

**Correction requise** : les 4 fichiers primitives doivent être corrigés pour `collision_layer = 8` (bitmask décimal LAYER_ENVIRONMENT correct pour sérialisation `.tscn`). Cette correction est hors scope du design spec mais est un prérequis bloquant pour que l'étage soit jouable. Le lint `lint-collision-layers` CI (ADR-0008 D-6) vérifie les `.tscn` en WARN seulement au MVP (layers 6+), donc ce bug peut silencieusement passer le CI mais casse le gameplay.

Les commentaires dans les primitives mentionnent "layer 2, décimal 2 — sérialisation éditeur OK per ADR-0008" mais c'est incorrect. ADR-0008 D-1 : LAYER_ENVIRONMENT = layer 4 = bit 3 (0-indexé) = bitmask 8 décimal. Layer 2 = LAYER_ENEMY.

Pour la géométrie custom ajoutée par le programmer, utiliser `set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)` en GDScript (API 1-indexée, jamais bitmask littéral — lint `collision-layer-api-1-indexed`).

### Risque 4 — FirstEnemySightline vs distance contrainte

La valeur 14 m calculée ci-dessus pour FirstEnemySightline est proche de la limite de 15 m. Si les corridors sont légèrement ajustés par le programmer, la distance peut dépasser 15 m et faire échouer le lint invariant #9. Recommandation : le programmer doit mesurer la distance dans l'éditeur Godot avec le gizmo de Marker3D après placement, et ajuster si nécessaire.

### Risque 5 — NavigationRegion3D

La scène doit contenir un `NavigationRegion3D` baked authoring-time sous `StaticEnvironment` (ADR-0011 REQ-11). Rebake interdit runtime. Le programmer doit bake le navmesh une fois la géométrie finale en place dans l'éditeur Godot, puis committer le `.tscn` avec le navmesh inclus.

### Risque 6 — Shader chrome_zen_flat absent

Les primitives ont un TODO story-022 : remplacer StandardMaterial3D par ShaderMaterial chrome_zen_flat. Au MVP, le placeholder est acceptable. Le programmer ne doit pas bloquer l'implémentation du `.tscn` sur la disponibilité du shader.

### Open Question 1 — Profondeur Room_03 exact

La Room_03 doit satisfaire simultanément : FirstEnemySightline ≤ 15 m, SafeZoneCenter ≥ 6 m de EnemySlot_01, ≥ 2 murs wall-run. Ces contraintes dans une salle COMBAT de 12×12 m (dimensions R-2.A) sont tenables mais le programmer doit les vérifier visuellement. Si la salle est trop petite pour les trois contraintes simultanées, augmenter à 14×14 m (dans la range admissible).

### Open Question 2 — Hauteur Room_07 (SECRET_HUB + Atrium)

L'Atrium primitive a un ceiling local à Y=4 m (transform Ceiling dans atrium.tscn : y=4.0). Pour placer SecretCollectVolume_02 à Y=21 m (sommet atrium Room_07 origin Y=16 + 5 m), il faut soit modifier la primitive (hors scope, requiert un amendement de la primitive), soit ajouter des murs supplémentaires custom au-dessus de l'Atrium pour simuler une hauteur de 5 m. L'alternative recommandée : PlaceSecretCollectVolume_02 à Y ≈ 20 m (Room_07 origin Y=16 + 4 m ceiling Atrium) = Y absolu ≈ 20 m. Ajuster SecretLureMarker_02 en conséquence.
