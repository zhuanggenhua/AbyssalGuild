# Source-backed spawn policy

This independently implemented factory behavior was audited against StackCraft
revision `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, principally CardManager's
factories, CardInstance.Initialize/TryAttachToNearbyStack, CardStack.MergeWith,
and recipe/pack/chest/encounter call sites. No Unity runtime was launched.

## API and ordering

`session.spawn_card(guid, position = Vector2.ZERO, target_stack = -1,
options = {})` retains native explicit-target construction. Options:

- `refuse_attach: true`: skip candidate lookup, retain overlap resolution.
- `ignored_stack_id`: exclude a processing/withdrawal-origin stack.
- `height`: source Y coordinate for the attachment query; pack contents use 0.1.

`session.spawn_target_selector(card_id, ignored_stack_id) -> int` is an optional
**read-only** view geometry query. The view reads `session.spawn_query_height`
while the callback runs. It returns a candidate ID or -1. The session validates
that the returned stack still exists, is not excluded, and passes existing
stacking/crafting rules, then performs the regular merge/chest interception.
The callback must not mutate stacks/cards. Recursive spawn calls from this
selector are rejected without allocations. Query height is reset afterward.

`session.spawn_layout_resolver() -> void` optionally resolves overlaps after
attachment and before factory stats/card-created events. It must only update
layout positions, never spawn cards. RefuseAll still invokes this resolver.
Explicit native `target_stack >= 0` construction skips both callbacks.

Factory ordering is: validate definition/friendly policy → allocate/register
singleton → optional candidate lookup and merge → overlap resolution → stats
and card-created event for non-packs → changed notification. Existing merge
logic may emit its own change/stats notifications during attachment, as source
stack registration/destruction can do. There is no deferred next-frame attach.

A successful spawn can be immediately deposited into a nearby chest. Its
allocated ID is still returned and its creation event still carries the
captured base definition, even though `cards.has(id)` is now false. Callers must
check live existence before dereferencing the returned ID. This preserves the
source factory event after Initialize's chest interception without trying to
retain a destroyed coin as a live model card. It is distinct from factory
rejection, which returns -1 and emits no creation event.

## Friendly mode

The generic non-pack factory rejects aggressive definitions before allocating
IDs or invoking placement hooks. This covers pack contents, loot, exploration,
crafting, production and encounters uniformly. Packs use the separate source
CreatePackInstance path and are not filtered as aggressive ordinary cards.

Suppressed pack draws still consume their slot; they are not rerolled.
Exploration still publishes exploration-finished after attempting valid loot.
Ordinary crafting consumes inputs and publishes its declared output completion
even if the friendly-mode factory suppresses that output, matching source
RecipeDefinition.Execute. Its native event uses card_id = -1 in that case.

Source MarkCardAsDiscovered occurs before this friendly filter. The native
model does **not yet** persist discovered-card IDs; that separate missing
feature is explicitly not replaced by recipe discovery or added by this patch.

## Call-site policies

- Pack contents, death loot, passive production, sale currency and purchased
  packs: normal automatic attachment.
- Ordinary craft, exploration, growth and research recipe cards: automatic
  attachment excluding the processing stack.
- Chest withdrawal: exclude chest stack, preventing immediate redeposit.
- Encounters and initial non-pack cards: refuse attachment.
- Initial packs: normal automatic attachment.
- Traveling cards and their equipment: refuse attachment while staging.
- Native save reconstruction: build staged model objects directly, never call
  the factory or presentation callbacks.

Board adapters must remove earlier manual post-spawn attachment wrappers for
pack draws, purchases, chest clicks and AI produce. Otherwise they can attach
again after the factory event and defeat a caller's exclusion policy.
AI's default produce path already calls the central factory; no custom
produce_spawner is required when the session hooks are bound.

Callbacks belong to the live session and are not serialized. Codec.restore and
campaign travel retain them on that same live session. Rebind when replacing
an entire session object. Temporary campaign sessions do not inherit live view
callbacks. Destination rejection of a traveler or equipment returns an error
before committing campaign state instead of indexing an invalid instance ID.

## Iteration safety and verification

Candidate selection is pure and completes before merging. Candidate geometry
should be gathered into an array before any mutation. Existing AI iterations
use snapshots. Craft ticks now verify each snapshotted stack is still the same
registered object before advancing it, preventing stale advancement following
an attachment/removal elsewhere in the tick.

`tests/godot/test_spawn_factory.gd` has 29 checks covering attachment/event and
layout ordering, RefuseAll/exclusions/direct targets, stale and recursive
selectors, friendly atomic rejection, suppressed pack/craft/exploration,
auto-deposit metadata, chest withdrawal, source Beginning-pack aggression and
query height, real encounter isolation and restore bypass.

Verified alongside runtime (76), special recipes (445), world rules (76), AI
(55), save codec (381), travel (35), quest integration (70), and combat/equipment
(60) checks. Physical collider lookup and overlap layout remain view adapters;
headless fixtures do not claim identical Unity Physics hit ordering.
