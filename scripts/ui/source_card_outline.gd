extends MeshInstance3D
## Same mesh, no shadow, and unscaled-time sweep from the source Highlight path.
const SHADER = preload("res://scripts/ui/shaders/card_outline.gdshader")

static func create(body: MeshInstance3D, metadata: Dictionary):
	if metadata.get("shader_source_path") != "Shaders/CardOutline.shadergraph" or not body.has_meta("mesh_to_card"):
		return null
	var properties: Dictionary = metadata.get("properties", {})
	for key in ["_OutlineSize", "_OutlineColor", "_MinAlpha", "_RotationSpeed"]:
		if not properties.has(key): return null
	var result = new()
	result.mesh = body.mesh
	result.transform = body.transform
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var conversion: Transform3D = body.get_meta("mesh_to_card")
	material.set_shader_parameter("mesh_to_card", conversion)
	material.set_shader_parameter("card_to_mesh", conversion.affine_inverse())
	material.set_shader_parameter("outline_size", float(properties._OutlineSize))
	var color: Dictionary = properties._OutlineColor
	material.set_shader_parameter("outline_color", Color(color.r, color.g, color.b, color.a))
	material.set_shader_parameter("min_alpha", float(properties._MinAlpha))
	material.set_shader_parameter("rotation_speed", float(properties._RotationSpeed))
	result.material_override = material
	result.process_mode = Node.PROCESS_MODE_ALWAYS
	return result

func _process(_delta: float) -> void:
	material_override.set_shader_parameter("unscaled_time", Time.get_ticks_msec() / 1000.0)

static func alpha_at(source_uv: Vector2, seconds: float, speed: float, minimum: float, opacity: float) -> float:
	# Numeric reference for the graph's atan2/add/divide/fraction/lerp branch.
	var centered := source_uv - Vector2(0.5, 0.5)
	var phase := fposmod((atan2(centered.y, centered.x) + seconds * speed) / 6.283180236816406, 1.0)
	return opacity * lerpf(1.0, minimum, phase)
