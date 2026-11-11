extends RefCounted
## Independent implementation of the audited QuestManager event semantics.
enum QuestType { HAVE, OBTAIN, DISCOVER, DEFEAT, CRAFT, SELL, BUY, EQUIP, EXPLORE, TIME, DAY, FOOD, COINS, CAPACITY }
enum QuestStatus { INACTIVE, ACTIVE, COMPLETED }
signal quest_activated(instance: Dictionary)
signal quest_completed(instance: Dictionary)
var catalog
var quest_groups: Array = []
var definitions: Dictionary = {} # Stable Quest.Id -> normalized fields.
var guid_to_id: Dictionary = {}
var active_quests: Array = []
var completed_quests: Array = []
var completed_ids: Dictionary = {}
var errors: Array[String] = []

## Default is Main, never the union of Main and Island.
func configure(source_catalog, scene_name: String = "Main", groups: Variant = null) -> bool:
	catalog = source_catalog
	definitions.clear()
	guid_to_id.clear()
	errors.clear()
	_reset()
	quest_groups = []
	var found_manager: bool = groups != null
	if groups != null:
		quest_groups = groups.duplicate(true)
	else:
		for scene in catalog.data.get("scenes", []):
			if scene.get("name", "") == scene_name:
				for document in scene.get("documents", []):
					if document.get("fields", {}).has("questGroups"):
						quest_groups = document.fields.questGroups.duplicate(true)
						found_manager = true
	if not found_manager:
		errors.append("No quest manager for scene: " + scene_name)
		return false
	for entry in catalog.data.get("quests", []):
		guid_to_id[str(entry.guid)] = str(entry.fields.get("id", ""))
	for group in quest_groups:
		for reference in group.get("Quests", []):
			var guid: String = catalog.ref_guid(reference)
			var fields: Dictionary = catalog.fields(guid).duplicate(true)
			var id: String = str(fields.get("id", ""))
			if id.is_empty() or definitions.has(id):
				errors.append("Missing or duplicate Quest.Id: " + guid)
				continue
			var defaults := {"title": "", "description": "", "type": 0, "targetAmount": 1, "targetPace": 1, "targetCard": {}, "targetRecipe": {}, "prerequisiteQuests": [], "questsToUnlock": []}
			for key in defaults:
				if not fields.has(key):
					fields[key] = defaults[key]
			fields["guid"] = guid
			definitions[id] = fields
	for fields in definitions.values():
		for key in ["prerequisiteQuests", "questsToUnlock"]:
			for reference in fields[key]:
				if not definitions.has(_reference_id(reference)):
					errors.append("Missing scene quest reference: " + catalog.ref_guid(reference))
	return errors.is_empty()

func _reset() -> void:
	active_quests.clear()
	completed_quests.clear()
	completed_ids.clear()

func start_new_game(session) -> void:
	_reset()
	for id in definitions:
		if definitions[id].prerequisiteQuests.is_empty():
			_activate(id, session)

func completed_count() -> int:
	return completed_ids.size()

func all_quests() -> Array:
	return completed_quests + active_quests

func _reference_id(reference: Variant) -> String:
	return str(guid_to_id.get(catalog.ref_guid(reference), ""))

func _activate(id: String, session) -> void:
	if completed_ids.has(id) or not definitions.has(id):
		return
	for instance in active_quests:
		if instance.id == id:
			return
	var instance := {"id": id, "status": QuestStatus.ACTIVE, "current_amount": 0}
	active_quests.append(instance)
	quest_activated.emit(instance)
	# Only Have and Discover replay state at activation in the source.
	if int(definitions[id].type) == QuestType.HAVE:
		sync_stats(session)
	elif int(definitions[id].type) == QuestType.DISCOVER:
		for recipe_id in session.discovered_recipes.keys():
			process_event("recipe_discovered", {"recipe_id": recipe_id}, session)

func _check(instance: Dictionary, session) -> void:
	if instance.status != QuestStatus.ACTIVE:
		return
	var fields: Dictionary = definitions[instance.id]
	if int(instance.current_amount) < int(fields.targetAmount):
		return
	instance.status = QuestStatus.COMPLETED
	active_quests.erase(instance)
	completed_ids[instance.id] = true
	completed_quests.append(instance)
	for reference in fields.questsToUnlock:
		var id: String = _reference_id(reference)
		if not definitions.has(id):
			continue
		var eligible := true
		for prerequisite in definitions[id].prerequisiteQuests:
			if not completed_ids.has(_reference_id(prerequisite)):
				eligible = false
		if eligible:
			_activate(id, session)
	# Source emits completion after recursively activating its successors.
	quest_completed.emit(instance)

func sync_stats(session) -> void:
	var snapshot: Dictionary = session.stats()
	for instance in active_quests.duplicate():
		var fields: Dictionary = definitions[instance.id]
		var amount: int
		match int(fields.type):
			QuestType.HAVE:
				var target: String = catalog.ref_guid(fields.targetCard)
				if int(catalog.fields(target).get("category", 0)) == 7:
					amount = int(snapshot.get("currency", 0))
				else:
					amount = 0
					for card in session.cards.values():
						if card.base_definition_guid == target:
							amount += 1
			QuestType.FOOD:
				amount = int(snapshot.get("nutrition", 0))
			QuestType.COINS:
				amount = int(snapshot.get("currency", 0))
			QuestType.CAPACITY:
				amount = int(snapshot.get("card_limit", 0))
			_:
				continue
		instance.current_amount = amount
		_check(instance, session)

## See docs/quest-tracker.md for required emission sites and payload identities.
func process_event(kind: String, payload: Dictionary, session) -> void:
	if kind == "stats_changed":
		sync_stats(session)
		return
	for instance in active_quests.duplicate():
		var fields: Dictionary = definitions[instance.id]
		var type: int = int(fields.type)
		var target: String = catalog.ref_guid(fields.targetCard)
		var amount: int = 1
		var additive := true
		var matches := false
		match kind:
			"card_created":
				matches = type == QuestType.OBTAIN and target == str(payload.get("base_definition_guid", ""))
			"card_killed":
				matches = type == QuestType.DEFEAT and target == str(payload.get("definition_guid", ""))
			"crafted":
				matches = type == QuestType.CRAFT and target == str(payload.get("definition_guid", ""))
			"recipe_discovered":
				matches = type == QuestType.DISCOVER and str(catalog.fields(catalog.ref_guid(fields.targetRecipe)).get("id", "")) == str(payload.get("recipe_id", ""))
				additive = false
			"cards_sold":
				if type == QuestType.SELL:
					amount = 0
					for guid in payload.get("base_definition_guids", []):
						if target.is_empty() or target == str(guid):
							amount += 1
					matches = amount > 0
			"pack_purchased":
				matches = type == QuestType.BUY and (target.is_empty() or target == str(payload.get("definition_guid", "")))
			"card_equipped", "exploration_finished":
				matches = type == (QuestType.EQUIP if kind == "card_equipped" else QuestType.EXPLORE) and target == str(payload.get("definition_guid", ""))
				additive = false
			"time_pace_changed":
				matches = type == QuestType.TIME and int(fields.targetPace) == int(payload.get("pace", -1))
				additive = false
			"day_started":
				matches = type == QuestType.DAY
				amount = int(payload.get("day", 0))
				additive = false
		if matches:
			instance.current_amount = int(instance.current_amount) + amount if additive else amount
			_check(instance, session)

func save_state() -> Dictionary:
	var active: Array = []
	for instance in active_quests:
		active.append({"QuestId": instance.id, "CurrentAmount": instance.current_amount})
	var progress: int = _round_to_even(100.0 * completed_count() / definitions.size()) if not definitions.is_empty() else 0
	return {"CompletedQuests": completed_ids.keys(), "ActiveQuests": active, "QuestProgress": progress}

## Restore does not re-evaluate or complete active quests, nor activate new roots.
## Unknown completed IDs remain counted, matching source save compatibility.
func restore_state(data: Dictionary) -> void:
	_reset()
	for id in data.get("CompletedQuests", []):
		completed_ids[str(id)] = true
		if definitions.has(str(id)):
			completed_quests.append({"id": str(id), "status": QuestStatus.COMPLETED, "current_amount": int(definitions[str(id)].targetAmount)})
	for saved in data.get("ActiveQuests", []):
		var id: String = str(saved.get("QuestId", ""))
		if definitions.has(id):
			var instance := {"id": id, "status": QuestStatus.ACTIVE, "current_amount": int(saved.get("CurrentAmount", 0))}
			active_quests.append(instance)
			quest_activated.emit(instance)

func _round_to_even(value: float) -> int:
	var lower: int = int(floor(value))
	if value - float(lower) == 0.5:
		return lower if lower % 2 == 0 else lower + 1
	return int(round(value))
