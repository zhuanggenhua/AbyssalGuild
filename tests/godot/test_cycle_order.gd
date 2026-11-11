extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make(limit: int = 100):
	var catalog := Catalog.new()
	var rules: Array = []
	rules.resize(144)
	rules.fill(1)
	catalog.configure({"cards": [
		{"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero", "category": 2, "faction": 1, "maxHealth": 10, "isSellable": false, "loot": [{"Card": {"guid": "corpse"}, "Weight": 1}]}},
		{"guid": "starver", "script_class": "CardDefinition", "fields": {"id": "starver", "category": 2, "faction": 1, "loot": [{"Card": {"guid": "food_b"}, "Weight": 1}]}},
		{"guid": "enemy", "script_class": "CardDefinition", "fields": {"id": "enemy", "category": 9, "faction": 2}},
		{"guid": "food_a", "script_class": "CardDefinition", "fields": {"id": "food_a", "category": 3, "nutrition": 4}},
		{"guid": "food_b", "script_class": "CardDefinition", "fields": {"id": "food_b", "category": 3, "nutrition": 2}},
		{"guid": "empty_food", "script_class": "CardDefinition", "fields": {"id": "empty_food", "category": 3, "nutrition": 0}},
		{"guid": "corpse", "script_class": "CardDefinition", "fields": {"id": "corpse", "category": 4}},
		{"guid": "material", "script_class": "CardDefinition", "fields": {"id": "material", "category": 1, "sellPrice": 3}},
		{"guid": "visitor", "script_class": "CardDefinition", "fields": {"id": "visitor", "category": 1}},
		{"guid": "coin", "script_class": "CardDefinition", "fields": {"id": "coin", "category": 7}},
		{"guid": "gear", "script_class": "CardDefinition", "fields": {"id": "gear", "category": 5, "equipmentSlot": 0}},
		{"guid": "boost", "script_class": "LimitBoosterDefinition", "fields": {"id": "boost", "category": 6, "boostAmount": 10}}
	], "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "category": 0, "slots": [{"Entries": [{"Card": {"guid": "boost"}, "Weight": 1}]}]}}],
	"encounters": [{"guid": "event", "fields": {"id": "arrival", "type": 0, "dayValue": 5, "chance": 1.0, "count": 1, "maxCardsOnBoardLimit": 4, "oneTimeOnly": true, "cardToSpawn": {"guid": "visitor"}}}],
	"settings": [{"guid": "settings", "script_class": "CardSettings", "fields": {"hungerPerCharacter": 2, "baseCardLimit": limit, "stackStep": {"x": 0, "y": 0, "z": 0}}}, {"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}],
	"scenes": [{"name": "Main", "documents": [
		{"script_class": "TradeManager", "fields": {"m_GameObject": {"fileID": "10"}, "currencyCard": {"guid": "coin"}}},
		{"file_id": "11", "object_type": "Transform", "fields": {"m_GameObject": {"fileID": "10"}}},
		{"script_class": "EncounterManager", "fields": {"allEncounters": [{"guid": "event"}]}}
	]}]})
	var session := Session.new()
	session.configure(catalog, 123)
	return session

func _init() -> void:
	_test_snapshots()
	_test_source_order()
	_test_selling_events()
	_test_pack_phases()
	_test_source_data()
	print("Cycle order: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_snapshots() -> void:
	var s = make()
	var first: int = s.spawn_card("starver")
	var second: int = s.spawn_card("hero")
	s.end_day()
	check(not s.cards.has(first) and not s.cards.has(second), "Starvation loot cannot enter the initial food pool")
	check(s.stats().nutrition == 2 and s.phase == "game_over", "Late food remains on a board with no survivors")

	s = make()
	s.spawn_card("hero")
	second = s.spawn_card("hero")
	var food: int = s.spawn_card("food_b")
	var empty: int = s.spawn_card("empty_food")
	var live = s
	var food_id: int = food
	var empty_id: int = empty
	var replenish := func(kind: String, payload: Dictionary):
		if kind == "card_killed" and payload.card_id == food_id:
			live.cards[empty_id].nutrition = 2
	s.event_occurred.connect(replenish)
	s.end_day()
	check(not s.cards.has(second) and s.cards[empty].nutrition == 2, "Initially empty food stays ineligible if nutrition changes during feeding")
	s.event_occurred.disconnect(replenish)

	s = make()
	first = s.spawn_card("hero")
	food = s.spawn_card("food_b")
	Equipment.detach(s, food)
	s.end_day()
	check(not s.cards.has(first) and s.cards[food].nutrition == 2, "Unregistered food is absent from source AllCards")

	s = make()
	s.spawn_card("hero")
	second = s.spawn_card("hero")
	var initial: int = s.spawn_card("food_a")
	food = s.spawn_card("food_b")
	var removed: int = second
	live = s
	var remove_waiting := func(kind: String, _payload: Dictionary):
		if kind == "stats_changed" and live.phase == "feeding" and live.cards.has(removed):
			live._remove_card(removed)
			live._remove_card(food)
	s.event_occurred.connect(remove_waiting)
	s.end_day()
	check(s.phase == "ready" and s.cards[initial].nutrition == 2, "Removed snapshot references are skipped safely without feeding replacements")
	s.event_occurred.disconnect(remove_waiting)

func _test_source_order() -> void:
	var s = make()
	var first: int = s.spawn_card("hero")
	var second: int = s.spawn_card("hero")
	check(s.move_to_stack(first, s.cards[second].stack_id), "Character reorder fixture uses an ordinary stack move")
	var food: int = s.spawn_card("food_b")
	check(s._feeding_card_ids() == [second, first, food], "Registered stack/member order replaces global creation order")
	s.end_day()
	check(s.cards.has(second) and not s.cards.has(first), "Stack-first character receives scarce food")

	s = make()
	first = s.spawn_card("hero")
	var enemy: int = s.spawn_card("enemy")
	s.combat.start_combat([first], [enemy])
	second = s.spawn_card("hero")
	food = s.spawn_card("food_b")
	check(s._feeding_card_ids() == [second, food, first, enemy], "All registered board stacks precede ongoing combatants")
	s.end_day()
	check(s.cards.has(second) and not s.cards.has(first), "Board character eats before earlier-created combat character")

	s = make()
	first = s.spawn_card("hero")
	second = s.spawn_card("hero")
	var first_enemy: int = s.spawn_card("enemy")
	var second_enemy: int = s.spawn_card("enemy")
	s.combat.start_combat([second], [second_enemy])
	s.combat.start_combat([first], [first_enemy])
	food = s.spawn_card("food_b")
	check(s._feeding_card_ids() == [food, second, second_enemy, first, first_enemy], "Combat registration order preserves attacker then defender enumeration")
	s.end_day()
	check(s.cards.has(second) and not s.cards.has(first), "Older registered combat gets scarce food first")

	s = make()
	s.spawn_card("hero")
	s.spawn_card("hero")
	first = s.spawn_card("food_a")
	second = s.spawn_card("food_b")
	s.end_day()
	check(s.cards.has(first) and s.cards[first].nutrition == 2 and not s.cards.has(second), "Equal-distance leftovers reenter the tail, after untouched food")
	check(s.stats().characters == 2 and s.phase == "ready", "Both characters survive stable-tie distribution")

	s = make()
	s.spawn_card("hero")
	first = s.spawn_card("food_a")
	second = s.spawn_card("food_b")
	check(s.move_to_stack(first, s.cards[second].stack_id), "Food reorder fixture uses an ordinary stack move")
	s.end_day()
	check(s.cards[first].nutrition == 4 and not s.cards.has(second), "Initial equal-distance food ties follow stack/member order, not creation order")

	s = make()
	s.spawn_card("hero")
	first = s.spawn_card("food_b", Vector2(10, 0))
	second = s.spawn_card("food_b", Vector2(1, 0))
	s.end_day()
	check(s.cards.has(first) and not s.cards.has(second), "Nearest current settled pose still overrides candidate-list order")

func _test_selling_events() -> void:
	var s = make(2)
	var hero: int = s.spawn_card("hero")
	s.spawn_card("material")
	var gear: int = s.spawn_card("gear")
	s.phase = "selling"
	s.paused = true
	check(s.equipment.equip(hero, gear) and s.stats().excess == 0, "Equipping gear removes it from the board count")
	check(s.phase == "selling", "Source has no fabricated stats notification when equipping")
	s.spawn_card("coin")
	check(s.phase == "ready" and s.world.processed_days.has(1), "Unrelated stats notification completes selling after board count changed")
	s._notify_stats_changed()
	check(s.world.processed_days.size() == 1, "Ready phase ignores later selling notifications")

	s = make(1)
	s.day = 5
	s.spawn_card("hero")
	var sold: int = s.spawn_card("material")
	s.phase = "selling"
	s.paused = true
	var records: Array = []
	var created: Array = []
	var live = s
	var observe := func(kind: String, payload: Dictionary):
		if kind == "encounter":
			records.append({"currency": live.stats().currency, "phase": live.phase, "count": live.world.board_card_count()})
			live._notify_stats_changed() # Reentry must not select/spawn twice.
		elif kind == "card_created":
			created.append(payload.base_definition_guid)
	s.event_occurred.connect(observe)
	check(s.sell_card(sold), "Excess card sells")
	check(records == [{"currency": 1, "phase": "ready", "count": 3}], "Encounter selection occurs on first payout, below the all-card threshold")
	check(created == ["visitor", "coin", "coin", "coin"], "Nested encounter creation precedes first coin's created event and remaining payout")
	check(s.stats().currency == 3 and s.world.board_card_count() == 5, "Original sale finishes payout after synchronous cycle transition")
	check(s.world.completed_encounters.has("arrival") and s.world.processed_days.size() == 1, "Encounter reentry guard is claimed exactly once")
	s.event_occurred.disconnect(observe)

	s = make(1)
	s.spawn_card("hero")
	sold = s.spawn_card("material")
	s.catalog.fields("material").sellPrice = 0
	s.phase = "selling"
	check(s.sell_card(sold) and s.phase == "ready" and s.stats().currency == 0, "Zero-price sale transitions on final stats notification without a payout coin")

func _test_pack_phases() -> void:
	var s = make(1)
	s.spawn_card("hero")
	s.spawn_card("material")
	var pack: int = s.spawn_card("pack", Vector2(4, -3))
	s.phase = "selling"
	s.paused = true
	var opened: int = s.open_pack(pack)
	check(opened >= 0 and s.cards[opened].definition_guid == "boost", "Selling permits normal pack opening")
	check(s.cards[opened].position == Vector2(4, -3), "Pack output preserves the existing pack-root spawn rule")
	check(not s.cards.has(pack) and s.phase == "ready", "Pack output stats can satisfy selling before exhausted-pack cleanup")
	for locked in ["feeding", "ready", "game_over"]:
		s = make()
		pack = s.spawn_card("pack")
		s.phase = locked
		var before: Dictionary = Codec.capture(s)
		check(s.open_pack(pack) == -1 and Codec.capture(s) == before, "Pack opening remains atomic and locked in " + locked)

	s = make()
	s.spawn_card("hero")
	s.spawn_card("food_b")
	s.speed = 2
	s.end_day()
	var events: Array = []
	var day_events := func(kind: String, _payload: Dictionary): events.append(kind)
	s.event_occurred.connect(day_events)
	check(s.start_day() and s.day == 2 and not s.paused and s.speed == 1 and s.elapsed == 0, "Start Day retains silent normal pace reset")
	check(events == ["day_started"], "Start Day still publishes only day-started before caller checkpoints")
	s.event_occurred.disconnect(day_events)

func _test_source_data() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SOURCE-DATA CYCLE CHECKS SKIPPED: private catalog unavailable")
		return
	var catalog := Catalog.new()
	check(catalog.load_file() == OK, "Private source catalog loads")
	var s := Session.new()
	s.configure(catalog, 123)
	var villager: String = catalog.find_by_name("Villager")
	s.spawn_card(villager)
	s.spawn_card(villager)
	var stew: int = s.spawn_card(catalog.find_by_name("Stew"))
	var apple: int = s.spawn_card(catalog.find_by_name("Apple"))
	check(s.cards[stew].nutrition == 10 and s.cards[apple].nutrition == 2, "Source food nutrition is unmodified")
	s.end_day()
	check(s.cards[stew].nutrition == 8 and not s.cards.has(apple) and s.stats().characters == 2, "Source Stew leftover goes behind equally near Apple")

	s = Session.new()
	s.configure(catalog, 123)
	s.day = 7
	s.spawn_card(villager)
	for i in range(23): s.spawn_card(catalog.find_by_name("Wood"))
	var sword: int = s.spawn_card(catalog.find_by_name("Sword"))
	for i in range(74): s.spawn_card(catalog.find_by_name("Coin"))
	for i in range(2): s.spawn_card(catalog.find_by_name("Berry"))
	s.end_day()
	check(s.phase == "selling" and s.stats().excess == 1 and s.world.board_card_count() == 99, "Source board reaches selling with 99 all-cards and one excess")
	# The first eligible roll is the scene's Slime. Control only the random seed,
	# without modifying imported chance, threshold, price or encounter fields.
	for seed_value in range(100):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randf() < 0.5:
			s.rng.seed = seed_value
			break
	var payouts: Array = []
	var live = s
	var source_event := func(kind: String, payload: Dictionary):
		if kind == "encounter": payouts.append([live.stats().currency, payload.encounter_guid])
	s.event_occurred.connect(source_event)
	check(s.sell_card(sword), "Source Sword sells for three coins")
	check(payouts.size() == 1 and payouts[0] == [75, s.world.encounter_guids[1]], "Source weekly encounter triggers at first coin while board count is below 100")
	check(s.stats().currency == 77 and s.world.board_card_count() == 102 and s.phase == "ready", "Source remaining coins finish after encounter without reselection")
	s.event_occurred.disconnect(source_event)

	s = Session.new()
	s.configure(catalog)
	var starter: int = s.start_new_game()
	s.phase = "selling"
	var opened: int = s.open_pack(starter)
	check(opened >= 0 and s.cards[opened].definition_guid == villager, "Source Starter Pack's first slot opens during selling")
	check(s.cards[starter].uses_left == 3 and s.phase == "ready", "Source pack draw completes even when its stats event ends selling")
