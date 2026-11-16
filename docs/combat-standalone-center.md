# Standalone combat entrance center (bounded migration)

Source baseline: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.

`CombatManager.CreateCombatTaskInternal` initializes `CombatRect` before
`EnterCombat`. `CombatRect.Initialize` averages the entrants' live transform
positions, flattens the result, then clamps the rectangle to the Board.
Using their queued destinations instead is observably different while moving.

The native Board now supplies a separate standalone center sampler after the
pre-start overlap decision and before membership changes or progress RNG draws.
All entrants must have finite, ordinary grounded source-world observations via
the existing live-pose admission. If any observation is unsupported, no mixed
live/target average is invented; the previous target-derived fallback remains.

A finite receipt belongs only to this newly created standalone task. Initial
layout consumes it and applies the existing imported-size Board clamp. It does
not move card targets while sampling. Receipt data is omitted from save_state.
Existing/saved layouts retain their own center and discard any stale receipt;
merges do not invoke this sampler. Subsequent layout updates retain the center.

This does not establish full equivalence of rectangle initialization timing,
overlap-resolution side effects, merge occupant sampling, raised/dragged/equipped
poses, or complete rendered/pixel parity. These remain separate work.

Validation extends the existing source-free combat-merge-pose suite (finite seed,
invalid fallback and retained center) and authentic imported native Board suite
(live average distinct from targets; complete-group rejection; pre-membership and
pre-RNG sampling; imported clamp; receipt consumption; saved-layout path
precedence; merge bypass). Production feedback/audio remains active; its fixture
teardown drains the real native playback references.
