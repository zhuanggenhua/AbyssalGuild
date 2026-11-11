extends SceneTree
## Independent adversarial checkpoint tests; no view or private source required.
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
var checks := 0
var failures := 0
var changes := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func make():
	var catalog = Catalog.new()
	var documents := [{"script_class": "CardManager", "fields": {"defaultSpawnCards": []}}, {"fields": {"questGroups": []}}, {"script_class": "CameraController", "fields": {}}, {"script_class": "EncounterManager", "fields": {"allEncounters": [{"guid": "arrival"}]}}]
	catalog.configure({"cards": [{"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero", "category": 2, "faction": 1, "maxHealth": 10}}, {"guid": "food", "script_class": "CardDefinition", "fields": {"id": "food", "category": 3, "nutrition": 4}}, {"guid": "visitor", "script_class": "CardDefinition", "fields": {"id": "visitor", "category": 1}}], "settings": [{"guid": "settings", "script_class": "CardSettings", "fields": {"hungerPerCharacter": 2, "baseCardLimit": 100}}], "encounters": [{"guid": "arrival", "fields": {"id": "arrival-id", "type": 0, "dayValue": 2, "chance": 1.0, "count": 2, "oneTimeOnly": true, "maxCardsOnBoardLimit": 100, "notificationMessage": "Arrival", "cardToSpawn": {"guid": "visitor"}}}], "scenes": [{"name": "Main", "documents": documents}, {"name": "Island", "documents": documents.duplicate(true)}]})
	var session = Session.new()
	session.configure(catalog, 938)
	session.board_bounds = Rect2(-10, -10, 20, 20)
	return session

func canonical(session) -> String:
	return JSON.stringify(Codec.capture(session), "", true, true)

func reject(target, snapshot: Dictionary, label: String) -> void:
	var before := canonical(target)
	var count := changes
	check(not Codec.restore(target, snapshot).ok, label)
	check(canonical(target) == before and changes == count, label + " preserves live state RNG and signals")

func step(session) -> void:
	session.tick(maxf(0.0001, session.cycle.remaining) + 0.00001)

func _init() -> void:
	var source = make()
	var hero: int = source.spawn_card("hero")
	var food: int = source.spawn_card("food")
	source.cards[hero].health = 1
	source.day = 2
	var initial := Codec.capture(source)
	source.end_day()
	var snapshots := {}
	for index in 25:
		if not snapshots.has(source.cycle.stage): snapshots[source.cycle.stage] = Codec.capture(source)
		if source.phase == "ready": break
		step(source)
	check(snapshots.has("leftover_settle") and snapshots.has("encounter_notification") and snapshots.has("encounter_wait") and snapshots.has("ready"), "fixture reaches all effect and encounter boundaries")
	var target = make()
	target.changed.connect(func(): changes += 1)
	for name in snapshots:
		var snapshot: Dictionary = snapshots[name]
		check(Codec.restore(target, JSON.parse_string(JSON.stringify(snapshot, "", true, true))).ok, "valid stage roundtrip " + name)
		for frame in 30:
			if target.phase == "ready": break
			step(target)
		check(target.phase == "ready" and canonical(target) == canonical(source), "saved boundary resumes exactly once with original encounter RNG " + name)
		var bad := snapshot.duplicate(true)
		bad.session.cycle.remaining = float(snapshot.session.cycle.remaining) + 100
		reject(target, bad, "excessive stage duration " + name)
		bad = snapshot.duplicate(true)
		bad.session.phase = "playing"
		reject(target, bad, "phase-stage mismatch " + name)
		if name not in ["ready", "selling", "game_over", "await_feed", "idle"]:
			bad = snapshot.duplicate(true)
			bad.session.paused = false
			reject(target, bad, "active wait without paused flag " + name)
	for value in [null, {}, [], NAN, INF, -0.01, true, "0.1"]:
		var bad: Dictionary = snapshots.food_chew.duplicate(true)
		bad.session.cycle.remaining = value
		reject(target, bad, "invalid duration scalar")
	var bad: Dictionary = snapshots.leftover_settle.duplicate(true)
	bad.session.cycle.need = 1
	reject(target, bad, "leftover settle cannot replay already satisfied hunger")
	bad = snapshots.character_wait.duplicate(true)
	bad.session.cycle.need = 1
	reject(target, bad, "live character cannot skip unsatisfied hunger at character wait")
	check(Codec.restore(target, snapshots.leftover_settle).ok, "restore after consumption")
	var nutrition: int = target.cards[food].nutrition
	var health: int = target.cards[hero].health
	var rng_state: int = target.rng.state
	step(target)
	check(target.cycle.stage == "character_wait" and target.cards[food].nutrition == nutrition and target.cards[hero].health == health and target.rng.state == rng_state, "leftover resume does not charge heal or draw RNG twice")
	bad = snapshots.food_lift.duplicate(true)
	bad.session.cycle.foods.append(food)
	reject(target, bad, "selected food cannot also remain in pending food queue")
	bad = snapshots.food_lift.duplicate(true)
	bad.session.cycle.old_stack_id = hero
	reject(target, bad, "old food stack cannot alias a live card identity")
	bad = snapshots.food_lift.duplicate(true)
	bad.session.cycle.food_id = hero
	reject(target, bad, "selected food cannot alias character")
	bad = snapshots.food_lift.duplicate(true)
	for card in bad.session.cards:
		if int(card.id) == food:
			var old: int = int(card.stack_id)
			card.stack_id = -1
			bad.session.stacks = bad.session.stacks.filter(func(stack): return int(stack.id) != old)
	reject(target, bad, "selected food remains subject to registered ownership without orphan exception")
	bad = snapshots.food_lift.duplicate(true)
	bad.session.cycle.foods.append(int(bad.session.next_id))
	reject(target, bad, "queue cannot refer to never allocated future identity")
	# Missing historical food can be cancelled safely; absence is not an orphan.
	var missing: Dictionary = snapshots.food_lift.duplicate(true)
	var removed_stack := -1
	for card in missing.session.cards:
		if int(card.id) == food: removed_stack = int(card.stack_id)
	missing.session.cards = missing.session.cards.filter(func(card): return int(card.id) != food)
	missing.session.stacks = missing.session.stacks.filter(func(stack): return int(stack.id) != removed_stack)
	check(Codec.restore(target, missing).ok, "missing historically selected food accepted for safe cancellation")
	step(target)
	check(not target.cards.has(food) and target.cycle.stage == "character_wait", "missing food cancellation does not manufacture replacement nutrition")
	for vanished in [hero, food]:
		var interrupted = make()
		check(Codec.restore(interrupted, snapshots.food_lift).ok, "restore interruption fixture")
		interrupted.kill_card(vanished)
		check(Codec.restore(target, JSON.parse_string(JSON.stringify(Codec.capture(interrupted), "", true, true))).ok, "legitimate in-flight disappearance checkpoints without orphan exemptions")
		step(interrupted)
		step(target)
		check(canonical(interrupted) == canonical(target), "disappearance reload resumes identical cancellation hunger RNG and registration")
	var notification: Dictionary = snapshots.encounter_notification
	for change in ["claim", "one_time", "cursor", "missing_cycle"]:
		bad = notification.duplicate(true)
		match change:
			"claim": bad.session.world.processed_days.clear()
			"one_time": bad.session.world.completed_encounters.clear()
			"cursor": bad.session.cycle.spawn_index = 1
			"missing_cycle": bad.session.erase("cycle")
		reject(target, bad, "encounter replay guard " + change)
	bad = snapshots.encounter_wait.duplicate(true)
	bad.session.cycle.spawn_index = 3
	reject(target, bad, "encounter cursor cannot exceed count or lose ID correspondence")
	bad = snapshots.encounter_focus.duplicate(true)
	bad.session.cycle.spawned_ids[0] = int(bad.session.stacks[0].id)
	reject(target, bad, "spawned card cannot alias registered stack")
	check(Codec.restore(target, snapshots.encounter_wait).ok, "encounter checkpoint restores after first spawn")
	var first_count: int = target.cards.size()
	step(target)
	check(target.cards.size() == first_count + 1 and target.cycle.save_state().spawn_index == 2, "resume spawns only next unprocessed encounter card")
	var legacy := initial.duplicate(true)
	legacy.session.phase = "feeding"
	legacy.session.paused = true
	legacy.session.erase("cycle")
	check(Codec.restore(target, legacy).ok and target.cycle.stage == "await_feed", "legacy feeding infers awaiting confirmation not pending effect")
	nutrition = target.cards[food].nutrition
	target.tick(100)
	check(target.cards[food].nutrition == nutrition and target.cycle.stage == "await_feed", "legacy wait cannot consume without explicit Feed")
	# Inactive scene state must be validated before current/global campaign state.
	var inactive: Dictionary = snapshots.leftover_settle.duplicate(true)
	inactive.session.scene_name = "Island"
	inactive.session.world.scene = "Island"
	inactive.session.ai.scene = "Island"
	target.campaign.saved_scenes["Island"] = inactive
	var campaign: Dictionary = target.campaign.capture()
	check(target.campaign._validate_snapshot(campaign).ok, "valid inactive pending cycle stages successfully")
	var before_campaign := JSON.stringify(target.campaign.capture(), "", true, true)
	campaign.scenes.Island.session.cycle.remaining = INF
	check(not target.campaign.restore(campaign).ok and JSON.stringify(target.campaign.capture(), "", true, true) == before_campaign, "inactive invalid cycle cannot partially replace active campaign or globals")
	# Slots delegate the complete campaign validation, including encounter headers.
	check(Codec.restore(target, notification).ok, "restore active encounter before slot check")
	target.campaign.saved_scenes.clear()
	var root := "user://test-cycle-validation-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var slots := Slots.new()
	slots.configure(target.campaign, root)
	var created: Dictionary = slots.create_slot()
	check(created.ok, "slot writer accepts validated encounter phase")
	var inventory: Dictionary = slots.list_slots()
	check(inventory.ok and inventory.slots.size() == 1 and inventory.slots[0].valid and inventory.slots[0].day == 2, "slot inventory accepts encounter header through campaign staging")
	step(target)
	check(slots.load_slot(1).ok and target.cycle.stage == "encounter_notification", "slot reload restores cursor instead of claiming encounter again")
	var disk: Dictionary = target.campaign.capture()
	disk.scenes.Main.session.world.processed_days.clear()
	var file := FileAccess.open(slots.slot_path(1), FileAccess.WRITE)
	file.store_string(JSON.stringify(disk, "", true, true))
	file.close()
	inventory = slots.list_slots()
	check(not inventory.slots[0].valid and not inventory.slots[0].errors.is_empty(), "slot enumeration reports invalid encounter claim instead of dropping entry")
	var before_slot := canonical(target)
	check(not slots.load_slot(1).ok and canonical(target) == before_slot, "corrupt encounter slot load leaves live cycle and RNG intact")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(slots.slot_path(1) + suffix): DirAccess.remove_absolute(slots.slot_path(1) + suffix)
	DirAccess.remove_absolute(root)
	check(not DirAccess.dir_exists_absolute(root), "only test-owned slot store removed")
	print("Cycle save validation: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
