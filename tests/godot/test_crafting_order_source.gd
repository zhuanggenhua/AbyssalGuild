extends SceneTree
## Private catalog probes use legal assembly and elapsed ticks, never injected
## crafting timers, task IDs, quest completion state or altered source recipes.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func make(seed: int = 115):
	var c = Catalog.new()
	if c.load_file() != OK: return null
	var s = Session.new(); s.configure(c, seed)
	return s

func find_card(s, name: String) -> int:
	var guid: String = s.catalog.find_by_name(name)
	for card in s.cards.values():
		if card.base_definition_guid == guid: return card.id
	return -1

func spawn(s, name: String, position: Vector2 = Vector2.ZERO) -> int:
	return s.spawn_card(s.catalog.find_by_name(name), position)

func base(s, name: String, position: Vector2):
	return s.stacks[s.cards[spawn(s, name, position)].stack_id]

func assemble(s, stack) -> int:
	var worker: int = spawn(s, "Villager", stack.position + Vector2(2, 0))
	check(s.move_to_stack(worker, stack.id), "actual villager joins ingredient")
	return worker

func pair(s, name: String, position: Vector2):
	var stack = base(s, name, position)
	assemble(s, stack)
	return stack

func ticks(s, frames: int) -> void:
	for _i in frames: s.tick(1.0 / 60.0)

func listen(s) -> Array:
	var events: Array = []
	var weak = weakref(s)
	s.event_occurred.connect(func(kind, payload):
		if kind == "crafted": events.append(weak.get_ref().catalog.fields(payload.definition_guid).displayName))
	return events

func encoded(s) -> String:
	return JSON.stringify(Codec.capture(s), "", true, true)

func quest(s, number: int) -> String:
	return str(s.catalog.fields(s.catalog.find_by_name("introduction_%02d" % number, "quests")).id)

func active_amount(s, id: String) -> int:
	for item in s.quest_tracker.active_quests:
		if item.id == id: return item.current_amount
	return -1

func _init() -> void:
	if make() == null:
		printerr("FAIL: Private source catalog required for crafting order probes")
		quit(1); return
	test_original_reproduction()
	test_quest_credit()
	test_spawn_callback()
	test_native_checkpoint()
	test_travel_order()
	print("Source crafting activation order: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func test_original_reproduction() -> void:
	var s = make(); s.set_paused(true)
	var wood = pair(s, "Wood", Vector2(-4, 0))
	var timber = pair(s, "Timber", Vector2(4, 0))
	check(s.catalog.get_definition(wood.recipe_guid).name == "Recipe_Timber" and s.catalog.get_definition(timber.recipe_guid).name == "Recipe_WoodenStick", "actual source recipes selected")
	var events := listen(s)
	s.set_paused(false); ticks(s, 601)
	check(events == ["Wooden Stick", "Timber"], "audit reproduction completes in reverse activation order after 601 fixed ticks")
	# Deliberately make activation order disagree with registered stack order.
	s = make(); s.set_paused(true)
	wood = base(s, "Wood", Vector2(-4, 0)); timber = base(s, "Timber", Vector2(4, 0))
	assemble(s, timber); assemble(s, wood)
	events = listen(s); s.set_paused(false); ticks(s, 601)
	check(events == ["Timber", "Wooden Stick"], "reversing stack registration alone cannot implement source activation order")

func reach_timber_quest():
	var s = make()
	var pack: int = s.start_new_game()
	for _i in 4: s.open_pack(pack)
	check(s.quest_tracker.completed_ids.has(quest(s, 1)), "real starter opening completes intro 1")
	var villager: int = find_card(s, "Villager")
	var bush: int = find_card(s, "Berry Bush")
	check(s.move_to_stack(villager, s.cards[bush].stack_id), "real harvest recipe discovery")
	check(s.quest_tracker.completed_ids.has(quest(s, 2)), "real harvest discovery completes intro 2")
	var rock: int = find_card(s, "Rock")
	check(s.move_to_stack(villager, s.cards[rock].stack_id), "villager leaves bush and starts mining")
	ticks(s, 601)
	var stone: int = find_card(s, "Stone")
	check(stone > 0 and s.quest_tracker.completed_ids.has(quest(s, 3)), "actual mining completion unlocks selling")
	check(s.sell_card(stone) and s.quest_tracker.completed_ids.has(quest(s, 4)), "actual sale completes intro 4")
	spawn(s, "Coin"); spawn(s, "Coin")
	check(s.buy_pack(s.catalog.find_by_name("01_Pack_Beginning", "packs")) > 0 and s.quest_tracker.completed_ids.has(quest(s, 5)), "real purchase completes intro 5")
	var tree: int = spawn(s, "Tree", Vector2(8, 0))
	check(s.move_to_stack(villager, s.cards[tree].stack_id), "villager leaves mining and starts logging")
	ticks(s, 601)
	check(s.quest_tracker.completed_ids.has(quest(s, 6)) and active_amount(s, quest(s, 7)) == 0, "actual logging opens Get Timber with no fabricated quest state")
	s.split_stack(villager, Vector2(12, 0))
	return s

func test_quest_credit() -> void:
	var s = reach_timber_quest()
	s.set_paused(true)
	pair(s, "Wood", Vector2(-4, 8)); pair(s, "Timber", Vector2(4, 8))
	var events := listen(s)
	s.set_paused(false); ticks(s, 601)
	check(events == ["Wooden Stick", "Timber"], "real intro quest receives source-ordered completions")
	check(s.quest_tracker.completed_ids.has(quest(s, 7)) and not s.quest_tracker.completed_ids.has(quest(s, 8)), "Get Timber completes but earlier stick cannot retroactively complete successor")
	check(active_amount(s, quest(s, 8)) == 0, "new Get a Stick quest has zero credit for earlier same-frame event")
	pair(s, "Timber", Vector2(12, 8)); ticks(s, 601)
	check(s.quest_tracker.completed_ids.has(quest(s, 8)), "later genuine stick craft completes successor normally")

func test_spawn_callback() -> void:
	var s = make()
	var idle: int = spawn(s, "Soil", Vector2(4, 0))
	var target: int = s.cards[idle].stack_id
	var gathering = pair(s, "Berry Bush", Vector2(-4, 0))
	var berry_guid: String = s.catalog.find_by_name("Berry")
	var weak = weakref(s)
	s.spawn_target_selector = func(id, _ignored):
		return target if weak.get_ref().cards[id].definition_guid == berry_guid else -1
	var events := listen(s)
	for _frame in 610:
		s.tick(1.0 / 60.0)
		if not events.is_empty(): break
	var next = s.stacks[target]
	check(events == ["Berry"] and s.catalog.get_definition(next.recipe_guid).get("name") == "Recipe_BerryBush", "actual output attachment starts next recipe in completion callback")
	check(next.progress == 0, "callback-created craft on older registered stack gets no current-frame delta")
	# Stop the existing gather task using a real split, then advance growth normally.
	s.split_stack(gathering.card_ids.back(), Vector2(-8, 0))
	var duration: float = float(s.catalog.fields(next.recipe_guid).get("craftingDuration", 0))
	check(duration > 0, "attached Berry selects a real positive-duration source growth recipe")
	s.spawn_target_selector = Callable()
	s.tick(duration)
	check(next.recipe_guid.is_empty() and events == ["Berry", "Berry Bush"], "new output-triggered work completes on its own future tick")

func test_native_checkpoint() -> void:
	var s = make(); s.set_paused(true)
	var wood = base(s, "Wood", Vector2(-4, 0)); var timber = base(s, "Timber", Vector2(4, 0))
	assemble(s, timber); assemble(s, wood)
	s.set_paused(false); ticks(s, 301)
	var before: String = encoded(s)
	var saved = make(999)
	check(Codec.restore(saved, JSON.parse_string(before)).ok and encoded(saved) == before, "real midpoint save preserves nonregistration activation order and exact model")
	var left := listen(s); var right := listen(saved)
	ticks(s, 300); ticks(saved, 300)
	check(left == ["Timber", "Wooden Stick"] and left == right and encoded(s) == encoded(saved), "actual fixed-tick checkpoint continuation preserves event order, IDs, quests and RNG")

func test_travel_order() -> void:
	var s = make()
	var timber = base(s, "Timber", Vector2(4, 0)); var wood = base(s, "Wood", Vector2(-4, 0))
	assemble(s, wood); assemble(s, timber)
	# Five elapsed seconds leave ordinary crafts halfway. Travel is selected last.
	s.tick(5)
	var portal = pair(s, "Grand Portal", Vector2(10, 0))
	var departure: Array = []
	var weak = weakref(s)
	s.campaign.before_travel = func():
		departure.append(JSON.parse_string(JSON.stringify(weak.get_ref().campaign.capture(), "", true, true)))
		return {"ok": true}
	var events := listen(s)
	s.tick(5)
	check(s.scene_name == "Island" and s.elapsed == 0 and events.is_empty(), "newest travel completes before older ready crafts and stops old cursor")
	check(departure.size() == 1 and departure[0].current_scene == "Main", "departure callback captures complete travel task before transition")
	var old: Dictionary = s.campaign.saved_scenes.Main.session
	check(old.crafting.activation_order == [wood.id, timber.id] and old.stacks[0].progress == 5 and old.stacks[1].progress == 5, "inactive scene retains surviving task order and unticked five-second timers")
	var restored = make(77)
	check(restored.campaign.restore(JSON.parse_string(JSON.stringify(s.campaign.capture(), "", true, true))).ok, "campaign restores independent scene task orders")
	# Return via legal new ingredients; the destination's saved tasks remain frozen.
	pair(s, "Grand Portal", Vector2(15, 0)); pair(restored, "Grand Portal", Vector2(15, 0))
	var restored_events := listen(restored)
	s.tick(5); restored.tick(5)
	check(s.scene_name == "Main" and restored.scene_name == "Main" and s.stacks[wood.id].progress == 5, "return travel restores old tasks without ticking destination during transition")
	s.tick(5); restored.tick(5)
	check(events == ["Wooden Stick", "Timber"] and restored_events == events, "returned tasks complete in preserved activation order")
	check(JSON.stringify(s.campaign.capture(), "", true, true) == JSON.stringify(restored.campaign.capture(), "", true, true), "campaign continuation preserves both scene snapshots and RNG")
	# Loading the departure checkpoint must execute that same completed travel once.
	var resumed = make(8)
	check(resumed.campaign.restore(departure[0]).ok, "departure callback snapshot restores completed travel identity")
	resumed.set_paused(true)
	resumed.tick(1.0 / 60.0)
	check(resumed.scene_name == "Island" and resumed.elapsed == 0, "completed departure checkpoint travels once even paused without advancing new scene")
	check(resumed.campaign.saved_scenes.Main.session.crafting.activation_order == [wood.id, timber.id], "checkpoint replay retains surviving task order")
	check(not s.stacks.has(portal.id), "travel source stack no longer exists")
	s.campaign.before_travel = Callable()
