extends SceneTree
const Queue = preload("res://scripts/ui/info_request_queue.gd")
var failures := 0
var checks := 0
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void:
	var queue = Queue.new()
	var card := {"header":"Card","body":"unchanged"}
	queue.submit("card",0,card)
	queue.submit("journal",0,{"header":"Quest"})
	check(queue.current().header == "Quest","latest equal priority")
	var previous: int = queue.serial
	queue.submit("card",0,card)
	check(queue.serial == previous+1 and queue.current().header == "Card","identical renewed request still becomes newest")
	card.body = "external mutation"
	check(queue.current().body == "unchanged","submission owns detached information")
	queue.submit("modal",2,{"header":"Modal"})
	queue.submit("card",0,{"header":"Card","body":"still newer"})
	check(queue.current().header == "Modal","serial never overrules priority")
	queue.submit("modal",2,{})
	check(queue.current().body == "still newer","clearing high priority reveals newest underlying request")
	queue.submit("card",0,{})
	check(queue.current().header == "Quest","clear only removes its owner")
	print("Info request order: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL",checks])
	quit(0 if failures == 0 else 1)
