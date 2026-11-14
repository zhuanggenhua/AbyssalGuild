extends RefCounted
## Source scene-entry target geometry, NOT save deserialization or gameplay spawn.
## Input records are validated geometry descriptors. No RNG, events, slot writes,
## texture/physics queries, or persistent ID allocation occur in this planner.
const Layout = preload("res://scripts/model/board_layout.gd")

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _valid_id(value: Variant) -> bool:
	return value is int and value > 0

static func _valid_size(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and value.x > 0 and value.y > 0

static func _check_card(card: Variant, seen: Dictionary, equipment: bool = false) -> String:
	if not card is Dictionary or not _valid_id(card.get("id")) or seen.has(card.id): return "Invalid or repeated card identity"
	if not _valid_size(card.get("size")) or not card.get("pack") is bool: return "Missing source card geometry/type"
	if not card.get("equipment") is Array: return "Missing source equipment sequence"
	if equipment and (card.pack or not card.equipment.is_empty()): return "Locked source does not recursively restore equipment children"
	if card.pack and not card.equipment.is_empty(): return "Pack cannot own source equipment"
	if card.pack and card.get("attachment_forbidden") != true: return "Pack attachment requires an unproven physics query"
	if not card.equipment.is_empty() and card.get("equipper_supported") != true: return "Missing source owner CardEquipper contract"
	seen[card.id] = true
	var slots := {}
	for item in card.equipment:
		if not item is Dictionary or not item.get("slot") is int or item.slot not in [0, 1, 2] or slots.has(item.slot): return "Invalid or repeated equipment slot"
		if item.get("equip_succeeds") != true: return "Equipment rejection/replacement is outside the supported source branch"
		slots[item.slot] = true
		var error := _check_card(item, seen, true)
		if not error.is_empty(): return error
	return ""

static func _check_records(records: Array, seen_cards: Dictionary, seen_stacks: Dictionary, incoming: bool, defaults: bool) -> String:
	for record in records:
		if not record is Dictionary or not _valid_id(record.get("id")) or seen_stacks.has(record.id): return "Invalid or repeated stack identity"
		if not record.get("position") is Vector2 or not record.position.is_finite(): return "Invalid saved/spawn position"
		if not record.get("cards") is Array or record.cards.is_empty(): return "Empty source stack"
		if (incoming or defaults) and record.cards.size() != 1: return "Source incoming/default creation must be individually ordered"
		seen_stacks[record.id] = true
		for card in record.cards:
			var error := _check_card(card, seen_cards)
			if not error.is_empty(): return error
			if card.pack and (incoming or record.cards.size() != 1): return "Unsupported pack traveler/mixed stack"
	return ""

static func _new_state(context: Dictionary, record: Dictionary, card: Dictionary, id: int, position: Vector2) -> Dictionary:
	var state := Layout.stack_state(id, position, card.size, 1, false, context.step)
	state["card_ids"] = [card.id]
	return state

static func _resolve(context: Dictionary, cause: String) -> void:
	var resolved := Layout.resolve_overlaps(context.states, [], context.bounds, context.margin, context.iterations)
	context.states = resolved.stacks
	context.trace.append({"event": "resolve", "cause": cause, "iterations": resolved.iterations})

static func _equipment(context: Dictionary, owner: Dictionary) -> void:
	for item in owner.equipment:
		context.temporary -= 1
		var id: int = context.temporary
		context.states.append(_new_state(context, {}, item, id, Vector2.ZERO))
		context.trace.append({"event": "equipment_initialize_at_zero", "owner": owner.id, "card": item.id, "temporary": id})
		_resolve(context, "equipment_initialize")
		# RestoreSavedStats then Equip: successful Equip unregisters its stack.
		# There is no extra ResolveOverlaps after successful equipment removal.
		for index in range(context.states.size() - 1, -1, -1):
			if context.states[index].id == id: context.states.remove_at(index)
		context.trace.append({"event": "equip_unregister", "owner": owner.id, "card": item.id, "slot": item.slot})

static func _anchor(context: Dictionary, id: int, point: Vector2, when: String) -> void:
	for row in context.states:
		if row.id == id: row.position = point
	context.trace.append({"event": "reset_anchor", "stack": id, "when": when})

static func _initialize_record(context: Dictionary, record: Dictionary, incoming: bool, defaults: bool) -> void:
	var main_id := 0
	for index in record.cards.size():
		var card: Dictionary = record.cards[index]
		var temporary: int = record.id
		if index > 0:
			context.temporary -= 1
			temporary = context.temporary
		context.states.append(_new_state(context, record, card, temporary, record.position))
		var event := "traveler_initialize" if incoming else ("default_initialize" if defaults else "saved_initialize")
		context.trace.append({"event": event, "stack": temporary, "card": card.id})
		_resolve(context, event)
		_equipment(context, card)
		if incoming or defaults or card.pack: continue
		if index == 0:
			main_id = temporary
			_anchor(context, main_id, record.position, "first")
		else:
			for n in range(context.states.size() - 1, -1, -1):
				if context.states[n].id == temporary: context.states.remove_at(n)
			for row in context.states:
				if row.id == main_id:
					row.card_ids.append(card.id)
					row.count = row.card_ids.size()
			context.trace.append({"event": "unregister_temporary_and_append", "stack": main_id, "card": card.id})
	if main_id > 0: _anchor(context, main_id, record.position, "after_stack")

static func plan(records: Array, incoming: Array, config: Dictionary) -> Dictionary:
	if config.get("scene") not in ["Main", "Island"]: return _fail("Unmapped source scene")
	if not config.get("bounds") is Rect2 or not config.bounds.has_area(): return _fail("Missing source board bounds")
	if not config.get("step") is Vector3 or not config.step.is_finite(): return _fail("Missing source stack step")
	if not config.get("max_iterations") is int or config.max_iterations <= 0: return _fail("Missing source solver iteration limit")
	if not config.get("top_margin") is float or not is_finite(config.top_margin): return _fail("Missing source top margin")
	if config.get("combat") != false or config.get("board_boost") != 0: return _fail("Combat/board expansion ordering not verified")
	if not config.get("default_spawn") is bool: return _fail("Missing source entry kind")
	var seen_cards := {}; var seen_stacks := {}
	var error := _check_records(incoming, seen_cards, seen_stacks, true, false)
	if not error.is_empty(): return _fail(error)
	error = _check_records(records, seen_cards, seen_stacks, false, config.default_spawn)
	if not error.is_empty(): return _fail(error)
	var context := {"states": [], "trace": [], "temporary": 0, "bounds": config.bounds, "margin": config.top_margin, "iterations": config.max_iterations, "step": config.step}
	var expected := {}; var expected_owners := {}
	for record in incoming + records:
		var ids: Array = []
		for card in record.cards:
			ids.append(card.id)
			for item in card.equipment: expected_owners[item.id] = card.id
		expected[record.id] = {"position": record.position, "card_ids": ids}
	for record in incoming: _initialize_record(context, record, true, false)
	for record in records: _initialize_record(context, record, false, config.default_spawn)
	return {"ok": true, "states": context.states, "trace": context.trace, "input_cards": seen_cards.keys(), "input_stacks": seen_stacks.keys(), "expected": expected, "expected_owners": expected_owners}

## Explicit commit boundary. Caller must admit an actual scene-entry transaction;
## never call this from SaveCodec.restore or ordinary staging/validation copies.
static func apply(session, result: Dictionary) -> Dictionary:
	if not result.get("ok", false): return _fail("Cannot apply failed source plan")
	if result.states.size() != session.stacks.size(): return _fail("Stale stack registry")
	if result.input_cards.size() != session.cards.size() or result.expected_owners != session.equipment.owners: return _fail("Stale card/equipment registry")
	for id in result.input_cards:
		if not session.cards.has(id): return _fail("Stale card identity")
	var next_stacks := {}
	for row in result.states:
		if not session.stacks.has(row.id) or next_stacks.has(row.id): return _fail("Stale stack identity")
		var stack = session.stacks[row.id]
		if row.card_ids != stack.card_ids or not row.position.is_finite() or stack.position != result.expected[row.id].position: return _fail("Stale stack membership/position")
		for id in row.card_ids:
			if not session.cards.has(id) or session.cards[id].stack_id != row.id: return _fail("Stale card owner")
		next_stacks[row.id] = stack
	# Validation above is complete before the first mutation.
	for row in result.states:
		var stack = next_stacks[row.id]
		stack.position = row.position
		for id in stack.card_ids: session.cards[id].position = row.position
	session.stacks = next_stacks
	return {"ok": true}
