extends RefCounted
## Pure dynamic-definition factory. Callers own registration, spawning and discovery.
## Template metadata is scene-owned; never borrow another scene or synthesize defaults.

static func card_manager(catalog, scene_name: String) -> Dictionary:
	for scene in catalog.data.get("scenes", []):
		if scene.get("name", "") != scene_name:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CardManager":
				return document.get("fields", {})
	return {}

static func build(catalog, recipe_guid: String, scene_name: String) -> Dictionary:
	var recipe: Dictionary = catalog.fields(recipe_guid)
	if recipe.is_empty() or str(recipe.get("id", "")).is_empty():
		return {}
	var manager: Dictionary = card_manager(catalog, scene_name)
	var template: Dictionary = catalog.fields(catalog.ref_guid(manager.get("recipeCardTemplate", {})))
	if template.is_empty():
		return {}
	var fields: Dictionary = template.duplicate(true)
	var key: String = "Recipe:" + str(recipe.id)
	fields.id = key
	var output: String = catalog.ref_guid(recipe.get("resultingCard", {}))
	fields.displayName = "Recipe: " + str(catalog.fields(output).get("displayName", "???"))
	var description: String = ""
	var ingredients: Array = recipe.get("requiredIngredients", [])
	for index in range(ingredients.size()):
		var ingredient: Dictionary = ingredients[index]
		var ingredient_guid: String = catalog.ref_guid(ingredient.card)
		if ingredient_guid.is_empty():
			continue
		description += str(catalog.fields(ingredient_guid).get("displayName", "")) + " x" + str(ingredient.count)
		if index < ingredients.size() - 1:
			description += ", "
	if not description.is_empty():
		description += "."
	fields.description = description
	fields.recipe_guid = recipe_guid
	return {"guid": key, "script_class": "CardDefinition", "fields": fields}

static func from_id(catalog, guid: String, scene_name: String) -> Dictionary:
	if not guid.begins_with("Recipe:"):
		return {}
	var recipe_id: String = guid.trim_prefix("Recipe:")
	for recipe in catalog.data.get("recipes", []):
		if str(recipe.fields.get("id", "")) == recipe_id:
			return build(catalog, str(recipe.guid), scene_name)
	return {}
