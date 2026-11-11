# Active-scene special recipe data

The source's live CardManager owns the recipe-card template, category-to-prefab
mapping and CardSettings reference. CardManager.CreateRecipeCardDefinition
clones that manager's template. GrowthRecipe displaces the split seed by the
seed instance's Size.x, initialized from its prefab collider width plus its
CardSettings margin. Selecting the first exported scene or first settings
asset is not equivalent.

`special_recipes.gd` now passes `session.scene_name` when resolving the manager
for dynamic recipe cards and growth displacement. Width uses the active
manager's category prefab and referenced CardSettings margin. Duplicate
category bindings keep the first nonempty binding, matching source lookup
construction. An unknown scene or missing manager never borrows another
scene's template/prefab; missing template returns -1 and missing geometry
returns zero displacement. No GameSession API or UI changes are needed.

The existing public helper arguments remain compatible through a Main default;
all runtime call sites explicitly pass the active scene. Dynamic card identity,
ingredient formatting, spawn exclusions and recipe consumption are unchanged.

`tests/godot/test_special_recipe_scenes.gd` uses only synthetic data. Island is
exported before Main, the two scenes have different template markers/prices,
different collider widths, and different settings margins. An unrelated
settings asset is deliberately first. The test performs Main → Island → Main
through real campaign travel and verifies newly created recipe cards and split
seed offsets at each destination. It also checks scene reorder, absent scenes,
missing managers, template immutability and duplicate mapping behavior.

Verified: 20 focused checks, special recipes 445, travel 35, scene spawn 28,
spawn factory 29, and save codec 381. The 20-check suite also passes in an
isolated project with no private data/assets. No Unity runtime was used.
