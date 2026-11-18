extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const SourceSlot = preload("res://scripts/ui/source_saved_slot.gd")
func _init() -> void: call_deferred("run")
func motion_at(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=pos; event.global_position=pos
	root.push_input(event,true)
func mouse(index: int, down: bool, pos: Vector2) -> void:
	motion_at(pos)
	var event := InputEventMouseButton.new()
	event.position=pos; event.global_position=pos; event.button_index=index; event.pressed=down
	root.push_input(event,true)
func center_of(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas()*(control.size*.5)
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
		var entry_at := center_of(board.title_load_button)
		mouse(MOUSE_BUTTON_LEFT,true,entry_at); mouse(MOUSE_BUTTON_LEFT,false,entry_at)
		await process_frame
		assert(board.title_saves.is_visible_in_tree(),"enter Saved Games through the mounted title button")
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
		var documents: Array = board.catalog.data.referenced_prefabs
		var candidates := documents.filter(func(item):return item.get("name")=="SavedGameSlot")
		assert(candidates.size()==1 and SourceSlot.source_pointer_admitted(board.catalog.data,candidates[0]))
		assert(not SourceSlot.source_pointer_admitted({},candidates[0]))
		var disabled_prefab: Dictionary = candidates[0].duplicate(true)
		for document in disabled_prefab.documents:
			if str(document.get("file_id"))=="1671686374944474514": document.fields.m_Enabled=0
		assert(not SourceSlot.source_pointer_admitted(board.catalog.data,disabled_prefab),
			"disabled exact TextButton cannot broaden the slot fallback")
		assert(row.load_button.button_mask==7 and row.archive_button.button_mask==7,
			"actual mounted row admits all three authored mouse buttons")
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
		var sound_proof: Array = []
		row.archive_button.play_click=func():
			sound_proof.append([board.archive_dialog.visible,board.selected_slot])
			board._play_ui_click()
		var archive_at := center_of(row.archive_button)
		var load_at := center_of(row.load_button)
		for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			var before_sounds := sound_proof.size()
			mouse(index,true,archive_at)
			assert(board.pending_archive_plan.is_empty(),"archive must be inert until release")
			mouse(index,false,Vector2(-100,-100))
			assert(board.pending_archive_plan.is_empty() and sound_proof.size()==before_sounds,"outside release cancels archive")
			await process_frame
			mouse(index,true,archive_at); mouse(index,false,archive_at)
			await process_frame
			assert(board.archive_dialog.visible and board.pending_archive_plan.slots==[1],
				"matching release requests the exact row's recoverable archive: %d" % index)
			assert(FileAccess.file_exists(board.slots.slot_path(1)),"no save removal on row button")
			assert(sound_proof.size()==before_sounds+1 and sound_proof.back()==[true,1],"one click after confirmation opens")
			for modal_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
				var ok_at := center_of(board.archive_dialog.get_ok_button())+Vector2(board.archive_dialog.position)
				mouse(modal_index,true,ok_at); mouse(modal_index,false,ok_at)
				mouse(modal_index,true,load_at); mouse(modal_index,false,load_at)
			assert(FileAccess.file_exists(board.slots.slot_path(1)) and not board.scene_transition.active(),
				"modal confirmation is not widened; held row cannot load through it")
			board._cancel_archive_slots()
			board.archive_dialog.hide()
			await process_frame
		# Cross the real scroll threshold before release over the same row.
		mouse(MOUSE_BUTTON_LEFT,true,archive_at)
		motion_at(archive_at+Vector2(0,11))
		motion_at(archive_at)
		assert(host.suppress_click,"live ScrollRect drag preserves suppression")
		mouse(MOUSE_BUTTON_LEFT,false,archive_at)
		assert(board.pending_archive_plan.is_empty(),"matching release after scroll cannot archive")
		await process_frame
		host.motion.position=0; host.motion.velocity=0; host._apply_motion()
		for secondary in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			var before_sounds := sound_proof.size()
			for pressed_first in [false,true]:
				if pressed_first: mouse(secondary,true,archive_at)
				mouse(MOUSE_BUTTON_LEFT,true,archive_at)
				motion_at(archive_at+Vector2(0,11))
				motion_at(archive_at)
				if not pressed_first: mouse(secondary,true,archive_at)
				mouse(MOUSE_BUTTON_LEFT,false,archive_at)
				await process_frame
				mouse(secondary,false,archive_at)
				assert(board.pending_archive_plan.is_empty() and sound_proof.size()==before_sounds,
					"secondary capture cannot resurrect a mixed left scroll drag")
				await process_frame
				host.motion.position=0; host.motion.velocity=0; host._apply_motion()
		mouse(MOUSE_BUTTON_RIGHT,true,archive_at)
		board._refresh_slots()
		assert(not row.is_visible_in_tree())
		mouse(MOUSE_BUTTON_RIGHT,false,archive_at)
		assert(board.pending_archive_plan.is_empty(),"a rebuilt list cancels a held stale row")
		await process_frame
		row=host.rows[0]
		row.load_button.disabled=true
		load_at=center_of(row.load_button)
		mouse(MOUSE_BUTTON_MIDDLE,true,load_at); mouse(MOUSE_BUTTON_MIDDLE,false,load_at)
		assert(not board.scene_transition.active(),"disabled save row load stays inert")
		row.load_button.disabled=false
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
		for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
			var loaded_row = board.source_saved_rows.rows[0]
			var reported: Array = []
			loaded_row.load_button.play_click=func():
				reported.append([board.scene_transition.active(),board.selected_slot])
				board._play_ui_click()
			var at := center_of(loaded_row.load_button)
			mouse(index,true,at)
			assert(not board.scene_transition.active(),"save load waits for release")
			mouse(index,false,Vector2(-100,-100)); await process_frame
			assert(reported.is_empty() and not board.scene_transition.active(),"outside release cancels load")
			mouse(index,true,at); mouse(index,false,at)
			assert(reported==[[true,1]],"one click after load transition begins: %d" % index)
			board._process(1); board._process(1); board.set_process(false)
			assert(board.running and board.active_slot==1)
			if index!=MOUSE_BUTTON_MIDDLE:
				board._return_title()
				board._open_title_saves()
				await process_frame
		print("Source saved rows board: PASS (real Title entry, L/R/M release and Click order, drag/hidden/modal guards, recoverable archive/restore and exact-slot load)")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()
