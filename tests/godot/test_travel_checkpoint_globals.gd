extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0

# Test-only observer effects prove collection provenance too. Ordinary held
# release currently discovers recipes without changing collection/read flags.
class SettlementSession extends "res://scripts/model/game_session.gd":
	func _discover_recipe(recipe_id: String) -> void:
		super._discover_recipe(recipe_id)
		if recipe_id == "tail-id":
			collection.mark_card("staged-only")
			collection.mark_seen("tail-id")

class TracedCampaign extends "res://scripts/model/campaign.gd":
	var trace: Array = []
	func _temporary(place: String):
		var temporary = super._temporary(place)
		temporary.quest_tracker.quest_activated.connect(func(instance): trace.append(place + ":activate:" + instance.id))
		temporary.quest_tracker.quest_completed.connect(func(instance): trace.append(place + ":complete:" + instance.id))
		return temporary

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)

func ingredient(guid: String, count: int = 1) -> Dictionary:
	return {"card": {"guid": guid}, "count": count, "consumptionMode": 0}

func quest(id: String, type: int, extra: Dictionary = {}) -> Dictionary:
	var fields := {"id": id, "type": type, "targetAmount": 1}
	fields.merge(extra, true)
	return {"guid": id, "script_class": "Quest", "fields": fields}

func fixture() -> Dictionary:
	var cards: Array = []
	for guid in ["base", "fiber", "result", "portal", "hero", "default", "source-only", "destination-only", "staged-only"]:
		cards.append({"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid + "-card", "category": 2 if guid == "hero" else 4, "displayName": guid, "uses": 1, "maxHealth": 10}})
	var recipes: Array = [{"guid": "tail", "script_class": "RecipeDefinition", "fields": {"id": "tail-id", "requiredIngredients": [ingredient("fiber", 3)], "resultingCard": {"guid": "result"}, "craftingDuration": 100, "randomWeight": 1}}, {"guid": "travel", "script_class": "TravelRecipe", "fields": {"id": "travel-id", "requiredIngredients": [ingredient("portal"), ingredient("hero")], "targetScenes": ["Main", "Island"], "craftingDuration": 10, "randomWeight": 1}}]
	for name in ["source", "destination"]:
		recipes.append({"guid": name, "script_class": "RecipeDefinition", "fields": {"id": name + "-id", "requiredIngredients": [ingredient("result", 99)]}})
	var quests := [quest("main-discover", 2, {"targetRecipe": {"guid": "tail"}}), quest("main-day", 10, {"targetAmount": 50}), quest("island-discover", 2, {"targetRecipe": {"guid": "tail"}, "questsToUnlock": [{"guid": "island-obtain"}]}), quest("island-obtain", 1, {"targetCard": {"guid": "default"}, "prerequisiteQuests": [{"guid": "island-discover"}], "questsToUnlock": [{"guid": "island-have"}]}), quest("island-have", 0, {"targetCard": {"guid": "hero"}, "prerequisiteQuests": [{"guid": "island-obtain"}]}), quest("island-day", 10, {"targetAmount": 50})]
	var scenes: Array = []
	for place in ["Main", "Island"]:
		var refs: Array = []
		for entry in quests:
			if str(entry.guid).begins_with(place.to_lower() + "-"):
				refs.append({"guid": entry.guid})
		scenes.append({"name": place, "documents": [{"script_class": "CardManager", "fields": {"defaultSpawnCards": [{"guid": "default"}], "defaultSpawnRadius": 0.5}}, {"fields": {"questGroups": [{"Quests": refs}]}}]})
	var matrix: Array = []; matrix.resize(144); matrix.fill(1)
	return {"cards": cards, "recipes": recipes, "quests": quests, "scenes": scenes, "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": matrix}}]}

func make_session(place: String = "Main", observe_settlement: bool = true):
	var catalog = Catalog.new(); catalog.configure(fixture())
	var session = SettlementSession.new() if observe_settlement else Session.new()
	session.configure(catalog, 995, place)
	session.campaign = TracedCampaign.new(); session.campaign.configure(session, place, 3)
	session.quest_tracker.start_new_game(session)
	return session

func travel_stack(session) -> Dictionary:
	var portal: int = session.spawn_card("portal", Vector2(4, 0))
	var hero: int = session.spawn_card("hero", Vector2(6, 0))
	check(session.move_to_stack(hero, session.cards[portal].stack_id), "legal separate travel stack")
	session.cards[hero].health = 7
	session.cards[hero].nutrition = 3
	return {"portal": portal, "hero": hero, "stack": session.cards[portal].stack_id}

func setup(hold: bool = true, observe_settlement: bool = true) -> Dictionary:
	var session = make_session("Main", observe_settlement)
	var base: int = session.spawn_card("base", Vector2(-4, 0))
	var fibers: Array = []
	for _index in 3:
		var fiber: int = session.spawn_card("fiber", Vector2(-2, 0))
		check(session.move_to_stack(fiber, session.cards[base].stack_id), "legal fiber tail assembly")
		fibers.append(fiber)
	if hold:
		check(session.drag.begin(fibers[0]).ok, "fiber tail physically held")
		check(not session.discovered_recipes.has("tail-id"), "held tail has not discovered its recipe live")
	session._discover_recipe("source-id")
	session.collection.mark_card("source-only")
	session.collection.mark_seen("source-id")
	session.collection.mark_seen("main-day")
	session.day = 8; session.elapsed = 23.5
	session.world.processed_days[7] = true
	var ids := travel_stack(session)
	ids.session = session; ids.base = base; ids.fibers = fibers
	return ids

func live_state(session) -> String:
	return canonical({"session": Codec._capture_unsettled(session), "saved": session.campaign.saved_scenes, "scene": session.campaign.current_scene, "slot": session.campaign.slot_number, "definitions": session.catalog.definitions, "source_data": session.catalog.data, "hold": [session.drag.card_id, session.drag.stack_id, session.drag._original_stack_id, session.drag.transitioning]})

func public_trace(session) -> Array:
	var result: Array = []
	session.changed.connect(func(): result.append("changed"))
	session.event_occurred.connect(func(kind, _payload): result.append(kind))
	session.collection.changed.connect(func(): result.append("collection"))
	session.quest_tracker.quest_activated.connect(func(instance): result.append("activate:" + instance.id))
	session.quest_tracker.quest_completed.connect(func(instance): result.append("complete:" + instance.id))
	return result

func assert_globals(session, destination_known: bool = false) -> void:
	for id in ["tail-id", "source-id", "travel-id"] + (["destination-id"] if destination_known else []):
		check(session.discovered_recipes.has(id), "arrival retains recipe " + id)
	for id in ["source-only-card", "staged-only-card"] + (["destination-only-card"] if destination_known else []):
		check(session.collection.discovered_cards.has(id), "arrival retains collection provenance " + id)
	for id in ["tail-id", "source-id", "main-day"] + (["destination-id", "island-day"] if destination_known else []):
		check(session.collection.seen_items.has(id), "arrival retains read flag " + id)
	check(not session.collection.seen_items.has("island-discover"), "quest completion does not imply read")

func assert_roundtrip(session, label: String) -> void:
	var snapshot: Dictionary = session.campaign.capture()
	var fresh = make_session()
	check(fresh.campaign.restore(JSON.parse_string(canonical(snapshot))).ok, label + " campaign restores")
	check(canonical(fresh.discovered_recipes) == canonical(session.discovered_recipes), label + " Continue reveals no additional recipe")
	check(canonical(fresh.collection.save_state()) == canonical(session.collection.save_state()), label + " Continue reveals no additional collection/read state")
	check(canonical(Codec.capture(fresh)) == canonical(Codec.capture(session)), label + " active state/RNG/IDs/quests exactly roundtrip")

func test_first_visit() -> void:
	var ids := setup(); var session = ids.session
	var before: String = live_state(session)
	var card_ref = session.cards[ids.hero]; var stack_ref = session.stacks[ids.stack]
	var events := public_trace(session)
	var calls: Array = []
	session.campaign.before_travel = func():
		calls.append(true)
		check(live_state(session) == before, "all staging leaves live state unchanged until checkpoint")
		check(session.cards[ids.hero] == card_ref and session.stacks[ids.stack] == stack_ref, "precommit keeps live model references")
		check(events.is_empty(), "staged settlement and quests emit no live events before checkpoint")
		check(not session.collection.seen_items.has("tail-id"), "staged read flag has not leaked before checkpoint")
		return {"ok": true}
	var result: Dictionary = session.campaign.travel(ids.stack, "travel")
	session.campaign.before_travel = Callable()
	check(result.ok and session.scene_name == "Island" and calls.size() == 1, "successful staged travel commits once")
	if not result.ok: return
	check(not session.drag.active(), "commit clears old scene hold")
	assert_globals(session)
	check(session.quest_tracker.definitions.size() == 4 and session.quest_tracker.completed_ids.keys() == ["island-discover", "island-obtain", "island-have"], "new destination sees staged discovery before default spawn and travelers")
	check(session.quest_tracker.save_state().QuestProgress == 75, "destination uses its own unequal quest denominator")
	var main: Dictionary = session.campaign.saved_scenes.Main.session
	check(main.quests.CompletedQuests == ["main-discover"] and main.quests.QuestProgress == 50, "inactive source uses source quest definitions and settlement effects")
	check(main.discovered_recipes.has("tail-id") and main.collection.seen_items.has("tail-id"), "source baseline retains same staged global knowledge")
	check(main.cards.size() == 4 and main.stacks.size() == 2, "source baseline keeps held split and excludes travelers")
	check(session.cards[result.traveler_ids[ids.hero]].health == 7 and session.cards[result.traveler_ids[ids.hero]].nutrition == 3 and session.cards[result.traveler_ids[ids.hero]].uses_left == 0, "traveler stats and post-consume uses preserved")
	var trace: Array = session.campaign.trace.filter(func(entry): return entry.begins_with("Island:"))
	check(trace == ["Island:activate:island-discover", "Island:activate:island-obtain", "Island:complete:island-discover", "Island:activate:island-day", "Island:activate:island-have", "Island:complete:island-obtain", "Island:complete:island-have"], "staged quest activation and recursive completion keep their ordering")
	check(events == ["activate:island-day", "changed", "scene_changed"], "commit restores only destination active quests before changed and scene_changed")
	assert_roundtrip(session, "first visit")
	# Saving has no corrective effect: arrival is already globally consistent.
	var path := "user://travel_checkpoint_globals.json"
	check(session.campaign.save_file(path).ok, "committed campaign saves")
	var fresh = make_session()
	check(fresh.campaign.load_file(path).ok, "committed campaign loads")
	check(canonical(Codec.capture(fresh)) == canonical(Codec.capture(session)), "disk Continue matches arrival exactly")
	var returning := travel_stack(fresh)
	check(fresh.campaign.travel(returning.stack, "travel").ok and fresh.scene_name == "Main", "return restores frozen source")
	assert_globals(fresh)
	check(fresh.day == 8 and fresh.elapsed == 23.5 and fresh.world.processed_days.has(7), "travel back preserves source clock and world")
	check(fresh.stacks[fresh.cards[ids.fibers[0]].stack_id].recipe_guid == "tail", "travel back restores settled eligible tail recipe")
	check(fresh.quest_tracker.definitions.size() == 2 and fresh.quest_tracker.completed_ids.keys() == ["main-discover"], "travel back restores own quest table without destination IDs")
	assert_roundtrip(fresh, "return visit")
	var again := travel_stack(fresh)
	check(fresh.campaign.travel(again.stack, "travel").ok and fresh.scene_name == "Island", "second round trip restores existing destination")
	assert_globals(fresh)
	check(fresh.quest_tracker.completed_count() == 3, "existing destination quest completion preserved")
	assert_roundtrip(fresh, "second round trip")

func test_existing_destination() -> void:
	var ids := setup(); var session = ids.session
	var destination = make_session("Island")
	destination._discover_recipe("destination-id")
	destination.collection.mark_card("destination-only")
	destination.collection.mark_seen("destination-id"); destination.collection.mark_seen("island-day")
	destination.day = 12; destination.elapsed = 11
	var prior: Dictionary = Codec.capture(destination)
	session.campaign.saved_scenes.Island = prior.duplicate(true)
	var result: Dictionary = session.campaign.travel(ids.stack, "travel")
	check(result.ok and session.scene_name == "Island", "travel to independently saved destination succeeds")
	if not result.ok: return
	assert_globals(session, true)
	check(session.day == 12 and session.elapsed == 11, "existing destination clock preserved")
	check(canonical(session.quest_tracker.save_state()) == canonical(prior.session.quests), "restored Discover quests are not replayed or restarted by global merging")
	check(canonical(session.campaign.saved_scenes.Island) == canonical(prior), "inactive stored snapshot not mutated by merging")
	assert_roundtrip(session, "existing destination")

func test_rejections() -> void:
	for response in [{"ok": false, "error": "checkpoint denied"}, {"ok": "invalid"}, false]:
		var ids := setup(); var session = ids.session
		var before: String = live_state(session)
		var references: Dictionary = session.cards.duplicate()
		var events := public_trace(session); var calls: Array = []
		session.campaign.before_travel = func():
			calls.append(true)
			check(live_state(session) == before and events.is_empty(), "checkpoint rejection observes untouched live session")
			return response
		check(not session.campaign.travel(ids.stack, "travel").ok and calls.size() == 1, "false or malformed departure checkpoint blocks commit")
		session.campaign.before_travel = Callable()
		check(live_state(session) == before and events.is_empty(), "rejected travel preserves all live/global/hold/RNG/catalog state and signals")
		check(session.cards == references and session.drag.active(), "rejected travel preserves references and pointer grant")
	for failure in ["missing destination", "corrupt destination", "transitioning hold"]:
		var ids := setup(); var session = ids.session
		if failure == "missing destination": session.catalog.fields("travel").targetScenes = ["Main", "Missing"]
		elif failure == "corrupt destination":
			session.campaign.saved_scenes.Island = Codec.capture(make_session("Island"))
			session.campaign.saved_scenes.Island.session.next_id = -1
		else: session.drag.transitioning = true
		var before: String = live_state(session)
		var events := public_trace(session); var calls: Array = []
		session.campaign.before_travel = func(): calls.append(true); return {"ok": true}
		check(not session.campaign.travel(ids.stack, "travel").ok, failure + " rejects")
		session.campaign.before_travel = Callable()
		check(live_state(session) == before and events.is_empty() and calls.is_empty(), failure + " rejects before checkpoint without mutation")

func test_release_equivalence() -> void:
	for hold in [true, false]:
		var held := setup(hold, false); var released := setup(hold, false)
		if hold: released.session.drag.finish_standard()
		check(held.session.campaign.travel(held.stack, "travel").ok and released.session.campaign.travel(released.stack, "travel").ok, "equivalent held/released or ordinary travel succeeds")
		check(canonical(held.session.campaign.capture()) == canonical(released.session.campaign.capture()), "travel keeps exact RNG/IDs/positions/metadata/quests versus explicit release or ordinary control")

func _init() -> void:
	test_first_visit()
	test_existing_destination()
	test_rejections()
	test_release_equivalence()
	print("Travel checkpoint globals: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
