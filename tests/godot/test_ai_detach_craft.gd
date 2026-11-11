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
func make():
	var c = Catalog.new()
	var rules: Array = []; rules.resize(144); rules.fill(1)
	var cards: Array = []
	for guid in ["a", "b", "cow", "result"]:
		cards.append({"guid": guid, "script_class": "CardDefinition", "fields": {"id": guid, "category": 9 if guid == "cow" else 4}})
	c.configure({"cards": cards, "recipes": [{"guid": "pair", "script_class": "RecipeDefinition", "fields": {"id": "pair", "allowExcessIngredients": false, "craftingDuration": 1, "randomWeight": 1, "requiredIngredients": [{"card": {"guid": "a"}, "count": 1, "consumptionMode": 0}, {"card": {"guid": "b"}, "count": 1, "consumptionMode": 0}], "resultingCard": {"guid": "result"}}}], "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}], "referenced_prefabs": [{"guid": "ai", "documents": [{"script_class": "CardAI"}]}], "scenes": [{"name": "Main", "documents": [{"script_class": "CardManager", "fields": {"cardPrefabs": [{"category": 9, "prefab": {"guid": "ai"}}]}}]}]})
	var s = Session.new(); s.configure(c, 123)
	return s
func _init() -> void:
	for accepted in [false, true]:
		var s = make()
		var a: int = s.spawn_card("a")
		var cow: int = s.spawn_card("cow")
		var b: int = s.spawn_card("b")
		check(s.move_to_stack(cow, s.cards[a].stack_id) and s.move_to_stack(a, s.cards[b].stack_id), "legal extra-mob assembly")
		var old = s.stacks[s.cards[b].stack_id]
		check(old.recipe_guid.is_empty(), "extra mob blocks strict recipe")
		s.ai.point_validator = func(_point, _stack): return accepted
		s.ai.agents[cow].move_timer = 0; s.ai.tick(0.01)
		check(old.recipe_guid == "pair" and s.crafting.save_state().activation_order == [old.id], "detachment activates newly valid recipe regardless of patrol acceptance")
		for _frame in 70: s.tick(1.0 / 60.0)
		check(s.cards.values().filter(func(card): return card.definition_guid == "result").size() == 1, "activated recipe completes normally once")
	# Defensive helper behavior: source cancels an existing craft, not reselects it.
	var s = make()
	var cow: int = s.spawn_card("cow")
	s.spawn_card("a", Vector2.ZERO, s.cards[cow].stack_id)
	s.spawn_card("b", Vector2.ZERO, s.cards[cow].stack_id)
	var old = s.stacks[s.cards[cow].stack_id]
	old.recipe_guid = "pair"; s.crafting.activate(old)
	s.ai._detach(cow)
	check(old.recipe_guid.is_empty() and s.crafting.save_state().activation_order.is_empty(), "previously crafting detach only cancels existing task")
	print("AI detach crafting: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
