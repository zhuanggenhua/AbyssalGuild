extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init(): call_deferred("run")
func run():
	var c = Catalog.new()
	var loaded := c.load_file()
	check(loaded == OK, "licensed catalog required")
	if loaded != OK: quit(1); return
	var recipe := ""
	for entry in c.data.recipes:
		if entry.script_class == "TravelRecipe": recipe = entry.guid
	var qid := ""
	for entry in c.data.quests:
		var f: Dictionary = entry.fields
		if int(f.get("type", -1)) == 0 and int(f.get("targetAmount", 0)) == 2 and c.ref_guid(f.get("targetCard", {})) == c.find_by_name("Villager"):
			qid = str(f.id)
	check(not recipe.is_empty() and not qid.is_empty(), "source travel and Have2 Villagers bindings")
	var s = Session.new(); s.configure(c, 88, "Island")
	var portal: int = s.spawn_card(c.find_by_name("Grand Portal"))
	var sid: int = s.cards[portal].stack_id
	s.spawn_card(c.find_by_name("Villager"), Vector2.ZERO, sid)
	var dest = Session.new(); dest.configure(c, 99, "Main"); dest._next_id = 2000
	dest.spawn_card(c.find_by_name("Villager"))
	check(dest.quest_tracker.definitions.has(qid), "quest belongs to source Main group")
	dest.quest_tracker.active_quests.append({"id": qid, "status": 1, "current_amount": 1})
	var saved := Codec.capture(dest); s.campaign.saved_scenes["Main"] = saved
	check(s.campaign.travel(sid, recipe).ok, "real recipe return accepted")
	check(s.quest_tracker.save_state() == saved.session.quests, "source saved quest amount preserved")
	var copy = Session.new(); copy.configure(c, 0, "Main")
	var restored: Dictionary = copy.campaign.restore(s.campaign.capture())
	check(restored.ok, "arrival save loads")
	check(copy.quest_tracker.save_state() == saved.session.quests, "arrival roundtrip unchanged")
	copy.spawn_card(c.find_by_name("Wood"))
	check(copy.quest_tracker.completed_ids.has(qid), "post-load real stats event completes Have")
	# A separate equipped traveler exercises real class substitution/owner remap.
	var geared = Session.new(); geared.configure(c, 51, "Main")
	var gp: int = geared.spawn_card(c.find_by_name("Grand Portal"))
	var gv: int = geared.spawn_card(c.find_by_name("Villager"), Vector2.ZERO, geared.cards[gp].stack_id)
	var sword: int = geared.spawn_card(c.find_by_name("Sword"))
	check(geared.equipment.equip(gv, sword), "source equipment accepted")
	var island = Session.new(); island.configure(c, 78, "Island"); island._next_id = 1000
	island.spawn_card(c.find_by_name("Wood"), Vector2(3, 4))
	geared.campaign.saved_scenes["Island"] = Codec.capture(island)
	var result: Dictionary = geared.campaign.travel(geared.cards[gp].stack_id, recipe)
	check(result.ok, "real equipped revisit")
	if result.ok:
		check(geared.equipment.owners[result.traveler_ids[sword]] == result.traveler_ids[gv], "real equipment owner remap intact")
		check(geared.cards.has(1000), "saved destination retained")
		check(geared._next_id > int(result.traveler_ids[sword]), "allocator retained")
	print("Source saved travel quest window: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
