extends SceneTree
## Container/text bounds and title lifecycle. Rendered acceptance is separate.
const Board = preload("res://scripts/ui/board.gd")
class PointerProbe extends Node:
	var buttons: Array[int] = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			buttons.append(event.button_index)
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button: result.append(child)
		result.append_array(buttons(child))
	return result
func title_state(board) -> Array:
	return [board.camera.transform, board.camera.projection, board.camera.keep_aspect,
		board.camera.size, board.camera.fov, board.camera.near, board.camera.far,
		board.board_mesh.mesh.size, board.board_mesh.position,
		board.board_mesh.material_override.albedo_color, board.source_light.transform,
		board.source_light.light_color, board.source_light.light_energy,
		board.source_light.shadow_enabled, board.source_light.shadow_opacity]
func check_notice_bounds(board, context: String) -> void:
	var notice: Label = board.notice
	var background: StyleBox = notice.get_theme_stylebox("normal")
	check(board.hud.get_global_rect().encloses(notice.get_global_rect()), "notice fits HUD: " + context)
	check(notice.get_line_count() * notice.get_line_height() <= notice.size.y - background.get_minimum_size().y, "notice text fits backing: " + context)
	check(not notice.get_global_rect().intersects(board.detail_toggle.get_global_rect()), "notice leaves journal toggle clear: " + context)
	check(not notice.get_global_rect().intersects(Rect2(18, 835, 248, 40)), "notice leaves market toggle clear: " + context)
func test_notice(board) -> void:
	var background: StyleBox = board.notice.get_theme_stylebox("normal")
	check(background is StyleBoxFlat, "notice has a native flat backing on bright boards")
	if background is StyleBoxFlat:
		var foreground: Color = board.notice.get_theme_color("font_color")
		var light: float = foreground.srgb_to_linear().get_luminance()
		var dark: float = background.bg_color.srgb_to_linear().get_luminance()
		check(background.bg_color.a == 1.0 and foreground.a == 1.0, "notice colors remain opaque over white and cream boards")
		check((maxf(light, dark) + 0.05) / (minf(light, dark) + 0.05) >= 4.5, "notice style has at least 4.5:1 text contrast")
	check(board.notice.mouse_filter == Control.MOUSE_FILTER_IGNORE, "notice backing does not own board input")
	check(board.notice.focus_mode == Control.FOCUS_NONE, "notice is not an extra keyboard focus stop")
	for message in ["Arrived at Island · saved.", "Arrived at Island · SAVE FAILED: Could not write save file. Live game kept open; retry Save."]:
		board.notice.text = message
		await process_frame
		check_notice_bounds(board, message)
	var probe := PointerProbe.new()
	root.add_child(probe)
	# Exercise native Viewport routing over both glyphs and backing padding.
	for point in [board.notice.get_global_rect().position + Vector2(2, 2), board.notice.get_global_rect().get_center()]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		root.push_input(motion)
		await process_frame
		check(root.gui_get_hovered_control() == null, "notice does not suppress board hover")
		for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = button
			event.pressed = true
			root.push_input(event)
			event.pressed = false
			root.push_input(event)
		await process_frame
	check(probe.buttons == [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN], "notice passes clicks and wheel through to unhandled board input")
	probe.queue_free()
func _init() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	var board = Board.new()
	board.slot_root = "user://gui-layout-%d" % Time.get_ticks_usec()
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	var initial: Array = title_state(board)
	board.title_panel.hide()
	board.hud.show()
	board.market_panel.show()
	board.detail_panel.show()
	await process_frame
	await process_frame
	await test_notice(board)
	var tab_count := 0
	for button in buttons(board.detail_panel) + board.speed_buttons.values():
		var text_width: float = button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		var padding: float = button.get_theme_stylebox("normal").get_minimum_size().x
		check(button.size.x >= text_width + padding, "label fits actual button: " + button.text)
		check(board.hud.get_global_rect().encloses(button.get_global_rect()), "button fits HUD: " + button.text)
		if button.text in ["Quests", "Recipes"]:
			tab_count += 1
			check(button.size.x >= 90 and not button.clip_text, "journal tab has readable intrinsic and allocated width")
	check(tab_count == 2, "both journal destinations exposed")
	for size in [Vector2i(1280, 800), Vector2i(1233, 771)]:
		# Match canvas_items at the actual cloud/native 16:10 viewport sizes.
		root.content_scale_size = Vector2i(1440, 900)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.size = size
		await process_frame
		await process_frame
		check_notice_bounds(board, str(size))
		for button in buttons(board.detail_panel):
			check(button.size.x >= button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x + button.get_theme_stylebox("normal").get_minimum_size().x, "scaled sidebar text fits: %s %s" % [size, button.text])
	board.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	board.camera.fov = 30
	board.camera.position = Vector3(2, 10, 1)
	board.camera.h_offset = 0.5
	board.camera.v_offset = 0.5
	board.camera_motion.move_to(board.camera.position, Vector3.ONE, Vector3.DOWN)
	board.source_light.light_color = Color.ORANGE
	board.source_light.light_energy = 1
	board.source_light.shadow_enabled = true
	board.board_mesh.mesh.size = Vector3(12, 0.2, 8)
	board.board_mesh.material_override.albedo_color = Color.WHITE
	board.original_board = Node3D.new()
	board.add_child(board.original_board)
	var old_board: Node3D = board.original_board
	board.board_mesh.hide()
	board.panning = true
	board._show_title()
	check(title_state(board) == initial, "title restores first-launch camera, board and light")
	check(board.board_mesh.visible == (board.source_title == null) and board.original_board == null and not old_board.visible and old_board.is_queued_for_deletion(), "old private board hidden and released")
	check(board.camera.h_offset == 0 and board.camera.v_offset == 0 and board.camera_motion.focus.is_empty() and board.camera_motion.target == board.camera.position and not board.panning, "title clears shake, pending focus and panning")
	check(board.title_home.visible and not board.hud.visible, "title visibility reset")
	board._show_title()
	check(title_state(board) == initial, "repeated title restoration is stable")
	if board.data_error == OK:
		for _pass in range(2):
			board.start_new()
			board.set_process(false)
			check(board.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and board.camera.fov == 30 and board.geometry_key.begins_with("Main:"), "new game reapplies source gameplay framing")
			board._return_title()
			check(not board.running and title_state(board) == initial, "saved return restores native title world")
			board._continue_game()
			board.set_process(false)
			check(board.running and board.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and board.camera.fov == 30, "continue reapplies gameplay framing")
			board._show_title()
			check(title_state(board) == initial, "continue then title preserves first-launch presentation")
	else:
		print("SKIP: source gameplay/title round trips require private data")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("GUI layout and title reset: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
