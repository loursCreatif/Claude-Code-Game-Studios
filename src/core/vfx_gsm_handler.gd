## VFXGSMHandler — Domaine GSM visibility gating + accessibility settings pull.
## Possédé et instancié par VFXSystem (composition). Reçoit une référence
## injectée au Node VFXSystem pour modifier _is_active et déléguer freeze/restore
## au VFXCombatHandler.
## PAS un autoload — pas de class_name (référencé via preload binding local dans
## vfx_system.gd pour bypass class cache CI gdUnit4-action).
## ADR-0007 D-9 (pull pattern boot) + ADR-0015 D-1 (accessibility pull Option A).
## Outbound-zero (R-VFX-14) : aucun emit_signal ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const VFXGSMHandler := preload(...)`
# dans vfx_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à VFXSystem (Node) — pour _is_active, _combat handler, etc.
## Injectée dans VFXSystem._ready() après instanciation.
var _vfx: Node = null


# ---------------------------------------------------------------------------
# State — accessibility
# ---------------------------------------------------------------------------

## Reduce motion actif (pull depuis AccessibilityService story-005 — défaut false).
var _reduce_motion: bool = false

## Reduce flash actif (pull depuis AccessibilityService story-005 — défaut false).
var _reduce_flash: bool = false

## Multiplicateur flash brightness (story-005 — défaut 1.0).
var _flash_mult: float = 1.0


# ---------------------------------------------------------------------------
# Injectable refs (test pattern)
# ---------------------------------------------------------------------------

## Référence injectable AccessibilityService — set par connect_accessibility_signals.
## null = fallback sur `/root/AccessibilityService` en prod.
var _accessibility_service_ref: Node = null

## Référence injectable GSM — set par connect_gsm_signals.
## null = fallback sur `/root/GameStateManager` autoload prod.
var _gsm_ref: Node = null


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## Handler state_changed (GSM) — story-006.
## R-VFX-12 + ADR-0007 D-2 : freeze pool + trail + flash overlay si MENU/PAUSED/BOSS_DEFEATED ;
## restore process_mode si retour PLAYING (AC-VFX-17).
func _on_state_changed(new_state: int = 0) -> void:
	_apply_visibility_for_state(new_state)


## Handler settings_changed (AccessibilityService) — story-005.
## Re-pull live + apply update mid-swing si reduce_motion changé (R-VFX-11 + AC-NEW-07).
## Note : flash en cours non rétroactif (durée 80 ms trop courte) — AC-VFX-20 next flash.
func _on_accessibility_settings_changed() -> void:
	var prev_reduce_motion: bool = _reduce_motion
	_pull_accessibility_settings()

	# AC-NEW-07 — apply live update mid-swing si reduce_motion changé
	if _vfx._combat._trail_active and prev_reduce_motion != _reduce_motion:
		var trail_color: Color = _vfx.TRAIL_COLOR
		trail_color.a = _vfx.KATANA_TRAIL_OPACITY_MAX * (_vfx.REDUCE_MOTION_TRAIL_MULT if _reduce_motion else 1.0)
		_vfx._combat._set_trail_color(trail_color)


# ---------------------------------------------------------------------------
# Public connection helpers (test injection pattern)
# ---------------------------------------------------------------------------

## Injecte un mock GSM et connecte son signal.
## Story-006 : store _gsm_ref + re-pull immédiat post-injection (ADR-0007 D-9).
func connect_gsm_signals(gsm: Node) -> void:
	if gsm == null:
		return
	_gsm_ref = gsm
	if gsm.has_signal(&"state_changed") and not gsm.state_changed.is_connected(_on_state_changed):
		gsm.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)
	_pull_initial_gsm_state()  # re-pull immédiat post-injection


## Injecte un mock AccessibilityService et connecte son signal.
## Story-005 : set _accessibility_service_ref pour pull + re-pull immédiat post-injection.
func connect_accessibility_signals(accessibility: Node) -> void:
	if accessibility == null:
		return
	_accessibility_service_ref = accessibility
	if accessibility.has_signal(&"settings_changed") and not accessibility.settings_changed.is_connected(_on_accessibility_settings_changed):
		accessibility.settings_changed.connect(_on_accessibility_settings_changed, CONNECT_DEFERRED)
	_pull_accessibility_settings()  # re-pull immédiat post-injection


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Pull les settings AccessibilityService (R-VFX-5/11/15 + ADR-0015 D-1 Option A).
## Guard EC-VFX-08 : defaults safe si Service non initialisé OU mock absent.
## Lit depuis _accessibility_service_ref (test mock) OU autoload global fallback.
func _pull_accessibility_settings() -> void:
	var svc: Node = _accessibility_service_ref
	if svc == null:
		svc = _vfx.get_node_or_null("/root/AccessibilityService")
	if not is_instance_valid(svc):
		# Defaults safe — corrigés par settings_changed live dès Service prêt
		_reduce_flash = false
		_flash_mult = 1.0
		_reduce_motion = false
		push_warning("VFX: AccessibilityService not yet initialized at pull — using defaults")
		return

	# Pull via methods canoniques (real service + mock délègue properties)
	if svc.has_method(&"is_reduce_flash_enabled"):
		_reduce_flash = svc.is_reduce_flash_enabled()
	if svc.has_method(&"get_flash_mult"):
		_flash_mult = svc.get_flash_mult()
	if svc.has_method(&"is_reduce_motion_enabled"):
		_reduce_motion = svc.is_reduce_motion_enabled()


## Applique la matrice visibilité ADR-0007 D-2 :
## PLAYING + RESPAWNING → VFX actif ; MENU + PAUSED + BOSS_DEFEATED → freeze.
## Détecte transition (was_active != _is_active) pour appel freeze/restore.
func _apply_visibility_for_state(state: int) -> void:
	var was_active: bool = _vfx._is_active
	_vfx._is_active = (state == _vfx.STATE_PLAYING or state == _vfx.STATE_RESPAWNING)
	if not _vfx._is_active:
		_freeze_vfx()
	elif not was_active:  # transition false → true (PLAYING/RESPAWNING return)
		_restore_vfx()


## Freeze pool VFX (R-VFX-12 + AC-VFX-15/16).
## Délègue freeze pool/trail/flash au combat handler.
## Decals : restent visibles (mémoire physique salle Pillar 2 — reset par respawn story-003 only).
func _freeze_vfx() -> void:
	_vfx._combat.freeze_combat_state()


## Restore pool VFX au retour PLAYING (R-VFX-12 + AC-VFX-17).
func _restore_vfx() -> void:
	_vfx._combat.restore_combat_state()


## Pull initial GSM state au boot (ADR-0007 D-9 pull pattern).
## Guard EC : si GSM non initialisé OU pas de get_current_state, default PLAYING.
func _pull_initial_gsm_state() -> void:
	var svc: Node = _gsm_ref
	if svc == null:
		svc = _vfx.get_node_or_null("/root/GameStateManager")
	if not is_instance_valid(svc):
		# GSM autoload Not Started — default PLAYING (mitigation MVP)
		_vfx._is_active = true
		push_warning("VFX: GSM not available at pull — defaulting _is_active = true (PLAYING assumption)")
		return

	if svc.has_method(&"get_current_state"):
		var initial_state: int = svc.get_current_state()
		_apply_visibility_for_state(initial_state)
	else:
		_vfx._is_active = true  # default safe
