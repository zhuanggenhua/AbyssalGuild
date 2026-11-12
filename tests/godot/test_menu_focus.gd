extends SceneTree
## Actual Viewport keyboard routing using test-only empty gameplay data.
const Board = preload("res://scripts/ui/board.gd")
const MenuFocus = preload("res://scripts/ui/menu_focus.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func key(code: Key, pressed: bool = true, shift: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	return event

func stroke(code: Key, shift: bool = false) -> void:
	root.push_input(key(code, true, shift))
	await process_frame
	root.push_input(key(code, false, shift))
	await process_frame

func _init() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	var board = Board.new()
	var path := "user://menu-focus-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	board.options_path = path + "/options.json"
	board.slot_root = path + "/slots"
	board.legacy_paths.clear()
	board.options_apply_adapter = func(_plan): return {"ok": true, "capabilities": {}, "warnings": []}
	root.add_child(board)
	await process_frame
	board.set_process(false)
	board.catalog.configure({})
	board.session.configure(board.catalog)
	board.title_panel.hide()
	board.hud.show()
	board.market_panel.show()
	board.running = true
	board._refresh()
	await process_frame
	for pass_index in range(2):
		board.day_clock.grab_focus()
		await stroke(KEY_ESCAPE)
		check(board.pause_overlay.visible and root.gui_get_focus_owner() == board.pause_controls[0], "opening pause focuses Continue")
		root.gui_release_focus()
		await stroke(KEY_TAB)
		check(root.gui_get_focus_owner() == board.pause_controls[0], "lost pause focus recovers inside the menu")
		for index in range(6):
			await stroke(KEY_TAB)
			check(root.gui_get_focus_owner() == board.pause_controls[(index + 1) % 3], "Tab cycles only the three menu buttons")
		await stroke(KEY_TAB, true)
		check(root.gui_get_focus_owner() == board.pause_controls[2], "reverse Tab wraps within menu")
		await stroke(KEY_DOWN)
		check(root.gui_get_focus_owner() == board.pause_controls[0], "Down wraps within menu")
		await stroke(KEY_UP)
		check(root.gui_get_focus_owner() == board.pause_controls[2], "Up wraps within menu")
		await stroke(KEY_LEFT)
		await stroke(KEY_RIGHT)
		check(root.gui_get_focus_owner() == board.pause_controls[2], "horizontal navigation never reaches the HUD")
		board.pause_controls[1].grab_focus()
		await stroke(KEY_ENTER)
		var panel = board.options_panel
		check(panel.visible and root.gui_get_focus_owner() == panel.sliders.sfx, "Options starts at its first slider")
		var ring: Array = MenuFocus.loop(panel.focus_controls)
		check(ring.size() == 4, "unsupported graphics controls are excluded from the focus loop")
		root.gui_release_focus()
		await stroke(KEY_TAB, true)
		check(root.gui_get_focus_owner() == ring.back(), "lost options focus recovers inside options")
		panel.sliders.sfx.grab_focus()
		for index in range(8):
			await stroke(KEY_TAB)
			check(root.gui_get_focus_owner() == ring[(index + 1) % ring.size()], "options Tab cannot escape behind overlay")
		await stroke(KEY_TAB, true)
		check(root.gui_get_focus_owner() == ring.back(), "options reverse Tab wraps")
		panel.sliders.sfx.grab_focus()
		var volume: float = panel.sliders.sfx.value
		await stroke(KEY_LEFT)
		check(root.gui_get_focus_owner() == panel.sliders.sfx and panel.sliders.sfx.value < volume, "slider arrows still edit volume without losing focus")
		panel._request_reset()
		await process_frame
		await stroke(KEY_ESCAPE)
		check(panel.visible and not panel.reset_dialog.visible and board.pause_overlay.visible, "cancel reset keeps options and pause open")
		panel.sliders.bgm.grab_focus()
		DirAccess.make_dir_absolute(board.options_path + ".tmp")
		await stroke(KEY_ESCAPE)
		check(panel.visible and root.gui_get_focus_owner() == panel.sliders.bgm, "save failure keeps current options focus")
		DirAccess.remove_absolute(board.options_path + ".tmp")
		await stroke(KEY_ESCAPE)
		check(not panel.visible and board.pause_overlay.visible and root.gui_get_focus_owner() == board.pause_controls[1], "options close restores its menu opener")
		board.pause_controls[0].grab_focus()
		await stroke(KEY_SPACE)
		check(not board.pause_overlay.visible and root.gui_get_focus_owner() == board.day_clock and not board.session.paused, "Space on Continue restores HUD focus without toggling manual pause")
	# Return-target safety: a hidden control is not refocused on close.
	board.speed_buttons[1.0].grab_focus()
	await stroke(KEY_ESCAPE)
	board.market_panel.hide()
	await stroke(KEY_ESCAPE)
	check(root.gui_get_focus_owner() == board.day_clock, "hidden opener falls back to the visible day clock")
	# Opening options directly in gameplay still returns into its pause menu.
	board.day_clock.grab_focus()
	board._open_options()
	await stroke(KEY_ESCAPE)
	check(root.gui_get_focus_owner() == board.pause_controls[0] and board.pause_overlay.visible, "direct options entry has a safe pause return target")
	await stroke(KEY_ESCAPE)
	check(root.gui_get_focus_owner() == board.day_clock, "second cancel restores gameplay opener")
	board._show_title()
	board.title_new_button.grab_focus()
	board._open_options()
	await stroke(KEY_ESCAPE)
	check(board.title_panel.visible and root.gui_get_focus_owner() == board.title_new_button, "title options restore the title opener")
	var temporary := Button.new()
	root.add_child(temporary)
	var expired: WeakRef = weakref(temporary)
	temporary.queue_free()
	await process_frame
	MenuFocus.restore(expired, board.title_new_button)
	check(root.gui_get_focus_owner() == board.title_new_button, "freed return target safely uses fallback")
	board.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Menu focus: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
