extends RefCounted
## Source-audited scene encounters, storage, enclosure and autonomous decisions.
## Coordinates are source world X/Z, represented by Vector2 X/Y.
var _session: WeakRef
var scene_name: String = "Main"
var encounter_guids: Array = []
var currency_guid: String = ""
var spawn_edge_padding: float = 2.0
var completed_encounters: Dictionary = {} # Encounter.Id, not asset GUID.
var processed_days: Dictionary = {} # End-cycle reentry guard, including empty days.
var production_timers: Dictionary = {}

func configure(session, selected_scene: String = "Main") -> void:
	_session = weakref(session)
	scene_name = selected_scene
	encounter_guids.clear()
	currency_guid = ""
	spawn_edge_padding = 2.0
	reset()
	for scene in session.catalog.data.get("scenes", []):
		if scene.get("name", "") != scene_name:
			continue
		for document in scene.get("documents", []):
			var fields: Dictionary = document.get("fields", {})
			if document.get("script_class", "") == "EncounterManager":
				spawn_edge_padding = float(fields.get("spawnEdgePadding", 2.0))
				for reference in fields.get("allEncounters", []):
					encounter_guids.append(session.catalog.ref_guid(reference))
			if document.get("script_class", "") == "TradeManager":
				currency_guid = session.catalog.ref_guid(fields.get("currencyCard", {}))

func reset() -> void:
	completed_encounters.clear()
	processed_days.clear()
	production_timers.clear()

func export_state() -> Dictionary:
	return {"scene": scene_name, "completed_encounters": completed_encounters.keys(), "processed_days": processed_days.keys()}

func save_state() -> Dictionary:
	return export_state()

func stage_state(raw: Variant, _cards: Dictionary = {}) -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid world snapshot"}
	if not raw is Dictionary or not raw.get("scene") is String or raw.scene != scene_name:
		return invalid
	if not raw.get("completed_encounters") is Array or not raw.get("processed_days") is Array or raw.processed_days.size() > 100000:
		return invalid
	var known: Dictionary = {}
	var session = _session.get_ref()
	for guid in encounter_guids:
		var fields: Dictionary = session.catalog.fields(guid)
		if fields.get("oneTimeOnly", false):
			known[str(fields.get("id", ""))] = true
	var result := {"ok": true, "completed_encounters": {}, "processed_days": {}, "unstacked": []}
	for id in raw.completed_encounters:
		if not id is String or not known.has(id) or result.completed_encounters.has(id):
			return invalid
		result.completed_encounters[id] = true
	for day in raw.processed_days:
		if not (day is int or day is float) or not is_finite(float(day)) or float(day) < 1 or float(day) > 9007199254740991.0 or floor(float(day)) != float(day) or result.processed_days.has(int(day)):
			return invalid
		result.processed_days[int(day)] = true
	return result

func apply_state(staged: Dictionary) -> void:
	completed_encounters = staged.completed_encounters.duplicate()
	processed_days = staged.processed_days.duplicate()
	production_timers.clear()

func restore_state(state: Dictionary) -> bool:
	var staged: Dictionary = stage_state(state)
	if not staged.ok:
		return false
	apply_state(staged)
	return true

func board_card_count() -> int:
	var session = _session.get_ref()
	return session.cards.size() - session.equipment.owners.size()

static func matches_day(fields: Dictionary, day: int) -> bool:
	var value: int = int(fields.get("dayValue", 0))
	match int(fields.get("type", 0)):
		0: return day == value
		1: return value != 0 and day > 0 and day % value == 0
		2: return day >= value and day <= int(fields.get("maxDayValue", 999))
		3: return day >= value
	return false

## Optional roll callable is only invoked for candidates passing non-RNG checks.
## All candidates roll in serialized order, even after a higher priority success.
func select_encounter(day: int, friendly: bool = false, roll: Callable = Callable()) -> String:
	var session = _session.get_ref()
	var best: String = ""
	var best_priority: int = -2147483648
	var best_type: int = 5
	for guid in encounter_guids:
		var fields: Dictionary = session.catalog.fields(guid)
		var spawn: String = session.catalog.ref_guid(fields.get("cardToSpawn", {}))
		if fields.is_empty() or spawn.is_empty():
			continue
		if board_card_count() >= int(fields.get("maxCardsOnBoardLimit", 100)):
			continue
		if fields.get("oneTimeOnly", false) and completed_encounters.has(str(fields.get("id", ""))):
			continue
		if friendly and session.catalog.fields(spawn).get("isAggressive", false):
			continue
		if not matches_day(fields, day):
			continue
		var value: float = float(roll.call()) if roll.is_valid() else session.rng.randf()
		if value > float(fields.get("chance", 1.0)):
			continue
		var priority: int = int(fields.get("priority", 0))
		var kind: int = int(fields.get("type", 0))
		if best.is_empty() or priority > best_priority or (priority == best_priority and kind < best_type):
			best = guid
			best_priority = priority
			best_type = kind
	return best

## Call once after feeding/selling succeeds, BEFORE incrementing the day.
## null bounds reproduces the source's no-Board fallback at the origin.
func finish_day(day: int, friendly: bool = false, bounds: Variant = null, top_margin: float = 1.5) -> Dictionary:
	if processed_days.has(day):
		return {}
	processed_days[day] = true
	var session = _session.get_ref()
	var guid: String = select_encounter(day, friendly)
	if guid.is_empty():
		return {}
	var fields: Dictionary = session.catalog.fields(guid)
	if fields.get("oneTimeOnly", false):
		completed_encounters[str(fields.get("id", ""))] = true
	var spawned: Array = []
	for index in range(int(fields.get("count", 1))):
		var position := Vector2.ZERO
		if bounds is Rect2:
			position = Vector2(session.rng.randf_range(bounds.position.x + spawn_edge_padding, bounds.end.x - spawn_edge_padding), session.rng.randf_range(bounds.position.y + spawn_edge_padding, bounds.end.y - spawn_edge_padding))
			position.y = minf(position.y, bounds.end.y - top_margin - 1.0)
		# Every event card gets its own stack (source RefuseAll).
		spawned.append(session.spawn_card(session.catalog.ref_guid(fields.get("cardToSpawn", {})), position))
	var result := {"encounter_guid": guid, "id": str(fields.get("id", "")), "message": str(fields.get("notificationMessage", "")), "spawned": spawned}
	session.event_occurred.emit("encounter", result)
	return result

func _is_chest(card_id: int) -> bool:
	var session = _session.get_ref()
	return session.cards.has(card_id) and session.catalog.get_definition(session.cards[card_id].base_definition_guid).get("script_class", "") == "ChestDefinition"

## handled remains true for a full chest if the dropped top card is currency.
func deposit_stack(chest_id: int, stack_id: int) -> Dictionary:
	var result := {"handled": false, "deposited": 0}
	var session = _session.get_ref()
	if not _is_chest(chest_id) or currency_guid.is_empty() or not session.stacks.has(stack_id):
		return result
	var ids: Array = session.stacks[stack_id].card_ids.duplicate()
	if ids.is_empty() or session.cards[ids.front()].base_definition_guid != currency_guid:
		return result
	result.handled = true
	var chest = session.cards[chest_id]
	var capacity: int = int(session.catalog.fields(chest.base_definition_guid).get("capacity", 50))
	for id in ids:
		if chest.stored_coins >= capacity:
			break
		if session.cards.has(id) and session.cards[id].base_definition_guid == currency_guid:
			chest.stored_coins += 1
			result.deposited += 1
			session.stacks[stack_id].cancel_craft()
			session._remove_card(id) # Destroy, never Kill or loot.
	if result.deposited > 0:
		session._notify_stats_changed()
		session.changed.emit()
	return result

## Click gate is separate: trade withdrawal is allowed while chest is stacked.
func can_click_chest(chest_id: int) -> bool:
	var session = _session.get_ref()
	return _is_chest(chest_id) and session.stacks.has(session.cards[chest_id].stack_id) and session.stacks[session.cards[chest_id].stack_id].card_ids.size() == 1

## Caller supplies Board-enforced spawn position for click withdrawal.
func withdraw_coin(chest_id: int, spawn_on_board: bool = false, spawn_position: Vector2 = Vector2.ZERO) -> bool:
	var session = _session.get_ref()
	if not _is_chest(chest_id) or currency_guid.is_empty() or session.cards[chest_id].stored_coins <= 0:
		return false
	session.cards[chest_id].stored_coins -= 1
	if spawn_on_board:
		session.spawn_card(currency_guid, spawn_position)
	session._notify_stats_changed()
	session.changed.emit()
	return true

func should_stay_in_enclosure(card_id: int) -> bool:
	var session = _session.get_ref()
	if not session.cards.has(card_id):
		return false
	var card = session.cards[card_id]
	if session.catalog.fields(card.definition_guid).get("isAggressive", false) or not session.stacks.has(card.stack_id):
		return false
	var ids: Array = session.stacks[card.stack_id].card_ids
	for index in range(ids.size()):
		var definition: Dictionary = session.catalog.get_definition(session.cards[ids[index]].base_definition_guid)
		if definition.get("script_class", "") == "EnclosureDefinition":
			var distance: int = ids.find(card_id) - index
			return distance > 0 and distance <= int(definition.fields.get("capacity", 1))
	return false

func can_act(card_id: int) -> bool:
	var session = _session.get_ref()
	if not session.cards.has(card_id) or session.combat.dragged.has(card_id) or session.combat.membership.has(card_id):
		return false
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	return stack == null or stack.recipe_guid.is_empty()

## Call at AI creation/restart for passive mobs; no automatic registration.
func start_production(card_id: int) -> bool:
	var session = _session.get_ref()
	production_timers.erase(card_id)
	if not session.cards.has(card_id):
		return false
	var fields: Dictionary = session.catalog.fields(session.cards[card_id].definition_guid)
	if fields.get("isAggressive", false) or session.catalog.ref_guid(fields.get("produceCard", {})).is_empty():
		return false
	production_timers[card_id] = session.rng.randf_range(0.5, 1.0) + float(fields.get("produceInterval", 10.0))
	return true

## delta is scaled game time, zero while paused. Failed checks consume the interval.
## One wake per frame, no catch-up burst (matching coroutine waits).
func tick_production(delta: float) -> Array:
	var spawned: Array = []
	if delta <= 0:
		return spawned
	var session = _session.get_ref()
	for id in production_timers.keys():
		if not session.cards.has(id):
			production_timers.erase(id)
			continue
		production_timers[id] -= delta
		if production_timers[id] > 0:
			continue
		var fields: Dictionary = session.catalog.fields(session.cards[id].definition_guid)
		production_timers[id] = float(fields.get("produceInterval", 10.0))
		var produce: String = session.catalog.ref_guid(fields.get("produceCard", {}))
		if not fields.get("isAggressive", false) and can_act(id) and not produce.is_empty():
			spawned.append(session.spawn_card(produce, session.cards[id].position))
	return spawned

## Combat snapshots: {id, ongoing, position: Vector2, has_player}. Omit rectless tasks.
## This chooses intent only; movement validation/stack detachment belongs to caller.
func aggressive_intent(card_id: int, combats: Array = []) -> Dictionary:
	var session = _session.get_ref()
	if not session.cards.has(card_id):
		return {}
	var card = session.cards[card_id]
	var fields: Dictionary = session.catalog.fields(card.definition_guid)
	var radius: float = float(fields.get("aggroRadius", 5.0))
	var attack: float = float(fields.get("attackRadius", 1.5))
	var nearest: Dictionary = {}
	var distance: float = radius * radius
	for task in combats:
		if not task.get("ongoing", false) or not task.get("has_player", false) or not task.get("position") is Vector2:
			continue
		var candidate: float = card.position.distance_squared_to(task.position)
		if candidate < distance:
			distance = candidate
			nearest = task
	if not nearest.is_empty():
		return {"action": "join_combat" if sqrt(distance) <= attack * 1.5 else "approach_combat", "combat_id": nearest.id, "position": nearest.position}
	var target: int = -1
	distance = INF # Source FindClosestPlayerCard does NOT enforce its radius parameter.
	for candidate in session.cards.values():
		if session.equipment.owners.has(candidate.id):
			continue
		if int(session.catalog.fields(candidate.definition_guid).get("faction", 0)) != 1 or session.combat.membership.has(candidate.id):
			continue
		var value: float = card.position.distance_squared_to(candidate.position)
		if value < distance:
			distance = value
			target = candidate.id
	if target != -1:
		return {"action": "attack_player" if sqrt(distance) <= attack else "approach_player", "card_id": target, "position": session.cards[target].position}
	return {"action": "patrol"}
