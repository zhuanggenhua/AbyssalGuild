extends SceneTree
const Presenter = preload("res://scripts/ui/vendor_unlock_presenter.gd")
const CameraMotion = preload("res://scripts/ui/camera_motion.gd")
const View = preload("res://scripts/ui/trade_zone_view.gd")
var checks: int = 0
var failures: int = 0

class Tracker extends RefCounted:
	signal quest_completed(instance: Dictionary)
class Session extends RefCounted:
	var quest_tracker = Tracker.new()
	var phase: String = "playing"
	var paused: bool = false
	var speed: float = 2.0
class Board extends Node3D:
	var session = Session.new()
	var hud = Control.new()
	var running: bool = true
	var trade_zones: Array = []
	var trade_views: Dictionary = {}
	var camera_motion = CameraMotion.new()
	var camera_position := Vector3(0, 10, 2)
	var drag_grant: int = 44
	var syncs: int = 0
	var refreshes: int = 0
	var focus_calls: Array = []
	var notice = Label.new()
	func _init() -> void:
		add_child(hud)
		hud.add_child(notice)
		camera_motion.configure(camera_position)
	func _sync_trade_zones() -> void:
		syncs += 1
	func _focus_camera_position(position: Vector3, duration: float) -> void:
		focus_calls.append({"position": position, "duration": duration})
		camera_motion.move_to(camera_position, position, Vector3(0, -1, 0), duration)
	func _refresh() -> void:
		refreshes += 1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func zone(index: int, active: bool) -> Dictionary:
	return {"kind": "vendor", "index": index, "pack_guid": "pack-%d" % index, "active": active, "title": "Test %d" % index, "center": Vector3(index, 0, 4)}

func _init() -> void: call_deferred("run")
func run() -> void:
	var board := Board.new()
	root.add_child(board)
	var presenter := Presenter.new()
	board.add_child(presenter)
	for index in [1, 2]:
		board.trade_views[index] = View.new()
		board.add_child(board.trade_views[index])
	board.trade_zones = [zone(1, true), zone(2, false)]
	presenter.bind(board)
	check(not presenter.is_active() and not presenter.info_panel.visible and board.focus_calls.is_empty(), "Bind is silent for initially eligible vendors")
	board.notice.text = "SAVE FAILED: retain live game"
	board.trade_zones[1].active = true
	board.session.quest_tracker.quest_completed.emit({"id": "test"})
	check(board.syncs == 1 and presenter.is_active() and board.trade_views[2].highlighted, "Real quest callback refreshes activation then highlights new vendor")
	check(board.focus_calls == [{"position": Vector3(2, 0, 4), "duration": 0.5}], "Focus uses exact source position and default duration")
	check(presenter.info_label.text == "Pack Unlocked\nYou can buy Test 2 card pack here." and presenter.info_panel.visible, "Sequence-priority notice remains visible")
	check(board.notice.text == "SAVE FAILED: retain live game" and board.drag_grant == 44, "Reveal neither overwrites save failure nor revokes held drag")
	board.session.phase = "feeding"
	presenter.advance(0.25)
	check(not presenter.info_panel.visible and presenter.is_active(), "Cycle modal suppresses reveal info without cancelling its real clock")
	board.session.phase = "playing"
	presenter.advance(0.25)
	check(presenter.info_panel.visible and presenter.sequence.stage == "hold", "Reveal info returns after modal and full focus interval")
	presenter.advance(2.0)
	check(not presenter.is_active() and not board.trade_views[2].highlighted and not presenter.info_panel.visible, "Completion releases only own highlight and info")
	check(board.session.speed == 2 and not board.session.paused and board.notice.text.begins_with("SAVE FAILED"), "Selected pace and important notice remain untouched")
	var old_tracker = board.session.quest_tracker
	board.session = Session.new()
	board.trade_zones = [zone(1, false)]
	presenter.bind(board)
	board.trade_zones[0].active = true
	old_tracker.quest_completed.emit({})
	check(not presenter.is_active(), "Rebind disconnects old session tracker")
	board.session.quest_tracker.quest_completed.emit({})
	check(presenter.is_active(), "New session tracker owns fresh reveal baseline")
	presenter.cancel()
	check(not presenter.is_active() and board.camera_motion.focus.is_empty() and not board.trade_views[1].highlighted, "Cancellation stops own active focus and highlight")
	presenter.cancel()
	board.session.quest_tracker.quest_completed.emit({})
	check(not presenter.is_active(), "Cancelled/disconnected tracker cannot restart reveal")
	board.trade_zones[0].active = false
	presenter.bind(board)
	board.trade_zones[0].active = true
	board.session.quest_tracker.quest_completed.emit({})
	board.camera_motion.move_to(board.camera_position, Vector3(9, 0, 9), Vector3(0, -1, 0), 1.0)
	var cycle_focus: Dictionary = board.camera_motion.focus.duplicate(true)
	presenter.cancel()
	check(board.camera_motion.focus == cycle_focus, "Cancel does not erase a newer cycle's camera focus")
	board.trade_zones[0].active = false
	presenter.bind(board)
	board.trade_zones[0].active = true
	board.session.quest_tracker.quest_completed.emit({})
	var refreshes_before: int = board.refreshes
	board.running = false
	await process_frame
	check(board.refreshes == refreshes_before, "Deferred reveal refresh cannot redraw a board after title transition")
	presenter.queue_free()
	await process_frame
	check(not board.trade_views[1].highlighted and board.camera_motion.focus.is_empty(), "Tree teardown cleans own outstanding focus and highlight")
	board.queue_free()
	await process_frame
	print("Vendor unlock presenter: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
