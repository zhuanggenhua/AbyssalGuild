extends SceneTree
## Real Viewport routing with a source-free session; not physical input QA.
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func stroke(code: Key) -> void:
	root.push_input(key(code))
	await process_frame
	root.push_input(key(code, false))
	await process_frame

func _init() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	var board = Board.new()
	var path := "user://pause-input-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	board.options_path = path + "/options.json"
	board.slot_root = path + "/slots"
	board.legacy_paths.clear()
	board.options_apply_adapter = func(_plan): return {"ok": true, "capabilities": {}, "warnings": []}
	root.add_child(board)
	await process_frame
	board.set_process(false)
	var accepts: Array[InputEvent] = InputMap.action_get_events("ui_accept")
	board.title_new_button.grab_focus()
	await stroke(KEY_SPACE)
	check(board.title_preferences.visible and not board.running, "Space retains native title button activation")
	board._title_back()
	# Explicit test-only fixture. Production never substitutes an empty catalog.
	board.catalog.configure({})
	board.session.configure(board.catalog)
	board.title_panel.hide()
	board.hud.show()
	board.market_panel.show()
	board.running = true
	board._refresh()
	await process_frame
	var controls: Array = board.speed_buttons.values() + [board.pause_button, board.day_clock, board.day_button, board.detail_toggle]
	for control in controls:
		var fired := [0]
		var callback: Callable = func(): fired[0] += 1
		control.pressed.connect(callback)
		board.session.phase = "playing"
		board._refresh()
		control.grab_focus()
		check(root.gui_get_focus_owner() == control, "native focus reaches " + control.text)
		board.session.set_speed(2.0)
		await stroke(KEY_SPACE)
		check(board.session.paused and board.session.speed == 2.0 and board.session.phase == "playing" and fired[0] == 0, "Space pauses instead of activating focused " + control.text)
		root.push_input(key(KEY_SPACE, true, true))
		root.push_input(key(KEY_SPACE, false))
		await process_frame
		check(board.session.paused and fired[0] == 0, "echo/release cannot activate focused " + control.text)
		await stroke(KEY_SPACE)
		check(not board.session.paused and board.session.speed == 2.0 and fired[0] == 0, "second Space resumes once without changing speed")
		control.pressed.disconnect(callback)
	board.speed_buttons[1.0].grab_focus()
	await stroke(KEY_ENTER)
	check(board.session.speed == 1.0 and not board.session.paused, "Enter still activates the focused HUD button")
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		board.session.phase = phase
		board._refresh()
		await stroke(KEY_SPACE)
		check(not board.session.paused and board.session.phase == phase, "Space never changes pace during " + phase)
	board.session.phase = "playing"
	board._refresh()
	board._toggle_pause_menu()
	root.gui_release_focus()
	await stroke(KEY_SPACE)
	check(board.pause_overlay.visible and not board.session.paused, "unfocused pause menu does not toggle manual pause")
	board._toggle_pause_menu()
	board._open_options()
	board.options_panel.source_slider_adapters.get("sfx", board.options_panel.sliders.sfx).grab_focus()
	await stroke(KEY_SPACE)
	check(board.options_panel.visible and not board.session.paused, "options retain input ownership")
	board.options_panel.request_close()
	board._toggle_pause_menu()
	board.archive_dialog.popup_centered()
	await process_frame
	board.archive_dialog.get_cancel_button().grab_focus()
	await stroke(KEY_SPACE)
	check(not board.archive_dialog.visible and not board.session.paused, "native modal Space cancels without changing gameplay pace")
	check(InputMap.action_get_events("ui_accept") == accepts, "native accept bindings are unchanged")
	board.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Pause input: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
