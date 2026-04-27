# Enemy System — Review r1 — 2026-04-27

> **Reviewer**: game-designer (fresh session — aucune mémoire de la session de design productrice)
> **Review mode**: solo (production/review-mode.txt = "solo")
> **GDD cible**: design/gdd/enemy-system.md — In Design r1 — 528 lignes
> **Date**: 2026-04-27
> **CD-GDD-ALIGN gate**: skipped — solo mode

---

## 1. Verdict Global

**NEEDS REVISION**

Le GDD Enemy System r1 est solide dans sa structure et sa philosophie de design — la Fantasy est exceptionnellement bien écrite et le Player Fantasy est le meilleur de tous les GDDs du studio à ce jour. L'architecture Grunt statique one-shot est correcte, les 8 sections obligatoires sont toutes présentes avec un niveau de détail supérieur à la moyenne. Cependant, il y a **4 BLOCKING** non-négociables, tous convergents sur un seul problème central : le **cross-GDD conflict OQ-ENM-1** sur l'autorité d'émission du signal `enemy_killed` crée une inconsistance architecturale formelle entre Combat r6 (APPROVED) et Enemy r1, et plusieurs conséquences en cascade dans les formules et les dépendances qui doivent être résolues avant que le GDD puisse être APPROVED.

---

## 2. Scope Signal

- **Review mode**: solo (CD-PILLARS skipped, AD-CONCEPT-VISUAL skipped)
- **Specialists consultés**: none (solo mode auto-approve — fresh session reviewer seul)
- **Blocking items**: 4
- **Recommended items**: 7
- **Nice-to-have items**: 5

---

## 3. Completeness Check

### 8 sections obligatoires

| Section | Présente | Qualité | Notes |
|---------|----------|---------|-------|
| 1. Overview | ✅ | Excellente | Scope architectural clair, dual-purpose (infra + player-facing) |
| 2. Player Fantasy | ✅ | Exceptionnelle | Meilleure Player Fantasy de tous les GDDs du studio |
| 3. Detailed Rules | ✅ | Très bonne | 13 Core Rules + States and Transitions table |
| 4. Formulas | ✅ | Bonne | F-ENM-1/2/3 + cross-refs. Une lacune (voir BLOCKING-2) |
| 5. Edge Cases | ✅ | Excellente | 16 edge cases couvrent les scénarios critiques |
| 6. Dependencies | ✅ | Très bonne | Hard + Soft + Cousins + bidirectional check |
| 7. Tuning Knobs | ✅ | Bonne | 7 knobs + per-slot metadata + latents Tier 2+ |
| 8. Acceptance Criteria | ✅ | Bonne | 28 ACs couvrant Logic/Integration/Visual/Perf |

### Sections bonus

| Section | Présente | Notes |
|---------|----------|-------|
| Visual/Audio Requirements | ✅ | Détaillé, asset spec stub présent |
| UI Requirements | ✅ | Correct (pas d'UI Enemy-owned) |
| Open Questions | ✅ | 10 OQs bien formulées, résolutions proposées |
| States and Transitions | ✅ | Table + transitions valides/interdites |
| Interactions with Other Systems | ✅ | Table 8 systèmes couverts |
| Cross-system formula references | ✅ | Table bidirectionnelle |

**Completeness score: 8/8 sections + 5 bonus = COMPLET**

---

## 4. Dependency Graph

### Upstream (systèmes dont Enemy dépend)

| Système | Statut GDD | Direction | Bidirectionnel ? |
|---------|------------|-----------|-----------------|
| Level System | APPROVED r3 | Amont | ✅ Level §header liste Enemy en "Depended on by" |
| Player Combat System | APPROVED r6 | Aval (reçoit appels) | ✅ Combat ligne 270 cite Enemy comme receveur de `die()` |
| Player Movement System | In Review r3 | Aval (indirect) | ⚠️ À confirmer — Enemy GDD ligne 327 note "À confirmer" |
| Game State Manager | APPROVED r1 | Amont | ✅ GSM non explicitement bidirectionnel — acceptable (Enemy est consumer passif) |
| ADR-0008 | Accepted | Contrainte | ✅ LAYER_ENEMY=2, LAYER_ENEMY_HITBOX=3 corrects |

### Downstream (systèmes qui consomment Enemy)

| Système | Statut GDD | Signal consommé | Bidirectionnel dans cible |
|---------|------------|-----------------|--------------------------|
| Audio System | APPROVED r2.1 | `enemy_killed` | ⚠️ Conflit OQ-ENM-1 — Audio pense que Combat émet |
| Credit Economy | Not Started | `enemy_killed` | N/A (pas designé) |
| VFX & Feedback | Not Started | `enemy_killed` | N/A |
| HUD System | Not Started | `enemy_killed` | N/A |
| Checkpoint & Respawn | Not Started | `is_dead()`, `_restore_from_snapshot()` | N/A |
| Hazard System | Not Started (Tier 2+) | appelle `die()` | N/A |

**Upstream DESIGNED: 4/4 (Level ✅, Combat ✅, Movement ⚠️, GSM ✅)**
**Downstream not-started: 5/5 (acceptable — registre les contrats)**

---

## 5. BLOCKING Items

| # | Item | Source | Lignes GDD | Convergence |
|---|------|--------|-----------|-------------|
| B-1 | OQ-ENM-1 : Combat GDD APPROVED r6 émet `enemy_killed` (ligne 286 Combat) mais Enemy r1 dit Enemy émet (Rule 11 ligne 128). Deux GDDs APPROUVÉS ou en cours d'approbation avec des claims contradictoires sur l'autorité d'émission. | Reviewer frais + Combat r6 §Published API | enemy:128, combat:177, combat:270, combat:286 | Cross-GDD structural |
| B-2 | LaserCone body_mask incohérent dans le GDD : l'Overview ligne 12 dit `LAYER_ENEMY_HITBOX = layer 3` mais la collision table Rule 4 (ligne 76) dit le LaserCone est sur `layer 4 (LAYER_ENEMY_HITBOX bit)`. Dans Combat GDD ligne 208 la table assigne LAYER_ENEMY_HITBOX = 3 = `0b00100` bit 2. La collision table Enemy §Rule 4 colonne Layer dit "4 (LAYER_ENEMY_HITBOX bit)" — c'est le **bit index 4** ou le **layer number 4** ? Ambiguïté 1-indexé vs 0-indexé non résolue dans la table elle-même. AC-ENM-06 dit `0b00000100` (bit 2 = layer 3 1-indexed) mais Rule 4 dit "layer 4". | Reviewer frais | enemy:76, enemy:453 |  Cross-doc structural |
| B-3 | F-ENM-3 : le death tween utilise `create_tween()` (Rule 11.d ligne 129) mais Godot 4.6 Tween créé via `create_tween()` sur un nœud est automatiquement pausé quand `tree.paused = true` par défaut (`TWEEN_PAUSE_BOUND`). OR, la formule F-ENM-3 (ligne 228) dit « wall-clock ABSOLU (pas Engine.time_scale-affected — utilise `Time.get_ticks_msec()` delta) ». Ces deux affirmations sont contradictoires : un `create_tween()` bound à l'arbre SERA pausé par GSM. Pour que le tween soit wall-clock absolu, il faut `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` explicitement. Sans ça, EC-ENM-9 (ligne 278) est incohérent avec F-ENM-3. | Reviewer frais — vérification Godot 4.6 API | enemy:129, enemy:228, enemy:278 | Godot API |
| B-4 | Bidirectionalité Movement GDD non confirmée (ligne 327 : "À confirmer") : Enemy appelle `Player.die()` via LaserCone body_entered. Movement GDD r3 doit explicitement documenter qu'Enemy appelle sa méthode `die()`. Le reviewer note que Movement est "In Review r3" et que ce contrat est "pending re-review fresh". La dépendance existe dans le code mais l'autorité documentaire est manquante. Un GDD ne peut être APPROVED si une dépendance critique a un contrat unilatéral non confirmé. | Reviewer frais | enemy:327, systems-index:24 | Missing bidirectional |

---

## 6. RECOMMENDED Items

| # | Item | Justification |
|---|------|---------------|
| R-1 | Préciser l'ordre d'exécution entre `LaserCone.monitoring = false` (Rule 11.b) et `enemy_killed.emit()` (Rule 11.c) dans `die()`. Le pseudocode Rule 6 montre l'ordre correctement (`_state → emit → tween`), mais Rule 11 liste les étapes a/b/c/d en ordre différent (a=state, b=monitoring=false, c=emit, d=tween). L'ordre b avant c est CRITIQUE : si `enemy_killed` est émis avant `LaserCone.monitoring = false`, le consumeur VFX pourrait spawner un effet AVANT que le cône ne soit désactivé — fenêtre de 1 tick où le cône peut encore tuer. | Précision impl |
| R-2 | EnemySpawner : OQ-ENM-2 recommande "Service ad-hoc — LevelSystem instancie ses grunts directement". Si tel est le cas, le contrat API `LevelSystem.get_etage_enemy_slots() -> Array[Marker3D]` (Interactions table ligne 163) est inutile — c'est Level qui fait le spawn, pas un EnemySpawner qui appelle Level. Cette tension dans le design doit être résolue : soit Level spawne (pas d'API get_etage_enemy_slots exposée), soit un EnemySpawner consume l'API. L'une des deux descriptions du GDD est à supprimer. | Clarity / impl ambiguity |
| R-3 | AC-ENM-13 (ligne 473) dit "Audio reçoit `enemy_killed` via signal connection au tick T". Cette assertion dépend directement de la résolution OQ-ENM-1 : si Combat est l'émetteur, Audio se connecte à Combat, pas à Enemy. L'AC ne peut être correcte dans les deux configurations. Mettre l'AC en dépendance conditionnelle de la résolution OQ-ENM-1 ou reformuler en un AC plus neutre (testé après résolution). | AC correctness |
| R-4 | `DEATH_TWEEN_DURATION_MS = 150 ms` est déclaré `const` dans Tuning Knobs (ligne 334) mais le registry entities.yaml (ligne 69) présente une valeur alternative : `death_tween_duration_ms: 400 if reduce_motion=true`. Cette valeur de 400 ms n'est ni documentée dans le GDD ni dans les Tuning Knobs. Réduite mobilité = motion sensitivity ? La valeur 400 doit apparaître dans les Tuning Knobs avec son safe range, ou être retirée du registry jusqu'à ce que Accessibility System soit designé. | Consistency registry/GDD |
| R-5 | Rule 13 (ligne 137-141) décrit la persistance inter-respawn avec un `set_meta` / `get_meta` pattern sur les nœuds Enemy. Ce pattern est fonctionnel mais fragile pour Checkpoint System (future dépendance) : si Enemy est `queue_free()`'d (unload étage), les metas disparaissent avec le nœud. Le GDD documente bien que `queue_free` n'arrive pas au MVP (Rule 12), mais le Checkpoint GDD futur devra assumer une API plus robuste. Recommander d'upgrader vers une méthode `get_state_snapshot() -> Dictionary` au lieu de `set_meta` pour préparer le Checkpoint GDD. | Future-proofing API |
| R-6 | EC-ENM-5 (ligne 270) : "Player.die() doit être idempotent côté Movement (Movement GDD Rule die())". Ce contrat est cité mais non vérifié — Movement est In Review r3 et "pending re-review fresh". Ce cross-contract est critical et doit être tracé formellement dans l'AC (cross-link AC-ENM-05 ↔ AC movement idempotence). | Cross-AC traceability |
| R-7 | La section Visual/Audio mentionne "le rouge est saturé et fluo" (ligne 381) avec `emission_energy_multiplier = 3.0`. Le GDD game-concept §Visual Identity Anchor dit "la seule couleur d'accent rouge réservée à l'hostile". Ces deux statements sont alignés, mais le GDD Enemy ne cite pas explicitement l'art-bible ni le Visual Identity Anchor — il devrait (cross-ref formelle) pour éviter que le grunt soit visuellement re-designé sans mettre à jour Enemy GDD. | Traceability art-bible |

---

## 7. NICE-TO-HAVE Items

| # | Item |
|---|------|
| N-1 | AC-ENM-21 (30 grunts perf budget) — le budget 0.5 ms cumulé est raisonnable mais non justifié mathématiquement. Un calcul type "30 grunts × 0 _physics_process (désactivé Rule 10) + 30 × signal overhead ≈ X µs" renforcerait l'AC. |
| N-2 | Les tuning knobs sont tous des `const` au MVP "par simplicité" (ligne 334). Le CLAUDE.md studio dit "Gameplay values must be data-driven (external config), never hardcoded". Recommander de migrer vers `enemy_constants.gd` ou `.tres` dès r1 pour respecter les standards, même si le scope est petit. |
| N-3 | F-ENM-2 donne la position du centre du BoxShape comme `Grunt.%FacingPivot.global_position + FacingPivot.basis.z * (LASER_RANGE_M / 2)`. Cette formule suppose que `FacingPivot.global_position == Grunt.global_position`, ce qui n'est vrai que si FacingPivot a offset 0. La hiérarchie Rule 3 ne précise pas la position relative de FacingPivot dans Grunt. Ajouter explicitement `FacingPivot.position = Vector3.ZERO` dans la spec de la hiérarchie. |
| N-4 | EC-ENM-3 analyse le cas de tick-order combat vs body_entered avec "DFS preorder". Cette analyse est juste pour `_physics_process` de GDScript nodes, mais les signaux physics (`body_entered` depuis Jolt) sont émis en milieu de physics step, pas strictement DFS. L'EC est correct dans ses conclusions (Option A/B) mais l'explication du mécanisme est légèrement inexacte — "ordre DFS preorder du scene tree" s'applique aux _physics_process callbacks, pas directement aux signaux Area3D. Affiner la formulation pour éviter confusion implémentation. |
| N-5 | OQ-ENM-6 recommande `laser_active = true` cône hors path pour onboarding. Cette décision a un impact direct sur Level System (authoring première salle). La recommandation devrait être croisée avec Level GDD OnboardingAnchors rule (Level GDD Rule 16 Combat onboarding). Trace explicite manquante. |

---

## 8. OQ-ENM Resolutions

| OQ | Verdict | Recommandation | Rationale |
|----|---------|----------------|-----------|
| **OQ-ENM-1** | **RESOLVED — Enemy émet** | Enemy est l'autorité d'émission de `enemy_killed`. Combat GDD doit être amendé r7 : Rule 9 "émet `enemy_killed`" → "écoute `enemy_killed`" (Enemy en émet la source) ; ligne 286 Published API : supprimer `enemy_killed` du signal list de CombatSystem ; Credit Economy, VFX, Audio se connectent à Enemy.enemy_killed, pas à CombatSystem.enemy_killed. | (1) **Hazard Tier 2+** : un Hazard peut appeler `enemy.die()` sans passer par Combat — si Combat était l'émetteur, les kills Hazard seraient silencieux pour Credit/VFX/Audio, ce qui est un bug architectural garanti. (2) **Cohérence sémantique** : l'ennemi sait quand il meurt — c'est son signal. Combat sait qu'il a frappé — c'est le rôle de `swing_started/ended`. (3) **Idempotence déjà résolue** : Enemy.die() idempotent garantit un seul emit. La double-sécurité `_hit_this_swing` de Combat reste valide pour éviter les appels multiples à `die()`. (4) **Slow-mo Combat Rule 13** : Combat réagit à `enemy_killed` (Enemy-emitted) pour déclencher `Engine.time_scale = 0.3` — c'est la bonne direction causale : le grunt meurt → Combat réagit au kill → slow-mo. L'inverse (Combat émet → Combat réagit) serait un self-loop architectural. (5) **Alignement Audio** : Audio GDD r2.1 dit "Audio écoute `enemy_killed` signal" sans préciser la source — la résolution "Enemy émet" est transparente pour Audio. |
| **OQ-ENM-2** | **RESOLVED — LevelSystem spawne directement** | LevelSystem instancie ses grunts au signal `level_active` en itérant sur ses propres nœuds `EnemySlot_*`. Pas d'autoload `EnemySpawner` séparé au MVP. L'API `LevelSystem.get_etage_enemy_slots()` est retirée de la Interactions table Enemy — obsolète. | Cohérence avec architecture Level System APPROVED r3 (Level possède la scène d'étage et ses occupants). Un autoload séparé serait une indirection sans valeur au MVP (1 archetype, logique triviale). LevelSystem devient la factory de grunts, ce qui est naturel : il connaît les slots. Si Tier 2+ nécessite un EnemyManager plus complexe, l'API peut être extraite alors. |
| **OQ-ENM-3** | **RESOLVED — BoxShape3D MVP** | Conserver `BoxShape3D` pour le LaserCone MVP. `CylinderShape3D` n'existe pas en Godot 4.6 (la forme disponible est `CapsuleShape3D`). Le rectangle 0.5 × 0.3 × 6 m est plus prévisible pour le joueur (side-step mesurable) et plus léger en collision check. | Lisibilité Pillar 1 > précision géométrique. Le visual EmissiveMesh peut être un quad incliné pour suggérer la forme de cône sans que la hitbox physique soit un cône. Playtestable Sprint A. |
| **OQ-ENM-4** | **DEFERRED → Sprint A (Credit Economy GDD)** | Valeur provisoire 1 crédit/kill acceptable. Credit Economy GDD doit figer la valeur en fonction du nombre d'upgrades et du nombre de salles par étage. | L'économie entière (faucets/sinks) doit être modelée dans Credit Economy GDD avant de fixer CREDIT_VALUE["grunt"]. Valeur 1 est une borne basse raisonnable pour tester l'équilibre. |
| **OQ-ENM-5** | **RESOLVED — sample universel clac** | Un seul sample `combat_kill_clac.wav` partagé tous archétypes, pitch-shift +2/+4 semitones pour multi-kill (Audio GDD r2.1 Rule 13 figé). Aucune décision supplémentaire Enemy à prendre. | Audio GDD r2.1 APPROVED a déjà figé ce contrat. La décision Enemy est triviale : "se conformer à Audio GDD r2.1 Rule 13". |
| **OQ-ENM-6** | **DEFERRED → Sprint B (authoring Level 1)** | Recommandation `laser_active = true` cône hors path. La décision finale doit être prise par le level designer quand il layout la salle 1 et observe le comportement de 5 playtesters naïfs. Un test A/B rapide (5 runs `laser_active=false` vs 5 runs `laser_active=true` orienté hors path) tranchera empiriquement. | Pillar 4 FLOW et la grammaire visuelle "rouge = hostile" plaident pour `laser_active=true`, mais l'argument pédagogique de "première salle safe" est valide. Empirique > théorique ici. |
| **OQ-ENM-7** | **DEFERRED → Tier 2** | Pas d'ADR Enemy au MVP. ADR-0012 à créer quand archétypes mobiles (pathfinding, behavior tree) arrivent. | Le Grunt MVP est tellement simple (statique, 0 IA) qu'un ADR ajouterait uniquement de la bureaucratie sans valeur architecturale. ADR-0006 Combat Tick Model couvre déjà l'ordre tick/signal critique. |
| **OQ-ENM-8** | **RESOLVED — aucune animation MVP** | Fixture pure, aucune animation idle. | Pillar 1 lecture instantanée serait dégradée par un micro-tilt qui attire l'attention sur le grunt plutôt que sur son cône. Scope creep évident. |
| **OQ-ENM-9** | **DEFERRED → Sprint B (Checkpoint GDD)** | Signature `_restore_from_snapshot(was_dead: bool)` au MVP. API enrichie (`state: State`, `position: Vector3`) au Checkpoint GDD si Tier 2+ ennemi mobile. | Signature minimale suffit pour 1 archetype statique. L'expansion naturelle quand Checkpoint GDD est designé. |
| **OQ-ENM-10** | **DEFERRED → Sprint C (perf benchmark)** | AC-ENM-21 budget 30 grunts / 16.6 ms p99 à valider empiriquement sur build intégré (Movement + Combat + Level + Audio + Enemy cumulé). | Les 30 grunts n'ont pas de `_physics_process` actif (Rule 10) — le coût est presque nul. Le benchmark est une validation de confiance, pas une correction probable. |

---

## 9. Cross-GDD Conflicts

### Conflict 1 — OQ-ENM-1 : Autorité du signal `enemy_killed`

**Description** : Combat GDD APPROVED r6 déclare `enemy_killed(enemy: Node, position: Vector3)` dans sa §Published API (combat:286) comme un signal de CombatSystem, émis dans Rule 9 (combat:177). Enemy GDD r1 Rule 11 (enemy:128) stipule que Enemy émet ce signal depuis `die()`. Deux GDDs ont des claims en conflit sur qui émet ce signal.

**Résolution** : Enemy est l'autorité d'émission (voir OQ-ENM-1 ci-dessus).

**Action requise** : Amendement Combat GDD r7 (à écrire par le session Combat — NE PAS modifier Combat GDD dans cette session) :
- combat:177 (Rule 9) : supprimer "Chaque kill traité émet `enemy_killed(enemy: Node, position: Vector3)`" → remplacer par "Combat appelle `enemy.die()` sur chaque collider hit. Le signal `enemy_killed` est émis par Enemy lui-même depuis `die()`."
- combat:270 (Interactions table Enemy row) : "Combat émet `enemy_killed(enemy: Node, position: Vector3)` signal que l'Enemy System peut connecter" → "Combat appelle `enemy.die()`. Enemy émet `enemy_killed` que Combat connecte pour déclencher slow-mo (Rule 13)."
- combat:286 (Published API) : retirer `enemy_killed` du signal list de CombatSystem. CombatSystem ne déclare plus ce signal — il le consomme depuis Enemy.
- Conséquences consumers : Credit Economy, VFX, Audio, HUD se connectent désormais à `Enemy.enemy_killed`, pas `CombatSystem.enemy_killed`. Audio GDD r2.1 ne cite pas la source explicitement — pas de changement requis sur Audio. Credit Economy, VFX, HUD (Not Started) doivent design avec Enemy comme source.

### Conflict 2 — Collision layer LAYER_ENEMY_HITBOX : numérotation ambiguë

**Description** : Rule 4 (enemy:76) dit "layer 4 (LAYER_ENEMY_HITBOX bit)" pour le LaserCone. Combat GDD Rule 12 (combat:208) dit LAYER_ENEMY_HITBOX = 3 = `0b00100`. AC-ENM-06 dit `0b00000100` (bit 2 = layer 3 en convention Godot 1-based). Le chiffre "4" dans la table Enemy est probablement le bit 4 en notation 1-based (= `0b01000` = layer 4), ce qui contredit Combat.

**Impact** : Si Enemy LaserCone est configuré avec `set_collision_layer_value(4, true)` (Godot 1-based = bit 3 = `0b01000` = LAYER_ENVIRONMENT) au lieu de `set_collision_layer_value(3, true)` (bit 2 = `0b00100` = LAYER_ENEMY_HITBOX), le cône ne tuera jamais le joueur et le projet sera non-fonctionnel.

**Résolution** : LAYER_ENEMY_HITBOX = bit `0b00100` = layer number 3 (1-indexed Godot) = registry constant value 3. La table Rule 4 dans Enemy contient un typo — "layer 4" doit être "layer 3". AC-ENM-06 est correct (`0b00000100`).

**Action requise** : corriger enemy:76 "layer 4 (LAYER_ENEMY_HITBOX bit)" → "layer 3 (LAYER_ENEMY_HITBOX, 1-indexed Godot convention)".

### Conflict 3 — Movement bidirectionalité non confirmée

**Description** : Enemy GDD ligne 327 note "⚠️ À confirmer dans Movement GDD r3 — pending re-review fresh". Enemy appelle `Player.die()` mais Movement GDD n'a pas encore été re-reviewé après r3. Ce contrat est unilatéral côté Enemy.

**Résolution** : non-bloquant immédiatement pour l'approbation Enemy (Movement GDD r3 ne sera pas modifié dans cette session), mais doit être résolu quand Movement passe en re-review r4. Tracer comme dépendance de gate.

---

## 10. Pillars Alignment

| Pillar | Couverture dans Enemy GDD | Verdict |
|--------|--------------------------|---------|
| **Pillar 1 — FLOW AVANT TOUT** | Le Grunt statique sans `_physics_process` (Rule 10), la mort instantanée (Rule 1), le tween 150 ms rapide (F-ENM-3), le LaserCone désactivé à l'instant de `die()` (Rule 11.b) — tout cela sert FLOW. La lecture instantanée en < 0.5 s est une target spécifiée (Player Fantasy §1). | ✅ Bien servi |
| **Pillar 2 — LA PROGRESSION SE VOIT** | Non directement servi — Enemy System n'interagit pas avec le Shop ni les upgrades. Les grunts du même étage redeviennent accessibles / restent morts post-upgrade = indirect mais présent via la persistance Rule 12-13. | ⚠️ Servi indirectement (correct pour ce système) |
| **Pillar 3 — SECONDE CHANCE N'EST JAMAIS LOIN** | Rule 12 (pas de queue_free), Rule 13 (persistance mort entre respawns), Player Fantasy §4 "mort pédagogique" — c'est le pilier le mieux servi du GDD. | ✅ Excellent |
| **Pillar 4 — SECRETS RÉCOMPENSENT LE MOUVEMENT** | Mentionné dans le header "Pillar 4 (positionnement spatial pour secrets — indirect)". Correct — Enemy n'est pas le système des secrets. La menace du cône crée la nécessité de mouvement, qui rend les secrets accessibles. | ✅ Bien aligné (rôle indirect approprié) |

**Pillar sur-investi** : aucun. Le GDD évite de déborder dans la responsabilité d'autres systèmes.
**Pillar sous-investi** : Pillar 2 — logiquement correct (Enemy n'est pas un système de progression), mais le GDD pourrait mentionner explicitement que la visibilité de la progression via Enemy se manifeste dans l'architecture Level (grunts à côté de secrets inaccessibles qui le deviennent).

---

## 11. AC Quality Audit

### Vue d'ensemble 28 ACs

| Groupe | Nb | Types | Conformité naming | Coverage EC |
|--------|----|-------|-------------------|-------------|
| Core invariants | 7 (AC-01 à 07) | Logic × 7 | ✅ | EC-1/2/3/4 ✅ |
| Spawn et orientation | 3 (AC-08 à 10) | Integration × 3 | ✅ | EC-6/7/16 ✅ |
| Death sequence | 2 (AC-11 à 12) | Logic × 2 | ✅ | F-ENM-3 ✅ |
| Cross-system integration | 3 (AC-13 à 15) | Integration × 3 | ✅ | EC-3/14/5 ✅ |
| Persistance respawn | 3 (AC-16 à 18) | Integration × 3 | ✅ | EC-11/12/13 ✅ |
| Pause / state | 2 (AC-19 à 20) | Integration × 1, Logic × 1 | ✅ | EC-9/10 ✅ |
| Performance | 2 (AC-21 à 22) | Perf × 2 | ✅ | — |
| Authoring lints | 3 (AC-23 à 25) | Logic × 3 | ✅ | EC-6/7/8 ✅ |
| Visual / Feel | 3 (AC-26 à 28) | Visual × 3 | ✅ | Playtest ✅ |

### ACs conformes au format studio

Format `**AC-ENM-NN [type]** : GIVEN ... WHEN ... THEN ...` : ✅ 28/28 conformes.

### ACs problématiques

| AC | Problème |
|----|---------|
| **AC-ENM-13** | Dépend de la résolution OQ-ENM-1 : "Audio reçoit `enemy_killed` via signal connection au tick T" est faux si Combat reste l'émetteur. Après résolution OQ-ENM-1 (Enemy émet), reformuler : "Audio reçoit `enemy_killed` depuis Enemy, pas depuis CombatSystem." |
| **AC-ENM-19** | Dépend de la résolution BLOCKING-3 (tween wall-clock vs pause). Si le tween n'est pas `TWEEN_PAUSE_PROCESS`, l'AC est non-testable comme spécifié. |
| **AC-ENM-12** | Cohérent avec F-ENM-3 (wall-clock via `Time.get_ticks_msec()`), mais la résolution BLOCKING-3 doit être appliquée avant que l'AC soit testable. |

### ACs manquants identifiés

| AC manquant | Type | Justification |
|-------------|------|---------------|
| `enemy.is_dead()` renvoie `false` quand ALIVE, `true` quand DYING ou DEAD | Logic | Getter public utilisé par Checkpoint — non couvert explicitement |
| `_restore_from_snapshot(true)` sur DYING : tween kill + DEAD direct | Logic | EC-ENM-13 describe mais aucun AC ne couvre `is_in_state(DYING)` entrée |
| Normalisation `EnemySlot.global_basis.orthonormalized()` au spawn (EC-ENM-6) | Logic | L'orthonormalisation forcée de Rule 9 / EC-ENM-6 n'a pas d'AC de validation |

---

## 12. Game Design Theory Red Flags

### Dominant strategies

**Aucune détectée pour le Grunt MVP** — le design est intentionnellement asymétrique (joueur = mobilité, grunt = fixture). La seule stratégie optimale (approcher par le côté/dos) est exactement la stratégie *intended*. Pas de dominant strategy parasitaire.

**Risque futur Tier 2+** : si des archétypes mobiles arrivent sans varier leur faiblesse géométrique (toujours côté/dos), le vocabulaire de combat devient répétitif. Mention utile pour le Tier 2 GDD Enemy v2.

### Cognitive overload

**Grunt MVP : charge cognitive minimale** — un seul pattern à lire (cône rouge = zone mort, dehors du cône = safe). Correct. Le GDD cible < 0.5 s de lecture (Player Fantasy §1).

**Risque 30 grunts par étage** : avec 30 grunts simultanément visibles dans un espace multi-salles, la charge de lecture visuelle peut dépasser le budget attentionnel. Le GDD ne modélise pas cela explicitement. AC-ENM-21 mesure la perf mais pas la lisibilité au-delà de 5-6 grunts simultanément visibles. ADVISORY — à suivre en playtest.

### Balance

**One-shot mutuel : balance parfaitement transitive** — le grunt est rigoureusement symétrique (1 PV joueur, 1 PV grunt). Aucun déséquilibre possible dans ce modèle. La seule variable est le positionnement (hors portée = safe), ce qui favorise la compétence. Correctement ancré dans le design.

**LaserCone dimensions** : LASER_WIDTH_M = 0.5 m est étroit (player capsule ~0.8 m de diamètre — à vérifier contre Movement GDD). Le side-step marge de 0.1 m mentionné en F-ENM-2 suppose `player_radius = 0.4 m`. Si Movement GDD définit une capsule différente, la marge side-step change. Vérification nécessaire à l'intégration.

### Feedback loops

**Loop positif fonctionnel** : tuer grunt → crédits → upgrades → accès à plus de secrets → plus de crédits → etc. Cycle correct.

**Risque feedback négatif** : si un grunt tue le joueur juste avant un checkpoint, la frustration peut être supérieure à la pédagogie (Pillar 3 promesse). Le GDD adresse cela via la mort pédagogique (grunt reste visible) mais ne teste pas la valeur psychologique de la résilience. AC-ENM-28 (3 tentatives max réussite) est la bonne validation — bien présente.

---

## 13. Solo Gate Status

**CD-GDD-ALIGN gate** : skipped (solo mode confirmé — production/review-mode.txt = "solo").

**Gate QL-TEST-COVERAGE** : skipped (solo mode).

**Gate LP-CODE-REVIEW** : skipped (solo mode, pas de code implémenté).

---

## 14. Recommandation Suite

**Verdict : NEEDS REVISION**

### Changements requis avant approbation (dans l'ordre de priorité)

1. **B-2 (BLOCKING) — Corriger typo layer collision table** : enemy:76 "layer 4" → "layer 3 (1-indexed Godot convention)". Changement éditorial 1 ligne.

2. **B-3 (BLOCKING) — Tween wall-clock vs pause** : Rule 11.d doit ajouter `tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` explicitement. F-ENM-3 doit noter que cette ligne est obligatoire pour garantir le wall-clock. EC-ENM-9 reste correct mais doit noter la dépendance au pause_mode. 3-4 lignes de corrections.

3. **B-4 (BLOCKING) — Note de dépendance Movement** : la note "⚠️ À confirmer" (ligne 327) peut rester dans le GDD actuel, mais doit être marquée comme condition de gate pour l'approbation finale : `enemy-system APPROVED iff movement-system re-review r4 confirme le contrat die() bidirectionnel`. Ajouter en note de bas de GDD.

4. **OQ-ENM-1 résolution + R-2 (BLOCKING + RECOMMENDED)** : 
   - Rule 11.c : confirmer que Enemy émet `enemy_killed` (déjà le cas — juste clarifier que Combat ne le ré-émet pas).
   - Interactions table : clarifier que Credit Economy, VFX, HUD se connectent à **Enemy.enemy_killed**, pas à CombatSystem.enemy_killed.
   - Note explicite : "Post-résolution, un amendement Combat r7 est nécessaire pour retirer `enemy_killed` du Published API de CombatSystem".
   - Supprimer `LevelSystem.get_etage_enemy_slots()` de la Interactions table si OQ-ENM-2 est résolu (LevelSystem spawne directement).

5. **R-4 (RECOMMENDED) — Registry/GDD align sur reduce_motion=true (400 ms)** : soit documenter dans Tuning Knobs la valeur de 400 ms (avec Accessibility System comme dépendance conditionnelle), soit retirer du registry jusqu'à ce que l'Accessibility System soit designé.

6. **ACs manquants** : ajouter les 3 ACs identifiés (is_dead() getter, _restore_from_snapshot sur DYING, orthonormalisation spawn).

### Amendement Combat GDD r7 requis

Cette review identifie formellement les modifications nécessaires au Combat GDD r6 (APPROVED) :

```
Amendment List pour Combat GDD r7 :
- combat:177 (Rule 9, multi-hit) : retirer "émet enemy_killed"
  → "Combat appelle enemy.die() — Enemy émet son propre signal enemy_killed"
- combat:270 (Interactions table Enemy row) : rewrite sentence
  → "Combat appelle enemy.die() au hit. Enemy émet enemy_killed que
     Combat connecte pour déclencher slow-mo Rule 13."
- combat:286 (Published API signals) : supprimer signal enemy_killed
  de la liste des signaux émis par CombatSystem. Ajouter commentaire
  "enemy_killed est émis par Enemy System — Combat en est consumer."
- combat:272 (Credit Economy row) : mettre à jour
  → "Credit Economy connecte Enemy.enemy_killed (pas CombatSystem)"
- combat:273 (VFX row) : mettre à jour
  → "VFX connecte Enemy.enemy_killed (pas CombatSystem.enemy_killed)"
```

**NE PAS modifier Combat GDD dans cette session** — ces modifications sont tracées pour la session Combat r7.

### Prochaine étape après corrections

Si les 6 points ci-dessus sont appliqués : relancer `/design-review enemy-system` fresh pour confirmation APPROVED. Le scope des changements est **S (small)** — pas de redesign architectural, uniquement corrections éditoriales + clarifications + 3 ACs + 1 amendement de résolution OQ.

Après APPROVED : `/create-epics enemy-system` pour Sprint A (OQ-ENM-1 résolu, OQ-ENM-2 résolu, archetype grunt implémentable).
