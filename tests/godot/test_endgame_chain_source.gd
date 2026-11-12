extends SceneTree
## Licensed-catalog model regression, not natural progression or GUI acceptance.
## Prerequisite cards are fixture-spawned; kill_card tests death/loot routing,
## not whether a player party can defeat these enemies in combat.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func spawn(s, name: String) -> int:
	return s.spawn_card(s.catalog.find_by_name(name), Vector2(20, 20), -1, {"refuse_attach": true})

func find_card(s, name: String) -> int:
	var guid: String = s.catalog.find_by_name(name)
	for card in s.world_cards():
		if card.base_definition_guid == guid: return card.id
	return -1

func _init() -> void:
	var c = Catalog.new()
	if c.load_file() != OK:
		printerr("FAIL: Licensed catalog required for endgame chain")
		quit(1); return
	var s = Session.new(); s.configure(c, 173)
	var altar: int = spawn(s, "Sacrificial Altar")
	# The acolyte's source loot supplies the summoning ingredient.
	var acolyte: int = spawn(s, "Crimson Acolyte")
	check(s.kill_card(acolyte), "acolyte death uses normal kill path")
	var chalice: int = find_card(s, "Blood Chalice")
	check(chalice > 0, "acolyte loot creates Blood Chalice")
	if chalice < 0:
		quit(1); return
	check(s.move_to_stack(chalice, s.cards[altar].stack_id), "chalice legally joins altar")
	var ritual = s.stacks[s.cards[altar].stack_id]
	check(c.get_definition(ritual.recipe_guid).get("name") == "Recipe_DemonLord", "real ritual recipe selected")
	s.tick(5.01)
	var demon: int = find_card(s, "Demon Lord")
	check(demon > 0 and not s.cards.has(chalice) and s.cards.has(altar), "ritual consumes chalice, preserves altar, spawns Demon Lord")
	if demon < 0:
		quit(1); return
	check(s.kill_card(demon), "Demon Lord death uses normal kill path")
	var core: int = find_card(s, "Abyssal Core")
	check(core > 0 and not s.cards.has(demon), "Demon Lord drops Abyssal Core")
	if core < 0:
		quit(1); return
	var build_stack: int = s.cards[core].stack_id
	for name in ["Stone", "Brick"]:
		for _i in 5:
			check(s.move_to_stack(spawn(s, name), build_stack), "portal material legally stacks")
	var villagers: Array = []
	var swords: Array = []
	for _i in 3:
		var villager: int = spawn(s, "Villager")
		var sword: int = spawn(s, "Sword")
		check(s.equipment.equip(villager, sword), "portal worker equipped")
		check(s.cards[villager].definition_guid != s.cards[villager].base_definition_guid, "equipped worker is transformed")
		check(s.move_to_stack(villager, build_stack), "transformed worker legally joins portal materials")
		villagers.append(villager); swords.append(sword)
	check(c.get_definition(s.stacks[build_stack].recipe_guid).get("name") == "Recipe_GrandPortal", "three transformed villagers match actual portal recipe")
	s.tick(30.01)
	var portal: int = find_card(s, "Grand Portal")
	check(portal > 0 and not s.cards.has(core), "actual portal output consumes the core")
	check(find_card(s, "Stone") == -1 and find_card(s, "Brick") == -1, "portal consumes all ten materials")
	for id in villagers:
		check(s.cards.has(id) and s.equipment.equipped.has(id), "portal retains transformed worker and gear")
	if portal < 0:
		quit(1); return
	# Take only the top worker, leaving two workers and their equipment in Main.
	var traveler: int = villagers.back()
	var traveler_class: String = s.cards[traveler].definition_guid
	var traveler_health: int = s.cards[traveler].health
	check(s.move_to_stack(traveler, s.cards[portal].stack_id), "one transformed worker joins completed portal")
	var travel_recipe: String = s.stacks[s.cards[portal].stack_id].recipe_guid
	check(c.get_definition(travel_recipe).get("script_class") == "TravelRecipe", "completed portal selects travel")
	s.tick(float(c.fields(travel_recipe).get("craftingDuration", 5)) + 0.01)
	check(s.scene_name == "Island" and s.elapsed == 0, "timed departure reaches fresh Island without advancing its clock")
	var arrived: int = find_card(s, "Villager")
	check(arrived > 0, "traveler retains villager base identity")
	if arrived < 0:
		quit(1); return
	check(s.cards[arrived].definition_guid == traveler_class and s.cards[arrived].health == traveler_health, "arrival retains transformed class and health")
	check(s.equipment.equipped.has(arrived) and s.cards[arrived].uses_left == 0, "arrival retains gear and post-consume uses")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.campaign.capture()))
	var restored = Session.new(); restored.configure(c, 1)
	check(restored.campaign.restore(saved).ok, "endgame arrival survives campaign JSON restore")
	var return_portal: int = find_card(restored, "Grand Portal")
	var return_worker: int = find_card(restored, "Villager")
	check(restored.move_to_stack(return_worker, restored.cards[return_portal].stack_id), "restored exhausted travelers can reassemble")
	restored.tick(float(c.fields(travel_recipe).get("craftingDuration", 5)) + 0.01)
	check(restored.scene_name == "Main", "same completed portal returns to Main")
	check(restored.cards.has(altar), "Main altar preserved")
	for id in villagers.slice(0, 2):
		check(restored.cards.has(id) and restored.equipment.equipped.has(id), "Main workers and equipment preserved without duplication")
	check(restored.cards[find_card(restored, "Grand Portal")].uses_left == -1, "return preserves source's exhausted portal semantics")
	print("Source endgame chain: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
