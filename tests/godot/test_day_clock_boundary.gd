extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make():
	var catalog := Catalog.new()
	catalog.configure({"cards": [], "scenes": [{"name": "Main", "documents": [{"script_class": "QuestManager", "fields": {"questGroups": []}}]}]})
	var session := Session.new()
	session.configure(catalog, 51)
	session.day_duration = 1.0
	return session

func _init() -> void:
	for delta in [0.25, 0.5, 100.0]:
		var s = make()
		s.elapsed = 0.75
		var events: Array = []
		var observer := func(kind, _payload):
			if kind in ["day_ended", "cycle_stage_changed", "time_pace_changed"]:
				events.append({"kind": kind, "elapsed": s.elapsed, "phase": s.phase, "paused": s.paused, "stage": s.cycle.stage})
		s.event_occurred.connect(observer)
		s.tick(delta)
		check(s.phase == "playing" and not s.paused and s.elapsed == 0.75 + delta, "crossing keeps playing and full overshoot: " + str(delta))
		check(events.is_empty() and (s.phase in ["playing", "selling"]), "crossing does not acquire day input lock")
		var saved := Codec.capture(s)
		var restored = make()
		check(Codec.restore(restored, saved).ok and restored.elapsed == s.elapsed and restored.phase == "playing", "pending threshold roundtrip")
		restored.tick(0.0)
		check(restored.phase == "feeding" and restored.elapsed == 0.0, "restored pending threshold ends on next zero-delta Update")
		s.tick(0.0)
		check(s.phase == "feeding" and s.paused and s.elapsed == 0.0 and s.day == 1 and not (s.phase in ["playing", "selling"]), "next zero-delta Update ends and locks day")
		check(events.size() == 2 and events[0].kind == "day_ended" and events[1].kind == "cycle_stage_changed", "day event then cycle event without pace event")
		for event in events:
			check(event.elapsed == 0.0 and event.paused and event.phase == "feeding" and event.stage == "await_feed", "callbacks observe reset clock and acquired day lock")
		s.tick(0.0)
		s.tick(100.0)
		check(events.size() == 2 and s.cycle.stage == "await_feed" and s.day == 1, "no duplicate or catch-up days")
		s.event_occurred.disconnect(observer)

	for external in [false, true]:
		for delta in [0.0, 0.2, 100.0]:
			var s = make()
			s.elapsed = 0.75
			if not external: s.set_paused(true)
			if external: s.tick_paused(delta)
			else: s.tick(delta)
			check(s.elapsed == 0.75 and s.phase == "playing", "below threshold respects pause: " + str([external, delta]))
			s.elapsed = 1.1
			if external: s.tick_paused(delta)
			else: s.tick(delta)
			check(s.elapsed == 0.0 and s.phase == "feeding" and s.paused, "pending threshold processes under pause: " + str([external, delta]))

	var fast = make()
	fast.set_speed(2.0)
	fast.tick(0.5)
	check(fast.phase == "playing" and fast.elapsed == 1.0 and fast.time_pace() == 2, "Fast crosses using double delta without immediate stop")
	fast.set_paused(true)
	fast.tick(0.1)
	check(fast.phase == "feeding" and fast.elapsed == 0.0, "pause after crossing does not suppress next Update")
	var normal = make()
	normal.tick(0.0)
	check(normal.phase == "playing" and normal.elapsed == 0.0, "zero delta below threshold does not end")
	normal.tick(0.5)
	normal.set_speed(2.0)
	normal.tick(0.25)
	check(normal.phase == "playing" and normal.elapsed == 1.0, "pace change preserves threshold branch")
	normal.tick(0.1)
	check(normal.phase == "feeding" and normal.elapsed == 0.0, "positive next Update resets rather than adding delta")
	print("Day clock boundary: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
