extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Tracker = preload("res://scripts/model/quest_tracker.gd")
class FakeSession:
	var cards := {}
	var discovered_recipes := {}
	var snapshot := {"currency": 0, "nutrition": 0, "card_limit": 24}
	func stats() -> Dictionary:
		return snapshot
var checks := 0
var failures := 0
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func ref(guid: String) -> Dictionary:
	return {"guid": guid}
func quest(id: String, type: int, amount: int = 1, target: String = "wood") -> Dictionary:
	return {"guid": id, "fields": {"id": id, "type": type, "targetAmount": amount, "targetCard": ref(target)}}
func fixture(entries: Array) -> Array:
	var catalog = Catalog.new()
	catalog.configure({"quests": entries, "cards": [{"guid": "wood", "fields": {}}, {"guid": "coin", "fields": {"category": 7}}], "recipes": [{"guid": "recipe", "fields": {"id": "recipe-id"}}]})
	var references: Array = []
	for entry in entries:
		references.append(ref(entry.guid))
	var tracker = Tracker.new()
	check(tracker.configure(catalog, "", [{"GroupName": "Test", "Quests": references}]), "synthetic configuration")
	return [tracker, FakeSession.new()]
func progress(tracker, id: String) -> int:
	for instance in tracker.all_quests():
		if instance.id == id:
			return int(instance.current_amount)
	return -1
func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "load audited data")
	check(catalog.data.quests.size() == 66, "66 original quest assets")
	var tracker = Tracker.new()
	check(tracker.configure(catalog), "Main references valid")
	check(tracker.definitions.size() == 63, "Main contains 63 quests")
	check(tracker.configure(catalog, "Island"), "Island references valid")
	check(tracker.definitions.size() == 3, "Island contains 3 quests")
	for entry in catalog.data.quests:
		check(int(entry.fields.type) in range(14), "known quest enum")
		check(int(entry.fields.get("targetAmount", 1)) >= 1, "positive target")
		for key in ["targetCard", "targetRecipe"]:
			var guid: String = catalog.ref_guid(entry.fields.get(key, {}))
			check(guid.is_empty() or not catalog.fields(guid).is_empty(), "target resolves")

	# Count/additive event types with exact identity and wrong-target rejection.
	for spec in [[1, "card_created", "base_definition_guid"], [3, "card_killed", "definition_guid"], [4, "crafted", "definition_guid"], [6, "pack_purchased", "definition_guid"]]:
		var f: Array = fixture([quest("q", spec[0], 2)])
		f[0].start_new_game(f[1])
		f[0].process_event(spec[1], {spec[2]: "wrong"}, f[1])
		check(progress(f[0], "q") == 0, "wrong target ignored")
		f[0].process_event(spec[1], {spec[2]: "wood"}, f[1])
		check(progress(f[0], "q") == 1, "first count")
		f[0].process_event(spec[1], {spec[2]: "wood"}, f[1])
		check(f[0].completed_count() == 1, "second count completes")
		f[0].process_event(spec[1], {spec[2]: "wood"}, f[1])
		check(f[0].completed_count() == 1, "no double completion")

	# These source event types SET one, even with targetAmount > 1.
	for spec in [[7, "card_equipped"], [8, "exploration_finished"], [9, "time_pace_changed"]]:
		var f: Array = fixture([quest("q", spec[0], 2)])
		f[0].start_new_game(f[1])
		for i in 3:
			f[0].process_event(spec[1], {"definition_guid": "wood", "pace": 1}, f[1])
		check(progress(f[0], "q") == 1 and f[0].completed_count() == 0, "set one not accumulated")
	var f: Array = fixture([quest("any", 5, 4, ""), quest("specific", 5, 2)])
	f[0].start_new_game(f[1])
	f[0].process_event("cards_sold", {"base_definition_guids": ["wood", "coin", "wood"]}, f[1])
	check(progress(f[0], "any") == 3 and progress(f[0], "specific") == 2, "sell grouped quantity and any")
	f = fixture([quest("buy", 6, 1, "")])
	f[0].start_new_game(f[1])
	f[0].process_event("pack_purchased", {"definition_guid": "pack"}, f[1])
	check(f[0].completed_count() == 1, "buy any")
	f = fixture([quest("day", 10, 5)])
	f[0].start_new_game(f[1])
	f[0].process_event("day_started", {"day": 4}, f[1])
	f[0].process_event("day_started", {"day": 5}, f[1])
	check(progress(f[0], "day") == 5 and f[0].completed_count() == 1, "absolute day")

	# Have uses base identity; currency Have counts stored currency via snapshot.
	f = fixture([quest("have", 0, 2), quest("money", 0, 5, "coin"), quest("food", 11, 10), quest("coins", 12, 10), quest("capacity", 13, 30)])
	f[1].cards = {1: {"base_definition_guid": "wood", "definition_guid": "equipped"}}
	f[1].snapshot.currency = 5
	f[0].start_new_game(f[1])
	check(progress(f[0], "have") == 1 and f[0].completed_ids.has("money"), "Have retroactive and currency")
	f[1].cards.clear()
	f[1].snapshot = {"currency": 10, "nutrition": 10, "card_limit": 30}
	f[0].sync_stats(f[1])
	check(progress(f[0], "have") == 0, "Have can decrease before completion")
	check(f[0].completed_count() == 4, "all stat targets completed")

	# Only explicit unlock links activate dependencies. Both prerequisites required.
	var a: Dictionary = quest("a", 1)
	var b: Dictionary = quest("b", 1)
	var c: Dictionary = quest("c", 2)
	var orphan: Dictionary = quest("orphan", 1)
	a.fields.questsToUnlock = [ref("c")]
	b.fields.questsToUnlock = [ref("c")]
	c.fields.prerequisiteQuests = [ref("a"), ref("b")]
	c.fields.targetRecipe = ref("recipe")
	orphan.fields.prerequisiteQuests = [ref("a")]
	f = fixture([a, b, c, orphan])
	f[1].discovered_recipes["recipe-id"] = true
	f[0].start_new_game(f[1])
	check(progress(f[0], "c") == -1, "locked Discover not tracked")
	f[0].process_event("card_created", {"base_definition_guid": "wood"}, f[1])
	check(f[0].completed_count() == 3, "all prerequisites then retroactive discovery")
	check(progress(f[0], "orphan") == -1, "no implicit dependency scan")
	var saved: Dictionary = f[0].save_state()
	check(saved.QuestProgress == 75, "save percentage")
	f[0].restore_state(saved)
	check(f[0].completed_count() == 3, "restore completed")
	f[0].restore_state({"CompletedQuests": ["unknown"], "ActiveQuests": [{"QuestId": "a", "CurrentAmount": 12}, {"QuestId": "unknown", "CurrentAmount": 2}]})
	check(f[0].completed_count() == 1 and progress(f[0], "a") == 12, "restore does not complete or replay; preserves unknown completed id")
	# Stats-only roots do not replay during activation.
	f = fixture([quest("food", 11, 1), quest("obtain", 1, 1)])
	f[1].snapshot.nutrition = 20
	f[1].cards = {1: {"base_definition_guid": "wood"}}
	f[0].start_new_game(f[1])
	check(progress(f[0], "food") == 0 and progress(f[0], "obtain") == 0, "nonretroactive stats and Obtain")
	var discovery: Dictionary = quest("discover", 2, 2)
	discovery.fields.targetRecipe = ref("recipe")
	f = fixture([discovery])
	f[0].start_new_game(f[1])
	for i in 3:
		f[0].process_event("recipe_discovered", {"recipe_id": "recipe-id"}, f[1])
	check(progress(f[0], "discover") == 1 and f[0].completed_count() == 0, "Discover sets one")
	f = fixture([{"guid": "defaults", "fields": {"id": "defaults"}}])
	check(f[0].definitions.defaults.type == 0 and f[0].definitions.defaults.targetAmount == 1 and f[0].definitions.defaults.targetPace == 1, "source field defaults")
	check(not tracker.configure(catalog, "MissingScene"), "missing scene reports configuration failure")
	var eight: Array = []
	for i in 8:
		eight.append(quest(str(i), 1))
	f = fixture(eight)
	f[0].restore_state({"CompletedQuests": ["0"]})
	check(f[0].save_state().QuestProgress == 12, "Unity percentage midpoint rounds to even")
	print("Quest checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
