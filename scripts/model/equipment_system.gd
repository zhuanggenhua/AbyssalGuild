extends RefCounted
## Independent data-model rewrite of equipment/stat rules. No scene dependencies.
const StackModel = preload("res://scripts/model/stack.gd")
const STAT_NAMES = ["maxHealth", "attack", "defense", "attackSpeed", "accuracy", "dodge", "criticalChance", "criticalMultiplier"]
const DEFAULTS = [15, 2, 1, 100, 95, 5, 5, 150]
var _session: WeakRef
var equipped: Dictionary = {} # wearer -> {slot -> item}
var owners: Dictionary = {} # item -> wearer
var originals: Dictionary = {}
var class_items: Dictionary = {}

func configure(session) -> void:
	_session = weakref(session)
	reset()

func reset() -> void:
	equipped.clear()
	owners.clear()
	originals.clear()
	class_items.clear()

static func round_even(value: float) -> int:
	var lower := floori(value)
	var fraction := value - lower
	if is_equal_approx(fraction, 0.5):
		return lower if lower % 2 == 0 else lower + 1
	return floori(value + 0.5)

func stats(card_id: int) -> Dictionary:
	var session = _session.get_ref()
	if not session.cards.has(card_id):
		return {}
	var fields: Dictionary = session.catalog.fields(session.cards[card_id].definition_guid)
	var result: Dictionary = {}
	for i in STAT_NAMES.size():
		var value: float = float(fields.get(STAT_NAMES[i], DEFAULTS[i]))
		for item in equipped.get(card_id, {}).values():
			if not session.cards.has(item):
				continue
			for modifier in session.catalog.fields(session.cards[item].definition_guid).get("statModifiers", []):
				if int(modifier.get("Stat", -1)) == i:
					value += float(modifier.get("value", 0))
		result[STAT_NAMES[i]] = round_even(value)
	return result

func equip(wearer_id: int, item_id: int) -> bool:
	var session = _session.get_ref()
	if not session.cards.has(wearer_id) or not session.cards.has(item_id) or owners.has(item_id):
		return false
	var wearer = session.cards[wearer_id]
	var item = session.cards[item_id]
	var fields: Dictionary = session.catalog.fields(item.definition_guid)
	if int(fields.get("category", 0)) != 5 or int(session.catalog.fields(wearer.definition_guid).get("category", 0)) != 2:
		return false
	var slot: int = int(fields.get("equipmentSlot", 0))
	unequip(wearer_id, slot)
	if not equipped.has(wearer_id):
		equipped[wearer_id] = {}
	equipped[wearer_id][slot] = item_id
	owners[item_id] = wearer_id
	detach(session, item_id)
	var transform_guid: String = session.catalog.ref_guid(fields.get("classChangeResult", {}))
	if not transform_guid.is_empty() and not session.catalog.fields(transform_guid).is_empty():
		if not originals.has(wearer_id):
			originals[wearer_id] = wearer.definition_guid
		class_items[wearer_id] = item_id
		wearer.definition_guid = transform_guid
	# SetDefinition does not heal or clamp health; modifiers are evaluated on new base.
	session.event_occurred.emit("card_equipped", {"card_id": wearer_id, "definition_guid": item.definition_guid})
	session.changed.emit()
	return true

func unequip(wearer_id: int, slot: int) -> int:
	var session = _session.get_ref()
	if not equipped.get(wearer_id, {}).has(slot):
		return -1
	var item_id: int = equipped[wearer_id][slot]
	if class_items.get(wearer_id, -1) == item_id:
		if session.cards.has(wearer_id):
			session.cards[wearer_id].definition_guid = originals[wearer_id]
		originals.erase(wearer_id)
		class_items.erase(wearer_id)
	equipped[wearer_id].erase(slot)
	owners.erase(item_id)
	if session.cards.has(item_id):
		if session.cards.has(wearer_id):
			session.cards[item_id].position = session.cards[wearer_id].position
		return_to_board(session, item_id)
	session.changed.emit()
	return item_id

func unequip_all(wearer_id: int) -> void:
	for slot in equipped.get(wearer_id, {}).keys():
		unequip(wearer_id, slot)
	equipped.erase(wearer_id)

static func detach(session, card_id: int) -> void:
	var card = session.cards[card_id]
	var stack = session.stacks.get(card.stack_id)
	if stack != null:
		stack.cancel_craft()
		stack.card_ids.erase(card_id)
		if stack.card_ids.is_empty():
			session.stacks.erase(stack.id)
	card.stack_id = -1

static func return_to_board(session, card_id: int) -> void:
	if not session.cards.has(card_id) or session.stacks.has(session.cards[card_id].stack_id):
		return
	var stack = StackModel.new(session._next_id)
	session._next_id += 1
	stack.position = session.cards[card_id].position
	stack.card_ids.append(card_id)
	session.stacks[stack.id] = stack
	session.cards[card_id].stack_id = stack.id
