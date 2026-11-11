extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Prefs = preload("res://scripts/ui/title_gameplay_prefs.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var isolated := "user://title-prefs-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	board.slot_root = isolated + "/slots"
	board.options_path = isolated + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "required actual source data loaded")
	if board.data_error != OK:
		board.queue_free()
		await process_frame
		quit(1)
		return
	check(Prefs.resolve(board.catalog.data).source_backed, "actual Title reference resolution")
	check(board.duration.min_value == 60 and board.duration.max_value == 180 and board.duration.step == 1 and board.duration.value == 120, "actual source initial slider config")
	check(board.duration_label.text == "Day Duration: 120 sec" and board.friendly_choice.text.contains("OFF"), "initial labels reflect controls")
	board.duration.value = 137
	board.friendly_choice.button_pressed = true
	check(board.duration.value == 137 and board.duration_label.text == "Day Duration: 137 sec" and board.friendly_choice.text.contains("No enemies will appear"), "arbitrary whole-second edit and live friendly label")
	board.start_new()
	board.set_process(false)
	check(board.running and board.session.day_duration == 137 and board.session.friendly_mode, "new game receives selected prefs")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(board._active_slot_path()))
	check(saved.scenes.Main.session.day_duration == 137 and saved.scenes.Main.session.friendly_mode, "initial native slot stores selected prefs")
	board._return_title()
	board.duration.value = 83
	board.friendly_choice.button_pressed = false
	check(board.duration_label.text == "Day Duration: 83 sec" and board.friendly_choice.text.contains("Enemies may appear"), "return and repeated edit refresh both labels")
	board.start_new()
	board.set_process(false)
	check(board.active_slot == 2 and board.session.day_duration == 83 and not board.session.friendly_mode, "second new game receives fresh controls")
	board._return_title()
	board.selected_slot = 1
	board._continue_game()
	board.set_process(false)
	check(board.session.day_duration == 137 and board.session.friendly_mode, "Continue restores saved prefs, not current title controls")
	board._return_title()
	var prior_slot: int = board.active_slot
	board.data_error = ERR_FILE_NOT_FOUND
	board.start_new()
	check(not board.running and board.active_slot == prior_slot, "missing game data still blocks new game despite fallback controls")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Title gameplay prefs board: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
