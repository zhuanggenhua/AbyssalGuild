extends SceneTree
## Actual licensed FBX, controlled surface cameras, production factory + binder.
## Not a Unity screenshot/GI comparison. Headless deliberately returns NOT RUN / 2.
const Assets = preload("res://scripts/ui/visual_assets.gd")
const Binder = preload("res://scripts/ui/source_flat_board_lighting.gd")
const SOURCE := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
const SIZE := Vector2i(512,384)
const TOLERANCE := .008
var out := ""
var cases: Array = []
var failures: Array[String] = []
var assets = Assets.new()
var max_error := 0.0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("FAIL: ", label)
func rgb(c: Color) -> Array: return [c.r,c.g,c.b]
func digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(bytes); return h.finish().hex_encode()
func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(meshes(child))
	return result
func output(report: Dictionary, code: int) -> void:
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(report,"  ")+"\n")
	print("Actual FBX face probe: ", report.status, " (", cases.size(), " cases; ", failures.size(), " failures)")
	quit(code)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out=arg.trim_prefix("--output=")
	if out.is_empty(): out=ProjectSettings.globalize_path("user://board-face-probe")
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="gl_compatibility":
		output({"status":"NOT RUN","reason":"Native Compatibility root Window required","cases":[]},2); return
	if assets.load_manifest()!=OK or assets.load_render_pipeline(SOURCE)!=OK:
		failures.append("Fresh licensed manifest/pipeline required")
		output({"status":"FAILED","failures":failures,"cases":[]},1); return
	DirAccess.make_dir_recursive_absolute(out)
	root.size=SIZE
	for scene in ["Main","Island"]:
		for boost in [0.0,1.0]:
			for surface in [0,1]:
				for mode in ["ambient","direct","back"]:
					await capture(scene,boost,surface,mode)
		for mode in ["blocked_ambient","blocked_direct"]: await capture(scene,0.0,0,mode)
	validate_shadows()
	check(cases.size()==28,"all 28 cases captured")
	output({"status":"PASS" if failures.is_empty() else "FAIL","scope":"Real imported Main/Island FBX and actual production factory/binder, both surfaces, boost 0/1, controlled above/below surface cameras. Flat ambient model only; no Unity screenshot or SH claim.","engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"root_size":str(root.size),"linear_tolerance":TOLERANCE,"max_asserted_linear_error":max_error,"cases":cases,"failures":failures},0 if failures.is_empty() else 1)
func surface_target(mesh: MeshInstance3D, surface: int, boost: float) -> Vector3:
	var arrays := mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
	var shapes := mesh.mesh.surface_get_blend_shape_arrays(surface)
	if not shapes.is_empty():
		var shape: PackedVector3Array=shapes[0][Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i]=vertices[i].lerp(shape[i],boost) if mesh.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED else vertices[i]+shape[i]*boost
	var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var largest := -1.0
	var target := Vector3.ZERO
	for i in range(0,ids.size(),3):
		var a: Vector3=mesh.global_transform*vertices[ids[i]]
		var b: Vector3=mesh.global_transform*vertices[ids[i+1]]
		var c: Vector3=mesh.global_transform*vertices[ids[i+2]]
		var area := (b-a).cross(c-a).length_squared()
		if area>largest: largest=area; target=(a+b+c)/3.0
	return target
func decoded(c: Color) -> Color:
	return Color(c.r*(c.r*(c.r*.305306011+.682171111)+.012522878),c.g*(c.g*(c.g*.305306011+.682171111)+.012522878),c.b*(c.b*(c.b*.305306011+.682171111)+.012522878))
func reference(color: Color, environment: Environment, light: DirectionalLight3D) -> Color:
	var albedo := decoded(color)
	var l: Vector3=light.global_basis.z.normalized()
	var h := (l+Vector3.UP).normalized()
	var loh := clampf(l.dot(h),0,1)
	var spec := .04/(6.0*maxf(.1,loh*loh)*1.00001*1.00001)
	var irradiance := light.light_color.srgb_to_linear()*light.light_energy
	var value := (albedo*.96+Color(spec,spec,spec))*irradiance*maxf(0,l.y)
	if environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR:
		value+=environment.ambient_light_color.srgb_to_linear()*environment.ambient_light_energy*albedo
	return value
func world_inventory(node: Node, target: World3D) -> Array:
	var result: Array=[]
	if node is WorldEnvironment or node is Light3D:
		var actual: World3D=node.get_world_3d() if node is Node3D else node.get_viewport().find_world_3d()
		if actual==target:
			var parent:=node.get_parent()
			result.append({"id":node.get_instance_id(),"kind":node.get_class(),"path":str(node.get_path()),"queued":node.is_queued_for_deletion(),"parent_id":parent.get_instance_id(),"parent_queued":parent.is_queued_for_deletion()})
	for child in node.get_children(): result.append_array(world_inventory(child,target))
	return result
func cleanup(holder: Node, binder: Node = null) -> void:
	# Unlike production's persistent world, each isolated probe owns a whole world
	# configuration. Detach it synchronously before the next case constructs one.
	if is_instance_valid(binder): binder.call("clear")
	root.remove_child(holder)
	check(not holder.is_inside_tree(),"prior fixture synchronously left tree")
	holder.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
func capture(scene: String, boost: float, surface: int, mode: String) -> void:
	var id := "%s_b%d_s%d_%s" % [scene,int(boost),surface,mode]
	var holder := Node3D.new(); holder.name=id; root.add_child(holder)
	var world := WorldEnvironment.new(); world.environment=Environment.new(); holder.add_child(world)
	assets.apply_source_environment(world.environment,scene)
	# Black clear identifies genuinely culled back faces, not a lighting tweak.
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color.BLACK
	if mode.ends_with("direct"): world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	var light := DirectionalLight3D.new(); holder.add_child(light); assets.apply_source_light(light,scene)
	var board=assets.create_board_mesh(scene,boost)
	if board==null:
		failures.append(id+" actual FBX missing"); await cleanup(holder); return
	holder.add_child(board)
	var nodes := meshes(board)
	if nodes.size()!=1:
		failures.append(id+" expected one actual mesh"); await cleanup(holder); return
	var mesh: MeshInstance3D=nodes[0]
	check(mesh.mesh.get_blend_shape_count()==1 and mesh.mesh.get_blend_shape_name(0)=="Scale",id+" actual Scale blend shape")
	var originals: Array[Material]=[]
	for i in mesh.mesh.get_surface_count(): originals.append(mesh.get_surface_override_material(i))
	var target := surface_target(mesh,surface,boost)
	var camera := Camera3D.new(); holder.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=.6
	camera.position=target+Vector3(0,-10 if mode=="back" else 10,0)
	camera.look_at(target,Vector3.FORWARD); camera.current=true
	var inventory:=world_inventory(root,board.get_world_3d())
	check(inventory.size()==2,id+" exactly one isolated WorldEnvironment and light before binding")
	check(board.get_world_3d().environment==world.environment,id+" current environment owns actual World3D")
	var binder := Binder.new(); holder.add_child(binder); binder.bind(board,world.environment)
	var initial_active:=binder.active_count()
	check(initial_active==2,id+" production binder admits both surfaces")
	var original: ShaderMaterial=originals[surface] as ShaderMaterial
	var material: ShaderMaterial=mesh.get_surface_override_material(surface) as ShaderMaterial
	if original==null or material==null:
		failures.append(id+" production shader material missing"); await cleanup(holder); return
	check(original.shader.code.contains("cull_back") and material.shader.code.contains("cull_back"),id+" original and production Cull.Back")
	check(light.shadow_enabled and is_equal_approx(light.shadow_opacity,.7),id+" source shadows retained")
	var authored: Color=original.get_shader_parameter("source_base_color")
	if mode.begins_with("blocked"):
		var blocker := MeshInstance3D.new(); blocker.mesh=BoxMesh.new(); blocker.mesh.size=Vector3(.5,.5,.5)
		blocker.position=target+light.global_basis.z.normalized()*.8
		blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		holder.add_child(blocker)
	for frame in 8: await process_frame; await RenderingServer.frame_post_draw
	check(binder.active_count()==2,id+" binder remains active at readback")
	var im := root.get_texture().get_image()
	check(im!=null and not im.is_empty() and im.get_size()==SIZE,id+" actual framebuffer dimensions")
	if im==null or im.is_empty(): await cleanup(holder); return
	check(root.size==SIZE,id+" actual root Window dimensions")
	var observed := Color(0,0,0,0)
	for x in range(SIZE.x/2-2,SIZE.x/2+2):
		for y in range(SIZE.y/2-2,SIZE.y/2+2): observed+=im.get_pixel(x,y).srgb_to_linear()/16.0
	var expected := reference(authored,world.environment,light) if mode!="back" else Color.BLACK
	var error := maxf(absf(observed.r-expected.r),maxf(absf(observed.g-expected.g),absf(observed.b-expected.b)))
	if not mode.begins_with("blocked"):
		max_error=maxf(max_error,error)
		check(error<TOLERANCE,id+" source linear formula / back-face absence error="+str(error))
	var path := out.path_join(id+".png")
	check(im.save_png(path)==OK,id+" PNG saved")
	cases.append({"id":id,"context_before_bind":inventory,"initial_active":initial_active,"readback_active":binder.active_count(),"scene":scene,"boost":boost,"surface":surface,"mode":mode,"image_size":str(im.get_size()),"root_visible_size":str(root.get_visible_rect().size),"root_final_transform":str(root.get_final_transform()),"camera_target":[target.x,target.y,target.z],"camera_position":[camera.position.x,camera.position.y,camera.position.z],"authored_color":rgb(authored),"observed_linear":rgb(observed),"expected_unoccluded_linear":rgb(expected),"error_unoccluded":error,"flat_ambient_linear":rgb(world.environment.ambient_light_color.srgb_to_linear()*world.environment.ambient_light_energy*decoded(authored)),"shadow_enabled":light.shadow_enabled,"shadow_opacity":light.shadow_opacity,"light_color":rgb(light.light_color),"light_energy":light.light_energy,"determinant":mesh.global_basis.determinant(),"indices_sha256":digest(mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].to_byte_array()),"png":path})
	var checkpoint:=FileAccess.open(out.path_join("checkpoint.json"),FileAccess.WRITE)
	checkpoint.store_string(JSON.stringify({"cases":cases,"failures":failures},"  ")); checkpoint.flush(); checkpoint.close()
	print("CASE_COMPLETE ",id," count=",cases.size()," failures=",failures.size())
	await cleanup(holder,binder)
func find_case(scene: String, mode: String) -> Dictionary:
	for row in cases:
		if row.scene==scene and row.mode==mode and row.boost==0 and row.surface==0: return row
	return {}
func validate_shadows() -> void:
	for scene in ["Main","Island"]:
		var clear := find_case(scene,"direct")
		var blocked := find_case(scene,"blocked_direct")
		var ambient := find_case(scene,"blocked_ambient")
		if clear.is_empty() or blocked.is_empty() or ambient.is_empty(): check(false,scene+" shadow pair missing"); continue
		var reduction := 0.0
		for c in 3:
			reduction=maxf(reduction,clear.observed_linear[c]-blocked.observed_linear[c])
			check(absf(ambient.observed_linear[c]-blocked.observed_linear[c]-ambient.flat_ambient_linear[c])<TOLERANCE,scene+" ambient invariant under shadow channel"+str(c))
		check(reduction>.03,scene+" actual occluder reduces direct light")
