extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var folder := "user://options-audio-life-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	board.slot_root = folder + "/slots"
	board.options_path = folder + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	if board.data_error != OK:
		print("SKIP: options scene lifecycle requires private catalog")
		board.queue_free(); await process_frame; quit(); return
	var options = board.options_panel
	var owner: int = board.feedback.get_instance_id()
	options.open(); options.request_close()
	check(options.volume_initialized, "Title first activation establishes one Start")
	board._open_title_preferences(); board._title_back()
	board._open_title_saves(); board._title_back()
	check(options.volume_initialized, "Title prefs/save navigation does not recreate source Options")
	board._show_title()
	check(options.volume_initialized, "re-show same Title is not scene creation")
	board.selected_slot = 999999
	board._continue_game()
	check(not board.running and options.volume_initialized, "failed load leaves existing Title lifecycle intact")
	board.start_new()
	check(board.running and board.session.scene_name == "Main" and not options.volume_initialized, "successful Title-to-Main recreates source Options lifecycle")
	options.open(); options.request_close()
	check(options.volume_initialized, "Main first activation runs its own Start")
	# Synthetic scene-change notification exercises the actual scene binding route,
	# not recipe mechanics (travel mechanics have their separate source suite).
	board.session.scene_name = "Island"
	board._on_session_event("scene_changed", {})
	check(not options.volume_initialized and board.feedback.get_instance_id() == owner, "Main-to-Island rebuilds Options but preserves AudioManager owner")
	options.open(); options.request_close()
	board._show_title()
	check(not board.running and not options.volume_initialized and board.feedback.get_instance_id() == owner, "Island-to-Title creates Options lifecycle without recreating AudioManager")
	options.open(); options.request_close()
	board._show_title()
	check(options.volume_initialized, "repeated same Title presentation does not rerun Start")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Options audio scene lifecycle: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
