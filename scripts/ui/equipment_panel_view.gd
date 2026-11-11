extends Node3D
## Compact occupancy only. Expanded floating-card interaction is a separate stage.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
const CardMeshBinding = preload("res://scripts/ui/card_mesh_binding.gd")
const SHADER = preload("res://scripts/ui/shaders/equipment_slots.gdshader")
var body: MeshInstance3D
var surface: ShaderMaterial
var active_slots := Vector3.ZERO
var uses_source_mesh := false
var fallback_slots: Array[MeshInstance3D] = []
var active_color := Color.WHITE
var inactive_color := Color(0.25,0.25,0.25,1)

static func create(assets, metadata: Dictionary):
	var pose := SourceCamera.reflected_pose(metadata.get("transform_chain", []))
	if pose.is_empty():
		return null
	var panel = load("res://scripts/ui/equipment_panel_view.gd").new()
	panel.name = "EquipmentPanel"
	panel.transform = pose.transform
	var references: Array = metadata.get("materials", [])
	var source: Dictionary = {}
	if not references.is_empty():
		source = assets.manifest.get("materials", {}).get(str(references[0].get("guid", "")), {})
	var colors: Dictionary = source.get("colors", {})
	panel.active_color = assets.source_color(colors.get("_ActiveColor", {}), Color.WHITE)
	panel.inactive_color = assets.source_color(colors.get("_InactiveColor", {}), Color(0.25,0.25,0.25,1))
	panel._bind_mesh(assets, metadata, source)
	if not panel.uses_source_mesh:
		panel._build_fallback(metadata.get("size", {}))
	panel.set_slots([])
	return panel

func _bind_mesh(assets, metadata: Dictionary, source: Dictionary) -> void:
	if source.get("shader_source_path", "") != "Shaders/EquipmentPanel.shadergraph":
		return
	var texture_guid: String = str(source.get("textures", {}).get("_OverlayTex", {}).get("m_Texture", {}).get("guid", ""))
	var overlay: Texture2D = assets.texture(texture_guid)
	var packed: PackedScene = assets.model_scene(str(metadata.get("mesh", {}).get("guid", "")))
	if overlay == null or packed == null:
		return
	var instance := packed.instantiate()
	var meshes: Array[Dictionary] = []
	CardMeshBinding._collect_meshes(instance, Transform3D.IDENTITY, meshes)
	if meshes.size() != 1 or meshes[0].mesh.get_surface_count() != 1:
		instance.free()
		return
	var arrays: Array = meshes[0].mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_TEX_UV].is_empty():
		instance.free()
		return
	surface = ShaderMaterial.new()
	surface.shader = SHADER
	surface.resource_name = str(source.get("name", "EquipmentSlots"))
	surface.set_shader_parameter("overlay_texture", overlay)
	surface.set_shader_parameter("base_color", assets.source_color(source.get("colors", {}).get("_BaseColor", {})))
	surface.set_shader_parameter("active_color", active_color)
	surface.set_shader_parameter("inactive_color", inactive_color)
	body = MeshInstance3D.new()
	body.mesh = meshes[0].mesh
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * meshes[0].transform
	body.material_override = surface
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	uses_source_mesh = true
	instance.free()

func _build_fallback(size: Dictionary) -> void:
	var width: float = float(size.get("x", 0.0))
	var depth: float = float(size.get("z", 0.0))
	if not is_finite(width) or not is_finite(depth) or width <= 0 or depth <= 0:
		return # Do not guess a source panel footprint.
	for index in 3:
		var slot := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width / 3.0 * 0.9, 0.006, depth)
		slot.mesh = mesh
		slot.position.x = (index - 1) * width / 3.0
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		slot.material_override = material
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
		fallback_slots.append(slot)

func set_slots(slots: Array) -> void:
	active_slots = Vector3.ZERO
	for value in slots:
		if not value is int or value < 0 or value > 2:
			continue
		active_slots[value] = 1.0
	visible = active_slots != Vector3.ZERO
	if surface != null:
		surface.set_shader_parameter("active_slots", active_slots)
	for index in fallback_slots.size():
		fallback_slots[index].material_override.albedo_color = active_color if active_slots[index] > 0 else inactive_color

static func compose_sample(base: Color, overlay: Color, active: Color, inactive: Color, u: float, slots: Vector3) -> Color:
	var index: int = 0 if u < 0.3333 else (1 if u < 0.6666 else 2)
	var tint := inactive.lerp(active, slots[index])
	var color := base.lerp(overlay * tint, overlay.a)
	color.a = 1.0
	return color
