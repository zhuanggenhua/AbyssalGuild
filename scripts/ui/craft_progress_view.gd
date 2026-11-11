extends Node3D
## Source task ratio/stack anchor; generated native bars, not Unity Image sprites.
## No local clock: paused progress remains visible and exactly unchanged.
const BAR_SIZE = Vector2(0.8, 0.05)
const SURFACE_LIFT = 0.08 # Native card view's 0.06 baseline plus clearance, not model Y.
var bars: Dictionary = {}

func sync(descriptors: Dictionary) -> void:
	for id in bars.keys():
		if not descriptors.has(id) or not _valid(descriptors[id]):
			_remove_bar(id)
	for id in descriptors:
		if not _valid(descriptors[id]): continue
		var descriptor: Dictionary = descriptors[id]
		if not bars.has(id): bars[id] = _create_bar(id)
		var record: Dictionary = bars[id]
		var source: Vector3 = descriptor.anchor
		record.root.position = Vector3(source.x, source.y + SURFACE_LIFT, -source.z)
		var ratio: float = clampf(float(descriptor.ratio), 0, 1)
		record.fill.visible = ratio > 0
		record.fill.scale.x = maxf(ratio, 0.00001)
		record.fill.position.x = BAR_SIZE.x * (ratio - 1.0) / 2.0
		record.root.set_meta("progress_ratio", ratio)
		record.root.set_meta("paused", bool(descriptor.get("paused", false)))

func reset() -> void:
	for id in bars.keys(): _remove_bar(id)

func _remove_bar(id) -> void:
	var node: Node3D = bars[id].root
	node.hide()
	remove_child(node)
	node.queue_free()
	bars.erase(id)

func _create_bar(id) -> Dictionary:
	var node := Node3D.new()
	node.name = "CraftProgress_%s" % str(id)
	add_child(node)
	var background := _rectangle(Color(0.25, 0.25, 0.25, 0.8))
	node.add_child(background)
	var fill := _rectangle(Color(1, 0.7974138, 0, 1))
	fill.position.y = 0.002
	node.add_child(fill)
	return {"root": node, "background": background, "fill": fill}

static func _rectangle(color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = BAR_SIZE
	result.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result

static func _valid(value: Variant) -> bool:
	return value is Dictionary and value.get("anchor") is Vector3 and value.anchor.is_finite() and (value.get("ratio") is float or value.get("ratio") is int) and is_finite(float(value.ratio))
