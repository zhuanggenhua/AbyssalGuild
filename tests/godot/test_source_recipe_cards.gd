extends SceneTree
## Private imported-data regression. Fails, rather than skips, without local data.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
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

func make_session(place: String):
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, place + " real source data loaded")
	var session = Session.new()
	session.configure(catalog, 1, place)
	return session

func check_template(session, id: int, label: String) -> void:
	check(session.cards.has(id), label + " card exists")
	if not session.cards.has(id):
		return
	var guid: String = session.cards[id].definition_guid
	var fields: Dictionary = session.catalog.fields(guid)
	var manager: Dictionary = RecipeCard.card_manager(session.catalog, session.scene_name)
	var template: Dictionary = session.catalog.fields(session.catalog.ref_guid(manager.recipeCardTemplate))
	check(fields.size() == template.size() + 1, label + " retains all source template fields")
	for key in template:
		if key not in ["id", "displayName", "description"]:
			check(fields.get(key) == template[key], label + " source template " + key)
	var recipe: Dictionary = session.catalog.fields(str(fields.get("recipe_guid", "")))
	check(not recipe.is_empty() and fields.id == "Recipe:" + str(recipe.get("id", "")), label + " recipe identity")
	check(not recipe.get("requiredIngredients", []).is_empty() and not str(fields.get("description", "")).is_empty(), label + " ingredient description present")

func scene_continuation(place: String) -> void:
	var session = make_session(place)
	var original_source: String = canonical(session.catalog.data)
	var pack_guid: String = session.catalog.find_by_name("01_Pack_Beginning", "packs")
	check(not pack_guid.is_empty(), place + " Beginning pack exists")
	if pack_guid.is_empty():
		return
	var pack: int = session.spawn_card(pack_guid)
	var generated: int = -1
	var events: Array = []
	var created: Array = []
	session.event_occurred.connect(func(kind, payload):
		events.append(kind)
		if kind == "card_created":
			created.append(int(payload.card_id)))
	while session.cards.has(pack):
		events.clear()
		var id: int = session.open_pack(pack)
		if session.cards.has(id) and session.cards[id].definition_guid.begins_with("Recipe:"):
			generated = id
			break
	check(generated >= 0, place + " seed 1 draws an actual recipe")
	if generated < 0:
		return
	check_template(session, generated, place + " Beginning draw")
	check(events.find("recipe_discovered") < events.find("card_created") and events.find("card_created") < events.find("pack_opened"), place + " real pack event order")
	var pack_fields: String = canonical(session.catalog.fields(session.cards[generated].definition_guid))
	var saved: Dictionary = JSON.parse_string(canonical(Codec.capture(session)))
	var restored = make_session(place)
	check(Codec.restore(restored, saved).ok, place + " actual pack fresh JSON restore")
	check_template(restored, generated, place + " restored Beginning draw")
	check(canonical(restored.catalog.fields(restored.cards[generated].definition_guid)) == pack_fields, place + " pack metadata exact after restore")
	while session.cards.has(pack):
		check(session.open_pack(pack) == restored.open_pack(pack), place + " remaining pack spawn ID continuation")
		check(canonical(Codec.capture(session)) == canonical(Codec.capture(restored)), place + " remaining pack state/RNG continuation")
	var research: Dictionary = {}
	for entry in session.catalog.data.recipes:
		if entry.get("script_class") == "ResearchRecipe":
			research = entry
			break
	check(not research.is_empty(), place + " actual research recipe found")
	if research.is_empty():
		return
	var stack_id: int = -1
	for ingredient in research.fields.requiredIngredients:
		for index in range(int(ingredient.count)):
			var id: int = session.spawn_card(session.catalog.ref_guid(ingredient.card), Vector2(9, 11), stack_id)
			stack_id = session.cards[id].stack_id
	var stack = session.stacks[stack_id]
	session._check_recipe(stack)
	check(stack.recipe_guid == str(research.guid), place + " actual ingredients select research")
	# Avoid crossing the day boundary while testing the real research timer.
	session.day_duration = 100000
	var duration: float = float(research.fields.craftingDuration)
	session.tick(duration * 0.25)
	check(stack.progress > 0 and stack.progress < duration, place + " research in progress")
	saved = JSON.parse_string(canonical(Codec.capture(session)))
	restored = make_session(place)
	check(Codec.restore(restored, saved).ok, place + " mid-research fresh JSON restore")
	check(canonical(Codec.capture(session)) == canonical(Codec.capture(restored)), place + " mid-research state exact")
	events.clear()
	created.clear()
	session.tick(duration * 0.75)
	restored.tick(duration * 0.75)
	check(canonical(Codec.capture(session)) == canonical(Codec.capture(restored)), place + " research timer/RNG/discovery continuation")
	# Source world production may create a card earlier in the same tick.
	var new_recipes: Array = created.filter(func(id): return session.cards.has(id) and session.cards[id].definition_guid.begins_with("Recipe:"))
	check(new_recipes.size() == 1, place + " research produces one recipe alongside world updates")
	if new_recipes.size() != 1:
		return
	var next_id: int = int(new_recipes[0])
	check_template(session, next_id, place + " completed actual research")
	check_template(restored, next_id, place + " resumed actual research")
	check(events.rfind("card_created") >= 0 and events.rfind("card_created") < events.find("recipe_discovered"), place + " actual research spawn before discovery")
	var fields: String = canonical(session.catalog.fields(session.cards[next_id].definition_guid))
	var fresh = make_session(place)
	check(Codec.restore(fresh, JSON.parse_string(canonical(Codec.capture(session)))).ok, place + " completed research fresh restore")
	check(canonical(fresh.catalog.fields(fresh.cards[next_id].definition_guid)) == fields, place + " research metadata exact after fresh restore")
	check(canonical(session.catalog.data) == original_source, place + " real source catalog data unchanged")

func _init() -> void:
	scene_continuation("Main")
	scene_continuation("Island")
	print("Source recipe cards: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
