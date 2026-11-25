# Source-order vendor payment integration

`Session.pay_vendor` now implements the source `PackVendor.CanTrade` and
`ProcessTransaction` order rather than treating payment as a generic forward
array deduction. Only this Session method changed in this slice. Whole-price
`buy_pack` remains a separate convenience path.

- Validate the complete stack before mutation: each member must exist and be a
  Currency-category card or an actual chest containing at least one coin.
  A nonchest's stored balance is not valid payment. Currency from another scene
  remains valid because source tests category, not the scene currency GUID.
- Source `BottomCard` is the last array member. Consume last-first and stop once
  the remaining price is paid. A consumed coin cancels active crafting on the
  dropped stack, matching `CardStack.DestroyCard`.
- Withdraw only the amount needed from a chest. The chest itself stays in place;
  if it empties before the price is met, stop rather than skipping to cards below
  it. As in `ChestLogic.TryWithdrawCoin(false)`, unresolved scene currency means
  no withdrawal, even though `CanTrade` accepted the nonempty chest.
- Spawn purchased packs through the existing centralized factory and source
  vendor-position adapter. Reset paid amount, publish `pack_purchased`, then the
  final stats notification only if coins were consumed or withdrawn. Pack creation
  keeps its existing distinction from ordinary `card_created` events.

## Return and UI contract

The existing `{accepted, paid, pack_id}` fields are preserved. `terminal` is added:
true only when the original dropped-stack object is empty after all synchronous
factory/transaction side effects. Rejected transactions return false. This is the
source `TradeZone.TryTradeAndConsumeStack` meaning, not merely “payment accepted.”

A partial installment consisting only of coins can be terminal even without a
purchase. A purchase via chest or with extra coins can be nonterminal. The UI must
continue its equipment/combat/placement fallback on nonterminal outcomes using
remaining cards, and stop on terminal outcomes. A zero-price pack leaves its
payment stack intact. Current completed-quest gating is retained; source sticky
activation/nearest physical trade zone selection belongs to the view integration.

`trade_layout.payment_plan` remains a pure geometry/integration aid. For chest
plans, callers must also ensure the scene currency resolves before applying a
withdrawal. `Session.pay_vendor` performs that check directly and is the mutation
entry point. No category-wide stats or buying-price changes were made.

## Verification

Godot 4.6.3 `test_vendor_payment.gd`: 20/20, runnable without private data. Covers
partial installments, last-first order, foreign currency, fake storage rejection,
empty chest whole-stack rejection, chest blocking/order, craft cancellation,
quest locks, zero-price packs, unresolved chest currency, source event order,
RNG preservation, centralized factory invocation, and terminal state after a
synchronous factory callback consumes a remaining payment card.

Prior world rules 76/76, trade currency 40/40, scene spawn 28/28 and trade layout
61/61 remain regression targets. These tests do not claim rendered trade zones,
mouse acceptance, or Unity runtime parity. No original source/assets were copied.

Final regression: all four focused suites above passed, and `tools/test_all.sh`
completed successfully with no script errors, including Python 66, UI 136,
combat-board 40, save-slot 40, save-codec 381 and the existing gameplay suites.
The dedicated new vendor-payment test must also be included when extending the
aggregate runner; it was executed separately for this change.

### Buyer: live spawn origin during board contraction

`CardBuyer.ProcessTransaction` evaluates `TradeZone.spawnPosition` on each
coin creation, after destroying the sold cards. A sale can therefore move its
own payout point: the authored Yard provides +4 capacity and pays three coins;
the first coin publishes the reduced snapshot, so the buyer header moves
before coin two. The requested origins are old, new, new, independent of
attachment or final overlap positions. An ordinary two-coin Plank sale keeps
the same origin for both. The licensed headless Board test records requests
before the existing selector and does not assert native Unity pixel parity.
## Physical trade now preserves the missing zone feedback

Checked against locked StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:
`TradeZone.TryTradeAndConsumeStack` instantiates its own Puff at the zone
transform **after validation but before** the buyer/vendor mutates payment. It
does not use the held card or payout spawn pose. `PuffParticle.Awake` requests
Puff audio immediately. The Main/Island Buyer and PackVendor component
references resolve to the same prefab GUID **and component ID** as each scene's
active CardSettings Puff, so the existing Puff renderer and lifecycle can be
reused. Missing or different source references do not borrow card effects.
No private prefab, art, or particle data is included in this change.

Only Board's physical drop supplies the explicitly resolved source position.
Buyer and pack vendor emit a model presentation request after the existing full
validation, before sale notification or withdrawal. This preserves the separate
chest withdrawal Puffs, including their post-decrement order. The request adds
nothing to saved state, and uses the existing independent presentation RNG.
The standard optional-resource behavior still applies: a valid cue requests its
sound even if the renderer cannot build the visual.

`PackVendor.ProcessTransaction` then reports a completed purchase if applicable,
notifies final stats on a balance change, updates its visible price and requests
CashRegister even on an accepted installment that has not yet bought a pack.
Godot now issues that cue at the accepted physical route after settlement and
price refresh, once for terminal and nonterminal results alike, rather than on
the generic `pack_purchased` domain event. A rejected drop has neither zone Puff
nor register; repeat pointer-up does not replay them. The separate native
convenience Buy button retains one success cue without pretending to hit a zone.
Buyer proceeds with its existing Coins routing and payout, unaffected.

The locked-data Board trade fixture asserts live price at the moment of the
register request, actual source-zone origin versus payout location, and
zone/chest Puff ordering; the drag fixture exercises a real board pick, held
motion into the header and captured pointer-up. Existing Puff renderer/model
tests exercise optional resource behavior separately. These checks verify
event/renderer setup, not audible playback, Unity runtime order across
different systems, or framebuffer parity.

### Vendor discovery display follows the owned source notifications

The source subscribes to `CraftingManager.OnRecipeDiscovered` and
`CardManager.OnStatsChanged` and refreshes only the active vendor's tracker.
Update the mounted tracker at those notifications rather than waiting for the
deferred collection and journal refresh. The tracker update must not touch
the current price/title, move zones, or run a transaction. In particular
`PackVendor.ProcessTransaction` still refreshes the price after stats and before
CashRegister. Locked zones are unchanged. The owned factory and a real pack
recipe draw verify both live captions at the event boundary.
