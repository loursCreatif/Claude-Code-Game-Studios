## CombatTickHandler — Physics tick dispatch + swing lifecycle (Stories 001–016).
##
## Extrait de CombatSystem (TD-008 split). Possédé et instancié par CombatSystem.
## PAS de class_name — référencé via preload binding local dans combat_system.gd
## pour bypass class cache CI gdUnit4-action (même pattern que audio_combat_handler.gd).
##
## Responsabilités :
##   - `tick(delta)` : body complet de CombatSystem._physics_process (ADR-0006 D-3).
##   - `start_swing()` : transition IDLE→SWINGING, arm ShapeCast, init cooldown.
##
## ADR-0006 D-3 (physics_process authority, tick model).
## ADR-0006 D-5 (wall-clock injectable via _combat._get_time_msec).

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const CombatTickHandler := preload(...)`
# dans combat_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected references
# ---------------------------------------------------------------------------

## Référence injectée au Node CombatSystem parent.
## Accès à : tous les champs d'état (_state, _active_tick, _cooldown_timer,
##           _hit_this_swing, _death_pending, _buffered_attack, _prev_position,
##           _shape_cast, _camera_system), constantes (ACTIVE_TICKS, ATTACK_COOLDOWN_MS,
##           ATTACK_BUFFER_MS), handlers (_slow_mo_handler, _hit_handler, _lifecycle_handler),
##           signals (swing_ended), enum State.
var _combat: Node = null


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Body complet du CombatSystem._physics_process — délégué depuis le Node principal.
##
## Ordre d'exécution (ADR-0006 D-3) :
##   1. Invariants debug-only (story 016).
##   2. Race mitigation IDLE/DEAD (story 015 AC-CMB-28).
##   3. Slow-mo restore (story 013 — time_scale cohérent pour ce tick).
##   4. Cooldown decrement.
##   5. SWINGING → tick active, collect hits, resolve kills, check expiry.
##   6. Buffer single-slot consommation (story 004 AC-CMB-38).
##   7. Death pending drain (story 014 Rule 17 M1 Option C).
##   8. Capture _prev_position FIN tick (story 008).
func tick(delta: float) -> void:
	# Story 016 : invariants debug-only.
	if OS.is_debug_build():
		_combat._lifecycle_handler.validate_invariants()

	# Story 015 AC-CMB-28 : race mitigation IDLE only.
	if _combat._state == _combat.State.IDLE:
		var p: Node = _combat.get_parent()
		if p is MovementController and (p as MovementController).state == MovementController.State.DEAD:
			_combat._state = _combat.State.DEAD
			if _combat._shape_cast != null:
				_combat._shape_cast.enabled = false
			return

	# Story 013 : slow-mo restore en premier (time_scale cohérent pour ce tick).
	_combat._slow_mo_handler.check_slow_mo_restore()

	_combat._cooldown_timer = maxf(0.0, _combat._cooldown_timer - delta)

	if _combat._state == _combat.State.DEAD:
		return

	if _combat._state == _combat.State.SWINGING:
		_combat._active_tick += 1

		var swing_hits: Array[int] = _combat._hit_handler.collect_swing_hits()
		_combat._hit_handler.resolve_kills(swing_hits)
		_combat._hit_handler.update_sweep_origin()

		if _combat._active_tick >= _combat.ACTIVE_TICKS:
			_combat._state = _combat.State.IDLE
			_combat._active_tick = 0
			_combat._hit_this_swing.clear()
			if _combat._shape_cast != null:
				_combat._shape_cast.enabled = false
			_combat.swing_ended.emit()

	# Story 004 AC-CMB-38 : consommation buffer single-slot.
	if _combat._state == _combat.State.IDLE and _combat._cooldown_timer == 0.0 and _combat._buffered_attack:
		_combat._buffered_attack = false
		start_swing()

	# Story 014 : drain `_death_pending` reçu mid-swing (Rule 17 Hybrid M1 Option C).
	if _combat._death_pending:
		_combat._lifecycle_handler.drain_death_pending()

	# Story 008 : capture `_prev_position` à la FIN du tick.
	var parent_3d: Node3D = _combat.get_parent() as Node3D
	if parent_3d != null:
		_combat._prev_position = parent_3d.global_position


## Transition IDLE→SWINGING : arm ShapeCast, init cooldown, reset _hit_this_swing.
##
## Guard : si aim invalide (validate_aim retourne false), le swing est annulé silencieusement.
## Proxy test seam : accessible via `combat._start_swing()` → `_tick_handler.start_swing()`.
func start_swing() -> void:
	if _combat._camera_system != null:
		var raw: Variant = _combat._camera_system.get("aim_forward")
		if raw is Vector3 and not _combat._hit_handler.validate_aim(raw as Vector3):
			return

	_combat._state = _combat.State.SWINGING
	_combat._active_tick = 0
	_combat._cooldown_timer = _combat.ATTACK_COOLDOWN_MS / 1000.0
	_combat._hit_this_swing.clear()
	_combat._hit_handler.update_sweep_origin()
	if _combat._shape_cast != null:
		_combat._shape_cast.enabled = true
