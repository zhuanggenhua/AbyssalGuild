extends SceneTree
## Private scene lifecycle bindings, not rendered pixel equivalence.
const Board = preload("res://scripts/ui/board.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	board.slot_root = "user://source-world-%d" % Time.get_ticks_usec()
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	var title_color: Color = board.world_environment.ambient_light_color
	var title_energy: float = board.world_environment.ambient_light_energy
	for scene_name in ["Main", "Island", "Main"]:
		board.session.configure(board.catalog, 1, scene_name)
		board.session.start_new_game()
		var old: Node3D = board.source_background
		board._enter_game()
		board.set_process(false)
		check(board.source_background != null and board.source_background.get_child_count() == 1, scene_name + " background attached")
		if is_instance_valid(old): check(old.is_queued_for_deletion() and not old.visible, "old background hidden and released")
		var expected: Dictionary = board.visual_assets.scene_configuration(scene_name).render_settings
		var color: Dictionary = expected.m_AmbientSkyColor
		check(board.world_environment.ambient_light_color.is_equal_approx(Color(color.r,color.g,color.b)), scene_name + " source ambient")
		check(is_equal_approx(board.world_environment.ambient_light_energy, expected.m_AmbientIntensity), scene_name + " source ambient energy")
		await process_frame
	var old: Node3D = board.source_background
	board._restore_title_world()
	check(board.source_background == null, "Title removes gameplay-only plane")
	check(old.is_queued_for_deletion() and not old.visible, "Title hides and releases last plane")
	check(board.world_environment.ambient_light_color == title_color and board.world_environment.ambient_light_energy == title_energy, "Title restores documented native shell ambient")
	board._return_title()
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Source world scene lifecycle: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
