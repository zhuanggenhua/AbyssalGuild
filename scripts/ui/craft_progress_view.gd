extends Node3D
const ShaderSource = preload("res://scripts/ui/shaders/craft_progress.gdshader")
var bars: Dictionary = {}
var bound_key := ""
var settings: Dictionary = {"size":{"x":.8,"y":.05},"background":{"r":.25,"g":.25,"b":.25,"a":.8},"fill":{"r":1,"g":.7974138,"b":0,"a":1}}
var texture: Texture2D
var canvas_basis := Basis(Vector3.RIGHT,-PI/2)
func bind_source(assets, scene_name: String) -> void:
	if assets == null or not assets.has_method("progress_configuration"): return
	var key := str(assets.get_instance_id()) + scene_name
	if key == bound_key: return
	var record: Dictionary = assets.progress_configuration(scene_name)
	if record.get("image_type", -1) != 3 or record.get("fill_method", -1) != 0 or record.get("fill_origin", -1) != 0 or record.get("world_canvas_chain", []).is_empty(): return
	reset()
	configure(record, assets.texture(str(record.sprite.get("guid", ""))), effective_transform(record.world_canvas_chain).basis)
	bound_key = key
func configure(metadata: Dictionary, sprite: Texture2D, world_canvas: Basis) -> void:
	settings = metadata
	texture = sprite
	canvas_basis = world_canvas
static func color(fields: Dictionary) -> Color:
	return Color(fields.r,fields.g,fields.b,fields.a)
static func reflected(point: Vector3) -> Vector3:
	return Vector3(point.x,point.y,-point.z)
static func effective_transform(chain: Array) -> Transform3D:
	var result := Transform3D.IDENTITY
	for item in chain:
		var q: Dictionary = item.m_LocalRotation
		var p: Dictionary = item.m_LocalPosition
		var s: Dictionary = item.m_LocalScale
		result *= Transform3D(Basis(Quaternion(-float(q.x),-float(q.y),float(q.z),float(q.w))).scaled_local(Vector3(float(s.x),float(s.y),float(s.z))),Vector3(float(p.x),float(p.y),-float(p.z)))
	return result
func sync(descriptors: Dictionary) -> void:
	for id in bars.keys():
		if not descriptors.has(id) or not _valid(descriptors[id]):
			bars[id].root.hide()
			remove_child(bars[id].root)
			bars[id].root.queue_free()
			bars.erase(id)
	for id in descriptors:
		if not _valid(descriptors[id]): continue
		var d: Dictionary = descriptors[id]
		if not bars.has(id):
			var node := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(settings.size.x,settings.size.y)
			node.mesh = quad
			var material := ShaderMaterial.new()
			material.shader = ShaderSource
			if texture == null:
				var white := Image.create(1,1,false,Image.FORMAT_RGBA8)
				white.fill(Color.WHITE)
				texture = ImageTexture.create_from_image(white)
			material.set_shader_parameter("source_sprite",texture)
			material.set_shader_parameter("background",color(settings.background))
			material.set_shader_parameter("fill_color",color(settings.fill))
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			bars[id] = {"root":node}
		var node: MeshInstance3D = bars[id].root
		# Input anchor is already source TargetPosition + source displayOffset.
		var anchor: Vector3 = d.anchor
		if settings.has("offset"):
			# Current descriptor already includes legacy source default; replace, do not double-add.
			anchor += Vector3(settings.offset.x,settings.offset.y,settings.offset.z) - Vector3(0,0,.55)
		node.position = reflected(anchor)
		node.set_meta("progress_ratio",clampf(d.ratio,0,1))
		node.set_meta("paused",bool(d.get("paused",false)))
		node.basis = canvas_basis
		node.material_override.set_shader_parameter("ratio",clampf(d.ratio,0,1))
func reset() -> void: sync({})
static func composite(bg: Color, texel: Color, tint: Color, uv_x: float, ratio: float) -> Color:
	var fg := texel * tint
	if ratio <= 0 or uv_x > clampf(ratio,0,1): fg.a = 0
	var a := fg.a + bg.a * (1-fg.a)
	if a == 0: return Color(0,0,0,0)
	return Color((fg.r*fg.a+bg.r*bg.a*(1-fg.a))/a,(fg.g*fg.a+bg.g*bg.a*(1-fg.a))/a,(fg.b*fg.a+bg.b*bg.a*(1-fg.a))/a,a)

static func _valid(value: Variant) -> bool:
	return value is Dictionary and value.get("anchor") is Vector3 and value.anchor.is_finite() and (value.get("ratio") is float or value.get("ratio") is int) and is_finite(float(value.ratio))
