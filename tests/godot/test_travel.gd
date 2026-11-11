extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Campaign = preload("res://scripts/model/campaign.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "real catalog loaded")
	var session = Session.new()
	session.configure(catalog, 51)
	var campaign = Campaign.new()
	campaign.configure(session, "Main", 3)
	check(Campaign.next_slot([1, 3, 4]) == 2, "first free positive slot")
	var recipe: Dictionary = {}
	for entry in catalog.data.recipes:
		if entry.script_class == "TravelRecipe":
			recipe = entry
	check(recipe.fields.targetScenes == ["Main", "Island"], "real cyclic destination list")
	var portal: int = session.spawn_card(catalog.find_by_name("Grand Portal"), Vector2(15, 20))
	var stack: int = session.cards[portal].stack_id
	var villager: int = session.spawn_card(catalog.find_by_name("Villager"), Vector2(15, 20), stack)
	var sword: int = session.spawn_card(catalog.find_by_name("Sword"))
	check(session.equipment.equip(villager, sword), "equip traveler")
	session.cards[villager].health = 7
	var original_class: String = session.cards[villager].definition_guid
	var wood: int = session.spawn_card(catalog.find_by_name("Wood"), Vector2(8, 9))
	session.world.processed_days[7] = true
	session.day = 8
	session.elapsed = 23.5
	session.vendor_payments["51c2d41ab5d413649adfbe0e3bb29d85"] = 2
	session._discover_recipe(str(recipe.fields.id))
	var before: String = JSON.stringify(campaign.capture())
	var old_targets: Array = recipe.fields.targetScenes
	recipe.fields.targetScenes = ["Main", "Missing"]
	check(not campaign.travel(stack, recipe.guid).ok, "unknown destination rejected")
	check(JSON.stringify(campaign.capture()) == before, "rejection preserves all state")
	recipe.fields.targetScenes = old_targets
	var result: Dictionary = campaign.travel(stack, recipe.guid)
	check(result.ok, "Main to Island")
	if not result.ok:
		printerr(result)
		quit(1)
		return
	check(campaign.current_scene == "Island" and session.day == 1, "destination new clock")
	check(session.cards.size() == 4, "Island default plus two travelers and attached gear")
	var traveler: int = result.traveler_ids[villager]
	check(traveler != villager and session.cards[traveler].position.length() <= 1, "new identity and spawn position")
	check(session.cards[traveler].health == 7 and session.cards[traveler].uses_left == 0, "stats preserve post-consume zero uses")
	check(session.cards[traveler].definition_guid == original_class and session.equipment.equipped.has(traveler), "class and equipment restored")
	check(campaign.saved_scenes.Main.session.cards.size() == 1, "consumed source baseline excludes travelers and gear")
	check(session.discovered_recipes.has(str(recipe.fields.id)), "global recipe discovery")
	# Independent board cards permit a source-faithful round trip without reusing exhausted cards.
	var return_portal: int = session.spawn_card(catalog.find_by_name("Grand Portal"))
	var return_stack: int = session.cards[return_portal].stack_id
	session.spawn_card(catalog.find_by_name("Villager"), Vector2.ZERO, return_stack)
	session.day = 3
	result = campaign.travel(return_stack, recipe.guid)
	check(result.ok and campaign.current_scene == "Main", "Island to Main")
	check(session.day == 8 and session.elapsed == 23.5, "Main clock restored")
	check(session.world.processed_days.has(7) and session.world.scene_name == "Main", "Main world progress restored")
	check(session.cards.has(wood) and session.cards[wood].position == Vector2(8, 9), "Main board preserved")
	check(session.vendor_payments.values() == [2], "Main vendor installments restored")
	check(campaign.saved_scenes.Island.session.day == 3, "Island frozen independently")
	var reused_portal: int = result.traveler_ids[return_portal]
	var reused_villager: int = -1
	for card in session.world_cards():
		if card.base_definition_guid == catalog.find_by_name("Villager"):
			reused_villager = card.id
	check(session.move_to_stack(reused_villager, session.cards[reused_portal].stack_id), "reassemble exhausted travelers")
	result = campaign.travel(session.cards[reused_portal].stack_id, recipe.guid)
	check(result.ok and session.cards[result.traveler_ids[reused_portal]].uses_left == -1, "reused traveler preserves negative uses")
	check(session.day == 3 and session.world.scene_name == "Island", "Island return restores correct world and clock")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(campaign.capture()))
	var fresh = Session.new()
	fresh.configure(catalog, 8)
	var restored = Campaign.new()
	restored.configure(fresh)
	check(restored.restore(snapshot).ok, "campaign JSON roundtrip")
	check(restored.slot_number == 3 and restored.current_scene == "Island" and restored.saved_scenes.size() == 2, "slot and scene index retained")
	before = JSON.stringify(restored.capture())
	snapshot.scenes.Main.session.cards[0].id = -1
	check(not restored.restore(snapshot).ok and JSON.stringify(restored.capture()) == before, "inactive scene corruption rejected atomically")
	var path := "user://travel_test_campaign.json"
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	check(campaign.save_file(path).ok, "campaign file saved")
	check(campaign.save_file(path).ok, "validated backup created")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	var recovered: Dictionary = restored.load_file(path)
	check(recovered.ok and recovered.recovered, "corrupt primary recovers validated backup")
	check(restored.current_scene == "Island" and restored.slot_number == 3, "disk restored scene and slot")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	_test_recipe_tick(catalog, recipe)
	print("Travel checks: ", checks, ", failures: ", failures)
	quit(1 if failures else 0)

func _test_recipe_tick(catalog, recipe: Dictionary) -> void:
	var session = Session.new()
	session.configure(catalog, 902)
	var portal: int = session.spawn_card(catalog.find_by_name("Grand Portal"))
	var villager: int = session.spawn_card(catalog.find_by_name("Villager"))
	check(session.move_to_stack(villager, session.cards[portal].stack_id), "runtime travel stack assembled")
	var stack = session.stacks[session.cards[portal].stack_id]
	check(stack.recipe_guid == str(recipe.guid), "runtime selects TravelRecipe")
	session.tick(float(recipe.fields.craftingDuration))
	check(session.scene_name == "Island" and session.campaign.current_scene == "Island", "recipe completion changes active scene")
	check(session.elapsed == 0, "old tick never advances destination clock")
	check(session.campaign.saved_scenes.has("Main"), "runtime departure snapshot saved")
