# Epics Index

Last Updated: 2026-04-27 (`/create-stories combat-system` — 14 stories Ready (11 Logic + 3 Integration). Story 006 exploite explicitement ADR-0008 Accepted (helper `CollisionLayers.build_mask` + Decision Matrix archetype Katana ShapeCast layer=1/mask=2 via API 1-indexée). Story 009 réutilise `CollisionLayers.build_mask([LAYER_ENEMY])` pour `PhysicsShapeQueryParameters3D`. Coverage 14/17 TR-cmb Covered, TR-cmb-006 N/A intentional, TR-cmb-016 Blocked Gap G-4. Stories 005/008/009 préparent Gap 2 (ShapeCast overlap origine) + Gap 7 (CapsuleShape3D basis) — owners lead-programmer pré-Sprint 1 via AC-CMB-47-Prelim + helper `_build_capsule_basis()`. Story 014 mesure `_collect_swing_hits()` complet (P-1 r6) p99 ≤ 5 ms + soak 1000 cycles + OBJECT_COUNT (P-08 r4). Sprint 0 prereq pour story 006 : `src/core/collision_layers.gd` + `project.godot [layer_names]` + lint CI `lint-collision-layers` (cf. ADR-0008 Migration Plan). Next : `/story-readiness production/epics/combat-system/story-001-scene-skeleton-structural-invariants.md` puis `/dev-story`.) — Previous : `/create-epics combat-system` créé l'epic 14/17 TRs Covered. — Previous 2026-04-24 (`/create-stories level-system` — 22 stories finales Ready après consolidation multi-scheme. Cleanup : 11 fichiers Schéma B (lint-first isolé) + 7 duplicates Schéma D (lifecycle redondants) + 2 duplicates getters/reload = 20 fichiers supprimés. Coverage finale C1 (001-008 lifecycle) + C2 (010-012 hierarchy+archetype+primitives) + C3 (013-014, 021 collision+walls+EC-7) + C4 (015-017 budgets+perf) + C5 (009 spatial lookups) + C6 (018 secret) + C7 (019 onboarding) + C8 (020 formulas) + V-presentation (022 shader/atlas). ADR-0007 GSM Accepted donc 5 TRs autrefois Blocked maintenant Ready. Next : `/story-readiness` + `/dev-story` sur story-001.)
Engine: Godot 4.6
Control Manifest Version: 2026-04-23

| Epic | Layer | System | GDD | Stories | Status |
|------|-------|--------|-----|---------|--------|
| [input-system](input-system/EPIC.md) | Foundation | Input System | [input-system.md](../../design/gdd/input-system.md) | 10 created (9 Ready + 1 Blocked story-010 attend ADR-0014) | Ready |
| [player-movement-system](player-movement-system/EPIC.md) | Core | Player Movement System | [player-movement-system.md](../../design/gdd/player-movement-system.md) | 18 created (17 Ready + 1 Blocked story-018 attend ADR-0015) | Ready |
| [camera-system](camera-system/EPIC.md) | Core | Camera System | [camera-system.md](../../design/gdd/camera-system.md) | 13 created (12 Ready + 1 Blocked story-013 attend ADR-0014) | Ready |
| [level-system](level-system/EPIC.md) | Core | Level System | [level-system.md](../../design/gdd/level-system.md) | 22 created (all Ready — C1..C8 full coverage) | Ready |
| [combat-system](combat-system/EPIC.md) | Feature | Player Combat System | [player-combat-system.md](../../design/gdd/player-combat-system.md) | 22 created (13 Ready + 9 Blocked — Gaps 1/2/5/7/8 + Audio/VFX/Accessibility) | Ready |

## Layer Progress

| Layer | Epics Created | Systems in Scope | Notes |
|-------|---------------|------------------|-------|
| Foundation | 1 / 3 | Input System ✅ ; Game State Manager ❌ (GDD absent, ADR-0007 Proposed) ; Save/Load ⏸️ (post-MVP polish, ADR-0014 Polish phase) | **Blocker partiel** : GSM epic attend GDD + ADR-0007 Accepted. Save/Load différé Polish phase (non-blocker MVP). |
| Core | 3 / 3 | Player Movement ✅ ; Camera ✅ ; Level ✅ ; Audio ❌ (ADR-0006 est Combat Tick Model — Audio ADR à numéroter distinctement, probablement ADR-0016 ou renumbering) | **Blocker partiel** : Audio epic attend ADR Audio System Architecture (mix buses, pooling AudioStreamPlayer, ducking, Movement/Level signal binding). Core layer architecturalement complète pour MVP Sprint 1 (Movement + Camera + Level prêts `/create-stories`). |
| Feature | 1 / 10 | Player Combat ✅ ; autres (Enemy, Hazard, Boss, Checkpoint/Respawn, Credit Economy, Shop, HUD, VFX/Feedback, Audio) ⏳ | Combat débloqué par ADR-0001/0002/0005/0006/0008 Accepted. Audio ADR à numéroter distinctement (ADR-0006 = Combat Tick Model). |
| Presentation | 0 / 3 | — | Attend Feature près de complet |

## Blocked / Out-of-Scope Foundation Systems

- **Game State Manager** : GDD absent (`systems-index.md` row 2 = Not Started). ADR-0007 planned (architecture.md §8.2, avant Sprint Menu/Checkpoint). Action : écrire GDD via `/design-system game-state-manager` puis `/architecture-decision` ADR-0007 avant de re-run `/create-epics layer:foundation`.
- **Save/Load System** : architecture.md §4.1 Foundation, marqué "post-MVP polish". Dépend de ADR-0014 (G-2a/b). Non prioritaire MVP.

## Next Steps

1. **`/create-stories level-system`** — décomposer l'epic Level en stories par cluster (C1..C8). Priorité Sprint 1 : C1 Lifecycle + C2 Scene hierarchy + C3 Collision layers (fondations dont dépendent C4..C8). 5 stories C1 Blocked jusqu'à ADR-0007 Accepted.
2. **`/story-readiness production/epics/input-system/story-001-inputmanager-autoload-boot.md`** puis `/dev-story` — démarrer l'implémentation de la 1ère story Foundation (10 stories Input créées, 9 Ready). Story Input-001 déjà implémentée et en attente de `/code-review` + `/story-done` selon session state.
3. **`/story-readiness production/epics/camera-system/story-001-scene-skeleton-project-settings.md`** puis `/dev-story` — démarrer Camera Story 001 (scene skeleton CameraArm + project settings rendering, foundation Camera epic)
4. **`/story-readiness production/epics/player-movement-system/story-001-*.md`** puis `/dev-story` — Movement Story 001 (scene skeleton Player + state enum + physics settings)
5. **Lead-programmer benchmark EC-8 Jolt CCD** en marge — runner headless `tests/performance/level_ccd_sweep_runner.gd` (dash + wall-run ~27 m/s sweep vs mur épaisseur MVP). Follow-up empirique, pas blocker epic.
6. **Unblock ADR-0007** : re-run `/architecture-review` ou décision explicite user pour transition Proposed → Accepted (débloque 5 TR-lvl cluster C1 Lifecycle).
7. **Unblock Audio** : `/architecture-decision` ADR Audio System Architecture (numérotation distincte — ADR-0006 est Combat Tick Model déjà Accepted) puis `/design-system audio-system` puis `/create-epics audio-system`
8. **Unblock GSM** : `/design-system game-state-manager` (post ADR-0007 Accepted)
9. **`/gate-check production`** après Foundation + Core epics + stories + implémentation (+ playtest prototype ≥ 3 sessions valide feel Pillar 1)
