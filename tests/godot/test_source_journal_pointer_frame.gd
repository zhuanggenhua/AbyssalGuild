extends SceneTree
const Frame = preload("res://scripts/ui/source_journal_pointer_frame.gd")
const L := MOUSE_BUTTON_LEFT
const R := MOUSE_BUTTON_RIGHT
const M := MOUSE_BUTTON_MIDDLE
const DOWN := Vector2i(1,0)
const UP := Vector2i(0,1)
const TAP := Vector2i(1,1)
const A := 11
const B := 12
const SCROLL := 13
var f := Frame.new()
var n := 0
var bad := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	n += 1
	if not ok: bad += 1; printerr("FAIL: ",label)
func step(x: float, moved: bool, edges: Dictionary = {}, click: int = A,
		down: int = 0, drag: int = SCROLL, ignored: Array = []) -> Array[Dictionary]:
	return f.advance(Vector2(x,0), moved, edges, click, down, drag, 10.0, ignored)
func clicks(events: Array[Dictionary]) -> Array:
	return events.filter(func(e): return e.kind == "click").map(func(e): return [e.button,e.receiver])
func kinds(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e.kind)

func run() -> void:
	for order in [[L,R],[R,L],[M,R]]:
		f.reset(); step(0,false,{L:DOWN,R:DOWN,M:DOWN})
		check(clicks(step(0,false,{order[0]:UP})) == [[order[0],A]],"first released button uses shared eligibility")
		check(clicks(step(0,false,{order[1]:UP})).is_empty(),"second release does not toggle again")
	f.reset(); step(0,false,{R:DOWN,L:DOWN})
	check(clicks(step(0,false,{R:UP,L:UP})) == [[L,A]],"same processed frame uses L/R/M order")
	f.reset(); step(0,false,{L:DOWN})
	step(4,true,{},0,0,0); step(0,true)
	check(clicks(step(0,false,{L:UP})) == [[L,A]],"exit/re-entry below threshold retains eligibility")
	f.reset(); step(0,false,{L:DOWN})
	check(clicks(step(4,true,{L:UP},B)).is_empty(),"different raycast handler is not a match")
	f.reset(); step(0,false,{L:DOWN})
	step(4,true,{R:DOWN},B)
	check(clicks(step(4,false,{L:UP},B)) == [[L,B]],"click receiver shared across different rows, press state separate")
	check(clicks(step(4,false,{R:UP},B)).is_empty(),"shared click consumed across rows")
	f.reset(); step(0,false,{L:DOWN},0,0,0); step(1,true,{R:DOWN})
	check(clicks(step(1,false,{L:UP})) == [[L,A]],"outside press does not own its own click receiver")
	f.reset(); step(0,false,{L:DOWN}); step(1,true,{R:DOWN},0,0,0)
	check(clicks(step(0,true,{L:UP})).is_empty(),"press without click handler replaces shared receiver")
	f.reset(); step(0,false,{L:DOWN,R:DOWN}); step(4,true,{R:UP},B)
	check(clicks(step(4,false,{L:UP})).is_empty(),"mismatched release still consumes eligibility")
	for button in [L,R,M]:
		f.reset(); step(0,false,{button:DOWN})
		check(step(9.99,true).is_empty(),"movement under ten physical px does not start drag")
		check(kinds(step(10,true)) == ["begin_drag","drag"],"threshold starts that button's drag")
		check(kinds(step(10,false,{button:UP})) == ["end_drag"],"drag across handlers cancels click")
		f.reset(); step(0,false,{button:DOWN})
		check(clicks(step(10,true,{button:UP})) == [[button,A]],"release in the first crossed frame is processed before drag")
	f.reset(); step(0,false,{L:DOWN,R:DOWN})
	check(clicks(step(10,true,{R:UP})).is_empty(),"earlier left drag can cancel later right release in the same frame")
	f.reset(); step(0,false,{L:DOWN,R:DOWN})
	check(clicks(step(10,true,{L:UP})) == [[L,A]],"left release precedes right drag in the same frame")
	f.reset(); step(0,false,{R:DOWN}); step(10,true,{L:DOWN})
	check(clicks(step(10,false,{R:UP})) == [[R,A]],"earlier button press resets delta before later drag")
	f.reset()
	check(clicks(step(0,false,{M:TAP})) == [[M,A]],"coalesced press and release")
	f.reset(); step(0,false,{L:DOWN})
	check(clicks(step(0,false,{L:UP},A,0,SCROLL,[L])).is_empty(),"focus-driven cancellation never clicks")
	f.reset(); step(0,false,{R:DOWN},A,SCROLL,SCROLL)
	check(kinds(step(10,true)) == ["begin_drag","drag"] and
		kinds(step(10,false,{R:UP})) == ["click","end_drag"],"same press/drag receiver does not cancel shared eligibility")
	f.reset(); step(0,false,{L:DOWN}); f.reset()
	check(clicks(step(0,false,{L:UP})).is_empty(),"session reset clears capture and eligibility")
	print("Source journal pointer frames: %d/%d" % [n-bad,n])
	quit(1 if bad else 0)
