extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
const Combat = preload("res://scripts/model/combat_system.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	var catalog = Catalog.new()
	var definitions: Array = []
	var fixture := {
		"hero": {"category": 2, "faction": 1, "combatType": 1, "attack": 6, "maxHealth": 20, "accuracy": 100, "criticalChance": 0},
		"mob": {"category": 9, "faction": 2, "combatType": 2, "defense": 1, "dodge": 0, "maxHealth": 40},
		"mage": {"category": 2, "faction": 1, "combatType": 3, "attack": 10, "maxHealth": 30},
		"weapon": {"category": 5, "equipmentSlot": 0, "classChangeResult": {"guid": "mage"}, "statModifiers": [{"Stat": 1, "value": 2.5}]},
		"armor": {"category": 5, "equipmentSlot": 1, "statModifiers": [{"Stat": 1, "value": 0.5}, {"Stat": 0, "value": 10}]},
		"blade": {"category": 5, "equipmentSlot": 0, "statModifiers": [{"Stat": 1, "value": 1}]}
	}
	for guid in fixture:
		definitions.append({"guid": guid, "script_class": "CardDefinition", "fields": fixture[guid]})
	catalog.configure({"cards": definitions, "scenes": [{"name": "Main", "documents": [{"script_class": "TradeManager", "fields": {"currencyCard": {"guid": "coin"}}}, {"script_class": "CombatManager", "fields": {"arrowProjectile": {"guid": "arrow"}}}]}], "referenced_prefabs": [{"guid": "arrow", "documents": [{"script_class": "CombatProjectile", "fields": {"duration": 0.5}}]}]})
	var session = Session.new()
	session.configure(catalog, 123)
	var equipment = Equipment.new()
	equipment.configure(session)
	var combat = Combat.new()
	combat.configure(session, equipment)
	var hero: int = session.spawn_card("hero")
	var mob: int = session.spawn_card("mob")
	var weapon: int = session.spawn_card("weapon")
	var armor: int = session.spawn_card("armor")
	check(Equipment.round_even(2.5) == 2 and Equipment.round_even(3.5) == 4 and Equipment.round_even(-1.5) == -2, "Unity ties-to-even")
	check(combat.resolve_attack(hero, mob, 0.96, 1).type == "miss", "95 percent hit ceiling")
	check(combat.resolve_attack(hero, mob, 0.95, 1).damage == 8, "inclusive hit, five times 1.5 rounds even")
	check(combat.resolve_attack(hero, mob, 0, 0).damage == 12, "inclusive zero critical boundary, sequential rounding")
	fixture.hero.criticalMultiplier = 0
	check(combat.resolve_attack(hero, mob, 0, 0).damage == 0, "no invented post-critical minimum")
	fixture.hero.criticalMultiplier = 150
	fixture.hero.attack = -50
	check(combat.resolve_attack(hero, mob, 0, 1).damage == 2, "minimum base damage precedes RPS")
	fixture.hero.attack = 6
	fixture.hero.accuracy = -999
	check(combat.resolve_attack(hero, mob, 0.05, 1).type == "normal", "five percent hit floor")
	fixture.hero.accuracy = 100
	for pair in [[1, 2], [2, 3], [3, 1]]:
		check(Combat.advantage(pair[0], pair[1]) == 1 and Combat.advantage(pair[1], pair[0]) == -1, "RPS direction")
	check(Combat.advantage(0, 1) == 0 and Combat.advantage(3, 3) == 0, "neutral and equal types")
	check(equipment.equip(hero, armor), "equip armor")
	check(equipment.equip(hero, weapon), "equip class weapon")
	check(session.cards[hero].definition_guid == "mage" and session.cards[hero].base_definition_guid == "hero", "transform preserves identity")
	check(equipment.stats(hero).attack == 13 and equipment.stats(hero).maxHealth == 40, "sum fractions before rounding, reapply all modifiers")
	check(session.cards[hero].health == 20, "class change does not heal")
	check(session.cards[weapon].stack_id == -1 and equipment.owners[weapon] == hero, "equipped item remains owned but leaves board")
	check(not equipment.equip(hero, weapon), "reject duplicate equipped instance")
	var blade: int = session.spawn_card("blade")
	check(equipment.equip(hero, blade), "replace weapon")
	check(session.cards[hero].definition_guid == "hero" and equipment.stats(hero).attack == 8, "revert class and preserve armor")
	check(session.stacks.has(session.cards[weapon].stack_id), "replaced equipment returns to board")
	equipment.unequip_all(hero)
	check(equipment.stats(hero).attack == 6 and equipment.owners.is_empty(), "unequip all clears modifiers")
	var task_id: int = combat.start_combat([hero], [mob])
	check(task_id > 0 and session.cards[hero].stack_id == -1 and session.cards[mob].stack_id == -1, "combat detaches both stacks")
	check(combat.start_combat([hero], [mob]) == -1, "cannot enter two combats")
	var task: Dictionary = combat.tasks[task_id]
	task.progress[hero] = 500.0
	task.progress[mob] = 0.0
	combat.tick(0.5)
	check(task.progress[hero] == 550.0 and task.timer == 0.5, "raw attack speed accumulation, no premature turn")
	combat.dragged[hero] = true
	combat.tick(0.5)
	check(task.execution.actor == mob and task.progress[mob] == 100.0 and task.progress[hero] == 600.0, "dragged actor skipped; reset waits for return")
	check(not combat.flee(mob), "defender cannot flee")
	check(combat.flee(hero) and combat.tasks.is_empty(), "player attacker can flee and end fight")
	check(session.stacks.has(session.cards[hero].stack_id) and session.stacks.has(session.cards[mob].stack_id), "flee and survivor return to board")
	task_id = combat.start_combat([mob], [hero], false)
	check(not combat.flee(hero), "player defender cannot flee")
	var reinforce: int = session.spawn_card("hero")
	check(combat.add_combatants(task_id, [reinforce]), "reinforce by faction")
	check(reinforce in combat.tasks[task_id].defenders, "player reinforcement joins defender side")
	combat.remove_combatant(hero)
	check(combat.tasks.has(task_id), "one defender remains")
	session._remove_card(reinforce)
	combat.tick(0.1)
	check(combat.tasks.is_empty(), "externally removed last defender cleans combat")
	# Lethal turn exercises session kill/loot event path; deterministic attack ceiling
	# needs seed search because hit rolls are intentionally never forced in tick.
	var victim: int = session.spawn_card("mob")
	session.cards[victim].health = 1
	task_id = combat.start_combat([hero], [victim])
	for attempt in 20:
		if not combat.tasks.has(task_id):
			break
		combat.tasks[task_id].progress[hero] = 10000.0
		combat.resolve_turn(task_id)
		combat.tick(0.0, 0.6)
		combat.tick(0.0, 0.3)
		combat.tick(0.5, 0.5)
	check(not session.cards.has(victim) and combat.tasks.is_empty(), "lethal damage kills and ends combat")
	check(session.stacks.has(session.cards[hero].stack_id), "winner returns to board")
	var mob2: int = session.spawn_card("mob")
	var hero2: int = session.spawn_card("hero")
	var fight1: int = combat.start_combat([mob], [hero], false)
	var fight2: int = combat.start_combat([hero2], [mob2])
	var merged: int = combat.merge_combats([fight1, fight2, fight1])
	check(merged > 0 and combat.tasks.size() == 1, "merge replaces tasks, tolerates repeated IDs")
	check(combat.tasks[merged].player_is_attacker and combat.tasks[merged].attackers.size() == 2 and combat.tasks[merged].defenders.size() == 2, "merge repartitions by faction and player becomes attacker")
	check(combat.flee(hero), "previous player defender can flee after merge")
	check(equipment.equip(hero2, weapon), "equip during active fight")
	var saved_equipment: Dictionary = JSON.parse_string(JSON.stringify(equipment.save_state()))
	var staged_equipment: Dictionary = equipment.stage_state(saved_equipment, session.cards)
	check(staged_equipment.ok and weapon in staged_equipment.unstacked, "JSON equipment staging validates ownership")
	var saved_combat: Dictionary = JSON.parse_string(JSON.stringify(combat.save_state()))
	var staged_combat: Dictionary = combat.stage_state(saved_combat, session.cards)
	check(staged_combat.ok and hero2 in staged_combat.unstacked, "JSON combat staging validates membership")
	equipment.apply_state(staged_equipment)
	combat.apply_state(staged_combat)
	check(equipment.stats(hero2).attack == 12 and combat.membership.has(hero2), "apply staged state preserves equipment/combat")
	saved_equipment.wearers[0].items[0].item = 999999
	check(not equipment.stage_state(saved_equipment, session.cards).ok, "bad equipment reference rejected")
	saved_combat.tasks[0].attackers.append(hero2)
	check(not combat.stage_state(saved_combat, session.cards).ok, "duplicate combatant rejected")
	check(combat.membership.has(hero2) and equipment.owners.has(weapon), "failed staging never mutates live helpers")
	_test_session(catalog)
	print("Combat/equipment checks: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)

func _test_session(catalog) -> void:
	catalog.data.scenes = [] # This separate trading fixture uses legacy name lookup.
	catalog.definitions["coin"] = {"guid": "coin", "fields": {"displayName": "Coin", "category": 7}}
	catalog.data.cards.append(catalog.definitions.coin)
	catalog.definitions["food"] = {"guid": "food", "fields": {"category": 3, "nutrition": 2}}
	var session = Session.new()
	session.configure(catalog, 23)
	var hero: int = session.spawn_card("hero")
	var weapon: int = session.spawn_card("weapon")
	check(session.equipment.equip(hero, weapon), "session owns configured equipment")
	check(session.stats().cards_owned == 1 and session.world_cards().size() == 1, "equipped gear excluded from source AllCards and capacity")
	var target: int = session.spawn_card("mob")
	check(not session.move_to_stack(weapon, session.cards[target].stack_id) and session.split_stack(weapon, Vector2.ZERO) == -1 and not session.sell_card(weapon), "stackless equipment guards")
	check(session.sell_card(hero), "sell equipped wearer")
	check(not session.cards.has(weapon) and session.equipment.owners.is_empty(), "ordinary wearer destruction removes attached gear")
	hero = session.spawn_card("hero")
	weapon = session.spawn_card("weapon")
	session.equipment.equip(hero, weapon)
	var fight: int = session.combat.start_combat([hero], [target])
	check(fight > 0 and not session.move_to_stack(hero, session.cards[weapon].stack_id) and session.split_stack(hero, Vector2.ZERO) == -1 and not session.sell_card(hero), "stackless fighter guards")
	session.paused = true
	var before: float = session.combat.tasks[fight].progress[hero]
	session.tick(0.2)
	check(session.combat.tasks[fight].progress[hero] == before, "session pause gates combat tick")
	session.paused = false
	session.speed = 2.0
	session.tick(0.1)
	check(is_equal_approx(session.combat.tasks[fight].progress[hero], before + 20), "session scales combat delta once")
	catalog.definitions.hero.fields["loot"] = [{"Card": {"guid": "food"}, "Weight": 1}]
	catalog.definitions.mage.fields["loot"] = [{"Card": {"guid": "blade"}, "Weight": 1}]
	check(session.kill_card(hero), "kill equipped combatant")
	check(session.stats().nutrition == 2, "death loot uses reverted original class")
	check(session.cards.has(weapon) and session.stacks.has(session.cards[weapon].stack_id) and session.equipment.owners.is_empty(), "kill drops gear instead of destroying")
	check(session.combat.tasks.is_empty() and session.stacks.has(session.cards[target].stack_id), "external death ends fight and returns survivor")
	hero = session.spawn_card("hero")
	var armor: int = session.spawn_card("armor")
	session.equipment.equip(hero, armor)
	session.cards[hero].health = 1
	session.end_day()
	check(session.cards[hero].health == 16, "feeding uses equipped maximum health")
	session.start_new_game()
	check(session.equipment.equipped.is_empty() and session.combat.tasks.is_empty() and session.equipment.owners.is_empty(), "new game resets helpers")
