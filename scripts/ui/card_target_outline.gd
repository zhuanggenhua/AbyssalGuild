extends Node3D
## Native outline approximation, isolated from card selection and combat surfaces.
## Uses the card collider footprint, never alters a pick shape or body material.
var edges: Array[MeshInstance3D] = []

func configure(footprint: Vector3) -> void:
	if not footprint.is_finite() or footprint.x <= 0 or footprint.z <= 0: return
	var thickness: float = minf(footprint.x, footprint.z) * 0.025
	var size := Vector2(footprint.x + thickness, footprint.z + thickness)
	for index in 4:
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x + thickness, 0.007, thickness) if index < 2 else Vector3(thickness, 0.007, size.y + thickness)
		edge.mesh = mesh
		edge.position = Vector3(0, footprint.y / 2.0 + 0.012, (index * 2 - 1) * size.y / 2.0) if index < 2 else Vector3(((index - 2) * 2 - 1) * size.x / 2.0, footprint.y / 2.0 + 0.012, 0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("f5cf71")
		edge.material_override = material
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge)
		edges.append(edge)
	hide()
