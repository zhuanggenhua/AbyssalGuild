# Completed source arrival: close during fade-in

This is distinct from pre-blackout source close and unlocked ordinary close. The locked original persistent director handles sceneLoaded by restoring travelers, updating CurrentScene and delivering scene data to managers. Its travel coroutine resumes after the async scene load, releases external time pause, then runs the incoming fade. Application quit outside day-end saves that now-current destination.

Only a completed, single, accepted ordinary source travel may issue this receipt. At commit the exact outgoing owner, candidate, transition generation, original stack/card identities, craft generation and accepted traveler mapping must still match. Original source departure admission is rechecked through its pure admitted predicate, without capturing/copying campaign state at commit; extra travel and unresolved other completed tasks reject the grant. Receipt installation follows _enter_game only if the actual destination owner and transition generation still match.

Close is admitted only during the incoming phase with that same owner/scene/generation, source lock, no pending travel, idle playing cycle and quiet UI/input/combat/AI. A destination with another portal recipe is excluded. No grant exists for title/new/load transitions, transition-out, the black/loading commit phase, unknown imports, or stale receipts.

Successful close uses the existing native destination checkpoint, preserving slot/timestamp and backing up the prior departure. It never reuses the old-scene consumed snapshot or overwrites any staged destination. Failed writer leaves the incoming session open with the existing retry notice, a deliberate native safety policy rather than claimed Unity shutdown-veto semantics. Existing precommit behavior remains separate; its historical incoming-ignore test now checks unverified incoming fallback, while the new suite covers verified source incoming.

Tests dispatch actual Board close notifications and intercept final quit. Native OS event timing and Unity framebuffer identity are outside this focused logic verification.

Receipt references expire when fade-in completes, a generation mismatch is synchronized, title opens, another transition is accepted, or the Board quits/exits. Expiry and direct-cancel sync are regression-tested.
