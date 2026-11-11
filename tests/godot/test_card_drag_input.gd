extends SceneTree
const Drag = preload("res://scripts/ui/card_drag_input.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void:
	var settings := {"clickThreshold": 0.25}
	check(Drag.is_click(Vector3(3,0,7),Vector2(3,7),settings),"stationary release clicks")
	check(Drag.is_click(Vector3(3,0,7),Vector2(3.125,7),settings),"subthreshold final world displacement clicks")
	check(not Drag.is_click(Vector3(3,0,7),Vector2(3.25,7),settings),"threshold equality is drag")
	check(not Drag.is_click(Vector3(3,0,7),Vector2(3.3,7),settings),"over-threshold world displacement is drag")
	check(not Drag.is_click(Vector3(3,0.3,7),Vector2(3,7),settings),"source initial stack height contributes after release flatten")
	check(Drag.is_click(Vector3(3,0.1,7),Vector2(3,7),settings),"small source stack height can click")
	check(not Drag.is_click(Vector3.ZERO,Vector2.ZERO,{"clickThreshold":0}),"zero threshold never clicks")
	check(not Drag.is_click(Vector3(INF,0,0),Vector2.ZERO,settings),"invalid origin rejected")
	check(not Drag.is_click(Vector3.ZERO,Vector2(NAN,0),settings),"invalid destination rejected")
	var catalog = Catalog.new()
	catalog.data = {"scenes":[{"name":"Main","documents":[{"script_class":"CardManager","fields":{"cardSettings":{"guid":"main"}}}]},{"name":"Island","documents":[{"script_class":"CardManager","fields":{"cardSettings":{"guid":"island"}}}]}]}
	catalog.definitions = {"base":{"script_class":"CardSettings","fields":{"clickThreshold":0.1}},"main":{"fields":{"clickThreshold":0.2}},"island":{"fields":{"clickThreshold":0.3}}}
	catalog.data["settings"] = [catalog.definitions.base]
	check(Drag.source_settings(catalog,"Main").clickThreshold == 0.2,"active Main settings chosen")
	check(Drag.source_settings(catalog,"Island").clickThreshold == 0.3,"active Island settings chosen")
	check(Drag.source_settings(catalog,"Missing").clickThreshold == 0.1,"sceneless fixture falls back explicitly")
	print("Card drag input: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
