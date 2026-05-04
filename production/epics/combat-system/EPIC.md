# Epic: Player Combat System

> **Layer**: Feature
> **GDD**: design/gdd/player-combat-system.md
> **Architecture Module**: PlayerCombat (architecture.md §Feature Layer)
> **Status**: Ready
> **Stories**: 22 created (2026-04-27) — 17 Ready + 5 Blocked (Gap 1 MockEnemy / Gap 2 ShapeCast empirical / Gap 5 playtest protocol / Audio System GDD / VFX System GDD) — ADR-0015 Accepted 2026-05-02 a débloqué story-022

## Overview

Le Player Combat System traduit l'action `attack` en un geste létal unique : un
sweep de katana qui tue instantanément tout ennemi standard dont la hitbox est
touchée. Architecturalement, il s'agit d'un node enfant direct du Player
CharacterBody3D (DFS preorder garantit Player → Combat dans la même frame
physics, invariant Rule 17 mutual kill), tournant exclusivement en
`_physics_process` @ 60 Hz (ADR-0001 autorité). Quatre responsabilités :
(1) recevoir le signal `attacked` émis par Movement (ADR-0005 D-2 outbound) et
gérer cooldown + buffer 80 ms ; (2) effectuer un sweep ShapeCast3D anti-tunneling
avec `N_SUBSTEPS=3` entre `_prev_position` et la position actuelle (ADR-0006
D-1) ; (3) consommer `CameraSystem.aim_forward` roll-corrigé (ADR-0002, jamais
la rotation caméra brute) ; (4) émettre `enemy_killed` / `multi_kill` pour que
VFX/Audio/Credit Economy/HUD réagissent sans couplage. Mutual kill Hybrid M1
Option C : Player.died SYNC déclenche `_death_pending=true` traité au END du
tick (ADR-0006 D-2). Slow-mo mécanique 50 ms wall-clock @ Engine.time_scale=0.3
sur 1er kill du swing, restoré dans `_physics_process` (ADR-0001 authority,
PAS `_process`). Collision via taxonomie 5-layer ratifiée ADR-0008 (Katana
ShapeCast layer=1 mask=2 ; Enemy lethal hitbox layer=3 mask=1).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0001: Physics Rate 60 Hz | Tick fixe 60 Hz, `_physics_process` autorité simulation, slow-mo via Engine.time_scale dans `_physics_process` | LOW |
| ADR-0002: Camera Scene Tree CameraArm | `aim_forward` roll-corrigé close-form trigo, jamais lecture `camera.basis.z` directe | LOW |
| ADR-0005: Movement Signals Architecture | Movement émet `attacked` signal outbound-only ; Combat reçoit (jamais polling Input) ; `Player.died` SYNC exemption Rule 17 | LOW |
| ADR-0006: Combat Tick Model | DFS Player→Combat, ShapeCast3D anti-tunneling N=3 substeps, mutual kill Hybrid M1 Option C, slow-mo wall-clock injecté Callable | MEDIUM (Jolt CCD margin behavior empirique) |
| ADR-0008: Collision Layer Taxonomy | 5 layers (1=Player, 2=Enemy, 3=EnemyHitbox, 4=Environment, 5=Interactive) ; API 1-indexée `set_collision_layer_value(N)` ; helper `CollisionLayers.build_mask()` | LOW |
| ADR-0015: Accessibility Interface Layer | Autoload `AccessibilityService` source-of-truth `reduce_motion` / `disable_slow_mo` / `slow_mo_scale_mult` / `flash_mult` ; pull-pattern + `settings_changed` signal ; persistance déléguée ADR-0014 | LOW |

**Highest engine risk**: MEDIUM (ADR-0006 — ShapeCast3D.margin behavior Jolt
vs GodotPhysics3D à benchmarker EC-8 lors de la story sweep).

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-cmb-001 | CombatSystem direct child Player CharacterBody3D (DFS preorder Player → Combat) | ADR-0006 ✅ |
| TR-cmb-002 | `physics_process_priority == 0` invariant structurel (assert _ready) | ADR-0006 ✅ |
| TR-cmb-003 | `_prev_position: Vector3` owned exclusivement par Combat ; mis à jour fin de tick | ADR-0006 ✅ |
| TR-cmb-004 | ShapeCast3D sweep anti-tunneling N_SUBSTEPS=3 + Jolt CCD complément | ADR-0001, ADR-0006 ✅ |
| TR-cmb-005 | `_build_capsule_basis(forward)` cross product direct + guards colinéarité | ADR-0006 ✅ |
| TR-cmb-006 | Géométrie hitbox KATANA_REACH=1.8m KATANA_RADIUS=0.45m + invariants safe ranges | ❌ N/A intentional (tuning Combat-local GDD-owned Rule 4/11) |
| TR-cmb-007 | Sweep orientation read-only `CameraSystem.aim_forward` ; forbidden `camera.basis.z` | ADR-0002, ADR-0006 ✅ |
| TR-cmb-008 | Trigger via signal `Player.attacked()` Movement-emitted (pas polling Input direct) | ADR-0004, ADR-0005, ADR-0006 ✅ |
| TR-cmb-009 | Attack buffer single-slot ATTACK_BUFFER_MS=80ms ; clear sur died/respawned | ADR-0005, ADR-0006 ✅ |
| TR-cmb-010 | Timing constants SWING=120ms COOLDOWN=400ms SLOW_MO_DUR=50ms SLOW_MO_SCALE=0.3 + invariants #4/#6/#7 | ADR-0001, ADR-0006 ✅ |
| TR-cmb-011 | Multi-hit dedup `_hit_this_swing: Array[int]` instance_ids tri distance MAX=3 + signals | ADR-0006 ✅ |
| TR-cmb-012 | Collision layer taxonomy 5-layer freeze inline Rule 12 ratifié | ADR-0008 ✅ |
| TR-cmb-013 | Slow-mo wall-clock `_get_time_msec` Callable injecté ; restore dans `_physics_process` | ADR-0001, ADR-0006 ✅ |
| TR-cmb-014 | Mutual kill Hybrid M1 Option C : `_death_pending` flag END tick | ADR-0005, ADR-0006 ✅ |
| TR-cmb-015 | Idempotence hit tracking instance_ids + filter is_instance_valid + clear sur exit Swinging | ADR-0006 ✅ |
| TR-cmb-016 | Accessibility `reduce_motion` impact Combat (slow-mo mult ≥1.0, disable toggle, flash mult) | ADR-0015 ✅ Accepted 2026-05-02 |
| TR-cmb-017 | Injection `_get_time_msec: Callable = Time.get_ticks_msec` substitutable test | ADR-0006 ✅ |

**Coverage**: 16 / 17 covered, 1 N/A intentional (TR-cmb-006 GDD-owned tuning), 0 gaps.

## Untraced Requirements (warnings)

✅ **TR-cmb-016** : RÉSOLU 2026-05-02. ADR-0015 Accessibility Interface Layer
Accepted (autoload `AccessibilityService` + `accessibility_settings.tres`
délégué ADR-0014). Story-022 Status `Blocked → Ready (Polish P3)`.

✅ **TR-cmb-006** : intentional N/A — tuning GDD-owned (Rule 4/11). Implémenté
comme constants @export ou const dans le script Combat sans ADR ; safe ranges
documentés directement GDD §Tuning Knobs.

## Definition of Done

L'epic est complet quand :
- Toutes les stories sont implémentées, reviewed, closed via `/story-done`
- Tous les ACs de `design/gdd/player-combat-system.md` sont vérifiés
- Toutes les Logic et Integration stories ont tests passants dans `tests/unit/combat/` et `tests/integration/combat/`
- Toutes les Visual/Feel et UI stories ont evidence docs avec sign-off dans `production/qa/evidence/`
- Bench ShapeCast3D.margin Jolt vs GodotPhysics3D documenté (EC-8 ADR-0006)
- Lint CI `lint-collision-layers` passe (ADR-0008 D-6)

## Stories

| # | Story | Type | Status | ADR / Blocker |
|---|-------|------|--------|---------------|
| 001 | Scene skeleton & structural invariants | Logic | Ready | ADR-0006 D-1/D-2 |
| 002 | State machine + cooldown + active_tick lifecycle | Logic | Ready | ADR-0001 + ADR-0006 |
| 003 | Death/respawn lifecycle full reset | Logic | ✅ Complete 2026-05-02 | ADR-0005 + ADR-0006 (test 6/6 PASS, doc sync) |
| 004 | `attacked()` handler + buffer single-slot 80ms | Logic | ✅ Complete 2026-05-02 | ADR-0004 + ADR-0005 + ADR-0006 (test 9/9 PASS, doc sync) |
| 005 | `_build_capsule_basis()` helper + 100-sample sphere test | Logic | ✅ Complete 2026-05-02 | ADR-0006 D-7 (test 6/6 PASS, fix is_equal_approx vector tolerance `report_264`) |
| 006 | ShapeCast3D node config + collision layers | Logic | ✅ Complete 2026-05-02 | ADR-0008 (test 4/4 PASS, doc sync) |
| 007 | Sweep position + aim_forward consumption + invalid/NaN guards | Logic | ✅ Complete 2026-05-02 | ADR-0002 + ADR-0006 (test 8/8 PASS, fix is_equal_approx vector tolerance `report_264`) |
| 008 | `_prev_position` per-tick update + reach constant | Logic | ✅ Complete 2026-05-02 | ADR-0006 D-3 (test 7/7 PASS, fix is_equal_approx vector tolerance `report_264`) |
| 009 | Anti-tunneling N=3 substeps + Jolt margin empirical | Logic | ✅ Complete 2026-05-02 | ADR-0001 + ADR-0006 (test 8/8 PASS, fix is_equal_approx vector tolerance `report_264`) |
| 010 | Tick-0 overlap mitigation + Gap 2 prelim test | Logic | ✅ Complete 2026-05-04 (Variante B empirique — Godot 4.6+Jolt détecte natively, 0 prod code) | Gap 2 résolu — empirical test `tests/empirical/shapecast_overlap_origin_test.gd` + régression test 2/2 PASS |
| 011 | Single-hit kill + dedup `_hit_this_swing` | Logic | ✅ Complete 2026-05-02 | ADR-0006 D-3 + Gap 1 résolu (MockEnemy créé) |
| 012 | Multi-hit + tri distance + MAX_KILLS + multi_kill signal | Logic | ✅ Complete 2026-05-02 | ADR-0006 + Formula 6 (distance squared zéro-sqrt) |
| 013 | Slow-mo wall-clock + Callable injection + restore + edge cases | Logic | ✅ Complete 2026-05-02 | ADR-0001 + ADR-0006 D-5 (impl déjà livrée stories 011/012/022, doc sync 2026-05-02) |
| 014 | Mutual kill Hybrid M1 Option C `_death_pending` | Integration | ✅ Complete 2026-05-02 | ADR-0005 D-5 amendment r2 + ADR-0006 D-2 (impl déjà livrée, test 4/4 PASS, doc sync 2026-05-02) |
| 015 | Mid-swing transitions + race Idle mitigation + pause spam | Integration | ✅ Complete 2026-05-02 | ADR-0006 + ADR-0004 (test 3/3 PASS, doc sync 2026-05-02) |
| 016 | Invariants runtime `_validate_invariants()` + smoke check | Logic | ✅ Complete 2026-05-02 | ADR-0006 (DEC-r5-2 Option A) (test 5/5 PASS, doc sync 2026-05-02) |
| 017 | ShapeCast microbench p99 ≤5ms | Integration | Complete 2026-05-04 (GdUnit4 conversion ; baseline Apple M4 p99=0.005 ms — Tier 1 official sign-off DEFERRED CI) | ADR-0006 + ADR-0001 |
| 018 | Integration soak frametime + memory + OBJECT_COUNT | Integration | Complete 2026-05-04 (4/4 GdUnit4 PASS — AC-CMB-37 a-e + AC-CMB-35b 1+2 baseline Apple M4 ; Tier 1 sign-off + draw_calls full-stack DEFERRED CI infra ; (f) zero warnings DEFERRED instrumentation) | ADR-0001 + ADR-0003 + ADR-0006 |
| 019 | Combat feel playtest protocol + Visual/Feel ACs | Visual/Feel | Ready 2026-05-04 (panel Martin pending) | Gap 5 résolu — `production/qa/protocols/combat-feel-interview.md` publié (15 questions × 5 axes) |
| 020 | Swoosh fade-out wall-clock + multi-kill clac + ducking | Integration | **Blocked** | Audio System GDD non écrit (#11 backlog) |
| 021 | VFX decal cap pool LRU contract | Integration | **Blocked** | VFX System GDD + GPU Tier 1 runner |
| 022 | Accessibility `reduce_motion` Combat impact | Logic | Ready (Polish P3) | ADR-0015 ✅ Accepted 2026-05-02 |

**Totaux** : 22 stories — 19 Complete (001/002/003/004/005/006/007/008/009/010/011/012/013/014/015/016/017/018/022) + 1 Ready (019 Gap 5 panel Martin pending) + 2 Blocked (020 Audio GDD ; 021 VFX GDD). 2026-05-04 P2 unblock : Gap 2 résolu Variante B empirique (story-010 Complete sans code production, mitigation `_tick0_intersect_shape_overlap` redondante) + Gap 5 résolu protocol playtest publié (story-019 Ready, recrutement panel Martin reste). 2026-05-04 P3 close-out : story-017 microbench + story-018 soak intégration baseline Apple M4 (Tier 1 sign-off DEFERRED CI infra).
Doc sync 2026-05-02 : 11 stories ont vu leur Status recadré ; root-cause des 6 failures pré-existants 005/007/008/009 = signature GdUnit4 `assert_vector(...).is_equal_approx(expected: Vector, approx: Vector)` veut un Vector3 comme tolérance, pas un float (`_validate_is_vector_type` rejette float silencieusement). Fix systémique = remplacer `, 0.001)` → `, Vector3.ONE * 0.001)` (4 fichiers test combat + 4 occurrences `test_movement_signals_typed_contract.gd`).
**Coverage TR-cmb** : 16/17 TRs Covered via stories ; TR-cmb-006 N/A intentional GDD-owned ; TR-cmb-016 covered ADR-0015 Accepted 2026-05-02 (story-022 Ready Polish P3).

**Notes prereqs** :
- Story 005 + 010 sont conditionnés par travail empirique pré-Sprint 1 du lead-programmer (Gap 2 + Gap 7 + Gap 8 docs `engine-reference/godot/modules/physics.md`).
- Story 006 dépend du Sprint 0 Technical Setup (`src/core/collision_layers.gd` + `project.godot [layer_names]` + lint CI `lint-collision-layers`, ADR-0008 Migration Plan).
- ~~Stories 011-012 attendent `tests/unit/combat/mock_enemy.gd` (Gap 1, qa-tester).~~ **Gap 1 RÉSOLU 2026-05-02** : MockEnemy créé (`tests/unit/combat/mock_enemy.gd`, StaticBody3D minimal, contract parité Grunt). Story-011 Complete, story-012 Ready.
- Stories 019-022 sont des Blocked tracking — débloqués par travaux d'autres systèmes (Audio, VFX, ADR Accessibility).

## Next Step

Run `/story-readiness production/epics/combat-system/story-001-scene-skeleton-structural-invariants.md` puis `/dev-story` pour démarrer l'implémentation. Ordering par dépendances :
001 → 002 → 003 / 004 → 005 / 006 → 007 → 008 → 009 → 010* → 011* → 012* → 013 → 014 / 015 → 016 → 017 → 018 → (019* / 020* / 021* / 022*) (* = Blocked).
