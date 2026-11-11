extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const World = preload("res://scripts/model/world_rules.gd")
var checks: int = 0
var failures: int = 0
var rolls: int = 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func roll_zero() -> float:
	rolls += 1
	return 0.0
func _init() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "real data loads")
	var session = Session.new()
	session.configure(catalog, 30)
	var world = World.new()
	world.configure(session)
	check(world.encounter_guids.size() == 3, "Main has only serialized encounters")
	check(catalog.get_definition(world.encounter_guids[1]).name == "Encounter_Weekly_Slime", "scene order differs from global asset order")
	check(catalog.fields(world.currency_guid).displayName == "Coin", "Main currency")
	world.configure(session, "Island")
	check(world.encounter_guids.is_empty(), "Island does not inherit Main encounters")
	check(catalog.fields(world.currency_guid).displayName == "Coral", "Island currency")
	world.configure(session)
	for type in range(4):
		var fields := {"type": type, "dayValue": 7, "maxDayValue": 9}
		check(World.matches_day(fields, 7), "all date types include day value")
		check(not World.matches_day(fields, 6), "all types reject earlier day")
	check(World.matches_day({"type": 1, "dayValue": 7}, 14), "recurring cycle")
	check(not World.matches_day({"type": 1, "dayValue": 7}, 0), "recurring excludes zero")
	check(not World.matches_day({"type": 1, "dayValue": 0}, 7), "invalid zero recurrence guarded")
	check(World.matches_day({"type": 2, "dayValue": 7, "maxDayValue": 9}, 9), "range max inclusive")
	check(not World.matches_day({"type": 2, "dayValue": 7, "maxDayValue": 9}, 10), "range max enforced")
	check(World.matches_day({"type": 3, "dayValue": 7}, 100), "minimum continues")
	rolls = 0
	check(world.select_encounter(7, false, roll_zero) == world.encounter_guids[1], "stable tie favors Slime")
	check(rolls == 2, "roll every eligible candidate before sorting")
	rolls = 0
	check(world.select_encounter(7, true, roll_zero).is_empty() and rolls == 0, "friendly rejects aggressive before RNG")
	var villager: String = world.encounter_guids[0]
	var event: Dictionary = world.finish_day(5, false, Rect2(-10, -10, 20, 20), 3)
	check(event.encounter_guid == villager and event.spawned.size() == 1, "day-five one-time villager")
	var position: Vector2 = session.cards[event.spawned[0]].position
	check(position.x >= -8 and position.x <= 8 and position.y >= -8 and position.y <= 6, "padded board and top margin")
	check(world.finish_day(5).is_empty(), "same day cannot execute twice")
	check(world.select_encounter(5).is_empty(), "one-time stable ID stored")
	check(world.completed_encounters.has(catalog.fields(villager).id), "completion uses encounter ID not GUID")
	world.finish_day(6)
	check(world.processed_days.has(6), "empty encounter day also guarded")
	var state: Dictionary = JSON.parse_string(JSON.stringify(world.export_state()))
	world.reset()
	check(world.restore_state(state) and world.finish_day(5).is_empty(), "roundtrip preserves guard and completion")
	check(not world.restore_state({"scene": "Island"}), "wrong scene state rejected")
	var unchanged: Dictionary = world.save_state()
	for bad in [
		{"scene": "Main", "completed_encounters": ["unknown"], "processed_days": []},
		{"scene": "Main", "completed_encounters": [catalog.fields(villager).id, catalog.fields(villager).id], "processed_days": []},
		{"scene": "Main", "completed_encounters": [], "processed_days": [5, 5]},
		{"scene": "Main", "completed_encounters": [], "processed_days": [0]},
		{"scene": "Main", "completed_encounters": [], "processed_days": [1.5]},
		{"scene": "Main", "completed_encounters": [], "processed_days": [INF]},
		{"scene": "Main", "completed_encounters": [], "processed_days": ["5"]}]:
		check(not world.stage_state(bad).ok and world.save_state() == unchanged, "invalid world stage leaves live state unchanged")
	# Fixtures preserve source field names, with explicit manager configuration.
	var definitions: Array = []
	var fixtures := {
		"coin": {"category": 7}, "other": {"category": 0},
		"chest": {"capacity": 2}, "pen": {"capacity": 2},
		"mob": {"category": 9, "faction": 2, "isAggressive": true, "attackRadius": 1.5, "aggroRadius": 5.0},
		"cow": {"category": 9, "produceCard": {"guid": "milk"}, "produceInterval": 10.0},
		"milk": {"category": 3}, "hero": {"category": 2, "faction": 1}
	}
	for guid in fixtures:
		definitions.append({"guid": guid, "script_class": "ChestDefinition" if guid == "chest" else ("EnclosureDefinition" if guid == "pen" else "CardDefinition"), "fields": fixtures[guid]})
	catalog.configure({"cards": definitions})
	session = Session.new()
	session.configure(catalog, 123)
	world.configure(session)
	world.currency_guid = "coin"
	var chest: int = session.spawn_card("chest")
	var c1: int = session.spawn_card("coin")
	var coin_stack: int = session.cards[c1].stack_id
	var other: int = session.spawn_card("other", Vector2.ZERO, coin_stack)
	session.stacks[coin_stack].card_ids = [other, c1]
	check(not world.deposit_stack(chest, coin_stack).handled, "noncurrency first/TopCard rejects entire drop")
	session.stacks[coin_stack].card_ids = [c1, other]
	var c2: int = session.spawn_card("coin", Vector2.ZERO, coin_stack)
	var c3: int = session.spawn_card("coin", Vector2.ZERO, coin_stack)
	session.stacks[coin_stack].recipe_guid = "fixture_craft"
	var deposit: Dictionary = world.deposit_stack(chest, coin_stack)
	check(session.stacks[coin_stack].recipe_guid.is_empty(), "deposit cancels affected crafting task")
	check(deposit.handled and deposit.deposited == 2 and session.cards[chest].stored_coins == 2, "capacity caps deposit")
	check(not session.cards.has(c1) and not session.cards.has(c2) and session.cards.has(c3) and session.cards.has(other), "bottom-to-top deposit keeps invalid and excess cards")
	session.stacks[coin_stack].card_ids = [c3, other]
	deposit = world.deposit_stack(chest, coin_stack)
	check(deposit.handled and deposit.deposited == 0, "full chest still handles currency drop")
	check(world.can_click_chest(chest), "singleton chest clickable")
	session.spawn_card("other", Vector2.ZERO, session.cards[chest].stack_id)
	check(not world.can_click_chest(chest), "stacked chest cannot click")
	check(world.withdraw_coin(chest) and session.cards[chest].stored_coins == 1, "trade withdraw from stacked chest")
	var count: int = session.cards.size()
	check(world.withdraw_coin(chest, true, Vector2(4, 5)) and session.cards.size() == count + 1, "withdraw spawn produces one coin")
	check(not world.withdraw_coin(chest), "empty withdrawal rejected")
	world.currency_guid = ""
	check(not world.deposit_stack(chest, coin_stack).handled, "no currency rejects deposits")
	world.currency_guid = "coin"
	var pen: int = session.spawn_card("pen")
	var pen_stack: int = session.cards[pen].stack_id
	session.spawn_card("other", Vector2.ZERO, pen_stack)
	var cow: int = session.spawn_card("cow", Vector2.ZERO, pen_stack)
	var cow2: int = session.spawn_card("cow", Vector2.ZERO, pen_stack)
	check(world.should_stay_in_enclosure(cow), "raw second position protected")
	check(not world.should_stay_in_enclosure(cow2), "nonmob consumes enclosure position")
	check(not world.should_stay_in_enclosure(pen), "enclosure itself not above enclosure")
	var mob: int = session.spawn_card("mob")
	var mob_stack: int = session.cards[mob].stack_id
	session.spawn_card("pen", Vector2.ZERO, mob_stack)
	check(not world.should_stay_in_enclosure(mob), "aggressive ignores enclosure")
	check(world.start_production(cow), "passive producer starts")
	check(float(world.production_timers[cow]) >= 10.5 and float(world.production_timers[cow]) <= 11.0, "initial jitter before first full interval")
	check(not world.start_production(mob), "aggressive cannot produce")
	check(world.tick_production(0).is_empty(), "paused production does nothing")
	session.combat.dragged[cow] = true
	check(world.tick_production(11).is_empty(), "dragged producer skips interval")
	session.combat.dragged.erase(cow)
	check(world.tick_production(9).is_empty(), "failed wake does not accumulate production")
	check(world.tick_production(1).size() == 1, "enclosed cow still produces")
	check(world.tick_production(100).size() == 1, "long frame does not catch up coroutine")
	session.stacks[pen_stack].recipe_guid = "craft"
	check(not world.can_act(cow) and world.tick_production(10).is_empty(), "crafting blocks production")
	session.stacks[pen_stack].recipe_guid = ""
	session.combat.membership[cow] = 99
	check(not world.can_act(cow), "combat blocks AI")
	session.combat.membership.erase(cow)
	check(world.aggressive_intent(mob).action == "patrol", "no player or combat patrols")
	var hero: int = session.spawn_card("hero", Vector2(100, 0))
	check(world.aggressive_intent(mob).card_id == hero, "player hunt intentionally ignores aggro radius")
	var tasks := [{"id": 20, "ongoing": true, "has_player": true, "position": Vector2(2, 0)}]
	check(world.aggressive_intent(mob, tasks).action == "join_combat", "combat takes priority and joins at 1.5 attack radius")
	tasks[0].position = Vector2(4, 0)
	check(world.aggressive_intent(mob, tasks).action == "approach_combat", "approach nearby combat")
	tasks[0].position = Vector2(5, 0)
	check(world.aggressive_intent(mob, tasks).action == "approach_player", "combat aggro boundary strictly excluded")
	session.cards[hero].position = Vector2(1.5, 0)
	session.stacks[session.cards[hero].stack_id].position = Vector2(1.5, 0)
	check(world.aggressive_intent(mob).action == "attack_player", "attack range inclusive")
	session.combat.membership[hero] = 1
	check(world.aggressive_intent(mob).action == "patrol", "hunt excludes engaged player")
	# Selection precedence, count, chance and completion using fixture encounters.
	for n in range(4):
		catalog.definitions[str(n)] = {"guid": str(n), "fields": {"id": "id" + str(n), "cardToSpawn": {"guid": "cow"}, "type": n, "dayValue": 7, "maxDayValue": 9, "priority": 0, "chance": 1.0, "maxCardsOnBoardLimit": 1000}}
	world.encounter_guids = ["3", "2", "1", "0"]
	world.reset()
	rolls = 0
	check(world.select_encounter(7, false, roll_zero) == "0" and rolls == 4, "intrinsic type beats serialized order")
	catalog.definitions["3"].fields.priority = 1
	check(world.select_encounter(7, false, roll_zero) == "3", "explicit priority beats type")
	catalog.definitions["3"].fields.maxCardsOnBoardLimit = world.board_card_count()
	check(world.select_encounter(7, false, roll_zero) == "0", "card count limit exclusive")
	world.encounter_guids = ["0"]
	catalog.definitions["0"].fields.chance = 0
	check(world.select_encounter(7, false, roll_zero) == "0", "chance uses inclusive comparison at zero")
	catalog.definitions["0"].fields.chance = 1
	catalog.definitions["0"].fields.count = 3
	catalog.definitions["0"].fields.maxCardsOnBoardLimit = world.board_card_count() + 1
	event = world.finish_day(7)
	check(event.spawned.size() == 3, "limit gates eligibility not spawned count")
	var distinct: Dictionary = {}
	for id in event.spawned:
		distinct[session.cards[id].stack_id] = true
	check(distinct.size() == 3, "event count uses separate stacks")
	print("World rules: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
