extends SceneTree
const Receivers = preload("res://scripts/ui/source_touch_card_receivers.gd")
var failed := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(expect: bool, label: String) -> void:
	checks += 1
	if not expect:
		push_error(label)
		failed += 1

func run() -> void:
	var ledger := Receivers.new()
	var first := Node3D.new()
	var second := Node3D.new()
	check(ledger.capture(3,first) and ledger.capture(8,second), "independent original Press receivers")
	check(not ledger.capture(3,second), "do not steal an active contact's receiver")
	check(ledger.release(4)==null and ledger.owns(3) and ledger.owns(8), "unrelated up keeps both grants intact")
	check(ledger.release(3)==first and not ledger.owns(3) and ledger.owns(8), "first up routes only to first card")
	check(ledger.release(8)==second and ledger.release(8)==null, "later receiver gets exactly one up")
	check(ledger.capture(3,first) and ledger.capture(8,first), "same card may receive two independently routed presses")
	check(ledger.release(8)==first and ledger.release(3)==first, "CardController, not routing, decides whether either up acts")
	check(ledger.capture(0,first), "contact index reuse after release")
	first.free()
	check(ledger.owns(0) and ledger.release(0)==null and not ledger.owns(0), "destroyed view is not retargeted or retained")
	check(ledger.capture(0,second), "fresh view may use recycled index after cleanup")
	ledger.reset()
	check(not ledger.owns(0) and ledger.release(0)==null, "scene boundary never releases old receivers into new scene")
	check(not ledger.capture(-1,second) and not ledger.capture(1,null), "invalid device/receiver rejected")
	second.free()
	print("Touch card receiver ledger: %d/%d (routing unit only)" % [checks-failed,checks])
	quit(failed)
