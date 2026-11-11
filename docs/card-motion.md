# Ordinary card movement

`card_motion.gd` is a read-only model adapter with private presentation state. It
consumes value snapshots and returns rendered positions; it does not advance
simulation clocks, write gameplay positions, consume random values, or serialize
animation state.

Static reference checks: `CardInstance.SetTargetAnimated`, `SetTargetInstant`,
`SetTargetDamped` and its `Update` damping path; `CardStack.SetTargetPosition` and
`SetDragTargetPosition`; `CardController.UpdateDragPosition`; source CardSettings.
The original project was inspected as text only and is not copied into this repo.

- Target changes restart animation from the current rendered position. Repeated
  syncs with the same target do not restart it. The source defaults are a 0.1 s
  unscaled movement and serialized DOTween OutQuad (6). The adapter also supports
  Linear, Sine and Quad family values 1–7; other values fall back to OutQuad.
- Instant targets cancel animation/damping. Optional grounding is exposed in the
  adapter. Existing board-plane clearance (0.06) is retained for resting cards.
- Drag heads snap to the imported `dragHeight` (0.1). Tails follow the preceding
  card's current position plus the reflected source stack step, not the stack's
  final target. Damping is `1 - exp(-swaySharpness * real_delta)`, default sharpness
  100. Source squared-distance snap threshold 0.0001 is retained.
- Board process supplies real frame time even under ordinary and menu pauses.
  Refresh-only calls use zero elapsed time. Combat, cycle, and equipment remain
  later/higher-priority pose owners. Source scene CardSettings are resolved by the
  same lookup as pointer input.
- State is pruned on removal; object identity and definition changes prevent
  same-numeric-ID reuse inheriting an old animation. Title, game entry, and scene
  arrival reset all movement state.

Focused checks: `test_card_motion.gd` (synthetic; no licensed data) and
`test_card_motion_board.gd` (imported source board wiring). The latter checks
unchanged save/model snapshots, paused movement, lifted head, lagging tail,
release, same-ID replacement, removal and title/entry cleanup. Existing combat,
cycle, equipment, pointer drag and held-stack suites cover ownership regressions.

These are static/headless checks only. Visual/manual comparison with Unity has
not run: no display server is available. Exact frame ordering across Unity's
MonoBehaviour updates and Godot processing is not claimed as visually accepted.
