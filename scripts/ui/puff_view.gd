extends Node3D
## Native horizontal planes. Standard-alpha multiplication is an approximation,
## not a recreation of Unity's unresolved built-in particle shader.
const Simulation = preload("res://scripts/ui/puff_simulation.gd")
var simulation = Simulation.new()
var particles: Array[MeshInstance3D] = []
var source_texture: Texture2D
var _material_tint: Color = Color.WHITE

func configure(assets, record: Dictionary, presentation_seed: int) -> bool:
	if is_queued_for_deletion(): return false
	_clear()
	if not Simulation.is_supported(record) or int(record.get("renderer_mode",-1)) != 2:
		return false
	var renderer: Dictionary = record.get("renderer_fields",{})
	if int(renderer.get("m_CastShadows",-1)) != 0 or int(renderer.get("m_ReceiveShadows",-1)) != 0:
		return false
	for field in ["m_Pivot","m_Flip"]:
		var vector: Dictionary = renderer.get(field,{})
		if vector.size()!=3 or not Simulation._vector(vector,["x","y","z"]): return false
		if Vector3(float(vector.x),float(vector.y),float(vector.z)) != Vector3.ZERO: return false
	var references: Array = record.get("materials",[])
	if references.size()!=1: return false
	var material: Dictionary = assets.manifest.get("materials",{}).get(str(references[0].get("guid","")),{})
	var color: Dictionary = material.get("colors",{}).get("_Color",{})
	if not Simulation._vector(color,["r","g","b","a"]): return false
	_material_tint = assets.source_color(color)
	var texture_data: Dictionary = material.get("textures",{}).get("_MainTex",{})
	var uv_scale: Dictionary = texture_data.get("m_Scale",{})
	var uv_offset: Dictionary = texture_data.get("m_Offset",{})
	if not Simulation._vector(uv_scale,["x","y"]) or not Simulation._vector(uv_offset,["x","y"]): return false
	if Vector2(float(uv_scale.x),float(uv_scale.y)) != Vector2.ONE or Vector2(float(uv_offset.x),float(uv_offset.y)) != Vector2.ZERO:
		return false
	var texture_guid: String = str(texture_data.get("m_Texture",{}).get("guid",""))
	var importer: Dictionary = assets.manifest.get("assets",{}).get(texture_guid,{}).get("texture_importer",{})
	if int(importer.get("filter_mode",-1)) not in [0,1] or int(importer.get("wrap_u",-1)) not in [0,1]: return false
	if importer.get("wrap_u") != importer.get("wrap_v") or int(importer.get("mipmaps",-1)) not in [0,1]: return false
	source_texture = assets.texture(texture_guid)
	if source_texture == null: return false
	if not simulation.configure(record,presentation_seed):
		source_texture = null
		return false
	name = "NativePuff"
	set_meta("source_prefab_guid",str(record.get("prefab_guid","")))
	set_meta("source_material_guid",str(references[0].get("guid","")))
	set_meta("material_equivalence","native_standard_alpha_approximation")
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	for index in int(record.burst_count):
		var particle := MeshInstance3D.new()
		particle.name = "Particle%d" % index
		particle.mesh = mesh
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var surface := StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		surface.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		surface.no_depth_test = false
		surface.cull_mode = BaseMaterial3D.CULL_DISABLED
		surface.albedo_texture = source_texture
		surface.texture_repeat = int(importer.wrap_u)==0
		if int(importer.filter_mode)==0:
			surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if int(importer.mipmaps)==1 else BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if int(importer.mipmaps)==1 else BaseMaterial3D.TEXTURE_FILTER_LINEAR
		particle.material_override = surface
		add_child(particle)
		particles.append(particle)
	_sync_states()
	return true

func advance(unscaled_delta: float, scaled_delta: float) -> bool:
	if is_queued_for_deletion() or not simulation.advance(unscaled_delta,scaled_delta):
		return false
	_sync_states()
	if simulation.is_expired():
		visible = false
		queue_free()
	return true

func is_expired() -> bool:
	return simulation.is_expired()

func _sync_states() -> void:
	for particle in particles: particle.visible=false
	for state in simulation.sample_states():
		var particle: MeshInstance3D = particles[int(state.index)]
		particle.position = state.position
		# Avoid a singular zero-scale basis at the source curve's zero endpoint.
		var size: float = float(state.size)
		particle.visible = size > 0 and state.color.a > 0
		if size > 0: particle.scale = Vector3(size,1,size)
		particle.material_override.albedo_color = state.color * _material_tint

func _clear() -> void:
	for particle in particles:
		remove_child(particle)
		particle.free()
	particles.clear()
	simulation.reset()
	source_texture = null
	_material_tint = Color.WHITE
	visible = true
