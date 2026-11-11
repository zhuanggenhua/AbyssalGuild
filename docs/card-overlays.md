# Card status labels and compact equipment panel

This slice adds the source-referenced sell-price, current nutrition and current
health displays, plus the compact equipment occupancy panel. It does not add the
source's expanded floating equipment-card interaction.

## Static findings and private metadata

Reference inputs are the card prefabs, CardInstance's stat-display updates,
CardEquipper, ChestLogic, EquipmentPanel, its FBX/material and its shader graph,
all from the source locked in `docs/source-lock.json`. No Unity process was run.

The importer follows serialized component references, not child names or category
assumptions. A source card displays only the fields wired in its prefab. Price is
the definition's sell price even when its sellable flag is false; a chest overrides
that display with stored coins. Health and nutrition use current instance values,
including zero. Equipping does not add equipment sell prices to this number.

The text RectTransforms are direct children of a plain Transform. Their serialized
local X/Y values are not their resolved label locations: anchored X/Y define the
horizontal icon placement and elevation, while local Z supplies the board-plane
position. The new helper handles this specific parent case and refuses to guess
nested RectTransform layout. It preserves the source label rectangles and colors
in the private manifest. Existing title metadata also benefits from this anchor
resolution when its explicit reference is present.

The character's EquipmentPanel component reference identifies its owner, mesh,
material and transform chain. Its metadata, all original media and the regenerated
manifest remain under ignored private input paths. Public files contain only
independently written adapters, shaders, synthetic tests and documentation.

## Runtime behavior

CardView.configure remains compatible. It creates referenced numeric labels and
an optional panel; CardView.update_state receives a full display snapshot:

- `health`, `nutrition`, `sell_price`: current display values.
- `price_override`: optional text, used for chest coins. Omission or null clears a
  previous override, avoiding stale text after reuse or definition changes.
- `equipment_slots`: array of source slot integers: Weapon, Armor, Accessory in
  their existing order. Invalid entries are ignored. Omitting slots clears them.

Each update mutates the existing nodes without recreating them. Label3D uses
Godot font metrics to fit numeric text within the imported rectangle. This is
explicitly not TextMeshPro font, baseline, auto-sizing or rasterization parity.
Original colors are used with source card materials; generated card fallback uses
dark text and a raised label plane so numbers remain readable.

The compact panel is hidden when no valid slots are occupied. Its actual private
FBX uses the same handedness bridge as card meshes and retains its own source
pose. The independent, opaque, double-sided unlit shader splits horizontal U into
three bands, chooses active/inactive icon tint from occupancy, and blends the
private icon atlas over the source base color using the atlas alpha. Material
properties unused by the audited source graph are not introduced into the blend.
Panel meshes do not cast shadows.

If the panel pose/size metadata exists but its FBX cache, recognized shader or
texture does not, a clearly generated three-segment occupancy indicator provides
a functional fallback. No source footprint is guessed if dimensions or pose are
missing. Neither the source nor generated compact panel adds an input collider
in this slice, so it does not intercept card/board clicks.

Expanded equipment interaction is now implemented separately in
`equipment-display.md` and `equipment-board-ui.md`: source toggle/day/outside-click
rules, slot poses and unequip-drag are covered. The standalone overlay remains
responsible only for compact occupancy and live labels. Cosmetic Perlin motion
and typography still do not claim exact Unity rendering.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_card_visual_metadata.py' -v
bash tools/test_godot.sh res://tests/godot/test_card_overlays.gd
```

Five synthetic Python tests verify explicit references, anchored coordinate
resolution, no mutation, unknown/nested-parent rejection and correct panel owner
selection. The Godot suite covers label values/positions/colors, zero/negative
values, long-number fitting, chest override clearing, all three slot mappings,
repeated updates, source and missing-cache fallback paths, material parameters
and CPU composition reference samples.

The private branch verifies every configured scene label and panel, comparing
positions to private metadata. Without imported FBX cache it checks the fallback
and explicitly skips the original mesh branch. With cache it checks actual panel
bounds, UV direction, source pose and texture binding. Use the real-project
headless command and writable HOME/XDG setup in `docs/card-mesh-binding.md`,
substituting `test_card_overlays.gd` as the script.

No GPU shader, screenshot, pixel comparison or human mouse/visual acceptance was
performed. Headless resource/logic checks do not establish rendered parity.
