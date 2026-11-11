extends RefCounted
## Read-only source information/feedback adapters. Never select or advance a recipe.
const STAT_KEYS = ["maxHealth", "attack", "defense", "attackSpeed", "accuracy", "dodge", "criticalChance", "criticalMultiplier"]
const STAT_LABELS = ["Max Health", "Attack", "Defense", "Attack Speed", "Accuracy", "Dodge", "Crit. Chance", "Crit. Multiplier"]
const COMBAT_NAMES = {1: "Melee", 2: "Ranged", 3: "Magic"}
const PROGRESS_OFFSET = Vector3(0, 0, 0.55) # Source coordinates; renderer reflects Z once.

static func hover_info(session, card_id: int, enabled: bool = true) -> Dictionary:
	if not enabled or session == null or not session.cards.has(card_id): return {}
	var card = session.cards[card_id]
	var stack = session.stacks.get(card.stack_id)
	if not _valid_stack(session, stack) or not stack.card_ids.has(card_id): return {}
	var craft: Dictionary = _craft(session, stack)
	var result := {"card_id": card_id, "stack_id": stack.id, "header": "", "body": "", "kind": "card"}
	if not craft.is_empty():
		result.header = _name(session.catalog, stack.recipe_guid)
		result.body = "Time left: %.1fs" % craft.remaining
		result.kind = "craft"
		return result
	if stack.card_ids.size() > 1:
		var counts: Dictionary = {}
		for id in stack.card_ids:
			var guid: String = session.cards[id].definition_guid
			counts[guid] = int(counts.get(guid, 0)) + 1
		var groups: Array[String] = []
		for guid in counts:
			groups.append("%s x%d" % [_name(session.catalog, guid), counts[guid]])
		result.header = "Stack of Cards"
		result.body = ", ".join(groups) + "."
		result.kind = "stack"
		return result
	# Source TopCard is FIRST, despite native stack's bottom-to-top terminology.
	var top = session.cards[stack.card_ids.front()]
	var fields: Dictionary = session.catalog.fields(top.definition_guid)
	result.header = _name(session.catalog, top.definition_guid)
	result.body = str(fields.get("description", ""))
	if int(fields.get("category", 0)) == 2:
		var stats: Dictionary = session.equipment.stats(top.id)
		result.body += "\nHealth (%s/%s)" % [str(top.health), str(stats.get("maxHealth", 0))]
		var combat_type: int = int(fields.get("combatType", 0))
		if COMBAT_NAMES.has(combat_type):
			result.body += "\n" + COMBAT_NAMES[combat_type]
			for index in STAT_KEYS.size():
				result.body += "\n%s (%s)" % [STAT_LABELS[index], str(stats.get(STAT_KEYS[index], 0))]
	return result

## EquipmentPanel hover is a separate source request, not stackless card hover.
## Route the board picker's panel_owner here; preserve attachment order, not slots.
static func equipment_panel_info(session, owner_id: int, enabled: bool = true) -> Dictionary:
	if not enabled or session == null or not session.cards.has(owner_id): return {}
	var names: Array[String] = []
	for item_id in session.equipment.equipped.get(owner_id, {}).values():
		if not session.cards.has(item_id) or session.equipment.owners.get(item_id, -1) != owner_id: continue
		names.append("• " + _name(session.catalog, session.cards[item_id].definition_guid))
	if names.is_empty(): return {}
	return {"kind": "equipment_panel", "owner_id": owner_id, "header": "Equipments", "body": "\n".join(names)}

## Caller supplies MODEL-qualified stack IDs, never screen-nearness candidates.
## Source highlighting additionally hides all crafting targets, even excess joins.
static func drag_targets(session, lifted_card_id: int, qualified_stack_ids: Array, enabled: bool = true) -> Dictionary:
	var result: Dictionary = {}
	if not enabled or session == null or not session.cards.has(lifted_card_id): return result
	var lifted = session.cards[lifted_card_id]
	var source = session.stacks.get(lifted.stack_id)
	if not _valid_stack(session, source) or not source.card_ids.has(lifted_card_id): return result
	for id in qualified_stack_ids:
		if not id is int or id == source.id: continue
		var stack = session.stacks.get(id)
		if not _valid_stack(session, stack) or not stack.recipe_guid.is_empty(): continue
		# Recheck the authoritative pure predicate: supplied IDs may be stale.
		if not session.can_move_to_stack(lifted_card_id, id): continue
		var bottom_id: int = stack.card_ids.back()
		if bottom_id != lifted_card_id: result[bottom_id] = {"stack_id": id, "card_id": bottom_id}
	return result

static func crafting_progress(session, enabled: bool = true) -> Dictionary:
	var result: Dictionary = {}
	if not enabled or session == null: return result
	for stack in session.stacks.values():
		if not _valid_stack(session, stack): continue
		var craft: Dictionary = _craft(session, stack)
		if craft.is_empty() or not stack.position.is_finite(): continue
		craft.stack_id = stack.id
		craft.top_card_id = stack.card_ids.front()
		craft.recipe_guid = stack.recipe_guid
		craft.anchor = Vector3(stack.position.x, 0, stack.position.y) + PROGRESS_OFFSET
		craft.paused = stack.paused or session.paused or session.phase != "playing" or session.speed <= 0
		result[stack.id] = craft
	return result

static func apply_target_highlights(views: Dictionary, targets: Dictionary) -> void:
	# Full snapshot, including false entries, clears previous drag targets.
	for id in views:
		var view = views[id]
		if is_instance_valid(view) and view.has_method("set_drag_target"):
			view.set_drag_target(targets.has(id))

static func _valid_stack(session, stack) -> bool:
	if stack == null or stack.card_ids.is_empty(): return false
	for id in stack.card_ids:
		if not session.cards.has(id) or session.cards[id].stack_id != stack.id: return false
	return true

static func _craft(session, stack) -> Dictionary:
	if stack.recipe_guid.is_empty(): return {}
	var recipe: Dictionary = session.catalog.fields(stack.recipe_guid)
	var duration: float = float(recipe.get("craftingDuration", 0))
	if not is_finite(duration) or duration <= 0 or not is_finite(stack.progress): return {}
	# recipe_guid is the model's registered-task state, not a fresh recipe query.
	# A lifted tail can temporarily remove required ingredients while the original
	# task remains paused. Only the model's release/cancel path ends that task.
	var progress: float = maxf(0, stack.progress)
	return {"elapsed": progress, "duration": duration, "remaining": maxf(0, duration - progress), "ratio": clampf(progress / duration, 0, 1)}

static func _name(catalog, guid: String) -> String:
	var fields: Dictionary = catalog.fields(guid)
	return str(fields.get("displayName", fields.get("id", guid)))
