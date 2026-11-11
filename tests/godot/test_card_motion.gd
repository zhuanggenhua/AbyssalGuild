extends SceneTree
const Motion = preload("res://scripts/ui/card_motion.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func record(id: int, target: Vector3, mode: String = "animated", identity: int = 1) -> Dictionary:
	return {"id":id,"identity":identity,"target":target,"mode":mode,"current":target,"leader":id-1,"step":Vector3(0,0.002,0.18)}
func _init() -> void:
	var motion = Motion.new()
	var settings := {"moveDuration":1.0,"moveEase":6,"swaySharpness":2.0}
	var records := [record(1,Vector3.ZERO)]
	motion.sync(records,0,settings)
	records[0].target = Vector3(10,0,0)
	check(motion.sync(records,0.5,settings)[1].is_equal_approx(Vector3(7.5,0,0)),"source OutQuad duration")
	check(motion.sync(records,0,settings)[1].x == 7.5,"refresh does not restart or advance")
	check(motion.sync(records,0.5,settings)[1].x == 10,"same target reaches endpoint")
	records[0].target = Vector3(20,0,0)
	motion.sync(records,0.5,settings)
	records[0].target = Vector3(30,0,0)
	check(is_equal_approx(motion.sync(records,0.5,settings)[1].x,26.875),"retarget starts from current pose")
	motion.set_target_instant(1,Vector3(1,3,2),true)
	check(motion.states[1].position == Vector3(1,0,2) and motion.states[1].mode == "instant","instant cancels tween and grounds")
	motion.set_target_animated(1,Vector3(2,8,3),true)
	check(motion.states[1].target.y == 0,"animated optional ground")
	motion.reset()
	records = [record(1,Vector3.ZERO),record(2,Vector3.ZERO),record(3,Vector3.ZERO)]
	motion.sync(records,0,settings)
	records[0].target = Vector3(10,0.1,0); records[0].mode = "instant"
	records[1].mode = "damped"; records[2].mode = "damped"
	var poses: Dictionary = motion.sync(records,0.1,settings)
	check(poses[1] == Vector3(10,0.1,0),"drag head snaps to lifted target")
	check(poses[2].is_equal_approx(Vector3(10,0.102,0.18)*(1-exp(-0.2))),"tail follows exponential unscaled delta")
	check(is_zero_approx(poses[3].x),"second tail follows preceding current pose, not endpoint")
	var before: Array = records.duplicate(true)
	motion.sync(records,0.1,settings)
	check(records == before,"adapter never mutates snapshots")
	records[1].mode = "animated"; records[1].target = Vector3.ZERO
	motion.sync(records,0,settings)
	check(motion.states[2].mode == "animated","release cancels damped mode")
	records[0].mode = "blocked"; records[0].current = Vector3(20,10,0)
	check(not motion.sync(records,0.1,settings).has(1),"priority owner not overwritten")
	records[0].mode = "animated"
	check(motion.sync(records,0,settings)[1] == records[0].current,"priority release starts at rendered pose")
	records[0].identity = 42
	check(motion.sync(records,0,settings)[1] == records[0].target,"same ID replacement clears stale motion")
	motion.sync([records[0]],0,settings)
	check(motion.states.size() == 1,"removed cards pruned")
	motion.reset(); check(motion.states.is_empty(),"travel title reset")
	check(is_equal_approx(Motion.eased(0.5,1),0.5),"serialized linear ease honored")
	print("Card motion: %d/%d passed" % [checks-failures,checks]); quit(1 if failures else 0)
