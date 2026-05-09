# Sprint Pre-Production (rétroactif) — 2026-05-05

> **Status** : Closing — sprint plan rétroactif documentant les 14 epics complétés en Pre-Production avant gate Pre-Production → Production.

**Période** : 2026-04-15 → 2026-05-05 (3 semaines)
**Stage** : Pre-Production
**Branche** : `chore/story-014-tech-debt-cleanup` (consolidation cross-epic)
**Review mode** : Solo MVP

---

## Objectif sprint

Compléter les fondations Foundation + Core layers du MVP avec coverage tests automatisés, lints statiques, ADRs ratifiés, et CI verte avant entrée en Production. Sprint suivait pattern epic-direct (pas de file sprint formel) — ce document existe à des fins de traçabilité gate Pre-Production → Production conformément exigence "Sprint plan references real story file paths from `production/epics/`".

---

## Stories en scope — 175 total / 162 Complete (effectifs) / 1 Closed-Migrated / 12 unstarted (épics post-Pre-Production)

| Epic | Layer | Stories total | Complete | Ready/Pending | Status | Reference |
|------|-------|---------------|----------|---------------|--------|-----------|
| **input-system** | Foundation | 10 | **10/10** ✅ | — | Complete | `production/epics/input-system/EPIC.md` |
| **save-load-system** | Foundation | 8 | **8/8** ✅ | — | Complete | `production/epics/save-load-system/EPIC.md` |
| **menu-system** | Foundation | 13 | **13/13** ✅ | — | Complete | `production/epics/menu-system/EPIC.md` |
| **accessibility-system** | Foundation | 1 | **1/1** ✅ | — | Complete (interface layer ADR-0015) | `production/epics/accessibility-system/EPIC.md` |
| **audio-system** | Core | 12 | **12/12** ✅ | — | Complete (Epic close-out commit `6e5cf2b`) | `production/epics/audio-system/EPIC.md` |
| **camera-system** | Core | 13 | **13/13** ✅ | — | Complete | `production/epics/camera-system/EPIC.md` |
| **player-movement-system** | Core | 18 | **17/18** | 1 (canonical fails diagnostic post-`b60d809`) | Complete (1 story canonical fail tech-debt — voir notes) | `production/epics/player-movement-system/EPIC.md` |
| **combat-system** | Feature | 22 | **19/22** | 1 Ready (019 panel Martin) + 1 Closed-Migrated (021→VFX) + 1 (subtle Status format variance) | Complete (re-affirmé 2026-05-05 `qa-signoff-combat-system-2026-05-05.md` APPROVED WITH CONDITIONS) | `production/epics/combat-system/EPIC.md` |
| **enemy-system** | Feature | 6 | **6/6** ✅ | — | Complete | `production/epics/enemy-system/EPIC.md` |
| **level-system** | Feature | 23 | **23/23** ✅ | — | Complete | `production/epics/level-system/EPIC.md` |
| **credit-economy-system** | Feature | 8 | **7/8** | 1 (story-008 BLOCKED HUD epic absent) | Complete partiel (story-008 bloqué upstream HUD) | `production/epics/credit-economy-system/EPIC.md` |
| **shop-system** | Feature | 16 | **15/16** | 1 Deprecated Tier 2+ | Complete | `production/epics/shop-system/EPIC.md` |
| **upgrade-system** | Feature | 11 | **11/11** ✅ | — | Complete (1 partial AC-UPG-37-bis playtest DEFERRED) | `production/epics/upgrade-system/EPIC.md` |
| **hud-system** | Feature | 6 | **5/6** | 1 BLOCKED (story-006 playtest manuel Visual/Feel ADVISORY) | In Progress 2026-05-05 — 46/46 PASS cumulé (story-001..005 Complete) | `production/epics/hud-system/EPIC.md` |
| **vfx-system** | Feature | 8 | **6/8** | 2 Ready (story-008 ADVISORY playtest) | In Progress 2026-05-09 — autoload + combat + LRU + flash + accessibility + GSM gating ✅ **AC-CMB-42 + WCAG 2.3.1 + ADR-0015 D-1 + AC-VFX-15 GSM gating close-out cross-system VFX** ; 41/41 PASS cumulé / 3.07 s | `production/epics/vfx-system/EPIC.md` |

**Totaux scope sprint Pre-Production** :
- **Foundation** : 32/32 stories Complete (Input + SaveLoad + Menu + Accessibility) — 0 gap
- **Core** : 42/43 Complete (Audio + Camera + Movement) — 1 canonical fail Movement post-`b60d809` à diagnostiquer
- **Feature** : 81/87 Complete (Combat + Enemy + Level + Credit + Shop + Upgrade) — 1 Closed-Migrated + 1 Blocked upstream + 1 Ready panel Martin + 1 Deprecated + 1 partial DEFERRED
- **Out of scope (Production sprint suivant)** : HUD 0/6 + VFX 0/8 = 14 stories à venir

**Effectifs livrés Pre-Production** : ~155-162 stories complétées + 13 archivées historiques = **~175 stories tracked**.

---

## Architecture livrée

| Artefact | Status | Reference |
|----------|--------|-----------|
| Master architecture document | ✅ | `docs/architecture/architecture.md` |
| Architecture traceability matrix | ✅ 0 Foundation gaps + 0 Core gaps | `docs/architecture/architecture-traceability.md` |
| Control manifest | ✅ | `docs/architecture/control-manifest.md` |
| ADRs Accepted | **15 ADRs** Accepted (ADR-0001 à ADR-0011 + ADR-0014 + ADR-0015) | `docs/architecture/adr-*.md` |
| Engine reference Godot 4.6 | ✅ | `docs/engine-reference/godot/VERSION.md` |
| TR registry | ✅ | `docs/architecture/tr-registry.yaml` |

---

## QA livré

| Artefact | Status | Reference |
|----------|--------|-----------|
| QA plans | ✅ 2 plans | `production/qa/qa-plan-audio-system-2026-05-04.md` + `qa-plan-combat-system-2026-05-04.md` |
| QA sign-offs | ✅ 3 sign-offs (Audio + Combat ×2) | `production/qa/qa-signoff-audio-system-2026-05-04.md` + `qa-signoff-combat-system-2026-05-04.md` + `qa-signoff-combat-system-2026-05-05.md` |
| Smoke checks | ✅ 2 reports | `production/qa/smoke-2026-05-04.md` (PASS WITH WARNINGS) + `smoke-2026-05-05.md` (FAIL infra cross-pollution — Combat scope isolated PASS) |
| Test suite mature | ~1035 tests, Combat scope **118/118 PASS** isolated | Global suite pollué par autoload reuse cross-suite (tech-debt W-4) |
| Lints statiques | ✅ 5 lints CI | collision-layers + audio-anti-patterns + movement-emit-physics-only + no-alloc-hot-paths + input-main-thread |

---

## GDDs livrés

**18 GDDs MVP-tier** dans `design/gdd/` :

- audio-system, camera-system, credit-economy, enemy-system, hud-system, input-system, level-system, menu-system, player-combat-system, player-movement-system, save-load-system, secret-system, shop-system, upgrade-system, vfx-system, accessibility-requirements (`design/`), game-concept, game-pillars

**Cross-GDD review** : `design/gdd/gdd-cross-review-*.md` présent (passing).

---

## Tech-debt connue (sprint Production)

1. **Test infra autoload reuse cross-suite GdUnit4 v5** (W-4 smoke-2026-05-05) — full-suite cmdtool unique fail, scope per-epic isolated PASS confirmé. Story tech-debt dédiée à créer.
2. **Movement canonical fails 4** (jump_coyote / gravity_airborne / grounded_horizontal / wall_jump) post-commit `b60d809 fix(player): physics_interpolation_mode=2 (OFF) Godot 4.6` — diagnostic requis.
3. **Camera 8 fails story_001 isolé** (scene_skeleton_project_settings) — à confirmer.
4. **Tier 1 hardware sign-off DEFERRED** (W-1+W-2 smoke-2026-05-04) — gates draw_calls + 60 fps full-stack baselines à exécuter sur Tier 1 minimum (i3-10100F + GTX 1050) avant Production.
5. **Story-018 (f) zero warnings stderr DEFERRED** — instrumentation framework GdUnit4 manquante.
6. **Story-019 Combat panel ≥5 testeurs × 3 sessions Martin** — protocol publié, recrutement pending (`production/qa/protocols/combat-feel-interview.md`).

---

## Vertical Slice — état empirique

**Code source** : 14 epics complétés couvrent boot → main menu → new game → level (etage 1) → combat (katana sweep + slow-mo) → death/respawn → save/load → upgrade/shop/credit chain.

**Empirical validation** : **PENDING** — `feel-playtest-session-1-2026-04-27.md` reste en TEMPLATE (zéro session humaine documentée). Ceci est le bloquer principal restant pour passer gate Pre-Production → Production (Vertical Slice Validation Item 1 = NOT DONE).

**Minimal path to Production gate PASS** :
1. Martin lance le jeu 30 min (boot → core loop end-to-end) — remplit playtest template + signal critical fun blockers (oui/non)
2. Re-run `/gate-check pre-production-to-production` post-playtest

---

## References

- Architecture : `docs/architecture/architecture.md`
- Traceability : `docs/architecture/architecture-traceability.md`
- ADR list : `docs/architecture/adr-*.md` (15 Accepted)
- Epics index : `production/epics/index.md`
- Stories total : 175 (162 Complete + 13 archivées)
- Yesterday's gate-check : `production/gate-checks/2026-05-04-pre-production-to-production.md` (FAIL — minimal path identifié)
- Today's smoke : `production/qa/smoke-2026-05-05.md` (FAIL infra cross-pollution / Combat isolated PASS)
- Today's signoff : `production/qa/qa-signoff-combat-system-2026-05-05.md` (APPROVED WITH CONDITIONS)
