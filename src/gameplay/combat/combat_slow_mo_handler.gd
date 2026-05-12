## CombatSlowMoHandler — Slow-mo feedback kill + accessibility reduce-motion (Story 013 + 022).
##
## Extrait de CombatSystem (TD-008 split). Possédé et instancié par CombatSystem.
## PAS de class_name — référencé via preload binding local dans combat_system.gd
## pour bypass class cache CI gdUnit4-action (même pattern que audio_combat_handler.gd).
##
## ADR-0006 D-3 (physics_process only for time_scale restore).
## ADR-0015 D-3 (pull-pattern AccessibilityService).

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const CombatSlowMoHandler := preload(...)`
# dans combat_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Constants (mirrored from CombatSystem for internal use)
# ---------------------------------------------------------------------------

const SLOW_MO_SCALE: float = 0.3
const SLOW_MO_DURATION_MS: float = 50.0


# ---------------------------------------------------------------------------
# Injected references
# ---------------------------------------------------------------------------

## Référence injectée au Node CombatSystem parent (pour lire _get_time_msec).
var _combat: Node = null


# ---------------------------------------------------------------------------
# Slow-mo state
# ---------------------------------------------------------------------------

## Drapeau slow-mo actif (story 013 owner ; story 003 lit pour restore défensif au died).
var _slow_mo_active: bool = false

## Timestamp wall-clock (Time.get_ticks_msec) du début slow-mo (story 013 ; reset au respawn).
var _slow_mo_start_msec: int = 0


# ---------------------------------------------------------------------------
# Accessibility state (story 022)
# ---------------------------------------------------------------------------

## Si `true`, désactive la slow-mo sur 1er enemy_killed (AC-CMB-19 r6).
var _reduce_motion_disable_slow_mo: bool = false

## Multiplier slow-mo [1.0, 3.33]. effective_scale = SLOW_MO_SCALE × mult clampé [0.0, 1.0].
var _reduce_motion_slow_mo_scale_mult: float = 1.0

## Multiplier flash VFX [0.0, 1.0]. Stocké pour future contract Combat→VFX.
var _reduce_motion_flash_mult: float = 1.0


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Story 013 : déclenche slow-mo sur 1er enemy_killed du swing.
##
## Idempotent (multi-kill n'étend pas la fenêtre — `_slow_mo_active` flag).
## Branch accessibility (story 022) :
##   - `_reduce_motion_disable_slow_mo == true` → ne mute PAS Engine.time_scale.
##   - `_reduce_motion_slow_mo_scale_mult > 1.0` → atténue effective_scale.
##
## Appelé depuis CombatHitHandler._resolve_kills loop.
func trigger_slow_mo_if_first_kill() -> void:
	if _slow_mo_active:
		return  # idempotence multi-kill (AC-CMB-25)
	if _reduce_motion_disable_slow_mo:
		return  # accessibility branch C (AC-CMB-19 r6)
	_slow_mo_active = true
	_slow_mo_start_msec = _combat._get_time_msec.call() as int
	var effective_scale: float = clampf(
		SLOW_MO_SCALE * _reduce_motion_slow_mo_scale_mult, 0.0, 1.0
	)
	Engine.time_scale = effective_scale


## Story 013 : restore Engine.time_scale à 1.0 quand SLOW_MO_DURATION_MS écoulé.
##
## Appelé au début de `_physics_process` (via CombatSystem) pour que les autres
## systèmes lisent un time_scale cohérent dans le même tick.
## ADR-0001 authority : restore depuis `_physics_process` UNIQUEMENT.
func check_slow_mo_restore() -> void:
	if not _slow_mo_active:
		return
	var now: int = _combat._get_time_msec.call() as int
	var elapsed: int = now - _slow_mo_start_msec
	if elapsed >= int(SLOW_MO_DURATION_MS):
		Engine.time_scale = 1.0
		_slow_mo_active = false
		_slow_mo_start_msec = 0


## Restore immédiat au died (story 003 AC-CMB-21).
func restore_on_death() -> void:
	if _slow_mo_active:
		Engine.time_scale = 1.0
		_slow_mo_active = false
		_slow_mo_start_msec = 0


## Reset complet au respawn (story 003 AC-CMB-11 part 5+6).
func reset_on_respawn() -> void:
	_slow_mo_active = false
	_slow_mo_start_msec = 0


## Story 022 : applique les settings reduce_motion lus depuis AccessibilityService.
## Pull-pattern (ADR-0015 D-3). Bornes clampées service-level (D-7).
func apply_accessibility() -> void:
	_reduce_motion_disable_slow_mo = AccessibilityService.get_disable_slow_mo()
	_reduce_motion_slow_mo_scale_mult = AccessibilityService.get_slow_mo_scale_mult()
	_reduce_motion_flash_mult = AccessibilityService.get_flash_mult()
