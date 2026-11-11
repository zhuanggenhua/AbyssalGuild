extends RefCounted
## Multi-scene owner. Session and SaveCodec integration is deliberately explicit.
const Codec = preload("res://scripts/model/save_codec.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Special = preload("res://scripts/model/special_recipes.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
const FORMAT = "abyssal-guild-campaign"
var _session: WeakRef
var current_scene: String = "Main"
var slot_number: int = 1
var saved_scenes: Dictionary = {}

func configure(session, scene_name: String = "Main", slot: int = 1) -> void:
	_session = weakref(session)
	current_scene = scene_name
	slot_number = slot

static func next_slot(taken: Array) -> int:
	var candidate := 1
	while candidate in taken:
		candidate += 1
	return candidate

func _defaults(scene_name: String) -> Dictionary:
	for scene in _session.get_ref().catalog.data.get("scenes", []):
		if scene.get("name") == scene_name:
			for document in scene.get("documents", []):
				if document.get("fields", {}).has("defaultSpawnCards"):
					return document.fields
	return {}

func _temporary(scene_name: String):
	var live = _session.get_ref()
	var catalog = Catalog.new()
	catalog.configure(live.catalog.data)
	var session = live.get_script().new()
	session.configure(catalog, live.rng.seed, scene_name)
	session.friendly_mode = live.friendly_mode
	session.quest_tracker.configure(catalog, scene_name)
	return session

func _random_position(session) -> Vector2:
	var point := Vector3(2, 2, 2)
	while point.length_squared() > 1:
		point = Vector3(session.rng.randf_range(-1, 1), session.rng.randf_range(-1, 1), session.rng.randf_range(-1, 1))
	return Vector2(point.x, point.z)

func _new_scene(scene_name: String, next_id: int):
	var session = _temporary(scene_name)
	session._next_id = next_id
	session.day_duration = _session.get_ref().day_duration
	session.quest_tracker.start_new_game(session)
	var defaults := _defaults(scene_name)
	var center: Dictionary = defaults.get("defaultSpawnPosition", {})
	for reference in defaults.get("defaultSpawnCards", []):
		var position := Vector2(float(center.get("x", 0)), float(center.get("z", 0))) + _random_position(session) * float(defaults.get("defaultSpawnRadius", 1))
		session.spawn_card(session.catalog.ref_guid(reference), position, -1, {"refuse_attach": session.catalog.get_definition(session.catalog.ref_guid(reference)).get("script_class", "") != "PackDefinition"})
	return session

## Fully staged transaction: no live mutation or public event on rejection.
func travel(stack_id: int, recipe_guid: String) -> Dictionary:
	var live = _session.get_ref()
	var recipe: Dictionary = live.catalog.get_definition(recipe_guid)
	if recipe.get("script_class") != "TravelRecipe" or not live.stacks.has(stack_id):
		return Codec._fail("Invalid travel recipe or stack")
	var scenes = recipe.fields.get("targetScenes", [])
	if not scenes is Array or scenes.is_empty() or current_scene not in scenes:
		return Codec._fail("Current scene is absent from travel cycle")
	var target: String = str(scenes[(scenes.find(current_scene) + 1) % scenes.size()])
	if target == current_scene or _defaults(target).is_empty() or not live.matches_recipe(live.stacks[stack_id], recipe.fields):
		return Codec._fail("Invalid destination or travel ingredients")
	var source = _temporary(current_scene)
	var loaded := Codec.restore(source, Codec.capture(live))
	if not loaded.ok:
		return loaded
	var ids: Array = source.stacks[stack_id].card_ids.duplicate()
	# Hold model references across consumption, mirroring source's pre-consume list.
	var travelers: Array = []
	var traveler_refs: Array = []
	var gear: Dictionary = source.equipment.save_state()
	var gear_cards := {}
	for id in ids:
		travelers.append(_card_data(source.cards[id]))
		traveler_refs.append(source.cards[id])
		for item in source.equipment.equipped.get(id, {}).values():
			gear_cards[item] = _card_data(source.cards[item])
	Special.consume(source, source.stacks[stack_id], recipe.fields)
	for index in travelers.size():
		travelers[index].uses_left = traveler_refs[index].uses_left
	# Explicit migration policy: retained ingredients travel too, never duplicate.
	for id in ids:
		source._remove_card(id)
	var baseline := Codec.capture(source)
	var destination = _temporary(target)
	if saved_scenes.has(target):
		loaded = Codec.restore(destination, saved_scenes[target])
		if not loaded.ok:
			return loaded
	else:
		destination = _new_scene(target, source._next_id)
	destination._next_id = maxi(destination._next_id, source._next_id)
	destination.discovered_recipes.merge(live.discovered_recipes, true)
	var remap := {}
	for traveler in travelers:
		var id: int = _restore_card(destination, traveler, _random_position(destination))
		if id < 0:
			return Codec._fail("Traveler rejected by destination card factory")
		remap[traveler.id] = id
	for record in gear.wearers:
		if not remap.has(record.wearer):
			continue
		var wearer: int = remap[record.wearer]
		destination.equipment.equipped[wearer] = {}
		for entry in record.items:
			var item: int = _restore_card(destination, gear_cards[entry.item], destination.cards[wearer].position)
			if item < 0:
				return Codec._fail("Equipment rejected by destination card factory")
			Equipment.detach(destination, item)
			remap[entry.item] = item
			destination.equipment.equipped[wearer][int(entry.slot)] = item
			destination.equipment.owners[item] = wearer
		if record.class_item != -1:
			destination.equipment.originals[wearer] = record.original
			destination.equipment.class_items[wearer] = remap[record.class_item]
	var snapshot := Codec.capture(destination)
	var valid := Codec._stage(destination, snapshot)
	if not valid.ok:
		return valid
	# Validation above makes this commit deterministic. Tracker must match destination.
	saved_scenes[current_scene] = baseline
	current_scene = target
	live.scene_name = target
	live.world.configure(live, target)
	live.ai.configure(live, live.world, target)
	live.quest_tracker.configure(live.catalog, target)
	loaded = Codec.restore(live, snapshot)
	if not loaded.ok:
		return loaded
	live.event_occurred.emit("scene_changed", {"scene": target})
	return {"ok": true, "scene": target, "traveler_ids": remap}

func _card_data(card) -> Dictionary:
	var result := {}
	for key in ["id", "definition_guid", "base_definition_guid", "uses_left", "nutrition", "health", "stored_coins"]:
		result[key] = card.get(key)
	return result

func _restore_card(session, original, position: Vector2) -> int:
	# Dynamic recipe cards may not be in an independently configured catalog.
	if session.catalog.get_definition(original.definition_guid).is_empty():
		Codec._recipe_card(session.catalog, original.definition_guid)
	var id: int = session.spawn_card(original.definition_guid, position, -1, {"refuse_attach": true})
	if id < 0 or not session.cards.has(id):
		return -1
	for key in ["base_definition_guid", "uses_left", "nutrition", "health", "stored_coins"]:
		session.cards[id].set(key, original.get(key))
	return id

## Save/index APIs return JSON-compatible dictionaries; persistence owned by caller.
func capture() -> Dictionary:
	var scenes := saved_scenes.duplicate(true)
	scenes[current_scene] = Codec.capture(_session.get_ref())
	return {"format": FORMAT, "version": 1, "slot_number": slot_number, "current_scene": current_scene, "scenes": scenes}

func restore(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary or snapshot.get("format") != FORMAT or snapshot.get("version") != 1 or not Codec._integer(snapshot.get("slot_number"), 1):
		return Codec._fail("Invalid campaign header")
	if not snapshot.get("scenes") is Dictionary or not snapshot.get("current_scene") is String or not snapshot.scenes.has(snapshot.current_scene):
		return Codec._fail("Invalid campaign scenes")
	for name in snapshot.scenes:
		if not name is String or _defaults(name).is_empty():
			return Codec._fail("Unknown campaign scene")
		var session = _temporary(name)
		var valid := Codec._stage(session, snapshot.scenes[name])
		if not valid.ok:
			return valid
	var live = _session.get_ref()
	current_scene = snapshot.current_scene
	slot_number = int(snapshot.slot_number)
	saved_scenes = snapshot.scenes.duplicate(true)
	live.scene_name = snapshot.current_scene
	live.world.configure(live, snapshot.current_scene)
	live.ai.configure(live, live.world, snapshot.current_scene)
	live.quest_tracker.configure(live.catalog, snapshot.current_scene)
	var result := Codec.restore(live, snapshot.scenes[snapshot.current_scene])
	if not result.ok:
		return result
	return {"ok": true}

func _validate_snapshot(snapshot: Variant) -> Dictionary:
	var temporary = _temporary(current_scene)
	var campaign = get_script().new()
	campaign.configure(temporary, current_scene)
	return campaign.restore(snapshot)

func save_file(path: String = "user://campaign.json") -> Dictionary:
	var snapshot := capture()
	var valid := _validate_snapshot(snapshot)
	if not valid.ok:
		return valid
	var encoded := JSON.stringify(snapshot, "", true, true)
	if encoded.to_utf8_buffer().size() > Codec.MAX_BYTES:
		return Codec._fail("Campaign exceeds size limit")
	var temporary := path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return Codec._fail("Cannot create campaign temporary file")
	file.store_string(encoded)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return Codec._fail("Campaign write failed: " + error_string(error))
	var read := Codec._read(temporary)
	if not read.ok or not _validate_snapshot(read.snapshot).ok:
		return Codec._fail("Campaign temporary verification failed")
	if FileAccess.file_exists(path):
		var old := Codec._read(path)
		if old.ok and _validate_snapshot(old.snapshot).ok:
			error = DirAccess.copy_absolute(path, path + ".bak.tmp")
			if error != OK:
				return Codec._fail("Campaign backup copy failed")
			error = DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak")
			if error != OK:
				return Codec._fail("Campaign backup rename failed")
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		return Codec._fail("Campaign commit failed: " + error_string(error))
	return {"ok": true, "path": path}

func load_file(path: String = "user://campaign.json") -> Dictionary:
	var errors: Array = []
	for candidate in [path, path + ".bak"]:
		var read := Codec._read(candidate)
		if not read.ok:
			errors.append(read.error)
			continue
		var snapshot = read.snapshot
		# Explicit legacy one-scene migration. No claim of Unity format support.
		if snapshot is Dictionary and snapshot.get("format") == Codec.FORMAT:
			var name: String = str(snapshot.get("session", {}).get("scene_name", "Main"))
			snapshot = {"format": FORMAT, "version": 1, "slot_number": slot_number, "current_scene": name, "scenes": {name: snapshot}}
		var result := restore(snapshot)
		if result.ok:
			return {"ok": true, "path": candidate, "recovered": candidate != path}
		errors.append(result.error)
	return Codec._fail("; ".join(errors))
