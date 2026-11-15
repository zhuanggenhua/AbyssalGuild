extends SceneTree
const Clock = preload("res://scripts/ui/day_clock.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var docs := [{"script_class": "DayTimeUI", "fields": {"timeProgress": {"fileID": "fill"}, "paceIcons": [{"guid": "pause"}, {"guid": "normal"}, {"guid": "fast"}]}}, {"file_id": "fill", "fields": {"m_Color": {"r": 0.1, "g": 0.2, "b": 0.3, "a": 0.4}}}]
	var source := {"scenes": [{"name": "Main", "documents": [{"fields": {"m_SourcePrefab": {"guid": "ui"}}}]}], "referenced_prefabs": [{"guid": "decoy", "documents": []}, {"guid": "ui", "documents": docs}]}
	var config := Clock.resolve(source, "Main")
	check(config.source_backed and config.pace_icons == ["pause", "normal", "fast"], "resolve scene-referenced prefab and icon order")
	check(config.color.is_equal_approx(Color(0.1, 0.2, 0.3, 0.4)), "source progress tint")
	check(not Clock.resolve(source, "Island").source_backed, "never adopt another scene UI")
	docs[0].fields.timeProgress.fileID = "missing"
	check(not Clock.resolve(source, "Main").source_backed, "broken fill reference explicit fallback")
	var view = Clock.new()
	root.add_child(view)
	view.configure({}, "Main", null)
	var session = Session.new()
	session.phase = "playing"
	session.day_duration = 100
	session.elapsed = 25
	view.sync(session, true, false)
	check(view.visible and not view.disabled and view.progress.value == 0.25 and view.text == "Day %d" % session.day, "normal day quarter fill")
	check(view.icon == null and view.tooltip_text.contains("fallback"), "honest text fallback")
	for pace in [2, 0, 1]:
		session.cycle_time_pace()
		view.sync(session, true, false)
		check(session.time_pace() == pace and view.text == "Day %d" % session.day, "source pace cycle %d" % pace)
	session.elapsed = 200
	view.sync(session, true, true)
	check(view.disabled and view.progress.value == 1.0 and session.time_pace() == 1, "external lock does not rewrite pace; fill clamps")
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		session.phase = phase
		view.sync(session, true, false)
		check(not view.visible and view.disabled, "day end hides clock " + phase)
	session.phase = "playing"
	view.sync(session, false, false)
	check(not view.visible and view.disabled, "title hides and blocks")
	# Isolated source text state contract; no changes to fill or source click behavior.
	docs[0].fields.timeProgress.fileID = "fill"
	docs[0].fields.dayText = {"fileID":"day_text"}
	docs.append({"file_id":"day_text","fields":{"m_fontColor":{"r":1,"g":1,"b":1,"a":1},"m_fontStyle":0,"m_enableVertexGradient":0}})
	source.provenance = {"source_commit":Clock.TEXT_SOURCE_COMMIT}
	view.add_theme_color_override("font_hover_color",Color.RED)
	var focus_style = view.get_theme_stylebox("focus")
	var shadow = view.get_theme_color("font_shadow_color")
	view.configure(source,"Main",null)
	for key in Clock.TEXT_COLORS: check(view.get_theme_color(key)==Color.WHITE,"source DayText state "+key)
	check(view.get_theme_stylebox("focus")==focus_style and view.get_theme_color("font_shadow_color")==shadow,"focus style and text shadow untouched")
	var notifications = [0]
	view.theme_changed.connect(func(): notifications[0]+=1)
	view._configure_text_tint(source)
	check(notifications[0]==0,"same tint has no theme churn")
	view.sync(session,true,false)
	check(notifications[0]==0,"clock sync does not write theme")
	view.configure(source,"Island",null)
	check(view.get_theme_color("font_hover_color")==Color.RED and not view.has_theme_color_override("font_color"),"unreferenced scene restores original fallback")
	for bad in [{}, {"m_fontColor":false}, {"m_fontColor":{"r":1,"g":NAN,"b":1,"a":1},"m_fontStyle":0,"m_enableVertexGradient":0}, {"m_fontColor":{"r":1,"g":1,"b":1,"a":1},"m_fontStyle":1,"m_enableVertexGradient":0}, {"m_fontColor":{"r":1,"g":1,"b":1,"a":1},"m_fontStyle":0,"m_enableVertexGradient":1}]:
		view.configure(source,"Main",null)
		view.source_config.text_record = bad
		view._configure_text_tint(source)
		check(not view.source_text_tint_active and view.get_theme_color("font_hover_color")==Color.RED,"bad replacement record restores tint")
	view.configure(source,"Main",null)
	view._configure_text_tint({})
	check(not view.source_text_tint_active,"unverified source rejected")
	view.configure(source,"Main",null)
	var replacement_theme := Theme.new()
	replacement_theme.set_color("font_color","Button",Color.GREEN)
	view.theme = replacement_theme
	view._configure_text_tint(source)
	check(view.get_theme_color("font_color")==Color.WHITE,"source tint survives inherited theme replacement")
	view._configure_text_tint({"provenance":false})
	check(view.get_theme_color("font_color")==Color.GREEN,"fallback uses replacement inherited theme")
	view.configure(source,"Main",null)
	view.source_config.text_record.m_fontColor.g = 0.5
	view._configure_text_tint(source)
	check(view.get_theme_color("font_color").g==0.5,"valid replacement tint updates")
	view.queue_free()
	await process_frame
	print("Day clock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
