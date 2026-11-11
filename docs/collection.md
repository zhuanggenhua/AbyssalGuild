# Global collection and unread menu state

Independent source audit: CardManager discovery/factory/restore paths,
GameData, PackVendor.UpdateCollectionTracker, MenuView, RecipesView and
QuestsView at source revision `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
No Unity execution or original source inclusion is required.

## Model API

`session.collection` is a Collection instance configured with the catalog.

- `mark_card(guid) -> bool`: resolve a definition GUID and record its stable
  CardDefinition.Id once. Packs and all Recipe-category cards are excluded.
- `is_card_discovered(guid) -> bool`: query a resolved definition's stable ID.
- `pack_progress(pack_guid, discovered_recipes) -> Dictionary`: returns found,
  total, cards_total, recipes_total and complete. A zero-total pack is not
  marked complete and should show no tracker.
- `is_unread(item_id)`: known Recipe.Id or Quest.Id absent from SeenItems.
- `mark_seen(item_id)`: call only on an individual visible item's hover-enter.
  Headers, opening a menu and completing a quest do not mark rows read.
- `changed`: emitted for a new gameplay card discovery or newly seen row.
  Connect the view directly, including for friendly-suppressed spawns which
  produce no ordinary card-created/stats event. This native refresh signal is
  an adapter, not a new gameplay stats/quest event.

`reset()` clears both sets for a new game. Configure/reset/apply/merge do not
emit intermediate collection events; successful session restoration emits the
normal session changed notification. Read state is one shared namespace for
raw recipe and quest IDs, matching source. The current export has no collisions.

Factory marking occurs before friendly-mode suppression, so rejected aggressive
spawns still count as discovered. It occurs before attachment or destruction,
so a coin immediately deposited into a chest still becomes discovered. A pack
itself does not count merely because it was bought or spawned. Class changes
from equipping are not factory calls and do not independently mark the new
character class. Later traveler reconstruction is a factory call and can.

Dynamic physical recipe cards have IDs like `Recipe:<recipe-id>` but category
Recipe, and do not become discovered cards. Discovering their underlying
recipe uses the existing, separate `session.discovered_recipes` mechanism.

## Pack totals

Card references are deduplicated by definition identity/GUID across all slots;
recipe references are deduplicated by Recipe.Id, separately from cards. Null
references/lists are skipped. Neither weight nor RecipeChance reduces totals.
Nonpositive weighted entries remain drawable in source because draws clamp
weights to at least one. Recipes with zero chance still contribute to totals.

The source export's totals are: Starter 4, Beginning 14, Revelations 27,
Farmstead 19, Hearty Meals 19, Knowledge 27, Blacksmith 20, Adventure 15,
Construction 20, Island 5, Survival 7. Found cards consult card discovery;
found recipes consult recipe discovery. Trackers should remain hidden for
inactive vendors and show COMPLETED only for nonzero fully found totals.

## Native persistence and compatibility

Standalone session saves optionally contain `collection` with string arrays
`discovered_cards` and `seen_items`. `stage_state` validates without mutation;
`apply_state` commits copies. Arrays are capped at 100,000 IDs each. IDs are
nonempty strings of at most 256 characters without NUL; duplicates and malformed
types are rejected. IDs are serialized sorted for stable comparisons.

Unknown bounded strings are deliberately preserved. They are inert until
corresponding content is resolvable. This mirrors source GameData retaining
unknown discovery/read IDs while CardManager skips unresolvable definitions.
Restore does not apply factory exclusions to saved discovery strings, also as
in source; normal gameplay never adds pack/Recipe-category IDs. Seen actions
accept known menu IDs only, but saved unknown IDs remain intact.

Legacy native snapshots missing collection infer only existing non-pack,
non-Recipe effective card IDs, including equipped items represented as model
cards. Read state begins empty. This cannot recover sold/deleted cards or prior
friendly-suppressed draws, and makes no claim to reconstruct complete history.
Native snapshots with collection present are restored exactly, without inferring
extra discoveries from transformed card instances or replaying creation events.

Existing recipe-state validation remains unchanged: native discovered recipe
IDs must be known to the catalog. This patch does not relax other save rules.

## Campaign-global semantics

Campaign capture adds `global_progress`, containing the canonical collection
and discovered_recipes. Scene snapshots retain copies for standalone usability
and backwards compatibility. Campaign restore validates **every** scene and
the optional global section before live mutation, then unions their validated
progress. An old destination scene cannot erase discoveries or read markers
made elsewhere. Legacy campaign files lacking the global section union their
available scene histories, with conservative inference for missing collections.

Travel merges current global progress into the staged destination and makes
current recipe knowledge available before new-scene quest activation. Staged
travelers may add legitimate discoveries. These changes affect only temporary
sessions until the complete transition validates. Failed travel does not leak
IDs, recipe progress, unread state, cards or random draws into the live session.

Loading a different campaign/slot replaces progress with that file's validated
union; it never imports knowledge from the previously active slot. Loading an
older save intentionally restores that save's history, not unsaved future
progress. The no-rollback guarantee applies across scenes within the restored
campaign, not across independent save timelines.

## Departure checkpoint hook

`campaign.before_travel: Callable` is live-only and must return
`{ok: bool, error?: String}`. It is called once after travel has completely
validated/staged, but before committing any live scene, items or global state.
A failed/invalid response aborts the transition. It is not serialized, copied
to temporary sessions, or called while validating/loading snapshots. The view
can bind its departure save handler and separately save on scene_changed.

Native ordering intentionally checkpoints the unchanged pretravel source before
an atomic transition. Source TravelRecipe consumes inputs before GameDirector's
SaveGame and scene change, with Unity deferred-destruction ambiguity. The native
checkpoint prioritizes recoverable departure state and an all-or-nothing live
transition rather than reproducing that ambiguity. Checkpoint callbacks must
not mutate gameplay state; save-file validation uses isolated temporary state.

## Verification

`test_collection.gd`: 57 checks with the private export, 46 without it. Covers
friendly rejection, ID kinds, exclusions, idempotence, pack totals, unknown IDs,
read isolation, atomic bad-state rejection, native/legacy saves, global travel
and return, canonical/legacy campaign union, cross-slot isolation, failed
checkpoints, inactive-scene corruption, class transformation, null lists and
new-game reset. Eleven optional checks verify real source pack totals.

Also verified: save codec 381, travel 35, factory 29, scene spawn 28, runtime 76,
special recipes 445, quest integration 70, quests 322, slots 40 and AI 55 checks.
