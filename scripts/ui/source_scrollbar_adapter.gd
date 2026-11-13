extends Control
## Same-version Scrollbar vertical/Automatic/continuous/flat Image branch.
signal value_changed(value: float)
const Geometry = preload("res://scripts/ui/source_control_metadata.gd")
var tint = preload("res://scripts/ui/selectable_tint.gd").new()
var source: Dictionary
var value := 0.0
var fraction := 1.0
var handle := ColorRect.new()
var allowed: Callable
var pointer_down := false
var dragging := false
var press_point := Vector2.ZERO
var drag_offset := 0.0
var hovered := false
var last_tick := 0
var held_keys: Dictionary = {}
var move_direction := 0
var move_count := 0
var last_move := 0.0
var repeat_delay := 0.5
var repeat_rate := 0.1
func _init() -> void: add_child(handle)
static func metadata(documents: Array, reference: Dictionary) -> Dictionary:
	var c := Geometry.fields(documents,reference)
	if int(c.get("m_Direction",-1))!=2 or int(c.get("m_NumberOfSteps",-1))!=0 or int(c.get("m_Transition",-1))!=1 or int(c.get("m_Navigation",{}).get("m_Mode",-1))!=3: return {}
	var h := Geometry.fields(documents,c.get("m_HandleRect",{}))
	var parent := Geometry.fields(documents,h.get("m_Father",{}))
	var image := Geometry.fields(documents,c.get("m_TargetGraphic",{}))
	if h.is_empty() or parent.is_empty() or image.get("m_GameObject")!=h.get("m_GameObject") or str(image.get("m_Sprite",{}).get("fileID",""))!="0": return {}
	return {"control":c,"handle":h,"container":parent,"image":image}
func configure(record: Dictionary, guard: Callable) -> bool:
	if record.is_empty(): return false
	source=record
	allowed=guard
	value=float(source.control.m_Value)
	fraction=clampf(float(source.control.m_Size),0,1)
	tint.configure(source.control.m_Colors)
	handle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_ALL
	mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(refresh)
	mouse_entered.connect(func(): hovered=true; _state())
	mouse_exited.connect(func(): hovered=false; _state())
	focus_entered.connect(_state)
	focus_exited.connect(_state)
	repeat_delay=float(source.get("repeat_delay",0.5))
	repeat_rate=float(source.get("repeat_rate",0.1))
	last_tick=Time.get_ticks_usec()
	refresh()
	return true
func admitted() -> bool:
	return is_visible_in_tree() and bool(source.get("control",{}).get("m_Interactable",0)) and (not allowed.is_valid() or allowed.call())
func _has_point(point: Vector2) -> bool:
	# Only Handle has a raycast Graphic. Root/SlidingArea have no Image.
	return Rect2(handle.position,handle.size).has_point(point)
func container_rect() -> Rect2: return Geometry.rectangle(source.container,size)
func refresh() -> void:
	if source.is_empty(): return
	var r := container_rect()
	var driven: Dictionary=source.handle.duplicate(true)
	var movement := clampf(value,0,1)*(1-fraction)
	driven.m_AnchorMin={"x":0,"y":movement}
	driven.m_AnchorMax={"x":1,"y":movement+fraction}
	var result := Geometry.rectangle(driven,r.size)
	handle.position=r.position+result.position
	handle.size=result.size
	handle.color=Geometry.color(source.image.m_Color)*tint.current
func sync(normalized_value: float, visible_fraction: float) -> void:
	fraction=clampf(visible_fraction,0,1)
	# Source Set accepts unbounded ScrollRect values; UpdateVisuals alone clamps.
	value=normalized_value
	refresh()
func set_source_value(next: float) -> void:
	if value==next: return
	value=next
	refresh()
	value_changed.emit(value)
func update_drag(point: Vector2) -> void:
	var r:=container_rect()
	var remaining:=r.size.y*(1-fraction)
	if remaining<=0: return
	# Unity bottom-origin cursor; subtract offset and driven (non-sizeDelta) half height.
	var cursor:=r.end.y-point.y
	var corner:=cursor-drag_offset-r.size.y*fraction*0.5
	set_source_value(clampf(corner/remaining,0,1))
func press(point: Vector2) -> void:
	if not admitted(): return
	grab_focus()
	pointer_down=true
	dragging=false
	press_point=point
	repeat_press()
	_state()
func repeat_press() -> void:
	if not admitted(): return
	if pointer_down and not dragging and not Rect2(handle.position,handle.size).has_point(press_point): update_drag(press_point)
func move_pointer(point: Vector2) -> void:
	if not pointer_down or not admitted(): return
	if not dragging:
		dragging=true
		drag_offset=0
		if Rect2(handle.position,handle.size).has_point(press_point): drag_offset=(handle.position.y+handle.size.y*0.5)-press_point.y
	update_drag(point)
func release() -> void:
	pointer_down=false
	dragging=false
	_state()
func move_vertical(up: bool) -> void:
	if admitted(): set_source_value(clampf(value+(0.1 if up else -0.1),0,1))
func advance_navigation(direction: int, now: float) -> void:
	if direction!=move_direction: move_count=0
	move_direction=direction
	if direction==0:
		move_count=0
		return
	var wait:=repeat_rate if move_count>1 else repeat_delay
	if move_count==0 or now>last_move+wait:
		move_vertical(direction>0)
		move_count+=1
		last_move=now
func _state() -> void:
	if source.is_empty(): return
	tint.set_state("Disabled" if not admitted() else ("Pressed" if pointer_down else ("Selected" if has_focus() else ("Highlighted" if hovered else "Normal"))))
func _process(_dt: float) -> void:
	var now:=Time.get_ticks_usec()
	var elapsed: float=(now-last_tick)/1000000.0
	last_tick=now
	if not admitted(): pointer_down=false; dragging=false
	if not has_focus() or not admitted(): held_keys.clear()
	var up:=held_keys.has(KEY_UP) or held_keys.has(KEY_W)
	var down:=held_keys.has(KEY_DOWN) or held_keys.has(KEY_S)
	advance_navigation(int(up)-int(down),now/1000000.0)
	_state()
	tint.advance(elapsed)
	refresh()
	# Unity repeats after end-of-frame at the initial press point, not moving pointer.
	if pointer_down and not dragging: call_deferred("repeat_press")
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: press(event.position)
		else: release()
	elif event is InputEventMouseMotion and pointer_down:
		move_pointer(event.position)
	elif event is InputEventKey and event.keycode in [KEY_UP,KEY_DOWN,KEY_W,KEY_S]:
		if event.pressed: held_keys[event.keycode]=true
		else: held_keys.erase(event.keycode)
		accept_event()
	# PageUp/Down intentionally has no value mapping in source Scrollbar.
