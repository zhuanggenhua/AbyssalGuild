extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
var signals_seen := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func recipe(guid: String, ingredients: Array, excess: bool = false) -> Dictionary:
	return {"guid": guid, "script_class": "RecipeDefinition", "fields": {"id": guid, "requiredIngredients": ingredients, "allowExcessIngredients": excess, "randomWeight": 1, "craftingDuration": 10, "resultingCard": {"guid": "result"}}}

func ingredient(guid: String, count: int = 1) -> Dictionary:
	return {"card": {"guid": guid}, "count": count, "consumptionMode": 0}

func make_session(extra_recipes: Array = []):
	var catalog = Catalog.new()
	var matrix: Array = []; matrix.resize(144); matrix.fill(1)
	var definitions: Array = []
	for guid in ["a", "b", "result", "station", "wood", "gear", "hero", "enemy", "coin"]:
		var category: int = {"station": 6, "gear": 5, "hero": 2, "enemy": 9, "coin": 7}.get(guid, 4)
		definitions.append({"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid, "displayName": guid, "category": category, "faction": 1 if guid == "hero" else (2 if guid == "enemy" else 0), "maxHealth": 10, "equipmentSlot": 0}})
	catalog.configure({"cards": definitions, "recipes": [recipe("pair", [ingredient("a"), ingredient("b")])] + extra_recipes, "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": matrix}}, {"guid": "settings", "script_class": "CardSettings", "fields": {"stackStep": {"x": 0, "y": 0.02, "z": -0.3}}}]})
	var session = Session.new()
	session.configure(catalog, 917)
	session.world.currency_guid = "coin"
	return session

func pair(session, progress: float = 3.0) -> Array:
	var a: int = session.spawn_card("a", Vector2(1, 2))
	var stack = session.stacks[session.cards[a].stack_id]
	var b: int = session.spawn_card("b", Vector2.ZERO, stack.id)
	session._check_recipe(stack)
	stack.progress = progress
	return [a, b, stack]

func encoded(session) -> String:
	return JSON.stringify(Codec.capture(session), "", true, true)

func _init() -> void:
	test_pick_and_return()
	test_other_releases()
	test_terminals_and_changes()
	test_checkpoint()
	print("Held stack checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func test_pick_and_return() -> void:
	var s = make_session()
	var ids := pair(s, 9.9)
	var original = ids[2]
	var target: Vector2 = s.card_target_position(ids[1])
	var next_id: int = s._next_id
	var before_rng: int = s.rng.state
	var begun: Dictionary = s.drag.begin(ids[1])
	check(begun.ok and begun.split and original.card_ids == [ids[0]], "press physically removes crafting tail immediately")
	check(original.paused and original.recipe_guid == "pair" and original.progress == 9.9, "pickup pauses original without validation/reset")
	var held = s.stacks[begun.stack_id]
	check(held.card_ids == [ids[1]] and held.position == target and s.cards[ids[1]].stack_id == held.id, "tail owns registered stack at lifted card pose")
	check(held.recipe_guid.is_empty() and s.rng.state == before_rng, "held tail does not choose a recipe or draw RNG")
	check(s._next_id == next_id + 1, "split allocates exactly one stack identity")
	s.tick(0.2)
	check(s.cards.has(ids[1]) and original.progress == 9.9, "9.9-second craft cannot consume held ingredient")
	check(not s.can_move_to_stack(ids[1], original.id), "strict active recipe normally refuses attachment")
	var genuine: int = s.drag.original_stack_id(ids[1])
	check(genuine == original.id and s.can_move_to_stack(ids[1], original.id, genuine), "genuine original permits return")
	var outsider: int = s.spawn_card("b")
	check(s.drag.original_stack_id(outsider) == -1, "unrelated card cannot borrow original-stack bypass")
	var repeated: Dictionary = s.drag.begin(ids[1])
	check(repeated.ok and repeated.repeated and s._next_id == next_id + 3, "same repeated press does not split or allocate again")
	check(not s.drag.begin(outsider).ok and s.drag.card_id == ids[1] and original.paused, "different repeated press cannot discard paused context")
	check(s.move_to_stack(ids[1], original.id, genuine), "returned tail attaches")
	s.drag.finish_standard(original.id)
	check(original.card_ids == [ids[0], ids[1]] and original.progress == 9.9 and not original.paused, "return resumes same task at same elapsed progress")
	check(not s.drag.active() and s.drag.original_stack_id() == -1, "release consumes ephemeral return permission")
	s.tick(0.2)
	check(not s.cards.has(ids[0]) and not s.cards.has(ids[1]), "returned craft completes normally on subsequent tick")
	# Whole-stack pickup must not pause, replace the stack or restart its recipe.
	s = make_session(); ids = pair(s, 3)
	before_rng = s.rng.state; next_id = s._next_id
	begun = s.drag.begin(ids[0])
	check(begun.ok and not begun.split and begun.stack_id == ids[2].id, "first-card press keeps original stack identity")
	check(not ids[2].paused and s.drag.original_stack_id() == -1 and s._next_id == next_id, "whole-stack drag has no paused-original context")
	s.tick(0.5)
	check(ids[2].progress == 3.5 and s.rng.state == before_rng, "whole-stack craft continues while held")
	s.drag.finish_standard()
	check(ids[2].progress == 3.5, "unmerged whole-stack release keeps progress")
	s.drag.finish_standard(); s.drag.finish_terminal()
	check(ids[2].progress == 3.5, "duplicate release is a no-op")
	check(not s.drag.begin(-123).ok and not s.drag.active(), "missing press has no side effects")

func test_other_releases() -> void:
	var s = make_session()
	var ids := pair(s)
	s.drag.begin(ids[1]); var held_id: int = s.drag.stack_id
	s.drag.finish_standard()
	check(ids[2].recipe_guid.is_empty() and ids[2].progress == 0 and not ids[2].paused, "empty-board or rejected-target release cancels invalid remainder")
	check(s.cards[ids[1]].stack_id == held_id and s.stacks.has(held_id), "ordinary release keeps detached tail, never rolls back")
	# The remainder can continue a workstation even after excess is removed.
	var work := recipe("work", [ingredient("station"), ingredient("wood")], true)
	s = make_session([work])
	var base: int = s.spawn_card("station")
	var original = s.stacks[s.cards[base].stack_id]
	s.spawn_card("wood", Vector2.ZERO, original.id)
	var excess: int = s.spawn_card("wood", Vector2.ZERO, original.id)
	s._check_recipe(original); original.progress = 4
	s.drag.begin(excess); s.tick(0.25)
	check(original.paused and original.progress == 4, "still-valid original also pauses until release")
	s.drag.finish_standard()
	check(original.recipe_guid == "work" and original.progress == 4 and not original.paused, "other release validates and resumes valid workstation")
	# Splitting an idle stack checks its remaining base, but not the new tail.
	var solo := recipe("solo", [ingredient("a")])
	var tail_recipe := recipe("tail", [ingredient("b")])
	s = make_session([solo, tail_recipe]); ids = pair(s)
	ids[2].cancel_craft(); s.drag.begin(ids[1])
	check(ids[2].recipe_guid == "solo" and s.stacks[s.drag.stack_id].recipe_guid.is_empty(), "idle-source split starts only remaining-base recipe")
	held_id = s.drag.stack_id; s.drag.finish_standard()
	check(s.stacks[held_id].recipe_guid == "tail", "unattached tail is checked once on release")
	# A physically rejected return must not claim the active-craft exception won.
	s = make_session(); ids = pair(s); s.drag.begin(ids[1])
	s.catalog.stacking_rules().fill(0)
	check(not s.move_to_stack(ids[1], ids[2].id, s.drag.original_stack_id(ids[1])), "original bypass does not override physical matrix")
	s.drag.finish_standard()
	check(ids[2].recipe_guid.is_empty(), "rejected original return is ordinary validation, not forced resume")
	# A different compatible stack receives the tail while original is validated.
	s = make_session(); ids = pair(s); s.drag.begin(ids[1])
	var other: int = s.spawn_card("a", Vector2(8, 8))
	var other_stack: int = s.cards[other].stack_id
	check(s.move_to_stack(ids[1], other_stack, s.drag.original_stack_id(ids[1])), "different target merge succeeds")
	s.drag.finish_standard(other_stack)
	check(ids[2].recipe_guid.is_empty() and s.stacks[other_stack].recipe_guid == "pair", "different target starts its own recipe and old invalid task stops")

func test_terminals_and_changes() -> void:
	var work := recipe("work", [ingredient("station"), ingredient("wood")], true)
	for action in ["sale", "equipment", "combat", "missing", "phase"]:
		var s = make_session([work])
		var base: int = s.spawn_card("station")
		var original = s.stacks[s.cards[base].stack_id]
		s.spawn_card("wood", Vector2.ZERO, original.id)
		var guid: String = {"equipment": "gear", "combat": "hero"}.get(action, "wood")
		var held: int = s.spawn_card(guid, Vector2.ZERO, original.id)
		s._check_recipe(original); original.progress = 6; s.drag.begin(held)
		if action == "sale":
			check(s.sell_stack(s.drag.stack_id), "held tail can be sold independently")
			s.drag.finish_terminal()
		elif action == "equipment":
			var wearer: int = s.spawn_card("hero")
			check(s.equipment.equip(wearer, held), "held equipment can attach without disturbing base membership")
			s.drag.finish_terminal()
		elif action == "combat":
			var enemy: int = s.spawn_card("enemy")
			check(s.combat.start_combat([held], [enemy], true) >= 0, "held fighter can enter combat")
			s.drag.finish_terminal()
		elif action == "missing":
			s.kill_card(held); s.drag.finish_standard()
		else:
			s.phase = "selling"; s.drag.finish_standard()
		if action in ["sale", "equipment", "combat"]:
			check(original.recipe_guid.is_empty() and original.progress == 0, action + " terminal stops even a still-valid original recipe")
		else:
			check(original.recipe_guid == "work" and original.progress == 6 and not original.paused, action + " ordinary release safely resumes live valid remainder")
		check(not s.drag.active(), action + " consumes hold exactly once")
	# Original deletion or a replaced task must not leave orphan IDs or resurrect it.
	var s = make_session(); var ids := pair(s); s.drag.begin(ids[1])
	s.kill_card(ids[0]); s.drag.finish_standard()
	check(s.cards.has(ids[1]) and not s.stacks.has(ids[2].id) and not s.drag.active(), "original disappearance settles surviving held tail")
	s = make_session([recipe("solo", [ingredient("a")])]); ids = pair(s); s.drag.begin(ids[1])
	ids[2].cancel_craft(); s._check_recipe(ids[2]); ids[2].progress = 2
	s.drag.finish_standard()
	check(ids[2].recipe_guid == "solo" and ids[2].progress == 2 and not ids[2].paused, "release validates current task without resurrecting old recipe")
	# Stale begin is not available for equipped or combat-held cards.
	var gear: int = s.spawn_card("gear"); var hero: int = s.spawn_card("hero")
	s.equipment.equip(hero, gear)
	check(not s.drag.begin(gear).ok, "equipment must use unequip path before standard hold")
	var foe: int = s.spawn_card("enemy"); s.combat.start_combat([hero], [foe], true)
	check(not s.drag.begin(hero).ok, "combat pickup is separate from standard split")
	# Source trade handling returns false for accepted payments with leftovers.
	s = make_session([work])
	s.catalog.data["packs"] = [{"guid": "offer", "script_class": "PackDefinition", "fields": {"id": "offer", "buyPrice": 1, "slots": [{}]}}]
	s.catalog.configure(s.catalog.data)
	var station: int = s.spawn_card("station")
	var original = s.stacks[s.cards[station].stack_id]
	s.spawn_card("wood", Vector2.ZERO, original.id)
	var coin: int = s.spawn_card("coin", Vector2.ZERO, original.id)
	s.spawn_card("coin", Vector2.ZERO, original.id)
	s._check_recipe(original); original.progress = 4; s.drag.begin(coin)
	var payment: Dictionary = s.pay_vendor("offer", s.drag.stack_id)
	check(payment.accepted and not payment.terminal and s.cards.has(coin), "accepted excess payment leaves registered held remainder")
	check(original.paused and s.drag.original_stack_id(coin) == original.id, "nonterminal payment retains genuine original context")
	s.drag.finish_standard()
	check(original.recipe_guid == "work" and original.progress == 4 and not original.paused, "nonterminal payment follows ordinary validate/resume rather than terminal cancel")

func test_checkpoint() -> void:
	var tail_recipe := recipe("tail", [ingredient("b")])
	var s = make_session([tail_recipe]); var ids := pair(s)
	s.drag.begin(ids[1]); var held_id: int = s.drag.stack_id
	var before_rng: int = s.rng.state
	var before_knowledge: Dictionary = s.discovered_recipes.duplicate()
	var old_card = s.cards[ids[1]]; var old_stack = s.stacks[held_id]
	s.changed.connect(func(): signals_seen += 1)
	s.event_occurred.connect(func(_kind, _payload): signals_seen += 1)
	signals_seen = 0
	var snapshot: Dictionary = Codec.capture(s)
	check(signals_seen == 0 and s.rng.state == before_rng and s.discovered_recipes == before_knowledge, "held checkpoint has zero live events, knowledge changes or RNG draws")
	check(s.drag.active() and ids[2].paused and ids[2].progress == 3 and s.cards[ids[1]] == old_card and s.stacks[held_id] == old_stack, "held checkpoint preserves live references, pause and progress")
	check(JSON.stringify(snapshot, "", true, true) == encoded(s), "repeated held capture is deterministic")
	var loaded = make_session([tail_recipe])
	check(Codec.restore(loaded, JSON.parse_string(JSON.stringify(snapshot, "", true, true))).ok, "held snapshot freshly restores")
	check(not loaded.drag.active() and loaded.cards[ids[1]].stack_id == held_id, "snapshot settles split membership without persisting pointer state")
	check(loaded.stacks[ids[2].id].recipe_guid.is_empty() and not loaded.stacks[ids[2].id].paused, "invalid original cannot reload indefinitely paused")
	check(loaded.stacks[held_id].recipe_guid == "tail" and loaded.stacks[held_id].progress == 0, "checkpoint runs normal unattached-tail recipe selection on clone")
	check(s.stacks[held_id].recipe_guid.is_empty(), "clone recipe choice does not start live held tail")
	s.drag.finish_standard()
	check(encoded(loaded) == encoded(s), "checkpoint equals actual immediate ordinary release including RNG and discovery")
	s.tick(0.75); loaded.tick(0.75)
	check(encoded(loaded) == encoded(s), "normalized checkpoint preserves exact subsequent simulation")
	# A valid remaining work recipe keeps its elapsed progress and resumes.
	var work := recipe("work", [ingredient("station"), ingredient("wood")], true)
	s = make_session([work]); var base: int = s.spawn_card("station")
	var original = s.stacks[s.cards[base].stack_id]
	s.spawn_card("wood", Vector2.ZERO, original.id)
	var extra: int = s.spawn_card("wood", Vector2.ZERO, original.id)
	s._check_recipe(original); original.progress = 7.25; s.drag.begin(extra)
	loaded = make_session([work])
	check(Codec.restore(loaded, Codec.capture(s)).ok and loaded.stacks[original.id].progress == 7.25 and not loaded.stacks[original.id].paused, "held workstation save resumes valid remainder at exact progress")
	var path := "user://held-state.json"
	check(Codec.save_file(s, path).ok and s.drag.active() and original.paused, "held disk save does not consume live hold")
	check(Codec.load_file(loaded, path).ok and not loaded.drag.active(), "held disk checkpoint loads without transient state")
	# Successful restore clears an older hold; rejected restore leaves it intact.
	var before: Dictionary = Codec.capture(s)
	check(not Codec.restore(s, {}).ok and s.drag.active() and original.paused, "failed load preserves existing hold and paused task")
	check(Codec.restore(s, before).ok and not s.drag.active(), "successful load invalidates all old pointer references")
	s.drag.begin(extra); s.start_new_game()
	check(not s.drag.active(), "new game clears transient hold")
	# Native snapshots are taken at boundaries, never halfway through discovery.
	s = make_session([recipe("solo", [ingredient("a")])]); ids = pair(s)
	ids[2].cancel_craft()
	var reentrant: Array = []
	var during_discovery := func(kind, _payload):
		if kind == "recipe_discovered": reentrant.append(Codec.capture(s))
	s.event_occurred.connect(during_discovery)
	s.drag.begin(ids[1])
	s.event_occurred.disconnect(during_discovery)
	check(reentrant.size() == 1 and reentrant[0].has("capture_error"), "capture rejects half-applied press/discovery transition")
	check(not Codec.restore(s, reentrant[0]).ok and s.drag.active(), "reentrant checkpoint cannot restore or invalidate the live hold")
	# Whole-stack capture differs only by discarding the pointer, not its craft.
	s = make_session(); ids = pair(s, 5); s.drag.begin(ids[0])
	loaded = make_session()
	check(Codec.restore(loaded, Codec.capture(s)).ok and loaded.stacks[ids[2].id].progress == 5 and not loaded.stacks[ids[2].id].paused, "whole-stack held save retains active task without restart")
	check(loaded.stacks[ids[2].id].card_ids == ids[2].card_ids and loaded._next_id == s._next_id and loaded.rng.state == s.rng.state, "whole-stack snapshot keeps exact membership, IDs and RNG")
	# Even after an asynchronous kill, capture cannot persist dangling references.
	s = make_session(); ids = pair(s); s.drag.begin(ids[1]); s.kill_card(ids[0])
	loaded = make_session()
	check(Codec.restore(loaded, Codec.capture(s)).ok and loaded.cards.has(ids[1]) and not loaded.drag.active(), "held save handles disappeared original without orphan references")
	s.kill_card(ids[1])
	check(Codec.restore(loaded, Codec.capture(s)).ok and loaded.cards.is_empty(), "held save handles disappeared original and entire tail")
