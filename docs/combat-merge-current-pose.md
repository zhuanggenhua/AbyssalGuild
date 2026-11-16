# Combat start overlap uses current ground poses

Locked CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`CombatManager.cs` lines 293–318 and 426–441: before creating a task,
the manager computes its potential bounds from the **current transforms** of
all new combatants. A queued destination is not the position at this decision.

The native pre-start overlap selector now samples ordinary stable-ground XZ
through the existing Board live-pose adapter, before membership changes. It
uses the current source-ground coordinate for each admitted actor, leaving
the model target, motion state, random state, factions, sizes and merge order
unchanged. A card currently next to an ongoing combat can merge even if its
pending endpoint is distant; a distant card no longer merges only because
its pending endpoint is nearby.

The helper copies records rather than writing source state. Missing,
nonfinite, non-Vector3, non-ground or unsupported observations keep the prior
settled-target fallback. This is intentionally bounded: original potential
bounds have height 1 and existing combat bounds have height 2, both centered
at their current transform Y. The native planar model cannot certify elevated
intersections and this patch does not flatten arbitrary Y. Ordinary Board
pose admission rejects drag/damped/blocked/equipped/combat ownership and
unproven vertical transitions.

The existing region-center adapter, first layout initialization and merge
reinitialization still use settled layout coordinates, not a verified live
CombatRect transform. This change corrects the pre-start **membership decision**,
not all combat placement or animated region behavior.

Public tests cover current-near/stale-far, current-far/stale-near, unchanged
input and sampling order, invalid/elevated/missing fallback. The private
imported Board test exercises real view nodes, genuine catalog factions,
the native selector and actual CombatSystem.start_combat merge; it confirms
both new sides and existing fighters join one task. View positions in that
test are controlled observations, not Unity screenshot or scheduling parity.
