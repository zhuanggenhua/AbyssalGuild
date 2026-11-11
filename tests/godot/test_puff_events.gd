extends SceneTree
## Event-boundary tests have no renderer, audio resources, or private assets.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Driver = preload("res://tests/godot/cycle_test_driver.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make():
	var c := Catalog.new()
	var cards: Array = []
	var fields := {
		"input": {"category": 4}, "output": {"category": 4}, "coin": {"category": 7, "displayName": "Coin"},
		"hero": {"category": 2, "faction": 1, "maxHealth": 10, "loot": [{"Card": {"guid": "output"}, "Weight": 1}]},
		"enemy": {"category": 9, "faction": 2, "isAggressive": true},
		"gear": {"category": 5, "equipmentSlot": 0}, "chest": {"category": 6, "capacity": 2},
		"cow": {"category": 9, "produceCard": {"guid": "food"}, "produceInterval": 10},
		"food": {"category": 3, "nutrition": 2}, "grower": {"category": 6}, "location": {"category": 10}}
	for guid in fields:
		cards.append({"guid": guid, "name": "Coin" if guid == "coin" else guid, "script_class": "ChestDefinition" if guid == "chest" else ("GrowerDefinition" if guid == "grower" else "CardDefinition"), "fields": fields[guid]})
	var recipes: Array = []
	for script in ["RecipeDefinition", "ExplorationRecipe", "GrowthRecipe", "ResearchRecipe", "TravelRecipe"]:
		recipes.append({"guid": script, "script_class": script, "fields": {"id": script, "resultingCard": {"guid": "output"}, "requiredIngredients": [{"card": {"guid": "input"}, "count": 2, "consumptionMode": 2}]}})
	recipes.append({"guid": "null", "script_class": "RecipeDefinition", "fields": {"id": "null", "requiredIngredients": [{"card": {"guid": "input"}, "count": 2, "consumptionMode": 2}]}})
	c.configure({"cards": cards, "recipes": recipes,
		"packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "buyPrice": 2, "slots": [{"Entries": [{"Card": {"guid": "output"}, "Weight": 1}]}]}}],
		"settings": [{"guid": "settings", "script_class": "CardSettings", "fields": {"baseCardLimit": 100, "hungerPerCharacter": 2, "stackStep": {"y": 0.02, "z": -0.3}}}],
		"referenced_prefabs": [{"guid": "ai", "documents": [{"script_class": "CardAI"}]}],
		"scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai"}}]}}, {"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}, {"script_class": "CameraController"}, {"script_class": "EncounterManager", "fields": {"allEncounters": [{"guid": "arrival"}]}}]}],
		"encounters": [{"guid": "arrival", "fields": {"id": "arrival", "type": 0, "dayValue": 2, "chance": 1.0, "count": 1, "oneTimeOnly": true, "maxCardsOnBoardLimit": 100, "cardToSpawn": {"guid": "output"}}}]})
	var s := Session.new()
	s.configure(c, 91)
	return s

func listen(s) -> Array:
	var result: Array = []
	var ref: WeakRef = weakref(s)
	s.event_occurred.connect(func(kind, payload):
		var live = ref.get_ref()
		var present: Array = live.cards.keys()
		var coins: Dictionary = {}
		for id in present: coins[id] = live.cards[id].stored_coins
		result.append({"kind": kind, "payload": payload.duplicate(true), "present": present, "coins": coins, "owners": live.equipment.owners.duplicate(), "combat": live.combat.membership.duplicate()})
	)
	return result

func kinds(events: Array) -> Array:
	return events.map(func(e): return e.kind)

func named(events: Array, kind: String) -> Array:
	return events.filter(func(e): return e.kind == kind)

func complete(s, recipe_guid: String, observe: bool = true) -> Array:
	var first: int = s.spawn_card("input", Vector2(2, 3))
	var stack = s.stacks[s.cards[first].stack_id]
	var last: int = s.spawn_card("input", Vector2.ZERO, stack.id)
	stack.recipe_guid = recipe_guid
	var events: Array = listen(s) if observe else []
	s._complete_recipe(stack)
	return [events, first, last]

func _init() -> void:
	_test_recipes()
	_test_chests()
	_test_production()
	_test_kills_and_cycle()
	_test_cosmetic_independence()
	_test_source_data()
	print("Puff events: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_recipes() -> void:
	for recipe in ["RecipeDefinition", "null"]:
		var s = make()
		var before: int = s.rng.state
		var result := complete(s, recipe)
		var events: Array = result[0]
		check(kinds(events).slice(0, 2) == ["puff_requested", "recipe_pop_requested"], recipe + " Puff then Pop are first completion events")
		check(named(events, "puff_requested").size() == 1 and named(events, "recipe_pop_requested").size() == 1, recipe + " one pair, not per ingredient")
		for index in range(2):
			check(events[index].present.has(result[1]) and events[index].present.has(result[2]), recipe + " both inputs still present at cue")
			check(events[index].payload.card_id == result[1] and events[index].payload.position == Vector3(2, 0, 3), recipe + " first/TopCard identity and preconsumption pose")
		check(events[1].payload.recipe_guid == recipe, recipe + " Pop identifies recipe")
		check(not s.cards.has(result[1]) and not s.cards.has(result[2]) and named(events, "card_killed").is_empty(), recipe + " ingredients Destroy without Kill puffs")
		check(named(events, "crafted").size() == (1 if recipe == "RecipeDefinition" else 0), recipe + " null output still cues without fabricated craft success")
		check(s.rng.state == before, recipe + " cues do not draw gameplay RNG")
	var s = make()
	s.cycle.pose_sampler = func(_id): return Vector3(7, 0.8, -9)
	var result := complete(s, "RecipeDefinition")
	check(result[0][0].payload.position == Vector3(7, 0.8, -9), "Recipe samples current source pose instead of settled root")
	for script in ["ExplorationRecipe", "GrowthRecipe", "ResearchRecipe", "TravelRecipe"]:
		result = complete(make(), script)
		check(named(result[0], "puff_requested").is_empty() and named(result[0], "recipe_pop_requested").is_empty(), script + " override never inherits base cues")

func _test_chests() -> void:
	var s = make()
	var chest: int = s.spawn_card("chest", Vector2(5, 6))
	var first: int = s.spawn_card("coin")
	var stack: int = s.cards[first].stack_id
	var second: int = s.spawn_card("coin", Vector2.ZERO, stack)
	var third: int = s.spawn_card("coin", Vector2.ZERO, stack)
	var events := listen(s)
	var result: Dictionary = s.world.deposit_stack(chest, stack)
	check(result.deposited == 2 and kinds(events) == ["puff_requested", "stats_changed"], "Deposit puffs once before final stats")
	check(events[0].coins[chest] == 0 and events[0].present.has(first) and events[0].present.has(second), "Deposit Puff precedes removal and increment")
	check(events[0].payload.card_id == chest and events[0].payload.position == Vector3(5, 0, 6), "Deposit puffs chest, not deposited coin")
	events.clear()
	var before: Dictionary = Codec.capture(s)
	result = s.world.deposit_stack(chest, stack)
	check(result.handled and result.deposited == 0 and kinds(events) == ["puff_requested"], "Full valid deposit puffs even with zero gameplay change")
	check(Codec.capture(s) == before and s.cards.has(third), "Full chest attempt preserves exact gameplay state")
	events.clear()
	var invalid: int = s.spawn_card("input")
	events.clear()
	check(not s.world.deposit_stack(chest, s.cards[invalid].stack_id).handled and events.is_empty(), "Invalid top card has no Puff")
	check(not s.world.deposit_stack(-1, stack).handled and events.is_empty(), "Missing chest has no Puff")
	var count: int = s.cards.size()
	check(s.world.withdraw_coin(chest), "Non-board withdrawal succeeds")
	check(kinds(events) == ["puff_requested", "stats_changed"] and events[0].coins[chest] == 1 and s.cards.size() == count, "Non-board Puff follows decrement, without spawning")
	events.clear()
	check(s.world.withdraw_coin(chest, true, Vector2(4, 2)), "Board withdrawal succeeds")
	check(kinds(events) == ["puff_requested", "stats_changed", "card_created", "stats_changed"], "Board withdrawal Puff precedes coin creation")
	check(events[0].coins[chest] == 0 and events[0].present.size() == count and s.cards.size() == count + 1, "Board withdrawal Puff observes decremented chest before new coin")
	events.clear()
	check(not s.world.withdraw_coin(chest) and events.is_empty(), "Empty withdrawal emits no Puff")
	s.cards[chest].stored_coins = 2
	result = s.pay_vendor("pack", s.cards[chest].stack_id)
	check(result.accepted and result.pack_id >= 0, "Vendor accepts chest payment")
	check(kinds(events) == ["puff_requested", "puff_requested", "pack_purchased", "stats_changed"], "Vendor non-board withdrawals each puff before purchase, one final stats")
	check(events[0].coins[chest] == 1 and events[1].coins[chest] == 0, "Vendor Puff observes each individual decrement")
	events.clear()
	s.cards[chest].stored_coins = 2
	check(s.buy_pack("pack") >= 0 and kinds(events) == ["puff_requested", "puff_requested", "pack_purchased", "stats_changed"], "Native global buy helper retains per-coin chest Puff")
	events.clear()
	var payment: int = s.spawn_card("coin")
	s.spawn_card("coin", Vector2.ZERO, s.cards[payment].stack_id)
	events.clear()
	check(s.pay_vendor("pack", s.cards[payment].stack_id).pack_id >= 0 and kinds(events) == ["pack_purchased", "stats_changed"], "Loose coin payment destroys coins without false Puffs")
	events.clear()
	s.cards[chest].stored_coins = 1
	s.world.currency_guid = ""
	check(not s.world.withdraw_coin(chest) and not s.world.deposit_stack(chest, stack).handled and events.is_empty(), "Unresolved currency rejects without Puff")
	# Sceneless native sale adapter, without trade geometry dependencies.
	s = make()
	s.catalog.data.scenes = []
	var sold: int = s.spawn_card("input")
	events = listen(s)
	check(s.sell_card(sold) and named(events, "puff_requested").is_empty() and named(events, "recipe_pop_requested").is_empty(), "Sale does not Puff or play base-recipe Pop")

func _test_production() -> void:
	var s = make()
	var cow: int = s.spawn_card("cow", Vector2(-3, 4))
	check(s.ai.agents.has(cow), "Synthetic AI resolved through source-shaped prefab mapping")
	s.ai.agents[cow].move_timer = 100
	s.world.production_timers[cow] = 0
	var events := listen(s)
	var before: int = s.rng.state
	s.ai.tick(0.01)
	check(kinds(events) == ["stats_changed", "card_created", "puff_requested"], "Live AI Puff follows produce creation")
	check(events[-1].payload.card_id == cow and events[-1].payload.position == Vector3(-3, 0, 4), "AI puffs producer pose rather than produce")
	check(events[-1].present.size() == 2 and s.rng.state == before, "AI cue occurs after spawn, without gameplay RNG")
	events.clear()
	s.world.production_timers[cow] = 0
	s.ai.produce_spawner = func(_guid, _position, _ignored): return -1
	s.ai.tick(0.01)
	check(kinds(events) == ["puff_requested"], "Source AI still puffs after a rejected factory result")
	events.clear()
	s.world.production_timers[cow] = 0
	s.combat.dragged[cow] = true
	s.ai.tick(0.01)
	check(events.is_empty(), "Blocked production emits no Puff")
	s.combat.dragged.erase(cow)
	s.world.production_timers[cow] = 0
	s.world.tick_production(0.01)
	check(kinds(events) == ["stats_changed", "card_created", "puff_requested"], "Explicit world production utility retains same event order")

func _test_kills_and_cycle() -> void:
	var s = make()
	var hero: int = s.spawn_card("hero", Vector2(2, -4))
	var gear: int = s.spawn_card("gear")
	check(s.equipment.equip(hero, gear), "Kill fixture attaches gear")
	var events := listen(s)
	check(s.kill_card(hero, Vector3(6, 0.3, 8)), "Kill succeeds")
	check(kinds(events) == ["card_killed", "stats_changed", "card_created", "puff_requested"], "Kill keeps early killed, loot-created, then one late Puff")
	check(events[0].present.has(hero) and events[0].owners.has(gear), "Early killed observes card and equipment before cleanup")
	check(events[-1].present.has(hero) and not events[-1].owners.has(gear) and s.cards.has(gear) and not s.cards.has(hero), "Puff observes cleaned gear and live dying card before removal")
	check(events[-1].payload.position == Vector3(6, 0.3, 8), "Kill captures supplied individual source pose")
	events.clear()
	check(not s.kill_card(hero) and events.is_empty(), "Repeated Kill has no duplicate Puff")
	var fighter: int = s.spawn_card("hero")
	var enemy: int = s.spawn_card("enemy")
	check(s.combat.start_combat([fighter], [enemy]) >= 0, "Combat cleanup fixture starts valid combat")
	events.clear()
	s.kill_card(fighter)
	check(events[0].kind == "card_killed" and events[0].combat.has(fighter), "Early killed still sees combat membership")
	check(events[-1].kind == "puff_requested" and not events[-1].combat.has(fighter) and events[-1].present.has(fighter), "Late Puff sees combat removed but dying card still valid")
	var pack: int = s.spawn_card("pack")
	events.clear()
	s.open_pack(pack)
	check(kinds(events) == ["stats_changed", "card_created", "card_killed", "puff_requested", "pack_opened"], "Exhausted pack Kill puffs before final opened event")
	s = make()
	hero = s.spawn_card("hero")
	var food: int = s.spawn_card("food")
	events = listen(s)
	Driver.finish(s)
	check(named(events, "puff_requested").size() == 1 and named(events, "puff_requested")[0].payload.card_id == food, "Depleted food puffs through Kill once")
	s = make()
	hero = s.spawn_card("hero")
	food = s.spawn_card("food")
	s.cards[food].nutrition = 4
	events = listen(s)
	Driver.finish(s)
	check(s.cards.has(food) and named(events, "puff_requested").is_empty(), "Partial food consumption has no Puff")
	s = make()
	hero = s.spawn_card("hero")
	events = listen(s)
	Driver.finish(s)
	check(s.phase == "game_over" and named(events, "puff_requested").size() == 1 and named(events, "puff_requested")[0].payload.card_id == hero, "Starvation Kill puffs once")
	s = make()
	s.day = 2
	hero = s.spawn_card("hero")
	s.spawn_card("food")
	s.end_day()
	while s.cycle.stage != "encounter_focus" and s.phase in ["feeding", "encounter"]:
		s.tick(s.cycle.remaining + 0.0001)
	check(s.cycle.stage == "encounter_focus", "Encounter reaches separate camera focus wait")
	events = listen(s)
	var spawned: int = s.cycle.focus_state().card_id
	s.tick(0.49)
	check(events.is_empty(), "Encounter Puff does not precede camera completion")
	s.tick(0.02)
	check(kinds(events) == ["puff_requested", "cycle_stage_changed"] and events[0].payload.card_id == spawned and s.cycle.stage == "encounter_wait", "Encounter puffs after focus and before its final realtime wait")

func _test_cosmetic_independence() -> void:
	var a = make()
	var b = make()
	var observed := listen(a)
	complete(a, "RecipeDefinition")
	complete(b, "RecipeDefinition", false)
	check(Codec.capture(a) == Codec.capture(b), "Listening or absence of visuals/audio leaves state and gameplay RNG identical")
	var id: int = a.spawn_card("input", Vector2(1, 2))
	var before: Dictionary = Codec.capture(a)
	seed(918)
	var expected: int = randi()
	seed(918)
	a.request_puff(id)
	check(randi() == expected and Codec.capture(a) == before, "Explicit Puff consumes neither global nor session RNG and mutates no state")
	check(observed[-1].payload.position == Vector3(1, 0, 2), "Missing visual adapter falls back to individual settled pose")
	var count: int = observed.size()
	a.request_puff(-1)
	check(observed.size() == count, "Missing reference safely suppresses cosmetic request")
	a.cycle.pose_sampler = func(_id): return Vector3(NAN, 0, 0)
	a.request_puff(id)
	check(observed[-1].payload.position == Vector3(1, 0, 2), "Invalid view pose falls back without affecting gameplay")

func _test_source_data() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SOURCE-DATA PUFF EVENT CHECKS SKIPPED: private catalog unavailable")
		return
	var c := Catalog.new()
	check(c.load_file() == OK, "Private source catalog loads")
	var s := Session.new()
	s.configure(c, 90)
	var recipe: Dictionary = c.get_definition(c.find_by_name("Recipe_Anvil", "recipes"))
	check(not recipe.is_empty() and recipe.script_class == "RecipeDefinition", "Actual Anvil is base recipe")
	var stack_id := -1
	for ingredient in recipe.fields.requiredIngredients:
		for _i in range(int(ingredient.count)):
			var id: int = s.spawn_card(c.ref_guid(ingredient.card), Vector2(2, 3), stack_id)
			stack_id = s.cards[id].stack_id
	var top: int = s.stacks[stack_id].card_ids.front()
	s.stacks[stack_id].recipe_guid = recipe.guid
	var events := listen(s)
	s._complete_recipe(s.stacks[stack_id])
	check(kinds(events).slice(0, 2) == ["puff_requested", "recipe_pop_requested"] and events[0].payload.card_id == top, "Actual Anvil cues before source top/input destruction")
	check(named(events, "puff_requested").size() == 1 and named(events, "crafted").size() == 1, "Actual multi-input Anvil has one Puff and one crafted")
	var chest: int = s.spawn_card(c.find_by_name("Card_Chest_WoodenChest"), Vector2(5, -2))
	s.cards[chest].stored_coins = int(c.fields(s.cards[chest].base_definition_guid).capacity)
	var coin: int = s.spawn_card(s.world.currency_guid)
	events.clear()
	check(s.world.deposit_stack(chest, s.cards[coin].stack_id).handled and kinds(events) == ["puff_requested"], "Actual full Wooden Chest still puffs")
	events.clear()
	check(s.world.withdraw_coin(chest) and kinds(events) == ["puff_requested", "stats_changed"], "Actual non-board withdrawal puffs")
	var cow: int = s.spawn_card(c.find_by_name("Cow"), Vector2(3, 4))
	check(s.ai.agents.has(cow), "Actual Cow AI registered")
	s.ai.agents[cow].move_timer = 100
	s.world.production_timers[cow] = 0
	events.clear()
	s.ai.tick(0.01)
	check(kinds(events) == ["stats_changed", "card_created", "puff_requested"] and events[-1].payload.card_id == cow, "Actual Cow creates Milk then puffs producer")
	for script in ["ExplorationRecipe", "GrowthRecipe", "ResearchRecipe", "TravelRecipe"]:
		s = Session.new()
		s.configure(c, 90)
		for entry in c.data.recipes:
			if entry.script_class == script:
				recipe = entry
				break
		stack_id = -1
		for ingredient in recipe.fields.requiredIngredients:
			for _i in range(int(ingredient.count)):
				var id: int = s.spawn_card(c.ref_guid(ingredient.card), Vector2.ZERO, stack_id)
				stack_id = s.cards[id].stack_id
		s.stacks[stack_id].recipe_guid = recipe.guid
		events = listen(s)
		s._complete_recipe(s.stacks[stack_id])
		check(named(events, "puff_requested").is_empty() and named(events, "recipe_pop_requested").is_empty(), "Actual " + script + " excludes base Puff and Pop")
		if script == "TravelRecipe":
			check(s.scene_name == "Island" and named(events, "travel_failed").is_empty(), "Successful actual travel also emits no base cues")
	print("Private Puff event hooks: PASS (base recipe, full chest, non-board withdrawal, Cow produce, all four overrides)")
