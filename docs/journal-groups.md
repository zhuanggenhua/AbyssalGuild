# Journal groups

`scripts/ui/journal_groups.gd` produces presentation-only descriptors from the catalog and current session. No source code or assets are embedded in this helper.

Static references: source `RecipesView`, `QuestsView`, `MenuView`, and the imported `UIRoot` view metadata.

- Recipes use numeric category order, then case-insensitive display-name order. Only discovered recipes with a valid resulting card appear. Category captions resolve through the imported enum; empty categories are hidden. The row shows the resulting card and ingredients.
- Quests use the current scene's configured group order and first group membership. Active and completed instances remain together under their source group, with completed instances marked `√`. Initial construction follows source insertion immediately after the group header (reverse completed-then-active instance iteration), not alphabetical ordering. A presentation-only per-scene order then retains existing rows on completion and inserts newly observed activations first. This transient order resets with the session/scene and is never written into game saves.
- Headers start expanded. Tab changes, read-state refreshes, discoveries, and quest completion do not reset expansion. Keys separate recipe categories and scene-specific quest groups. A new session or scene transition resets all expansion, including recipe categories, matching source UIRoot recreation. Collapse is transient UI state, never saved as game progress.
- Native RichTextLabel metadata distinguishes typed group headers from raw collection IDs. Only currently rendered headers can toggle; only visible rows can mark an item seen. Headers never mark read, and collapsed rows are excluded from the hover allow-list. Foreign, malformed, other-tab, and hidden-journal metadata are ignored.
- Header color comes from the appropriate imported UIRoot view, with a neutral fallback for synthetic/public fixtures.

Validation: `tests/godot/test_journal_groups.gd` always tests pure ordering/filtering with synthetic data, then explicitly skips private integration when the import is absent. With the private import it also tests headless native signal integration, including collapsed discovery, completed history, tabs, scene replacement, new sessions, header tint, and read-state guards. Regression suites: `test_trade_collection_ui.gd` and `test_card_feedback_board.gd`. The trade fixture deliberately selects a recipe with a resulting card; exploration/null-result recipes do not have source recipe buttons.

No Unity launch, windowed acceptance, or pixel-perfect layout claim is made. Native rows retain inline description/progress/ingredients rather than the source hover-info panel geometry. Locale-specific .NET collation is not emulated; current imported display names use ordinary case-insensitive text ordering.
