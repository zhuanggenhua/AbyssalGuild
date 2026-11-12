extends RefCounted
## Deliberately narrow adapter for scene-authored built-in textured planes.
const BuiltinResources := "0000000000000000e000000000000000"
const BuiltinShaders := "0000000000000000f000000000000000"

static func background(assets: RefCounted, scene: Dictionary) -> Node3D:
	var group := Node3D.new()
	group.name = "SourceBackground"
	for entry in scene.get("scene_meshes", []):
		var mesh_ref: Dictionary = entry.get("mesh", {})
		if mesh_ref.get("guid", "") != BuiltinResources or str(mesh_ref.get("fileID", "")) != "10209" or not bool(entry.get("enabled", false)):
			continue
		var references: Array = entry.get("materials", [])
		if references.size() != 1:
			continue
		var source: Dictionary = assets.manifest.get("materials", {}).get(references[0].get("guid", ""), {})
		var shader_ref: Dictionary = source.get("shader_reference", {})
		if shader_ref.get("guid", "") != BuiltinShaders or str(shader_ref.get("fileID", "")) != "10752":
			continue # Only Unity Unlit/Texture, not arbitrary Standard/ShaderGraph assets.
		var tex_env: Dictionary = source.get("textures", {}).get("_MainTex", {})
		var guid: String = str(tex_env.get("m_Texture", {}).get("guid", ""))
		var tex: Texture2D = assets.texture(guid)
		var importer: Dictionary = assets.manifest.get("assets", {}).get(guid, {}).get("texture_importer", {})
		var pose := preload("res://scripts/ui/source_camera.gd").reflected_pose(entry.get("transform_chain", []))
		if tex == null or pose.is_empty() or int(importer.get("wrap_u", -1)) != 0 or int(importer.get("wrap_v", -1)) != 0 or int(importer.get("filter_mode", -1)) != 1:
			continue # Mixed wrap/filter modes need a separate verified mapping.
		var material := StandardMaterial3D.new()
		material.resource_name = str(source.get("name", "SourceBackground"))
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = tex
		# Unlit/Texture has no tint property; stale _Color is intentionally ignored.
		material.texture_repeat = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if bool(importer.get("mipmaps", false)) else BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var uv_scale: Dictionary = tex_env.get("m_Scale", {})
		var uv_offset: Dictionary = tex_env.get("m_Offset", {})
		material.uv1_scale = Vector3(float(uv_scale.get("x", 1)), float(uv_scale.get("y", 1)), 1)
		material.uv1_offset = Vector3(float(uv_offset.get("x", 0)), float(uv_offset.get("y", 0)), 0)
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(10, 10) # Unity's built-in plane, before Transform scale.
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.transform = pose.transform
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if int(entry.get("cast_shadows", 0)) == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.set_meta("source_renderer_file_id", entry.get("file_id", ""))
		group.add_child(instance)
	if group.get_child_count() == 0:
		group.free()
		return null
	return group

static func environment(target: Environment, scene: Dictionary) -> bool:
	var settings: Dictionary = scene.get("render_settings", {})
	if int(settings.get("m_AmbientMode", -1)) != 3 or not settings.has("m_AmbientSkyColor"):
		return false # Skybox/gradient ambient and fog require separate mapping.
	if bool(settings.get("m_Fog", false)):
		return false
	target.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var color: Dictionary = settings.m_AmbientSkyColor
	target.ambient_light_color = Color(float(color.r), float(color.g), float(color.b), float(color.get("a", 1)))
	target.ambient_light_energy = float(settings.get("m_AmbientIntensity", 1.0))
	target.reflected_light_source = 1 # ReflectedLightSource: Background=0, Disabled=1, Sky=2 (runtime property metadata).
	return true
