# Story 011: Single-hit kill + dedup `_hit_this_swing`

> **Epic**: Player Combat System
> **Status**: Blocked
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> **BLOCKED**: Gap 1 — `tests/unit/combat/mock_enemy.gd` non créé. ACs CMB-05/06 requirent `MockEnemy` GDScript avec `die()` idempotent + `is_dead() -> bool` + `CollisionShape3D` layer=2. Owner : `qa-tester`. Échéance : avant story-011 dev-story.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-011` partie single-hit + `TR-cmb-015` (idempotence hit tracking)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model)
**ADR Decision Summary**: `_hit_this_swing: Array[int]` stocke `get_instance_id()` (pas Node refs — survit `queue_free`). Filter `is_instance_valid(collider) + collider.has_method('die') + !collider.is_dead() + !id in _hit_this_swing`. Cleared sur entrée Swinging et fin Swinging (transition Idle).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Object.get_instance_id()` stable Godot 4.0+. `is_instance_valid(obj)` stable.

**Control Manifest Rules (Feature layer)**:
- Required: stocker `instance_id: int` (pas Node refs) dans `_hit_this_swing`
- Forbidden: lecture `_hit_this_swing` depuis thread non-main (ADR-0006 D-3 rule + zero-alloc hot path)
- Guardrail: filtrage `is_instance_valid` + `has_method('die')` AVANT appel `die()` (no-crash si collider mauvais type)

---

## Acceptance Criteria

*From GDD AC-CMB-05/06/45 + Rule 6/9/10 :*

- [ ] **AC-CMB-05** : Combat `Swinging` + MockEnemy à 0.9 m (< KATANA_REACH=1.8) → `MockEnemy.die()` appelé exactement 1 fois, signal `enemy_killed(enemy, position)` émis avec `position == MockEnemy.global_position`, ennemi ajouté à `_hit_this_swing`
- [ ] **AC-CMB-06** : MockEnemy déjà dans `_hit_this_swing` (même swing tick suivant) → `MockEnemy.die()` PAS appelé une 2e fois (guard `collider.get_instance_id() in _hit_this_swing`)
- [ ] **AC-CMB-45** : collider layer=2 sans méthode `die()` (mock erroné) → aucun crash, skip silencieux, `push_warning` debug build, `enemy_killed` non émis, `_hit_this_swing` non muté
- [ ] `_hit_this_swing` cleared en début de Swinging (entrée state) ET en sortie (transition Idle) — story-002 augmenté
- [ ] Filtrage : `is_instance_valid(c) and c.has_method('die') and not c.is_dead() and not c.get_instance_id() in _hit_this_swing`
- [ ] **MockEnemy contract** (créé par qa-tester pré-Sprint 1) : `die()` idempotent, `is_dead() -> bool` retourne true post-die, CollisionShape3D layer=2

---

## Implementation Notes

*Derived from ADR-0006 D-4 + GDD Rule 6/9/10 :*

```gdscript
# combat_system.gd — extension de _physics_process Swinging branch
signal enemy_killed(enemy: Node3D, position: Vector3)

func _physics_process(delta: float) -> void:
    # ... cooldown, state machine
    if _state == State.SWINGING:
        var hit_ids := _collect_swing_hits()  # story-009 + story-010
        for id in hit_ids:
            if id in _hit_this_swing:
                continue
            var c: Object = instance_from_id(id)
            if not is_instance_valid(c):
                continue
            if not c.has_method("die"):
                if OS.is_debug_build():
                    push_warning("Combat: collider layer=2 sans 'die()' — skipped, id=%d" % id)
                continue
            if c.has_method("is_dead") and c.is_dead():
                continue
            # Hit accepté
            _hit_this_swing.append(id)
            c.die()
            enemy_killed.emit(c, c.global_position)
            # Multi-kill cap + signal multi_kill : story-012
            if _hit_this_swing.size() >= MAX_KILLS_PER_SWING:
                break
    # ... fin tick : _prev_position update (story-008)
```

- Initialiser `_hit_this_swing` cleared dans `_start_swing()` : `_hit_this_swing.clear()`
- Re-cleared à la fin de la window active dans transition vers Idle (story-002 AC-04)

---

## Out of Scope

- Story 012 : tri par distance + MAX_KILLS_PER_SWING + signal `multi_kill(count)`
- Story 014 : `_death_pending` end-of-tick handling (mutual kill ne stoppe pas la résolution mid-tick)

---

## QA Test Cases

- **AC-1** Single hit kill
  - Given: Combat `Swinging`, MockEnemy à 0.9 m, `_hit_this_swing` empty
  - When: `_physics_process` tick avec swing actif
  - Then: `MockEnemy.die()` appelé 1×, `enemy_killed.emit(MockEnemy, MockEnemy.global_position)` reçu, `_hit_this_swing == [MockEnemy.get_instance_id()]`
  - Edge cases: MockEnemy à 1.799 m (juste sous reach) — kill ; à 1.801 m — pas kill

- **AC-2** Dedup intra-swing
  - Given: MockEnemy déjà dans `_hit_this_swing`
  - When: tick suivant de la même window, MockEnemy toujours intersecté
  - Then: `MockEnemy.die()` PAS rappelé, `enemy_killed` PAS réémis, `_hit_this_swing` inchangé
  - Edge cases: MockEnemy.queue_free() entre ticks → `is_instance_valid` filter

- **AC-3** No die() method skip
  - Given: collider layer=2 sans méthode `die()` (e.g. MockGenericNode avec CollisionShape3D layer=2)
  - When: intersecté pendant Swinging
  - Then: pas de crash, `push_warning` reçu (debug), `enemy_killed` non émis, `_hit_this_swing` non muté
  - Edge cases: collider avec `die` qui n'est pas méthode (variable nommée die) — skip

- **AC-4** Cleared on swing start
  - Given: `_hit_this_swing == [101, 102]` (résiduel d'un swing précédent — synthétique)
  - When: `_start_swing()` exécuté
  - Then: `_hit_this_swing.is_empty() == true`
  - Edge cases: cleared aussi à fin window (story-002 AC-04 already covered)

- **AC-5** is_dead() filter
  - Given: MockEnemy avec `is_dead() == true` (déjà mort tick précédent, pas encore freed)
  - When: intersecté pendant Swinging
  - Then: `die()` PAS appelé, `enemy_killed` PAS émis
  - Edge cases: MockEnemy sans `is_dead` méthode — skip is_dead check, kill normal

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/single_hit_kill_dedup_test.gd` — must exist and pass (BLOCKED Gap 1 MockEnemy)

**Status**: [ ] Not yet created (BLOCKED)

---

## Dependencies

- Depends on: Story 002 (state machine), Story 009 (`_collect_swing_hits()`), Story 010 (tick-0 mitigation if Variante A), **Gap 1 MockEnemy résolu** (qa-tester)
- Unlocks: Story 012 (multi-hit), Story 013 (slow-mo on kill), Story 014 (mutual kill)
