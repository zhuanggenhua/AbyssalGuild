extends Node
## Synthetic decision experiment only. Never a Unity scene or actual GI substitute.
const Binder = preload("res://scripts/ui/source_flat_board_lighting.gd")
const Lit = preload("res://scripts/ui/source_lit_material.gd")
const COLOR := Color(.42808828,.4678468,.49056602)
const AMBIENT := Color(.60480005,.63552,.72)
const LIGHT_COLOR := Color(1,.95686275,.8392157)
const TOLERANCE := 0.008
var samples: Array = []
var failures: Array[String] = []
func vector(c: Color)->Array: return [c.r,c.g,c.b]
func output_path()->String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="): return a.trim_prefix("--output=")
	return "res://result.json"
func finish(report:Dictionary,code:int)->void:
	var file:=FileAccess.open(output_path(),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")+"\n")
	print("Production flat-board probe: ",report.status)
	get_tree().quit(code)
func _ready()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="gl_compatibility":
		finish({"status":"NOT RUN","reason":"Native Compatibility framebuffer required","samples":[]},2)
		return
	for mode in ["stock","candidate"]:
		for ambient in [false,true]:
			for shadow in [false,true]:
				for geometry in ["clear","blocked","edge","backlit"]:
					await render_case(mode,ambient,shadow,geometry)
	validate()
	finish({"status":"candidate_pass" if failures.is_empty() else "candidate_fail","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"scope":"Synthetic opaque board only. Linear composition of current Godot flat-ambient contribution, NOT verified Unity SH. Uses current production binder; synthetic geometry only.","samples":samples,"failures":failures,"linear_tolerance":TOLERANCE},0 if failures.is_empty() else 1)
func material()->ShaderMaterial:
	var assets=preload("res://scripts/ui/visual_assets.gd").new()
	var path:="Shaders/SimpleLit.shadergraph"
	var digest:=preload("res://scripts/ui/source_lit_material.gd").BOARD_GRAPH_SHA256
	assets.manifest={"inputs":{path:digest}}
	assets.render_pipeline={"execution":{"mode":"render_graph","rule":"unity_6000_5_builtin_urp_17_5"},"selected_quality":0,"qualities":[{"pipeline_guid":"synthetic"}],"pipelines":{"synthetic":{"schema":"urp_renderer_list"}}}
	var contract={"schema_version":3,"geometry":"unmodified_object_vertices_tangent_normal","target":"universal_lit","workflow":"metallic","metallic":0,"smoothness":0,"opaque":true,"double_sided":false,"render_face":2,"cull_mode":"back","normal_policy":"inverse_transpose_no_face_flip","clearcoat":false,"material_override":false,"graph_sha256":digest}
	return Lit.board_material(assets,{"shader_source_path":path,"keywords":[],"source_lit":contract,"colors":{"_Color":{"r":COLOR.r,"g":COLOR.g,"b":COLOR.b,"a":1}}})
func render_case(mode:String,ambient:bool,shadow:bool,geometry:String)->void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(128,128)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world:=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color.BLACK
	preload("res://scripts/ui/source_world.gd").environment(world.environment,{"render_settings":{"m_AmbientMode":3,"m_AmbientSkyColor":{"r":AMBIENT.r,"g":AMBIENT.g,"b":AMBIENT.b,"a":1},"m_AmbientIntensity":1,"m_Fog":false}})
	if not ambient: world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	world.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	world.environment.tonemap_exposure=1
	viewport.add_child(world)
	var mesh:=MeshInstance3D.new()
	mesh.mesh=QuadMesh.new()
	mesh.mesh.size=Vector2(3,3)
	mesh.set_surface_override_material(0,material())
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var board:=Node3D.new()
	board.set_meta("source_prefab_guid","synthetic-source-board")
	viewport.add_child(board)
	board.add_child(mesh)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1
	camera.position=Vector3(0,0,3)
	camera.near=.1
	camera.far=20
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true
	var light:=DirectionalLight3D.new()
	light.rotation.y=deg_to_rad(135 if geometry=="backlit" else 45)
	light.light_color=LIGHT_COLOR
	light.light_energy=1
	light.shadow_enabled=shadow
	light.shadow_opacity=.7 # Actual Main/Island source strength; do not force opaque black shadows.
	light.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	viewport.add_child(light)
	if geometry in ["blocked","edge"]:
		var blocker:=MeshInstance3D.new()
		blocker.mesh=BoxMesh.new()
		blocker.mesh.size=Vector3(.3,.8,.3)
		blocker.position=Vector3(.5 if geometry=="blocked" else .75,0,.5)
		blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		viewport.add_child(blocker)
	if mode=="candidate":
		var binder:=Binder.new()
		viewport.add_child(binder)
		binder.bind(board,world.environment)
		if binder.active_count()!=1: failures.append("Production binder did not admit synthetic board")
	for i in 8:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	if image==null or image.is_empty() or image.get_size()!=Vector2i(128,128):
		failures.append("Missing/wrong framebuffer")
		viewport.queue_free()
		return
	var pixels:=[]
	for x in [32,48,62,63,64,65,80,96]:
		for y in [62,63,64,65]:
			var pixel:=image.get_pixel(x,y)
			pixels.append({"x":x,"y":y,"srgb":vector(pixel),"linear":vector(pixel.srgb_to_linear())})
	var id:="%s_ambient%d_shadow%d_%s" % [mode,int(ambient),int(shadow),geometry]
	var path:=output_path().get_basename()+"_"+id+".png"
	if image.save_png(path)!=OK: failures.append("Failed PNG "+id)
	samples.append({"id":id,"mode":mode,"ambient":ambient,"shadow":shadow,"geometry":geometry,"pixels":pixels,"png":path,"candidate_admitted":mesh.get_surface_override_material(0).get_meta("source_flat_linear_composition",false),"shadow_still_enabled":light.shadow_enabled,"shadow_opacity":light.shadow_opacity})
	viewport.queue_free()
	await get_tree().process_frame
func sample(mode:String,ambient:bool,shadow:bool,geometry:String)->Dictionary:
	for row in samples:
		if row.mode==mode and row.ambient==ambient and row.shadow==shadow and row.geometry==geometry: return row
	return {}
func difference(a:Dictionary,b:Dictionary)->float:
	if a.is_empty() or b.is_empty(): return INF
	var largest:=0.0
	for i in a.pixels.size():
		for c in 3: largest=maxf(largest,absf(a.pixels[i].linear[c]-b.pixels[i].linear[c]))
	return largest
func validate()->void:
	if samples.size()!=32: failures.append("Expected 32 cases, got %d" % samples.size())
	# Direct BRDF is algebraically unchanged, including real shadow attenuation.
	for shadow in [false,true]:
		for geometry in ["clear","blocked","edge","backlit"]:
			if difference(sample("stock",false,shadow,geometry),sample("candidate",false,shadow,geometry))>TOLERANCE:
				failures.append("Direct changed "+str(shadow)+geometry)
	for ambient in [false,true]:
		for geometry in ["clear","backlit"]:
			if difference(sample("candidate",ambient,false,geometry),sample("candidate",ambient,true,geometry))>TOLERANCE:
				failures.append("Candidate toggle mismatch "+str(ambient)+geometry)
		for geometry in ["clear","blocked","edge","backlit"]:
			if difference(sample("stock",ambient,false,geometry),sample("candidate",ambient,false,geometry))>TOLERANCE:
				failures.append("Unshadowed path changed "+str(ambient)+geometry)
	# Establish actual occlusion, not merely a shadow_enabled property assertion.
	if difference(sample("candidate",false,true,"clear"),sample("candidate",false,true,"blocked"))<.03:
		failures.append("Occluder did not measurably reduce direct light")
	# Under real occlusion the candidate's ambient increase must remain the same A,
	# within framebuffer quantization. No ambient-darkening with shadow attenuation.
	var base:=AMBIENT.srgb_to_linear()
	var decoded:=Color(COLOR.r*(COLOR.r*(COLOR.r*.305306011+.682171111)+.012522878),COLOR.g*(COLOR.g*(COLOR.g*.305306011+.682171111)+.012522878),COLOR.b*(COLOR.b*(COLOR.b*.305306011+.682171111)+.012522878))
	var expected:=vector(base*decoded)
	for geometry in ["clear","blocked","edge","backlit"]:
		var off:=sample("candidate",false,true,geometry)
		var on:=sample("candidate",true,true,geometry)
		for i in on.get("pixels",[]).size():
			for c in 3:
				if absf(on.pixels[i].linear[c]-off.pixels[i].linear[c]-expected[c])>TOLERANCE:
					failures.append("Ambient changed under attenuation "+geometry)
					return
