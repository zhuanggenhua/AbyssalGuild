extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "audited catalog loads")
	check(catalog.stacking_rules().size() == 144, "12 by 12 little-endian matrix")
	var session = Session.new()
	session.configure(catalog, 1234)
	var pack: int = session.start_new_game()
	check(session.cards.size() == 1, "only starter on new board")
	check(session.cards[pack].uses_left == 4, "starter has four slots")
	var opened: Array = []
	for expected in ["Villager", "Berry Bush", "Rock", "Wood"]:
		var id: int = session.open_pack(pack)
		check(id >= 0, "slot spawned: " + expected)
		if id >= 0:
			opened.append(id)
			check(catalog.fields(session.cards[id].definition_guid).displayName == expected, "starter order: " + expected)
	check(not session.cards.has(pack), "empty starter removed")
	check(session.open_pack(pack) == -1, "cannot reopen destroyed pack")
	check(session.stats().characters == 1 and session.stats().nutrition_need == 2, "character hunger rule")
	var villager: int = opened[0]
	var bush: int = opened[1]
	check(session.move_to_stack(villager, session.cards[bush].stack_id), "villager onto bush allowed")
	var stack = session.stacks[session.cards[bush].stack_id]
	check(not stack.recipe_guid.is_empty(), "gather recipe starts")
	var duration: float = float(catalog.fields(stack.recipe_guid).get("craftingDuration", 5))
	var uses: int = session.cards[bush].uses_left
	session.tick(duration / 2.0)
	check(is_equal_approx(stack.progress, duration / 2.0), "progress halfway")
	session.paused = true
	session.tick(1)
	check(is_equal_approx(stack.progress, duration / 2.0), "pause preserves progress")
	session.paused = false
	session.tick(duration / 2.0)
	check(session.cards[bush].uses_left == uses - 1, "resource consumes one durability")
	check(session.cards.has(villager), "Keep preserves villager")
	check(session.stats().nutrition > 0, "gather creates food")
	check(not stack.recipe_guid.is_empty(), "consuming recipe auto repeats")
	var wood: int = opened[3]
	check(session.sell_card(wood), "sell wood")
	check(not session.cards.has(wood) and session.stats().currency == 1, "sale creates coin card")
	check(not session.sell_card(villager), "villager cannot be sold")
	var own_recipe: Dictionary = {"requiredIngredients": [{"card": {"guid": session.cards[bush].definition_guid}, "count": 1}], "allowExcessIngredients": false}
	check(not session.matches_recipe(stack, own_recipe), "strict recipe rejects unrelated extras")
	own_recipe.allowExcessIngredients = true
	check(session.matches_recipe(stack, own_recipe), "workstation tolerates extras")
	var before_day: int = session.day
	while session.stats().nutrition < 2:
		session.spawn_card(catalog.find_by_name("Berry"))
	session.end_day()
	check(session.phase == "ready", "fed village ready for next day")
	check(session.start_day() and session.day == before_day + 1, "new day explicit")
	var starving = Session.new()
	starving.configure(catalog)
	starving.spawn_card(catalog.find_by_name("Villager"))
	starving.end_day()
	check(starving.phase == "game_over" and starving.stats().characters == 0, "unfed character dies")
	test_feeding_detaches_single_card(catalog)
	test_review_regressions(catalog)
	test_death_loot(catalog)
	test_edge_cases(catalog)
	print("Runtime checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func test_edge_cases(catalog) -> void:
	var session = Session.new()
	session.configure(catalog, 77)
	var wood: String = catalog.find_by_name("Wood")
	var rock: String = catalog.find_by_name("Rock")
	check(session._weighted([], true).is_empty(), "empty weighted slot returns nothing")
	check(session._weighted([{"Card": {"guid": wood}, "Weight": 0}], true) == wood, "pack clamps zero weight to one")
	check(session._weighted([{"Card": {"guid": wood}, "Weight": 0}], false).is_empty(), "loot zero weight ignored")
	check(session.can_stack(rock, rock), "same-definition resource allowed")
	check(not session.can_stack(rock, catalog.find_by_name("Berry Bush")), "different resource definitions rejected")
	var recipe: Dictionary = {"requiredIngredients": [{"card": {"guid": wood}, "count": 1, "consumptionMode": 2}], "resultingCard": {"guid": rock}, "id": "test_destroy"}
	catalog.definitions["test_recipe"] = {"fields": recipe}
	var id: int = session.spawn_card(wood)
	session.cards[id].uses_left = 99
	var stack = session.stacks[session.cards[id].stack_id]
	stack.recipe_guid = "test_recipe"
	session._complete_recipe(stack)
	check(not session.cards.has(id), "Destroy ignores durability")
	var purchase = Session.new()
	purchase.configure(catalog)
	var pack_guid: String = ""
	for entry in catalog.data.packs:
		if int(entry.fields.get("buyPrice", 0)) > 1 :
			pack_guid = str(entry.guid)
			break
	check(not pack_guid.is_empty(), "source has paid vendor")
	purchase.completed_quests = int(catalog.fields(pack_guid).get("minQuests", 0))
	check(purchase.buy_pack(pack_guid) == -1, "insufficient currency rejects without mutation")
	var coin: String = catalog.find_by_name("Coin")
	var coin_id: int = purchase.spawn_card(coin)
	var partial: Dictionary = purchase.pay_vendor(pack_guid, purchase.cards[coin_id].stack_id)
	check(partial.accepted and partial.paid == 1 and partial.pack_id == -1, "partial payment persists")
	check(not purchase.cards.has(coin_id), "partial payment consumes coin")
	var price: int = int(catalog.fields(pack_guid).buyPrice)
	for i in range(price - 1):
		purchase.spawn_card(coin)
	var bought: int = purchase.buy_pack(pack_guid)
	check(bought >= 0 and purchase.stats().currency == 0, "purchase honors previous installment")
	check(purchase.cards[bought].uses_left == catalog.fields(pack_guid).slots.size(), "purchased pack has all slots")
	var hunger = Session.new()
	hunger.configure(catalog)
	var villager: int = hunger.spawn_card(catalog.find_by_name("Villager"))
	var berry: int = hunger.spawn_card(catalog.find_by_name("Berry"))
	hunger.cards[berry].nutrition = 3
	hunger.cards[villager].health = 1
	hunger.end_day()
	check(hunger.cards[berry].nutrition == 1, "feeding preserves leftover nutrition")
	check(hunger.cards[villager].health > 1, "feeding heals survivor")
	var overflow = Session.new()
	overflow.configure(catalog)
	overflow.spawn_card(catalog.find_by_name("Villager"))
	var food: int = overflow.spawn_card(catalog.find_by_name("Berry"))
	overflow.cards[food].nutrition = 2
	for i in range(25):
		overflow.spawn_card(wood)
	overflow.end_day()
	check(overflow.phase == "selling" and overflow.stats().excess == 2, "day blocks on excess cards")
	check(not overflow.start_day(), "cannot skip excess sale")
	var sold: int = 0
	for card in overflow.cards.values().duplicate():
		if card.definition_guid == wood and sold < 2:
			overflow.sell_card(card.id)
			sold += 1
	check(overflow.phase == "ready", "selling exact excess unblocks next day")
	catalog.definitions.erase("test_recipe")

func test_death_loot(catalog) -> void:
	var session = Session.new()
	session.configure(catalog, 71)
	var villager: String = catalog.find_by_name("Villager")
	var loot: String = catalog.ref_guid(catalog.fields(villager).loot[0].Card)
	var position := Vector2(2.5, -1.75)
	var id: int = session.spawn_card(villager, position)
	session.end_day()
	check(not session.cards.has(id), "starvation removes villager")
	check(session.cards.size() == 1, "starvation creates exactly one loot card")
	var dropped = session.cards.values()[0]
	check(dropped.definition_guid == loot, "starvation uses source villager loot")
	check(dropped.position == position, "death loot retains world position")
	check(not session.kill_card(id) and session.cards.size() == 1, "repeated death cannot duplicate loot")
	check(session._roll_loot([{"Card": {"guid": loot}, "Weight": 0}]).is_empty(), "death ignores zero loot weight")
	check(session._roll_loot([{"Card": {"guid": loot}, "Weight": -4}]).is_empty(), "death ignores negative loot weight")
	check(session._roll_loot([{"Card": {}, "Weight": 10}]).is_empty(), "null loot entry has no output")
	var destroyed: int = session.spawn_card(villager)
	session._remove_card(destroyed)
	check(session.cards.size() == 1, "ordinary destruction does not spawn death loot")
	var nonliving: int = session.spawn_card(catalog.find_by_name("Wood"))
	session.kill_card(nonliving)
	check(session.cards.size() == 1, "nonliving kill creates no death loot")

func test_review_regressions(catalog) -> void:
	var session = Session.new()
	session.configure(catalog, 19)
	session.paused = true
	session.speed = 2
	session.start_new_game()
	check(not session.paused and session.speed == 1, "new game resets pause and speed")
	session.tick(1)
	check(session.elapsed == 1, "new game after pause advances time")
	var overflow = Session.new()
	overflow.configure(catalog)
	for i in range(2):
		overflow.spawn_card(catalog.find_by_name("Villager"))
	var food: int = overflow.spawn_card(catalog.find_by_name("Berry"))
	overflow.cards[food].nutrition = 2
	for i in range(23):
		overflow.spawn_card(catalog.find_by_name("Wood"))
	overflow.end_day()
	check(overflow.stats().characters == 1, "one of two villagers survives insufficient food")
	check(overflow.stats().cards_owned == 25, "corpse counts toward day-end capacity")
	check(overflow.phase == "selling" and overflow.stats().excess == 1, "death loot can require an excess sale")
	check(session._round_to_even(2.5) == 2 and session._round_to_even(4.5) == 4, "healing midpoint rounds down to even")
	check(session._round_to_even(3.5) == 4 and session._round_to_even(7.5) == 8, "healing midpoint rounds up to even")
	for name in ["Baby", "Ranger"]:
		var healing = Session.new()
		healing.configure(catalog)
		var character: int = healing.spawn_card(catalog.find_by_name(name))
		check(character >= 0, "source character exists: " + name)
		if character < 0:
			continue
		healing.cards[character].health = 1
		for i in range(2):
			var berry: int = healing.spawn_card(catalog.find_by_name("Berry"))
			healing.cards[berry].nutrition = 1
		var maximum: int = int(catalog.fields(healing.cards[character].definition_guid).maxHealth)
		var expected: int = mini(maximum, 1 + 2 * session._round_to_even(float(maximum) * 0.25))
		healing.end_day()
		check(healing.cards[character].health == expected, "feeding uses source midpoint healing: " + name)

func test_feeding_detaches_single_card(catalog) -> void:
	var session = Session.new()
	session.configure(catalog)
	var destination := Vector2(3, 2)
	session.spawn_card(catalog.find_by_name("Villager"), destination)
	var wood: int = session.spawn_card(catalog.find_by_name("Wood"), Vector2(-2, -1))
	var original = session.stacks[session.cards[wood].stack_id]
	var berry: int = session.spawn_card(catalog.find_by_name("Berry"), original.position, original.id)
	var rock: int = session.spawn_card(catalog.find_by_name("Rock"), original.position, original.id)
	session.cards[berry].nutrition = 3
	catalog.definitions["test_feeding_craft"] = {"fields": {"requiredIngredients": [{"card": {"guid": session.cards[wood].definition_guid}, "count": 1}], "allowExcessIngredients": true}}
	original.recipe_guid = "test_feeding_craft"
	original.progress = 2
	session.end_day()
	check(original.card_ids == [wood, rock], "feeding removes only food from middle of stack")
	check(session.cards[rock].stack_id == original.id, "feeding does not split cards above food")
	check(original.recipe_guid.is_empty() and original.progress == 0, "feeding cancels old craft even if remaining inputs match")
	check(session.cards[berry].stack_id != original.id, "partially eaten food remains in separate stack")
	check(session.cards[berry].nutrition == 1, "detached food retains remaining nutrition")
	check(session.cards[berry].position == destination, "remaining food moves to eater world position")
	check(session.stacks[session.cards[berry].stack_id].position == destination, "remaining food stack position follows food")
	catalog.definitions.erase("test_feeding_craft")
