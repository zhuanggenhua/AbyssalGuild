extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class DayFeedback extends "res://scripts/ui/audio_feedback.gd":
	var probes: Array = []
	var observe: Callable
	func play_event(name: String) -> bool:
		if name=="Click" and observe.is_valid(): probes.append(observe.call())
		return super.play_event(name)
const Clock = preload("res://scripts/ui/day_clock.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func mouse(index: int, down: bool, pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=pos; motion.global_position=pos
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index=index; event.pressed=down; event.position=pos; event.global_position=pos
	root.push_input(event,true)

func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = DayFeedback.new()
	var isolated := "user://day-clock-%d" % Time.get_ticks_usec()
	board.slot_root = isolated + "/slots"
	board.options_path = isolated + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "required actual source loaded")
	if board.data_error != OK:
		board.queue_free()
		await process_frame
		quit(1)
		return
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
	var click_probe: DayFeedback = board.feedback
	click_probe.observe = func(): return [board.session.time_pace(),board.day_clock.icon]
	await process_frame
	var pos: Vector2 = board.day_clock.get_global_rect().get_center()
	check(board.day_clock.button_mask==7,"source DayTimeUI covers all mouse actions from UIRoot")
	for index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var before: int = board.session.time_pace()
		var after: int = (before+1)%3
		var count := click_probe.probes.size()
		mouse(index,true,pos)
		check(board.session.time_pace()==before and click_probe.probes.size()==count,"no cycle/sound on button down")
		mouse(index,false,Vector2(-100,-100))
		check(board.session.time_pace()==before and click_probe.probes.size()==count,"outside release cancels cycle")
		mouse(index,true,pos)
		mouse(index,false,pos)
		check(board.session.time_pace()==after and click_probe.probes.size()==count+1
			and click_probe.probes.back()[0]==after,"exactly one pace cycle before Click sound on matching release: %d" % index)
		if has_media:
			var icons: Array = board.day_clock.source_config.pace_icons
			check(icons.size()==3 and click_probe.probes.size()==count+1
				and click_probe.probes.back()[1]==board.visual_assets.texture(icons[after])
				and board.day_clock.icon==click_probe.probes.back()[1],"exact private pace image changes before Click request")
	# Normalize so failures in the sequence don't cascade into unrelated assertions.
	board.session.set_speed(1.0)
	board._refresh()
	click_probe.observe=Callable()
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
	for index in [1,2,3]:
		mouse(index,true,pos); mouse(index,false,pos)
	check(board.session.time_pace()==1,"real Pause overlay prevents all three clock events")
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
	for index in [1,2,3]:
		mouse(index,true,pos); mouse(index,false,pos)
	check(board.session.phase=="feeding","day-ended clock cannot consume or transition through pointer release")
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
	board.day_clock.configure(board.catalog.data,"Island",board.visual_assets)
	board._refresh()
	check(board.day_clock.button_mask==7,"Island source scene references same live DayTimeUI")
	pos=board.day_clock.get_global_rect().get_center()
	mouse(MOUSE_BUTTON_RIGHT,true,pos); mouse(MOUSE_BUTTON_RIGHT,false,pos)
	check(board.session.time_pace()==2,"Island clock handles actual matching secondary release")
	var changed: Dictionary = board.catalog.data.duplicate(true)
	for prefab in changed.get("referenced_prefabs", []):
		if prefab.get("guid") != "5e2985d7789c5254b831d166e6931134": continue
		for doc in prefab.get("documents", []):
			if str(doc.get("file_id"))=="7199047651661109440": doc.fields.m_Enabled=0
	check(not Clock.resolve(changed,"Island").get("pointer_click",false),"disabled DayTimeUI cannot widen pointer acceptance")
	var fallback_pace: int = board.session.time_pace()
	board.day_clock.configure({},"Island",board.visual_assets)
	check(board.day_clock.button_mask==MOUSE_BUTTON_MASK_LEFT,"source reconfiguration restores fallback primary-only")
	mouse(MOUSE_BUTTON_RIGHT,true,pos); mouse(MOUSE_BUTTON_RIGHT,false,pos)
	check(board.session.time_pace()==fallback_pace,"missing source cannot widen fallback pointer admission")
	board.day_clock.configure(board.catalog.data,"Island",board.visual_assets)
	board.session.set_speed(1.0)
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
