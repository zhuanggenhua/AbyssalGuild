# Registered cards drive StatsSnapshot and encounter capacity

Reference: the pinned Unity CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
`CardManager.AllCards` enumerates registered stack members followed by
combatants in active fights. `GetStatsSnapshot` uses that enumeration, not
the backing set of extant card instances. An unregistered card does not count
merely because it has not been destroyed. Equipped cards are also not members
and the native projection does not duplicate a card across ownership paths.

The Godot Stats HUD and the encounter capacity guard now share that projection.
Encounter capacity includes currencies and packs. For the separate owned-card
limit, those two kinds are excluded. Currency combines loose currency cards
with balances on actual ChestDefinition-backed instances, not arbitrary card
stored fields. Only an actual LimitBoosterDefinition contributes to TotalBoost.
The snapshot retains signed `owned - limit`; the existing selling transition
already handles nonpositive values as no outstanding sales.

The targeted cycle test checks detachment and re-registration, ongoing combat,
the exact encounter threshold, typed capacity and currency, and the existing
first-payout selling-to-encounter transition. The real Board fixture measures
the source capacity HUD before and after removing a source booster. These
checks use Godot headless, not a matched native Unity screenshot.

## Stats HUD notification boundary

`CardStatsUI.Start` reads one snapshot, then `OnStatsChanged` alone replaces
the text. `OnDayStarted` and `OnDayEnded` toggle the original group visibility
and raycast state, not its numbers. `CardEquipper` emits `OnCardEquipped`
after removing the registered equipment stack; `ReturnCardToBoard` registers
the returning item and resolves overlaps without emitting `OnStatsChanged`.
The pack factory is also silent. The next normal card spawn or other actual
stats publication shows the live snapshot. HUD refresh/resize, pause, and
unrelated frame or equipment events do not recalculate those labels.

The Godot stats receiver applies each snapshot at publication before the later
selling observer can create nested spawns. It rebinds at scene entry and
releases the previous world on new scene/title. No changes to the separately
queried economy/cycle state or authored HUD layout in this patch.

Run `bash tools/test_godot.sh res://tests/godot/test_source_stats_events_board.gd`.
The Board case checks a fresh game, real Sword equip/unequip, food and coin
spawns, a real pack, and switching world/title lifetimes. Its direct domain
calls isolate notification semantics; this is not a visual or hardware-input
check and does not recreate a Unity runtime frame sequence.
