extends RefCounted
## Global card discovery and menu read state. Stable definition IDs, not GUIDs.
signal changed
const MAX_IDS = 100000
const MAX_ID_LENGTH = 256
var catalog
var discovered_cards: Dictionary = {}
var seen_items: Dictionary = {}
var known_menu_ids: Dictionary = {}

func configure(source_catalog) -> void:
	catalog = source_catalog
	known_menu_ids.clear()
	for group in ["recipes", "quests"]:
		for entry in catalog.data.get(group, []):
			var id: String = str(entry.fields.get("id", ""))
			if valid_id(id):
				known_menu_ids[id] = true
	reset()

func reset() -> void:
	discovered_cards.clear()
	seen_items.clear()

static func valid_id(id: Variant) -> bool:
	return id is String and not id.is_empty() and id.length() <= MAX_ID_LENGTH and not id.to_utf8_buffer().has(0)

func mark_card(guid: String) -> bool:
	var definition: Dictionary = catalog.get_definition(guid)
	var fields: Dictionary = definition.get("fields", {})
	var id: Variant = fields.get("id", "")
	if definition.get("script_class", "") == "PackDefinition" or int(fields.get("category", 0)) == 8 or not valid_id(id) or discovered_cards.has(id):
		return false
	discovered_cards[id] = true
	changed.emit()
	return true

func is_card_discovered(guid: String) -> bool:
	var id: String = str(catalog.fields(guid).get("id", ""))
	return not id.is_empty() and discovered_cards.has(id)

func is_unread(id: String) -> bool:
	return known_menu_ids.has(id) and not seen_items.has(id)

## Call on an actual item hover-enter only, not on menu opening or completion.
func mark_seen(id: String) -> bool:
	if not known_menu_ids.has(id) or seen_items.has(id) or not valid_id(id):
		return false
	seen_items[id] = true
	changed.emit()
	return true

func pack_progress(pack_guid: String, discovered_recipes: Dictionary) -> Dictionary:
	var possible_cards: Dictionary = {}
	var possible_recipes: Dictionary = {}
	for slot in catalog.fields(pack_guid).get("slots", []):
		var entries: Variant = slot.get("Entries", [])
		if not entries is Array:
			entries = []
		for entry in entries:
			if not entry is Dictionary:
				continue
			var guid: String = catalog.ref_guid(entry.get("Card", {}))
			if not catalog.get_definition(guid).is_empty():
				possible_cards[guid] = true
		var recipes: Variant = slot.get("PossibleRecipes", [])
		if not recipes is Array:
			recipes = []
		for reference in recipes:
			var id: String = str(catalog.fields(catalog.ref_guid(reference)).get("id", ""))
			if not id.is_empty():
				possible_recipes[id] = true
	var found: int = 0
	for guid in possible_cards:
		if is_card_discovered(guid):
			found += 1
	for id in possible_recipes:
		if discovered_recipes.has(id):
			found += 1
	var total: int = possible_cards.size() + possible_recipes.size()
	return {"found": found, "total": total, "cards_total": possible_cards.size(), "recipes_total": possible_recipes.size(), "complete": total > 0 and found >= total}

func save_state() -> Dictionary:
	var cards: Array = discovered_cards.keys()
	var seen: Array = seen_items.keys()
	cards.sort()
	seen.sort()
	return {"discovered_cards": cards, "seen_items": seen}

func stage_state(raw: Variant, _cards: Dictionary = {}) -> Dictionary:
	var invalid := {"ok": false, "error": "Invalid collection snapshot"}
	if not raw is Dictionary:
		return invalid
	var result := {"ok": true, "discovered_cards": {}, "seen_items": {}, "unstacked": []}
	for key in ["discovered_cards", "seen_items"]:
		if not raw.get(key) is Array or raw[key].size() > MAX_IDS:
			return invalid
		for id in raw[key]:
			if not valid_id(id) or result[key].has(id):
				return invalid
			result[key][id] = true
	return result

func apply_state(staged: Dictionary) -> void:
	discovered_cards = staged.discovered_cards.duplicate()
	seen_items = staged.seen_items.duplicate()

## Legacy evidence only: cannot recover sold cards or prior suppressed draws.
func infer_legacy(cards: Dictionary) -> Dictionary:
	var result := {"ok": true, "discovered_cards": {}, "seen_items": {}, "unstacked": []}
	for card in cards.values():
		var definition: Dictionary = catalog.get_definition(card.definition_guid)
		var fields: Dictionary = definition.get("fields", {})
		var id: Variant = fields.get("id", "")
		if definition.get("script_class", "") != "PackDefinition" and int(fields.get("category", 0)) != 8 and valid_id(id):
			result.discovered_cards[id] = true
	return result

func merge_state(staged: Dictionary) -> void:
	discovered_cards.merge(staged.discovered_cards, true)
	seen_items.merge(staged.seen_items, true)
