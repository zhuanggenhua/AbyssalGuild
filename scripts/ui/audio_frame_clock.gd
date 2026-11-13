extends RefCounted
## Unity Time.unscaledTime is constant for every request in one render frame.
## Sample the host monotonic clock once, at the pre-process hook (or first audio request if input precedes it) of an
## engine process frame. This maps same-frame admission, not Unity's exact frame-start
## sampling instant or its single-precision accumulation/FixedUpdate clock.
var frame_provider: Callable = func(): return Engine.get_process_frames()
var time_provider: Callable = func(): return Time.get_ticks_usec() / 1000000.0
var sampled_frame: int = -1
var sampled_time := 0.0
func now() -> float:
	var frame: int = frame_provider.call()
	if frame != sampled_frame:
		sampled_time = float(time_provider.call())
		sampled_frame = frame
	return sampled_time
