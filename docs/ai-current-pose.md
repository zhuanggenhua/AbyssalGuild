# AI decisions use current card transforms

Source: locked CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`Assets/StackCraft/Scripts/Card/Components/CardAI.cs`, lines 147–230.
`FindClosestRelevantCombat`, `FindClosestPlayerCard`, the attack threshold, and
`MoveTowards` use current three-dimensional `transform.position`. A queued/tween
endpoint is not interchangeable: it can select a different player or begin a
fight before the card reaches range.

The board now injects current horizontal card coordinates into WorldRules. It reads
actual card XZ at the AI update point and reflects Godot Z back to Unity Z.
Native ordinary card roots have an extra Y=0.06 display lift, while held cards use
a different height contract. The adapter therefore accepts only ordinary animated/instant motion whose target,
current state and actual rendered Y all equal the source settled stack Y plus 0.06.
It supplies the known source height and current XZ only in that stable-height case.
Damped/blocked/held/equipped/combat owners and changing vertical motion return no
sample: the entire actor pose falls back to the prior settled model contract.
This is not a universal subtraction of 0.06. Current vertical height during
those rejected cases remains unverified. The model sampler
supports Vector3 and its isolated exact-Y tests do not establish native Y parity.
It does not advance CardMotion or write a view/model position just to sample.
The existing root order runs AI before synchronizing the next ordinary card-motion
frame; this patch does not invent a new Unity script/tween scheduling guarantee.
Invalid, queued-for-deletion or absent views return no sample, so model-only tests
and first-frame/missing-view paths explicitly retain settled-target fallback.
The callback survives model configure/travel and scene entry rebinds it. It is not
serialized and consumes no randomness.

Nearest-player comparisons, attack/join thresholds and approach origin now use
current XZ with the explicit existing Y contract. Ground-to-ground approach now starts at the observed current position and targets
the observed current destination. If either retained model Y is nonzero, movement explicitly
retains the prior settled XZ placement contract until the vertical target model is
ported. This fallback is covered by a focused test and is not source parity. Search
order, strict closest-combat radius, inclusive attack radius, unrestricted player
search radius, existing-combat priority and board rejection are unchanged.

Tests cover opposite live/target nearest order, stale near endpoints, live height,
exact attack threshold, stable ties, source unrestricted player search, nearby and
far existing combat, current-origin ground step, explicit elevated fallback, rejected placement, invalid
samples, and reconfiguration. The private Board suite uses the actual imported
mob/player catalog, actual view nodes, a due AI tick and the real board validator.
It verifies an actual synchronized ordinary view at Y=0.06 maps to source Y=0.
Other cases deliberately control view poses; none is a Unity screenshot comparison.

## Explicit remaining scope

The stack model still stores XZ targets: vertical target persistence/animation is
not established by this change, including elevated approach. Combat region centers
still use the existing settled layout adapter, not an independently sampled animated
Rect transform. AI detach and produce spawn still use their prior
settled-target adapters; passive patrol correctly remains based on stack target
as in `MoveRandomly`. No raw original files/assets or screenshots are distributed.
This is bounded decision and horizontal approach correction, not full AI or visual
acceptance.
