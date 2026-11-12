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
