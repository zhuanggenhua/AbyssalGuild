extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks := 0
var failures := 0
var log_events: Array = []
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
func listen(session) -> void:
	session.event_occurred.connect(func(kind: String, payload: Dictionary):
		log_events.append({"kind": kind, "payload": payload.duplicate(true), "cards": session.cards.size(), "currency": session.stats().currency})
	)
func count_event(kind: String) -> int:
	var count := 0
	for event in log_events:
		if event.kind == kind:
			count += 1
	return count
func event_kinds() -> Array:
	var result: Array = []
	for event in log_events:
		result.append(event.kind)
	return result
func quest_id(catalog, name: String) -> String:
	for entry in catalog.data.quests:
		if entry.name == name:
			return str(entry.fields.id)
	return ""
func card_id(session, name: String) -> int:
	var guid: String = session.catalog.find_by_name(name)
	for id in session.cards:
		if session.cards[id].definition_guid == guid:
			return id
	return -1
func done(session, name: String) -> bool:
	return session.quest_tracker.completed_ids.has(quest_id(session.catalog, name))
func synthetic(session, fields_list: Array) -> void:
	var groups: Array = []
	for fields in fields_list:
		var id: String = str(fields.id)
		var entry := {"guid": id, "fields": fields}
		session.catalog.data.quests.append(entry)
		session.catalog.definitions[id] = entry
		groups.append({"guid": id})
	check(session.quest_tracker.configure(session.catalog, "", [{"GroupName": "Fixture", "Quests": groups}]), "synthetic source group config")
	session.quest_tracker.start_new_game(session)
func amount(session, id: String) -> int:
	for instance in session.quest_tracker.all_quests():
		if instance.id == id:
			return instance.current_amount
	return -1
func _initialize() -> void:
	test_introduction()
	test_source_events()
	test_recipe_cards_and_restore()
	print("Quest integration checks: %d; failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_introduction() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "load actual catalog")
	var session = Session.new()
	session.configure(catalog, 31)
	listen(session)
	var starter: int = session.start_new_game()
	check(session.quest_tracker.definitions.size() == 63, "Main quest group installed")
	check(session.completed_quests == 0, "new game no fabricated completions")
	check(log_events.is_empty(), "specialized pack spawn is not normal card-created")
	var beginning: String = catalog.find_by_name("Beginning", "packs")
	if beginning.is_empty():
		for entry in catalog.data.packs:
			if entry.name == "01_Pack_Beginning":
				beginning = entry.guid
	check(not beginning.is_empty(), "resolve actual Beginning pack")
	check(session.buy_pack(beginning) == -1, "vendor initially locked")
	for i in 3:
		session.open_pack(starter)
		check(not done(session, "introduction_01"), "partial pack not defeated")
	check(count_event("card_created") == 3, "one Obtain notification per drawn normal card")
	log_events.clear()
	session.open_pack(starter)
	check(done(session, "introduction_01"), "last starter slot completes Defeat quest")
	check(not session.cards.has(starter), "starter removed")
	check(event_kinds() == ["stats_changed", "card_created", "card_killed", "pack_opened"], "last opening source notification order")
	check(session.completed_quests == 1, "only starter completion")
	check(session.open_pack(starter) == -1 and session.completed_quests == 1, "repeat open cannot duplicate completion")
	var villager: int = card_id(session, "Villager")
	var bush: int = card_id(session, "Berry Bush")
	var rock: int = card_id(session, "Rock")
	check(villager >= 0 and bush >= 0 and rock >= 0, "actual starter contents")
	log_events.clear()
	check(session.move_to_stack(villager, session.cards[bush].stack_id), "stack villager on bush")
	check(done(session, "introduction_02"), "berry recipe discovered at craft start")
	check(count_event("recipe_discovered") == 1 and count_event("crafted") == 0, "discovery precedes completed harvest")
	session.tick(10.0)
	check(card_id(session, "Berry") >= 0, "real berry harvested")
	check(count_event("crafted") == 1 and count_event("recipe_discovered") == 1, "auto-repeat does not rediscover")
	session.split_stack(villager, Vector2(2, 2))
	check(session.move_to_stack(villager, session.cards[rock].stack_id), "stack villager on rock")
	var mining_stack = session.stacks[session.cards[rock].stack_id]
	var duration: float = float(catalog.fields(mining_stack.recipe_guid).get("craftingDuration", 5))
	session.tick(duration)
	check(done(session, "introduction_03"), "stone craft completes actual intro quest")
	check(session.completed_quests == 3, "Beginning threshold reached by actual actions")
	session.split_stack(villager, Vector2(4, 2))
	log_events.clear()
	check(session.sell_card(card_id(session, "Stone")), "sell actual harvested stone")
	check(done(session, "introduction_04"), "sale completes actual intro quest")
	check(count_event("cards_sold") == 1 and count_event("card_killed") == 0, "sale is not defeat")
	check(log_events[0].kind == "cards_sold" and log_events[0].currency == 0, "sale notification before removal or revenue")
	check(session.sell_card(card_id(session, "Wood")), "sell starter wood")
	check(session.sell_card(card_id(session, "Berry")), "sell harvested berry")
	check(session.stats().currency >= 3, "earn pack cost without injected coins")
	log_events.clear()
	var purchased: int = session.buy_pack(beginning)
	check(purchased >= 0, "buy unlocked Beginning pack with earned coins")
	check(done(session, "introduction_05"), "actual purchase completes intro quest")
	check(session.completed_quests == 5, "five real introduction completions")
	check(count_event("pack_purchased") == 1 and count_event("card_created") == 0, "pack purchase exactly once, no Obtain")
	check(event_kinds() == ["pack_purchased", "stats_changed"], "vendor purchase before final stats")
	var saved: Dictionary = session.quest_tracker.save_state()
	session.quest_tracker.restore_state(saved)
	check(session.completed_quests == 5, "restore count derived from IDs")
	var roots_before: int = session.quest_tracker.active_quests.size()
	session.quest_tracker.restore_state(saved)
	check(session.quest_tracker.active_quests.size() == roots_before, "restore does not duplicate roots")
	session.start_new_game()
	check(session.completed_quests == 0 and session.discovered_recipes.is_empty(), "new game resets tracker and discovery")
	# Disconnect external test listener to avoid retaining a RefCounted closure cycle.
	for connection in session.event_occurred.get_connections():
		if connection.callable.get_method() != "_track_quest_event":
			session.event_occurred.disconnect(connection.callable)

func test_source_events() -> void:
	var catalog = Catalog.new()
	catalog.load_file()
	var session = Session.new()
	session.configure(catalog)
	var wood: String = catalog.find_by_name("Wood")
	var berry: String = catalog.find_by_name("Berry")
	var coin: String = catalog.find_by_name("Coin")
	synthetic(session, [
		{"id": "sell-any", "type": 5, "targetAmount": 20},
		{"id": "sell-wood", "type": 5, "targetAmount": 20, "targetCard": {"guid": wood}},
		{"id": "obtain", "type": 1, "targetAmount": 20, "targetCard": {"guid": wood}},
		{"id": "defeat", "type": 3, "targetAmount": 20, "targetCard": {"guid": wood}},
		{"id": "food-death", "type": 3, "targetAmount": 20, "targetCard": {"guid": berry}},
		{"id": "pause", "type": 9, "targetAmount": 1, "targetPace": 0},
		{"id": "day", "type": 10, "targetAmount": 2}
	])
	listen(session)
	log_events.clear()
	var a: int = session.spawn_card(wood)
	var stack_id: int = session.cards[a].stack_id
	session.spawn_card(wood, Vector2.ZERO, stack_id)
	check(amount(session, "obtain") == 2, "two actual spawns give two Obtain")
	check(event_kinds() == ["stats_changed", "card_created", "stats_changed", "card_created"], "normal spawn stats before Obtain")
	log_events.clear()
	check(session.sell_stack(stack_id), "sell two-card stack")
	check(amount(session, "sell-any") == 2 and amount(session, "sell-wood") == 2, "whole sale counts quantities once")
	check(count_event("cards_sold") == 1 and count_event("card_killed") == 0, "one sale event, no death")
	check(amount(session, "defeat") == 0, "selling never Defeat")
	var dead: int = session.spawn_card(wood)
	log_events.clear()
	check(session.kill_card(dead), "explicit Kill")
	check(log_events[0].kind == "card_killed" and log_events[0].cards == session.cards.size() + 1, "Kill notified before removal")
	check(amount(session, "defeat") == 1, "Kill counts one")
	log_events.clear()
	session.set_paused(true)
	check(amount(session, "pause") == 1, "pause control completes source Time quest")
	session.set_paused(true)
	check(count_event("time_pace_changed") == 1, "unchanged pace does not re-emit")
	session.cycle_time_pace()
	session.cycle_time_pace()
	check(session.speed == 2 and not session.paused, "pace cycle normal then fast")
	session.set_speed(8)
	check(session.speed == 2, "reject unsupported speed")
	session.spawn_card(catalog.find_by_name("Villager"))
	var food: int = session.spawn_card(berry)
	session.cards[food].nutrition = 2
	log_events.clear()
	session.end_day()
	check(amount(session, "food-death") == 1, "fully consumed food uses Kill")
	check(count_event("stats_changed") == 1, "feeding publishes stats after consumption")
	check(session.start_day(), "surviving day advances")
	check(amount(session, "day") == 2, "day event carries absolute day")
	check(not session.paused and session.speed == 1, "new day silently resets pace")
	check(count_event("time_pace_changed") == 0, "day start does not counterfeit pace-change action")
	# Partial vendor payments do not count Buy; completion does, without Obtain.
	var pack: String = catalog.find_by_name("Beginning", "packs")
	if pack.is_empty():
		for entry in catalog.data.packs:
			if entry.name == "01_Pack_Beginning":
				pack = entry.guid
	catalog.definitions[pack].fields.minQuests = 0 # Focused transaction fixture.
	synthetic(session, [{"id": "buy-any", "type": 6, "targetAmount": 10}, {"id": "obtain-pack", "type": 1, "targetAmount": 10, "targetCard": {"guid": pack}}])
	log_events.clear()
	var payment: int = session.spawn_card(coin)
	var partial: Dictionary = session.pay_vendor(pack, session.cards[payment].stack_id)
	check(partial.accepted and partial.pack_id == -1, "partial installment accepted")
	check(amount(session, "buy-any") == 0, "partial installment not Buy")
	var payment2: int = session.spawn_card(coin)
	var payment_stack: int = session.cards[payment2].stack_id
	session.spawn_card(coin, Vector2.ZERO, payment_stack)
	log_events.clear()
	var complete: Dictionary = session.pay_vendor(pack, payment_stack)
	check(complete.pack_id >= 0 and amount(session, "buy-any") == 1, "full installment exactly one Buy")
	check(amount(session, "obtain-pack") == 0, "specialized pack creation excluded from Obtain")
	check(event_kinds() == ["pack_purchased", "stats_changed"], "installment completion order")
	for connection in session.event_occurred.get_connections():
		if connection.callable.get_method() != "_track_quest_event":
			session.event_occurred.disconnect(connection.callable)

func test_recipe_cards_and_restore() -> void:
	var catalog = Catalog.new()
	catalog.load_file()
	var session = Session.new()
	session.configure(catalog)
	var recipe: String = ""
	for entry in catalog.data.recipes:
		if entry.name == "Recipe_Berry":
			recipe = entry.guid
	synthetic(session, [{"id": "discover", "type": 2, "targetAmount": 2, "targetRecipe": {"guid": recipe}}])
	var pack: String = catalog.data.packs[0].guid
	catalog.definitions[pack].fields.slots = [{"PossibleRecipes": [{"guid": recipe}], "RecipeChance": 1.0, "Entries": []}]
	listen(session)
	var id: int = session.spawn_card(pack)
	log_events.clear()
	session.open_pack(id)
	check(amount(session, "discover") == 1, "recipe card marks discovery once")
	check(event_kinds() == ["recipe_discovered", "stats_changed", "card_created", "card_killed", "pack_opened"], "recipe card discovery before card spawn and exhausted pack death")
	var saved: Dictionary = session.quest_tracker.save_state()
	session.quest_tracker.restore_state(saved)
	check(amount(session, "discover") == 1 and session.completed_quests == 0, "restore retains active amount without replay")
	var events_before: int = log_events.size()
	session._discover_recipe(str(catalog.fields(recipe).id))
	check(log_events.size() == events_before, "duplicate discovery publishes no event")
	for connection in session.event_occurred.get_connections():
		if connection.callable.get_method() != "_track_quest_event":
			session.event_occurred.disconnect(connection.callable)
