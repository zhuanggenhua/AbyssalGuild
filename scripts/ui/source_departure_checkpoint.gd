extends RefCounted
## First accepted travel checkpoint only. Never changes the live owner or arrival.
const Travel = preload("res://scripts/ui/source_travel_layout.gd")
const Admission = preload("res://scripts/ui/source_restore_admission.gd")
static func capture(source, stack_id: int, recipe_guid: String, accepted: Dictionary) -> Dictionary:
	if not accepted.get("ok", false) or source.catalog.data.get("provenance", {}).get("source_commit", "") != Admission.SOURCE_COMMIT: return {}
	var recipe: Dictionary = source.catalog.get_definition(recipe_guid)
	if recipe_guid != Travel.RECIPE_GUID or recipe.get("source_sha256", "") != Travel.RECIPE_SHA or recipe.get("script_class") != "TravelRecipe": return {}
	var fields: Dictionary = recipe.get("fields", {})
	var cycle: Array = fields.get("targetScenes", [])
	if cycle != ["Main", "Island"] or source.scene_name not in cycle or accepted.get("scene") != cycle[(cycle.find(source.scene_name) + 1) % cycle.size()]: return {}
	if source.phase != "playing" or source.cycle.stage != "idle" or source.drag.active() or not source.combat.tasks.is_empty() or not source.combat.membership.is_empty(): return {}
	if not source.stacks.has(stack_id): return {}
	var stack = source.stacks[stack_id]
	if stack.recipe_guid != recipe_guid or stack.progress < float(fields.get("craftingDuration", 0)) or not source.matches_recipe(stack, fields): return {}
	var matching := 0
	for other in source.stacks.values():
		if other.recipe_guid == recipe_guid: matching += 1
	if matching != 1 or stack.card_ids.size() != 2: return {}
	var rules: Array = fields.get("requiredIngredients", [])
	if rules.size() != 2 or fields.get("allowExcessIngredients", 1) != 0 or fields.get("isContinuous", 1) != 0: return {}
	var expected := {}
	for rule in rules:
		var guid: String = rule.get("card", {}).get("guid", "")
		if guid.is_empty() or expected.has(guid) or rule.get("consumptionMode", -1) != 0 or rule.get("count", 0) != 1 or source.catalog.fields(guid).get("uses", 0) != 1: return {}
		expected[guid] = true
	var ids: Array = stack.card_ids.duplicate()
	var remap: Dictionary = accepted.get("traveler_ids", {})
	if remap.size() != ids.size(): return {}
	for id in ids:
		if not source.cards.has(id) or not remap.has(id): return {}
		var card = source.cards[id]
		if card.stack_id != stack_id or not expected.has(card.definition_guid) or card.base_definition_guid != card.definition_guid or card.uses_left != 1: return {}
		if source.equipment.owners.has(id) or source.equipment.equipped.has(id): return {}
		expected.erase(card.definition_guid)
	var snapshot: Dictionary = source.campaign.capture().duplicate(true)
	var state: Dictionary = snapshot.scenes[snapshot.current_scene].session
	state.cards = state.cards.filter(func(card): return card.id not in ids)
	state.stacks = state.stacks.filter(func(row): return row.id != stack_id)
	state.crafting.activation_order = state.crafting.activation_order.filter(func(id): return id != stack_id)
	return snapshot
