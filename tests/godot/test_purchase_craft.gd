extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const CycleDriver = preload("res://tests/godot/cycle_test_driver.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func ingredient(guid: String, count: int = 1) -> Dictionary:
	return {"card": {"guid": guid}, "count": count, "consumptionMode": 2}

func recipe(guid: String, ingredients: Array, excess: bool = false) -> Dictionary:
	return {"guid": guid, "script_class": "RecipeDefinition", "fields": {"id": guid, "requiredIngredients": ingredients, "allowExcessIngredients": excess, "randomWeight": 1, "craftingDuration": 10, "resultingCard": {"guid": "result"}}}

func make(price: int = 3, recipes: Array = []):
	var catalog = Catalog.new()
	var rows: Array = []
	for pair in [["wood", 4], ["coin", 7], ["foreign", 7], ["chest", 8], ["station", 6], ["result", 4], ["visitor", 4]]:
		rows.append({"guid": pair[0], "name": pair[0], "script_class": "ChestDefinition" if pair[0] == "chest" else "CardDefinition", "fields": {"id": pair[0], "category": pair[1], "capacity": 8, "sellPrice": 1}})
	var matrix: Array = []; matrix.resize(144); matrix.fill(1)
	catalog.configure({"cards": rows, "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "buyPrice": price, "minQuests": 0, "slots": []}}],
		"recipes": recipes if not recipes.is_empty() else [recipe("work", [ingredient("wood"), ingredient("coin", 2)])],
		"settings": [{"guid": "rules", "script_class": "StackingRulesMatrix", "fields": {"rules": matrix}}]})
	var s = Session.new(); s.configure(catalog, 887); s.world.currency_guid = "coin"
	return s

func assemble(s, guids: Array, progress: float = 5.0) -> Dictionary:
	var stack_id := -1
	var ids: Array = []
	for guid in guids:
		var id: int = s.spawn_card(guid, Vector2(1, 2), stack_id)
		ids.append(id); stack_id = s.cards[id].stack_id
	var stack = s.stacks[stack_id]
	s._check_recipe(stack)
	if not stack.recipe_guid.is_empty(): stack.progress = progress
	return {"stack": stack, "ids": ids}

func encoded(s) -> String:
	return JSON.stringify(Codec.capture(s), "", true, true)

func count(s, guid: String) -> int:
	var total := 0
	for card in s.cards.values():
		if card.base_definition_guid == guid: total += 1
	return total

func restored(s):
	var result = Session.new(); result.configure(s.catalog, 1)
	check(Codec.restore(result, JSON.parse_string(encoded(s))).ok, "post-purchase JSON snapshot restores")
	return result

func _init() -> void:
	test_invalidation_and_callbacks()
	test_preflight()
	test_payment_order_and_chests()
	test_excess_and_empty_stacks()
	test_held_lifecycle()
	test_selling_callback()
	print("Purchase craft checks: %d passed / %d total" % [checks - failures, checks])
	quit(1 if failures else 0)

func test_invalidation_and_callbacks() -> void:
	# A second eligible recipe must not start just because payment changed membership.
	var s = make(3, [recipe("work", [ingredient("wood"), ingredient("coin", 2)]), recipe("wood_only", [ingredient("wood")])])
	var work := assemble(s, ["wood", "coin", "coin"], 9.5)
	var loose: int = s.spawn_card("coin")
	check(work.stack.recipe_guid == "work", "currency-input recipe starts before purchase")
	var state: int = s.rng.state
	var knowledge: Dictionary = s.discovered_recipes.duplicate()
	var events: Array = []
	var callbacks: Array = []
	var observe := func(kind, _payload): events.append(kind)
	s.event_occurred.connect(observe)
	s.changed.connect(func(): events.append("changed"))
	s.spawn_target_selector = func(_id, _ignored):
		callbacks.append(work.stack.recipe_guid.is_empty() and s.stats().currency == 0)
		return -1
	s.spawn_layout_resolver = func(): callbacks.append(work.stack.recipe_guid.is_empty() and s.stats().currency == 0)
	var bought: int = s.buy_pack("pack")
	check(bought > 0 and s.cards[bought].definition_guid == "pack", "paid convenience purchase returns the new pack")
	check(work.stack.card_ids == [work.ids[0]] and not s.cards.has(loose), "all three payment coins removed, wood survives")
	check(work.stack.recipe_guid.is_empty() and work.stack.progress == 0 and not work.stack.paused, "invalidated craft clears task, time and pause")
	check(callbacks == [true, true], "central factory selector and layout callbacks see validated craft and settled funds")
	check(events == ["changed", "pack_purchased", "stats_changed", "changed"], "validation adds no signals and preserves purchase/stats ordering")
	check(s.rng.state == state and s.discovered_recipes == knowledge, "validation neither rerolls nor discovers the now-eligible alternate recipe")
	check(s.vendor_payments.pack == 0, "completed installment balance resets")
	s.spawn_target_selector = Callable(); s.spawn_layout_resolver = Callable()
	var loaded = restored(s)
	s.tick(1); loaded.tick(1)
	check(count(s, "result") == 0 and count(s, "pack") == 1 and count(s, "wood") == 1, "next tick cannot produce both pack and invalid recipe output")
	check(encoded(s) == encoded(loaded), "round-trip preserves cancelled craft next tick and RNG")
	s.event_occurred.disconnect(observe)

func test_preflight() -> void:
	var s = make()
	var work := assemble(s, ["wood", "coin", "coin"], 7.25)
	var events: Array = []
	s.event_occurred.connect(func(kind, _payload): events.append(kind))
	s.changed.connect(func(): events.append("changed"))
	var before: String = encoded(s)
	check(s.buy_pack("pack") == -1 and encoded(s) == before and events.is_empty(), "insufficient funds preserve exact craft, IDs, currency, RNG and signals")
	check(s.buy_pack("missing") == -1 and s.buy_pack("wood") == -1 and encoded(s) == before and events.is_empty(), "unknown and nonpack targets reject atomically")
	s.catalog.fields("pack").minQuests = 1
	s.catalog.fields("pack").buyPrice = 1
	check(s.buy_pack("pack") == -1 and encoded(s) == before and events.is_empty(), "quest gate precedes affordable payment and validation")
	s.catalog.fields("pack").minQuests = 0
	s.catalog.fields("pack").buyPrice = 0
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid == "work" and work.stack.progress == 7.25, "zero-price pack never consumes inputs or resets valid progress")
	check(events == ["changed", "pack_purchased", "changed"] and s.stats().currency == 2, "free purchase keeps currency and omits stats notification")
	s = make(); work = assemble(s, ["wood", "coin", "coin"], 7.25)
	s.vendor_payments.pack = 3
	check(s.buy_pack("pack") > 0 and s.stats().currency == 2 and work.stack.progress == 7.25, "fully prepaid purchase leaves craft untouched")

func test_payment_order_and_chests() -> void:
	var s = make(4, [recipe("work", [ingredient("wood"), ingredient("coin")], true)])
	var work := assemble(s, ["wood", "coin", "chest"], 8)
	var chest: int = work.ids[2]
	s.cards[chest].stored_coins = 8
	var later: int = s.spawn_card("foreign")
	s.vendor_payments.pack = 1
	var events: Array = []
	var balances: Array = []
	var on_event := func(kind, _payload):
		events.append(kind)
		if kind == "puff_requested": balances.append([s.cards[chest].stored_coins, work.stack.recipe_guid.is_empty()])
	s.event_occurred.connect(on_event)
	var state: int = s.rng.state
	check(s.buy_pack("pack") > 0, "prior installment plus mixed payment buys pack")
	check(not s.cards.has(work.ids[1]) and s.cards[chest].stored_coins == 6 and s.cards.has(later), "existing global insertion order spends first coin then only needed chest balance")
	check(balances == [[7, true], [6, true]], "each withdrawal puff sees decremented balance and already invalidated coin craft")
	check(events == ["puff_requested", "puff_requested", "pack_purchased", "stats_changed"], "chest puffs precede purchase and the sole final stats notification")
	check(s.rng.state == state, "mixed payment and validation consume no RNG")
	s.event_occurred.disconnect(on_event)
	# Emptying even a full chest changes storage, not recipe membership.
	s = make(8, [recipe("chest_work", [ingredient("chest"), ingredient("wood")])])
	work = assemble(s, ["chest", "wood"], 9)
	s.cards[work.ids[0]].stored_coins = 8
	later = s.spawn_card("coin")
	check(s.buy_pack("pack") > 0 and s.cards[work.ids[0]].stored_coins == 0 and s.cards.has(later), "full chest exactly pays price without consuming chest or later coin")
	check(work.stack.recipe_guid == "chest_work" and work.stack.progress == 9 and work.stack.card_ids == work.ids, "chest-funded craft preserves membership, identity and elapsed time")
	var loaded = restored(s)
	s.tick(1); loaded.tick(1)
	check(count(s, "result") == 1 and count(s, "pack") == 1 and encoded(s) == encoded(loaded), "chest-funded valid craft completes once after save and reload")
	# A partly funded chest does not block later global cards in convenience buying.
	s = make(3)
	chest = s.spawn_card("chest"); s.cards[chest].stored_coins = 1
	var first: int = s.spawn_card("foreign"); later = s.spawn_card("coin")
	check(s.buy_pack("pack") > 0 and s.cards[chest].stored_coins == 0 and not s.cards.has(first) and not s.cards.has(later), "convenience buying retains chest-then-foreign-currency-then-coin order")

func test_excess_and_empty_stacks() -> void:
	var s = make(2, [recipe("work", [ingredient("wood"), ingredient("coin", 2)], true)])
	var work := assemble(s, ["wood", "coin", "coin", "coin", "coin", "coin"], 6.75)
	var untouched := assemble(s, ["wood", "coin", "coin"], 4.25)
	var state: int = s.rng.state
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid == "work" and work.stack.progress == 6.75, "spending excess coins retains the exact valid task and progress")
	check(work.stack.card_ids == [work.ids[0], work.ids[3], work.ids[4], work.ids[5]], "partial same-stack payment consumes earliest cards, not the stack tail")
	check(untouched.stack.card_ids == untouched.ids and untouched.stack.progress == 4.25, "later unrelated crafting stack is untouched")
	var loaded = restored(s)
	s.tick(0.25); loaded.tick(0.25)
	check(encoded(s) == encoded(loaded) and work.stack.progress == 7 and s.rng.state == state, "preserved excess task resumes identically after reload without reselection")
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid.is_empty() and work.stack.progress == 0, "later purchase cancels only when remaining inputs become insufficient")
	check(untouched.stack.recipe_guid == "work" and untouched.stack.progress == 4.5, "second purchase still does not reset untouched task")
	s = make(2, [recipe("coins", [ingredient("coin", 2)])])
	work = assemble(s, ["coin", "coin"], 9)
	check(s.buy_pack("pack") > 0 and not s.stacks.has(work.stack.id) and work.stack.card_ids.is_empty(), "fully consumed payment stack unregisters")
	check(work.stack.recipe_guid.is_empty() and work.stack.progress == 0 and not work.stack.paused, "retained empty stack object cannot keep a stale craft")

func test_held_lifecycle() -> void:
	# Buying unrelated currency must not validate a deliberately incomplete held original.
	var s = make(1)
	s.spawn_card("coin")
	var work := assemble(s, ["wood", "coin", "coin"], 9.5)
	s.drag.begin(work.ids[2])
	var held: int = s.drag.stack_id
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid == "work" and work.stack.paused and work.stack.progress == 9.5, "unaffected held original retains its paused returnable task")
	check(s.drag.active() and s.drag.stack_id == held and s.drag.original_stack_id(work.ids[2]) == work.stack.id, "unrelated purchase leaves pointer grant and original identity unchanged")
	check(s.move_to_stack(work.ids[2], work.stack.id, s.drag.original_stack_id(work.ids[2])), "tail can still return after unrelated payment")
	s.drag.finish_standard(work.stack.id); s.tick(0.5)
	check(count(s, "result") == 1 and not s.drag.active(), "returned unaffected task completes at preserved time")
	# Paying away a detached ingredient must not settle/reset the live pointer itself.
	s = make(); work = assemble(s, ["wood", "coin", "coin"], 9.5)
	s.spawn_card("coin"); s.drag.begin(work.ids[1]); held = s.drag.stack_id
	check(s.buy_pack("pack") > 0 and not s.stacks.has(held) and s.drag.active(), "fully spent held tail waits for normal lifecycle settlement")
	check(work.stack.paused and work.stack.recipe_guid == "work", "spending detached coins does not prematurely settle untouched paused original")
	var loaded = restored(s)
	check(loaded.stacks[work.stack.id].recipe_guid.is_empty() and not loaded.drag.active(), "held post-purchase checkpoint normalizes missing ingredients without orphan task")
	check(s.drag.active() and work.stack.paused, "checkpoint does not change live hold or paused original")
	s.drag.finish_standard(); s.tick(1); loaded.tick(1)
	check(encoded(s) == encoded(loaded) and count(s, "result") == 0, "spent held tail ordinary release and restored next tick agree without double-spend")
	# A partially consumed tail still carries its original return permission.
	s = make(2, [recipe("work", [ingredient("wood")], true)])
	work = assemble(s, ["wood", "coin", "coin", "coin"], 7)
	s.drag.begin(work.ids[1]); held = s.drag.stack_id
	check(s.buy_pack("pack") > 0 and s.stacks[held].card_ids == [work.ids[3]], "partial held-tail purchase retains surviving member")
	check(s.drag.original_stack_id(work.ids[3]) == work.stack.id and work.stack.paused, "surviving held member keeps genuine original context after leading card is spent")
	s.drag.finish_standard()
	check(not s.drag.active() and work.stack.recipe_guid == "work" and work.stack.progress == 7 and not work.stack.paused, "partial payment uses ordinary resume rather than terminal cancellation")
	# Payment touching a paused original validates it but never unpauses a valid task.
	s = make(1, [recipe("work", [ingredient("wood"), ingredient("coin")], true)])
	work = assemble(s, ["wood", "coin", "coin", "wood"], 8)
	s.drag.begin(work.ids[3])
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid == "work" and work.stack.progress == 8 and work.stack.paused, "spending original excess coin preserves valid paused progress")
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid.is_empty() and work.stack.progress == 0 and not work.stack.paused, "spending last required original coin cancels even a paused task")
	check(s.drag.active() and s.cards.has(work.ids[3]), "invalidated original does not discard surviving held tail")
	s.drag.finish_standard(); s.tick(3)
	check(count(s, "result") == 0 and not s.drag.active(), "ordinary release cannot resurrect cancelled original")
	# A whole-stack hold has no paused original; it is validated directly.
	s = make(2); work = assemble(s, ["wood", "coin", "coin"], 9.5)
	s.drag.begin(work.ids[0])
	check(s.buy_pack("pack") > 0 and work.stack.recipe_guid.is_empty() and s.drag.active(), "whole-stack held purchase cancels invalid inputs without consuming pointer grant")
	s.drag.finish_standard(); s.tick(1)
	check(count(s, "result") == 0, "whole-stack release cannot complete spent recipe")

func test_selling_callback() -> void:
	var s = make(2)
	s.catalog.data.encounters = [{"guid": "arrival", "fields": {"id": "arrival", "type": 0, "dayValue": 1, "chance": 1.0, "count": 1, "maxCardsOnBoardLimit": 3, "oneTimeOnly": true, "cardToSpawn": {"guid": "visitor"}}}]
	s.catalog.data.scenes = [{"name": "Main", "documents": [{"script_class": "EncounterManager", "fields": {"allEncounters": [{"guid": "arrival"}]}}]}]
	s.catalog.configure(s.catalog.data); s.configure(s.catalog, 887)
	var work := assemble(s, ["wood", "coin", "coin"], 9.5)
	s.phase = "selling"; s.paused = true
	var events: Array = []
	var observed: Array = []
	var on_event := func(kind, _payload):
		events.append(kind)
		if kind == "encounter":
			observed.append([count(s, "pack"), work.stack.recipe_guid.is_empty(), s.stats().currency, s.phase])
			s._notify_stats_changed()
	s.event_occurred.connect(on_event)
	check(s.buy_pack("pack") > 0, "purchase still completes in selling phase")
	check(observed == [[1, true, 0, "encounter"]], "final stats callback sees purchased pack and validated recipe before one encounter selection")
	check(events[0] == "pack_purchased" and events.count("encounter") == 1 and count(s, "visitor") == 1, "purchase precedes synchronous encounter callbacks with no duplicate selection")
	CycleDriver.drain(s)
	check(s.phase == "ready" and s.world.completed_encounters.has("arrival"), "encounter remains completable after purchase callback")
	s.event_occurred.disconnect(on_event)
