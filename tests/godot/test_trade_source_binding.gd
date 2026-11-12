extends SceneTree
const Binding = preload("res://scripts/ui/trade_source_binding.gd")
const View = preload("res://scripts/ui/trade_zone_view.gd")
class Assets extends RefCounted:
	var manifest := {"materials":{"mat":{"shader_source_path":"Shaders/SimpleLit.shadergraph","colors":{"_Color":{"r":.1,"g":.2,"b":.3,"a":1}}}}}
	func model_scene(_guid: String) -> PackedScene:
		var node := MeshInstance3D.new()
		node.mesh = PlaneMesh.new()
		var packed := PackedScene.new()
		packed.pack(node)
		node.free()
		return packed
	func source_color(value: Dictionary) -> Color:
		return Color(value.get("r",1),value.get("g",1),value.get("b",1),value.get("a",1))
	func texture(_guid: String) -> Texture2D: return null
func _init() -> void:
	var assets := Assets.new()
	var pose := {"m_LocalPosition":{"x":0,"y":.001,"z":.35},"m_LocalRotation":{"x":.7071068,"y":0,"z":0,"w":.7071068},"m_LocalScale":{"x":1,"y":1,"z":1}}
	var label := {"pose":pose,"rect":{"m_SizeDelta":{"x":.7,"y":.4}},"text":{"m_text":"???","m_fontSize":1.2,"m_enableWordWrapping":true}}
	var record := {"mesh":{"guid":"model"},"materials":[{"guid":"mat"}],"labels":{"title":label,"price":label.duplicate(true),"tracker":label.duplicate(true)},"outline":{"shader_source_path":"Shaders/CardOutline.shadergraph","properties":{"_OutlineSize":.1,"_OutlineColor":{"r":0,"g":1,"b":1,"a":1},"_MinAlpha":.2,"_RotationSpeed":2}}}
	record.labels.price.text.m_text = ""
	record.labels.tracker.text.m_text = ""
	var bound := Binding.create(assets,record,"")
	assert(not bound.is_empty())
	assert(bound.body.material_override.albedo_color.is_equal_approx(Color(.1,.2,.3)))
	assert(bound.outline.mesh == bound.body.mesh)
	assert(bound.outline.visible == false)
	assert(bound.labels.title.position.is_equal_approx(Vector3(0,.001,-.35)))
	assert(bound.labels.title.text == "???")
	assert(bound.labels.title.get_meta("source_font_missing"))
	assert(is_equal_approx(bound.labels.title.pixel_size,.0012))
	var view := View.new()
	root.add_child(view)
	view.source_nodes = bound
	view.add_child(bound.root)
	var zone := {"index":3,"kind":"vendor","title":"Timber","price_text":"Price: 4","active":false}
	view.update_caption(zone,"Discovered:\n2/4")
	assert(bound.labels.title.text == "???" and bound.labels.price.text == "" and bound.labels.tracker.text == "")
	assert(view.get_info().is_empty())
	zone.active = true
	view.update_caption(zone,"COMPLETED")
	assert(bound.labels.title.text == "Timber" and bound.labels.price.text == "Price: 4")
	assert(bound.labels.tracker.modulate.is_equal_approx(Color("FFD700")))
	assert(view.get_info() == {"header":"Pack Vendor","body":"You can buy Timber card pack here."})
	view.set_highlighted(true)
	assert(bound.outline.visible and not view.highlight_outline.visible)
	view.update_caption(zone,"Discovered:\n1/4")
	assert(bound.labels.tracker.modulate == Color.WHITE)
	view.zone_snapshot = {"kind":"buyer"}
	assert(view.get_info().header == "Card Buyer")
	view.free()
	print("Source trading presentation: PASS")
	quit()
