# Combat join membership and progress boundary

Source lock: Unity CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
`CombatTask.AddCombatants` lines 320–342 appends each valid recruit to its
side list and the historical combatant list, enters that card, and only then
initializes its progress. After all recruits the source resizes and checks for
an overlap once. `CardCombatant.EnterCombat` records the task, leaves the
previous stack, clears highlights and stops its AI before returning.

This change aligns list visibility at the Godot entry signal. The current
admitted card and earlier recruits are visible in both appropriate lists,
while its own progress draw has not executed. Later recruits remain absent.
The constructor retains its distinct all-progress-before-entry order. This
does not change snapshots, RNG algorithms, active combat layouts or timers.

The native combat-order test observes three interleaved recruits into a
reversed player orientation, including duplicate/invalid input, after detach
and before each draw. Its resize callback checks all progress has initialized
before geometry evaluation. A callback-controlled RNG isolates the exact
position of each draw; it does not imply cross-engine bitstream parity.
