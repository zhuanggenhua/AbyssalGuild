extends Node3D
## All geometry and materials are generated here; no template art is bundled.
var card_id: int
var caption: Label3D
var body: MeshInstance3D
var material: StandardMaterial3D

func configure(id: int, title: String, category: int, is_pack: bool) -> void:
	card_id = id
	body = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.06, 1.95)
	body.mesh = mesh
	material = StandardMaterial3D.new()
	material.albedo_color = Color.from_hsv(fposmod(category * 0.091 + 0.07, 1.0), 0.28, 0.86)
	if is_pack:
		material.albedo_color = Color("ca9b57")
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
	caption.position = Vector3(0, 0.04, -0.63)
	caption.width = 175
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(caption)

func highlight(value: bool) -> void:
	material.emission_enabled = value
	material.emission = Color("31666b")
	material.emission_energy_multiplier = 0.25
