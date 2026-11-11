extends RefCounted
## Tests that assert final rules still exercise the real model timeline.
static func finish(session) -> bool:
	session.end_day()
	return drain(session)

static func drain(session) -> bool:
	for frame in range(20000):
		if session.phase not in ["feeding", "encounter"]: return true
		if session.cycle.stage == "await_feed":
			push_error("Cycle test driver cannot skip explicit Feed confirmation")
			return false
		session.tick(0.05)
	push_error("Cycle did not finish within the test frame bound")
	return false
