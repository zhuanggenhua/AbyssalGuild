extends RefCounted
## Pure CPU presentation state. No scene nodes, model access, audio or global RNG.
var elapsed: float = 0.0
var scaled_elapsed: float = 0.0
var _configuration: Dictionary = {}
var _births: Array[Dictionary] = []
var _expired: bool = true
var _rng := RandomNumberGenerator.new()

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _vector(value: Variant, names: Array) -> bool:
	if not value is Dictionary: return false
	for key in names:
		if not _number(value.get(key)): return false
	return true

static func _keys_valid(keys: Variant, weighted: bool) -> bool:
	if not keys is Array or keys.size() < 2: return false
	var previous: float = -1.0
	for key in keys:
		if not key is Dictionary or not _number(key.get("time")) or not _number(key.get("value")): return false
		var time: float = float(key.time)
		if time < 0 or time > 1 or time <= previous: return false
		previous = time
		if weighted:
			for name in ["inSlope","outSlope","inWeight","outWeight","weightedMode"]:
				if not _number(key.get(name)): return false
			if float(key.weightedMode) not in [0.0,1.0,2.0,3.0]: return false
			if float(key.inWeight) < 0 or float(key.inWeight) > 1 or float(key.outWeight) < 0 or float(key.outWeight) > 1: return false
		elif float(key.value) < 0 or float(key.value) > 1: return false
	return float(keys[0].time) == 0.0 and float(keys[-1].time) == 1.0

static func is_supported(record: Dictionary) -> bool:
	if not bool(record.get("supported", false)) or not record.get("unsupported", []).is_empty(): return false
	for field in ["duration", "cleanup_scaled_seconds", "burst_count"]:
		if not _number(record.get(field)) or float(record[field]) <= 0: return false
	if float(record.burst_count) != float(int(record.burst_count)) or int(record.burst_count) > 1000: return false
	for key in ["lifetime","speed","size"]:
		var range_value: Dictionary = record.get("ranges",{}).get(key,{})
		if not _number(range_value.get("min")) or not _number(range_value.get("max")): return false
		if float(range_value.min) < 0 or float(range_value.max) < float(range_value.min): return false
		if key != "speed" and float(range_value.min) <= 0: return false
	var shape: Dictionary = record.get("shape",{})
	if not _number(shape.get("radius")) or float(shape.radius) <= 0: return false
	for key in ["position","rotation_degrees"]:
		if not _vector(shape.get(key),["x","y","z"]): return false
	if not _vector(record.get("start_color"),["r","g","b","a"]): return false
	return _keys_valid(record.get("size_keys"),true) and _keys_valid(record.get("opacity_keys"),false)

func configure(record: Dictionary, presentation_seed: int) -> bool:
	reset()
	if not is_supported(record): return false
	_configuration = record.duplicate(true)
	_rng.seed = presentation_seed
	var shape: Dictionary = record.shape
	var rotation: Dictionary = shape.rotation_degrees
	# Unity Euler applies Z then X then Y. Reflect the resulting source point's Z.
	var basis := Basis(Vector3.UP,deg_to_rad(float(rotation.y))) * Basis(Vector3.RIGHT,deg_to_rad(float(rotation.x))) * Basis(Vector3.BACK,deg_to_rad(float(rotation.z)))
	var center := Vector3(float(shape.position.x),float(shape.position.y),float(shape.position.z))
	for index in int(record.burst_count):
		var angle: float = _rng.randf() * TAU
		var radius: float = sqrt(_rng.randf()) * float(shape.radius)
		var source_position: Vector3 = center + basis * Vector3(cos(angle)*radius,sin(angle)*radius,0)
		var position := Vector3(source_position.x,source_position.y,-source_position.z)
		# Documented native interpretation of SpherizeDirection=1: outwards from
		# the system Transform origin, including the shape's offset, not a cone.
		var speed: float = _range_value(record.ranges.speed)
		_births.append({"index":index,"position":position,"velocity":position.normalized()*speed,
			"lifetime":_range_value(record.ranges.lifetime),"size":_range_value(record.ranges.size)})
	_expired = false
	return true

func _range_value(value: Dictionary) -> float:
	return _rng.randf_range(float(value.min),float(value.max))

func advance(unscaled_delta: float, scaled_delta: float) -> bool:
	if _expired or not is_finite(unscaled_delta) or not is_finite(scaled_delta) or unscaled_delta < 0 or scaled_delta < 0:
		return false
	elapsed += unscaled_delta
	scaled_elapsed += scaled_delta
	_expired = scaled_elapsed >= float(_configuration.cleanup_scaled_seconds)
	return true

func birth_states() -> Array[Dictionary]:
	return _births.duplicate(true)

func sample_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _expired: return result
	var tint: Dictionary = _configuration.start_color
	var color := Color(float(tint.r),float(tint.g),float(tint.b),float(tint.a))
	for birth in _births:
		if elapsed >= float(birth.lifetime): continue
		var age: float = elapsed / float(birth.lifetime)
		var opacity: float = linear_value(_configuration.opacity_keys,age)
		result.append({"index":birth.index,"age":elapsed,"normalized_age":age,
			"position":birth.position + birth.velocity * elapsed,
			"size":float(birth.size) * weighted_value(_configuration.size_keys,age),
			"color":Color(color,color.a*opacity)})
	return result

func is_expired() -> bool:
	return _expired

func reset() -> void:
	_configuration.clear()
	_births.clear()
	elapsed = 0.0
	scaled_elapsed = 0.0
	_expired = true

static func _bezier(a: float, b: float, c: float, d: float, u: float) -> float:
	var v: float = 1.0-u
	return v*v*v*a + 3.0*v*v*u*b + 3.0*v*u*u*c + u*u*u*d

static func weighted_value(keys: Array, time: float) -> float:
	if keys.is_empty() or not is_finite(time): return 0.0
	if time <= float(keys[0].time): return float(keys[0].value)
	if time >= float(keys[-1].time): return float(keys[-1].value)
	for index in range(keys.size()-1):
		var left: Dictionary = keys[index]
		var right: Dictionary = keys[index+1]
		if time > float(right.time): continue
		var dt: float = float(right.time)-float(left.time)
		var outgoing: float = float(left.outWeight) if int(left.weightedMode)&2 else 1.0/3.0
		var incoming: float = float(right.inWeight) if int(right.weightedMode)&1 else 1.0/3.0
		var x1: float = float(left.time)+dt*outgoing
		var x2: float = float(right.time)-dt*incoming
		var y1: float = float(left.value)+float(left.outSlope)*dt*outgoing
		var y2: float = float(right.value)-float(right.inSlope)*dt*incoming
		# Weighted tangents reparameterize time. Do not use normalized time as u.
		var lower: float = 0.0
		var upper: float = 1.0
		for iteration in 40:
			var middle: float = (lower+upper)*0.5
			if _bezier(float(left.time),x1,x2,float(right.time),middle) < time: lower=middle
			else: upper=middle
		return _bezier(float(left.value),y1,y2,float(right.value),(lower+upper)*0.5)
	return 0.0

static func linear_value(keys: Array, time: float) -> float:
	if keys.is_empty() or not is_finite(time): return 0.0
	if time <= float(keys[0].time): return float(keys[0].value)
	for index in range(keys.size()-1):
		var left: Dictionary = keys[index]
		var right: Dictionary = keys[index+1]
		if time <= float(right.time):
			return lerpf(float(left.value),float(right.value),(time-float(left.time))/(float(right.time)-float(left.time)))
	return float(keys[-1].value)
