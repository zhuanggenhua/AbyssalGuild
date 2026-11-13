extends SceneTree
## Synthetic/headless checks, not display or physical-controller QA.
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
var quits := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func cancel(east: bool = false) -> InputEvent:
	if east:
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_B
		event.pressed = true
		return event
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event
func _init() -> void: call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	var board = Board.new()
	var path := "user://title-nav-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	board.slot_root = path + "/slots"
	board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	board.quit_callback = func(): quits += 1
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.title_home.visible and not board.title_preferences.visible and not board.title_saves.visible, "initial separate home")
	check(board.title_preferences.is_ancestor_of(board.duration) and board.title_saves.is_ancestor_of(board.slot_picker) and board.title_saves.is_ancestor_of(board.archive_picker) and board.title_saves.is_ancestor_of(board.legacy_picker), "controls preserved in destinations")
	var error: int = board.data_error
	for east in [false, true]:
		board.title_new_button.pressed.emit()
		board.title_new_button.pressed.emit()
		check(board.title_preferences.visible and board.title_home.visible == (board.source_title != null) and board.active_slot == 0 and not board.running and not FileAccess.file_exists(board.slots.slot_path(1)), "repeated New Game allocates nothing")
		board._unhandled_input(cancel(east))
		board.title_confirm_button.pressed.emit()
		check(board.title_home.visible and not board.running and board.active_slot == 0, "cancel invalidates stale Confirm")
	board.title_new_button.pressed.emit()
	board.title_cancel_button.pressed.emit()
	board._confirm_title_new_game()
	check(board.title_home.visible and board.active_slot == 0, "explicit Cancel invalidates Confirm")
	board.title_load_button.pressed.emit()
	board.title_load_button.pressed.emit()
	check(board.title_saves.visible and board.title_home.visible == (board.source_title != null) and not board.title_preferences.visible, "Load overlays saved games above source Home")
	check(board.source_title == null or (not board._text_button_allowed(board.title_new_button) and board.title_new_button.focus_mode == Control.FOCUS_NONE), "visible Home behind overlay cannot receive activation/focus")
	board.title_status.text = "Shared diagnostic"
	board.title_back_button.pressed.emit()
	check(board.title_home.visible and board.title_status.is_visible_in_tree() and board.title_status.text == "Shared diagnostic", "Back preserves shared errors")
	board.title_load_button.pressed.emit()
	board.archive_dialog.popup_centered()
	board.title_new_button.pressed.emit()
	board._open_options()
	board.title_back_button.pressed.emit()
	board._unhandled_input(cancel())
	check(board.title_saves.visible and board.archive_dialog.visible and not board.options_panel.visible, "archive modal priority")
	await process_frame
	root.push_input(cancel(true))
	await process_frame
	check(not board.archive_dialog.visible and board.title_saves.visible, "modal cancel does not also navigate")
	board._unhandled_input(cancel(true))
	check(board.title_home.visible, "next cancel returns home")
	board.title_new_button.pressed.emit()
	board._open_options()
	DirAccess.make_dir_absolute(board.options_path + ".tmp")
	board.options_panel._volume_changed(0.25, "sfx")
	board._unhandled_input(cancel())
	board._title_back()
	board._confirm_title_new_game()
	check(board.options_panel.visible and board.options_panel.dirty and board.title_preferences.visible and board.active_slot == 0 and board.options_panel.status_label.text.contains("Could not save"), "options save error blocks underlying back/Confirm")
	DirAccess.remove_absolute(board.options_path + ".tmp")
	board._unhandled_input(cancel(true))
	check(not board.options_panel.visible and board.title_preferences.visible, "recovery closes only options")
	board._title_back()
	board._confirm_title_new_game()
	check(board.active_slot == 0, "interrupted Confirm stale after Back")
	board.data_error = ERR_FILE_NOT_FOUND
	board.title_status.text = "Source data missing"
	board.title_new_button.pressed.emit()
	board.title_confirm_button.pressed.emit()
	check(not board.running and board.active_slot == 0 and board.title_preferences.visible and board.title_status.text == "Source data missing", "missing data retains diagnostic without allocation")
	board._title_back()
	board.title_quit_button.pressed.emit()
	board.title_new_button.pressed.emit()
	check(board.quit_dialog.visible and board.title_home.visible and quits == 0, "missing-data quit confirmation blocks navigation")
	board._cancel_quit()
	board.quit_dialog.hide()
	board._confirm_quit()
	check(quits == 0, "canceled quit stale")
	board.data_error = error
	if error == OK:
		board.title_new_button.pressed.emit()
		board.duration.value = 137
		board.friendly_choice.button_pressed = true
		board.title_confirm_button.pressed.emit()
		board.title_confirm_button.pressed.emit()
		check(not board.running and board.scene_transition.active(), "Confirm waits for black before slot creation")
		board.duration.value = 155
		board.friendly_choice.button_pressed = false
		board._process(1.0)
		board._process(1.0)
		board.set_process(false)
		check(board.running and board.active_slot == 1 and not FileAccess.file_exists(board.slots.slot_path(2)) and board.session.day_duration == 137 and board.session.friendly_mode, "Confirm creates exactly one slot with chosen prefs")
		board._return_title()
		board._confirm_title_new_game()
		check(board.title_home.visible and not board.running and board.active_slot == 1, "return title clears stale intent")
		board.title_load_button.pressed.emit()
		if board.source_saved_rows != null:
			board.source_saved_rows.rows[0].load_button.pressed.emit()
		else:
			board.continue_button.pressed.emit()
		board._process(1.0)
		board._process(1.0)
		board.set_process(false)
		check(board.running and board.active_slot == 1, "saved games Continue preserved")
		board._return_title()
		board._open_title_preferences()
		board.start_new()
		board.set_process(false)
		board._return_title()
		board._confirm_title_new_game()
		check(not board.running and board.active_slot == 2 and not FileAccess.file_exists(board.slots.slot_path(3)), "programmatic start supported and clears intent")
	else:
		print("SKIP: slot creation requires imported data")
	board.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("Title navigation board: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
