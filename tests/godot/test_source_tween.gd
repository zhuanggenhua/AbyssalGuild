extends SceneTree
const Math = preload("res://scripts/ui/source_tween.gd")
var checks := 0
var failures := 0
func near(actual: float, expected: float, label: String) -> void:
	checks += 1
	if absf(actual - expected) > 0.00001:
		push_error("%s: actual=%s expected=%s" % [label, actual, expected])
		failures += 1
func vector_near(actual: Vector3, expected: Vector3, label: String) -> void:
	near(actual.x, expected.x, label + ".x")
	near(actual.y, expected.y, label + ".y")
	near(actual.z, expected.z, label + ".z")
func _initialize() -> void:
	near(Math.out_quad(0.5), 0.75, "OutQuad midpoint")
	near(Math.out_quad(-1), 0, "clamp before")
	near(Math.out_quad(2), 1, "clamp after")
	var a := Vector3(2, 3, 4)
	var b := Vector3(6, 3, 8)
	vector_near(Math.jump_one(a,b,1,0.3,0), a, "jump start")
	vector_near(Math.jump_one(a,b,1,0.3,0.3), b, "jump finish")
	vector_near(Math.jump_one(a,b,1,0.3,0.15), Vector3(5,3.75,7), "nested midpoint")
	var apex_time := 0.3 * (1.0 - sqrt(0.5))
	vector_near(Math.jump_one(a,b,1,0.3,apex_time), Vector3(4,4,6), "early apex")
	near(Math.jump_one(a,Vector3(6,5,8),1,0.3,0.15).y, 5.625, "nested endpoint offset")
	near(Math.jump_one(Vector3.ZERO,Vector3.ZERO,1,1,0.25).y, 0.984375, "quarter")
	near(Math.jump_one(Vector3.ZERO,Vector3.ZERO,1,1,0.75).y, 0.234375, "three quarters")
	var rotation := Math.punch_plan(Vector3(0,15,0),0.25,25)
	assert(rotation.targets.size() == 6)
	var expected := [15.0,-12.5,10.0,-7.5,5.0,0.0]
	var t := 0.0
	for i in 6:
		near(rotation.lengths[i], 0.25 * float(i+1)/21.0, "rotation length")
		near(rotation.targets[i].y,expected[i],"rotation knot")
		t += rotation.lengths[i]
		near(Math.punch_sample(rotation,Vector3(0,7,0),t).y,7+expected[i],"rotation sample knot")
	near(t,0.25,"rotation total")
	near(Math.punch_sample(rotation,Vector3.ZERO,rotation.lengths[0]/2).y,11.25,"segment OutQuad")
	var scale := Math.punch_plan(Vector3(0.15,0.15,0),1.0)
	assert(scale.targets.size() == 10)
	vector_near(Math.punch_sample(scale,Vector3(2,3,4),scale.lengths[0]),Vector3(2.15,3.15,4),"additive nonunit scale")
	vector_near(Math.punch_sample(scale,Vector3(2,3,4),1.0),Vector3(2,3,4),"scale returns captured base")
	var elastic := Math.punch_plan(Vector3(10,0,0),1,4,0.5)
	near(elastic.targets[1].x,-3.75,"elastic negative")
	near(elastic.targets[2].x,5,"elastic positive unaffected")
	near(Math.punch_plan(Vector3.ONE,1,4,-3).targets[1].x,0,"elastic min")
	near(Math.punch_plan(Vector3.ONE,1,4,3).targets[1].x,-0.75,"elastic max")
	assert(Math.punch_plan(Vector3.ZERO,0.01,0).targets.size() == 2)
	vector_near(Math.punch_sample(Math.punch_plan(Vector3.ZERO,0.01,0),a,0.005),a,"zero direction")
	# Replacing an active tween preserves its current property as the new startup base.
	var interrupted := Math.punch_sample(rotation,Vector3(0,7,0),0.04)
	vector_near(Math.punch_sample(rotation,interrupted,0),interrupted,"retrigger has no reset")
	vector_near(Math.punch_sample(rotation,interrupted,0.25),interrupted,"retrigger returns new base")
	print("Source tween mathematics: %s (%d numeric checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
