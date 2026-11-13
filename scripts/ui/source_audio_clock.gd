extends RefCounted
## AudioManager persists; TimeManager does not. Time.timeScale itself is global.
## Cold Title starts at 1. Returning via TravelSequence leaves it at 0 because
## Title has no TimeManager to execute SetExternalPause(false).
var retained_scale := 1.0
var advances := 0
func sample(real_delta: float, has_time_manager: bool, pace: int, external_pause: bool) -> float:
	advances += 1
	if has_time_manager:
		retained_scale = 0.0 if external_pause else float(clampi(pace, 0, 2))
	return maxf(0.0, real_delta) * retained_scale if is_finite(real_delta) else 0.0
