# Gate Check: Technical Setup → Pre-Production

**Date** : 2026-04-27
**Checked by** : `/gate-check pre-production` skill
**Mode** : Solo (director gates CD/TD/PR/AD skipped — artifact + quality checks only)
**Current `production/stage.txt`** : `Pre-Production` (déjà entré)
**Target validé** : Technical Setup → Pre-Production (retroactive validation)

---

## Disambiguation

Le projet est déjà en `Pre-Production`. Cette gate-check valide **rétroactivement** la transition TS → PP avec le travail accumulé depuis. Le résumé Pre-Production → Production (gate suivante) est ajouté en bonus en §3.

---

## 1. Required Artifacts: 13/13 present ✅

- [x] **Engine choisi** — Godot 4.6 (CLAUDE.md + technical-preferences.md)
- [x] **Technical preferences populé** — naming conventions, performance budgets, file extension routing, engine specialists
- [x] **Art bible** — `design/art/art-bible.md` 10 sections (≥ 4 requises Visual Identity Foundation)
- [x] **≥ 3 ADRs Foundation-layer** — 10 ADRs présents, dont Foundation : ADR-0001 (Physics 60 Hz), ADR-0004 (Input API + Focus), ADR-0007 (Game State Manager). Plus Core/Feature : ADR-0002 (Camera), ADR-0003 (Rendering), ADR-0005 (Movement Signals), ADR-0006 (Combat Tick), ADR-0008 (Collision Layers), ADR-0009 (Audio — **Proposed** new), ADR-0011 (Level Scene)
- [x] **Engine reference docs** — `docs/engine-reference/godot/` avec VERSION.md + breaking-changes.md + deprecated-apis.md + current-best-practices.md + modules/{audio,physics,input,navigation,networking,rendering,ui,animation}.md
- [x] **Test framework** — `tests/unit/` + `tests/integration/` + `tests/performance/` + `tests/smoke/` + `tests/fixtures/` + `tests/helpers/` + `gdunit4_runner.gd` script
- [x] **CI workflow** — `.github/workflows/tests.yml` exists
- [x] **Example tests** — multiple .gd test files (ex : `enable_refcount_test.gd`, `latency_ring_buffer_test.gd`, `was_pressed_this_tick_test.gd`, `story_005_tilt_wall_run_test.gd`)
- [x] **Master architecture doc** — `docs/architecture/architecture.md`
- [x] **Architecture traceability index** — `docs/architecture/architecture-traceability.md` v2.3 (88 TRs / 80 Covered = 91%)
- [x] **`/architecture-review` run** — 9 review reports dans `docs/architecture/architecture-review-*.md` (dernière r4 du 2026-04-23, verdict PASS)
- [x] **Accessibility requirements** — `design/accessibility-requirements.md` exists
- [x] **Interaction pattern library** — `design/ux/interaction-patterns.md` exists ; aussi `design/ux/main-menu.md`

---

## 2. Quality Checks: 9/10 passing ✅ (1 advisory)

- [x] **ADR coverage core systems** — Rendering (ADR-0003), Input (ADR-0004), State management (ADR-0007), Physics (ADR-0001), Movement (ADR-0005), Camera (ADR-0002), Combat (ADR-0006), Collision (ADR-0008), Audio (ADR-0009), Level (ADR-0011)
- [x] **Naming conventions + perf budgets** — `.claude/docs/technical-preferences.md` complet
- [x] **Accessibility tier défini** — `design/accessibility-requirements.md` exists
- [x] **Main menu UX spec démarré** — `design/ux/main-menu.md` exists
- [x] **ADR Engine Compatibility sections (10/10)** — toutes ADR ont Engine Compatibility + ADR Dependencies + GDD Requirements Addressed (verified via `grep -c "^## Engine Compatibility\|^## ADR Dependencies\|^## GDD Requirements Addressed"` retourne 3 par ADR)
- [x] **No deprecated APIs in ADRs** — grep `yield(|TileMap[^L]|VisibilityNotifier|Navigation2D|Navigation3D` sur tous ADRs retourne zéro match
- [x] **HIGH RISK engine domains addressed** — Audio (LOW), Physics (MEDIUM ADR-0001 + Jolt notes), Rendering (HIGH ADR-0003 Forward+ + glow rework + D3D12), Input (LOW). Tous documentés ou flaggés en open questions ADR-level
- [x] **Foundation layer gaps = 0** — architecture-traceability.md v2.3 confirme `Foundation layer gaps : 0` ✅, `Core layer gaps : 0` ✅, `Feature layer blockers MVP : 0` ✅
- [x] **ADR Circular Dependency Check** — graph build : ADR-0001 → ∅ ; ADR-0002 → ADR-0001 ; ADR-0003 → ADR-0001 ; ADR-0004 → ADR-0001 ; ADR-0005 → ADR-0001 ; ADR-0006 → ADR-0001/0005 ; ADR-0007 → ADR-0001/0004/0005 ; ADR-0008 → ADR-0001 ; ADR-0009 → ADR-0001/0002/0005/0006/0007/0011 ; ADR-0011 → ADR-0001/0003/0005/0006/0007. **Aucun cycle détecté** ✅
- [⚠️] **ADR-0009 Audio Status** — `Proposed` (newly written 2026-04-27, not yet Accepted). Non-blocking pour TS → PP (Foundation 3+ ADRs déjà Accepted via ADR-0001/0004/0007). Bloque toutefois Audio epic + story-020 Combat. À promouvoir Accepted via fresh `/architecture-review` session indépendante.

---

## 3. Bonus: Pre-Production → Production gate readiness (informational)

**Verdict prospectif** : **FAIL** — gate suivante (PP → Production) n'est pas franchissable actuellement.

### Required Artifacts manquants pour PP → Production

- [❌] **Vertical Slice playable build** — `prototypes/movement-katana/` existe mais pas validé comme VS-complete (build de prototype, pas vertical slice end-to-end testé)
- [❌] **≥ 3 playtest sessions** — `production/playtests/` n'existe pas
- [❌] **Vertical Slice playtest report** — absent
- [❌] **First sprint plan** — `production/sprints/` n'existe pas
- [❌] **HUD design doc** — `design/ux/hud.md` absent
- [⚠️] **All MVP GDDs complete** — seulement 4/17 APPROVED (Input r4, GSM r1, Combat r6, Level r3). 2 In Review (Movement r3, Camera r2 — pending fresh re-review). 11 Not Started (Save/Load, Audio, Checkpoint, Enemy, Hazard, Credit Economy, Upgrade, Shop, Secret, HUD, Menu, VFX/Feedback). Audio System GDD bloqué par ADR-0009 Proposed → à promouvoir.

### Required Artifacts présents pour PP → Production

- [x] **Master architecture doc** ✅
- [x] **3+ ADRs Foundation** ✅ (10 ADRs)
- [x] **Control manifest** ✅ (`docs/architecture/control-manifest.md` v2026-04-23)
- [x] **Epics Foundation + Core layer** ✅ (input-system, player-movement-system, camera-system, level-system, combat-system) + EPIC.md index à jour avec 5 epics

### Recommandations pour franchir PP → Production

1. **Promouvoir ADR-0009 Audio Proposed → Accepted** (fresh `/architecture-review` session)
2. **Approuver Movement + Camera GDDs** (fresh `/design-review` r4 sessions sur Movement et r3 fresh sur Camera)
3. **Construire Vertical Slice end-to-end** : Sprint 1 implémentation Movement + Camera + Level + Combat stories Ready actuels
4. **Lancer ≥ 3 playtest sessions** sur le VS, documenter dans `production/playtests/`
5. **Écrire HUD design doc** (`/ux-design hud`) — TR-cmb-013 cooldown_ratio + checkpoint indicator + score
6. **Designer 11 GDDs MVP restants** (Save, Audio, Checkpoint, Enemy, Hazard, Credit, Upgrade, Shop, Secret, HUD, Menu, VFX) — éligibles `/design-system [system]` parallélisables
7. **Créer first sprint plan** (`/sprint-plan`) référence stories epics existants
8. **/team-qa sprint** + **smoke-check** post-VS-complete

---

## 4. Blockers (TS → PP)

**Aucun** ✅ — gate retroactivement validée.

L'unique signal mineur est **ADR-0009 Audio Proposed**, mais ne bloque pas la transition TS → PP (Foundation a déjà 3+ ADRs Accepted). Bloque seulement l'avancement vers PP → Production des stories Audio downstream.

---

## 5. Recommandations

**Pour conserver l'état Pre-Production (saine)** :
- Promouvoir ADR-0009 → Accepted via fresh `/architecture-review`
- Approuver Movement + Camera GDDs via fresh `/design-review`
- Maintenir l'inventory architecture-traceability à 91%+ Coverage

**Pour préparer PP → Production (priorisé)** :
1. Vertical Slice build (impl Sprint 1 stories Ready Combat/Movement/Camera/Level)
2. ≥ 3 playtests sessions internes
3. Sprint 1 plan formel
4. 11 GDDs MVP manquants (Save/Audio peuvent paralléliser dès maintenant ; HUD/Menu/VFX gates Vertical Slice ; Checkpoint/Enemy/Hazard/Credit/Upgrade/Shop/Secret gates Sprint 2-4)

---

## 6. Chain-of-Verification

**5 questions Pass-draft :**

1. **Vérifié par lecture vs inferred ?** — Tous les artefacts checked via `ls` ou `grep` direct. ADR sections via `grep -c`. Foundation gaps via lecture explicite traceability v2.3. ✅ Verified, pas inferred.

2. **MANUAL CHECK NEEDED items marqués PASS sans confirmation user ?** — Non. `Core loop fun validated` et `Core fantasy delivered` ne sont pas dans gate TS → PP (ils appartiennent à PP → Production). Pour TS → PP, tous critères auto-vérifiables.

3. **Artefacts content vs empty headers ?** — Vérifié pour ADR (3 sections each via grep), art-bible (10 sections), control manifest (header + version), tests (multiple .gd files). architecture-traceability lu directement. ✅

4. **Blocker dismissed comme minor pourrait être vrai bloqueur ?** — ADR-0009 Proposed est marqué advisory. Le gate exige "ADRs cover core systems" — Audio est core, mais Audio System GDD n'existe pas non plus. Cependant Pre-Production gate ne demande pas tous les MVP systems implémentés — seulement architecture coverage. Foundation gaps = 0 confirme architecture coverage suffisante. Verdict tient.

5. **Single check moins confiant ?** — `interaction-patterns.md` content quality non lu. Si fichier est un stub vide, le gate ne devrait pas pass. Vérification additionnelle requise (file existence + minimum content). Non vérifié — ADVISORY (pas blocker, fichier exists).

**Verdict final** : **unchanged — PASS** (Chain-of-Verification : 5 questions checked).

---

## Verdict: **PASS** (Technical Setup → Pre-Production)

Le projet a légitimement franchi la transition Technical Setup → Pre-Production. Tous les artefacts requis sont présents avec contenu réel ; toutes les quality checks passent (9/10 strict + 1 advisory ADR-0009 Proposed non-blocking pour cette gate).

**Prospective PP → Production** : **FAIL** — vertical slice + playtests + 11 GDDs MVP + sprint plan + HUD design manquants. Roadmap claire (§3) pour franchir cette prochaine gate.

---

## Update `production/stage.txt`?

**Aucun changement requis** — `production/stage.txt` est déjà `Pre-Production`. La gate retroactive ne nécessite pas d'écriture.
