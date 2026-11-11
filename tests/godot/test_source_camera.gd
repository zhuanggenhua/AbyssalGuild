extends SceneTree
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
func _init():
	call_deferred("run")
func run():
	var scene := {"cameras": [{"resolved_pose": true, "orthographic": 0, "field_of_view": 30, "fov_axis": 0, "near": 2, "far": 40,
		"transform_chain": [{"m_LocalPosition": {"x": 0, "y": 10, "z": -1}, "m_LocalRotation": {"x": 0.67559016, "y": 0, "z": 0, "w": 0.7372774}, "m_LocalScale": {"x": 1, "y": 1, "z": 1}}]}]}
	var config := SourceCamera.configuration(scene)
	assert(config.transform.origin.is_equal_approx(Vector3(0,10,1)))
	var forward: Vector3 = -config.transform.basis.z
	assert(forward.is_equal_approx(Vector3(0,-sin(deg_to_rad(85)), -cos(deg_to_rad(85)))))
	var camera := Camera3D.new()
	root.add_child(camera)
	assert(SourceCamera.apply(camera, scene))
	assert(camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	assert(is_equal_approx(camera.fov, 30))
	assert(is_equal_approx(camera.near, 2))
	assert(is_equal_approx(camera.far, 40))
	var before := camera.transform
	assert(not SourceCamera.apply(camera, {}))
	assert(camera.transform == before)
	var assets = preload("res://scripts/ui/visual_assets.gd").new()
	if assets.load_manifest() == OK:
		var light := DirectionalLight3D.new()
		root.add_child(light)
		for scene_name in ["Main", "Island"]:
			assert(assets.apply_source_camera(camera, scene_name))
			assert(camera.global_position.is_equal_approx(Vector3(0,10,1)))
			assert(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and is_equal_approx(camera.fov,30))
			assert(is_equal_approx(camera.near,2) and is_equal_approx(camera.far,40))
			assert(assets.apply_source_light(light,scene_name))
			assert(is_equal_approx(light.light_energy,1))
			assert(light.light_color.is_equal_approx(Color(1,.95686275,.8392157)))
		light.free()
	camera.free()
	print("Source camera pose/projection: PASS")
	quit()
