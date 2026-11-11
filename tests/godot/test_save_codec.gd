extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
var notifications := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", label)

func make_session():
	var catalog = Catalog.new()
	catalog.configure({"cards": [{"guid": "card", "script_class": "CardDefinition", "fields": {"id": "wood", "category": 0, "maxHealth": 15}}], "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"id": "pack", "slots": [{}, {}]}}], "recipes": [{"guid": "recipe", "script_class": "RecipeDefinition", "fields": {"id": "recipe-id", "resultingCard": {"guid": "card"}}}], "quests": [{"guid": "quest", "fields": {"id": "quest-id", "targetAmount": 5}}], "scenes": [{"name": "Main", "documents": [{"fields": {"questGroups": [{"Quests": [{"guid": "quest"}]}]}}]}]})
	# Generated cards require the scene's real template contract, not codec defaults.
	catalog.data.cards.append({"guid": "recipe-template", "script_class": "CardDefinition", "fields": {"id": "template", "category": 8, "isSellable": true, "sellPrice": 3}})
	catalog.data.scenes[0].documents.append({"script_class": "CardManager", "fields": {"recipeCardTemplate": {"guid": "recipe-template"}}})
	catalog.configure(catalog.data)
	var session = Session.new()
	session.configure(catalog, 123)
	return session

func reject(session, snapshot: Variant, label: String) -> void:
	var before := JSON.stringify(Codec.capture(session), "", true, true)
	var count := notifications
	check(not Codec.restore(session, snapshot).ok, label)
	check(JSON.stringify(Codec.capture(session), "", true, true) == before, label + " preserves state")
	check(notifications == count, label + " emits no change")

func _init() -> void:
	var source = make_session()
	var first: int = source.spawn_card("card", Vector2(2.25, -1.5))
	var second: int = source.spawn_card("card", Vector2.ZERO, source.cards[first].stack_id)
	var pack: int = source.spawn_card("pack")
	source.cards[first].stored_coins = 7
	source.cards[first].nutrition = 3
	source.cards[first].health = 9
	source.cards[pack].uses_left = 1
	source.cards[second].uses_left = 2
	var stack = source.stacks[source.cards[first].stack_id]
	stack.recipe_guid = "recipe"
	stack.progress = 1.234567891234
	stack.paused = true
	source.discovered_recipes["recipe-id"] = true
	source.vendor_payments["pack"] = 2
	source.quest_tracker.restore_state({"CompletedQuests": ["legacy-id"], "ActiveQuests": [{"QuestId": "quest-id", "CurrentAmount": 3}]})
	source.day = 3
	source.elapsed = 18.125
	source.speed = 2
	source.paused = true
	source.rng.seed = -9223372036854775807
	source.rng.randi()
	var snapshot := Codec.capture(source)
	var target = make_session()
	target.changed.connect(func(): notifications += 1)
	var decoded = JSON.parse_string(JSON.stringify(snapshot, "", true, true))
	check(Codec.restore(target, decoded).ok, "JSON round trip")
	check(JSON.stringify(Codec.capture(target), "", true, true) == JSON.stringify(snapshot, "", true, true), "all fields round trip")
	check(notifications == 1, "one session notification")
	check(target.rng.randi() == source.rng.randi(), "RNG exact continuation above JSON safe integer range")
	for phase in ["playing", "feeding", "selling", "ready", "game_over"]:
		var state := snapshot.duplicate(true)
		state.session.phase = phase
		state.session.erase("cycle") # Legacy passive phases infer their initial controller state.
		check(Codec.restore(target, state).ok and target.phase == phase, "phase " + phase)
	for malformed in [null, [], {}, {"format": Codec.FORMAT, "version": 2}]:
		reject(target, malformed, "invalid root")
	for key in ["cards", "stacks", "quests", "day", "rng_state", "vendor_payments", "discovered_recipes"]:
		var bad := snapshot.duplicate(true)
		bad.session[key] = null
		reject(target, bad, "null " + key)
	for value in ["9223372036854775808", "1.5", 123, "01", " 2"]:
		var bad := snapshot.duplicate(true)
		bad.session.rng_state = value
		reject(target, bad, "invalid RNG")
	var bad := snapshot.duplicate(true)
	bad.session.cards[0].position = [NAN, 0]
	reject(target, bad, "nonfinite position")
	bad = snapshot.duplicate(true)
	bad.session.cards[0].health = 1.5
	reject(target, bad, "fractional integer")
	bad = snapshot.duplicate(true)
	bad.session.cards[0].definition_guid = "missing"
	reject(target, bad, "unknown definition")
	bad = snapshot.duplicate(true)
	bad.session.cards.append(bad.session.cards[0].duplicate())
	reject(target, bad, "duplicate instance")
	bad = snapshot.duplicate(true)
	bad.session.stacks[0].card_ids.append(first)
	reject(target, bad, "duplicate membership")
	bad = snapshot.duplicate(true)
	bad.session.stacks[0].card_ids.erase(first)
	reject(target, bad, "orphan card")
	bad = snapshot.duplicate(true)
	bad.session.next_id = 1
	reject(target, bad, "next ID collision")
	bad = snapshot.duplicate(true)
	bad.session.quests.ActiveQuests.append({"QuestId": "quest-id", "CurrentAmount": 1})
	reject(target, bad, "duplicate quest")
	# Synthetic recipe cards must be regenerated on a fresh catalog.
	var generated := snapshot.duplicate(true)
	generated.session.cards[0].definition_guid = "Recipe:recipe-id"
	generated.session.cards[0].base_definition_guid = "Recipe:recipe-id"
	check(Codec.restore(target, generated).ok, "generated recipe card restores")
	check(target.catalog.fields("Recipe:recipe-id").recipe_guid == "recipe", "recipe card definition regenerated")
	var path := "user://test-save-codec-" + str(OS.get_process_id()) + ".json"
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	check(Codec.save_file(source, path).ok, "first atomic save")
	source.day = 4
	check(Codec.save_file(source, path).ok, "second save creates backup")
	source.day = 5
	check(Codec.save_file(source, path).ok, "third save replaces backup")
	check(Codec.load_file(target, path).ok and target.day == 5, "primary preferred")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var recovered := Codec.load_file(target, path)
	check(recovered.ok and recovered.recovered and target.day == 4, "backup recovery")
	check(Codec.save_file(source, path).ok, "corrupt primary replaceable")
	var backup := Codec._read(path + ".bak")
	check(backup.ok and backup.snapshot.session.day == 4, "healthy backup not overwritten by corrupt primary")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("null")
	file.close()
	file = FileAccess.open(path + ".bak", FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	var before := JSON.stringify(Codec.capture(target))
	check(not Codec.load_file(target, path).ok, "both invalid fail")
	check(before == JSON.stringify(Codec.capture(target)), "failed load leaves live game intact")
	check(not Codec.save_file(source, "user://missing-save-dir/test.json").ok, "unwritable target reports failure")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	combined_subsystems()
	ai_checkpoints()
	combat_layout_checkpoints()
	combat_execution_checkpoints()
	projectile_scene_checkpoints()
	print("Save codec checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)

func combat_session():
	var session = make_session()
	var entries: Array = []
	var fields := {
		"hero": {"category": 2, "faction": 1, "maxHealth": 20},
		"mage": {"category": 2, "faction": 1, "maxHealth": 30},
		"mob": {"category": 9, "faction": 2, "maxHealth": 40},
		"weapon": {"category": 5, "equipmentSlot": 0, "classChangeResult": {"guid": "mage"}},
		"armor": {"category": 5, "equipmentSlot": 1}}
	for guid in fields:
		entries.append({"guid": guid, "script_class": "CardDefinition", "fields": fields[guid]})
	var data: Dictionary = session.catalog.data.duplicate(true)
	data.cards.append_array(entries)
	session.catalog.configure(data)
	return session

func combined_subsystems() -> void:
	var source = combat_session()
	var hero: int = source.spawn_card("hero")
	var mob: int = source.spawn_card("mob")
	var weapon: int = source.spawn_card("weapon")
	var armor: int = source.spawn_card("armor")
	check(source.equipment.equip(hero, weapon), "combined class-changing equip")
	check(source.equipment.equip(hero, armor), "combined second equipment slot")
	var battle: int = source.combat.start_combat([hero], [mob])
	check(battle > 0, "combined battle started")
	source.combat.tasks[battle].timer = -0.25
	source.combat.tasks[battle].progress[hero] = -0.5
	source.combat.dragged[hero] = true
	var snapshot := Codec.capture(source)
	var target = combat_session()
	target.changed.connect(func(): notifications += 1)
	var result := Codec.restore(target, JSON.parse_string(JSON.stringify(snapshot, "", true, true)))
	check(result.ok, "combined snapshot restores")
	check(JSON.stringify(Codec.capture(target), "", true, true) == JSON.stringify(snapshot, "", true, true), "equipment and active combat exact JSON roundtrip")
	check(target.equipment.owners.get(weapon) == hero and target.equipment.owners.get(armor) == hero, "equipment owner maps restored")
	check(target.equipment.originals.get(hero) == "hero" and target.cards[hero].definition_guid == "mage", "class-change base retained")
	check(target.combat.membership.get(hero) == battle and target.combat.membership.get(mob) == battle, "combat membership restored")
	check(target.combat.dragged.is_empty(), "transient dragging omitted")
	check(target.rng.randi() == source.rng.randi(), "combined RNG continuity")
	for value in [null, {}, [], "1", 1.5, INF]:
		var bad := snapshot.duplicate(true)
		bad.session.equipment.wearers[0].wearer = value
		reject(target, bad, "bad equipment wearer scalar")
		bad = snapshot.duplicate(true)
		bad.session.combat.next_id = value
		reject(target, bad, "bad combat next ID scalar")
		bad = snapshot.duplicate(true)
		bad.session.combat.tasks[0].progress[0].card = value
		reject(target, bad, "bad combat progress ID scalar")
	for value in [null, {}, [], "1", INF, NAN]:
		var bad := snapshot.duplicate(true)
		bad.session.combat.tasks[0].timer = value
		reject(target, bad, "bad combat timer scalar")
	var bad := snapshot.duplicate(true)
	bad.session.combat.tasks[0].attackers.append(hero)
	reject(target, bad, "duplicate fighter through codec")
	bad = snapshot.duplicate(true)
	bad.session.equipment.wearers[0].items.append(bad.session.equipment.wearers[0].items[0].duplicate())
	reject(target, bad, "duplicate equipment through codec")
	bad = snapshot.duplicate(true)
	bad.session.erase("equipment")
	reject(target, bad, "unaccounted stackless items")
	bad = snapshot.duplicate(true)
	bad.session.erase("combat")
	reject(target, bad, "unaccounted stackless fighters")
	var path := "user://test-save-combined-" + str(OS.get_process_id()) + ".json"
	check(Codec.save_file(source, path).ok, "combined save to disk")
	check(Codec.load_file(target, path).ok, "combined load from disk")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var legacy := Codec.capture(make_session())
	legacy.session.erase("equipment")
	legacy.session.erase("combat")
	check(Codec.restore(target, legacy).ok, "base-only v1 snapshot loads")
	check(target.equipment.equipped.is_empty() and target.combat.tasks.is_empty(), "missing old subsystem fields reset stale maps")

func ai_session():
	var session = combat_session()
	var data: Dictionary = session.catalog.data.duplicate(true)
	data.cards.append({"guid": "producer", "script_class": "CardDefinition", "fields": {"category": 9, "faction": 2, "produceCard": {"guid": "card"}, "produceInterval": 4.0}})
	data.referenced_prefabs = [{"guid": "ai-prefab", "documents": [{"script_class": "CardAI"}]}]
	data.scenes[0].documents.append({"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai-prefab"}}]}})
	session.catalog.configure(data)
	session.ai.configure(session, session.world, "Main")
	session.ai.point_validator = func(_position: Vector2, _stack: int): return true
	return session

func ai_checkpoints() -> void:
	var source = ai_session()
	var producer: int = source.spawn_card("producer")
	check(source.ai.agents.has(producer) and source.world.production_timers.has(producer), "imported prefab mapping registers producer AI")
	source.ai.agents[producer].move_timer = 0.25
	source.world.production_timers[producer] = 0.125
	source.world.processed_days[2] = true
	var rng_before: int = source.rng.state
	var snapshot := Codec.capture(source)
	check(source.rng.state == rng_before, "AI capture consumes no RNG")
	var target = ai_session()
	target.changed.connect(func(): notifications += 1)
	check(Codec.restore(target, JSON.parse_string(JSON.stringify(snapshot, "", true, true))).ok, "AI checkpoint JSON restores")
	check(target.ai.agents[producer].move_timer == 0.25, "movement timer restored exactly")
	check(target.world.production_timers.get(producer) == 0.125, "world restore occurs before AI timer application")
	check(target.world.processed_days.has(2), "world progress and AI timers coexist")
	check(target.rng.state == rng_before, "AI restore consumes no RNG")
	source.tick(0.5)
	target.tick(0.5)
	check(source.cards.size() == 2 and target.cards.size() == 2, "restored production wake produces exactly once")
	check(JSON.stringify(Codec.capture(source), "", true, true) == JSON.stringify(Codec.capture(target), "", true, true), "AI next tick movement production and RNG continue exactly")
	check(source.cards[producer].position != Vector2.ZERO, "restored movement wake executes patrol")
	for key in ["move_timer", "produce_timer"]:
		for value in [null, {}, "1", -0.1, INF, NAN]:
			var bad := snapshot.duplicate(true)
			bad.session.ai.agents[0][key] = value
			reject(target, bad, "malformed AI " + key)
	var bad := snapshot.duplicate(true)
	bad.session.ai.agents.clear()
	reject(target, bad, "missing live AI checkpoint record")
	bad = snapshot.duplicate(true)
	bad.session.ai.agents.append(bad.session.ai.agents[0].duplicate())
	reject(target, bad, "duplicate AI checkpoint record")
	bad = snapshot.duplicate(true)
	bad.session.ai.scene = "Island"
	reject(target, bad, "AI configured scene mismatch")
	var hero: int = source.spawn_card("hero")
	check(source.combat.start_combat([hero], [producer]) > 0, "producer enters combat")
	var battle := Codec.capture(source)
	check(not battle.session.ai.agents[0].running, "combat checkpoint stops producer AI")
	check(Codec.restore(target, battle).ok, "stopped AI combat snapshot restores")
	check(not target.world.production_timers.has(producer), "combat restore does not restart production")
	bad = battle.duplicate(true)
	bad.session.ai.agents[0].running = true
	bad.session.ai.agents[0].produce_timer = 1.0
	reject(target, bad, "running AI cannot coexist with staged combat membership")
	# Older saves have no coroutine checkpoint; load must not draw RNG itself.
	var legacy := snapshot.duplicate(true)
	legacy.session.erase("ai")
	check(Codec.restore(target, legacy).ok, "legacy checkpoint without AI loads")
	check(target.ai.agents.is_empty() and target.world.production_timers.is_empty(), "legacy missing AI clears old agents and producer timers")
	check(target.rng.state == rng_before, "legacy restore preserves stored RNG until tick")
	target.paused = true
	target.tick(0.25)
	check(target.ai.agents.is_empty() and target.rng.state == rng_before, "paused legacy session postpones AI initialization")
	var path := "user://test-save-legacy-ai-" + str(OS.get_process_id()) + ".json"
	check(Codec.save_file(target, path).ok, "legacy AI can be resaved immediately while paused")
	check(target.ai.agents.is_empty() and target.world.production_timers.is_empty() and target.rng.state == rng_before, "legacy resave normalization is read-only and consumes no RNG")
	var pending := Codec.capture(target)
	check(pending.session.ai.agents.size() == 1 and not pending.session.ai.agents[0].running and pending.session.ai.agents[0].move_timer == 0.0, "legacy capture emits stopped pending restart record")
	check(not pending.session.ai.agents[0].has("produce_timer"), "pending legacy restart has no invented production timer")
	var reloaded = ai_session()
	check(Codec.load_file(reloaded, path).ok, "immediate legacy resave loads as native AI checkpoint")
	check(not reloaded.ai.agents[producer].running and reloaded.world.production_timers.is_empty() and reloaded.rng.state == rng_before, "resaved pending AI waits until unpaused tick without RNG draw")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = legacy.session.rng_seed.to_int()
	expected_rng.state = legacy.session.rng_state.to_int()
	var expected_move: float = expected_rng.randf_range(0.5, 1.0) + target.ai.move_interval - 0.25
	var expected_produce: float = expected_rng.randf_range(0.5, 1.0) + 4.0 - 0.25
	target.paused = false
	target.tick(0.25)
	check(target.ai.agents[producer].running and target.ai.agents[producer].move_timer == expected_move, "first unpaused tick initializes legacy movement wait")
	check(target.world.production_timers[producer] == expected_produce, "first unpaused tick initializes legacy producer wait")
	check(target.rng.state == expected_rng.state, "legacy first tick consumes exactly initial movement and production RNG draws")
	reloaded.paused = false
	reloaded.tick(0.25)
	check(JSON.stringify(Codec.capture(target), "", true, true) == JSON.stringify(Codec.capture(reloaded), "", true, true), "immediate legacy resave preserves next tick restart and RNG semantics")
	check(Codec.restore(source, Codec.capture(target)).ok, "reinitialized legacy AI can be checkpointed again")

func combat_layout_checkpoints() -> void:
	var source = combat_session()
	var hero: int = source.spawn_card("hero", Vector2(2, 3))
	var mob: int = source.spawn_card("mob", Vector2(-4, 5))
	var battle: int = source.combat.start_combat([hero], [mob])
	var original := {"center": Vector2(-3.25, 8.5), "cell": Vector2(1.5, 2.25), "config": {"untrusted": "not persisted"}, "size": Vector2(9, 9), "positions": {hero: Vector2(4, 5)}}
	source.combat.tasks[battle]["layout"] = original.duplicate(true)
	var rng_before: int = source.rng.state
	var snapshot := Codec.capture(source)
	check(snapshot.session.combat.tasks[0].layout == {"center": [-3.25, 8.5], "cell": [1.5, 2.25]}, "combat geometry serializes only center and initial cell spacing")
	check(source.combat.tasks[battle].layout == original and source.rng.state == rng_before, "layout capture leaves runtime geometry and RNG unchanged")
	var target = combat_session()
	target.changed.connect(func(): notifications += 1)
	check(Codec.restore(target, JSON.parse_string(JSON.stringify(snapshot, "", true, true))).ok, "combat layout JSON roundtrip")
	check(target.combat.tasks[battle].layout == {"center": original.center, "cell": original.cell}, "restored geometry contains only placement metadata as Vector2")
	check(target.rng.state == rng_before, "layout restoration consumes no RNG")
	var path := "user://test-save-combat-layout-" + str(OS.get_process_id()) + ".json"
	check(Codec.save_file(source, path).ok, "midcombat geometry saves to disk")
	target.combat.tasks[battle].layout.center = Vector2(99, 99)
	check(Codec.load_file(target, path).ok, "midcombat geometry loads from disk")
	check(target.combat.tasks[battle].layout.center == original.center and target.combat.tasks[battle].layout.cell == original.cell, "midcombat load preserves center and initial spacing")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	for value in [null, [], 1, "layout", {}, {"center": [0, 0]}, {"center": [0, 0], "cell": [1, 1], "positions": {}}]:
		var bad := snapshot.duplicate(true)
		bad.session.combat.tasks[0].layout = value
		reject(target, bad, "malformed combat layout shape")
	for key in ["center", "cell"]:
		for value in [null, {}, [], [1], [1, 2, 3], Vector2.ONE, ["1", 1], [true, 1], [NAN, 1], [1, INF], [1.0e21, 1]]:
			var bad := snapshot.duplicate(true)
			bad.session.combat.tasks[0].layout[key] = value
			reject(target, bad, "invalid combat layout " + key)
	for value in [[0, 1], [1, 0], [-1, 1], [1, -1], [1.0e-100, 1]]:
		var bad := snapshot.duplicate(true)
		bad.session.combat.tasks[0].layout.cell = value
		reject(target, bad, "nonpositive or unrepresentable cell axis")
	var legacy := snapshot.duplicate(true)
	legacy.session.combat.tasks[0].erase("layout")
	check(Codec.restore(target, legacy).ok, "legacy battle without layout loads")
	check(not target.combat.tasks[battle].has("layout"), "legacy restoration does not invent placement metadata")
	check(not Codec.capture(target).session.combat.tasks[0].has("layout"), "legacy re-save omits geometry until adapter initializes it")

func combat_execution_checkpoints() -> void:
	var source = combat_session()
	var hero: int = source.spawn_card("hero")
	var mob: int = source.spawn_card("mob")
	var battle: int = source.combat.start_combat([hero], [mob])
	source.combat.tasks[battle].progress[hero] = 100.0
	source.combat.tasks[battle].progress[mob] = 0.0
	source.combat.resolve_turn(battle)
	var travel := Codec.capture(source)
	check(travel.session.combat.tasks[0].execution.phase == "travel", "execution travel checkpoint captured")
	var target = combat_session()
	target.changed.connect(func(): notifications += 1)
	var selector := func(_request): return []
	target.combat.start_overlap_selector = selector
	check(Codec.restore(target, JSON.parse_string(JSON.stringify(travel, "", true, true))).ok, "in-flight travel restores")
	check(target.combat.start_overlap_selector == selector, "runtime callback not serialized or overwritten on restore")
	check(not travel.session.combat.has("start_overlap_selector"), "snapshot excludes callback objects")
	source.combat.tick(0.0, 0.3)
	target.combat.tick(0.0, 0.3)
	check(JSON.stringify(Codec.capture(source), "", true, true) == JSON.stringify(Codec.capture(target), "", true, true), "paused travel resume consumes identical damage RNG once")
	check(source.combat.tasks[battle].execution.phase == "return", "impact enters return phase")
	source.cards[mob].health = 0
	var returning := Codec.capture(source)
	check(Codec.restore(target, returning).ok and target.cards[mob].health == 0, "pending dead target accepted only during valid return")
	source.combat.tick(0.0, 0.3)
	target.combat.tick(0.0, 0.3)
	check(JSON.stringify(Codec.capture(source), "", true, true) == JSON.stringify(Codec.capture(target), "", true, true), "restored return cleanup and loot RNG agree")
	var death_wait := Codec.capture(source)
	check(death_wait.session.combat.tasks[0].defenders.is_empty() and death_wait.session.combat.tasks[0].execution.phase == "death_wait", "last target removal preserves death wait checkpoint")
	check(Codec.restore(target, JSON.parse_string(JSON.stringify(death_wait, "", true, true))).ok, "empty enemy side death wait restores")
	source.combat.tick(0.0, 1.0)
	target.combat.tick(0.0, 1.0)
	check(target.combat.tasks.has(battle), "paused scaled death wait does not expire")
	source.combat.tick(0.5, 0.5)
	target.combat.tick(0.5, 0.5)
	check(source.combat.tasks.is_empty() and target.combat.tasks.is_empty(), "restored death wait completes battle once")
	check(JSON.stringify(Codec.capture(source), "", true, true) == JSON.stringify(Codec.capture(target), "", true, true), "death wait resume preserves final session RNG and membership")
	for key in ["actor", "target", "combat_type", "remaining", "phase", "attacker_position", "defender_position"]:
		for value in [null, {}, []]:
			var bad := travel.duplicate(true)
			bad.session.combat.tasks[0].execution[key] = value
			reject(target, bad, "malformed execution field " + key)
	for mutation in [{"actor": 999}, {"target": 999}, {"target": hero}, {"target": -1}, {"combat_type": 4}, {"remaining": INF}, {"remaining": NAN}, {"remaining": -0.1}, {"remaining": 3601}, {"phase": "impact"}]:
		var bad := travel.duplicate(true)
		bad.session.combat.tasks[0].execution.merge(mutation, true)
		reject(target, bad, "invalid execution participant duration or phase")
	var bad := returning.duplicate(true)
	bad.session.combat.tasks[0].execution.remaining = 0.31
	reject(target, bad, "return duration cannot exceed source wait")
	bad = death_wait.duplicate(true)
	bad.session.combat.tasks[0].execution.remaining = 0.51
	reject(target, bad, "death wait duration cannot exceed source wait")
	bad = death_wait.duplicate(true)
	bad.session.combat.tasks[0].execution.target = mob
	reject(target, bad, "death wait cannot reference removed target")
	bad = death_wait.duplicate(true)
	bad.session.combat.tasks[0].erase("execution")
	reject(target, bad, "empty side cannot be restored as legacy idle")
	bad = travel.duplicate(true)
	bad.session.combat.tasks[0].progress[0].card = 999
	reject(target, bad, "execution progress must reference task participant")
	bad = travel.duplicate(true)
	bad.session.combat.tasks[0].execution["callback"] = "never execute serialized callbacks"
	reject(target, bad, "execution rejects unexpected callback fields")
	for checkpoint in [travel, returning, death_wait]:
		bad = checkpoint.duplicate(true)
		for card in bad.session.cards:
			if card.id == hero: card.health = 0
		check(Codec.restore(target, bad).ok and target.cards[hero].health == 0, "source-legal merged zero-health actor remains loadable")
	bad = travel.duplicate(true)
	for card in bad.session.cards:
		if card.id == mob: card.health = 0
	check(Codec.restore(target, bad).ok and target.cards[mob].health == 0, "source-legal merged zero-health target remains loadable")
	bad = returning.duplicate(true)
	var extra: Dictionary = bad.session.cards[0].duplicate(true)
	extra.id = int(bad.session.next_id)
	extra.health = 0
	bad.session.next_id += 1
	bad.session.cards.append(extra)
	bad.session.combat.tasks[0].attackers.append(extra.id)
	bad.session.combat.tasks[0].progress.append({"card": extra.id, "value": 0.0})
	check(Codec.restore(target, bad).ok and target.cards[int(extra.id)].health == 0, "source-legal extra merged zero-health participant retained")
	bad = travel.duplicate(true)
	bad.session.combat.tasks[0].execution.remaining = 0.3001
	reject(target, bad, "melee travel cannot exceed actual source duration")
	var ranged := travel.duplicate(true)
	ranged.session.combat.tasks[0].execution.combat_type = 2
	ranged.session.combat.tasks[0].execution.remaining = 0.6
	reject(target, ranged, "projectile travel without source component rejected")
	target.catalog.data.scenes[0].documents.append({"script_class": "CombatManager", "fields": {"arrowProjectile": {"guid": "arrow-prefab"}}})
	target.catalog.data.referenced_prefabs = [{"guid": "arrow-prefab", "documents": [{"script_class": "CombatProjectile", "fields": {"duration": 0.6}}]}]
	check(Codec.restore(target, ranged).ok, "projectile travel within imported duration restores")
	bad = ranged.duplicate(true)
	bad.session.combat.tasks[0].execution.remaining = 0.6001
	reject(target, bad, "projectile travel cannot exceed imported duration")
	var legacy := travel.duplicate(true)
	legacy.session.combat.tasks[0].erase("execution")
	check(Codec.restore(target, legacy).ok and not target.combat.tasks[battle].has("execution"), "old idle combat snapshot remains loadable")
	# Campaign validates inactive scenes before committing current/global state.
	source.catalog.data.scenes[0].documents[0].fields.defaultSpawnCards = []
	source.catalog.data.scenes.append({"name": "Island", "documents": [{"fields": {"defaultSpawnCards": [], "questGroups": []}}]})
	var inactive := travel.duplicate(true)
	inactive.session.scene_name = "Island"
	inactive.session.world.scene = "Island"
	inactive.session.ai.scene = "Island"
	inactive.session.quests = {"CompletedQuests": [], "ActiveQuests": [], "QuestProgress": 0}
	source.campaign.saved_scenes["Island"] = inactive
	var campaign: Dictionary = source.campaign.capture()
	check(source.campaign._validate_snapshot(campaign).ok, "valid inactive-scene execution passes whole campaign staging")
	var before_campaign: String = JSON.stringify(source.campaign.capture(), "", true, true)
	campaign.scenes.Island.session.combat.tasks[0].execution.actor = 999
	check(not source.campaign.restore(campaign).ok, "malformed inactive-scene execution blocks entire campaign restore")
	check(JSON.stringify(source.campaign.capture(), "", true, true) == before_campaign, "inactive-scene failure preserves live campaign global progress and slot")

func projectile_scene_checkpoints() -> void:
	var live = combat_session()
	var data: Dictionary = live.catalog.data
	data.scenes[0].documents[0].fields.defaultSpawnCards = []
	data.scenes[0].documents.append({"script_class": "CombatManager", "fields": {"arrowProjectile": {"guid": "main-arrow"}}})
	data.scenes.append({"name": "Island", "documents": [{"fields": {"defaultSpawnCards": [], "questGroups": []}}, {"script_class": "CombatManager", "fields": {"arrowProjectile": {"guid": "island-arrow"}}}]})
	data.referenced_prefabs = [{"guid": "main-arrow", "documents": [{"script_class": "CombatProjectile", "fields": {"duration": 0.2}}]}, {"guid": "island-arrow", "documents": [{"script_class": "CombatProjectile", "fields": {"duration": 0.8}}]}]
	var island = Session.new()
	island.configure(live.catalog, 55, "Island")
	var hero: int = island.spawn_card("hero")
	var mob: int = island.spawn_card("mob")
	var battle: int = island.combat.start_combat([hero], [mob])
	island.combat.tasks[battle]["execution"] = {"phase": "travel", "remaining": 0.6, "actor": hero, "target": mob, "combat_type": 2, "attacker_position": Vector2.ZERO, "defender_position": Vector2.ZERO}
	var saved := Codec.capture(island)
	check(live.scene_name == "Main" and live.combat.projectile_duration(2) == 0.2, "live Main projectile duration differs from saved Island")
	check(live.combat.stage_state(saved.session.combat, island.cards, "Island").ok, "explicit helper snapshot scene overrides live scene without mutation")
	check(not live.combat.stage_state(saved.session.combat, island.cards, "Main").ok, "same remaining time invalid for shorter Main projectile")
	check(live.scene_name == "Main", "helper scene-context staging never mutates live scene")
	var before: String = JSON.stringify(Codec.capture(live), "", true, true)
	check(not Codec.restore(live, saved).ok and JSON.stringify(Codec.capture(live), "", true, true) == before, "direct mismatched-scene restore fails before helper mutation")
	check(Codec.restore(island, saved).ok, "direct restore into correctly configured Island accepts its own duration")
	live.campaign.saved_scenes["Island"] = saved
	var campaign: Dictionary = live.campaign.capture()
	check(live.campaign._validate_snapshot(campaign).ok, "inactive Island checkpoint validated against Island not live Main duration")
	var good_campaign: String = JSON.stringify(live.campaign.capture(), "", true, true)
	var bad: Dictionary = campaign.duplicate(true)
	bad.scenes.Island.session.combat.tasks[0].execution.remaining = 0.81
	check(not live.campaign.restore(bad).ok and JSON.stringify(live.campaign.capture(), "", true, true) == good_campaign, "inactive scene excessive duration rejects whole campaign transactionally")
	campaign.current_scene = "Island"
	check(live.campaign.restore(campaign).ok and live.scene_name == "Island" and live.combat.tasks[battle].execution.remaining == 0.6, "campaign switches to Island using saved-scene duration")
	# Converse case: current Island's longer duration must not admit Main excess.
	var shorter: Dictionary = saved.duplicate(true)
	shorter.session.scene_name = "Main"
	shorter.session.world.scene = "Main"
	shorter.session.ai.scene = "Main"
	live.campaign.saved_scenes["Main"] = shorter
	var invalid: Dictionary = live.campaign.capture()
	before = JSON.stringify(live.campaign.capture(), "", true, true)
	check(not live.campaign.restore(invalid).ok and JSON.stringify(live.campaign.capture(), "", true, true) == before, "inactive Main duration does not inherit live Island allowance")
