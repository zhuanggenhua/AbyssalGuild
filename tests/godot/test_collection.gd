extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Collection = preload("res://scripts/model/collection.gd")
var checks: int = 0
var failures: int = 0
var notifications: int = 0
var checkpoints: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func notice() -> void:
	notifications += 1
func block_departure() -> Dictionary:
	checkpoints += 1
	return {"ok": false, "error": "fixture checkpoint failure"}
func allow_departure() -> Dictionary:
	checkpoints += 1
	return {"ok": true}
func encoded(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)
func fixture():
	var catalog = Catalog.new()
	var cards: Array = []
	for spec in [["hero", 2], ["wood", 4], ["mob", 9], ["recipe_card", 8], ["gear", 5]]:
		cards.append({"guid": spec[0], "script_class": "CardDefinition", "fields": {"id": "card-id-" + spec[0], "category": spec[1], "isAggressive": spec[0] == "mob"}})
	var slots := [{"Entries": [{"Card": {"guid": "wood"}, "Weight": 0}, {"Card": {"guid": "mob"}, "Weight": -3}, {"Card": {"guid": "wood"}, "Weight": 5}, {"Card": {"fileID": 0}}, null], "PossibleRecipes": [{"guid": "recipe"}, {"guid": "recipe"}], "RecipeChance": 0}]
	catalog.configure({"cards": cards, "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack-id", "slots": slots}}], "recipes": [
		{"guid": "recipe", "script_class": "RecipeDefinition", "fields": {"id": "recipe-id", "resultingCard": {"guid": "wood"}}},
		{"guid": "travel", "script_class": "TravelRecipe", "fields": {"id": "travel-id", "targetScenes": ["Main", "Island"], "requiredIngredients": [{"card": {"guid": "hero"}, "count": 1, "consumptionMode": 1}]}},
		{"guid": "second_recipe", "script_class": "RecipeDefinition", "fields": {"id": "second-recipe-id", "resultingCard": {"guid": "wood"}}}],
		"quests": [{"guid": "quest", "fields": {"id": "quest-id"}}],
		"scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"defaultSpawnCards": []}}]}, {"name": "Island", "documents": [{"script_class": "CardManager", "fields": {"defaultSpawnCards": []}}]}]})
	var session = Session.new()
	session.configure(catalog, 44)
	return session
func _init() -> void:
	var session = fixture()
	var collection = session.collection
	collection.changed.connect(notice)
	check(collection.pack_progress("pack", {}).total == 3, "dedupe cards and recipe IDs despite weights and zero chance")
	session.friendly_mode = true
	var before_id: int = session._next_id
	check(session.spawn_card("mob") == -1 and collection.is_card_discovered("mob"), "friendly-suppressed mob discovered before factory rejection")
	check(session._next_id == before_id and notifications == 1, "discovery notification does not allocate card")
	check(collection.discovered_cards.has("card-id-mob") and not collection.discovered_cards.has("mob"), "card ID stored, not GUID")
	check(not collection.mark_card("mob") and notifications == 1, "discovery idempotent")
	session.spawn_card("pack")
	session.spawn_card("recipe_card")
	check(not collection.is_card_discovered("pack") and not collection.is_card_discovered("recipe_card"), "pack and Recipe-category excluded")
	session.catalog.definitions["Recipe:recipe-id"] = {"guid": "Recipe:recipe-id", "fields": {"id": "Recipe:recipe-id", "category": 8}}
	session.spawn_card("Recipe:recipe-id")
	check(not collection.discovered_cards.has("Recipe:recipe-id"), "dynamic recipe card excluded")
	check(collection.pack_progress("pack", {}).found == 1, "card discovery separate from recipe discovery")
	session._discover_recipe("recipe-id")
	check(collection.pack_progress("pack", session.discovered_recipes).found == 2, "recipe discovery contributes recipe entry only")
	var wood: int = session.spawn_card("wood")
	session._remove_card(wood)
	check(collection.pack_progress("pack", session.discovered_recipes).complete, "discovery persists after card removal")
	check(collection.pack_progress("missing", {}).total == 0 and not collection.pack_progress("missing", {}).complete, "empty tracker not completed")
	check(collection.is_unread("recipe-id") and collection.is_unread("quest-id") and not collection.is_unread(""), "known item rows unread, headers not")
	check(collection.mark_seen("recipe-id") and not collection.is_unread("recipe-id") and collection.is_unread("quest-id"), "reading one row leaves others unread")
	check(not collection.mark_seen("recipe-id") and not collection.mark_seen("unknown"), "seen action idempotent and only known UI items")
	var state := {"discovered_cards": ["missing-content-id", "card-id-wood"], "seen_items": ["removed-quest-id"]}
	var staged: Dictionary = collection.stage_state(state)
	collection.apply_state(staged)
	check(collection.save_state().discovered_cards.has("missing-content-id") and not collection.is_card_discovered("missing-content-id"), "unknown discovery preserved inertly")
	check(collection.save_state().seen_items.has("removed-quest-id") and not collection.is_unread("removed-quest-id"), "unknown seen ID preserved inertly")
	var unchanged: String = encoded(collection.save_state())
	for bad in [null, {}, {"discovered_cards": {}, "seen_items": []}, {"discovered_cards": [""], "seen_items": []}, {"discovered_cards": ["x", "x"], "seen_items": []}, {"discovered_cards": ["a".repeat(257)], "seen_items": []}, {"discovered_cards": [1], "seen_items": []}, {"discovered_cards": [], "seen_items": [false]}]:
		check(not collection.stage_state(bad).ok and encoded(collection.save_state()) == unchanged, "malformed collection staging atomic")
	var snapshot: Dictionary = Codec.capture(session)
	check(snapshot.session.has("collection") and Codec.restore(session, snapshot).ok and encoded(collection.save_state()) == unchanged, "native collection roundtrip")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.session.collection.seen_items = ["x", "x"]
	var before: String = encoded(Codec.capture(session))
	check(not Codec.restore(session, malformed).ok and encoded(Codec.capture(session)) == before, "invalid collection rejects entire session atomically")
	# Missing optional collection fields recover visible evidence only, not seen rows.
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.session.erase("collection")
	session.spawn_card("hero")
	legacy = Codec.capture(session)
	legacy.session.erase("collection")
	check(Codec.restore(session, legacy).ok, "legacy session loads")
	check(collection.is_card_discovered("hero") and not collection.is_card_discovered("mob") and collection.seen_items.is_empty(), "legacy infers live nonpack evidence, not lost friendly draws/read state")
	check(not collection.is_card_discovered("recipe_card") and not collection.is_card_discovered("pack"), "legacy excludes pack/recipe evidence")
	# Stale destination scenes cannot roll back global progress.
	session = fixture()
	session.friendly_mode = true
	session.spawn_card("mob")
	session.collection.mark_seen("recipe-id")
	session._discover_recipe("recipe-id")
	var hero: int = session.spawn_card("hero")
	var stack: int = session.cards[hero].stack_id
	session.campaign.before_travel = block_departure
	before = encoded(session.campaign.capture())
	check(not session.campaign.travel(stack, "travel").ok and checkpoints == 1, "failed departure checkpoint aborts valid travel")
	check(encoded(session.campaign.capture()) == before, "checkpoint failure preserves cards/global state/scene/RNG")
	check(session.campaign._validate_snapshot(session.campaign.capture()).ok and checkpoints == 1, "snapshot validation never calls checkpoint hook")
	session.campaign.before_travel = allow_departure
	var traveled: Dictionary = session.campaign.travel(stack, "travel")
	check(traveled.ok and checkpoints == 2 and session.scene_name == "Island", "departure hook permits staged travel")
	check(session.collection.is_card_discovered("mob") and not session.collection.is_unread("recipe-id"), "global suppressed discovery and read state travel")
	session.spawn_card("wood")
	session.collection.mark_seen("quest-id")
	session._discover_recipe("second-recipe-id")
	hero = session.spawn_card("hero")
	traveled = session.campaign.travel(session.cards[hero].stack_id, "travel")
	check(traveled.ok and session.scene_name == "Main", "return to stale Main snapshot")
	check(session.collection.is_card_discovered("wood") and not session.collection.is_unread("quest-id") and session.discovered_recipes.has("second-recipe-id"), "global card recipe and seen progress never rolls back")
	var campaign: Dictionary = session.campaign.capture()
	check(campaign.has("global_progress"), "campaign carries canonical global progress")
	# Union survives root missing and a stale active scene in legacy campaigns.
	var old_campaign: Dictionary = campaign.duplicate(true)
	old_campaign.erase("global_progress")
	old_campaign.scenes.Main.session.collection = {"discovered_cards": [], "seen_items": []}
	old_campaign.scenes.Main.session.discovered_recipes = {}
	var destination = fixture()
	destination.collection.mark_seen("travel-id")
	check(destination.campaign.restore(old_campaign).ok and destination.collection.is_card_discovered("wood") and not destination.collection.is_unread("quest-id"), "legacy campaign unions all scene histories")
	check(destination.collection.is_unread("travel-id"), "loading another campaign does not leak previous slot read state")
	var bad_campaign: Dictionary = campaign.duplicate(true)
	bad_campaign.global_progress.collection.discovered_cards = [12]
	before = encoded(destination.campaign.capture())
	check(not destination.campaign.restore(bad_campaign).ok and encoded(destination.campaign.capture()) == before, "malformed canonical globals leave live campaign unchanged")
	bad_campaign = campaign.duplicate(true)
	bad_campaign.scenes.Island.session.day = 0
	check(not destination.campaign.restore(bad_campaign).ok and encoded(destination.campaign.capture()) == before, "invalid inactive scene prevents any global mutation")
	check(destination.campaign.restore(campaign).ok and destination.collection.save_state() == session.collection.save_state(), "canonical campaign global roundtrip")
	# Transformations do not pass through the discovery factory.
	var transformed = fixture()
	transformed.catalog.definitions["warrior"] = {"guid": "warrior", "script_class": "CardDefinition", "fields": {"id": "warrior-id", "category": 2}}
	transformed.catalog.definitions.gear.fields.classChangeResult = {"guid": "warrior"}
	var wearer: int = transformed.spawn_card("hero")
	var gear: int = transformed.spawn_card("gear")
	check(transformed.equipment.equip(wearer, gear) and transformed.cards[wearer].definition_guid == "warrior", "fixture class transformation succeeds")
	check(not transformed.collection.is_card_discovered("warrior") and transformed.collection.is_card_discovered("hero"), "equipping alone does not discover transformed class")
	transformed.catalog.definitions.pack.fields.slots.append({"Entries": null, "PossibleRecipes": null})
	check(transformed.collection.pack_progress("pack", {}).total == 3, "null source slot lists ignored")
	transformed.collection.mark_seen("recipe-id")
	transformed.start_new_game()
	check(transformed.collection.discovered_cards.is_empty() and transformed.collection.seen_items.is_empty(), "new game clears prior global collection")
	# Optional private source audit; synthetic coverage above runs in public CI.
	var real = Catalog.new()
	if real.load_file() == OK:
		var tracker = Collection.new()
		tracker.configure(real)
		var totals := {"00_Pack_Starter": 4, "01_Pack_Beginning": 14, "02_Pack_Revelations": 27, "03_Pack_Farmstead": 19, "04_Pack_HeartyMeals": 19, "05_Pack_Knowledge": 27, "06_Pack_Blacksmith": 20, "07_Pack_Adventure": 15, "08_Pack_Construction": 20, "10_Pack_Island": 5, "11_Pack_Survival": 7}
		for name in totals:
			check(tracker.pack_progress(real.find_by_name(name, "packs"), {}).total == totals[name], "real source pack total " + name)
	else:
		print("SKIP: private source collection totals unavailable")
	print("Collection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
