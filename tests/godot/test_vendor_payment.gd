extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func make(price: int = 3):
	var catalog := Catalog.new()
	var rows: Array = []
	for pair in [["coin", 7], ["coral", 7], ["fake", 1], ["chest", 8]]:
		rows.append({"guid": pair[0], "name": pair[0], "script_class": "ChestDefinition" if pair[0] == "chest" else "CardDefinition", "fields": {"id": pair[0], "category": pair[1], "capacity": 20}})
	catalog.configure({"cards": rows, "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "category": 0, "buyPrice": price, "minQuests": 0, "slots": []}}], "scenes": [{"name": "Main", "documents": [{"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}]}]})
	var session := Session.new()
	session.configure(catalog, 8)
	return session
func payment_stack(session, guids: Array, stored: int = 0) -> Dictionary:
	var ids: Array = []
	var stack_id := -1
	for guid in guids:
		var id: int = session.spawn_card(guid, Vector2.ZERO, stack_id)
		ids.append(id)
		stack_id = session.cards[id].stack_id
		if guid == "chest" or guid == "fake": session.cards[id].stored_coins = stored
	return {"id": stack_id, "cards": ids}
func _init() -> void:
	var session = make()
	var stack := payment_stack(session, ["coin"])
	var events: Array = []
	var on_event := func(kind, _payload): events.append(kind)
	session.event_occurred.connect(on_event)
	var state: int = session.rng.state
	var result: Dictionary = session.pay_vendor("pack", stack.id)
	check(result.accepted and result.paid == 1 and result.pack_id == -1 and result.terminal, "Partial coin installment empties stack and is terminal")
	check(session.vendor_payments.pack == 1 and not session.stacks.has(stack.id), "Partial payment retained, empty stack removed")
	check(events == ["stats_changed"] and session.rng.state == state, "Partial emits only final stats, no RNG")
	stack = payment_stack(session, ["coin", "coral", "coin"])
	events.clear()
	result = session.pay_vendor("pack", stack.id)
	check(result.accepted and result.paid == 0 and result.pack_id > 0 and not result.terminal, "Remaining price purchase preserves excess card")
	check(session.cards.has(stack.cards[0]) and not session.cards.has(stack.cards[1]) and not session.cards.has(stack.cards[2]), "Payment consumes last-first including foreign Currency")
	check(events == ["pack_purchased", "stats_changed"], "Pack purchased event precedes final stats, no card-created for pack")
	session.event_occurred.disconnect(on_event)

	session = make()
	stack = payment_stack(session, ["coin", "chest"], 1)
	result = session.pay_vendor("pack", stack.id)
	check(result.accepted and result.paid == 1 and not result.terminal and result.pack_id == -1, "Empty last chest stops partial payment")
	check(session.cards.has(stack.cards[0]) and session.cards[stack.cards[1]].stored_coins == 0, "Earlier coin remains behind empty chest")

	session = make()
	stack = payment_stack(session, ["chest", "coin"], 4)
	session.stacks[stack.id].recipe_guid = "test-craft"
	session.stacks[stack.id].progress = 2
	result = session.pay_vendor("pack", stack.id)
	check(result.pack_id > 0 and not result.terminal and session.cards[stack.cards[0]].stored_coins == 2, "Last coin then earlier chest covers remaining price")
	check(session.stacks[stack.id].recipe_guid.is_empty(), "Consumed coin cancels dropped craft")

	session = make()
	stack = payment_stack(session, ["chest"], 8)
	result = session.pay_vendor("pack", stack.id)
	check(result.pack_id > 0 and not result.terminal and session.cards[stack.cards[0]].stored_coins == 5, "Chest purchase remains nonterminal")

	session = make()
	stack = payment_stack(session, ["coin", "fake"], 12)
	var before := Codec.capture(session)
	check(not session.pay_vendor("pack", stack.id).accepted and Codec.capture(session) == before, "Fake stored balance cannot impersonate chest; atomic rejection")
	stack = payment_stack(session, ["coin", "chest"], 0)
	before = Codec.capture(session)
	check(not session.pay_vendor("pack", stack.id).accepted and Codec.capture(session) == before, "Whole stack containing empty chest rejected")
	check(not session.pay_vendor("missing", stack.id).terminal and not session.pay_vendor("pack", -99).accepted, "Invalid target reports nonterminal rejection")
	session.catalog.fields("pack").minQuests = 1
	before = Codec.capture(session)
	check(not session.pay_vendor("pack", stack.id).accepted and Codec.capture(session) == before, "Locked vendor quest gate preserved")

	session = make(0)
	stack = payment_stack(session, ["coin"])
	events.clear()
	session.event_occurred.connect(on_event)
	result = session.pay_vendor("pack", stack.id)
	check(result.pack_id > 0 and not result.terminal and session.cards.has(stack.cards[0]), "Free purchase leaves payment intact")
	check(events == ["pack_purchased"], "Free purchase has no fabricated stats notification")
	session.event_occurred.disconnect(on_event)

	session = make()
	stack = payment_stack(session, ["chest"], 8)
	session.world.currency_guid = ""
	result = session.pay_vendor("pack", stack.id)
	check(result.accepted and result.paid == 0 and result.pack_id == -1 and not result.terminal and session.cards[stack.cards[0]].stored_coins == 8, "Source withdrawal requires resolved currency even after chest validation")

	# Hook observes a completed payment before factory resolution; result evaluates
	# the retained original stack object AFTER hook-driven interactions finish.
	session = make(2)
	stack = payment_stack(session, ["coin", "coin", "coin"])
	var hook_calls: Array = []
	var live = session
	var dropped_id: int = stack.id
	var retained_coin: int = stack.cards[0]
	var resolver := func():
		hook_calls.append(live.stacks.has(dropped_id) and live.stacks[dropped_id].card_ids == [retained_coin])
		# Stand-in for a synchronous factory/board interaction consuming the tail.
		live._remove_card(retained_coin)
	session.spawn_layout_resolver = resolver
	result = session.pay_vendor("pack", stack.id)
	check(hook_calls == [true] and result.pack_id > 0, "Pack uses central factory after currency consumption")
	check(result.terminal and not session.stacks.has(stack.id), "Terminal is evaluated after factory callback, not cached before it")
	session.spawn_layout_resolver = Callable()
	print("Vendor payment: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
