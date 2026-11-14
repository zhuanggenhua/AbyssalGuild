extends RefCounted
## Bounded URP 17.5 metallic-workflow direct light, not a scene color correction.
## Unknown graphs/pipelines retain the previous fallback and are not parity claims.
# Locked a11a89 SimpleLit graph bytes. Card contract/shader remains unchanged.
const BOARD_GRAPH_SHA256 := "ecac38c65d483b39fdb2d6032cfbb0bad6d3d856b5183ea657da8c455a1ce0fe"
const DIRECT_LIGHT_CODE := """

void light() {
    float cosine = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    vec3 half_sum = LIGHT + VIEW;
    vec3 half_direction = half_sum * inversesqrt(max(1.175494351e-38, dot(half_sum, half_sum)));
    float light_half = clamp(dot(LIGHT, half_direction), 0.0, 1.0);
    float specular_term = 0.04 / (6.0 * max(0.1, light_half * light_half) * 1.00001 * 1.00001);
    DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cosine * (0.96 / PI);
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * cosine * (specular_term / PI);
}
"""
const BOARD_FRAGMENT := """shader_type spatial;
render_mode cull_back;
uniform vec4 source_base_color : source_color = vec4(1.0);
void fragment() {
    ALBEDO = source_base_color.rgb;
    ROUGHNESS = 1.0;
    METALLIC = 0.0;
}
"""
static var _board_shader: Shader
static var _card_shaders: Dictionary = {}

static func admission(source: Dictionary, manifest: Dictionary, pipeline: Dictionary, renderer: String) -> bool:
	if renderer != "gl_compatibility" or bool(ProjectSettings.get_setting("rendering/lights_and_shadows/use_physical_light_units", false)):
		return false
	var path: String = str(source.get("shader_source_path", ""))
	if path not in ["Shaders/Card.shadergraph", "Shaders/SimpleLit.shadergraph"]:
		return false
	if not source.get("keywords") is Array or not source.keywords.is_empty():
		return false
	var contract = source.get("source_lit")
	if not contract is Dictionary:
		return false
	var required := {"schema_version":2, "geometry":"unmodified_object_vertices_tangent_normal", "target":"universal_lit", "workflow":"metallic", "metallic":0, "smoothness":0, "opaque":true, "double_sided":true, "clearcoat":false, "material_override":false}
	if path == "Shaders/SimpleLit.shadergraph":
		required.merge({"schema_version":3,"double_sided":false,"render_face":2,"cull_mode":"back","normal_policy":"inverse_transpose_no_face_flip"}, true)
	for key in required:
		if not contract.has(key):
			return false
		# JSON numbers may arrive as INT or FLOAT, never collections/bools.
		if typeof(required[key]) == TYPE_INT:
			if not _finite_number(contract[key]): return false
		elif typeof(contract[key]) != typeof(required[key]):
			return false
		if contract[key] != required[key]:
			return false
	var digest: String = str(contract.get("graph_sha256", ""))
	if path == "Shaders/SimpleLit.shadergraph" and digest != BOARD_GRAPH_SHA256: return false
	if digest.length() != 64 or not manifest.get("inputs") is Dictionary or str(manifest.inputs.get(path, "")) != digest:
		return false
	var execution = pipeline.get("execution")
	if not execution is Dictionary or str(execution.get("mode", "")) != "render_graph" or str(execution.get("rule", "")) != "unity_6000_5_builtin_urp_17_5":
		return false
	var qualities = pipeline.get("qualities")
	var selected = pipeline.get("selected_quality")
	if not qualities is Array or not _finite_number(selected):
		return false
	if selected < 0 or selected >= qualities.size() or selected != int(selected):
		return false
	if not qualities[int(selected)] is Dictionary:
		return false
	var guid: String = str(qualities[int(selected)].get("pipeline_guid", ""))
	if guid.is_empty(): guid = str(pipeline.get("graphics_pipeline_guid", ""))
	if guid.is_empty() or not pipeline.get("pipelines") is Dictionary:
		return false
	var selected_pipeline = pipeline.pipelines.get(guid)
	return selected_pipeline is Dictionary and str(selected_pipeline.get("schema", "")) == "urp_renderer_list"

static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func supports(assets, source: Dictionary) -> bool:
	return admission(source, assets.manifest, assets.render_pipeline, RenderingServer.get_current_rendering_method())

static func board_material(assets, source: Dictionary) -> ShaderMaterial:
	if source.get("shader_source_path", "") != "Shaders/SimpleLit.shadergraph" or not supports(assets, source):
		return null
	if not source.get("colors") is Dictionary or not source.colors.get("_Color") is Dictionary:
		return null
	if _board_shader == null:
		_board_shader = Shader.new()
		_board_shader.code = BOARD_FRAGMENT + DIRECT_LIGHT_CODE
	var material := ShaderMaterial.new()
	material.shader = _board_shader
	material.resource_name = str(source.get("name", "SourceLitBoard"))
	# Keep authored color unchanged. Conversion is done by source_color uniforms.
	material.set_shader_parameter("source_base_color", assets.source_color(source.colors._Color))
	material.set_meta("source_direct_lit", true)
	material.set_meta("source_board_cull", "back")
	return material

static func card_shader(assets, source: Dictionary, fallback: Shader) -> Shader:
	if source.get("shader_source_path", "") != "Shaders/Card.shadergraph" or not supports(assets, source):
		return fallback
	# The existing texture, overlay, flash and emission fragment is not rewritten.
	if not _card_shaders.has(fallback.code):
		var shader := Shader.new()
		shader.code = fallback.code + DIRECT_LIGHT_CODE
		_card_shaders[fallback.code] = shader
	return _card_shaders[fallback.code]
