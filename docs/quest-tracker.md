# Quest tracker domain port

Scope: independent GDScript implementation of Quest, QuestInstance and QuestManager behavior. This is a tested domain component integrated with the existing session core, not a claim that the whole game migration is finished. Original Unity source and assets are not distributed here.

## Source parity

Reference: audited template Scripts/Quest/{Quest,QuestInstance,QuestManager}.cs; Scripts/Trading/TradeManager.cs (HandleQuestCompleted); Scripts/Core/TimeManager.cs. Runtime identifiers are serialized Quest.Id; asset GUIDs resolve references. Quest groups retain scene order. Main has 63 quests, Island 3; the 66 exported assets must never all become Main quests.

Defaults: type Have (0), targetAmount 1, targetPace Normal (1), empty text/references/lists. No invented targetDays behavior: this obsolete serialized field is absent from current Quest.cs. Empty/duplicate IDs are diagnosed rather than randomly regenerated, since asset identity must remain stable.

QuestType values 0–13: Have, Obtain, Discover, Defeat, Craft, Sell, Buy, Equip, Explore, Time, Day, Food, Coins, Capacity. Instances start Active with zero when activated; inactive definitions are not in all_quests(). Progress is not clamped.

- Have sets current base-definition card count; Currency-category targets use the full currency snapshot, including stored coins.
- Obtain counts newly created cards by base definition. Existing cards do not replay.
- Discover sets 1 for the specific target recipe's serialized Id.
- Defeat counts killed cards by current definition, not base definition.
- Craft counts notifications by resulting card, not targetRecipe.
- Sell counts the entire sold-stack snapshot or only matching base definitions. Buy counts one completed purchase, optional specific pack.
- Equip and Explore set 1 for a specific equipment/area definition. Repeating either does not increment.
- Time sets 1 on the matching pace-change event (Paused 0, Normal 1, Fast 2); it is not elapsed time.
- Day sets the current absolute day.
- Food, Coins, Capacity set current nutrition, currency and card-limit snapshots, and can decrease before completion.

Initial activation visits roots without prerequisites. Completion activates only explicit questsToUnlock whose entire prerequisite list is completed. There is no global scan to unlock all eligible definitions. Only Have and Discover replay existing state on activation. Have replay invokes the entire stats handler, so other active stat quests can also progress. Unlocks and recursive retroactive completions occur before the parent completion signal, following source order.

There are **no explicit card, currency, XP or item rewards** in these source quest classes. The completion count drives vendor minQuests gates; completed_count() is the authoritative value, not a fabricated counter. Consumers should read that count after quest_completed, including recursive completions.

## Session integration (implemented for current core)

GameSession.configure installs the selected scene's tracker (Main by default) and connects event_occurred once to its event handler, before UI listeners. start_new_game resets cards, discovery, time, payments and tracker, activates the 63 Main definitions according to source roots, then creates the starter pack. completed_quests is a getter derived from quest_tracker.completed_count(); there is no incrementable gameplay counter. Do not replay historical Obtain/Buy/Craft actions. The implemented SaveCodec restores cards and discovered recipes before calling tracker.restore_state, without also calling start_new_game.

The session and its existing equipment/recipe adapters emit the applicable events below. No fake successes or completion buttons are added by the tracker. Required payloads:

| Event | Payload | Source-equivalent emission point |
|---|---|---|
| card_created | base_definition_guid | Once after successful normal card creation, after source stats notification. Do not duplicate when output is crafted. Specialized pack spawn emits neither stats_changed nor card_created, as in CreatePackInstance. |
| card_killed | definition_guid | Before source Kill removal, preserving current definition. Includes fully opened pack, eaten-up food and starvation/combat kills; NOT every generic deletion or sale. Starter quest is Defeat of Starter Pack and depends on this event. |
| recipe_discovered | recipe_id | First source discovery from crafting or recipe-card discovery; key is Recipe.Id, not asset GUID. |
| crafted | definition_guid | Each source NotifyCraftingFinished; current session output payload already has the correct field. |
| cards_sold | base_definition_guids (array, duplicates retained) | One sale transaction's original stack contents, captured before destruction. Do not also emit per-card sales for the same transaction. |
| pack_purchased | definition_guid | Exactly once on successful full purchase or completed vendor installments. No credit for partial payments or pack opening. |
| card_equipped | definition_guid | Equipment definition from successful source equip action. |
| exploration_finished | definition_guid | Explored area definition, not result/loot definition. |
| time_pace_changed | pace (0/1/2) | Actual source-equivalent pause/normal/fast change, not tick. |
| day_started | day | Source day-start event, with absolute current day. |
| stats_changed | empty dictionary | At source NotifyStatsChanged boundaries, after state mutation. |

sync_stats(session) expects session.stats() keys currency, nutrition, card_limit, plus session.cards values with base_definition_guid. Retroactive discovery expects session.discovered_recipes keyed by Recipe.Id. The tracker does not mutate session or award items. Both direct buy_pack and installment pay_vendor consult the derived completion count.

Precise ordering matters: card creation in CardManager calls NotifyStatsChanged before OnCardCreated. Broadly connecting every UI changed signal would add replay points absent from source; use actual stat mutations. During restore, quest_activated signals are UI notifications, not permission to resync.

### Current-core emission ordering

- Ordinary spawn: mutate cards/stack, stats_changed, card_created. Pack creation has neither of these two events.
- Kill: card_killed while the card still exists, then optional character/mob loot creation and removal. Generic removal does not become a kill; there is no invented universal post-removal stats event.
- Pack opening: optional first recipe discovery, normal result spawn, then Kill only when uses reach zero. pack_opened is retained for presentation, not quest progression.
- Standard recipe: first discovery when work begins; consume/destroy ingredients without Kill, normal output creation, crafted only for a valid result, stop work, stats_changed, optional repeat. Repeated work does not rediscover the recipe.
- Sale: validate entire transaction, one cards_sold snapshot before any deletion, delete all sold cards, create earned coins, final stats_changed. sell_card shares the transaction implementation and sell_stack does not call it repeatedly.
- Purchase: consume payment, spawn pack, pack_purchased once, stats_changed only if payment changed stats. Partial installments emit stats but not purchase. Free packs do not invent a stat mutation.
- Food: fully consumed food uses Kill; stats_changed follows each consumption. Starvation uses Kill (and source loot rules).
- User time controls: set_speed accepts only 1 or 2 and unpauses; set_paused changes pause state; cycle_time_pace follows Paused → Normal → Fast → Paused. Only actual user pace changes emit time_pace_changed. Automatic day-end pause and new-day Normal reset are silent; start_day emits day_started with absolute day.

These are synchronous domain notifications; original Unity animations/coroutine waits are outside this core.

## Persistence

save_state returns CompletedQuests (stable ID array), ActiveQuests (QuestId / CurrentAmount), QuestProgress percentage. restore_state reconstructs completed instances at targetAmount; preserves unknown completed IDs in the completion count (source compatibility), skips unknown active definitions, emits activation for restored active quests, and performs no completion/replay or root activation. Valid source saves have unique active IDs.

### Restored Active quests and journal presentation

The source `QuestInstance.IsComplete()` compares `CurrentAmount >= TargetAmount`;
it does not test `Status` or membership in the manager's completed-ID set.
`QuestsView.CreateQuestButton` uses that predicate for its completion suffix, and
`GetItemInfo` uses it to omit the progress line. `QuestManager.RestoreQuests`
explicitly restores an active record as Active with its saved amount and sends
the activation notification, without checking completion or unlocking successors.
Thus a valid restored Active record at or above its target already displays the
suffix and no progress line, while the manager still counts it as active.

`journal_groups.gd` now maps that numeric display predicate. It previously used
`completed_ids`, which incorrectly showed these restored rows as incomplete.
This is a presentation correction only: it does not change tracker status,
completion counts, vendor gates, save contents, successor activation, event
emission, or seen/unseen state. It does not manufacture a completion
event during loading or refreshing.

The focused journal test covers below/equal/above-target amounts, an already
completed record, repeat refresh, unchanged save state and event counts, no
successor unlock, and a real-catalog full-session SaveCodec restore into the
native ledger. Running the initial restored-state fixtures against the preceding UI predicate fails
six assertions: two synthetic suffix/progress pairs and the native pair.

### Button lifetime and hover timing

The numeric predicate alone is insufficient. Unity evaluates the initial title
suffix when creating a button, later only appends a suffix on the completion
event, and queries details on hover entry. A restored Active Food/Have quest can
subsequently fall below its target: its already-created button retains its suffix,
but a new hover request includes the current progress. The existing hover request
is a snapshot, not a live progress binding.

`quest_journal_state.gd` maps that presentation lifetime independently of the
tracker. It captures each instance's title at creation, subscribes to activation
and completion, and updates only an existing matching instance on completion.
Same-instance repeated activation and repeated completion cannot duplicate a row
or suffix. Initial population follows `AllQuests`; subsequent activations insert
in event order. Rebinding a new view reevaluates current numeric state and
disconnects the old tracker; title/scene teardown also disconnects it. No journal
presentation state is serialized into a game save.

Board activation/completion notifications update journal text synchronously,
without reentering geometry or gameplay transactions. Ordinary refresh uses the
stored captions and excludes live detail text from its display identity, so a
progress change does not recreate the displayed text. Tab hiding/showing retains
the quest view, matching `MenuView.ToggleView` changing CanvasGroup visibility
rather than destroying the GameObject. A real scene/view reconstruction resets it.

On hover entry, Board asks for current quest information, even if no ledger
refresh occurred since the last progress change. `InfoRequestQueue` retains the
request's copied descriptor until exit or another explicit request. Refreshing or
completing a quest does not renew the request or silently alter its priority.

New checks cover real tracker Food/Have decreases, creation versus completion,
identity isolation, repeated events, event insertion order, old-tracker cleanup,
rebuild, and native ledger/hover signal integration. The pure lifecycle test has
58 checks; the real-catalog journal test has 66. Replacing the final Board and
descriptor adapter with the first, numeric-only checkpoint fails five native
assertions covering retained captions, progress-only refresh, fresh hover reads,
tab lifetime, and immediate completion text.

These are deterministic domain and injected native-signal tests, not a claim that
Unity and Godot dispatch physical-pointer events at identical renderer-frame
boundaries. Physical hit testing, hover events caused by live text relayout, and
rendered timing remain unverified without a working graphical session. No Unity
editor launch or screenshot-derived visual adjustment is used for this change.

## Validation

Run from repository root:

    HOME=/tmp/stackcraft-quest-home XDG_DATA_HOME=/tmp/stackcraft-quest-data XDG_CONFIG_HOME=/tmp/stackcraft-quest-config godot --headless --path . --script tests/godot/test_quests.gd

Godot 4.6.3 headless: 322 checks, zero failures (the original 319 plus missing-scene and Unity midpoint-rounding regression checks). Coverage includes real 66-asset target/reference validation and Main/Island isolation; all 14 types; additive versus set-one semantics; wrong targets; no double completion; specific/any trade targets; base/current card identity; currency snapshot; decreasing Have; dependency AND and explicit links; retroactive Discover; no retroactive Obtain/stat-only activation; persistence and unknown-ID compatibility.

Additional runs under the same writable HOME/XDG setup:

    godot --headless --path . --script tests/godot/test_runtime.gd
    godot --headless --path . --script tests/godot/test_quest_integration.gd

Core: 76/76 assertions. Only the pre-existing vendor-isolation fixture changed: it now restores real completed quest IDs instead of setting completed_quests directly; that fixture is not presented as real gameplay.

Integration: 70/70 assertions. The separate actual-data gameplay test starts a new Main game, opens all four Starter slots, stacks Villager on Berry Bush to discover/harvest berries, mines Rock for Stone, sells the harvested Stone/Berry and starter Wood to earn the actual three-coin price, and buys Beginning. The five original introduction quests complete through session actions, without injected coins or fabricated completions. It also checks gating, event order, no duplicate sale/Buy/Obtain, snapshot restoration, new-game reset, partial vendor payment, food Kill, day and time controls, and recipe-card discovery. Focused synthetic fixtures are explicitly marked, including a zero-gate vendor transaction fixture.

Full-session persistence is implemented separately by [SaveCodec](save-format.md),
including the restored-Active journal case above. The domain and headless native
UI checks are not rendered/manual UI acceptance or proof of complete Unity/Godot
equivalence. This test result is not completion of the entire original game.
