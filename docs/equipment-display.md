# Expanded equipment display controller

This is the view/controller layer for the source equipment panel. It uses private
serialized attachment points rather than a replacement layout. Board input and
model unequip integration are separate callers of this controller.

## Static source audit

All paths below refer to the locked source, not files redistributed by this
repository. Unity was not launched.

- `Scripts/Card/UI/EquipmentPanel.cs`: Awake initializes slot state; Start hides
  attached cards. AttachEquipment preserves scale while setting the parent,
  source slot local position and identity local rotation, then opens the panel.
  DetachEquipment restores visibility and identity world rotation. Panel clicks
  toggle while clickable; the handler does not restrict the mouse button.
- The same component checks left-button presses for outside close. Its own panel
  is exempt, as is **any** equipment card, not only an item owned by this panel.
  Clicking another panel closes the first. Day-end notification closes expanded
  cards and locks toggling; day-start notification only unlocks toggling.
- The compact panel's renderer/collider depend on having equipment, not on its
  expanded state or day click lock.
- `Scripts/Card/Components/CardController.cs`: a left press on equipped gear first
  checks general input enablement, unequips its slot, and starts dragging. This
  branch precedes combat handling. It does not add a wearer-combat or wearer-drag
  restriction. Ordinary combat-card dragging retains its separate source gates.
- `Scripts/Card/CardInstance.cs`, SetVisible: visible equipment must also have an
  enabled card collider and labels; hidden equipment must not intercept clicks.
- `Scripts/Card/CardManager.cs`: restored equipment is attached during scene/card
  restoration. The controller's first snapshot starts closed, reflecting the
  source panel's startup HideCards. Later attachments/replacements open it.
- `Scripts/Core/TimeManager.cs`: source orbit uses scaled Unity Time.time, so it
  freezes at zero time scale and accelerates at the selected pace.

The private metadata helper retains all three explicit attach points plus orbit
radius and speed from the referenced panel component. Missing or invalid fields
are rejected; no layout or animation parameters are guessed. The original
prefab, models, material, textures and generated records remain private.

## Controller contract

`equipment_display_controller.gd` does not mutate the equipment model or consume
its random generator. Its caller supplies:

- `sync(equipped, views, metadata, day_open)`: equipment owner-to-slot maps, card
  views, owner-to-private-panel metadata, and day click state. Call after ordinary
  board card positioning/visibility. Unchanged snapshots keep user expansion
  choices and do not draw random numbers. Added/replaced equipment opens an
  already initialized panel. Class-change view reconstruction keeps the same
  owner's controller state.
- `advance(scaled_delta)`: call once per rendered frame with scaled elapsed time.
  Pauses/modal time locks pass zero. Non-finite or negative deltas are ignored.
- `pointer_down(panel_owner, hit_equipment_card)`: call for left presses only to
  apply source outside-close rules.
- `click_panel(owner)`: toggle a non-empty, day-enabled panel on a genuine click.
  Panel click must not begin dragging its wearer.
- `hover_names(owner, names)`: ordered equipped display names for optional hover
  presentation. `is_expanded(owner)` is available for input/tests.
- `reset()`: remove controller-created pick targets/state during session changes.

Panel pick bodies carry `equipment_panel_owner` and `card_id` metadata. Their
footprint/center come from the private collider record; a minimum Godot pick
thickness replaces the source zero-height collider. Occupied panels remain
pickable when closed or day-locked, as in the source; the controller gates toggles.

Expanded gear remains owned by the board's existing view collection. The
controller composes wearer/panel/slot transforms to obtain the same source pose
instead of physically reparenting views. This avoids destroying equipment views
when a class-changing item causes the wearer view to be rebuilt. Attachment
preserves world scale and resets local rotation. Hidden gear snaps to its exact
base attachment point and loses its card collision layer. Detaching restores
visibility/collision and identity world rotation; the board/model controls its
new stack position.

When beginning a drag from equipped gear, callers must capture its current view
world position **before** the model unequip operation. The current model returns
it near the wearer; overwrite that temporary stack/card position with the captured
board-plane position before dragging, preserving the source pickup origin.

## Deliberate cross-engine differences

Source AttachEquipment draws two Unity global Random.Range values in [0, 1000]
for noise phase offsets. This adapter draws equivalent phase ranges from a
separate presentation-only RNG on attachment. Ordinary sync and animation frames
consume no random draws. It intentionally does not reproduce Unity global-RNG
consumption or disturb gameplay/save RNG continuity.

Source samples Mathf.PerlinNoise(time*speed+offsetX, 0) and
Mathf.PerlinNoise(0, time*speed+offsetZ), maps the result to a signed range, and
multiplies by radius. The adapter uses Godot FastNoiseLite Perlin, with fractal
layers disabled and unit frequency, preserving sample-axis layout, scaled time,
source radius, source speed and reflected world Z. Exact Unity noise values,
phases, animation trajectories and cross-engine replay equivalence are not
claimed. This is distinct from using invented attachment positions.

## Tests and limits

```sh
python3 -m unittest discover -s tests -p 'test_equipment_interaction_metadata.py' -v
bash tools/test_godot.sh res://tests/godot/test_equipment_display.gd
```

Synthetic checks cover startup/restore, attach/open, close/reopen, multiple
panels, any-equipment outside-click exemption, day gates, world pose and scale,
collider size/center/visibility, no duplicate pick bodies, class-change rebuild,
detach visibility, bounded scaled-time animation, no frame RNG consumption,
missing metadata and reset. Private checks compare all three source slot base
poses and animation parameters with the imported metadata. Without private
metadata that branch explicitly skips.

Board routing/drag behavior should also be exercised in its integration suite.
These checks do not prove rendered animation, original font fidelity, GPU shader
behavior, pointer interaction on a real display, or pixel parity. No such manual
or GPU acceptance is claimed.
