extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
var checks := 0
var failures := 0
var resolves := 0
var attempts := 0
var accepted := true
var moved_positions: Array = []
var s
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func validate(_point: Vector2, _stack: int) -> bool:
	attempts += 1
	return accepted
func resolve() -> void:
	resolves += 1
	moved_positions.append(s.stacks.values().map(func(stack): return stack.position))
func fixture():
	var catalog = Catalog.new()
	var definitions: Array = []
	for guid in ["cow", "mob", "hero", "other"]:
		definitions.append({"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid, "category": 9 if guid in ["cow", "mob"] else (2 if guid == "hero" else 4), "faction": 1 if guid == "hero" else 0, "isAggressive": guid == "mob", "attackRadius": 1, "aggroRadius": 5, "maxHealth": 10}})
	catalog.configure({"cards": definitions, "referenced_prefabs": [{"guid": "ai", "documents": [{"script_class": "CardAI"}]}], "scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai"}}]}}]}]})
	var session = Session.new(); session.configure(catalog, 123)
	return session
func _init() -> void:
	s = fixture()
	s.ai.point_validator = validate; s.ai.placement_resolver = resolve
	var cow: int = s.spawn_card("cow")
	var other: int = s.spawn_card("cow", Vector2(8, 0))
	for id in [cow, other]: s.ai.agents[id].move_timer = 0
	s.ai.tick(0.01)
	check(resolves == 2 and attempts == 2, "each of two due patrols resolves immediately once")
	check(moved_positions[0][1] == Vector2(8, 0) and moved_positions[1][1] != Vector2(8, 0), "first placement precedes second move")
	accepted = false; attempts = 0; resolves = 0
	s.ai.agents[cow].move_timer = 0; s.ai.tick(0.01)
	check(attempts == 5 and resolves == 1, "exhausted patrol resolves exactly once")
	s.ai.max_attempts = 0; resolves = 0
	s.ai.agents[cow].move_timer = 0; s.ai.tick(0.01)
	check(resolves == 1, "zero-attempt patrol still resolves")
	s.ai.max_attempts = 5
	var mob: int = s.spawn_card("mob", Vector2(20, 0))
	s.spawn_card("hero", Vector2(30, 0))
	resolves = 0; attempts = 0
	s.ai.agents[mob].move_timer = 0; s.ai.tick(0.01)
	check(resolves == 0 and attempts == 1, "rejected player approach does not resolve or patrol")
	accepted = true; s.ai.agents[mob].move_timer = 0; s.ai.tick(0.01)
	check(resolves == 1, "accepted player approach resolves")
	s.ai.combat_geometry = func(): return [{"id": 99, "ongoing": true, "has_player": true, "position": Vector2(24, 0)}]
	accepted = false; resolves = 0; s.ai.agents[mob].move_timer = 0; s.ai.tick(0.01)
	check(resolves == 0, "rejected combat approach does not resolve")
	accepted = true; s.ai.agents[mob].move_timer = 0; s.ai.tick(0.01)
	check(resolves == 1, "accepted combat approach resolves")
	s.ai.configure(s, s.world, "Main")
	check(s.ai.placement_resolver == Callable(self, "resolve"), "configure preserves injected placement adapter")
	# Re-registration differs from card creation order; only registered cards participate.
	s = fixture()
	mob = s.spawn_card("mob")
	var first: int = s.spawn_card("hero", Vector2(-4, 0))
	var second: int = s.spawn_card("hero", Vector2(4, 0))
	check(s.world.aggressive_intent(mob).card_id == first, "initial tie follows registration")
	Equipment.detach(s, first, Vector2(-4, 0)); Equipment.return_to_board(s, first)
	check(s.world.aggressive_intent(mob).card_id == second, "re-registered earlier-created hero loses stable tie")
	var carrier: int = s.spawn_card("other", Vector2(4, 0))
	# Tail split creates a new registered stack at the end without changing card IDs.
	var st = s.stacks[s.cards[second].stack_id]
	var old = s.stacks[s.cards[carrier].stack_id]
	s.stacks.erase(old.id); st.card_ids.push_front(carrier); s.cards[carrier].stack_id = st.id
	s.split_stack(second, Vector2(4, 0))
	check(s.world.aggressive_intent(mob).card_id == first, "split appends target registration behind prior tie")
	var before: Array = s.source_card_ids()
	var restored: Dictionary = Codec.restore(s, Codec.capture(s))
	check(restored.ok and s.source_card_ids() == before and s.world.aggressive_intent(mob).card_id == first, "checkpoint retains stable target order")
	Equipment.detach(s, first, Vector2(-1, 0))
	check(s.world.aggressive_intent(mob).card_id == second, "unregistered closer player is excluded")
	s._remove_card(first)
	s.equipment.owners[second] = carrier
	check(s.world.aggressive_intent(mob).action == "patrol", "equipped player excluded")
	s.equipment.owners.erase(second); s.combat.membership[second] = 99
	check(s.world.aggressive_intent(mob).action == "patrol", "combat player excluded")
	print("AI placement and target order: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
