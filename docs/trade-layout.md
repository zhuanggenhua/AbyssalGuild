# Trade-zone geometry and drop plans

`trade_layout.gd` is a pure adapter over the imported source scene/prefab data.
It does not create nodes, mutate Session, publish transactions, or copy original
source/assets. Source audit: `TradeManager.Awake/UpdateZoneLayout/HandleBoundsUpdated`,
`TradeZone.TryTradeAndConsumeStack`, `CardController.TryTradeWithNearbyZone`,
`CardBuyer.CanTrade/ProcessTransaction`, and `PackVendor.RestoreState/TryActivate/
CanTrade/ProcessTransaction`. Unity was not executed.

## Geometry API

`zones(catalog, scene_name, board_bounds=null, top_margin=1.5,
completed_quests=0, payments={}, activated={})` returns `{zones:Array,errors:Array}`.
It resolves direct TradeManager components and referenced buyer/vendor prefabs.
Missing/broken geometry and sheared parent transforms report errors, not invented
bounds. The currently imported Main and Island resolve 9 and 2 zones respectively.
Prefab-instance override expansion is not newly implemented.

Each zone exposes:

- `index` (buyer zero, then offered packs including locked entries), `kind`,
  `prefab_guid`, `pack_guid`, source stable `pack_id`, scene `currency_guid`.
- `center:Vector3`, `transform:Transform3D`, raw `local_bounds:AABB`, enclosing
  `world_bounds:AABB`, `zone_scale`, `spawn_position:Vector3`, `collider_enabled`.
- `active`, `min_quests`, `total_price`, `paid`, `remaining_price`, `title`,
  `price_text`. Inactive vendor text is empty rather than presenting an unlocked
  offer. `activated` and `payments` are keyed by catalog pack GUID for Session.

The parent Transform chain affects zone position/rotation/scale. Zone layout
replaces prefab local position and scale, but retains its root local rotation.
Source `zoneScale` scales the raw collider, not its center-to-center spacing.
The current collider is `(0.8,0,1.0000004)` and becomes about `(0.9,0,1.125)` under
zoneScale. Its zero height is retained for query math; rendering may use a thin
visual plate but must not use that invented thickness for source hit tests.

If current board bounds are supplied, their header center replaces manager world
position while preserving parent-derived world basis. Spawn position is zone
WORLD origin plus the unrotated, unscaled WORLD `spawnOffset`. Existing
`scene_spawn.vendor_position`/`buyer_position` remain unchanged and tested to agree.
All coordinates use original X/Y/Z; the current board view must apply its source
Z reflection when drawing nodes and convert pointer positions back before queries.

## Drop selection and validation

`nearest_zone(zone_list, position:Vector3, radius:float)` returns a zone dictionary
or empty dictionary. Use imported `CardSettings.attachRadius` (currently 0.25).
It intersects the sphere with the oriented raw box, using actual 3D height and
no card margin. `world_bounds` is for rendering/inspection, not an exact rotated
box hit test. `intersects(zone,position,radius)` exposes that predicate separately.

CRITICAL: source selects the nearest intersecting zone by distance to its transform
origin BEFORE checking eligibility. It does not select the nearest tradeable zone.
A closer inactive vendor or rejecting buyer prevents a farther zone from being
tried in that drop attempt. Equal-distance ties preserve input hit order. The
helper defaults naturally to scene zone order if passed `zones` directly; that
is deterministic, not proof of Unity physics enumeration parity. A view can
reorder snapshots to its actual collision-hit order.

Call `card_snapshots(session, ids)` for `{ok,cards}`. Check `ok` before proceeding;
invalid IDs must not be treated as an empty valid payment. Snapshot order must be
original stack array order. `can_trade(zone,cards)` is suitable for both highlight
and selected-target validation. Inactive vendors cannot trade. Buyer requires
all cards sellable and any actual chest empty. Vendor requires ALL cards to be
Currency-category or actual chest with at least one stored coin. A different
scene's Currency category is valid: source does not require matching currency
GUID. A nonchest with an arbitrary stored balance is invalid.

## Payment plan and transaction handoff

`payment_plan(zone,cards)` returns an immutable-input plan:
`accepted`, `purchased`, post-transaction `paid`, `consumed_ids`, `stored_after`,
`remaining_ids`, `terminal`, `stats_changed`.

Source `BottomCard` is the LAST array element, so consumption proceeds last-first.
A chest remains in the stack after withdrawal. If it empties before covering the
price, source stops at that chest rather than skipping to earlier cards. A paid
purchase resets paid amount to zero and consumes only the required coins. A free
pack can be purchased without removing any payment card.

`accepted` does NOT mean terminal. `TradeZone.TryTradeAndConsumeStack` returns true
only if the dropped stack is EMPTY after processing. Therefore a partial coin
installment that empties the stack is terminal, but a full purchase using a chest
is nonterminal. For nonterminal outcomes, source continues equipment/combat/stack
placement actions using the remaining cards. Never remove/destroy a surviving
chest or extra coins just because the transaction was accepted.

The caller owns actual consumption, pack spawning, quest/stats events, effects,
and continuing drop resolution. In source drop order, trade precedes equipment,
join/start combat, and ordinary stack placement. Successful model application must
retain existing validated factory/event paths rather than mutate a second game
state. This helper does not execute a payment.

## Session integration

`Session.pay_vendor` now traverses last-first, validates actual chests, and returns
`terminal` separately from `accepted`; see `docs/vendor-payment.md`. Board trade
routing must use that terminal field, not accepted, to decide whether to stop
later drop actions. The pure payment plan assumes a resolved scene currency for
chest withdrawal; the Session mutation path explicitly checks it. Category-wide
currency acceptance and buy-price calculation remain unchanged. Existing sales
use scene-specific payout currency.

Vendor activation is sticky in source once unlocked; pass previously active pack
GUIDs in `activated` if quest counts can decrease. Normally completed quest count
is monotonic. Stored remaining display is `total_price - paid` without clamping,
matching source display logic, even for a malformed overpayment snapshot.

## Validation

Godot 4.6.3: `test_trade_layout.gd` 61/61, `test_trade_currency.gd` 40/40,
`test_scene_spawn.gd` 28/28. Geometry tests cover both scenes/current and expanded
bounds, parent rotation/nonuniform scale, source scale versus world spawn offset,
zero-height/raw sphere intersection, disabled collider, nearest inactive zone,
tie order, and unlock/remaining-price metadata. Payment tests cover full, partial,
excess, free purchases, empty/nonempty chest, actual-chest eligibility, whole-stack
rejection, last-first consumption and terminal behavior. Synthetic math/payment
checks also run without private data; source-specific checks explicitly skip.

These are model/adapter checks, not rendered trade-zone or mouse acceptance.
