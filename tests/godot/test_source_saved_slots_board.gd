extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1440,900)
	var board = Board.new()
	var path := "user://source-slot-board-%d" % Time.get_ticks_usec()
	board.slot_root = path+"/slots"
	board.options_path = path+"/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	if board.source_saved_rows == null:
		print("Source saved rows board: SKIP (licensed catalog unavailable)")
	else:
		board.start_new()
		board.set_process(false)
		board._return_title()
		board.start_new()
		board.set_process(false)
		board._return_title()
		board._open_title_saves()
		await process_frame
		assert(board.source_saved_rows.rows.size() == 2)
		assert(not board.slot_picker.is_visible_in_tree() and not board.continue_button.is_visible_in_tree())
		var row = board.source_saved_rows.rows[0]
		assert(row.size.is_equal_approx(Vector2(760,100)))
		assert(row.info.get_meta("source_rect") == Rect2(10,10,600,80))
		assert(row.info.text.contains("Last Saved:") and not row.info.text.contains("File modified:"))
		assert(row.archive_button.text == "Archive")
		var host = board.source_saved_rows
		host.set_process(false)
		assert(host.motion.elasticity == 0.1 and host.motion.deceleration == 0.135 and host.drag_threshold == 10)
		assert(is_equal_approx(host.bar.fraction,host.motion.bar_fraction()))
		assert(host.bar.source.control.m_Direction==2 and host.bar.source.control.m_NumberOfSteps==0)
		assert(str(host.bar.source.image.m_Sprite.fileID)=="0")
		assert(is_equal_approx(host.bar.source.image.m_Color.r,0.638))
		assert(host.bar.repeat_delay==0.5 and host.bar.repeat_rate==0.1)
		assert(host.scroll_delta_per_tick==6)
		var center: Vector2 = host.get_global_transform_with_canvas()*Vector2(50,50)
		var press := InputEventMouseButton.new()
		press.position = center; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
		host._input(press)
		var drag := InputEventMouseMotion.new()
		drag.position = center+Vector2(0,9); host._input(drag)
		assert(not host.motion.dragging)
		drag.position = center+Vector2(0,11); host._input(drag)
		assert(host.motion.dragging and host.suppress_click)
		drag.position = center+Vector2(0,100); host._input(drag)
		assert(host.motion.position<0 and host.content.position.y>0)
		row.archive_button.pressed.emit()
		assert(not board.archive_dialog.visible)
		press.pressed = false; host._input(press)
		row.archive_button.pressed.emit()
		assert(not board.archive_dialog.visible)
		await process_frame
		assert(not host.suppress_click and not host.motion.dragging)
		var wheel := InputEventMouseButton.new()
		wheel.position=center; wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true; wheel.factor=1
		var before: float = host.motion.position
		host._input(wheel)
		assert(host.motion.position==before+6)
		wheel.position=host.get_global_transform_with_canvas()*Vector2(host.size.x-5,50)
		before=host.motion.position
		host._input(wheel)
		assert(host.motion.position==before+6) # Scrollbar raycast bubbles IScrollHandler to ScrollView too.
		host.motion.position=0; host.motion.velocity=0; host._apply_motion()
		row.archive_button._enter()
		assert(row.archive_button.underline)
		row.archive_button.pressed.emit()
		assert(board.archive_dialog.visible and board.pending_archive_plan.slots == [1])
		assert(FileAccess.file_exists(board.slots.slot_path(1)))
		row.load_button.pressed.emit()
		assert(not board.scene_transition.active())
		board._cancel_archive_slots()
		board.archive_dialog.hide()
		board.recovery_button.pressed.emit()
		await process_frame
		assert(board.recovery_window.visible and board.recovery_window.is_ancestor_of(board.archive_picker))
		row.archive_button.pressed.emit()
		assert(board.pending_archive_plan.is_empty())
		board._handle_escape()
		assert(not board.recovery_window.visible and board.title_saves.visible)
		row.archive_button.pressed.emit()
		board._confirm_archive_slots()
		await process_frame
		assert(board.source_saved_rows.rows.size() == 1 and not FileAccess.file_exists(board.slots.slot_path(1)))
		assert(not board.restore_archive_button.disabled)
		board.recovery_button.pressed.emit()
		board.restore_archive_button.pressed.emit()
		assert(FileAccess.file_exists(board.slots.slot_path(1)) and board.source_saved_rows.rows.size() == 2)
		board._close_recovery()
		board.source_saved_rows.rows[0].load_button.pressed.emit()
		board._process(1)
		board._process(1)
		board.set_process(false)
		assert(board.running and board.active_slot == 1)
		print("Source saved rows board: PASS (rows, hidden selector, source callbacks, modal guards, safe archive/restore/load, recovery focus)")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()
