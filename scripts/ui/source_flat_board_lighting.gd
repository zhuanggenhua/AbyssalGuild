extends Node
## Linear composition of the existing flat model, NOT a Unity SH/GI reconstruction.
## Bound only after an admitted source board enters its real world. Preserve every
## original material; unsupported or changed runtime contexts restore it verbatim.
const Lit = preload("res://scripts/ui/source_lit_material.gd")
const LIGHT_CODE := """
void light() {
    float cosine = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    vec3 half_sum = LIGHT + VIEW;
    vec3 half_direction = half_sum * inversesqrt(max(1.175494351e-38, dot(half_sum, half_sum)));
    float light_half = clamp(dot(LIGHT, half_direction), 0.0, 1.0);
    float specular_term = 0.04 / (6.0 * max(0.1, light_half * light_half) * 1.00001 * 1.00001);
    vec3 direct = LIGHT_COLOR * ATTENUATION * cosine * (ALBEDO * 0.96 + vec3(specular_term)) / PI;
    // Ambient is unoccluded, direct retains the engine's real shadow attenuation.
    // SPECULAR_LIGHT here is the final-color accumulator, not an extra specular lobe.
    SPECULAR_LIGHT += source_flat_ambient_linear * ALBEDO + direct;
}
"""
const FRAGMENT_CODE := """shader_type spatial;
render_mode cull_back, ambient_light_disabled;
uniform vec4 source_base_color : source_color = vec4(1.0);
uniform vec3 source_flat_ambient_linear = vec3(0.0);
void fragment() {
    ALBEDO = source_base_color.rgb;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}
"""

var records: Array[Dictionary] = []
var _environment: Environment
var _board: WeakRef
var _observed: Array[WeakRef] = []
var _observed_ids: Dictionary = {}
var _shader: Shader

func _ready() -> void:
	get_tree().node_added.connect(_observe_node)
	_observe_tree(get_tree().root)
	RenderingServer.frame_pre_draw.connect(refresh)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(refresh): RenderingServer.frame_pre_draw.disconnect(refresh)
	if get_tree().node_added.is_connected(_observe_node): get_tree().node_added.disconnect(_observe_node)
	clear()

func _observe_tree(node: Node) -> void:
	_observe_node(node)
	for child in node.get_children(): _observe_tree(child)

func _observe_node(node: Node) -> void:
	if not (node is Light3D or node is WorldEnvironment or node is Camera3D or node is ReflectionProbe or node is LightmapGI or node is VoxelGI): return
	var id := node.get_instance_id()
	if _observed_ids.has(id): return
	_observed_ids[id] = true
	_observed.append(weakref(node))

func bind(board: Node3D, environment: Environment) -> void:
	clear()
	if board == null or not board.is_inside_tree() or str(board.get_meta("source_prefab_guid", "")).is_empty(): return
	_board = weakref(board)
	_environment = environment
	_collect(board)
	refresh()

func _collect(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var original: Material = node.get_surface_override_material(surface)
			if not _original_supported(original): continue
			records.append({"mesh": weakref(node), "surface": surface, "original": original, "replacement": null, "mesh_resource": node.mesh, "retired": false})
	for child in node.get_children(): _collect(child)

static func _original_supported(material: Material) -> bool:
	return material is ShaderMaterial and material.shader != null and bool(material.get_meta("source_direct_lit", false)) and material.get_meta("source_board_cull", "") == "back" and material.shader.code == Lit.BOARD_FRAGMENT + Lit.DIRECT_LIGHT_CODE and material.next_pass == null

func clear() -> void:
	for record in records: _restore(record)
	records.clear()
	_environment = null
	_board = null
	_shader = null

func _restore(record: Dictionary) -> void:
	var mesh = record.mesh.get_ref()
	if not is_instance_valid(mesh) or mesh.mesh == null or record.surface >= mesh.mesh.get_surface_count(): return
	# Never overwrite a material another owner replaced after our binding.
	if record.replacement != null and mesh.get_surface_override_material(record.surface) == record.replacement:
		mesh.set_surface_override_material(record.surface, record.original)

func active_count() -> int:
	var result := 0
	for record in records:
		var mesh = record.mesh.get_ref()
		if is_instance_valid(mesh) and mesh.mesh != null and record.surface < mesh.mesh.get_surface_count() and record.replacement != null and mesh.get_surface_override_material(record.surface) == record.replacement: result += 1
	return result

func _context(world: World3D) -> Dictionary:
	var rejected := {}
	var version := Engine.get_version_info()
	if RenderingServer.get_current_rendering_method() != "gl_compatibility" or version.major != 4 or version.minor != 6 or version.patch != 3 or str(version.get("hash", "")) != "7d41c59c457bd5a245092b4e7eb2d833e3b3f8c3": return rejected
	if bool(ProjectSettings.get_setting("rendering/lights_and_shadows/use_physical_light_units", false)) or bool(ProjectSettings.get_setting("rendering/shading/overrides/force_vertex_shading", false)): return rejected
	var environment := _environment
	if environment == null or world.environment != environment: return rejected
	if environment.ambient_light_source not in [Environment.AMBIENT_SOURCE_COLOR, Environment.AMBIENT_SOURCE_DISABLED]: return rejected
	if environment.reflected_light_source != 1 or environment.fog_enabled or environment.volumetric_fog_enabled: return rejected
	if environment.tonemap_mode != Environment.TONE_MAPPER_LINEAR or environment.tonemap_exposure != 1 or environment.adjustment_enabled or environment.glow_enabled: return rejected
	if not is_finite(environment.ambient_light_energy) or environment.ambient_light_energy < 0: return rejected
	for channel in [environment.ambient_light_color.r, environment.ambient_light_color.g, environment.ambient_light_color.b]:
		if not is_finite(channel) or channel < 0 or channel > 1: return rejected
	var lights: Array[Light3D] = []
	var worlds := 0
	var retained: Array[WeakRef] = []
	_observed_ids.clear()
	for reference in _observed:
		var node = reference.get_ref()
		if not is_instance_valid(node): continue
		retained.append(reference)
		_observed_ids[node.get_instance_id()] = true
	_observed = retained
	for reference in _observed:
		var node = reference.get_ref()
		if not node.is_inside_tree(): continue
		var node_world: World3D = node.get_world_3d() if node is Node3D else node.get_viewport().find_world_3d()
		if node_world != world: continue
		if node is Light3D: lights.append(node)
		if node is WorldEnvironment:
			worlds += 1
			if node.environment != environment or node.camera_attributes != null: return rejected
		if node is ReflectionProbe or node is LightmapGI or node is VoxelGI: return rejected
		if node is Camera3D and (node.attributes != null or node.environment != null): return rejected
	if worlds != 1 or lights.size() != 1 or not lights[0] is DirectionalLight3D: return rejected
	var light := lights[0]
	if light.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY or not light.is_visible_in_tree() or light.light_negative or not is_finite(light.light_energy) or light.light_energy <= 0: return rejected
	var ambient := Color.BLACK
	if environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR: ambient = environment.ambient_light_color.srgb_to_linear() * environment.ambient_light_energy
	return {"light": light, "ambient": Vector3(ambient.r, ambient.g, ambient.b)}

func refresh() -> void:
	if records.is_empty(): return
	var board = _board.get_ref() if _board != null else null
	if not is_instance_valid(board) or not board.is_inside_tree() or board.is_queued_for_deletion():
		clear()
		return
	var world: World3D = board.get_world_3d()
	var context := _context(world)
	for record in records:
		var mesh = record.mesh.get_ref()
		if not is_instance_valid(mesh) or not mesh.is_inside_tree() or mesh.mesh == null or record.surface >= mesh.mesh.get_surface_count(): continue
		var current: Material = mesh.get_surface_override_material(record.surface)
		# External ownership changes retire this binding rather than overwriting them.
		if record.retired: continue
		if current != record.original and current != record.replacement:
			record.retired = true
			continue
		if record.replacement != null and (record.replacement.shader == null or record.replacement.shader.code != FRAGMENT_CODE + LIGHT_CODE or record.replacement.next_pass != null):
			_restore(record)
			record.retired = true
			continue
		if context.is_empty() or (mesh != board and not board.is_ancestor_of(mesh)) or mesh.mesh != record.mesh_resource or mesh.get_world_3d() != world or mesh.material_override != null or mesh.material_overlay != null or mesh.transparency != 0 or mesh.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED or not _original_supported(record.original) or (context.light.light_cull_mask & mesh.layers) == 0:
			_restore(record)
			continue
		if _shader == null:
			_shader = Shader.new()
			_shader.code = FRAGMENT_CODE + LIGHT_CODE
		if record.replacement == null:
			record.replacement = record.original.duplicate() as ShaderMaterial
			record.replacement.shader = _shader
			record.replacement.set_meta("source_flat_linear_composition", true)
		# Source base-color updates and flat-energy/color changes remain data-driven.
		record.replacement.set_shader_parameter("source_base_color", record.original.get_shader_parameter("source_base_color"))
		record.replacement.set_shader_parameter("source_flat_ambient_linear", context.ambient)
		if current != record.replacement: mesh.set_surface_override_material(record.surface, record.replacement)
