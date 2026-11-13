extends RefCounted
## Vertical, top-pivot, axis-aligned Elastic branch only. Position is Unity Y-up.
var position := 0.0
var velocity := 0.0
var previous := 0.0
var viewport_height := 0.0
var content_height := 0.0
var elasticity := 0.1
var deceleration := 0.135
var sensitivity := 1.0
var inertia := true
var dragging := false
var scrolling := false
var pointer_start := 0.0
var content_start := 0.0
func configure(fields: Dictionary) -> bool:
	if int(fields.get("m_Horizontal",0)) != 0 or int(fields.get("m_Vertical",1)) != 1 or int(fields.get("m_MovementType",1)) != 1: return false
	elasticity = float(fields.get("m_Elasticity",0.1))
	deceleration = float(fields.get("m_DecelerationRate",0.135))
	sensitivity = float(fields.get("m_ScrollSensitivity",1))
	inertia = bool(fields.get("m_Inertia",1))
	return true
func hidden_length() -> float: return maxf(0,content_height-viewport_height)
func offset(at: float) -> float:
	# AdjustBounds extends short top-pivot content down to viewport size.
	if -at > 0.001: return -at
	if hidden_length()-at < -0.001: return hidden_length()-at
	return 0
func initialize_drag() -> void: velocity = 0
func begin_drag(local_y_up: float) -> void:
	pointer_start = local_y_up
	content_start = position
	dragging = true
func drag(local_y_up: float) -> void:
	if not dragging: return
	var proposed := content_start+local_y_up-pointer_start
	var correction := offset(proposed)
	position = proposed+correction-rubber(correction,viewport_height)
func end_drag() -> void: dragging = false
func wheel(unity_scroll_delta: Vector2) -> void:
	var dy := -unity_scroll_delta.y
	if absf(unity_scroll_delta.x) > absf(dy): dy = unity_scroll_delta.x
	position += dy*sensitivity
	scrolling = true
static func rubber(stretch: float, view: float) -> float:
	if view <= 0: return 0
	return (1.0-1.0/(absf(stretch)*0.55/view+1.0))*view*signf(stretch)
static func damp(current: float, target: float, speed: float, smooth: float, dt: float) -> Vector2:
	var omega := 2.0/maxf(0.0001,smooth)
	var x := omega*dt
	var decay := 1.0/(1.0+x+0.48*x*x+0.235*x*x*x)
	var change := current-target
	var temp := (speed+omega*change)*dt
	var next_speed := (speed-omega*temp)*decay
	var result := target+(change+temp)*decay
	if (target-current > 0) == (result > target):
		result = target
		next_speed = 0 if dt != 0 else speed
	return Vector2(result,next_speed)
func step(unscaled_dt: float) -> void:
	var correction := offset(position)
	if unscaled_dt > 0:
		if not dragging and (correction != 0 or velocity != 0):
			if correction != 0:
				var result := damp(position,position+correction,velocity,elasticity*(3.0 if scrolling else 1.0),unscaled_dt)
				position = result.x
				velocity = 0 if absf(result.y)<1 else result.y
			elif inertia:
				velocity *= pow(deceleration,unscaled_dt)
				if absf(velocity)<1: velocity = 0
				position += velocity*unscaled_dt
			else: velocity = 0
		if dragging and inertia: velocity = lerpf(velocity,(position-previous)/unscaled_dt,clampf(unscaled_dt*10,0,1))
	previous = position
	scrolling = false
func normalized() -> float:
	if hidden_length() <= 0: return 1 if position < 0 else 0
	return 1.0-position/hidden_length()
func set_normalized(value: float) -> void:
	var proposed := (1-value)*hidden_length()
	if absf(position-proposed)>0.01:
		position = proposed
		velocity = 0
func bar_fraction() -> float:
	var extent := maxf(content_height,viewport_height)
	return clampf((viewport_height-absf(offset(position)))/extent,0,1) if extent>0 else 1
