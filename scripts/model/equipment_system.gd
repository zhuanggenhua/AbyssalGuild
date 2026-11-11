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

func save_state() -> Dictionary:
	var wearers: Array = []
	for wearer in equipped:
		var items: Array = []
		for slot in equipped[wearer]:
			items.append({"slot": slot, "item": equipped[wearer][slot]})
		wearers.append({"wearer": wearer, "items": items, "original": originals.get(wearer, ""), "class_item": class_items.get(wearer, -1)})
	return {"wearers": wearers}

func stage_state(raw: Variant, cards: Dictionary) -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid equipment snapshot"}
	if not raw is Dictionary or not raw.get("wearers", null) is Array:
		return invalid
	if raw.wearers.size() > cards.size():
		return invalid
	var result := {"ok": true, "equipped": {}, "owners": {}, "originals": {}, "class_items": {}, "unstacked": []}
	var catalog = _session.get_ref().catalog
	for record in raw.wearers:
		if not record is Dictionary or not record.get("items", null) is Array:
			return invalid
		if not valid_integer(record.get("wearer"), 1) or not valid_integer(record.get("class_item", -1)) or not record.get("original", "") is String or record.items.size() > 3:
			return invalid
		var wearer: int = int(record.get("wearer", -1))
		if not cards.has(wearer) or result.equipped.has(wearer) or int(catalog.fields(cards[wearer].definition_guid).get("category", 0)) != 2:
			return invalid
		result.equipped[wearer] = {}
		for entry in record.items:
			if not entry is Dictionary or not valid_integer(entry.get("item"), 1) or not valid_integer(entry.get("slot"), 0):
				return invalid
			var item: int = int(entry.get("item", -1))
			var slot: int = int(entry.get("slot", -1))
			if not cards.has(item) or result.owners.has(item) or result.equipped[wearer].has(slot) or slot not in [0, 1, 2]:
				return invalid
			var fields: Dictionary = catalog.fields(cards[item].definition_guid)
			if int(fields.get("category", 0)) != 5 or int(fields.get("equipmentSlot", 0)) != slot or cards[item].stack_id != -1:
				return invalid
			result.equipped[wearer][slot] = item
			result.owners[item] = wearer
			result.unstacked.append(item)
		var original: String = str(record.get("original", ""))
		var class_item: int = int(record.get("class_item", -1))
		if original.is_empty() != (class_item == -1):
			return invalid
		if class_item != -1:
			if not cards.has(class_item) or result.owners.get(class_item, -1) != wearer or catalog.fields(original).is_empty():
				return invalid
			if catalog.ref_guid(catalog.fields(cards[class_item].definition_guid).get("classChangeResult", {})) != cards[wearer].definition_guid:
				return invalid
			result.originals[wearer] = original
			result.class_items[wearer] = class_item
	return result

func apply_state(staged: Dictionary) -> void:
	equipped = staged.equipped
	owners = staged.owners
	originals = staged.originals
	class_items = staged.class_items

static func valid_integer(value: Variant, minimum: int = -1) -> bool:
	if not value is int and not value is float:
		return false
	return is_finite(float(value)) and float(value) >= minimum and float(value) <= 9007199254740991.0 and float(value) == floor(float(value))

static func valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## Ordinary destruction destroys attached equipment; Kill drops it first.
func remove_card_state(card_id: int) -> void:
	var session = _session.get_ref()
	if owners.has(card_id):
		var wearer: int = owners[card_id]
		for slot in equipped.get(wearer, {}).keys():
			if equipped[wearer][slot] == card_id:
				unequip(wearer, slot)
	for item in equipped.get(card_id, {}).values().duplicate():
		session._remove_card(item)
	equipped.erase(card_id)
	originals.erase(card_id)
	class_items.erase(card_id)
