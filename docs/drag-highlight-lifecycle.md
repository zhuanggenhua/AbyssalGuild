# Source drag highlight lifetime

Locked StackCraft a11a89b04cea8370476f2559b639bb9b4cbc08d8. No Unity execution.
This implements the normal live-target path, not complete multi-touch or exact
Unity exception propagation.

CardController equipped/standard pointer-down calls CardManager's highlight
query once, after its split/unequip setup. Combat-down returns without querying.
CardManager uses CanStack(lifted.Definition, target.BottomCard.Definition), then
excludes the same card/stack and active crafting targets. This source matrix
direction is not the general native drop predicate: no proximity, lock, excess
join or other convenience filter is added. Source BottomCard is native back().

TradeManager similarly samples CanTrade at down. A buyer accepts sellable cards
and no nonempty chest; an active vendor accepts Currency category or nonempty
chest. No transaction quantity, price currency GUID or spatial overlap is needed
for these highlights. Qualifying object references are retained, including
duplicates, rather than re-derived each frame or keyed only by reused numeric IDs.

CardController's accepted left-up clears both manager lists before drop/click
actions, even after a later input lock. CardCombatant.EnterCombat clears only the
card list. Native combat entry emits the corresponding presentation event.
Vendor reveal still writes directly to the same zone setter, so the last write
wins. No priority/refcount restoration of a reveal highlight is invented.

GUI hover, Pause, late locks, focus-out, HUD visibility or changed eligibility do
not re-query or clear the down snapshot. Scene fade clears hover/progress only;
actual manager/session teardown disposes retained references. Existing dragging
permission is independent from these presentation lists.

Destroyed-reference boundary: source ForEach has no null guard and can throw
before List.Clear or subsequent zone clearing. Native records
source_missing_reference and stops that clear list, leaving its entries; it does
not silently prune, restore or re-query. It does not emulate the Unity exception
that aborts the entire remaining drop call chain. That exceptional path remains
explicitly non-equivalent. This is not an added automatic recovery policy.

The real board integration suite exercises 18 cases: actual down/up, source
crafting exclusions, buyer/card writes, changed targets, pause/lock/focus/HUD/fade
persistence, disable/reenable, combat entry, combat-down, reveal competing with
release, and destroyed-reference diagnosis. Older card feedback expectations
that incorrectly required menu/focus clearing were corrected against source.

Input audit separately confirms source UI can select multiple touch targets,
but all CardControllers move using one shared Pointer.current with separate
card offsets. Native primary-touch emulation, including canceled release, works;
secondary-touch selection and same-stack competition are not yet mapped. This
highlight change does not claim to implement independent multi-finger dragging.
