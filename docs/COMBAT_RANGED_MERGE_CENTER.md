# Ranged resize to merge-center handoff

This bounded change carries an observed native resize into the immediately
following merge. It does not add new artwork, change combat timing or establish
rendered equivalence.

## Locked source

Unity CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:

- `CombatTask.AddCombatants` admits cards, then calls `Rect.UpdateLayout`,
  `CheckAndMergeCombats`, and finally stack overlap resolution.
- `CombatRect.UpdateLayout/ArrangeRow` use immediate grounded card transforms.
- `CombatManager.CheckAndMergeCombats` includes the resized source task and all
  intersecting tasks. `MergeCombats` consolidates factions, removes old tasks,
  then creates a replacement rectangle.
- `CombatRect.Initialize` averages actual card transforms before arranging the
  replacement. Ranged and magic travel/return do not run a card combat tween.

The previous version already wrote native slots during ranged/magic travel and
return, but the merge admission Boolean rejected every active source task even
after those writes. In a fully synchronized fixture, fallback model arithmetic
can produce the same final layout center. This change establishes the proven
native handoff, not a demonstrated visible position difference.

## Ephemeral proof

The model opens a monotonic, nonserialized scope around the real
`AddCombatants` resize selector and synchronous merge, then closes it.
Callback signatures are unchanged. Before cleanup, it invalidates that scope if
source membership or model-only drag changed.

The Board records a receipt only after a complete successful native ranged
resize inside that scope. It retains the source task snapshot and reference,
complete ordered source IDs, card/view identities, and observed positions.
After old cleanup, the merge sampler can consume it once. It rejects a different
scope, changed task contents, incomplete source set, uncleared membership,
remaining source task, changed native identity/parent, deleted view or changed
position. All existing drag, equipment, cycle, finite grounded position,
definition, card motion, layout slot and presentation-tween guards still apply.
Other active tasks are not admitted merely because the source task was resized.

Ordinary idle merge admission remains unchanged. Standalone merges, direct
unscoped resize calls, stale receipts, melee and death waits retain the existing
conservative fallback. The receipt does not advance execution, draw RNG, retarget
or delete a detached projectile, or enter save data.

## Evidence

`test_combat_ranged_merge_center_board.gd` uses real imported arrow/magic cards,
actual Board/CardView nodes and both travel/return phases. It checks valid
handoff and rejection after moved position, modified execution, active neighbor,
unscoped direct resize and model-only drag after the native write. Receipts are
one-use and old projectiles retain their captured endpoint without late damage.

Candidate: 558/558 assertions. Baseline comparison rejects the four new valid
native-center observations; unchanged defenses still pass. This is headless node
and lifecycle evidence, not Unity execution or GPU/GameView screenshot acceptance.
