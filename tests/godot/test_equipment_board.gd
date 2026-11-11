extends SceneTree
class BoardAdapter extends "res://scripts/ui/board.gd":
	var test_hit := {"card_id": -1, "panel_owner": -1}
	func _pick_target(_screen: Vector2) -> Dictionary: return test_hit
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event_name: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = BoardAdapter.new()
	# Geometry/input suite: silence async audio; runtime audio tests remain separate.
	board.feedback.free()
	board.feedback = SilentFeedback.new()
	var path := "user://equipment-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"
	board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.start_new()
	board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_layout_resolver = Callable()
	board.session.spawn_target_selector = Callable()
	var wearer: int = board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2.ZERO)
	var gear: int = board.session.spawn_card(board.catalog.find_by_name("Sword"), Vector2(4, 0))
	var loose: int = board.session.spawn_card(board.catalog.find_by_name("Sword"), Vector2(-4, 0))
	board._sync_views()
	check(board.equipment_display.records.has(wearer), "source metadata creates wearer interaction record")
	if not board.equipment_display.records.has(wearer):
		board.queue_free(); await process_frame; quit(1); return
	check(board.session.equipment.equip(wearer, gear), "real equipment attaches")
	board._sync_views()
	check(board.equipment_display.is_expanded(wearer) and board.views[gear].visible, "runtime equip opens and exposes gear")
	board._begin_card_press({"card_id": loose, "panel_owner": -1}, Vector2.ZERO)
	check(board.equipment_display.is_expanded(wearer), "any loose equipment press preserves open panel")
	board.dragging = -1
	board.session.drag.finish_standard()
	board.test_hit = {"card_id": wearer, "panel_owner": wearer}
	board._begin_card_press(board.test_hit, Vector2.ZERO)
	check(board.dragging == -1 and board.equipment_display.is_expanded(wearer), "panel press does not drag wearer or toggle before release")
	board._finish_drag(Vector2.ZERO)
	check(not board.equipment_display.is_expanded(wearer), "matching panel release closes")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	board._unhandled_input(right)
	right.pressed = false
	board._unhandled_input(right)
	check(board.equipment_display.is_expanded(wearer), "source panel click also accepts right button")
	board._begin_card_press({"card_id": -1, "panel_owner": -1}, Vector2.ZERO)
	check(not board.equipment_display.is_expanded(wearer), "empty board left press closes")
	board.equipment_display.click_panel(wearer)
	for phase in ["feeding", "selling", "ready", "game_over"]:
		board.session.phase = phase
		board._sync_views()
		check(not board.equipment_display.is_expanded(wearer) and not board.equipment_display.click_panel(wearer), phase + " closes and disables panel")
	board.session.phase = "playing"
	board._sync_views()
	check(board.equipment_display.click_panel(wearer), "day start restores toggle")
	var enemy_guid := ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2:
			enemy_guid = entry.guid; break
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(3, 0))
	board.session.combat.start_combat([wearer], [enemy])
	board._sync_views()
	check(board.equipment_display.is_expanded(wearer), "wearer combat does not close equipment")
	var position: Vector3 = board.views[gear].global_position
	board._begin_card_press({"card_id": gear, "panel_owner": -1}, Vector2.ZERO)
	check(not board.session.equipment.owners.has(gear) and board.dragging == gear, "equipped gear press unequips and starts drag despite wearer combat")
	check(board.session.cards[gear].position.is_equal_approx(Vector2(position.x, -position.z)), "unequip preserves expanded world XZ rather than wearer root")
	board.dragging = -1
	board.session.combat.dragged.clear()
	var time: float = board.equipment_display.scaled_time
	board.session.paused = true
	board._process(0.1)
	check(board.equipment_display.scaled_time == time, "manual pause freezes presentation orbit")
	board.pause_overlay.show()
	board._process(0.1)
	check(board.equipment_display.scaled_time == time, "modal pause freezes presentation orbit")
	board._show_title()
	check(board.equipment_display.records.is_empty(), "title clears controller state")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Equipment board checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
