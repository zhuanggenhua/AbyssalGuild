# Locked source craft hover: bounded original Single F1

This bridge changes only the number in `Time left: …s`, not craft time, progress,
ratio, saves, recipe matching, stat readouts, hover refresh or text layout.

## Source contract

The locked original CardInstance.GetInfo formats a Single-precision subtraction
with F1. Matching-provider Mono first normalizes to seven significant decimal
digits, then formats one decimal place. Native `%.1f` is not equivalent: actual
starter → Villager + Berry Bush → three .25-second ticks leaves 9.25 seconds;
original prints9.3, previous native prints9.2. This example uses real recipe
activation and elapsed ticks, not a manually assigned progress value.

Stat.Value returns an integer. The separate ordinary character/equipment strings
are unchanged; no fractional-stat formatting is introduced.

## Admission

Only the locked catalog provenance commit and its observed recipe
durations (5,10,15,20,30,40,60,90,120,180 seconds) use this bridge. Progress must
be finite and within[0,duration]. Other provenance, durations, invalid/negative
progress and transient overshoot retain the previous formatter. Existing _craft
visibility and progress-ratio checks are untouched.

Display operands are converted individually to binary32 and subtracted in
binary32, like the original expression. This does not change native timer
accumulation or claim its complete history is bit-identical to Unity. The
existing HUD decimal-point punctuation remains; process locale is not changed.

## Compact rule

For nonnegative binary32 x≤180, set q=floor(10x). If q<1800, compare x with

    ((2q+1)*(D/20)-1)/D

where D is200000000 for q0,20000000 for q1..9,2000000 for q10..99,
200000 for q100..999,20000 otherwise. Increment q when x reaches this threshold;
print q as tenths. Integer numerator calculation avoids log/pow decimal-order
errors. This encodes the two-stage original rounding, not arbitrary epsilon or
naive half-up on the original binary value.

## Evidence boundary

The exact provider comparator and original library/IL remain private; no vendor
code, data table or runtime Mono dependency is shipped. Numeric public regression
values are independent input/output controls. Full-domain exhaustive evidence is
required before this candidate is accepted; see the private release report for
that exact completion status. Partial threshold sampling alone is insufficient.

`test_source_craft_f1` checks original default-format boundaries, signed zero,
endpoint, bounded source admission and unchanged fallback/read-only behavior.
Private real-Board regression exercises the reachable9.25 case and actual Sword
readouts; source-data interaction and complete test suites remain required.
