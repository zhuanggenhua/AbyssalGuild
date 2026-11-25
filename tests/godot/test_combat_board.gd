extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const CombatLayout = preload("res://scripts/model/combat_layout.gd")
const BoardLayout = preload("res://scripts/model/board_layout.gd")
const CardDragInput = preload("res://scripts/ui/card_drag_input.gd")
class ColliderProbeBoard extends "res://scripts/ui/board.gd":
	var collider_sizes: Dictionary = {}
	var combat_queries: Array[Vector3] = []
	func _card_collider_size(id: int) -> Vector3:
		return collider_sizes[id] if collider_sizes.has(id) else super._card_collider_size(id)
	func _raw_nearby_stack(id: int, point: Vector3, radius: float) -> int:
		combat_queries.append(point)
		return super._raw_nearby_stack(id, point, radius)
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
func check_combat_hit_ranking(board, villager_guid: String, enemy_guid: String) -> void:
	# Deliberately different collider widths isolate per-hit ranking from
	# ordinary attach, which ranks all members of an admitted stack.
	var attacker: int = board.session.spawn_card(villager_guid, Vector2(-4, 0), -1, {"refuse_attach": true})
	var decoy: int = board.session.spawn_card(villager_guid, Vector2(4, 0), -1, {"refuse_attach": true})
	var decoy_stack: int = board.session.cards[decoy].stack_id
	var tail: int = board.session.spawn_card(villager_guid, Vector2(4, 0), decoy_stack)
	var opponent: int = board.session.spawn_card(enemy_guid, Vector2(0, 4), -1, {"refuse_attach": true})
	board._set_board_card_position(decoy, Vector2(0.30, 0))
	board._set_board_card_position(opponent, Vector2(-0.32, 0))
	var narrow := Vector3(0.04, 0.10, 0.10)
	var wide := Vector3(0.40, 0.10, 0.20)
	board.collider_sizes = {decoy: narrow, tail: wide, opponent: wide}
	var point := Vector3.ZERO
	var root_center := Vector3(0.30, 0, 0)
	var tail_center: Vector3 = root_center + board._stack_step()
	var opponent_center := Vector3(-0.32, 0, 0)
	var radius := 0.25
	check(not BoardLayout.sphere_intersects_aabb(point, radius, AABB(root_center - narrow * 0.5, narrow))
		and BoardLayout.sphere_intersects_aabb(point, radius, AABB(tail_center - wide * 0.5, wide))
		and BoardLayout.sphere_intersects_aabb(point, radius, AABB(opponent_center - wide * 0.5, wide))
		and root_center.length_squared() < opponent_center.length_squared()
		and opponent_center.length_squared() < tail_center.length_squared(), "combat probe distinguishes an admitted member from a non-hit stack root")
	check(board._raw_nearby_stack(attacker, point, radius) == board.session.cards[opponent].stack_id,
		"combat initiation ranks individual collider hits, not non-hit members of admitted stacks")
	for id in [attacker, decoy, tail, opponent]: board.session._remove_card(id)
	board.collider_sizes.clear()
	board._refresh()
func check_native_lifted_combat_query(board, villager_guid: String, enemy_guid: String, depth: float, should_fight: bool) -> void:
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var attacker: int = board.session.spawn_card(villager_guid, Vector2(-2, 0), -1, {"refuse_attach": true})
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(3, 0), -1, {"refuse_attach": true})
	board._set_board_card_position(enemy, Vector2(0, depth))
	board._refresh()
	await physics_frame
	await physics_frame
	var settings: Dictionary = CardDragInput.source_settings(board.catalog, board.session.scene_name)
	var height: float = settings.dragHeight
	var radius: float = settings.attachRadius
	var size: Vector3 = board._card_collider_size(enemy)
	var center := Vector3(0, 0, depth)
	var aabb := AABB(center - size * 0.5, size)
	check(BoardLayout.sphere_intersects_aabb(Vector3.ZERO, radius, aabb)
		and BoardLayout.sphere_intersects_aabb(Vector3(0, height, 0), radius, aabb)==should_fight,
		"authored enemy collider distinguishes both sides of the lifted-query boundary")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = board.camera.unproject_position(board.views[attacker].global_position)
	board._unhandled_input(press)
	check(board.dragging == attacker and board.session.drag.active_for(attacker), "native mouse press captures ordinary source combatant")
	var pointer: Vector2 = board.drag_origin - board.drag_anchor
	board._update_drag_position(board.camera.unproject_position(Vector3(pointer.x, 0, -pointer.y)))
	var held: Vector2 = board.session.card_target_position(attacker)
	check(held.length() < 0.0001, "native captured drag reaches exact XZ query fixture")
	board.combat_queries.clear()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = board._card_pointer
	board._input(release)
	check(board.combat_queries.size() == 1 and board.combat_queries[0].is_equal_approx(Vector3(held.x, height, held.y)),
		"ordinary combat query uses synchronously lifted source hold before grounding")
	check(board.session.combat.membership.has(attacker)==should_fight and board.session.combat.membership.has(enemy)==should_fight,
		"actual captured combatants enter combat only from a valid lifted hit")
	check(not board.session.drag.active_for(attacker),"combat or placement clears held transaction")
	if should_fight:
		check(board.session.combat.membership.get(attacker,-1)==board.session.combat.membership.get(enemy,-2),
			"both grounded stacks enter the same combat task")
func check_native_lifted_equip_query(board, villager_guid: String, depth: float, should_equip: bool) -> void:
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var gear: int = board.session.spawn_card(board.catalog.find_by_name("Sword"), Vector2(-2, 0), -1, {"refuse_attach": true})
	var wearer: int = board.session.spawn_card(villager_guid, Vector2(3, 0), -1, {"refuse_attach": true})
	board._set_board_card_position(wearer,Vector2(0,depth))
	board._refresh()
	await physics_frame
	await physics_frame
	var settings: Dictionary = CardDragInput.source_settings(board.catalog,board.session.scene_name)
	var box: Vector3 = board._card_collider_size(wearer)
	var aabb := AABB(Vector3(0,0,depth)-box*.5,box)
	check(BoardLayout.sphere_intersects_aabb(Vector3.ZERO,settings.attachRadius,aabb)
		and BoardLayout.sphere_intersects_aabb(Vector3(0,settings.dragHeight,0),settings.attachRadius,aabb)==should_equip,
		"authored character collider distinguishes grounded and lifted sword query")
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=board.camera.unproject_position(board.views[gear].global_position)
	board._unhandled_input(event)
	check(board.dragging==gear and board.session.drag.active_for(gear),"captured loose Sword starts normal hold")
	var point: Vector2 = board.drag_origin - board.drag_anchor
	board._update_drag_position(board.camera.unproject_position(Vector3(point.x,0,-point.y)))
	check(board.session.card_target_position(gear).length() < .0001,"held Sword reached the fixture XZ")
	event=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=false
	event.position=board._card_pointer
	board._input(event)
	check((board.session.equipment.owners.get(gear,-1)==wearer)==should_equip,
		"actual captured Sword %s at lifted overlap boundary"%("equips" if should_equip else "does not equip"))
	check(not board.session.drag.active_for(gear),"release clears held transaction")
func run() -> void:
	var board = ColliderProbeBoard.new()
	board.slot_root = "user://ui-test-slots-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	board.legacy_paths.clear()
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
	check_combat_hit_ranking(board, villager_guid, enemy_guid)
	var player: int = board.session.spawn_card(villager_guid, Vector2(-3, -1), -1, {"refuse_attach": true})
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(1, -1), -1, {"refuse_attach": true})
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = board.session.rng.state
	var expected_progress: Dictionary = {player: expected_rng.randf_range(0.0, 0.5), enemy: expected_rng.randf_range(0.0, 0.5)}
	var entered: Array = []
	var constructor_observer := func(kind: String, payload: Dictionary):
		if kind != "combat_entered": return
		entered.append(payload.card_id)
		var observed: Dictionary = board.session.combat.tasks[payload.combat_id]
		check(observed.combatants == [player, enemy] and observed.progress == expected_progress, "native Board entry observes complete constructor progress")
		check(board.session.rng.state == expected_rng.state, "native Board entry consumers do not reroll constructor progress")
	board.session.event_occurred.connect(constructor_observer)
	drop(board, player, board.session.cards[enemy].position)
	board.session.event_occurred.disconnect(constructor_observer)
	check(entered == [player, enemy], "native Board publishes each entry once in source order")
	check(board.session.combat.membership.has(player) and board.session.combat.membership.has(enemy), "drag onto enemy starts fight before ordinary stack")
	var task_id: int = board.session.combat.membership[player]
	var state: Dictionary = board.combat_layouts[task_id]
	var center: Vector2 = state.center
	var cell: Vector2 = state.cell
	check(board.combat_rectangles.has(task_id) and board.combat_rectangles[task_id].mesh != null, "source sliced rectangle rendered")
	if board.combat_rectangles.has(task_id):
		var rectangle: MeshInstance3D = board.combat_rectangles[task_id]
		var texture: Texture2D = rectangle.material_override.albedo_texture
		var record: Dictionary = board.visual_assets.scene_configuration(board.session.scene_name).combat.rectangle
		check(rectangle.name == "SourceCombatRectangle" and rectangle.get_meta("source_prefab_guid") == record.prefab_guid,
			"Board binds authored rectangle prefab, not placeholder")
		check(texture == board.visual_assets.texture(record.sprite.guid) and texture.get_size() == Vector2(128,128),
			"original cached rectangle texture on actual Board mesh")
		check(rectangle.position.is_equal_approx(Vector3(center.x,-0.025,-center.y))
			and rectangle.material_override.albedo_color == Color.WHITE, "source child depth and white tint")
		check(rectangle.mesh.surface_get_array_len(0) == 36 and rectangle.mesh.surface_get_array_index_len(0) == 54,
			"UGUI full nine quads including center on live Board")
		var original_mesh: Mesh = rectangle.mesh
		var moved_center: Vector2 = center + Vector2(0.375,-0.625)
		var moved := state.duplicate(true)
		moved.center = moved_center
		board._draw_combat_rectangle(task_id,moved)
		check(board.combat_rectangles[task_id] == rectangle and rectangle.mesh == original_mesh
			and rectangle.position.is_equal_approx(Vector3(moved_center.x,-0.025,-moved_center.y)),
			"same-size relocation updates pose without rebuilding mesh")
		board._draw_combat_rectangle(task_id,state)
		var island: Dictionary = board.visual_assets.scene_configuration("Island")
		check(island.world_canvas_reference_ppu == 100 and island.combat.rectangle == record,
			"Island shares the locked rectangle and effective CanvasScaler")

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
	# Real view hooks merge a new overlapping fight before allocating its task.
	var old_task: int = task_id
	var old_center: Vector2 = board.combat_layouts[old_task].center
	var second_player: int = board.session.spawn_card(villager_guid, Vector2(4, -2), -1, {"refuse_attach": true})
	var second_enemy: int = board.session.spawn_card(enemy_guid, Vector2(5, -2), -1, {"refuse_attach": true})
	board._set_board_card_position(second_player, old_center)
	board._set_board_card_position(second_enemy, old_center + Vector2(0.1, 0))
	var merged: int = board.session.combat.start_combat([second_player], [second_enemy])
	board._refresh()
	check(merged >= 0 and merged != old_task and board.session.combat.tasks.size() == 1, "view pre-start overlap hook merges existing fight")
	check(board.session.combat.tasks[merged].player_is_attacker and board.session.combat.tasks[merged].attackers.size() == 2, "merged fight normalizes player attacking side")
	check(not board.combat_rectangles.has(old_task) and board.combat_rectangles.has(merged), "merge replaces old rectangle without survivor transition")
	check(board.session.cards[player].stack_id == -1 and board.session.cards[enemy].stack_id == -1, "old fighters remain detached through merge")
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board._refresh()
	var left: int = _create_fight(board, villager_guid, enemy_guid, Vector2(-3, -1))
	var right: int = _create_fight(board, villager_guid, enemy_guid, Vector2(3, -1))
	check(left != right and board.session.combat.tasks.size() == 2, "separated fights remain independent")
	var newcomers: Array = []
	for index in range(10): newcomers.append(board.session.spawn_card(villager_guid, Vector2(0, -3), -1, {"refuse_attach": true}))
	check(board.session.combat.add_combatants(left, newcomers), "newcomers accepted before resize overlap check")
	board._refresh()
	check(board.session.combat.tasks.size() == 1 and not board.session.combat.tasks.has(left) and not board.session.combat.tasks.has(right), "resized rectangle overlap merges separate tasks")
	check(board.combat_rectangles.size() == 1 and board.combat_layouts.size() == 1, "resize merge removes stale rectangles")
	await check_native_lifted_combat_query(board, villager_guid, enemy_guid,.74,false)
	await check_native_lifted_combat_query(board, villager_guid, enemy_guid,.72,true)
	await check_native_lifted_equip_query(board,villager_guid,.74,false)
	await check_native_lifted_equip_query(board,villager_guid,.72,true)
	print("Combat board checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)

func _create_fight(board, player_guid: String, enemy_guid: String, center: Vector2) -> int:
	var player: int = board.session.spawn_card(player_guid, center, -1, {"refuse_attach": true})
	var enemy: int = board.session.spawn_card(enemy_guid, center, -1, {"refuse_attach": true})
	board._set_board_card_position(player, center + Vector2(0, -0.2))
	board._set_board_card_position(enemy, center + Vector2(0, 0.2))
	var task_id: int = board.session.combat.start_combat([player], [enemy])
	board._refresh()
	return task_id
