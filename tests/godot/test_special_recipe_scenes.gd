extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
var checks: int = 0
var failures: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func manager(template: String, prefab: String, settings: String) -> Dictionary:
	return {"script_class": "CardManager", "fields": {"defaultSpawnCards": [], "recipeCardTemplate": {"guid": template}, "cardSettings": {"guid": settings}, "cardPrefabs": [{"category": 3, "prefab": {"guid": prefab}}]}}
func build_catalog():
	var catalog = Catalog.new()
	catalog.configure({
		"cards": [
			{"guid": "main_template", "script_class": "CardDefinition", "fields": {"id": "main-template-id", "category": 8, "sellPrice": 2, "mainMarker": true}},
			{"guid": "island_template", "script_class": "CardDefinition", "fields": {"id": "island-template-id", "category": 8, "sellPrice": 9, "islandMarker": true}},
			{"guid": "seed", "script_class": "CardDefinition", "fields": {"id": "seed-id", "category": 3, "displayName": "Seed"}},
			{"guid": "grower", "script_class": "GrowerDefinition", "fields": {"id": "grower-id", "category": 6}},
			{"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero-id", "category": 2}}],
		"recipes": [
			{"guid": "recipe", "script_class": "RecipeDefinition", "fields": {"id": "recipe-id", "resultingCard": {"guid": "seed"}, "requiredIngredients": [{"card": {"guid": "seed"}, "count": 2}]}},
			{"guid": "travel", "script_class": "TravelRecipe", "fields": {"id": "travel-id", "targetScenes": ["Main", "Island"], "requiredIngredients": [{"card": {"guid": "hero"}, "count": 1, "consumptionMode": 1}]}}],
		"settings": [
			{"guid": "wrong_first_settings", "script_class": "CardSettings", "fields": {"margin": {"x": 99}}},
			{"guid": "main_settings", "script_class": "CardSettings", "fields": {"margin": {"x": 0.2}}},
			{"guid": "island_settings", "script_class": "CardSettings", "fields": {"margin": {"x": 0.7}}}],
		"referenced_prefabs": [
			{"guid": "main_prefab", "documents": [{"object_type": "BoxCollider", "fields": {"m_Size": {"x": 2}}}]},
			{"guid": "island_prefab", "documents": [{"object_type": "BoxCollider", "fields": {"m_Size": {"x": 5}}}]}],
		# Island deliberately first: default Main must never mean first exported scene.
		"scenes": [
			{"name": "Island", "documents": [manager("island_template", "island_prefab", "island_settings")]},
			{"name": "Main", "documents": [manager("main_template", "main_prefab", "main_settings")]},
			{"name": "Empty", "documents": []}]})
	return catalog
func grow_seed(session) -> Vector2:
	var grower: int = session.spawn_card("grower", Vector2(10, 20))
	var stack = session.stacks[session.cards[grower].stack_id]
	var seed: int = session.spawn_card("seed", Vector2(10, 20), stack.id)
	Special.execute(session, stack, {"script_class": "GrowthRecipe", "fields": {"resultingCard": {"guid": "seed"}, "requiredIngredients": []}})
	check(session.cards[seed].stack_id != stack.id, "seed splits before growth result")
	return session.cards[seed].position
func _init() -> void:
	var catalog = build_catalog()
	var session = Session.new()
	session.configure(catalog, 16, "Main")
	var recipe_card: int = Special.spawn_recipe_card(session, "recipe", Vector2.ZERO)
	var fields: Dictionary = catalog.fields(session.cards[recipe_card].definition_guid)
	check(fields.sellPrice == 2 and fields.get("mainMarker", false) and not fields.has("islandMarker"), "Main template selected even when Island exported first")
	check(fields.id == "Recipe:recipe-id" and fields.displayName == "Recipe: Seed" and fields.description == "Seed x2.", "dynamic recipe identity/content preserved")
	check(not catalog.fields("main_template").has("recipe_guid"), "template source remains unchanged")
	check(grow_seed(session).is_equal_approx(Vector2(12.2, 20)), "Main seed offset uses Main collider and referenced settings")
	check(is_equal_approx(Special._card_width(catalog, "seed", "Island"), 5.7), "Island width distinct from Main and first global settings")
	# Go through real campaign transition, not just a reassigned scene field.
	var hero: int = session.spawn_card("hero")
	var result: Dictionary = session.campaign.travel(session.cards[hero].stack_id, "travel")
	check(result.ok and session.scene_name == "Island", "synthetic campaign travels to Island")
	recipe_card = Special.spawn_recipe_card(session, "recipe", Vector2.ZERO)
	fields = session.catalog.fields(session.cards[recipe_card].definition_guid)
	check(fields.sellPrice == 9 and fields.get("islandMarker", false) and not fields.has("mainMarker"), "dynamic recipe after travel clones active Island template")
	check(grow_seed(session).is_equal_approx(Vector2(15.7, 20)), "growth after travel uses Island prefab width/margin")
	hero = session.spawn_card("hero")
	result = session.campaign.travel(session.cards[hero].stack_id, "travel")
	check(result.ok and session.scene_name == "Main", "return transition restores active Main")
	recipe_card = Special.spawn_recipe_card(session, "recipe", Vector2.ZERO)
	check(session.catalog.fields(session.cards[recipe_card].definition_guid).sellPrice == 2, "new recipe after return uses Main template again")
	check(grow_seed(session).is_equal_approx(Vector2(12.2, 20)), "growth after return uses Main width again")
	# Missing manager never borrows any other scene's valid manager.
	session.scene_name = "Missing"
	var next_id: int = session._next_id
	check(Special.spawn_recipe_card(session, "recipe", Vector2.ZERO) == -1 and session._next_id == next_id, "unknown scene cannot silently borrow template")
	check(Special._card_width(session.catalog, "seed", "Missing") == 0, "unknown scene has no guessed width")
	session.scene_name = "Empty"
	check(Special.spawn_recipe_card(session, "recipe", Vector2.ZERO) == -1, "scene without manager cannot borrow template")
	# Reordering scene data does not change results.
	session.catalog.data.scenes.reverse()
	check(Special._card_manager(session.catalog, "Main").recipeCardTemplate.guid == "main_template", "scene ordering irrelevant")
	check(Special._card_manager(session.catalog, "Island").recipeCardTemplate.guid == "island_template", "Island still selected after reorder")
	# Source prefab lookup keeps first valid category binding, not last.
	var main: Dictionary = Special._card_manager(session.catalog, "Main")
	main.cardPrefabs.append({"category": 3, "prefab": {"guid": "island_prefab"}})
	check(is_equal_approx(Special._card_width(session.catalog, "seed", "Main"), 2.2), "duplicate mapping keeps first valid binding")
	print("Special recipe scenes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
