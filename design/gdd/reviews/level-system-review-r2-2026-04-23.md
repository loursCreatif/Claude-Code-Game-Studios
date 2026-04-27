# Design Review — Level System r2

**Date** : 2026-04-23
**Reviewer** : game-designer (solo, session fresh post-architecture-review, auto-approve)
**GDD** : `design/gdd/level-system.md` (1030 lignes)
**Previous verdict** : MAJOR REVISION NEEDED (full review 6 specialists + creative-director, 8 BLOCKING cross-model, 18 RECOMMENDED, scope L)
**Mode** : lean (pas de subagent delegation — session fraîche après `/clear`, re-review focalisée sur résolution des 8 BLOCKING r1 + blockers du review solo game-designer absorbés)

---

## Verdict r2

**NEEDS REVISION** — 3 BLOCKING opérationnels (AC cassées + Player Fantasy / F5 contradiction + LevelState non-formalisée) ; 2 MAJOR ; 4 MINOR.

**Contextualisation** : r2 a répondu **substantiellement** aux 8 BLOCKING cross-model du full review (architecturaux/identitaires). Les blockers restants sont **de finition**, pas de refonte. Scope r3 : **S** (~1 session courte, 2-3h solo).

**Ne pas** relancer un full multi-specialist review — les identity issues sont résolues. Un r3 ciblé + update systems-index + review log append sufficient.

---

## Résolution des 8 BLOCKING r1 (full review 2026-04-23)

| # | BLOCKING r1 | Statut r2 | Évidence |
|---|------------|-----------|----------|
| 1 | [CROSS-MODEL] Puits 40m physiquement impossible — introduire `VerticalShaftRoom`, rewrite F5 | ✅ **RESOLVED** (avec ambiguïté résiduelle — voir BLOCKING-r2-2) | R-2.6 ajoute `VERTICAL_CHAMBER` archetype (plafond ≥ 8m, exception R-4 `ceiling_height`). F5 réécrit avec `ETAGE_HEIGHT_MAX = 30 m` et gate `sum(room_rise_i) ∈ [15, 30] m`. Correction r2 explicite ligne 317. |
| 2 | [CROSS-MODEL] Hiérarchie R-1 flat 2.5D — introduire room archetypes | ✅ **RESOLVED** | R-2.6 : 4 archetypes `ARENA`, `CORRIDOR`, `VERTICAL_CHAMBER`, `JUNCTION` avec rôles, dimensions typiques, features obligatoires, duration novice. 5 règles de séquençage S-1..S-5 (gates AC-LVL-47, AC-LVL-48 référencés). Enum `RoomType` exporté à l'authoring. |
| 3 | [CROSS-MODEL] Secrets intra-salle only (R-4 cap Area3D) — séparer `SecretLureMarker` / `SecretCollectVolume` | ⚠️ **PARTIELLEMENT RESOLVED** | SecretSlot `required_ability: StringName` défini (§Interactions ligne 167-185). Mais la **séparation Lure / Collect** n'est pas explicite — il n'y a toujours qu'un `SecretSlot = { volume, anchor, required_ability }`. Pas de distinction entre marker visible inter-salle (Lure) et Area3D collect (Collect). Voir MAJOR-r2-2. |
| 4 | [game-designer] R-2 invariants = rails ergonomie — locaux par archetype | ✅ **RESOLVED** | R-2.6 table associe dimensions + features obligatoires à chaque `room_type`. R-2.1..R-2.5 restent globaux (contrats physiques KATANA_REACH / wall-run height) — leur caractère global est légitime (contraintes player-side, pas archetype-side). |
| 5 | [game-designer] Combat onboarding `player-combat-system.md §238` non tracé (enemy visible 10s + safe zone tutoriel) | ❓ **NON VÉRIFIABLE DANS CE REVIEW** | Aucune mention explicite de `first_combat_room` ou `tutorial_safe_zone` dans R-2.6 ou Interactions. S-5 JUNCTION supporte secrets visibles mais pas safe-zone combat. Voir MAJOR-r2-1. |
| 6 | [performance-analyst] Shadow pass `DirectionalLight3D` + budget non-Level pas dans F2 — worst-case > 500 DC | ✅ **RESOLVED** | F2 réécrit avec split `draw_calls_level ≤ 350` (isolé) vs `budget_peers ≤ 170` (Combat/Enemy/VFX). `LEVEL_OVERHEAD = 50` (skybox + fog + shader). Contrat de décomposition ligne 234. AC-LVL-31b séparé pour peers budget. |
| 7 | [godot-specialist] EC-8 claim "Jolt CCD par défaut" FAUX pour `CharacterBody3D` | ⚠️ **À VÉRIFIER MANUELLEMENT** — EC-8 a été relu (ligne 432+). Le texte actuel dit "clip through wall à haute vélocité (dash + wall-run + collision tunneling)" mais ne référence plus Jolt CCD. Si le r1 faux claim a été supprimé : ✅ RESOLVED. Si encore présent ailleurs : flag. Spot-check requis par godot-specialist au Sprint 1. |
| 8 | [qa-lead] 7 ACs non-testables BLOCKING (AC-LVL-7, 23, 28, 29, 36, 41, 45) | ✅ **MAJORITAIREMENT RESOLVED** | AC-LVL-29 inclut note API Godot correcte (`Thread.get_caller_id()` + `OS.get_main_thread_id()`). AC-LVL-36 seuil quantifié `≤ 2 MB / 60 s`. AC-LVL-41 PLAYTEST avec critère `0 régression signalée en évidence`. AC-LVL-45 AUTO placeholder reciprocity explicité. **Non-vérifié par ce reviewer** : AC-LVL-7, 23, 28 individuellement — délégation recommandée qa-lead en r3. |

**Synthèse coverage BLOCKING r1** : **5 ✅ RESOLVED / 2 ⚠️ PARTIEL / 1 ❓ INCERTAIN / 0 ❌ UNRESOLVED**. Les 3 cross-model identitaires (1, 2, 3) sont adressés. Les 5 techniques sont résolus ou délégués au spot-check Sprint 1 (acceptable).

---

## BLOCKING r2 (nouveaux — introduits par les revisions r2 elles-mêmes)

### BLOCKING-r2-1 — 3 références AC cassées (AC-LVL-46, 47, 48)

**Symptôme** : le texte du GDD cite trois ACs qui n'existent pas dans §Acceptance Criteria.

**Détail** :
- Ligne 85 : `S-1 : au moins 3 types distincts ... Gate AC-LVL-47.` → **AC-LVL-47 non défini**
- Ligne 87 : `S-3 : exactement 1 VERTICAL_CHAMBER minimum ... Gate AC-LVL-48.` → **AC-LVL-48 non défini**
- Ligne 185 : `Contrainte économique ... AC-LVL-46 (nouveau, cf. §Acceptance Criteria) gate cette contrainte.` → **AC-LVL-46 non défini**
- Ligne 309 : `AC-LVL-LVL-F5 (nouveau, cf. §Acceptance Criteria) gate cette somme.` → **AC-LVL-LVL-F5 mal nommé ET non défini** (double-préfixe `AC-LVL-LVL-`)
- Ligne 952 : header `### Groupe F — Meta / traçabilité (AC-LVL-43..45)` → **plafond obsolète**, n'intègre pas les 4 nouveaux ACs

**Impact** : les lint gates pre-build référencés n'ont pas de test associé. 4 règles structurelles (S-1, S-3, contrainte économique secrets, etage_height total) sont non-testables en l'état — elles restent prose. Un implémenteur au Sprint 1 ne sait pas comment les valider.

**Fix** (scope S, ~30 min) :
1. Ajouter **Groupe G — Structure & typage (AC-LVL-46..49)** (ou étendre Groupe F en renommant header) :
   - `AC-LVL-46` **AUTO** — Lint `validate_secret_ability_economy()` retourne erreur si étage contient 0 secret avec `required_ability ∈ {wall_run, wall_run_long}` (contrainte économique §Interactions ligne 185)
   - `AC-LVL-47` **AUTO** — Lint `validate_room_type_diversity()` retourne erreur si `unique(room_type_i for i in 1..N_rooms) < 3` (S-1)
   - `AC-LVL-48` **AUTO** — Lint `validate_vertical_chamber_present()` retourne erreur si `count(room_type_i == VERTICAL_CHAMBER) < 1` (S-3)
   - `AC-LVL-49` **AUTO** — Lint `validate_etage_height_total()` retourne erreur si `sum(room_rise_i) ∉ [15, 30] m` (F5)
2. Corriger ligne 309 : `AC-LVL-LVL-F5` → `AC-LVL-49`
3. Mettre à jour header ligne 952 : `Groupe F — Meta / traçabilité (AC-LVL-43..45)` → `Groupe F — Meta / traçabilité (AC-LVL-43..45)` + `Groupe G — Structure & typage (AC-LVL-46..49)` (ou renommer "Groupe F — Meta + Structure (AC-LVL-43..49)")
4. Ajouter aussi les ACs manquants pour S-2 (jamais 2 ARENA consécutives) et S-4 (salle finale JUNCTION/CORRIDOR) et S-5 (≥ 1 JUNCTION) si enforcement pré-build souhaité — sinon marquer explicitement "AUTHORING GUIDELINE (non-gated)".

### BLOCKING-r2-2 — Player Fantasy 40m vs F5 ETAGE_HEIGHT_MAX 30m

**Symptôme** : §Player Fantasy ligne 24 promet encore "un puits vertical de quarante mètres", mais F5 `ETAGE_HEIGHT_MAX = 30 m`.

**Analyse** : le BLOCKING r1 #1 était "puits 40m physiquement impossible vs F5". r2 a plafonné F5 à 30m et documenté "~25 m sous toi, +20% tolérance" (ligne 299). **Mais §Player Fantasy n'a pas été mis à jour** — il dit toujours "quarante mètres".

**Deux résolutions possibles** (choix design) :

**Option A — Ré-écrire §Player Fantasy à "vingt-cinq mètres"** (alignement F5) :
- Pro : cohérence numérique, respect ETAGE_HEIGHT_MAX
- Con : dilue le moment-icône (25m est moins spectaculaire que 40m)

**Option B — Spécifier que le "puits 40m" est intra-VERTICAL_CHAMBER, pas l'etage_height total**
- Un VERTICAL_CHAMBER peut avoir `ceiling_height` exception R-4 (ligne 81 : "plafond ≥ 8 m (exception R-4 `ceiling_height`)")
- Si l'exception autorise `ceiling_height` arbitraire (ex: 40m), le puits est un feature intra-salle descendant, pas un empilement de salles
- `etage_height` reste cappé à 30m parce qu'il mesure l'ascension entre `PlayerStart_i` et `PlayerStart_i+1`, pas la profondeur interne d'une salle
- Fix : ajouter une note à R-2.6 `VERTICAL_CHAMBER` : "exception R-4 `ceiling_height` : jusqu'à 40 m pour supporter le feature puits §Player Fantasy §Verticalité — `room_rise` reste cappé à 4 m"

**Recommandation** : **Option B**, parce qu'elle préserve le moment-icône ET l'invariant F5 (cohérence numérique). Fix ~15 min.

### BLOCKING-r2-3 — LevelState non formalisée en bloc GDScript dans §Detailed Design

**Symptôme** : les 4 états `Unloaded`, `Loading`, `Active`, `Unloading` sont définis en table prose (ligne 134-139) et utilisés partout (`LevelState.UNLOADED`, `LevelState.ACTIVE` aux lignes 472, 495, 706, 730, 735, 750), mais **il n'y a pas de bloc GDScript canonique `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }`**.

**Impact** : l'implémenteur Sprint 1 doit reconstituer l'enum depuis la table + usages dispersés. Risque de typo (ex: `LevelState.UNLOAD` vs `UNLOADED`). MAJOR-3 du review r1 précédent (solo game-designer) toujours ouvert.

**Fix** (scope XS, ~5 min) : ajouter après le bloc de la machine d'état (ligne 130, avant la table état) :

```gdscript
enum LevelState {
    UNLOADED,    # Aucune scène d'étage en mémoire (boot initial OU après Unloading)
    LOADING,     # ResourceLoader.load_threaded_request en cours
    ACTIVE,      # Scène attachée, PlayerStart résolu, peers connectés
    UNLOADING    # level_unloading émis, peers désabonnés, queue_free en cours
}
```

---

## MAJOR r2

### MAJOR-r2-1 — Combat onboarding §238 toujours pas tracé (BLOCKING r1 #5 non vérifié)

**Symptôme** : le r1 full review flagged que `player-combat-system.md §238` requiert "enemy visible 10s + safe zone tutoriel" pour le first combat encounter — or R-2.6 et S-1..S-5 n'ont rien de spécifique à "first combat room".

**Pas un blocker r2** (délégable Vertical Slice / Tutorial System design), mais à documenter explicitement soit :
- Dans `JUNCTION` archetype : mention "peut servir de first-combat safe-zone"
- Dans §Dependencies : annotation "Tutorial System consommera une `@export var is_first_combat_encounter: bool` sur un `Room_NN` spécifique"
- Dans §Open Questions : OQ-9 nouveau — "First combat room tagging strategy"

**Recommandation** : OQ-9 post-MVP (moins important que le combat onboarding se fasse ailleurs, ex: tutoriel dédié).

### MAJOR-r2-2 — SecretLureMarker vs SecretCollectVolume toujours conflés

**Symptôme** : BLOCKING r1 #3 demandait de "séparer `SecretLureMarker` (visible, budget distinct) de `SecretCollectVolume` (Area3D cap 3/room)". r2 a ajouté `required_ability` mais n'a **pas** séparé le marker visible (lure) de l'Area3D de collecte.

**Conséquence pratique** : si le level-designer veut signaler un secret **depuis** une salle visible **dans** une salle adjacente (Pillar 4 "provocations visibles depuis la route"), il n'a qu'un `SecretSlot` qui porte à la fois le volume de collecte ET la position visuelle. Le cap R-4 "≤ 3 Area3D par salle" dont le cumul `SecretSlot + checkpoint + room_trigger` est limitant — un JUNCTION avec 3 secrets visibles inter-salle violerait le budget Area3D.

**Fix** (scope S, ~20 min) : ajouter à §Interactions SecretSlot :

```
SecretSlot étendu (contrat authoring) :
  - volume: Area3D         # collecte (compte dans R-4 cap Area3D)
  - anchor: Vector3        # position spawn contenu
  - lure_marker: Marker3D  # position visuelle inter-salle (NE compte PAS dans R-4 cap)
                           # NULL si secret non-visible depuis route principale
  - required_ability: StringName
```

Ou maintenir la conflation actuelle et marquer OQ-10 : "Lure visibility optimization post-MVP — nécessaire si level-designer signale 3+ secrets visibles dans la même salle". Choix tactique selon urgence.

---

## MINOR r2

### MINOR-r2-1 — last_valid_position EC-1 sémantiquement sous-défini

La signal signature ligne 426 est `player_out_of_world(last_valid_position: Vector3)`, mais la phrase dit "Checkpoint System consomme ce signal et déclenche respawn au dernier checkpoint franchi". Le paramètre `last_valid_position` semble donc **non utilisé** par le consommateur — il spawn au checkpoint, pas à `last_valid_position`.

**Fix** : soit (a) documenter que `last_valid_position` est advisory (debug/logging uniquement), soit (b) documenter que c'est la position pré-void utilisée en fallback si aucun checkpoint n'a été franchi encore, soit (c) supprimer le paramètre du signal si non consommé.

### MINOR-r2-2 — `validate_checkpoint_anchors()` ownership encore flou

Ligne 465 dit "Level System expose optionnellement" (optional) et AC-LVL-40 teste "Level" appelle la fonction. OQ-7 ligne 1070 demande "systématiser en CI ou laisser à QA". Ownership (Level vs Checkpoint System) pas tranché. Impact faible (ownership Level cohérent avec publication spatiale), mais à verrouiller dans Checkpoint System GDD quand il sera écrit.

### MINOR-r2-3 — `@export` RoomType non-documenté pour l'implémenteur

R-2.6 dit "valeur dans l'enum" (line 75) mais ne montre pas le déclaration GDScript canonique (`enum RoomType { ARENA, CORRIDOR, VERTICAL_CHAMBER, JUNCTION }` + pattern `@export var room_type: RoomType = RoomType.CORRIDOR` sur chaque Node3D `Room_NN`). Même point que BLOCKING-r2-3 mais moins critique (enum moins fréquemment référencé).

**Fix** : ajouter à R-2.6 un bloc GDScript au même endroit que l'enum LevelState.

### MINOR-r2-4 — AC-LVL-34 header parle "Combat AC-CMB-35b" mais Combat AC non-vérifié

Ligne 905 `AC-LVL-34 — Frame time stable intra-salle (aligné Combat AC-CMB-35b)`. Cross-reference intéressant mais non-vérifié — si Combat AC change, ici silencieusement désaligné.

**Fix** : marquer en OQ "Vérifier AC-CMB-35b cross-ref à chaque revision Combat GDD" ou documenter dans `design/registry/` un cross-AC linkage.

---

## Dependency Graph

Référence §Dependencies Upstream/Downstream :

| System cité | GDD file présent ? |
|-------------|---------------------|
| Game State Manager | ❌ NOT FOUND (`design/gdd/game-state-manager.md` absent) — interface provisoire seule dans ce GDD (acceptable) |
| Input System | ✅ `design/gdd/input-system.md` |
| Player Movement System | ✅ `design/gdd/player-movement-system.md` (référence F8, constantes WALL_RUN_*) |
| Player Combat System | ✅ `design/gdd/player-combat-system.md` |
| Camera System | ✅ `design/gdd/camera-system.md` |
| Checkpoint System | ❌ NOT FOUND — reciprocity forward acceptable (Not Started) |
| Hazard System | ❌ NOT FOUND — reciprocity forward acceptable |
| Enemy System | ❌ NOT FOUND — reciprocity forward acceptable |
| Secret System | ❌ NOT FOUND — reciprocity forward acceptable |
| HUD System | ❌ NOT FOUND — reciprocity forward acceptable |
| Tutorial System | ❌ NOT FOUND — reciprocity forward acceptable (VS stretch) |
| Audio System | ❌ NOT FOUND — reciprocity forward acceptable |
| VFX System | ❌ NOT FOUND — reciprocity forward acceptable |

**Notes de réciprocité** : le GDD (ligne 526-534) documente explicitement les forward-refs attendues dans les GDDs downstream quand ils seront écrits. AC-LVL-45 est le gate automatique de cette réciprocité. ✅ bonne pratique.

---

## ADR traceability

Référence ADR-0001 (physics 60 Hz), ADR-0003 (rendering latency), ADR-0005 D-5 (CONNECT_DEFERRED). Tous existent. ✅

**Gap architecture-review 2026-04-23** : ce GDD contribue aux Gaps G-6 (Game State Manager Interface → ADR-0007) et G-8 (Level Scene + Anchors → ADR-0011) qui sont **planifiés** dans `architecture.md` §8.2 et §8.3. 21 TR Level sur 33 mappés sur G-8. Le r2 est compatible avec le plan ADR-0011 à venir — aucune revision GDD requise à ce niveau.

---

## Completeness : 8/8 sections présentes

✅ Overview / Player Fantasy / Detailed Design / Formulas / Edge Cases / Dependencies / Tuning Knobs / Visual-Audio / UI / Acceptance Criteria / Open Questions

(11 sections rédigées — excède les 8 standard de `.claude/rules/design-docs.md`)

---

## Scope Signal : S

**r3 scope** : 2-3 heures solo, 0 subagent à spawn.

Les revisions r3 sont **purement éditoriales/typographiques** :
- 4 ACs à ajouter (BLOCKING-r2-1)
- 1 reformulation Player Fantasy 40m OU 1 note R-2.6 ceiling_height exception (BLOCKING-r2-2, Option B recommandée)
- 1 bloc GDScript enum LevelState (BLOCKING-r2-3)
- 1 bloc GDScript enum RoomType (MINOR-r2-3)
- 4 ajustements MINOR optionnels

Aucune refonte identitaire, aucun specialist à consulter.

---

## Verdict final : NEEDS REVISION

**Rationale** : le GDD r2 est **substantiellement aligné** avec le verdict MAJOR REVISION NEEDED du full review (5 BLOCKING CROSS-MODEL / 2 technique ✅ RESOLVED, 2 PARTIEL). Les blockers r2 sont de finition (AC manquantes + enum + 1 inconsistence numérique Player Fantasy / F5), **pas** d'identité.

**Critère de merge r3** : r3 est mergeable pour Sprint 1 dès que les 3 BLOCKING-r2 sont résolus. Aucun re-review full requis après r3 — un `/design-review design/gdd/level-system.md --depth lean` de 15 min suffira à valider, OU un check inline par le user.

**Scope** : **S** — 2-3h éditoriales solo.

---

## Specialist disagreements : aucun

Review lean solo (aucun subagent spawned ce run). Les disagreements du full review r1 (rigidité R-2 vs flexibilité, single-scene .tscn vs PackedScene, qa-lead ACs classification) ont été tranchés par le creative-director senior et appliqués en r2. Rien à résurveiller.

---

## Senior verdict (synthèse game-designer solo)

> "Le GDD Level System r2 a fait le gros travail identitaire demandé par le full review r1 — room archetypes introduits (4 types avec rôles et duration novice), F2 draw-call budget séparé Level/peers, F5 réécrit avec gate numérique, F8 dérivé-pas-fabriqué, SecretSlot.required_ability structuré. Ce n'est plus un GDD qui 'livre l'implémentabilité au prix de la fantasy' — les promesses Player Fantasy (verticalité, secrets = mouvement, séparation Level/peers) sont chacune ancrée dans une règle testable. Reste 3 blockers de **finition** : 4 ACs citées dans le texte mais non rédigées dans §Acceptance Criteria (effet : lints pré-build référencés sans test associé), une inconsistence résiduelle Player Fantasy 40m / F5 30m (résolvable en note d'exception R-2.6), et l'enum `LevelState` utilisée sans être formalisée en bloc GDScript. Aucun des trois n'est un obstacle de design — ce sont des items d'édition. r3 ciblé, 2-3h solo, et on bascule Sprint 1. Ne pas relancer un full multi-specialist."

---

## Next steps

### Option A (recommandée) — r3 ciblé maintenant

Appliquer les 3 BLOCKING-r2 + MINOR-r2-3 (enum RoomType bloc) dans une session courte :
- 4 nouveaux ACs en Groupe G
- Note R-2.6 ceiling_height exception 40m (Option B)
- Bloc GDScript enum LevelState
- Bloc GDScript enum RoomType

Puis `/design-review design/gdd/level-system.md --depth lean` (15 min) pour valider, OU inline user check, et marquer systems-index Level System → **Approved r3**.

### Option B — Paralléliser

Démarrer en parallèle `/design-system hazard-system` (#6 MVP) ou `/design-system checkpoint-system` (#8 MVP) — ils dépendent de Level mais le r2 est *suffisamment* stable pour servir de référence (les blockers restants n'affectent ni les contrats de signaux ni les slots spatial). Revenir à r3 Level après.

### Option C — Épic breakdown prématuré

`/create-epics level-system` sur r2 pour commencer le backlog. Déconseillé — les 4 ACs manquantes sont des gates lint qui figureront dans des stories ; mieux vaut les avoir avant breakdown.

**Recommandation** : **Option A**, puis basculer vers `/design-system hazard-system` une fois r3 merged.

---

## Traceability

- **GDD cible** : `design/gdd/level-system.md` (1030 lignes, r2)
- **Review précédente solo (subsumed)** : `design/gdd/reviews/level-system-review-r1-2026-04-23.md` (525 lignes)
- **Review log** : `design/gdd/reviews/level-system-review-log.md` (à mettre à jour post-r2)
- **Systems index** : `design/gdd/systems-index.md` (Level System toujours "NEEDS REVISION r1 MAJOR" — à mettre à jour post-r3)
- **Architecture** : 21 TR Level mappés sur Gap G-8 (ADR-0011 planifié) ; compatible r2.
