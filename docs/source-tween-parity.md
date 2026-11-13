# Source tween mathematics and combat integration

The mathematics was first verified in an independent temporary project, then
integrated into combat_presentation.gd and impact_view.gd.
No Unity or DLL was executed. No third-party original files are included. The small
math module is an independent implementation, not vendored DOTween source.

## Provenance and confidence

Locked CardLoop commit: `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
DOTween DLL Git blob SHA: `73235fc01a2d43cf393d9d7c897be3924bbbefeb`.

The source checkout is sparse: lack of Plugins/Packages in the working tree is NOT
proof of absent dependencies. Full Git tree lists Assets/Plugins/Demigiant/DOTween.
Read-only GitHub retrieval and in-memory PE/CLI metadata/IL inspection found the
DLL static constructor sets Version to **1.2.790** and defaultEaseType to enum value
6, whose constant metadata identifies **OutQuad**. Generic assembly version 1.0.0.0
is not the product version. Its accompanying XML default-ease comment is stale
(says InOutQuad). Neither manifest nor package lock supplies DOTween; PluginImporter
meta confirms plugin enablement, not version. YokiFrame's conditional initializer
changes recycling/safety/capacity, not ease. No StackCraft override was found.

Locked dependency:
https://github.com/zhuanggenhua/CardLoop/blob/a11a89b04cea8370476f2559b639bb9b4cbc08d8/Assets/Plugins/Demigiant/DOTween/DOTween.dll

Official algorithm references (develop currently reports 1.3.045; NOT used as a
claim that every version is equivalent). Relevant paths were corroborated against
locked 1.2.790 IL, not merely assumed from current documentation:

- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/ShortcutExtensions.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/DOTween.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/Sequence.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/TweenSettingsExtensions.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/Plugins/Core/SpecialPluginsUtils.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/Plugins/Vector3ArrayPlugin.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/Plugins/FloatPlugin.cs
- https://github.com/Demigiant/dotween/blob/develop/_DOTween.Assembly/DOTween/Core/Easing/EaseManager.cs
- https://dotween.demigiant.com/documentation.php

Audited DLL method rows: Punch 55; DOJump 251 and callback 1047; Sequence.DoInsert
175, DoStartup 185, DoApplyTween 186; Join 353; SetPunch 624; ElapsedPercentage 160;
DOTween static constructor 110. This identifies evidence locations, not runtime
execution instructions.

## API and formulas

`out_quad(unit_time)` clamps to [0,1], returns E(u)=u(2-u).
`jump_one(start, finish, power, duration, elapsed)` implements ONLY source-used
numJumps=1, non-relative, no explicit SetEase override. Positive duration required.
Let q=E(t/T), r=2q before q=.5 and r=2(1-q) thereafter:

- x,z = start + (finish-start) q
- y = startY + power E(r) + (finishY-startY) E(q)

The second E is deliberate. Outer sequence default OutQuad remaps child time;
Y child has OutQuad/Yoyo, and endpoint-Y correction itself uses OutQuad of the
child's full elapsed percentage. For T=.3 the apex with equal endpoint heights is
at .0878679656 seconds, not .15. At .15, x/z progress=.75 and lift=.75 power.

`punch_plan(direction,duration,vibrato=10,elasticity=1)` returns relative vector
knots plus durations. N=max(2,trunc(vibrato*duration)); elasticity clamped [0,1].
Segment i duration = T*2(i+1)/(N(N+1)). For i<N-1, positive even knots have
coefficient 1-i/N, negative odd knots have -(1-i/N)*elasticity. Last knot is zero.
The first segment starts at zero offset. Each segment interpolates with OutQuad.

`punch_sample(plan,current_base,elapsed)` ADDS the interpolated offset to the
captured startup property. Base is fixed for this tween, not reread every sample.
It returns base outside [0,T]. Callers must not keep sampling a killed tween.

This is mathematical equivalence, not a bit-identical Unity floating point emulator:
Godot scalar intermediates and double duration arrays can differ in rounding from
Unity float accumulation. Pure samples are checked to 1e-5; runtime object startup,
update dispatch, transform conventions and competing writes are caller work.

## Runtime integration and remaining boundaries

### CombatTask jump

combat_presentation now uses nested DOJump mathematics and event-boundary actual
3D pose capture. Live attacks no longer use the legacy 2D execution endpoints.
Source CombatTask sets Attacking before animation. Melee/None attack captures the
actual defender Transform position plus up*.05, DOJump(power1,jumps1,T.3), independent
update, then waits. Resolve attack only after completion. Return endpoint is the
then-current Rect layout position, also DOJump1/1/.3. Do not substitute an
already-cached target pose for an actually animated transform position. Coordinate
conversion belongs at API boundary. Ranged/Magic projectile and realtime .3 return
wait remain distinct. Death cleanup .5 wait is scaled, unlike independent tweens.

### CardInstance.TakeDamage overlapping/replacement hits

Source kills previous hurt Sequence WITHOUT completing/resetting properties.
New flash getter captures the current material `_FlashAmount` when startup occurs;
new rotation getter captures then-current local Euler rotation. Do not forcibly
reset either to zero. Preserve the capture phase, not just event-time values, if
multiple hits arrive before the next tween update.

Sequence insertion has an easy-to-miss delayed-Join effect:
1. Flash .1 duration, .05 delay, 2 Yoyo loops inserts at .05.
2. DoInsert stores that delayed insertion as lastTweenInsertTime.
3. Joining rotation punch therefore starts at .05 too, and lasts .25.
4. Whole hurt sequence ends at .30, NOT .25.

Implemented state: alive/generation, sequence age, flash-started/rotation-started,
flash baseline and rotation baseline. Kill invalidates old state but preserves its
last writes. At age<.05, neither child writes. At first child startup capture each
getter once. Flash reaches1 at age.15 and returns to captured f0 at .25:

- .05..15: f0+(1-f0)*E((age-.05)/.1)
- .15..25: f0+(1-f0)*E((.25-age)/.1)
- after .25: final f0 remains; no additional flash writes from this tween.

Rotation plan direction=(0,15,0), duration.25,vibrato25,elasticity1;
use local elapsed age-.05, finishing at age.30. Its six relative Y knots are
[15,-12.5,10,-7.5,5,0], durations=.25*[1,2,3,4,5,6]/21.
Audit Unity-to-Godot local Euler sign/handedness (implemented as reflected negative Godot Y15).
Do not silently overwrite an unrelated transform channel such as active attack jump.

Integration regressions: ages0,.049,.05,.15,.25,.30; retrigger during ascent,
descent and rotation-only tail; two hits before startup; killed tween never writes;
unscaled clock while gameplay paused; finish/cancel while object is removed.
Delayed startup and same-frame dispatch require a real native lifecycle test, not
just pure math assertions. Runtime regression now also verifies delayed startup, replacement and tail writes.

### HitUI.Initialize

Source DOPunchScale((.15,.15,0),1), defaultvibrato10,elasticity1, independent update,
OnComplete destroys HitUI. Root prefab scale is1 but implement ADDITIVE anyway.
10 knots coefficients=[1,-.9,.8,-.7,.6,-.5,.4,-.3,.2,0], durationweights[1..10]/55.
Capture startup localScale, sample with punch_sample. Preserve source sprite/type,
miss damage visibility, effect sprite selection and TransformPoint spawn location.
Do not retain a generated sinusoidal pulse or arbitrary alpha fade on source path.
Test nonunit scale (2,3,4) first peak=(2.15,3.15,4), not multiplicative
(2.30,3.45,4); final base restored before destruction; cancellation frees once.

### Camera MoveTo and Shake boundaries

MoveTo OutQuad is already mathematically implemented natively; do not invent a new
curve. Source moves controller Transform (not camera child), resets dragging,
sets dragOrigin from pointer, uses lerp(maxDistance,minDistance,.8), endpoint target
minus current camera forward*distance, durationdefault.5, independent update,
assigns targetPos only after completion. Separate controller and child transforms.

Shake is deliberately NOT implemented here. Source is Transform.DOShakePosition
on camera child, not Camera overload; duration.3,strength.1,vibrato10,randomness90,
ignoreZ=false,fadeOut=true,Full randomness. N3, linear segment durations .05,.10,.15,
nonzero magnitudes .1 then .066666..., final zero. Random angular draws and local
3D vectors replace the current native sinusoid. Source does not kill earlier
shakes, so a single resettable shake age is not equivalent. Unity global RNG draw
order, same-frame scheduling and overlapping setter last-write order are NOT yet
mapped. An injectable random provider test is necessary, but is not proof of
runtime RNG equivalence. Do not silently consume native gameplay RNG or claim
complete equivalence for camera shake.

## Reproduction

`godot --headless --path . --script res://tests/godot/test_source_tween.gd`

`godot --headless --path . --script res://tests/godot/test_source_tween_lifecycle.gd`

Godot 4.6.3: `Source tween mathematics: PASS (57 numeric checks)`.
Also asserts segment counts for source rotation/scale and minimum-count behavior.
Headless runtime integration is additionally covered by test_source_tween_lifecycle.gd
and existing combat presentation/feedback tests. No visual acceptance is claimed.

Verified integration results: lifecycle16 checks; combat presentation20; combat
feedback UI23/23; combat sprite/flash synthetic104 and total260 with private resources.
The public changes contain no dependency DLL, original artwork or private JSON.

## Actual endpoint capture and native save boundary

CombatTask.AttackSequenceCoroutine reads defender.transform.position once for the
attack endpoint, and Rect.GetLayoutPosition(attacker) once after resolution for
return. CombatRect.ArrangeRow calls SetTargetInstant(forceGround:true), whose
implementation forces Y=0; native combat layout now uses that ground height.

CombatPresentation.capture takes injectable current-pose and home-pose samplers.
Board calls it on combat_attack_started and combat_return_started. The sampler
first evaluates any live captured tween at the current real clock, then reads the
actual view transform. Thus return starts at completed attack position even when
model transition precedes the next draw. Existing advance-before-model-tick order
is retained. No movement of target/layout retargets an already-started tween.
Melee endpoints and ranged origins/targets retain actual captured heights. Impact
spawn likewise uses the sampled current origin with the target's actual basis.

Source GameData.CombatData saves CardData lists, faction side and RectPosition only;
CombatManager.LoadCombats reconstructs tasks, not running tweens. The existing
native save format already deliberately persists execution phase and remaining
clock (seven fields). Optional sibling visual_motion now preserves fixed start/
finish Vector3 geometry for that existing native continuation feature. It does not
add an execution state or mutate card targets/RNG. Old seven-field records without
visual_motion retain explicitly legacy snapshot reconstruction; original actual
3D endpoints cannot be recovered from data that never stored them.

visual_motion has exactly actor, phase, combat_type, start, finish and duration.
Stage validates matching execution phase/actor/type, source duration, exactly three
finite bounded coordinates and no orphan/unknown structure. Validation stages an
isolated copy before restore commit; corrupt geometry is not silently ignored.
Travel metadata is cleared at impact, then the return event captures new geometry.
Death_wait/completion clears it. Presentation reset/cancel removes cached motions.

Verified test_combat_motion_capture: 28 checks, including displaced/high start and
finish, moved target, fixed return after moved layout, pause-independent sampling,
nonzero-height checkpoint replay, legacy compatibility, malformed values and
atomic rejection. Existing regressions: save_codec534, combat_timeline59,
death_wait_flee44, combat_merge27, combat_board40, feedback_ui23, presentation20.
