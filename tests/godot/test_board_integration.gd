extends SceneTree
## Real source-backed board adapter checks, not Unity hit-order or visual parity.
const Board = preload("res://scripts/ui/board.gd")
const Layout = preload("res://scripts/model/board_layout.gd")
const SceneSpawn = preload("res://scripts/model/scene_spawn.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func clear_board(board) -> void:
	board.dragging = -1
	board.layout_locks.clear()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board._refresh()

func state(board, id: int) -> Dictionary:
	for item in board._layout_states():
		if item.id == board.session.cards[id].stack_id: return item
	return {}

func run() -> void:
	var board = Board.new()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "real source data required for board integration")
	if board.data_error != OK:
		board.queue_free()
		await process_frame
		quit(1)
		return
	board.start_new()
	board.set_process(false)
	var starter: String = board.session.cards.values()[0].definition_guid
	check(not board.market_panel.visible and not board.detail_panel.visible, "sidebars initially hidden to avoid covering starter")
	var toggles: Dictionary = {}
	for node in board.hud.get_children():
		if node is Button and node.text in ["Market & controls", "Inspect & journal"]: toggles[node.text] = node
	check(toggles.size() == 2, "both sidebar toggle buttons available")
	for caption in toggles:
		var button: Button = toggles[caption]
		check(button.visible and not button.disabled and button.position.y == 835, "sidebar toggle accessible at bottom: " + caption)
		button.pressed.emit()
	check(board.market_panel.visible and board.detail_panel.visible, "sidebar buttons reveal controls and inspector")
	for button in toggles.values(): button.pressed.emit()
	check(not board.market_panel.visible and not board.detail_panel.visible, "sidebar buttons close panels without replacing board")
	clear_board(board)
	var wood_guid: String = board.catalog.find_by_name("Wood")
	var a: int = board.session.spawn_card(wood_guid)
	var b: int = board.session.spawn_card(wood_guid)
	var raw: Vector3 = board._card_collider_size(a)
	var footprint: Vector2 = board._card_footprint(a)
	check(raw.x > 0 and raw.z > 0, "real source collider resolved")
	check(footprint.is_equal_approx(Vector2(raw.x, raw.z) + Vector2(0.1, 0.1)), "source margin adds 0.1 on each footprint axis")
	board._resolve_layout()
	check(Layout.separation(Layout.stack_bounds(state(board, a)), Layout.stack_bounds(state(board, b))).length() < 0.001, "overlapping stacks separate")
	check(board.session.cards[a].position == board.session.stacks[board.session.cards[a].stack_id].position, "layout synchronizes card and stack positions")
	# A dragged stack stays fixed while the other yields.
	for id in [a, b]:
		board.session.stacks[board.session.cards[id].stack_id].position = Vector2.ZERO
		board.session.cards[id].position = Vector2.ZERO
	board.dragging = a
	check(state(board, a).locked, "dragging marks layout state locked")
	board._resolve_layout()
	check(board.session.cards[a].position == Vector2.ZERO and board.session.cards[b].position != Vector2.ZERO, "drag lock holds selected stack while neighbor separates")
	board.dragging = -1
	for id in [a, b]:
		board.session.stacks[board.session.cards[id].stack_id].position = Vector2.ZERO
		board.session.cards[id].position = Vector2.ZERO
	board.layout_locks[board.session.cards[a].stack_id] = true
	board._resolve_layout()
	check(board.session.cards[a].position == Vector2.ZERO, "explicit pack-animation lock holds stack")
	board.layout_locks.clear()
	# Collider broad phase must include a card whose center is outside radius.
	clear_board(board)
	var moving: int = board.session.spawn_card(wood_guid, Vector2(-4, -2))
	var target: int = board.session.spawn_card(wood_guid, Vector2.ZERO)
	var target_stack: int = board.session.cards[target].stack_id
	var edge := Vector3(raw.x * 0.5 + 0.2, 0, 0)
	check(edge.length() > 0.25, "test point lies outside old center-radius shortcut")
	check(board._nearby_stack(moving, edge, 0.25) == target_stack, "attachment uses sphere-collider intersection")
	check(board._nearby_stack(moving, edge, 0.25, target_stack) == -1, "explicit ignored stack excluded")
	check(board._nearby_stack(moving, Vector3(raw.x * 0.5 + 0.26, 0, 0), 0.25) == -1, "outside collider and radius cannot attach")
	clear_board(board)
	moving = board.session.spawn_card(wood_guid, Vector2(-4, -2))
	var invalid: int = board.session.spawn_card(starter, Vector2.ZERO)
	target = board.session.spawn_card(wood_guid, Vector2(0.35, 0))
	check(not board.session.can_move_to_stack(moving, board.session.cards[invalid].stack_id), "nearest pack is ineligible fixture")
	var before: String = str(board.session.stacks.keys()) + str(board.session.cards.keys())
	check(board._nearby_stack(moving, Vector3.ZERO, 1.0) == board.session.cards[target].stack_id, "invalid nearest candidate does not mask valid farther candidate")
	check(before == str(board.session.stacks.keys()) + str(board.session.cards.keys()), "candidate query does not change membership")
	# A real click keeps pack XZ and separates output without an arbitrary spawn offset.
	clear_board(board)
	var pack: int = board.session.spawn_card(starter, Vector2(-2, -1))
	var pack_position: Vector2 = board.session.cards[pack].position
	var observation := {"id": -1, "position": Vector2.INF, "locked": false}
	var observe := func(kind: String, payload: Dictionary):
		if kind == "pack_opened":
			observation.id = int(payload.card_id)
			observation.position = board.session.cards[observation.id].position
			observation.locked = board.layout_locks.has(board.session.cards[pack].stack_id)
	board.session.event_occurred.connect(observe)
	board.dragging = pack
	board.drag_moved = false
	board._finish_drag(Vector2.ZERO)
	board.session.event_occurred.disconnect(observe)
	observe = Callable()
	check(observation.locked, "actual pack draw locks source stack during emission")
	check(observation.position == pack_position, "pack output starts at source pack XZ")
	check(board.session.cards[pack].position == pack_position, "pack remains stationary while output separates")
	check(board.session.cards[observation.id].position.distance_to(pack_position) > 0.1, "drawn output separates through solver")
	check(board.layout_locks.is_empty(), "pack draw releases temporary lock")
	# Geometry shrink clamps existing full stack to the source board limits.
	clear_board(board)
	var booster_guid: String = ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("boostAmount", 0)) > 0:
			booster_guid = entry.guid
			break
	check(not booster_guid.is_empty(), "source capacity booster available")
	var booster: int = board.session.spawn_card(booster_guid)
	a = board.session.spawn_card(wood_guid)
	board._update_board_geometry()
	var expanded: Rect2 = board.session.board_bounds
	var edge_position: Vector2 = board._clamp_stack_position(a, expanded.end)
	board.session.stacks[board.session.cards[a].stack_id].position = edge_position
	board.session.cards[a].position = edge_position
	board.session._remove_card(booster)
	board._update_board_geometry()
	check(board.session.board_bounds.get_area() < expanded.get_area(), "removing booster shrinks source board bounds")
	check(board.session.cards[a].position.is_equal_approx(board._clamp_stack_position(a, edge_position)), "shrink clamps card using source footprint and top margin")
	var shrunk: Rect2 = board.session.board_bounds
	var half: Vector2 = board._card_footprint(a) * 0.5
	var clamped: Vector2 = board.session.cards[a].position
	check(clamped.x >= shrunk.position.x + half.x - 0.0001 and clamped.x <= shrunk.end.x - half.x + 0.0001 and clamped.y >= shrunk.position.y + half.y - 0.0001 and clamped.y <= shrunk.end.y - half.y - board.session.board_top_margin + 0.0001, "shrunk card is inside legal placement area within float tolerance")
	# With no overlapping cards left, purchase location remains the source vendor spawn.
	clear_board(board)
	var offer: String = board.vendor_guids[0]
	var requirement: int = int(board.catalog.fields(offer).get("minQuests", 0))
	var quest_ids: Array = board.session.quest_tracker.definitions.keys()
	for i in range(requirement): board.session.quest_tracker.completed_ids[quest_ids[i]] = true
	check(board.session.completed_quests >= requirement, "source vendor quest requirement satisfied")
	var price: int = int(board.catalog.fields(offer).get("buyPrice", 3))
	for i in range(price): board.session.spawn_card(board.catalog.find_by_name("Coin"), Vector2.ZERO)
	var expected: Vector2 = SceneSpawn.vendor_position(board.catalog, board.session.scene_name, offer, board.session.board_bounds, board.session.board_top_margin)
	board._buy(offer)
	var purchase: int = -1
	for card in board.session.cards.values():
		if card.definition_guid == offer: purchase = card.id
	check(purchase >= 0, "UI purchase creates offered pack")
	if purchase >= 0:
		check(board.session.cards[purchase].position.is_equal_approx(expected), "purchase uses source vendor spawn without arbitrary relocation")
	check(board.session.stats().currency == 0, "purchase consumes exact source price")
	print("Board integration checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	# Drain deferred node/audio/resource deletion before terminating the tree.
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)
