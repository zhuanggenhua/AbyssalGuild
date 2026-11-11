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
