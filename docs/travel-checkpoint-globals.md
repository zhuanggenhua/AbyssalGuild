# Travel globals after a held checkpoint

## Defect and narrow correction

Native `SaveCodec.capture` settles a held split as an ordinary unattached release
in an isolated session. That release can select a recipe and update discovery or
quest state. Travel already used this normalized snapshot to freeze its source
scene, but initialized and merged destination globals from the unchanged live
session. Arrival could therefore forget a recipe that the frozen source knew;
saving and continuing would reveal it again when campaign restore merged scenes.

`Campaign` now supplies the staged departure session to first-visit initialization
and merges that same session's discoveries and collection into either a new or a
restored destination. First-visit Discover quests see the normalized discoveries
before root activation, default-card spawning and traveler restoration. Source
and destination still use separate quest tables and progress denominators.

Revisited quests retain the existing restore contract: saved active/completed
state is loaded without replaying recipe-discovery events or reactivating roots.
Global merging does not mark a newly discovered recipe or completed quest as
read. Existing destination discoveries and read flags are retained by union.

Only `campaign.gd` changes production behavior. The held helper, SaveCodec,
recipe selection, traveler eligibility, consumption, ID allocation, RNG sampling,
dynamic recipe-card definitions and quest-event code are not changed here.

## Transaction boundary

Source settlement, destination quest activation and the global merges all occur
in isolated models. The existing custom `before_travel` checkpoint runs after
validation and before live commit. A false/malformed checkpoint response, corrupt
destination, missing scene or reentrant held capture leaves the live globals,
cards, model references, source catalog, RNG, pointer grant and saved-scene index
unchanged. No staged discovery or quest signal is published on the live session.

Successful commit freezes the source, installs the destination and clears the
old hold. Arrival, immediate save/Continue, return travel and later visits now
agree on global knowledge without relying on reload to repair it.

## Static reference and policy boundary

Reference remains CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`Assets/StackCraft`. Relevant static evidence:

- `Scripts/Core/GameDirector.cs`: `InitiateTravel` saves before scene transition.
- `Scripts/Crafting/CraftingManager.cs`: `HandleBeforeSave` unions discoveries
  into game data; `Awake` imports that global recipe knowledge.
- `Scripts/SaveSystem/GameData.cs`: discovered recipes/cards and seen item IDs
  are global sets, separate from scene snapshots.
- `Scripts/Quest/QuestManager.cs`: activation of a Discover quest checks known
  recipes; saved quest restoration does not repeat that activation check.

This correction makes the existing **native held-checkpoint policy** consistent
across travel. It is not a claim that Unity performs the native clone-and-release
normalization. Unity was not launched, and no original source or assets were
copied into the implementation. See [held checkpoints](held-stack-lifecycle.md)
and [travel policies](travel.md).

## Verification

The dedicated tests use the isolated `tools/test_godot.sh` runner:

- `test_travel_checkpoint_globals.gd`: **175/175** synthetic checks. Covers
  first visits, unequal quest tables, recursive activation/completion order,
  explicit-release equivalence, ordinary travel, staged/live/destination global
  provenance, read flags, custom checkpoint failures, early rejection, references,
  exact RNG/IDs/metadata roundtrips, disk Continue and repeated return travel.
  A test-only session observer adds collection/read changes on settlement so
  those fields also prove staged provenance; it does not imply normal release
  currently changes read flags. The old Campaign failed 19 behavioral checks.
- `test_travel_checkpoint_globals_source.gd`: **80/80** licensed-data checks.
  Builds Wood plus three Fiber through the real stacking matrix, holds the Fiber
  tail, then uses a separate lawful Grand Portal plus Villager stack. Both direct
  and timed travel know Rope immediately on Island; source, JSON/disk Continue,
  return travel and second visits agree. Failed checkpoint remains atomic.

Focused regressions also pass: held **73**, source held **17**, travel **35**,
SaveCodec **534**, cycle save validation **144**, cycle order **45**, cycle
timeline **127**, cycle presentation **8**, recipe definitions **195**, source
recipe cards **248**, special recipe scenes **20**, collection **57**, quests
**322**, and quest integration **70**. Total: **2,150 checks** across 16 suites.

These results were obtained on the coherent `69a7062` baseline (published held
checkpoint `d494ac2`), overlaid only with this Campaign change and the two new
test files, using Godot **4.6.3**. Concurrent crafting-order changes were excluded
from that focused snapshot and require their own integrated validation. No
shared runner files are changed here. These model tests do not establish rendered
UI, physical mouse/touch, audio or exported-build acceptance.
