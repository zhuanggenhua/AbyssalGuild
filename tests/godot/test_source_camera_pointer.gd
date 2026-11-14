extends SceneTree
const Pointer = preload("res://scripts/ui/source_camera_pointer.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func touch(index: int, down: bool, position: Vector2, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index; event.pressed = down; event.position = position; event.canceled = canceled
	return event
func move(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new(); event.index = index; event.position = position
	return event
func _init() -> void:
	var pointer = Pointer.new()
	check(not pointer.known and not pointer.primary_active, "initial state has no pointer or touch")
	check(not pointer.observe(touch(9,false,Vector2.ONE)).released and not pointer.known, "unknown release cannot manufacture a primary")
	pointer.observe(touch(3,true,Vector2(10,20)))
	check(pointer.primary_active and not pointer.orphan and pointer.position == Vector2(10,20), "first active contact supplies primary position")
	pointer.observe(move(3,Vector2(20,30)))
	check(pointer.position == Vector2(20,30), "primary motion updates shared pointer")
	pointer.observe(touch(7,true,Vector2(100,200)))
	pointer.observe(move(7,Vector2(200,300)))
	check(pointer.position == Vector2(20,30) and pointer.primary_index == 3, "secondary begin/motion cannot take over primary")
	var mouse := InputEventMouseButton.new(); mouse.button_index=MOUSE_BUTTON_LEFT; mouse.pressed=false; mouse.device=-1; mouse.position=Vector2(99,99)
	check(pointer.suppress_emulated_camera_event(mouse) and not pointer.observe(mouse).sample and pointer.position == Vector2(20,30), "early emulated mouse release does not own primary state")
	mouse.device=0
	check(not pointer.suppress_emulated_camera_event(mouse), "real mouse release is never filtered by touch count")
	pointer.observe(mouse)
	check(pointer.position == mouse.position, "physical mouse can supply shared pointer while touch is held")
	pointer.observe(move(7,Vector2(999,999)))
	check(pointer.position == Vector2(20,30), "accepted secondary touch makes frozen primary the current pointer again")
	var result: Dictionary = pointer.observe(touch(3,false,Vector2(30,40)))
	check(not result.released and pointer.primary_active and pointer.orphan, "ending first contact forms a still-pressed orphan")
	check(pointer.position == Vector2(30,40), "orphan uses primary end event's final position")
	pointer.observe(touch(5,true,Vector2(500,600)))
	pointer.observe(move(5,Vector2(600,700)))
	check(pointer.primary_index == 3 and pointer.position == Vector2(30,40), "new contact during orphan cannot start another primary")
	check(not pointer.observe(touch(7,false,Vector2(999,999))).released, "non-final secondary end does not release orphan")
	result = pointer.observe(touch(5,false,Vector2(700,800),true))
	check(result.released and not pointer.primary_active and not pointer.orphan and pointer.contacts.is_empty(), "last canceled secondary ends orphan")
	check(pointer.position == Vector2(30,40), "last secondary never changes retained primary position")
	check(not pointer.observe(touch(5,false,Vector2.ZERO,true)).released, "duplicate release has no new primary edge")
	pointer.observe(touch(11,true,Vector2(50,60)))
	check(pointer.primary_index == 11 and pointer.position == Vector2(50,60), "fresh contact after all releases starts a new primary")
	result = pointer.observe(touch(11,false,Vector2(60,70),true))
	check(result.released and pointer.position == Vector2(60,70), "single primary cancel immediately releases, retaining final position")
	pointer.observe(touch(0,true,Vector2(7,8)))
	pointer.observe(touch(1,true,Vector2(70,80)))
	result = pointer.observe(touch(0,false,Vector2(8,9),true))
	check(not result.released and pointer.orphan and pointer.position == Vector2(8,9), "canceling first of two contacts still forms an orphan")
	check(pointer.observe(touch(1,false,Vector2.ZERO)).released, "ordinary final end releases a canceled-first orphan")
	for index in 10: pointer.observe(touch(index,true,Vector2(index,index)))
	pointer.observe(touch(10,true,Vector2(100,100)))
	check(pointer.contacts.size() == 10 and not pointer.contacts.has(10), "locked source ten-contact capacity")
	check(not pointer.observe(touch(10,false,Vector2.ZERO)).released and pointer.contacts.size() == 10, "ignored overflow contact cannot release primary")
	for index in 9: check(not pointer.observe(touch(index,false,Vector2(index,index))).released, "capacity sequence releases only its last contact")
	check(pointer.observe(touch(9,false,Vector2(9,9))).released, "last admitted contact releases primary")
	var snapshot: Vector2 = pointer.position
	pointer.observe(move(88,Vector2(999,999)))
	pointer.observe(touch(88,true,Vector2(NAN,1)))
	check(pointer.position == snapshot and pointer.contacts.is_empty(), "unknown/nonfinite native input cannot mutate camera pointer")
	print("Source camera pointer: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
