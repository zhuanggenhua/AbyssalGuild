# Scene transition timing and ownership

Static reference: locked `Scripts/Core/GameDirector.cs` (`TravelSequence`, `InitiateTravel`, `BackToTitle`, `GameOver`) and `Scripts/UI/ScreenFader.cs`. This source revision names the coroutine `TravelSequence`, not `LoadGameSceneRoutine`.

- One second linear black fade each way, advanced with real delta. Commit occurs at full black, once, with no carry-over of an oversized frame into the new scene.
- Fade-out owns an independent external pause and input/raycast lock. It never modifies the user's paused flag or pace. Existing menu/vendor pauses remain independent. Unscaled combat travel/return, cycle presentation, camera and presentation continue through the existing paused tick path; day, crafting progress and scaled death waits stop. Pending recipe travel also prevents re-entry/other completed crafting until the transaction settles.
- Source clears its pause and raycast block before fade-in. Native follows this, so ordinary gameplay/menu input and clocks resume behind the fading black. Duplicate scene requests remain rejected until the full sequence completes.
- New-game Confirm, Continue, legacy-copy load, both Save & Title buttons, game-over confirmed archive, and automatic recipe travel route through the controller. Direct `start_new`, `_continue_game`, `_return_title`, `_adopt_legacy` and campaign APIs remain synchronous transactional operations for programmatic callers. `_enter_game` and `_show_title` are commit/lifecycle operations, not fade requests.
- Missing imported data rejects new/load before starting. Native load/archive failures fade back to the old session with their error; departure/title save failures reject before fading. Native recoverable game-over archive replaces source destructive deletion. Quit/window-close requests during a transition cannot bypass its ownership; explicit execution/teardown cancels the pending commit. Token cancellation/reentrant replacement prevents stale completion from reviving an old transition.

## Departure snapshot and native safety policy

Unity `InitiateTravel` saves and captures traveler data **before** fade-out, while real-time combat can still progress. Native stages a complete candidate campaign at request time, validates its travel transaction without live callbacks, then writes the live departure checkpoint once before starting the fade. At black it atomically swaps that validated candidate. Old-scene real-time activity after the capture intentionally does not rewrite the captured travelers. Arrival checkpoint remains after successful scene change. Invalid recipes/destinations or failed departure saves reject before fade without swapping the live session.

Native retained-ingredient/held-stack settlement and recoverable archive policies remain unchanged. Save & Title checkpoints before fading, then shows title at black without a second save. New/load/legacy-slot creation and game-over archive happen at black, rather than changing campaign data before the fade; this is a deliberate atomic safety difference from source save timing. Direct programmatic APIs remain synchronous.

## Verification

`test_scene_transition.gd`: linear timings, real delta validation, repeated requests, once-only commit, cancel, reentrant replacement and stale completion.

`test_scene_transition_board.gd` (licensed imported data required): new/load/title, missing data/save, save and travel rejection, clock/pause ownership, menu/quit gating, interrupted teardown. Existing navigation and campaign tests remain separate regression coverage. These headless checks do not establish visual, physical input or audio acceptance. No Unity launch or display used.
