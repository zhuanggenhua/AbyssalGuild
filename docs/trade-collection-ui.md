# Trade zones and collection presentation

The board adapter now renders original generated plates and labels at the exact
zone transforms resolved by `TradeLayout.zones`. Main has one buyer plus eight
vendors; Island has one buyer plus one vendor. No template artwork or original UI
prefab is copied into the public view implementation.

## Trade geometry and actions

- Source X/Y/Z transforms are reflected into view -Z. Mesh thickness is a visual
  aid only; sphere queries use the source oriented raw collider, including its
  zero height. Source zone scale, rotation, header position and spawn positions
  remain separate values. The view has no invented trade physics collider.
- Scene, board-size, quest and payment changes refresh the zone snapshots and
  labels. Locked vendors keep empty offer text while retaining their physical
  zone. Active vendors show the source remaining price and collection tracker.
- On a standard card-tail drop, trade is attempted before equipment, joining or
  starting combat, and ordinary stack placement. In-combat fighter drops still
  follow the existing flee/snap-back policy rather than selling fighters.
- The helper chooses the nearest intersecting zone **before** eligibility checks.
  A nearer inactive/rejecting zone prevents trying a farther accepting trade zone.
  Input scene order breaks equal-distance ties. This is deterministic target-pose
  geometry, not a claim of Unity physics query enumeration parity.
- The selected source stack tail is validated and split before the transaction.
  Buyer actions use `Session.sell_stack`; vendor actions use `Session.pay_vendor`.
  No parallel payment/sale implementation is introduced in the view.
- `accepted` and `terminal` are distinct. A coin installment that empties its stack
  ends drop handling. A surviving chest or excess coins continue once through
  the remaining drop actions and placement. Empty-chest last-first stopping,
  partial payments, source payout/spawn positions and factory events remain
  model-owned. See `trade-layout.md` and `vendor-payment.md`.
- Trade obeys the shared playing/selling input policy. Whole-price buy and explicit
  sell buttons remain convenience alternatives, not substitutes for zone drops.

## Collection presentation

Both vendor labels and market-button tooltips use
`session.collection.pack_progress(pack_guid, discovered_recipes)`: positive totals
show `found / total found` or `COMPLETED`; zero totals show no tracker. Discovery
is not inferred from live board card count.

The journal remains a `RichTextLabel`, now populated with per-item metadata.
Active and completed quests have individual rows; discovered recipes also have
individual rows. Unread rows show `NEW`. Hovering a visible item passes its raw
Quest.Id or Recipe.Id directly to `collection.mark_seen`. No dynamic `Recipe:`
card prefix, UI label, header or list index is stored as a read marker.

Opening a tab, completing a quest and refreshing a list do not mark entries read.
The hover handler rejects hidden-ledger, unknown and non-row metadata. Repeated
hover is idempotent. Completed quest history remains available and hoverable.

Collection signals can fire inside card creation/transactions. The board only
schedules a deferred label/journal refresh in response; it does not reenter
geometry resolution, mutate cards, advance RNG or save. Normal board refreshes
also update labels. Journal content is rebuilt only when its row signature changes,
retaining its current scroll position when possible. Tests/readers should inspect
`ledger.get_parsed_text()` rather than `.text`, because RichTextLabel push-meta
rows are built through its structured API, without parsing source text as BBCode.

## Checks and remaining acceptance

`bash tools/test_godot.sh res://tests/godot/test_trade_collection_ui.gd`

The source-backed integration suite checks generated transforms/raw hit height,
nearest-before-validation, trade terminal order, tail-only sale, partial/full
coin and chest payments, single purchase on nonterminal fallback, source header
movement, completed history, individual raw-ID hover marking, hidden/unknown
rejection, label-only signal refresh and collection completion. It uses a unique
test-owned slot directory. Existing smoke checks also verify zone replacement on
Main/Island travel and Continue.

Rendered label legibility, mouse overlap ordering and original art/animation
parity remain unverified. A thin plate and generated type are intentionally new
presentation, not a reproduction of the original trade prefab appearance.
