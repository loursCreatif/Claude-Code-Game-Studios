# Epic: Enemy System

> **Status**: Active (Sprint 1 Foundation)
> **Owner**: Gameplay
> **Manifest Version**: 2026-04-23
> **Governing ADRs**: ADR-0006 Combat Tick Model, ADR-0008 Collision Layer Taxonomy

## Overview

Système d'entités hostiles MVP — Grunts statiques humanoïdes braquant un cône
laser frontal létal. Invariant inviolable **one-shot mutuel** : tout enemy
standard est 1 PV strict, le LaserCone tue le Player en 1 hit, le katana tue
le Grunt en 1 hit.

Architecture : `CharacterBody3D` (LAYER_ENEMY=2) + `Area3D` LaserCone
(LAYER_ENEMY_HITBOX=3, mask LAYER_PLAYER=1) + state machine ALIVE → DYING
→ DEAD avec tween wall-clock 150 ms (`set_ignore_time_scale(true)`).

**Pillars implémentés** : Pillar 1 FLOW (lecture instantanée, coda du clac),
Pillar 3 SECONDE CHANCE (mort pédagogique — grunt reste à sa place au respawn).

## Governing ADRs

| ADR | Title | Status | Coverage |
|-----|-------|--------|----------|
| ADR-0006 | Combat Tick Model | Accepted | Ordre `_physics_process` parent/enfant, signal SYNC `enemy_killed` |
| ADR-0008 | Collision Layer Taxonomy | Accepted r4 2026-04-23 | LAYER_ENEMY=2, LAYER_ENEMY_HITBOX=3 figés |

## GDD Source

`design/gdd/enemy-system.md` — **APPROVED r2** 2026-04-27 (28 ACs, 16 EC, 7 Tuning Knobs).

## Cross-GDD Gates (CLEARED)

| Gate | Status | Source |
|------|--------|--------|
| Combat r7 amendement OQ-ENM-1 | ✅ CLEARED 2026-04-27 | `Enemy` est l'autorité d'émission de `enemy_killed` ; Combat consumer SYNC pour slow-mo Rule 13 |
| Movement r3+ confirmation `Player.die()` bidirectionnel | ✅ CLEARED | Movement Rule 9 + Interactions table cite Enemy comme caller de `Player.die()` |

## Stories

| ID | Title | Status | Layer | Type | ACs Targeted |
|----|-------|--------|-------|------|--------------|
| 001 | Foundation Grunt script + state machine + die idempotent + tween wall-clock | ✅ Complete 2026-05-02 | Foundation | Logic | AC-ENM-01/02/03/07/07b/11/12/18/18b |
| 002 | Scene `Grunt.tscn` + collision layers + LaserCone Area3D + lethal handler | ✅ Complete 2026-05-02 | Core | Logic+Integration | AC-ENM-04/05/06/07c |
| 003 | LevelSystem spawn integration (`EnemySlot_*` Marker3D iteration + archetype fallback) | ✅ Complete 2026-05-02 | Core | Integration | AC-ENM-08/09/10 |
| 004 | Combat sweep + Player laser integration tests (cross-system) | Blocked (story-002+Combat impl) | Integration | Integration | AC-ENM-13/14/15 |
| 005 | Pause/state lifecycle integration (GameStateManager) | ✅ Complete 2026-05-02 | Integration | Integration | AC-ENM-19/20 |
| 006 | Authoring lints (`validate_enemy_slot_*` triplet) | ✅ Complete 2026-05-02 | Tooling | Logic | AC-ENM-23/24/25 |
| 007 | Performance benchmark 30 grunts (frame budget + zero-alloc) | ✅ Complete 2026-05-02 | Perf | Perf | AC-ENM-21/22 |
| 008 | Visual/Feel playtest evidence | Ready (story-007 perf validé) | Polish | Visual | AC-ENM-26/27/28 |

**Totaux** : 1 Ready / 1 Blocked / 6 Complete.

**Tests** : 50/50 PASSED — story-001 (11) + story-002 (13) + story-003 (6) + story-005 (4) + story-006 lints (12) + story-007 perf (4).

## TR Coverage

| TR-ID | Description | Covered by | Status |
|-------|-------------|------------|--------|
| TR-cmb-013 | `enemy.die()` idempotent contract | story-001 | ✅ Complete |
| TR-cmb-014 | `Enemy.enemy_killed` signal SYNC | story-001 | ✅ Complete |
| TR-lvl-009 | EnemySlot factory iteration | story-003 | ✅ Complete |
| TR-enm-001 | Tween wall-clock `set_ignore_time_scale(true)` | story-001 | ✅ Complete |
| TR-enm-002 | LaserCone state guard `_state != ALIVE` | story-002 | ✅ Complete |
| TR-enm-003 | Tween pause behavior `TWEEN_PAUSE_BOUND` (EC-ENM-9) | story-005 | ✅ Complete |
| TR-enm-004 | Authoring lints `validate_enemy_slot_*` triplet | story-006 | ✅ Complete |
| TR-enm-005 | Frame budget 30 grunts + zero-alloc per-tick (Rule 10 enforced) | story-007 | ✅ Complete |

## Out of Scope MVP

- **Boss System** — système séparé (post-MVP).
- **AI mobile/pathfinding** — Grunt MVP est strictement statique (Rule 10).
- **Hazard System** — cousin Tier 2+, contract latent au MVP.
- **Tier 2+ archétypes** : sentinelle pivotante, brute, drone, sniper.
- **Animation idle/breathing** — fixture rigide MVP.

## Notes

- **No-alloc hot paths** : Grunt MVP n'a pas de hot path (pas de `_physics_process`,
  Rule 10). Pas de scope no-alloc requis tant que Tier 2+ n'introduit pas d'AI tick.
- **Persistance respawn** : `_restore_from_snapshot(was_dead: bool)` API publique
  prête pour Checkpoint System futur (Rule 13). MVP : appelable manuellement par tests.
- **Pillar 3** : pas de `queue_free()` au MVP (Rule 12) — grunt mort persiste invisible
  pour permettre Checkpoint snapshot.
