extends RefCounted
## Presentation-only target tracking. Records are value snapshots, never model objects.
var states: Dictionary = {}

func reset() -> void:
	states.clear()

static func eased(t: float, source_ease: int) -> float:
	# DOTween serialized Ease values used by CardSettings. Unknown curves use
	# its default OutQuad; the imported source currently selects OutQuad (6).
	match source_ease:
		1: return t
		2: return 1.0-cos(t*PI/2.0)
		3: return sin(t*PI/2.0)
		4: return -(cos(PI*t)-1.0)/2.0
		5: return t*t
		7: return 2*t*t if t < 0.5 else 1-pow(-2*t+2,2)/2
	return 1.0-(1.0-t)*(1.0-t)

func set_target_instant(id: int, target: Vector3, force_ground: bool = false) -> void:
	if force_ground: target.y = 0
	states[id].merge({"position":target,"target":target,"mode":"instant","elapsed":0.0},true)

func set_target_animated(id: int, target: Vector3, force_ground: bool = false) -> void:
	if force_ground: target.y = 0
	states[id].merge({"start":states[id].position,"target":target,"mode":"animated","elapsed":0.0},true)

func set_target_damped(id: int, target: Vector3) -> void:
	states[id].merge({"target":target,"mode":"damped","elapsed":0.0},true)

func sync(records: Array, real_delta: float, settings: Dictionary) -> Dictionary:
	var dt: float = maxf(real_delta,0) if is_finite(real_delta) else 0.0
	var duration: float = maxf(float(settings.get("moveDuration",0.1)),0)
	var sharpness: float = maxf(float(settings.get("swaySharpness",100)),0)
	var live: Dictionary = {}
	var result: Dictionary = {}
	# Snapshot predecessor poses before damping. Head snapping happens first,
	# but each trailing card follows its predecessor's current, not final, pose.
	var preceding: Dictionary = {}
	for record in records:
		var id: int = record.id
		live[id] = true
		if not states.has(id) or states[id].identity != record.identity:
			states[id] = {"identity":record.identity,"position":record.target,"target":record.target,"mode":"instant","elapsed":0.0}
		preceding[id] = states[id].position
	for record in records:
		var id: int = record.id
		var state: Dictionary = states[id]
		var mode: String = record.get("mode","animated")
		var target: Vector3 = record.target
		if mode == "blocked":
			# Higher-priority owners supply actual rendered poses on every sync.
			set_target_instant(id,record.current)
			state.mode = "blocked"
			continue
		if state.mode == "blocked": state.position = record.current
		if mode == "instant":
			set_target_instant(id,target)
			preceding[id] = target
		elif mode == "damped":
			target = preceding.get(record.get("leader",-1),target) + record.get("step",Vector3.ZERO)
			set_target_damped(id,target)
		elif state.mode != "animated" or state.target != target:
			set_target_animated(id,target)
		if state.mode == "animated":
			state.elapsed += dt
			var t: float = 1.0 if duration <= 0 else clampf(state.elapsed/duration,0,1)
			state.position = state.start.lerp(state.target,eased(t,int(settings.get("moveEase",6))))
		elif state.mode == "damped":
			state.position = state.position.lerp(state.target,1.0-exp(-sharpness*dt))
			if state.position.distance_squared_to(state.target) < 0.0001: state.position = state.target
		result[id] = state.position
	for id in states.keys():
		if not live.has(id): states.erase(id)
	return result
