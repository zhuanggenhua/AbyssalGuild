extends SceneTree
const Geometry = preload("res://scripts/model/combat_merge_geometry.gd")
const Layout = preload("res://scripts/model/combat_layout.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void:
	var raw := [{"id":1,"position":Vector2(20,20),"size":Vector2.ONE,"faction":1},
		{"id":2,"position":Vector2(20,20),"size":Vector2.ONE,"faction":2}]
	var seen: Array = []
	var live := Geometry.current_ground_records(raw,func(id):
		seen.append(id)
		return Vector3(0,0,0))
	var cfg := {"ok":true,"axis_x":Vector2.RIGHT,"axis_y":Vector2.DOWN,"scale":Vector2.ONE,"pivot":Vector2(0.5,0.5)}
	var active := {7:Layout.initialize([live[0]],[live[1]],cfg,Rect2(-100,-100,200,200),0)}
	check(seen == [1,2],"sampling preserves registration order once each")
	check(Geometry.before_start([raw[0]],[raw[1]],active).is_empty(),"queued targets do not overlap")
	check(Geometry.before_start([live[0]],[live[1]],active) == [7],"current ground transforms select overlap")
	check(raw[0].position == Vector2(20,20) and raw[1].position == Vector2(20,20),"sampling does not mutate targets")
	var rejected := [null,Vector2.ZERO,Vector3(NAN,0,0),Vector3(0,0.1,0)]
	for sample in rejected:
		var result := Geometry.current_ground_records(raw,func(_id):return sample)
		check(result == raw,"invalid or elevated observation retains existing settled adapter")
	check(Geometry.current_ground_records(raw,Callable()) == raw,"absent observer retains model fallback")
	var far := Geometry.current_ground_records(live,func(_id):return Vector3(40,0,40))
	check(Geometry.before_start([far[0]],[far[1]],active).is_empty(),"live far excludes stale-near merge")
	print("Combat merge pose: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
