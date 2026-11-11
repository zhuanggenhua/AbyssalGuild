extends SceneTree
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
	return s.spawn_card(s.catalog.find_by_name(name))
func _init() -> void:
	var catalog = Catalog.new()
	check(catalog.load_file() == OK, "private source catalog available")
	var s = Session.new(); s.configure(catalog, 123)
	var apple: int = spawn(s, "Apple")
	var cow: int = spawn(s, "Cow")
	var berry: int = spawn(s, "Berry")
	check(s.move_to_stack(cow, s.cards[apple].stack_id), "source matrix legally allows Cow onto Apple")
	check(s.move_to_stack(apple, s.cards[berry].stack_id), "source matrix legally carries Apple and Cow onto Berry")
	var old = s.stacks[s.cards[berry].stack_id]
	check(old.card_ids == [berry, apple, cow] and old.recipe_guid.is_empty(), "extra Cow blocks strict Fruit Salad without injected recipe state")
	s.ai.point_validator = func(_point, _stack): return false
	s.world.production_timers[cow] = 1000
	s.ai.agents[cow].move_timer = 0
	s.ai.tick(0.01)
	check(old.card_ids == [berry, apple] and s.cards[cow].stack_id != old.id, "due Cow detaches despite rejected patrol")
	check(not old.recipe_guid.is_empty() and catalog.get_definition(old.recipe_guid).get("name", "") == "Recipe_FruitSalad", "AI departure starts newly valid source Fruit Salad")
	check(s.crafting.save_state().activation_order.has(old.id), "new recipe registers with authoritative crafting order")
	for _frame in 610: s.tick(1.0 / 60.0)
	var salads := 0
	for card in s.cards.values():
		if card.definition_guid == catalog.find_by_name("Fruit Salad"): salads += 1
	check(salads == 1 and not s.cards.has(apple) and not s.cards.has(berry), "actual recipe completes once after normal elapsed ticks")
	print("AI detach source crafting: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
