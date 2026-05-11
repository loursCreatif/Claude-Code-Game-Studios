## VFXCombatHandler — Domaine combat : trail katana + orchestration blood/decal/flash.
## Possédé et instancié par VFXSystem (composition). Reçoit une référence
## injectée au Node VFXSystem pour accéder aux pools et à l'état partagé.
## PAS un autoload — pas de class_name (référencé via preload binding
## local dans vfx_system.gd pour bypass class cache CI gdUnit4-action).
## ADR-0009 D-3 (wall-clock fades) + D-4 (CONNECT_DEFERRED).
## Pool exclusive (AC-VFX-05) : aucun GPUParticles3D/Decal/MeshInstance3D.new() ici.
## Blood/decal délégué à VFXBloodDecalHandler, flash à VFXFlashHandler.

extends RefCounted

const VFXFlashHandler := preload("res://src/core/vfx_flash_handler.gd")
const VFXBloodDecalHandler := preload("res://src/core/vfx_blood_decal_handler.gd")

# NOTE : pas de `class_name` — référencé via `const VFXCombatHandler := preload(...)`
# dans vfx_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à VFXSystem (Node) — pour accès pools, overlay, _is_active.
## Injectée dans VFXSystem._ready() après instanciation.
var _vfx: Node = null


# ---------------------------------------------------------------------------
# Sub-handlers (composition)
# ---------------------------------------------------------------------------

## Handler flash kill + flash respawn (wall-clock, outbound-zero).
var _flash: VFXFlashHandler = null

## Handler blood spurt + decal projection.
var _blood_decal: VFXBloodDecalHandler = null


# ---------------------------------------------------------------------------
# Pool references (refs vers pools alloués par VFXSystem)
# ---------------------------------------------------------------------------

## Pool GPUParticles3D (référence partagée depuis VFXSystem._blood_particle_pool).
var _blood_particle_pool: Array[GPUParticles3D] = []

## Pool Decal (référence partagée depuis VFXSystem._decal_pool).
var _decal_pool: Array[Decal] = []

## Trail mesh (référence partagée depuis VFXSystem._trail_mesh).
var _trail_mesh: MeshInstance3D = null

## Trail material (référence partagée depuis VFXSystem._trail_material).
var _trail_material: StandardMaterial3D = null

## Flash overlay ColorRect (référence partagée depuis VFXSystem._flash_overlay_rect).
var _flash_overlay_rect: ColorRect = null

## Blood shader material partagé (référence depuis VFXSystem._blood_shader_material).
var _blood_shader_material: ShaderMaterial = null


# ---------------------------------------------------------------------------
# State — trail katana
# ---------------------------------------------------------------------------

## True quand le trail katana est actif (swing en cours OU fade-out).
var _trail_active: bool = false

## Timestamp de démarrage du fade-out trail (0 = pas de fade-out en cours).
var _trail_fade_start_msec: int = 0

## Direction de l'attaque mémorisée depuis swing_started.
var _swing_aim_forward: Vector3 = Vector3.FORWARD

## Dernier cone effectif calculé (testable — AC-VFX-12). Proxy vers _blood_decal.
var _last_effective_cone_deg: float:
	get: return _blood_decal._last_effective_cone_deg
	set(v): _blood_decal._last_effective_cone_deg = v


# ---------------------------------------------------------------------------
# Proxy properties — blood/decal state (compatibilité tests VFXSystem)
# ---------------------------------------------------------------------------

var _blood_idx: int:
	get: return _blood_decal._blood_idx
	set(v): _blood_decal._blood_idx = v

var _decal_write_head: int:
	get: return _blood_decal._decal_write_head
	set(v): _blood_decal._decal_write_head = v

var _room_decal_count: int:
	get: return _blood_decal._room_decal_count
	set(v): _blood_decal._room_decal_count = v


# ---------------------------------------------------------------------------
# Proxy properties — flash state (compatibilité tests VFXSystem)
# ---------------------------------------------------------------------------

var _flash_kill_active: bool:
	get: return _flash._flash_kill_active
	set(v): _flash._flash_kill_active = v

var _flash_kill_use_grey: bool:
	get: return _flash._flash_kill_use_grey
	set(v): _flash._flash_kill_use_grey = v

var _flash_respawn_active: bool:
	get: return _flash._flash_respawn_active
	set(v): _flash._flash_respawn_active = v

var _flash_last_msec: int:
	get: return _flash._flash_last_msec
	set(v): _flash._flash_last_msec = v


# ---------------------------------------------------------------------------
# Initialisation — appelée après injection _vfx
# ---------------------------------------------------------------------------

## Instancie et injecte les sub-handlers. Doit être appelé après _vfx est set.
func init_sub_handlers() -> void:
	_flash = VFXFlashHandler.new()
	_flash._vfx = _vfx

	_blood_decal = VFXBloodDecalHandler.new()
	_blood_decal._vfx = _vfx
	_blood_decal._blood_particle_pool = _blood_particle_pool
	_blood_decal._decal_pool = _decal_pool
	_blood_decal._blood_shader_material = _blood_shader_material


# ---------------------------------------------------------------------------
# Tick methods — appelés depuis VFXSystem._physics_process
# ---------------------------------------------------------------------------

## Tick fade-out trail katana exponentiel 100 ms (R-VFX-7 + AC-VFX-14).
## Calcul wall-clock via _vfx._get_time_msec pour résistance Engine.time_scale.
func tick_trail_fade() -> void:
	var elapsed_ms: int = _vfx._get_time_msec.call() - _trail_fade_start_msec
	if elapsed_ms >= _vfx.KATANA_TRAIL_FADE_MS:
		_trail_mesh.visible = false
		_trail_active = false
		_trail_fade_start_msec = 0
	else:
		var t: float = float(elapsed_ms) / float(_vfx.KATANA_TRAIL_FADE_MS)
		var opacity: float = _vfx.KATANA_TRAIL_OPACITY_MAX * exp(-3.0 * t)
		var color: Color = _vfx.TRAIL_COLOR
		color.a = opacity
		_set_trail_color(color)


## Tick flash kill — délégué à VFXFlashHandler.
func tick_flash_kill() -> void:
	_flash.tick_flash_kill()


## Tick flash respawn — délégué à VFXFlashHandler.
func tick_flash_respawn() -> void:
	_flash.tick_flash_respawn()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## Handler swing_started (Combat) — story-002.
## Active le trail katana ImmediateMesh avec opacité max (R-VFX-7 + AC-VFX-13).
func _on_swing_started(direction: Vector3 = Vector3.ZERO) -> void:
	if not _vfx._is_active:
		return
	_swing_aim_forward = direction.normalized()
	_trail_active = true
	_trail_fade_start_msec = 0
	_trail_mesh.visible = true
	var trail_color: Color = _vfx.TRAIL_COLOR
	trail_color.a = _vfx.KATANA_TRAIL_OPACITY_MAX * (_vfx.REDUCE_MOTION_TRAIL_MULT if _vfx._reduce_motion else 1.0)
	_set_trail_color(trail_color)


## Handler swing_ended (Combat) — story-002.
## Déclenche le fade-out exponentiel 100 ms du trail (R-VFX-7 + AC-VFX-14).
## story-006 : ignoré si frozen — trail déjà cleared par _freeze_vfx.
func _on_swing_ended() -> void:
	if not _vfx._is_active or not _trail_active:
		return
	_trail_fade_start_msec = _vfx._get_time_msec.call()


## Handler multi_kill (Combat) — no-op MVP.
## R-VFX-10 : burst additif déjà couvert par enemy_killed séquentiels.
func _on_multi_kill(_count: int = 0) -> void:
	pass


## Handler enemy_killed (Enemy) — story-002.
## CRITIQUE ADR-0006 D-3 / R-AUD-7 : utiliser `position` parameter EXCLUSIVEMENT.
## Jamais `enemy.global_position` — enemy peut être queue_free post-DEFERRED.
func _on_enemy_killed(_enemy: Node = null, position: Vector3 = Vector3.ZERO) -> void:
	if not _vfx._is_active:
		return
	_blood_decal.spawn_blood_spurt(position)
	_blood_decal.spawn_decal_on_surface(position)
	_flash.trigger_flash_kill()


## Handler died (Camera) — story-004.
## Déclenche le flash kill 80 ms wall-clock + WCAG 333 ms guard (R-VFX-5 + AC-VFX-06).
func _on_died() -> void:
	if not _vfx._is_active:
		return
	_flash.trigger_flash_kill()


## Handler respawned (Camera) — story-002+004.
## AC-VFX-22 : reset complet pool blood + trail + decals dans le même frame.
## Story-004 : ajoute trigger flash respawn 50 ms (R-VFX-15 + AC-VFX-09).
func _on_respawned(_position: Vector3 = Vector3.ZERO) -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.restart()
		p.emitting = false
	_trail_mesh.visible = false
	_trail_active = false
	_trail_fade_start_msec = 0
	for d: Decal in _decal_pool:
		d.visible = false
	_blood_decal._room_decal_count = 0
	_blood_decal._decal_write_head = 0

	# NEW story-004 — Trigger flash respawn (skip si reduce_flash via R-VFX-15 guard)
	_flash.trigger_flash_respawn()


# ---------------------------------------------------------------------------
# Private helpers — trail
# ---------------------------------------------------------------------------

## Applique une couleur (avec alpha) sur le trail mesh via le material pré-alloué.
## _trail_material (StandardMaterial3D) pré-alloué dans VFXSystem._setup_vfx_pool (R-VFX-2).
func _set_trail_color(color: Color) -> void:
	_trail_material.albedo_color = color


# ---------------------------------------------------------------------------
# Freeze / restore helpers (appelés depuis VFXGSMHandler)
# ---------------------------------------------------------------------------

## Freeze pool + trail + flash (R-VFX-12 + AC-VFX-15/16).
func freeze_combat_state() -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.emitting = false
		p.process_mode = Node.PROCESS_MODE_DISABLED

	_trail_mesh.visible = false
	_trail_active = false
	_trail_fade_start_msec = 0

	_flash_overlay_rect.visible = false
	_flash._flash_kill_active = false
	_flash._flash_respawn_active = false
	_flash._flash_kill_start_msec = 0
	_flash._flash_respawn_start_msec = 0


## Restore pool process_mode au retour PLAYING (R-VFX-12 + AC-VFX-17).
func restore_combat_state() -> void:
	for p: GPUParticles3D in _blood_particle_pool:
		p.process_mode = Node.PROCESS_MODE_INHERIT

	_trail_mesh.visible = false
	_trail_active = false
	_flash_overlay_rect.visible = false
