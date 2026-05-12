## CombatLifecycleHandler — Death/respawn lifecycle + invariants validation (Stories 003 + 016).
##
## Extrait de CombatSystem (TD-008 split). Possédé et instancié par CombatSystem.
## PAS de class_name — référencé via preload binding local dans combat_system.gd
## pour bypass class cache CI gdUnit4-action (même pattern que audio_combat_handler.gd).
##
## ADR-0005 D-5 amendment r2 (SYNC exemption died — CONNECT_DEFERRED FORBIDDEN).
## ADR-0006 D-3 (physics_process authority).

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const CombatLifecycleHandler := preload(...)`
# dans combat_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected references
# ---------------------------------------------------------------------------

## Référence injectée au Node CombatSystem parent.
var _combat: Node = null


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Handler signal Player.died — connexion SYNC (ADR-0005 D-5 amendment r2 exemption).
##
## Pattern hybride story-003 + story-014 (Rule 17 M1 Option C) :
##   - Toujours set `_death_pending = true`.
##   - Si `_state != SWINGING` → drain immédiat.
##   - Si `_state == SWINGING` → drain DIFFÉRÉ à fin de `_physics_process`.
##
## FORBIDDEN (AC-CMB-41 clause 8) : ne jamais utiliser await / call_deferred ici.
func on_player_died() -> void:
	_combat._death_pending = true
	if _combat._state != _combat.State.SWINGING:
		drain_death_pending()


## Drain du flag `_death_pending` : restore slow-mo, transition Dead, disable ShapeCast.
##
## Idempotent : safe d'appeler avec `_death_pending == false` (no-op).
func drain_death_pending() -> void:
	if not _combat._death_pending:
		return
	_combat._death_pending = false
	_combat._slow_mo_handler.restore_on_death()
	_combat._state = _combat.State.DEAD
	if _combat._shape_cast != null:
		_combat._shape_cast.enabled = false


## Handler signal Player.respawned — reset complet à l'état Idle propre.
##
## Couvre AC-CMB-11 (b) — 8 vars + 2 effets externes :
##   (1) _state = IDLE     (2) _active_tick = 0
##   (3) _hit_this_swing.clear()  (4) _cooldown_timer = 0.0
##   (5+6) slow-mo reset via handler  (7) _death_pending = false
##   (8) _buffered_attack = false
##   AND : Engine.time_scale = 1.0, ShapeCast3D.enabled = false.
##
## Le paramètre spawn_position n'est pas utilisé par Combat.
func on_player_respawned(_spawn_position: Vector3) -> void:
	_combat._state = _combat.State.IDLE
	_combat._active_tick = 0
	_combat._hit_this_swing.clear()
	_combat._cooldown_timer = 0.0
	_combat._slow_mo_handler.reset_on_respawn()
	_combat._death_pending = false
	_combat._buffered_attack = false
	Engine.time_scale = 1.0
	if _combat._shape_cast != null:
		_combat._shape_cast.enabled = false


## Story 016 : valide les 8 invariants Combat sur valeurs courantes (live-tuning safe).
##
## Appelé chaque `_physics_process` sous `OS.is_debug_build()` guard.
## `assert()` est compilé out en release.
func validate_invariants() -> void:
	assert(
		_combat.KATANA_REACH > _combat.PLAYER_CAPSULE_RADIUS + 1.0,
		"Invariant #1: KATANA_REACH (%.3f) doit être > PLAYER_CAPSULE_RADIUS + 1.0 (%.3f)"
		% [_combat.KATANA_REACH, _combat.PLAYER_CAPSULE_RADIUS + 1.0]
	)
	assert(_combat.KATANA_REACH > 0.0, "Invariant #2: KATANA_REACH doit être > 0")
	var min_cooldown_ms: float = _combat.SWING_DURATION_MS + (1000.0 / 60.0)
	assert(
		_combat.ATTACK_COOLDOWN_MS >= min_cooldown_ms,
		"Invariant #3: ATTACK_COOLDOWN_MS (%.2f) doit être >= SWING + 1 frame (%.2f)"
		% [_combat.ATTACK_COOLDOWN_MS, min_cooldown_ms]
	)
	assert(
		_combat.ATTACK_COOLDOWN_MS > _combat.SWING_DURATION_MS + _combat.SLOW_MO_DURATION_MS,
		"Invariant #4: ATTACK_COOLDOWN_MS (%.2f) doit être > SWING + SLOW_MO (%.2f)"
		% [_combat.ATTACK_COOLDOWN_MS, _combat.SWING_DURATION_MS + _combat.SLOW_MO_DURATION_MS]
	)
	var gap_max: float = _combat.V_MAX * (1.0 / 60.0) / float(_combat.N_SUBSTEPS)
	var enemy_diam: float = 2.0 * _combat.ENEMY_RADIUS_MIN
	assert(
		gap_max < enemy_diam,
		"Invariant #5 anti-tunneling: gap_max (%.4f) doit être < 2 × ENEMY_RADIUS_MIN (%.4f)"
		% [gap_max, enemy_diam]
	)
	assert(
		_combat.SLOW_MO_DURATION_MS < _combat.ATTACK_COOLDOWN_MS / 2.0,
		"Invariant #6: SLOW_MO_DURATION_MS (%.2f) doit être < ATTACK_COOLDOWN_MS / 2 (%.2f)"
		% [_combat.SLOW_MO_DURATION_MS, _combat.ATTACK_COOLDOWN_MS / 2.0]
	)
	assert(
		_combat.ATTACK_BUFFER_MS <= _combat.ATTACK_COOLDOWN_MS / 5.0,
		"Invariant #7: ATTACK_BUFFER_MS (%.2f) doit être <= ATTACK_COOLDOWN_MS / 5 (%.2f)"
		% [_combat.ATTACK_BUFFER_MS, _combat.ATTACK_COOLDOWN_MS / 5.0]
	)
	var duty: float = _combat.SWING_DURATION_MS / (_combat.SWING_DURATION_MS + _combat.ATTACK_COOLDOWN_MS)
	assert(
		duty < 0.4,
		"Invariant #8 duty cycle staccato: duty (%.3f) doit être < 0.4"
		% duty
	)
