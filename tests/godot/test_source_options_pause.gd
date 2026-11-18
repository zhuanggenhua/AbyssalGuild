extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
func _init() -> void: call_deferred("run")
var close_signals := 0
var click_sounds := 0
func click_at(index: int, down: bool, position: Vector2):
	var motion := InputEventMouseMotion.new()
	motion.position = position; motion.global_position = position; root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = index; event.pressed = down; event.position = position; event.global_position = position
	root.push_input(event, true)
func run() -> void:
	root.gui_embed_subwindows = true
	var board = Board.new()
	board.options_path = "user://source-options-test.json"
	board.slot_root = "user://source-options-slots"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	if board.options_panel.source_view == null:
		assert(board.options_panel.close_button.button_mask == MOUSE_BUTTON_MASK_LEFT)
		for button in board.pause_controls: assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT)
		print("Source Options/Pause layout: SKIP (licensed source unavailable)")
	else:
		var options = board.options_panel
		for key in options.buttons:
			assert(options.buttons[key].button_mask == 7,"source graphics TextButton accepts three mouse buttons: "+key)
		assert(options.reset_button.button_mask == MOUSE_BUTTON_MASK_LEFT)
		assert(options.close_button.button_mask == 7)
		var view = options.source_view
		var panel: Control = view.nodes[view.layout.resolve("MainPanel")]
		assert(panel.size.is_equal_approx(Vector2(400,670)))
		assert(options.buttons.resolution.get_parent() == view.nodes[view.layout.resolve("MainPanel/ResolutionButton")])
		assert(options.sliders.sfx.step == 0 and options.sliders.bgm.step == 0)
		assert(options.source_slider_adapters.size() == 2)
		assert(board.duration_adapter != null and board.friendly_adapter != null)
		var pause = board.pause_overlay.get_child(board.pause_overlay.get_child_count()-1)
		var pause_panel: Control = pause.nodes[pause.layout.resolve("MainPanel")]
		assert(pause_panel.size.is_equal_approx(Vector2(400,290)))
		assert(board.pause_controls[0].text == "Continue to Play")
		assert(board.pause_controls[2].text == "Quit to Title & Save")
		board._open_title_preferences()
		await process_frame
		assert(root.gui_get_focus_owner() == board.duration_adapter)
		var value: float = board.duration.value
		var event := InputEventAction.new()
		event.action = "ui_right"
		event.pressed = true
		board.duration_adapter._gui_input(event)
		assert(board.duration.value == value+1)
		options.open()
		# Native QA exposed no-signal model refresh leaving the handle at zero.
		for channel in ["sfx", "bgm"]:
			var adapter = options.source_slider_adapters[channel]
			var track: Rect2 = adapter.Metadata.rectangle(adapter.metadata.handle_parent, adapter.size)
			assert(is_equal_approx(adapter.handle.position.x + adapter.handle.size.x / 2, track.position.x + track.size.x * adapter.normalized()), "Source slider geometry must reflect loaded options")
		var old_friendly: bool = board.friendly_choice.button_pressed
		board.friendly_adapter._activate()
		assert(board.friendly_choice.button_pressed == old_friendly) # Overlay guard.
		assert(root.gui_get_focus_owner() == options.source_slider_adapters.sfx)
		var retained_value: float = options.sliders.sfx.value
		options.request_close()
		options.model.set_volume("sfx", 0.25)
		options.open()
		var slider = options.source_slider_adapters.sfx
		var track: Rect2 = slider.Metadata.rectangle(slider.metadata.handle_parent, slider.size)
		assert(is_equal_approx(slider.normalized(), retained_value))
		assert(is_equal_approx(slider.handle.position.x + slider.handle.size.x / 2, track.position.x + track.size.x * retained_value), "Reopening same source instance does not run Start again")
		options.request_close()
		board._title_back()
		options.closed.connect(func(): close_signals += 1)
		options.play_click = func(): click_sounds += 1
		for index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			board._open_options(); await process_frame
			var pos: Vector2 = options.close_button.get_global_rect().get_center()
			var old := close_signals
			click_at(index, true, pos)
			assert(options.visible and close_signals == old, "Close is not invoked on press")
			click_at(index, false, Vector2(-100,-100)); await process_frame
			assert(options.visible and close_signals == old, "outside release cancels Close")
			click_at(index, true, pos); click_at(index, false, pos); await process_frame
			assert(not options.visible and close_signals == old+1, "one Close on matching release")
			assert(click_sounds == close_signals and FileAccess.file_exists(options.path), "save and hide, then one click sound")
			click_at(index, true, pos); click_at(index, false, pos); await process_frame
			assert(close_signals == old+1, "hidden panel is inert")
		board._open_options(); await process_frame
		var pos: Vector2 = options.close_button.get_global_rect().get_center()
		var old := close_signals
		options.reset_dialog.popup_centered(); await process_frame
		for index in [1,2,3]:
			click_at(index, true, pos); click_at(index, false, pos)
		assert(options.visible and close_signals == old, "reset modal owns input")
		options.reset_dialog.hide(); await process_frame
		options.close_button.disabled = true
		click_at(2, true, pos); click_at(2, false, pos)
		assert(options.visible and close_signals == old, "disabled Close remains inert")
		options.close_button.disabled = false
		var save_path: String = options.path
		options.path = "user://absent-close-dir/options.json"
		options.load_warning = false
		click_at(3, true, pos); click_at(3, false, pos); await process_frame
		assert(options.visible and options.dirty and close_signals == old, "failed save keeps Options open")
		assert(click_sounds == old+1, "admitted failed-save action still emits source click sound")
		options.path = save_path
		click_at(3, true, pos)
		options.reset_source_lifecycle(); await process_frame
		click_at(3, false, pos)
		assert(not options.visible and close_signals == old, "reset lifecycle invalidates pending close")
		board._open_options(); await process_frame
		pos = options.close_button.get_global_rect().get_center()
		click_at(2, true, pos); click_at(2, false, pos); await process_frame
		assert(not options.visible and close_signals == old+1, "reopen uses same save-and-close action")
		var original: Dictionary = board.catalog.data
		options.close_button.button_mask = MOUSE_BUTTON_MASK_LEFT
		assert(not options._admit_source_close_pointer({}, view))
		var bad: Dictionary = original.duplicate(true)
		bad.provenance.source_commit = "wrong"
		assert(not options._admit_source_close_pointer(bad, view))
		for mutation in ["controller_disabled", "wrong_reference", "button_disabled", "wrong_gameobject", "wrong_script"]:
			bad = original.duplicate(true)
			for prefab in bad.referenced_prefabs:
				if prefab.name != "GameOptionsUI": continue
				for document in prefab.documents:
					if str(document.file_id) == "98810512149128886":
						if mutation == "controller_disabled": document.fields.m_Enabled = 0
						if mutation == "wrong_reference": document.fields.closeButton.fileID = "0"
					if str(document.file_id) == "3374842419896805458":
						if mutation == "button_disabled": document.fields.m_Enabled = 0
						if mutation == "wrong_gameobject": document.fields.m_GameObject.fileID = "0"
						if mutation == "wrong_script": document.fields.m_Script.guid = "wrong"
			assert(not options._admit_source_close_pointer(bad, view), mutation)
		assert(options.close_button.button_mask == MOUSE_BUTTON_MASK_LEFT)
		var host = options.close_button.get_parent()
		options.close_button.reparent(options)
		assert(not options._admit_source_close_pointer(original, view), "wrong mounted host rejected")
		options.close_button.reparent(host)
		assert(options._admit_source_close_pointer(original, view))
		assert(options.reset_button.button_mask == MOUSE_BUTTON_MASK_LEFT)
		print("Source Options Close: PASS (actual sequential L/R/M, outside, modal, disabled, save failure, hidden/reopen lifecycle, provenance and serialized graph)")
		await verify_pause_pointer(board,pause)
		print("Source Options/Pause layout: PASS (source tree, preferred sizes, control refs, focus, modal guards)")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()

func click(index: int, position: Vector2) -> void:
	click_at(index, true, position)
	click_at(index, false, position)

func verify_pause_pointer(board, view) -> void:
	board.start_new()
	assert(board.running and board.active_slot>0)
	var options = board.options_panel
	var played: Array[String] = []
	board.pause_controls[0].play_click = func(): played.append("continue:" + str(board.pause_overlay.visible))
	board.pause_controls[1].play_click = func(): played.append("options:" + str(options.visible))
	board.pause_controls[2].play_click = func(): played.append("title:" + str(board.scene_transition.active()))
	for index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
		var cancel := InputEventKey.new()
		cancel.keycode = KEY_ESCAPE; cancel.pressed = true
		root.push_input(cancel)
		cancel = InputEventKey.new()
		cancel.keycode = KEY_ESCAPE; cancel.pressed = false
		root.push_input(cancel)
		await process_frame
		assert(board.pause_overlay.visible and not options.visible)
		var old := played.size()
		var option_pos: Vector2 = board.pause_controls[1].get_global_rect().get_center()
		click_at(index,true,option_pos)
		assert(not options.visible and played.size()==old,"Pause Options does not trigger on mouse down")
		click_at(index,false,Vector2(-100,-100))
		assert(not options.visible and played.size()==old,"Pause Options cancels outside release")
		click(index,option_pos); await process_frame
		assert(options.visible and board.pause_overlay.visible and played.size()==old+1 and played.back()=="options:true",
			"Pause Options mouse%d opens actual sibling before its one Click" % index)
		click(index,option_pos)
		assert(options.visible and played.size()==old+1,"Options sibling does not pass a click back to Pause")
		click(index,options.close_button.get_global_rect().get_center()); await process_frame
		assert(not options.visible and board.pause_overlay.visible,"Options Close returns to existing Pause")
		var continue_pos: Vector2 = board.pause_controls[0].get_global_rect().get_center()
		click_at(index,true,continue_pos)
		assert(board.pause_overlay.visible and played.size()==old+1)
		click_at(index,false,continue_pos); await process_frame
		assert(not board.pause_overlay.visible and board.running and played.size()==old+2 and played.back()=="continue:false",
			"Continue mouse%d resumes current session before its one Click" % index)
		board._toggle_pause_menu()
		await process_frame
		var title_pos: Vector2 = board.pause_controls[2].get_global_rect().get_center()
		var slot: int = board.active_slot
		var slot_path: String = board.slots.slot_path(slot)
		var slot_root: String = board.slot_root
		var blocker := slot_root.path_join("pointer-test-blocker")
		var file := FileAccess.open(blocker,FileAccess.WRITE)
		assert(file!=null); file.store_string("test-owned"); file.close()
		board.slot_root = blocker.path_join("slots")
		click(index,title_pos)
		assert(board.running and board.pause_overlay.visible and not board.scene_transition.active()
			and "Could not save" in board.notice.text and played.size()==old+3 and played.back()=="title:false",
			"Save & Title mouse%d retains session when writing fails" % index)
		board.slot_root = slot_root
		board.session.elapsed = float(index)+.5
		click_at(index,true,title_pos)
		assert(board.running and not board.scene_transition.active() and played.size()==old+3)
		click_at(index,false,title_pos)
		assert(board.scene_transition.active() and board.running and played.size()==old+4 and played.back()=="title:true",
			"Save & Title mouse%d saves before fade then requests one Click" % index)
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot_path))
		assert(is_equal_approx(float(saved.scenes.Main.session.elapsed),float(index)+.5))
		board._process(1.0); board._process(1.0)
		assert(not board.running and board.title_panel.visible)
		board.selected_slot = slot
		board._request_continue_game(); board._process(1.0)
		assert(board.running and board.active_slot==slot and is_equal_approx(board.session.elapsed,float(index)+.5),
			"saved session and clock restored before first resumed gameplay frame")
		board._process(1.0)
	for index in 3:
		var button: Button = board.pause_controls[index]
		assert(button.button_mask==7)
		var original: Dictionary = board.catalog.data
		var mutated: Dictionary = original.duplicate(true)
		mutated.provenance.source_commit = "wrong"
		assert(not board._admit_source_pause_pointer(mutated,view,index) and button.button_mask==1)
		for change in ["controller", "link", "disabled", "owner", "script"]:
			mutated = original.duplicate(true)
			var id: String = ["8171884105890585185","2697808248802931809","6850422679154243207"][index]
			for prefab in mutated.referenced_prefabs:
				if prefab.name != "UIRoot": continue
				for doc in prefab.documents:
					if str(doc.file_id)=="8547574447435325085":
						if change=="controller": doc.fields.m_Enabled=0
						if change=="link": doc.fields[["continueButton","optionsButton","titleButton"][index]].fileID="0"
					if str(doc.file_id)==id:
						if change=="disabled": doc.fields.m_Enabled=0
						if change=="owner": doc.fields.m_GameObject.fileID="0"
						if change=="script": doc.fields.m_Script.guid="wrong"
			assert(not board._admit_source_pause_pointer(mutated,view,index) and button.button_mask==1,change)
		var host := button.get_parent()
		button.reparent(board.pause_overlay)
		assert(not board._admit_source_pause_pointer(original,view,index) and button.button_mask==1)
		button.reparent(host)
		assert(board._admit_source_pause_pointer(original,view,index) and button.button_mask==7)
	print("Source Pause pointers: PASS (L/R/M through Options, Continue and Save/Title; source/fallback guards)")
