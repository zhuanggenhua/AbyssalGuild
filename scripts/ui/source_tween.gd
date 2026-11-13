extends RefCounted
## Independent scalar/vector implementation of the source-used DOTween 1.2.790 math.
## Callers own startup getter capture, lifecycle, coordinate conversion and clock.

static func out_quad(unit_time: float) -> float:
	var u := clampf(unit_time, 0.0, 1.0)
	return u * (2.0 - u)

## Source DOJump(..., numJumps=1): outer OutQuad, linear X/Z, nested
## Y OutQuad Yoyo, plus OutQuad endpoint-Y correction on nested elapsed percent.
static func jump_one(start: Vector3, finish: Vector3, power: float, duration: float, elapsed: float) -> Vector3:
	assert(duration > 0.0)
	var q := out_quad(elapsed / duration)
	var result := start.lerp(finish, q)
	var leg := 2.0 * q if q <= 0.5 else 2.0 * (1.0 - q)
	result.y = start.y + power * out_quad(leg) + (finish.y - start.y) * out_quad(q)
	return result

## Compile relative segment targets once. Elasticity affects negative excursions only.
## The captured base is deliberately NOT stored here: it belongs to tween startup.
static func punch_plan(direction: Vector3, duration: float, vibrato: int = 10, elasticity: float = 1.0) -> Dictionary:
	assert(duration > 0.0)
	var count := maxi(2, int(float(vibrato) * duration))
	var elastic := clampf(elasticity, 0.0, 1.0)
	var lengths := PackedFloat64Array()
	var targets := PackedVector3Array()
	var weight_sum := float(count * (count + 1)) / 2.0
	for i in count:
		lengths.append(duration * float(i + 1) / weight_sum)
		var coefficient := 0.0
		if i < count - 1:
			coefficient = 1.0 - float(i) / float(count)
			if i % 2 == 1:
				coefficient *= -elastic
		targets.append(direction * coefficient)
	return {"duration": duration, "lengths": lengths, "targets": targets}

## Additive punch: never multiply an existing scale by (1 + offset).
static func punch_sample(plan: Dictionary, current_base: Vector3, elapsed: float) -> Vector3:
	if elapsed <= 0.0 or elapsed >= float(plan.duration):
		return current_base
	var lengths: PackedFloat64Array = plan.lengths
	var targets: PackedVector3Array = plan.targets
	var previous := Vector3.ZERO
	var segment_start := 0.0
	for i in targets.size():
		var end_time := segment_start + lengths[i]
		if elapsed <= end_time:
			return current_base + previous.lerp(targets[i], out_quad((elapsed - segment_start) / lengths[i]))
		previous = targets[i]
		segment_start = end_time
	return current_base
