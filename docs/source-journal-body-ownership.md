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

`board.gd` now keeps two persistent ScrollRect hosts with independent vertical
motion, content signatures, info and visible-row/group metadata. RichTextLabel
is a non-scrolling child of each content row; neither authored view has a scrollbar. Selecting a
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

The host only reports an admitted source layout after resolving each ScrollRect and
MenuView to the same local Content reference and the active direct Viewport /
Content parent chain under MenuPanel. The admitted branch has an axis-aligned
full-stretch viewport with the authored hidden Mask graphic, top-pivot non-scaled
Content, no scrollbar references, and top-left VerticalLayoutGroup plus
preferred-height ContentSizeFitter. Admitted motion and row padding / spacing
flow from serialized fields. An incomplete or incompatible record uses the
explicit unverified fallback, clearing any formerly admitted motion state on
replacement. Geometry admission does not prove how Unity rasterizes the mask.

## Evidence and limits

`test_journal_body_ownership.gd` uses the actual Board controls with a synthetic
long-content fixture: distinct nonzero offsets 120/240, repeated reentry, body
identity, independent hover ownership, hidden completion, hidden discovery in a
collapsed category, hidden content refresh, drawer closure/reopening and fresh
lifecycle reset. With private source data it additionally calls real `start_new`
and verifies authored selection and reset. It runs in the public aggregate; the
strict imported runner also requires the private-lifecycle marker and equal
passed/total counts (no private skip accepted).

The synthetic host test verifies admission rejection, invalid replacement,
wheel/drag and unscaled inertia. The private Board test verifies both separately
resolved original views at startup as well as GUI event routing and normal
ownership. Native row shaping is still deliberately marked fallback, not TMP
preferred size, baseline or SDF parity. Mask edge pixels, full-game playthrough
and synchronized Unity/Godot screenshots remain unverified.

The pinned `MenuView` declares U+25BA (►) and U+25BC (▼) for group state,
U+2022 (•) for rows, and a plain space followed by red U+25CF (●) for unread
rows. Quests append U+221A (√) before that unread suffix. The source-authored
strings do not prove how a player font resolves those glyphs. In this import,
the project-default TMP setting points to a font not present in the locked
source tree; the separately available LiberationSans is not that reference.
The production view stays on its explicitly unverified native metrics instead
of using another project’s font as supposed source parity.

### Board mouse processing frame

The project's Input System 1.19.0 module processes one mouse raycast per
frame in left, right, middle order. Its press and drag captures are per
button, but the click receiver and eligibility are shared. A pointer exit
does not itself discard eligibility. A release consumes eligibility, even
on a mismatched current hit; a fresh press replaces the shared receiver.
Each button releases before its drag phase, so motion on an earlier frame
and movement coincident with release are not interchangeable.

The Board samples physical events without consuming camera, modal, or wheel
routing, then processes them once against the final current hit. Both tabs
share one model; item rows participate in hit matching even if they have no
click action. Only the left slot drives the ScrollRect captured at press.
Layout at release is rechecked, including clipping and later visible
blockers; the outbound fader is a blocker, the inbound fader is not.
The header remains a separate left-only Toggle, and touch-emulated events
stay on the previous compatibility route rather than joining the real mouse
model. Pen, native multi-touch and exact live Unity frame comparison are
still outside this slice. Only a positively admitted original ScrollRect
uses the framed path. The native suite includes actual Viewport input and
initialized Board processing; the reference test covers the order-sensitive
combinations without depending on rendering.

Reference: [Input module, pinned 1.19.0](https://github.com/Unity-Technologies/InputSystem/blob/ca8d898356596a91bda6505e506cc1a4bb3a9fa6/Packages/com.unity.inputsystem/InputSystem/Plugins/UI/InputSystemUIInputModule.cs#L430-L479),
[shared click transitions](https://github.com/Unity-Technologies/InputSystem/blob/ca8d898356596a91bda6505e506cc1a4bb3a9fa6/Packages/com.unity.inputsystem/InputSystem/Plugins/UI/InputSystemUIInputModule.cs#L596-L730),
[per-button state](https://github.com/Unity-Technologies/InputSystem/blob/ca8d898356596a91bda6505e506cc1a4bb3a9fa6/Packages/com.unity.inputsystem/InputSystem/Plugins/UI/PointerModel.cs#L237-L269).

### Combined wheel and button frames

The source pointer is sampled before any input-specific callback can move
the content. Physical wheel events contribute signed raw ticks to the
current frame; horizontal/vertical dominance is resolved after summing,
and equal opposite ticks cancel. Dispatch follows Unity's left button and
drag, then wheel, then right and middle. Thus a wheel shift does not
retroactively change the captured click's current receiver in that frame.
Pointer-enter resolves the same authored ScrollRect through clipped row or
padding; covered surfaces do not receive Journal scrolling. Header and
fallback input ownership are unchanged. The Board camera still receives
its separate existing raw route; combinations at camera zoom clamps and
source update phase are not validated by these Journal checks.

The Journal host's unscaled motion step runs after the Board frame sample.
With a held left drag, that step computes velocity from the combined drag
and wheel displacement. With a left release in that frame, it instead
runs inertia (inside bounds) or the source wheel-adjusted spring (outside
bounds). Tests also send wheel to Recipes while a previously captured
Quests drag is still active; each host receives only its own action.

### 同一滚轮输入的独立相机更新

锁定 Unity `com.unity.inputsystem` 1.19.0 默认动态更新、UniformAcrossAllPlatforms，
在每次更新前清除 Mouse.scroll、逐事件合计；原项目未覆盖这一模式。Windows 一格
滚轮以归一化的 1 读取，不是旧原生计数 120；Godot 每个按下事件保留带符号 factor。
Journal 按自己的二维轴选择、翻转和 ScrollRect 灵敏度 6 更新，CameraController
独立读取同帧纵轴合计，在平移后和 unscaled SmoothDamp 前仅处理一次。相反滚轮先
抵消，小滚轮合计才过阈值，越界时拒绝整个缩放量，成功才夹取 XZ。GUI 消费不排除
相机观测；不在 unhandled 输入重复分派。原生触控不冒充 Mouse.scroll。

当前仅更改相机滚轮批次：原有物理像素平移由现有路径保持，并未迁移所有鼠标平移
边缘到统一帧。旅行淡出的原有严格迁移护栏仍有效，只有同一会话和淡出代次接纳的
有效合计才授予离场平滑；新场景与新代次不会承接积压。
