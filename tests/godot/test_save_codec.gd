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
