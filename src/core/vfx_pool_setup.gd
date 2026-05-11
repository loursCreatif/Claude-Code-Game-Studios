## VFXPoolSetup — Construction et initialisation des pools VFX au boot.
## Possédé et instancié par VFXSystem (composition). Centralise les 4 fonctions
## de setup qui allouent les GPUParticles3D, Decals, MeshInstance3D et le
## CanvasLayer flash overlay — pool exclusive (AC-VFX-05).
## PAS un autoload — pas de class_name (référencé via preload binding
## local dans vfx_system.gd).
## Appelé UNE SEULE FOIS depuis VFXSystem._ready() — pas de hot path ici.
## Outbound-zero (R-VFX-14) : aucun emit_signal ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const VFXPoolSetup := preload(...)`
# dans vfx_system.gd.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à VFXSystem (Node) — pour constantes de taille pool,
## couleurs, shaders et add_child des nœuds racines.
## Injectée dans VFXSystem._ready() avant appel à build_pools().
var _vfx: Node = null


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

## Construit et attache tous les pools au Node VFXSystem.
## Doit être appelé après que _vfx est injecté.
## Retourne un Dictionary avec les références créées pour injection dans _vfx.
func build_pools() -> Dictionary:
	var blood_shader_material: ShaderMaterial = _create_blood_shader_material()

	var pool_root: Node3D = Node3D.new()
	pool_root.name = &"VFXPool3D"
	_vfx.add_child(pool_root)

	var blood_particle_pool: Array[GPUParticles3D] = []
	var decal_pool: Array[Decal] = []
	var trail_mesh: MeshInstance3D = null
	var trail_material: StandardMaterial3D = null

	_build_blood_pool(pool_root, blood_shader_material, blood_particle_pool)
	_build_decal_pool(pool_root, decal_pool)
	trail_material = _build_trail_mesh(pool_root)
	trail_mesh = pool_root.get_node(^"KatanaTrailMesh") as MeshInstance3D

	var flash_overlay_rect: ColorRect = _build_flash_overlay()

	return {
		"blood_particle_pool": blood_particle_pool,
		"decal_pool": decal_pool,
		"trail_mesh": trail_mesh,
		"trail_material": trail_material,
		"flash_overlay_rect": flash_overlay_rect,
		"blood_shader_material": blood_shader_material,
	}


# ---------------------------------------------------------------------------
# Private builders — pool 3D
# ---------------------------------------------------------------------------

func _build_blood_pool(
	pool_root: Node3D,
	blood_shader_material: ShaderMaterial,
	out_pool: Array[GPUParticles3D]
) -> void:
	for _i: int in range(_vfx.BLOOD_PARTICLE_POOL_SIZE):
		var p: GPUParticles3D = GPUParticles3D.new()  # lint-vfx-pool-ok: pool boot délégué depuis VFXSystem._ready() exclusivement
		p.emitting = false
		p.one_shot = true
		p.amount = 6
		p.lifetime = 0.4
		p.process_material = blood_shader_material
		pool_root.add_child(p)
		out_pool.append(p)


func _build_decal_pool(pool_root: Node3D, out_pool: Array[Decal]) -> void:
	var decal_color: Color = Color(
		_vfx.BLOOD_COLOR.r,
		_vfx.BLOOD_COLOR.g,
		_vfx.BLOOD_COLOR.b,
		0.7
	)
	for _i: int in range(_vfx.DECAL_POOL_SIZE):
		var d: Decal = Decal.new()  # lint-vfx-pool-ok: pool boot délégué depuis VFXSystem._ready() exclusivement
		d.visible = false
		d.modulate = decal_color
		d.size = Vector3(0.6, 0.3, 0.6)
		pool_root.add_child(d)
		out_pool.append(d)


## Construit le trail mesh ImmediateMesh et son material StandardMaterial3D.
## Retourne le StandardMaterial3D (trail_mesh est nommé "KatanaTrailMesh" — récupéré via get_node).
func _build_trail_mesh(pool_root: Node3D) -> StandardMaterial3D:
	var trail_material: StandardMaterial3D = StandardMaterial3D.new()
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.albedo_color = _vfx.TRAIL_COLOR

	var trail_mesh: MeshInstance3D = MeshInstance3D.new()  # lint-vfx-pool-ok: pool boot délégué depuis VFXSystem._ready() exclusivement
	trail_mesh.name = &"KatanaTrailMesh"
	trail_mesh.visible = false
	trail_mesh.mesh = ImmediateMesh.new()
	trail_mesh.material_override = trail_material
	pool_root.add_child(trail_mesh)

	return trail_material


# ---------------------------------------------------------------------------
# Private builders — flash overlay
# ---------------------------------------------------------------------------

func _build_flash_overlay() -> ColorRect:
	var flash_layer: CanvasLayer = CanvasLayer.new()
	flash_layer.name = &"VFXFlashOverlay"
	flash_layer.layer = _vfx.FLASH_OVERLAY_LAYER
	_vfx.add_child(flash_layer)

	var flash_overlay_rect: ColorRect = ColorRect.new()
	flash_overlay_rect.name = &"FlashOverlayRect"
	flash_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay_rect.visible = false
	flash_layer.add_child(flash_overlay_rect)

	return flash_overlay_rect


# ---------------------------------------------------------------------------
# Private — shader material
# ---------------------------------------------------------------------------

func _create_blood_shader_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load("res://assets/shaders/particles_combat_blood.gdshader")
	mat.shader = shader
	mat.set_shader_parameter(&"blood_color", _vfx.BLOOD_COLOR)
	mat.set_shader_parameter(&"spread_deg", _vfx.BLOOD_CONE_ANGLE_DEG)
	return mat
