## VFXFlashHandler — Domaine flash kill + flash respawn wall-clock.
## Possédé et instancié par VFXCombatHandler (composition interne).
## Reçoit une référence injectée au Node VFXSystem pour accéder aux constantes,
## à l'overlay ColorRect et à l'injection wall-clock (_get_time_msec).
## PAS un autoload — pas de class_name (référencé via preload binding
## local dans vfx_combat_handler.gd).
## ADR-0009 D-3 (wall-clock fades) : aucun Tween sur color/modulate ici.
## Outbound-zero (R-VFX-14) : aucun emit_signal ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const VFXFlashHandler := preload(...)`
# dans vfx_combat_handler.gd pour bypass l'absence de class cache en CI.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à VFXSystem (Node) — pour _get_time_msec, constantes,
## _flash_overlay_rect, _reduce_flash, DEFAULT/REDUCE_FLASH_BRIGHTNESS.
## Injectée par VFXCombatHandler après instanciation.
var _vfx: Node = null


# ---------------------------------------------------------------------------
# State — flash kill
# ---------------------------------------------------------------------------

## True quand flash kill actif (wall-clock timer en cours dans _physics_process).
var _flash_kill_active: bool = false

## Timestamp démarrage flash kill (0 = pas de flash en cours).
var _flash_kill_start_msec: int = 0

## True si reduce_flash actif au moment du trigger (gris substitute pour la durée du flash).
var _flash_kill_use_grey: bool = false


# ---------------------------------------------------------------------------
# State — flash respawn
# ---------------------------------------------------------------------------

## True quand flash respawn actif (wall-clock timer en cours).
var _flash_respawn_active: bool = false

## Timestamp démarrage flash respawn (0 = pas de flash en cours).
var _flash_respawn_start_msec: int = 0


# ---------------------------------------------------------------------------
# State — rate guard
# ---------------------------------------------------------------------------

## Timestamp du dernier flash émis (WCAG 333 ms guard story-004).
var _flash_last_msec: int = 0


# ---------------------------------------------------------------------------
# Tick methods — appelés depuis VFXSystem._physics_process via VFXCombatHandler
# ---------------------------------------------------------------------------

## Tick flash kill wall-clock 80 ms (R-VFX-5 + AC-VFX-06/25).
func tick_flash_kill() -> void:
	var elapsed_kill_ms: int = _vfx._get_time_msec.call() - _flash_kill_start_msec
	if elapsed_kill_ms >= _vfx.FLASH_KILL_DURATION_MS:
		_flash_kill_active = false
		_vfx._flash_overlay_rect.visible = _flash_respawn_active  # garde si respawn en cours
	else:
		var t_kill: float = float(elapsed_kill_ms) / float(_vfx.FLASH_KILL_DURATION_MS)
		_apply_flash_kill_color(t_kill)


## Tick flash respawn wall-clock 50 ms binaire pop (R-VFX-15 + AC-VFX-09/15).
func tick_flash_respawn() -> void:
	var elapsed_respawn_ms: int = _vfx._get_time_msec.call() - _flash_respawn_start_msec
	if elapsed_respawn_ms >= _vfx.FLASH_RESPAWN_DURATION_MS:
		_flash_respawn_active = false
		_vfx._flash_overlay_rect.visible = _flash_kill_active  # garde si kill en cours
	# 50 ms = pop binaire, pas de fade interpolé MVP (R-VFX-15)


# ---------------------------------------------------------------------------
# Trigger methods — appelés depuis VFXCombatHandler
# ---------------------------------------------------------------------------

## Flash kill 80 ms wall-clock + WCAG 333 ms plancher 3 Hz guard (R-VFX-5/13 + AC-VFX-06/08).
## reduce_flash → fondu gris #A0A0A0 substitute (R-VFX-5 + AC-VFX-07 + F-VFX-2).
## story-006 : early-out guard si frozen (MENU/PAUSED/BOSS_DEFEATED).
func trigger_flash_kill() -> void:
	if not _vfx._is_active:
		return
	var now: int = _vfx._get_time_msec.call()
	if now - _flash_last_msec < _vfx.FLASH_MIN_INTERVAL_MS:
		push_warning("VFX: flash rate guard triggered — skip flash kill (last=%d, now=%d, delta=%d ms)" % [
			_flash_last_msec, now, now - _flash_last_msec
		])
		return
	_flash_last_msec = now
	_flash_kill_active = true
	_flash_kill_start_msec = now
	_flash_kill_use_grey = _vfx._reduce_flash
	_vfx._flash_overlay_rect.visible = true
	_apply_flash_kill_color(0.0)  # t = 0 → opacity max


## Flash respawn 50 ms blanc pur (R-VFX-15 + AC-VFX-09).
## reduce_flash → flash supprimé entièrement (pas de substitut gris — durée 50 ms trop courte).
## story-006 : early-out guard si frozen (MENU/PAUSED/BOSS_DEFEATED).
func trigger_flash_respawn() -> void:
	if not _vfx._is_active:
		return
	if _vfx._reduce_flash:
		return  # AC-VFX-09 — zéro flash respawn si reduce_flash ON
	var now: int = _vfx._get_time_msec.call()
	_flash_respawn_active = now > 0  # wall-clock guard
	_flash_respawn_start_msec = now
	_vfx._flash_overlay_rect.visible = true
	_vfx._flash_overlay_rect.color = Color(
		_vfx.DEFAULT_FLASH_BRIGHTNESS,
		_vfx.DEFAULT_FLASH_BRIGHTNESS,
		_vfx.DEFAULT_FLASH_BRIGHTNESS,
		1.0
	)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Applique la couleur flash kill au tick `t` ∈ [0, 1] (0 = début, 1 = fin).
## Gère reduce_flash gris substitute via _flash_kill_use_grey (F-VFX-2).
## Fade-out linéaire alpha 1.0 → 0.0 sur 80 ms wall-clock.
func _apply_flash_kill_color(t: float) -> void:
	var base_brightness: float = _vfx.REDUCE_FLASH_BRIGHTNESS if _flash_kill_use_grey else _vfx.DEFAULT_FLASH_BRIGHTNESS
	var alpha: float = 1.0 - t
	_vfx._flash_overlay_rect.color = Color(base_brightness, base_brightness, base_brightness, alpha)
