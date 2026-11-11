extends SceneTree
const Order = preload("res://scripts/model/crafting_order.gd")
const Stack = preload("res://scripts/model/stack.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0

class Model:
	extends RefCounted
	var stacks := {}
	var catalog = Catalog.new()
	var scene_name := "Main"
	var crafting = Order.new()
	var finished: Array = []
	var callback: Callable
	func _init() -> void:
		catalog.configure({"recipes": [{"guid": "job", "fields": {"craftingDuration": 1.0}}]})
		crafting.configure(self)
	func _complete_recipe(stack) -> void:
		finished.append(stack.id)
		stack.cancel_craft()
		if callback.is_valid(): callback.call(stack)
	func add(id: int):
		var stack = Stack.new(id)
		stacks[id] = stack
		return stack
	func start(stack) -> void:
		stack.recipe_guid = "job"
		stack.progress = 0
		crafting.activate(stack)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func encoded(s) -> String:
	return JSON.stringify(Codec.capture(s), "", true, true)

func _init() -> void:
	test_helper()
	test_actual_selection()
	test_callback_activation()
	test_weighted_repeats()
	test_save_order()
	test_held_order()
	test_paused_clock()
	print("Crafting activation order: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func test_helper() -> void:
	var m = Model.new()
	var a = m.add(1); var b = m.add(2); var c = m.add(3)
	m.start(c); m.start(a); m.start(b)
	check(m.crafting.save_state().activation_order == [3, 1, 2], "activation differs from stack creation order")
	m.crafting.advance(1)
	check(m.finished == [2, 1, 3], "helper walks task activations newest first")
	check(m.crafting.save_state().activation_order.is_empty(), "completed entries removed")
	m.finished.clear(); m.start(c); m.start(a); m.start(b)
	a.paused = true
	m.crafting.advance(0.5)
	check(a.progress == 0 and b.progress == 0.5 and c.progress == 0.5, "task pause skips only its timer")
	a.paused = false; b.cancel_craft(); m.start(b)
	check(m.crafting.save_state().activation_order == [3, 1, 2], "resume retains order, replacement appended")
	m.crafting.advance(0.5)
	check(m.finished == [3] and a.progress == 0.5 and b.progress == 0.5, "cancellation cannot preserve old timer")
	m.crafting.advance(0.5)
	check(m.finished == [3, 2, 1], "resumed task keeps earlier activation")
	m.finished.clear(); m.start(a); m.start(b)
	m.callback = func(stack):
		if stack == b:
			a.cancel_craft(); m.start(a); m.start(c)
	m.crafting.advance(1)
	check(m.finished == [2] and a.progress == 0 and c.progress == 0, "callback replacement and new task do not tick in old cursor")
	check(m.crafting.save_state().activation_order == [1, 3], "callback-created tasks retain append order")
	m.callback = Callable(); m.crafting.advance(1)
	check(m.finished == [2, 3, 1], "callback tasks begin together next frame newest first")
	m.finished.clear(); m.start(a); m.start(b)
	m.callback = func(stack):
		if stack == b: m.stacks.erase(a.id)
	m.crafting.advance(1)
	check(m.finished == [2], "removed earlier stack cannot be advanced")
	m.callback = Callable(); m.stacks[a.id] = a; m.start(a)
	a.progress = 1.25; a.paused = true
	m.crafting.advance(0)
	check(m.finished == [2, 1], "already-complete paused task executes even with zero scaled delta")
	m.finished.clear(); m.start(a); m.start(b)
	m.callback = func(_stack): m.scene_name = "Island"
	check(m.crafting.advance(1) and m.finished == [2] and a.progress == 0, "travel exits old scene cursor immediately")
	m.callback = Callable()
	m.crafting.reset()
	check(m.crafting.save_state().activation_order.is_empty(), "reset discards previous activation list")

func card(guid: String, category: int = 0) -> Dictionary:
	return {"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid, "category": category, "maxHealth": 10}}

func recipe(guid: String, input: String, output: String, continuous: bool = false) -> Dictionary:
	return {"guid": guid, "script_class": "RecipeDefinition", "fields": {"id": guid, "craftingDuration": 1.0, "randomWeight": 1, "isContinuous": continuous, "requiredIngredients": [{"card": {"guid": input}, "count": 1, "consumptionMode": 1}, {"card": {"guid": "worker"}, "count": 1, "consumptionMode": 1}], "resultingCard": {"guid": output}}}

func make(recipes: Array = []):
	var c = Catalog.new()
	if recipes.is_empty(): recipes = [recipe("a", "a_in", "a_out"), recipe("b", "b_in", "b_out"), recipe("c", "c_in", "c_out")]
	var rules: Array = []; rules.resize(144); rules.fill(1)
	c.configure({"cards": [card("a_in"), card("b_in"), card("c_in"), card("worker", 2), card("a_out"), card("b_out"), card("c_out")], "recipes": recipes, "settings": [{"guid": "rules", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}]})
	var s = Session.new(); s.configure(c, 397)
	return s

func base(s, guid: String):
	var id: int = s.spawn_card(guid)
	return s.stacks[s.cards[id].stack_id]

func assemble(s, stack) -> int:
	var worker: int = s.spawn_card("worker")
	check(s.move_to_stack(worker, stack.id), "legal recipe assembly")
	return worker

func listen(s) -> Array:
	var result: Array = []
	s.event_occurred.connect(func(kind, payload):
		if kind == "crafted": result.append(payload.definition_guid))
	return result

func test_actual_selection() -> void:
	var s = make()
	var a = base(s, "a_in"); var b = base(s, "b_in"); var c = base(s, "c_in")
	s.set_paused(true)
	assemble(s, c); assemble(s, a); assemble(s, b)
	var events := listen(s)
	var state: int = s.rng.state
	s.tick(8)
	check(a.progress == 0 and b.progress == 0 and c.progress == 0 and events.is_empty(), "global pause preserves freshly activated zero-progress tasks")
	s.set_paused(false); s.tick(1)
	check(events == ["b_out", "a_out", "c_out"], "selection activation, not registration, determines completion")
	check(s.rng.state == state, "nonrepeating completion adds no scheduling RNG")
	check(s.crafting.save_state().activation_order.is_empty(), "ordinary completion cancels exact active identities")
	# Same logical stack is newest after cancellation and recipe reselection.
	s = make(); a = base(s, "a_in"); b = base(s, "b_in")
	var worker: int = assemble(s, a); assemble(s, b)
	var detached: int = s.split_stack(worker, Vector2.ONE)
	check(detached > 0 and a.recipe_guid.is_empty(), "real ingredient split cancels previous task")
	check(s.move_to_stack(worker, a.id), "replacement assembled on original stack")
	events = listen(s); s.tick(1)
	check(events == ["a_out", "b_out"], "replacement gets newest activation even on oldest stack")

func test_callback_activation() -> void:
	var s = make()
	var c = base(s, "c_in"); var a = base(s, "a_in"); var b = base(s, "b_in")
	assemble(s, a); assemble(s, b)
	var events := listen(s)
	var weak = weakref(s)
	var on_event := func(kind, payload):
		if kind == "crafted" and payload.definition_guid == "b_out": assemble(weak.get_ref(), c)
	s.event_occurred.connect(on_event)
	s.tick(1)
	check(events == ["b_out", "a_out"] and c.progress == 0, "completion callback activation cannot consume current frame")
	s.event_occurred.disconnect(on_event); s.tick(1)
	check(events == ["b_out", "a_out", "c_out"], "callback activation advances on next tick")
	# Repeating jobs reselect in completion order and reverse their next frame order.
	s = make([recipe("a", "a_in", "a_out", true), recipe("b", "b_in", "b_out", true)])
	a = base(s, "a_in"); b = base(s, "b_in"); assemble(s, a); assemble(s, b)
	events = listen(s)
	var expected = RandomNumberGenerator.new(); expected.state = s.rng.state
	expected.randf(); expected.randf()
	s.tick(1)
	check(events == ["b_out", "a_out"] and a.progress == 0 and b.progress == 0, "repeats have no leftover delta and wait next frame")
	check(s.crafting.save_state().activation_order == [b.id, a.id] and s.rng.state == expected.state, "repeat selection consumes exactly two existing weighted draws in completion order")
	expected.randf(); expected.randf(); s.tick(1)
	check(events == ["b_out", "a_out", "a_out", "b_out"] and s.rng.state == expected.state, "repeat activation changes next-frame order without extra RNG")

func test_save_order() -> void:
	var s = make([recipe("a", "a_in", "a_out", true), recipe("b", "b_in", "b_out", true)])
	var a = base(s, "a_in"); var b = base(s, "b_in")
	assemble(s, b); assemble(s, a); s.tick(0.25)
	a.paused = true
	var snapshot: Dictionary = JSON.parse_string(encoded(s))
	check(snapshot.session.crafting.activation_order.map(func(id): return int(id)) == [b.id, a.id], "save writes activation independent of stack rows")
	var loaded = make(s.catalog.data.recipes)
	check(Codec.restore(loaded, snapshot).ok and encoded(s) == encoded(loaded), "activation, exact timer/pause and RNG survive JSON")
	a.paused = false; loaded.stacks[a.id].paused = false
	var left := listen(s); var right := listen(loaded)
	s.tick(0.75); loaded.tick(0.75)
	check(left == ["a_out", "b_out"] and left == right and encoded(s) == encoded(loaded), "save continuation preserves completion, repeat order and RNG")
	var before: String = encoded(loaded)
	var notifications: Array = []
	loaded.changed.connect(func(): notifications.append(true))
	for malformed in [null, [], {}, {"activation_order": null}, {"activation_order": [a.id]}, {"activation_order": [a.id, a.id]}, {"activation_order": [a.id, 999]}, {"activation_order": [a.id, 1.5]}, {"activation_order": [a.id, str(b.id)]}]:
		var bad := snapshot.duplicate(true); bad.session.crafting = malformed
		check(not Codec.restore(loaded, bad).ok and encoded(loaded) == before and notifications.is_empty(), "malformed order rejects atomically: " + str(malformed))
	var legacy := snapshot.duplicate(true); legacy.session.erase("crafting")
	check(Codec.restore(loaded, legacy).ok, "legacy v1 without order remains loadable")
	check(loaded.crafting.save_state().activation_order == [a.id, b.id], "legacy fallback uses saved stack row order, not fabricated history")
	check(loaded.stacks[a.id].paused and loaded.stacks[a.id].progress == 0.25, "legacy fallback leaves paused timer untouched")
	# Empty and zero-progress paused states are valid, not inferred as absent tasks.
	var zero = make(); var work = base(zero, "a_in"); assemble(zero, work); work.paused = true
	var zero_snapshot := Codec.capture(zero)
	check(Codec.restore(make(), zero_snapshot).ok and zero_snapshot.session.crafting.activation_order == [work.id], "zero-progress paused active task is serialized")
	zero.start_new_game()
	check(zero.crafting.save_state().activation_order.is_empty(), "new game resets old order")

func test_held_order() -> void:
	var s = make()
	var a = base(s, "a_in"); var b = base(s, "b_in")
	var worker: int = assemble(s, a); assemble(s, b)
	s.tick(0.25)
	check(s.drag.begin(worker).ok and a.paused, "partial hold pauses incomplete original without cancelling")
	var raw := Codec._capture_unsettled(s)
	var loaded = make()
	check(Codec.restore(loaded, raw).ok and loaded.stacks[a.id].paused and loaded.stacks[a.id].progress == 0.25, "staging accepts incomplete paused original needed by held normalization")
	var held: int = s.drag.stack_id
	check(s.move_to_stack(worker, a.id, s.drag.original_stack_id(worker)), "held ingredient returns with source permission")
	s.drag.finish_standard(a.id)
	var events := listen(s); s.tick(0.75)
	check(events == ["b_out", "a_out"] and not s.stacks.has(held), "pause and return preserve original activation order")
	s = make(); a = base(s, "a_in"); b = base(s, "b_in"); assemble(s, a); assemble(s, b)
	check(s.drag.begin(a.card_ids.front()).ok and not a.paused, "full-stack hold keeps running source task")
	events = listen(s); s.tick(1)
	check(events == ["b_out", "a_out"] and s.drag.active(), "whole-stack drag does not suspend or reorder crafts")
	s.drag.finish_standard()

func test_paused_clock() -> void:
	for path in ["global", "phase", "external"]:
		var s = make()
		var a = base(s, "a_in"); var b = base(s, "b_in")
		assemble(s, a); assemble(s, b)
		# Deliberate completed-save fixture tests source manager vs task pause edges.
		a.progress = 1.25; a.paused = true
		b.progress = 0.5
		var loaded = make()
		check(Codec.restore(loaded, Codec.capture(s)).ok, path + " completed paused save stages")
		var events := listen(loaded)
		if path == "global": loaded.paused = true
		if path == "phase": loaded.phase = "feeding"
		if path == "external": loaded.tick_paused(0.5)
		else: loaded.tick(0.5)
		check(events == ["a_out"] and loaded.stacks[b.id].progress == 0.5, path + " executes completed task without advancing incomplete task")
		check(loaded.elapsed == 0 and loaded.stacks[a.id].recipe_guid.is_empty(), path + " keeps gameplay clock stopped and cancels finished task")
		if path == "external": loaded.tick_paused(1)
		else: loaded.tick(1)
		check(events == ["a_out"], path + " cannot repeat completed task on another paused tick")

func test_weighted_repeats() -> void:
	var choices := [recipe("a1", "a_in", "a_out", true), recipe("a2", "a_in", "c_out", true), recipe("b1", "b_in", "b_out", true), recipe("b2", "b_in", "c_out", true)]
	choices[1].fields.randomWeight = 3; choices[3].fields.randomWeight = 3
	var s = make(choices)
	var a = base(s, "a_in"); var b = base(s, "b_in")
	assemble(s, a); assemble(s, b)
	var events := listen(s)
	var expected = RandomNumberGenerator.new(); expected.state = s.rng.state
	var next_order: Array = [b, a]
	for cycle in 6:
		var predicted_events: Array = []
		var predicted_recipes := {}
		for stack in next_order:
			predicted_events.append(s.catalog.ref_guid(s.catalog.fields(stack.recipe_guid).resultingCard))
			var prefix: String = "a" if stack == a else "b"
			predicted_recipes[stack.id] = prefix + ("1" if expected.randf() * 4 <= 1 else "2")
		events.clear(); s.tick(1)
		check(events == predicted_events, "weighted repeat %d executes previous choices in activation order" % cycle)
		check(a.recipe_guid == predicted_recipes[a.id] and b.recipe_guid == predicted_recipes[b.id] and s.rng.state == expected.state, "weighted repeat %d assigns exact next RNG draws to source-ordered tasks" % cycle)
		check(a.progress == 0 and b.progress == 0, "weighted repeat %d starts next task with no frame remainder" % cycle)
		next_order.reverse()
