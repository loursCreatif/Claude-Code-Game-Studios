# Story 014: Mutual kill Hybrid M1 Option C `_death_pending`

> **Epic**: Player Combat System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-014` (mutual kill Hybrid M1 Option C — `_death_pending` flag END tick)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) D-2 + ADR-0005 (Movement Signals) D-5 amendment r2
**ADR Decision Summary**: `Player.died` signal SYNC (exemption ADR-0005 D-5 amendment r2). Handler `_on_player_died()` set `_death_pending = true` UNIQUEMENT — pas de mutation d'état. Au END de `_physics_process` Combat (après résolution colliders) : check `_death_pending` → transition Dead, clear ShapeCast3D.enabled, restore time_scale=1.0 si _slow_mo_active. Garantit symétrie : Player.die + Enemy.die sur même tick.

**Engine**: Godot 4.6 | **Risk**: LOW (mais Integration test difficile — ordre intra-tick non-observable GUT direct)
**Engine Notes**: DFS preorder Player → Combat garantit que Movement `_physics_process` exécute avant Combat. `signal.connect()` mode SYNC = flag 0 défaut.

**Control Manifest Rules (Feature layer)**:
- Required: `player.died.connect(_on_player_died)` mode SYNC (flags=0) — ADR-0005 D-5 amendment r2
- Forbidden: `player.died.connect(_on_player_died, CONNECT_DEFERRED)` (lint CI grep AC-CMB-41 clause 8)
- Guardrail: `_on_player_died` set `_death_pending = true` UNIQUEMENT, JAMAIS mutation `_state` directement

---

## Acceptance Criteria

*From GDD AC-CMB-20/41 + Rule 17 Hybrid + Edge Cases :*

- [ ] **AC-CMB-41** : scene intégrée Player + Combat + MockEnemy1 (0.8 m) + MockEnemyLaser intersectant Player même tick → 7 assertions post-tick :
  - (1) `_state == Dead`
  - (2) `_death_pending == false`
  - (3) `MockEnemy1.die()` appelé exactement 1 fois
  - (4) `enemy_killed(MockEnemy1, ...)` émis exactement 1 fois
  - (5) `swing_ended` **non** émis
  - (6) `ShapeCast3D.enabled == false`
  - (7) `Player.state == Dead`
- [ ] **AC-CMB-41 clause 8 (grep)** : `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd` retourne zéro match
- [ ] **AC-CMB-20** : Combat `Swinging` à `_active_tick = 3`, **aucun collider** dans le sweep, `Player.died()` reçu → après `_physics_process` complet : `_state == DEAD`, `swing_ended` non émis, `ShapeCast3D.enabled == false`, aucun `enemy_killed`, `Engine.time_scale == 1.0 ± 0.0001`, `_death_pending == false` (consommé)
- [ ] Handler `_on_player_died()` set UNIQUEMENT `_death_pending = true` — aucune mutation d'autres champs (ni `_state`, ni `ShapeCast3D.enabled`, ni `Engine.time_scale`)
- [ ] Au END de `_physics_process` (après résolution colliders et update `_prev_position`) : check `_death_pending` → transition Dead complète

---

## Implementation Notes

*Derived from ADR-0006 D-2 + ADR-0005 D-5 amendment r2 + GDD Rule 17 Hybrid M1 Option C :*

```gdscript
var _death_pending: bool = false

func _ready() -> void:
    # ... autres assertions
    player.died.connect(_on_player_died)  # SYNC flag 0
    var conn := player.died.get_connections()
    for c in conn:
        if c.callable.get_method() == "_on_player_died":
            assert(c.flags == 0, "player.died must be SYNC connection — ADR-0005 D-5 amendment r2")

func _on_player_died() -> void:
    # Rule 17 Hybrid M1 Option C : ne mute QUE _death_pending
    _death_pending = true

func _physics_process(delta: float) -> void:
    # ... cooldown, state machine, sweep resolve (story-002 + 011 + 012)
    # END OF TICK : drain _death_pending
    if _death_pending:
        _death_pending = false
        if _slow_mo_active:
            Engine.time_scale = 1.0
            _slow_mo_active = false
            _slow_mo_start_msec = 0
        _state = State.DEAD
        $ShapeCast3D.enabled = false
        # _hit_this_swing reset au respawn (story-003)
    # FIN ABSOLUE :
    _prev_position = player.global_position  # story-008
```

- AC-CMB-41 vérification ordre intra-tick = via 7 assertions post-tick + clause 8 grep statique (l'ordre est garanti par DFS preorder + handler SYNC, observabilité indirecte acceptée)

---

## Out of Scope

- Story 003 : `_on_player_died` original handler (immediate restore quand pas Swinging) — cette story 014 augmente le handler pour set `_death_pending` quand Swinging
- Story 015 : transitions Movement state mid-swing (séparé du mutual kill)

---

## QA Test Cases

- **AC-1** Mutual kill complete tick
  - Given: scene Player + Combat + MockEnemy1 (0.8 m) + MockEnemyLaser configuré pour killing-tick
  - When: `_physics_process` tick exécuté (DFS Player → Combat)
  - Then: 7 assertions vérifiées : (1) `_state == DEAD`, (2) `_death_pending == false`, (3) MockEnemy1.die() 1×, (4) enemy_killed 1×, (5) swing_ended non émis, (6) ShapeCast.enabled==false, (7) Player.state==Dead
  - Edge cases: 2 enemies + laser (mutual triple kill) — 2× enemy_killed + multi_kill(2) émis avant transition Dead

- **AC-2** SYNC connection grep (clause 8)
  - Given: source `combat_system.gd`
  - When: `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd`
  - Then: zéro match
  - Edge cases: connect alternative API `player.died.connect(method, 0)` autorisé (flag explicite 0 = SYNC)

- **AC-3** Death without collider (AC-CMB-20)
  - Given: Combat `Swinging` à `_active_tick = 3`, ShapeCast vide (pas de collider)
  - When: `Player.died.emit()` reçu pendant ce tick + `_physics_process` continue
  - Then: post-tick : `_state == DEAD`, `_death_pending == false`, `ShapeCast.enabled == false`, aucun `enemy_killed` ni `swing_ended`, `Engine.time_scale == 1.0`
  - Edge cases: `_active_tick = 0` (juste début swing) — même comportement

- **AC-4** Handler purity
  - Given: `_state == SWINGING`, `_active_tick = 3`, `ShapeCast.enabled == true`
  - When: `_on_player_died()` exécuté SYNC (handler appelé directement)
  - Then: immédiatement après handler : `_state == SWINGING` (inchangé), `ShapeCast.enabled == true` (inchangé), `Engine.time_scale` (inchangé), `_death_pending == true`
  - Edge cases: `_on_player_died` appelé 2× même tick (synthétique) — `_death_pending` reste true (idempotent)

- **AC-5** End-of-tick drain order
  - Given: `_state == SWINGING`, `_slow_mo_active == true`, `Engine.time_scale = 0.3`, `_death_pending == true` (set durant tick)
  - When: fin de `_physics_process` Combat
  - Then: `Engine.time_scale == 1.0` (restore d'abord), puis `_state == DEAD`, `_death_pending == false`, `ShapeCast.enabled == false`
  - Edge cases: `_death_pending == true` AVEC kill résolu même tick → kill résolu mid-tick, transition Dead end-tick (AC-CMB-41 covers)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/combat/mutual_kill_death_pending_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 003 (basic died handler), Story 011 (kill resolution mid-tick), Story 013 (slow-mo restore)
- Unlocks: Story 015 (mid-swing transitions edge cases)
