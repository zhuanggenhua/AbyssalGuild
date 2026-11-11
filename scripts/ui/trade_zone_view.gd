extends Node3D
## Original thin plate/label presentation. Hit tests use TradeLayout's raw box,
## never this visible thickness. No original UI art or physics collider is copied.
var plate: MeshInstance3D
var caption: Label3D
var material: StandardMaterial3D
var zone_snapshot: Dictionary = {}
var highlighted: bool = false
var highlight_outline: MeshInstance3D

func _init() -> void:
	plate = MeshInstance3D.new()
	plate.mesh = BoxMesh.new()
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = material
	add_child(plate)
	highlight_outline = MeshInstance3D.new()
	highlight_outline.mesh = ImmediateMesh.new()
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1.0, 0.85, 0.2)
	outline_material.no_depth_test = true
	highlight_outline.material_override = outline_material
	highlight_outline.visible = false
	add_child(highlight_outline)
	caption = Label3D.new()
	caption.font_size = 30
	caption.pixel_size = 0.0032
	caption.width = 220
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.rotation_degrees.x = -90
	caption.position.y = 0.035
	caption.outline_size = 2
	add_child(caption)

func configure(zone: Dictionary, tracker: String) -> void:
	zone_snapshot = zone
	var reflection := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	var source: Transform3D = zone.transform
	transform = Transform3D(reflection * source.basis * reflection, reflection * source.origin)
	var bounds: AABB = zone.local_bounds
	plate.mesh.size = Vector3(bounds.size.x, maxf(0.025, bounds.size.y), bounds.size.z)
	plate.position = reflection * bounds.get_center()
	_update_highlight(bounds, reflection)
	material.albedo_color = Color(0.15, 0.65, 0.62, 0.7) if zone.kind == "buyer" else (Color(0.7, 0.48, 0.18, 0.75) if zone.active else Color(0.1, 0.15, 0.2, 0.6))
	update_caption(zone, tracker)

func update_caption(zone: Dictionary, tracker: String) -> void:
	if not zone.active:
		caption.text = ""
	elif zone.kind == "buyer":
		caption.text = "SELL\nDrop sellable cards"
	else:
		caption.text = "%s\n%s%s" % [zone.title, zone.price_text, "\n" + tracker if not tracker.is_empty() else ""]

func set_highlighted(value: bool) -> void:
	highlighted = value
	highlight_outline.visible = value

func _update_highlight(bounds: AABB, reflection: Basis) -> void:
	var mesh: ImmediateMesh = highlight_outline.mesh
	mesh.clear_surfaces()
	var corners: Array[Vector3] = [
		Vector3(bounds.position.x, bounds.end.y + 0.04, bounds.position.z),
		Vector3(bounds.end.x, bounds.end.y + 0.04, bounds.position.z),
		Vector3(bounds.end.x, bounds.end.y + 0.04, bounds.end.z),
		Vector3(bounds.position.x, bounds.end.y + 0.04, bounds.end.z)]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in corners.size():
		mesh.surface_add_vertex(reflection * corners[index])
		mesh.surface_add_vertex(reflection * corners[(index + 1) % corners.size()])
	mesh.surface_end()
