extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class CombatClockSpy extends RefCounted:
	var calls: Array = []
	var order: Array = []
	var membership: Dictionary = {}
	var dragged: Dictionary = {}
	func tick(scaled: float, real: float) -> void:
		order.append("combat")
		calls.append(Vector2(scaled, real))

class AIClockSpy extends RefCounted:
	var order: Array = []
	func tick(_scaled: float) -> void:
		order.append("ai")

var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func make():
	var catalog := Catalog.new()
	var rules: Array = []
	rules.resize(144)
	rules.fill(1)
	catalog.configure({"cards": [
		{"guid": "base", "script_class": "CardDefinition", "fields": {"id": "base", "category": 1}},
		{"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero", "category": 2, "faction": 1, "loot": [{"Card": {"guid": "loot"}, "Weight": 1}]}},
		{"guid": "loot", "script_class": "CardDefinition", "fields": {"id": "loot", "category": 1}},
		{"guid": "seed", "script_class": "CardDefinition", "fields": {"id": "seed", "category": 3}},
		{"guid": "grower", "script_class": "GrowerDefinition", "fields": {"id": "grower", "category": 6, "hasDurability": true, "uses": 1}},
		{"guid": "chest", "script_class": "ChestDefinition", "fields": {"id": "chest", "category": 8, "capacity": 1}},
		{"guid": "coin", "script_class": "CardDefinition", "fields": {"id": "coin", "category": 7}}],
		"packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "category": 0, "slots": [{"Entries": [{"Card": {"guid": "loot"}, "Weight": 1}]}]}}],
		"settings": [{"guid": "settings", "script_class": "CardSettings", "fields": {"stackStep": {"x": 0, "y": 0.002, "z": -0.18}, "margin": {"x": 0.1}}}, {"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}],
		"referenced_prefabs": [{"guid": "seed-prefab", "documents": [{"object_type": "BoxCollider", "fields": {"m_Size": {"x": 0.8}}}]}],
		"scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"defaultSpawnCards": [], "cardSettings": {"guid": "settings"}, "cardPrefabs": [{"category": 3, "prefab": {"guid": "seed-prefab"}}]}}, {"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}]}]})
	var session := Session.new()
	session.configure(catalog, 21)
	return session
func group(session, names: Array, position: Vector2 = Vector2(2, 3)) -> Array:
	var ids: Array = []
	var stack_id := -1
	for name in names:
		var id: int = session.spawn_card(name, position, stack_id)
		ids.append(id)
		stack_id = session.cards[id].stack_id
	return ids
func _init() -> void:
	var session = make()
	var ids := group(session, ["base", "base", "hero"])
	var events: Array = []
	var observer := func(kind, _payload): events.append(kind)
	session.event_occurred.connect(observer)
	var rng := RandomNumberGenerator.new()
	rng.state = session.rng.state
	rng.randi_range(0, 0)
	check(session.kill_card(ids[2]), "Kill stacked character")
	var loot = session.cards.values()[-1]
	check(loot.definition_guid == "loot" and loot.position.is_equal_approx(Vector2(2, 2.64)), "Death loot starts at individual target")
	check(events[0] == "card_killed" and events.has("card_created"), "Existing kill then loot-created ordering preserved")
	check(session.rng.state == rng.state, "Death pose lookup adds no random draws")
	session.event_occurred.disconnect(observer)
	# Notification cleanup can alter membership; the capture must precede it.
	session = make()
	ids = group(session, ["base", "base", "hero"])
	var live = session
	var before_id: int = ids[0]
	var cleanup := func(kind, _payload):
		if kind == "card_killed": live._remove_card(before_id)
	session.event_occurred.connect(cleanup)
	session.kill_card(ids[2])
	check(session.cards.values()[-1].position.is_equal_approx(Vector2(2, 2.64)), "Death pose survives notification-driven reindexing")
	session.event_occurred.disconnect(cleanup)

	for consume_mode in [1, 0]:
		session = make()
		ids = group(session, ["base", "grower", "seed", "base"])
		var old_stack = session.stacks[session.cards[ids[0]].stack_id]
		var recipe := {"resultingCard": {"guid": "seed"}, "requiredIngredients": [{"card": {"guid": "grower"}, "count": 1, "consumptionMode": consume_mode}]}
		Special._grow(session, old_stack, recipe)
		var seed_stack = session.stacks[session.cards[ids[2]].stack_id]
		check(seed_stack != old_stack and seed_stack.position.is_equal_approx(Vector2(2.9, 2.64)), "Growth split preserves pre-consumption seed pose plus source width")
		check(seed_stack.card_ids == ids.slice(2), "Growth transfers complete seed tail")
		check(session.card_target_position(ids[3]).is_equal_approx(Vector2(2.9, 2.46)), "Seed tail derives offsets exactly once")
		check(session.cards.values()[-1].definition_guid == "seed" and session.cards.values()[-1].position == Vector2(2, 3), "Grown output intentionally stays crafting-root based")
		check(session.cards.has(ids[1]) == (consume_mode == 1), "Grower consumption behavior preserved")
		var snapshot := Codec.capture(session)
		var restored = make()
		check(Codec.restore(restored, snapshot).ok and Codec.capture(restored) == snapshot, "Growth pose remains compatible with unchanged save schema")
	session = make()
	ids = group(session, ["grower", "seed"])
	var old_stack = session.stacks[session.cards[ids[0]].stack_id]
	Special._grow(session, old_stack, {"resultingCard": {"guid": "seed"}, "requiredIngredients": [{"card": {"guid": "grower"}, "count": 1, "consumptionMode": 0}]})
	check(session.cards[ids[1]].stack_id == old_stack.id, "Source SplitAt still refuses index zero after grower removal")

	session = make()
	ids = group(session, ["base", "coin", "coin"], Vector2(5, 6))
	var chest: int = session.spawn_card("chest", Vector2(10, 0))
	check(session.move_to_stack(ids[1], session.cards[chest].stack_id), "Tail currency drop on limited chest accepted")
	check(not session.cards.has(ids[1]) and session.cards.has(ids[2]) and session.cards[chest].stored_coins == 1, "Chest partial deposit preserves leftover tail")
	check(session.stacks[session.cards[ids[2]].stack_id].position.is_equal_approx(Vector2(5, 5.82)), "Leftover tail starts at dragged member pose, not old stack root")
	# Source packs deliberately spawn from Stack.TargetPosition, even if stacked.
	session = make()
	ids = group(session, ["base", "pack"])
	var opened: int = session.open_pack(ids[1])
	check(opened > 0 and session.cards[opened].position == Vector2(2, 3), "Pack draw keeps intentional root spawn")
	# Test the Session clock bridge independently of combat action sequencing.
	session = make()
	var clock_spy := CombatClockSpy.new()
	var ai_spy := AIClockSpy.new()
	ai_spy.order = clock_spy.order
	session.combat = clock_spy
	session.ai = ai_spy
	session.paused = true
	session.tick(0.25)
	check(clock_spy.calls == [Vector2(0, 0.25)] and session.elapsed == 0 and clock_spy.order == ["combat"], "Paused Session advances real combat clock without AI")
	session.paused = false
	session.phase = "feeding"
	session.tick(0.5)
	check(clock_spy.calls[-1] == Vector2(0, 0.5) and session.elapsed == 0 and clock_spy.order == ["combat", "combat"], "Day-cycle pause advances combat without AI")
	session.phase = "playing"
	session.speed = 2
	session.tick(0.2)
	check(clock_spy.calls[-1] == Vector2(0.4, 0.2) and is_equal_approx(session.elapsed, 0.4) and clock_spy.order == ["combat", "combat", "ai", "combat"], "Playing preserves AI then combat order with separate clocks")
	session.tick(0)
	check(clock_spy.calls.size() == 3 and clock_spy.order.size() == 4, "Zero delta dispatches neither AI nor combat")
	print("Individual pose spawns: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
