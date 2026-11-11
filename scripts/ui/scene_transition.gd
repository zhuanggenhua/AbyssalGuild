extends RefCounted
## Source-timed, real-time fade with generation-owned commit; never owns user pause.
const DURATION := 1.0
var phase: String = "idle"
var alpha: float = 0.0
var generation: int = 0
var elapsed: float = 0.0
var _commit: Callable

func active() -> bool:
	return phase != "idle"

func blocks_input() -> bool:
	return phase == "out" or phase == "commit"

func begin(commit: Callable) -> bool:
	if active() or not commit.is_valid(): return false
	generation += 1
	_commit = commit
	phase = "out"
	elapsed = 0
	alpha = 0
	return true

func cancel() -> void:
	generation += 1
	_commit = Callable()
	phase = "idle"
	elapsed = 0
	alpha = 0

func advance(real_delta: float) -> void:
	if not is_finite(real_delta) or real_delta <= 0 or not active(): return
	if phase == "commit": return
	elapsed = minf(DURATION, elapsed + real_delta)
	alpha = elapsed / DURATION if phase == "out" else 1.0 - elapsed / DURATION
	if elapsed < DURATION: return
	if phase == "in":
		phase = "idle"
		return
	phase = "commit"
	var token: int = generation
	var action: Callable = _commit
	_commit = Callable() # Consume before invoking reentrant code.
	if action.is_valid(): action.call()
	if generation != token: return
	phase = "in"
	elapsed = 0
	alpha = 1
