extends SceneTree
## Locked Board and the actual registered equipment, pack and spawn transactions.
const Board = preload("res://scripts/ui/board.gd")
class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func run() -> void:
	var board := Board.new()
	board.feedback.free()
	board.feedback=QuietAudio.new()
	board.slot_root = "user://source-stats-events/slots"
	board.options_path = "user://source-stats-events/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "locked source catalog")
	if board.data_error != OK:
		board.free()
		finish()
		return
	board.start_new()
	var session = board.session
	check(board.running and labels(board) == expected(session.stats()), "initial HUD reads current registered snapshot")
	var wearer: int = session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-5, 3), -1, {"refuse_attach":true})
	var sword_guid: String = board.catalog.find_by_name("Sword")
	var gear: int = session.spawn_card(sword_guid, Vector2(-2, 3), -1, {"refuse_attach":true})
	var loose := labels(board)
	check(wearer >= 0 and gear >= 0 and loose == expected(session.stats()), "normal CreateCard immediately refreshes all three labels")
	var slot := int(board.catalog.fields(sword_guid).equipmentSlot)
	check(session.equipment.equip(wearer, gear), "actual card equips and leaves registered stack")
	board._refresh()
	check(labels(board) == loose and loose != expected(session.stats()), "equipment-only notification does not refresh HUD numbers")
	var berry: int = session.spawn_card(board.catalog.find_by_name("Berry"), Vector2(2, 3), -1, {"refuse_attach":true})
	var armed := labels(board)
	check(berry >= 0 and armed != loose and armed == expected(session.stats()), "next true stats event sees equipment excluded and new food included")
	check(session.equipment.unequip(wearer, slot) == gear, "actual unequip returns gear to a registered stack")
	board._refresh()
	check(labels(board) == armed and armed != expected(session.stats()), "returning a registered stack does not fabricate a stats event")
	var pack_guid: String = board.vendor_guids.front()
	var pack: int = session.spawn_card(pack_guid, Vector2(6, 3), -1, {"refuse_attach":true})
	board._refresh()
	check(pack >= 0 and labels(board) == armed and armed != expected(session.stats()), "CreatePackInstance does not refresh stale text")
	board._enter_game()
	check(labels(board) == expected(session.stats()), "new presentation lifetime samples once, including a silent mutation")
	var old = session
	board.start_new()
	var fresh := labels(board)
	check(not is_same(old, board.session) and fresh == expected(board.session.stats()), "new world gains its own snapshot")
	old.spawn_card(board.catalog.find_by_name("Berry"), Vector2(8, 3), -1, {"refuse_attach":true})
	check(labels(board) == fresh, "retired world cannot update the current HUD")
	var board_snapshot := labels(board)
	var coin: int = board.session.spawn_card(board.session.world.currency_guid, Vector2(-7, -3), -1, {"refuse_attach":true})
	check(coin >= 0 and labels(board) != board_snapshot and labels(board) == expected(board.session.stats()), "active world still updates without waiting for a frame")
	board._show_title()
	var closed := labels(board)
	board.session.spawn_card(board.session.world.currency_guid, Vector2(-7, 3), -1, {"refuse_attach":true})
	check(not board.running and labels(board) == closed, "returning to title retires the current presentation subscription")
	board.free()
	await process_frame
	finish()

func labels(board: Board) -> Array:
	return board.stat_labels.map(func(label): return label.text)

func expected(snapshot: Dictionary) -> Array:
	return [
		"%d/%d" % [snapshot.nutrition, snapshot.nutrition_need],
		str(snapshot.currency),
		"%d/%d" % [snapshot.cards_owned, snapshot.card_limit]
	]

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", name)

func finish() -> void:
	print("Source Board stats events: %d/%d" % [checks-failures, checks])
	quit(int(failures > 0))
