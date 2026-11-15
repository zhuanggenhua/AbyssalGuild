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
		print("Source Options/Pause layout: PASS (source tree, preferred sizes, control refs, focus, modal guards)")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()
