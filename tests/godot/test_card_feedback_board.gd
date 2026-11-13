extends SceneTree
## Live board/model integration with source data. Headless input/structure, not GPU QA.
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class BoardAdapter extends "res://scripts/ui/board.gd":
	var hit := {"card_id": -1, "panel_owner": -1}
	var real_pick: bool = false
	func _pick_target(point: Vector2) -> Dictionary:
		return super._pick_target(point) if real_pick else hit
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _init() -> void: call_deferred("run")
func spawn(board, title: String, position: Vector2, target: int = -1) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(title), position, target, {"refuse_attach": true})
func point(board, id: int, panel: int = -1) -> void:
	board.hit = {"card_id": id, "panel_owner": panel}
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(950, 350)
	board._input(motion)
	board._sync_card_feedback()
func press(board, id: int) -> void:
	board.hit = {"card_id": id, "panel_owner": -1}
	board._begin_card_press(board.hit, board.camera.unproject_position(board.views[id].global_position))
	board._sync_views()
func clear_cards(board) -> void:
	board.vendor_unlock.cancel()
	board.session.drag.reset(); board.dragging = -1; board.drag_grant = -1; board.drag_delta = Vector2.ZERO
	board.session.combat.dragged.clear()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.phase = "playing"; board.session.paused = false; board.session.cycle.reset()
	board.session.elapsed = 0; board.session.speed = 1
	board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	board.pause_overlay.hide(); board.options_panel.hide()
	board._clear_card_feedback(); board.hit = {"card_id": -1, "panel_owner": -1}
	board._refresh()
func fruit(board) -> Array:
	clear_cards(board)
	var apple: int = spawn(board, "Apple", Vector2(-3, -1))
	var berry: int = spawn(board, "Berry", Vector2(0, -1))
	check(board.session.move_to_stack(berry, board.session.cards[apple].stack_id), "source Fruit Salad ingredients attach")
	var stack = board.session.stacks[board.session.cards[apple].stack_id]
	stack.progress = 3.0
	board._refresh()
	return [apple, berry, stack]

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	var board := BoardAdapter.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://card-feedback-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(not board.card_hover.visible and board.craft_progress.bars.is_empty(), "title starts with no hover or task bars")
	check(board.data_error == OK, "licensed source catalog required")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false)
	clear_cards(board)
	var fighter: int = spawn(board, "Warrior", Vector2(-2, -1))
	var wood: int = spawn(board, "Wood", Vector2(2, -1))
	board._refresh(); await physics_frame
	# Exercise the real physics ray/pointer route before the deterministic edge cases.
	board.real_pick = true
	var screen: Vector2 = board.camera.unproject_position(board.views[fighter].global_position)
	check(int(board._pick_target(screen).card_id) == fighter, "actual source card collider is ray-pickable")
	var motion := InputEventMouseMotion.new(); motion.position = screen
	board._input(motion); board._sync_card_feedback()
	check(board.card_hover.visible and board.hovered_card_id == fighter and board.card_hover.descriptor.kind == "card", "actual mouse-motion route shows hovered card information")
	board.real_pick = false
	board.notice.text = "SAVE FAILED: preserved notice"
	var action_text: String = board.day_button.text
	point(board, fighter)
	check(board.card_hover.body.text.contains("Crit. Multiplier") and board.selected == -1, "hover shows effective combat fields without selecting card")
	check(board.notice.text == "SAVE FAILED: preserved notice" and board.day_button.text == action_text, "hover never overwrites existing notice or cycle action")
	board.session.cards[fighter].health = 6; board._sync_views()
	check(board.card_hover.body.text.contains("Health (6/"), "stationary pointer refreshes live health")
	var old_view = board.views[fighter]
	board.session.cards[fighter].definition_guid = board.catalog.find_by_name("Mage")
	board._sync_views()
	check(board.views[fighter] != old_view and board.card_hover.descriptor.header == "Mage", "class-change rebuild replaces stale view and tooltip")
	# Bounded panel cannot cover the fixed day action or ordinary notice.
	check(not board.day_button.visible and not board.card_hover.get_global_rect().intersects(board.notice.get_global_rect()), "source hover has no simultaneous modal action and leaves diagnostic notice unobscured")
	var fields: Dictionary = board.catalog.fields(board.session.cards[fighter].definition_guid)
	var original_description: String = fields.description
	fields.description = "Readable long description. ".repeat(100)
	board._sync_views(); await process_frame
	board.card_hover.body.get_v_scroll_bar().value = 60
	var scroll: float = board.card_hover.body.get_v_scroll_bar().value
	board.hit.card_id = wood
	board._sync_card_hover(board.card_hover.body)
	check(board.hovered_card_id == fighter and board.card_hover.body.get_v_scroll_bar().value == scroll, "scrolling own panel retains source and scroll rather than ray-picking behind it")
	check(board.card_hover.mouse_filter == Control.MOUSE_FILTER_STOP, "hover header/background block clicks through to board")
	var panel_point: Vector2 = board.card_hover.body.get_global_rect().get_center()
	var over_panel := InputEventMouseMotion.new(); over_panel.position = panel_point
	root.push_input(over_panel); await process_frame
	board._sync_card_feedback()
	check(board._own_hover_control(root.gui_get_hovered_control()) and board.hovered_card_id == fighter, "native GUI pointer route retains tooltip over its own scrolling body")
	var camera_target: Vector3 = board.camera_motion.target
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true; wheel.position = panel_point
	root.push_input(wheel); await process_frame
	check(board.camera_motion.target != camera_target and board.hovered_card_id == fighter, "source wheel over information also zooms without dismissing tooltip")
	var panel_click := InputEventMouseButton.new(); panel_click.button_index = MOUSE_BUTTON_LEFT; panel_click.pressed = true; panel_click.position = panel_point
	root.push_input(panel_click); await process_frame
	check(board.dragging == -1 and board.selected == -1, "actual information-panel click never selects or drags a card behind it")
	panel_click.pressed = false; root.push_input(panel_click)
	over_panel.position = Vector2(950, 350); root.push_input(over_panel); await process_frame
	board._sync_card_hover(board.day_button)
	check(not board.card_hover.visible and board.hovered_card_id == -1, "unrelated GUI clears hover")
	fields.description = original_description
	point(board, fighter)
	root.size = Vector2i(560, 360); await process_frame
	# The private runner keeps project.godot's canvas_items stretch: physical
	# Window.size can shrink while the logical canvas remains 1440 x 900.
	check(root.get_visible_rect().encloses(board.card_hover.get_global_rect()), "hover bounds fit logical canvas after physical window resize")
	var previous_scale: Vector2i = root.content_scale_size
	root.content_scale_size = Vector2i(560, 360); await process_frame
	check(board.hud.size == Vector2(560, 360), "narrow fixture actually resizes the logical HUD")
	check(Rect2(Vector2.ZERO, Vector2(560, 360)).encloses(board.card_hover.get_global_rect()), "hover bounds fit narrower logical viewport")
	root.content_scale_size = previous_scale
	root.size = Vector2i(1440, 900); await process_frame
	point(board, fighter)
	board._notification(Node.NOTIFICATION_WM_MOUSE_EXIT); board._sync_views()
	check(not board.card_hover.visible and not board._card_pointer_known, "window exit clears and prevents stale automatic hover")
	point(board, fighter)
	board._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT); board._sync_views()
	check(not board.card_hover.visible, "focus loss clears hover")
	point(board, -1)
	check(not board.card_hover.visible and board.hovered_panel_owner == -1, "empty board clears all hover routes")
	point(board, wood); board.session.kill_card(wood); board._sync_views()
	check(not board.card_hover.visible and not board.views.has(wood), "death clears card view and hover together")

	test_equipment_hover(board)
	test_drag_targets(board)
	await test_craft_and_lifecycle(board)
	board.queue_free(); await process_frame; await create_timer(0.3).timeout
	print("Card feedback board checks: %d passed / %d total; no GPU/manual input acceptance" % [checks - failures, checks])
	quit(1 if failures else 0)

func test_equipment_hover(board) -> void:
	clear_cards(board)
	var wearer: int = spawn(board, "Villager", Vector2(-2, -1))
	var gear: int = spawn(board, "Sword", Vector2(2, -1))
	board._sync_views()
	check(board.session.equipment.equip(wearer, gear), "source equipment attaches for panel routing")
	board._sync_views()
	check(board.equipment_display.is_expanded(wearer) and board.views[gear].visible, "live gear expansion exists")
	point(board, wearer, wearer)
	check(board.hovered_panel_owner == wearer and board.hovered_card_id == -1 and board.card_hover.descriptor.kind == "equipment_panel", "panel-owner collider follows distinct panel tooltip path")
	check(board.card_hover.header.text == "[Equipments]" and board.card_hover.body.text == "• Sword", "panel hover is the source inventory-name list")
	point(board, gear)
	check(not board.card_hover.visible, "visible equipped card itself keeps source-empty stackless tooltip")
	board.equipment_display.click_panel(wearer)
	point(board, gear)
	check(not board.card_hover.visible and not board.views[gear].visible, "hidden gear cannot resurrect a stale picked tooltip")
	point(board, wearer, wearer)
	check(board.card_hover.visible, "closed compact panel remains a valid inventory hover")
	var enemy_guid := ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2: enemy_guid = entry.guid; break
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(2, -1), -1, {"refuse_attach": true})
	check(board.session.combat.start_combat([wearer], [enemy]) > 0, "actual combat detaches wearer")
	board._sync_views(); point(board, wearer)
	check(not board.card_hover.visible, "live combat member also follows source-empty stackless tooltip")
	point(board, wearer, wearer)
	check(board.card_hover.visible and board.card_hover.body.text == "• Sword", "combat owner's equipment panel still exposes inventory names")
	board.session.equipment.unequip(wearer, 0); board._sync_views()
	check(not board.card_hover.visible, "last unequip removes compact-panel hover")
	point(board, gear)
	check(board.card_hover.visible and board.card_hover.descriptor.header == "Sword", "returned loose equipment recovers singleton tooltip")

func test_drag_targets(board) -> void:
	clear_cards(board)
	var incoming: int = spawn(board, "Wood", Vector2(-3, -1))
	var target: int = spawn(board, "Wood", Vector2(3, -1))
	var station: int = spawn(board, "Sawmill", Vector2(0, 1))
	var working = board.session.stacks[board.session.cards[station].stack_id]
	for index in 4: spawn(board, "Wood", Vector2.ZERO, working.id)
	board.session._check_recipe(working); working.progress = 2
	board._refresh()
	check(not working.recipe_guid.is_empty() and board.session.can_move_to_stack(incoming, working.id), "source excess-ingredient craft can accept incoming wood")
	board.views[target].set_hurt_flash(0.7)
	var color: Color = board.views[target].material.albedo_color
	press(board, incoming)
	check(board.card_drag_targets.has(target) and board.views[target].drag_target.visible, "actual press shows distant model-qualified target without radius filtering")
	check(not board.card_drag_targets.has(incoming) and not board.card_drag_targets.has(working.card_ids.back()), "own and actively crafting stacks stay unhighlighted")
	check(board.views[incoming].material.emission_enabled and board.views[target].hurt_flash == 0.7 and board.views[target].material.albedo_color == color, "target outline preserves selection and hurt flash")
	var expected: Dictionary = {}
	for stack in board.session.stacks.values():
		if stack.recipe_guid.is_empty() and board.session.can_move_to_stack(incoming, stack.id): expected[stack.card_ids.back()] = true
	check(board.card_drag_targets.keys() == expected.keys(), "board targets exactly match model-qualified source highlight subset")
	var snapshot: String = JSON.stringify(Codec._capture_unsettled(board.session))
	var rng_before: int = board.session.rng.state
	for iteration in 5: board._sync_card_feedback()
	check(JSON.stringify(Codec._capture_unsettled(board.session)) == snapshot and board.session.rng.state == rng_before, "presentation refresh does not alter live hold/model/RNG")
	board._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT); board._sync_card_feedback()
	check(board.card_drag_targets.has(target) and board.views[target].drag_target.visible and board.drag_grant == incoming, "focus loss preserves source down-sampled highlights")
	point(board, incoming)
	check(board.card_drag_targets.has(target), "fresh pointer update leaves existing source snapshot intact")
	board._toggle_pause_menu()
	check(board.card_drag_targets.has(target) and board.views[target].drag_target.visible and board.drag_grant == incoming, "menu preserves source highlight and held permission")
	board._toggle_pause_menu(); point(board, incoming)
	var release := InputEventMouseButton.new(); release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false; release.position = Vector2(950, 350)
	board._input(release)
	check(board.card_drag_targets.is_empty() and not board.views[target].drag_target.visible and board.dragging == -1, "global pointer-up clears every target immediately")
	board._input(release)
	check(board.card_drag_targets.is_empty(), "duplicate release cannot restore targets")
	press(board, incoming); board.session.kill_card(incoming); board._sync_views()
	check(board.dragging == -1 and board.card_drag_targets.has(target) and board.views[target].drag_target.visible, "destroyed held source has no source OnPointerUp to clear other target outlines")

func test_craft_and_lifecycle(board) -> void:
	var ids := fruit(board)
	var stack = ids[2]
	point(board, ids[0])
	check(board.card_hover.descriptor.kind == "craft" and board.craft_progress.bars.size() == 1, "live recipe shows hover and one world meter")
	var meter: Node3D = board.craft_progress.bars[stack.id].root
	var anchor: Vector3 = meter.position
	var body: String = board.card_hover.body.text
	press(board, ids[1]); point(board, ids[0])
	check(stack.paused and stack.card_ids == [ids[0]] and not board.session.matches_recipe(stack, board.catalog.fields(stack.recipe_guid)), "actual partial-tail pickup leaves paused incomplete original")
	check(board.card_hover.body.text == body and board.craft_progress.bars[stack.id].root == meter and meter.get_meta("paused"), "paused incomplete original retains countdown and exact existing meter")
	board._process(0.2)
	check(stack.progress == 3 and meter.position == anchor and board.card_hover.body.text == body, "board tick freezes incomplete recipe without following lifted tail")
	board._open_options()
	check(not board.card_hover.visible and board.craft_progress.bars.is_empty() and board.drag_grant == ids[1], "Options clears feedback while retaining live held task/grant")
	board.options_panel.hide(); board.pause_overlay.hide(); point(board, ids[0])
	check(board.craft_progress.bars.has(stack.id) and stack.progress == 3 and board.card_hover.descriptor.kind == "craft", "closing menus rebuilds same paused task snapshot")
	board._set_board_card_position(ids[1], Vector2(3, -1)); board.drag_moved = true
	board._finish_drag(Vector2.ZERO)
	check(stack.recipe_guid.is_empty() and board.craft_progress.bars.is_empty(), "nonreturn release cancels model task and removes meter")
	ids = fruit(board); stack = ids[2]; board.session.paused = true; point(board, ids[0])
	check(board.card_hover.visible and board.craft_progress.bars[stack.id].root.get_meta("paused"), "manual time pause keeps card information and frozen meters")
	board.notice.text = "SAVE FAILED: independent notice"
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		board.session.phase = phase; board._sync_card_feedback()
		check((not board.card_hover.visible if phase == "encounter" else board.card_hover.visible and board.card_hover.descriptor.header in ["End of Day 1", "Feeding People", "Sell Excess Cards", "Start of Day 2", "Game Over"]) and board.craft_progress.bars.has(stack.id) and board.notice.text == "SAVE FAILED: independent notice", phase + " information outranks hover without losing frozen craft bar or notice")
	board.session.phase = "playing"; point(board, ids[0])
	var zones: Array = board.trade_zones.duplicate(true); zones[1].active = true
	board.vendor_unlock.sequence.on_quest_completed(zones); board._sync_card_feedback()
	check(board.vendor_unlock.is_active() and not board.vendor_unlock.info_panel.visible and board.card_hover.visible and board.card_hover.descriptor.header == "Pack Unlocked", "source vendor reveal owns information priority")
	check(board.craft_progress.bars[stack.id].root.get_meta("paused") and board.notice.text == "SAVE FAILED: independent notice", "vendor reveal preserves bar and ordinary save-error notice")
	board.vendor_unlock.cancel(); point(board, ids[0])
	board.game_over_dialog.popup_centered()
	check(not board.card_hover.visible and board.craft_progress.bars.is_empty(), "native confirmation dialog immediately clears lower-priority feedback")
	board.game_over_dialog.hide(); point(board, ids[0])
	board.pause_overlay.show(); board._show_title()
	check(not board.running and not board.card_hover.visible and board.craft_progress.bars.is_empty() and not board._card_pointer_known, "title cleanup survives menu-hide visibility callbacks")
	board._enter_game(); board.set_process(false)
	check(not board.card_hover.visible and board.craft_progress.bars.has(stack.id), "reenter restores tasks but does not resurrect stale hover")
	point(board, ids[0])
	var old_meter: Node3D = board.craft_progress.bars[stack.id].root
	var replacement = Session.new(); replacement.configure(board.catalog)
	check(Codec.restore(replacement, Codec.capture(board.session)).ok, "replacement session retains same numeric card/stack IDs")
	board.session = replacement; board._enter_game(); board.set_process(false)
	check(board.hovered_card_id == -1 and not board.card_hover.visible and board.craft_progress.bars[stack.id].root != old_meter, "session rebind cannot reuse hovered IDs or old task nodes")
	# Actual campaign travel rebuilds scene ownership through the normal event path.
	var recipe: Dictionary = {}
	for entry in board.catalog.data.recipes:
		if entry.get("script_class", "") == "TravelRecipe": recipe = entry; break
	var portal: int = spawn(board, "Grand Portal", Vector2(1, -2))
	var travel_stack: int = board.session.cards[portal].stack_id
	spawn(board, "Villager", Vector2(1, -2), travel_stack)
	board._sync_views(); point(board, portal)
	var travelled: Dictionary = board.session.campaign.travel(travel_stack, str(recipe.guid))
	check(travelled.ok and board.session.scene_name == "Island", "actual source travel commits destination")
	check(not board.card_hover.visible and board.hovered_card_id == -1 and board.hovered_panel_owner == -1 and board.card_drag_targets.is_empty(), "travel clears both hover identities and all drag targets")
	check(not board.craft_progress.bars.has(stack.id) and board._feedback_scene == "Island", "destination has no departure task bar")
	board._show_title()
	await process_frame
