extends RefCounted
## Engine-independent gameplay slice. No nodes, imported art, or Unity code.
const CardModel = preload("res://scripts/model/card.gd")
const StackModel = preload("res://scripts/model/stack.gd")
const QuestTracker = preload("res://scripts/model/quest_tracker.gd")
signal changed
signal event_occurred(kind: String, payload: Dictionary)
var catalog
var cards: Dictionary = {}
var stacks: Dictionary = {}
var discovered_recipes: Dictionary = {}
var quest_tracker = QuestTracker.new()
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

func configure(source_catalog, random_seed: int = 1) -> void:
	catalog = source_catalog
	rng.seed = random_seed
	quest_tracker.configure(catalog, "Main")
	if not event_occurred.is_connected(_track_quest_event):
		event_occurred.connect(_track_quest_event)

func start_new_game() -> int:
	cards.clear()
	stacks.clear()
	discovered_recipes.clear()
	vendor_payments.clear()
	day = 1
	elapsed = 0.0
	phase = "playing"
	paused = false
	speed = 1.0
	_next_id = 1
	quest_tracker.start_new_game(self)
	var starter: String = catalog.find_by_name("Starter Pack", "packs")
	if starter.is_empty():
		for entry in catalog.data.get("packs", []):
			if "00_Pack_Starter" in entry.get("source_path", ""):
				starter = str(entry.guid)
	var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	while offset.length_squared() > 1:
		offset = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return spawn_card(starter, Vector2(-3.5, 0.6) + Vector2(offset.x, offset.z) * 1.2)

func spawn_card(guid: String, position: Vector2 = Vector2.ZERO, target_stack: int = -1) -> int:
	if catalog.get_definition(guid).is_empty():
		return -1
	var card = CardModel.new(_next_id, guid, catalog.fields(guid))
	_next_id += 1
	card.position = position
	cards[card.id] = card
	if catalog.get_definition(guid).get("script_class", "") == "PackDefinition":
		card.uses_left = catalog.fields(guid).get("slots", []).size()
	if not stacks.has(target_stack):
		var stack = StackModel.new(_next_id)
		_next_id += 1
		stack.position = position
		stacks[stack.id] = stack
		target_stack = stack.id
	card.stack_id = target_stack
	stacks[target_stack].card_ids.append(card.id)
	# Source CreatePackInstance does not publish card-created or stats events.
	if catalog.get_definition(guid).get("script_class", "") != "PackDefinition":
		_notify_stats_changed()
		event_occurred.emit("card_created", {"card_id": card.id, "base_definition_guid": card.base_definition_guid})
	changed.emit()
	return card.id

func _remove_card(id: int) -> void:
	if not cards.has(id):
		return
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
	var fields: Dictionary = catalog.fields(card.definition_guid)
	var category: int = int(fields.get("category", 0))
	# Source notifies before loot, equipment cleanup and removal.
	event_occurred.emit("card_killed", {"card_id": id, "definition_guid": card.definition_guid})
	if category == 2 or category == 9:
		spawn_card(_roll_loot(fields.get("loot", [])), card.position)
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
	var spawned: int = spawn_card(output, card.position)
	card.uses_left -= 1
	if card.uses_left <= 0:
		kill_card(id)
	event_occurred.emit("pack_opened", {"card_id": spawned, "slot": index})
	changed.emit()
	return spawned

func can_stack(bottom_guid: String, top_guid: String) -> bool:
	var rules: Array = catalog.stacking_rules()
	var bottom: int = int(catalog.fields(bottom_guid).get("category", 0))
	var top: int = int(catalog.fields(top_guid).get("category", 0))
	var index: int = bottom * 12 + top
	if index >= rules.size():
		return false
	return int(rules[index]) == 1 or (int(rules[index]) == 2 and bottom_guid == top_guid)

func move_to_stack(card_id: int, target_id: int) -> bool:
	if not cards.has(card_id) or not stacks.has(target_id):
		return false
	var card = cards[card_id]
	var source = stacks[card.stack_id]
	var target = stacks[target_id]
	if source == target or target.card_ids.is_empty():
		return false
	var moving: Array = source.card_ids.slice(source.card_ids.find(card_id))
	# Source uses incoming bottom vs target bottom, not target top.
	if not can_stack(card.definition_guid, cards[target.card_ids[0]].definition_guid):
		return false
	if not target.recipe_guid.is_empty():
		var recipe: Dictionary = catalog.fields(target.recipe_guid)
		if not recipe.get("allowExcessIngredients", false):
			return false
		for moving_id in moving:
			var allowed: bool = false
			for ingredient in recipe.get("requiredIngredients", []):
				if catalog.ref_guid(ingredient.card) == cards[moving_id].base_definition_guid:
					allowed = true
			if not allowed:
				return false
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
	if not cards.has(card_id):
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
		# Specialized recipe actions are intentionally not silently treated as standard crafts.
		if entry.get("script_class", "") != "RecipeDefinition":
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
	if paused or phase != "playing" or delta <= 0:
		return
	var step: float = delta * speed
	for stack in stacks.values().duplicate():
		if stack.recipe_guid.is_empty() or stack.paused:
			continue
		stack.progress += step
		if stack.progress >= float(catalog.fields(stack.recipe_guid).get("craftingDuration", 5)):
			_complete_recipe(stack)
	elapsed += step
	if elapsed >= day_duration:
		# Automatic day-end pause is silent in TimeManager, unlike user cycling.
		paused = true
		phase = "feeding"
	changed.emit()

func _complete_recipe(stack) -> void:
	var recipe: Dictionary = catalog.fields(stack.recipe_guid)
	var repeatable: bool = bool(recipe.get("isContinuous", false))
	for ingredient in recipe.get("requiredIngredients", []):
		var remaining: int = int(ingredient.count)
		var mode: int = int(ingredient.get("consumptionMode", 0))
		if mode != 1:
			repeatable = true
		for id in stack.card_ids.duplicate():
			if remaining <= 0:
				break
			if cards[id].base_definition_guid != catalog.ref_guid(ingredient.card):
				continue
			remaining -= 1
			if mode == 0:
				cards[id].uses_left -= 1
			if mode == 2 or (mode == 0 and cards[id].uses_left <= 0):
				_remove_card(id)
	var output: String = catalog.ref_guid(recipe.get("resultingCard", {}))
	# Spawn outside the processing stack, as source spawn excludes that stack.
	var spawned: int = spawn_card(output, stack.position)
	if spawned >= 0:
		event_occurred.emit("crafted", {"card_id": spawned, "definition_guid": output})
	stack.cancel_craft()
	_notify_stats_changed()
	var category: int = int(catalog.fields(output).get("category", 0))
	if repeatable and category != 2 and category != 9 and stacks.has(stack.id):
		_check_recipe(stack)

func stats() -> Dictionary:
	var result := {"currency": 0, "nutrition": 0, "characters": 0, "cards_owned": 0, "card_limit": int(catalog.settings("CardSettings").get("baseCardLimit", 24))}
	for card in cards.values():
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
	var coin: String = catalog.find_by_name("Coin")
	if coin.is_empty():
		return false
	var base_guids: Array = []
	var total_price: int = 0
	for id in ids:
		if not cards.has(id):
			return false
		var card = cards[id]
		var fields: Dictionary = catalog.fields(card.definition_guid)
		if not fields.get("isSellable", true) or card.stored_coins > 0:
			return false
		base_guids.append(card.base_definition_guid)
		total_price += int(fields.get("sellPrice", 1))
	var position: Vector2 = cards[ids[0]].position
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
	var purchased: int = spawn_card(guid)
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
					var candidate: float = character.position.distance_squared_to(food.position)
					if candidate < distance:
						distance = candidate
						nearest = food
			if nearest == null:
				kill_card(character.id)
				break
			_prepare_food_for_feeding(nearest, character.position)
			var eaten: int = mini(need, nearest.nutrition)
			nearest.nutrition -= eaten
			need -= eaten
			var maximum: int = int(catalog.fields(character.definition_guid).get("maxHealth", 15))
			character.health = mini(maximum, character.health + _round_to_even(float(maximum) * 0.5 * eaten / hunger))
			if nearest.nutrition <= 0:
				kill_card(nearest.id)
			_notify_stats_changed()
	for stack in stacks.values():
		_validate_craft(stack)
	var snapshot: Dictionary = stats()
	phase = "game_over" if snapshot.characters <= 0 else ("selling" if snapshot.excess > 0 else "ready")
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
## Returns {accepted, paid, pack_id}; an accepted partial payment is not a purchase.
func pay_vendor(pack_guid: String, stack_id: int) -> Dictionary:
	var rejected := {"accepted": false, "paid": int(vendor_payments.get(pack_guid, 0)), "pack_id": -1}
	var definition: Dictionary = catalog.get_definition(pack_guid)
	if not stacks.has(stack_id) or definition.get("script_class", "") != "PackDefinition":
		return rejected
	if completed_quests < int(definition.fields.get("minQuests", 0)):
		return rejected
	var ids: Array = stacks[stack_id].card_ids.duplicate()
	for id in ids:
		if int(catalog.fields(cards[id].definition_guid).get("category", 0)) != 7 and cards[id].stored_coins <= 0:
			return rejected
	var price: int = int(definition.fields.get("buyPrice", 3))
	var paid: int = int(vendor_payments.get(pack_guid, 0))
	var stats_changed := false
	for id in ids:
		if paid >= price:
			break
		var card = cards[id]
		if int(catalog.fields(card.definition_guid).get("category", 0)) == 7:
			_remove_card(id)
			paid += 1
			stats_changed = true
		else:
			var amount: int = mini(price - paid, card.stored_coins)
			paid += amount
			card.stored_coins -= amount
			stats_changed = stats_changed or amount > 0
			if paid < price:
				break
	var pack_id: int = -1
	if paid >= price:
		pack_id = spawn_card(pack_guid)
		paid = 0
		vendor_payments[pack_guid] = 0
		event_occurred.emit("pack_purchased", {"definition_guid": pack_guid})
	vendor_payments[pack_guid] = paid
	if stats_changed:
		_notify_stats_changed()
	changed.emit()
	return {"accepted": true, "paid": paid, "pack_id": pack_id}

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
