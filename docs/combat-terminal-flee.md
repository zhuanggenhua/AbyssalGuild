# Bounded terminal Flee cleanup

Source pin: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.

This slice corrects the last-player-attacker **idle** cleanup transaction in the
real Board adapter. It does not certify the full combat migration.

## Original path and mapped order

`CombatTask.Flee`: remove attacker, leave combat, call `Rect.UpdateLayout`, then
`EndCombat` when the attacker row is empty. `CombatRect.ArrangeRow` uses instant
ground slots. `EndCombat` stops the attack coroutine, marks Finished and closes
its rectangle before iterating remaining attackers then defenders. Each survivor
leaves combat; a singleton is constructed from its **current transform**, then
registered, then given an enforced ground placement target. Only afterwards
`CardController.HandleCombatDrop` registers the departing singleton and resolves
overlaps.

The terminal adapter requires pinned imported provenance, Main/Island source
configuration, identity Board transform, idle execution, and live directly-owned
native survivor nodes that pass the existing atomic layout guards. It updates the
remaining row and records actual native positions, not old combat model slots.
The model removes the task (Finished), closes native logical rectangle state with
a private synchronous callback, then restarts each survivor's AI inline before constructing its singleton, in row
order before the departing card. The existing public completion event stays after all singleton
registrations so unrelated observers never consume half-committed membership.
The former nonterminal layout hook and generic death/finish path are unchanged.

## Inline AI restart boundary

The locked player combat prefabs have no CardAI component. This path now also
requires that the departing card has no imported AI mapping. AI-bearing departing
cards use the prior generic fallback: a pre-mutation admission proof would be
needed to run their StartAI before layout without consuming RNG on rejection.

For admitted survivors, `CardCombatant.LeaveCombat` calls `CardAI.StartAI` inline.
The movement coroutine consumes its initial jitter draw immediately; a passive
producer then consumes the production coroutine's initial jitter draw. The Godot
adapter invokes this draw pair after rectangle close and membership removal,
before creating that survivor's singleton. It uses the existing timer owners.
The public-event resync sees running agents and does not repeat the draws. A
missing agent is registered once, since registration itself starts its AI.

## Verification boundary

`test_combat_terminal_flee_board.gd` instantiates the real Board with licensed
source inputs and drives native press/motion/frame/release. It checks post-layout
native transforms, close-before-registration, survivor-before-departing stack IDs,
placement targets and safe public notification. The authored Chicken producer
and Crab aggressive survivor are created in reverse of their combat row order,
so insertion-order public resync cannot accidentally satisfy draw-order checks.
The checks include stopped AI at close, movement/production/next-survivor draw
order, settled timers at the public event, unchanged next RNG consumer, and
single initialization when recovering a missing AI agent. Private runner requires a counted
success marker. These are headless native-node checks, not GPU or screenshot proof.

## Still unaccepted

- The survivor and departing **visual** ground tween (`DOMove`, source duration
  and ease) and ordinary CardView height are not fixed here. Model target order
  must not be mistaken for transform interpolation equivalence.
- AI-bearing departing cards, active combat restart, and general AI lifecycle
  equivalence are not accepted. No source-authored AI-bearing player last attacker
  was established for the pre-layout admission case.
- The existing timer represents jitter plus interval as one countdown. Unity
  uses consecutive coroutine waits; overshoot/frame-resume equivalence remains
  unaccepted. RNG checks prove draw ownership/order within Godot, not numerical
  equivalence between Unity and Godot RNG implementations.
- Active actor/target, active coroutines, melee, transformed/invalid views,
  equipment/cycle presentation and complex overlap movement are not expanded.
- No original assets, screenshots, private input data or source text are included.

## Idle terminal native hold/release

`CardController.OnPointerDown` constructs the combat singleton from the actual
transform and captures its offset, without calling `UpdateDragPosition` in this
branch. The next `Update` uses `Board.ClampToBounds`, which preserves authored
DragHeight (`0.1`) and does not yet enforce the header. `HandleCombatDrop` reads
the current transform, not the pointer-up event position. The admitted native
terminal route now uses this same held capture as the nonterminal route. A newer
motion or release event without a frame does not replace the last actual pose.

Admission remains idle, no departing AI, pinned Main/Island, identity Board and
valid survivor native nodes. Before using the held position transaction, the
no-contact preview excludes the rectangle that `EndCombat` closes and includes
each defender's resized, placement-enforced singleton. Overlapping terminal
releases retain the prior unaccepted settlement adapter. The actual held X/Z is
visible to the terminal Flee callback before header placement; final model target
placement follows Flee. This does not expand visual landing tween acceptance.

The native regression now deliberately sends a new inside motion and inside
release after an outside/header held frame. It checks pointer offset, delayed
frame update, `0.1` height, physical clamp versus header placement, consumed hold,
missing-survivor/active-execution rejection and survivor contact exclusion, along
with the earlier ordered cleanup and RNG assertions. This is not paired Unity
runtime or screenshot acceptance.

## Combat pointer audio dispatch

At the same locked source revision, `CardController.OnPointerDown` returns from
its combat branch before reaching the standard branch's `PlaySFX(CardPick)`.
The Board no longer sends that extra pick request for an accepted combat press.
`OnPointerUp` still sends `CardDrop` before `HandleCombatDrop` classifies the
release; this order is unchanged. Standard accepted press/release retain their
pick/drop events. Equipped-card early-return semantics are a separate, unaccepted
routing item, not implicitly certified by this change.

The existing native Board regression compares ordinary and terminal combat
press/release using private imported AudioManager clip mappings and real pool
slots. It checks no combat pick request/slot, original pick clip on ordinary
press, original drop clip on combat release, and the drop request already present
when terminal Flee layout is called. Cooldown bookkeeping is cleared between
independent cases so a wrongly sent pick cannot hide behind cooldown rejection.
No replacement audio assets or production cooldown changes are introduced. This
proves dispatch and clip routing, not listening/acoustic or paired Unity parity.
