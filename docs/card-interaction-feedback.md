# Card hover, drag targets, and crafting bars

This is an independent Godot presentation implementation, statically checked
against the locked StackCraft `Assets/StackCraft` source at
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. Unity was not run. No original
scripts, prefabs, fonts, shaders, or media were copied into this change.

## Source behavior

- `Scripts/Card/CardInstance.cs`, `GetInfo`: an active craft takes priority and
  shows recipe display name plus remaining seconds to one decimal. Otherwise a
  multiple-card stack groups effective definitions in first-occurrence order,
  not matching display names. A singleton shows its display name and description.
  Only category Character appends current/effective maximum health. Characters
  with combat type other than None also show the type and eight effective stats
  from `Scripts/Combat/CombatStats.cs`: maximum health, attack, defense, attack
  speed, accuracy, dodge, critical chance, critical multiplier. Mobs do not gain
  an invented stat tooltip. Unstacked equipped/combat cards return no card hover.
- This empty stackless path is explicit: `CardInstance.GetInfo` returns immediately
  when `Stack == null`. `CardEquipment.OnEquipped` and `CardCombatant.EnterCombat`
  clear that stack reference. Expanding gear visibility does not restore a stack.
  `Scripts/Card/UI/EquipmentPanel.cs` has a DIFFERENT hover method: header
  `Equipments`, with equipped display names as bullet lines in attachment order.
  That panel route does not show the per-card description or combat-stat block.
- Hover refreshes during a craft and clears on exit/disable. The native adapter
  reads fresh snapshots, so it also reflects health/class/equipment changes.
- `Scripts/UI/InfoPanel.cs`: Hover has lower priority than Sequence and Modal.
  Hover must never replace feeding/selling/encounter instructions or their action
  controls. The helper does not own the existing board's modal requests.
- `Scripts/Card/CardManager.cs`, `HighlightStackableStacks`: highlight the last
  array member, called BottomCard by the source. Exclude the lifted card, its
  stack, and every active crafting stack. Matrix eligibility is directional and
  must come from the existing model; highlighting is not a radius query. The
  source highlight is intentionally narrower than drop acceptance: an excess
  ingredient may join an active recipe without that stack being highlighted.
- `Scripts/Crafting/CraftingManager.cs`, `Scripts/Crafting/CraftingTask.cs`, and
  `Scripts/UI/ProgressUI.cs`: one bar per active task, progress/duration, positioned
  at the stack target plus source offset `(0,0,0.55)`. It does not follow the last
  member's raised/slid pose. Pausing keeps the same visible ratio. Completion or
  cancellation removes the task UI. Source TopCard means the FIRST array member.
- `CardController.OnPointerDown` splits a lifted tail and pauses the original
  registered task without ingredient revalidation. `CraftingManager.Update`
  continues updating its UI while paused; `CardInstance.GetInfo` likewise trusts
  that task. Consequently the temporarily incomplete original stack keeps its
  recipe hover and frozen bar. The lifted tail has no recipe UI of its own.
  Returning the tail resumes the original task; a different release validates
  the remainder and may cancel it. Presentation must not perform that validation.
- The locked `Prefabs/UI/ProgressUI.prefab` specifies a `0.8 × 0.05` rectangle,
  left-to-right horizontal fill, golden fill, and translucent dark background.

## Independent APIs

`scripts/ui/card_interaction_descriptors.gd` has no nodes, clock, RNG, or writes
to model/save state:

- `hover_info(session, card_id, enabled=true) -> Dictionary`: `header`, `body`,
  `kind` (`card`, `stack`, `craft`), `card_id`, and `stack_id`; empty means clear.
- `equipment_panel_info(session, owner_id, enabled=true) -> Dictionary`: source
  panel header/bullet body with `kind=equipment_panel` and `owner_id`. The board
  picker already provides distinct `panel_owner` metadata. Only live items whose
  ownership agrees with that owner are listed; stale/empty/blocked panels clear.
- `drag_targets(session, lifted_card_id, qualified_stack_ids, enabled=true)`:
  dictionary keyed by target card ID with `card_id` and `stack_id`. Supply only
  model-qualified stack IDs. The helper rechecks `session.can_move_to_stack`
  to reject stale candidates, then applies the source crafting exclusion. It
  neither selects a nearest destination nor performs equipment/combat drops.
- `crafting_progress(session, enabled=true)`: dictionary keyed by stack ID, with
  `top_card_id`, `recipe_guid`, `elapsed`, `duration`, `remaining`, `ratio`,
  `paused`, and `anchor`. The anchor is in SOURCE coordinates; the renderer alone
  reflects Z. Duration must be finite and positive, progress finite, all members
  live and still in that stack, and recipe metadata present. Invalid numeric or
  missing task metadata is hidden, never repaired or rerolled. Ratios and remaining
  seconds are
  bounded for a transient completed/invalid numeric snapshot without changing
  model time. Task existence is the model's `recipe_guid`, NOT a fresh ingredient
  match; a paused original can legitimately lack the ingredients currently held.
- `apply_target_highlights(views, targets)` applies a full snapshot and clears
  omitted IDs. `CardView.set_drag_target(bool)` lazily creates an independent
  outline, never altering selected-card emission, hurt flash, or picking shapes.

`scripts/ui/card_hover_view.gd` is a native Panel with `set_descriptor(dict)` and
`set_bounds(Rect2, font_scale=1)`. Empty descriptor clears and hides immediately.
It shows literal text, clips a two-line header, and preserves the entire body in
a bounded scroll area. Repeating an unchanged descriptor preserves scroll. Bounds
are HUD-logical coordinates, so viewport canvas scaling is not applied twice.

`scripts/ui/craft_progress_view.gd` owns generated world bars. Call
`sync(descriptors)` after model changes or `reset()` at a lifecycle boundary.
Omitted/invalid tasks are hidden and detached immediately, then freed. Repeated
snapshots reuse nodes. There is no local progress animation or game-clock tick.

## Board integration contract

The initial change deliberately does NOT edit `board.gd` or model/import code.
These helpers alone are not a claim that live board integration is complete.

1. Create one hover view under the HUD and one progress view under the board.
   Give the hover view an available rectangle beside the existing action panel;
   do not overlay or replace cycle/modal buttons. Resize through `set_bounds`.
2. Resolve the current visible ray-picked card each frame when not over a menu,
   unrelated GUI panel, higher-priority sequence, or modal. Use the same pick path
   and GUI/action gates as board input. Clear on empty board, pointer exit, focus
   loss, menu/dialog open, or hidden/rebuilt/dead card. If the pointer is over the
   information panel's scroll body, retain the current valid hover so scrolling
   does not dismiss it. Route a valid `panel_owner` hit to `equipment_panel_info`;
   do not substitute that owner as the card hit. A visible expanded gear card
   itself still receives the source-empty stackless `hover_info` response.
3. Pass the resulting ID into `hover_info`; send every full result, including
   `{}`, to `set_descriptor`. Keep selected-card inspection a separate concept:
   selected-card emission and hover must not modify each other.
4. While an authorized live stack drag exists, build candidate IDs with the pure
   `session.can_move_to_stack(lifted_id, stack_id)` predicate over current stacks,
   not `_nearby_stack`, and pass them to `drag_targets`. Apply the result to ALL
   current views. An equipped/combat-only card without a stack has no candidates.
   Clear on release, cancellation, drag loss, invalid/dead source, or blocked UI.
5. Call `crafting_progress(session, board_visible)` and `progress.sync(...)` every
   presentation update. A paused game or stack keeps bars visible. A hidden board
   (title/menu/session replacement) clears bars. Day-end modal may suppress hover
   and targets while retaining frozen bars behind the modal.
6. Before travel/session restore/title transition, set the retained hovered ID to
   `-1`, clear hover/targets, and reset progress. Numeric IDs can be reused after
   load/travel, so a valid ID alone cannot identify the previous hovered object.
   Then resample the new scene. Never carry old descriptors across session swaps.
7. If a drag replaces or destroys a card view, update the full snapshot against
   the new `views` dictionary. The outline is owned by its card, so stale card
   overlays die with that view. Progress UI remains independently keyed by task.

## Explicit rendering limits

The hover panel uses Godot's native fallback font and a native screen layout, not
TextMeshPro font metrics, Unity priority-panel positioning, or original art.
The independent gold rectangular target outline follows the collider footprint,
not the Unity expanded-mesh outline shader. Its color/thickness are an explicit
native approximation, with no reuse of selection or combat materials.

Progress uses generated unshaded planes with the source prefab's measured size,
fill direction, and colors. The native board card baseline is `0.06`; the meter
uses `0.08` Y as an explicit depth-clearance approximation. It reflects the source
anchor's Z once and does not add stack-card step, drag visual offset, or card
scale. No Unity Image sprite shape, mask rasterization, or WorldCanvas shader
parity is claimed. GPU occlusion, final UI framing, font appearance, and actual
mouse/gamepad feel still require visual/manual acceptance.

## Verification

Run the dedicated checks explicitly until the integration owner adds them to the
general/private runners:

```sh
bash tools/test_godot.sh res://tests/godot/test_card_interaction_feedback.gd
bash tools/test_godot.sh res://tests/godot/test_source_card_interaction.gd
```

Godot 4.6.3 headless: 130 synthetic checks and 665 imported-source checks pass,
covering 103 real card definitions, 5 Characters, and all 90 source recipes.
Synthetic cases cover effective stats/grouping, source array orientation,
pause/invalid recipe/NaN bounds, live/dead/stale members, candidate filtering,
model snapshot and RNG immutability, full clear snapshots, repeated view reuse,
small and scaled text bounds, scroll retention, and independent selection/hurt
shader state. The synthetic suite drives actual held-tail begin/return/release
and paused game ticks, verifying that an incomplete original retains its task
hover/bar until model cancellation. It also uses real equip/unequip and combat
ownership to distinguish source-empty stackless card hover from the equipment
panel's live name list, with stale item/owner and inconsistent-stack cases.
These are model/helper/render-structure checks, not live board input or GPU/manual
acceptance. The partial-tail regression depends on the held-stack model batch.
