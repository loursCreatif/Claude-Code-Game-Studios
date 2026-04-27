# Story 015: Mid-swing state transitions + race Idle mitigation + pause spam

> **Epic**: Player Combat System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-28/29/50 (cross-system state edge cases pendant Swinging)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0004 (Input pause)
**ADR Decision Summary**: Combat ne lit pas `Player.state` pour gating swing (Rule 8 — toutes states Movement autorisées). Seule garde : `_state != Dead`. Race condition Idle (Player passe à Dead sans signal `died` reçu — théorique) → mitigation `_state == IDLE and player.state == Dead` force `_state = Dead`. AC-CMB-50 vérifie 4 transitions Movement mid-swing (Grounded↔Airborne, Dashing, WallRunning) — Combat continue normalement.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: API `Player.state` (read-only enum exposée par Movement) stable.

**Control Manifest Rules (Feature layer)**:
- Required: lecture `player.state` UNIQUEMENT pour mitigation race Idle (whitelist) ; sinon poll interdit
- Forbidden: `match player.state` ou `player.state == X` pour gating gameplay (Combat agnostic des states Movement, Rule 8)
- Guardrail: mitigation race appliquée UNIQUEMENT si `_state == IDLE` (ne pas écraser `_death_pending` Hybrid quand Swinging — AC-CMB-28 r4 isolation)

---

## Acceptance Criteria

*From GDD AC-CMB-28/29/50 :*

- [ ] **AC-CMB-50** : `Combat Swinging` à `_active_tick = 3`, scene intégrée Player+Movement+Camera+Combat. Pour les 4 sous-cas (a) Grounded→Airborne, (b) Airborne→Grounded, (c) Grounded→Dashing, (d) Airborne→WallRunning :
  - (1) `_state` reste `Swinging`
  - (2) `_active_tick` continue normal (3 → 4 → ... → 7)
  - (3) `ShapeCast3D.global_transform.origin` mis à jour chaque tick avec `_prev_position + aim × reach/2`
  - (4) `aim_forward` reste roll-corrigé (tilt wall-run n'affecte pas — couvert AC-CMB-26)
  - (5) `N_SUBSTEPS == 3` constant (pas branching state)
  - (6) à expiration : transition Idle, `swing_ended` émis, `_hit_this_swing.clear()`
- [ ] **AC-CMB-28** : `Combat _state == IDLE` (pas Swinging), `Player.state == Dead` sans `Player.died()` émis (race théorique 1 tick) → mitigation détecte (`player.state == Dead and _state == IDLE`), force `_state = Dead`, `ShapeCast3D.enabled = false`. **Restriction r2** : mitigation NE s'applique PAS quand `_state == SWINGING` (mécanisme `_death_pending` gouverne)
- [ ] **AC-CMB-29** : test intégration `InputManager.enabled = false` (pause), 10 clics `attack` injectés → `Player.attacked()` non émis (Movement n'émet pas), `Combat._state` reste Idle

---

## Implementation Notes

*Derived from ADR-0006 + GDD Edge Cases :*

```gdscript
func _physics_process(delta: float) -> void:
    # Mitigation race Idle (AC-CMB-28 — restriction r2 isolée)
    if _state == State.IDLE and player.state == Movement.State.DEAD:
        _state = State.DEAD
        $ShapeCast3D.enabled = false
        return  # rest of process skipped — fully Dead

    # ... cooldown, state machine, sweep (story-002, 008, 009, 011, 012)
    # AC-CMB-50: aucune logique branchement sur player.state pour gating swing
```

- AC-CMB-50 ne nécessite pas de code new — simplement vérifier que rien n'est branché sur `player.state` :
  ```bash
  grep -nE 'match\s+player\.state|player\.state\s*[!=]=' src/gameplay/combat/combat_system.gd
  # → seul match autorisé : la mitigation race ligne unique IDLE+Dead
  ```
- AC-CMB-29 : Movement n'émet pas `attacked()` quand pause active (story Movement). Combat passive : si signal n'arrive pas, rien à faire.

---

## Out of Scope

- Story 014 : `_death_pending` Swinging Hybrid (cette story 015 isole IDLE-only mitigation)
- Story 003 : died/respawned reset (cette story s'occupe seulement de la race théorique sans signal)

---

## QA Test Cases

- **AC-1** 4 mid-swing transitions
  - Given: Combat `Swinging` `_active_tick=3`, scene Player+Movement+Camera+Combat
  - When: pour chaque sous-cas (a-d), Movement transit (Grounded→Airborne via jump, etc.)
  - Then: 6 assertions per sous-cas : `_state==SWINGING`, `_active_tick++`, ShapeCast origin update, aim_forward roll-correct, N_SUBSTEPS==3, expiration → Idle + swing_ended + clear
  - Edge cases: 2 transitions consécutives mid-swing (e.g. Grounded→Dashing→Airborne) — Combat continue agnostic

- **AC-2** Idle race mitigation
  - Given: Combat `_state == IDLE`, `Player.state == DEAD`, signal `died` non émis (race synthétique)
  - When: `_physics_process` exécuté
  - Then: `_state == DEAD`, `ShapeCast3D.enabled == false`
  - Edge cases: `Player.state == Dead` ET `_state == SWINGING` → mitigation NE s'applique PAS (story-014 `_death_pending` gouverne)

- **AC-3** Pause spam ignored
  - Given: scene intégrée + `InputManager.enabled = false` (pause)
  - When: 10 clics `attack` injectés via GUT
  - Then: `Player.attacked()` non émis (Movement consume), `Combat._state` reste IDLE
  - Edge cases: pause toggled false puis 1 click → attack émis normalement

- **AC-4** No state polling grep
  - Given: source `combat_system.gd`
  - When: `grep -nE 'match\s+player\.state|player\.state\s*==' src/gameplay/combat/combat_system.gd`
  - Then: max 1 match (la mitigation IDLE+Dead — ligne unique)
  - Edge cases: lectures dans tests autorisées (`tests/integration/combat/`)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/combat/mid_swing_transitions_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 014 (death_pending mid-swing — distinct mécanisme), Movement story exposing `state` enum read-only
- Unlocks: Story 016 (invariants validation)
