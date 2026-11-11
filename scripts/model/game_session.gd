extends RefCounted
## Engine-independent gameplay slice. No nodes, imported art, or Unity code.
const Collection = preload("res://scripts/model/collection.gd")
const CardModel = preload("res://scripts/model/card.gd")
const StackModel = preload("res://scripts/model/stack.gd")
const SpecialRecipes = preload("res://scripts/model/special_recipes.gd")
const EquipmentSystem = preload("res://scripts/model/equipment_system.gd")
const MobAI = preload("res://scripts/model/mob_ai.gd")
const Campaign = preload("res://scripts/model/campaign.gd")
const WorldRules = preload("res://scripts/model/world_rules.gd")
const CombatSystem = preload("res://scripts/model/combat_system.gd")
const QuestTracker = preload("res://scripts/model/quest_tracker.gd")
signal changed
signal event_occurred(kind: String, payload: Dictionary)
var catalog
var collection = Collection.new()
var cards: Dictionary = {}
var stacks: Dictionary = {}
var discovered_recipes: Dictionary = {}
var quest_tracker = QuestTracker.new()
var equipment = EquipmentSystem.new()
var combat = CombatSystem.new()
var world = WorldRules.new()
var campaign = Campaign.new()
var ai = MobAI.new()
var scene_name: String = "Main"
var friendly_mode: bool = false
var board_bounds: Variant = null
var board_top_margin: float = 1.5
var completed_quests: int:
	get:
		return quest_tracker.completed_count()
var vendor_payments: Dictionary = {}
var day: int = 1
var elapsed: float = 0.0
var day_duration: float = 120.0
var phase: String = "playing"
var paused: bool = false
var speed: float = 1.0
var rng := RandomNumberGenerator.new()
var _next_id: int = 1
## Pure view geometry query; session owns validation and merge side effects.
var spawn_target_selector: Callable = Callable()
var spawn_layout_resolver: Callable = Callable()
var spawn_query_height: float = 0.0
var _selecting_spawn: bool = false

func configure(source_catalog, random_seed: int = 1, selected_scene: String = "Main") -> void:
	catalog = source_catalog
	collection.configure(catalog)
	scene_name = selected_scene
	campaign.configure(self, scene_name)
	world.configure(self, scene_name)
	equipment.configure(self)
	combat.configure(self, equipment)
	rng.seed = random_seed
	quest_tracker.configure(catalog, scene_name)
	if not event_occurred.is_connected(_track_quest_event):
		event_occurred.connect(_track_quest_event)
	ai.configure(self, world, scene_name)

## Settled source target, not an animated transform. Stored save fields stay unchanged.
func card_target_position_3d(card_id: int) -> Vector3:
	if not cards.has(card_id):
		return Vector3.ZERO
	var card = cards[card_id]
	var stack = stacks.get(card.stack_id)
	if stack == null or not stack.card_ids.has(card_id):
		return Vector3(card.position.x, 0, card.position.y)
	var index: int = stack.card_ids.find(card_id)
	var settings: Dictionary = catalog.settings("CardSettings")
	# Scene settings win; the catalog fallback keeps sceneless model fixtures usable.
	for scene in catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "CardManager":
				var guid: String = catalog.ref_guid(document.get("fields", {}).get("cardSettings", {}))
				if not guid.is_empty() and not catalog.fields(guid).is_empty():
					settings = catalog.fields(guid)
		break
	var step: Dictionary = settings.get("stackStep", {})
	return Vector3(stack.position.x, 0, stack.position.y) + Vector3(float(step.get("x", 0)), float(step.get("y", 0)), float(step.get("z", 0))) * index

func card_target_position(card_id: int) -> Vector2:
	var target := card_target_position_3d(card_id)
	return Vector2(target.x, target.z)

## Capture before any batch mutation changes stack indices. Missing IDs are omitted.
func capture_card_targets(ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in ids:
		if cards.has(id):
			result[id] = card_target_position(id)
	return result

func start_new_game() -> int:
	campaign.saved_scenes.clear()
	campaign.current_scene = scene_name
	ai.reset()
	world.reset()
	equipment.reset()
	combat.reset()
	cards.clear()
	stacks.clear()
	discovered_recipes.clear()
	collection.reset()
	vendor_payments.clear()
	day = 1
	elapsed = 0.0
	phase = "playing"
	paused = false
	speed = 1.0
	_next_id = 1
	quest_tracker.start_new_game(self)
	var defaults: Dictionary = campaign._defaults(scene_name)
	var center: Dictionary = defaults.get("defaultSpawnPosition", {})
	var position := Vector2(float(center.get("x", 0)), float(center.get("z", 0)))
	var radius := float(defaults.get("defaultSpawnRadius", 1))
	var first_id := -1
	for reference in defaults.get("defaultSpawnCards", []):
		# Retain the existing sphere rejection sampler and its RNG draw order.
		var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		while offset.length_squared() > 1:
			offset = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var spawned: int = spawn_card(catalog.ref_guid(reference), position + Vector2(offset.x, offset.z) * radius, -1, {"refuse_attach": catalog.get_definition(catalog.ref_guid(reference)).get("script_class", "") != "PackDefinition"})
		if first_id < 0:
			first_id = spawned
	return first_id

func spawn_card(guid: String, position: Vector2 = Vector2.ZERO, target_stack: int = -1, options: Dictionary = {}) -> int:
	var definition: Dictionary = catalog.get_definition(guid)
	if definition.is_empty() or _selecting_spawn:
		return -1
	var is_pack: bool = definition.get("script_class", "") == "PackDefinition"
	if not is_pack:
		collection.mark_card(guid)
	# CreateCardInstance rejects aggressive definitions before instance allocation.
	# Packs use CreatePackInstance, a separate source factory without this gate.
	if not is_pack and friendly_mode and definition.fields.get("isAggressive", false):
		return -1
	var direct_target: bool = target_stack >= 0
	var card = CardModel.new(_next_id, guid, catalog.fields(guid))
	_next_id += 1
	card.position = position
	cards[card.id] = card
	if is_pack:
		card.uses_left = catalog.fields(guid).get("slots", []).size()
	if not stacks.has(target_stack):
		var stack = StackModel.new(_next_id)
		_next_id += 1
		stack.position = position
		stacks[stack.id] = stack
		target_stack = stack.id
	card.stack_id = target_stack
	stacks[target_stack].card_ids.append(card.id)
	if not direct_target and not options.get("refuse_attach", false) and spawn_target_selector.is_valid():
		var ignored: int = int(options.get("ignored_stack_id", -1))
		spawn_query_height = float(options.get("height", 0.0))
		_selecting_spawn = true
		var selected: Variant = spawn_target_selector.call(card.id, ignored)
		_selecting_spawn = false
		spawn_query_height = 0.0
		# The selector only supplies geometry. Recheck live membership and rules.
		if selected is int and selected != ignored and cards.has(card.id) and stacks.has(selected):
			move_to_stack(card.id, selected)
	if not direct_target and spawn_layout_resolver.is_valid():
		spawn_layout_resolver.call()
	# Auto-deposit may already have consumed the card. Retain its instance ID and
	# definition metadata: source emits created after Initialize's attachment too.
	# Source CreatePackInstance does not publish card-created or stats events.
	if not is_pack:
		_notify_stats_changed()
		event_occurred.emit("card_created", {"card_id": card.id, "base_definition_guid": card.base_definition_guid})
	changed.emit()
	return card.id

func _remove_card(id: int) -> void:
	if not cards.has(id):
		return
	equipment.remove_card_state(id)
	combat.remove_combatant(id, false)
	var stack = stacks.get(cards[id].stack_id)
	if stack != null:
		stack.card_ids.erase(id)
		if stack.card_ids.is_empty():
			stacks.erase(stack.id)
	cards.erase(id)

## Kill differs from sale/crafting destruction; fully consumed food and packs also Kill.
## Source Kill draws one loot entry only for Character/Mob categories.
func kill_card(id: int) -> bool:
	if not cards.has(id):
		return false
	var card = cards[id]
	# Preserve the individual pose before cleanup/notifications can change membership.
	var death_position := card_target_position(id)
	var fields: Dictionary = catalog.fields(card.definition_guid)
	# Source notifies before loot, equipment cleanup and removal.
	event_occurred.emit("card_killed", {"card_id": id, "definition_guid": card.definition_guid})
	equipment.unequip_all(id)
	combat.remove_combatant(id, false)
	fields = catalog.fields(card.definition_guid)
	var category: int = int(fields.get("category", 0))
	if category == 2 or category == 9:
		spawn_card(_roll_loot(fields.get("loot", [])), death_position)
	var stack = stacks.get(card.stack_id)
	_remove_card(id)
	if stack != null:
		_validate_craft(stack)
	changed.emit()
	return true

func _roll_loot(entries: Array) -> String:
	# Unlike pack weights, loot ignores nonpositive weights and does not clamp.
	# A positive-weight entry with a null Card still occupies its probability.
	var total: int = 0
	for entry in entries:
		if entry is Dictionary:
			total += maxi(0, int(entry.get("Weight", 0)))
	if total <= 0:
		return ""
	var roll: int = rng.randi_range(0, total - 1)
	for entry in entries:
		if not entry is Dictionary:
			continue
		var weight: int = int(entry.get("Weight", 0))
		if weight <= 0:
			continue
		if roll < weight:
			return catalog.ref_guid(entry.get("Card", {}))
		roll -= weight
	return ""

func _weighted(entries: Array, minimum_one: bool) -> String:
	var total: int = 0
	for entry in entries:
		if not catalog.ref_guid(entry.get("Card", {})).is_empty():
			total += maxi(1 if minimum_one else 0, int(entry.get("Weight", 1)))
	if total <= 0:
		return ""
	var roll: int = rng.randi_range(0, total - 1)
	for entry in entries:
		var guid: String = catalog.ref_guid(entry.get("Card", {}))
		if guid.is_empty():
			continue
		roll -= maxi(1 if minimum_one else 0, int(entry.get("Weight", 1)))
		if roll < 0:
			return guid
	return ""

func open_pack(id: int) -> int:
	if phase != "playing" or not cards.has(id):
		return -1
	var card = cards[id]
	var definition: Dictionary = catalog.get_definition(card.definition_guid)
	if definition.get("script_class", "") != "PackDefinition":
		return -1
	var slots: Array = definition.fields.get("slots", [])
	var index: int = slots.size() - card.uses_left
	if index < 0 or index >= slots.size():
		return -1
	var slot: Dictionary = slots[index]
	var output: String = ""
	var recipes: Array = slot.get("PossibleRecipes", [])
	if not recipes.is_empty() and rng.randf() < float(slot.get("RecipeChance", 0.1)):
		var undiscovered: Array = []
		for reference in recipes:
			var guid: String = catalog.ref_guid(reference)
			var recipe_id: String = str(catalog.fields(guid).get("id", ""))
			if not recipe_id.is_empty() and not discovered_recipes.has(recipe_id):
				undiscovered.append(guid)
		if not undiscovered.is_empty():
			var recipe_guid: String = undiscovered[rng.randi_range(0, undiscovered.size() - 1)]
			var recipe: Dictionary = catalog.fields(recipe_guid)
			_discover_recipe(str(recipe.id))
			output = "Recipe:" + str(recipe.id)
			catalog.definitions[output] = {"guid": output, "script_class": "CardDefinition", "fields": {"id": output, "displayName": "Recipe: " + str(catalog.fields(catalog.ref_guid(recipe.get("resultingCard", {}))).get("displayName", "???")), "category": 8, "isSellable": true, "sellPrice": 1, "recipe_guid": recipe_guid}}
	if output.is_empty():
		output = _weighted(slot.get("Entries", []), true)
	var spawned: int = spawn_card(output, card.position, -1, {"height": 0.1})
	card.uses_left -= 1
	if card.uses_left <= 0:
		kill_card(id)
	event_occurred.emit("pack_opened", {"card_id": spawned, "slot": index})
	changed.emit()
	return spawned

func can_stack(bottom_guid: String, top_guid: String) -> bool:
	if catalog.get_definition(bottom_guid).is_empty() or catalog.get_definition(top_guid).is_empty():
		return false
	var rules: Array = catalog.stacking_rules()
	var bottom: int = int(catalog.fields(bottom_guid).get("category", 0))
	var top: int = int(catalog.fields(top_guid).get("category", 0))
	if bottom < 0 or bottom >= 12 or top < 0 or top >= 12:
		return false
	var index: int = bottom * 12 + top
	if index >= rules.size():
		return false
	return int(rules[index]) == 1 or (int(rules[index]) == 2 and bottom_guid == top_guid)

## Pure candidate filter. Source array naming is counterintuitive: TopCard is
## first, BottomCard is last. The lifted card is the first matrix argument.
## Equipment/combat terminal drop actions are separate, before regular stacking.
func can_move_to_stack(card_id: int, target_id: int, original_crafting_stack_id: int = -1) -> bool:
	if not cards.has(card_id) or not stacks.has(target_id) or not stacks.has(cards[card_id].stack_id):
		return false
	var card = cards[card_id]
	var source = stacks[card.stack_id]
	var target = stacks[target_id]
	if source == target or target.card_ids.is_empty() or card_id not in source.card_ids:
		return false
	if not can_stack(card.definition_guid, cards[target.card_ids.back()].definition_guid):
		return false
	if not target.recipe_guid.is_empty() and target_id != original_crafting_stack_id:
		var recipe: Dictionary = catalog.fields(target.recipe_guid)
		if not recipe.get("allowExcessIngredients", false):
			return false
		# CanJoinActiveCraft checks only the incoming effective definition.
		for ingredient in recipe.get("requiredIngredients", []):
			if catalog.ref_guid(ingredient.card) == card.definition_guid:
				return true
		return false
	return true

func move_to_stack(card_id: int, target_id: int, original_crafting_stack_id: int = -1) -> bool:
	if not can_move_to_stack(card_id, target_id, original_crafting_stack_id):
		return false
	var source = stacks[cards[card_id].stack_id]
	var target = stacks[target_id]
	var moving: Array = source.card_ids.slice(source.card_ids.find(card_id))
	if target_id == original_crafting_stack_id:
		target.paused = false
	elif moving.size() == source.card_ids.size():
		source.cancel_craft()
	# MergeWith invokes only the last target card's IOnStackable before append.
	# A full chest still handles a valid currency drop and leaves it untouched.
	var last_id: int = target.card_ids.back()
	if world._is_chest(last_id) and not world.currency_guid.is_empty() and cards[moving.front()].base_definition_guid == world.currency_guid:
		if moving.size() != source.card_ids.size():
			var detached_id: int = split_stack(card_id, card_target_position(card_id))
			source = stacks[detached_id]
		world.deposit_stack(last_id, source.id)
		_check_recipe(target)
		changed.emit()
		return true
	for moving_id in moving:
		source.card_ids.erase(moving_id)
		target.card_ids.append(moving_id)
		cards[moving_id].stack_id = target_id
		cards[moving_id].position = target.position
	_validate_craft(source)
	if source.card_ids.is_empty():
		stacks.erase(source.id)
	_check_recipe(target)
	changed.emit()
	return true

func split_stack(card_id: int, position: Vector2) -> int:
	if not cards.has(card_id) or not stacks.has(cards[card_id].stack_id):
		return -1
	var source = stacks[cards[card_id].stack_id]
	var moving: Array = source.card_ids.slice(source.card_ids.find(card_id))
	var target = StackModel.new(_next_id)
	_next_id += 1
	target.position = position
	stacks[target.id] = target
	for id in moving:
		source.card_ids.erase(id)
		target.card_ids.append(id)
		cards[id].stack_id = target.id
		cards[id].position = position
	_validate_craft(source)
	if source.card_ids.is_empty():
		stacks.erase(source.id)
	_check_recipe(target)
	changed.emit()
	return target.id

func matches_recipe(stack, recipe: Dictionary) -> bool:
	var composition: Dictionary = {}
	for id in stack.card_ids:
		var guid: String = cards[id].base_definition_guid
		composition[guid] = int(composition.get(guid, 0)) + 1
	var required: Dictionary = {}
	for ingredient in recipe.get("requiredIngredients", []):
		var guid: String = catalog.ref_guid(ingredient.card)
		required[guid] = true
		var count: int = int(composition.get(guid, 0))
		if recipe.get("allowExcessIngredients", false) or int(catalog.fields(guid).get("category", 0)) == 1:
			if count < int(ingredient.count):
				return false
		elif count != int(ingredient.count):
			return false
	if required.is_empty():
		return false
	if not recipe.get("allowExcessIngredients", false):
		for guid in composition:
			if not required.has(guid):
				return false
	return true

func _validate_craft(stack) -> void:
	if not stack.recipe_guid.is_empty() and not matches_recipe(stack, catalog.fields(stack.recipe_guid)):
		stack.cancel_craft()

func _check_recipe(stack) -> void:
	if not stack.recipe_guid.is_empty():
		return
	var matches: Array = []
	var total: float = 0.0
	for entry in catalog.data.get("recipes", []):
		# Special actions share selection and timing, but execute their own rules.
		if entry.get("script_class", "") not in ["RecipeDefinition", "TravelRecipe"] and not SpecialRecipes.supports(str(entry.get("script_class", ""))):
			continue
		if matches_recipe(stack, entry.fields):
			matches.append(entry)
			total += maxf(0, float(entry.fields.get("randomWeight", 1)))
	if matches.is_empty():
		return
	var chosen: Dictionary = matches.back()
	if total <= 0:
		chosen = matches[rng.randi_range(0, matches.size() - 1)]
	else:
		var roll: float = rng.randf() * total
		for entry in matches:
			roll -= maxf(0, float(entry.fields.get("randomWeight", 1)))
			if roll <= 0:
				chosen = entry
				break
	stack.recipe_guid = str(chosen.guid)
	stack.progress = 0
	_discover_recipe(str(chosen.fields.id))

func tick(delta: float) -> void:
	if delta <= 0:
		return
	# Source real-time combat travel/return continues while scaled gameplay pauses.
	if paused or phase != "playing":
		combat.tick(0.0, delta)
		return
	var tick_scene: String = scene_name
	var step: float = delta * speed
	ai.tick(step)
	combat.tick(step, delta)
	for stack in stacks.values().duplicate():
		if not stacks.has(stack.id) or stacks[stack.id] != stack:
			continue
		if stack.recipe_guid.is_empty() or stack.paused:
			continue
		stack.progress += step
		if stack.progress >= float(catalog.fields(stack.recipe_guid).get("craftingDuration", 5)):
			_complete_recipe(stack)
			if scene_name != tick_scene:
				return # Never advance old-scene stacks or destination time after travel.
	elapsed += step
	if elapsed >= day_duration:
		# Automatic day-end pause is silent in TimeManager, unlike user cycling.
		paused = true
		phase = "feeding"
	changed.emit()

func _complete_recipe(stack) -> void:
	var entry: Dictionary = catalog.get_definition(stack.recipe_guid)
	var recipe: Dictionary = entry.get("fields", {})
	if entry.get("script_class", "") == "TravelRecipe":
		var result: Dictionary = campaign.travel(stack.id, stack.recipe_guid)
		if not result.ok:
			stack.cancel_craft()
			event_occurred.emit("travel_failed", {"error": result.error})
		return
	var repeatable: bool = bool(recipe.get("isContinuous", false))
	for ingredient in recipe.get("requiredIngredients", []):
		if int(ingredient.get("consumptionMode", 0)) != 1:
			repeatable = true
	var output: String = catalog.ref_guid(recipe.get("resultingCard", {}))
	if SpecialRecipes.supports(str(entry.get("script_class", ""))):
		SpecialRecipes.execute(self, stack, entry)
	elif entry.get("script_class", "RecipeDefinition") == "RecipeDefinition":
		SpecialRecipes.consume(self, stack, recipe)
		# Spawn excludes the processing stack, as in the source.
		var spawned: int = spawn_card(output, stack.position, -1, {"ignored_stack_id": stack.id})
		if not catalog.get_definition(output).is_empty():
			event_occurred.emit("crafted", {"card_id": spawned, "definition_guid": output})
	else:
		# Never interpret unsupported Travel as ordinary crafting, even if forced.
		stack.cancel_craft()
		return
	stack.cancel_craft()
	_notify_stats_changed()
	# Source checks the declared result, NOT a random exploration loot result.
	var category: int = int(catalog.fields(output).get("category", 0))
	if repeatable and category != 2 and category != 9 and stacks.has(stack.id):
		_check_recipe(stack)

## Source AllCards is registered board stacks plus combatants, never attached gear.
func world_cards() -> Array:
	var result: Array = []
	for card in cards.values():
		if not equipment.owners.has(card.id):
			result.append(card)
	return result

func stats() -> Dictionary:
	var result := {"currency": 0, "nutrition": 0, "characters": 0, "cards_owned": 0, "card_limit": int(catalog.settings("CardSettings").get("baseCardLimit", 24))}
	for card in world_cards():
		var definition: Dictionary = catalog.get_definition(card.definition_guid)
		var fields: Dictionary = definition.fields
		var category: int = int(fields.get("category", 0))
		if category == 7:
			result.currency += 1
		elif definition.get("script_class", "") != "PackDefinition":
			result.cards_owned += 1
		result.currency += card.stored_coins
		if category == 3:
			result.nutrition += card.nutrition
		if category == 2:
			result.characters += 1
		result.card_limit += int(fields.get("boostAmount", 0))
	result["nutrition_need"] = result.characters * int(catalog.settings("CardSettings").get("hungerPerCharacter", 2))
	result["excess"] = maxi(0, result.cards_owned - result.card_limit)
	return result

func sell_card(id: int) -> bool:
	return _sell_cards([id])

## Validate and publish the entire transaction before deleting any sold card.
func _sell_cards(ids: Array) -> bool:
	if ids.is_empty():
		return false
	var coin: String = world.currency_guid
	# Legacy headless fixtures without scene data have no TradeManager to resolve.
	var fixture_without_scenes: bool = catalog.data.get("scenes", []).is_empty()
	if coin.is_empty() and fixture_without_scenes:
		coin = catalog.find_by_name("Coin")
	if coin.is_empty() or catalog.get_definition(coin).is_empty() or int(catalog.fields(coin).get("category", -1)) != 7:
		return false
	var base_guids: Array = []
	var total_price: int = 0
	for id in ids:
		if not cards.has(id) or equipment.owners.has(id) or combat.membership.has(id):
			return false
		var card = cards[id]
		var fields: Dictionary = catalog.fields(card.definition_guid)
		if not fields.get("isSellable", true) or card.stored_coins > 0:
			return false
		base_guids.append(card.base_definition_guid)
		total_price += int(fields.get("sellPrice", 1))
	var resolved: Variant = preload("res://scripts/model/scene_spawn.gd").buyer_position(catalog, scene_name, board_bounds, board_top_margin)
	if not resolved is Vector2 and not fixture_without_scenes:
		return false
	var position: Vector2 = resolved if resolved is Vector2 else cards[ids[0]].position
	event_occurred.emit("cards_sold", {"base_definition_guids": base_guids})
	for id in ids:
		var stack = stacks.get(cards[id].stack_id)
		_remove_card(id)
		if stack != null:
			_validate_craft(stack)
	for i in range(total_price):
		spawn_card(coin, position)
	_notify_stats_changed()
	if phase == "selling" and stats().excess <= 0:
		phase = "ready"
		world.finish_day(day, friendly_mode, board_bounds, board_top_margin)
	changed.emit()
	return true

func buy_pack(guid: String) -> int:
	var definition: Dictionary = catalog.get_definition(guid)
	if definition.get("script_class", "") != "PackDefinition" or completed_quests < int(definition.fields.get("minQuests", 0)):
		return -1
	var price: int = maxi(0, int(definition.fields.get("buyPrice", 3)) - int(vendor_payments.get(guid, 0)))
	if stats().currency < price:
		return -1
	var stats_changed: bool = price > 0
	for card in cards.values().duplicate():
		if price <= 0:
			break
		if int(catalog.fields(card.definition_guid).get("category", 0)) == 7:
			_remove_card(card.id)
			price -= 1
		else:
			var amount: int = mini(price, card.stored_coins)
			card.stored_coins -= amount
			price -= amount
	vendor_payments[guid] = 0
	var spawn: Variant = preload("res://scripts/model/scene_spawn.gd").vendor_position(catalog, scene_name, guid, board_bounds, board_top_margin)
	var purchased: int = spawn_card(guid, spawn if spawn is Vector2 else Vector2.ZERO)
	if purchased >= 0:
		event_occurred.emit("pack_purchased", {"definition_guid": guid})
	if stats_changed:
		_notify_stats_changed()
	changed.emit()
	return purchased

func end_day() -> Dictionary:
	if phase != "playing" and phase != "feeding":
		return stats()
	phase = "feeding"
	paused = true
	var hunger: int = int(catalog.settings("CardSettings").get("hungerPerCharacter", 2))
	for character in cards.values().duplicate():
		if int(catalog.fields(character.definition_guid).get("category", 0)) != 2:
			continue
		var need: int = hunger
		while need > 0:
			var nearest = null
			var distance: float = INF
			for food in cards.values():
				if int(catalog.fields(food.definition_guid).get("category", 0)) == 3 and food.nutrition > 0:
					var candidate: float = card_target_position_3d(character.id).distance_squared_to(card_target_position_3d(food.id))
					if candidate < distance:
						distance = candidate
						nearest = food
			if nearest == null:
				kill_card(character.id)
				break
			_prepare_food_for_feeding(nearest, card_target_position(character.id))
			var eaten: int = mini(need, nearest.nutrition)
			nearest.nutrition -= eaten
			need -= eaten
			var maximum: int = int(equipment.stats(character.id).get("maxHealth", 15))
			character.health = mini(maximum, character.health + _round_to_even(float(maximum) * 0.5 * eaten / hunger))
			if nearest.nutrition <= 0:
				kill_card(nearest.id)
			_notify_stats_changed()
	for stack in stacks.values():
		_validate_craft(stack)
	var snapshot: Dictionary = stats()
	phase = "game_over" if snapshot.characters <= 0 else ("selling" if snapshot.excess > 0 else "ready")
	if phase == "ready":
		world.finish_day(day, friendly_mode, board_bounds, board_top_margin)
	changed.emit()
	return snapshot

func start_day() -> bool:
	if phase != "ready":
		return false
	day += 1
	elapsed = 0
	phase = "playing"
	# Source StartNewDay resets pace silently; it only publishes day-started.
	paused = false
	speed = 1.0
	event_occurred.emit("day_started", {"day": day})
	changed.emit()
	return true

func sell_stack(stack_id: int) -> bool:
	if not stacks.has(stack_id):
		return false
	return _sell_cards(stacks[stack_id].card_ids.duplicate())

## Source vendor supports installments. Validates the whole dropped stack first.
## Returns {accepted, paid, pack_id, terminal}; terminal means the dropped stack emptied.
func pay_vendor(pack_guid: String, stack_id: int) -> Dictionary:
	var rejected := {"accepted": false, "paid": int(vendor_payments.get(pack_guid, 0)), "pack_id": -1, "terminal": false}
	var definition: Dictionary = catalog.get_definition(pack_guid)
	if not stacks.has(stack_id) or definition.get("script_class", "") != "PackDefinition":
		return rejected
	if completed_quests < int(definition.fields.get("minQuests", 0)):
		return rejected
	var dropped_stack = stacks[stack_id]
	var ids: Array = dropped_stack.card_ids.duplicate()
	for id in ids:
		if not cards.has(id):
			return rejected
		if int(catalog.fields(cards[id].definition_guid).get("category", 0)) != 7 and not (world._is_chest(id) and cards[id].stored_coins > 0):
			return rejected
	var price: int = int(definition.fields.get("buyPrice", 3))
	var paid: int = int(vendor_payments.get(pack_guid, 0))
	var stats_changed := false
	# Source BottomCard is the LAST member, not the first array element.
	ids.reverse()
	for id in ids:
		if paid >= price:
			break
		var card = cards[id]
		if int(catalog.fields(card.definition_guid).get("category", 0)) == 7:
			# CardStack.DestroyCard stops crafting before removing a payment card.
			dropped_stack.cancel_craft()
			_remove_card(id)
			paid += 1
			stats_changed = true
		else:
			# ChestLogic.TryWithdrawCoin(false) refuses an unresolved currency.
			if catalog.get_definition(world.currency_guid).is_empty():
				break
			var amount: int = mini(price - paid, card.stored_coins)
			paid += amount
			card.stored_coins -= amount
			stats_changed = stats_changed or amount > 0
			# Chest remains BottomCard, so once empty it blocks earlier payment cards.
			break
	var pack_id: int = -1
	if paid >= price:
		var spawn: Variant = preload("res://scripts/model/scene_spawn.gd").vendor_position(catalog, scene_name, pack_guid, board_bounds, board_top_margin)
		pack_id = spawn_card(pack_guid, spawn if spawn is Vector2 else Vector2.ZERO)
		paid = 0
		vendor_payments[pack_guid] = 0
		event_occurred.emit("pack_purchased", {"definition_guid": pack_guid})
	vendor_payments[pack_guid] = paid
	if stats_changed:
		_notify_stats_changed()
	changed.emit()
	return {"accepted": true, "paid": paid, "pack_id": pack_id, "terminal": dropped_stack.card_ids.is_empty()}

## Unity Mathf.RoundToInt rounds exact half values to the nearest even integer.
func _round_to_even(value: float) -> int:
	var lower: int = int(floor(value))
	if value - float(lower) == 0.5:
		return lower if lower % 2 == 0 else lower + 1
	return int(round(value))

## Consume removes just the food, never the cards above it, and stops its old craft.
func _prepare_food_for_feeding(food, destination: Vector2) -> void:
	var source = stacks.get(food.stack_id)
	if source != null and source.card_ids.size() > 1:
		source.cancel_craft()
		source.card_ids.erase(food.id)
		var separate = StackModel.new(_next_id)
		_next_id += 1
		separate.card_ids.append(food.id)
		stacks[separate.id] = separate
		food.stack_id = separate.id
	food.position = destination
	if stacks.has(food.stack_id):
		stacks[food.stack_id].position = destination

## Internal connection is installed once by configure, before UI subscribers.
func _track_quest_event(kind: String, payload: Dictionary) -> void:
	quest_tracker.process_event(kind, payload, self)

func _notify_stats_changed() -> void:
	event_occurred.emit("stats_changed", {})

func _discover_recipe(recipe_id: String) -> void:
	if recipe_id.is_empty() or discovered_recipes.has(recipe_id):
		return
	discovered_recipes[recipe_id] = true
	event_occurred.emit("recipe_discovered", {"recipe_id": recipe_id})

func time_pace() -> int:
	return 0 if paused else (2 if speed == 2.0 else 1)

## Public UI controls. Only source-supported Normal/Fast speeds are accepted.
func set_speed(value: float) -> void:
	if value != 1.0 and value != 2.0:
		return
	var previous: int = time_pace()
	speed = value
	paused = false
	if previous != time_pace():
		event_occurred.emit("time_pace_changed", {"pace": time_pace()})
	changed.emit()

func set_paused(value: bool) -> void:
	var previous: int = time_pace()
	paused = value
	if previous != time_pace():
		event_occurred.emit("time_pace_changed", {"pace": time_pace()})
	changed.emit()

## Matches TimeManager.CycleTimePace: Paused -> Normal -> Fast -> Paused.
func cycle_time_pace() -> void:
	match time_pace():
		0: set_speed(1.0)
		1: set_speed(2.0)
		2: set_paused(true)
