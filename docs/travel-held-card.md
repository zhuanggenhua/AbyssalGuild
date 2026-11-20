# A captured non-traveler card during portal fade

This is the original Grand Portal Main ↔ Island outbound sequence, with one physical mouse capture of a registered non-traveler singleton. Its definition must be an ordinary material or the exact authored Wooden Chest with a positive stored balance and scene currency, with no crafting tail, no overlapping touch owner, no equipment/combat ownership, and no side effect from native save normalization. The board admits the original portal recipe and binds the capture to its actual card, receiver, departing session and fade generation.

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
