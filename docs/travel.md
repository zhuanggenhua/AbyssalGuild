# Travel and campaign persistence

`Campaign` owns the current scene, positive save-slot number, and per-scene native
SaveCodec snapshots. It holds only a weak session reference. It does not preload
GameSession, so Session may own/preload Campaign without a dependency cycle.
`next_slot(taken)` returns the lowest unused positive integer; slot numbers are
save identities, not card or stack indices.

## Integration contract

- Configure Session with catalog, seed, and selected scene; configure Campaign
  with that Session and scene/slot. New games must clear campaign.saved_scenes.
- Include TravelRecipe in recipe selection. On completion call
  `campaign.travel(stack.id, recipe_guid)` **before** any ordinary consumption,
  craft cleanup, or repeated-recipe selection. Successful travel replaces the
  whole board; return immediately and stop the old tick's stack iteration.
- Session.configure accepts selected scene and configures scene-specific quests
  and WorldRules. SaveCodec snapshots include scene_name, friendly_mode, and
  WorldRules. Travel must not start another encounter/combat tick afterward.
- Save/load Campaign rather than just Session to preserve inactive scenes.
  `capture`/`restore` are JSON-compatible; `save_file`/`load_file` validate the
  entire campaign, use a same-directory temporary file, and keep a validated
  previous primary as `.bak`. Temporary files are never promoted on load.
  Legacy Godot session saves are adopted as a one-scene campaign when loading.
- UI can display current_scene/slot_number and react to scene_changed. No source
  assets or data are packaged by this helper.

## Audited source semantics

TravelRecipe copies the complete stack before ConsumeIngredients. GameDirector
then saves the source board, and only afterward constructs CardData from the
held traveler references. The actual Travel recipe lists Main, Island cyclically
and consumes one Grand Portal and one Villager. Both start with one use, so their
first transferred UsesLeft is zero, not one. CardInstance.Use blindly decrements;
RestoreSavedStats copies that value unchanged. Reusing exhausted travelers can
therefore produce negative UsesLeft. Native saves must allow signed uses values.

Each traveler is restored as a separate stack at a newly sampled flattened point
inside the unit sphere. Health, nutrition, uses, chest coins, original definition,
class transformation and attached equipment are retained. Runtime card/stack IDs
are newly allocated above both source and destination counters. Source registered
stack IDs are not imported as traveler IDs. Equipment slots and class-item links
are remapped to new IDs.

First visits use the destination scene's serialized CardManager defaults, not
Main's starter fallback: Island and Main have different default cards, centers
and radii. Revisited scenes restore board, clock, quests, vendor payments, combat,
and WorldRules/encounters. Discoveries merge from the departing scene globally.

## Explicit uncertainty and migration policies

This is static source verification, not a Unity execution claim. Unity Destroy is
deferred; pre-consume references may still be readable before frame end, while
DestroyCard removes cards from registered stacks immediately. Exact equipment
OnDestroy order and stale-reference behavior are not runtime-verified. The native
helper deliberately preserves pre-consume serialized identity/equipment and
post-consume uses, rather than pretending that timing is proven equivalent.

For retained/excess travel ingredients, Unity's source-board save may retain
survivors and duplicate them on a later visit. The migration explicitly removes
all departing travelers from the source baseline, preventing duplication. This
is a documented migration policy; the serialized default recipe consumes both
required cards fully, so its normal first departure needs no such correction.

Invalid destination, recipe composition, corrupt active/inactive scene, or invalid
travel payload rejects before live mutation. Staging uses independent sessions
and catalogs. Unity's source consumes before checking its destination list; the
native atomic rejection is an intentional safety improvement.

## Runtime/UI integration

Travel recipes now participate in session matching and completion. A successful
scene switch returns immediately from the old tick, so no old stack or elapsed
time advances in the destination. The board refreshes scene vendors and quests
and retains campaign saves in `user://session.json` (with legacy one-scene adoption).
The integrated runtime recipe path adds five real-data checks: total 35.
