# Bounded Stats layout candidate (not full typography parity)

Private acceptance scope: locked Unity UIRoot/Main + static source-font binding,
three numeric Stats controls, English/Chinese integer formatting. No DayClock,
other HUD or 3D title implementation is changed. No original fonts, screenshots,
source packages or private fixtures belong in a distributable patch.

## Exact source branches
Unity uGUI commit b394b8ab4f985d25230da1bb02268dcb3c85cb19:
- TMP_Text.GetPreferredWidth (3695–3718) uses infinite margin and converts Normal
  wrapping to NoWrap for the preferred-width request only. Source autosize is
  disabled, so point30 remains fixed. Final preferred-width quantization is
  `(int)(width*100+1)/100` (4866), not rounding to nearest.
- Active font feature kern controls pair adjustment (3985,4250–4285).
- HorizontalOrVerticalLayoutGroup182–216 accumulates float positions, with zero
  source spacing, normal child order, width control and no forced expansion.
- TextMeshProUGUI Overflow branches3443 and3942 ignore geometric bounds. A30-high
  logical RectTransform is therefore not a clipping rectangle for native text.

## Candidate structure
Source-specific text Control owns a separate unclipped native Label. The logical
box uses source preferred width and fixed30 height; native baseline is derived
from source FaceInfo and its actual native TextLine ascent, never a fitted pixel
constant. Native glyph shaping and rasterization are explicitly not TMP SDF.

A Stats-only Container applies the admitted source float child positions. Keeping
Godot HBox here was rejected experimentally: widths41.87/16.75 produced positions
64/169/249 instead of64/169.87/250.62. The fixed candidate does not compensate this
with offsets. It replaces only that group's positioning mechanism.

Whole-group native HBox fallback is mandatory if any child/font/text/layout
prerequisite fails. Even individually valid labels then use native minimum sizes
and baseline placement. Missing bindings clear stale overrides. Unsupported
locale, decimal/CJK/newline text, values outside source int32, missing modern
source fields, or unknown glyph-neighbor bounds cannot pass source acceptance.
A deferred parent-size refresh restores the original fixed50-high parent after
a temporary fallback multiline minimum shrinks; its width follows preferred
size. No outline, crop, glyph squeeze or responsive reflow is introduced.

## Verification and limits
Private native tests:72 admitted source geometry controls and48 whole-group
fallback controls,2 languages,4 physical dimensions,41 frame captures. The prior
HBox failure is retained separately. Five existing nearby/3D smoke tests pass.

For ordinary0/0,0,0/24 Stats at the sampled sizes, the corrected float geometry
produces exactly the SAME visible framebuffer Stats ROI as the prior production
baseline. Do not call this a visible correction of the user's reported offset.
Source contract correctness and visible sampled pixels are separate claims.
320x900 leaves source-fixed Stats outside the viewport; it is not a responsive
layout pass. No matched Unity framebuffer, SDF glyph material parity, all-font
coverage, or full-project migration acceptance is established by this candidate.
