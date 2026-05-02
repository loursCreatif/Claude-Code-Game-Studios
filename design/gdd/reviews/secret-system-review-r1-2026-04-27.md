# Secret System — Review r1 — 2026-04-27

> **Reviewer** : game-designer (fresh session — aucune mémoire de la session de design productrice)
> **Review mode** : solo (production/review-mode.txt = "solo")
> **GDD cible** : design/gdd/secret-system.md — In Design r1 — 779 lignes
> **Date** : 2026-04-27
> **CD-GDD-ALIGN gate** : skipped — solo mode

---

## 1. Verdict Global

**NEEDS REVISION**

Le GDD Secret System r1 est de haute qualité architecturale : la Player Fantasy est la meilleure du studio (sur-classe Enemy r1 sur la dimension narrative), les 8 sections obligatoires + 5 sections bonus sont présentes avec un niveau de détail exceptionnel, les 43 ACs sont bien structurés avec un niveau de précision implémentable. L'auteur a manifestement travaillé de concert avec les autres GDDs du sprint backbone — les cross-références Credit, Level, Audio, GSM sont précises et bien documentées.

Cependant, la review adversariale identifie **3 BLOCKING** non-négociables qui empêchent l'approbation en l'état :

1. **Interface Checkpoint incomplète et contradictoire** (B-1) : Secret System R-SEC-10 appelle `checkpoint.get_collected_secrets() -> Array[int]` mais le Checkpoint GDD (In Design) ne liste nulle part ce getter dans sa section Interactions, et n'a aucune mention de Secret System dans son §Interactions. Le contrat est unilatéral.

2. **`instance_id` comme clé de persistance cross-étage est architecturalement cassé** (B-2) : R-SEC-06 + R-SEC-10 utilisent `volume.get_instance_id()` comme clé de persistance inter-respawn ET inter-étage. Or Godot réassigne les instance_ids à chaque instanciation de scène. Quand Secret System lit le snapshot Checkpoint à `level_active` (R-SEC-10), les instance_ids sauvegardés lors de l'étage N ne correspondent plus aux instance_ids des volumes de l'étage N+1 (ou même de l'étage N après une transition). Le système produit silencieusement des faux positifs (secrets considérés collectés alors qu'ils ne l'ont jamais été) ou des faux négatifs (secrets recollectables alors qu'ils ont déjà été collectés).

3. **Absence de Tuning Knobs dans un fichier external data conforme CLAUDE.md** (B-3) : CLAUDE.md impose "Gameplay values must be data-driven (external config), never hardcoded". Les 2 knobs runtime de Secret System sont documentés comme valeurs à encoder dans le code (`IDEMPOTENCE_KEY_STRATEGY` est implicitement une constante GDScript, `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE` idem). Aucune référence à un fichier `.tres` ou `.gd` constants externe. Ce problème est partagé avec la note N-2 de l'Enemy review r1 — le studio n'a pas encore appliqué la règle CLAUDE.md sur les Tuning Knobs.

Les 4 RECOMMENDED et les 5 NICE-TO-HAVE sont des améliorations significatives mais non-bloquantes pour le sprint A backbone.

---

## 2. Scope Signal

- **Review mode** : solo (CD-PILLARS skipped, AD-CONCEPT-VISUAL skipped)
- **Specialists consultés** : none (solo mode auto-approve — fresh session reviewer seul)
- **Blocking items** : 3
- **Recommended items** : 4
- **Nice-to-have items** : 5

---

## 3. Completeness Check

### 8 sections obligatoires

| Section | Présente | Qualité | Notes |
|---------|----------|---------|-------|
| 1. Overview | ✅ | Excellente | Scope et boundaries très clairs, anti-patterns bien définis (pas de logique de placement, pas de logique économique, pas de logique visuelle) |
| 2. Player Fantasy | ✅ | Exceptionnelle | Meilleure du studio — narration immersive, anti-fantasy explicite, cohérence inter-systèmes, 3 dimensions (engagement, asymétrie viscérale, promesse de retour) |
| 3. Detailed Rules | ✅ | Très bonne | 15 Core Rules bien définies, States/Transitions table complète, Interactions table exhaustive |
| 4. Formulas | ✅ | Bonne | F-SEC-1 (référence crédit) et F-SEC-2 (yield session) correctes, worked examples valides. Lacune : F-SEC-2 est une formule de validation, pas une formule runtime — bien articulé |
| 5. Edge Cases | ✅ | Excellente | 14 EC runtime + 3 EC cross-system + 7 EC anti-patterns authoring. Couverture remarquable, notamment les anti-patterns authoring avec recommendations lint |
| 6. Dependencies | ✅ | Très bonne | Hard/Soft/Cousins/Bidirectional check/Provisional contracts/Anti-dependencies. Structure complète. Lacune sur Checkpoint (voir BLOCKING B-1) |
| 7. Tuning Knobs | ✅ | Moyenne | 2 knobs runtime + 9 authoring guidelines bien documentés. Lacune : aucun fichier external data référencé (voir BLOCKING B-3) |
| 8. Acceptance Criteria | ✅ | Très bonne | 43 ACs (29 BLOCKING + 14 ADVISORY), répartis en 10 groupes (A à J). Format GIVEN/WHEN/THEN respecté. Couverture des groupes logique/integration/visual/perf/static/manual exhaustive. Note : le GDD annonce 52 ACs en header §Tableau récapitulatif mais n'en contient que 43 numérotés. |

### Sections bonus

| Section | Présente | Notes |
|---------|----------|-------|
| Visual/Audio Requirements | ✅ | Excellent détail, spec critique Pillar 4 bien articulée, asset spec flag présent |
| UI Requirements | ✅ | Exceptionnel — liste exhaustive des éléments UI explicitement HORS MVP avec justification |
| Open Questions | ✅ | 10 OQs structurées en deux catégories (Provisoire / Décisions en attente), bien priorisées |
| States and Transitions | ✅ | Table complète 5 états + invariants d'état |
| Interactions with Other Systems | ✅ | Table 7 systèmes bien documentée |

**Completeness score : 8/8 sections + 5 bonus = COMPLET**

**Anomalie comptage ACs** : le tableau récapitulatif §Acceptance Criteria annonce 43 ACs Total mais le header Summary annonce "52 ACs annoncés" (instruction de review). Le contenu réel = 43 ACs numérotés (AC-SEC-01 à AC-SEC-52, mais avec un gap : la numérotation saute de AC-SEC-43 à AC-SEC-46 sans ACs 44/45 séquentiels car les groupes H et I sont bien numérotés 39-45, groupe J 46-52). Compter effectif = 52 ACs (9 groupe A + 6 groupe B + 5 groupe C + 6 groupe D + 5 groupe E + 7 groupe F + 3 groupe G + 2 groupe H + 5 groupe I + 7 groupe J = **52 total**). La table récapitulatif déclare 43 — erreur dans la table récapitulatif. À corriger dans r2.

---

## 4. Dependency Graph

### Upstream (systèmes dont Secret dépend)

| Système | Statut GDD | Interface | Direction | Bidirectionnel ? |
|---------|------------|-----------|-----------|-----------------|
| Level System | APPROVED r3/r4 | `level_active` signal + `get_secret_slots() -> Array[SecretSlot]` | Amont | ✅ Level §Interactions liste Secret comme aval avec ces interfaces |
| Game State Manager | APPROVED r1 | `state_changed(new_state: State)` + `request_new_run()` | Amont | ⚠️ GSM §Interactions ne liste pas Secret comme consumer — amendement GSM r2 requis (documenté dans §Dependencies du GDD, ligne 360) |
| Credit Economy | Designed r1 | Signal `secret_collected(secret_node: Node, tier: int)` | Aval | ✅ Credit r1 Rule 9 liste le contrat `secret_collected` comme OQ-CRD-1 — Secret ferme cette OQ |
| Checkpoint System | In Design | `checkpoint.get_collected_secrets() -> Array[int]` + `restore_collected_secrets(ids)` | Bidirectionnel | ❌ BLOCKING — Checkpoint GDD ne mentionne pas ces interfaces ni Secret System (voir B-1) |

### Downstream (systèmes qui consomment Secret)

| Système | Statut GDD | Signal consommé | Bidirectionnel dans cible |
|---------|------------|-----------------|--------------------------|
| VFX System | Not Started | `secret_collected(secret_node, tier)` | N/A (not started — contrat à enregistrer) |
| Audio System | APPROVED r2.1 | `secret_collected(secret_node, tier)` | ⚠️ Audio r2.1 ne liste pas explicitement `secret_collected` comme signal écouté (OQ-SEC-4 le note). Amendement Audio r2.2 requis |
| HUD System | In Design r1 | Indirect via `credits_changed(total, delta, SourceKind.SECRET)` | ⚠️ HUD GDD r1 §OQ-SEC-8 fait référence au problème mais la connexion est indirecte via Credit — acceptable |
| Save/Load System | Not Started | `save_int_array / load_int_array` | N/A (post-MVP) |
| Player Movement | In Review r3 | (aucun — cousin) | ✅ Cousin déclaré explicitement, zéro couplage |

**Upstream DESIGNED : 3/4** (Level ✅, GSM ⚠️ amendement requis, Credit ✅, Checkpoint ❌ BLOCKING)
**Downstream not-started acceptable** (VFX, Save/Load — contrats enregistrés comme provisoires)

---

## 5. BLOCKING Items

| # | Item | Source | Lignes GDD | Convergence |
|---|------|--------|-----------|-------------|
| B-1 | **Interface Checkpoint non confirmée** : Secret System R-SEC-10 (ligne 126-134) appelle `checkpoint.get_collected_secrets() -> Array[int]` et expose `get_collected_ids() -> Array[int]` + accepte `restore_collected_secrets(ids: Array[int])`. Or le Checkpoint GDD (In Design) §Interactions (lignes 194-209) liste 7 systèmes et ne contient **aucune** entrée Secret System. Le getter `get_collected_secrets()` et le setter `restore_collected_secrets()` ne figurent pas dans la §Published API du Checkpoint GDD. AC-SEC-12 (ligne 546) suppose que ce getter existe et retourne les bons ids — l'AC est non-testable si Checkpoint n'expose pas ce getter. Le contrat est unilatéral. | Reviewer frais — cross-read Checkpoint GDD + Secret GDD ligne 209-210 | secret:126-134, secret:209-210, secret:364-366, checkpoint:194-209 | Architectural cross-GDD |
| B-2 | **Clé `instance_id` invalide pour persistance cross-étage** : Secret R-SEC-06 + R-SEC-10 + Tuning Knob G-1 (lignes 85-91, 125-134, 387) utilisent `volume.get_instance_id()` (Godot `Object.get_instance_id()`) comme clé de persistance entre morts ET entre étages. Or Godot 4.6 réassigne les instance_ids à chaque instanciation de nœud — un nœud supprimé puis recréé (même scène, même chemin) obtient un id différent. Conséquences : (1) à l'entrée d'un nouvel étage (level_active étage N+1), les ids sauvegardés dans `_collected_secret_ids` de l'étage N ne correspondent pas aux nouveaux volumes de l'étage N+1 — comportement correct par hasard (les ids ne matchent pas, donc les nouveaux volumes sont vus comme non-collectés ✅). (2) Mais pour la **persistance intra-étage inter-respawn** — le cas réel MVP — si Level System décharge et recharge un étage (retour au menu → nouvelle run → même étage), les volumes sont réinstanciés avec de nouveaux instance_ids. Le Tuning Knob G-1 note lui-même "session-scoped" : "instance_id est session-scoped (Godot regénère les ids au boot)". Ce GDD admet donc implicitement que la clé casse dès la 2ème session, mais prétend que MVP est "session-only". **Problème** : R-SEC-10 (ligne 126) dit "_collected_secret_ids survit aux morts" et sera "peuplé depuis le snapshot Checkpoint actif" — mais si le Level recharge (new run), les ids du snapshot ne matchent pas les nouveaux ids. Le GDD suppose que `request_new_run()` purge le snapshot (R-SEC-11 ligne 134), ce qui est correct pour le reset entre runs — mais le chemin `niveau → mort → respawn SANS new_run → les ids sont stables` est uniquement garanti tant que les nœuds Area3D ne sont pas destroy+recréés. Cette stabilité repose sur le contrat Enemy/Level Rule 12 "pas de queue_free au MVP". Ce contrat est acceptable au MVP mais n'est nulle part cité explicitement dans Secret GDD comme contrainte requise sur Level/VFX ("Level ne doit jamais queue_free les SecretCollectVolume_NN pendant un run actif"). Sans cet invariant documenté, l'implémentation est fragile. De plus, OQ-SEC-2 reconnaît la migration nécessaire vers `uuid_export` — mais cette migration est déférée "Tier 2+ post-MVP playtest" alors que le risque existe dès le MVP si un playtest force un `load_threaded_request` de la scène d'étage. | Reviewer frais — analyse Godot instance_id lifecycle + cross-lecture R-SEC-06/10/OQ-SEC-2 | secret:85-91, secret:125-134, secret:387, secret:714-716 | Godot API + architectural |
| B-3 | **Tuning Knobs non data-driven** : CLAUDE.md studio (ligne ~8) impose "Gameplay values must be data-driven (external config), never hardcoded". Le §Tuning Knobs de Secret System (lignes 379-420) documente 2 knobs runtime (`IDEMPOTENCE_KEY_STRATEGY`, `IGNORE_BODY_ENTERED_BEFORE_LEVEL_ACTIVE`) et 9 knobs authoring sans référencer un seul fichier `assets/data/` ou `.tres`. Le GDD ne spécifie ni fichier de configuration externe ni pattern constant-export. AC-SEC-40 (lint hot-path) valide les allocations mais aucun AC ne valide que les constantes soient en fichier externe. Ce problème est systémique au studio (Enemy r1 N-2 l'avait signalé sans le bloquer) mais Secret System est le premier GDD où la règle CLAUDE.md est explicitement BLOCKINg par cette review car l'OQ-SEC-2 (Tuning Knobs Tier 2+) admet que la stratégie de clé devra changer — ce qui est impossible sans data-driven config. Fix minimal : référencer `assets/data/secret_config.tres` ou `src/gameplay/secret/secret_constants.gd` dans §Tuning Knobs avec les valeurs MVP + safe ranges. | CLAUDE.md "never hardcoded" + §Tuning Knobs ligne 379 + OQ-SEC-2 ligne 712 | secret:379-420, CLAUDE.md | Standards violation |

---

## 6. RECOMMENDED Items

| # | Item | Justification |
|---|------|---------------|
| R-1 | **Amendement GSM r2 à tracer formellement** : §Dependencies ligne 360 note "GSM GDD §Interactions liste les consumers de `state_changed` : Secret doit être ajouté via amendement GSM r2". Cette note est juste, mais elle est cachée dans une sous-section §Bidirectional check que le prochain reviewer de GSM pourrait manquer. Recommandation : créer une note de gate formelle en bas de §Dependencies du type `[GATE] amendement GSM r2 requis avant /create-epics secret-system`. Sans cette notation explicite, la propagation risque d'être oubliée lors du sprint épic. | Cross-GDD propagation discipline |
| R-2 | **EC-SEC-11 (secret_node = null) non propagé à Credit GDD** : l'edge case EC-SEC-11 (ligne 301-302) recommande "Credit GDD à amender Sprint A pour expliciter ce cas". Credit Economy r1 Rule 4 définit `try_spend` atomique et Rule 8 `credits_changed` SYNC, mais la section §Edge Cases de Credit GDD ne couvre pas `secret_node == null`. La robustesse du pipeline `secret_collected(null, tier)` → Credit handler repose sur une tolérance implicite. Recommandation : formaliser l'amendement Credit r2 pour couvrir explicitement `secret_node == null` dans Credit §Edge Cases — le crédit doit quand même être accordé (tier est suffisant pour F-CRD-2, secret_node n'est utilisé que par VFX/Audio). | Architectural completeness |
| R-3 | **AC-SEC-12 dépend d'un contrat Checkpoint non existant** : AC-SEC-12 (ligne 546) dit "mock `checkpoint.get_collected_secrets()` retournant `[42]`". Ce mock suppose que Checkpoint expose ce getter — or B-1 démontre que Checkpoint GDD ne le liste pas. Même si Checkpoint est amendé (résolution B-1), l'AC doit être conditionné à cet amendement : "GIVEN Checkpoint expose `get_collected_secrets() -> Array[int]` (Checkpoint GDD r2 amendement B-1 requis)". Sans cette conditionalité explicite, l'AC est non-testable en l'état du Checkpoint GDD actuel et fera échouer l'implémenteur qui lira les ACs sans contexte de review. | AC correctness |
| R-4 | **Layer 5 `LAYER_INTERACTIVE` : conformité ADR-0008 non citée dans §Detailed Rules** : R-SEC-04 (ligne 65) dit "Vérifie que `slot.collect_volume` est un Area3D valide sur le layer 5 (`LAYER_INTERACTIVE`)" mais ne cite pas ADR-0008 comme source de la constante. Combat GDD cite explicitement ADR-0008 pour toutes ses assertions de layer. Le §Dependencies de Secret ne liste pas ADR-0008. Si ADR-0008 est amendé (valeur de LAYER_INTERACTIVE changée), Secret System n'a aucun mécanisme de propagation. Recommandation : ajouter ADR-0008 en §Dependencies comme "Contrainte — LAYER_INTERACTIVE = 5" et citer ADR-0008 dans R-SEC-04. | Consistency with locked contracts |

---

## 7. NICE-TO-HAVE Items

| # | Item |
|---|------|
| N-1 | **Comptage ACs incohérent** : la table récapitulatif §Acceptance Criteria (ligne 494-503) annonce "Total ACs : 43" mais le GDD contient effectivement 52 ACs numérotés (groupes A=9, B=6, C=5, D=6, E=5, F=7, G=3, H=2, I=5, J=7 = 55 — après décompte précis). La discordance est confuse pour le QA Lead. Corriger la table récapitulatif avec le vrai compte. |
| N-2 | **F-SEC-2 (yield session) a un calcul incohérent** : ligne 253, le cap théorique est indiqué "5 secrets × tier 3 × 5 cr = 75 par étage × 2 = 150 max session". Mais F-SEC-2 formule dit `credits = BASE_SECRET_CREDIT × tier`, donc tier 3 = `5 × 3 = 15`, et 5 secrets tier 3 = `5 × 15 = 75`. La note "tier 3 × 5 cr" confond la formule multiplicative : 75 est correct mais le calcul intermédiaire présenté "tier 3 × 5 cr" est ambigu (on lit "3 × 5 = 15 cr par secret", non "5 cr × tier = 15 cr"). Reformuler : "5 secrets × (5 cr × 3) = 5 × 15 = 75 cr". |
| N-3 | **Connexion `CONNECT_ONE_SHOT = false` documentée dans R-SEC-14 mais non spécifiée pour body_entered** : R-SEC-04 (ligne 70) dit `flags = 0 (SYNC, pas CONNECT_DEFERRED)` pour la connexion body_entered. R-SEC-14 (ligne 167) documente la protection contre double souscription pour `level_active`. Mais R-SEC-04 ne spécifie pas explicitement si la connexion body_entered doit utiliser un flag `CONNECT_ONE_SHOT` ou non. Sans précision, l'implémenteur doit déduire que `flags = 0` = sans ONE_SHOT (comportement correct — le secret peut être approché plusieurs fois jusqu'à collecte, le handler vérifie idempotence). Un commentaire explicite éviterait une erreur d'implémentation. |
| N-4 | **EC-SEC-09 fait une hypothèse implicite sur `request_scene_transition`** : EC-SEC-09 (ligne 296) dit "`request_scene_transition` GSM repositionne le joueur à `player_start`, sortant de tout volume". Mais cette responsabilité n'est pas citée dans le GSM GDD (APPROVED r1) — le GSM Rule 6 dit `change_scene_to_file` ou `LevelSystem.load_etage` mais ne garantit pas que le joueur est repositionné avant que `level_active` ne soit émis. Si l'ordre est (a) level_active émis → (b) Secret cleanup → (c) Player repositionné, le problème EC-SEC-09 subsiste pour 1 frame. Vérifier avec GSM r1 et Level r3 que l'ordre est bien : Player repositionné AVANT `level_active` emit. |
| N-5 | **Pillar 4 design test non référencé** : le game-concept définit le design test de Pillar 4 comme "Si pour trouver un secret il faut réfléchir, on refait le secret en exigeant de bouger". Ce design test est cité dans le §Overview (ligne 10) mais aucun AC de la section J ne le formalise en gate. AC-SEC-48 s'en approche ("joueur comprend spontanément il y a quelque chose à atteindre") mais ne capture pas l'anti-énigme directement. Recommandation AC bonus : "GIVEN un secret est placé dans la scène, WHEN un playtest naïf est conduit, THEN aucun joueur ne mentionne avoir dû 'réfléchir à comment y aller' — uniquement 'c'était dur d'y arriver physiquement'." |

---

## 8. OQ Resolutions

### OQ-SEC-1 — Interface Checkpoint System *(PROVISOIRE)*

**Résolution proposée** : BLOCKED — résolution partielle possible mais le contrat exact doit être négocié lors du design Checkpoint r2.

Le Secret GDD propose deux interfaces :
- `checkpoint.get_collected_secrets() -> Array[int]` (Checkpoint expose vers Secret, Secret lit au `level_active`)
- `Secret.get_collected_ids() -> Array[int]` (Secret expose vers Checkpoint, Checkpoint lit à chaque checkpoint latch)

**Problème architectural** : Checkpoint GDD actuel (In Design) ne mentionne aucune de ces interfaces. Or le Checkpoint GDD *est déjà designé* et sa §Interactions (lines 194-208) est complète sans Secret System. Cela signifie que l'auteur du Checkpoint GDD n'a pas intégré la dépendance Secret — c'est un BLOCKING cross-GDD (B-1).

**Résolution recommandée** : lors de l'amendement Checkpoint r2, ajouter dans §Interactions :
```
| Secret System (In Design r1) | Bidirectionnel | getter get_collected_secrets() + setter restore_collected_secrets(ids) | Checkpoint expose la liste des instance_ids de secrets collectés à Secret System au level_active. Secret expose get_collected_ids() pour snapshot lecture. |
```

**Correction additionnelle** : renommer `restore_collected_secrets(ids)` en `inject_collected_secrets(ids: Array[int])` (Secret appelle Checkpoint) pour clarifier la direction de l'appel — actuellement ambigu ("restore" suggère que c'est Checkpoint qui restore, or c'est Secret qui injecte son état dans Checkpoint).

**Impact** : BLOCKING sur Secret r1. Résolution : Amendement Checkpoint r2 + Secret r2 pour aligner les noms d'interface.

**Classification** : **BLOCKING** (B-1)

**Cross-impact** : Checkpoint GDD r2 amendment required before `/create-epics secret-system`.

---

### OQ-SEC-2 — Save/Load API + clé de persistance Tier 2+ *(PROVISOIRE)*

**Résolution proposée** : DEFERRED Tier 2+, mais avec une action immédiate sur le MVP.

**Action MVP immédiate** : documenter dans §Detailed Rules (R-SEC-06 ou nouvelle Rule R-SEC-16) l'invariant suivant : "Les `SecretCollectVolume_NN` ne doivent jamais être queue_free() ou réinstanciés pendant un run actif. Leur instance_id est stable uniquement si le nœud existe sans interruption dans le scene tree. Level System et VFX System s'interdisent de supprimer ou recréer ces nœuds." Cet invariant rend explicite la dépendance implicite de R-SEC-06.

**Pour Tier 2+ Save/Load** : migrer vers `uuid_export` comme documenté dans OQ-SEC-2 et Tuning Knob G-1 — plan correct. L'UUID doit être un `@export var secret_uuid: StringName` stable cross-version sur chaque `SecretLureMarker_NN`. La migration Save/Load sera transparente au runtime.

**Format Save/Load recommandé** : `Array[StringName]` (UUIDs) plutôt que `Array[int]` (instance_ids) — stable cross-session, cross-version.

**Classification** : **RECOMMENDED** pour MVP (action R-SEC-16 invariant), DEFERRED pour la migration uuid_export

**Cross-impact** : Level GDD r5 (contrainte queue_free interdite sur SecretCollectVolume), VFX GDD futur (même contrainte).

---

### OQ-SEC-3 — Pitch-shift par tier post-MVP *(PROVISOIRE)*

**Résolution proposée** : DEFERRED — correcte.

Audio GDD r2.1 Rule 13 a déjà figé le pattern pitch-shift multi-kill (+2/+4 semitones) pour les kills. Le même pattern est disponible pour les secrets. La décision de différencier les tiers par pitch-shift est une décision playtest-data : si les joueurs distinguent perceptivement le tier via le delta HUD (5 vs 10 vs 15 cr), la différenciation audio est un bonus non-requis. Si les joueurs ne distinguent pas, le pitch-shift ajoute de la clarté sans violation de Pillar 4.

**Note**: si pitch-shift introduit, vérifier que le spectre grave (200-400 Hz, spec Audio §Visual Requirements ligne 456) reste perceptif après pitch-shift de +4 semitones (augmentation d'environ 26% de la fréquence fondamentale → 252-504 Hz). Risque : un sample de 200 Hz pitché +4 st donne 252 Hz — reste grave. Acceptable.

**Classification** : **NICE** (DEFERRED)

---

### OQ-SEC-4 — Bus audio dédié `SECRET_COLLECT` *(PROVISOIRE)*

**Résolution proposée** : Option (c) — nouveau bus `SECRET_COLLECT` parented à `SFX`. Recommandation confirmée.

**Justification** :
- Option (a) COMBAT_KILL : sémantiquement incorrect. Un secret n'est pas un kill. Le ducking Music via sidechain (ADR-0009 D-1) s'applique à COMBAT_KILL pour l'intensité du combat — le secret doit au contraire se fondre dans la musique, pas la ducker.
- Option (b) SFX générique : perd la tracabilité dans l'Audio profiler et rend le mixing futur (Tier 2+) impossible sans refactor.
- Option (c) `SECRET_COLLECT` parented à SFX : net, traceable, non-ducking Music, compatible avec le mixing Tier 2+ sans refactor.

**Action requise** : amendement Audio r2.2. Priority : avant `/create-epics secret-system`.

**Classification** : **RECOMMENDED** (R-4 du §Recommended Items) — à actionner Phase 5 propagation.

---

### OQ-SEC-5 — VFX du glow lure post-collect : éteint vs grayed-out *(à trancher Sprint A)*

**Résolution proposée** : **MVP = éteint complet**. Recommandation du GDD confirmée.

**Justification** :
- PRO grayed-out (Pillar 2) : argument séduisant en théorie — le joueur voit ses progrès dans la géométrie. Mais il y a un conflit : la géométrie peut changer d'une run à l'autre si Level est dynamique Tier 2+. Ancrer la progression dans la géométrie crée une dépendance à la persistance Level.
- CONTRA grayed-out (Pillar 4 + Pillar 1) : le glow cyan est actuellement le seul signal visuel qui dit "quelque chose est atteignable ici". Un glow désaturé crée une catégorie visuelle supplémentaire ("atteignable déjà-collecté") qui demande au joueur de lire/interpréter l'UI — exactement ce que Pillar 4 interdit.
- MVP éteint complet + compteur HUD = feedback suffisant. Le compteur HUD qui ne monte pas au re-passage d'un volume collecté est lui-même un feedback implicite de "déjà collecté".

**Classification** : **RESOLVED** — éteint complet MVP.

---

### OQ-SEC-6 — Comportement glow lure si `required_ability` non possédée *(reservation Tier 2+)*

**Résolution proposée** : DEFERRED Tier 2+ — MVP glow toujours allumé. Recommandation du GDD confirmée.

**Justification** : La logique "capability-aware glow" nécessite que VFX System soit connecté à un signal de Movement System indiquant les capabilities actuelles. Ce couplage VFX → Movement n'existe pas au MVP et violerait l'outbound-only pattern (ADR-0005 D-10 par analogie). De plus, la "promesse de retour" décrite dans Player Fantasy §28 est *intentionnellement silencieuse* — c'est au joueur de faire la connexion mentale "je ne peux pas atteindre ça maintenant, mais je pourrai". Un glow différentiel verbalise cette promesse, ce qui réduit l'agentivité du joueur (SDT Autonomy).

**Classification** : **NICE** (DEFERRED)

---

### OQ-SEC-7 — Lint Level pré-build pour validation tuples Secret *(à scoper Sprint A)*

**Résolution proposée** : RECOMMENDED Sprint 1 — ouvrir l'epic `level-system-lint-secret-tuples`.

**Justification** : Les 7 anti-patterns EC-SEC-AP-1 à EC-SEC-AP-7 documentent des bugs d'authoring qui produiront des violations Pillar 4 en production. Au MVP avec 1 seul étage et 3-5 secrets, un playtest manuel peut attraper ces erreurs. En Sprint 1 avec scaling (2+ étages), le lint devient nécessaire pour maintenir la qualité sans coût QA linéaire.

**Scope lint recommandé** : script GDScript headless (`tools/lint/level_secret_lint.gd`) invoqué par CI sur chaque `.tscn` étage. Validations : hauteur volumes, distance lure↔volume, séparation inter-volumes, cap volumes/salle, présence ≥ 1 wall_run par étage. Logique de lint : ~150 lignes GDScript.

**Classification** : **RECOMMENDED** (scope Sprint 1 non MVP)

---

### OQ-SEC-8 — Différenciation HUD pulse SourceKind KILL vs SECRET *(coordination HUD GDD)*

**Résolution proposée** : RESOLVED — HUD GDD r1 est déjà designé et traite ce cas.

Vérification cross-GDD : HUD GDD r1 Rule 5 (ligne 61-64) couvre explicitement l'animation increment positive avec Tween `Label.scale` sur `delta > 0`. La différenciation SourceKind.KILL vs SourceKind.SECRET n'est PAS encore spécifiée dans HUD GDD r1 — Rule 5 traite uniformément "delta > 0 (sources KILL, SECRET)". 

**Gap identifié** : HUD GDD r1 ne spécifie pas une amplitude de tween différente pour KILL vs SECRET. Pour matérialiser l'asymétrie viscérale Pillar 4 ("un riff isolé vs un battement régulier"), HUD devrait avoir :
- KILL : `scale` → `Vector2(1.02, 1.02)` (subtil, ~2%)
- SECRET : `scale` → `Vector2(1.08, 1.08)` (perceptible, ~8%)

**Action** : recommandation HUD GDD r2 — différencier amplitudes tween par SourceKind.

**Classification** : **RECOMMENDED** — coordination HUD r2 avant implémentation HUD.

---

### OQ-SEC-9 — Boss room : secret possible derrière le boss ? *(Tier 3 Full Vision)*

**Résolution proposée** : DEFERRED Tier 3 — recommandation du GDD correcte.

**Classification** : **NICE** (DEFERRED)

---

### OQ-SEC-10 — Speedrun mode : secrets collectés affectent leaderboard split ? *(Tier 3 Full Vision)*

**Résolution proposée** : DEFERRED Tier 3 — hors scope MVP. Recommandation du GDD correcte.

**Note** : la pratique standard speedrun (any% vs 100%) est une décision communautaire qui émerge naturellement si le jeu a une communauté speedrun. Implémenter une infrastructure de splits avant d'avoir des speedrunners est prématuré. Laisser émerger.

**Classification** : **NICE** (DEFERRED)

---

## 9. Cross-GDD Consistency Findings

### Conflict 1 — Checkpoint GDD ne liste pas Secret dans §Interactions

**Description** : Secret System R-SEC-10 (ligne 126-134) suppose que Checkpoint expose `get_collected_secrets() -> Array[int]` et accepte `restore_collected_secrets(ids: Array[int])`. Or le Checkpoint GDD §Interactions (lignes 194-209) liste 7 systèmes sans mentionner Secret System. Le Checkpoint GDD est In Design et son §Interactions est complet — l'omission est réelle, pas un WIP.

**Impact** : AC-SEC-12 est non-testable. R-SEC-10 est non-implémentable sans API Checkpoint. Pipeline "secret collecté survive à la mort" (promesse Pillar 3) est non-fonctionnel au MVP.

**Résolution** : Amendement Checkpoint r2 — ajouter ligne dans §Interactions :
```
| Secret System (In Design r1) | Bidirectionnel | expose get_collected_secrets() → Array[int] (Secret lit) + accepte inject_collected_secrets(ids: Array[int]) (Secret écrit) | Snapshot des secrets collectés au checkpoint latch — au level_active, Secret System injecte ses ids dans Checkpoint pour persistance. |
```

**Action requise** : Checkpoint GDD r2 amendment. NE PAS modifier Checkpoint GDD dans cette session.

---

### Conflict 2 — GSM GDD ne liste pas Secret comme consumer de `state_changed`

**Description** : Secret System R-SEC-02, R-SEC-08 souscrit à `state_changed(new_state: State)` du GSM. GSM GDD §Detailed Rules Rule 4 décrit `state_changed` et ses consumers, mais ne liste pas Secret System. §Depended on by (header GSM GDD) liste : Level, Menu, Save/Load, Shop, Camera, Combat, Movement, Checkpoint, HUD, Audio — pas Secret.

**Impact** : Si GSM est amendé pour réduire sa surface `state_changed` ou changer le type de payload, Secret System ne sera pas notifié. Ce risque est faible au MVP (GSM APPROVED et stable) mais crée une dépendance undocumentée.

**Résolution** : Amendement GSM r2 — ajouter Secret System dans §Depended on by. Déjà noté dans §Dependencies de Secret ligne 360 — à formaliser.

**Action requise** : GSM GDD r2 amendment (propagation légère — 1 ligne). Priorité basse, non-bloquant implémentation.

---

### Conflict 3 — Audio GDD r2.1 ne liste pas `secret_collected` comme signal écouté

**Description** : Secret GDD §Visual/Audio Requirements (lignes 451-462) définit le contrat "Audio System joue le clac secret sur `secret_collected`". Audio GDD r2.1 Rule 11 (APPROVED r2.1) liste les samples et buses actifs. OQ-SEC-4 note que `SECRET_COLLECT` bus n'existe pas encore dans Audio r2.1.

**Impact** : L'implémenteur Audio qui lit Audio GDD r2.1 n'a aucun signal `secret_collected` dans sa liste d'handlers. Le clac secret ne sera pas implémenté à partir de Audio GDD seul.

**Résolution** : Amendement Audio r2.2 — ajouter : (a) bus `SECRET_COLLECT` parented à `SFX`, (b) connexion `SecretSystem.secret_collected` → handler Audio, (c) spec sample `secret_collect.wav` (200-300 ms, 200-400 Hz, 48 kHz mono).

**Action requise** : Audio GDD r2.2 amendment. Priorité : avant `/create-epics secret-system`.

---

### Conflict 4 — HUD GDD r1 ne différencie pas KILL vs SECRET dans l'animation tween

**Description** : Secret GDD §UI Requirements + OQ-SEC-8 spécifie que HUD doit différencier visuellement KILL vs SECRET. HUD GDD r1 Rule 5 traite uniformément `delta > 0` pour les deux sources. Pas de différenciation d'amplitude tween par SourceKind.

**Impact** : La promesse "asymétrie viscérale" Player Fantasy §24 est affaiblie si le compteur pulse de la même façon pour +1 kill et +15 secret tier 3.

**Résolution** : Amendement HUD GDD r2 — Rule 5 étendu avec branchement par SourceKind. Recommandation amplitudes dans §OQ-SEC-8 resolution ci-dessus.

**Action requise** : HUD GDD r2 amendment. Priorité : avant implémentation HUD Rule 5.

---

## 10. Formulas Audit

### F-SEC-1 : Crédit délégué par tier (référence vers Credit Economy F-CRD-2)

| Check | Résultat |
|-------|---------|
| Variables définies | ✅ Toutes définies avec sources de vérité |
| Input ranges | ✅ `tier ∈ {1, 2, 3}`, bornes explicites |
| Division par zéro | N/A — multiplication uniquement |
| Overflow int | ✅ Max = 5 × 3 = 15 — zéro risque overflow |
| Cohérence avec Credit F-CRD-2 | ✅ Formule identique `credits = BASE_SECRET_CREDIT × tier` |
| Output range documenté | ✅ {5, 10, 15} |
| Comportement tier invalide | ✅ R-SEC-05 filtre en amont, Credit AC-CRD-15 filtre en aval — double garde |

**Verdict** : ✅ Formule correcte, audit clean.

---

### F-SEC-2 : Yield attendu de secrets par session (validation MVP)

| Check | Résultat |
|-------|---------|
| Variables définies | ✅ Toutes définies avec ranges |
| Cap théorique | ⚠️ "5 secrets × tier 3 × 5 cr = 75" — formulation ambiguë. Corriger en "5 × (5 cr × 3) = 5 × 15 = 75". Aucun impact sur le résultat (N-2) |
| Cohérence avec Credit F-CRD-4 | ✅ F-SEC-2 worked example (12 grunts + 4 secrets = 52 cr) aligne parfaitement avec Credit F-CRD-4 worked example étage 2 (52 cr) |
| Validation ratio Pillar 4 | ✅ Ratio 3.25:1 calculé correctement : `65/20 = 3.25`. Conforme à la promesse F-CRD-2 "ratio 5:1 minimum par secret individuel" (T1 = 5:1) ET "secrets >> kills sur session" (3.25:1 session) |
| Overflow int | ✅ Max session 2 étages = 150 cr — largement dans les bornes int GDScript |
| Cas edge (0 secrets) | ✅ Couvert — "Combat-only (skip secrets) = 0 cr" dans la table |

**Verdict** : ✅ Formule correcte, ambiguïté mineure de formulation (N-2). Audit clean.

---

## 11. Edge Cases Coverage Assessment

### Runtime edge cases (14 EC-SEC-01 à EC-SEC-14)

| EC | Couvert | Qualité | Notes |
|----|---------|---------|-------|
| EC-SEC-01 body_entered avant level_active | ✅ | Bonne | Garde `_is_active == false` correcte |
| EC-SEC-02 body_entered pendant PAUSED | ✅ | Bonne | Séquence post-resume bien analysée (secret reste UNCOLLECTED) |
| EC-SEC-03 double body_entered même frame | ✅ | Excellente | Mutation AVANT emit pattern ADR-0005 D-8 correct |
| EC-SEC-04 volume déjà collecté multi-passage | ✅ | Bonne | Silently ignored correct |
| EC-SEC-05 tier hors plage | ✅ | Bonne | push_warning + skip documenté |
| EC-SEC-06 slot mal formé | ✅ | Bonne | push_error + skip correct |
| EC-SEC-07 tableau vide | ✅ | Bonne | Phase ACTIVE sans slots — comportement nominal |
| EC-SEC-08 double level_active même tick | ✅ | Bonne | Cleanup idempotent Godot no-op correct |
| EC-SEC-09 level_active joueur dans volume | ✅ | Bonne | Cleanup + repositionnement joueur (hypothèse GSM — voir N-4) |
| EC-SEC-10 request_new_run ACTIVE | ✅ | Bonne | Reset complet correct |
| EC-SEC-11 secret_node = null | ✅ | Bonne | Documenté mais non propagé (voir R-2) |
| EC-SEC-12 glitch capability gate | ✅ | Excellente | Décision design Pillar 3 bien justifiée |
| EC-SEC-13 save corrompue cross-session | ✅ | Bonne | Instance_ids orphelines silencieux — correct post-MVP |
| EC-SEC-14 body_entered/exited rapide | ✅ | Bonne | Séquence Godot correctement analysée |

**Runtime EC coverage : 14/14 ✅** — couverture remarquable.

### Edge cases manquants (identifiés par reviewer)

| EC manquant | Criticité | Description |
|-------------|-----------|-------------|
| EC-SEC-MISSING-1 : `SecretCollectVolume_NN` a un `CollisionShape3D` désactivé (disabled=true) | MEDIUM | Si un autheur oublie d'activer la collision shape, le volume est dans la scène mais `body_entered` ne fire jamais. Secret System ne détecte pas ce cas — le slot est connecté mais inerte. Recommandation : ajouter validation R-SEC-13 : `slot.collect_volume.get_children().any(is_collision_shape_enabled)` → push_warning si zéro shape active. |
| EC-SEC-MISSING-2 : Secret tier=2 collecté, puis `inject_collected_secrets` Checkpoint pré-peuple avec cet id, puis `level_active` new étage — même id par coincidence dans nouvel étage | LOW | Via B-2 — instance_ids non-stables. Cas théorique au MVP (volumes session-scoped) mais à documenter comme limitation connue. |

---

### Authoring edge cases (7 EC-SEC-AP)

| EC | Qualité |
|----|---------|
| AP-1 volume trop bas | ✅ Bien documenté + knob + lint recommendation |
| AP-2 lure derrière porte | ✅ Bien documenté |
| AP-3 required_ability=none sur chemin critique | ✅ Bien documenté + critère angle 30° |
| AP-4 deux volumes colocalisés | ✅ Bien documenté + séparation min documentée |
| AP-5 lure non-visible | ✅ Bien documenté, recommandation playtest manuel |
| AP-6 required_ability incohérent avec géométrie | ✅ Bien documenté |
| AP-7 wall_run_long dans Traversal | ✅ Bien documenté |

**Authoring EC coverage : 7/7 ✅**

---

## 12. Acceptance Criteria Sanity

### Vue d'ensemble 52 ACs réels

| Groupe | ACs | Types | Conformité naming | Couverture EC |
|--------|-----|-------|-------------------|---------------|
| A — Lifecycle 2-phases | 7 (01-07) | AUTO × 7 | ✅ | R-SEC-02/03/04/11/14 ✅ |
| B — Idempotence état | 6 (08-13) | AUTO × 6 | ✅ | R-SEC-06/10, EC-03/04/10/14 ✅ |
| C — Garde GSM | 5 (14-18) | AUTO × 5 | ✅ | R-SEC-08, EC-02/09/10 ✅ |
| D — Tier validation | 6 (19-24) | AUTO × 6 | ✅ | R-SEC-05/13, EC-05/06/07 ✅ |
| E — Émission SYNC | 5 (25-28) | AUTO × 4, STATIC × 1 | ✅ | R-SEC-07/09/12 ✅ |
| F — Contrats cross-system | 7 (29-35) | AUTO × 7, ADVISORY × 1 | ✅ | Level/Credit/GSM/Checkpoint/VFX/Audio ✅ |
| G — Formules | 3 (36-38) | AUTO × 3 | ✅ | F-SEC-1/2 ✅ |
| H — Performance | 2 (39-40) | AUTO × 1, STATIC × 1 | ✅ | Budget perf ✅ |
| I — Authoring lints | 5 (41-45) | STATIC × 5 | ✅ | EC-SEC-AP ✅ |
| J — Expérience perçue | 7 (46-52) | MANUAL × 7 | ✅ | Pillar 4 validation ✅ |

### Anomalies trouvées dans les ACs

| AC | Problème |
|----|---------|
| **AC-SEC-12** | Dépend de Checkpoint getter non existant dans Checkpoint GDD — non-testable en l'état (voir B-1 + R-3) |
| **AC-SEC-33** | Appelle `restore_collected_secrets([id_vol_1, id_vol_2])` — interface non documentée dans Checkpoint GDD. Même problème que AC-SEC-12 |
| **AC-SEC-37** | Calcule `ratio_secret_kill ≥ 3.0` sur session simulée 2 étages. Ce test d'intégration requiert un mock des 2 étages, des 20 kills, et des 3 secrets — scope très élevé pour un AC AUTO. À dégrader en ADVISORY ou décomposer en 2 tests unitaires + 1 test d'intégration léger. |
| **AC-SEC-40** | STATIC lint — réserve pour le fichier d'implémentation non encore créé. L'AC est techniquement valide mais suppose que `_on_body_entered` est identifiable statiquement. Si l'implémentation nomme autrement la fonction, l'AC fail à tort. Recommandation : nommer la fonction dans le contrat d'implémentation. |

### ACs manquants identifiés

| AC manquant | Type | Justification |
|-------------|------|---------------|
| `_is_active` est `false` après `state_changed(MENU)` cleanup | BLOCKING AUTO | R-SEC-02 couvre l'INACTIVE initial mais AC-SEC-04 couvre `state_changed(MENU)` → mais assert uniquement `_is_active == false + zéro callable` — correct. ✅ Déjà couvert — faux positif reviewer |
| Table récapitulatif compte 43 au lieu de 52 | Logic | La table récapitulatif (ligne 494-503) annonce 43 Total mais le contenu réel est 52 — erreur éditoriale |
| EC-SEC-MISSING-1 (shape disabled) | ADVISORY AUTO | Voir §Edge Cases manquants ci-dessus |

---

## 13. Pillars Alignment

| Pillar | Couverture dans Secret GDD | Verdict |
|--------|--------------------------|---------|
| **Pillar 1 — FLOW AVANT TOUT** | Émission SYNC (R-SEC-07), garde GSM pre-collection (R-SEC-08), zéro cinematic (R-SEC-12), zéro alloc hot path (AC-SEC-40), clac immédiat (Visual/Audio spec 1 frame max) | ✅ Excellent — pillar structurel de toutes les règles |
| **Pillar 2 — LA PROGRESSION SE VOIT** | Secondaire : la progression se voit via le delta HUD Credit. Secret System ne gère pas directement la progression — délégation correcte. Persistance inter-respawn (R-SEC-10) sert la progression visible | ✅ Bien servi indirectement |
| **Pillar 3 — SECONDE CHANCE N'EST JAMAIS LOIN** | R-SEC-10 (collecté reste collecté), EC-SEC-12 (glitch accepté), AC-SEC-11 (persistance respawn), AC-SEC-50 (glow éteint visible post-respawn) | ✅ Excellent — pillar le mieux servi après Pillar 4 |
| **Pillar 4 — SECRETS RÉCOMPENSENT LE MOUVEMENT** | Raison d'être du système. Player Fantasy exceptionnelle, anti-patterns documentés (UI désactivés), EC-AP pour authoring, R-SEC-09 (glitch accepté) | ✅ Pillar primaire parfaitement servi |

**Pillar sur-investi** : aucun. Le GDD maintient sa discipline de boundaries (pas de logique de récompense secondaire au MVP).
**Pillar sous-investi** : Pillar 2 correctement minimal — Secret System délègue à Credit, comportement logique.

---

## 14. Recommandations Finales pour r2

### Checklist priorisée (dans l'ordre d'action)

**BLOCKING — à corriger avant APPROVED :**

1. **B-1 — Contrat Checkpoint** : ouvrir ticket `Checkpoint GDD r2 amendment` pour ajouter Secret System dans §Interactions avec les deux interfaces `get_collected_secrets() -> Array[int]` + `inject_collected_secrets(ids: Array[int])`. Modifier Secret GDD r2 pour aligner les noms (renommer `restore_collected_secrets` → `inject_collected_secrets` pour clarté direction). 3-4 lignes Checkpoint GDD + 2 lignes Secret GDD.

2. **B-2 — Invariant `instance_id` stabilité** : ajouter dans §Detailed Rules une nouvelle Rule R-SEC-16 : "Level System, VFX System, et tout autre consommateur de SecretCollectVolume_NN s'interdisent de `queue_free()` ou de réinstancier ces nœuds pendant un run actif (`_is_active == true`). Secret System n'est pas responsable de cette stabilité — c'est un pré-contrat Level/VFX. Violation → secret potentiellement non-collecté ou double-collecté silencieusement." 4-5 lignes Secret GDD + note dans Level GDD §Anti-dependencies.

3. **B-3 — Fichier data-driven** : créer une entrée Tuning Knobs avec référence au fichier `assets/data/secret_config.tres` (ou `src/gameplay/secret/secret_constants.gd`) et documenter les 2 knobs runtime avec leur valeur MVP dans ce fichier. 3 lignes Secret GDD + 1 fichier `.gd` constants (5-10 lignes).

**RECOMMENDED — à traiter dans la même session r2 :**

4. **R-1 — Gate formelle GSM r2** : ajouter note de gate "[GATE] amendement GSM r2 requis avant /create-epics secret-system" en bas de §Dependencies.

5. **R-2 — EC-SEC-11 propagation Credit** : créer ticket `Credit GDD r2 amendment` couvrant `secret_node == null` dans §Edge Cases Credit.

6. **R-3 — AC-SEC-12 conditionnel** : reformuler AC-SEC-12 avec condition "GIVEN Checkpoint expose `get_collected_secrets()` (Checkpoint GDD r2 amendment B-1 requis)".

7. **R-4 — ADR-0008 dans §Dependencies** : ajouter ADR-0008 dans §Dependencies de Secret System comme contrainte implicite (LAYER_INTERACTIVE = 5).

**NICE — optionnel r2 :**

8. **N-1 — Corriger table récapitulatif ACs** : 43 → 52 (correction éditoriale 1 ligne).

9. **N-2 — Reformuler F-SEC-2 cap théorique** : "5 × (5 cr × 3) = 75 cr".

10. **N-3 — Préciser flags body_entered** : ajouter commentaire explicite dans R-SEC-04 sur l'absence de `CONNECT_ONE_SHOT`.

### Amendements GDDs requis (hors Secret System)

| GDD | Amendement | Priorité | Session |
|-----|-----------|----------|---------|
| Checkpoint r2 | Ajouter Secret System dans §Interactions (interfaces get/inject) | BLOCKING pour Secret APPROVED | Avant /create-epics |
| GSM r2 | Ajouter Secret dans §Depended on by + §state_changed consumers | Recommended | Sprint 1 |
| Audio r2.2 | Ajouter bus SECRET_COLLECT + handler secret_collected + sample spec | Recommended | Avant /create-epics |
| Credit r2 | Ajouter EC secret_node == null dans §Edge Cases | Recommended | Sprint 1 |
| HUD r2 | Différencier amplitude tween KILL vs SECRET par SourceKind | Recommended | Avant implémentation HUD |
| Level r5 | Ajouter contrainte queue_free interdite sur SecretCollectVolume_NN dans §Anti-dependencies | Recommended | Sprint 1 |

### Prochaine étape après corrections

Si les 3 BLOCKING ci-dessus sont appliqués : relancer `/design-review secret-system` fresh pour confirmation APPROVED. Le scope des changements est **S (small)** — 1 nouvelle Rule (R-SEC-16), 2 modifications Tuning Knobs, 2 modifications §Dependencies, 3 reformulations ACs. Pas de redesign architectural.

Après APPROVED : `/create-epics secret-system` pour Sprint A backbone (le signal `secret_collected` ferme OQ-CRD-1 de Credit Economy — la boucle économique est alors complète pour playtest 1).
