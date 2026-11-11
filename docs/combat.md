# Combat and equipment model slice

This is an independent Godot implementation informed by static inspection of the
locked StackCraft revision `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
Reference paths: `Scripts/Combat/CombatTask.cs`, `CombatManager.cs`,
`Scripts/Stats/*`, `Scripts/Card/Components/CardCombatant.cs`, `CardEquipper.cs`,
`CardEquipment.cs`, `Scripts/Card/CardInstance.cs`, and
`Scripts/Card/Definitions/CardDefinition.cs`. No Unity execution or copied source
is required. Tests use original synthetic fixtures, not exported template content.

## Implemented rules

- All eight stats add equipment modifiers to definition base values and round
  once, using ties-to-even. Fractional modifiers are not rounded independently.
- Three equipment slots replace an existing item by returning it to the board.
  Class-changing equipment records the original definition, changes effective
  base stats, and reapplies every equipped modifier. Removing the active
  class-changing item restores that original definition, preserving other items.
  Current health is neither healed nor clamped by changing equipment or class.
- Equipped cards retain their instance IDs, remain in the session card registry,
  and have no world stack. Character identity (`base_definition_guid`) is retained.
- Combat entrants leave world stacks and cancel their crafting. Each entrant
  receives random initial action progress in [0, 0.5]. Living combatants gain raw
  AttackSpeed × delta progress, not AttackSpeed / 100.
- One actor per one-second logical turn: greatest progress, stable input order
  for ties, dragged actors skipped, opposite-side target chosen randomly. Actor
  progress resets after resolving its turn. Each tick resolves at most one turn,
  including large deltas, matching the source's Update loop.
- Hit chance clamps (Accuracy − Dodge) / 100 to [0.05, 0.95]. Equality hits.
  Critical chance clamps to [0, 1]; equality crits, even an exact zero RNG roll.
- Damage is max(1, Attack − Defense), then rounded RPS multiplication, then
  separately rounded critical multiplication. No invented final damage floor.
  Melee beats Ranged, Ranged beats Magic, Magic beats Melee. Defaults are 1.5
  advantage and 0.75 disadvantage; multipliers are public configuration fields.
- Faction-aware reinforcements, explicit merges, external removal/death cleanup,
  and survivor return to individual world stacks. Merging resets progress and
  always designates Player as attacker, as in the source.
- Flee is available only to the player attacking side. `dragged` is an explicit
  view-supplied exclusion map. Session kill handles death notification and loot.

## Session integration contract

Create `equipment_system.gd` and `combat_system.gd` instances per session.
Configure equipment with `configure(session)` and combat with
`configure(session, equipment)`. Reset both on new game. Pass scaled, unpaused
simulation delta to `combat.tick(step)`; do not pass raw delta a second time.

After `card_killed` is emitted but before loot is selected, call
`equipment.unequip_all(id)` and `combat.remove_combatant(id, false)`. Re-read the
card's effective definition after unequipping: class reversion precedes source
loot selection. Use `equipment.stats(id).maxHealth` for feeding healing.

Reject ordinary move/split/sale of stackless combatants and equipped items.
Stackless cards must not crash board drawing, selection or persistence code.
`equipment.owners` identifies equipped items and `combat.membership` identifies
active fighters. Equipment emits `card_equipped` with the equipment definition
GUID (for quest tracking), not the wearer's transformed definition.

## Deliberate remaining scope

This is a logical model slice, not complete scene parity. Attack/projectile
animations, real-time attack/return delays, sound, camera shake, hurt feedback,
combat rectangle layout, automatic spatial overlap/merge detection, drag-based
engagement and AI initiation are not provided
by these files. The caller explicitly starts/merges combats. Consequently exact
wall-clock attack timing is not yet source-equivalent during presentation delays.
Equipment dropping returns to the wearer's board position; spatial displacement
and placement constraints remain view/board work. Multiplier defaults come from
source fields, not a scene serialization audit. No Unity visual parity claimed.

## Verification

Run `bash tools/test_godot.sh res://tests/godot/test_combat.gd`.
The fixture covers rounding, hit/critical boundaries, all RPS directions,
transformation/reversion, modifier sums, replacement, health preservation,
stack detachment/return, action accumulation, drag exclusion, flee permissions,
reinforcements, external removal, lethal turns and faction-based merges.

## Snapshot helper contract

Both helpers expose `save_state()`, `stage_state(raw, cards)` and
`apply_state(staged)`. Staging validates references against an already restored
card map without mutating live state, returning `ok`, an error on failure, and
`unstacked` card IDs on success. The enclosing save codec must check that these
IDs exactly account for stackless cards and do not overlap between helpers.
The codec applies only after every session section validates. Equipment owners
and combat membership are derived, never trusted from saved redundant maps.
JSON uses arrays of records so numeric dictionary keys are preserved explicitly.
This local snapshot preserves action progress/timers; source Unity reload instead
initializes combat action progress again. Transient drag exclusion is not saved.

Session regression tests cover scaled/paused tick, stackless guards, equipped
wearer sales, death drops and post-reversion loot, equipped-health feeding and
new-game reset. Ordinary wearer destruction removes attached gear (source
GameObject child destruction); Kill explicitly drops it before removal.
Snapshot scalar validation rejects containers, strings and fractional or unsafe
IDs before conversion. Arrays are bounded by restored card counts and three
slots. Finite negative progress/timers remain valid: negative stat modifiers and
oversized single-frame delta can produce these in the source model.

Attached gear is excluded from `world_cards()`, owned-card capacity and Have quest
counts, matching CardEquipment.OnEquipped unregistering its world stack. Combatants
remain counted. This is separate from persistent ownership in the card registry.
