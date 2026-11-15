extends SceneTree
const Clock = preload("res://scripts/ui/day_clock.gd")
const Session = preload("res://scripts/model/game_session.gd")
class FakeAssets extends RefCounted:
	var image: Texture2D = GradientTexture2D.new()
	func texture(_guid: String) -> Texture2D: return image
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
	docs[1].fields.merge({"m_Type":3,"m_FillMethod":0,"m_FillOrigin":0,"m_Sprite":{"guid":"57fe652483042fb4ba6612b888e7a928","fileID":21300000}})
	view.configure(source,"Main",null)
	check(view.progress.step==0,"source filled image disables native percentage snapping")
	var old_step_view := ProgressBar.new()
	old_step_view.max_value=1
	old_step_view.value=.12345
	check(old_step_view.value==.12,"real default ProgressBar negative control")
	old_step_view.free()
	for fraction in [.0009,.00125,.12345,.9951,1.2,-.1]:
		session.day_duration=100;session.elapsed=fraction*100;session.phase="playing"
		view.sync(session,true,false)
		check(absf(view.progress.value-clampf(fraction,0,1))<1e-12,"unquantized transport "+str(fraction))
	var changes=[0]
	view.progress.changed.connect(func():changes[0]+=1)
	view._configure_progress_precision(source)
	check(changes[0]==0,"same precision setting emits no changed signal")
	view.configure(source,"Island",null)
	check(view.progress.step==view.native_progress_step,"unreferenced scene restores native step")
	for key in ["m_Type","m_FillMethod","m_FillOrigin"]:
		view.configure(source,"Main",null)
		view.source_config.fill_record=docs[1].fields.duplicate(true)
		view.source_config.fill_record[key]=-1
		view._configure_progress_precision(source)
		check(view.progress.step==view.native_progress_step,"unsupported fill shape fallback "+key)
	for sprite in [{},{"guid":"wrong","fileID":21300000},{"guid":"57fe652483042fb4ba6612b888e7a928","fileID":0}]:
		view.configure(source,"Main",null)
		view.source_config.fill_record=docs[1].fields.duplicate(true)
		view.source_config.fill_record.m_Sprite=sprite
		view._configure_progress_precision(source)
		check(view.progress.step==view.native_progress_step,"missing/unproved source sprite step fallback")
	view.configure(source,"Main",null);view._configure_progress_precision({})
	check(view.progress.step==view.native_progress_step,"unverified source step fallback")
	docs[0].fields.paceImage={"fileID":"8580080717683932055"}
	docs.append({"file_id":"8580080717683932055","fields":{"m_Color":{"r":1,"g":1,"b":1,"a":1}}})
	var media=FakeAssets.new()
	view.add_theme_color_override("icon_disabled_color",Color(1,0,0,.25))
	view.configure(source,"Main",media);session.phase="playing"
	view.sync(session,true,true,true)
	check(view.get_theme_color("icon_disabled_color")==Color.WHITE,"ordinary source pause preserves original icon white")
	var prior_events=notifications[0]
	view.sync(session,true,true,true)
	check(notifications[0]==prior_events,"stable ordinary pause tint has no theme churn")
	view.sync(session,true,true,false)
	check(view.get_theme_color("icon_disabled_color")==Color(1,0,0,.25),"other blocked owner restores prior icon override")
	view.sync(session,true,true,true);view.configure({},"Main",media)
	check(view.get_theme_color("icon_disabled_color")==Color(1,0,0,.25),"unverified reconfigure restores immediately")
	view.configure(source,"Main",media);view.sync(session,true,true,true)
	media.image=null;view.sync(session,true,true,true)
	check(not view.pause_icon_tint_active and view.get_theme_color("icon_disabled_color")==Color(1,0,0,.25),"missing actual texture restores fallback")
	media.image=GradientTexture2D.new()
	for record in [{},{"m_Color":false},{"m_Color":{"r":1,"g":1,"b":1,"a":.5}}]:
		view.configure(source,"Main",media);view.source_config.pace_record=record;view._configure_pace_tint(source);view.sync(session,true,true,true)
		check(not view.pause_icon_tint_active,"unsupported original image record fallback")
	view.configure(source,"Main",media);view.sync(session,true,true,true);session.phase="feeding";view.sync(session,true,true,true)
	check(not view.pause_icon_tint_active and not view.visible,"hidden phase does not keep icon override")
	session.phase="playing";view.configure(source,"Main",media);view.source_config.pace_image_id="wrong";view._configure_pace_tint(source);view.sync(session,true,true,true)
	check(not view.pause_icon_tint_active,"wrong source image reference rejected")
	view.configure(source,"Main",media);view.sync(session,true,true,true);view.hide()
	check(not view.pause_icon_tint_active,"direct hide invalidates pause tint without sync")
	view.remove_theme_color_override("icon_disabled_color")
	view.configure(source,"Main",media);view.sync(session,true,true,true)
	var icon_theme=Theme.new();icon_theme.set_color("icon_disabled_color","Button",Color.BLUE);view.theme=icon_theme
	view.sync(session,true,true,false)
	check(view.get_theme_color("icon_disabled_color")==Color.BLUE and not view.has_theme_color_override("icon_disabled_color"),"inherited replacement theme fallback restored")
	view.queue_free()
	await process_frame
	print("Day clock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
