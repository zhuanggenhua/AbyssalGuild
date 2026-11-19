# Day clock fill value precision

Source DayTimeUI assigns TimeManager.NormalizedTime directly to Image.fillAmount. TimeManager normalizes and Clamp01s; Image.fillAmount clamps again but has no hundredth-percentage snapping. Locked UIRoot timeProgress is the referenced sprite-backed Filled Image, Horizontal, origin Left. No null-sprite fallback or radial interpretation is assumed.

Godot4.7.2 ProgressBar constructs itself with step0.01. Range snaps a requested value to that step before clamping. With max_value1 this changes the real Board fraction0.12345 to0.12, an extra quantization absent from the original. This adapter configures step0 only for the locked source provenance and exact known sprite-backed filled-image configuration; unverified or unsupported configuration restores the ProgressBar's captured native step. It does not change the session clock or arithmetic producing the normalized fraction. Repeating the same setting produces no Range changed notification; sync and inputs are otherwise untouched.

## Horizontal fill draw

The source sprite is the scene-referenced Square.png: single full-image sprite,
64×64 uniform opaque white in the locked asset, linear clamp, no mipmaps. The
locked project has no active SpriteAtlas for this input. The visually authored
Image is active, full stretch, m_PreserveAspect=0, m_UseSpriteMesh=0 and
m_RaycastTarget=0. There is no transparent edge to trim. Admission requires the
known metadata digest and verifies a fully opaque white 64×64 runtime image, not
an arbitrary substitute. Missing or different content keeps the native fill.

The source horizontal Image.GenerateFilledSprite skips fractions below 0.001;
otherwise it emits its floating-point right edge and matching partial UV span.
The scoped child draws exactly this rectangle and source tint over the existing
ProgressBar background without reading pointer input or becoming clock owner. The
ProgressBar still transports the live fraction and retains the fallback for data-
only runs. The child suppresses the default rounded style-box fill only when
admitted. The Godot focus, timer, text and pace handlers are unchanged.

Godot logical geometry and native pixels are different evidence. The imported
Main/Island fixture checks bounds, non-cent span, threshold, float UV and fallback.
The X11 fixture additionally reads actual rendered colors below/above the source
threshold and normal visible extension. It is not the original Unity renderer,
and does not establish UI pixel adjustment, TMP, capture-state or final render
parity. Source uses binary32; the drawing adapter converts the fraction, not the
existing timer implementation.
