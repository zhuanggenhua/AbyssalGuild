extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func send_button(index: int, down: bool, pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = down
	event.position = pos
	event.global_position = pos
	root.push_input(event, true)
func run() -> void:
	var board = Board.new()
	board.slot_root = "user://journal-header"
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	if board.data_error != OK:
		printerr("FAIL: private UIRoot required")
		board.free()
		quit(1)
		return
	board.start_new()
	await process_frame
	board.set_process(false)
	var drain = preload("res://tests/godot/source_test_audio_drain.gd").new()
	drain.observe_music(board.feedback.music)
	var q = board.journal_tabs.get_child(0)
	var r = board.journal_tabs.get_child(1)
	q.set_process(false)
	r.set_process(false)
	check(not q.source.is_empty() and not r.source.is_empty(), "exact separate Toggle metadata resolved")
	check(q.selected and not r.selected, "authored exclusive initial state")
	check(q.image != q.label and r.image != r.label, "graphic is not tint target")
	check(q.label.text == "Quests" and r.label.text == "Recipes", "authored TMP texts")
	check(q.image.color.is_equal_approx(Color(.21933962,.6486481,.8773585,1)), "authored graphic colour")
	check(q.label.get_meta("source_font_status") == "source_font_bound_native_layout", "exact private font bound")
	check(q.has_meta("source_baseline_down"), "private TMP face baseline used")
	check(is_equal_approx(q.size.x, r.size.x) and is_equal_approx(q.size.y,60), "equal native 200 by 60 layout")
	check(is_equal_approx(q.size.x,200), "source header width")
	q.advance_visual(.1,"Normal")
	r.advance_visual(.1,"Normal")
	check(q.image_alpha == 1 and r.image_alpha == 0, "stable initial graphic alpha")
	board.detail_panel.show()
	board.journal_bodies.quests.show()
	r.pressed.emit()
	check(board.active_tab == "recipes" and r.selected and not q.selected, "native pressed changes same owner/body")
	check(q.image_alpha == 1 and r.image_alpha == 0, "switch does not snap alpha")
	q.advance_visual(.05,"Pressed")
	r.advance_visual(.05,"Selected")
	check(is_equal_approx(q.image_alpha,.5) and is_equal_approx(r.image_alpha,.5), "midpoint graphic fades independent")
	check(is_equal_approx(q.label.modulate.r,(1+.78431374)/2), "label selectable tint interpolation")
	check(r.label.modulate.is_equal_approx(Color.WHITE), "selected label white while graphic fades")
	q.pressed.emit()
	q.advance_visual(.05,"Normal")
	r.advance_visual(.05,"Highlighted")
	check(is_equal_approx(q.image_alpha,.75) and is_equal_approx(r.image_alpha,.25), "rapid reversal starts at actual drawn alpha")
	q.advance_visual(.05,"Disabled")
	r.advance_visual(.05,"Highlighted")
	check(q.image_alpha == 1 and r.image_alpha == 0, "toggle ownership stable at endpoint")
	check(q.label.modulate.a < 1 and q.image.modulate.a == 1, "disabled target alpha does not fade checked image")
	q.pressed.emit()
	check(q.selected and not r.selected and board.active_tab == "quests", "repeated active click cannot switch group off")
	var before: float = q.image_alpha
	board._sync_source_info()
	check(q.image_alpha == before, "ordinary HUD sync does not reset animation")
	board.detail_panel.position = board.journal_slide.open_position
	await process_frame
	var point: Vector2 = r.get_global_transform_with_canvas() * (r.size/2)
	send_button(MOUSE_BUTTON_RIGHT, true, point)
	send_button(MOUSE_BUTTON_RIGHT, false, point)
	check(board.active_tab == "quests", "native right-button input does not activate Toggle")
	send_button(MOUSE_BUTTON_LEFT, true, point)
	check(board.active_tab == "quests", "native press does not activate before release")
	send_button(MOUSE_BUTTON_LEFT, false, point)
	check(board.active_tab == "recipes", "real viewport left click activates Recipes")
	board._show_journal_tab("quests")
	r.disabled = true
	send_button(MOUSE_BUTTON_LEFT, true, point)
	send_button(MOUSE_BUTTON_LEFT, false, point)
	check(board.active_tab == "quests", "native disabled Toggle rejects actual pointer")
	r.disabled = false
	q.set_selected(false, true)
	q.set_selected(true)
	q.advance_visual(.04,"Normal")
	q.pressed.emit()
	q.advance_visual(.03,"Normal")
	check(is_equal_approx(q.image_alpha,.58), "active re-click restarts only own unfinished CrossFadeAlpha")
	q.set_selected(false)
	q.set_process(true)
	Engine.time_scale = 0
	var until := Time.get_ticks_msec() + 160
	while Time.get_ticks_msec() < until: await process_frame
	await process_frame
	check(q.image_alpha == 0, "actual process uses unscaled wall time")
	Engine.time_scale = 1
	q.set_process(false)
	board.free()
	check(await drain.wait_after_teardown(self), "audio resources drained")
	print("Source journal header: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
