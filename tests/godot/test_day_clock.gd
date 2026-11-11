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
	check(view.visible and not view.disabled and view.progress.value == 0.25 and view.text.contains("Normal"), "normal day quarter fill")
	check(view.icon == null and view.tooltip_text.contains("fallback"), "honest text fallback")
	for pace in [2, 0, 1]:
		session.cycle_time_pace()
		view.sync(session, true, false)
		check(session.time_pace() == pace and view.text.contains(["Paused", "Normal", "Fast"][pace]), "source pace cycle %d" % pace)
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
	view.queue_free()
	await process_frame
	print("Day clock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
