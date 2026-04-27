# Story 004: `attacked()` handler + buffer single-slot 80ms

> **Epic**: Player Combat System
> **Status**: Ready
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-008` (signal-driven trigger), `TR-cmb-009` (attack buffer single-slot)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0005 (Movement Signals) + ADR-0004 (Input)
**ADR Decision Summary**: Combat ne polle JAMAIS InputManager directement (forbidden). Movement émet `attacked()` signal outbound-only (ADR-0005 D-2). Buffer single-slot 80 ms : un signal reçu pendant que `_cooldown_timer > 0` mais dans `[0, ATTACK_BUFFER_MS]` est mémorisé en `_buffered_attack = true` ; consommé à expiration cooldown si `_state == Idle`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Engine.is_in_physics_frame()` stable Godot 4.0+ (assert AC-CMB-52).

**Control Manifest Rules (Feature layer)**:
- Required: signal-driven (Combat reçoit, ne polle pas)
- Forbidden: lecture directe `InputManager.was_pressed_this_tick(...)` depuis `src/gameplay/combat/` (Core Rule 1 + grep CI)
- Guardrail: handler `attacked()` doit asserter `Engine.is_in_physics_frame()` en debug build

---

## Acceptance Criteria

*From GDD, AC-CMB-22/23/30/38/39/40/52 :*

- [ ] **AC-CMB-22** : 2× `Player.attacked()` même tick (Idle, cooldown=0) → 1 seul swing déclenché (`_state == SWINGING`, `_active_tick == 0`)
- [ ] **AC-CMB-23** : `_cooldown_timer == 0.0` exact + `Player.attacked()` → swing accepté immédiatement (garde inclusive)
- [ ] **AC-CMB-30** : `Player.attacked()` reçu en `Swinging` à `_active_tick = 4` → ignoré silencieusement (pas de re-démarrage, pas de reset window)
- [ ] **AC-CMB-38** : `Swinging` + `_cooldown_timer = 0.05` (dans buffer 80 ms) + `Player.attacked()` → `_buffered_attack == true`, `_state` reste Swinging ; à `_cooldown_timer == 0.0`, tick suivant `_state == SWINGING` (nouveau swing), `_buffered_attack == false`, `_active_tick == 0`
- [ ] **AC-CMB-39** : signaux hors fenêtre buffer (cooldown > 80 ms) ignorés ; signaux multiples dans fenêtre → single-slot (1er retenu, suivants ignorés)
- [ ] **AC-CMB-40** : `Player.died()` reçu avec `_buffered_attack == true` → `_buffered_attack == false` (clear à died ET respawned, cf. story-003)
- [ ] **AC-CMB-52 (ADVISORY)** : handler contient `assert(Engine.is_in_physics_frame(), ...)` en tête, debug build only ; grep `assert\(Engine\.is_in_physics_frame` dans `combat_system.gd` retourne ≥1 match
- [ ] **Forbidden grep** : aucune lecture `InputManager.` dans `src/gameplay/combat/`

---

## Implementation Notes

*Derived from ADR-0006 + GDD Rule 3 r1 buffering + ADR-0005 D-2:*

- Connecter dans `_ready()` : `player.attacked.connect(_on_player_attacked)` (mode SYNC ou DEFERRED selon ADR-0005 — par défaut DEFERRED si Combat alloue, mais ici handler simple → SYNC OK ; trancher avec ADR-0006 D-6)
- Variables : `_buffered_attack: bool = false`
- Constante : `const ATTACK_BUFFER_MS: float = 80.0` (Section G GDD)
- `_on_player_attacked()` :
  ```gdscript
  if OS.is_debug_build():
      assert(Engine.is_in_physics_frame(), "attacked() received outside _physics_process — ADR-0005 D-4 violation")
  if _state == State.DEAD:
      return  # AC-03 coverage
  if _state == State.IDLE and _cooldown_timer <= 0.0:
      _start_swing()  # logique state-machine story-002
      return
  if _state == State.SWINGING and _cooldown_timer > 0.0 and _cooldown_timer <= ATTACK_BUFFER_MS / 1000.0:
      _buffered_attack = true  # single-slot, écrase pas (1er retenu)
      return
  # else: hors fenêtre OU re-attack pendant active window → ignoré silencieusement
  ```
- À expiration cooldown dans `_physics_process` (story-002 augmenté) :
  ```gdscript
  if _cooldown_timer <= 0.0 and _state == State.IDLE and _buffered_attack:
      _buffered_attack = false
      _start_swing()
  ```
- Reset `_buffered_attack = false` dans `_on_player_died` ET `_on_player_respawned` (cf. story-003 AC-CMB-11 (8))

---

## Out of Scope

- Story 005-007 : géométrie sweep / aim_forward
- Story 008-010 : anti-tunneling et tick-0 mitigation
- Story 011-012 : résolution kills

---

## QA Test Cases

- **AC-1** Double-emit same tick
  - Given: Combat `Idle`, `_cooldown_timer = 0.0`
  - When: 2× `player.attacked.emit()` même tick
  - Then: après 1 `_physics_process` : `_state == SWINGING`, `_active_tick == 0`, `_cooldown_timer == 0.4 ± 0.001`
  - Edge cases: 100× emits même tick → 1 seul swing

- **AC-2** Cooldown=0 inclusive
  - Given: `_cooldown_timer == 0.0` exactement (transition depuis > 0 au tick précédent)
  - When: `player.attacked.emit()`
  - Then: swing accepté tick courant (pas de délai 1 tick)
  - Edge cases: `_cooldown_timer == 0.0001` — gate boucle 1 tick avant accept

- **AC-3** Re-attack mid-swing ignored
  - Given: `_state == SWINGING`, `_active_tick == 4`, `_cooldown_timer == 0.27`
  - When: `player.attacked.emit()`
  - Then: `_state == SWINGING`, `_active_tick == 5` au tick suivant (progression normale), pas de reset
  - Edge cases: emit chaque tick pendant active window → tous ignorés ou bufferisés selon cooldown

- **AC-4** Buffer single-slot in window
  - Given: `_state == SWINGING`, `_cooldown_timer = 0.05` (in buffer 80ms)
  - When: `player.attacked.emit()`
  - Then: `_buffered_attack == true`, `_state` reste SWINGING
  - Edge cases: 2e emit dans fenêtre → toujours `_buffered_attack == true` (idempotent), 3e idem

- **AC-5** Buffered consumed at cooldown=0
  - Given: `_buffered_attack == true`, `_state == IDLE`, `_cooldown_timer = 0.001`
  - When: 1× `_physics_process(1.0/60.0)` (cooldown → 0)
  - Then: `_state == SWINGING`, `_buffered_attack == false`, `_active_tick == 0`
  - Edge cases: `_buffered_attack` set au tick exact de cooldown=0 → consommé même tick

- **AC-6** Buffer cleared on died
  - Given: `_buffered_attack == true`
  - When: `player.died.emit()`
  - Then: `_buffered_attack == false`
  - Edge cases: died puis respawned → `_buffered_attack == false` (clear 2× safe)

- **AC-7** Forbidden grep InputManager
  - Given: source `src/gameplay/combat/combat_system.gd`
  - When: `grep -nE 'InputManager\.' src/gameplay/combat/`
  - Then: zéro match
  - Edge cases: imports Movement OK (Movement émet attacked, pas Combat polling)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/attacked_handler_buffer_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002 (state machine), Story 003 (died/respawned reset), Movement story émettant `attacked` signal
- Unlocks: Story 011 (kill resolution déclenchée par swing)
