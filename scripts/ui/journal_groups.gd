extends RefCounted
## Pure source-shaped journal descriptors. Expansion is presentation-only.
static func describe(catalog, session, tab: String, expansion: Dictionary, quest_order: Array = []) -> Array:
	var groups: Array = []
	if tab == "recipes":
		var recipes: Array = catalog.data.get("recipes", []).duplicate()
		recipes.sort_custom(func(a, b):
			var ac := int(a.fields.get("category", 0))
			var bc := int(b.fields.get("category", 0))
			return ac < bc if ac != bc else str(a.fields.get("displayName", "")).nocasecmp_to(str(b.fields.get("displayName", ""))) < 0)
		var by_category: Dictionary = {}
		for recipe in recipes:
			var fields: Dictionary = recipe.fields
			var id := str(fields.get("id", ""))
			var result: String = catalog.ref_guid(fields.get("resultingCard", {}))
			# Source omits recipes without a resulting card, including exploration.
			if id.is_empty() or not session.discovered_recipes.has(id) or catalog.fields(result).is_empty(): continue
			var category := int(fields.get("category", 0))
			if not by_category.has(category):
				var title := "Category %d" % category
				for label in catalog.data.get("enums", {}).get("RecipeCategory", {}):
					if int(catalog.data.enums.RecipeCategory[label]) == category: title = label
				by_category[category] = groups.size()
				groups.append({"key": "recipes:%d" % category, "title": title, "rows": []})
			var ingredients: Array[String] = []
			for ingredient in fields.get("requiredIngredients", []):
				ingredients.append("%s x%d" % [_name(catalog, catalog.ref_guid(ingredient.get("card", {}))), int(ingredient.get("count", 1))])
			groups[by_category[category]].rows.append(_row(session, id, "• %s" % _name(catalog, result), {"header": "Recipe: " + _name(catalog, result), "body": ", ".join(ingredients) + ("." if not ingredients.is_empty() else "")}))
	else:
		var tracker = session.quest_tracker
		var ordered_ids: Array = reconcile_quest_order(tracker, quest_order)
		var instances: Dictionary = {}
		for instance in tracker.all_quests(): instances[str(instance.id)] = instance
		var assigned: Dictionary = {}
		for index in range(tracker.quest_groups.size()):
			var group: Dictionary = tracker.quest_groups[index]
			var members: Dictionary = {}
			for reference in group.get("Quests", []):
				var id := str(tracker.guid_to_id.get(catalog.ref_guid(reference), ""))
				if id.is_empty() or assigned.has(id): continue
				assigned[id] = true
				members[id] = true
			var rows: Array = []
			# Retain existing rows while inserting newly observed activations first.
			for id in ordered_ids:
				var instance: Dictionary = instances[id]
				if not members.has(id): continue
				var fields: Dictionary = tracker.definitions.get(id, {})
				var complete: bool = tracker.completed_ids.has(id)
				var title := "• " + str(fields.get("title", id))
				title += " √" if complete else ""
				var body := str(fields.get("description", ""))
				if not complete: body += "\n\nProgress: %d / %d" % [int(instance.current_amount), int(fields.get("targetAmount", 1))]
				rows.append(_row(session, id, title, {"header": str(fields.get("title", id)), "body": body}))
			if not rows.is_empty():
				groups.append({"key": "quests:%s:%d" % [session.scene_name, index], "title": str(group.get("GroupName", "Quests")), "rows": rows})
	var result: Array = []
	for group in groups:
		var expanded: bool = expansion.get(group.key, true)
		result.append({"id": "", "group": group.key, "text": group.title + (" ▼" if expanded else " ▶"), "unread": false})
		if expanded: result.append_array(group.rows)
	if result.is_empty(): result.append({"id": "", "group": "", "text": "Discover recipes by combining cards or opening packs." if tab == "recipes" else "No quests yet.", "unread": false})
	return result

static func _row(session, id: String, text: String, info: Dictionary = {}) -> Dictionary:
	return {"id": id, "group": "", "text": text, "unread": session.collection.is_unread(id), "info": info}

static func _name(catalog, guid: String) -> String:
	return str(catalog.fields(guid).get("displayName", catalog.get_definition(guid).get("name", guid)))

static func header_color(catalog, tab: String) -> Color:
	var script: String = "RecipesView" if tab == "recipes" else "QuestsView"
	for prefab in catalog.data.get("referenced_prefabs", []):
		if prefab.get("name", "") != "UIRoot": continue
		for document in prefab.get("documents", []):
			if document.get("script_class", "") != script: continue
			var value: Dictionary = document.get("fields", {}).get("headerColor", {})
			if not value.is_empty(): return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))
	return Color.WHITE

static func reconcile_quest_order(tracker, previous: Array) -> Array:
	var present: Dictionary = {}
	for instance in tracker.all_quests(): present[str(instance.id)] = true
	var result: Array = []
	for id in previous:
		if present.has(id) and not result.has(id): result.append(id)
	# Empty previous state seeds the reverse source rebuild order. Later calls
	# insert only new activations, never move a row because its status changed.
	for instance in tracker.all_quests():
		var id := str(instance.id)
		if not result.has(id): result.push_front(id)
	return result
