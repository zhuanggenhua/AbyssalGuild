extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const CombatLayout = preload("res://scripts/model/combat_layout.gd")
const BoardLayout = preload("res://scripts/model/board_layout.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func drop(board, id: int, destination: Vector2) -> void:
	board.dragging = id
	board.drag_moved = true
	board.drag_delta = destination - board.session.cards[id].position
	board._finish_drag(board.camera.unproject_position(Vector3(destination.x, 0, -destination.y)))
func run() -> void:
	var board = Board.new()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "real source data loaded")
	if board.data_error != OK: quit(1); return
	board.start_new()
	board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board._refresh()
	check(board.session.spawn_target_selector.is_valid() and board.session.spawn_layout_resolver.is_valid(), "native factory geometry callbacks bound")
	check(not board.session.ai.produce_spawner.is_valid(), "AI delegates to native factory without double attachment")
	var villager_guid: String = board.catalog.find_by_name("Villager")
	var enemy_guid: String = ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2:
			enemy_guid = entry.guid
			break
	var player: int = board.session.spawn_card(villager_guid, Vector2(-3, -1), -1, {"refuse_attach": true})
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(1, -1), -1, {"refuse_attach": true})
	drop(board, player, board.session.cards[enemy].position)
	check(board.session.combat.membership.has(player) and board.session.combat.membership.has(enemy), "drag onto enemy starts fight before ordinary stack")
	var task_id: int = board.session.combat.membership[player]
	var state: Dictionary = board.combat_layouts[task_id]
	var center: Vector2 = state.center
	var cell: Vector2 = state.cell
	check(board.combat_rectangles.has(task_id) and board.combat_rectangles[task_id].mesh != null, "original generated rectangle rendered")
	check(board.session.cards[player].position == state.positions[player] and board.session.cards[enemy].position == state.positions[enemy], "helper slots applied to model fighters")
	check(board.views[player].position.z == -state.positions[player].y, "combat view reflects helper world Z")
	check(board._combat_geometry()[0].position == center, "AI gets actual retained rectangle center")
	check(board._can_drag_card(player) and not board._can_drag_card(enemy), "only player attacking side draggable in combat")
	# Joining resizes without reseeding the cached cell or moving the center.
	var recruit: int = board.session.spawn_card(villager_guid, Vector2(-4, -2), -1, {"refuse_attach": true})
	drop(board, recruit, center)
	state = board.combat_layouts[task_id]
	check(board.session.combat.membership.get(recruit, -1) == task_id, "drag into rectangle joins existing task")
	check(state.center == center and state.cell == cell and state.attackers.size() == 2, "join preserves original center and cell spacing")
	var expected: Dictionary = CombatLayout.update_layout(state, board._fighter_records(state.attackers), board._fighter_records(state.defenders))
	check(state.bounds == expected.bounds and state.positions == expected.positions, "current size and slots match exact helper")
	# A free stack spawned inside combat is displaced by exact rectangle bounds.
	var wood: int = board.session.spawn_card(board.catalog.find_by_name("Wood"), center, -1, {"refuse_attach": true})
	board._refresh()
	var wood_state: Dictionary = {}
	for candidate in board._layout_states():
		if candidate.id == board.session.cards[wood].stack_id: wood_state = candidate
	check(BoardLayout.separation(BoardLayout.stack_bounds(wood_state), state.bounds).length() < 0.001, "stack separation respects combat rectangle bounds")
	# Model drift cannot redefine an established combat center.
	board.session.cards[player].position += Vector2(2, 0)
	board._sync_combat_layouts()
	check(board.combat_layouts[task_id].center == center and board.session.cards[player].position == state.positions[player], "sync restores slots without averaging moved fighters")
	var gear: int = board.session.spawn_card(board.catalog.find_by_name("Sword"), Vector2(-5, -2), -1, {"refuse_attach": true})
	drop(board, gear, board.session.cards[player].position)
	check(board.session.equipment.owners.get(gear, -1) == player, "equipment drop finds detached combat character before ordinary stacking")
	check(not board.session.combat.membership.has(gear) and board.session.combat.tasks[task_id].attackers.size() == 2, "equipment does not join combat as a fighter")
	board._save_game()
	check(board.notice.text == "Saved locally.", "combat layout campaign saves")
	board._return_title()
	board._continue_game()
	board.set_process(false)
	state = board.combat_layouts[task_id]
	check(state.center == center and state.cell == cell, "Continue restores minimal layout center and cell")
	check(board.session.equipment.owners.get(gear, -1) == player, "Continue restores fighter equipment with layout")
	check(state.has("config") and state.has("positions") and board.combat_rectangles.has(task_id), "Continue reconstructs imported config and rendered geometry")
	check(board.session.spawn_target_selector.is_valid() and board.session.spawn_layout_resolver.is_valid(), "Continue rebinds factory callbacks")
	# Inside drops and defending-side outside drops return to slots, not flee.
	var slot: Vector2 = state.positions[player]
	drop(board, player, center)
	check(board.session.combat.membership.has(player) and board.session.cards[player].position == slot, "inside attacker drop snaps to slot")
	drop(board, enemy, Vector2(-20, -20))
	check(board.session.combat.membership.has(enemy) and board.session.cards[enemy].position == state.positions[enemy], "defender cannot flee outside rectangle")
	drop(board, player, Vector2(-20, -20))
	check(not board.session.combat.membership.has(player) and board.session.stacks.has(board.session.cards[player].stack_id), "outside attacker drop flees to board")
	check(board.session.cards[player].position.is_equal_approx(board._clamp_stack_position(player, Vector2(-20, -20))), "flee position obeys singleton source clamp")
	check(board.combat_layouts[task_id].center == center and board.combat_layouts[task_id].cell == cell, "removing fighter retains center and cell")
	var survivor_position: Vector2 = board.session.cards[enemy].position
	drop(board, recruit, Vector2(-20, -20))
	check(board.session.combat.tasks.is_empty() and board.combat_layouts.is_empty() and board.combat_rectangles.is_empty(), "last attacker flee removes task and rectangle")
	check(board.session.stacks.has(board.session.cards[enemy].stack_id), "combat survivor returns to singleton board stack")
	check(board.session.cards[enemy].position.is_equal_approx(board._clamp_stack_position(enemy, survivor_position)), "survivor keeps current slot then source clamp")
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board._refresh()
	player = board.session.spawn_card(villager_guid, Vector2(-2, -1), -1, {"refuse_attach": true})
	enemy = board.session.spawn_card(enemy_guid, Vector2(2, -1), -1, {"refuse_attach": true})
	drop(board, enemy, board.session.cards[player].position)
	task_id = board.session.combat.membership[enemy]
	check(not board.session.combat.tasks[task_id].player_is_attacker, "mob drag initiates mob-attacker fight")
	check(not board._can_drag_card(enemy) and not board._can_drag_card(player), "mob-initiated fight allows neither side attacker-flee drag")
	drop(board, player, Vector2(-20, -20))
	check(board.session.combat.membership.has(player), "player defender cannot flee mob-initiated fight")
	print("Combat board checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)
