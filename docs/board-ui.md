# Runnable 3D board shell

This is an independently implemented Godot 4.6 UI over the audited runtime model. It is a functional migration slice, **not visual parity or final gameplay acceptance**. It uses generated box meshes, flat colors and system/default fonts. No original template textures, models, audio, screenshots, or copied third-party artwork are included.

## Run

1. Follow `docs/data-import.md` to generate local `data/stackcraft.json` from a licensed original source copy. Generated content remains ignored and must not be publicly committed.
2. Open `project.godot` in Godot 4.6, or run `godot --path .`.
3. Choose a 60–180 second day duration and New game. Continue reads the Godot-native save at `user://session.json`, falling back to its validated backup where supported by the codec.

Without valid data, the title shows an import command and refuses to start. There is no substituted mock game.

## Controls

- Left-click a pack to draw one slot. Right-click selects without opening.
- Drag a card to carry that card and all cards above it. Drop on a stack to attempt the model's stacking rules; drop on empty board to split/move the tail. A rejected merge stays in its original location. Releasing over a UI panel cancels the drag.
- Drop a single equipment card onto a character to equip it. Unequip returns its items to the board. Select an enemy and choose Engage selected enemy to start combat with the nearest available friendly. Combatants remain visible when detached from stacks; their health and combat stats are shown in inspection.
- Select a card to inspect its source description and runtime health/food/durability. Sell card and sell stack are separate commands.
- Space toggles pause. Buttons set speed. WASD pans the camera; mouse wheel zooms.
- Main's shop is resolved from its `TradeManager.offeredPacks`, including supported prefab overrides. It does not sell every pack in the catalog. Locks use completed quest count; buying uses available coins.
- End day feeds villagers; at automatic day-end choose Feed villagers. Sell excess cards before Start next day. Starvation can end the game.
- Quests displays active Main quests and completion count. Recipes only displays discovered recipes.
- Save writes the current game; Save & title refuses to close on save failure. New game does not immediately overwrite an existing disk save. Continue does not advance time while on the title.

## Automated checks

```sh
bash tools/test_godot.sh res://tests/godot/test_ui_smoke.gd
```

The runner uses temporary HOME/XDG directories, avoiding the player's saves. With data, this checks title/new/continue, source starter opening, generated card nodes, stack/craft/split integration, inspection, pause, sale, recipe ledger, save/restore, repeated new-game view cleanup, day feeding/capacity/continuation, equipment drops, combat engagement, equipment/combat restoration and failed Continue preservation and failed-save refusal to leave the live board. Without data it explicitly checks the blocked/missing-data path instead. The output distinguishes these runs. This headless test is not mouse/visual acceptance.

## Manual acceptance still required

- Launch at 1440×900 and 1280×800: text legibility, clipping, scrollable eight-vendor shop, orthographic card labels, exposed stack headers.
- Open all starter slots. Drag Villager onto Berry Bush, observe recipe progress, pause/resume, wait for food, then split the villager tail.
- Try disallowed stack pairs. Release a dragged card over each UI panel, then drag again; there should be no stuck mouse state.
- Pan and zoom, then drag near the board edge. Verify all created cards remain accessible.
- Save, return to title, Continue twice, and New game. Verify no stale card titles or invisible reused card nodes. Check corrupt-primary backup recovery separately with disposable saves.
- Feed with enough and insufficient food; exceed capacity and sell down; verify next-day and game-over flows.
- Equip and unequip an item; check class-change labels and combat stats. Engage an enemy, pause, save/continue mid-fight, and verify deaths and returned survivors.
- Check vendor locks, insufficient funds, repeated buys, all quest text and discovered recipe scrolling against source data.

## Known scope limits

The UI is a new layout, not a reproduction of the Unity Title/Main/Island composition. Only Main starts here; Island/travel, encounter presentation, original animations, audio, cursor effects and original art are not implemented in this shell. Combat uses an explicit engagement button, not source-equivalent automatic overlap detection or animated battle presentation. Equipment has basic drop/unequip controls, not source-equivalent equipment slot artwork. Buying currently provides a whole-price button, not a drag-to-vendor installment UI. Selling is through explicit controls, not a 3D buyer drop zone. No Unity runtime was launched.

## Latest automated result

Godot 4.6.3: 61/61 real-data UI smoke checks passed after combat/equipment integration. Earlier missing-data branch: 4/4 passed. Main scene launched headlessly without script errors. No display server was available for screenshot capture or human visual/input acceptance. These results are separate from visual parity.

## Subsequent integrated features

Main/Island travel is now connected to actual TravelRecipe completion. Scene
vendors, quests and persisted clocks change together. Save/Continue uses the
multi-scene campaign envelope, including validated legacy session adoption.
Friendly mode filters aggressive encounters. Daily encounters are connected after
feeding/selling. Currency stacks can be dropped on chests and a selected sole
chest can withdraw coins. Optional private original card art, prefab colors and
collider sizes now bind to views; missing media does not create fake source art.
These updates supersede the earlier Main-only/no-travel limits, but not the
unverified visual/manual-input acceptance boundary.
