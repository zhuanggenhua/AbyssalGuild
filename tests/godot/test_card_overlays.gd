extends SceneTree
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const EquipmentPanelView = preload("res://scripts/ui/equipment_panel_view.gd")
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func pose(position: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"m_LocalPosition": {"x": position.x,"y":position.y,"z":position.z},
		"m_LocalRotation":{"x":0,"y":0,"z":0,"w":1},"m_LocalScale":{"x":1,"y":1,"z":1}}

func label_record(position: Vector3) -> Dictionary:
	return {"transform_chain":[pose(position)],"color":{"r":0.9,"g":0.8,"b":0.7,"a":1},"rect_size":{"x":0.6,"y":0.4}}

func mesh_scene() -> PackedScene:
	var node := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,0),Vector3(1,0,0),Vector3(0,0,1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh
	var scene := PackedScene.new()
	check(scene.pack(node) == OK, "pack synthetic mesh")
	node.free()
	return scene

func assets_fixture():
	var assets = VisualAssets.new()
	assets.manifest = {"scenes":{"Main":{"categories":{"2":"prefab"},"packPrefab":"pack"}},
		"prefabs":{"prefab":{"size":{"x":2,"y":0,"z":3},"materials":[{"guid":"card_mat"}],"mesh":{"guid":"mesh"},"transform_chain":[pose()],
			"labels":{"price":label_record(Vector3(-0.6,0,-1)),"health":label_record(Vector3(0.6,0,-1)),"nutrition":label_record(Vector3(0,0,-1))},
			"equipment_panel":{"size":{"x":1.2,"z":0.3},"transform_chain":[pose(Vector3(0,0,-2))],"mesh":{"guid":"mesh"},"materials":[{"guid":"panel_mat"}]}}, "pack":{}},
		"materials":{"card_mat":{"shader_source_path":"Shaders/Card.shadergraph","textures":{"_BaseTex":{"m_Texture":{"guid":"art"}},"_OverlayTex":{"m_Texture":{"guid":"art"}}}},
			"panel_mat":{"name":"SyntheticPanel","shader_source_path":"Shaders/EquipmentPanel.shadergraph","textures":{"_OverlayTex":{"m_Texture":{"guid":"art"}}},
				"colors":{"_BaseColor":{"r":0.1,"g":0.2,"b":0.3,"a":1},"_ActiveColor":{"r":1,"g":0.5,"b":0.2,"a":1},"_InactiveColor":{"r":0.2,"g":0.1,"b":0.3,"a":1}}}}}
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	assets.texture_cache.art = ImageTexture.create_from_image(image)
	assets.model_cache.mesh = mesh_scene()
	return assets

func run() -> void:
	var assets = assets_fixture()
	var card = CardView.new()
	card.configure(1, "Synthetic", 2, false, assets, {"sellPrice":9,"maxHealth":12,"nutrition":3,"isSellable":false})
	check(card.stat_labels.size() == 3, "roles are explicit, not guessed from category")
	check(card.stat_labels.price.text == "9", "source Price exists even when not sellable")
	check(card.stat_labels.health.text == "12" and card.stat_labels.nutrition.text == "3", "configure defaults")
	check(card.stat_labels.price.position.is_equal_approx(Vector3(-0.6,0.01,1)), "reflected label anchor")
	check(card.stat_labels.price.modulate.is_equal_approx(Color(0.9,0.8,0.7,1)), "source label color")
	check(card.equipment_panel != null and not card.equipment_panel.visible, "empty equipment panel hidden")
	check(card.equipment_panel.uses_source_mesh, "cached panel uses source mesh")
	check(card.equipment_panel.position.is_equal_approx(Vector3(0,0,2)), "panel source pose")
	check(card.equipment_panel.body.basis.is_equal_approx(Basis(Vector3.UP, PI)), "panel mesh handedness bridge")
	check(card.equipment_panel.surface.get_shader_parameter("overlay_texture") == assets.texture_cache.art, "panel texture binding")
	check(card.equipment_panel.surface.get_shader_parameter("base_color").is_equal_approx(Color(0.1,0.2,0.3,1)), "panel base color")
	check(card.equipment_panel.surface.get_shader_parameter("active_color").is_equal_approx(Color(1,0.5,0.2,1)), "panel active color")
	check(card.equipment_panel.surface.get_shader_parameter("inactive_color").is_equal_approx(Color(0.2,0.1,0.3,1)), "panel inactive color")
	check(card.equipment_panel.body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "panel no shadow")
	var child_count: int = card.get_child_count()
	card.update_state({"health":0,"nutrition":1,"sell_price":4,"price_override":"27","equipment_slots":[0,2]})
	check(card.stat_labels.health.text == "0" and card.stat_labels.nutrition.text == "1", "live zero health and nutrition")
	check(card.stat_labels.price.text == "27", "chest price override")
	check(card.equipment_panel.visible and card.equipment_panel.active_slots == Vector3(1,0,1), "slot mapping")
	check(card.equipment_panel.surface.get_shader_parameter("active_slots") == Vector3(1,0,1), "live occupancy shader binding")
	for index in 10:
		card.update_state({"health":index,"nutrition":index,"sell_price":index,"equipment_slots":[1]})
	check(card.stat_labels.price.text == "9", "omitted override clears stale chest value")
	check(card.equipment_panel.active_slots == Vector3(0,1,0), "replacement clears old slots")
	check(card.get_child_count() == child_count, "repeated snapshots do not duplicate nodes")
	card.update_state({"health":-3,"price_override":"12345678","equipment_slots":[-1,3,"0",0.5]})
	check(card.stat_labels.health.text == "-3", "source values are not silently clamped")
	check(not card.equipment_panel.visible, "invalid slots do not make panel visible")
	var label: Label3D = card.stat_labels.price
	var width: float = ThemeDB.fallback_font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x * label.pixel_size
	check(width <= 0.60001 and label.pixel_size > 0, "long numeric override fits rectangle")
	card.update_state({"price_override":null,"equipment_slots":null})
	check(card.stat_labels.price.text == "9" and not card.equipment_panel.visible, "null override and slots clear safely")
	card.free()

	var panel_data: Dictionary = assets.manifest.prefabs.prefab.equipment_panel
	var unknown: Dictionary = panel_data.duplicate(true)
	unknown.transform_chain = []
	check(assets.create_equipment_panel(unknown) == null, "missing pose does not guess a panel position")
	assets.manifest.materials.panel_mat.shader_source_path = "Shaders/Other.shadergraph"
	var unsupported: Node3D = assets.create_equipment_panel(panel_data)
	check(not unsupported.uses_source_mesh and unsupported.fallback_slots.size() == 3, "unknown shader uses explicit generated fallback")
	unsupported.free()
	assets.manifest.materials.panel_mat.shader_source_path = "Shaders/EquipmentPanel.shadergraph"
	var saved_texture: Texture2D = assets.texture_cache.art
	assets.texture_cache.erase("art")
	var missing_texture: Node3D = assets.create_equipment_panel(panel_data)
	check(not missing_texture.uses_source_mesh and missing_texture.fallback_slots.size() == 3, "missing atlas keeps functional occupancy fallback")
	missing_texture.free()
	assets.texture_cache.art = saved_texture
	assets.model_cache.clear()
	var fallback = CardView.new()
	fallback.configure(2,"Fallback",2,false,assets)
	check(not fallback.equipment_panel.uses_source_mesh, "missing model uses generated panel")
	check(fallback.equipment_panel.fallback_slots.size() == 3, "fallback occupancy has three slots")
	check(fallback.stat_labels.price.position.is_equal_approx(Vector3(-0.6,0.02,1)), "fallback labels clear box face")
	check(fallback.stat_labels.price.modulate.is_equal_approx(Color("162b33")), "fallback labels retain readable dark style")
	fallback.update_state({"equipment_slots":[2]})
	check(fallback.equipment_panel.visible, "fallback occupancy still functional")
	check(fallback.equipment_panel.fallback_slots[2].material_override.albedo_color.is_equal_approx(Color(1,0.5,0.2,1)), "fallback active tint")
	fallback.update_state({})
	check(not fallback.equipment_panel.visible, "unequip hides fallback panel")
	fallback.free()
	var pack = CardView.new()
	pack.configure(3,"Pack",0,true,assets)
	check(pack.stat_labels.is_empty() and pack.equipment_panel == null, "missing references do not invent overlays")
	pack.free()
	check(EquipmentPanelView.compose_sample(Color.BLACK,Color.WHITE,Color(1,0,0,1),Color(0,0,1,1),0.1,Vector3(1,0,0)).is_equal_approx(Color(1,0,0,1)), "first slot tint")
	check(EquipmentPanelView.compose_sample(Color.BLACK,Color.WHITE,Color(1,0,0,1),Color(0,0,1,1),0.4,Vector3(1,0,0)).is_equal_approx(Color(0,0,1,1)), "middle inactive tint")
	check(EquipmentPanelView.compose_sample(Color.BLACK,Color.WHITE,Color(1,0,0,1),Color(0,0,1,1),0.8,Vector3(0,0,1)).is_equal_approx(Color(1,0,0,1)), "last slot tint")
	check(EquipmentPanelView.compose_sample(Color(0.2,0.3,0.4,1),Color(1,1,1,0),Color.WHITE,Color.BLACK,0.1,Vector3.ZERO).is_equal_approx(Color(0.2,0.3,0.4,1)), "transparent icons reveal base")
	print("Card overlay synthetic checks: %d passed" % checks)
	test_private()
	quit()

func test_private() -> void:
	var assets = VisualAssets.new()
	if assets.load_manifest() != OK:
		print("Private card overlays: SKIP (private visual manifest unavailable)")
		return
	var first: Dictionary = assets.appearance(2,false)
	if not first.prefab.has("labels") or first.prefab.get("equipment_panel", {}).is_empty():
		print("Private card overlays: SKIP (regenerate private visual manifest)")
		return
	var has_cache: bool = assets.model_scene(str(first.prefab.equipment_panel.mesh.guid)) != null
	var count := 0
	var panels := 0
	for scene in ["Main","Island"]:
		var config: Dictionary = assets.scene_configuration(scene)
		var categories: Array = config.categories.keys()
		categories.append("0")
		for key in categories:
			var appearance: Dictionary = assets.appearance(int(key),int(key)==0,{},scene)
			var card = CardView.new()
			card.configure(count,"Private test",int(key),int(key)==0,assets,{},scene)
			card.update_state({"health":7,"nutrition":4,"sell_price":5,"equipment_slots":[0,2]})
			for role in ["price","health","nutrition"]:
				check(card.stat_labels.has(role) == appearance.prefab.labels.has(role), "exact source label roles")
				if not card.stat_labels.has(role): continue
				var record: Dictionary = appearance.prefab.labels[role]
				var expected: Dictionary = SourceCamera.reflected_pose(record.transform_chain)
				var lift: float = 0.01 if card.source_material != null else 0.02
				check(card.stat_labels[role].position.is_equal_approx(expected.transform.origin + Vector3(0,lift,0)), "actual label anchor")
				check(card.stat_labels[role].text == {"price":"5","health":"7","nutrition":"4"}[role], "actual label update")
				count += 1
			if card.equipment_panel != null:
				panels += 1
				check(card.equipment_panel.uses_source_mesh == has_cache, "actual mesh cache selection")
				check(card.equipment_panel.active_slots == Vector3(1,0,1), "actual panel occupancy")
				if has_cache:
					inspect_private_panel(assets,card.equipment_panel,appearance.prefab.equipment_panel)
				card.update_state({})
				check(not card.equipment_panel.visible, "actual panel hides after unequip")
			card.free()
	print("Private card overlays: PASS (%d labels, %d panels; %s)" % [count,panels,"actual cached FBX" if has_cache else "FBX unavailable, generated panel fallback"])
	if not has_cache:
		print("Private EquipmentPanel FBX: SKIP (Godot import cache unavailable)")
	print("Card overlay total checks: %d passed; no GPU or manual visual acceptance" % checks)

func inspect_private_panel(assets, panel, metadata: Dictionary) -> void:
	var expected: Dictionary = SourceCamera.reflected_pose(metadata.transform_chain)
	check(panel.transform.is_equal_approx(expected.transform), "actual panel source transform")
	var arrays: Array = panel.body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bounds := AABB(panel.body.transform * vertices[0],Vector3.ZERO)
	for index in vertices.size():
		var vertex: Vector3 = panel.body.transform * vertices[index]
		bounds = bounds.expand(vertex)
		check(is_equal_approx(uvs[index].x, vertex.x / float(metadata.size.x) + 0.5), "panel U left to right")
	check(bounds.size.is_equal_approx(Vector3(float(metadata.size.x),0,float(metadata.size.z))), "actual panel outline bounds")
	var source: Dictionary = assets.manifest.materials[str(metadata.materials[0].guid)]
	check(panel.surface.get_shader_parameter("overlay_texture") == assets.texture(str(source.textures._OverlayTex.m_Texture.guid)), "actual panel atlas binding")
