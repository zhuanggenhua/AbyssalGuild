extends RefCounted
## Authored departure checkpoint before fade. Never changes the live owner or arrival.
const Codec = preload("res://scripts/model/save_codec.gd")
const Travel = preload("res://scripts/ui/source_travel_layout.gd")
const Admission = preload("res://scripts/ui/source_restore_admission.gd")
static func admitted(source, stack_id: int, recipe_guid: String, accepted: Dictionary, captured_hold: int = -1, replay_candidate = null) -> bool:
	if not accepted.get("ok", false) or source.catalog.data.get("provenance", {}).get("source_commit", "") != Admission.SOURCE_COMMIT: return false
	var recipe: Dictionary = source.catalog.get_definition(recipe_guid)
	if recipe_guid != Travel.RECIPE_GUID or recipe.get("source_sha256", "") != Travel.RECIPE_SHA or recipe.get("script_class") != "TravelRecipe": return false
	var fields: Dictionary = recipe.get("fields", {})
	var cycle: Array = fields.get("targetScenes", [])
	if cycle != ["Main", "Island"] or source.scene_name not in cycle or accepted.get("scene") != cycle[(cycle.find(source.scene_name) + 1) % cycle.size()]: return false
	if source.phase != "playing" or source.cycle.stage != "idle" or not source.combat.tasks.is_empty() or not source.combat.membership.is_empty(): return false
	if not source.stacks.has(stack_id): return false
	if source.drag.active():
		# One admitted non-traveler is already registered at its held target.
		# Native save normalization must be a no-op (no early craft/quest/RNG).
		if captured_hold < 0 or source.drag.held_ids() != [captured_hold] \
				or source.stacks[stack_id].card_ids.has(captured_hold) \
				or Codec.capture(source) != Codec._capture_unsettled(source): return false
	var stack = source.stacks[stack_id]
	if stack.recipe_guid != recipe_guid or stack.progress < float(fields.get("craftingDuration", 0)) or not source.matches_recipe(stack, fields): return false
	var matching := 0
	for other in source.stacks.values():
		if other.recipe_guid == recipe_guid: matching += 1
	if matching != 1 or stack.card_ids.size() != 2: return false
	var rules: Array = fields.get("requiredIngredients", [])
	if rules.size() != 2 or fields.get("allowExcessIngredients", 1) != 0 or fields.get("isContinuous", 1) != 0: return false
	var expected := {}
	for rule in rules:
		var guid: String = rule.get("card", {}).get("guid", "")
		if guid.is_empty() or expected.has(guid) or rule.get("consumptionMode", -1) != 0 or rule.get("count", 0) != 1 or source.catalog.fields(guid).get("uses", 0) != 1: return false
		expected[guid] = true
	var ids: Array = stack.card_ids.duplicate()
	var remap: Dictionary = accepted.get("traveler_ids", {})
	var returned := false
	var fresh_inputs := true
	var with_equipment := false
	for id in ids:
		if not source.cards.has(id) or not remap.has(id): return false
		var card = source.cards[id]
		if card.stack_id != stack_id or not expected.has(card.base_definition_guid) or card.uses_left > 1: return false
		if source.equipment.owners.has(id): return false
		var items: Dictionary = source.equipment.equipped.get(id, {})
		if not items.is_empty():
			if int(source.catalog.fields(card.definition_guid).get("category", -1)) != 2 or captured_hold >= 0: return false
			with_equipment = true
		if card.definition_guid != card.base_definition_guid and (items.is_empty() \
				or source.equipment.originals.get(id, "") != card.base_definition_guid \
				or source.equipment.class_items.get(id, -1) not in items.values()): return false
		returned = returned or card.uses_left <= 0
		fresh_inputs = fresh_inputs and card.uses_left == 1
		expected.erase(card.base_definition_guid)
	if not returned and not with_equipment: return remap.size() == ids.size()
	# Repeated journeys and equipped travelers rely on the actual staged map.
	# The authored forward portal also consumes a fresh equipped pair on a
	# first visit. This never grants the separate close or held-window receipts.
	if replay_candidate == null or replay_candidate == source or replay_candidate.catalog != source.catalog \
			or replay_candidate.scene_name != accepted.scene: return false
	if not source.campaign.saved_scenes.has(accepted.scene) and not (with_equipment and fresh_inputs \
			and source.scene_name == "Main" and accepted.scene == "Island"): return false
	var seen := {}
	var count := ids.size()
	for id in ids:
		if not _matches_transfer(source, replay_candidate, remap, seen, id, true): return false
		var owner: int = remap[id]
		var items: Dictionary = source.equipment.equipped.get(id, {})
		var moved_items := {}
		for slot in items:
			var item: int = items[slot]
			if source.equipment.owners.get(item, -1) != id \
					or not _matches_transfer(source, replay_candidate, remap, seen, item, false) \
					or replay_candidate.equipment.owners.get(remap[item], -1) != owner: return false
			moved_items[slot] = remap[item]
			count += 1
		if replay_candidate.equipment.equipped.get(owner, {}) != moved_items: return false
		var class_item: int = source.equipment.class_items.get(id, -1)
		if replay_candidate.equipment.originals.get(owner, "") != source.equipment.originals.get(id, "") \
				or replay_candidate.equipment.class_items.get(owner, -1) != remap.get(class_item, -1): return false
	return remap.size() == count

static func _matches_transfer(source, candidate, remap: Dictionary, seen: Dictionary, id: int, consumes_use: bool) -> bool:
	var next_id: Variant = remap.get(id)
	if not next_id is int or seen.has(next_id) or not source.cards.has(id) or not candidate.cards.has(next_id): return false
	var prior = source.cards[id]
	var next = candidate.cards[next_id]
	if next.definition_guid != prior.definition_guid or next.base_definition_guid != prior.base_definition_guid \
			or next.uses_left != prior.uses_left - int(consumes_use) or next.health != prior.health \
			or next.nutrition != prior.nutrition or next.stored_coins != prior.stored_coins: return false
	seen[next_id] = true
	return true

## The separate close windows have only been validated for the fresh pair.
static func all_fresh(source, stack_id: int) -> bool:
	if not source.stacks.has(stack_id): return false
	for id in source.stacks[stack_id].card_ids:
		if not source.cards.has(id) or source.cards[id].uses_left != 1 \
				or not source.equipment.equipped.get(id, {}).is_empty(): return false
	return true

static func capture(source, stack_id: int, recipe_guid: String, accepted: Dictionary, captured_hold: int = -1, replay_candidate = null) -> Dictionary:
	if not admitted(source, stack_id, recipe_guid, accepted, captured_hold, replay_candidate): return {}
	var ids: Array = source.stacks[stack_id].card_ids.duplicate()
	var snapshot: Dictionary = source.campaign.capture().duplicate(true)
	var state: Dictionary = snapshot.scenes[snapshot.current_scene].session
	var migrating_ids := ids.duplicate()
	for id in ids:
		migrating_ids.append_array(source.equipment.equipped.get(id, {}).values())
	state.cards = state.cards.filter(func(card): return card.id not in migrating_ids)
	state.equipment.wearers = state.equipment.wearers.filter(func(row): return row.wearer not in ids)
	state.stacks = state.stacks.filter(func(row): return row.id != stack_id)
	state.crafting.activation_order = state.crafting.activation_order.filter(func(id): return id != stack_id)
	return snapshot
