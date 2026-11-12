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
