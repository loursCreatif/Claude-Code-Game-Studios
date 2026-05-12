## VFXBloodDecalHandler — Domaine blood spurt (GPUParticles3D) + decal projection.
## Possédé et instancié par VFXCombatHandler (composition interne).
## Reçoit une référence injectée au Node VFXSystem pour accéder aux pools,
## constantes et raycast world_3d.
## PAS un autoload — pas de class_name (référencé via preload binding
## local dans vfx_combat_handler.gd).
## Pool exclusive (AC-VFX-05) : aucun GPUParticles3D/Decal.new() ici.
## Outbound-zero (R-VFX-14) : aucun emit_signal ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const VFXBloodDecalHandler := preload(...)`
# dans vfx_combat_handler.gd.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à VFXSystem (Node) — pour pools, constantes, get_viewport().
## Injectée par VFXCombatHandler après instanciation.
var _vfx: Node = null


# ---------------------------------------------------------------------------
# Pool references (refs partagées depuis VFXSystem via VFXCombatHandler)
# ---------------------------------------------------------------------------

## Pool GPUParticles3D (référence partagée depuis VFXSystem._blood_particle_pool).
var _blood_particle_pool: Array[GPUParticles3D] = []

## Pool Decal (référence partagée depuis VFXSystem._decal_pool).
var _decal_pool: Array[Decal] = []

## Blood shader material partagé (référence depuis VFXSystem._blood_shader_material).
var _blood_shader_material: ShaderMaterial = null


# ---------------------------------------------------------------------------
# State — blood + decal
# ---------------------------------------------------------------------------

## Index round-robin courant pour le pool particles sang.
var _blood_idx: int = 0

## Write head ring buffer pour le pool decals.
var _decal_write_head: int = 0

## Nombre de decals spawned dans la room courante (LRU guard story-003).
var _room_decal_count: int = 0

## Dernier cone effectif calculé (testable — AC-VFX-12).
var _last_effective_cone_deg: float = 30.0  # miroir BLOOD_CONE_ANGLE_DEG


# ---------------------------------------------------------------------------
# Public methods — appelés depuis VFXCombatHandler
# ---------------------------------------------------------------------------

## Spawn un slot blood spurt depuis le pool round-robin.
## Applique reduce_motion mult sur cone angle (AC-VFX-12).
func spawn_blood_spurt(position: Vector3) -> void:
	var slot: GPUParticles3D = _blood_particle_pool[_blood_idx]
	slot.global_position = position
	slot.emitting = false
	slot.restart()
	slot.emitting = true

	var effective_cone_deg: float = _vfx.BLOOD_CONE_ANGLE_DEG
	if _vfx._reduce_motion:
		effective_cone_deg *= _vfx.REDUCE_MOTION_PARTICLE_ANGLE_MULT
	_last_effective_cone_deg = effective_cone_deg
	# Appliquer effective_cone_deg sur le shader particles partagé avant restart() (AC-VFX-12).
	# Safe sur le ShaderMaterial PARTAGÉ : reduce_motion est un flag global (même valeur
	# pour tous les slots concurrents — pas de variance per-slot). Muté avant restart().
	_blood_shader_material.set_shader_parameter(&"spread_deg", effective_cone_deg)

	_blood_idx = (_blood_idx + 1) % _vfx.BLOOD_PARTICLE_POOL_SIZE


## Projette un decal sur la surface la plus proche via raycast.
## Skip silencieux + push_warning si aucune surface trouvée (EC-VFX-07).
func spawn_decal_on_surface(position: Vector3) -> void:
	var surface_pos: Vector3 = _perform_decal_raycast(position)
	if surface_pos == Vector3.INF:
		push_warning("VFX: no surface found for decal at %s" % position)
		return
	var slot: Decal = _decal_pool[_decal_write_head % _vfx.DECAL_POOL_SIZE]
	slot.global_position = surface_pos
	slot.visible = true
	_decal_write_head += 1
	_room_decal_count = mini(_room_decal_count + 1, _vfx.MAX_DECALS_PER_ROOM)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Raycast vers le sol puis vers les murs pour trouver la surface de projection decal.
## Retourne Vector3.INF si aucune surface trouvée dans DECAL_RAYCAST_MAX_DISTANCE.
func _perform_decal_raycast(from_position: Vector3) -> Vector3:
	var viewport: Viewport = _vfx.get_viewport()
	if viewport == null:
		return Vector3.INF
	var world: World3D = viewport.world_3d
	if world == null:
		return Vector3.INF
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return Vector3.INF

	# Priorité : sol (Vector3.DOWN)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_position,
		from_position + Vector3.DOWN * _vfx.DECAL_RAYCAST_MAX_DISTANCE
	)
	var result: Dictionary = space_state.intersect_ray(query)

	# Fallback : murs (4 directions cardinales) — itère constante pré-allouée (R-VFX-2)
	if result.is_empty():
		for dir: Vector3 in _vfx._RAYCAST_FALLBACK_DIRS:
			query = PhysicsRayQueryParameters3D.create(
				from_position,
				from_position + dir * _vfx.DECAL_RAYCAST_MAX_DISTANCE
			)
			result = space_state.intersect_ray(query)
			if not result.is_empty():
				break

	if result.is_empty():
		return Vector3.INF

	return result["position"] as Vector3
