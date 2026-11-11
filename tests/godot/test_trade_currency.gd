extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Spawn = preload("res://scripts/model/scene_spawn.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _init() -> void:
	var fixture := Catalog.new()
	fixture.configure({"cards": [
		{"guid": "coin", "name": "Coin", "script_class": "CardDefinition", "fields": {"category": 7, "displayName": "Coin"}},
		{"guid": "wood", "script_class": "CardDefinition", "fields": {"category": 1, "sellPrice": 1}}]})
	var fake := Session.new()
	fake.configure(fixture)
	var id := fake.spawn_card("wood", Vector2(2, 3))
	check(fake.sell_card(id), "Sceneless fixture retains legacy Coin adapter")
	check(fake.cards.values()[0].definition_guid == "coin" and fake.cards.values()[0].position == Vector2(2, 3), "Fixture payout position remains explicit fallback")
	fixture.data.scenes = [{"name": "Main", "documents": []}]
	fake = Session.new()
	fake.configure(fixture)
	id = fake.spawn_card("wood")
	var before := Codec.capture(fake)
	check(not fake.sell_card(id) and Codec.capture(fake) == before, "Scene present but unresolved currency rejects atomically")
	var catalog := Catalog.new()
	if catalog.load_file() != OK:
		print("Trade currency: %d/%d synthetic passed; source data unavailable" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	for scene_name in ["Main", "Island"]:
		var session := Session.new()
		session.configure(catalog, 123, scene_name)
		var expected_currency := catalog.find_by_name("Coin" if scene_name == "Main" else "Coral")
		check(session.world.currency_guid == expected_currency, scene_name + " resolved source currency")
		var expected_position := Vector2(-4.4 if scene_name == "Main" else -0.55, 1.85)
		check(Spawn.buyer_position(catalog, scene_name).is_equal_approx(expected_position), scene_name + " serialized buyer is zone zero")
		session.board_bounds = Rect2(-12, -8, 24, 16)
		expected_position.y = 5.85
		check(Spawn.buyer_position(catalog, scene_name, session.board_bounds).is_equal_approx(expected_position), scene_name + " expanded board buyer")
		var wood: String = catalog.find_by_name("Wood")
		id = session.spawn_card(wood, Vector2(0, -3), -1, {"refuse_attach": true})
		var events: Array = []
		var state: int = session.rng.state
		var on_event := func(kind, payload):
			if kind == "cards_sold":
				events.append({"kind": kind, "ids_present": session.cards.has(id), "guids": payload.base_definition_guids.duplicate()})
			else:
				events.append({"kind": kind})
		session.event_occurred.connect(on_event)
		check(session.sell_card(id), scene_name + " sale accepted")
		check(not session.cards.has(id), scene_name + " sold card removed")
		check(events[0].kind == "cards_sold" and events[0].ids_present and events[0].guids == [wood], scene_name + " sale event before destruction preserves identities")
		check(events[-1].kind == "stats_changed", scene_name + " final stats notification preserved")
		var count := 0
		for card in session.cards.values():
			check(card.definition_guid == expected_currency, scene_name + " payout uses actual currency")
			check(session.stacks[card.stack_id].position.is_equal_approx(expected_position), scene_name + " payout at buyer rather than sold position")
			count += 1
		check(count == int(catalog.fields(wood).get("sellPrice", 1)), scene_name + " source sell value")
		check(session.rng.state == state, scene_name + " sale does not draw RNG")
		# Validate before any mutation/event: invalid references, nonempty chest, unsellable.
		id = session.spawn_card(wood, Vector2.ZERO, -1, {"refuse_attach": true})
		before = Codec.capture(session)
		events.clear()
		check(not session._sell_cards([id, -999]) and Codec.capture(session) == before and events.is_empty(), scene_name + " mixed invalid batch atomic")
		session.cards[id].stored_coins = 1
		before = Codec.capture(session)
		check(not session.sell_card(id) and Codec.capture(session) == before and events.is_empty(), scene_name + " nonempty storage atomic")
		session.cards[id].stored_coins = 0
		var fields: Dictionary = catalog.fields(wood)
		var original_sellable: Variant = fields.get("isSellable", true)
		fields.isSellable = false
		before = Codec.capture(session)
		check(not session.sell_card(id) and Codec.capture(session) == before and events.is_empty(), scene_name + " unsellable atomic")
		fields.isSellable = original_sellable
		var valid_currency: String = session.world.currency_guid
		for invalid_currency in ["", "not-a-definition", wood]:
			session.world.currency_guid = invalid_currency
			before = Codec.capture(session)
			check(not session.sell_card(id) and Codec.capture(session) == before and events.is_empty(), scene_name + " invalid real currency never falls back")
		session.world.currency_guid = valid_currency
		# Broken parent chain must not silently pay at an invented origin.
		var transform_fields: Dictionary = {}
		for scene in catalog.data.scenes:
			if scene.name != scene_name: continue
			for document in scene.documents:
				if document.get("file_id", "") == "866460967": transform_fields = document.fields
		var old_parent: Variant = transform_fields.m_Father
		transform_fields.m_Father = {"fileID": "unknown-parent"}
		before = Codec.capture(session)
		check(not session.sell_card(id) and Codec.capture(session) == before and events.is_empty(), scene_name + " unresolved buyer placement atomic")
		transform_fields.m_Father = old_parent
		session.event_occurred.disconnect(on_event)
	check(Spawn.buyer_position(catalog, "missing") == null, "Missing buyer scene explicit")
	print("Trade currency: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
