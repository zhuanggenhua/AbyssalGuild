extends RefCounted
## Versioned Godot-native saves. No Unity binary/JSON compatibility implied.
const FORMAT = "abyssal-guild-session"
const VERSION = 1
const MAX_BYTES = 8 * 1024 * 1024
const MAX_ITEMS = 100000
const Card = preload("res://scripts/model/card.gd")
const Stack = preload("res://scripts/model/stack.gd")
const Catalog = preload("res://scripts/model/catalog.gd")

static func capture(session) -> Dictionary:
	var card_rows: Array = []
	var stack_rows: Array = []
	for card in session.cards.values():
		var row := {}
		for key in ["id", "definition_guid", "base_definition_guid", "stack_id", "uses_left", "nutrition", "health", "stored_coins"]:
			row[key] = card.get(key)
		row.position = [card.position.x, card.position.y]
		card_rows.append(row)
	for stack in session.stacks.values():
		stack_rows.append({"id": stack.id, "card_ids": stack.card_ids.duplicate(), "position": [stack.position.x, stack.position.y], "recipe_guid": stack.recipe_guid, "progress": stack.progress, "paused": stack.paused})
	var snapshot := {"format": FORMAT, "version": VERSION, "session": {
		"day": session.day, "elapsed": session.elapsed, "day_duration": session.day_duration,
		"phase": session.phase, "paused": session.paused, "speed": session.speed,
		"scene_name": session.scene_name, "friendly_mode": session.friendly_mode,
		"next_id": session._next_id, "rng_seed": str(session.rng.seed), "rng_state": str(session.rng.state),
		"cards": card_rows, "stacks": stack_rows, "discovered_recipes": session.discovered_recipes.duplicate(true),
		"vendor_payments": session.vendor_payments.duplicate(true), "quests": session.quest_tracker.save_state()}}
	for key in ["equipment", "combat", "world"]:
		var helper = session.get(key)
		if helper != null and helper.has_method("save_state"):
			snapshot.session[key] = helper.save_state()
	return snapshot

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= 9007199254740991.0

static func _number(value: Variant, minimum: float = 0.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum

static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], -1.0e20) and _number(value[1], -1.0e20) and absf(float(value[0])) <= 1.0e20 and absf(float(value[1])) <= 1.0e20

static func _int64_string(value: Variant) -> bool:
	# Round trip rejects overflow, leading zeros, whitespace, and exponent forms.
	return value is String and value.is_valid_int() and str(value.to_int()) == value

static func _recipe_card(catalog, guid: String) -> bool:
	if not guid.begins_with("Recipe:"):
		return false
	var recipe_id := guid.trim_prefix("Recipe:")
	for recipe in catalog.data.get("recipes", []):
		if str(recipe.fields.get("id", "")) != recipe_id:
			continue
		var result: String = catalog.ref_guid(recipe.fields.get("resultingCard", {}))
		catalog.definitions[guid] = {"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid, "displayName": "Recipe: " + str(catalog.fields(result).get("displayName", "???")), "category": 8, "isSellable": true, "sellPrice": 1, "recipe_guid": str(recipe.guid)}}
		return true
	return false

## Stage using independent model objects; no live session/catalog mutation on failure.
static func _stage(session, snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or snapshot.get("format") != FORMAT or snapshot.get("version") != VERSION:
		return _fail("Unsupported save format or version")
	var data = snapshot.get("session")
	if not data is Dictionary:
		return _fail("Missing session")
	if not data.get("scene_name", "Main") is String or data.get("scene_name", "Main") != session.scene_name or not data.get("friendly_mode", false) is bool:
		return _fail("Invalid scene or gameplay preferences")
	for key in ["day", "next_id"]:
		if not _integer(data.get(key), 1):
			return _fail("Invalid " + key)
	for key in ["elapsed", "day_duration", "speed"]:
		if not _number(data.get(key)):
			return _fail("Invalid " + key)
	if data.day_duration <= 0 or not float(data.speed) in [1.0, 2.0] or not data.get("phase") in ["playing", "feeding", "selling", "ready", "game_over"] or not data.get("paused") is bool:
		return _fail("Invalid clock or phase")
	if not _int64_string(data.get("rng_seed")) or not _int64_string(data.get("rng_state")):
		return _fail("Invalid RNG state")
	for key in ["cards", "stacks"]:
		if not data.get(key) is Array or data[key].size() > MAX_ITEMS:
			return _fail("Invalid " + key)
	for key in ["discovered_recipes", "vendor_payments"]:
		if not data.get(key) is Dictionary or data[key].size() > MAX_ITEMS:
			return _fail("Invalid " + key)
	var catalog = Catalog.new()
	catalog.configure(session.catalog.data)
	var recipes := {}
	var recipe_guids := {}
	for entry in catalog.data.get("recipes", []):
		recipes[str(entry.fields.get("id", ""))] = true
		recipe_guids[str(entry.guid)] = true
	for key in data.discovered_recipes:
		if not key is String or not recipes.has(key) or not data.discovered_recipes[key] is bool or data.discovered_recipes[key] != true:
			return _fail("Unknown or invalid discovered recipe")
	for key in data.vendor_payments:
		if not key is String or catalog.get_definition(key).get("script_class") != "PackDefinition" or not _integer(data.vendor_payments[key]):
			return _fail("Invalid vendor payment")
	var cards := {}
	var stacks := {}
	var all_ids := {}
	for row in data.cards:
		if not row is Dictionary:
			return _fail("Invalid card row")
		for key in ["id", "stack_id", "uses_left", "nutrition", "health", "stored_coins"]:
			if not _integer(row.get(key), 1 if key == "id" else (-9007199254740991 if key == "uses_left" else (-1 if key == "stack_id" else 0))):
				return _fail("Invalid card " + key)
		if all_ids.has(int(row.id)) or row.id >= data.next_id or not _position(row.get("position")):
			return _fail("Invalid card identity or position")
		for key in ["definition_guid", "base_definition_guid"]:
			if not row.get(key) is String:
				return _fail("Invalid card definition")
			var guid: String = row[key]
			if catalog.get_definition(guid).is_empty() and not _recipe_card(catalog, guid):
				return _fail("Unknown card definition: " + guid)
			if not catalog.get_definition(guid).get("script_class", "").ends_with("Definition") or not catalog.fields(guid).has("category") and catalog.get_definition(guid).get("script_class") != "PackDefinition":
				return _fail("Definition is not a card: " + guid)
		var card = Card.new(int(row.id), row.definition_guid, catalog.fields(row.definition_guid))
		for key in ["base_definition_guid", "stack_id", "uses_left", "nutrition", "health", "stored_coins"]:
			card.set(key, row[key])
		card.position = Vector2(row.position[0], row.position[1])
		cards[card.id] = card
		all_ids[card.id] = true
	var membership := {}
	for row in data.stacks:
		if not row is Dictionary or not _integer(row.get("id"), 1):
			return _fail("Invalid stack")
		if all_ids.has(int(row.id)) or row.id >= data.next_id or not _position(row.get("position")):
			return _fail("Invalid stack identity or position")
		if not row.get("card_ids") is Array or row.card_ids.is_empty() or row.card_ids.size() > MAX_ITEMS or not row.get("recipe_guid") is String or not _number(row.get("progress")) or not row.get("paused") is bool:
			return _fail("Invalid stack state")
		if not row.recipe_guid.is_empty() and not recipe_guids.has(row.recipe_guid):
			return _fail("Unknown stack recipe")
		var stack = Stack.new(int(row.id))
		for id in row.card_ids:
			if not _integer(id, 1) or not cards.has(int(id)) or membership.has(int(id)) or cards[int(id)].stack_id != stack.id:
				return _fail("Inconsistent stack membership")
			membership[int(id)] = true
			stack.card_ids.append(int(id))
		stack.position = Vector2(row.position[0], row.position[1])
		stack.recipe_guid = row.recipe_guid
		stack.progress = row.progress
		stack.paused = row.paused
		stacks[stack.id] = stack
		all_ids[stack.id] = true
	var helpers := {}
	for key in ["equipment", "combat", "world"]:
		var helper = session.get(key)
		if data.has(key):
			if helper == null or not helper.has_method("stage_state"):
				return _fail("Unsupported saved subsystem: " + key)
			var staged: Dictionary = helper.stage_state(data[key], cards)
			if not staged.get("ok", false):
				return _fail(key + ": " + str(staged.get("error", "Invalid state")))
			for id in staged.unstacked:
				if membership.has(id) or not cards.has(id) or cards[id].stack_id != -1:
					return _fail("Conflicting " + key + " card membership")
				membership[id] = true
			helpers[key] = staged
	if membership.size() != cards.size():
		return _fail("Orphan card")
	var quests = data.get("quests")
	if not quests is Dictionary or not quests.get("CompletedQuests") is Array or not quests.get("ActiveQuests") is Array or not _integer(quests.get("QuestProgress")):
		return _fail("Invalid quest state")
	if quests.CompletedQuests.size() + quests.ActiveQuests.size() > MAX_ITEMS:
		return _fail("Too many quests")
	var seen := {}
	for id in quests.CompletedQuests:
		if not id is String or id.is_empty() or seen.has(id):
			return _fail("Invalid completed quest")
		seen[id] = true
	for quest in quests.ActiveQuests:
		if not quest is Dictionary or not quest.get("QuestId") is String or not _integer(quest.get("CurrentAmount")):
			return _fail("Invalid active quest")
		if seen.has(quest.QuestId) or not session.quest_tracker.definitions.has(quest.QuestId):
			return _fail("Unknown or duplicate active quest")
		seen[quest.QuestId] = true
	return {"ok": true, "data": data.duplicate(true), "cards": cards, "stacks": stacks, "catalog": catalog, "helpers": helpers}

static func restore(session, snapshot: Variant) -> Dictionary:
	var staged := _stage(session, snapshot)
	if not staged.ok:
		return staged
	var data: Dictionary = staged.data
	# Commit only after all fields and cross references passed validation.
	session.catalog.definitions = staged.catalog.definitions
	session.cards = staged.cards
	session.stacks = staged.stacks
	for key in ["day", "elapsed", "day_duration", "phase", "paused", "speed", "discovered_recipes", "vendor_payments"]:
		session.set(key, data[key])
	for guid in session.vendor_payments:
		session.vendor_payments[guid] = int(session.vendor_payments[guid])
	session.scene_name = data.get("scene_name", "Main")
	session.friendly_mode = data.get("friendly_mode", false)
	session._next_id = int(data.next_id)
	session.rng.seed = data.rng_seed.to_int()
	session.rng.state = data.rng_state.to_int()
	for key in ["equipment", "combat", "world"]:
		var helper = session.get(key)
		if helper != null:
			if staged.helpers.has(key):
				helper.apply_state(staged.helpers[key])
			else:
				helper.reset()
	session.quest_tracker.restore_state(data.quests)
	session.changed.emit()
	return {"ok": true}

static func _read(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot open " + path + ": " + error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES:
		return _fail("Save exceeds size limit")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return _fail("Invalid JSON at line " + str(parser.get_error_line()))
	return {"ok": true, "snapshot": parser.data}

## One writer per path. Temp is in the same directory for atomic rename.
static func save_file(session, path: String = "user://session.json") -> Dictionary:
	var snapshot := capture(session)
	var valid := _stage(session, snapshot)
	if not valid.ok:
		return valid
	var encoded := JSON.stringify(snapshot, "", true, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return _fail("Save exceeds size limit")
	var temporary := path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Cannot create temporary save: " + error_string(FileAccess.get_open_error()))
	file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _fail("Save write failed: " + error_string(write_error))
	var checked := _read(temporary)
	if not checked.ok or not _stage(session, checked.snapshot).ok:
		return _fail("Temporary save verification failed")
	# Keep last validated primary. Never replace a healthy backup with corruption.
	if FileAccess.file_exists(path):
		var old := _read(path)
		if old.ok and _stage(session, old.snapshot).ok:
			var backup_temp := path + ".bak.tmp"
			var copied := DirAccess.copy_absolute(path, backup_temp)
			if copied != OK:
				return _fail("Backup copy failed: " + error_string(copied))
			var backed_up := DirAccess.rename_absolute(backup_temp, path + ".bak")
			if backed_up != OK:
				return _fail("Backup replacement failed: " + error_string(backed_up))
	var replaced := DirAccess.rename_absolute(temporary, path)
	if replaced != OK:
		return _fail("Save replacement failed: " + error_string(replaced))
	return {"ok": true, "path": path}

## Prefer committed primary, then last good backup. Never silently promote .tmp.
static func load_file(session, path: String = "user://session.json") -> Dictionary:
	var errors: Array = []
	for candidate in [path, path + ".bak"]:
		var read := _read(candidate)
		if read.ok:
			var result := restore(session, read.snapshot)
			if result.ok:
				return {"ok": true, "path": candidate, "recovered": candidate != path}
			errors.append(result.error)
		else:
			errors.append(read.error)
	return _fail("; ".join(errors))
