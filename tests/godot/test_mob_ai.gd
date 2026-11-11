extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const World = preload("res://scripts/model/world_rules.gd")
const AI = preload("res://scripts/model/mob_ai.gd")
var checks: int = 0
var failures: int = 0
var validations: int = 0
var snapshots: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func allow_point(_point: Vector2, _stack: int) -> bool:
	validations += 1
	return true
func reject_point(_point: Vector2, _stack: int) -> bool:
	validations += 1
	return false
func geometry() -> Array:
	return snapshots
func _init() -> void:
	var catalog = Catalog.new()
	catalog.load_file()
	var session = Session.new()
	session.configure(catalog, 123)
	var world = World.new()
	world.configure(session)
	var ai = AI.new()
	ai.configure(session, world)
	var cow_guid: String = catalog.find_by_name("Cow")
	var hero_guid: String = catalog.find_by_name("Villager")
	var cow: int = session.spawn_card(cow_guid)
	var hero: int = session.spawn_card(hero_guid)
	check(ai.agents.has(cow) and not ai.agents.has(hero), "actual prefab CardAI only on mob, not player")
	check(ai.move_interval == 5 and ai.move_radius == 1 and ai.max_attempts == 5, "actual CardSettings movement values")
	check(ai.agents[cow].move_timer >= 5.5 and ai.agents[cow].move_timer <= 6, "initial move interval plus jitter")
	ai.point_validator = allow_point
	var previous: Vector2 = session.cards[cow].position
	ai.tick(0)
	check(session.cards[cow].position == previous, "zero delta freezes motion")
	ai.tick(5)
	check(session.cards[cow].position == previous, "no move before initial delay")
	ai.tick(1)
	check(is_equal_approx(previous.distance_to(session.cards[cow].position), 1), "passive movement uses fixed radius")
	# Controlled source-shaped fixture for deterministic lifecycle and movement.
	var definitions: Array = []
	var fixture := {
		"cow": {"category": 9, "faction": 0, "produceCard": {"guid": "milk"}, "produceInterval": 10},
		"mob": {"category": 9, "faction": 2, "isAggressive": true, "aggroRadius": 5, "attackRadius": 1.5},
		"hero": {"category": 2, "faction": 1},
		"milk": {"category": 3}, "pen": {"category": 6, "capacity": 1}, "other": {"category": 4}}
	for guid in fixture:
		definitions.append({"guid": guid, "script_class": "EnclosureDefinition" if guid == "pen" else "CardDefinition", "fields": fixture[guid]})
	catalog = Catalog.new()
	catalog.configure({"cards": definitions, "referenced_prefabs": [{"guid": "ai_prefab", "documents": [{"script_class": "CardAI"}]}], "scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai_prefab"}}]}}]}]})
	session = Session.new()
	session.configure(catalog, 123)
	world = World.new()
	world.configure(session)
	ai = AI.new()
	ai.configure(session, world)
	ai.point_validator = allow_point
	cow = session.spawn_card("cow")
	var companion: int = session.spawn_card("other", Vector2.ZERO, session.cards[cow].stack_id)
	var old_stack: int = session.cards[cow].stack_id
	ai.agents[cow].move_timer = 0
	ai.tick(0.01)
	check(session.cards[cow].stack_id != old_stack and session.cards[companion].stack_id == old_stack, "move detaches only moving card")
	check(session.stacks[session.cards[cow].stack_id].card_ids == [cow], "detached mob singleton")
	var pen: int = session.spawn_card("pen")
	var penned: int = session.spawn_card("cow", Vector2.ZERO, session.cards[pen].stack_id)
	ai.agents[penned].move_timer = 0
	world.production_timers[penned] = 0
	var count: int = session.cards.size()
	ai.tick(0.01)
	check(session.cards[penned].stack_id == session.cards[pen].stack_id and session.cards[penned].position == Vector2.ZERO, "enclosure stops detachment and patrol")
	check(session.cards.size() == count + 1, "enclosure still produces")
	var stacked: int = session.spawn_card("cow", Vector2.ZERO, session.cards[pen].stack_id)
	ai.agents[stacked].move_timer = 100
	world.production_timers[stacked] = 0
	count = session.cards.size()
	ai.tick(0.01)
	check(session.cards.size() == count + 1, "stacked producer not banned by cards above/below")
	session.combat.dragged[cow] = true
	previous = session.cards[cow].position
	ai.agents[cow].move_timer = 0
	world.production_timers[cow] = 0
	count = session.cards.size()
	ai.tick(0.01)
	check(session.cards[cow].position == previous and session.cards.size() == count, "drag blocks both movement and production")
	check(ai.agents[cow].move_timer == ai.move_interval and world.production_timers[cow] == 10, "blocked wakes consume whole intervals")
	session.combat.dragged.erase(cow)
	session.stacks[session.cards[cow].stack_id].recipe_guid = "craft"
	ai.agents[cow].move_timer = 0
	ai.tick(0.01)
	check(session.cards[cow].position == previous, "crafting blocks motion")
	session.stacks[session.cards[cow].stack_id].cancel_craft()
	ai.point_validator = reject_point
	validations = 0
	ai.agents[cow].move_timer = 0
	ai.tick(0.01)
	check(validations == 5 and session.cards[cow].position == previous, "patrol maximum attempts and no invalid movement")
	ai.point_validator = Callable()
	ai.agents[cow].move_timer = 0
	ai.tick(0.01)
	check(session.cards[cow].position == previous, "missing board adapter does not invent bounds")
	ai.point_validator = allow_point
	# Hunting ignores radius, moves only one step, then starts source mob-initiated fight.
	var mob: int = session.spawn_card("mob", Vector2(20, 0))
	hero = session.spawn_card("hero", Vector2(100, 0))
	ai.agents[mob].move_timer = 0
	ai.tick(0.01)
	check(session.cards[mob].position == Vector2(21, 0), "hunt outside aggro radius advances one move-radius")
	session.cards[hero].position = Vector2(22, 0)
	session.stacks[session.cards[hero].stack_id].position = Vector2(22, 0)
	ai.agents[mob].move_timer = 0
	ai.tick(0.01)
	check(session.combat.membership.has(mob) and session.combat.membership.has(hero), "automatic combat initiation")
	var combat_id: int = int(session.combat.membership.get(mob, -1))
	check(not session.combat.tasks[combat_id].player_is_attacker, "mob initiated battle side designation")
	check(not ai.agents[mob].running and not world.production_timers.has(mob), "combat stops AI immediately")
	session.combat.remove_combatant(mob)
	check(ai.agents[mob].running and ai.agents[mob].move_timer >= 5.5, "leaving finished combat restarts initial delay")
	# Existing combat geometry priority and joining.
	var enemy: int = session.spawn_card("mob", Vector2(40, 0))
	var defender: int = session.spawn_card("hero", Vector2(40, 0))
	combat_id = session.combat.start_combat([enemy], [defender], false)
	var joiner: int = session.spawn_card("mob", Vector2(37, 0))
	ai.combat_geometry = geometry
	snapshots = [{"id": combat_id, "ongoing": true, "has_player": true, "position": Vector2(40, 0)}]
	ai.agents[joiner].move_timer = 0
	ai.tick(0.01)
	check(session.cards[joiner].position == Vector2(38, 0), "approaches actual supplied combat rectangle")
	ai.agents[joiner].move_timer = 0
	ai.tick(0.01)
	check(session.combat.membership.get(joiner, -1) == combat_id and not ai.agents[joiner].running, "joins nearby fight and stops lifecycle")
	# Membership transitions without events are still reconciled on next tick.
	session.combat.membership[cow] = 999
	ai.tick(0.01)
	check(not ai.agents[cow].running and not world.production_timers.has(cow), "combat membership reconciliation stops production")
	session.combat.membership.erase(cow)
	ai.tick(0.01)
	check(ai.agents[cow].running and world.production_timers[cow] >= 10.4, "membership exit starts fresh production delay")
	session._remove_card(cow)
	ai.tick(0.01)
	check(not ai.agents.has(cow) and not world.production_timers.has(cow), "dead agent state cleaned")
	var bounds := Rect2(-5, -5, 10, 10)
	check(AI.point_in_board(Vector2(4.5, 3), bounds, Vector2(1, 2), 1), "board inclusive edges")
	check(not AI.point_in_board(Vector2(4.6, 3), bounds, Vector2(1, 2), 1), "board width footprint")
	check(not AI.point_in_board(Vector2(0, 3.1), bounds, Vector2(1, 2), 1), "restricted header footprint")
	check(not AI.point_in_board(Vector2(0, -4.1), bounds, Vector2(1, 2), 1), "board lower footprint")
	ai.reset()
	check(ai.agents.is_empty() and world.production_timers.is_empty(), "reset transient state")
	ai.resync()
	check(ai.agents.has(penned), "load resync recreates live AI")
	# Native checkpoints preserve timers and RNG without resync on restore.
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(ai.save_state(), "", true, true))
	var staged: Dictionary = ai.stage_state(checkpoint, session.cards)
	check(staged.ok, "native checkpoint stages with live AI prefab eligibility")
	check(AI.validate_combat_state(staged, session.combat.membership), "checkpoint combat state crosscheck")
	var rng_state: int = session.rng.state
	var expected: Dictionary = ai.save_state()
	ai.reset()
	ai.apply_state(staged)
	check(ai.save_state() == expected and session.rng.state == rng_state, "checkpoint applies exact timer state without RNG draws")
	var before: Dictionary = ai.save_state()
	var first: int = -1
	for index in range(checkpoint.agents.size()):
		if checkpoint.agents[index].running:
			first = index
			break
	check(first >= 0, "running fixture available for checkpoint faults")
	var malformed: Array = []
	var bad: Dictionary = checkpoint.duplicate(true)
	bad.scene = "Island"
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents.append(bad.agents[0].duplicate(true))
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents.pop_back()
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents[0].card = hero
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents[0].card = 999999
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents[0].running = 1
	malformed.append(bad)
	for invalid_timer in [-1, INF, NAN, "1", true]:
		bad = checkpoint.duplicate(true)
		bad.agents[0].move_timer = invalid_timer
		malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents[first].erase("produce_timer")
	malformed.append(bad)
	bad = checkpoint.duplicate(true)
	bad.agents[first].running = false
	bad.agents[first].produce_timer = 1.0
	malformed.append(bad)
	for entry in malformed:
		check(not ai.stage_state(entry, session.cards).ok and ai.save_state() == before and session.rng.state == rng_state, "invalid AI state fails without mutation or RNG")
	var conflicting: Dictionary = staged.duplicate(true)
	conflicting.agents[enemy].running = true
	check(not AI.validate_combat_state(conflicting, session.combat.membership), "codec rejects running AI in combat")
	# Membership can change between ticks: save normalizes only the stop, no draws.
	var running_id: int = int(checkpoint.agents[first].card)
	session.combat.membership[running_id] = 999
	var stopped: Dictionary = ai.stage_state(ai.save_state(), session.cards)
	check(stopped.ok and not stopped.agents[running_id].running and not stopped.production_timers.has(running_id), "snapshot stops newly engaged agent without RNG")
	check(session.rng.state == rng_state, "read-only snapshot never samples RNG")
	session.combat.membership.erase(running_id)
	# An old save can be re-saved before its first active AI tick.
	ai.reset()
	var legacy_rng: int = session.rng.state
	var pending: Dictionary = ai.save_state()
	var pending_staged: Dictionary = ai.stage_state(pending, session.cards)
	check(pending_staged.ok and not pending.agents.is_empty(), "immediate legacy checkpoint includes every live AI card")
	var all_pending: bool = true
	for record in pending.agents:
		all_pending = all_pending and not record.running and record.move_timer == 0 and not record.has("produce_timer")
	check(all_pending and ai.agents.is_empty() and world.production_timers.is_empty() and session.rng.state == legacy_rng, "missing agents serialize pending restart without mutation or RNG")
	check(AI.validate_combat_state(pending_staged, session.combat.membership), "pending legacy records validate in and out of combat")
	print("Mob AI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
