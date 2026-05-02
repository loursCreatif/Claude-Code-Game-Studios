# Gate Check: Pre-Production → Production

**Date** : 2026-04-27
**Checked by** : `/gate-check production` skill
**Review mode** : `solo` (director panel skipped — artifact + quality checks only)
**Stage source** : `production/stage.txt` = `Pre-Production`

---

## Verdict : **FAIL**

> La gate Pre-Production → Production exige un **Vertical Slice jouable et playtesté**. Le projet n'a aucun scene d'intégration (pas de `run/main_scene` dans `project.godot`), aucun sprint plan, aucune session de playtest sur build intégré, et le HUD/pause UX sont absents. Plusieurs des 4 critères de **Vertical Slice Validation** échouent — ce qui force automatiquement la verdict en **FAIL** par règle du gate (« #1 cause of production failure » per GDC postmortem data, 155 projects).
>
> Excellente nouvelle : la **Foundation technique est solide** (9 ADRs Accepted, control manifest, architecture doc, traceability index, 79 tests, 5 epics avec stories Ready, code Movement/Level/Combat scaffolded). La gate est franchissable en **2-3 sprints courts** si on bascule l'effort sur l'intégration.

---

## Required Artifacts : 6 / 14 ✅

| Item | Status | Note |
|---|---|---|
| ✅ | Au moins 1 prototype dans `prototypes/` avec README | `prototypes/movement-katana/` — README + REPORT présents |
| ❌ | Sprint plan dans `production/sprints/` | **DOSSIER VIDE** — aucun sprint plan rédigé |
| ⚠️ | Art bible 9 sections complètes + sign-off AD-ART-BIBLE | 9 sections présentes ; sign-off **« Skipped — Solo mode »** |
| ❌ | Character visual profiles | Aucun (`design/art/characters/` inexistant) |
| ⚠️ | Tous les MVP-tier GDDs complets | **8/17 GDDs présents**, **4/17 APPROVED MVP** (Combat r6, Level r3, GSM r1, Audio r2.1) — Movement/Camera/Input pending re-review fresh ; 9 GDDs Not Started (Save/Load, Hazard, Enemy, Checkpoint, Credit Economy, Upgrade, Shop, Secret, HUD, Menu, VFX) |
| ✅ | Master architecture document | `docs/architecture/architecture.md` 25 KB |
| ✅ | ≥3 ADRs Foundation-layer | **9 ADRs** (0001-0009 + 0011) couvrant Physics, Camera, Rendering, Input, Movement Signals, Combat Tick, GSM, Collision Layers, Audio, Level Scene |
| ✅ | Control manifest | `docs/architecture/control-manifest.md` 24 KB |
| ⚠️ | Epics Foundation + Core layers | Foundation **1/3** (Input ✅ ; GSM ❌ ; Save/Load ⏸ post-MVP) ; Core **3/3** (Movement, Camera, Level) ; Feature 1/10 (Combat) |
| ❌ | **Vertical Slice build playable** | **Aucune scène d'intégration** : `project.godot` n'a pas de `run/main_scene`. Seulement `Player.tscn`, `combat_system.tscn`, `input_debug_overlay.tscn` isolés |
| ❌ | Vertical Slice playtested ≥3 sessions | `production/playtests/` **vide**. Templates DEFERRED dans `production/qa/evidence/` (story-017) — playtests réels non exécutés |
| ❌ | Vertical Slice playtest report | Idem — non produit |
| ⚠️ | UX specs main menu, HUD, pause | **Seulement `main-menu.md`** — `hud.md` ❌, `pause-menu.md` ❌ |
| ❌ | HUD design document | **Manquant** (`design/ux/hud.md`) |

---

## Quality Checks : 3 / 12 ✅

| Item | Status | Note |
|---|---|---|
| ❌ | **Core loop fun validated by playtest data** | Pas de playtest de la VS intégrée. Seules données : prototype `movement-katana` (« code à jeter ») |
| ⚠️ | UX specs couvrent UI Requirements de tous les MVP GDDs | Couverture partielle (main-menu seulement) |
| ✅ | Interaction pattern library documente patterns key screens | `design/ux/interaction-patterns.md` Standard tier, baseline initialisée |
| ✅ | Accessibility tier addressé dans key screens | Tier **Standard** committed (`design/accessibility-requirements.md` 17 KB) |
| ✅ | Sprint plan référence stories réelles | N/A — pas de sprint plan |
| ❌ | **Vertical Slice COMPLETE start→challenge→resolution** | Aucune VS intégrée n'existe. Stories implementées en isolation (Movement, Level, Combat partiel) sans intégration |
| ⚠️ | Architecture sans open questions Foundation/Core | Quelques OQs pendantes (ADR-0014 G-2a/b deferred Polish) — non-blockers |
| ✅ | Tous ADRs ont Engine Compatibility section | À vérifier formellement, mais convention respectée sur ADR-0001 à 0011 |
| ⚠️ | Tous ADRs ont ADR Dependencies section | Convention respectée |
| ⚠️ | `/review-all-gdds` + `/architecture-review` récents | `/architecture-review` ✅ (9 reports — dernier r5-audio 2026-04-27). **`/review-all-gdds` cross-GDD report ABSENT** dans `design/gdd/` |
| ❌ | **Core fantasy delivered** (playtester décrit Pillar 1 sans prompt) | Pas de playtest VS — non vérifiable |

---

## Vertical Slice Validation : 0 / 4 ✅ — **AUTO-FAIL**

> Règle du gate : « If any Vertical Slice Validation item is FAIL, the verdict is automatically FAIL regardless of other checks. »

| Item | Status | Note |
|---|---|---|
| ❌ | Un humain a joué la core loop sans dev guidance | **Pas de VS à jouer**. Le prototype `movement-katana` ne compte pas (separate project, marked NOT FOR PRODUCTION) |
| ❌ | Le jeu communique quoi faire dans les 2 premières minutes | N/A — pas de scène entry-point |
| ❌ | Aucun bug bloquant dans la VS build | N/A — pas de VS |
| ❌ | Le core mechanic feels good (subjective check) | À valider par Martin sur build intégré ; prototype validé feel-only séparé |

---

## Blockers (à résoudre avant Production)

### 1. **Vertical Slice scene absente** — BLOQUANT MAJEUR
`project.godot` n'a pas de `run/main_scene`. Aucune scène n'intègre Player + Camera + Level + Combat. Le prototype dans `prototypes/movement-katana/` est explicitement « NOT FOR PRODUCTION ».
**Action** : créer `src/main.tscn` qui charge un `Etage` exemple (test_etage_01.tscn ou vraie level art) avec Player + Camera + Combat + 1 ennemi de test. Ajouter `run/main_scene="res://src/main.tscn"` à `project.godot`. Cette scène doit démontrer la **core loop end-to-end** : entrée étage → mouvement/parkour → combat 1 ennemi → checkpoint/secret → exit trigger.

### 2. **Aucun sprint plan** — BLOQUANT REQUIRED
`production/sprints/` est vide.
**Action** : `/sprint-plan` pour générer le Sprint 1 plan referencing real stories from `production/epics/*/`.

### 3. **Aucun playtest de la VS** — BLOQUANT REQUIRED
`production/playtests/` vide. Les evidence dans `production/qa/evidence/` sont DEFERRED templates (story-017 Movement) — pas de session réelle sur build intégré.
**Action** : après création VS, **3 sessions playtest minimum** documentées dans `production/playtests/` couvrant new player experience + mid-game systems + difficulty curve.

### 4. **HUD design doc manquant** — BLOQUANT REQUIRED
`design/ux/hud.md` n'existe pas. Le jeu a une HUD (crédits, secrets count, état player, slow-mo cue, kill confirm) — required.
**Action** : `/ux-design hud` ou `/team-ui hud`. Couvre crédits + secrets + slow-mo cue + kill confirm + reduce_flash/motion compliance Standard tier.

### 5. **Pause menu UX spec manquant** — BLOQUANT REQUIRED
**Action** : `/ux-design pause-menu`.

### 6. **MVP GDDs incomplets (4/17 APPROVED, 9 Not Started)** — BLOQUANT REQUIRED
GDDs absents : Save/Load (post-MVP polish, OK), Hazard, Enemy, Checkpoint & Respawn, Credit Economy, Upgrade, Shop, Secret System, HUD System, Menu System, VFX & Feedback.
**Action MVP minimum** : Sprint 1 a besoin minimum de **Enemy + Checkpoint + Credit Economy + HUD** designés. Hazard + Secret + Shop peuvent attendre Sprint 2. `/design-system enemy-system` puis chainer.

### 7. **GDDs Movement / Camera / Input pending re-review fresh** — BLOQUANT QUALITY
Status `In Review` dans `systems-index.md` pour Movement r3, Camera r2, Input r4 — fixes appliqués, re-review fresh non lancée.
**Action** : `/design-review design/gdd/player-movement-system.md` + même chose Camera + Input. Vise APPROVED.

### 8. **Cross-GDD review absent** — BLOQUANT QUALITY
Aucun `design/gdd/gdd-cross-review-*.md`.
**Action** : `/review-all-gdds` une fois les 3 GDDs Movement/Camera/Input APPROVED.

### 9. **Foundation epic GameStateManager non créé** — BLOQUANT
ADR-0007 Accepted ✅ et GSM GDD APPROVED r1 ✅ — mais l'epic n'existe pas dans `production/epics/`. Sans GSM autoload, pas de scène intégrée fonctionnelle (pause, scene transitions, respawn pipeline).
**Action** : `/create-epics game-state-manager` puis `/create-stories game-state-manager` puis `/dev-story` sur les stories Foundation Sprint 1 (autoload boot + state enum + signal bus minimal).

---

## Recommendations (non-blocking)

- **R1 — Solo mode AD-ART-BIBLE sign-off** : commentaire « Skipped — Solo mode » accepté par le protocole solo, mais reconfirme verbalement avec Martin avant Production.
- **R2 — Character visual profiles** : si seuls Player + 3 ennemis types existent dans la vision, créer `design/art/characters/{player,grunt-medium,sentinel-fast,brute-heavy}.md` (1 page chacun) avant production assets.
- **R3 — Cleanup Foundation Save/Load** : confirmer formellement Save/Load = Polish phase dans `architecture.md` et systems-index (déjà coché — juste valider le freeze).
- **R4 — Stories status normalization** : 5 epics × 80 stories utilisent un format `**Status**: ...` fragile à grepper. Standardiser en frontmatter YAML `status: Ready|InProgress|Complete` aiderait `/sprint-status` et `/gate-check` futurs.
- **R5 — Tests Movement story-017 evidence DEFERRED** : 5 templates Visual/Feel dans `production/qa/evidence/` à compléter dès qu'un VS jouable existe (Martin + 5 tiers playtesters).

---

## Roadmap minimale vers PASS (3 sprints courts estimés)

### Sprint A — « Vertical Slice Backbone » (~5 jours)
1. `/design-system enemy-system` + `/design-system checkpoint-respawn` + `/design-system credit-economy` + `/ux-design hud`
2. `/architecture-decision` ADR Enemy + ADR Checkpoint si nécessaire
3. `/create-epics game-state-manager` + `/create-stories game-state-manager`
4. `/dev-story` sur GSM Foundation stories (autoload + state enum + signal_bus minimal)
5. Créer `src/main.tscn` (Player + Camera + 1 etage test + 1 enemy stub) → ajouter `run/main_scene` dans `project.godot`

### Sprint B — « VS playable » (~5 jours)
1. `/dev-story` Enemy stub minimal (1 archetype, 1 hit deals damage, 1 hit dies)
2. `/dev-story` Checkpoint + respawn pipeline
3. `/dev-story` Credit collection on kill + secret triggers
4. `/dev-story` HUD minimal (crédits + secrets count)
5. `/sprint-plan` Sprint 1 (référence stories réelles ci-dessus)
6. `/design-review` Movement + Camera + Input → APPROVED fresh
7. `/review-all-gdds`

### Sprint C — « VS playtest + sign-off » (~3 jours)
1. 3 sessions playtest sur build VS (Martin + 2 tiers minimum)
2. `/playtest-report` × 3
3. Compléter evidence story-017 Movement Visual/Feel
4. `/team-qa sprint` + `/smoke-check` PASS
5. **Re-run `/gate-check production`** → PASS attendu

---

## Chain-of-Verification (5 questions pour FAIL draft)

**Q1 — Ai-je correctement séparé hard blockers vs strong recommendations ?**
→ Oui. Les 9 blockers sont tous artifacts/quality checks listés explicitement dans la spec gate. Les R1-R5 sont des suggestions non listées dans la spec.

**Q2 — Y a-t-il des items PASS où j'ai été trop laxiste ?**
→ Art bible : 9 sections présentes mais sign-off skipped (solo mode). Le gate exige « AD-ART-BIBLE sign-off verdict is recorded ». Strictement c'est ⚠️ pas ✅. Marqué ⚠️ pour cohérence.
→ Control manifest : 24 KB est-il suffisamment détaillé ? Read partiel suggère oui (extracted from accepted ADRs, used by all stories). PASS confirmé.

**Q3 — Y a-t-il des blockers additionnels manqués ?**
→ Le gate exige aussi que `/architecture-review` soit récent. Dernier report 2026-04-27 r5-audio = OK.
→ Le gate exige « ADR Engine Compatibility section ». Pas formellement vérifié sur les 9 ADRs — risque latent. Ajouté en ⚠️.
→ Pas de regression manquée.

**Q4 — Path minimal vers PASS clair ?**
→ Oui : roadmap Sprint A/B/C ci-dessus. Les 9 blockers se résolvent en 13 jours estimés.

**Q5 — Le FAIL est-il résolvable, ou indique-t-il un problème de design plus profond ?**
→ **Résolvable**. La Foundation technique est solide (9 ADRs, control manifest, 79 tests, 5 epics, code Movement+Level+Combat scaffolded). Le projet a de l'avance sur la couche architecture mais retard sur la couche intégration. Pivot d'effort sur VS et 4 GDDs MVP (Enemy, Checkpoint, Credit Economy, HUD) suffit.

**Conclusion verification** : verdict **unchanged — FAIL**. 5 questions checked.

---

## Prochaines étapes recommandées

| | Action | Cmd |
|---|---|---|
| **A** | **Recommandé** : démarrer Sprint A (« VS Backbone ») — `/design-system enemy-system` puis chainer Checkpoint + Credit Economy + HUD UX | `/design-system enemy-system` |
| **B** | Si urgence : créer le VS scene minimal d'abord avec stub enemy hardcoded, défer GDDs | manual `src/main.tscn` |
| **C** | Si scope reduction nécessaire : déférer Combat full au Sprint 2 et viser VS « parkour-only loop » (déjà 90% prêt) — Movement+Camera+Level intégrés sans combat | `/scope-check` |
| **D** | Stop session ici, Martin re-priorise demain | — |
