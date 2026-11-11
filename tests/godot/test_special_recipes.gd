extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
var checks: int = 0
var failures: int = 0
var events: Array = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func new_session():
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "source catalog loads")
	var session = Session.new()
	session.configure(catalog, 123)
	session.event_occurred.connect(func(kind, payload): events.append([kind, payload]))
	return session

func ingredient_stack(session, entry):
	var stack_id: int = -1
	for ingredient in entry.fields.requiredIngredients:
		for i in range(int(ingredient.count)):
			var id: int = session.spawn_card(session.catalog.ref_guid(ingredient.card), Vector2(3, 4), stack_id)
			stack_id = session.cards[id].stack_id
	return session.stacks[stack_id]

func count_event(kind: String) -> int:
	return events.filter(func(e): return e[0] == kind).size()

func _init() -> void:
	var source = new_session()
	var counts: Dictionary = {}
	for entry in source.catalog.data.recipes:
		var type: String = entry.script_class
		if not Special.supports(type):
			continue
		counts[type] = counts.get(type, 0) + 1
		var session = new_session()
		var stack = ingredient_stack(session, entry)
		check(session.matches_recipe(stack, entry.fields), "real ingredients match " + entry.name)
		var original: Array = stack.card_ids.duplicate()
		var before: int = session.cards.size()
		events.clear()
		check(Special.execute(session, stack, entry), "dispatch " + entry.name)
		check(count_event("crafted") == 0, "special never emits ordinary crafted")
		if type == "ExplorationRecipe":
			check(session.cards.size() == before + 1, "exploration spawns one loot")
			check(count_event("exploration_finished") == 1, "exploration event")
			check(stack.card_ids == original, "exploration keeps real inputs")
			check(entry.fields.craftingDuration == 60 and entry.fields.isContinuous == 1, "source exploration timing")
		elif type == "GrowthRecipe":
			check(session.cards.size() == before + 1, "growth adds one result, preserves seed")
			check(stack.card_ids.size() == 1, "grower remains alone")
			check(session.cards[original[1]].uses_left == 1, "seed Consume rule deliberately ignored")
			check(session.cards[original[1]].stack_id != stack.id, "seed separated")
			check(session.cards[original[1]].position.is_equal_approx(Vector2(3.9, 3.82)), "source member pose plus collider and margin displacement")
			check(count_event("exploration_finished") == 0, "growth no explore event")
		else:
			check(session.cards.size() == before + 1, "research produces one recipe card")
			check(session.discovered_recipes.size() == 1, "research marks result discovered")
			check(count_event("recipe_discovered") == 1, "research discovered event")
			check(events[-1][0] == "recipe_discovered", "research discovery follows spawn")
	check(counts == {"ExplorationRecipe": 5, "GrowthRecipe": 6, "ResearchRecipe": 1}, "all 12 source special recipes covered")
	var session = new_session()
	var grow: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Growth_Box_Berry", "recipes"))
	var stack = ingredient_stack(session, grow)
	var seed: int = stack.card_ids[1]
	var extra: int = session.spawn_card(session.catalog.find_by_name("Wood"), stack.position, stack.id)
	Special.execute(session, stack, grow)
	check(session.cards[extra].stack_id == session.cards[seed].stack_id, "growth splits all above seed")
	# Seed at bottom: source SplitAt returns null and does not move the grower.
	session = new_session()
	stack = ingredient_stack(session, grow)
	stack.card_ids.reverse()
	Special.execute(session, stack, grow)
	check(stack.card_ids.size() == 2, "bottom seed cannot split")
	# Grower Destroy makes the seed bottom before the split attempt.
	session = new_session()
	var destructive: Dictionary = grow.duplicate(true)
	destructive.fields.requiredIngredients[0].consumptionMode = 2
	stack = ingredient_stack(session, destructive)
	Special.execute(session, stack, destructive)
	check(stack.card_ids.size() == 1 and session.cards.size() == 2, "destroy grower only, seed survives")
	# No eligible results: inputs still consumed before candidate search.
	session = new_session()
	var research: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Research_Library", "recipes")).duplicate(true)
	for entry in session.catalog.data.recipes:
		session.discovered_recipes[str(entry.fields.id)] = true
	research.fields.requiredIngredients[1].consumptionMode = 2
	stack = ingredient_stack(session, research)
	events.clear()
	Special.execute(session, stack, research)
	check(session.cards.size() == 1, "empty research consumes specified inputs")
	check(count_event("recipe_discovered") == 0, "empty research emits no discovery")
	# Candidate filter excludes special/outputless/discovered, retaining source type rule.
	session = new_session()
	var candidates: Array = Special.research_candidates(session)
	check(not candidates.is_empty(), "real research candidates exist")
	for candidate in candidates:
		check(not Special.supports(candidate.script_class) and not session.catalog.ref_guid(candidate.fields.resultingCard).is_empty(), "eligible candidate " + candidate.name)
	session._discover_recipe(str(candidates[0].fields.id))
	check(Special.research_candidates(session).size() == candidates.size() - 1, "discovered result excluded")
	# Null/zero loot still applies consumption, but neither spawn nor explore event.
	var exploration: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Exploration_Fields", "recipes")).duplicate(true)
	stack = ingredient_stack(session, exploration)
	var area: int = stack.card_ids[0]
	session.catalog.fields(session.cards[area].definition_guid).loot = [{"Weight": 10, "Card": {"fileID": "0"}}]
	exploration.fields.requiredIngredients[1].consumptionMode = 2
	events.clear()
	Special.execute(session, stack, exploration)
	check(stack.card_ids.size() == 1 and stack.card_ids[0] == area, "null loot still consumes explorer")
	check(count_event("exploration_finished") == 0 and count_event("card_created") == 0, "null loot no false success")
	# Preserve the otherwise easy-to-miss double loot RNG advance.
	session = new_session()
	exploration = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Exploration_Fields", "recipes"))
	stack = ingredient_stack(session, exploration)
	var probe = new_session()
	probe.rng.state = session.rng.state
	var loot_table: Array = session.catalog.fields(session.cards[stack.card_ids[0]].definition_guid).loot
	probe._roll_loot(loot_table)
	var expected_loot: String = probe._roll_loot(loot_table)
	events.clear()
	Special.execute(session, stack, exploration)
	check(session.rng.state == probe.rng.state, "exploration advances RNG for predicate and actual loot")
	var created: Array = events.filter(func(e): return e[0] == "card_created")
	check(created.size() == 1 and created[0][1].base_definition_guid == expected_loot, "second roll chooses actual exploration output")
	check(events.find(created[0]) < events.find(events.filter(func(e): return e[0] == "exploration_finished")[0]), "explore event follows loot spawn")
	check(not Special.execute(session, stack, {"script_class": "TravelRecipe"}), "Travel explicitly unsupported")
	check(not Special.supports("RecipeDefinition"), "ordinary craft not intercepted")
	test_session_integration()
	print("Special recipes: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Real merge -> selection -> time -> action -> quest event, never direct execute.
func test_session_integration() -> void:
	var source = new_session()
	for entry in source.catalog.data.recipes:
		if not Special.supports(entry.script_class):
			continue
		var session = new_session()
		var quest_id: String = ""
		if entry.script_class == "ExplorationRecipe":
			var area_guid: String = session.catalog.ref_guid(entry.fields.requiredIngredients[0].card)
			for quest in session.catalog.data.quests:
				if int(quest.fields.type) == 8 and session.catalog.ref_guid(quest.fields.targetCard) == area_guid:
					quest_id = str(quest.fields.id)
					break
			check(not quest_id.is_empty(), "source Explore quest exists " + entry.name)
			# Legitimate save-state setup: restore the corresponding source quest active.
			session.quest_tracker.restore_state({"ActiveQuests": [{"QuestId": quest_id, "CurrentAmount": 0}]})
		var stack_id: int = -1
		var originals: Array = []
		events.clear()
		for ingredient in entry.fields.requiredIngredients:
			for i in range(int(ingredient.count)):
				var id: int = session.spawn_card(session.catalog.ref_guid(ingredient.card), Vector2(3, 4))
				originals.append(id)
				if stack_id < 0:
					stack_id = session.cards[id].stack_id
				else:
					check(session.move_to_stack(id, stack_id), "merge source inputs " + entry.name)
		var stack = session.stacks[stack_id]
		check(stack.recipe_guid == str(entry.guid), "actual selection " + entry.name)
		check(session.discovered_recipes.has(str(entry.fields.id)), "selection discovers actual special " + entry.name)
		check(count_event("recipe_discovered") == 1, "discover special exactly once at start")
		var before: int = session.cards.size()
		var duration: float = float(entry.fields.craftingDuration)
		events.clear()
		session.tick(duration / 2.0)
		check(is_equal_approx(stack.progress, duration / 2.0), "halfway timer")
		check(session.cards.size() == before and count_event("exploration_finished") == 0, "no early action")
		session.set_paused(true)
		session.tick(duration)
		check(is_equal_approx(stack.progress, duration / 2.0), "pause freezes special")
		session.set_paused(false)
		session.tick(duration / 2.0)
		check(session.cards.size() == before + 1, "timed completion creates one result " + entry.name)
		check(count_event("crafted") == 0, "no ordinary craft event after integrated special")
		check(count_event("stats_changed") >= 2, "spawn and completion publish stats")
		for id in originals:
			check(session.cards.has(id), "actual Keep inputs and special seed survive")
		check(stack.progress == 0, "completion resets progress")
		if entry.script_class == "GrowthRecipe":
			check(stack.recipe_guid.is_empty(), "split seed prevents repeat match")
			check(session.cards[originals[1]].stack_id != stack_id, "integrated seed split")
			check(session.cards[originals[1]].uses_left == 1, "integrated seed not consumed")
			var output: String = session.catalog.ref_guid(entry.fields.resultingCard)
			var matching: int = 0
			for card in session.cards.values():
				if card.definition_guid == output:
					matching += 1
			check(matching == 2, "original seed plus grown output")
		else:
			check(stack.recipe_guid == str(entry.guid), "continuous special repeats on same stack")
			if entry.script_class == "ExplorationRecipe":
				check(count_event("exploration_finished") == 1, "integrated exploration event")
				check(session.quest_tracker.completed_ids.has(quest_id), "actual Explore quest completed by gameplay")
			else:
				check(count_event("recipe_discovered") == 1 and session.discovered_recipes.size() == 2, "research discovers new result after own discovery")
				var recipe_cards: Array = session.cards.values().filter(func(c): return int(session.catalog.fields(c.definition_guid).get("category", 0)) == 8)
				check(recipe_cards.size() == 1, "one integrated recipe card")
				check(not str(session.catalog.fields(recipe_cards[0].definition_guid).description).is_empty(), "recipe card has source ingredient description")
	# Remove an ingredient halfway: real split cancels special without output.
	var session = new_session()
	var grow: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Growth_Box_Berry", "recipes"))
	var grower: int = session.spawn_card(session.catalog.ref_guid(grow.fields.requiredIngredients[0].card))
	var seed: int = session.spawn_card(session.catalog.ref_guid(grow.fields.resultingCard))
	var stack_id: int = session.cards[grower].stack_id
	check(session.move_to_stack(seed, stack_id), "start growth for cancellation")
	session.tick(10)
	session.split_stack(seed, Vector2(5, 5))
	check(session.stacks[stack_id].recipe_guid.is_empty(), "ingredient removal cancels growth")
	session.tick(60)
	check(session.cards.size() == 2, "cancelled growth does not produce")
	# All-researched real Library continues with no false output or discovery.
	session = new_session()
	var research: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Research_Library", "recipes"))
	var stack = ingredient_stack(session, research)
	for recipe in session.catalog.data.recipes:
		session.discovered_recipes[str(recipe.fields.id)] = true
	session._check_recipe(stack)
	events.clear()
	session.tick(60)
	check(session.cards.size() == 4 and count_event("recipe_discovered") == 0, "exhausted research no output/discovery")
	check(stack.recipe_guid == str(research.guid), "source exhausted continuous research repeats")
	# Invalid forced travel tasks cannot degrade into ordinary recipes.
	stack.recipe_guid = "unsupported-travel"
	session.crafting.activate(stack) # Explicit forced task for rejection coverage.
	session.catalog.definitions["unsupported-travel"] = {"script_class": "TravelRecipe", "fields": {"craftingDuration": 1, "requiredIngredients": research.fields.requiredIngredients, "resultingCard": grow.fields.resultingCard}}
	events.clear()
	session.tick(1)
	check(session.cards.size() == 4 and stack.recipe_guid.is_empty(), "Travel with invalid destinations is guarded")
	check(count_event("crafted") == 0, "Travel never emits fake craft")

	# Research completes a real Discover quest for its newly revealed recipe.
	session = new_session()
	var discover_quest: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("introduction_02", "quests"))
	var target_recipe: String = session.catalog.ref_guid(discover_quest.fields.targetRecipe)
	var target_id: String = str(session.catalog.fields(target_recipe).id)
	for recipe in session.catalog.data.recipes:
		if str(recipe.fields.id) != target_id:
			session.discovered_recipes[str(recipe.fields.id)] = true
	session.quest_tracker.restore_state({"ActiveQuests": [{"QuestId": discover_quest.fields.id, "CurrentAmount": 0}]})
	stack = ingredient_stack(session, research)
	session._check_recipe(stack)
	events.clear()
	session.tick(60)
	check(session.discovered_recipes.has(target_id), "integrated research selects last eligible source recipe")
	check(session.quest_tracker.completed_ids.has(str(discover_quest.fields.id)), "research event completes actual Discover quest")
	check(count_event("recipe_discovered") == 1, "one discovery event for research result")
	# Exploration producing a living loot does not disable its repeat timer.
	session = new_session()
	var explore: Dictionary = session.catalog.get_definition(session.catalog.find_by_name("Recipe_Exploration_Fields", "recipes"))
	stack = ingredient_stack(session, explore)
	var area_guid: String = session.cards[stack.card_ids[0]].definition_guid
	var villager: String = session.catalog.find_by_name("Villager")
	session.catalog.fields(area_guid).loot = [{"Weight": 1, "Card": {"guid": villager}}]
	session._check_recipe(stack)
	session.tick(60)
	check(stack.recipe_guid == str(explore.guid), "living exploration loot does not stop repeat")
	check(session.stats().characters == 2, "living loot spawned once")
