extends SceneTree
## Actual private FBX and production scene lifecycle, not framebuffer/Unity parity.
const Board = preload("res://scripts/ui/board.gd")
const Lit = preload("res://scripts/ui/source_lit_material.gd")
const Card = preload("res://scripts/ui/card_surface.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)
func _init()->void: call_deferred("run")
func run()->void:
	# Detect missing optional caches before constructing the live UI/audio owner.
	# The strict private runner freshly imports and rejects this explicit skip.
	var assets=preload("res://scripts/ui/visual_assets.gd").new()
	if assets.load_manifest()!=OK:
		print("Private flat board lighting: SKIP (licensed manifest missing)")
		quit()
		return
	for scene in ["Main","Island"]:
		var available=assets.create_board_mesh(scene)
		if available==null:
			print("Private flat board lighting: SKIP (actual FBX cache missing)")
			quit()
			return
		available.free()
	var board:=Board.new()
	board.slot_root="user://flat-board-private-%d" % Time.get_ticks_usec()
	board.options_path=board.slot_root+"/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.flat_board_lighting.active_count()==0,"Title untouched")
	for scene in ["Main","Island","Main"]:
		board.session.configure(board.catalog,1,scene)
		board.session.start_new_game()
		board._enter_game()
		board.set_process(false)
		board.flat_board_lighting.refresh()
		check(board.source_flat_environment_bound,scene+" actual environment/source light bound")
		check(board.flat_board_lighting.active_count()==2,scene+" both actual surfaces use linear composition")
		var source:Dictionary=board.visual_assets.scene_configuration(scene).render_settings
		var color:Dictionary=source.m_AmbientSkyColor
		check(board.world_environment.ambient_light_color.is_equal_approx(Color(color.r,color.g,color.b)),scene+" unchanged authored ambient")
		check(is_equal_approx(board.world_environment.ambient_light_energy,source.m_AmbientIntensity),scene+" unchanged ambient energy")
		check(board.source_light.shadow_enabled,scene+" real shadows remain enabled")
		var light:Dictionary=board.visual_assets.directional_light_configuration(scene)
		check(board.source_light.light_color.is_equal_approx(light.color) and is_equal_approx(board.source_light.light_energy,light.intensity),scene+" direct parameters unchanged")
		check(is_equal_approx(board.source_light.shadow_opacity,light.shadows.m_Strength),scene+" shadow strength unchanged")
		for record in board.flat_board_lighting.records:
			check(record.original.get_meta("source_board_cull", "")=="back" and record.replacement.shader.code.contains("cull_back") and not record.replacement.shader.code.contains("cull_disabled"),scene+" source cull retained by composition")
			check(record.original.shader.code==Lit.BOARD_FRAGMENT+Lit.DIRECT_LIGHT_CODE,scene+" exact original material retained")
			check(record.replacement.get_shader_parameter("source_base_color")==record.original.get_shader_parameter("source_base_color"),scene+" base color copied unchanged")
		var card_count:=0
		for view in board.views.values():
			if view.source_material!=null:
				card_count+=1
				check(view.source_material.shader.code==Card.SHADER.code+Lit.DIRECT_LIGHT_CODE,scene+" card fragment/light untouched")
		check(card_count>0,scene+" actual card/pack checked")
		var old=board.original_board
		board.geometry_key="force independent rebuild"
		board._update_board_geometry()
		check(board.original_board!=old and old.is_queued_for_deletion(),scene+" geometry recreated")
		check(board.flat_board_lighting.active_count()==2,scene+" regenerated geometry rebound")
		var extra:=DirectionalLight3D.new()
		root.add_child(extra) # Same World3D sibling, outside Board.
		board.flat_board_lighting.refresh()
		check(board.flat_board_lighting.active_count()==0,scene+" external sibling light safely restores originals")
		extra.free()
		board.flat_board_lighting.refresh()
		check(board.flat_board_lighting.active_count()==2,scene+" restored valid context re-enables")
		await process_frame
	board._restore_title_world()
	check(board.flat_board_lighting.active_count()==0 and board.flat_board_lighting.records.is_empty(),"Title clears all bindings")
	check(not board.source_flat_environment_bound,"Title cannot accidentally use gameplay flat context")
	board._return_title()
	board.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("Private flat board lighting: %s (%d checks; actual Main/Island FBX, no pixel claim)" % ["PASS" if failures==0 else "FAIL",checks])
	quit(1 if failures else 0)
