extends RefCounted
## Source font identity is bound; TMP layout and built-in icon shader parity stay explicit.
const Pose = preload("res://scripts/ui/source_camera.gd")
const MeshBinding = preload("res://scripts/ui/card_mesh_binding.gd")
const Outline = preload("res://scripts/ui/source_card_outline.gd")

static func create(assets, record: Dictionary, currency_art: String) -> Dictionary:
	var packed: PackedScene = assets.model_scene(str(record.get("mesh", {}).get("guid", "")))
	var references: Array = record.get("materials", [])
	if packed == null or references.size() != 1: return {}
	var source: Dictionary = assets.manifest.get("materials", {}).get(str(references[0].get("guid", "")), {})
	if source.get("shader_source_path") != "Shaders/SimpleLit.shadergraph": return {}
	var instance := packed.instantiate()
	var meshes: Array[Dictionary] = []
	MeshBinding._collect_meshes(instance, Transform3D.IDENTITY, meshes)
	if meshes.size() != 1 or meshes[0].mesh.get_surface_count() != 1:
		instance.free()
		return {}
	var root := Node3D.new()
	root.name = "SourceTradeZone"
	var body := MeshInstance3D.new()
	body.name = "SourceTradeMesh"
	body.mesh = meshes[0].mesh
	var bridge: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * meshes[0].transform
	body.transform = bridge
	body.set_meta("mesh_to_card", bridge)
	body.set_meta("source_mesh_guid", str(record.mesh.guid))
	var material := StandardMaterial3D.new()
	material.albedo_color = assets.source_color(source.get("colors", {}).get("_Color", {}))
	material.metallic = 0
	material.roughness = 1
	material.disable_receive_shadows = not bool(record.get("receive_shadows", false))
	body.material_override = material
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if int(record.get("cast_shadows", 0)) == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)
	instance.free()
	var outline = Outline.create(body, record.get("outline", {}))
	if outline != null:
		outline.name = "SourceTradeHighlight"
		root.add_child(outline)
		outline.hide()
	var labels := {}
	for role in record.get("labels", {}):
		var label := _label(record.labels[role], assets)
		if label != null:
			labels[role] = label
			root.add_child(label)
	var icon := _icon(assets, record.get("icon", {}), currency_art)
	if icon != null: root.add_child(icon)
	return {"root": root, "body": body, "outline": outline, "labels": labels, "icon": icon}

static func _label(record: Dictionary, assets) -> Label3D:
	var pose := Pose.reflected_pose([record.get("pose", {})])
	if pose.is_empty(): return null
	var source: Dictionary = record.get("text", {})
	var size: Dictionary = record.get("rect", {}).get("m_SizeDelta", {})
	if float(size.get("x", 0)) <= 0: return null
	var label := Label3D.new()
	label.transform = pose.transform
	var font_binding: Dictionary = preload("res://scripts/ui/source_font_registry.gd").shared().bind_label(label, source)
	if label.font == null:
		label.font = ThemeDB.fallback_font
	label.font_size = 100
	# TMP world text uses one tenth of its point size in scene units. Native font
	# glyph metrics differ from TMP layout; retain source size rather than fit.
	label.pixel_size = float(source.get("m_fontSize", 1)) / 1000.0
	label.width = float(size.x) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if bool(source.get("m_enableWordWrapping", false)) else TextServer.AUTOWRAP_OFF
	label.outline_size = 0
	label.modulate = assets.source_color(source.get("m_fontColor", {}))
	label.horizontal_alignment = {1:HORIZONTAL_ALIGNMENT_LEFT, 2:HORIZONTAL_ALIGNMENT_CENTER, 4:HORIZONTAL_ALIGNMENT_RIGHT}.get(int(source.get("m_HorizontalAlignment", 2)), HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = {256:VERTICAL_ALIGNMENT_TOP, 512:VERTICAL_ALIGNMENT_CENTER, 1024:VERTICAL_ALIGNMENT_BOTTOM}.get(int(source.get("m_VerticalAlignment", 512)), VERTICAL_ALIGNMENT_CENTER)
	label.text = str(source.get("m_text", "")) if source.get("m_text") != null else ""
	label.set_meta("source_font_missing", font_binding.font == null)
	label.set_meta("source_text", label.text)
	label.set_meta("source_color", label.modulate)
	return label

static func _icon(assets, record: Dictionary, art: String) -> MeshInstance3D:
	var mesh_ref: Dictionary = record.get("mesh", {})
	if str(mesh_ref.get("fileID", "")) != "10210" or mesh_ref.get("guid") != "0000000000000000e000000000000000": return null
	var pose := Pose.reflected_pose([record.get("pose", {})])
	var references: Array = record.get("materials", [])
	if pose.is_empty() or references.size() != 1: return null
	var texture: Texture2D = assets.texture(art)
	if texture == null: return null
	var source: Dictionary = assets.manifest.get("materials", {}).get(str(references[0].get("guid", "")), {})
	var shader_ref: Dictionary = source.get("shader_reference", {})
	if str(shader_ref.get("fileID", "")) != "10750" or shader_ref.get("guid") != "0000000000000000f000000000000000": return null
	var icon := MeshInstance3D.new()
	icon.name = "SourceCurrencyIcon"
	icon.mesh = QuadMesh.new()
	icon.mesh.size = Vector2.ONE
	icon.transform = pose.transform
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	var tex_env: Dictionary = source.get("textures", {}).get("_MainTex", {})
	var uv_scale: Dictionary = tex_env.get("m_Scale", {})
	var uv_offset: Dictionary = tex_env.get("m_Offset", {})
	material.uv1_scale = Vector3(float(uv_scale.get("x", 1)), float(uv_scale.get("y", 1)), 1)
	material.uv1_offset = Vector3(float(uv_offset.get("x", 0)), float(uv_offset.get("y", 0)), 0)
	var importer: Dictionary = assets.manifest.get("assets", {}).get(art, {}).get("texture_importer", {})
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if int(importer.get("filter_mode", 1)) == 0 else (BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if bool(importer.get("mipmaps", false)) else BaseMaterial3D.TEXTURE_FILTER_LINEAR)
	material.texture_repeat = int(importer.get("wrap_u", 0)) == 0 and int(importer.get("wrap_v", 0)) == 0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Built-in shader implementation unavailable: texture/pose are source-backed,
	# alpha mix is an explicitly unresolved renderer adaptation, not shader parity.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	icon.material_override = material
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	icon.set_meta("source_shader_reference", shader_ref)
	icon.set_meta("source_shader_parity", "unverified_builtin_10750")
	return icon
