extends RefCounted
## Stateless source-specialized actions over the session's sole card/stack state.
const StackModel = preload("res://scripts/model/stack.gd")
const TYPES = ["ExplorationRecipe", "GrowthRecipe", "ResearchRecipe"]

static func supports(script_class: String) -> bool:
	return script_class in TYPES

## Caller owns completion, stats notification, and repeat selection.
## false means unsupported, including TravelRecipe; never fall through to normal crafting.
static func execute(session, stack, entry: Dictionary) -> bool:
	match entry.get("script_class", ""):
		"ExplorationRecipe": _explore(session, stack, entry.fields)
		"GrowthRecipe": _grow(session, stack, entry.fields)
		"ResearchRecipe": _research(session, stack, entry.fields)
		_: return false
	return true

static func consume(session, stack, recipe: Dictionary) -> void:
	var rules: Dictionary = {}
	var remaining: Dictionary = {}
	for ingredient in recipe.get("requiredIngredients", []):
		var guid: String = session.catalog.ref_guid(ingredient.card)
		if not rules.has(guid):
			rules[guid] = ingredient
			remaining[guid] = int(ingredient.count)
	for id in stack.card_ids.duplicate():
		var guid: String = session.cards[id].base_definition_guid
		if rules.has(guid) and remaining[guid] > 0:
			_apply(session, id, int(rules[guid].get("consumptionMode", 0)))
			remaining[guid] -= 1

static func _apply(session, id: int, mode: int) -> void:
	if mode == 0:
		session.cards[id].uses_left -= 1
	if mode == 2 or (mode == 0 and session.cards[id].uses_left <= 0):
		session._remove_card(id)

static func _explore(session, stack, recipe: Dictionary) -> void:
	for id in stack.card_ids:
		var guid: String = session.cards[id].definition_guid
		var fields: Dictionary = session.catalog.fields(guid)
		if int(fields.get("category", 0)) != 10:
			continue
		# Source FirstOrDefault predicate rolls once; its body rolls again.
		if session._roll_loot(fields.get("loot", [])).is_empty():
			continue
		var loot: String = session._roll_loot(fields.get("loot", []))
		if not loot.is_empty():
			session.spawn_card(loot, stack.position)
			session.event_occurred.emit("exploration_finished", {"definition_guid": guid})
		break
	consume(session, stack, recipe)

static func _grow(session, stack, recipe: Dictionary) -> void:
	var grower: int = -1
	var seed: int = -1
	var output: String = session.catalog.ref_guid(recipe.get("resultingCard", {}))
	for id in stack.card_ids:
		var guid: String = session.cards[id].definition_guid
		if grower < 0 and session.catalog.get_definition(guid).get("script_class", "") == "GrowerDefinition":
			grower = id
		if seed < 0 and guid == output:
			seed = id
	if grower >= 0:
		for ingredient in recipe.get("requiredIngredients", []):
			if session.catalog.ref_guid(ingredient.card) == session.cards[grower].definition_guid:
				_apply(session, grower, int(ingredient.get("consumptionMode", 0)))
				break
	# SplitAt refuses bottom index and moves the seed AND every card above it.
	var index: int = stack.card_ids.find(seed)
	if index > 0:
		var separate = StackModel.new(session._next_id)
		session._next_id += 1
		separate.position = session.cards[seed].position + Vector2(_card_width(session.catalog, output), 0)
		separate.card_ids = stack.card_ids.slice(index)
		stack.card_ids.resize(index)
		session.stacks[separate.id] = separate
		for id in separate.card_ids:
			session.cards[id].stack_id = separate.id
			session.cards[id].position = separate.position
	if not output.is_empty():
		session.spawn_card(output, stack.position)

static func research_candidates(session) -> Array:
	var candidates: Array = []
	for entry in session.catalog.data.get("recipes", []):
		if supports(str(entry.get("script_class", ""))):
			continue
		if session.discovered_recipes.has(str(entry.fields.get("id", ""))):
			continue
		if session.catalog.ref_guid(entry.fields.get("resultingCard", {})).is_empty():
			continue
		candidates.append(entry)
	return candidates

static func _research(session, stack, recipe: Dictionary) -> void:
	consume(session, stack, recipe)
	var candidates: Array = research_candidates(session)
	if candidates.is_empty():
		return
	var chosen: Dictionary = candidates[session.rng.randi_range(0, candidates.size() - 1)]
	spawn_recipe_card(session, str(chosen.guid), stack.position)
	session._discover_recipe(str(chosen.fields.id))

## Also suitable for the session's pack-recipe path: clone the actual scene template.
static func spawn_recipe_card(session, recipe_guid: String, position: Vector2) -> int:
	var recipe: Dictionary = session.catalog.fields(recipe_guid)
	var manager: Dictionary = _card_manager(session.catalog)
	var template: Dictionary = session.catalog.fields(session.catalog.ref_guid(manager.get("recipeCardTemplate", {})))
	if template.is_empty():
		return -1
	var fields: Dictionary = template.duplicate(true)
	var key: String = "Recipe:" + str(recipe.id)
	fields.id = key
	var output: String = session.catalog.ref_guid(recipe.get("resultingCard", {}))
	fields.displayName = "Recipe: " + str(session.catalog.fields(output).get("displayName", "???"))
	var description: String = ""
	var ingredients: Array = recipe.get("requiredIngredients", [])
	for index in range(ingredients.size()):
		var ingredient: Dictionary = ingredients[index]
		var ingredient_guid: String = session.catalog.ref_guid(ingredient.card)
		if ingredient_guid.is_empty():
			continue
		description += str(session.catalog.fields(ingredient_guid).get("displayName", "")) + " x" + str(ingredient.count)
		if index < ingredients.size() - 1:
			description += ", "
	if not description.is_empty():
		description += "."
	fields.description = description
	fields.recipe_guid = recipe_guid
	session.catalog.definitions[key] = {"guid": key, "script_class": "CardDefinition", "fields": fields}
	return session.spawn_card(key, position)

static func _card_manager(catalog) -> Dictionary:
	for scene in catalog.data.get("scenes", []):
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CardManager":
				return document.fields
	return {}

static func _card_width(catalog, guid: String) -> float:
	var category: int = int(catalog.fields(guid).get("category", 0))
	var prefab_guid: String = ""
	for binding in _card_manager(catalog).get("cardPrefabs", []):
		if int(binding.category) == category:
			prefab_guid = catalog.ref_guid(binding.prefab)
	for prefab in catalog.data.get("referenced_prefabs", []):
		if str(prefab.guid) == prefab_guid:
			for document in prefab.get("documents", []):
				if document.get("object_type", "") == "BoxCollider":
					return float(document.fields.m_Size.x) + float(catalog.settings("CardSettings").get("margin", {}).get("x", 0))
	# Missing geometry: no invented displacement. Source assets contain the size.
	return 0.0
