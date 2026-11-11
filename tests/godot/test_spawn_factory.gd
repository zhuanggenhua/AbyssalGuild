extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
var checks: int = 0
var failures: int = 0
var session
var selected: int = -1
var calls: Array = []
var events: Array = []
var try_reentry: bool = false
var reentry_result: int = 0
var layouts: int = 0
func resolve_layout() -> void:
	layouts += 1
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func choose(id: int, ignored: int) -> int:
	calls.append({"id": id, "ignored": ignored, "height": session.spawn_query_height})
	if try_reentry:
		reentry_result = session.spawn_card("material")
	return selected
func record(kind: String, payload: Dictionary) -> void:
	var id: int = int(payload.get("card_id", -1))
	events.append({"kind": kind, "payload": payload.duplicate(), "exists": session.cards.has(id), "stack": session.cards[id].stack_id if session.cards.has(id) else -1, "layouts": layouts})
func _init() -> void:
	var catalog = Catalog.new()
	var definitions: Array = []
	var fixtures := {"material": {"category": 4}, "coin": {"category": 7}, "chest": {"category": 6, "capacity": 2}, "mob": {"category": 9, "isAggressive": true}, "hero": {"category": 2}, "area": {"category": 10, "loot": [{"Card": {"guid": "mob"}, "Weight": 1}]}}
	for guid in fixtures:
		definitions.append({"guid": guid, "script_class": "ChestDefinition" if guid == "chest" else "CardDefinition", "fields": fixtures[guid]})
	var rules: Array = []
	rules.resize(144)
	rules.fill(1)
	catalog.configure({"cards": definitions, "packs": [{"guid": "pack", "script_class": "PackDefinition", "fields": {"slots": [{"Entries": [{"Card": {"guid": "mob"}, "Weight": 1}]}]}}], "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}]})
	session = Session.new()
	session.configure(catalog, 10)
	session.event_occurred.connect(record)
	session.spawn_target_selector = choose
	session.spawn_layout_resolver = resolve_layout
	var target: int = session.spawn_card("material")
	selected = session.cards[target].stack_id
	calls.clear()
	events.clear()
	var incoming: int = session.spawn_card("material")
	check(session.cards[incoming].stack_id == selected, "automatic spawn merges into selected compatible stack")
	var created: Dictionary = events.filter(func(e): return e.kind == "card_created").back()
	check(created.stack == selected, "created event observes final attached stack")
	check(created.layouts == layouts and layouts == 2, "creation event follows layout completion")
	check(calls.size() == 1 and session.spawn_query_height == 0, "selector queried once and transient height restored")
	var before_layouts: int = layouts
	var singleton: int = session.spawn_card("material", Vector2.ZERO, -1, {"refuse_attach": true})
	check(session.cards[singleton].stack_id != selected and calls.size() == 1, "RefuseAll skips selector")
	check(layouts == before_layouts + 1, "RefuseAll still resolves overlaps")
	var ignored: int = session.spawn_card("material", Vector2.ZERO, -1, {"ignored_stack_id": selected})
	check(session.cards[ignored].stack_id != selected and calls.back().ignored == selected, "model rejects ignored target even if selector returns it")
	var before: int = calls.size()
	var direct: int = session.spawn_card("material", Vector2.ZERO, selected)
	check(session.cards[direct].stack_id == selected and calls.size() == before, "explicit target preserves direct native construction")
	selected = 999999
	var stale: int = session.spawn_card("material")
	check(session.cards.has(stale), "stale selector target leaves singleton safely")
	selected = session.cards[target].stack_id
	try_reentry = true
	before = session.cards.size()
	session.spawn_card("material")
	try_reentry = false
	check(reentry_result == -1 and session.cards.size() == before + 1, "candidate selector cannot reenter card factory")
	# Atomic friendly suppression: no ID, event, selector or RNG changes.
	session.friendly_mode = true
	var next_id: int = session._next_id
	var rng_state: int = session.rng.state
	before = calls.size()
	var event_count: int = events.size()
	check(session.spawn_card("mob") == -1, "friendly factory suppresses aggressive definition")
	check(session._next_id == next_id and calls.size() == before and events.size() == event_count and session.rng.state == rng_state, "suppression has no allocation or creation side effects")
	var pack: int = session.spawn_card("pack", Vector2.ZERO, -1, {"refuse_attach": true})
	check(pack >= 0, "friendly mode still permits packs")
	check(session.open_pack(pack) == -1 and not session.cards.has(pack), "suppressed pack output still spends last slot and pack")
	# Source emits completion even when friendly mode suppresses crafted result.
	catalog.definitions["recipe"] = {"guid": "recipe", "script_class": "RecipeDefinition", "fields": {"resultingCard": {"guid": "mob"}, "requiredIngredients": [{"card": {"guid": "material"}, "count": 1, "consumptionMode": 2}]}}
	var input: int = session.spawn_card("material", Vector2.ZERO, -1, {"refuse_attach": true})
	var processing = session.stacks[session.cards[input].stack_id]
	processing.recipe_guid = "recipe"
	events.clear()
	session._complete_recipe(processing)
	check(not session.cards.has(input), "suppressed craft still consumes ingredient")
	var crafted: Array = events.filter(func(e): return e.kind == "crafted")
	check(crafted.size() == 1 and crafted[0].payload.definition_guid == "mob" and crafted[0].payload.card_id == -1, "suppressed craft publishes declared output completion")
	# Exploration likewise reports after attempting suppressed loot.
	var area: int = session.spawn_card("area", Vector2.ZERO, -1, {"refuse_attach": true})
	events.clear()
	Special.execute(session, session.stacks[session.cards[area].stack_id], {"script_class": "ExplorationRecipe", "fields": {"requiredIngredients": []}})
	check(events.filter(func(e): return e.kind == "exploration_finished").size() == 1, "suppressed exploration loot still reports exploration")
	# Chest can consume the just-initialized instance before its creation event.
	var chest: int = session.spawn_card("chest", Vector2.ZERO, -1, {"refuse_attach": true})
	session.world.currency_guid = "coin"
	selected = session.cards[chest].stack_id
	events.clear()
	var deposited: int = session.spawn_card("coin")
	check(deposited >= 0 and not session.cards.has(deposited) and session.cards[chest].stored_coins == 1, "automatic chest interception consumes spawned coin")
	created = events.filter(func(e): return e.kind == "card_created").back()
	check(created.payload.card_id == deposited and created.payload.base_definition_guid == "coin" and not created.exists, "consumed created event retains valid metadata")
	calls.clear()
	check(session.world.withdraw_coin(chest, true), "chest withdrawal succeeds")
	check(calls.back().ignored == selected and session.cards[chest].stored_coins == 0, "withdrawal cannot redeposit into originating chest")
	# Craft output excludes its own stack but can join another compatible stack.
	catalog.definitions.recipe.fields.resultingCard = {"guid": "material"}
	catalog.definitions.recipe.fields.requiredIngredients[0].consumptionMode = 1
	input = session.spawn_card("material", Vector2.ZERO, -1, {"refuse_attach": true})
	processing = session.stacks[session.cards[input].stack_id]
	processing.recipe_guid = "recipe"
	selected = session.cards[target].stack_id
	calls.clear()
	session._complete_recipe(processing)
	check(calls.size() == 1 and calls[0].ignored == processing.id, "ordinary craft passes source-stack exclusion")
	check(session.stacks[selected].card_ids.size() > 1, "ordinary craft may attach to another stack")
	# Source-derived pack contents retain their vertical attachment query offset.
	if catalog.load_file() != OK:
		print("Spawn factory: %d synthetic checks, %d failures; source-data branch SKIPPED" % [checks, failures])
		quit(1 if failures else 0)
		return
	session = Session.new()
	session.configure(catalog, 10)
	session.spawn_target_selector = choose
	selected = -1
	var real_pack: String = catalog.find_by_name("01_Pack_Beginning", "packs")
	check(not real_pack.is_empty(), "source Beginning pack present")
	var slime: String = catalog.find_by_name("Slime")
	var has_slime: bool = false
	for slot in catalog.fields(real_pack).slots:
		for entry in slot.get("Entries", []):
			has_slime = has_slime or catalog.ref_guid(entry.get("Card", {})) == slime
	check(has_slime, "real source pack includes aggressive output")
	catalog.definitions[real_pack].fields.slots = [{"Entries": [{"Card": {"guid": slime}, "Weight": 1}]}]
	pack = session.spawn_card(real_pack, Vector2.ZERO, -1, {"refuse_attach": true})
	calls.clear()
	check(session.open_pack(pack) >= 0 and calls.back().height == 0.1, "pack content central hook receives source 0.1 height")
	session.friendly_mode = true
	pack = session.spawn_card(real_pack, Vector2.ZERO, -1, {"refuse_attach": true})
	check(session.open_pack(pack) == -1, "real aggressive source definition respects friendly mode")
	# Encounter RefuseAll bypasses candidate selection for every card.
	calls.clear()
	var encounter: Dictionary = session.world.finish_day(5)
	check(encounter.spawned.size() == 1 and calls.is_empty(), "source day-five encounter refuses automatic attachment")
	# Reconstruction does not call placement hooks or replay creation events.
	var saved: Dictionary = Codec.capture(session)
	calls.clear()
	var restored: Dictionary = Codec.restore(session, saved)
	check(restored.ok and calls.is_empty(), "native restore bypasses spawn placement")
	print("Spawn factory: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
