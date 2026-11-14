extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
var evidence: Array = []

class TraceCampaign extends "res://scripts/model/campaign.gd":
	var events: Array = []
	var notifications: Array = []
	func _temporary(place: String):
		var s = super._temporary(place)
		s.event_occurred.connect(func(kind, payload): events.append([place, kind, payload.duplicate(true)]))
		s.quest_tracker.quest_completed.connect(func(q): notifications.append([place, q.id]))
		return s

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func fixture() -> Dictionary:
	var cards: Array = []
	for name in ["portal", "hero", "wood", "default"]:
		cards.append({"guid": name, "script_class": "CardDefinition", "fields": {"id": name, "category": 2 if name == "hero" else 4, "displayName": name, "uses": 1, "maxHealth": 10}})
	var scenes: Array = []
	var quests: Array = []
	for place in ["Main", "Island"]:
		var refs: Array = []
		for kind in [0, 1]:
			var id: String = place + str(kind)
			quests.append({"guid": id, "script_class": "Quest", "fields": {"id": id, "type": kind, "targetAmount": 2, "targetCard": {"guid": "hero"}}})
			refs.append({"guid": id})
		scenes.append({"name": place, "documents": [{"fields": {"defaultSpawnCards": [{"guid": "default"}], "defaultSpawnRadius": 0.5}}, {"fields": {"questGroups": [{"Quests": refs}]}}]})
	var matrix: Array = []; matrix.resize(144); matrix.fill(1)
	return {"cards": cards, "recipes": [{"guid": "travel", "script_class": "TravelRecipe", "fields": {"id": "travel", "requiredIngredients": [{"card": {"guid": "portal"}, "count": 1, "consumptionMode": 0}, {"card": {"guid": "hero"}, "count": 1, "consumptionMode": 0}], "targetScenes": ["Main", "Island"], "craftingDuration": 10, "randomWeight": 1}}], "quests": quests, "scenes": scenes, "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": matrix}}]}

func make_session(c, place: String, seed_value: int):
	var s = Session.new(); s.configure(c, seed_value, place)
	s.campaign = TraceCampaign.new(); s.campaign.configure(s, place)
	return s

func run_case(place: String, saved: bool):
	var c = Catalog.new(); c.configure(fixture())
	var other := "Island" if place == "Main" else "Main"
	var s = make_session(c, other, 51)
	var p: int = s.spawn_card("portal")
	s.spawn_card("hero", Vector2.ZERO, s.cards[p].stack_id)
	var initial: Dictionary = {}
	if saved:
		var dest = make_session(c, place, 78); dest._next_id = 1000
		dest.spawn_card("hero", Vector2(3, 4))
		for kind in [0, 1]:
			dest.quest_tracker.active_quests.append({"id": place + str(kind), "status": 1, "current_amount": 1})
		initial = Codec.capture(dest)
		s.campaign.saved_scenes[place] = initial.duplicate(true)
	var live_events: Array = []
	s.event_occurred.connect(func(kind, payload): live_events.append([kind, payload.duplicate(true)]))
	var result: Dictionary = s.campaign.travel(s.cards[p].stack_id, "travel")
	check(result.ok, place + " travel accepted")
	if not result.ok: return
	var arrival := Codec.capture(s)
	evidence.append({"place": place, "saved": saved, "arrival": arrival, "remap": result.traveler_ids, "staging_events": s.campaign.events.duplicate(true), "quest_notifications": s.campaign.notifications.duplicate(true), "live_events": live_events.duplicate(true)})
	check(live_events.size() == 1 and live_events[0][0] == "scene_changed", "live travel event contract")
	check(s.event_occurred.is_connected(s._track_quest_event), "live quest subscription retained")
	check(s.campaign.events.any(func(e): return e[0] == place and e[1] == "card_created"), "staging creation events not globally muted")
	if saved:
		check(s.quest_tracker.save_state() == initial.session.quests, place + " saved progress unchanged on arrival")
		check(s.campaign.notifications.is_empty(), "no initialization completion notifications")
		check(s.campaign.saved_scenes[place] == initial, "inactive snapshot unchanged")
		var copy = make_session(c, place, 0)
		check(copy.campaign.restore(s.campaign.capture()).ok, "whole campaign save restore")
		check(copy.quest_tracker.save_state() == initial.session.quests, "saved arrival survives roundtrip")
		copy.spawn_card("hero")
		check(copy.quest_tracker.completed_ids.has(place + "0"), "later real acquisition completes Have")
		check(copy.quest_tracker.completed_ids.has(place + "1"), "later real acquisition completes Obtain")
		s.spawn_card("wood")
		check(s.quest_tracker.completed_ids.has(place + "0"), "next real stats event checks Have")
		check(not s.quest_tracker.completed_ids.has(place + "1"), "nonmatching real acquisition not Obtain")
		s.spawn_card("hero")
		check(s.quest_tracker.completed_ids.has(place + "1"), "matching real acquisition still triggers Obtain")

func _init(): call_deferred("run")
func run():
	for place in ["Main", "Island"]:
		for saved in [true, false]: run_case(place, saved)
	if not OS.get_environment("TRAVEL_EVIDENCE").is_empty():
		var f = FileAccess.open(OS.get_environment("TRAVEL_EVIDENCE"), FileAccess.WRITE)
		f.store_string(JSON.stringify(evidence, "  ")); f.close()
	print("TRAVEL_SAVED_QUEST_WINDOW ", "PASS" if failures == 0 else "FAIL", " ", checks)
	quit(0 if failures == 0 else 1)
