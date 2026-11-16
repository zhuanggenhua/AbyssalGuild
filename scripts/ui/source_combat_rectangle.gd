extends RefCounted
## Locked WorldCanvas default UI/Image Sliced subset. Presentation owns neither
## the combat RectTransform size nor the gameplay hit/overlap bounds.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")

static func _positive(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value)) and float(value) > 0.0

static func _valid_vector(values: Variant, keys: String) -> bool:
	if not values is Dictionary: return false
	for key in keys:
		var v: Variant = values.get(key)
		if typeof(v) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(v)): return false
	return true

static func _asset_binding(assets, scene: Dictionary) -> Dictionary:
	var record: Dictionary = scene.get("combat", {}).get("rectangle", {})
	var guid: String = str(record.get("sprite", {}).get("guid", ""))
	var entry: Dictionary = assets.manifest.get("assets", {}).get(guid, {})
	var sprite: Dictionary = entry.get("sprite", {})
	var importer: Dictionary = entry.get("texture_importer", {})
	if sprite.get("mode", "") != "single_full_image" or sprite.get("packing_tag", "?") != "":
		return {} # Packed/atlased sprites require measured outer UVs, inner UVs and padding.
	if int(importer.get("filter_mode", -1)) != 1 or int(importer.get("srgb", 0)) != 1 or int(importer.get("mipmaps", -1)) != 0:
		return {}
	if int(importer.get("wrap_u", -1)) != 1 or int(importer.get("wrap_v", -1)) != 1:
		return {}
	if int(importer.get("alpha_usage", -1)) != 1 or int(importer.get("alpha_is_transparency", -1)) != 1:
		return {}
	var input_ppu: Variant = sprite.get("pixels_per_unit")
	var multiplier: Variant = record.get("sprite_ppu_multiplier")
	var reference_ppu: Variant = scene.get("world_canvas_reference_ppu")
	if not _positive(input_ppu) or not _positive(multiplier) or not _positive(reference_ppu):
		return {}
	var ppu: float = (float(input_ppu) / float(reference_ppu)) * float(multiplier)
	var size: Dictionary = sprite.get("pixel_size", {})
	var border: Dictionary = sprite.get("border_pixels", {})
	if not _positive(ppu) or not _valid_vector(size,"xy") or not _valid_vector(border,"xyzw"):
		return {}
	var pixels := Vector2(float(size.x),float(size.y))
	var borders := Vector4(float(border.x),float(border.y),float(border.z),float(border.w))
	if pixels.x <= 0 or pixels.y <= 0 or borders == Vector4.ZERO or minf(minf(borders.x,borders.y),minf(borders.z,borders.w)) < 0:
		return {}
	if borders.x+borders.z > pixels.x or borders.y+borders.w > pixels.y:
		return {}
	if not _valid_vector(record.get("pivot"),"xy") or not _valid_vector(record.get("color"),"rgba"):
		return {}
	if not record.get("fill_center") is bool:
		return {}
	var normal: Variant = record.get("normal_offset")
	if typeof(normal) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(normal)):
		return {}
	var canvas := SourceCamera.reflected_pose(scene.get("world_canvas_chain", []))
	if canvas.is_empty(): return {}
	var pose: Transform3D = canvas.transform
	if not pose.basis.is_finite() or absf(pose.basis.x.y) > 0.00001 or absf(pose.basis.y.y) > 0.00001:
		return {}
	var texture: Texture2D = assets.texture(guid)
	if texture == null or not texture.get_size().is_equal_approx(pixels):
		return {}
	var image := texture.get_image()
	# The locked unatlased texture reaches all four edges. Do not guess at
	# Unity DataUtility padding of a trimmed texture or a different atlas.
	if image == null or image.is_compressed() or image.get_used_rect() != Rect2i(Vector2i.ZERO, Vector2i(pixels)):
		return {}
	return {"basis":pose.basis, "normal":float(normal), "pivot":Vector2(float(record.pivot.x),float(record.pivot.y)),
		"ppu":ppu, "pixels":pixels, "borders":borders, "texture":texture, "prefab_guid":str(record.get("prefab_guid","")),
		"color":assets.source_color(record.color), "fill_center":record.fill_center}

static func bind(assets, scene: Dictionary) -> MeshInstance3D:
	var source := _asset_binding(assets,scene)
	if source.is_empty(): return null
	var group := MeshInstance3D.new()
	group.name = "SourceCombatRectangle"
	group.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.set_meta("source_binding", source)
	group.set_meta("source_prefab_guid", source.prefab_guid)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = source.color
	material.albedo_texture = source.texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.texture_repeat = false
	group.material_override = material
	return group

static func update(node: MeshInstance3D, state: Dictionary) -> bool:
	var source: Dictionary = node.get_meta("source_binding", {})
	var config: Dictionary = state.get("config", {})
	if source.is_empty() or config.is_empty():
		return false
	var size: Vector2 = state.size
	var center: Vector2 = state.center
	var basis: Basis = source.basis
	if not size.is_finite() or size.x <= 0 or size.y <= 0 or not center.is_finite():
		return false
	# Verify frame agrees with the imported model. Reflection negates world Z,
	# not the RectTransform's local x/y axes.
	var axis_x := Vector2(basis.x.x,-basis.x.z)
	var axis_y := Vector2(basis.y.x,-basis.y.z)
	if not axis_x.is_equal_approx(config.axis_x) or not axis_y.is_equal_approx(config.axis_y) or not source.pivot.is_equal_approx(config.pivot):
		return false
	# CombatRect.Initialize places the root at flattened average, then clamps in XZ.
	# The child-local +Z is reflected before applying the effective canvas basis.
	node.transform = Transform3D(basis,Vector3(center.x,0,-center.y) + basis * Vector3(0,0,-source.normal))
	if node.mesh != null and node.get_meta("source_size", Vector2.ZERO) == size:
		return true
	var mesh := sliced_mesh(size,source.pivot,source.borders,source.pixels,source.ppu,source.fill_center)
	if mesh == null: return false
	node.mesh = mesh
	node.set_meta("source_size",size)
	return true

## 2.5.0 UGUI Image.GenerateSlicedSprite for world rect (no pixel adjustment)
## and untrimmed, unatlased outer/inner UVs. Incoming border in L/B/R/T pixels.
static func sliced_mesh(size: Vector2, pivot: Vector2, border: Vector4,
		pixels: Vector2, ppu: float, fill_center: bool) -> ArrayMesh:
	if not size.is_finite() or not pixels.is_finite() or not pivot.is_finite() or not border.is_finite():
		return null
	if size.x <= 0 or size.y <= 0 or pixels.x <= 0 or pixels.y <= 0 or not _positive(ppu):
		return null
	var sides := border / ppu
	var total_x := sides.x+sides.z
	var total_y := sides.y+sides.w
	if total_x > size.x:
		var r := size.x/total_x
		sides.x *= r
		sides.z *= r
	if total_y > size.y:
		var r := size.y/total_y
		sides.y *= r
		sides.w *= r
	var start := -size*pivot
	var x := PackedFloat32Array([start.x,start.x+sides.x,start.x+size.x-sides.z,start.x+size.x])
	var y := PackedFloat32Array([start.y,start.y+sides.y,start.y+size.y-sides.w,start.y+size.y])
	var u := PackedFloat32Array([0,border.x/pixels.x,1.0-border.z/pixels.x,1])
	var v := PackedFloat32Array([1,1.0-border.y/pixels.y,border.w/pixels.y,0])
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(3):
		for j in range(3):
			if (not fill_center and i == 1 and j == 1) or x[i+1] <= x[i] or y[j+1] <= y[j]:
				continue
			# Corresponding UVs may coincide even for a nonempty center region.
			var k := vertices.size()
			vertices.append_array([Vector3(x[i],y[j],0),Vector3(x[i],y[j+1],0),Vector3(x[i+1],y[j+1],0),Vector3(x[i+1],y[j],0)])
			uv.append_array([Vector2(u[i],v[j]),Vector2(u[i],v[j+1]),Vector2(u[i+1],v[j+1]),Vector2(u[i+1],v[j])])
			indices.append_array([k,k+1,k+2,k+2,k+3,k])
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
