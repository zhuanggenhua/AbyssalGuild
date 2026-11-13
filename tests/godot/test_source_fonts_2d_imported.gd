extends SceneTree
const View = preload("res://scripts/ui/source_title_view.gd")
const PanelView = preload("res://scripts/ui/source_panel_view.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
var count := 0
func _init() -> void: call_deferred("run")
func check_view(view) -> void:
	for id in view.nodes:
		for child in view.nodes[id].get_children():
			if child is Label:
				var record: Dictionary = view.text_record(id)
				assert(not record.is_empty())
				assert(child.get_meta("source_font_guid") == record.m_fontAsset.guid)
				assert(child.get_meta("source_font_status") == "source_font_bound_native_layout")
				assert(child.get_theme_font("font").get_font_name() == "Liberation Sans")
				count += 1
func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
	assert(Fonts.shared().manifest.get("fonts", {}).size() > 0)
	var title = View.new()
	root.add_child(title)
	title.size = Vector2(1280, 720)
	assert(title.configure(data, null))
	check_view(title)
	var options = PanelView.new()
	root.add_child(options)
	options.size = title.size
	assert(options.configure_panel(data, "GameOptionsUI", "GameOptionsUI", "", null))
	check_view(options)
	var pause = PanelView.new()
	root.add_child(pause)
	pause.size = title.size
	assert(pause.configure_panel(data, "UIRoot", "UICanvas", "PauseMenu", null))
	check_view(pause)
	var metadata := title.bind_source_controls(data)
	var model := CheckButton.new()
	root.add_child(model)
	var toggle = preload("res://scripts/ui/source_text_toggle_adapter.gd").new()
	assert(toggle.bind(model, metadata.friendly))
	assert(toggle.label.get_meta("source_font_guid") == metadata.friendly.label.m_fontAsset.guid)
	assert(toggle.label.get_meta("source_font_status") == "source_font_bound_native_layout")
	count += 1
	var hud = preload("res://scripts/ui/source_hud_layout.gd").new()
	hud.configure(data)
	for path in ["DayTimeUI/DayText", "CardStatsUI/NutritionLabel", "CardStatsUI/CurrencyLabel", "CardStatsUI/CardLabel", "MenuPanel/Header/QuestsToggle/Label", "MenuPanel/Header/RecipesToggle/Label", "MenuPanel/MenuToggle/Label", "Watermark", "InfoPanel/InfoText", "InfoPanel/ActionButton"]:
		var record: Dictionary = hud.text_record(path)
		assert(record.has("m_fontAsset"), path)
		assert(Fonts.shared().resolve(record.m_fontAsset.guid).font != null, path)
		count += 1
	title.free()
	options.free()
	pause.free()
	model.free()
	var board = load("res://scripts/ui/board.gd").new()
	board.options_path = "user://font-components-options.json"
	board.slot_root = "user://font-components-slots"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.session.start_new_game()
	board._enter_game()
	await process_frame
	var mapped: Array = [board.day_clock, board.detail_toggle, board.watermark, board.card_hover.header, board.card_hover.body, board.info_action]
	mapped.append_array(board.stat_labels)
	mapped.append_array(board.journal_tabs.get_children())
	for control in mapped:
		assert(control.get_meta("source_font_status") == "source_font_bound_native_layout", control.name)
		assert(not str(control.get_meta("source_font_guid")).is_empty(), control.name)
		count += 1
	var default_guid: String = str(Fonts.shared().manifest.get("tmp_default_font_guid", ""))
	assert(not default_guid.is_empty(), "Locked TMP Settings default required")
	assert(board.ledger.get_meta("source_font_guid") == default_guid)
	assert(board.ledger.get_meta("source_font_status") == Fonts.shared().resolve(default_guid).status)
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Imported source 2D font components: PASS (", count, " exact source references)")
	quit()
