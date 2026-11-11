extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var catalog = Catalog.new()
	var rules: Array = []
	rules.resize(144)
	rules.fill(0)
	rules[4 * 12 + 2] = 1
	rules[7 * 12 + 6] = 1
	rules[7 * 12 + 2] = 1
	rules[4 * 12 + 4] = 2
	catalog.configure({"cards": [
		{"guid": "wood", "fields": {"category": 4}},
		{"guid": "stone", "fields": {"category": 4}},
		{"guid": "hero", "fields": {"category": 2}},
		{"guid": "coin", "fields": {"category": 7}},
		{"guid": "chest", "script_class": "ChestDefinition", "fields": {"category": 6, "capacity": 1}},
		{"guid": "pen", "script_class": "EnclosureDefinition", "fields": {"category": 6, "capacity": 0}}
	], "settings": [{"guid": "matrix", "script_class": "StackingRulesMatrix", "fields": {"rules": rules}}]})
	catalog.definitions["recipe"] = {"fields": {"allowExcessIngredients": true, "requiredIngredients": [{"card": {"guid": "wood"}, "count": 1}]}}
	var s = Session.new()
	s.configure(catalog)
	s.world.currency_guid = "coin"
	var target: int = s.spawn_card("stone")
	var target_stack: int = s.cards[target].stack_id
	s.spawn_card("hero", Vector2.ZERO, target_stack)
	var wood: int = s.spawn_card("wood")
	var wood_stack: int = s.cards[wood].stack_id
	var extra: int = s.spawn_card("coin", Vector2.ZERO, wood_stack)
	check(s.can_move_to_stack(wood, target_stack), "target last not first determines eligibility")
	check(s.cards[wood].stack_id == wood_stack and s.stacks[target_stack].card_ids.size() == 2, "candidate check is nonmutating")
	s.stacks[target_stack].recipe_guid = "recipe"
	s.stacks[target_stack].progress = 3
	check(s.can_move_to_stack(wood, target_stack), "only lifted card checked, unrelated trailing card allowed")
	s.cards[wood].definition_guid = "stone"
	check(not s.can_move_to_stack(wood, target_stack), "effective definition, not base, used for active recipe")
	s.cards[wood].definition_guid = "wood"
	check(s.move_to_stack(wood, target_stack), "eligible stack moves")
	check(s.stacks[target_stack].card_ids == [target, s.stacks[target_stack].card_ids[1], wood, extra] and s.stacks[target_stack].progress == 3, "append order and active progress retained")
	check(not s.can_move_to_stack(wood, target_stack), "same stack rejected")
	check(not s.can_stack("wood", "stone") and s.can_stack("wood", "wood"), "same-definition matrix rule")
	check(not s.can_stack("unknown", "wood"), "unknown definitions fail closed")
	var strict_target: int = s.spawn_card("hero")
	var strict_stack: int = s.cards[strict_target].stack_id
	var incoming: int = s.spawn_card("wood")
	catalog.definitions.recipe.fields.allowExcessIngredients = false
	s.stacks[strict_stack].recipe_guid = "recipe"
	s.stacks[strict_stack].paused = true
	s.stacks[strict_stack].progress = 7
	check(not s.can_move_to_stack(incoming, strict_stack), "strict active recipe rejects new stack")
	check(s.can_move_to_stack(incoming, strict_stack, strict_stack), "original crafting stack bypasses active gate")
	check(s.move_to_stack(incoming, strict_stack, strict_stack) and not s.stacks[strict_stack].paused and s.stacks[strict_stack].progress == 7, "original craft resumes without timer reset")
	var chest: int = s.spawn_card("chest")
	var chest_stack: int = s.cards[chest].stack_id
	var coin: int = s.spawn_card("coin")
	var coin_stack: int = s.cards[coin].stack_id
	var trailing: int = s.spawn_card("wood", Vector2.ZERO, coin_stack)
	var coin2: int = s.spawn_card("coin", Vector2.ZERO, coin_stack)
	check(s.can_move_to_stack(coin, chest_stack) and s.cards[chest].stored_coins == 0, "chest eligibility does not deposit")
	check(s.move_to_stack(coin, chest_stack), "chest IOnStackable handles merge")
	check(not s.cards.has(coin) and s.cards[chest].stored_coins == 1 and s.stacks[coin_stack].card_ids == [trailing, coin2], "partial deposit preserves remaining stack in order")
	var full_coin: int = s.spawn_card("coin")
	check(s.move_to_stack(full_coin, chest_stack) and s.cards.has(full_coin) and s.cards[full_coin].stack_id != chest_stack, "full chest handles without ordinary merge")
	var over_chest: int = s.spawn_card("hero", Vector2.ZERO, chest_stack)
	check(s.move_to_stack(full_coin, chest_stack) and s.cards[full_coin].stack_id == chest_stack, "buried chest is not handler when last card is character")
	check(s.cards.has(over_chest), "nonhandler remains intact")
	var pen: int = s.spawn_card("pen")
	var pen_coin: int = s.spawn_card("coin")
	check(s.move_to_stack(pen_coin, s.cards[pen].stack_id), "enclosure capacity is not a merge eligibility gate")
	var bad: int = s.spawn_card("wood")
	var bad_stack: int = s.cards[bad].stack_id
	var buried: int = s.spawn_card("chest", Vector2.ZERO, bad_stack)
	var reject: int = s.spawn_card("wood")
	check(not s.can_move_to_stack(reject, bad_stack), "last target rejection wins despite first same definition")
	check(s.cards.has(buried), "pure rejection preserves target")
	# Chest.OnStack inspects the incoming first card, not any coin in its tail.
	rules[4 * 12 + 6] = 1
	var chest2: int = s.spawn_card("chest")
	var noncoin: int = s.spawn_card("wood")
	var noncoin_stack: int = s.cards[noncoin].stack_id
	var tail_coin: int = s.spawn_card("coin", Vector2.ZERO, noncoin_stack)
	s.stacks[noncoin_stack].recipe_guid = "recipe"
	s.stacks[noncoin_stack].progress = 8
	var source_ref = s.stacks[noncoin_stack]
	check(s.move_to_stack(noncoin, s.cards[chest2].stack_id), "chest declines noncurrency first card and merges normally")
	check(s.cards[chest2].stored_coins == 0 and s.cards.has(tail_coin), "trailing currency not deposited when handler declines")
	check(source_ref.recipe_guid.is_empty() and source_ref.progress == 0, "merging whole source cancels its active craft")
	print("Stacking checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
