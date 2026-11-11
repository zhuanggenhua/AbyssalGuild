extends SceneTree
const Fade = preload("res://scripts/ui/scene_transition.gd")
var checks := 0
var failures := 0
var calls := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var fade = Fade.new()
	check(not fade.begin(Callable()), "missing commit rejected")
	check(fade.begin(func(): calls += 1), "begin")
	check(not fade.begin(func(): calls += 100), "repeated input cannot replace transaction")
	fade.advance(0.25)
	check(is_equal_approx(fade.alpha, 0.25) and calls == 0 and fade.blocks_input(), "linear fade-out owns input/pause, no early commit")
	fade.advance(-1)
	fade.advance(NAN)
	check(is_equal_approx(fade.alpha, 0.25), "invalid clocks ignored")
	fade.advance(0.75)
	check(calls == 1 and fade.alpha == 1 and not fade.blocks_input(), "black commit exactly once then releases external pause and raycasts")
	check(not fade.begin(func(): calls += 100), "scene requests blocked during fade-in")
	fade.advance(0.5)
	check(is_equal_approx(fade.alpha, 0.5), "linear fade-in")
	fade.advance(0.5)
	check(not fade.active() and calls == 1 and fade.alpha == 0, "finish")
	fade.begin(func(): calls += 1)
	fade.cancel()
	fade.advance(10)
	check(calls == 1 and not fade.active(), "interruption invalidates queued callback")
	fade.begin(func():
		fade.cancel()
		fade.begin(func(): calls += 10))
	fade.advance(1)
	check(fade.phase == "out" and fade.alpha == 0, "stale completion cannot alter reentrant replacement")
	fade.advance(1)
	check(calls == 11, "replacement callback runs once")
	fade.advance(100)
	fade.advance(100)
	check(calls == 11 and not fade.active(), "large deltas never replay commit")
	print("Scene transition: %d / %d" % [checks-failures, checks])
	quit(1 if failures else 0)
