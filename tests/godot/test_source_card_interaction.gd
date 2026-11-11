extends SceneTree
## Private source-data checks; no source strings or assets are copied into fixtures.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Card = preload("res://scripts/model/card.gd")
const Stack = preload("res://scripts/model/stack.gd")
const Descriptors = preload("res://scripts/ui/card_interaction_descriptors.gd")
const SaveCodec = preload("res://scripts/model/save_codec.gd")
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func _init() -> void:
	var catalog = Catalog.new()
	if catalog.load_file() != OK:
		print("Private card interaction: SKIP (private data not imported)")
		quit()
		return
	var session = Session.new()
	session.configure(catalog, 835)
	var cards_checked: int = 0
	var characters: int = 0
	var recipe_count: int = 0
	for entry in catalog.data.cards:
		session.cards.clear()
		session.stacks.clear()
		var stack = Stack.new(1)
		stack.card_ids = [2]
		session.stacks[1] = stack
		var card = Card.new(2, str(entry.guid), entry.fields)
		card.stack_id = 1
		session.cards[2] = card
		var info: Dictionary = Descriptors.hover_info(session, 2)
		check(info.header == str(entry.fields.get("displayName", entry.fields.get("id", entry.guid))), "actual source display name")
		check(info.body.begins_with(str(entry.fields.get("description", ""))), "actual source description preserved")
		if int(entry.fields.get("category", 0)) == 2:
			characters += 1
			var stats: Dictionary = session.equipment.stats(2)
			check(info.body.contains("Health (%s/%s)" % [card.health, stats.maxHealth]), "actual character effective health")
			if int(entry.fields.get("combatType", 0)) != 0:
				check(info.body.ends_with("Crit. Multiplier (%s)" % stats.criticalMultiplier), "actual source combat-stat block")
		cards_checked += 1
	for entry in catalog.data.recipes:
		if float(entry.fields.get("craftingDuration", 0)) <= 0: continue
		session.cards.clear()
		session.stacks.clear()
		var stack = Stack.new(1)
		stack.position = Vector2(2, -3)
		session.stacks[1] = stack
		var id: int = 2
		for ingredient in entry.fields.get("requiredIngredients", []):
			var guid: String = catalog.ref_guid(ingredient.card)
			for index in int(ingredient.count):
				var card = Card.new(id, guid, catalog.fields(guid))
				card.stack_id = 1
				session.cards[id] = card
				stack.card_ids.append(id)
				id += 1
		if stack.card_ids.is_empty(): continue
		check(session.matches_recipe(stack, entry.fields), "actual source ingredient fixture matches")
		stack.recipe_guid = str(entry.guid)
		stack.progress = float(entry.fields.craftingDuration) * 0.375
		var rng_before: int = session.rng.state
		var before: String = JSON.stringify(SaveCodec.capture(session))
		var progress: Dictionary = Descriptors.crafting_progress(session)
		check(progress.has(1) and is_equal_approx(progress[1].ratio, 0.375), "actual recipe duration normalized")
		check(progress[1].anchor.is_equal_approx(Vector3(2, 0, -2.45)), "actual recipe stack anchor")
		var info: Dictionary = Descriptors.hover_info(session, stack.card_ids.back())
		check(info.header == str(entry.fields.get("displayName", entry.fields.get("id", entry.guid))) and info.kind == "craft", "actual source craft hover takes precedence")
		check(JSON.stringify(SaveCodec.capture(session)) == before and session.rng.state == rng_before, "private recipe display preserves snapshot and RNG")
		recipe_count += 1
	check(cards_checked > 0 and characters > 0 and recipe_count > 0, "private source branches are required")
	print("Private card interaction: %d checks passed (%d cards, %d characters, %d recipes); no GPU/manual visual acceptance" % [checks, cards_checked, characters, recipe_count])
	quit()
