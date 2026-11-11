extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
const Driver = preload("res://tests/godot/cycle_test_driver.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func make(camera: bool = true):
	var c := Catalog.new()
	var documents: Array = [
		{"script_class": "CardManager", "fields": {"defaultSpawnCards": [], "cardSettings": {"guid": "settings"}}},
		{"script_class": "EncounterManager", "fields": {"allEncounters": [{"guid": "arrival"}]}},
		{"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}]
	if camera: documents.append({"script_class": "CameraController", "fields": {}})
	c.configure({"cards": [
		{"guid": "hero", "script_class": "CardDefinition", "fields": {"id": "hero", "category": 2, "faction": 1, "maxHealth": 10, "attack": 100, "accuracy": 100, "criticalChance": 0, "loot": [{"Card": {"guid": "corpse"}, "Weight": 1}]}},
		{"guid": "enemy", "script_class": "CardDefinition", "fields": {"id": "enemy", "category": 9, "faction": 2, "maxHealth": 10, "attack": 100, "accuracy": 100, "criticalChance": 0, "loot": [{"Card": {"guid": "hero"}, "Weight": 1}]}},
		{"guid": "food", "script_class": "CardDefinition", "fields": {"id": "food", "category": 3, "nutrition": 4}},
		{"guid": "corpse", "script_class": "CardDefinition", "fields": {"id": "corpse", "category": 4}},
		{"guid": "coin", "script_class": "CardDefinition", "fields": {"id": "coin", "category": 7}},
		{"guid": "visitor", "script_class": "CardDefinition", "fields": {"id": "visitor", "category": 1}}
	], "settings": [{"guid": "settings", "script_class": "CardSettings", "fields": {"hungerPerCharacter": 2, "baseCardLimit": 100, "dragHeight": 0.4, "stackStep": {"y": 0.01, "z": -0.2}}}],
	"encounters": [{"guid": "arrival", "fields": {"id": "arrival-id", "type": 0, "dayValue": 2, "chance": 1.0, "count": 2, "oneTimeOnly": true, "maxCardsOnBoardLimit": 100, "notificationMessage": "Visitors arrive", "cardToSpawn": {"guid": "visitor"}}}],
	"scenes": [{"name": "Main", "documents": documents}, {"name": "Island", "documents": documents.duplicate(true)}]})
	var s := Session.new()
	s.configure(c, 45)
	return s

func same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

func next(s) -> void:
	s.tick(maxf(s.cycle.remaining, 0.0001) + 0.00001)

func _init() -> void:
	_test_boundaries()
	_test_roundtrips()
	_test_removed_references()
	_test_pose_and_ownership()
	_test_combat_interleaving()
	_test_invalid_states()
	_test_slots_and_campaign()
	_test_source_data()
	print("Cycle timeline: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_boundaries() -> void:
	var s = make()
	var hero: int = s.spawn_card("hero", Vector2(3, 4))
	var food: int = s.spawn_card("food", Vector2(-2, 1))
	s.cards[hero].health = 1
	s.elapsed = 12
	s.speed = 2
	var events: Array = []
	var live = s
	var stable_save_results: Array = []
	var observer := func(kind: String, payload: Dictionary):
		events.append({"kind": kind, "payload": payload.duplicate(true)})
		if kind == "cycle_sound": stable_save_results.append(Codec._stage(live, Codec.capture(live)).ok)
	s.event_occurred.connect(observer)
	s.end_day()
	check(s.phase == "feeding" and s.cycle.stage == "character_focus" and s.elapsed == 0 and s.paused, "Manual day end begins realtime focus and resets elapsed silently")
	check(not s.start_day() and s.cards[food].nutrition == 4 and s.cards[hero].health == 1, "Start Day and effects blocked during focus")
	var initial: Dictionary = Codec.capture(s)
	s.end_day()
	check(same(Codec.capture(s), initial), "Repeated Feed cannot restart a running sequence")
	s.tick(100)
	check(s.cycle.stage == "food_lift" and s.cycle.remaining == 0.1 and s.cards[food].nutrition == 4, "Large delta crosses one wait only, preserving full next lift")
	check(s.cycle.presentation_state().from_position == Vector3(-2, 0, 1) and is_equal_approx(s.cycle.presentation_state().to_position.y, 0.4), "Lift uses individual origin and source DragHeight")
	s.tick(0.05)
	check(is_equal_approx(s.cycle.presentation_pose(food).y, 0.3), "Mid-lift source OutQuad pose is reconstructible")
	check(s.stats().nutrition == 4 and s.stats().cards_owned == 2, "Food remains registered and counted in flight")
	next(s)
	check(s.cycle.stage == "food_travel" and s.cycle.presentation_state().to_position == Vector3(3, 0.4, 4), "Travel samples character position after lift")
	next(s)
	check(s.cycle.stage == "food_chew" and s.cards[food].nutrition == 4 and s.cards[hero].health == 1, "Travel and Eat sound precede the chew effect")
	next(s)
	check(s.cycle.stage == "leftover_settle" and s.cards[food].nutrition == 2 and s.cards[hero].health == 6, "Chew completion applies nutrition and banker-rounded healing once")
	check(s.cards[food].position == Vector2(3, 4), "Leftover settles at captured character target")
	var stats_events: Array = events.filter(func(e): return e.kind == "stats_changed")
	check(stats_events.is_empty(), "Leftover stats notification waits until settle completes")
	next(s)
	check(s.cycle.stage == "character_wait" and s.phase == "feeding", "Final character still waits half a realtime second")
	check(events.filter(func(e): return e.kind == "stats_changed").size() == 1, "One completed consumption stats event")
	next(s)
	check(s.phase == "ready" and s.elapsed == 0, "Only final wait completion permits Start Day; no scaled time elapsed")
	check(events.filter(func(e): return e.kind == "time_pace_changed").is_empty(), "Automatic pause publishes no fabricated pace event")
	check(stable_save_results == [false, false], "Synchronous partial effect callbacks cannot persist half a transition")
	s.event_occurred.disconnect(observer)
	check(s.start_day() and s.day == 2 and s.speed == 1 and not s.paused and s.cycle.stage == "idle", "Ready start clears cycle before day-start checkpoint")

	s = make(false)
	s.spawn_card("hero")
	food = s.spawn_card("food")
	s.day_duration = 1
	s.tick(1)
	check(s.phase == "feeding" and s.cycle.stage == "await_feed" and s.elapsed == 0, "Automatic timeout awaits explicit feeding confirmation")
	s.tick(20)
	check(s.cycle.stage == "await_feed" and s.cards[food].nutrition == 4, "Awaiting feed has no automatic consumption")
	s.end_day()
	check(s.cycle.stage == "food_lift", "Scene without camera skips only camera focus wait")

func _test_roundtrips() -> void:
	var s = make()
	s.day = 2
	s.spawn_card("hero")
	var food: int = s.spawn_card("food")
	s.end_day()
	var stages: Array = []
	for boundary in range(20):
		if s.phase == "ready": break
		stages.append(s.cycle.stage)
		s.tick(s.cycle.remaining * 0.4)
		var snapshot: Dictionary = Codec.capture(s)
		var other = make()
		var outcome: Dictionary = Codec.restore(other, JSON.parse_string(JSON.stringify(snapshot, "", true, true)))
		check(outcome.ok, "Mid-stage save restores: " + s.cycle.stage + " " + str(outcome.get("error", "")))
		if not outcome.ok: break
		check(same(Codec.capture(other), snapshot), "Canonical full snapshot roundtrip: " + s.cycle.stage)
		check(other.cycle.presentation_state() == s.cycle.presentation_state() and other.cycle.focus_state() == s.cycle.focus_state(), "View reconstruction has no replayed effects: " + s.cycle.stage)
		var delta: float = s.cycle.remaining + 0.00001
		s.tick(delta)
		other.tick(delta)
		check(same(Codec.capture(other), Codec.capture(s)), "Resumed boundary matches uninterrupted state/RNG: " + str(stages.back()))
	check(stages == ["character_focus", "food_lift", "food_travel", "food_chew", "leftover_settle", "character_wait", "encounter_notification", "encounter_focus", "encounter_wait", "encounter_focus", "encounter_wait"], "Full source wait order with two sequential encounter cards")
	check(s.phase == "ready" and s.cards[food].nutrition == 2 and s.cards.size() == 4, "Resume neither consumes food twice nor duplicates encounter spawns")
	check(s.world.completed_encounters.has("arrival-id") and s.world.processed_days.has(2), "Encounter claim persists before completion")

	var legacy = make()
	var old: Dictionary = Codec.capture(legacy)
	old.session.phase = "feeding"
	old.session.paused = true
	old.session.erase("cycle")
	check(Codec.restore(legacy, old).ok and legacy.cycle.stage == "await_feed", "Legacy feeding means awaiting confirmation, never partially consumed")
	legacy.tick(20)
	check(legacy.cycle.stage == "await_feed", "Legacy feeding resave cannot start itself")

func _test_removed_references() -> void:
	var s = make()
	var first: int = s.spawn_card("hero")
	var second: int = s.spawn_card("hero")
	var food: int = s.spawn_card("food")
	s.end_day()
	s._remove_card(first)
	next(s)
	check(s.cycle.stage == "character_focus" and s.cycle.focus_state().card_id == second, "Vanished focus character is skipped safely")
	next(s)
	s._remove_card(food)
	var late: int = s.spawn_card("food")
	var saved: Dictionary = Codec.capture(s)
	var restored = make()
	check(Codec.restore(restored, saved).ok, "Removed queued/selected IDs are valid historical references")
	Driver.drain(restored)
	check(restored.phase == "game_over" and restored.cards[late].nutrition == 4, "Missing selected food does not recruit later food after restore")

	s = make(false)
	first = s.spawn_card("hero")
	food = s.spawn_card("food")
	s.end_day()
	s._remove_card(first)
	next(s)
	check(s.cycle.stage == "character_wait" and s.cards[food].nutrition == 4, "Interrupted food motion retains unconsumed food")
	Driver.drain(s)
	check(s.phase == "game_over", "Final survivor check follows safe cancellation")

func ensure_hit(s) -> void:
	for value in range(100):
		var probe := RandomNumberGenerator.new()
		probe.seed = value
		if probe.randf() < 0.9 and probe.randf() > 0.01:
			s.rng.seed = value
			return

func _test_pose_and_ownership() -> void:
	var s = make(false)
	var hero: int = s.spawn_card("hero")
	var near_live: int = s.spawn_card("food", Vector2(9, 0))
	s.spawn_card("food", Vector2.ZERO)
	var live = s
	var live_position := {"character": Vector3(10, 0, 0)}
	s.cycle.pose_sampler = func(id: int): return live_position.character if id == hero else live.card_target_position_3d(id)
	var rng_before: int = s.rng.state
	s.end_day()
	check(s.cycle.presentation_state().card_id == near_live, "Injected current character pose determines nearest food")
	live_position.character = Vector3(20, 2, -4)
	next(s)
	check(s.cycle.presentation_state().to_position.is_equal_approx(Vector3(20, 0.4, -4)), "Travel captures changed current pose only after lift")
	check(s.rng.state == rng_before, "Pose sampling and food presentation consume no gameplay RNG")
	s.cycle.pose_sampler = Callable()

	s = make(false)
	s.spawn_card("hero")
	var anchor: int = s.spawn_card("visitor", Vector2(3, 5))
	var old_stack = s.stacks[s.cards[anchor].stack_id]
	var food: int = s.spawn_card("food", Vector2(3, 5), old_stack.id)
	var tail: int = s.spawn_card("visitor", Vector2(3, 5), old_stack.id)
	old_stack.recipe_guid = "transient-craft"
	old_stack.progress = 2
	s.end_day()
	check(old_stack.card_ids == [anchor, tail] and old_stack.recipe_guid.is_empty(), "Only selected food detaches and old crafting stops before lift")
	check(s.stacks[s.cards[food].stack_id].card_ids == [food], "Detached in-flight food immediately owns a registered singleton stack")
	check(s.cycle.presentation_state().from_position.is_equal_approx(Vector3(3, 0.01, 4.8)), "Food lift preserves captured individual stacked origin")
	s.spawn_card("coin") # An interleaved stats event must still count the food.
	check(s.stats().nutrition == 4 and s.stats().cards_owned == 4, "Interleaved flight stats include food and retained old-stack members")
	var restored = make(false)
	check(Codec.restore(restored, JSON.parse_string(JSON.stringify(Codec.capture(s)))).ok, "Detached-food mid-flight save passes normal stack ownership validation")
	Driver.drain(restored)
	check(restored.cards[food].nutrition == 2 and restored.cards.has(tail), "Restored detached-food consumption preserves other stack members")

func _test_combat_interleaving() -> void:
	var s = make()
	var hero: int = s.spawn_card("hero")
	var enemy: int = s.spawn_card("enemy")
	var food: int = s.spawn_card("food")
	s.cards[hero].health = 1
	var combat: int = s.combat.start_combat([enemy], [hero], false)
	s.combat.tasks[combat].progress[enemy] = 1000
	s.combat.tasks[combat].progress[hero] = 0
	s.combat.resolve_turn(combat)
	ensure_hit(s)
	s.end_day()
	s.tick(0.3)
	check(s.cards[hero].health == 0 and s.cycle.stage == "character_focus", "Pending attack impacts during realtime feeding focus")
	s.tick(0.2)
	s.tick(0.1)
	check(not s.cards.has(hero) and s.cards[food].nutrition == 4, "Combat return death precedes food effect, preventing ghost feeding")
	check(s.combat.tasks[combat].execution.phase == "death_wait", "Lethal combat cleanup still waits on scaled clock")
	Driver.drain(s)
	check(s.phase == "game_over" and s.combat.tasks[combat].execution.remaining == 0.5, "Cycle finishes while scaled combat death wait remains paused")

	s = make()
	hero = s.spawn_card("hero")
	enemy = s.spawn_card("enemy")
	food = s.spawn_card("food")
	s.cards[food].nutrition = 2
	combat = s.combat.start_combat([hero], [enemy])
	s.combat.tasks[combat].progress[hero] = 1000
	s.combat.tasks[combat].progress[enemy] = 0
	s.combat.resolve_turn(combat)
	ensure_hit(s)
	s.end_day()
	Driver.drain(s)
	check(s.phase == "ready" and s.stats().characters == 2 and s.stats().nutrition == 0, "Combat-spawned character counts as survivor but does not join frozen feeding queue")

func _test_invalid_states() -> void:
	var s = make()
	s.spawn_card("hero")
	s.spawn_card("food")
	s.end_day()
	next(s)
	var snapshot: Dictionary = Codec.capture(s)
	var target = make()
	var before: Dictionary = Codec.capture(target)
	for spec in [["version", true], ["stage", "unknown"], ["remaining", -1], ["remaining", INF], ["remaining", 20], ["cursor", 1], ["character_id", -1], ["food_id", 0], ["food_id", 999999], ["old_stack_id", snapshot.session.cycle.food_id], ["need", 0], ["need", 3], ["food_origin", [0, 0, NAN]], ["characters", [1, 1]], ["foods", [snapshot.session.cycle.food_id]]]:
		var corrupt: Dictionary = snapshot.duplicate(true)
		corrupt.session.cycle[spec[0]] = spec[1]
		check(not Codec.restore(target, corrupt).ok and same(Codec.capture(target), before), "Corrupt cycle rejected atomically: " + str(spec))
	for field in ["phase", "paused"]:
		var corrupt: Dictionary = snapshot.duplicate(true)
		corrupt.session[field] = "playing" if field == "phase" else false
		check(not Codec.restore(target, corrupt).ok and same(Codec.capture(target), before), "Cycle rejects contradictory " + field)
	while s.cycle.stage != "leftover_settle": next(s)
	var repeat_bite: Dictionary = Codec.capture(s)
	repeat_bite.session.cycle.need = 1
	check(not Codec.restore(target, repeat_bite).ok and same(Codec.capture(target), before), "Leftover settle cannot restore positive hunger and charge another bite")
	next(s)
	var skip_bite: Dictionary = Codec.capture(s)
	skip_bite.session.cycle.need = 1
	check(not Codec.restore(target, skip_bite).ok, "Living character cannot enter final wait with unsatisfied hunger")

	s = make()
	s.day = 2
	s.phase = "selling"
	s.paused = true
	s._notify_stats_changed()
	snapshot = Codec.capture(s)
	check(s.phase == "encounter" and snapshot.session.cycle.stage == "encounter_notification", "Encounter notification is saveable before any spawn")
	for field in ["processed_days", "completed_encounters"]:
		var corrupt: Dictionary = snapshot.duplicate(true)
		corrupt.session.world[field] = []
		check(not Codec.restore(target, corrupt).ok, "Encounter rejects missing world claim: " + field)
	var no_cycle: Dictionary = snapshot.duplicate(true)
	no_cycle.session.erase("cycle")
	check(not Codec.restore(target, no_cycle).ok, "Encounter cannot load without its timeline cursor")

func _test_slots_and_campaign() -> void:
	var s = make()
	s.day = 2
	s.phase = "selling"
	s.paused = true
	s._notify_stats_changed()
	var slots := Slots.new()
	var root := "user://cycle-slots-" + str(Time.get_ticks_usec())
	slots.configure(s.campaign, root)
	var result: Dictionary = slots.create_slot()
	check(result.ok, "Active encounter saves through Campaign and SaveSlots")
	var inventory: Dictionary = slots.list_slots()
	check(inventory.ok and inventory.slots.size() == 1 and inventory.slots[0].valid, "Encounter header remains visible and valid in slot picker")
	var restored = make()
	var reader := Slots.new()
	reader.configure(restored.campaign, root)
	check(reader.load_slot(1).ok and restored.phase == "encounter" and restored.cycle.stage == "encounter_notification", "Slot load restores encounter phase and pending notification")
	Driver.drain(restored)
	check(restored.cards.size() == 2 and restored.phase == "ready", "Loaded encounter finishes exactly two spawns")
	var snapshot: Dictionary = s.campaign.capture()
	var island = make()
	island.scene_name = "Island"
	island.world.configure(island, "Island")
	island.ai.configure(island, island.world, "Island")
	island.quest_tracker.configure(island.catalog, "Island")
	snapshot.scenes["Island"] = Codec.capture(island)
	snapshot.current_scene = "Island"
	var switched: Dictionary = restored.campaign.restore(snapshot)
	check(switched.ok and restored.scene_name == "Island", "Inactive Main encounter is validated while another scene is active: " + str(switched))
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.scenes.Main.session.cycle.remaining = -1
	var prior: Dictionary = restored.campaign.capture()
	check(not restored.campaign.restore(invalid).ok and same(restored.campaign.capture(), prior), "Invalid inactive-scene cycle cannot partially change campaign")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var path: String = slots.slot_path(1) + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(root)

func _test_source_data() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SOURCE-DATA TIMELINE CHECKS SKIPPED: private catalog unavailable")
		return
	var c := Catalog.new()
	check(c.load_file() == OK, "Source timeline catalog loads")
	for scene_name in ["Main", "Island"]:
		var s := Session.new()
		s.configure(c, 20, scene_name)
		check(s.cycle.camera_available(), scene_name + " resolves camera through its referenced prefab")
		var hero: int = s.spawn_card(c.find_by_name("Villager"))
		var food: int = s.spawn_card(c.find_by_name("Apple"))
		s.cards[hero].health = 1
		s.end_day()
		check(s.cycle.stage == "character_focus" and s.cycle.remaining == 0.5, scene_name + " uses source camera wait")
		s.tick(0.25)
		var restored := Session.new()
		restored.configure(c, 99, scene_name)
		check(Codec.restore(restored, JSON.parse_string(JSON.stringify(Codec.capture(s)))).ok and restored.cycle.focus_state().duration == 0.25, scene_name + " resumes remaining source focus")
		Driver.drain(restored)
		check(restored.phase == "ready" and not restored.cards.has(food) and restored.cards[hero].health > 1, scene_name + " completes source Apple consumption after timed stages")
