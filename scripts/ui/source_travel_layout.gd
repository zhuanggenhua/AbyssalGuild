extends RefCounted
## Live-only source registration schedule, never a save format or travel commit.
## A rejected geometry admission does not reject or alter the existing trip.
const Admission = preload("res://scripts/ui/source_restore_admission.gd")
const Planner = preload("res://scripts/model/source_restore_layout.gd")
const RECIPE_GUID := "d5d66946e2ba247499709d2b17796dc0"
const RECIPE_SHA := "6c69e5a2d1fc2bd4ddcf414a386d9231793f6968fbc7a6cd55416201399dfe3b"

static func _fail(reason: String) -> Dictionary: return {"ok": false, "reason": reason}

static func _quiet(session) -> bool:
	return session.phase == "playing" and session.cycle.stage == "idle" and session.elapsed < session.day_duration and not session.drag.active() and session.combat.tasks.is_empty() and session.combat.membership.is_empty()

static func capture(source, stack_id: int, recipe_guid: String) -> Dictionary:
	if not _quiet(source): return _fail("Departure lifecycle outside proven travel geometry")
	if source.catalog.data.get("provenance", {}).get("source_commit", "") != Admission.SOURCE_COMMIT: return _fail("Unknown source travel contract")
	var recipe: Dictionary = source.catalog.get_definition(recipe_guid)
	if recipe_guid != RECIPE_GUID or recipe.get("source_sha256", "") != RECIPE_SHA or not source.stacks.has(stack_id): return _fail("Unmapped travel recipe/stack")
	var cycle: Array = recipe.get("fields", {}).get("targetScenes", [])
	if cycle != ["Main", "Island"] or source.scene_name not in cycle: return _fail("Unmapped travel cycle")
	var target: String = cycle[(cycle.find(source.scene_name) + 1) % cycle.size()]
	if not source.campaign.saved_scenes.has(target): return _fail("New/default destination geometry remains separate")
	var ids: Array = source.stacks[stack_id].card_ids.duplicate()
	if ids.size() != 2 or not source.matches_recipe(source.stacks[stack_id], recipe.fields): return _fail("Only the locked single-character portal stack is admitted")
	var characters := 0
	var cards := {}
	for id in ids:
		if not source.cards.has(id): return _fail("Missing departure traveler")
		if int(source.catalog.fields(source.cards[id].definition_guid).get("category", -1)) == 2: characters += 1
		cards[id] = source.cards[id].definition_guid
	if characters != 1: return _fail("Ambiguous traveler identity")
	for stack in source.stacks.values():
		if stack.id != stack_id and not stack.recipe_guid.is_empty(): return _fail("Other departure crafting remains separate")
	var gear: Array = []
	for row in source.equipment.save_state().wearers:
		if row.wearer in ids:
			gear.append(row.duplicate(true))
			for item in row.items: cards[item.item] = source.cards[item.item].definition_guid
	return {"ok": true, "target": target, "source_ids": ids, "cards": cards, "gear": gear, "saved": source.campaign.saved_scenes[target].duplicate(true)}

## Called immediately after the unchanged model transaction, before the existing
## departure checkpoint. It captures provenance, not another random sample.
static func seal(candidate, result: Dictionary, context: Dictionary) -> Dictionary:
	if not context.get("ok", false): return context
	if not result.get("ok", false) or result.get("scene") != context.target or candidate.scene_name != context.target: return _fail("Mismatched travel result")
	var remap: Variant = result.get("traveler_ids")
	if not remap is Dictionary or remap.size() != context.cards.size(): return _fail("Incomplete explicit traveler map")
	var seen := {}
	for old_id in context.cards:
		if not remap.has(old_id) or not remap[old_id] is int or seen.has(remap[old_id]): return _fail("Invalid explicit traveler map")
		var id: int = remap[old_id]
		if not candidate.cards.has(id) or candidate.cards[id].definition_guid != context.cards[old_id]: return _fail("Traveler definition changed outside source contract")
		seen[id] = true
	for row in context.gear:
		var owner: int = remap[row.wearer]
		var items := {}
		for item in row.items:
			items[int(item.slot)] = remap[item.item]
			if candidate.equipment.owners.get(remap[item.item], -1) != owner: return _fail("Changed traveler equipment owner")
		if candidate.equipment.equipped.get(owner, {}) != items: return _fail("Changed traveler equipment slots")
		if row.class_item != -1 and (candidate.equipment.class_items.get(owner, -1) != remap[row.class_item] or candidate.equipment.originals.get(owner, "") != row.original): return _fail("Changed traveler equipment class")
	context["remap"] = remap.duplicate(true)
	context["candidate"] = weakref(candidate)
	context["snapshot"] = candidate.campaign.capture()
	context["consumed"] = false
	return context

static func plan(board, context: Dictionary) -> Dictionary:
	if not context.get("ok", false): return context
	if context.get("consumed", true) or not context.get("candidate") is WeakRef or context.candidate.get_ref() != board.session: return _fail("Stale/consumed travel entry")
	var session = board.session
	if session.campaign.capture() != context.snapshot: return _fail("Staged traveler/destination state changed")
	if not _quiet(session): return _fail("Destination lifecycle outside proven travel geometry")
	# sceneLoaded creates travelers then restores saved stacks before Board.Start.
	# A verified positive initial expansion therefore resolves at authored base
	# bounds, then exposes final bounds without a shrink/global-clamp pass. Keep
	# all live-context/quiet guards above and the cold metadata/graph guards below.
	var description := Admission.describe(board, true)
	if not description.ok: return description
	var by_card := {}; var by_stack := {}
	for row in description.rows:
		by_stack[row.id] = row
		for card in row.cards: by_card[card.id] = row
	var incoming: Array = []; var saved: Array = []; var seen := {}
	for old_id in context.source_ids:
		var id: int = context.remap[old_id]
		if not by_card.has(id) or by_card[id].cards.size() != 1: return _fail("Traveler is not an independent registered stack")
		var row: Dictionary = by_card[id]
		if seen.has(row.id): return _fail("Repeated traveler stack")
		seen[row.id] = true
		incoming.append(row)
	for prior in context.saved.get("session", {}).get("stacks", []):
		var id := int(prior.id)
		if not by_stack.has(id) or seen.has(id): return _fail("Missing/reused saved destination stack")
		var row: Dictionary = by_stack[id]
		if row.cards.map(func(card): return card.id) != prior.card_ids.map(func(card_id): return int(card_id)) or row.position != Vector2(prior.position[0], prior.position[1]): return _fail("Saved destination membership/anchor changed")
		seen[id] = true
		saved.append(row)
	if seen.size() != session.stacks.size(): return _fail("Incomplete travel stack provenance")
	return Planner.plan(saved, incoming, description.config)

static func apply(board, context: Dictionary) -> Dictionary:
	var planned := plan(board, context)
	# Consume even a rejected admission; no ordinary refresh may retry it later.
	context["consumed"] = true
	return Planner.apply(board.session, planned) if planned.get("ok", false) else planned
