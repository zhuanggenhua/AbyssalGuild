extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
const RecipeCard = preload("res://scripts/model/recipe_card_definition.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func canonical(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)

func fixture() -> Dictionary:
	var cards: Array = []
	for place in ["Main", "Island"]:
		cards.append({"guid": place + "-template", "script_class": "CardDefinition", "fields": {"id": place + "-template-id", "category": 8, "displayName": "Template", "description": "Original", "isSellable": place == "Main", "sellPrice": 2 if place == "Main" else 9, "hasDurability": true, "uses": 4 if place == "Main" else 7, "nutrition": 3, "maxHealth": 21, "sceneMarker": place, "nested": {"values": [1, 2], "icon": {"guid": place + "-icon"}}}})
	cards.append({"guid": "wood", "script_class": "CardDefinition", "fields": {"id": "wood-id", "category": 0, "displayName": "Wood"}})
	cards.append({"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero-id", "category": 2, "displayName": "Helper"}})
	var recipes := [
		{"guid": "recipe-a", "script_class": "RecipeDefinition", "fields": {"id": "a", "resultingCard": {"guid": "wood"}, "requiredIngredients": [{"card": {"guid": "wood"}, "count": 2}, {"card": {"guid": "hero"}, "count": 1}]}},
		{"guid": "recipe-b", "script_class": "RecipeDefinition", "fields": {"id": "b", "resultingCard": {"guid": "hero"}, "requiredIngredients": []}},
		{"guid": "travel", "script_class": "TravelRecipe", "fields": {"id": "travel-id", "targetScenes": ["Main", "Island"], "allowExcessIngredients": true, "requiredIngredients": [{"card": {"guid": "hero"}, "count": 1, "consumptionMode": 1}]}}]
	var slot := {"PossibleRecipes": [{"guid": "recipe-a"}, {"guid": "recipe-b"}], "RecipeChance": 1.0, "Entries": [{"Card": {"guid": "wood"}, "Weight": 1}]}
	var scenes: Array = []
	for place in ["Island", "Main"]:
		scenes.append({"name": place, "documents": [{"script_class": "CardManager", "fields": {"defaultSpawnCards": [], "recipeCardTemplate": {"guid": place + "-template"}}}]})
	scenes.append({"name": "Empty", "documents": []})
	return {"cards": cards, "recipes": recipes, "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack-id", "slots": [slot.duplicate(true), slot.duplicate(true), slot.duplicate(true)]}}], "scenes": scenes}

func make_session(place: String = "Main"):
	var catalog = Catalog.new()
	catalog.configure(fixture())
	var session = Session.new()
	session.configure(catalog, 17, place)
	return session

func clone_rng(session) -> RandomNumberGenerator:
	var oracle := RandomNumberGenerator.new()
	oracle.seed = session.rng.seed
	oracle.state = session.rng.state
	return oracle

func assert_fields(session, guid: String, place: String, label: String) -> void:
	var fields: Dictionary = session.catalog.fields(guid)
	var template: Dictionary = session.catalog.fields(place + "-template")
	check(not fields.is_empty(), label + " exists")
	for key in template:
		if key not in ["id", "displayName", "description"]:
			check(fields.get(key) == template[key], label + " preserves template " + key)
	check(fields.size() == template.size() + 1, label + " complete template plus recipe reference")
	check(fields.get("id") == guid and str(fields.get("recipe_guid", "")).begins_with("recipe-"), label + " dynamic identity")
	if guid == "Recipe:a":
		check(fields.displayName == "Recipe: Wood" and fields.description == "Wood x2, Helper x1.", label + " ingredient text")
	else:
		check(fields.displayName == "Recipe: Helper" and fields.description == "", label + " empty ingredient text")

func pure_builder() -> void:
	var session = make_session()
	var before: String = canonical(session.catalog.data)
	var definitions: String = canonical(session.catalog.definitions)
	var first: Dictionary = RecipeCard.build(session.catalog, "recipe-a", "Main")
	var second: Dictionary = RecipeCard.from_id(session.catalog, "Recipe:a", "Island")
	check(first.fields.sellPrice == 2 and second.fields.sellPrice == 9, "builder chooses named scene, not first exported scene")
	check(first.fields.description == "Wood x2, Helper x1.", "builder formats ingredients")
	first.fields.nested.values.append(99)
	check(session.catalog.fields("Main-template").nested.values == [1, 2] and second.fields.nested.values == [1, 2], "deep clone isolates nested arrays")
	for place in ["Missing", "Empty"]:
		check(RecipeCard.build(session.catalog, "recipe-a", place).is_empty(), "missing scene template has no fallback: " + place)
	check(RecipeCard.build(session.catalog, "missing", "Main").is_empty(), "unknown recipe has no definition")
	check(RecipeCard.from_id(session.catalog, "Recipe:missing", "Main").is_empty(), "unknown dynamic ID rejected")
	check(RecipeCard.from_id(session.catalog, "recipe-a", "Main").is_empty(), "static ID is not dynamic")
	check(canonical(session.catalog.data) == before and canonical(session.catalog.definitions) == definitions, "builder never mutates source or registry")

func spawn_restore_continuation(place: String) -> void:
	var session = make_session(place)
	var source: String = canonical(session.catalog.data)
	var events: Array = []
	session.event_occurred.connect(func(kind, _payload): events.append(kind))
	var pack: int = session.spawn_card("pack", Vector2(3, 5))
	var oracle := clone_rng(session)
	oracle.randf()
	var expected_guid: String = ["Recipe:a", "Recipe:b"][oracle.randi_range(0, 1)]
	var expected_id: int = session._next_id
	var result: int = session.open_pack(pack)
	check(result == expected_id and session._next_id == expected_id + 2, place + " pack IDs unchanged")
	check(session.rng.state == oracle.state and session.cards[result].definition_guid == expected_guid, place + " pack draws unchanged")
	check(session.cards[result].uses_left == (4 if place == "Main" else 7) and session.cards[result].health == 21 and session.cards[result].nutrition == 3, place + " pack initializes complete template state")
	check(events.find("recipe_discovered") < events.find("card_created") and events.find("card_created") < events.find("pack_opened"), place + " discovery before spawn before pack event")
	assert_fields(session, expected_guid, place, place + " pack")
	var snapshot: Dictionary = Codec.capture(session)
	var restored = make_session(place)
	check(Codec.restore(restored, JSON.parse_string(canonical(snapshot))).ok, place + " restore into fresh catalog")
	check(canonical(Codec.capture(restored)) == canonical(snapshot), place + " exact snapshot round trip")
	assert_fields(restored, expected_guid, place, place + " restored pack")
	# Research consumes first, draws one candidate, spawns, then discovers.
	var helper: int = session.spawn_card("hero")
	var helper_stack = session.stacks[session.cards[helper].stack_id]
	oracle = clone_rng(session)
	oracle.randi_range(0, 0)
	expected_id = session._next_id
	events.clear()
	Special.execute(session, helper_stack, {"script_class": "ResearchRecipe", "fields": {"requiredIngredients": [{"card": {"guid": "hero"}, "count": 1, "consumptionMode": 2}]}})
	check(not session.cards.has(helper) and session.cards.has(expected_id), place + " research consumes and spawns expected instance")
	check(session._next_id == expected_id + 2 and session.rng.state == oracle.state, place + " research RNG/IDs unchanged")
	check(events.find("card_created") >= 0 and events.find("card_created") < events.find("recipe_discovered"), place + " research spawn before discovery")
	assert_fields(session, session.cards[expected_id].definition_guid, place, place + " research")
	snapshot = Codec.capture(session)
	check(Codec.restore(restored, snapshot).ok, place + " research restore")
	assert_fields(restored, session.cards[expected_id].definition_guid, place, place + " restored research")
	while session.cards.has(pack):
		var a: int = session.open_pack(pack)
		var b: int = restored.open_pack(pack)
		check(a == b and canonical(Codec.capture(session)) == canonical(Codec.capture(restored)), place + " remaining pack deterministic after restore")
	check(canonical(session.catalog.data) == source, place + " spawn/restore leave source data intact")
	# Reject only after recipe definition staging, proving no partial registry mutation.
	var bad: Dictionary = snapshot.duplicate(true)
	bad.session.cards[-1].base_definition_guid = "missing"
	var before: String = canonical(Codec.capture(restored))
	var before_definitions: String = canonical(restored.catalog.definitions)
	check(not Codec.restore(restored, bad).ok, place + " corrupt restore rejected")
	check(canonical(Codec.capture(restored)) == before and canonical(restored.catalog.definitions) == before_definitions, place + " rejected restore preserves state and registry")
	var missing = make_session(place)
	RecipeCard.card_manager(missing.catalog, place).erase("recipeCardTemplate")
	check(not Codec.restore(missing, snapshot).ok, place + " missing template rejects dynamic saved card")
	check(not missing.catalog.definitions.has(expected_guid), place + " missing template never registers fabricated definition")

func campaign_scenes() -> void:
	var session = make_session()
	var stationary: int = Special.spawn_recipe_card(session, "recipe-a", Vector2.ZERO)
	var hero: int = session.spawn_card("hero")
	var traveler: int = session.spawn_card("Recipe:a", Vector2.ZERO, session.cards[hero].stack_id)
	var result: Dictionary = session.campaign.travel(session.cards[hero].stack_id, "travel")
	check(result.ok and session.scene_name == "Island", "recipe traveler enters Island")
	if not result.ok:
		return
	check(session.cards.has(result.traveler_ids[traveler]), "recipe traveler retains remapped identity")
	assert_fields(session, "Recipe:a", "Island", "traveler destination")
	var snapshot: Dictionary = session.campaign.capture()
	var fresh = make_session()
	check(fresh.campaign.restore(JSON.parse_string(canonical(snapshot))).ok, "campaign restores active and inactive recipe scenes")
	assert_fields(fresh, "Recipe:a", "Island", "active restored Island")
	hero = int(result.traveler_ids[hero])
	result = fresh.campaign.travel(fresh.cards[hero].stack_id, "travel")
	check(result.ok and fresh.scene_name == "Main" and fresh.cards.has(stationary), "return restores inactive Main recipe instance")
	assert_fields(fresh, "Recipe:a", "Main", "inactive Main restored on return")
	# An invalid inactive recipe must leave active campaign and catalog untouched.
	snapshot.scenes.Main.session.cards[0].definition_guid = "Recipe:missing"
	var before: String = canonical(fresh.campaign.capture())
	var definitions: String = canonical(fresh.catalog.definitions)
	check(not fresh.campaign.restore(snapshot).ok, "invalid inactive scene rejected")
	check(canonical(fresh.campaign.capture()) == before and canonical(fresh.catalog.definitions) == definitions, "invalid inactive scene is atomic")

func missing_template_pack() -> void:
	var session = make_session("Empty")
	var pack: int = session.spawn_card("pack")
	var oracle := clone_rng(session)
	oracle.randf()
	oracle.randi_range(0, 1)
	var next_id: int = session._next_id
	check(session.open_pack(pack) == -1, "selected recipe without template produces no card")
	check(session.rng.state == oracle.state and session._next_id == next_id, "missing template does not draw weighted fallback or allocate IDs")
	check(session.cards[pack].uses_left == 2 and session.discovered_recipes.size() == 1, "missing template preserves pack consumption/discovery order")

func _init() -> void:
	pure_builder()
	spawn_restore_continuation("Main")
	spawn_restore_continuation("Island")
	campaign_scenes()
	missing_template_pack()
	print("Recipe card definitions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
