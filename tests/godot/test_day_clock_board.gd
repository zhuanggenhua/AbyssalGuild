extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Clock = preload("res://scripts/ui/day_clock.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var isolated := "user://day-clock-%d" % Time.get_ticks_usec()
	board.slot_root = isolated + "/slots"
	board.options_path = isolated + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "required actual source loaded")
	var has_media := FileAccess.file_exists("res://assets/imported/manifest.json")
	var resource_failures: int = failures
	if not has_media: print("SKIP: private day clock artwork (optional manifest absent)")
	for scene in ["Main", "Island"]:
		var config := Clock.resolve(board.catalog.data, scene)
		check(config.source_backed, scene + " actual scene UIRoot binding")
		board.day_clock.configure(board.catalog.data,scene,board.visual_assets)
		for key in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_disabled_color","font_focus_color"]:
			check(board.day_clock.get_theme_color(key)==Color.WHITE,scene+" source DayText tint "+key)
		board.session.elapsed=board.session.day_duration*.12345
		board.day_clock.sync(board.session,true,false)
		check(absf(board.day_clock.progress.value-.12345)<1e-12,scene+" actual imported noncent fraction transport")
		if not has_media: continue
		check(config.pace_icons.size() == 3, scene + " complete source icon references")
		for guid in config.pace_icons:
			var texture = board.visual_assets.texture(guid)
			check(texture != null and texture.get_width() > 0, scene + " private pace texture " + guid)
	board.start_new()
	board.set_process(false)
	check(board.day_clock.visible and board.stats_box.visible and not board.market_panel.visible, "clock and stats accessible while market hidden")
	if has_media:
		check(board.day_clock.icon != null, "live private source pace icon")
		if failures == resource_failures: print("Day clock private resource bindings: verified")
	else:
		check(board.day_clock.icon == null and board.day_clock.tooltip_text.contains("fallback"), "data-only live clock uses explicit text fallback")
	board.session.elapsed = board.session.day_duration * 0.5
	board._refresh()
	check(is_equal_approx(board.day_clock.progress.value, 0.5), "live half day fill")
	for pace in [2, 0, 1]:
		board.day_clock.pressed.emit()
		check(board.session.time_pace() == pace, "live clock click pace %d" % pace)
	var old_icon_disabled: Color = board.day_clock.get_theme_color("icon_disabled_color")
	var normal_icon: Texture2D = board.day_clock.icon
	var normal_fill: float = board.day_clock.progress.value
	var normal_rect: Rect2 = board.day_clock.get_rect()
	board._toggle_pause_menu()
	var source_pause = null
	for child in board.pause_overlay.get_children():
		if child.get_script()==preload("res://scripts/ui/source_panel_view.gd"): source_pause=child
	check(source_pause!=null and source_pause.source_backed and source_pause.is_visible_in_tree(),"actual embedded source PauseMenu is live")
	if source_pause!=null:
		var shade_color: Color = source_pause.Layout.color(source_pause.layout.field(source_pause.layout.root_id,"m_Color",{}))
		check(shade_color.is_equal_approx(Color(0,0,0,.8)),"locked source PauseMenu shade is black alpha .8")
		var has_live_shade=false
		for child in source_pause.get_children():
			if child is ColorRect and child.is_visible_in_tree() and child.color.is_equal_approx(shade_color): has_live_shade=true
		check(has_live_shade,"actual source shade renders declared color")
		for child in board.pause_overlay.get_children():
			if child is Control and child!=source_pause:check(not child.is_visible_in_tree(),"native fallback pause decoration hidden")
	if has_media:
		check(board.day_clock.get_theme_color("icon_disabled_color")==Color.WHITE,"ordinary real source PauseMenu keeps pace icon white")
		check(board.day_clock.icon==normal_icon and board.day_clock.progress.value==normal_fill and board.day_clock.get_rect()==normal_rect,"pause tint does not alter asset fill or rect")
	print("PACE_PAUSE_LIFECYCLE pause visible=",board.day_clock.visible," disabled=",board.day_clock.disabled," tint=",board.day_clock.get_theme_color("icon_disabled_color"))
	check(board.day_clock.disabled, "menu external pause disables clock")
	check(board.day_clock.get_theme_color("font_disabled_color")==Color.WHITE,"external input lock does not fabricate source Selectable dimming")
	board._cycle_clock_pace()
	check(board.session.time_pace() == 1, "menu blocks clock without replacing saved pace")
	board._toggle_pause_menu()
	check(not board.day_clock.disabled, "closing menu restores clock input")
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"closing ordinary pause restores original icon theme")
	board._open_options()
	check(board.day_clock.disabled, "options external pause disables clock")
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"Options keeps old disabled icon behavior")
	print("PACE_PAUSE_LIFECYCLE options visible=",board.day_clock.visible," disabled=",board.day_clock.disabled," tint=",board.day_clock.get_theme_color("icon_disabled_color"))
	board._cycle_clock_pace()
	check(board.session.time_pace() == 1, "options preserve selected pace")
	board.options_panel.hide()
	board.pause_overlay.hide()
	board._refresh()
	board.detail_panel.show()
	board.session.cycle.request_end_day()
	check(board.journal_slide.is_animating and not board.day_clock.visible and not board.stats_box.visible, "actual day-ended event begins journal close and hides source status immediately")
	board.journal_slide.advance(0.5)
	check(not board.detail_panel.visible, "journal closes after source half-second slide")
	board._refresh()
	check(board.day_button.visible, "persistent day action survives source status hiding")
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"hidden day end restores icon fallback")
	board._cycle_clock_pace()
	check(board.session.phase == "feeding", "clock cannot advance day-end phase")
	# Opening the journal during day-end must not be undone on every refresh.
	board.detail_panel.show()
	board._refresh()
	check(board.detail_panel.visible, "auto close only on transition")
	board.session.phase = "ready"
	board.session.start_day()
	board._refresh()
	check(board.day_clock.visible and board.stats_box.visible and board.session.time_pace() == 1, "new day restores clock stats and normal pace")
	board.session.scene_name = "Island"
	board._refresh()
	check(board.market_heading.text == "STACKCRAFT / ISLAND", "live scene identity replaces literal Main")
	# Re-enter the actual pause path then invalidate only its presentation owner.
	board._toggle_pause_menu()
	board.scene_transition.begin(func():pass)
	board._process(0.0)
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"transition owner restores prior icon even while normal clock sync is paused")
	board.scene_transition.advance(1.0);board._process(0.0)
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"incoming fade remains outside ordinary pause scope")
	board.scene_transition.cancel();board._process(0.0)
	if has_media: check(board.day_clock.get_theme_color("icon_disabled_color")==Color.WHITE,"ordinary pause reacquires after transition owner ends")
	board.source_hud.hide()
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"hidden HUD parent immediately restores fallback")
	board.source_hud.show();board._refresh()
	board.day_clock.hide()
	check(board.day_clock.get_theme_color("icon_disabled_color")==old_icon_disabled,"direct hidden clock immediately restores fallback")
	board._show_title()
	var pace_before: int = board.session.time_pace()
	board._cycle_clock_pace()
	check(board.session.time_pace() == pace_before and not board.day_clock.is_visible_in_tree(), "title rejects stale clock press")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Day clock board: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
