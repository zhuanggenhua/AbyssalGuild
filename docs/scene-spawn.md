# Scene defaults and vendor spawn positions

This slice statically follows original `CardManager.SpawnDefaultCards`,
`TradeManager.UpdateZoneLayout/HandleBoundsUpdated`, and
`TradeZone.spawnPosition`. No Unity runtime was launched.

## New-game defaults

`Session.start_new_game` now reads the selected scene's serialized
`defaultSpawnCards`, `defaultSpawnPosition`, and `defaultSpawnRadius` through the
existing Campaign scene resolver. It processes every reference in order, including
non-pack cards, and returns the first successfully created ID for existing UI
callers. An empty or unresolved list returns -1 rather than inventing a starter.

Each entry consumes the same three-at-a-time rejection sample previously used by
Session, projected from a 3D unit sphere into XZ. Thus Main's current single pack
keeps exactly the existing seed draw order, while Island gets its own default
pack and center/radius. This matches the source distribution and call count, not
Unity's engine-specific random sequence. Source center Y is not represented in
the planar Session model. Campaign's existing direct scene-field resolver is
unchanged; unresolved prefab-instance defaults are not newly supported.

## Vendor placement

`scripts/model/scene_spawn.gd` resolves direct scene TradeManager components,
ordered offered-pack references, spacing, spawn offset, and the full serialized
Transform parent chain. Buyer occupies zone zero. Locked vendors still occupy
their serialized slots. Zone local X is:

`-(offered_count * spacing)/2 + (vendor_index + 1) * spacing`

The manager's world position becomes the current board header center when Session
has `board_bounds: Rect2`, with its existing world rotation/scale preserved.
Otherwise, its serialized world transform supplies the initial header position.
The zone position uses the manager transform, then adds `spawnOffset` in WORLD
space, matching the source's actual property rather than the field's misleading
local-offset tooltip. Zone's own visual scale does not scale the spawn offset.

`vendor_position(catalog, scene_name, pack_guid, board_bounds=null,
top_margin=1.5)` returns a planar Vector2 or null when unresolved. Both `buy_pack`
and a completed `pay_vendor` use it; neither draws random numbers. Partial payment
still produces no pack. Non-offered packs, missing scenes, unresolved prefab
instances, or broken transform chains retain the old model's origin fallback;
that compatibility fallback is not claimed as source placement parity. There
are no guessed source coordinates in the resolver.

The view must not subsequently reposition a purchased pack with a hardcoded
layout. Separation, attachment, and visual spawn animation remain separate
integration responsibilities. The main model field `board_bounds` must be kept
up to date after scene changes and board growth for current-header placement.

## Validation

Godot 4.6.3 with the private imported data:

- `test_scene_spawn.gd`: 28/28, covering both scene defaults, definition/list order,
  exact seed consumption, changed center/radius, multiple/non-pack/empty defaults,
  first/last vendors, expanded and translated board/header, unresolved lookups,
  whole-price and installment purchase locations, and no purchase RNG draws.
- Existing runtime suite: 76/76.
- Travel suite: 35/35.
- Isolated UI smoke suite: 135/135 (import-cache-dependent source FBX assertion
  explicitly unavailable in the isolated runner; fallback checked).

Use `bash tools/test_godot.sh res://tests/godot/test_scene_spawn.gd`.
These tests assert model behavior, not mouse/animation or Unity execution parity.
