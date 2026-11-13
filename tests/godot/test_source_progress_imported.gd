extends SceneTree
const Assets = preload("res://scripts/ui/visual_assets.gd")
const View = preload("res://scripts/ui/craft_progress_view.gd")
var checks := 0
var failures := 0
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var assets = Assets.new()
	check(assets.load_manifest() == OK,"required private manifest")
	for scene in ["Main","Island"]:
		var config: Dictionary = assets.progress_configuration(scene)
		check(config.size == {"x":.8,"y":.05} and config.image_type == 3 and config.fill_method == 0 and config.fill_origin == 0,scene+" source-filled metadata")
		var view = View.new(); root.add_child(view)
		view.bind_source(assets,scene)
		check(view.texture != null and view.texture.get_width()==64,scene+" original Square sprite loaded")
		view.sync({1:{"anchor":Vector3(3,0,4.55),"ratio":.35}})
		check(view.bars[1].root.position.is_equal_approx(Vector3(3,0,-4.55)),scene+" no source-absent lift")
		check((view.bars[1].root.basis * Vector3.UP).is_equal_approx(Vector3(0,0,-1)),scene+" effective Canvas rotation")
		var board: Node3D = assets.create_board_mesh(scene)
		check(board != null,scene+" required cached board FBX")
		if board != null:
			check(board.position.is_equal_approx(Vector3(0,-.05,0)),scene+" scene effective Y override")
			check(board.basis.z.is_equal_approx(Vector3(0,0,-1)),scene+" mesh reflected exactly once")
			board.free()
		view.queue_free()
	await process_frame
	print("Private source progress/board: %s (%d checks)" % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)
