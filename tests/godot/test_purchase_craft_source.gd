extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Spawn = preload("res://scripts/model/scene_spawn.gd")
var catalog = Catalog.new()
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func session(scene: String = "Main"):
	var s = Session.new(); s.configure(catalog, 887, scene)
	# Source vendor gates use real completed Quest IDs, never a fabricated count.
	for id in s.quest_tracker.definitions: s.quest_tracker.completed_ids[id] = true
	return s

func chest_recipe(s) -> Dictionary:
	var wood: int = s.spawn_card(catalog.find_by_name("Wood"), Vector2.ZERO)
	var stack = s.stacks[s.cards[wood].stack_id]
	var ids: Array = [wood]
	for guid in [catalog.find_by_name("Wood"), s.world.currency_guid, s.world.currency_guid]:
		var id: int = s.spawn_card(guid, Vector2(4, 0))
		ids.append(id)
		check(s.move_to_stack(id, stack.id), s.scene_name + " actual recipe ingredient legally joins")
	check(catalog.ref_guid(catalog.fields(stack.recipe_guid).get("resultingCard", {})) == catalog.find_by_name("Wooden Chest"), s.scene_name + " actual currency recipe selects Wooden Chest")
	check(s.matches_recipe(stack, catalog.fields(stack.recipe_guid)) and float(catalog.fields(stack.recipe_guid).craftingDuration) == 10, s.scene_name + " source task is valid and takes ten seconds")
	stack.progress = 5
	return {"stack": stack, "ids": ids}

func encoded(s) -> String:
	return JSON.stringify(Codec.capture(s), "", true, true)

func count(s, guid: String) -> int:
	var total := 0
	for card in s.cards.values():
		if card.base_definition_guid == guid: total += 1
	return total

func reload(s):
	var loaded = session(s.scene_name)
	check(Codec.restore(loaded, JSON.parse_string(encoded(s))).ok, "actual post-purchase checkpoint restores")
	return loaded

func _init() -> void:
	check(catalog.load_file() == OK, "locked private source catalog loads")
	if catalog.data.is_empty(): quit(1); return
	for scene in ["Main", "Island"]:
		var s = session(scene)
		var work := chest_recipe(s)
		var offer: String = catalog.find_by_name("01_Pack_Beginning" if scene == "Main" else "11_Pack_Survival", "packs")
		check(int(catalog.fields(offer).buyPrice) == 3, scene + " actual offer costs three")
		var before: String = encoded(s)
		check(s.buy_pack(offer) == -1 and encoded(s) == before, scene + " two required crafting coins cannot cover price; rejection is atomic")
		s.spawn_card(s.world.currency_guid, Vector2(6, 0))
		var events: Array = []
		var on_event := func(kind, _payload): events.append(kind)
		s.event_occurred.connect(on_event)
		var state: int = s.rng.state
		var knowledge: Dictionary = s.discovered_recipes.duplicate()
		var bought: int = s.buy_pack(offer)
		check(bought > 0 and s.cards[bought].position == Spawn.vendor_position(catalog, scene, offer), scene + " purchase uses actual vendor placement")
		check(work.stack.recipe_guid.is_empty() and work.stack.progress == 0 and work.stack.card_ids == work.ids.slice(0, 2), scene + " spending recipe currency immediately stops Wooden Chest and leaves both Wood cards")
		check(events == ["pack_purchased", "stats_changed"] and s.rng.state == state and s.discovered_recipes == knowledge, scene + " purchase retains event/RNG/discovery order")
		var loaded = reload(s)
		s.tick(6); loaded.tick(6)
		check(count(s, offer) == 1 and count(s, catalog.find_by_name("Wooden Chest")) == 0 and count(s, catalog.find_by_name("Wood")) == 2, scene + " formerly failing six-second continuation produces no free chest")
		check(encoded(s) == encoded(loaded), scene + " restored next tick exactly matches live result")
		s.event_occurred.disconnect(on_event)

	# Keep the same legitimate source recipe; pre-fund from a real full chest
	# inserted earlier, so its ingredients are never used as payment.
	var s = session()
	var chest_guid: String = catalog.find_by_name("Wooden Chest")
	var chest: int = s.spawn_card(chest_guid)
	var capacity: int = int(catalog.fields(chest_guid).capacity)
	s.cards[chest].stored_coins = capacity
	var work := chest_recipe(s)
	var offer: String = catalog.find_by_name("01_Pack_Beginning", "packs")
	var original: String = work.stack.recipe_guid
	check(s.buy_pack(offer) > 0 and s.cards[chest].stored_coins == capacity - 3, "actual full chest covers purchase without spending recipe coins")
	check(work.stack.recipe_guid == original and work.stack.progress == 5 and work.stack.card_ids == work.ids, "untouched actual recipe preserves exact progress")
	var loaded = reload(s)
	s.tick(6); loaded.tick(6)
	check(count(s, chest_guid) == 2 and count(s, offer) == 1 and encoded(s) == encoded(loaded), "lawful chest-funded recipe still completes once across save/load")

	# The source pointer split pauses the old recipe while its two coins are held.
	s = session(); work = chest_recipe(s)
	s.spawn_card(s.world.currency_guid)
	s.drag.begin(work.ids[2])
	check(s.buy_pack(offer) > 0 and work.stack.paused and s.drag.active(), "actual purchase can spend held coins without silently consuming pointer lifecycle")
	loaded = reload(s)
	check(loaded.stacks[work.stack.id].recipe_guid.is_empty() and not loaded.drag.active(), "actual held post-purchase save cannot retain an orphan chest task")
	s.drag.finish_standard(); s.tick(6); loaded.tick(6)
	check(count(s, chest_guid) == 0 and encoded(s) == encoded(loaded), "actual held ordinary release and restored next tick cannot double-spend")
	print("Source purchase craft checks: %d passed / %d total" % [checks - failures, checks])
	quit(1 if failures else 0)
