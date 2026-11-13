extends SceneTree
const Model = preload("res://scripts/ui/source_scrollrect_vertical.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr(message)
func near(a: float,b: float) -> bool: return absf(a-b)<0.00001
func _initialize() -> void:
	var m = Model.new()
	check(m.configure({}),"supported defaults")
	check(not m.configure({"m_Horizontal":1}),"horizontal rejected")
	m.viewport_height = 200
	m.content_height = 600
	check(near(m.offset(-50),50) and near(m.offset(450),-50),"top/bottom bounds signs")
	check(m.offset(-0.0005)==0,"source .001 threshold")
	m.begin_drag(0)
	m.drag(-100)
	check(near(m.position,-43.13725490196),"RubberDelta100/200")
	m.step(0.02)
	check(near(m.velocity,-431.3725490196),"drag velocity dt10 lerp")
	m.end_drag()
	var before: float = m.position
	for i in 180: m.step(1.0/60)
	check(absf(m.position)<0.001 and m.position>before,"elastic settles at top")
	m.position = 200; m.previous = 200; m.velocity = 100
	m.step(1)
	check(near(m.velocity,13.5) and near(m.position,213.5),"inertia rate per second")
	m.velocity=0.5; m.step(0.01)
	check(m.velocity==0,"velocity threshold")
	m.position=0; m.previous=0
	m.wheel(Vector2(0,1)); check(m.position==-1,"wheel upward")
	m.wheel(Vector2(3,1)); check(m.position==2,"dominant horizontal wheel maps vertical")
	m.position=-50; m.velocity=0; m.scrolling=true
	m.step(0.02)
	var slow: float=m.position
	m.position=-50; m.velocity=0; m.scrolling=false
	m.step(0.02)
	check(m.position>slow,"wheel spring smoothTime times3")
	m.position=250; m.velocity=50
	m.set_normalized(0.5)
	check(m.position==200 and m.velocity==0,"scrollbar clears velocity")
	check(near(m.bar_fraction(),1.0/3),"bar visible fraction")
	m.position=-50
	check(near(m.bar_fraction(),0.25),"bar compresses overscroll")
	m.content_height=100; m.position=0
	check(m.offset(25)==-25 and m.normalized()==0,"short content top pivot bounds")
	m.position=-25
	check(m.normalized()==1,"short overscroll normalized source direction")
	m.velocity=42; m.previous=12; m.dragging=true
	m.step(0)
	check(m.velocity==42,"zero delta no divide")
	print("Source ScrollRect: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
