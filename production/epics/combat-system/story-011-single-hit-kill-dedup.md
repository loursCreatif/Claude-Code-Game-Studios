# Story 011: Single-hit kill + dedup `_hit_this_swing`

> **Epic**: Player Combat System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, solo)

> **GAP 1 RÉSOLU 2026-05-02** : `tests/unit/combat/mock_enemy.gd` créé (StaticBody3D minimal avec `die()` idempotent + `is_dead() -> bool` + CollisionShape3D layer=2). Pas de `class_name` (cache headless friendly — preload direct). Contract parité avec Grunt réel (`src/gameplay/enemy/grunt.gd`) livré Enemy story-001/002 — pourrait aussi servir comme fixture mais MockEnemy reste plus léger pour unit tests isolés.

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

- [x] **AC-CMB-05** : Combat `Swinging` + MockEnemy à 0.9 m (< KATANA_REACH=1.8) → `MockEnemy.die()` appelé exactement 1 fois, signal `enemy_killed(enemy, position)` émis avec `position == MockEnemy.global_position`, ennemi ajouté à `_hit_this_swing`
- [x] **AC-CMB-06** : MockEnemy déjà dans `_hit_this_swing` (même swing tick suivant) → `MockEnemy.die()` PAS appelé une 2e fois (guard `collider.get_instance_id() in _hit_this_swing`)
- [x] **AC-CMB-45** : collider layer=2 sans méthode `die()` (mock erroné) → aucun crash, skip silencieux, `push_warning` debug build, `enemy_killed` non émis, `_hit_this_swing` non muté
- [x] `_hit_this_swing` cleared en début de Swinging (entrée state) ET en sortie (transition Idle) — story-002 augmenté
- [x] Filtrage : `is_instance_valid(c) and c.has_method('die') and not c.is_dead() and not c.get_instance_id() in _hit_this_swing`
- [x] **MockEnemy contract** : `tests/unit/combat/mock_enemy.gd` créé 2026-05-02 — `die()` idempotent, `is_dead() -> bool` retourne true post-die, CollisionShape3D layer=2.

**Bonus ACs covered** :
- **MAX_KILLS_PER_SWING cap** : `_resolve_kills` break early dès `_hit_this_swing.size() >= 6` (anticipe story-012 plein scope, mais cap appliqué dès story-011).
- **Slow-mo trigger cross-link story-013** : `_trigger_slow_mo_if_first_kill` appelé après chaque die() (idempotent via `_slow_mo_active` flag).
- **Stale instance_id robustness** : `instance_from_id(stale)` retourne null/invalide → `is_instance_valid` filter skip silencieux, no-crash.

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
**Required evidence**: `tests/unit/combat/single_hit_kill_dedup_test.gd` — must exist and pass.

**Status**: ✅ Created 2026-05-02 — 8/8 PASS (`reports/report_252` puis `reports/report_255` post stash-restore).

**Test plan** :
| AC | Test function | Status |
|----|---------------|--------|
| AC-CMB-05 / AC-1 | `test_combat_single_hit_calls_die_once_and_appends_instance_id` | ✅ PASS |
| AC-CMB-06 / AC-2 | `test_combat_dedup_intra_swing_skips_already_hit_enemy` | ✅ PASS |
| AC-CMB-45 / AC-3 | `test_combat_collider_without_die_method_skipped_no_crash` | ✅ PASS |
| AC-4 | `test_combat_start_swing_clears_hit_this_swing` | ✅ PASS |
| AC-5 | `test_combat_already_dead_enemy_skipped` | ✅ PASS |
| Robustness | `test_combat_invalid_instance_id_skipped_no_crash` | ✅ PASS |
| Bonus MAX cap | `test_combat_max_kills_per_swing_cap_breaks_loop` | ✅ PASS |
| Bonus slow-mo | `test_combat_first_kill_triggers_slow_mo` | ✅ PASS |

**Régression vérifiée** : Combat + Enemy suite full run avant/après story-011 via `git stash` — **20 errors/failures pré-existants identiques** (anti_tunneling_substeps + state_machine_lifecycle + sweep_position_aim_guards + scene_skeleton_invariants + duplicates " 2" multi-session). Aucune régression introduite.

---

## Completion Notes

- **Implementation pattern** : `_resolve_kills(hit_ids: Array[int]) -> void` privée, appelée depuis `_physics_process` SWINGING branch. Remplace l'accumulation simple story-009 (`for instance_id: ...`) qui n'invoquait pas `die()`. Pas de signal `enemy_killed` Combat-side : OQ-ENM-1 amendment 2026-04-27 a transféré l'autorité d'émission à Enemy (Grunt emit SYNC quand `die()` est appelé). Combat → `_trigger_slow_mo_if_first_kill()` directement post-die, redondance évitée.
- **MockEnemy fixture light** : volontairement plus léger que Grunt complet (pas de LaserCone, pas de Tween scale, pas de signal `enemy_killed` interne). Suffit pour unit tests `_resolve_kills` isolés. Grunt reste testé en suite Enemy (50/50 PASS) + intégration cross-system future story-018 soak.
- **`class_name` omis** sur MockEnemy : le cache `.godot/global_script_class_cache.cfg` n'est rebuildé qu'à l'ouverture éditeur, ce qui casse le CI headless. Pattern `preload("res://tests/unit/combat/mock_enemy.gd").new()` utilisé à la place.
- **Stories débloquées** : story-012 (Multi-hit + tri distance + MAX_KILLS — cap déjà appliqué story-011, reste tri par distance et signal `multi_kill`), Enemy story-004 (Combat sweep + Player laser cross-system tests cf AC-ENM-13/14/15 — Combat appelle maintenant `enemy.die()` correctement, integration testable).

---

## Dependencies

- Depends on: Story 002 (state machine), Story 009 (`_collect_swing_hits()`), Story 010 (tick-0 mitigation if Variante A), **Gap 1 MockEnemy résolu** (qa-tester)
- Unlocks: Story 012 (multi-hit), Story 013 (slow-mo on kill), Story 014 (mutual kill)
