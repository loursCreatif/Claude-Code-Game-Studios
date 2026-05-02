# Design Review — Level System r2 (fresh, post CD 5 fixes applied)

**Date** : 2026-04-23
**Reviewer** : game-designer (solo lean, fresh session après application des 5 fixes CD via `/design-system level-system revision-r2`)
**GDD** : `design/gdd/level-system.md` (**1271 lignes**, r2 CD-applied)
**Previous verdict review chain** :
- r1 solo (2026-04-23) → APPROVED WITH REVISIONS (2 BLOCKING ciblés)
- r1 full 6 specialists + CD (2026-04-23) → MAJOR REVISION NEEDED (8 BLOCKING, 3 cross-model, scope L)
- r2 lean (2026-04-23, même date, **SUPERSEDED**) → NEEDS REVISION (3 BLOCKING finition) — basé sur état intermédiaire pre-CD-fixes
- **r2 fresh (ce rapport)** → à statuer

**Mode** : lean (solo game-designer, pas de subagent delegation — re-review focalisée validation des 5 fixes CD)

---

## Verdict r2 fresh

**APPROVED WITH MINOR OBSERVATIONS** — r2 mergeable pour Sprint 1.

**Rationale** : le GDD r2 post-CD-fixes **résout proprement les 5 fixes CD du full review** (cross-model, identité) ET **absorbe incidemment les 3 BLOCKING de ma r2 lean antérieure** (AC cassées, PF/F5 inconsistency, enum LevelState). Les ajouts sont cohérents, les ACs sont testables, la traçabilité cross-GDD (Movement, Combat Rule 16) est explicite. 0 BLOCKING, 0 MAJOR, 2 MINOR (non-bloquants).

**Systems-index recommandé** : `Level System → Approved r2 (CD 5 fixes applied, fresh review validated)`.

**Ne relance PAS** un full multi-specialist — l'identité est verrouillée, reste purement confirmation empirique Sprint 1 (benchmarks budget, NavMesh bake, Jolt CCD).

---

## Résolution des 5 fixes CD (top 5 ranked)

| # | Fix CD | Statut r2 | Évidence |
|---|-------|-----------|----------|
| 1 | Primitive `VerticalShaftRoom` + F5 multi-rise (puits 40m Fantasy structurellement possible) | ✅ **RESOLVED CLEAN** | R-1 r2 ligne 56 : primitive `VerticalShaftRoom_01..V` PackedScene 8-15m rise ; §Player Fantasy ligne 24 annotée "ce puits est une primitive structurelle explicite" ; F5 r2 `ETAGE_HEIGHT_MAX = 60m` (ligne 383) ; archetype `SHAFT` rise admissible [8, 15]m (R-2.A ligne 99) |
| 2 | R-1 hiérarchie 3D + archetypes explicites `TRAVERSAL / COMBAT / SHAFT / SECRET_HUB` + primitives `Mezzanine / Atrium / ShaftConnector / VerticalShaftRoom` | ✅ **RESOLVED CLEAN** | R-1 r2 lignes 42-75 : hiérarchie 3D avec @export archetype obligatoire ; primitives PackedScene authoring-time (lignes 53-56) ; enum `RoomArchetype` formel ligne 119-124 ; alias compat r1 documenté ligne 127 ; tuple Secret strict indexé par NN ligne 81 |
| 3 | R-2 invariants locaux par archetype (R-2.U + R-2.A) | ✅ **RESOLVED CLEAN** | R-2.U lignes 88-91 : **2 invariants universels seulement** (portes KATANA_REACH, wall-run height, borne Y=-2.0m avec exception shaft documentée ligne 91). R-2.A lignes 93-105 : table 9 invariants × 4 archetypes (dimensions, ceiling, rise, couloir, primitives, wall-run, slots, secrets, duration). Gate S-1..S-5 lignes 107-112. |
| 4 | `SecretLureMarker` (visible, cross-room, no collider) ≠ `SecretCollectVolume` (Area3D cap 3/salle) ≠ `SecretAnchor` (contenu) | ✅ **RESOLVED CLEAN** | R-1 r2 lignes 63 (SecretCollectVolume Area3D cap strict), 70 (SecretLureMarker Marker3D lueur cyan #3EE4FF portée ≥ 20m **aucun collider**), 71 (SecretAnchor spawn contenu). Tuple NN strict AC-LVL-53. `required_ability: StringName` déplacée sur le LureMarker (ligne 81). |
| 5 | Budget perf différencié par archetype + Combat Onboarding Contract tracé `player-combat-system.md` Rule 16 | ✅ **RESOLVED CLEAN** | R-4 r2 lignes 140-150 : table par-archetype (DC/StaticBody3D/Area3D/Marker3D/VRAM). Combat 38 DC > Traversal 22 (justifié rationale ligne 146). OnboardingAnchors sous-arbre ligne 72-74 : `FirstEnemySightline` + `SafeZoneCenter` pour Combat Rule 16. `Level.get_onboarding_anchors() → Dictionary` exposé (non-fatal absence étage ≠ 1). AC-LVL-54 gate. |

**Synthèse** : 5/5 ✅ RESOLVED CLEAN. Aucun fix partiellement appliqué, aucune contradiction introduite.

---

## Résolution des 3 BLOCKING r2 lean (SUPERSEDED, absorbés par r2 CD)

| # | BLOCKING r2 lean (review superseded) | Statut r2 CD-applied |
|---|-------------------------------------|----------------------|
| 1 | 4 ACs cassées (AC-LVL-46/47/48/LVL-F5 référencées lignes 85/87/185/309 mais absentes Groupe F) | ✅ **RESOLVED** — Groupe G (AC-LVL-46..50) rédigé ligne 1117 : secret count F7, checkpoint count F3, altitude totale F5, WorldBounds F6, diversité archetype. BONUS AC-LVL-51 checkpoint spacing invariant edge-case. + Groupe H (AC-LVL-52..55). |
| 2 | Player Fantasy 40m vs F5 ETAGE_HEIGHT_MAX 30m | ✅ **RESOLVED** — `ETAGE_HEIGHT_MAX = 60 m` (ligne 383), Shaft rise [8, 15]m, §PF ligne 24 annotée puits = primitive structurelle (non-métaphorique). Numérique + identité cohérents. |
| 3 | enum `LevelState` utilisée mais pas formalisée en bloc GDScript | ✅ **RESOLVED** — bloc GDScript formel `enum LevelState { UNLOADED, LOADING, ACTIVE, UNLOADING }` lignes 181-186 avec commentaire par état. |

**Synthèse** : 3/3 ✅ RESOLVED. Ma review r2 lean est officiellement **SUPERSEDED** par r2 CD-applied.

---

## Observations MINOR r2 (non-bloquants — Sprint 1 follow-up)

### MINOR-r2-fresh-1 — Budget cross-cap F2 vs R-4 per-archetype dans distributions S-compliant extrêmes

**Observation** : la table R-4 r2 (par-archetype DC) peut excéder le plafond `draw_calls_level ≤ 350` (F2) sous certaines distributions authorisées par S-1..S-5.

**Exemple** : configuration S-compliant maximale en Combat — 4 COMBAT + 1 SHAFT + 1 SECRET_HUB + 4 TRAVERSAL (N=10, alternance S-2 respectée, S-1/S-3/S-5 satisfaits) :
```
4 × 38 (COMBAT)   = 152
1 × 32 (SHAFT)    =  32
1 × 34 (SECRET_HUB) = 34
4 × 22 (TRAVERSAL) =  88
Sous-total salles   = 306
+ LEVEL_OVERHEAD    =  50
Total              = 356  → excède 350 de 6 DC
```

**Impact** : AC-LVL-55 détectera au lint pré-build, mais le level-designer aurait pu authorer cette config en croyant respecter tous les gates.

**Option A (recommandée)** : ajouter une règle de séquençage **S-6** : `n_combat ≤ 3 pour N_rooms ∈ [8, 10]` — ou plus précisément, gate `Σ DC_estimated_per_archetype ≤ 300` (marge overhead 50) au lint *avant* placement.

**Option B** : réduire légèrement COMBAT à 35 DC (au lieu de 38). Impact : combat plus nu (moins de wall-run décors).

**Option C** : laisser AC-LVL-55 faire le travail — si un désigner touche ce pli, il se fait rejeter au lint et doit réduire la densité de décor dans une salle Combat.

**Recommandation** : **Option C** (laisser AC-LVL-55 faire le travail, économique et opérationnel). L'observation est un détail budgétaire ; ne nécessite pas d'amendement GDD. Sprint 1 peut affiner si data playtest montre des rejets fréquents.

### MINOR-r2-fresh-2 — EC-8 Jolt CCD reste "CLAIM-UNVERIFIED" (tech-risk Sprint 1)

**Statut** : r2 a correctement flaggé EC-8 "Jolt CCD claim" comme CLAIM-UNVERIFIED et exigé benchmark prototype Sprint 1 (noté dans Last Updated header). Mais le benchmark n'est pas encore réalisé.

**Impact** : risque de clip-through wall à haute vélocité (dash + wall-run) non vérifié empiriquement. Si Godot 4.6 Jolt `CharacterBody3D` n'a effectivement pas de CCD, AC-LVL-41 PLAYTEST peut échouer.

**Mitigation existante** : l'addendum godot-specialist du full review r1 liste 3 tech-risks (ShapeCast3D margin Jolt, CapsuleShape3D basis, ShapeCast3D overlap) à résoudre pré-Sprint 1. Le Jolt CCD en fait partie implicitement (EC-8 amont).

**Action** : lead-programmer ou godot-specialist exécute le benchmark prototype dès Sprint 1 démarrage, **avant** l'implémentation Level System. Les 3 gaps empiriques ADR-0006 (Combat Tick Model) déjà listés couvrent ce terrain.

**Pas de fix GDD requis** — le flag CLAIM-UNVERIFIED est la bonne posture, c'est au code/bench de trancher.

---

## Completeness : 11/8 sections présentes

Sections rédigées : Overview / Player Fantasy / Detailed Design / Formulas / Edge Cases / Dependencies / Tuning Knobs / Visual-Audio / UI / Acceptance Criteria / Open Questions — **excède** les 8 standard de `.claude/rules/design-docs.md`. ✅

---

## Dependency Graph (inchangé)

Les dépendances §Dependencies r2 restent cohérentes avec r1 :
- Upstream : Game State Manager (Not Started — interface provisoire acceptable)
- Downstream : Checkpoint, Hazard, Enemy, Secret, HUD, Tutorial, Audio, VFX (tous Not Started — reciprocity forward acceptable, AC-LVL-45 retirée mais règle `.claude/rules/design-docs.md` maintient le gate)

**Nouvelle traçabilité r2** : `player-combat-system.md` Rule 16 (enemy visible ≤ 10s + safe zone ≥ 3m) maintenant tracée explicitement dans §Interactions + OnboardingAnchors. **Bidirectionalité Combat Rule 16 désormais satisfaite** — Combat peut référencer Level `get_onboarding_anchors()` sans rompre le contrat.

---

## ADR traceability

ADR-0001, ADR-0003, ADR-0005 D-5 référencés (inchangé). Compatible ADR-0006 (Combat Tick Model, Proposed) et plans ADR-0007 (Game State Manager — G-6) + ADR-0011 (Level Scene + Anchors — G-8) per architecture-review 2026-04-23.

**Rien de nouveau à ajouter côté ADR.**

---

## Scope Signal pour r3 (si r3 existe)

**Scope r3** : **N/A — pas de r3 requis**.

Le GDD r2 CD-applied est **mergeable pour Sprint 1**. Les 2 MINOR observations sont :
- Budget cross-cap : délégable AC-LVL-55 (déjà présente), pas d'amendement GDD
- EC-8 Jolt CCD : délégable benchmark prototype Sprint 1, pas d'amendement GDD

Aucune edit éditoriale restante de mon côté. r2 est verrouillé.

---

## Senior verdict (synthèse game-designer solo fresh session)

> "Le GDD Level System r2 CD-applied est un travail propre. Les 5 fixes du creative-director senior ont été appliqués chirurgicalement — pas de half-measures, pas de semi-résolutions. L'archetype `Shaft` porte désormais le puits 40m comme primitive structurelle, le tuple Secret Lure/Collect/Anchor sépare proprement visibilité et mécanique, R-2.A est une table dense mais lisible, R-4 per-archetype et AC-LVL-55 arbitrent ensemble la densité perf. Bonus propres incidemment résolus : Groupe G rédigé (AC cassées antérieures), enum LevelState formalisée, PF 40m réconciliée F5 60m. Le seul pli identifiable est un budget cross-cap théorique (4 COMBAT + shaft + hub + 4 traversal = 356 DC vs cap 350) — AC-LVL-55 le détecte au lint, pas besoin d'amendement. EC-8 Jolt CCD reste CLAIM-UNVERIFIED mais c'est la bonne posture — Sprint 1 empirical. **r2 est APPROVED** ; systems-index bascule `Designed r2` → `Approved r2`. `/create-epics level-system` peut démarrer."

---

## Next steps

### Option A (recommandée) — Marquer Approved, démarrer epic breakdown

1. Mettre à jour `systems-index.md` : Level System → **Approved r2**
2. Append ce review au `level-system-review-log.md`
3. `/create-epics level-system` → backlog stories Sprint 1
4. En parallèle : lead-programmer exécute benchmarks prototype (Jolt CCD EC-8 + 3 gaps ADR-0006)

### Option B — Paralléliser `/design-system` amont

Démarrer `/design-system` #6 Hazard ou #8 Checkpoint pendant que Level r2 est epic-broken-down en parallèle. Level r2 suffisamment stable comme référence.

### Option C — Consistency sweep cross-GDD

`/review-all-gdds` sur les 6 GDDs MVP actuels (Input r4, Movement r3, Camera r2, Combat r6, Level r2, game-concept) pour détecter les incohérences latentes. Recommandé avant epic breakdown mais non-bloquant.

**Recommandation** : **Option A** — le GDD Level est prêt, pas de raison de différer l'epic breakdown. Les bench prototype Sprint 1 se feront en marge.

---

## Traceability

- **GDD cible** : `design/gdd/level-system.md` (1271 lignes, r2 CD-applied 2026-04-23)
- **Review superseded (même date)** : `design/gdd/reviews/level-system-review-r2-2026-04-23.md` — basée sur état intermédiaire pre-CD-fixes, conservée pour historique
- **Review précédente r1 solo** : `design/gdd/reviews/level-system-review-r1-2026-04-23.md` (525 lignes)
- **Review log** : `design/gdd/reviews/level-system-review-log.md` (à appender)
- **Systems index** : `design/gdd/systems-index.md` (à bumper `Designed r2` → `Approved r2`)
- **Architecture** : 21 TR Level mappés Gap G-8 (ADR-0011 planifié) — compatible r2 sans changement
