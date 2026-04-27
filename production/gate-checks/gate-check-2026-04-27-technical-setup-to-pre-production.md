# Gate Check: Technical Setup → Pre-Production

| Field | Value |
|-------|-------|
| **Date** | 2026-04-27 |
| **Checked by** | `/gate-check pre-production` (gate-check skill) |
| **Review Mode** | `solo` (artifact-existence + quality checks only — director panel skipped) |
| **Engine** | Godot 4.6 (pinned 2026-02-12) |
| **Stage Before** | Pre-Production (set informally) |
| **Stage After** | Pre-Production (formalised) |

---

## Required Artifacts: 13/13 present

| # | Item | Path | Status |
|---|------|------|--------|
| 1 | Engine chosen (CLAUDE.md non-`[CHOOSE]`) | `CLAUDE.md` | ✅ Godot 4.6 / GDScript |
| 2 | Technical preferences populated | `.claude/docs/technical-preferences.md` | ✅ Naming + performance budgets + specialists routing |
| 3 | Art bible Sections 1–4 | `design/art/art-bible.md` | ✅ 96 KB (full bible exists) |
| 4 | ≥ 3 ADRs Foundation-layer | `docs/architecture/adr-*.md` | ✅ 9 ADRs Accepted (0001/0002/0003/0004/0005/0006/0007/0008/0011) |
| 5 | Engine reference docs | `docs/engine-reference/godot/` | ✅ VERSION + breaking-changes + deprecated-apis + best-practices + modules/ |
| 6 | Test framework dirs | `tests/unit/` + `tests/integration/` | ✅ Subfolders camera/collision/example/input/level + integration |
| 7 | CI/CD test workflow | `.github/workflows/tests.yml` | ✅ Exists |
| 8 | Example test file | `tests/unit/example/example_test.gd` | ✅ Exists |
| 9 | Master architecture document | `docs/architecture/architecture.md` | ✅ 25 KB (r1 du 2026-04-21) |
| 10 | Architecture traceability index | `docs/architecture/architecture-traceability.md` | ✅ v2.3 (88 TRs, 91% Covered) |
| 11 | `/architecture-review` report exists | `docs/architecture/architecture-review-*.md` | ✅ Multiple reviews (latest r4 PASS verdict) |
| 12 | Accessibility requirements | `design/accessibility-requirements.md` | ✅ Tier **Standard** (WCAG 2.1 AA) committed |
| 13 | Interaction pattern library | `design/ux/interaction-patterns.md` | ✅ Exists (9 KB) |

---

## Quality Checks: 10/10 passing

| # | Check | Result |
|---|-------|--------|
| 1 | Architecture decisions cover core systems (rendering / input / state) | ✅ ADR-0003 rendering, ADR-0004 input, ADR-0007 game state |
| 2 | Technical preferences have naming + performance budgets | ✅ snake_case + 60 fps + 16.6 ms frame + < 500 draw calls + 2 GB / 1 GB |
| 3 | Accessibility tier defined | ✅ Standard (motrices, photosensibilité, WCAG 2.1 AA) |
| 4 | At least one screen UX spec started | ✅ `design/ux/main-menu.md` (8 KB) |
| 5 | All ADRs have Engine Compatibility section | ✅ 9/9 (Engine Compatibility + GDD Requirements + ADR Dependencies sections present) |
| 6 | All ADRs have GDD Requirements Addressed section | ✅ 9/9 |
| 7 | No ADR references deprecated APIs | ✅ Tous les refs à `deprecated-apis.md` sont des consultations confirmant l'absence d'usage |
| 8 | All HIGH RISK engine domains addressed | ✅ Rendering Forward+/D3D12 (ADR-0003), Jolt physics (ADR-0001), accessibility deferred (G-4 documenté planned ADR Polish) |
| 9 | Architecture traceability — zero Foundation layer gaps | ✅ `Foundation layer gaps: 0 (0% ✅)` (architecture-traceability.md §1) |
| 10 | All ADRs agree on Godot 4.6 | ✅ Aucune référence stale à 4.3/4.4/4.5 dans une stance |

---

## ADR Circular Dependency Check

**Result: NO CYCLE DETECTED**

Dependency graph (Depends On edges):

```
ADR-0001 (Physics 60 Hz)            ← Foundation, no deps
ADR-0003 (Rendering Latency)        ← Foundation, no deps
ADR-0002 (Camera Scene Tree)        ← ADR-0001
ADR-0004 (Input API)                ← ADR-0001
ADR-0005 (Movement Signals)         ← ADR-0001, ADR-0004
ADR-0006 (Combat Tick Model)        ← ADR-0001, ADR-0005
ADR-0008 (Collision Layer Taxonomy) ← ADR-0001
ADR-0007 (Game State Manager)       ← ADR-0001, ADR-0003, ADR-0004, ADR-0005
ADR-0011 (Level Scene Architecture) ← ADR-0001, ADR-0003, ADR-0005
```

DAG valide. Topological sort possible. Tous les `Depends On` pointent vers ADRs Accepted.

---

## Engine Validation

| Check | Result |
|-------|--------|
| ADRs touching post-cutoff APIs flagged Knowledge Risk | ✅ ADR-0001 (Jolt 4.6), ADR-0003 (D3D12 4.6, Shader Baker 4.5), ADR-0007 (4.5+ pause), ADR-0011 (NavigationRegion3D 4.6) |
| `/architecture-review` engine audit deprecated API count | ✅ 0 |
| All ADRs agree on engine version | ✅ Godot 4.6 unanime |

---

## Blockers

**Aucun.** Le gate franchit cleanly.

---

## Recommendations (non-blocking)

1. **Sprint 0 Technical Setup follow-ups ADR-0008** (Migration Plan) — créer en parallèle :
   - `src/core/collision_layers.gd` (helper `build_mask()` + constants `LAYER_*`)
   - `.claude/rules/collision-layer-api-1-indexed.md` (lint rule forbidden_pattern)
   - CI job `lint-collision-layers` dans `.github/workflows/tests.yml`
   - Smoke test `tests/unit/collision/layer_mask_contract_test.gd`
   - Update `project.godot [layer_names]` si pas déjà fait
2. **GDD sync cosmétique différable Sprint 1 Combat** — Combat GDD l.88 snippet `query.collision_mask = 0b00010` → `CollisionLayers.build_mask([CollisionLayers.LAYER_ENEMY])` (ADR-0008 Migration Plan, hors scope lint D-6 actuellement).
2bis. **GDD sync cosmétique différable** — ADR-0011 l.433/484 référence "ADR-0008 planifié" à mettre à jour en "ADR-0008 Accepted" (consigné session-state r5).
3. **Re-générer architecture.md r2** — le master architecture document est r1 du 2026-04-21 et ne reflète pas encore ADR-0006/0007/0008/0011 Accepted. Non-blocker MVP mais utile avant gate Pre-Production → Production.
4. **Gaps Feature non-blockers MVP restants** documentés et planifiés :
   - **G-2a** Camera settings save/load (post-MVP)
   - **G-2b** Input settings save/load (post-MVP)
   - **G-4** Accessibility implementation (Polish/Full Vision — interface MVP via TR-mov-008)
   - **G-7** Audio System ADR (Sprint 1-2, non-blocker démarrage Pre-Prod)

---

## Chain-of-Verification

**5 questions challenge** la verdict draft = PASS :

1. **Q : Quels quality checks ai-je vérifiés en lisant un fichier vs inférés ?**
   R : Tous les 10 vérifiés via Bash/Read direct (grep ADR sections, lecture accessibility tier, lecture traceability §1 Coverage Summary). Aucun inféré.
2. **Q : Items MANUAL CHECK marqués PASS sans confirmation user ?**
   R : Aucun. Tous les checks sont vérifiables sur fichier.
3. **Q : Tous les artefacts listés ont-ils du contenu réel (pas templates vides) ?**
   R : Vérifié via taille (96 KB art-bible, 17 KB accessibility, 25 KB architecture, 18 KB traceability) et inspection ciblée.
4. **Q : Un blocker dismissé comme mineur pourrait-il en réalité empêcher la Pre-Production ?**
   R : Recommendation #3 (architecture.md r2) est cosmétique — la traceability matrix est l'autorité fonctionnelle, et elle est à jour v2.3. Pas de blocker caché.
5. **Q : Quel check suis-je le moins confiant ? Pourquoi ?**
   R : Quality #8 (HIGH RISK engine domains addressed). G-4 Accessibility est techniquement non-couverte par ADR mais documentée en gap planned ADR Polish + interface MVP TR-mov-008 prévue. Acceptable pour Pre-Prod (non-blocker MVP).

**Chain-of-Verification: 5 questions checked — verdict unchanged (PASS)**

---

## Verdict: ✅ PASS

**Technical Setup → Pre-Production** : tous les artefacts requis présents, toutes les quality checks passantes, aucun blocker, DAG ADR valide, engine consistent.

C'est le **second PASS officiel** du projet (le premier étant la conclusion architecture globale via `/architecture-review` r4 du 2026-04-23).

**Conséquence formelle** : le projet est officiellement en Pre-Production. Démarrage de l'implémentation des epics Foundation/Core (Level cluster C1 unblocked) est autorisé.

---

## Next Steps

1. **Démarrer Pre-Production** — implémenter le Vertical Slice
   - Option immédiate : `/dev-story production/epics/level-system/story-001-level-scene-root-state-machine.md`
   - Cluster C1 Lifecycle (stories 001-008) unblocked car ADR-0007 + ADR-0011 Accepted
2. **Sprint 0 Technical Setup follow-ups ADR-0008** — préalable recommandé avant story Combat impliquant collision layers
3. **Architecture.md r2** — re-génération recommandée pre-Production gate (non-blocker actuel)
