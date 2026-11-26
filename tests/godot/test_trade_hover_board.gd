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
	var buyer_serial: int = board.info_requests.requests.get("trade",{}).get("serial",-1)
	board.info_requests.submit("test-equal", 0, {"header":"Later Hover"})
	board._sync_card_hover(null)
	check(board.info_requests.current().get("header") == "Later Hover"
		and board.info_requests.requests.get("trade",{}).get("serial",-1) == buyer_serial,
		"stationary source buyer does not overtake a later equally ranked request")
	board.info_requests.submit("test-equal", 0, {})
	board.trade_views[0].hide()
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty(), "disable clears owned hover")
	board.trade_views[0].show()
	board.hit.trade_zone_index = 1
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty() and board.info_requests.requests.has("trade")
		and board.trade_views[1].pick_body.collision_layer != 0, "hittable inactive vendor publishes a blank tuple")
	var inactive_serial: int = board.info_requests.requests.get("trade",{}).get("serial",-1)
	for id in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[id] = true
	board._refresh()
	board._sync_card_hover(null)
	check(board.trade_views[1].get_info().get("header") == "Pack Vendor"
		and board.info_requests.current().is_empty()
		and board.info_requests.requests.get("trade",{}).get("serial",-1) == inactive_serial,
		"same collider activation updates vendor state but does not republish hover")
	board.hit.trade_zone_index = -1
	board._sync_card_hover(null)
	board.hit.trade_zone_index = 1
	board._sync_card_hover(null)
	check(board.info_requests.current().get("header") == "Pack Vendor", "reentry samples active vendor info")
	var active_serial: int = board.info_requests.requests.get("trade",{}).get("serial",-1)
	board.trade_views[1].update_tracker("5/7")
	board._sync_card_hover(null)
	check(board.info_requests.requests.get("trade",{}).get("serial",-1) == active_serial,
		"tracker updates do not republish source hover")
	board.hit.trade_zone_index = -1
	board._sync_card_hover(null)
	check(board.info_requests.current().is_empty(), "pointer exit clears hover")
	board.hit.trade_zone_index = 0
	board._sync_card_hover(null)
	board.info_requests.submit("test-modal", 2, {"header":"Modal"})
	board._sync_card_hover(null)
	check(board.info_requests.current().header == "Modal", "source modal outranks trade hover")
	board.info_requests.submit("test-modal", 2, {})
	var previous: Node3D = board.trade_views[0]
	var previous_serial: int = board.info_requests.requests["trade"].serial
	board.trade_views.erase(0)
	previous.hide()
	previous.queue_free()
	board._sync_trade_zones()
	board._sync_card_hover(null)
	check(board.trade_views[0] != previous and board.info_requests.current().get("header") == "Card Buyer"
		and board.info_requests.requests["trade"].serial > previous_serial, "same index with replacement collider enters afresh")
	board._clear_card_feedback()
	check(board.info_requests.current().is_empty(), "scene teardown clears trade request")
	board._return_title()
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Trade hover board: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
