extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const ImpactView = preload("res://scripts/ui/impact_view.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var events: Array = []
	func play_event(event_name: String) -> bool:
		events.append(event_name)
		return true
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	# Dedicated geometry/event suite, not an async audio teardown acceptance test.
	board.feedback.free()
	board.feedback = SilentFeedback.new()
	var path := "user://feedback-ui-%d" % Time.get_ticks_usec()
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
	var villager: String = board.catalog.find_by_name("Villager")
	var enemy_guid := ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category", 0)) == 9 and int(entry.fields.get("faction", 0)) == 2:
			enemy_guid = entry.guid
			break
	var first: int = board.session.spawn_card(villager, Vector2(-3, 0))
	var tail: int = board.session.spawn_card(villager, Vector2.ZERO, board.session.cards[first].stack_id)
	var last: int = board.session.spawn_card(villager, Vector2.ZERO, board.session.cards[first].stack_id)
	var enemy: int = board.session.spawn_card(enemy_guid, Vector2(2, 0))
	var root_position: Vector2 = board.session.cards[first].position
	var step: Vector3 = board._stack_step()
	var expected: Vector2 = root_position + Vector2(step.x, step.z)
	check(board._fighter_records([tail])[0].position.is_equal_approx(expected), "fighter records use derived per-card target")
	var destination: Vector2 = board.session.card_target_position(enemy)
	check(board._try_combat_drop(tail, destination, -1), "tail starts combat at dropped point")
	check(board.session.cards[first].position == root_position, "preceding stack restored after tail capture")
	check(board.session.cards[tail].position.is_equal_approx(destination), "first dragged fighter captured at destination")
	check(board.session.cards[last].position.is_equal_approx(destination + Vector2(step.x, step.z)), "second dragged fighter preserves source step")
	var task_id: int = board.session.combat.membership[tail]
	board._sync_views()
	var task: Dictionary = board.session.combat.tasks[task_id]
	for id in task.progress: task.progress[id] = 0.0
	task.progress[tail] = 100.0
	board.feedback.events.clear()
	board.session.combat.resolve_turn(task_id)
	check(board.feedback.events == ["AttackMelee"], "attack sound emitted at travel start only")
	check(task.execution.phase == "travel", "model owns in-flight travel")
	check(not board._can_drag_card(tail) and board._can_drag_card(last), "attacking actor cannot begin drag but idle ally can")
	var elapsed: float = board.session.elapsed
	var progress: Dictionary = task.progress.duplicate()
	board.pause_overlay.show()
	var actor_model_position: Vector2 = board.session.cards[tail].position
	var camera_position: Vector3 = board.camera.position
	board._process(0.1)
	check(board.views[tail].position.y > 0.12 and board.session.cards[tail].position == actor_model_position, "travel animates view without writing saved model pose")
	check(board.camera.position == camera_position, "presentation leaves navigation camera position unchanged")
	check(board.session.elapsed == elapsed and task.progress == progress, "menu pause advances no day/progress clock")
	check(is_equal_approx(task.execution.remaining, 0.2), "menu pause advances real travel once")
	board._process(0.25)
	check(task.execution.phase == "return", "menu pause resolves impact into return")
	check(board.feedback.events.size() >= 2 and board.feedback.events.count("AttackMelee") == 1, "impact emits feedback without repeated attack")
	board.feedback.events.clear()
	board._present_impact({"defender_id": enemy, "combat_type": 2, "result": {"type": "critical", "damage": 7, "advantage": 1}})
	check(board.feedback.events == ["HitRanged", "Critical"], "critical emits style hit followed by critical")
	var popup
	for child in board.get_children():
		if child is ImpactView: popup = child
	check(popup != null and popup.caption.text == "7!", "semantic critical damage popup remains available")
	if not board.visual_assets.scene_configuration(board.session.scene_name).get("combat", {}).get("hit_ui", {}).is_empty():
		check(popup.source_popup != null and not popup.caption.visible, "audited private HitUI replaces generated fallback")
		check(popup.source_popup.get_node("Damage").text == "7" and popup.source_popup.has_node("Effectiveness"), "private damage/effectiveness semantics preserved")
	var position: Vector3 = popup.position
	board.combat_presentation.advance(0.1)
	board._sync_views()
	check(is_equal_approx(board.views[enemy].hurt_flash, 0.75), "impact drives CardView flash without replacing selection emission")
	board.session._remove_card(enemy)
	check(is_instance_valid(popup) and popup.position == position, "popup owns position after lethal target removal")
	popup._process(0.4)
	check(not popup.is_queued_for_deletion(), "popup remains during real lifetime")
	popup._process(0.7)
	check(popup.is_queued_for_deletion(), "popup expires independently of model pause")
	board.feedback.events.clear()
	board._present_impact({"defender_id": -1, "combat_type": 3, "result": {"type": "miss"}})
	check(board.feedback.events == ["Miss"], "missing visual target still emits miss without attack")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Combat feedback UI checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
