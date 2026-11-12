# Native GUI smoke and layout corrections

Reference source: StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
Baseline GUI snapshot: public `de7204dbe9fc4749184d0e1a30e2fc5100eaf828`,
tree `4baa0223a9fafe7229e1a500353edabc59952bc8`. Unity was not launched.

## Observed baseline

A separate cloud-native Godot 4.6.3 Compatibility session rendered the actual
private-import project, using llvmpipe and a 1233 × 771 embedded viewport.
The source lock passed for all 1327 files and regenerated data matched.

Actual pointer/keyboard smoke covered New Game, preferences, Confirm, two
Starter draws, card drag, Space pause, Escape menu, Options, Save and return to
Title, Load Game and Continue. The saved cards and dragged position returned.
Pause grayscale affected the world while the HUD remained colored.

The rendered run exposed collapsed Quests/Recipes tabs, truncated inspector
actions, and a title that retained the bright Main board after returning from a
game. These defects were not detected by earlier headless behavior assertions.

## Corrections

- The journal tabs and native pace buttons now keep intrinsic text width and
  share available row space. They cannot collapse into two narrow strips when
  the shared button factory enables text clipping.
- Inspector action captions fit their native panel. Tooltips retain the complete
  selected-card action descriptions; callback behavior is unchanged.
- Cold title initialization and returning to title share one world-reset path.
  It releases gameplay board geometry, restores the original native title board,
  material, lighting and camera, and clears pending camera focus, pan and shake.
  New Game and Continue still apply the imported gameplay camera and lighting.

Static source evidence: `Scripts/Core/GameDirector.cs` routes BackToTitle and
GameOver through a transition to a fresh Title scene. The Godot single-scene
shell therefore cannot retain the gameplay world behind its title controls.
This restores the existing native title appearance, not the original Unity
Title Canvas or pixel output.

## Regression coverage

`test_gui_layout.gd` checks real container widths against font and style metrics,
both journal controls, the long action captions, 1440 × 900 logical layout at
1280 × 800 and 1233 × 771 window sizes, world restoration, repeated title reset,
and repeated New Game / saved return / Continue / title transitions when source
data exists. It is included in the ordinary and private imported runners.
The source-free run explicitly reports that real gameplay/title transitions
require private data; synthetic restoration and container checks still execute.

## Remaining acceptance limits

- The baseline first two Starter draws were partially outside the left viewport.
  This batch does not alter their positions or the source lens to hide that
  issue. Main serializes a spawn center at X=-3.5, Z=0.6 with radius 1.2.
  `PackInstance` creates a card at the pack's target XZ, then the overlap solver
  separates it from the locked pack. A 30-degree source camera can show less
  than the complete board at the native aspect ratio. Source placement, viewport
  framing and recovery usability require separate investigation.
- The cloud session could not open an audio device and used Godot's dummy audio
  driver. VSync was unsupported by its graphics driver. There is no listening
  acceptance claim.
- This is bounded native GUI smoke, not complete combat, travel, day-cycle,
  controller/touch, exact rendering/physics/RNG, Windows, export or installation
  acceptance. Original fonts and native UI composition remain different.
- Private PNG/WAV/FBX inputs and screenshots containing them are not added to the
  public repository. Earlier no-display statements describe earlier runs only;
  the bounded rendered smoke above is now available separately.

## Automated verification of this correction

The modified candidate passed 102 Python tests, 62 clean source-free Godot
suites, 102 full-data Godot suites and 42 freshly imported private suites.
The new focused checks passed 40/40 without source data and 48/48 with actual
source data, including the imported FBX path. All 1327 source hashes and a full
source-to-data regeneration still match. These counts do not imply every GUI
path has been manually exercised.

## Rendered retest result

The corrected board script (SHA-256
`1425cae134257e7534ba019654dbf89090d11163bd30e9d17494bab0b12e3478`)
passed the requested native-window retest: both journal destinations switched,
1x/2x changed the actual pace, the inspector captions fit and the full Withdraw
and Unequip tooltips appeared. New Game → Save/title → Load/Continue → Save/title
restored the same cold-start dark title on both returns, while Continue restored
the source gameplay pose.

The retest also found a separate keyboard issue: after focusing a 1x button,
Space reactivated that button rather than pausing. Actual Viewport event routing
confirmed that removing focus restores Space pause. This is a subsequent input
fix, not a passing result or part of this layout/title checkpoint.

## Space input ownership follow-up

The focused-HUD problem has a separate regression: `test_pause_input.gd` sends
press, echo and release events through the actual Godot Viewport, not directly
to `_unhandled_input`. The public baseline reproduced the defect with all six
focused controls: 1x, 2x, Pause, day clock, day action and journal toggle.

Gameplay Space is now intercepted before native GUI acceptance. Its first
non-echo press toggles manual pause once while retaining the selected speed;
release and autorepeat cannot activate the focused HUD control. Title, pause
menu, options and confirmation dialogs retain their normal Space handling,
and Enter still activates focused HUD controls. Day-end phases do not change
manual pause. No global `ui_accept` mapping or control focus mode is removed.

The 35-check source-free regression passes on Godot 4.6.3 and is included in
both ordinary and private imported runners. The test deliberately uses an empty
catalog only as an isolated routing fixture. Production still requires the
licensed import and never substitutes this fixture. This reimplementation was
verified independently from the earlier unuploaded local candidate; it does
not claim that candidate or its private-data/native-window checks were recovered.
Current full private-data, physical input, rendered, audio and Windows acceptance
remain separate. Pause-menu focus containment is not part of this checkpoint.

## Further native follow-up checkpoints

[Pause/options focus ownership](menu-focus.md) now has its own native keyboard
loop and return-target checks, including lost focus, modal cancellation and
failed settings saves. This is separate from the Space interception checkpoint.

[Starter framing audit](starter-framing.md) found that the locked source camera,
spawn extent and overlap rules can produce the observed initial crop. The
source-consistent lens and placement behavior are unchanged. Independent
perspective checks and actual Viewport middle-pan/wheel events recover a
synthetic cropped card and retain physics picking at both tested viewport sizes.
That source-free test is not a repeated private Starter draw or an actual
rendered/HUD-usability acceptance pass. Audio, Windows and final gameplay
acceptance remain open.

## Fresh native-window verification

A new isolated Linux desktop run of `389c5796135f553f9b93f3839e916fc7dd0df6e5`
with the reverified private import and official Godot 4.6.3 exercised real
pointer and keyboard input. It confirmed:

- Changed duration/Friendly preferences, Confirm, and two Starter draws.
- Focused 1x followed by Space paused once and resumed at Normal/1x.
- Escape focused Continue; forward/reverse menu boundaries stayed within the
  active menu. Options boundaries and slider keyboard adjustment worked.
- Closing options restored its opener. Space on Continue resumed only the
  menu, and repeated open/close preserved an already selected manual pause.
- Wheel zoom plus keyboard pan recovered the initially cropped Berry Bush and
  Villager. The recovered Villager could be selected and dragged.
- Save & return reached the restored title, and confirmed Quit closed the game.

This run exposed a small separate presentation defect: the pause heading was
visible through the default translucent options surface. The surface now has
an opaque local copy of the panel style. A native retest of
`options_panel.gd` SHA-256
`04cb70b763cd70b973c5c581bcdc0145f34922045d46ba6a9943c59c471bffe2`
confirmed no heading/subtitle behind Resolution or Window, legible settings,
correct return focus, and one-time Continue behavior. Its focused suite is now
64/64; the underlying Space suite remains 35/35.

Both native runs used isolated user settings/saves and Dummy audio. They do not
establish listening, full combat/travel/day-cycle interaction, Windows,
controller, export/install or final parity acceptance. Screenshots and imported
assets stayed private and are not part of this repository.

## Natural campaign and title fitting follow-up

A fresh isolated native Linux run starting from `83e8648`, on official Godot
4.6.3 with the verified private import, used only the ordinary game UI. No
injected cards, edited saves or test callbacks drove the campaign. It covered:

- All four Starter draws, camera recovery, stacking and tail splitting.
- Berry harvesting, rock mining and tree chopping through resource depletion.
- The first vendor unlock, 3D buyer sales and three separate coin installments
  for a Beginning pack, followed by ordinary pack draws and another purchase.
- Rejected mixed-content sales without losing cards, manual and timed day ends,
  three feeding/next-day cycles, and automatic new-day checkpoints.
- Save & Title, a normal Quit/relaunch, and Continue preserving Day 3, card
  contents and the outstanding two-coin vendor price.
- Wood → Timber → Wooden Stick → Wooden Club crafting in Day 4; equipping
  the club changed Villager to Warrior, dragging its expanded equipment card
  unequipped it back to Villager, and the club could be equipped again.

This exposed a separate title-layout defect: the native Berry Bush label wrapped
into the next stacked card's title. The source TMP title disables wrapping and
fits text to its padded rectangle. The native implementation now uses a
single line and native font metrics inside those imported bounds. A real-window
retest confirmed separated Berry Bush/Villager titles at both zoom levels;
Wooden Stick remained on one line too. See [card overlays](card-overlays.md).
It does not reproduce the unavailable source font or claim TMP pixel parity.

The normal baseline Quit also logged retained audio resources. The production
shutdown follow-up below addresses that observed exit defect. These runs used
Dummy audio. Hearing, natural combat and late-game travel, Windows, controller,
export/install and whole-game acceptance remain outside this bounded result.
Original screenshots, save files, logs and licensed assets remain private.

## Production Quit cleanup

The follow-up closes audio admission only after a successful quit checkpoint or
confirmation, stops/releases active music and overlapping SFX, then allows at
least 0.5 seconds of monotonic wall time for AudioServer to release queued
playbacks before SceneTree exits. Gameplay and input are disabled during that
brief drain. Failed saves and canceled/stale confirmations leave the game and
its audio alive. Callback-before-Click ordering cannot restart audio after quit.

`test_native_quit.gd` exercises actual process shutdown, rather than replacing
Quit with a test callback. It covers paused/zero-time-scale shutdown, repeated
requests, active overlapping audio, save failure, cancellation and checkpoint
preservation. The ordinary watchdog now treats ObjectDB/resource leak diagnostics
as failures. The private runner requires the actual cached-WAV branch. This is
exit-resource validation, not listening or an exact source-audio timing claim.

A fresh native-window launch with the combined fixes restored the natural Day 4
save, its Warrior/equipment and partial vendor payment. Save & Title followed by
confirmed Quit closed normally; the completed verbose log contained no script,
resource-in-use or ObjectDB leak diagnostics. Ten repeated cache-backed
real-process quit regressions also exited cleanly. This retest used Dummy audio.


## Natural combat and growth continuation

A subsequent run on `04dd21f8a3a3174fa1f1c3ac4f986085b57a9ff9` continued
the same normally saved Day 4 campaign through the ordinary native UI. It used
no injected cards, modified saves, fixture callbacks, or Unity execution.

- Mining, resource sales and earned Beginning packs provided two Chickens, Soil
  and eventually a Slime. A paused drag of the equipped Warrior onto a Chicken
  formed a combat rectangle. Resuming Normal pace completed the fight, removed
  that Chicken and returned the equipped Warrior at 18/20 health.
- A subsequent naturally drawn Slime approached the Warrior autonomously. With
  no further combat input it was defeated, leaving one Coin; the Warrior stayed
  at 18 health. The loot Coin was picked up and paid toward another pack.
- Chicken production, the full 120-second Soil/Berry growth, the Revelations
  vendor unlock, and harvesting the resulting Berry Bush ran naturally.
  An ordinary Save reported success after the combat and growth progress.
- The Day 5 cycle healed the equipped Warrior to 20 health and produced the
  configured wandering Villager encounter. Starting Day 6 checkpointed the new
  character and raised the normal food requirement from 2 to 4.
- A new naturally initiated, manually paused Day 6 fight survived Save & Title
  and Continue with its participants and equipment intact. A second Villager
  joined the restored fight. Dragging the attacking Warrior out reported Fled
  combat; dragging it back rejoined the surviving fight in the later row slot.
  Resuming completed the fight with both characters returned to ordinary stacks
  (Villager 15 health, Warrior 19), equipment retained and one Egg loot drop.
- Earned materials then built a House with the equipped Warrior. House plus
  the two characters produced a Baby; food demand rose to 6. Feeding at the
  natural Day 6 boundary preserved the family and healed the Warrior to 20.
  House/Baby growth completed in Day 7, producing a third adult and unlocking
  Farmstead. No timer or save edits were used.

Before/after screenshots and the native run log remain private. These observations
cover basic melee initiation, autonomous hostile approach, completion, loot use
and continued ordinary play. They do not establish animation frame timing,
projectile combat, combat merging, physical-controller behavior or listening.
The cloud run still uses Dummy audio.

The travel source was rechecked against the locked TravelRecipe and GameDirector:
copy travelers before consumption, checkpoint the source, cyclic destination,
independent traveler positions, and fade/pause boundaries. Focused Godot checks
passed 35 travel assertions, 80 source-data global-checkpoint assertions and
175 synthetic global-checkpoint assertions. Combat timeline/order/death-wait
checks passed 59, 45 and 44 assertions respectively. These tests create their
fixtures explicitly and are not evidence of natural progression to Island.
An additional licensed-catalog regression passed 45 assertions across acolyte
loot, the altar ritual, Demon Lord loot, portal crafting with three transformed
Villagers, timed travel, JSON restore and return. Its prerequisites are spawned
fixtures and its enemies use direct death calls: this establishes model chain
connectivity, not natural progression or combat victory.
The natural Grand Portal route requires 5 Stone, 5 Brick, an Abyssal Core and
3 Villagers; the Core is Demon Lord loot. That late-game route remains open.


## Island travel and status legibility follow-up

On baseline `1f40c9e94a4f306f04e8e828bfb0b95b446c6716`, the unchanged natural
campaign advanced from Day 7 to a normally saved Day 8 with four adults and
18 completed quests. It did not naturally reach the Grand Portal. The locked
catalog gates Blacksmith at 26 completed quests and Adventure at 30; their
Acolyte draws are probabilistic. Blacksmith costs 15 Coins with an 8% chance
per fully opened pack. Adventure costs 20, with a 16.8% first-pack chance while
Summoning Evil is unknown, then 20% once it is learned. These are not guaranteed
completion times. The required Altar, Acolyte, Demon Lord and portal chain also
needs substantial construction, food and combat preparation.

To exercise the travel UI without presenting an injected setup as a natural
win, a separate private slot was created through the native model's ordinary
card factory and equipment APIs. It started paused in Main with an existing
Grand Portal, a 17-health club-equipped Warrior, and a small retained base.
No travel was triggered by the builder. This fixture used different user-data
directories and never replaced or edited the natural Day 8 save.

Real pointer/keyboard play then covered:

- Dragging the Warrior onto the portal, the actual five-second travel recipe,
  fade, first Island arrival and its automatic checkpoint.
- Opening the default Island pack, harvesting Palm Tree and Basalt Columns,
  obtaining Coconuts/Stone and unlocking the Survival vendor.
- Save & Title, normal Quit, cold relaunch and Continue in Island with the
  traveler, equipment and active resource work restored.
- Return to Main, revisit to Island, and another round trip after paying Coral
  to Survival. The vendor's remaining price stayed at two Coins on returning.
  Read-only comparisons of actual arrival checkpoints verified retained cards
  and frozen scene clocks, with exactly one traveler and its retained equipment.
  The Warrior stayed at 17 health through all travel legs.
- Island feeding using the four earned Coconuts, healing the Warrior to 20,
  and the Day 2 automatic checkpoint with the partial vendor payment intact.

The first Island arrival exposed unreadable white status text over its bright
board. The native status label now has an opaque dark backing and white text,
keeping the same bounds and mouse-ignore behavior. Actual native-window retests
confirmed legible restored-slot, arrival, installment and next-day notices on
both Main and Island, including manual pause. The backing is native UI chrome,
not a claim of original source styling. The layout regression checks at least
4.5:1 contrast, wrapped failure text, scaled bounds, and actual Viewport hover,
click and wheel pass-through.

These are controlled late-game UI observations, not natural portal crafting or
Demon Lord victory. The separate natural campaign remains at Day 8. Native
audio-device listening, projectile/merge acceptance, Windows, controller and
export/install acceptance remain open. Licensed inputs, fixture builder, raw
screenshots, saves and logs stay private.

The combined correction passed 104 Python tests, 67 clean source-free Godot
suites, 108 full-data Godot suites and 47 fresh private-import suites. Source
lock verification passed all 1327 files, and source-to-data regeneration matched.
The GUI checks pass 64/64 without source data and 72/72 with it.

The first two full runs exposed a pre-existing test-only audio teardown race:
`test_world_post_process_board.gd`'s 100 ms timer could consume the preceding
slow frame's delta and exit after only 14–19 ms of wall time. Baseline comparisons
reproduced retained AudioStreamWAV/playback objects. That test now closes audio
admission using production shutdown, verifies voice/cache cleanup, and honors
production's monotonic drain deadline before freeing its board. The strict
leak watchdog and production audio behavior are unchanged. Ten focused runs
and the final complete regressions passed; normal native Quit logs were clean.


## Controlled projectile and overlap-merge acceptance

A separate native Linux 4.6.3 run on the unchanged `51277c7` gameplay code
used two private, paused prerequisite fixtures. Production card factories,
equipment APIs and normal saves created their starting positions. No combat
was prestarted, no character stats were changed, and no quest completion or
natural campaign advancement was fabricated. The four preserved natural saves,
including Day 8, remained byte-identical.

Ordinary pointer drags started a Bow/Chainmail Ranger versus a Cow and a
Staff/Chainmail Mage versus another Cow. At Normal/1x, rapid original-window
captures show the source Arrow and Magic sprites moving from their actors to
the targets, followed by damage popups, hurt flash/punch and health reduction.
Repeated attack/return cycles also ran. Normal Save preserved both tasks,
all eight card/equipment identities and the resulting health. This is a
controlled rendered ranged-combat check, not natural equipment acquisition,
full ranged-battle balance, listening acceptance or Unity pixel equivalence.

In the second fixture, pointer drags started two adjacent independent fights
while paused. Dragging a third Chainmail-equipped Villager into the left fight
expanded its rectangle into the right one. The visible result was one rectangle
with three players and two Cows. Actual before/after saves verified that tasks
1 and 2 were replaced by task 3, with player order `[1, 9, 5]`, opponent order
`[13, 15]`, unchanged health/equipment and no duplicated participant. Normal
combat then defeated both Cows. The rectangle disappeared, three equipped
Villagers returned as ordinary stacks at 14/13/12 health, and two Raw Meat loot
cards remained. No direct damage or death calls drove that resolution.

A read-only audit passed 107 state/preservation checks, and all five evidence
saves passed the native campaign validator. Both native sessions used ordinary
Save & Title and confirmed Quit; complete logs contained only the known VSync
warning, without script/resource-leak diagnostics. The run used llvmpipe and
Dummy audio. Fixtures, screenshots, raw saves, logs and imported media remain
private. Physics ordering, exact source animation/noise, other platforms and
natural endgame progression are not established by these controlled scenarios.

## Standalone Linux release acceptance

The [private export workflow](linux-export.md) separately builds an official
4.6.3 Linux x86_64 release executable plus PCK. Its native acceptance results
are recorded there. It does not publish a game package or replace the licensed
source recovery requirement for developers.
