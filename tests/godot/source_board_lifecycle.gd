extends SceneTree
## Actual production Board GPU material lifecycle, NOT pixel/Unity equivalence.
## A single persistent Board world/light; no per-case WorldEnvironment recreation.
const Board = preload("res://scripts/ui/board.gd")
const Lit = preload("res://scripts/ui/source_lit_material.gd")
var board
var checks := 0
var failures: Array[String] = []
var steps: Array = []
var out := ""
var environment: Environment
var light: DirectionalLight3D
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ",label)
func write_report(status: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("lifecycle-report.json"),FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"status":status,"scope":_mode_label()+"; no pixel or Unity equivalence claim. Options display adapter disabled; game simulation processing stopped.","native_frame_boundaries":_requires_native(),"engine":Engine.get_version_info(),"checks":checks,"failures":failures,"steps":steps},"  "))
		f.flush();f.close()
func _requires_native() -> bool: return true
func _mode_label() -> String: return "Production GPU lifecycle"
func _frame_boundary() -> void: await RenderingServer.frame_post_draw
func settle() -> void:
	for i in 3:
		await process_frame
		await _frame_boundary()
func verify(label: String, active: bool) -> void:
	check(board.world_environment==environment and board.source_light==light,label+" persistent environment/light")
	check(board.flat_board_lighting.active_count()==(2 if active else 0),label+" active surfaces")
	check(board.flat_board_lighting.records.size()==2,label+" two actual surface bindings")
	for record in board.flat_board_lighting.records:
		var mesh=record.mesh.get_ref()
		check(is_instance_valid(mesh),label+" live FBX mesh")
		if not is_instance_valid(mesh):continue
		var material=mesh.get_surface_override_material(record.surface)
		check(material!=null and mesh.get_active_material(record.surface)!=null,label+" non-null actual material")
		check(record.original!=null and record.original.shader!=null and record.original.shader.code==Lit.BOARD_FRAGMENT+Lit.DIRECT_LIGHT_CODE,label+" original Cull.Back reference retained")
		check(material==(record.replacement if active else record.original),label+" exact expected reference bound")
	steps.append({"step":label,"active_count":board.flat_board_lighting.active_count(),"records":board.flat_board_lighting.records.size()})
	write_report("RUNNING")
	print("LIFECYCLE_STEP ",label," checks=",checks," failures=",failures.size())
func verify_scale(expected: float, label: String) -> void:
	for record in board.flat_board_lighting.records:
		var mesh=record.mesh.get_ref()
		if not is_instance_valid(mesh):continue
		var found := false
		for i in mesh.mesh.get_blend_shape_count():
			if mesh.mesh.get_blend_shape_name(i)=="Scale":
				found=true
				check(is_equal_approx(mesh.get_blend_shape_value(i),expected),label+" actual Scale weight "+str(expected))
		check(found,label+" actual Scale blend shape present")
func boost_roundtrip(label: String) -> void:
	# Deliberate diagnostic generation of existing source cards, NOT natural play.
	# Do not edit catalog definitions or bypass the production geometry updater.
	var guid := ""
	var amount := 0
	for key in board.catalog.definitions:
		var fields: Dictionary=board.catalog.fields(key)
		var candidate := int(fields.get("boostAmount",0))
		if candidate>amount:
			amount=candidate;guid=str(key)
	check(amount>0 and not guid.is_empty(),label+" existing source booster definition available")
	if amount<=0:return
	var base_limit:=int(board.catalog.settings("CardSettings").get("baseCardLimit",24))
	check(int(board.session.stats().card_limit)==base_limit,label+" starts at source base card limit")
	var generated: Array[int]=[]
	var old=weakref(board.original_board)
	var count:=int(ceil(100.0/float(amount)))
	for i in count:
		var id:int=board.session.spawn_card(guid,Vector2.ZERO,-1,{"refuse_attach":true})
		check(id>=0,label+" diagnostic source booster spawned")
		if id>=0:generated.append(id)
	board._update_board_geometry()
	await settle()
	check(int(board.session.stats().card_limit)>=base_limit+100,label+" source stats produce boost1")
	check(old.get_ref()==null,label+" pre-boost geometry released after settled frames")
	verify(label+" diagnostic boost1",true)
	verify_scale(1.0,label+" diagnostic boost1")
	steps.append({"step":label+" diagnostic generation","natural_gameplay":false,"generated_count":generated.size(),"source_boost_amount":amount,"card_limit":board.session.stats().card_limit})
	old=weakref(board.original_board)
	for id in generated:check(board.session.kill_card(id),label+" diagnostic booster removed")
	board._update_board_geometry()
	await settle()
	check(int(board.session.stats().card_limit)==base_limit,label+" restored source base limit")
	check(old.get_ref()==null,label+" boost1 geometry released after settled frames")
	verify(label+" restored boost0",true)
	verify_scale(0.0,label+" restored boost0")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):out=arg.trim_prefix("--output=")
	if out.is_empty():out=ProjectSettings.globalize_path("user://board-face-lifecycle-%d"%Time.get_ticks_usec())
	if _requires_native() and (DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="gl_compatibility"):
		write_report("NOT RUN: native Compatibility frame_post_draw required")
		print("Production GPU lifecycle: NOT RUN (headless/unsupported; no pixel claims)")
		quit(2);return
	board=Board.new()
	board.slot_root="user://board-face-lifecycle-%d/slots"%Time.get_ticks_usec()
	board.options_path=board.slot_root+"/options.json"
	board.legacy_paths.clear()
	board.options_apply_adapter=func(_plan):return {"ok":true,"capabilities":{},"warnings":["Lifecycle probe leaves display options unchanged"]}
	root.add_child(board)
	board.set_process(false)
	await settle()
	environment=board.world_environment;light=board.source_light
	check(board.data_error==OK,"private source catalog loaded")
	check(board.flat_board_lighting.active_count()==0,"initial Title has no board bindings")
	if board.data_error!=OK:
		board.queue_free();await settle();write_report("FAIL");quit(1);return
	var turn := 0
	for scene in ["Main","Island","Main"]:
		turn+=1
		var label:="%d_%s"%[turn,scene]
		board.session.configure(board.catalog,1,scene)
		board.session.start_new_game()
		board._enter_game()
		board.set_process(false)
		await settle()
		verify(label+" entered",true)
		check(board.source_light.shadow_enabled,label+" source shadows retained")
		var old=weakref(board.original_board)
		board.geometry_key="lifecycle force real rebuild"
		board._update_board_geometry()
		await settle()
		check(old.get_ref()==null,label+" old geometry released after settled frames")
		verify(label+" geometry rebuilt",true)
		await boost_roundtrip(label)
		var extra:=DirectionalLight3D.new()
		root.add_child(extra) # Same persistent World3D, outside Board subtree.
		await settle()
		verify(label+" extra-light fallback",false)
		extra.queue_free()
		await settle()
		verify(label+" extra-light removed",true)
		var meshes: Array=[]
		for record in board.flat_board_lighting.records:
			var mesh=record.mesh.get_ref()
			if is_instance_valid(mesh) and not meshes.has(mesh):meshes.append(mesh)
		for mesh in meshes:mesh.transparency=.2
		await settle()
		verify(label+" transparency fallback",false)
		for mesh in meshes:mesh.transparency=0
		await settle()
		verify(label+" opaque restored",true)
	board._restore_title_world()
	await settle()
	check(board.flat_board_lighting.active_count()==0 and board.flat_board_lighting.records.is_empty(),"Title clears all bindings after settled frames")
	check(not board.source_flat_environment_bound and board.original_board==null,"Title leaves no source board")
	check(board.world_environment==environment and board.source_light==light,"Title retains single persistent world/light")
	steps.append({"step":"Title cleanup","active_count":0})
	write_report("RUNNING")
	board._return_title()
	# Final owner destruction must also safely release an active shared FBX.
	board.session.configure(board.catalog,1,"Main")
	board.session.start_new_game()
	board._enter_game()
	board.set_process(false)
	await settle()
	verify("final active world before owner deletion",true)
	var final_geometry=weakref(board.original_board)
	board.queue_free()
	await settle()
	check(final_geometry.get_ref()==null,"active source geometry freed with owner")
	write_report("PASS" if failures.is_empty() else "FAIL")
	print(_mode_label()+": ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size(),"; no pixel equivalence claim; runner MUST also reject engine error logs")
	quit(0 if failures.is_empty() else 1)
