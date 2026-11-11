extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
var catalog = Catalog.new()
var rope_guid: String
var rope_id: String
var travel: Dictionary

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)

func make_session():
	var independent = Catalog.new(); independent.configure(catalog.data)
	var result = Session.new(); result.configure(independent, 995)
	result.quest_tracker.start_new_game(result)
	return result

func travel_stack(session) -> int:
	var portal: int = session.spawn_card(catalog.find_by_name("Grand Portal"), Vector2(4, 0))
	var person: int = session.spawn_card(catalog.find_by_name("Villager"), Vector2(6, 0))
	check(session.move_to_stack(person, session.cards[portal].stack_id), "real Grand Portal and Villager assemble lawfully")
	var stack = session.stacks[session.cards[portal].stack_id]
	check(stack.recipe_guid == str(travel.guid), "actual TravelRecipe selected")
	return stack.id

func setup() -> Dictionary:
	var session = make_session()
	var wood: int = session.spawn_card(catalog.find_by_name("Wood"), Vector2(-4, 0))
	var fibers: Array = []
	for _index in 3:
		var fiber: int = session.spawn_card(catalog.find_by_name("Fiber"), Vector2(-2, 0))
		check(session.move_to_stack(fiber, session.cards[wood].stack_id), "real Wood plus Fiber tail uses legal stacking matrix")
		fibers.append(fiber)
	check(session.drag.begin(fibers[0]).ok, "real three-Fiber tail held")
	check(not session.discovered_recipes.has(rope_id) and session.stacks[session.drag.stack_id].recipe_guid.is_empty(), "Rope unknown while eligible Fiber tail is held")
	check(session.matches_recipe(session.stacks[session.drag.stack_id], catalog.fields(rope_guid)), "detached real Fiber tail qualifies for Rope")
	var stack: int = travel_stack(session)
	check(session.collection.mark_seen(str(travel.fields.id)), "existing global read flag recorded")
	return {"session": session, "wood": wood, "fiber": fibers[0], "stack": stack}

func test_arrival(runtime: bool) -> void:
	var ids := setup(); var session = ids.session
	var snapshot: Dictionary = Codec.capture(session)
	check(snapshot.session.discovered_recipes.has(rope_id), "held native checkpoint discovers Rope only in staging")
	check(canonical(snapshot) == canonical(Codec.capture(session)) and not session.discovered_recipes.has(rope_id), "repeated real held capture deterministic without live discovery")
	var events: Array = []; var callbacks: Array = []
	session.event_occurred.connect(func(kind, _payload): events.append(kind))
	session.campaign.before_travel = func():
		callbacks.append(true)
		check(session.scene_name == "Main" and session.drag.active() and not session.discovered_recipes.has(rope_id), "departure checkpoint runs before live hold/global commit")
		return {"ok": true}
	if runtime:
		session.tick(float(travel.fields.craftingDuration) + 0.1)
	else:
		check(session.campaign.travel(ids.stack, str(travel.guid)).ok, "direct travel commits")
	session.campaign.before_travel = Callable()
	check(session.scene_name == "Island" and callbacks.size() == 1, "real timed or direct travel reaches Island once")
	check(session.discovered_recipes.has(rope_id), "Rope immediately known on Island without save/Continue")
	check(not session.drag.active() and session.elapsed == 0, "scene commit clears hold and stops old tick")
	check(session.collection.seen_items.has(str(travel.fields.id)) and not session.collection.seen_items.has(rope_id), "global prior read flag survives but newly discovered Rope remains unread")
	check(not events.has("recipe_discovered") and events.count("scene_changed") == 1, "staging emits no duplicate live recipe discovery event")
	var saved: Dictionary = session.campaign.saved_scenes.Main
	check(saved.session.discovered_recipes.has(rope_id), "Main departure and Island agree about Rope")
	check(saved.session.cards.size() == 4 and saved.session.stacks.size() == 2, "departure keeps Wood and physical three-Fiber split only")
	var source = make_session()
	check(Codec.restore(source, saved).ok, "actual inactive source snapshot validates")
	check(source.stacks[source.cards[ids.fiber].stack_id].recipe_guid == rope_guid and source.stacks[source.cards[ids.fiber].stack_id].progress == 0, "source restores newly selected Rope craft without consuming Fiber")
	var fresh = make_session()
	check(fresh.campaign.restore(JSON.parse_string(canonical(session.campaign.capture()))).ok, "real campaign JSON Continue succeeds")
	check(canonical(Codec.capture(fresh)) == canonical(Codec.capture(session)), "real Continue leaves all arrival state, recipes, RNG and IDs identical")
	var path := "user://travel_checkpoint_rope.json"
	check(session.campaign.save_file(path).ok and fresh.campaign.load_file(path).ok, "real held travel survives file save and Continue")
	check(canonical(Codec.capture(fresh)) == canonical(Codec.capture(session)), "disk Continue cannot reveal missing Rope knowledge")
	var returning: int = travel_stack(fresh)
	check(fresh.campaign.travel(returning, str(travel.guid)).ok and fresh.scene_name == "Main", "real return to frozen Main succeeds")
	check(fresh.discovered_recipes.has(rope_id) and fresh.stacks[fresh.cards[ids.fiber].stack_id].recipe_guid == rope_guid, "return retains Rope and its previously held craft")
	var again: int = travel_stack(fresh)
	check(fresh.campaign.travel(again, str(travel.guid)).ok and fresh.scene_name == "Island" and fresh.discovered_recipes.has(rope_id), "existing Island retains same knowledge on second round trip")

func test_checkpoint_failure() -> void:
	var ids := setup(); var session = ids.session
	var before: String = canonical(Codec._capture_unsettled(session))
	var definitions: String = canonical(session.catalog.definitions)
	var held: int = session.drag.stack_id
	var events: Array = []
	session.event_occurred.connect(func(kind, _payload): events.append(kind))
	session.campaign.before_travel = func(): return {"ok": false, "error": "fixture checkpoint failure"}
	var result: Dictionary = session.campaign.travel(ids.stack, str(travel.guid))
	session.campaign.before_travel = Callable()
	check(not result.ok and result.error == "fixture checkpoint failure", "real checkpoint error preserved")
	check(canonical(Codec._capture_unsettled(session)) == before and canonical(session.catalog.definitions) == definitions, "real rejected travel preserves live cards/quests/global/RNG/catalog state")
	check(session.drag.active() and session.drag.stack_id == held and session.campaign.saved_scenes.is_empty() and events.is_empty(), "real rejected travel preserves hold and emits no transition")
	check(not session.discovered_recipes.has(rope_id), "failed real travel does not learn staged Rope")

func _init() -> void:
	check(catalog.load_file() == OK, "locked private source catalog loaded")
	if catalog.data.is_empty(): quit(1); return
	rope_guid = catalog.find_by_name("Recipe_Rope", "recipes")
	rope_id = str(catalog.fields(rope_guid).get("id", ""))
	for entry in catalog.data.recipes:
		if entry.script_class == "TravelRecipe": travel = entry
	check(not rope_guid.is_empty() and not rope_id.is_empty() and not travel.is_empty(), "real Rope and travel definitions found")
	if rope_guid.is_empty() or travel.is_empty(): quit(1); return
	test_arrival(false)
	test_arrival(true)
	test_checkpoint_failure()
	print("Source travel checkpoint globals: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
