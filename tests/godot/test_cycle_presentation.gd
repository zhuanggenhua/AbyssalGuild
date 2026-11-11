extends SceneTree
const Presentation = preload("res://scripts/ui/cycle_presentation.gd")
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	assert(value,label)
func _init() -> void:
	var state := {"stage":"lift","card_id":1,"from_position":Vector3(2,0.1,3),"to_position":Vector3(2,1,3),"duration":0.1,"elapsed":0.05}
	var original: Dictionary = state.duplicate(true)
	check(Presentation.sample(state).is_equal_approx(Vector3(2,0.775,3)), "lift uses model elapsed with explicit source default easing")
	check(state == original, "presentation never changes snapshot timing")
	var view := Node3D.new()
	Presentation.apply(state,{1:view})
	check(view.position.is_equal_approx(Vector3(2,0.775,-3)), "source pose reflects Z once")
	state.stage = "travel"; state.from_position = Vector3(2,1,3); state.to_position = Vector3(6,1,-1); state.duration = 0.2; state.elapsed = 0.1
	check(Presentation.sample(state).is_equal_approx(Vector3(5,1,0)), "travel restores from saved midpoint without local clock")
	state.elapsed = 10
	check(Presentation.sample(state) == state.to_position, "completed phase clamps to endpoint")
	state.duration = 0
	check(Presentation.sample(state) == state.to_position, "zero duration has safe endpoint")
	check(Presentation.sample({}) == null, "no phase leaves normal board pose alone")
	Presentation.apply(state,{})
	check(Presentation.sample({"from_position":Vector3.ZERO}) == null, "incomplete state cannot fabricate a pose")
	view.free()
	print("Cycle presentation checks: %d passed" % checks)
	quit()
