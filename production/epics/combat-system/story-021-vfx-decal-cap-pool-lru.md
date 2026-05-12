# Story 021: VFX decal cap pool LRU contract

> **Epic**: Player Combat System
> **Status**: Closed - Migrated to VFX System 2026-05-04
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

> **UNBLOCKED 2026-05-04** : VFX System GDD créé (`design/gdd/vfx-system.md` Designed r1 solo auto-approve) + epic VFX créé (`production/epics/vfx-system/EPIC.md`, 8/8 stories Ready). AC-CMB-42 (decal cap par room) **migré → AC-VFX-01/02/03/30 owned** dans VFX story-003 (`production/epics/vfx-system/story-003-decal-cap-lru-eviction.md`). VFX GDD r1 résout le contract avec `MAX_DECALS_PER_ROOM = 32` (R-VFX-4 + Formula 1 LRU ring buffer) — valeur révisée 12 → 32 par cohérence Chrome Zen "salle marquée" Pillar 2 (8-32 safe range Tuning Knob VFX). Cette story combat-021 reste **Closed/Migrated** — référence cross-cutting historique (Combat émetteur du contract initial, VFX implémente le pool LRU + résout cap final). 4 obligations Combat→VFX couvertes par AC-VFX-30 : (1) CONNECT_DEFERRED signals R-VFX-3 + AC-VFX-23 (VFX story-001) ; (2) zero mutation enemy/player AC-VFX-24 (VFX story-007 lint outbound) ; (3) trail swing_started→swing_ended AC-VFX-13/14 (VFX story-002) ; (4) flash blanc + splash sang `enemy_killed` AC-VFX-06 + AC-VFX-11 (VFX story-002 + story-004).

> **HISTORICAL BLOCKED context** (résolu 2026-05-04) : VFX System non implémenté. AC-CMB-42 reclassé ADVISORY r6 D-r4-1 (sera promue BLOCKING dès VFX System GDD disponible). Ownership : `combat-system` est l'**émetteur du contract** (`MAX_DECALS_PER_ROOM = 12` cap initial), VFX System implémente le pool LRU. Cette story conserve la traçabilité côté Combat. Aussi BLOCKED runner GPU Tier 1 (non headless) pour mesure frame time Forward+ post-Decal.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-42 (decal cap pool LRU + frame time post-decal)

**ADR Governing Implementation**: ADR-0006 (contract Combat→VFX) + ADR-0003 (Forward+ rendering)
**ADR Decision Summary**: Combat fixe le cap `MAX_DECALS_PER_ROOM = 12` (constant Section G safe range [4, 32]). VFX System pool LRU recycle les 3 plus anciens decals quand 15 kills émettent 15 `enemy_killed` signals. Frame time post-Decal mesurable uniquement sur runner GPU Tier 1 (non headless). Option future : scinder en (a) AC-CMB-42a logique pool LRU headless-safe (compte Decal nodes via `Performance.OBJECT_COUNT`) + (b) AC-CMB-42b frame time Forward+ GPU runner Tier 1.

**Engine**: Godot 4.6 + Forward+ | **Risk**: MEDIUM
**Engine Notes**: `Decal` node Godot 4.0+. `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` Performance metric. Frame time GPU non headless requis.

**Control Manifest Rules (Feature layer)**:
- Required: cap `MAX_DECALS_PER_ROOM = 12` exposé comme constant Combat ; VFX System lit/respecte
- Forbidden: VFX System ne doit PAS modifier le cap depuis son côté (Combat owne le contract)
- Guardrail: pool LRU recycle, pas allocation runtime (zero-alloc post-warmup)

---

## Acceptance Criteria

*From GDD AC-CMB-42 + r5 P-R5-06 + r6 D-r4-1 :*

- [ ] **AC-CMB-42 contract** : `CombatSystem.MAX_DECALS_PER_ROOM == 12` (constant Section G), exposé public read-only
- [ ] **AC-CMB-42 (a) — pool LRU logic (headless-safe)** : 15 kills successifs émettent 15 `enemy_killed` → VFX System recycle 3 oldest decals, total Decal nodes actifs = 12 (pas 15), mesurable via `Performance.OBJECT_COUNT` delta
- [ ] **AC-CMB-42 (b) — frame time Forward+ (GPU Tier 1 runner BLOCKED)** : 15 kills + 500 frames suivantes (8.3 sec @ 60 Hz) → frame time p99 ≤ 16.6 ms sur Tier 1 hardware testbed
- [ ] **r6 scope note** : AC-CMB-42 est un contract Combat→VFX. Si cap change Combat (`MAX_DECALS_PER_ROOM`), VFX GDD doit re-vérifier. Cette story conserve la traçabilité ; quand VFX System GDD existe, AC-CMB-42 sera migré ou dupliqué avec ownership clarifié

---

## Implementation Notes

*Derived from GDD AC-CMB-42 + r6 D-r4-1 :*

```gdscript
# Côté Combat (cette story) — contract definition
const MAX_DECALS_PER_ROOM: int = 12  # Section G safe range [4, 32]

# Côté VFX System (story future, BLOCKED) — pool LRU
# class_name VFXDecalPool extends Node
# var _pool: Array[Decal] = []  # pré-alloué MAX_DECALS_PER_ROOM
# var _lru_index: int = 0
# func _on_combat_enemy_killed(enemy, pos) -> void:
#     var decal := _pool[_lru_index]
#     decal.global_position = pos
#     decal.visible = true
#     _lru_index = (_lru_index + 1) % CombatSystem.MAX_DECALS_PER_ROOM
```

- **Cette story Combat-side** : exposer `MAX_DECALS_PER_ROOM` constant + s'assurer que `enemy_killed` signal contient bien `position: Vector3` (déjà couvert story-011)
- **Test Combat-side (headless-safe)** : mock VFXSystem qui compte appels `_on_enemy_killed` ; après 15 kills, mock vérifie qu'il a reçu 15 callbacks (cap est appliqué côté VFX, pas Combat)
- **Test full (BLOCKED GPU Tier 1)** : runner non-headless, mesure draw_calls + frame_time post-Decal Forward+

---

## Out of Scope

- VFX System full implementation (epic séparé futur)
- Decal pool allocation strategy (VFX System side)
- Frame time GPU bench (BLOCKED runner GPU Tier 1)

---

## QA Test Cases

- **AC-1** Cap constant exposed
  - Given: source `combat_system.gd`
  - When: `grep -nE 'MAX_DECALS_PER_ROOM' src/gameplay/combat/`
  - Then: ≥ 1 match `const MAX_DECALS_PER_ROOM: int = 12`
  - Edge cases: muter à 5 (in safe range) — story-016 invariant smoke check passes

- **AC-2** 15 kills emit 15 enemy_killed
  - Given: scene mock VFXSystem qui compte callbacks
  - When: 15 MockEnemies tués séquentiellement (5 swings × 3 kills)
  - Then: VFXSystem reçoit 15 callbacks `_on_combat_enemy_killed`
  - Edge cases: pool LRU côté VFX limite à 12 decals visibles — vérifié post VFX impl

- **AC-3** (BLOCKED GPU runner) Frame time p99 ≤ 16.6 ms post-Decal
  - Given: scene Forward+ runner GPU Tier 1, 15 kills + 500 frames soak
  - When: bench frame_time mesuré
  - Then: p99 ≤ 16.6 ms
  - Edge cases: BLOCKED jusqu'à runner GPU dédié

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/combat/decal_cap_contract_test.gd` (Combat-side mock, headless-safe) + `tests/perf/combat-decal-frametime-log.md` (BLOCKED GPU Tier 1)

**Status**: [ ] Not yet created (BLOCKED VFX System + GPU runner)

---

## Dependencies

- Depends on: Story 011 (enemy_killed émis avec position), VFX System GDD + epic (futur)
- Unlocks: VFX System contract verification (gate-check pre-production)
