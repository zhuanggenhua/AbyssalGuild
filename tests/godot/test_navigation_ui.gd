extends SceneTree
## Synthetic input/confirmation routing, not physical-controller or visual QA.
const Board = preload("res://scripts/ui/board.gd")
var checks: int = 0
var failures: int = 0
var quit_calls: int = 0
var serial: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func key(pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = pressed
	event.echo = echo
	return event

func east(pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_B
	event.pressed = pressed
	event.device = 3
	return event

func fake_apply(_plan: Dictionary) -> Dictionary:
	return {"ok": true, "capabilities": {}, "warnings": []}

func fake_quit() -> void:
	quit_calls += 1

func make_board():
	serial += 1
	var board = Board.new()
	var directory: String = "user://navigation-%d-%d" % [Time.get_ticks_usec(), serial]
	DirAccess.make_dir_recursive_absolute(directory)
	board.options_path = directory + "/options.json"
	board.options_apply_adapter = fake_apply
	board.slot_root = directory + "/slots"
	board.legacy_paths.clear()
	board.quit_callback = fake_quit
	root.add_child(board)
	await process_frame
	board.set_process(false)
	return board

func cancel_modal(event: InputEvent) -> void:
	await process_frame
	root.push_input(event)
	await process_frame

func discard_board(board) -> void:
	board.queue_free()
	await process_frame

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	var board = await make_board()
	check(board.title_panel.visible and board.title_quit_button.text == "Quit Game", "title offers an explicit Quit Game control even without imported data")
	for event in [key(), east(), key(false), key(true, true), east(false)]:
		board._unhandled_input(event)
	check(quit_calls == 0 and not board.quit_dialog.visible, "title cancel/release/echo never quits or opens a confirmation")
	board.title_quit_button.pressed.emit()
	check(board.quit_dialog.visible and board.pending_quit == "title" and quit_calls == 0, "Title Quit asks before invoking the injected quit callback")
	board.title_quit_button.pressed.emit()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	board._handle_escape()
	check(board.quit_dialog.visible and board.pending_quit == "title" and quit_calls == 0, "repeated requests and window-close cannot bypass the title confirmation")
	await cancel_modal(east())
	check(not board.quit_dialog.visible and board.pending_quit.is_empty() and quit_calls == 0, "gamepad East declines Title Quit through native cancel routing")
	board._confirm_quit()
	check(quit_calls == 0, "a canceled confirmation cannot be replayed")
	board._request_title_quit()
	await cancel_modal(key())
	check(not board.quit_dialog.visible and quit_calls == 0, "Escape declines Title Quit without exiting")
	board.archive_dialog.popup_centered()
	board._request_title_quit()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(board.archive_dialog.visible and not board.quit_dialog.visible and quit_calls == 0, "an existing archive modal blocks competing quit requests")
	await cancel_modal(east())
	check(not board.archive_dialog.visible and quit_calls == 0, "gamepad cancels archive without confirming it")
	board._open_options()
	var panel = board.options_panel
	panel._request_reset()
	var before_reset: Dictionary = panel.model.snapshot()
	board._unhandled_input(east())
	board._request_title_quit()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(panel.visible and panel.reset_dialog.visible and not board.quit_dialog.visible and quit_calls == 0, "options reset modal blocks underlying options-close and quit actions")
	await cancel_modal(east())
	check(panel.visible and not panel.reset_dialog.visible and panel.model.snapshot() == before_reset, "gamepad dismisses reset confirmation without resetting or closing options")
	board._request_title_quit()
	check(not board.quit_dialog.visible, "title button cannot quit through an open options panel")
	DirAccess.make_dir_absolute(board.options_path + ".tmp")
	panel._volume_changed(0.25, "sfx")
	board._unhandled_input(east())
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(panel.visible and panel.dirty and quit_calls == 0 and panel.status_label.text.contains("Could not save"), "gamepad cancel and window-close preserve options after save failure")
	DirAccess.remove_absolute(board.options_path + ".tmp")
	board._unhandled_input(east())
	check(not panel.visible and quit_calls == 0, "retrying cancel after options storage recovers closes only options")
	board._request_title_quit()
	board.quit_dialog.get_ok_button().pressed.emit()
	board._confirm_quit()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(quit_calls == 1 and board.quit_dispatched and board.pending_quit.is_empty(), "Title Quit acceptance invokes the injected callback exactly once")
	var has_source: bool = board.data_error == OK
	await discard_board(board)
	board = await make_board()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(quit_calls == 2 and not board.quit_dialog.visible, "ordinary title window-close keeps the existing direct quit behavior")
	await discard_board(board)
	if has_source:
		await test_gameplay()
	else:
		print("SKIP: navigation gameplay/save/ending checks require licensed imported data.")
	print("Navigation UI checks: %d passed / %d total" % [checks - failures, checks])
	await create_timer(0.2).timeout
	quit(0 if failures == 0 else 1)

func test_gameplay() -> void:
	var board = await make_board()
	var initial_quits: int = quit_calls
	board._request_title_quit()
	board.start_new()
	board.set_process(false)
	board._confirm_quit()
	check(board.running and quit_calls == initial_quits, "stale title confirmation cannot quit a newly started game")
	board.session.set_speed(2.0)
	board.session.elapsed = 20.0
	root.push_input(east())
	await process_frame
	check(board.pause_overlay.visible, "viewport gamepad input reaches gameplay cancel routing")
	root.push_input(key(true, true))
	await process_frame
	check(board.pause_overlay.visible, "viewport key echo does not dismiss the gameplay menu")
	root.push_input(key())
	await process_frame
	check(not board.pause_overlay.visible, "viewport keyboard input closes a gamepad-opened menu")
	for event in [key(false), key(true, true), east(false)]:
		board._unhandled_input(event)
	check(not board.pause_overlay.visible, "releases and key echo do not open gameplay pause")
	board._unhandled_input(east())
	board._process(2.0)
	check(board.pause_overlay.visible and board.session.elapsed == 20.0, "gamepad East opens an external pause that freezes gameplay time")
	check(board.session.speed == 2.0 and not board.session.paused, "external pause preserves selected fast pace")
	for event in [key(false), key(true, true), east(false)]:
		board._unhandled_input(event)
	check(board.pause_overlay.visible, "releases and echo do not close gameplay pause")
	board._unhandled_input(key())
	check(not board.pause_overlay.visible and board.session.speed == 2.0, "keyboard can close the menu opened by a gamepad")
	board.session.set_paused(true)
	board._unhandled_input(east())
	board._unhandled_input(east())
	check(board.session.paused and not board.pause_overlay.visible, "distinct repeated presses preserve manual pause across a menu roundtrip")
	board.session.set_paused(false)
	board._open_options()
	board._unhandled_input(east())
	check(not board.options_panel.visible and board.pause_overlay.visible, "gamepad closes gameplay options back to the pause menu")
	board._unhandled_input(key())
	check(not board._ui_pause_active() and board.session.speed == 2.0, "second cancel resumes the preserved pace")
	board._open_options()
	board.options_panel._request_reset()
	await cancel_modal(key())
	check(board.options_panel.visible and board.pause_overlay.visible and not board.options_panel.reset_dialog.visible, "native modal cancel does not also close gameplay options or resume the menu")
	board._unhandled_input(east())
	board._unhandled_input(key())
	var checkpoint: String = FileAccess.get_file_as_string(board._active_slot_path())
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		board.session.phase = phase
		board._unhandled_input(east())
		board._unhandled_input(key())
		board._open_options()
		board._request_title_quit()
		check(not board.pause_overlay.visible and not board.options_panel.visible and not board.quit_dialog.visible and board.session.phase == phase, phase + " blocks pause/options/title-quit entry")
		board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		check(board.quit_dialog.visible and board.pending_quit == "day_end" and board.quit_dialog.dialog_text.contains("not autosaved") and quit_calls == initial_quits, phase + " window-close retains a single day-end warning")
		await cancel_modal(east())
		check(not board.quit_dialog.visible and board.pending_quit.is_empty() and quit_calls == initial_quits, phase + " gamepad decline never quits")
		check(FileAccess.get_file_as_string(board._active_slot_path()) == checkpoint, phase + " cancel leaves the last checkpoint unchanged")
	board.game_over_dialog.popup_centered()
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(board.game_over_dialog.visible and not board.quit_dialog.visible, "game-over archive confirmation blocks a competing close warning")
	await cancel_modal(east())
	check(board.running and board.session.phase == "game_over" and not board.game_over_dialog.visible and FileAccess.get_file_as_string(board._active_slot_path()) == checkpoint, "gamepad declines game-over return without archiving the active slot")
	board.session.phase = "feeding"
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	board.session.phase = "playing"
	board._confirm_quit()
	check(quit_calls == initial_quits and board.pending_quit.is_empty(), "stale day-end confirmation cannot bypass a resumed playing checkpoint")
	board.session.elapsed = 31.0
	DirAccess.make_dir_absolute(board._active_slot_path() + ".tmp")
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(quit_calls == initial_quits and not board.quit_dialog.visible and not board.quit_dispatched, "failed gameplay checkpoint blocks quit instead of bypassing it with confirmation")
	check(FileAccess.get_file_as_string(board._active_slot_path()) == checkpoint, "failed quit checkpoint preserves the previous save")
	DirAccess.remove_absolute(board._active_slot_path() + ".tmp")
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved: String = FileAccess.get_file_as_string(board._active_slot_path())
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(quit_calls == initial_quits + 1 and saved != checkpoint and FileAccess.get_file_as_string(board._active_slot_path()) == saved, "successful gameplay close checkpoints and dispatches quit once")
	await discard_board(board)
	board = await make_board()
	board.start_new()
	board.set_process(false)
	checkpoint = FileAccess.get_file_as_string(board._active_slot_path())
	board.session.phase = "ready"
	board._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	board.quit_dialog.get_ok_button().pressed.emit()
	board._confirm_quit()
	check(quit_calls == initial_quits + 2 and FileAccess.get_file_as_string(board._active_slot_path()) == checkpoint, "confirmed day-end quit dispatches once without overwriting the last checkpoint")
	await discard_board(board)
