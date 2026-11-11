# Convenience purchase crafting validation

This is a narrow model correction to `GameSession.buy_pack`, the native shop
convenience action that gathers payment across the board. It is distinct from
the source-style dropped-stack installment action `pay_vendor`.

## Verified failure and correction

The locked source catalog contains a ten-second Wooden Chest recipe using two
Wood cards and two Coin cards, and an Island variant using two Coral cards.
With that task at five seconds and one additional loose currency card, buying
the corresponding three-currency pack previously removed all three currency
cards but left the chest recipe running on the two Wood cards. A native snapshot
accepted that state. Advancing six seconds then produced both the purchased pack
and a free crafted chest.

The purchase now retains each consumed currency card's stack object and calls
the existing `_validate_craft` immediately after removal. An invalid task loses
its recipe, elapsed progress and paused flag before payment continues, before
any subsequent chest puff, and before the purchased pack's factory callbacks.
Validation also clears the retained object if its last card was removed and the
stack was unregistered. A still-valid excess-ingredient task retains its exact
recipe, progress and paused state.

The change does not select a replacement recipe, discover recipes, consume RNG,
publish additional signals, or change generic `_remove_card`. Craft completion
uses that helper for its own sequential ingredient consumption and must not
acquire a purchase-specific cancellation side effect.

## Source audit and native boundary

Static evidence is from `zhuanggenhua/CardLoop` revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. Paths are relative to the private
`Assets/StackCraft` source root:

- `Scripts/Card/Components/CardController.cs:77–103,175–236` splits a held tail,
  pauses its original crafting task, and later resumes or validates that original
  on ordinary release. Successful terminal actions instead stop the original.
- `Scripts/Trading/PackVendor.cs:189–268` validates the dropped payment stack,
  consumes its last currency member through `DestroyCard`, withdraws stored
  chest currency individually, creates the purchased pack, then publishes
  purchase and final stats notifications.
- `Scripts/Card/CardStack.cs:158–176` stops crafting when `DestroyCard` removes a
  card. This unconditional source cancellation remains in native `pay_vendor`.
- `Scripts/Card/Behaviors/ChestLogic.cs:106–126` withdraws stored currency without
  destroying the chest; a withdrawal puff occurs after each decrement.
- `Scripts/Crafting/CraftingManager.cs:394–411` validates remaining ingredients
  when resolving an original crafting stack after a held-tail interaction.

Whole-board `buy_pack` has no identical source transaction. Its existing payment
order and preservation of still-valid excess progress are native convenience
policies, not claims that source `DestroyCard` preserves progress. This fix only
enforces the missing membership validation for that convenience action.

## Preserved behavior

- Insufficient funds, invalid/nonpack targets and quest locks reject before any
  mutation, signal, RNG draw or validation. Existing installments reduce the
  total due. Free or fully prepaid purchases do not touch crafting inputs.
- Payment retains global card insertion order, including foreign Currency
  categories and chest balances. It does not adopt dropped-stack last-first
  ordering or stop at an emptied chest. Only the amount still owed is withdrawn.
- Spending chest storage does not change recipe membership or reset a valid
  task. The chest itself and later unneeded payment cards remain.
- Affected valid paused originals stay paused. An invalidated affected original
  is cancelled. Unaffected originals remain paused while their tail is held,
  even if their temporary split membership is incomplete.
- Spending some or all of a held tail does not consume the pointer grant or
  force terminal cleanup. The existing ordinary release/checkpoint settlement
  handles surviving members, missing members and original progress. A whole-stack
  held task is validated directly when its currency inputs are consumed.
- Central pack creation, pack purchase notification, final stats notification,
  selling/encounter callbacks and save-format version remain unchanged.

## Verification

Godot 4.6.3, through the isolated `tools/test_godot.sh` runner:

- `test_purchase_craft.gd`: **59/59** synthetic checks. Covers invalidation before
  factory and puff callbacks; no replacement selection/RNG/discovery; atomic
  rejection; installments and free purchases; partial and full chest payment;
  global currency order; excess progress; empty-stack references; untouched,
  partial, missing and whole-stack holds; paused affected originals; JSON
  round-trip and next tick; synchronous selling/encounter ordering.
- `test_purchase_craft_source.gd`: **45/45** required-private-data checks. Covers
  the actual Main Coin/Beginning and Island Coral/Survival cases, both legitimate
  source Wooden Chest recipes and vendor placement, insufficient funds, actual
  full chest funding, actual held ingredient payment and exact saved continuation.
  It fails rather than skipping when its licensed catalog is absent.
- Existing regression gates: held stack **73**, source held stack **17**,
  SaveCodec **534**, cycle save validation **144**, cycle order **45**, vendor
  payment **20**, trade currency **40**, runtime **76**, world rules **76**, all
  passing. The source-lock checker matched all **1,327** files.

The new suites were also run against the unchanged pre-fix model in a disposable
projection as negative controls: the synthetic suite fails 10 of 59 checks and
the source suite fails 4 of 45. Final focused regressions run
against a frozen copy containing only this model correction, independent of
concurrent UI/crafting work. Tests use isolated temporary user directories;
no live save files or Unity process are used. No source code or assets are
redistributed by this change. These checks do not establish mouse, rendered,
audio, Windows export or complete migration acceptance.

## Unsupported callback-mutation boundary

Chest withdrawal puffs are synchronous model events. A listener that explicitly
saves or recursively purchases inside one can observe an unfinished transaction.
An isolated probe on the unchanged pre-fix model confirms both a restorable
midpayment snapshot and recursive spending beyond the available chest balance.
The [SaveCodec contract](save-format.md) already requires frame-boundary calls,
not saves inside in-progress gameplay callbacks. Current board puff listeners
are presentation handlers and do not purchase or save; no current user-flow
violation was identified. This slice preserves event order and does not add a
general transaction guard for unsupported callback mutation. Supporting such
reentrant use would require a separate transaction/checkpoint-boundary audit.
