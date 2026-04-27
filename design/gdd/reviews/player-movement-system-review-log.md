# Review Log — Player Movement System GDD

Historique des reviews indépendantes du GDD `design/gdd/player-movement-system.md`.

---

## Review r4 — 2026-04-23 (game-designer subagent) — P1 corrections appliquées 2026-04-23

**Verdict global** : APPROVED WITH NOTES → **APPROVED** (après application des 3 P1, 2026-04-23, Martin validé auto-mode)

### Actions post-review r4 (2026-04-23)

- [x] **P1 #1 appliqué** — 9 stale refs ADR-0001 propagées à ADR-0001 Accepted 2026-04-21 : Overview l.18, `delta` formula l.156, AC physics tick rate l.460, AC-MV-50 l.539, Decisions Taken l.584, Project Settings code l.600, Revision note Project Settings l.609, Escalations point 2 l.618, Revision cluster 4 l.622 (+ ajout note r4). Valeurs `PHYSICS_TICK_RATE` paramétriques → `60` littéral partout.
- [x] **P1 #2 appliqué** — JUMP_VELOCITY valeur nominale rebasée 7.0 → 7.2 m/s (Tuning Knobs l.329). Nominals recalculés dans Formulas (single 0.875 → 0.926 m ; combo 1.629 → 1.680 m ; output range nominal mis à jour l.257-258). Exemple prototype l.264 conservé historique avec flag « à re-valider Sprint 1 ».
- [x] **P1 #3 appliqué** — ADR-0005 Accepted 2026-04-21 propagé : (a) Escalations point 3 l.619 marqué Accepted + pointeur ADR-0005 ; (b) header Published API signals list l.82 annoté « Liste canonique par ADR-0005 D-2, amendement requis pour changement » ; (c) note CONNECT_DEFERRED l.96 référence ADR-0005 D-5 ; (d) 3 ACs symétriques d'idempotence ajoutés (AC-MV-26 `dash_started` 1×, AC-MV-36 `wall_run_entered` 1×, AC-MV-43 `dash_ended` précède strictement `died` si `die()` pendant Dashing — ADR-0005 VC-4).
- [ ] **P2s non appliqués** (optionnels) — WALL_JUMP_UP range min 6.0 → 6.1 ; note Edge Cases l.304 `emit_mouse_during_disable` obsolète ; DASH_SPEED exception sunset date ; `$WallRayLeft` → `%WallRayLeft` dans AC-MV-34 ; `AC-MV-50` scène test flag ADVISORY. À traiter en passe de polish avant ou pendant Sprint 1.
- [x] **Prêt pour création Epic Player Movement** — plus aucun blocker opérationnel côté GDD.

---


---

### 1. Complétude des 8 sections requises

| Section | Verdict | Notes |
|---|---|---|
| **Overview** | PRESENT & COMPLETE | Paragraphe dense et implémentable. La référence explicite à `PHYSICS_TICK_RATE` ∈ {60, 120} avec `[PENDING ADR-physics-tick-rate]` est maintenant obsolète (ADR-0001 Accepted = 60 Hz). Voir P1 #1. |
| **Player Fantasy** | PRESENT & COMPLETE | Référence Ghostrunner précise, anti-références nominatives, phrase-test concrète pour playtest. Excellent niveau de spécification émotionnelle. |
| **Detailed Rules** | PRESENT & COMPLETE | 10 rules + table états/transitions + interactions cross-system + Published API + accessibility options. Règle d'idempotence `die()` prescrite, priorité wall-run vs double-jump codée. |
| **Formulas** | PRESENT & COMPLETE | 6 formules avec variables typées, ranges, exemples calculés. Invariantes chiffrées et vérifiées aux coins. Seul point de fragilité : WALL_JUMP_UP min borderline (voir P2 #1). |
| **Edge Cases** | PRESENT & COMPLETE | 15 cas documentés avec comportement explicite. Aucun "handle gracefully". Couverture NaN/Infinity, idempotence, pause/respawn, boucle checkpoint, plateformes mobiles scopées hors-MVP. |
| **Dependencies** | PRESENT & COMPLETE | Table bidirectionnelle 10 systèmes. Note de cohérence bidirectionnelle explicite. Interfaces provisoires documentées. |
| **Tuning Knobs** | PRESENT & COMPLETE | 19 knobs (+ 1 post-MVP) avec valeurs, ranges, effets directionnels, invariants, contraintes croisées. Pattern hot-reload documenté. Incohérence mineure `JUMP_VELOCITY` valeur courante 7.0 vs range min 7.2 (voir P1 #2). |
| **Acceptance Criteria** | PRESENT & COMPLETE | 25+ ACs avec IDs stables, classification BLOCKING/ADVISORY, owners, format GIVEN/WHEN/THEN. Couverture : movement, saut, dash, wall-run, mort/respawn, perf, capabilities, états dégénérés, cross-system, feel. |

---

### 2. Findings par priorité

**P0 — Bloquants** (empêchent l'implémentation ou créent une ambiguïté implementeur)

Aucun P0 identifié. Les clusters 1-5 de la r3 ont été correctement propagés. Les blockers précédents sont tous résolus ou explicitement scopés.

---

**P1 — Majeurs** (incohérences, trous qui causeront du rework)

- **P1 #1 — ADR-0001 Accepted mais GDD dit encore "Proposed"** (lignes 18, 156, 584, 600, 609, 618, 622) : ADR-0001 est passé en statut `Accepted` le 2026-04-21 (confirmé lecture ADR). Le GDD contient encore 7 occurrences de `[PENDING ADR-physics-tick-rate]`, `[ADR-0001 Proposed]`, `hypothèse 120 Hz`, et des formulations conditionnelles (`à valider par benchmark`). Cela va induire en erreur tout développeur qui lit le GDD en isolation. La valeur de 120 Hz dans la table des Formulas (ligne 156) est particulièrement dangereuse car elle figure dans la définition du `delta`. **Action** : mettre à jour les 7 occurrences pour refléter ADR-0001 Accepted / 60 Hz définitif. Faible risque de cascade, impact traceabilité élevé.

- **P1 #2 — Incohérence `JUMP_VELOCITY` valeur courante vs range min** (ligne 329 Tuning Knobs) : la valeur courante listée dans Tuning Knobs est `7.0 m/s` mais le range `[7.2, 8.5]` et la note `*r3 : range min 6.0 → 7.2*` indiquent explicitement que 7.0 est sous le minimum. La valeur courante est soit un vestige de prototype non mis à jour, soit intentionnellement conservée pour le prototype avec une note d'exception — mais ce n'est pas indiqué clairement. La formule à la ligne 251 calcule le nominal avec `JUMP_VELOCITY=7.0` ce qui donne `h=0.875 m` (au-dessus du minimum 0.810 m à GRAVITY=28, mais en violation de l'invariant à GRAVITY max). **Action** : soit aligner la valeur courante sur 7.2 m/s (range min) avec recalcul du nominal, soit documenter explicitement l'exception "prototype seul, GRAVITY=28, marge 0.875 m > 0.800 m — acceptable, mais rebaser à 7.2 avant Sprint 1".

- **P1 #3 — ADR-0005 Accepted mais GDD dit encore "PENDING ADR Architecture signaux"** (ligne 619, section Escalations point 3) : ADR-0005 est passé en statut `Accepted` le 2026-04-21 (confirmé lecture ADR). La section Escalations dit encore « À écrire. 9 consommateurs des signaux Movement → direct signals ou EventBus autoload ? Technical-director arbitrage. À lever avant Sprint 1 ». De plus, les migrations GDD listées dans ADR-0005 (PENDING ADR marker, `CONNECT_DEFERRED` note, ACs symétriques `dash_started 1×`, `wall_run_entered 1×`, `dash_ended précède died`) ne semblent pas avoir été appliquées. **Action** : (a) marquer la ligne 619 RÉSOLU par ADR-0005 ; (b) ajouter header commentaire sur la liste signals Published API `# Canonical list per ADR-0005 (D-2). Ajout d'un signal = amendement ADR-0005.` ; (c) transformer la note CONNECT_DEFERRED ligne 96 pour référencer ADR-0005 D-5 ; (d) ajouter 3 ACs symétriques ADR-0005 VC-4 : `AC-MV-XX dash_started émis exactement 1× par transition * → Dashing`, `AC-MV-YY wall_run_entered idem`, `AC-MV-ZZ dash_ended précède died si die() pendant Dashing`.

---

**P2 — Mineurs** (polish, clarifications souhaitables)

- **P2 #1 — WALL_JUMP_UP invariant borderline documenté mais non résolu** (ligne 353) : la section Tuning Knobs / Interactions mentionne explicitement « très borderline (marge -0.004 m), range min effectif ≈ 6.03 m/s. À surveiller au tuning. » La marge négative à la borne min documentée (-0.004 m à WALL_JUMP_UP=6.0) signifie que la borne min publiée viole l'invariant de 0.007 %. Ce n'est pas bloquant (le défaut 6.5 m/s est largement au-dessus), mais le range min devrait logiquement être relevé à 6.1 m/s (arrondi au 0.1 supérieur) pour que la borne publiée soit conservatrice. **Action recommandée** : relever `WALL_JUMP_UP` range min de 6.0 à 6.1 m/s et mettre à jour le commentaire r3.

- **P2 #2 — Cross-doc blocker r2 #2 (`emit_mouse_during_disable`) statut ambigu dans le GDD** (ligne 304, Edge Cases) : la note dit « le Input System DOIT exposer un flag `emit_mouse_during_disable: bool`... Référencé comme blocker r2 #2 (cross-doc) — à lever à la révision du Input System GDD. » Or la review du Input GDD r2 (post-2026-04-21) a résolu ce point différemment : l'Input System expose `Disabled + MouseCaptured` comme état où `mouse_motion` n'est PAS émis pendant le respawn delay (ligne 65 et 252 du GDD Input). La note dans Movement est donc soit obsolète (le contrat a été établi autrement), soit insuffisamment précise (la distinction pause vs respawn est résolue côté Input, pas via flag). **Action recommandée** : mettre à jour la note Edge Cases ligne 304 pour refléter la résolution adoptée par le GDD Input (état `Disabled + MouseCaptured` = mouse_motion non émis) et retirer la référence au « blocker r2 #2 » qui n'est plus ouvert.

- **P2 #3 — Nominal DASH_SPEED 28 m/s < range min 30 m/s : exception prototype sans sunset date** (ligne 338, Tuning Knobs) : la note `†` documente l'exception mais ne fixe pas de date de sunset ni de condition de clôture (« à rebaser à 30 m/s minimum OU documenter comme exception prototype avec MOVE_SPEED=10 »). Sans deadline explicite, cette incohérence peut survivre en production. **Action recommandée** : ajouter une condition de clôture : « la valeur nominale 28 m/s doit être rebassée à ≥ 30 avant le Sprint 1 story `player-movement-dash-basic`. AC-MV-20 utilisera alors la valeur nominale du range, pas l'exception prototype. »

- **P2 #4 — `WallRayLeft` / `WallRayRight` reference incohérente** (ligne 46 vs ligne 528) : la section Detailed Rules (ligne 46) utilise le pattern `%WallRayLeft` (unique-name Godot 4.5+) et le nomme correctement. L'AC-MV-34 (ligne 528) utilise `$WallRayLeft` (path-based, fragilité au renommage). Les deux styles référencent le même node. **Action recommandée** : harmoniser AC-MV-34 pour utiliser `%WallRayLeft` (cohérent avec la prescription Rule 7 et la note godot-specialist F11).

- **P2 #5 — `AC-MV-50` fait référence à une scène de test qui n'existe pas encore** : la scène `tests/scenes/perf_test_movement.tscn` est référencée mais n'est pas encore créée. Ce n'est pas en soi un problème de GDD (c'est une tâche d'implémentation), mais l'AC devrait préciser qu'elle est `[ADVISORY — scène à créer en Sprint 1]` ou déplacer son statut de BLOCKING à ADVISORY jusqu'à ce que la scène existe.

---

### 3. Cohérence transverse

- **Avec input-system.md** : COHERENT avec réserve. Le GDD Input System résout le blocker r2 #2 autrement que la note de Movement l. 304 le prédit (`mouse_motion non émis` pendant `Disabled + MouseCaptured` au lieu d'un flag). Le contrat est en pratique aligné (les deux GDDs aboutissent au même comportement), mais la note Movement est obsolète. ADR-0001 60 Hz est cohérent avec le pattern `was_pressed_this_tick` d'ADR-0004. L'action abstraite `restart` apparaît dans Movement l. 68 et l. 311 — présente dans le Input GDD action table (ligne 49 lu). Cohérent.

- **Avec camera-system.md** : COHERENT. La hiérarchie 3-tier `CharacterBody3D → CameraArm → CameraEffects → Camera3D` est correctement documentée avec attribution de propriétés par étage. `BASE_FOV=90°`, `DASH_FOV_KICK=10°`, `WALL_RUN_TILT_ANGLE=0.35 rad` sont alignés avec le registry `entities.yaml`. La note sur `CameraEffects.rotation.z` vs `CameraArm` est présente et précise.

- **Avec player-combat-system.md** : COHERENT. `velocity` et `transform.basis` exposés. Note explicite interdisant `transform.basis.z` pour l'orientation du sweep (ligne 72). `attacked` signal forward documenté. L'invariant `DASH_DURATION (100 ms) < SWING_DURATION (120 ms)` du registry entities.yaml est cohérent avec DASH_DURATION=0.10 s.

- **Avec entities.yaml** : COHERENT. `RESPAWN_DELAY=0.05 s`, `mouse_sensitivity=0.0022 rad/px` (safe range [0.0005, 0.012]), `BASE_FOV=90°`, `DASH_FOV_KICK=10°`, `WALL_RUN_TILT_ANGLE=0.35 rad` tous alignés. La safe range `mouse_sensitivity` [0.0005, 0.012] est correctement référencée dans Movement UI Requirements et Tuning Knobs. Ownership `mouse_sensitivity` = Input System confirmé dans le registry — Movement consomme seulement. Aucune valeur de combat (KATANA_REACH, etc.) n'est incorrectement citée dans Movement.

- **Avec ADR-0001 (physics 60 Hz)** : PARTIELLEMENT COHERENT — voir P1 #1. Sur le fond, la décision 60 Hz est propagée dans les AC (AC-MV-50 cite `PHYSICS_TICK_RATE × 30 = 1782–1818`), dans les latency budgets de Game Feel, et dans les Project Settings requis. Les formulations conditionnelles résiduelles sont un problème de texte, pas de substance.

- **Avec ADR-0005 (movement signals)** : PARTIELLEMENT COHERENT — voir P1 #3. Les 8 signaux de l'ADR-0005 D-2 sont bien présents dans Published API. Les types de payload sont corrects (Vector3, float). La connexion mode CONNECT_DEFERRED est documentée mais référence le GDD r3 directement plutôt qu'ADR-0005. Les ACs de symétrie d'idempotence (VC-4 de l'ADR-0005) manquent.

---

### 4. Open Questions restantes

| Question | Owner | Bloquant ? | Note |
|---|---|---|---|
| Dash i-frames (100 ms invincibilité) ? | game-designer | Non — décision de playtest | Correctement scopé post-MVP. Non bloquant Sprint 1. |
| Triple-jump (MAX_AIR_JUMPS=2) post-MVP ? | game-designer | Non | Tier 2. Décision conditionnelle au level design. Bien scopé. |
| Plateformes mobiles / rotatives ? | level-designer | Non | Hors MVP, GDD séparé recommandé. Bien scopé. |
| ADR-0001 migration : prototype movement-katana à re-valider 60 Hz | lead-programmer | Oui (avant Sprint 1) | Bloquant mais hors scope de ce GDD. Référencé dans ADR-0001 Migration Plan. |
| ADR Combat Tick Model (gestion `enemy_killed` signal) | lead-programmer | Non (Sprint 1) | Bloquant pour Epic Combat, pas pour Epic Movement. ADR-0005 Amendment r2 documente l'exemption SYNC transitoire. |

**Open Questions dans le GDD toutes non-bloquantes pour l'implémentation du mouvement.** Le seul bloquant restant est extérieur au Movement GDD : le proto à valider en 60 Hz (ADR-0001 Migration Plan action `#2`).

---

### 5. Recommandation

**Ready for implementation ?** Oui, avec 3 corrections textuelles avant le début de Sprint 1.

Les P0 sont absents. Les P1 sont des stale references (ADR-0001 et ADR-0005 passés Accepted depuis la rédaction r3) et une incohérence de valeur nominale mineure. Aucun ne bloque la compréhension ou l'implémentation d'un développeur qui lit aussi les ADRs, mais ils créent une friction inutile.

**Prochaine action recommandée :**

1. **Avant Sprint 1 (non-bloquant pour le GO mais recommandé dans la même passe)** : corriger P1 #1 (7 occurrences ADR-0001 Proposed → Accepted), P1 #2 (rebaser valeur courante JUMP_VELOCITY à 7.2 m/s), P1 #3 (lever PENDING ADR signaux → ADR-0005 Accepted + 3 ACs symétriques + header Published API). Effort estimé < 1 h.
2. **Optionnel (P2s)** : corriger WALL_JUMP_UP range min → 6.1, mettre à jour note Edge Cases l. 304 (`emit_mouse_during_disable` résolu), ajouter sunset date au DASH_SPEED exception, harmoniser `%WallRayLeft` dans AC-MV-34. Effort estimé < 30 min.
3. **GO Epic Player Movement** — créer les epics et stories sprint plan dès les corrections P1 appliquées.

---


## Review — 2026-04-21 (r3) — Verdict: NEEDS REVISION (r4 fresh pending)

**Scope signal** : M (8-12 h doc + 1 h décisions Martin)
**Mode** : full (4 specialists : game-designer, systems-designer, qa-lead, godot-specialist + creative-director senior synthesis)
**Specialists findings** : qa-lead 12 (5 BLOCKING) · game-designer 14 (6 BLOCKING) · systems-designer 9 (7 BLOCKING) · godot-specialist 12 (3 BLOCKING) = **47 total, 21 BLOCKING**
**Prior verdict resolved** : r2 NEEDS REVISION → **appliqué r3 dans la même session** (révision immédiate, pas une fresh session post-review — voir caveat r4 ci-dessous)

### Clusters identifiés (synthèse creative-director)

1. **Cluster 1 — Décisions Martin r2 non propagées** (7 BLOCKING, 4/4 specialists convergent) : A/B/C/D. Application complète r3.
2. **Cluster 2 — Formule wall-jump air-jump cassée à MAX=1** (4 BLOCKING + 1 edge, 3/4 specialists convergent) : ambiguïté levée par widget Martin r3.
3. **Cluster 3 — Invariants numériques violés silencieusement** (3 BLOCKING, systems-designer domaine exclusif) : arithmétique corrigée.
4. **Cluster 4 — Statut ADR contradictoire** (2 BLOCKING, godot-specialist domaine exclusif) : ADRs paramétrés + pending explicit.
5. **Cluster 5 — AC cross-system non implémentable** (1 BLOCKING, qa-lead domaine exclusif) : mock interface inline.

### Décisions design prises (Martin, 2026-04-21, widget r3)

| Question | Décision | Impact |
|---|---|---|
| Wall-jump formule air-jump ? | **A) Wall-jump BLOQUE double-jump** (`air_jumps_used = MAX_AIR_JUMPS`) | Couloir 4 m retiré MVP, Level Grid Spec mis à jour |
| Couloir 4 m post-décision B ? | **Réduire à 3.25 m max dans Level Grid Spec** | Cascade level design, hauteurs conservées |
| Tick rate hypothèse ? | **Paramétrer `PHYSICS_TICK_RATE`** | [PENDING ADR-0001 Proposed] |
| RESPAWN_DELAY 50 ms maintenu ? | **A) Garder 50 ms + AC playtest garde-fou** | `death.wav` et fondu rouge à ≤ 40 ms |

### Désaccord design surfacé

**game-designer F2 ↔ Martin** (RESPAWN_DELAY 50 ms) : game-designer argumente que 50 ms est sous le seuil d'attribution causale (80-150 ms selon Csikszentmihalyi). Martin a maintenu 50 ms en r3. **Résolution creative-director** : appliquer décision Martin + ajouter AC-MV (garde-fou d'attribution causale testable) pour valider empiriquement en playtest MVP. Tension documentée, non renversée.

### Actions post-r3 (en cours pendant la session)

- [x] Décision design prise par Martin (4 widgets answered 2026-04-21 r3)
- [x] Propagation Cluster 1 (décisions A/B/C/D dans Rules, Tuning Knobs, ACs)
- [x] Cluster 2 : formule wall-jump `air_jumps_used = MAX_AIR_JUMPS` propagée
- [x] Cluster 3 : DASH_SPEED range min 30, JUMP_VELOCITY range min 7.2, momentum formule explicite, total chaîne 5.30 m
- [x] Cluster 4 : 3 ADRs marqués explicitement ; ADR-0001 Proposed référencé ; PHYSICS_TICK_RATE paramétré
- [x] Cluster 5 : `MockCombatSystem` interface inline spécifiée
- [x] Cross-doc : `level-grid-spec.md` mis à jour (couloir 4 m retiré MVP) ; `systems-index.md` status In Review
- [x] Format AC-XX-N appliqué à l'ensemble de la section Acceptance Criteria
- [x] ACs coverage gaps ajoutés (AC-MV-25 dash entry velocity.y=0, AC-MV-34 wall-run priority gauche, AC-MV-35 double-jump bloqué post wall-jump, AC-MV-41 died single emission, AC-MV-42 dash cooldown mort standard)
- [x] RECOMMENDED majeures appliquées : Camera hiérarchie 3 nœuds, `is_finite()` pattern velocity, typed signals debug build note, idempotence `die()` early-return prescrit, read-only `get:` pattern GDScript, `%WallRayLeft` unique-name
- [ ] **Session r4 FRESH (obligatoire)** : re-review dans nouvelle session sans biais du travail r3 — `/clear` puis `/design-review design/gdd/player-movement-system.md`. Cible verdict **APPROVED**.
- [ ] ADR-0001 à passer en Accepted après benchmark hardware minimum spec
- [ ] ADR Architecture signaux Movement à écrire (technical-director)

### Caveat r4

La révision r3 a été appliquée **dans la session r3 elle-même** — contrairement à r2 qui était resté en pending avec décisions non propagées. Le verdict r3 reste **NEEDS REVISION** (pas APPROVED) car :

1. La session de révision est **biaisée** : le reviewer et le réviseur sont le même agent. La r4 en fresh session est la vérification indépendante obligatoire.
2. **ADR-0001 reste Proposed** — l'Epic Player Movement ne peut pas démarrer avant Acceptance. Benchmark hardware minimum spec requis.
3. **ADR Architecture signaux Movement** reste à écrire — nécessite arbitrage technical-director.
4. **Dépendances cross-doc** : Input GDD doit exposer `emit_mouse_during_disable` (blocker r2 #2 toujours ouvert côté Input).

### Summary creative-director r3

> « Le GDD est à **une demi-journée de APPROVED** après r3 application. Tous les clusters r3 appliqués. Le reste = vérification indépendante (r4 fresh session) + benchmark ADR-0001 + ADR signaux. Process leçon retenue : les décisions Martin prises en widget doivent être propagées *dans la même session* pour éviter le problème r2 (décisions entendues mais jamais écrites au fichier). Appliqué ici. »

---

## Review — 2026-04-21 (r2) — Verdict: NEEDS REVISION (r3 pending)

**Scope signal** : M (revision restante) / L (implementation post-revision)
**Mode** : full (5 specialists : game-designer, systems-designer, gameplay-programmer, qa-lead, godot-specialist + creative-director)
**Prior verdict resolved** : r1 MAJOR REVISION NEEDED → downgradé à NEEDS REVISION. Clusters A/B/C/E/G confirmés fixés. ADR escalation list présente. Published API + Accessibility Options MVP ajoutés.

### Blockers résiduels (r3 doit fixer) — 6 items

1. **Cross-doc 60 Hz (Input) vs 120 Hz (Movement)** — hard blocker, nouveau, pas présent en r1. Movement déclare 120 Hz en 4 endroits ; Input GDD header dit "60 Hz actuate". ADR requis, cascader dans les deux GDDs.
2. **Edge case line 254 `mouse_motion` pendant pause** — non réconcilié. Movement dit "rotation reste appliquée", Input GDD doit exposer un flag `emit_mouse_during_disable` pour que le contrat fonctionne.
3. **Décision Martin r2 : `RESPAWN_DELAY = 0.2s → 0.05s`** — non appliquée au doc (file instability pendant session). Tuning Knob ligne 296 + rule 9 ligne 50.
4. **Décision Martin r2 : wall-jump consomme un air-jump** (`air_jumps_used = min(used, MAX-1)`). Rule 8 ligne 48 + AC combo ligne 493 + nouvelle AC wall-jump semantics. Note : à MAX=1 la formule donne toujours 0 — clarifier la sémantique exacte.
5. **Décision Martin r2 : Jump buffer post-MVP (split avec Coyote)** — rule 5, Tuning Knob JUMP_BUFFER, AC jump buffer. Conserver Coyote en MVP.
6. **Input GDD : ajouter flag `emit_mouse_during_disable` (règle 6a + API)** — cascade de la décision #2 côté Input.

### Minor / nice-to-have

- Edge case ligne 248 (jump buffer pendant dash) : retirer ou déplacer post-MVP (cohérent avec blocker #5).
- Input-to-pixel latency vs input-to-physics : se clarifie automatiquement une fois blocker #1 résolu.
- Phrasing "~65% Ghostrunner-like" : formule est acceleration `move_toward(65*delta)`, pas ratio.

### Actions post-r2

- [x] Mise à jour `systems-index.md` → "Needs Revision (r3)"
- [x] Review log entry (ce bloc)
- [ ] **Session r3** : appliquer les 6 blockers dans un fichier stable (pas de revision parallèle).
- [ ] **Re-review r3** en fresh session après application (obligatoire, cible verdict APPROVED).
- [ ] ADR `adr-physics-tick-rate.md` (bloqueur #1) avant Sprint 1.

### Summary creative-director

> « La révision r2 est sérieuse et bien exécutée. Published API et Accessibility Options MVP élèvent le doc d'une catégorie. Reste 2 frictions cross-doc + 4 décisions à appliquer — le doc est à une demi-journée de APPROVED. »

## Review — 2026-04-21 — Verdict: MAJOR REVISION NEEDED

**Scope signal** : M (doc revision) / L (implementation post-revision)
**Mode** : full (8 specialists + creative-director senior synthesis)
**Specialists** : game-designer, systems-designer, gameplay-programmer, godot-specialist, performance-analyst, qa-lead, level-designer, ux-designer, creative-director
**Blocking items** : 6 clusters | **Recommended** : 13 | **Nice-to-have** : 6
**Prior verdict resolved** : First review

### Résumé (synthèse creative-director)

> "La boussole pillar est juste, mais les règles ne servent pas encore les piliers — et pour le système #1 risque du projet, ce gap n'est pas acceptable pour entrer en Sprint 1. Une passe de révision focalisée (½ journée de décisions Martin + ½ journée de doc) amène ce GDD à APPROVED. Ne commence pas l'implémentation avant que Cluster A et Cluster B soient réconciliés."

### Bloquants identifiés

1. **Cluster A — Feel vs fantasy (Pillar 1)** : décélération 500 ms, dash 150 ms perceptible, cap post-dash à MOVE_SPEED contredisent "snap crisp binaire"
2. **Cluster B — Formules boundary failures** : max_combo_jump range faux, JUMP_VELOCITY min dangereux (0.56 m saut), transition Dashing→WallRunning absente, DASH_SPEED/MOVE_SPEED sans contrainte ratio
3. **Cluster C — Formule vs prototype (air control)** : GDD dit 100%, prototype fait `move_toward(air_accel=40)` — docs contradictoires
4. **Cluster E — ACs non-testables** : "playtesters ne prononcent jamais…", P99 latence sans méthodo, "sans bloquer transition" non défini, perf AC sans scène, règle 5 sans AC
5. **Cluster G — A11Y WCAG 2.3.1** : flash rouge+blanc 350 ms sans reduce-flash, camera tilt 12° + FOV pulse sans reduce-motion
6. **Cluster F — Level Grid Spec orphelin** : "1 dash = 1 gap 2 m" engage level design sur doc inexistant

### Décisions design prises (Martin, 2026-04-21)

| Question | Décision |
|---|---|
| Air control | ~65% (Ghostrunner-like) — aligner formule ET prototype |
| Slow-mo aérien | Hors MVP — système séparé futur (`aerial-slowmo-system.md`) |
| Feel Cluster A | Full fix : stop instantané + dash court (0.10 s) + momentum conservé |
| Open Questions | Coyote time MVP, Jump buffer MVP, i-frames dash non-MVP |

### Actions post-review

- [x] Décisions design prises par Martin (4 widgets answered 2026-04-21)
- [x] Rewrites du GDD (Clusters A, B, C, E, G + cross-doc + signals + Published API)
- [x] Mise à jour `game-concept.md` pour retirer slow-mo de MVP
- [x] Création `design/levels/level-grid-spec.md` stub
- [x] `systems-index.md` status Player Movement : Designed → Needs Revision
- [ ] **Re-review** `/design-review design/gdd/player-movement-system.md` en session fraîche (obligatoire — sortie du MAJOR REVISION NEEDED)
- [ ] ADR requis (technical-director) : architecture signaux Movement (direct vs EventBus)
- [ ] ADR requis (technical-director) : budget physique 120 Hz + fallback policy
- [ ] Intégration coyote time + jump buffer dans prototype `movement-katana` (0.5 j)
- [ ] Alignement prototype `movement-katana` sur AIR_CONTROL_FACTOR=65 m/s²

### Agent disagreements surfaced

Aucun désaccord frontal. Multiple spécialistes convergent sur :
- Coyote time + jump buffer = décisions MVP, pas questions playtest
- Air control = formule vs prototype à réconcilier, pas question ouverte
- Slow-mo aérien = inconsistance cross-doc à résoudre

### Escalations techniques (hors scope GDD revision)

- **Technical-director** : ADR requis sur budget physique 120 Hz + fallback policy (performance-analyst F1/F2)
- **Technical-director** : ADR requis sur architecture signaux direct vs EventBus autoload (godot-specialist F5)
- **Architect** : décision Jolt CCD pour ShapeCast3D (sera dans Player Combat GDD)
