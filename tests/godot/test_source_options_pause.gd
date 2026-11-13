extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	board.options_path = "user://source-options-test.json"
	board.slot_root = "user://source-options-slots"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	if board.options_panel.source_view == null:
		print("Source Options/Pause layout: SKIP (licensed source unavailable)")
	else:
		var options = board.options_panel
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
		print("Source Options/Pause layout: PASS (source tree, preferred sizes, control refs, focus, modal guards)")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()
