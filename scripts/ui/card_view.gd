extends Node3D
## Source mesh/material adapter when complete; generated geometry otherwise.
var card_id: int
var caption: Label3D
var body: MeshInstance3D
var material: StandardMaterial3D
var source_material: ShaderMaterial

func configure(id: int, title: String, category: int, is_pack: bool, visual_assets = null, fields: Dictionary = {}, scene_name: String = "Main", collider_size: Vector3 = Vector3.ZERO) -> void:
	card_id = id
	body = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.06, 1.95)
	if collider_size != Vector3.ZERO:
		mesh.size = Vector3(collider_size.x, maxf(collider_size.y, 0.02), collider_size.z)
	body.mesh = mesh
	material = StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fposmod(category * 0.091 + 0.07, 1.0), 0.28, 0.86)
	if is_pack:
		material.albedo_color = Color("ca9b57")
	var appearance: Dictionary = {}
	if visual_assets != null:
		appearance = visual_assets.appearance(category, is_pack, fields, scene_name)
		var source_size: Dictionary = appearance.get("prefab", {}).get("size", {})
		if source_size.has("x") and source_size.has("z"):
			mesh.size = Vector3(float(source_size.x), maxf(float(source_size.get("y", 0)), 0.02), float(source_size.z))
		var colors: Dictionary = appearance.get("material", {}).get("colors", {})
		if colors.has("_Color"):
			material.albedo_color = visual_assets.source_color(colors._Color)
	if visual_assets != null:
		var imported: MeshInstance3D = visual_assets.create_card_mesh(appearance)
		if imported != null:
			body.free()
			body = imported
			source_material = body.material_override
	if source_material == null:
		body.material_override = material
	add_child(body)
	var collision := StaticBody3D.new()
	collision.set_meta("card_id", id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	collision.add_child(shape)
	add_child(collision)
	caption = Label3D.new()
	caption.text = title
	caption.font_size = 36
	caption.pixel_size = 0.007
	caption.modulate = Color("162b33")
	caption.outline_size = 0
	caption.no_depth_test = false
	caption.rotation_degrees.x = -90
	caption.position = Vector3(0, mesh.size.y / 2.0 + 0.01, -mesh.size.z * 0.34)
	caption.pixel_size = mesh.size.x / 200.0
	caption.width = 175
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if source_material != null:
		var title_data: Dictionary = appearance.get("prefab", {}).get("title", {})
		var pose: Dictionary = preload("res://scripts/ui/source_camera.gd").reflected_pose(title_data.get("transform_chain", []))
		if not pose.is_empty():
			caption.transform = pose.transform
			caption.position.y += 0.01 # Avoid coplanar text on the source flat mesh.
			caption.modulate = visual_assets.source_color(title_data.get("color", {}))
			caption.pixel_size = float(title_data.get("rect_size", {}).get("x", mesh.size.x)) / 200.0
	add_child(caption)
	if visual_assets != null and source_material == null:
		var art: Texture2D = visual_assets.texture(appearance.get("art_guid", ""))
		if art != null:
			var face := MeshInstance3D.new()
			face.name = "SourceArt"
			var plane := PlaneMesh.new()
			var width: float = mesh.size.x * 0.8
			var height: float = minf(mesh.size.z * 0.58, width * art.get_height() / float(art.get_width()))
			plane.size = Vector2(height * art.get_width() / float(art.get_height()), height)
			face.mesh = plane
			face.position = Vector3(0, mesh.size.y / 2.0 + 0.005, mesh.size.z * 0.06)
			var art_material := StandardMaterial3D.new()
			art_material.albedo_texture = art
			art_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			face.material_override = art_material
			add_child(face)

func highlight(value: bool) -> void:
	material.emission_enabled = value
	material.emission = Color("31666b")
	material.emission_energy_multiplier = 0.25
	if source_material != null:
		source_material.set_shader_parameter("selection_emission", Vector3(0.192, 0.4, 0.42) * (0.25 if value else 0.0))
