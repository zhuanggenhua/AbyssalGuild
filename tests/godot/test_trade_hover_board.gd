extends SceneTree
## Real source rules, injected ray result; native pointer routing checked separately.
class Probe extends "res://scripts/ui/board.gd":
	var hit := {"card_id": -1, "panel_owner": -1, "trade_zone_index": -1}
	func _pick_target(_screen: Vector2) -> Dictionary: return hit
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board := Probe.new()
	board.slot_root = "user://trade-hover-%d" % Time.get_ticks_usec()
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.start_new()
	board.set_process(false)
	board._record_card_pointer(Vector2.ZERO)
	board.hit.trade_zone_index = 0
	board._sync_card_hover(null)
	check(board.info_requests.current() == {"header":"Card Buyer", "body":"Sell your cards here."}, "buyer source hover info")
	board.trade_views[0].hide()
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty(), "disable clears owned hover")
	board.trade_views[0].show()
	board.hit.trade_zone_index = 1
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty(), "inactive vendor has no source info")
	for id in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[id] = true
	board._refresh()
	board._sync_card_hover(null)
	check(board.info_requests.current().get("header") == "Pack Vendor", "active vendor source hover")
	board.hit.trade_zone_index = -1
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty(), "pointer exit clears hover")
	board.hit.trade_zone_index = 0
	board._sync_card_hover(null)
	board.info_requests.submit("test-modal", 2, {"header":"Modal"})
	board._sync_card_hover(null)
	check(board.info_requests.current().header == "Modal", "source modal outranks trade hover")
	board.info_requests.submit("test-modal", 2, {})
	board._clear_card_feedback()
	check(board.info_requests.current().is_empty(), "scene teardown clears trade request")
	board._return_title()
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Trade hover board: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
