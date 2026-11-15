# Source-locked ordinary arrival persistence

The locked original GameDirector saves before travel, on ordinary application
quit, and when returning to title. DayCycleManager saves when the Start Day
button callback runs. Neither arrival coroutine nor scene-loaded handling saves.
Quest/scene initialization does not introduce another disk write.

Board carries `source_arrival_no_save` beside layout provenance only after the
existing normalized departure capture admits the actual accepted traveler map.
That admission verifies original source commit, recipe hash/class/cycle,
ordinary single completed portal, exact original ingredients/uses, and quiet
source lifecycle. Failed departure save still rejects before fade. Commit retains
the same three bound arguments, consumes no new callbacks, preserves live arrival
layout and displays an arrival notice without claiming saved. It does not alter
launch slot creation or the old scene_changed fallback. Unverified imports,
equipment/excess/unsupported travelers and nonadmitted requests keep native
arrival autosave. The scope is not a global save-policy rewrite.

**Real consequence:** after an admitted arrival, abrupt application loss before
another legitimate save resumes the departed scene with the consumed portal
absent. Explicit Save or ordinary graceful close persists the destination. The
backup remains unchanged at arrival and rotates on the next actual successful
save. This deliberately replaces the earlier native convenience autosave only
for proven source-ordinary trips. It is not a promise to preserve unsaved arrival
progress after a crash.

`test_source_arrival_persistence_board.gd` runs actual Board recipe/transition,
primary/backup byte checks and new-Board Continue, including a return trip,
explicit save, close notification, unverified/hash/unsupported and legacy
fallbacks. It uses controlled frame steps and an intercepted final quit dispatch,
not a physical crash or Unity runtime. Geometry tests retain live assertions and
perform an actual explicit save before testing persistence. Source evidence was
verified privately against the existing import lock; proprietary excerpts and
assets are not included in this document.
