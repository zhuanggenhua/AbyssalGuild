# A captured non-traveler card during portal fade

This is the original Grand Portal Main ↔ Island outbound sequence, with one physical mouse capture of a registered non-traveler singleton. Its definition must be an ordinary material, the exact authored loaded Wooden Chest, or an exact regional pack with deterministic authored draws, with no crafting tail, no overlapping touch owner, no equipment/combat ownership, and no side effect from native save normalization. The board admits the original portal recipe and binds the capture to its actual card, receiver, departing session and fade generation.

The original TravelRecipe consumes first; GameDirector writes the departure save and copies traveler data before fade-out. GameData.StackData uses the current stack target. CardController continues sampling the mouse during Update while held; InputSystemUIInputModule sends physical Left Up to the stored pointerPress even if the fullscreen image now owns raycasts. CardController drops at the rendered pose, not the Up coordinates. Accordingly, Godot samples only physical motion for the old capture, uses the existing drop path once at the rendered pose, blocks fresh presses and discards the capture at scene replacement. The already serialized checkpoint and isolated destination candidate do not acquire any outgoing motion or drop changes. Arrival does not write a new checkpoint for this admitted case.

The native Godot test covers ordinary Wood landing on unoccupied space in both original boards, new Left Down, duplicated/emulated Up, and holding across black replacement. This is not acceptance of equipment, combat, held travel ingredients, mixed touch/mouse captures, terminal trades, other or empty chests, multi-card crafting tails, pointer ordering at exact Unity frames, physical hardware or Unity pixel parity. No original assets or screen captures are in the commit.


## Authored Wooden Chest
A pre-fade, already captured loaded Wooden Chest can finish on the old board.
CardController plays CardDrop before checking the last rendered position against
its press position. A sub-threshold move calls the existing chest click, which
subtracts one, puffs at the rendered location and uses the scene's TradeManager
currency. Spawn queries the rendered X/Z plus one chest width, with no
null-stack clamp and only this chest stack excluded. A compatible loose pile
can receive the coin; this is not a special forced standalone spawn. On success
the chest target returns to the press position. Above threshold this tested
open-board case follows regular drop without withdrawing.

The viewport/collider test loads a real coin by stacking, starts the existing
Grand Portal, supplies a distinct motion sample then Up elsewhere, and checks
a standalone coin on Main and normal factory attachment on Island. It rejects
emulated/duplicated and post-swap Up. Checks cover the pre-fade save balance,
old-board effects and isolation from the staged arrival. These are native
Godot checks with injected mouse events, not Unity/physical mouse or visual
effect/audio playback parity on both engines.


## Main Starter and Island packs
The source pack's click tests the drawn pose, but unlike ChestLogic it spawns
from its stack target. The dragged singleton has the authored stack target
height (0.1 here); PackInstance adds a further 0.1 before normal factory
attachment and overlap, with no ignored stack. The pack is locked for overlap
while the factory runs. A surviving pack continues at its grounded target;
the final slot kills and puffs at the lifted pose. No other pack or recipe
roll route is admitted by this change.

Both regional packs' first and last draws were exercised through the real
Grand Portal and Viewport receiver. Earlier slots of the last-draw fixtures
were consumed by the normal pack logic. Each departure click rolls once and
releases one authored result, leaving the already saved departure and staged
destination/RNG untouched. This verifies native Godot factory/receiver state,
not identical Unity/Godot PRNG sequences or new-card airborne artwork and
physical input parity.

## Reused authored portal and departure save
Returning from a valid earlier trip does not refill either traveler.
Original CardInstance.Use decrements the authored single use on every trip;
the director carries the consumed values forward (1 → 0 → -1 and onward).
For the exact Grand Portal pair with ordinary undisguised, unequipped
travelers and a previously visited destination, the same departure-only
checkpoint applies. A real staging map must identify both new cards uniquely,
preserve their base/current definitions and show precisely one use decremented
per traveler. This also admits a fresh Villager traveling with a reused portal.
The separately tested native close windows still require the fresh pair.

The native scenario actually drags the traveler onto the portal on each of
three legs. It verifies the excluded travelers and retained bystanders at
the departure write, identical file bytes after settled arrival, exact
consumption and destination remaps, and a new write only after ordinary
Pause → Title. The fixture starts from an isolated game using the source
definitions; it does not represent a natural full campaign or test an entire
later campaign save.
