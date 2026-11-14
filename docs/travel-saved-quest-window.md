# Saved-destination quest subscription window

This narrow correction applies only when travel revisits a saved destination. It does not claim complete travel-order or Unity RNG parity.

## Source contract

Locked StackCraft source `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:

- `GameDirector.HandleSceneLoaded` spawns travelers before `OnSceneDataReady` (`GameDirector.cs:58–70,224–232`). `CardManager.RestoreTraveler` restores each traveler's equipment inline (`CardManager.cs:348–366`).
- `QuestManager.Awake` subscribes scene-ready, whose saved branch calls `RestoreQuests`. That method copies each saved active amount without replaying current stats (`QuestManager.cs:140–147,177–221`).
- `QuestManager.Start` subscribes gameplay events, including `OnStatsChanged`, only afterward (`QuestManager.cs:72–101`). It does **not** immediately check Have. `ActivateQuest`, a distinct path, does immediately check Have and Discover (`QuestManager.cs:224–247`). Do not apply the saved-scene rule to new quest activation indiscriminately.
- `CardManager.CreateCardInstance` emits stats and creation during the factory (`CardManager.cs:476–477`). Board/UI initial snapshot reads do not republish those gameplay events. Later actual stats/acquisition events still reach quests.

## Bounded implementation

Existing Godot travel restores the saved destination before its arrival factories. Reordering those factories before `SaveCodec.restore` would erase arrivals and reset their RNG state. Instead, only the private staged destination's quest listener is disconnected after its successful saved restore, then reconnected after all traveler and equipment factories. Other event subscribers, event emissions, RNG calls, ID allocation, equipment remapping and live-session subscriptions are unchanged. Errors discard the private staged destination; there is no serialized mute flag or live global suppression.

New destinations retain existing behavior. Their default-card/quest activation ordering is a separate unresolved source-equivalence question; leaving it unchanged is not acceptance of it. Saved-scene geometry/factory ordering, source global RNG, engine lifecycle and rendered presentation also remain outside this patch.

## Regression contract

`test_travel_saved_quest_window.gd` uses entirely synthetic public fixtures for both directions and new/saved branches. Saved Have/Obtain progress must not change or publish completion during arrival, must survive campaign save/restore, and must resume on real later stats/matching acquisition. Factory and live scene events remain observable. Its optional `TRAVEL_EVIDENCE` output supports old/new differential inspection of exact state, RNG and event traces.

`test_travel_saved_quest_window_source.gd` requires licensed local data: actual Main Have2 Villagers return trip, save/restore and later stats completion; separately actual Sword class equipment, saved Island entity, allocator and owner remapping. These are controlled model fixtures, not claims of naturally achieved gameplay or Unity runtime execution.

Run with the verified official Godot 4.7.2 executable via `GODOT`:

```sh
bash tools/test_godot.sh res://tests/godot/test_travel_saved_quest_window.gd
bash tools/test_godot.sh res://tests/godot/test_travel_saved_quest_window_source.gd
```

Both suites participate in the fresh-import runner; the public fixture also runs without private inputs. No source assets, screenshots or private saved fixtures are needed in the public repository.
