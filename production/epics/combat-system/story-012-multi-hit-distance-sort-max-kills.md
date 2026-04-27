# Story 012: Multi-hit + tri distance + MAX_KILLS + multi_kill signal

> **Epic**: Player Combat System
> **Status**: Blocked
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> **BLOCKED**: Gap 1 — MockEnemy non créé (cf. story-011). Plus dépend de plusieurs MockEnemies positionnables pour AC-CMB-07.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-011` (multi-hit resolution complete : dedup + tri + MAX_KILLS + signals)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model)
**ADR Decision Summary**: Multi-hit cap `MAX_KILLS_PER_SWING = 3` ; tri ascending par distance pour résoudre les premiers ennemis ; signal `multi_kill(count)` émis si ≥2 kills sur le même swing après les `enemy_killed` individuels.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Array.sort_custom()` stable Godot 4.0+. Tri secondaire `instance_id` non-MVP (Gap 3, Tier 3 leaderboards).

**Control Manifest Rules (Feature layer)**:
- Required: `multi_kill(count)` émis APRÈS tous les `enemy_killed` individuels du tick
- Forbidden: tri non-déterministe (ordre Jolt par défaut peut différer run-to-run — Gap 3) — pour MVP, tri par distance suffit, secondaire `instance_id` post-MVP
- Guardrail: `MAX_KILLS_PER_SWING = 3` cap — au-delà, ennemis ignorés (pas de crash, pas de dégâts cumulés)

---

## Acceptance Criteria

*From GDD AC-CMB-07/25 + Rule 9 + Formula 6 :*

- [ ] **AC-CMB-07** : 4 MockEnemies aux distances `[0.3, 0.8, 1.2, 1.7]` m tous intersectés au même tick → `die()` appelé sur 3 premiers (0.3, 0.8, 1.2) **dans cet ordre exact**, PAS sur le 4e (1.7 m, au-delà cap), `multi_kill(3)` émis immédiatement après les 3 `enemy_killed`
- [ ] **AC-CMB-25** : 2 MockEnemies tués au même tick → 1er kill déclenche `_slow_mo_active = true` + Engine.time_scale=0.3 (story-013), 2e kill ne re-déclenche PAS slow-mo (idempotence Rule 13), `multi_kill(2)` émis après les 2 `enemy_killed`
- [ ] `MAX_KILLS_PER_SWING = 3` constant (Section G safe range [1, 10])
- [ ] Tri ascending par distance avant boucle dies : `hits.sort_custom(func(a, b): return _dist_to_player(a) < _dist_to_player(b))`
- [ ] Signal `multi_kill(count: int)` déclaré ; émis si `count >= 2` à la fin du tick, après tous les `enemy_killed` individuels

---

## Implementation Notes

*Derived from ADR-0006 + GDD Formula 6 + Rule 9 :*

```gdscript
signal multi_kill(count: int)

const MAX_KILLS_PER_SWING: int = 3

func _resolve_swing_hits() -> void:
    var hit_ids := _collect_swing_hits()  # story-009 + 010
    # Filter & sort
    var candidates: Array[Object] = []
    for id in hit_ids:
        if id in _hit_this_swing:
            continue
        var c := instance_from_id(id)
        if not is_instance_valid(c) or not c.has_method("die"):
            if OS.is_debug_build() and is_instance_valid(c):
                push_warning("Combat: collider sans die() skipped")
            continue
        if c.has_method("is_dead") and c.is_dead():
            continue
        candidates.append(c)
    # Tri par distance ascending (Formula 6)
    candidates.sort_custom(func(a, b):
        return player.global_position.distance_squared_to(a.global_position) < \
               player.global_position.distance_squared_to(b.global_position)
    )
    # Resolve up to MAX_KILLS_PER_SWING
    var kills_this_tick: int = 0
    for c in candidates:
        if _hit_this_swing.size() >= MAX_KILLS_PER_SWING:
            break
        _hit_this_swing.append(c.get_instance_id())
        c.die()
        enemy_killed.emit(c, c.global_position)
        kills_this_tick += 1
        # Slow-mo trigger: story-013
    if kills_this_tick >= 2:
        multi_kill.emit(kills_this_tick)
```

- Utiliser `distance_squared_to` (zéro sqrt — Pillar 1 hot path)

---

## Out of Scope

- Story 013 : déclenchement slow-mo sur 1er kill (idempotence intra-tick) — cette story signale juste `multi_kill`, le slow-mo handler dispatch depuis `enemy_killed`
- Story 014 : `_death_pending` mid-swing — résolution colliders du tick courant précède transition Dead (Rule 17 Hybrid)
- Gap 3 (tri secondaire `instance_id` pour speedrun déterminisme) — post-MVP

---

## QA Test Cases

- **AC-1** 4 enemies, max 3 kills sorted by distance
  - Given: 4 MockEnemies aux distances `[0.3, 0.8, 1.2, 1.7]` m intersectés même tick
  - When: `_physics_process` swing tick exécuté
  - Then: 3 `die()` appels dans l'ordre `[0.3, 0.8, 1.2]`, MockEnemy 1.7 m PAS tué, `multi_kill(3)` émis APRÈS les 3 `enemy_killed`
  - Edge cases: 5+ ennemis — toujours top-3 distance ; 2 ennemis à distance égale — ordre déterminé par Jolt (Gap 3 non-MVP)

- **AC-2** Multi-kill 2 enemies, slow-mo idempotence
  - Given: 2 MockEnemies tués même tick, `_slow_mo_active == false` au début
  - When: tick exécuté
  - Then: après 1er `enemy_killed` : `_slow_mo_active == true`, `Engine.time_scale == 0.3` ; après 2e `enemy_killed` : `_slow_mo_active` toujours `true`, `Engine.time_scale` PAS ré-assigné ; `multi_kill(2)` émis après les 2 `enemy_killed`
  - Edge cases: 1 kill seul — pas de `multi_kill` émis

- **AC-3** Cap exact 3
  - Given: 3 MockEnemies tous intersectés
  - When: tick exécuté
  - Then: 3 `die()`, `multi_kill(3)` émis (≥2)
  - Edge cases: muter `MAX_KILLS_PER_SWING = 1` → 1 kill, pas de `multi_kill`

- **AC-4** Sort by distance squared
  - Given: ennemis aux distances `[1.5, 0.5, 1.0]` m intersectés
  - When: tri appliqué
  - Then: ordre kill `[0.5, 1.0, 1.5]`
  - Edge cases: 2 ennemis à 1.0 m exact — ordre quelconque (déterminisme Gap 3 post-MVP)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/multi_hit_distance_sort_test.gd` — must exist and pass (BLOCKED Gap 1)

**Status**: [ ] Not yet created (BLOCKED)

---

## Dependencies

- Depends on: Story 011 (single hit + dedup), **Gap 1 MockEnemy résolu**
- Unlocks: Story 013 (slow-mo trigger sur 1er kill du multi-hit), Story 020 (audio multi-kill BLOCKED)
