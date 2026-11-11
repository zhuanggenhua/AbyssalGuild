extends SceneTree
const Controller = preload("res://scripts/ui/equipment_display_controller.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const EquipmentPanelView = preload("res://scripts/ui/equipment_panel_view.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func card(id: int, wearer: bool = false):
	var view = CardView.new()
	root.add_child(view)
	view.configure(id,"Synthetic",2 if wearer else 5,false)
	if wearer:
		view.equipment_panel = EquipmentPanelView.new()
		view.equipment_panel.position = Vector3(0,0.1,2)
		view.add_child(view.equipment_panel)
	return view

func metadata(radius: float = 0) -> Dictionary:
	return {"size":{"x":1.8,"y":0,"z":0.4},"center":{"x":0.1,"y":0,"z":0.2},
		"interaction":{"attach_points":{"0":{"x":-2,"y":0.3,"z":0.1},"1":{"x":0.2,"y":0.4,"z":-3},"2":{"x":2.5,"y":0.5,"z":0.2}},
		"animation_radius":radius,"animation_speed":0.8}}

func collision_layer(view: Node) -> int:
	for child in view.get_children():
		if child is StaticBody3D: return child.collision_layer
	return -1

func run() -> void:
	var controller = Controller.new()
	controller.rng.seed = 123
	var views := {1:card(1,true),2:card(2,true),10:card(10),11:card(11),12:card(12)}
	views[1].position = Vector3(5,1,4)
	views[2].position = Vector3(-5,1,4)
	views[10].scale = Vector3.ONE * 0.75
	var source := {1:metadata(),2:metadata()}
	controller.sync({},views,source)
	check(not controller.is_expanded(1) and not views[1].equipment_panel.visible,"initially closed and empty")
	check(controller.records[1].collider.collision_layer == 0,"empty panel cannot intercept ray")
	check(not controller.click_panel(1),"empty panel not clickable")
	var equipped := {1:{0:10}}
	controller.sync(equipped,views,source)
	check(controller.is_expanded(1),"runtime attach opens panel")
	check(views[10].visible and collision_layer(views[10]) == 1,"expanded equipment visible and pickable")
	check(views[10].get_parent() == root,"board retains view ownership")
	check(views[10].global_position.is_equal_approx(Vector3(3,1.4,5.9)),"source attach point reflected and composed")
	check(views[10].scale.is_equal_approx(Vector3.ONE * 0.75),"attachment preserves equipment scale")
	var pick: StaticBody3D = controller.records[1].collider
	check(pick.get_meta("equipment_panel_owner") == 1 and pick.get_meta("card_id") == 1,"pick metadata routes separately from card drag")
	check(pick.get_child(0).shape.size.is_equal_approx(Vector3(1.8,0.02,0.4)),"source panel collider footprint with pick thickness")
	check(pick.get_child(0).position.is_equal_approx(Vector3(0.1,0,-0.2)),"source collider center reflection")
	check(pick.collision_layer == 1,"occupied panel pickable")
	var children: int = views[1].equipment_panel.get_child_count()
	var rng_before: int = controller.rng.state
	for iteration in 6: controller.sync(equipped,views,source)
	check(controller.rng.state == rng_before, "ordinary sync consumes no random draws")
	check(views[1].equipment_panel.get_child_count() == children,"sync does not duplicate colliders")
	check(views[10].scale.is_equal_approx(Vector3.ONE * 0.75),"scale does not accumulate")
	check(controller.click_panel(1),"toggle closes")
	check(not views[10].visible and collision_layer(views[10]) == 0,"hidden gear cannot steal picks")
	check(views[10].global_position.is_equal_approx(Vector3(3,1.4,5.9)),"hidden gear snaps to base")
	controller.sync(equipped,views,source)
	check(not controller.is_expanded(1),"ordinary sync does not reopen user-closed panel")
	controller.click_panel(1)
	controller.pointer_down(1,false)
	check(controller.is_expanded(1),"own panel press is not outside")
	controller.pointer_down(-1,true)
	check(controller.is_expanded(1),"any equipment hit is exempt from outside close")
	controller.pointer_down(-1,false)
	check(not controller.is_expanded(1),"other-card or empty-board left press closes")
	equipped[2] = {2:11}
	controller.sync(equipped,views,source)
	controller.click_panel(1)
	check(controller.is_expanded(1) and controller.is_expanded(2),"separate panels can be open")
	controller.pointer_down(2,false)
	check(not controller.is_expanded(1) and controller.is_expanded(2),"another panel press closes first only")
	controller.sync(equipped,views,source,false)
	check(not controller.is_expanded(2) and not controller.click_panel(2),"day end closes and locks toggle")
	check(controller.records[2].collider.collision_layer == 1,"day lock blocks toggle without removing source panel")
	controller.sync(equipped,views,source,true)
	check(not controller.is_expanded(2) and controller.click_panel(2),"day start unlocks without reopening")
	check(controller.hover_names(2,{11:"Synthetic accessory"}) == ["Synthetic accessory"],"hover inventory names")
	controller.click_panel(2)
	equipped[2] = {}
	controller.sync(equipped,views,source)
	check(views[11].visible and collision_layer(views[11]) == 1,"detached hidden equipment restored")
	check(not views[2].equipment_panel.visible and controller.records[2].collider.collision_layer == 0,"last detach hides compact panel and collider")

	# Class-change rebuild keeps expansion state and board-owned item alive.
	controller.click_panel(1)
	var old = views[1]
	var old_pick = controller.records[1].collider
	views[1] = card(1,true)
	views[1].position = Vector3(9,0,0)
	controller.sync(equipped,views,source)
	check(controller.is_expanded(1) and is_instance_valid(views[10]),"wearer rebuild preserves expansion and item")
	check(controller.records[1].collider != old_pick,"new panel gets new pick target")
	check(old_pick.collision_layer == 0,"retired panel pick disabled immediately")
	check(views[10].global_position.is_equal_approx(Vector3(7,0.4,1.9)),"equipment follows replaced wearer")
	old.free()

	# Scaled-time orbit is bounded and pauses exactly when delta is zero.
	source[1] = metadata(0.2)
	controller.sync(equipped,views,source)
	var before: Vector3 = views[10].global_position
	controller.advance(-1)
	controller.advance(NAN)
	controller.advance(0)
	check(views[10].global_position.is_equal_approx(before),"paused animation is stationary")
	var animation_rng: int = controller.rng.state
	controller.advance(0.25)
	check(controller.rng.state == animation_rng,"frame animation consumes no RNG")
	check(not views[10].global_position.is_equal_approx(before),"scaled-time animation moves")
	var delta: Vector3 = views[10].global_position - Vector3(7,0.4,1.9)
	check(absf(delta.x) <= 0.20001 and absf(delta.z) <= 0.20001 and is_zero_approx(delta.y),"orbit follows source radius and horizontal axes")
	controller.click_panel(1)
	check(views[10].global_position.is_equal_approx(Vector3(7,0.4,1.9)),"closing animated gear restores exact base")
	controller.advance(0.5)
	check(views[10].global_position.is_equal_approx(Vector3(7,0.4,1.9)),"hidden gear does not orbit")

	# Initial saved equipment is closed, matching startup HideCards; no invented layout.
	var restored = Controller.new()
	restored.sync(equipped,views,source)
	check(not restored.is_expanded(1),"first restored snapshot starts closed")
	restored.reset()
	var missing = Controller.new()
	missing.sync(equipped,views,{1:{}})
	check(missing.records.is_empty(),"missing attach metadata is not guessed")
	missing.reset()
	var record_count: int = controller.records.size()
	source.erase(2)
	controller.sync(equipped,views,source)
	check(controller.records.size() == record_count - 1,"removed source view record cleaned")
	controller.reset()
	check(controller.records.is_empty() and is_zero_approx(controller.scaled_time),"session reset cleans controller")
	for view in views.values(): view.free()
	print("Equipment display synthetic checks: %d passed" % checks)
	await test_private()
	quit()

func test_private() -> void:
	var assets = VisualAssets.new()
	if assets.load_manifest() != OK:
		print("Private equipment interaction: SKIP (private visual manifest unavailable)")
		return
	var appearance: Dictionary = assets.appearance(2,false)
	var panel_data: Dictionary = appearance.prefab.get("equipment_panel",{})
	if panel_data.get("interaction",{}).is_empty():
		print("Private equipment interaction: SKIP (regenerate interaction metadata)")
		return
	var wearer = CardView.new()
	root.add_child(wearer)
	wearer.configure(100,"Private wearer",2,false,assets)
	var item = CardView.new()
	root.add_child(item)
	item.configure(200,"Private equipment",5,false,assets)
	var views := {100:wearer,200:item}
	var metadata_map := {100:panel_data}
	var controller = Controller.new()
	controller.sync({},views,metadata_map)
	for slot in 3:
		controller.sync({100:{slot:200}},views,metadata_map)
		check(controller.is_expanded(100) and item.visible,"actual slot attach opens equipment")
		controller.click_panel(100)
		var point: Dictionary = panel_data.interaction.attach_points[str(slot)]
		var expected: Vector3 = wearer.equipment_panel.global_transform * Vector3(float(point.x),float(point.y),-float(point.z))
		check(item.global_position.is_equal_approx(expected),"actual serialized slot base pose")
		check(item.global_basis.is_equal_approx(Basis.IDENTITY),"actual source local rotation and unit scale")
	check(controller.records[100].config.animation_radius == float(panel_data.interaction.animation_radius),"actual animation radius")
	check(controller.records[100].config.animation_speed == float(panel_data.interaction.animation_speed),"actual animation speed")
	controller.reset()
	wearer.free()
	item.free()
	print("Private equipment interaction: PASS (3 source slot poses, source animation parameters)")
	print("Equipment display total checks: %d passed; no GPU or manual input acceptance" % checks)
