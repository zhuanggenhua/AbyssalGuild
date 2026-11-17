# Journal body ownership (bounded migration)

Baseline: public `294e3372d1e7e0f0c32e8c65595739e98ec3db84`; source
`zhuanggenhua/CardLoop@a11a89b04cea8370476f2559b639bb9b4cbc08d8`.

## Source evidence

`Assets/StackCraft/Prefabs/UI/UIRoot.prefab` contains two independent active
view objects, not one content object rebuilt when selecting tabs:

| Owner | MenuView component | Content RectTransform | ScrollRect | Viewport |
| --- | --- | --- | --- | --- |
| Quests | 6882295174205039664 | 1761706873010989585 | 2388268852447840646 | 41694486927967532 |
| Recipes | 2889184954171660070 | 8320187493270481984 | 4221608159763471696 | 6761228442597916361 |

The Quests CanvasGroup starts alpha 1 / blocksRaycasts 1; Recipes starts 0 / 0.
`Assets/StackCraft/Scripts/UI/Menu/MenuView.cs::ToggleView` changes alpha and
raycast participation, never destroys content or disables its GameObject.
Each view's `Awake` also creates its own info requester key.
`QuestsView.cs::Start` subscribes activation/completion independently of tab
visibility, with teardown only at `OnDestroy`. `RecipesView.cs::Start` similarly
subscribes discovery. `HandleRecipeDiscovered` reveals the category header and
makes the discovered button active only if that category is expanded. A hidden
recipe view must therefore receive discovery, including collapsed categories.

## Bounded implementation

`board.gd` now keeps two persistent RichTextLabel bodies with independent native
scrollbars, content signatures, info and visible-row/group metadata. Selecting a
tab changes visibility/input participation and the existing public `ledger`,
`ledger_key`, `ledger_info`, `ledger_visible_ids` and `ledger_visible_groups`
references. It no longer transfers the previously selected body's offset.
Both bodies refresh from the existing source-shaped descriptors on presentation
events, including while hidden. Hidden discovery does not expand categories or
mark content read. Each view's hover exit clears only its own requester; stale
hidden hover/click signals cannot act on the selected view.

The fresh gameplay-scene entry (`_enter_game`, used by new game/continue/travel)
restores authored Quests selection and invalidates the journal lifecycle. The
next refresh resets both offsets, both requesters, signatures and expansion.
Ordinary tab/drawer toggles retain the body instances and offsets. Direct
`active_tab` assignments followed by refresh retain compatibility; unknown
public tab requests are ignored.

## Evidence and limits

`test_journal_body_ownership.gd` uses the actual Board controls with a synthetic
long-content fixture: distinct nonzero offsets 120/240, repeated reentry, body
identity, independent hover ownership, hidden completion, hidden discovery in a
collapsed category, hidden content refresh, drawer closure/reopening and fresh
lifecycle reset. With private source data it additionally calls real `start_new`
and verifies authored selection and reset. It runs in the public aggregate; the
strict imported runner also requires the private-lifecycle marker and equal
passed/total counts (no private skip accepted).

This is body **ownership/lifecycle**, not a new renderer. The previous body
geometry, RichTextLabel item rendering and font-binding policy are retained.
It does not certify source ScrollRect inertia/elasticity/wheel or drag behavior,
TMP line/baseline/SDF pixel parity, a natural full-game playthrough or synchronized
Unity/Godot screenshots. Header Toggle graphics, separate label ColorBlock tint,
ToggleGroup input/transition semantics remain a separate source-backed slice.
