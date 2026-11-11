# Generated recipe-card definitions

## Source contract and defect

Static reference: the locked `Assets/StackCraft` baseline at
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`, specifically
`Scripts/Card/CardManager.cs` (`CreateRecipeCardDefinition`, `GetDefinitionById`,
`SpawnRecipeCard`), `Scripts/Pack/PackSlot.cs` (`GetRandomCard`), and
`Scripts/Crafting/CraftingManager.cs` (`GetFormattedIngredients`). Unity was not
launched, and no original source or assets are included in this change.

The source uses one scene manager's recipe-card template for pack draws,
research, and dynamic-ID restoration. The Godot research path already cloned
that template, but pack draws and save restoration each built a six-field
approximation. A real Beginning-pack draw at seed 1 reproduced the missing
ingredient description, and saving a correct research card then restoring into a
fresh catalog lost its additional template metadata.

## Implementation

`recipe_card_definition.gd` is a pure builder shared by all three paths. It
selects the named scene's `CardManager.recipeCardTemplate`, deep-clones every
field, then replaces the dynamic ID, title, and ingredient description and adds
the internal recipe GUID. Building does not register a definition, consume RNG,
allocate an instance ID, discover a recipe, or emit an event. Callers retain
those responsibilities.

- Pack discovery still precedes definition construction and spawning. Research
  still consumes inputs, chooses its candidate, spawns, then discovers.
- A selected recipe with no template produces no card. It does not silently
  borrow another scene's template or consume an extra weighted fallback draw.
- Save staging reconstructs definitions in its independent catalog with the
  saved scene's template. Only a completely valid snapshot reaches the live
  registry. Invalid active or inactive campaign scenes leave live state intact.
- Travel passes its destination scene when reconstructing a dynamic traveler.
  Restoring an inactive scene later rebuilds that scene's template metadata.
- Save version and stored instance fields are unchanged. Source template data,
  nested dictionaries, and arrays are never modified. Runtime definitions are
  still registered in the owning catalog by the spawn/restore callers.

The numeric formatting of imported ingredient counts remains unchanged from the
existing research implementation. This slice does not change text localization,
rendering, recipe discovery policy, or the save format.

## Verification

Run the source-free synthetic suite in an isolated Godot project:

```sh
bash tools/test_godot.sh res://tests/godot/test_recipe_card_definition.gd
```

It covers unequal Main/Island templates, nested-clone isolation, complete card
initialization, exact draw/ID and event order, fresh save round trips, subsequent
pack draws, real campaign transitions with a recipe traveler, inactive-scene
restoration, corrupt saves, and missing-template failures. The existing
SaveCodec synthetic fixture now explicitly supplies its scene template instead
of relying on fabricated codec defaults.

With the locally imported licensed catalog, also run:

```sh
bash tools/test_godot.sh res://tests/godot/test_source_recipe_cards.gd
```

This required-data suite checks actual Beginning-pack draws in Main and Island,
full template-field retention, fresh JSON restoration, remaining pack draws,
actual ingredient selection and partial research timers, deterministic research
completion including concurrent world production, and another fresh restore.
It fails rather than skipping when imported data is missing.

These are model-level checks. They do not claim a visual or input acceptance
pass, Unity execution, or completion of the full migration.
