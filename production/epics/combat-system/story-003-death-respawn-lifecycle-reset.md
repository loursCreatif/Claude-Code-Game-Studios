# Story 003: Death/respawn lifecycle full reset

> **Epic**: Player Combat System
> **Status**: Done
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Estimate**: 4-6 hours (3 signal handlers + 1 GUT test file 4 cas)
> **Performance Note**: Handlers `_on_player_died` / `_on_player_respawned` = mutations O(1) sur scalaires/booléens (aucune itération, aucune alloc heap, restore `Engine.time_scale` ≤ 0.05 ms). Impact attendu : < 0.1 ms par event, négligeable vs budget physics 4 ms (ADR-0001 VC-4) et signal cumul 0.1 ms (ADR-0005 VC-8).

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-014` (mutual kill state ownership — partie reset uniquement)
*(Voir tr-registry.yaml pour ordering)*

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0005 (Movement Signals)
**ADR Decision Summary**: `Player.died` signal SYNC (ADR-0005 D-5 amendment r2 exemption pour Rule 17 Hybrid M1) ; `Player.respawned(Vector3)` reset complet de Combat à l'état Idle propre.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Signal `connect()` mode SYNC (default flag 0) stable Godot 4.0+. Aucune API post-cutoff impliquée.

**Control Manifest Rules (Feature layer)**:
- Required: connection SYNC (`flags == 0`) pour `player.died` (ADR-0005 D-5 amendment r2)
- Forbidden: connection `CONNECT_DEFERRED` sur `player.died` — viole Rule 17 Hybrid (vérifié AC-CMB-41 clause 8)
- Guardrail: reset complet `_death_pending` + `_buffered_attack` post-respawn pour éviter clic fantôme

---

## Acceptance Criteria

*From GDD, AC-CMB-11 + AC-CMB-21 :*

- [ ] **AC-CMB-11 (a)** : `Player.died()` reçu en `Idle` → `_state == DEAD`, `ShapeCast3D.enabled == false`
- [ ] **AC-CMB-11 (b) — full respawn reset** : `Player.respawned(Vector3.ZERO)` reçu sur état Combat `Dead` arbitraire (8 vars muées) → 8 assertions :
  - (1) `_state == IDLE`
  - (2) `_active_tick == 0`
  - (3) `_hit_this_swing.is_empty()`
  - (4) `_cooldown_timer == 0.0`
  - (5) `_slow_mo_active == false`
  - (6) `_slow_mo_start_msec == 0`
  - (7) `_death_pending == false`
  - (8) `_buffered_attack == false`
  - **AND** : `Engine.time_scale == 1.0 ± 0.0001`, `ShapeCast3D.enabled == false`
- [ ] **AC-CMB-21** : si `_slow_mo_active == true` au moment de `Player.died()` → `Engine.time_scale == 1.0 ± 0.0001` restauré AVANT toute autre transition Dead, `_slow_mo_active = false`

---

## Implementation Notes

*Derived from ADR-0006 D-6 + GDD Edge Cases §572 + AC-CMB-11 r4 P-05/P-06:*

- Connecter dans `_ready()` : `player.died.connect(_on_player_died)` (mode SYNC, flag 0 — vérifié grep CI)
- Connecter dans `_ready()` : `player.respawned.connect(_on_player_respawned)` (mode SYNC ou DEFERRED — décision ADR-0005, par défaut SYNC car léger)
- `_on_player_died()` :
  ```gdscript
  if _slow_mo_active:
      Engine.time_scale = 1.0
      _slow_mo_active = false
      _slow_mo_start_msec = 0
  _state = State.DEAD
  $ShapeCast3D.enabled = false
  # _death_pending handling : story-014 pour mutual kill mid-swing
  ```
- `_on_player_respawned(spawn_pos: Vector3)` : reset complet 8 vars (cf. liste AC-CMB-11)
- **Forbidden** : ne PAS `await` ou `call_deferred` dans `_on_player_died` — handler doit être SYNC pour `_death_pending` Rule 17 (story-014)

---

## Out of Scope

- Story 014 : `_death_pending` end-of-tick mid-swing handling (Rule 17 mutual kill complet)
- Story 013 : slow-mo lifecycle complet (cette story gère uniquement le restore défensif au died)
- Story 012 : `_buffered_attack` set/clear pendant gameplay normal

---

## QA Test Cases

- **AC-1** Died from Idle
  - Given: Combat `Idle`, `_slow_mo_active == false`
  - When: `player.died.emit()`
  - Then: `_state == DEAD`, `ShapeCast3D.enabled == false`, `Engine.time_scale == 1.0`
  - Edge cases: died répété (idempotent — déjà Dead, pas de side-effect)

- **AC-2** Respawn full reset
  - Given: Combat `Dead` avec `_active_tick=3, _hit_this_swing=[1,2,3], _cooldown_timer=0.15, _slow_mo_active=true, _slow_mo_start_msec=1234, _death_pending=true, _buffered_attack=true`
  - When: `player.respawned.emit(Vector3.ZERO)`
  - Then: 8 assertions list passent + `Engine.time_scale == 1.0 ± 0.0001` + `ShapeCast3D.enabled == false`
  - Edge cases: respawned reçu en `IDLE` (pas Dead) — comportement = même reset propre

- **AC-3** Died restore slow-mo
  - Given: `_slow_mo_active == true`, `Engine.time_scale == 0.3`
  - When: `player.died.emit()`
  - Then: `Engine.time_scale == 1.0 ± 0.0001` AVANT autre logique, `_slow_mo_active == false`, `_state == DEAD`
  - Edge cases: `Engine.time_scale = 0.5` debug externe — restore vers 1.0 (écrase, pas vers 0.5)

- **AC-4** Connection mode grep (clause AC-CMB-41 #8)
  - Given: source `combat_system.gd` complet
  - When: `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' src/gameplay/combat/combat_system.gd`
  - Then: zéro match
  - Edge cases: `connect_deferred` en variable name (commentaire) acceptable

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/death_respawn_lifecycle_test.gd` — doit exister et couvrir AC-1/AC-2/AC-3/AC-4 (4 cas) ; tous tests `PASS` requis avant `/story-done`.

**Status**: [ ] Test file à créer pendant `/dev-story` (handoff godot-gdscript-specialist)

---

## Dependencies

- Depends on: Story 002 (state machine), Movement story emit-die-respawned (Movement Story 016/017 ou équivalent)
- Unlocks: Story 014 (mutual kill mid-swing), Story 013 (slow-mo lifecycle complet)
