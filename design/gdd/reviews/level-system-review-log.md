# Level System — Review Log

Historique de révisions du GDD `design/gdd/level-system.md`.

---

## Review — 2026-04-23 (r2 fresh lean solo, post CD 5 fixes applied)

**Verdict** : **APPROVED WITH MINOR OBSERVATIONS** (mergeable Sprint 1)
**Scope signal** : N/A — pas de r3 requis, 0 edit éditoriale restante
**Specialists** : game-designer (solo lean fresh session, pas de delegation)
**Blocking items** : 0 | Recommended : 0 | Minor : 2 (non-bloquants)
**Détail** : [`level-system-review-r2-fresh-2026-04-23.md`](level-system-review-r2-fresh-2026-04-23.md)

### Résolution 5 fixes CD (cross-model top 5 ranked du full review r1)

**5/5 ✅ RESOLVED CLEAN** :
1. ✅ `VerticalShaftRoom` + F5 multi-rise : primitive PackedScene 8-15m rise, ETAGE_HEIGHT_MAX=60m, PF ligne 24 annotée puits-primitive (non-métaphore)
2. ✅ Hiérarchie 3D + archetypes : enum `RoomArchetype { TRAVERSAL, COMBAT, SHAFT, SECRET_HUB }` formel, 4 primitives (Mezzanine/Atrium/ShaftConnector/VerticalShaftRoom), alias compat r1
3. ✅ R-2 invariants locaux : R-2.U (2 universels registry-dérivés) + R-2.A (table 9 invariants × 4 archetypes)
4. ✅ SecretLureMarker ≠ SecretCollectVolume ≠ SecretAnchor : 3 nœuds distincts, tuple NN strict (AC-LVL-53), required_ability sur LureMarker
5. ✅ R-4 budget per-archetype + OnboardingAnchors : Combat Rule 16 tracé (FirstEnemySightline + SafeZoneCenter), AC-LVL-54 gate

### Résolution 3 BLOCKING r2 lean (SUPERSEDED review absorbés)

**3/3 ✅ RESOLVED** :
- ✅ 4 ACs cassées → Groupe G AC-LVL-46..50 rédigé (F7/F3/F5/F6/R-2.6 S-1/S-3/S-5) + bonus AC-LVL-51 (checkpoint spacing edge-case) + Groupe H AC-LVL-52..55 (CD fixes)
- ✅ PF 40m vs F5 30m → ETAGE_HEIGHT_MAX=60m + Shaft rise [8,15]m + PF annotation structurelle
- ✅ enum LevelState prose-only → bloc GDScript formel lignes 181-186

### MINOR observations (non-bloquants Sprint 1)

1. **Budget cross-cap F2 vs R-4 per-archetype** : distribution S-compliant extrême (4 COMBAT + shaft + hub + 4 traversal = 356 DC) excède cap 350. AC-LVL-55 détecte au lint — pas besoin d'amendement GDD. Recommandation Option C (laisser AC-LVL-55 arbitrer, Sprint 1 affine si rejets fréquents).
2. **EC-8 Jolt CCD** : reste CLAIM-UNVERIFIED dans r2 — bonne posture, benchmark prototype Sprint 1 par lead-programmer / godot-specialist (aligné gaps empiriques ADR-0006). Pas d'amendement GDD requis.

### Senior verdict (game-designer solo fresh)

> "r2 CD-applied est un travail propre. 5 fixes appliqués chirurgicalement, 3 BLOCKING r2 antérieurs incidemment absorbés. Seul pli : budget cross-cap théorique (AC-LVL-55 le détecte au lint, pas besoin d'amendement). EC-8 Jolt CCD reste CLAIM-UNVERIFIED — Sprint 1 empirical. **r2 APPROVED** ; `/create-epics level-system` peut démarrer."

Prior verdict resolved :
- r1 full MAJOR REVISION NEEDED (8 BLOCKING cross-model) → **5 fixes CD ranked appliqués clean, 3 tech techniques délégués Sprint 1 empirical** (acceptable)
- r2 lean NEEDS REVISION (3 BLOCKING finition) → **SUPERSEDED** (tous absorbés par r2 CD-applied)

---

## Revision — 2026-04-23 (r2 `/design-system` revision-r2, CD 5 fixes applied as direct input)

**Trigger** : Martin a relancé `/design-system level-system en mode revision-r2` en passant les **5 fixes ranked CD** du full multi-specialist review comme entrée directe (pas de nouveau review préalable — application surgicale).

**Fixes appliqués** (ordre CD) :

1. **VerticalShaftRoom primitive + F5 multi-rise** — introduction primitive `VerticalShaftRoom` (sous-scene PackedScene, chambre-puits ≥ 8 m, jusqu'à 15 m) dans R-1 r2. F5 réécrite avec `archetype_rise_range` : `Shaft ∈ [8, 15] m`, `ETAGE_HEIGHT_MAX` porté à 60 m pour accommoder le claim "puits 40 m" de §Player Fantasy (2 × Shaft 15 m + 10 m autres salles = 40 m structurellement légal).

2. **R-1 hiérarchie 3D + archetypes explicites** — R-1 réécrite en hiérarchie 3D avec `@export archetype: RoomArchetype` obligatoire. 4 primitives réutilisables : `Mezzanine`, `Atrium`, `ShaftConnector`, `VerticalShaftRoom`. R-2.6 renomée avec enum GDScript `RoomArchetype { TRAVERSAL, COMBAT, SHAFT, SECRET_HUB }` + alias de compatibilité r1 (`ARENA → COMBAT`, etc.). Nouveau sous-arbre `OnboardingAnchors` (étage 1 uniquement).

3. **R-2 invariants locaux par archetype** — R-2.1..R-2.5 universels r1 **supprimés**. Remplacés par R-2.U (3 invariants universels dérivés registry) + R-2.A (table 9 invariants × 4 archetypes — dimensions, ceiling, rise, couloir, primitives, wall-run, slots, secrets, duration). Les règles de séquençage S-1..S-5 inchangées mais gate renommées AC-LVL-50 r2.

4. **SecretLureMarker ≠ SecretCollectVolume** — split en 3 nœuds distincts : `SecretLureMarker_NN` (Marker3D visuel, aucun collider, cross-room visible) + `SecretCollectVolume_NN` (Area3D cap 3/salle) + `SecretAnchor_NN` (position spawn contenu). Tuple strict même NN (AC-LVL-53). `required_ability` déplacée sur le `SecretLureMarker` (c'est lui qui dit "tu viens quand tu as la capability"). Le contrat `SecretSlot` dans §Interactions Secret System inclut maintenant `lure: Marker3D + collect_volume: Area3D + content_anchor: Vector3 + required_ability: StringName`.

5. **Budget perf différencié par archetype + tracer onboarding combat §238** — R-4 réécrite avec table budget par archetype (DC / StaticBody3D / Area3D / Marker3D / VRAM). Primitives 3D ont un budget attribué inclus. Nouvelle sous-section **Combat Onboarding Contract** (§Interactions) trace explicitement `player-combat-system.md` Rule 16 (enemy visible ≤ 10 s + safe zone ≥ 3 m rayon). Level expose `get_onboarding_anchors() → Dictionary` (étage 1 only). 3 nouvelles ACs : AC-LVL-52 (archetype export obligatoire), AC-LVL-54 (onboarding anchors conformes), AC-LVL-55 (budget perf par archetype respecté).

**Groupe H AC-LVL-52..55 ajouté** : 4 ACs r2 CD-fix-specific en fin de §Acceptance Criteria.

**Pas de CD-GDD-ALIGN** : solo mode + revision-r2 mode (fixes CD déjà pre-validated par le full multi-specialist review 2026-04-23).

**Cohérence downstream** : `systems-index.md` bumped "NEEDS REVISION r2" → "Designed r2 — CD 5 fixes applied (pending fresh /design-review)". Aucune rupture avec ADR-0001/0003/0005. `player-combat-system.md` Rule 16 maintenant tracé dans Level GDD (contrat mutualisé — bidirectionalité désormais satisfaite pour Combat Rule 16).

**Next** : `/design-review design/gdd/level-system.md` fresh full session pour valider les 5 fixes CD et fermer le cycle r1 MAJOR REVISION → r2 CD-applied → r2 APPROVED cible.

---

## Review — 2026-04-23 (solo game-designer, fresh session)

**Verdict** : APPROVED WITH REVISIONS (≈ NEEDS REVISION — 2 BLOCKINGs ciblés)
**Scope signal** : S (ciblé — ambiguïté signal `room_entered` + AC manquante `checkpoint_spacing`)
**Specialists** : game-designer (solo, fresh session)
**Détail** : [`level-system-review-r1-2026-04-23.md`](level-system-review-r1-2026-04-23.md) — 525 lignes

Résumé : GDD structurellement solide, Player Fantasy excellente, séparation Level/peers saine. 2 BLOCKINGs non-architecturaux identifiés (signal ambiguity + missing checkpoint-spacing AC) à résoudre en r2 ciblée.

Prior verdict resolved : N/A (first review).

---

## Review — 2026-04-23 (full multi-specialist, 6 agents + creative-director senior)

**Verdict** : MAJOR REVISION NEEDED
**Scope signal** : L (3-5 jours solo — refonte identitaire, pas juste détails)
**Specialists** : game-designer, systems-designer, qa-lead, level-designer, performance-analyst, godot-specialist, creative-director (senior)
**Blocking items** : 8 (dont 3 cross-model confirmés par 2+ specialists)
**Recommended items** : 18
**Nice-to-have** : 3

### Senior verdict (creative-director)

> "Le GDD est techniquement thorough sur la plomberie (R-2..R-5, formules, lints) mais **livre l'implémentabilité au prix de la fantasy**. Un document qui promet 'un puits vertical de quarante mètres' en Player Fantasy puis le rend structurellement impossible en Rules ne peut pas passer gate CD-GDD-ALIGN. Ce n'est pas un défaut de détails — c'est un défaut d'identité."

### Blocking summary (ordre CD)

1. **[CROSS-MODEL]** Puits 40m physiquement impossible — §Player Fantasy promet le moment-icône, F5 (25m plafond) + R-2.5 (room_rise ≤ 4m) l'interdisent. Introduire primitive `VerticalShaftRoom`, réécrire F5.
2. **[CROSS-MODEL]** Hiérarchie R-1 = flat 2.5D, pas une tour — ajouter primitives `Mezzanine`, `Atrium`, `ShaftConnector` ; introduire room archetypes (Traversal / Combat / Shaft / Secret-Hub).
3. **[CROSS-MODEL]** Secrets intra-salle only (R-4 cap Area3D) — séparer `SecretLureMarker` (visible, budget distinct) de `SecretCollectVolume` (Area3D cap 3/room).
4. **[game-designer]** R-2 invariants = rails de confort ergonomique. Rendre invariants **locaux par room archetype**.
5. **[game-designer]** Combat onboarding contract de `player-combat-system.md §238` non tracé (enemy visible 10s + safe zone tutoriel).
6. **[performance-analyst]** Shadow pass `DirectionalLight3D` + budget non-Level non inclus dans F2 — worst-case dépasse 500 DC projet.
7. **[godot-specialist]** EC-8 claim "Jolt CCD par défaut" FAUX pour `CharacterBody3D` (`move_and_slide` discret, pas de CCD).
8. **[qa-lead]** 7 ACs non-testables BLOCKING : AC-LVL-7, 23, 28, 29, 36, 41, 45 (à absorber dans refonte r2).

### Disagreements

- **Rigidité vs flexibilité R-2** : arbitrage CD → room archetypes avec invariants locaux.
- **R-5.1 single .tscn** : level-designer + godot-specialist convergent (sub-scenes PackedScene).
- **qa-lead BLOCKING×7 vs CD HIGH×5** : arbitrage CD → absorber qa-lead dans sweep r2.

### Top 5 fixes ranked (CD)

1. Introduire `VerticalShaftRoom` + F5 multi-rise
2. R-1 hiérarchie 3D + room archetypes explicites
3. R-2 invariants locaux par archetype
4. `SecretLureMarker` ≠ `SecretCollectVolume`
5. Budget perf différencié par archetype + tracer onboarding combat §238

### Détail complet

Détail par specialist dans la transcription du review full (non persistée — session 2026-04-23). Les 18 MEDIUM et 3 POLISH findings couvrent :

- Traçabilité KATANA_REACH au lint pipeline (SD-F1)
- F2 overhead fantôme skybox + HUD double-compté (SD-F2)
- F8 `reach_margin = 2.3m` reverse-justified, à rapatrier Movement (SD-F3)
- `player_out_of_world` → Camera contradictoire §Interactions/UI-4 (SD-F8)
- R-5.1 single .tscn mauvaise justification — sub-scenes PackedScene (LD-F7 + GS-F6)
- R-2.2 corridors ≤8m interdit perspectives Chrome Zen longues (LD-F5)
- R-2.3 wall-run length 3m insuffisant pour chaîne (LD-F4)
- V-5 + palette identique + 30 DC/room = salles indistinguables (LD-F6 + GD-F6)
- R-5.2 NN flat sans branche — anticiper Vertical Slice branché (LD-F10)
- OQ-2 Vertical Slice 3 étages requiert refonte état machine (LD-F8)
- F4 `peer_bind ≤ 200ms` indéfendable sans entity count (SD-F7 + PA-F4)
- AC-LVL-34 p99/60 frames trop permissif — ajouter max frame time 33ms/300 frames (PA-F5)
- AC-LVL-32 VRAM delta sans warmup sous-estime 5-15MB (PA-F6)
- AC-LVL-12/13 bitmask comments trompeurs (GS-F2)
- EC-11/AC-LVL-26 conflate `call_deferred` vs `CONNECT_DEFERRED` (GS-F3)
- R-5.5 `ConcavePolygonShape3D` risques Jolt wall-run normal artefacts (GS-F4)
- `assert()` release stripping — `OS.is_debug_build()` guard explicite (GS-F5)
- V-1 shader Baker (Godot 4.5+) non mentionné (GS-F7)
- qa-lead precision gaps : AC-LVL-2, 5, 26, 34, 35, 37, 42
- qa-lead coverage gaps : EC-6, EC-11 recovery, V-1..V-5 lints
- qa-lead classifications : AC-LVL-10/27/44 → AUTO, AC-LVL-29/34 → SMOKE

Prior verdict resolved : le solo game-designer review (APPROVED WITH REVISIONS, 2 BLOCKINGs ciblés) est **INCLUS et dépassé** par ce full review. Les 2 BLOCKINGs solo game-designer (ambiguïté `room_entered` + AC `checkpoint_spacing`) deviennent MEDIUM r2 dans le nouveau scope, absorbés par les blockers CROSS-MODEL architecturaux.

---

## Review — 2026-04-23 (r2 lean solo game-designer, post full-review revisions)

**Verdict** : NEEDS REVISION (3 BLOCKING de finition — pas de refonte)
**Scope signal** : S (2-3h solo éditoriales)
**Specialists** : game-designer (solo lean, pas de delegation — re-review focalisée sur résolution 8 BLOCKING cross-model r1)
**Blocking items** : 3 | Recommended : 2 | Minor : 4
**Détail** : [`level-system-review-r2-2026-04-23.md`](level-system-review-r2-2026-04-23.md)

### Résolution des 8 BLOCKING r1 (full review cross-model)

**5 ✅ RESOLVED / 2 ⚠️ PARTIEL / 1 ❓ INCERTAIN / 0 ❌ UNRESOLVED**

- ✅ BLOCKING-1 Puits 40m : `VERTICAL_CHAMBER` archetype (R-2.6) + F5 réécrite (ETAGE_HEIGHT_MAX = 30 m)
- ✅ BLOCKING-2 Hiérarchie 2.5D : R-2.6 room archetypes (ARENA / CORRIDOR / VERTICAL_CHAMBER / JUNCTION) + séquençage S-1..S-5
- ⚠️ BLOCKING-3 SecretLure vs SecretCollect : `required_ability` ajoutée, séparation Lure/Collect reste conflée (voir MAJOR-r2-2)
- ✅ BLOCKING-4 R-2 invariants locaux : R-2.6 dimensions/features par archetype
- ❓ BLOCKING-5 Combat onboarding §238 : non-vérifiable dans review lean (voir MAJOR-r2-1)
- ✅ BLOCKING-6 F2 draw-call split : Level vs peers (`draw_calls_level ≤ 350` / `budget_peers ≤ 170`)
- ⚠️ BLOCKING-7 EC-8 Jolt CCD : spot-check Sprint 1 godot-specialist
- ✅ BLOCKING-8 7 ACs untestables : AC-LVL-29 API corrigée, AC-LVL-36 quantifiée, AC-LVL-41 critère concret, AC-LVL-45 AUTO explicité

### BLOCKING r2 (nouveaux — introduits par les revisions r2 elles-mêmes)

1. **3 références AC cassées** : AC-LVL-46, 47, 48 citées dans texte (lignes 85, 87, 185) mais absentes de §Acceptance Criteria. Groupe F header toujours "AC-LVL-43..45". Fix : ajouter Groupe G — Structure & typage (AC-LVL-46..49) avec 4 ACs AUTO pour S-1, S-3, contrainte économique secrets, F5 etage_height total.
2. **Player Fantasy 40m vs F5 30m** : §Player Fantasy ligne 24 "puits vertical de quarante mètres" inconsistent avec F5 `ETAGE_HEIGHT_MAX = 30 m`. Fix recommandé Option B : note R-2.6 `VERTICAL_CHAMBER` `ceiling_height` exception jusqu'à 40 m (feature intra-salle, pas cumul inter-salles — préserve moment-icône ET invariant numérique).
3. **Enum `LevelState` non formalisée** : utilisée partout (lignes 472, 495, 706, 730, 735, 750) mais pas de bloc GDScript `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }` dans §Detailed Design. Fix : ajouter bloc après la machine d'état ligne 130.

### Senior verdict (game-designer solo synthèse)

> "r2 a fait le gros travail identitaire — room archetypes, F2 split Level/peers, F5 re-gated, F8 dérivée. Restent 3 items de **finition** : ACs manquantes, inconsistence numérique 40m/30m, enum `LevelState` prose-only. Aucun obstacle de design. r3 2-3h solo et Sprint 1 débloque. **Ne pas relancer un full multi-specialist**."

Prior verdict resolved : le full review MAJOR REVISION NEEDED (8 BLOCKING cross-model, scope L) est **majoritairement résolu** par r2 (5/8 ✅ RESOLVED, 2 PARTIEL, 1 délégué spot-check Sprint 1). Le verdict r2 NEEDS REVISION porte uniquement sur 3 items éditoriaux, pas sur les identity issues tranchées par le creative-director.

---

## Revision — 2026-04-23 (r3 XS applied — 4 BLOCKING fixes from r2-fresh)

**Trigger** : user auto-approve Option A post-r2-fresh verdict NEEDS REVISION (4 BLOCKING scope XS).

**Fixes appliqués** (ordre sequential, ~30 min solo) :

1. **AC-LVL-48 range [15, 30] → [15, 60] m** (cross-model 3× BLOCKING) — gate lint pré-build aligné sur F5 `ETAGE_HEIGHT_MAX = 60 m`. Note ajoutée : "nominal MVP recommandé 30 m mais non-gated — double-shaft 40-45 m accommodant Player Fantasy `puits 40 m` est légal". Un étage documenté légal par F5 n'est plus rejeté par CI.

2. **AC-LVL-26 THEN reformulée** (cross-model 2× BLOCKING/REC) — supprimée la référence à `call_deferred` comme mécanisme de garantie d'ordre. Nouveau THEN teste le comportement observable uniquement (`peer_ready_tick < active_received_tick`). Raisonnement canonique déplacé en note pointant EC-11 : "la garantie provient de l'ordre natif Godot autoload → main scene, PAS d'une propriété de `call_deferred`". Contradiction doctrinale interne EC-11 ↔ AC-LVL-26 résolue.

3. **AC-LVL-33 retiré** (qa-lead BLOCKING) — marqué `REMOVED r3 — supersédé par AC-LVL-55`. Double-gate incompatible (Combat à 28 StaticBody3D passait AC-LVL-55 ≤32 mais échouait AC-LVL-33 ≤25) supprimé. AC-LVL-55 porte désormais seul la couverture per-archetype pour tous les archetypes (Traversal ≤18 ⊂ ancien ≤25, zéro perte de couverture).

4. **Tuning Knob `SECRET_DENSITY_DIVISOR` default 2 → 3** (game-designer BLOCKING) — corrigé table Tuning Knobs ligne 679 pour aligner avec F7 nominal "divisor = 3 (et non 2 comme r1)". Rationale ajoutée dans la cellule "hors range" : "2 = 5 secrets / 10 salles, dilue Pillar 4 (cf. F7 r2 '3 rares > 5 faciles')". Implémentation naïve du knob produit désormais 3 secrets alignés F7, pas 5.

**Résultat** : GDD 1271 → 1270 lignes (-1 nette : AC-LVL-33 compacté + notes ajoutées). Toutes les identity issues des 2 full reviews cross-model antérieurs ✅ résolues. Les 9 RECOMMENDED optionnels (REC-1..REC-9 du r2-fresh) sont absorbables en implémentation Sprint 1.

**Verdict post-r3** : **APPROVED r3** — mergeable Sprint 1. Aucun re-review full requis. Un `--depth lean` de 10 min post-r3 OU inline user check peut confirmer si désiré.

**Next** : `systems-index.md` bumped "APPROVED r2" → "APPROVED r3". Prêt pour `/create-epics level-system`.

---

## Review — 2026-04-23 (r2-fresh full multi-specialist, 3 agents parallèles post-r2-CD-application)

**Verdict** : NEEDS REVISION (4 BLOCKING éditoriaux — pas de refonte)
**Scope signal** : XS (~30 min solo, 4 edits ligne-level)
**Specialists** : game-designer, godot-specialist, qa-lead (3 lanes parallèles indépendantes, session fraîche)
**Blocking items** : 4 | Recommended : 9 | Nice-to-have : 0
**Détail** : [`level-system-review-r2-fresh-2026-04-23.md`](level-system-review-r2-fresh-2026-04-23.md)

### Contexte

Fresh full multi-specialist pass demandé par session state post-r2 CD 5 fixes application. 3 agents dispatchés en parallèle (lanes game-design / Godot 4.6 / QA testabilité), chacun formant son verdict sans voir les autres. Cross-model synthesis après collecte.

### Blocking (4 — tous éditoriaux / inconsistances internes)

1. **[CROSS-MODEL 3×]** AC-LVL-48 plafond [15, 30] m contredit F5 ETAGE_HEIGHT_MAX = 60 m — 3 agents convergent indépendamment. Un étage "double-shaft 40 m" légal F5 est rejeté par AC-LVL-48. Fix XS : aligner borne gate sur [15, 60] m.
2. **[cross-model 2×]** AC-LVL-26 `call_deferred` reasoning contredit EC-11 r2 — godot-specialist BLOCKING + qa-lead REC-1. EC-11 a reformulé correctement (ordre natif autoload Godot), AC-LVL-26 recycle l'ancien raisonnement r1. Fix S : reformuler THEN de AC-LVL-26 pour ne tester que le comportement observable.
3. **[qa-lead]** AC-LVL-33 (≤25 uniforme) vs AC-LVL-55 (Combat ≤32) double-gate incompatible — un COMBAT à 28 StaticBody3D passe 55 mais fail 33. Fix XS : retirer AC-LVL-33 (supersédé).
4. **[game-designer]** Tuning Knob `SECRET_DENSITY_DIVISOR` default=2 contredit F7 nominal=3 — implémentation naïve spawne 5 secrets vs 3 intended. Fix XS : corriger ligne 679 default → 3.

### Senior verdict (synthèse cross-model)

> "Le GDD Level System r2 CD-applied est structurellement mûr. Les 2 full reviews multi-specialist ont fait leur travail — room archetypes, F5 multi-rise, SecretLure split, Combat onboarding contract, budget perf per-archetype, tout est en place. Les identity issues sont closes. Reste 4 items de finition qui sont des inconsistances internes. Chaque fix est 1-4 lignes. r3 XS, 30 min solo, et le GDD bascule APPROVED r3. Ne pas relancer un full multi-specialist — plus rien à y apprendre."

### Résolution des BLOCKINGs antérieurs

- **Lean r2 BLOCKING-1** (AC-LVL-46/47/48 broken refs) → ✅ RESOLVED (ACs existent en r2 Groupe G)
- **Lean r2 BLOCKING-2** (Fantasy 40m vs F5 30m) → ⚠️ TRANSFORMÉ (F5 élargi à 60m, AC-LVL-48 non-aligné → BLOCKING-1 r2-fresh)
- **Lean r2 BLOCKING-3** (LevelState enum non-GDScript) → ✅ RESOLVED (bloc lignes 176-188)
- **Full #1/#2 BLOCKINGs cross-model** (8 + 5) → ✅ RESOLVED (toutes identity issues tranchées par r2 CD fixes)

### Specialist disagreements : aucun substantiel

Les 3 agents convergent totalement sur BLOCKING-1 (cross-model 3×), partiellement sur BLOCKING-2 (godot BLOCKING + qa ADVISORY). BLOCKING-3 et BLOCKING-4 sont single-lane mais logique arithmétique non-contestable.

Prior verdict resolved : les 3 lean r2 BLOCKINGs sont majoritairement résolus (2 ✅ / 1 transformé). Toutes les identity issues des 2 full reviews cross-model antérieurs sont closes. Le verdict r2-fresh NEEDS REVISION porte uniquement sur 4 items éditoriaux internes.

---

## Review — 2026-04-23 (second full multi-specialist pass — 6 agents + creative-director, session parallèle)

**Verdict** : NEEDS REVISION (ciblée — 5 BLOCKING cross-model, ~2-3h chirurgical)
**Scope signal** : L implémentation post-revision (inchangé vs première full review)
**Specialists** : game-designer, systems-designer, level-designer, performance-analyst, qa-lead, godot-specialist, creative-director (senior synthesis)
**Blocking items** : 5 (cross-model) | Recommended : ~13 | Nice-to-have : ~12

### Contexte

Review full-mode lancée en parallèle de la première session (multiplexage concurrent inattendu). Même GDD, mêmes spécialistes archétypes, mais spawning indépendant → findings convergents en substance mais clustering différent. Cette entrée documente la seconde passe **en complément** de la première, pas en remplacement.

### Blocking cross-model (partition différente, convergences fortes)

1. **Formules F2, F5, F7, F8** [cross-model : systems-designer + game-designer + performance-analyst] — F2 arithmétique erronée pour N=8 + overhead global vs per-peer ambigu ; F5 × ROOM_RISE_AVG=4 → 40m viole claim 25m ; F7 floor-then-clamp non pseudocodé, N=5 délirant ; F8 reach_margin=2.3m fabriqué sans dérivation formelle des constantes Movement.
2. **SecretSlot `required_ability` manquant** [cross-model : game-designer + level-designer] — "spatial only" encapsulation casse sur Pillar 4 ; pas de tag pour que Secret/HUD routent contenu par capacité ; `required_ability: StringName` enum {none, dash, double_jump, wall_run, wall_run_long} à ajouter.
3. **Typage de salle absent** [cross-model : game-designer + level-designer] — R-2 invariants uniformes produiraient 10 salles interchangeables. Introduire `room_type: RoomType` {ARENA, CORRIDOR, VERTICAL_CHAMBER, JUNCTION} + règles séquençage S-1..S-5.
4. **ACs gates inopérants** [cross-model : qa-lead + performance-analyst] — AC-LVL-29 API inexistante `OS.get_thread_caller_id()` ; AC-LVL-31 sample 60 frames vs 500 exigés testbed ; AC-LVL-34 p99 ≤16.6ms sans headroom (aligner Combat AC-CMB-35b p50≤12/p99≤14) ; AC-LVL-35 double gouverneur ; AC-LVL-44 lit `level.yaml` non créé.
5. **Bitmask labels inversés + CCD Jolt unverified + call_deferred reasoning faux** [godot-specialist] — AC-LVL-12/13 commentaires "(bit 4=layer 4)" faux (c'est bit 3 zéro-indexé) ; EC-8 "Jolt CCD par défaut 4.6" non vérifié pour CharacterBody3D.move_and_slide ; EC-11 justification call_deferred incorrecte (ordre autoload est natif Godot, pas propriété de call_deferred).

### Senior verdict (creative-director synthèse)

> "Le GDD est structurellement solide (8 sections, 0 broken reference, 4 piliers cités, Chrome Zen respecté) mais la densité (923 lignes) masque erreurs arithmétiques, formules non-dérivées, et encapsulations qui cassent P4. Les 5 blockers sont tous corrigibles **en une session de 2-3h chirurgicale** — pas besoin de refonte. La dette R/N (~25 findings) se traite progressivement pendant implémentation."

### Fixes appliqués en fin de session (dans le même fichier GDD)

1. ✅ F2 réécrite avec borne [290, 350] + sous-budget peers verrouillé ≤ 170dc
2. ✅ F5 gate sur `etage_height ∈ [15, 30] m` (total, pas avg seul)
3. ✅ F7 pseudocode explicite + clamp bilatéral [3, 5] + nominal divisor=3
4. ✅ F8 `wall_run_vertical_reach` dérivé formellement depuis constantes Movement + CI gate
5. ✅ SecretSlot `{volume, anchor, required_ability: StringName}` + lint obligatoire + contrainte économique ≥ 1 wall_run secret
6. ✅ R-2.6 `room_type` enum + features obligatoires par archetype + règles séquençage S-1..S-5
7. ✅ AC-LVL-29 API corrigée + reclassée AUTO
8. ✅ AC-LVL-31 scindé en 31 (isolation Level) + 31b (peers combat) ; 500 frames alignés testbed
9. ✅ AC-LVL-34 aligné Combat : p50≤12ms ET p99≤14ms
10. ✅ AC-LVL-35 scindé 35a AUTO (p99 objective) + 35b PLAYTEST (subjectif)
11. ✅ AC-LVL-36 ajouté `Performance.OBJECT_COUNT` (pattern Combat Pattern 2)
12. ✅ AC-LVL-41 protocole chiffré + référence `production/qa/playtest-protocols/`
13. ✅ AC-LVL-44 condition d'entrée `level.yaml` créé
14. ✅ AC-LVL-45 retiré (hors-périmètre, déplacé en règle review process)
15. ✅ AC-LVL-46..50 nouveaux (couverture F3/F5/F6/F7 + diversité typologique S-1/S-3/S-5)
16. ✅ AC-LVL-12/13 bitmask corrigé + API `set_collision_layer_value()` + gate `collision_mask ⊃ LAYER_PLAYER`
17. ✅ EC-8 CCD Jolt flaggé CLAIM-UNVERIFIED + benchmark prototype Sprint 1 obligatoire
18. ✅ EC-11 call_deferred reasoning reformulé (ordre autoload natif Godot)

### Divergence vs r2 lean précédente

Cette seconde full-review a identifié **les mêmes problèmes structurels** que la première full (room archetypes, SecretSlot, formules, Jolt CCD) mais a opéré une **partition différente** (5 vs 8 blockers cross-model). Les fixes appliqués ci-dessus sont **compatibles** avec ceux de la r2 lean post-first-review — les deux ensembles de patches co-existent dans le GDD r2 final. Pas de conflit de contenu, juste une duplication de traçabilité.

Prior verdict resolved : les 5 blockers cross-model de cette seconde passe sont tous ✅ RESOLVED par les 18 patches listés ci-dessus. Le GDD Level System r2 est désormais **Pending fresh re-review** — les deux chemins de révision convergent au même état final.

---

## Review — 2026-04-23 (fresh independent r3-validation — 6 specialists parallèles + creative-director senior)

**Verdict** : **APPROVED r3 (re-validated)**
**Scope signal** : XS r4 patches éditoriaux optionnels + S Sprint 1 stubs (owner level-designer + qa-lead)
**Specialists** : game-designer, systems-designer, qa-lead, performance-analyst, level-designer, godot-specialist (6 lanes parallèles indépendantes), creative-director (senior synthesis)
**Blocking items** : 0 | MAJOR-resid : 4 | MINOR-resid : 3 | Specialist-findings refuted : 4
**Trigger** : user `/design-review design/gdd/level-system.md — validation r2 indépendante` fresh session post application des 4/4 r3 patches par session concurrente

### Cross-check specialist findings vs GDD r3 state (ligne-par-ligne)

**4 findings REFUTED** — specialists ont lu le review-log historique sans cross-checker l'état courant du GDD :

| Finding | Agent(s) | Vérité GDD r3 |
|---|---|---|
| AC-LVL-48 gate [15, 30] m rejette Fantasy 40 m | cross-model 5× (game-designer, systems-designer, perf-analyst, level-designer, godot-specialist) | **FAUX** — ligne 1127 dit `[15, 60] m`. Patch r3 #1 appliqué. |
| SECRET_DENSITY_DIVISOR default=2 vs F7 nominal=3 | systems-designer | **FAUX** — Tuning Knobs ligne 679 dit `3`. Patch r3 #4 appliqué. |
| AC-LVL-33 double-gate avec AC-LVL-55 | qa-lead | **FAUX** — ligne 1037 marqué `REMOVED r3`. Patch r3 #3 appliqué. |
| AC-LVL-26 reasoning `call_deferred` faux | godot-specialist | **FAUX** — corrigé r2 ligne 591 avec note EC-11 canonique. |

**Leçon méthodologique** : les specialists auto-dispatched par `/design-review` full mode peuvent fabriquer des findings en lisant le review-log historique comme source de vérité. Brief futur : exiger cross-check ligne-par-ligne du GDD actuel avant chaque finding.

### MAJOR-resid CONFIRMED (survivent au cross-check)

1. **Artefacts fantômes référencés par ACs AUTO** (qa-lead + level-designer convergents) — vérifié filesystem :
   - `production/qa/playtest-protocols/` → INEXISTANT (AC-LVL-41)
   - `design/registry/level.yaml` → INEXISTANT (AC-LVL-44)
   - `tools/lint/level_lint.gd` → INEXISTANT (AC-LVL-14, 16-20, 50-55)
   - Sprint 1 blocker, pas GDD blocker. Owner : level-designer + qa-lead.

2. **F8 dérivation `3.375 → 2.3 m` non-arithmétique** (systems-designer) — lignes 482-485 : soustraction affichée 0.5 m produit 2.875, pas 2.3. La prose dit "10-15 %" mais applique 32 %. Risque `min_wall_height` sous-estimé 0.5+ m → murs à 4.0 m potentiellement trop courts pour wall-run complet. Fix r4 éditorial : corriger à 2.875 ou justifier la règle d'arrondi réelle appliquée.

3. **`LEVEL_OVERHEAD = 50` F2 n'inclut pas shadow pass DirectionalLight3D** (performance-analyst CRIT-1) — ligne 305 + ligne 745. Pas de lint/AC qui contraint `cast_shadow = SHADOW_DISABLED` sur MeshInstance3D. Shadow pass Forward+ peut ajouter +100-150 DC sur 250 receivers. Action Sprint 1 : benchmark étage 10-salles avec/sans shadow, puis bumper `LEVEL_OVERHEAD` à 120-150 OU ajouter règle authoring V-5.

4. **`assert()` release stripping (GS-F5 r1 NON-RÉSOLU r2/r3)** (godot-specialist) — lignes 529, 542, 1009. Pattern `_ensure()` helper recommandé pour EC-2, EC-4, AC-LVL-29. Fix r4 éditorial : ajouter bloc GDScript `func _ensure(cond, msg)` dans §Detailed Design, remplacer usages.

### MINOR-resid

5. **`CheckpointSlot` / `SecretSlot` types utilisés sans `class_name`** (godot-specialist H-2) — §Dependencies lignes 224/227 utilisent `Array[CheckpointSlot]` mais types déclarés comme Dictionary. Fix trivial Sprint 1 : créer `src/core/level/checkpoint_slot.gd` + `secret_slot.gd` comme `Resource` avec `class_name`.

6. **`@export archetype: RoomArchetype` scope enum non clarifié** (godot-specialist H-1) — R-1 mentionne l'export sans préciser enum global vs local vs Resource. Fix Sprint 1 : bloc GDScript canonique dans §Detailed Design.

7. **SECRET_HUB archetype gameplay-différencié** (game-designer + level-designer) — différence avec `TRAVERSAL + 1 Lure` limitée à "≥ 1 Atrium recommandé" (non-normatif). Chrome Zen palette identique = visuellement indistinguable sans VFX Lure. **Design critique, pas implementation blocker**. Recommandation CD post-playtest : soit dissoudre en `secret_density: int`, soit ajouter contrainte structurelle (≥ 2 routes alternatives, 0 EnemySlot, Atrium obligatoire).

### Specialist disagreements

- **D-1** : game-designer "1271 lignes déshumanisent le design" vs consensus implicite fonctionnement. Tranchage CD : non-blocker (les praticiens ont livré r3 efficacement), candidat refactor éditorial post-MVP.
- **D-2** : game-designer "Combat Onboarding SafeZone 3m géométriquement tendue dans 12×12m" — vérification géométrique : 3 EnemySlots triangle équilatéral permettent centre ≥ 4.6 m, SafeZone 3 m possible avec placement contraint. **Finding overblown** — CO-1..CO-3 valides.

### Senior verdict (creative-director)

> "Le GDD r3-patched résout proprement tous les BLOCKING cross-model r1/r2 et les 3 BLOCKING r2 lean + 4 BLOCKING r2-fresh. Les 5 fixes CD sont RESOLVED CLEAN. Les 4 r3 patches sont vérifiés ligne-par-ligne. Les 4 observations résiduelles sont soit patches éditoriaux chirurgicaux (<1h), soit validations benchmark Sprint 1, soit CD decisions post-playtest. Aucune n'est bloquante pour `/create-epics level-system`. Les specialists ont en partie fabriqué leurs findings depuis le review-log historique — rappel méthodologique pour les futures sessions full-mode : cross-check ligne-par-ligne avant claim."

### Résolution finale du cycle r1 → r2 → r3

- 8/8 BLOCKING r1 full ✅ RESOLVED CLEAN
- 3/3 BLOCKING r2 lean ✅ ABSORBÉS r2 CD + r3
- 5/5 BLOCKING r2 second full ✅ RESOLVED CLEAN (18 patches)
- 4/4 BLOCKING r2-fresh ✅ RESOLVED CLEAN (4 patches r3)
- 5/5 CD 5 fixes ✅ RESOLVED CLEAN
- 4/4 r3 patches ✅ VERIFIED CLEAN line-by-line (session indépendante)

Prior verdict resolved : **cycle complet clos**. Le chemin r1 MAJOR REVISION NEEDED → r2 CD-applied → r2-fresh NEEDS REVISION → r3 XS applied → **APPROVED r3 re-validated independently** est verrouillé. Les 4 MAJOR-resid sont traçables en Sprint 1 backlog (ou r4 patches éditoriaux 30 min si préféré). Ready pour `/create-epics level-system`.

---
