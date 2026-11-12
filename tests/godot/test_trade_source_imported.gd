extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Layout = preload("res://scripts/model/trade_layout.gd")
const View = preload("res://scripts/ui/trade_zone_view.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var assets := Assets.new()
	if assets.load_manifest() != OK:
		print("Private trade source: SKIP (licensed assets absent)")
		quit()
		return
	var catalog := Catalog.new()
	assert(catalog.load_file() == OK)
	var count := 0
	for scene in ["Main", "Island"]:
		var result := Layout.zones(catalog,scene)
		assert(result.errors.is_empty())
		for zone in result.zones:
			var view := View.new()
			root.add_child(view)
			view.bind_source(assets,catalog)
			view.configure(zone,"Discovered:\n1/3")
			assert(not view.source_nodes.is_empty(), "Requires cached original trading FBX and fresh manifest")
			assert(not view.plate.visible and not view.caption.visible)
			assert(view.pick_body.get_meta("trade_zone_index") == zone.index)
			assert(view.pick_body.collision_layer == 1)
			assert(view.source_nodes.body.get_meta("source_mesh_guid") == "fc556c3f0b79f26408df3d0250ad9bcf")
			assert(view.source_nodes.outline != null)
			if zone.kind == "buyer":
				assert(view.source_nodes.labels.title.text == "Sell")
				assert(view.source_nodes.icon != null)
				var art: String = str(catalog.fields(zone.currency_guid).artTexture.guid)
				assert(view.source_nodes.icon.material_override.albedo_texture == assets.texture(art))
			else:
				assert(view.source_nodes.labels.size() == 3)
				assert(view.source_nodes.labels.title.text == (str(zone.title) if zone.active else "???"))
			view.set_highlighted(true)
			assert(view.source_nodes.outline.visible)
			view.hide()
			assert(view.pick_body.collision_layer == 0)
			view.show()
			assert(view.pick_body.collision_layer == 1)
			view.free()
			count += 1
	print("Private trade source: PASS (%d cached original zones)" % count)
	quit()
