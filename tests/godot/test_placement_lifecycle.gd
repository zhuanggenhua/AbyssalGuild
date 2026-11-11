extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
const Layout = preload("res://scripts/model/board_layout.gd")
var checks := 0
var failures := 0
var events: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func resolve(session, size: Vector2) -> void:
	events.append("resolve")
	var states: Array = []
	for stack in session.stacks.values():
		states.append(Layout.stack_state(stack.id, stack.position, size, stack.card_ids.size()))
	var result: Dictionary = Layout.resolve_overlaps(states, [], Rect2(-30, -30, 60, 60))
	for state in result.stacks:
		var stack = session.stacks[state.id]
		stack.position = state.position
		for id in stack.card_ids:
			session.cards[id].position = state.position
func growth(catalog, recipe: Dictionary, label: String) -> void:
	var session = Session.new()
	session.configure(catalog)
	var fields: Dictionary = recipe.fields
	var output: String = catalog.ref_guid(fields.resultingCard)
	var grower_guid: String = catalog.ref_guid(fields.requiredIngredients[0].card)
	var grower: int = session.spawn_card(grower_guid)
	var stack = session.stacks[session.cards[grower].stack_id]
	var seed: int = session.spawn_card(output, Vector2.ZERO, stack.id)
	var width: float = Special._card_width(catalog, output, "Main")
	# A neighbouring seed stack occupies the split destination. The source's
	# first overlap pass must move it before the new output queries attachment.
	var obstacle: int = session.spawn_card(output, session.card_target_position(seed) + Vector2(width, 0))
	var initial: Vector2 = session.cards[obstacle].position
	events.clear()
	session.spawn_layout_resolver = resolve.bind(session, Vector2(maxf(width, 1), 2))
	session.spawn_target_selector = func(_id, _ignored):
		events.append("select")
		check(session.cards[obstacle].position != initial, label + ": obstacle moved before output attachment")
		return -1
	Special.execute(session, stack, recipe)
	check(events == ["resolve", "select", "resolve"], label + ": split placement precedes output selection and placement")
	check(session.cards[seed].stack_id != stack.id, label + ": original seed survives in split stack")
	check(session.cards.size() == 4, label + ": exactly one output created")
	# No split (seed index zero) must not add a spurious placement pass.
	events.clear()
	session.spawn_target_selector = Callable()
	Special.execute(session, session.stacks[session.cards[seed].stack_id], recipe)
	check(events == ["resolve"], label + ": no-split path only resolves the output")
	session.spawn_layout_resolver = Callable()
func equipment(catalog, hero_guid: String, gear_guid: String, label: String) -> void:
	var session = Session.new()
	session.configure(catalog)
	var hero: int = session.spawn_card(hero_guid)
	var gear: int = session.spawn_card(gear_guid, Vector2(10, 0))
	check(session.equipment.equip(hero, gear), label + ": gear equipped")
	events.clear()
	session.spawn_layout_resolver = resolve.bind(session, Vector2(1, 2))
	var slot: int = int(catalog.fields(gear_guid).get("equipmentSlot", 0))
	check(session.equipment.unequip(hero, slot) == gear, label + ": unequip returns same item")
	check(events == ["resolve"], label + ": returned item resolved immediately")
	check(session.cards[hero].position != session.cards[gear].position, label + ": returned item no longer overlaps wearer")
	check(not session.equipment.owners.has(gear), label + ": ownership cleared")
	check(session.equipment.equip(hero, gear), label + ": re-equip original item")
	var replacement: int = session.spawn_card(gear_guid, Vector2(12, 0))
	events.clear()
	check(session.equipment.equip(hero, replacement), label + ": replace same-slot item")
	check(events == ["resolve"] and not session.equipment.owners.has(gear), label + ": replacement resolves old item synchronously")
	check(session.equipment.owners.get(replacement, -1) == hero, label + ": replacement ownership retained")
	events.clear()
	session.equipment.unequip_all(hero)
	check(events == ["resolve"] and not session.equipment.owners.has(replacement), label + ": unequip-all uses immediate return placement")
	session.spawn_layout_resolver = Callable()
func combat_return(catalog) -> void:
	var session = Session.new()
	session.configure(catalog)
	var hero: int = session.spawn_card("hero")
	var enemy: int = session.spawn_card("enemy")
	var task: int = session.combat.start_combat([hero], [enemy])
	check(task >= 0, "combat return fixture starts")
	events.clear()
	session.spawn_layout_resolver = resolve.bind(session, Vector2(1, 2))
	var before: Vector2 = session.cards[enemy].position
	session.combat.remove_combatant(hero)
	check(events.is_empty(), "combat remove and finish do not run equipment placement")
	check(session.combat.tasks.is_empty(), "combat ends after attacker removed")
	check(session.cards[enemy].position == before, "survivor keeps its slot until combat presentation clamps")
	check(session.stacks.has(session.cards[hero].stack_id) and session.stacks.has(session.cards[enemy].stack_id), "combat returns both fighters to registered board stacks")
	session.spawn_layout_resolver = Callable()
func _init() -> void:
	var catalog = Catalog.new()
	catalog.configure({"cards": [
		{"guid": "grower", "script_class": "GrowerDefinition", "fields": {"category": 6}},
		{"guid": "seed", "script_class": "CardDefinition", "fields": {"category": 3}},
		{"guid": "hero", "fields": {"category": 2, "faction": 1}},
		{"guid": "enemy", "fields": {"category": 9, "faction": 2}},
		{"guid": "gear", "fields": {"category": 5, "equipmentSlot": 0}}]})
	var recipe := {"script_class": "GrowthRecipe", "fields": {"resultingCard": {"guid": "seed"}, "requiredIngredients": [{"card": {"guid": "grower"}, "count": 1, "consumptionMode": 1}]}}
	growth(catalog, recipe, "synthetic growth")
	equipment(catalog, "hero", "gear", "synthetic equipment")
	combat_return(catalog)
	var source = Catalog.new()
	if source.load_file() == OK:
		var count := 0
		for entry in source.data.get("recipes", []):
			if entry.get("script_class", "") == "GrowthRecipe":
				growth(source, entry, str(entry.name))
				count += 1
		check(count == 6, "all six imported growth recipes exercised")
		var gear := ""
		for entry in source.data.cards:
			if int(entry.fields.get("category", 0)) == 5:
				gear = str(entry.guid)
				break
		equipment(source, source.find_by_name("Villager"), gear, "imported equipment")
	else:
		print("SKIP: private source-data placement checks unavailable")
	print("Placement lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
